param(
  [Parameter(Mandatory=$true)][string]$App,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [switch]$SkipPortCheck
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent (Split-Path -Parent $scriptDir)

function Read-Manifest {
  param([string]$Path)
  $data = @{}
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#") -or $line -notmatch "=") { return }
    $parts = $line.Split("=", 2)
    $data[$parts[0].Trim()] = $parts[1].Trim()
  }
  return $data
}

$manifestPath = Join-Path $baseDir "apps\$App.env"
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Unknown app '$App'. Add apps\$App.env first."
}

$manifest = Read-Manifest -Path $manifestPath
$capabilities = @()
if ($manifest.ContainsKey("CAPABILITIES") -and $manifest["CAPABILITIES"].Trim()) {
  $capabilities = $manifest["CAPABILITIES"].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Host "App: $($manifest['APP_NAME']) ($App)"
if (-not $capabilities -or $capabilities.Count -eq 0) {
  Write-Host "No shared base capabilities are declared for this app. Nothing to start."
  if ($manifest.ContainsKey("NOTES")) { Write-Host $manifest["NOTES"] }
  exit 0
}

Write-Host "Starting base capabilities: $($capabilities -join ', ')"
& (Join-Path $baseDir "start-base-env.ps1") -Profiles $capabilities -DockerExe $DockerExe -ProjectName $ProjectName -SkipPortCheck:$SkipPortCheck
