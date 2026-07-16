param(
  [Parameter(Mandatory=$true)][string]$App,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy"
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

Set-Location $baseDir
if ($services.Count -eq 0) {
  Write-Host "No required base services declared for $App."
  exit 0
}
& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml ps @services
