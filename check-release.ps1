param(
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
$archiveManifestPath = Join-Path $scriptDir "scripts\common\image-archives.txt"

$profiles = @(
  "core", "postgres", "mysql", "minio", "valkey", "es8", "es7",
  "flink", "onlyoffice",
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

$baseImageListPaths = @(
  "image-list.core.txt",
  "image-list.ragflow.txt",
  "image-list.cdc.txt",
  "image-list.dyna-report.txt"
)
$baseImages = @(
  foreach ($baseImageListPath in $baseImageListPaths) {
    Get-Content -LiteralPath (Join-Path $scriptDir $baseImageListPath) |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -and -not $_.StartsWith("#") }
  }
) | Sort-Object -Unique

Write-Host "Application manifest check"
$composeServices = @(& $DockerExe @composeArgs config --services)
if ($LASTEXITCODE -ne 0) { throw "compose service listing failed" }
$composeServices = @($composeServices | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)

function Get-EnvFileValues {
  param([string]$Path)
  $values = @{}
  Get-Content -LiteralPath $Path | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$') {
      $values[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
    }
  }
  return $values
}

function Get-PortFromValue {
  param([string]$Value)
  if ($Value -match '^(https?|jdbc:[a-z]+)://[^/:]+:(\d+)') { return [int]$Matches[2] }
  if ($Value -match '^\d+$') { return [int]$Value }
  return $null
}

$envValues = Get-EnvFileValues -Path (Join-Path $scriptDir ".env")

Get-ChildItem -LiteralPath (Join-Path $scriptDir "apps") -Filter "*.env" -File | ForEach-Object {
  $appId = $_.BaseName
  $appLines = Get-Content -LiteralPath $_.FullName
  $appValues = Get-EnvFileValues -Path $_.FullName
  $requiredServicesLine = $appLines | Where-Object { $_ -match '^REQUIRED_SERVICES=' } | Select-Object -First 1
  if (-not $requiredServicesLine) { throw "REQUIRED_SERVICES is missing from apps\$($_.Name)" }
  $requiredServices = @(
    $requiredServicesLine.Substring("REQUIRED_SERVICES=".Length).Split(",") |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ }
  )
  $unknownServices = @($requiredServices | Where-Object { $_ -notin $composeServices })
  if ($unknownServices.Count -gt 0) {
    throw "App '$appId' references unknown Compose services: $($unknownServices -join ', ')"
  }

  foreach ($templateKey in @("HOST_ENV_TEMPLATE", "CONTAINER_ENV_TEMPLATE")) {
    if ($appValues.ContainsKey($templateKey)) {
      $templatePath = Join-Path $scriptDir $appValues[$templateKey]
      if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "App '$appId' $templateKey references missing file: $($appValues[$templateKey])"
      }
    }
  }

  if ($appValues.ContainsKey("HOST_PROBES")) {
    foreach ($probe in $appValues["HOST_PROBES"].Split(",")) {
      $portVar = ($probe.Trim().Split(":")[0]).Trim()
      if (-not $envValues.ContainsKey($portVar)) {
        throw "App '$appId' HOST_PROBES references unknown .env variable: $portVar"
      }
    }
  }

  if ($appValues.ContainsKey("HOST_PORT_MAP") -and $appValues.ContainsKey("HOST_ENV_TEMPLATE")) {
    $hostTemplatePath = Join-Path $scriptDir $appValues["HOST_ENV_TEMPLATE"]
    if (Test-Path -LiteralPath $hostTemplatePath) {
      $hostValues = Get-EnvFileValues -Path $hostTemplatePath
      foreach ($mapping in $appValues["HOST_PORT_MAP"].Split(",")) {
        $parts = $mapping.Trim().Split("=")
        if ($parts.Count -ne 2) { throw "App '$appId' has invalid HOST_PORT_MAP entry: $mapping" }
        $envPortName = $parts[0].Trim()
        $hostKey = $parts[1].Trim()
        if (-not $envValues.ContainsKey($envPortName)) {
          throw "App '$appId' HOST_PORT_MAP references unknown .env variable: $envPortName"
        }
        if (-not $hostValues.ContainsKey($hostKey)) {
          throw "App '$appId' HOST_PORT_MAP references missing key '$hostKey' in $($appValues['HOST_ENV_TEMPLATE'])"
        }
        $envPort = Get-PortFromValue -Value $envValues[$envPortName]
        $hostPort = Get-PortFromValue -Value $hostValues[$hostKey]
        if ($null -eq $envPort -or $null -eq $hostPort) {
          throw "App '$appId' cannot extract a numeric port from .env '$envPortName=$($envValues[$envPortName])' or template '$hostKey=$($hostValues[$hostKey])'"
        }
        if ($envPort -ne $hostPort) {
          throw "App '$appId' port mismatch: .env $envPortName=$envPort but $($appValues['HOST_ENV_TEMPLATE']) $hostKey=$hostPort"
        }
      }
    }
  }

  if ($appValues.ContainsKey("FLINK_TOTAL_SLOTS") -and $appValues["CAPABILITIES"].Split(",") -contains "flink") {
    $declaredTotal = 0
    if ($appValues["FLINK_TOTAL_SLOTS"] -notmatch '^\d+$') {
      throw "App '$appId' FLINK_TOTAL_SLOTS must be numeric: $($appValues['FLINK_TOTAL_SLOTS'])"
    }
    $declaredTotal = [int]$appValues["FLINK_TOTAL_SLOTS"]
    foreach ($varName in @("FLINK_TASK_SLOTS", "FLINK_TM_REPLICAS")) {
      if (-not $envValues.ContainsKey($varName) -or $envValues[$varName] -notmatch '^\d+$') {
        throw ".env must define numeric $varName when app '$appId' declares FLINK_TOTAL_SLOTS"
      }
    }
    $actualTotal = [int]$envValues["FLINK_TASK_SLOTS"] * [int]$envValues["FLINK_TM_REPLICAS"]
    if ($declaredTotal -ne $actualTotal) {
      throw "App '$appId' FLINK_TOTAL_SLOTS=$declaredTotal does not match .env FLINK_TASK_SLOTS*FLINK_TM_REPLICAS=$actualTotal"
    }
  }
}

