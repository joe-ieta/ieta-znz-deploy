param(
  [Parameter(Mandatory=$true)][string]$App,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
$manifestPath = Join-Path $baseDir "apps\$App.env"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Unknown app '$App'." }

$services = @()
Get-Content -LiteralPath $manifestPath | ForEach-Object {
  if ($_ -match '^REQUIRED_SERVICES=(.*)$') {
    $services = $Matches[1].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }
}

if ($services.Count -eq 0) {
  Write-Host "No required base services declared for $App."
  exit 0
}

if (-not $Force) {
  Write-Host "Refusing to stop shared base services for '$App' without -Force." -ForegroundColor Yellow
  Write-Host "These services may be used by other applications: $($services -join ', ')" -ForegroundColor Yellow
  Write-Host "Use stop-base-env.ps1 to stop the whole base environment, or rerun with -Force for targeted docker compose stop." -ForegroundColor Yellow
  exit 2
}

Set-Location $baseDir
& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml stop @services
if ($LASTEXITCODE -ne 0) { throw "docker compose stop failed" }
