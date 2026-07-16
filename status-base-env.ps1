param(
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml ps
