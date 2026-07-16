param(
  [ValidateSet("core", "ragflow", "cdc", "dyna-report", "llm", "all-no-llm", "all")]
  [string]$Preset = "all-no-llm",
  [string[]]$Profiles,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [switch]$SkipPortCheck
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

function Resolve-Profiles {
  if ($Profiles -and $Profiles.Count -gt 0) { return $Profiles }
  switch ($Preset) {
    "core" { return @("core") }
    "ragflow" { return @("ragflow") }
    "cdc" { return @("cdc") }
    "dyna-report" { return @("dyna-report") }
    "llm" { return @("llm", "llama-cpp", "vllm") }
    "all" { return @("ragflow", "cdc", "dyna-report", "llm", "llama-cpp", "vllm") }
    default { return @("ragflow", "cdc", "dyna-report") }
  }
}

function Get-EnvPortValue {
  param([string]$Name, [int]$DefaultValue)
  $envPath = Join-Path $scriptDir ".env"
  if (-not (Test-Path -LiteralPath $envPath)) { return $DefaultValue }
  $line = Get-Content -LiteralPath $envPath | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -Last 1
  if (-not $line) { return $DefaultValue }
  $value = ($line -replace "^\s*$Name\s*=\s*", "").Trim().Trim('"').Trim("'")
  if ($value -match '^\d+$') { return [int]$value }
  return $DefaultValue
}

function Test-RequiredPortsAvailable {
  param([string[]]$SelectedProfiles)
  $names = @()
  if ($SelectedProfiles -contains "core") { $names += @("POSTGRES_PORT", "MYSQL_PORT", "MINIO_PORT", "MINIO_CONSOLE_PORT", "VALKEY_PORT") }
  if ($SelectedProfiles -contains "postgres") { $names += "POSTGRES_PORT" }
  if ($SelectedProfiles -contains "mysql") { $names += "MYSQL_PORT" }
  if ($SelectedProfiles -contains "minio") { $names += @("MINIO_PORT", "MINIO_CONSOLE_PORT") }
  if ($SelectedProfiles -contains "valkey") { $names += "VALKEY_PORT" }
  if ($SelectedProfiles -contains "es8") { $names += "ES8_RAGFLOW_PORT" }
  if ($SelectedProfiles -contains "es7") { $names += "ES7_CDC_PORT" }
  if ($SelectedProfiles -contains "flink") { $names += "FLINK_REST_PORT" }
  if ($SelectedProfiles -contains "onlyoffice") { $names += "ONLYOFFICE_PORT" }
  if ($SelectedProfiles -contains "ragflow") { $names += @("MYSQL_PORT", "MINIO_PORT", "MINIO_CONSOLE_PORT", "VALKEY_PORT", "ES8_RAGFLOW_PORT") }
  if ($SelectedProfiles -contains "cdc") { $names += @("POSTGRES_PORT", "MYSQL_PORT", "ES7_CDC_PORT", "FLINK_REST_PORT") }
  if ($SelectedProfiles -contains "dyna-report") { $names += @("POSTGRES_PORT", "ONLYOFFICE_PORT") }
  if ($SelectedProfiles -contains "llama-cpp" -or $SelectedProfiles -contains "llm") { $names += "LLAMA_CPP_PORT" }
  if ($SelectedProfiles -contains "vllm" -or $SelectedProfiles -contains "llm") { $names += "VLLM_PORT" }

  $defaults = @{
    POSTGRES_PORT=5432; MYSQL_PORT=3306; MINIO_PORT=9000; MINIO_CONSOLE_PORT=9001; VALKEY_PORT=6379;
    ES8_RAGFLOW_PORT=1200; ES7_CDC_PORT=19200; FLINK_REST_PORT=19081; ONLYOFFICE_PORT=8088;
    LLAMA_CPP_PORT=18080; VLLM_PORT=18000
  }

  $busy = @()
  foreach ($name in ($names | Select-Object -Unique)) {
    $port = Get-EnvPortValue -Name $name -DefaultValue $defaults[$name]
    $listeners = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    if ($listeners) {
      $owners = $listeners | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object {
        $proc = Get-Process -Id $_ -ErrorAction SilentlyContinue
        if ($proc) { "$($proc.ProcessName)(PID=$_)" } else { "PID=$_" }
      }
      $busy += "${name}=${port}: $($owners -join ', ')"
    }
  }

  if ($busy.Count -gt 0) {
    Write-Host "Required host ports are already in use:" -ForegroundColor Yellow
    $busy | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host "Use -SkipPortCheck only when existing listeners are the same Docker project or when you intentionally changed .env." -ForegroundColor Yellow
    throw "Port preflight failed"
  }
}

$selectedProfiles = @(Resolve-Profiles | Select-Object -Unique)
Write-Host "Starting ieta-znz-deploy profiles: $($selectedProfiles -join ', ')"

if (-not $SkipPortCheck) { Test-RequiredPortsAvailable -SelectedProfiles $selectedProfiles }

$args = @("compose", "--project-name", $ProjectName, "-f", "docker-compose.ieta-znz-deploy.yml")
foreach ($profile in $selectedProfiles) { $args += @("--profile", $profile) }
$args += @("up", "-d")
& $DockerExe @args
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed" }

& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml ps
