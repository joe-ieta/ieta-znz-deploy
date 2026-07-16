param(
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [switch]$RemoveVolumes
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$args = @("compose", "--project-name", $ProjectName, "-f", "docker-compose.ieta-znz-deploy.yml", "down")
if ($RemoveVolumes) { $args += "--volumes" }
& $DockerExe @args
if ($LASTEXITCODE -ne 0) { throw "docker compose down failed" }
