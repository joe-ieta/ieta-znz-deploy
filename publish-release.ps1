param(
  [string]$DockerExe = "docker",
  [string]$ProjectName = "ieta-znz-deploy",
  [string]$OutDir = "ieta-znz-deploy-release"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

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
foreach ($line in $archiveEntries) {
  $parts = $line -split "\s+", 2
  if ($parts.Count -ne 2) { throw "Malformed archive entry: $line" }
  $relPath = $parts[0]
  $expectedTag = $parts[1]
  $fullPath = Join-Path $scriptDir ($relPath -replace "/", "\")
  if (-not (Test-Path -LiteralPath $fullPath)) { throw "Missing image archive: $relPath" }
  if ((Get-Item -LiteralPath $fullPath).Length -eq 0) { throw "Empty image archive: $relPath" }
  $manifestJson = & tar -xOf $fullPath manifest.json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $manifestJson) { throw "Cannot read manifest.json from archive: $relPath" }
  $manifest = $manifestJson | ConvertFrom-Json
  $repoTags = @($manifest.RepoTags)
  if ($repoTags -notcontains $expectedTag) {
    throw "Archive $relPath contains RepoTags [$($repoTags -join ', ')], expected $expectedTag"
  }
  Write-Host "  $relPath -> $expectedTag"
}

Write-Host "Assembling release artifact: $OutDir"
$outFull = Join-Path $scriptDir $OutDir
if (Test-Path -LiteralPath $outFull) { Remove-Item -Recurse -Force -LiteralPath $outFull }
New-Item -ItemType Directory -Path $outFull | Out-Null

$skipNames = @(".git", ".agents", "run", "models", ".gitignore", $OutDir)
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
