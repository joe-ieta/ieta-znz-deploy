param(
  [string]$DockerExe = "docker",
  [string]$BaseDir = ""
)

# Regenerates the offline image archives recorded in scripts/common/image-archives.txt.
# Each archive is produced by `docker save` of the pinned reference so the tar's internal
# RepoTags equals the Compose pinned tag (requirement R10). See docs/release-specification.md.
#
# Why digest-based pull: with the Docker Desktop containerd image store, pulling a tag merges a
# multi-arch index locally and `docker save <tag>` can fail with
# "unable to create manifests file: NotFound: content digest ... not found" when the other
# architecture's child manifest is not present. The standard procedure therefore resolves the
# platform manifest digest, pulls by digest, re-tags with the pinned tag, and saves.

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $BaseDir) { $BaseDir = Split-Path -Parent (Split-Path -Parent $scriptDir) }
$BaseDir = [System.IO.Path]::GetFullPath($BaseDir)
Set-Location $BaseDir

function Test-Archive {
  param([string]$TarPath, [string]$ExpectedTag, [string]$ExpectedArch)
  if (-not (Test-Path -LiteralPath $TarPath)) { return $false }
  $manifestJson = & tar -xOf $TarPath manifest.json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $manifestJson) { return $false }
  try { $manifest = $manifestJson | ConvertFrom-Json } catch { return $false }
  if (@($manifest.RepoTags) -notcontains $ExpectedTag) { return $false }
  $configRaw = & tar -xOf $TarPath $manifest.Config 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $configRaw) { return $false }
  try { $config = $configRaw | ConvertFrom-Json } catch { return $false }
  if ($config.architecture -ne $ExpectedArch) { return $false }
  return $true
}

function Invoke-WithRetry {
  param([scriptblock]$Action, [string]$Description, [int]$Attempts = 8, [int]$SleepSeconds = 10)
  for ($i = 1; $i -le $Attempts; $i++) {
    & $Action
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host "  $Description attempt $i failed, retrying in ${SleepSeconds}s..."
    Start-Sleep -Seconds $SleepSeconds
  }
  throw "$Description failed after $Attempts attempts"
}

function Get-PlatformDigest {
  param([string]$Tag, [string]$Arch)
  Invoke-WithRetry -Action {
    $script:mi = & $DockerExe manifest inspect $Tag 2>$null
    $LASTEXITCODE
  } -Description "manifest inspect $Tag"
  $list = $script:mi | ConvertFrom-Json
  $item = $list.manifests | Where-Object {
    $_.platform.os -eq 'linux' -and $_.platform.architecture -eq $Arch -and $_.platform.variant -notin @('v7')
  } | Select-Object -First 1
  if (-not $item) { throw "no linux/$Arch manifest for $Tag" }
  return $item.digest
}

function Save-PlatformArchive {
  param([string]$Tag, [string]$Arch, [string]$Platform, [string]$TarPath, [switch]$KeepLocal)
  $digest = Get-PlatformDigest -Tag $Tag -Arch $Arch
  & $DockerExe image rm $Tag 2>$null | Out-Null
  Invoke-WithRetry -Action {
    & $DockerExe pull --platform $Platform "${Tag}@${digest}" 2>$null | Out-Null
    $LASTEXITCODE
  } -Description "pull ${Tag}@${digest} [$Platform]"
  & $DockerExe tag "${Tag}@${digest}" $Tag 2>$null
  if ($LASTEXITCODE -ne 0) { throw "tag failed: $Tag" }
  & $DockerExe save $Tag -o $TarPath 2>$null
  if ($LASTEXITCODE -ne 0) { throw "save failed: $Tag -> $TarPath" }
  if (-not (Test-Archive -TarPath $TarPath -ExpectedTag $Tag -ExpectedArch $Arch)) {
    throw "verification failed: $TarPath (expected $Tag / $Arch)"
  }
  if (-not $KeepLocal) { & $DockerExe image rm $Tag 2>$null | Out-Null }
}

$archivesList = Join-Path $BaseDir "scripts\common\image-archives.txt"
if (-not (Test-Path -LiteralPath $archivesList)) { throw "scripts/common/image-archives.txt missing" }
$entries = @(
  Get-Content -LiteralPath $archivesList |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }
)

# Process arm64 first so the local image store ends up holding the amd64 images.
$ordered = @()
$ordered += $entries | Where-Object { $_ -match '^linux/arm64\|' }
$ordered += $entries | Where-Object { $_ -match '^linux/amd64\|' }

foreach ($line in $ordered) {
  $parts = $line.Split("|")
  if ($parts.Count -ne 4) { throw "Malformed archive entry (expected platform|runtime-image|archive-image|path): $line" }
  $platform = $parts[0].Trim()
  $runtimeImage = $parts[1].Trim()
  $archiveImage = $parts[2].Trim()
  $relPath = $parts[3].Trim()
  if ($platform -notin @("linux/amd64", "linux/arm64")) { throw "Unsupported platform '$platform' in entry: $line" }
  if ($runtimeImage -ne $archiveImage) {
    throw "R10: runtime-image and archive-image must be equal (pinned reference): $line"
  }
  $tag = $runtimeImage
  $arch = if ($platform -eq "linux/arm64") { "arm64" } else { "amd64" }
  $tarPath = Join-Path $BaseDir ($relPath -replace "/", "\")

  if (Test-Archive -TarPath $tarPath -ExpectedTag $tag -ExpectedArch $arch) {
    Write-Host "SKIP (valid): $relPath"
    continue
  }
  Write-Host "=== $tag [$platform] -> $relPath"
  Save-PlatformArchive -Tag $tag -Arch $arch -Platform $platform -TarPath $tarPath -KeepLocal:($arch -eq "amd64")
  Write-Host "OK: $relPath ($([math]::Round((Get-Item -LiteralPath $tarPath).Length / 1MB, 1)) MB)"
}

Write-Host "All archives up to date. Local store keeps linux/amd64 images."
