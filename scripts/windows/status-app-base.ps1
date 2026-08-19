param(
  [Parameter(Mandatory=$true)][string]$App,
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
$manifestPath = Join-Path $baseDir "apps\$App.env"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Unknown app '$App'." }

$appValues = @{}
Get-Content -LiteralPath $manifestPath | ForEach-Object {
  if ($_ -match '^([A-Za-z0-9_]+)=(.*)$') { $appValues[$Matches[1]] = $Matches[2].Trim() }
}
$fail = $false

Set-Location $baseDir
$services = @()
if ($appValues.ContainsKey("REQUIRED_SERVICES")) {
  $services = $appValues["REQUIRED_SERVICES"].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
if ($services.Count -gt 0) {
  foreach ($service in $services) {
    $ids = @(& $DockerExe compose --project-name $ProjectName -f docker-compose.ieta-znz-deploy.yml ps -q $service 2>$null)
    if ($ids.Count -eq 0) {
      Write-Host "[FAIL] service ${service}: not running" -ForegroundColor Red
      $fail = $true
      continue
    }
    $status = (& $DockerExe inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}|{{.State.Status}}' $ids[0] 2>$null)
    $health, $state = $status -split '\|'
    if ($health -eq "healthy") {
      Write-Host "[OK]   service ${service}: healthy"
    } elseif ($health -eq "no-healthcheck" -and $state -eq "running") {
      Write-Host "[OK]   service ${service}: running (no healthcheck declared)"
    } else {
      Write-Host "[FAIL] service ${service}: $status" -ForegroundColor Red
      $fail = $true
    }
  }
}

if ($appValues.ContainsKey("HOST_PROBES")) {
  $envValues = @{}
  $envPath = Join-Path $baseDir ".env"
  if (Test-Path -LiteralPath $envPath) {
    Get-Content -LiteralPath $envPath | ForEach-Object {
      if ($_ -match '^([A-Za-z0-9_]+)=(.*)$') { $envValues[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'") }
    }
  }
  $esEnvPassword = [Environment]::GetEnvironmentVariable("ELASTIC_PASSWORD")
  $esPassword = if (-not [string]::IsNullOrEmpty($esEnvPassword)) { $esEnvPassword } elseif ($envValues.ContainsKey("ELASTIC_PASSWORD")) { $envValues["ELASTIC_PASSWORD"] } else { "" }
  foreach ($probe in ($appValues["HOST_PROBES"].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $parts = $probe.Split(":")
    $portVar = $parts[0]
    $proto = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    $pathSuffix = if ($parts.Count -gt 2) { ($parts[2..($parts.Count - 1)]) -join ":" } else { "" }
    $path = if (-not $pathSuffix) { "" } elseif ($pathSuffix.StartsWith("/")) { $pathSuffix } else { "/" + $pathSuffix }
    $envPortValue = [Environment]::GetEnvironmentVariable($portVar)
    $port = if (-not [string]::IsNullOrEmpty($envPortValue)) { $envPortValue } elseif ($envValues.ContainsKey($portVar)) { $envValues[$portVar] } else { "" }
    if ($port -notmatch '^\d+$') {
      Write-Host "[FAIL] probe ${portVar}: .env value missing or not numeric" -ForegroundColor Red
      $fail = $true
      continue
    }
    if ($proto -eq "tcp") {
      $ok = Test-NetConnection 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
      if ($ok) {
        Write-Host "[OK]   probe 127.0.0.1:${port} (tcp)"
      } else {
        Write-Host "[FAIL] probe 127.0.0.1:${port} (tcp): connection failed" -ForegroundColor Red
        $fail = $true
      }
    } elseif ($proto -eq "http") {
      # Shared Elasticsearch password is sent for http probes; services without auth ignore it.
      try {
        $null = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Credential $(New-Object System.Management.Automation.PSCredential("elastic", (ConvertTo-SecureString $esPassword -AsPlainText -Force))) "http://127.0.0.1:$port$path"
        Write-Host "[OK]   probe http://127.0.0.1:$port$path"
      } catch {
        Write-Host "[FAIL] probe http://127.0.0.1:${port}${path}: HTTP check failed" -ForegroundColor Red
        $fail = $true
      }
    } else {
      Write-Host "[FAIL] probe ${probe}: unknown protocol '$proto'" -ForegroundColor Red
      $fail = $true
    }
  }
}

if ($fail) {
  Write-Host "Status check FAILED for $App." -ForegroundColor Red
  exit 1
}
Write-Host "Status check PASSED for $App."
exit 0
