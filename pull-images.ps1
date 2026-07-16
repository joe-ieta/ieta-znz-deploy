param(
  [ValidateSet("linux/amd64", "linux/arm64")]
  [string]$Platform = "linux/amd64",
  [string]$DockerExe = "docker",
  [switch]$IncludeLLM
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$imageLists = @(
  "image-list.core.txt",
  "image-list.ragflow.txt",
  "image-list.cdc.txt",
  "image-list.dyna-report.txt"
)
if ($IncludeLLM) { $imageLists += "image-list.llm.txt" }

$images = foreach ($list in $imageLists) {
  $path = Join-Path $scriptDir $list
  if (Test-Path -LiteralPath $path) {
    Get-Content -LiteralPath $path |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -and -not $_.StartsWith("#") }
  }
}
$images = @($images | Select-Object -Unique)

foreach ($image in $images) {
  Write-Host "Pulling $image for $Platform"
  & $DockerExe pull --platform $Platform $image
  if ($LASTEXITCODE -ne 0) { throw "docker pull failed: $image for $Platform" }
}

Write-Host "Pulled $($images.Count) pinned image references for $Platform."
