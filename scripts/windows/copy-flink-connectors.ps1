param(
  [Parameter(Mandatory=$true)][string]$SourceDir,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent (Split-Path -Parent $scriptDir)

if (-not (Test-Path -LiteralPath $SourceDir)) { throw "Connector source directory not found: $SourceDir" }
$jarCount = @(Get-ChildItem -LiteralPath $SourceDir -Filter "*.jar" -File).Count
if ($jarCount -eq 0) { throw "No *.jar files found in $SourceDir" }
$src = (Resolve-Path -LiteralPath $SourceDir).Path

Set-Location $baseDir
Write-Host "Copying $jarCount jar(s) into flink_lib (mounted at /opt/flink/lib/ieta)."
& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml run --rm --no-deps --entrypoint /bin/sh -v "${src}:/connectors:ro" flink-jobmanager -c 'for j in /connectors/*.jar; do cp -v "$j" /opt/flink/lib/ieta/; done'
if ($LASTEXITCODE -ne 0) { throw "connector copy failed" }

Write-Host "Restarting Flink services so connectors load into the classpath."
& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml restart flink-jobmanager flink-taskmanager
if ($LASTEXITCODE -ne 0) { throw "flink restart failed" }

Write-Host "Done. Connector jars now persist in the flink_lib named volume across compose down/up."
Write-Host "Verify: .\status-app-base.ps1 -App ieta-cdc-core"
