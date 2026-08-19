param(
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# The release artifact is built as a sibling of the repository checkout:
#   E:\CodexDev\ieta-znz-deploy-release  (i.e. <parent-of-repo>\ieta-znz-deploy-release)
if (-not $OutDir) {
  $OutDir = Join-Path (Split-Path -Parent $scriptDir) "ieta-znz-deploy-release"
}
if (-not [System.IO.Path]::IsPathRooted($OutDir)) {
  $OutDir = Join-Path $scriptDir $OutDir
}

Write-Host "Git cleanliness check (sourceDirty must be false)"
$porcelain = @(& git status --porcelain 2>$null)
if ($LASTEXITCODE -ne 0) { throw "git status failed; publishing requires a Git worktree" }
if ($porcelain.Count -gt 0) {
  Write-Host "Working tree is not clean:" -ForegroundColor Red
  $porcelain | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  throw "Publish refused: commit or stash all changes first so release-info.json can record a clean sourceCommit."
}

$commit = (& git rev-parse HEAD).Trim()
if (-not $commit) { throw "Cannot resolve HEAD commit" }
Write-Host "sourceCommit: $commit"

Write-Host "Release configuration check"
& (Join-Path $scriptDir "check-release.ps1") -DockerExe $DockerExe -ProjectName $ProjectName
if ($LASTEXITCODE -ne 0) { throw "check-release.ps1 failed" }

Write-Host "Offline image archive check"
$archivesList = Join-Path $scriptDir "scripts\common\image-archives.txt"
if (-not (Test-Path -LiteralPath $archivesList)) { throw "scripts/common/image-archives.txt missing" }
$archiveEntries = @(
  Get-Content -LiteralPath $archivesList |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") }
)
if ($archiveEntries.Count -eq 0) { throw "scripts/common/image-archives.txt has no entries" }

# Every archive tag must be one of the pinned image references (compose/image-list.txt),
# so a clean offline environment can load archives and `compose up` without manual retag.
$pinnedListPath = Join-Path $scriptDir "image-list.txt"
$pinnedImages = @(
  Get-Content -LiteralPath $pinnedListPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique
)

$archivesByPlatform = @{}
foreach ($line in $archiveEntries) {
  $parts = $line.Split("|")
  if ($parts.Count -ne 4) { throw "Malformed archive entry (expected platform|runtime-image|archive-image|path): $line" }
  $platform = $parts[0].Trim()
  $runtimeImage = $parts[1].Trim()
  $archiveImage = $parts[2].Trim()
  $relPath = $parts[3].Trim()

  if ($platform -notin @("linux/amd64", "linux/arm64")) {
    throw "Archive $relPath has unsupported platform '$platform'"
  }
  foreach ($tag in @($runtimeImage, $archiveImage)) {
    if ($tag -notin $pinnedImages) {
      throw "Archive $relPath lists image '$tag' which is not a pinned reference in image-list.txt"
    }
  }
  if ($runtimeImage -ne $archiveImage) {
    throw "Archive $relPath runtime-image '$runtimeImage' differs from archive-image '$archiveImage' (R10: archives are produced by docker save of the pinned reference)"
  }
  $expectedDir = if ($platform -eq "linux/arm64") { "images/linux-arm64" } else { "images/linux-amd64" }
  if ($relPath -notmatch "^${expectedDir}/") {
    throw "Archive $relPath is not under $expectedDir for platform $platform"
  }
  $fullPath = Join-Path $scriptDir ($relPath -replace "/", "\")
  if (-not (Test-Path -LiteralPath $fullPath)) { throw "Missing image archive: $relPath" }
  if ((Get-Item -LiteralPath $fullPath).Length -eq 0) { throw "Empty image archive: $relPath" }
  $manifestJson = & tar -xOf $fullPath manifest.json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $manifestJson) { throw "Cannot read manifest.json from archive: $relPath" }
  $manifest = $manifestJson | ConvertFrom-Json
  $repoTags = @($manifest.RepoTags)
  if ($repoTags -notcontains $archiveImage) {
    throw "Archive $relPath contains RepoTags [$($repoTags -join ', ')], expected $archiveImage"
  }
  $configRaw = & tar -xOf $fullPath $manifest.Config 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $configRaw) { throw "Cannot read image config from archive: $relPath" }
  $config = $configRaw | ConvertFrom-Json
  $expectedArch = if ($platform -eq "linux/arm64") { "arm64" } else { "amd64" }
  if ($config.architecture -ne $expectedArch) {
    throw "Archive $relPath contains $($config.architecture) image but platform is $platform"
  }
  if (-not $archivesByPlatform.ContainsKey($platform)) { $archivesByPlatform[$platform] = @() }
  $archivesByPlatform[$platform] += $runtimeImage
  Write-Host "  $relPath -> $runtimeImage [$platform]"
}

foreach ($platform in @("linux/amd64", "linux/arm64")) {
  $images = @($archivesByPlatform[$platform])
  $pinnedBase = @($pinnedImages | Where-Object { $_ -notmatch '^ghcr.io/|/vllm-openai:' })
  $missing = @($pinnedBase | Where-Object { $_ -notin $images })
  if ($missing.Count -gt 0) {
    throw "Missing $platform offline archives for pinned images: $($missing -join ', ')"
  }
}

Write-Host "Assembling release artifact: $OutDir"
$outFull = [System.IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $outFull) { Remove-Item -Recurse -Force -LiteralPath $outFull }
New-Item -ItemType Directory -Path $outFull | Out-Null

$skipNames = @(".git", ".agents", "run", "models", ".gitignore")
Get-ChildItem -LiteralPath $scriptDir -Force | Where-Object { $_.Name -notin $skipNames } | ForEach-Object {
  Copy-Item -Recurse -Force -LiteralPath $_.FullName -Destination $outFull
}

$createdAt = Get-Date -Format "yyyy-MM-dd"
$releaseInfo = [ordered]@{
  releaseName = "ieta-znz-deploy-release"
  createdAt = $createdAt
  sourceCommit = $commit
  sourceDirty = $false
  imageDelivery = "local-offline-archives-only"
  filesHashList = "release-files.sha256"
}
$releaseInfo | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $outFull "release-info.json")

Write-Host "Generating release-files.sha256"
$hashLines = @()
Get-ChildItem -LiteralPath $outFull -Recurse -File | Sort-Object { $_.FullName } | ForEach-Object {
  if ($_.Name -eq "release-files.sha256") { return }
  $rel = $_.FullName.Substring($outFull.Length).TrimStart("\", "/").Replace("\", "/")
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower()
  $hashLines += "$hash  $rel"
}
Set-Content -Encoding ASCII -LiteralPath (Join-Path $outFull "release-files.sha256") -Value $hashLines

Write-Host "Release artifact written to $OutDir"
Write-Host "release-info.json: $($releaseInfo | ConvertTo-Json -Compress)"
Write-Host "release-files.sha256: $($hashLines.Count) entries"
