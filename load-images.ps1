param(
  [ValidateSet("linux/amd64")]
  [string]$Platform = "linux/amd64",
  [string]$DockerExe = "docker",
  [switch]$ForceReload
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$archiveManifestPath = Join-Path $scriptDir "scripts\common\image-archives.txt"
$requiredImageLists = @(
  "image-list.core.txt",
  "image-list.ragflow.txt",
  "image-list.cdc.txt",
  "image-list.dyna-report.txt"
)

function Get-RequiredImages {
  param([string[]]$Paths)
  $images = foreach ($path in $Paths) {
    $fullPath = Join-Path $scriptDir $path
    if (Test-Path -LiteralPath $fullPath) {
      Get-Content -LiteralPath $fullPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }
    }
  }
  return @($images | Sort-Object -Unique)
}

function Get-PlatformArchives {
  param([string]$ManifestPath, [string]$RequestedPlatform)
  $archives = @()
  Get-Content -LiteralPath $ManifestPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }
    $parts = $line.Split("|")
    if ($parts.Count -ne 4) { throw "Invalid archive manifest line: $line" }
    if ($parts[0].Trim() -eq $RequestedPlatform) {
      $archives += [PSCustomObject]@{
        RuntimeImage = $parts[1].Trim()
        ArchiveImage = $parts[2].Trim()
        Archive = Join-Path $scriptDir $parts[3].Trim()
      }
    }
  }
  if ($archives.Count -eq 0) { throw "No offline archives declared for $RequestedPlatform" }
  return @($archives)
}

$requiredImages = @(Get-RequiredImages -Paths $requiredImageLists)
$missingImages = @()
foreach ($image in $requiredImages) {
  & $DockerExe image inspect $image *> $null
  if ($LASTEXITCODE -ne 0) { $missingImages += $image }
}

if (-not $ForceReload -and $missingImages.Count -eq 0) {
  Write-Host "All required base images are already present for $Platform."
  exit 0
}

if ($missingImages.Count -gt 0) {
  Write-Host "Missing base images: $($missingImages -join ', ')"
} else {
  Write-Host "Force reloading offline image archives for $Platform."
}

$archives = @(Get-PlatformArchives -ManifestPath $archiveManifestPath -RequestedPlatform $Platform)
foreach ($archive in $archives) {
  if (-not (Test-Path -LiteralPath $archive.Archive)) {
    throw "Offline archive not found: $($archive.Archive)"
  }
  Write-Host "Loading offline image archive $($archive.Archive)"
  & $DockerExe load -i $archive.Archive
  if ($LASTEXITCODE -ne 0) { throw "docker load failed: $($archive.Archive)" }

  & $DockerExe image inspect $archive.ArchiveImage *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Archive did not load the declared image tag: $($archive.ArchiveImage)"
  }
  if ($archive.ArchiveImage -ne $archive.RuntimeImage) {
    Write-Host "Tagging $($archive.ArchiveImage) as $($archive.RuntimeImage)"
    & $DockerExe tag $archive.ArchiveImage $archive.RuntimeImage
    if ($LASTEXITCODE -ne 0) { throw "docker tag failed: $($archive.RuntimeImage)" }
  }
  & $DockerExe image inspect $archive.RuntimeImage *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "Required runtime image is unavailable after offline load: $($archive.RuntimeImage)"
  }
}

foreach ($image in $requiredImages) {
  & $DockerExe image inspect $image *> $null
  if ($LASTEXITCODE -ne 0) { throw "Required base image is unavailable: $image" }
}

Write-Host "Loaded and verified $($archives.Count) offline image archives for $Platform."
