param(
  [ValidateSet("core", "ragflow", "cdc", "dyna-report", "llm", "all-no-llm", "all")]
  [string]$Preset = "all-no-llm",
  [switch]$SkipPortCheck
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir "start-base-env.ps1") -Preset $Preset -SkipPortCheck:$SkipPortCheck
