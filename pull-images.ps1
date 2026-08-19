param(
  [ValidateSet("linux/amd64")]
  [string]$Platform = "linux/amd64",
  [string]$DockerExe = "docker"
)

Write-Warning "Remote image pull is disabled. Loading local offline archives instead."
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "load-images.ps1") -Platform $Platform -DockerExe $DockerExe
