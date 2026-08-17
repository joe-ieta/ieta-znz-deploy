param(
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$profiles = @(
  "core", "postgres", "mysql", "minio", "valkey", "es8", "es7",
  "flink", "onlyoffice", "llm", "llama-cpp", "vllm",
  "ragflow", "cdc", "dyna-report"
)
$composeArgs = @(
  "compose", "--project-name", $ProjectName,
  "-f", "docker-compose.ieta-znz-deploy.yml"
)
foreach ($profile in $profiles) { $composeArgs += @("--profile", $profile) }

Write-Host "Compose config check"
& $DockerExe @composeArgs config --quiet
if ($LASTEXITCODE -ne 0) { throw "compose config failed" }

$composeImages = @(& $DockerExe @composeArgs config --images)
if ($LASTEXITCODE -ne 0) { throw "compose image listing failed" }
$composeImages = @($composeImages | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)

Write-Host "Pinned image reference check"
foreach ($image in $composeImages) {
  if ($image -notmatch ':[^/]+$') {
    throw "image has no explicit tag: $image"
  }
  $tag = ($image -split ':')[-1]
  if ($tag -eq "latest" -or $tag -eq "server" -or $tag -match '^v?\d+$') {
    throw "image tag is floating or insufficiently pinned: $image"
  }
  Write-Host "  $image"
}

$listPath = Join-Path $scriptDir "image-list.txt"
$listedImages = @(
  Get-Content -LiteralPath $listPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique
)

$missingFromList = @($composeImages | Where-Object { $_ -notin $listedImages })
$unusedInList = @($listedImages | Where-Object { $_ -notin $composeImages })
if ($missingFromList.Count -gt 0 -or $unusedInList.Count -gt 0) {
  if ($missingFromList.Count -gt 0) {
    Write-Host "Missing from image-list.txt: $($missingFromList -join ', ')" -ForegroundColor Yellow
  }
  if ($unusedInList.Count -gt 0) {
    Write-Host "Not used by Compose: $($unusedInList -join ', ')" -ForegroundColor Yellow
  }
  throw "image-list.txt and Compose image references differ"
}

function Read-KeyValueFile {
  param([string]$Path)
  $data = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $data }
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#") -or $line -notmatch "=") { return }
    $parts = $line.Split("=", 2)
    $data[$parts[0].Trim()] = $parts[1].Trim()
  }
  return $data
}

Write-Host "Host port consistency check (.env vs project-env/*.host.env)"
$envValues = Read-KeyValueFile -Path (Join-Path $scriptDir ".env")
$trackedPorts = @("POSTGRES_PORT", "MYSQL_PORT", "ES7_CDC_PORT", "FLINK_REST_PORT")
foreach ($name in $trackedPorts) {
  if (-not $envValues.ContainsKey($name)) {
    throw ".env does not define $name"
  }
  if ($envValues[$name] -notmatch '^\d+$') {
    throw ".env $name is not a numeric port: $($envValues[$name])"
  }
}

$urlKeyMap = @(
  @{ Pattern = "ELASTICSEARCH7_URL"; EnvVar = "ES7_CDC_PORT" },
  @{ Pattern = "FLINK_REST_URL"; EnvVar = "FLINK_REST_PORT" },
  @{ Pattern = "POSTGRES.*URL"; EnvVar = "POSTGRES_PORT" },
  @{ Pattern = "MYSQL.*URL"; EnvVar = "MYSQL_PORT" }
)

$hostEnvFiles = @(Get-ChildItem -LiteralPath (Join-Path $scriptDir "project-env") -Filter "*.host.env" | ForEach-Object { $_.FullName })
$portErrors = @()
foreach ($file in $hostEnvFiles) {
  $fileName = Split-Path -Leaf $file
  $hostValues = Read-KeyValueFile -Path $file
  foreach ($key in @("POSTGRES_PORT", "MYSQL_PORT")) {
    if ($hostValues.ContainsKey($key)) {
      $expected = $envValues[$key]
      if ($hostValues[$key] -ne $expected) {
        $portErrors += "$fileName : $key=$($hostValues[$key]) but .env has $expected"
      }
    }
  }
  foreach ($map in $urlKeyMap) {
    foreach ($entry in $hostValues.GetEnumerator()) {
      if ($entry.Key -notmatch $map.Pattern) { continue }
      if ($entry.Value -notmatch "://") {
        $portErrors += "$fileName : $($entry.Key)=$($entry.Value) is not a URL"
        continue
      }
      $expected = $envValues[$map.EnvVar]
      if ($entry.Value -notmatch ":${expected}(/|\z)") {
        $portErrors += "$fileName : $($entry.Key)=$($entry.Value) but .env $($map.EnvVar)=$expected"
      }
    }
  }
}

if ($portErrors.Count -gt 0) {
  Write-Host "Host port mismatch between .env and project-env templates:" -ForegroundColor Red
  $portErrors | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  throw ".env and project-env/*.host.env ports are inconsistent"
}

Write-Host "Application manifest check"
Get-ChildItem -LiteralPath (Join-Path $scriptDir "apps") -Filter "*.env" -File | ForEach-Object {
  $appId = $_.BaseName
  $appValues = Read-KeyValueFile -Path $_.FullName

  if ($appValues.ContainsKey("HOST_PROBES")) {
    foreach ($probe in $appValues["HOST_PROBES"].Split(",")) {
      $portVar = ($probe.Trim().Split(":")[0]).Trim()
      if (-not $envValues.ContainsKey($portVar)) {
        throw "App '$appId' HOST_PROBES references unknown .env variable: $portVar"
      }
    }
  }

  if ($appValues.ContainsKey("FLINK_TOTAL_SLOTS") -and $appValues["CAPABILITIES"].Split(",") -contains "flink") {
    if ($appValues["FLINK_TOTAL_SLOTS"] -notmatch '^\d+$') {
      throw "App '$appId' FLINK_TOTAL_SLOTS must be numeric: $($appValues['FLINK_TOTAL_SLOTS'])"
    }
    foreach ($varName in @("FLINK_TASK_SLOTS", "FLINK_TM_REPLICAS")) {
      if (-not $envValues.ContainsKey($varName) -or $envValues[$varName] -notmatch '^\d+$') {
        throw ".env must define numeric $varName when app '$appId' declares FLINK_TOTAL_SLOTS"
      }
    }
    $declaredTotal = [int]$appValues["FLINK_TOTAL_SLOTS"]
    $actualTotal = [int]$envValues["FLINK_TASK_SLOTS"] * [int]$envValues["FLINK_TM_REPLICAS"]
    if ($declaredTotal -ne $actualTotal) {
      throw "App '$appId' FLINK_TOTAL_SLOTS=$declaredTotal does not match .env FLINK_TASK_SLOTS*FLINK_TM_REPLICAS=$actualTotal"
    }
  }
}

Write-Host "Release configuration check passed."
