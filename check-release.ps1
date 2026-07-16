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

Write-Host "Release configuration check passed."
