param([Parameter(Mandatory=$true)][string]$App,[string]$DockerExe="docker",[string]$ProjectName="ieta-znz-deploy",[switch]$Force)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "scripts\windows\stop-app-base.ps1") -App $App -DockerExe $DockerExe -ProjectName $ProjectName -Force:$Force