Write-Host "Offline archive manifest check"
if (-not (Test-Path -LiteralPath $archiveManifestPath)) {
  throw "Offline archive manifest not found: $archiveManifestPath"
}

$archiveEntries = @(
  Get-Content -LiteralPath $archiveManifestPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }
)

$platformArchiveCounts = @{}
$platformRuntimeImages = @{}
foreach ($entry in $archiveEntries) {
  $parts = $entry.Split("|")
  if ($parts.Count -ne 4) {
    throw "Invalid archive manifest line: $entry"
  }
  $platform = $parts[0].Trim()
  $runtimeImage = $parts[1].Trim()
  $archiveImage = $parts[2].Trim()
  $relativePath = $parts[3].Trim()
  $fullPath = Join-Path $scriptDir $relativePath
  if (-not (Test-Path -LiteralPath $fullPath)) {
    throw "Offline archive missing: $relativePath"
  }
  if ($runtimeImage -notin $baseImages) {
    throw "Offline archive maps an image outside the base package: $runtimeImage"
  }

  $archiveManifestJson = & tar -xOf $fullPath manifest.json
  if ($LASTEXITCODE -ne 0) { throw "Cannot read Docker archive manifest: $relativePath" }
  $dockerArchiveManifest = @($archiveManifestJson | ConvertFrom-Json)[0]
  if ($archiveImage -notin @($dockerArchiveManifest.RepoTags)) {
    throw "Archive '$relativePath' does not contain declared tag '$archiveImage'"
  }

  $archiveConfigJson = & tar -xOf $fullPath $dockerArchiveManifest.Config
  if ($LASTEXITCODE -ne 0) { throw "Cannot read Docker archive config: $relativePath" }
  $archiveConfig = $archiveConfigJson | ConvertFrom-Json
  $expectedArchitecture = if ($platform -eq "linux/amd64") { "amd64" } elseif ($platform -eq "linux/arm64") { "arm64" } else { $null }
  if (-not $expectedArchitecture) { throw "Unsupported archive platform: $platform" }
  if ($archiveConfig.os -ne "linux" -or $archiveConfig.architecture -ne $expectedArchitecture) {
    throw "Archive platform mismatch for '$relativePath': expected $platform, found $($archiveConfig.os)/$($archiveConfig.architecture)"
  }

  if (-not $platformArchiveCounts.ContainsKey($platform)) {
    $platformArchiveCounts[$platform] = 0
    $platformRuntimeImages[$platform] = @()
  }
  if ($runtimeImage -in $platformRuntimeImages[$platform]) {
    throw "Duplicate offline archive mapping for $platform and $runtimeImage"
  }
  $platformArchiveCounts[$platform] += 1
  $platformRuntimeImages[$platform] += $runtimeImage
}

foreach ($requiredPlatform in @("linux/amd64", "linux/arm64")) {
  if (-not $platformArchiveCounts.ContainsKey($requiredPlatform) -or $platformArchiveCounts[$requiredPlatform] -eq 0) {
    throw "No offline archives declared for $requiredPlatform"
  }
  $missingPlatformImages = @($baseImages | Where-Object { $_ -notin $platformRuntimeImages[$requiredPlatform] })
  $extraPlatformImages = @($platformRuntimeImages[$requiredPlatform] | Where-Object { $_ -notin $baseImages })
  if ($missingPlatformImages.Count -gt 0 -or $extraPlatformImages.Count -gt 0) {
    throw "Offline archive mapping for $requiredPlatform does not match the base image lists. Missing: $($missingPlatformImages -join ', '); extra: $($extraPlatformImages -join ', ')"
  }
}

Write-Host "Offline archive manifest check passed."
Write-Host "Release configuration check passed."
