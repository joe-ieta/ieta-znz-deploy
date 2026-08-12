param(
  [string]$Destination = "E:\CodexDev\ieta-znz-deploy-release",
  [string]$DockerExe = "docker"
)

$ErrorActionPreference = "Stop"
$sourceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path)).TrimEnd("\")
$destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd("\")
$destinationParent = Split-Path -Parent $destinationRoot
$destinationName = Split-Path -Leaf $destinationRoot

if ($destinationRoot -eq $sourceRoot -or $destinationRoot.StartsWith($sourceRoot + "\", [StringComparison]::OrdinalIgnoreCase)) {
  throw "Release destination must be outside the source project: $destinationRoot"
}
if (Test-Path -LiteralPath $destinationRoot) {
  throw "Release destination already exists. Archive or remove it before publishing: $destinationRoot"
}
if (-not (Test-Path -LiteralPath $destinationParent)) {
  throw "Release destination parent does not exist: $destinationParent"
}

$safeSourceRoot = $sourceRoot.Replace('\', '/')
$commit = (& git -c "safe.directory=$safeSourceRoot" -C $sourceRoot rev-parse HEAD 2>$null)
if (-not $commit) { throw "Source is not a git repository; releases must map to a clean commit: $sourceRoot" }
$gitStatus = @(& git -c "safe.directory=$safeSourceRoot" -C $sourceRoot status --porcelain 2>$null)
if ($gitStatus.Count -gt 0) {
  Write-Host "Working tree is not clean. Releases must map to a clean commit (sourceDirty=false)." -ForegroundColor Yellow
  $gitStatus | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  throw "Refusing to publish from a dirty working tree. Commit or stash all changes first."
}

Write-Host "Running release checks."
& (Join-Path $sourceRoot "check-release.ps1") -DockerExe $DockerExe
if ($LASTEXITCODE -ne 0) { throw "Release checks failed." }

$sourceFiles = @(
  Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force |
    Where-Object {
      $_.FullName -notlike "$sourceRoot\.git\*" -and
      $_.FullName -notlike "$sourceRoot\.agents\*" -and
      $_.Name -notlike "*.log"
    }
)
$sourceBytes = ($sourceFiles | Measure-Object -Property Length -Sum).Sum
$driveRoot = [IO.Path]::GetPathRoot($destinationRoot)
$freeBytes = (Get-PSDrive -Name $driveRoot.Substring(0, 1)).Free
if ($freeBytes -lt ($sourceBytes + 1GB)) {
  throw "Insufficient free space. Required: $([math]::Round(($sourceBytes + 1GB) / 1GB, 2)) GB; available: $([math]::Round($freeBytes / 1GB, 2)) GB."
}

$stagingRoot = Join-Path $destinationParent (".$destinationName.staging-$PID")
if (Test-Path -LiteralPath $stagingRoot) {
  throw "Staging destination already exists: $stagingRoot"
}

try {
  Write-Host "Copying offline runtime package to staging directory."
  New-Item -ItemType Directory -Path $stagingRoot | Out-Null
  & robocopy $sourceRoot $stagingRoot /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XD .git .agents /XF *.log /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }

  $releaseInfo = [ordered]@{
    project = "ieta-znz-deploy"
    purpose = "multi-application shared offline Docker base runtime"
    createdAt = (Get-Date).ToString("o")
    sourceCommit = $commit.Trim()
    sourceDirty = $false
    platforms = @("windows-amd64-via-wsl", "linux-amd64", "linux-arm64")
    imageDelivery = "local-offline-archives-only"
  }
  $releaseInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stagingRoot "release-info.json") -Encoding utf8

  Write-Host "Generating SHA-256 file manifest."
  $hashLines = Get-ChildItem -LiteralPath $stagingRoot -Recurse -File -Force |
    Where-Object { $_.Name -ne "release-files.sha256" } |
    Sort-Object FullName |
    ForEach-Object {
      $relativePath = $_.FullName.Substring($stagingRoot.Length + 1).Replace("\", "/")
      $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      "$hash  $relativePath"
    }
  $hashLines | Set-Content -LiteralPath (Join-Path $stagingRoot "release-files.sha256") -Encoding ascii

  Rename-Item -LiteralPath $stagingRoot -NewName $destinationName
  $stagingRoot = $null
} finally {
  if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
    Write-Warning "Incomplete staging directory retained for inspection: $stagingRoot"
  }
}

$releaseFiles = Get-ChildItem -LiteralPath $destinationRoot -Recurse -File -Force
$releaseBytes = ($releaseFiles | Measure-Object -Property Length -Sum).Sum
Write-Host "Release published: $destinationRoot"
Write-Host "Files: $($releaseFiles.Count)"
Write-Host "Size: $([math]::Round($releaseBytes / 1GB, 2)) GB"
