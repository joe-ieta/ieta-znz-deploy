param(
  [ValidateSet("core", "ragflow", "cdc", "dyna-report", "all")]
  [string]$Preset = "all",
  [switch]$SkipPortCheck,
  [switch]$SkipImageLoad
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "start-base-env.ps1") -Preset $Preset -SkipPortCheck:$SkipPortCheck -SkipImageLoad:$SkipImageLoad
