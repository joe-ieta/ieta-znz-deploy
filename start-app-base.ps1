param(
  [Parameter(Mandatory=$true)][string]$App,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [switch]$SkipPortCheck
)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "scripts\windows\start-app-base.ps1") -App $App -DockerExe $DockerExe -ProjectName $ProjectName -SkipPortCheck:$SkipPortCheck
