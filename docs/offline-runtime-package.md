# Offline Runtime Package

## Purpose

This repository delivers a shared base runtime package for other IETA applications.
The package contains:

- Docker Compose definitions for shared third-party services
- app-to-capability manifests under `apps/`
- connection templates under `project-env/`
- local offline image archives under `images/`
- startup, status, and stop scripts for Windows, Ubuntu AMD64, and Ubuntu ARM64

This package is intended to be distributed as a local offline delivery.
Container images are loaded from the local `images/` directory.
They are not pulled from a remote registry during normal package delivery, and they must not be pushed to any remote repository.

## Supported platforms

- Windows AMD64, using WSL and Docker Desktop, for `linux/amd64` containers only
- Ubuntu AMD64, for `linux/amd64` containers
- Ubuntu ARM64, for `linux/arm64` containers

Windows on ARM is not a supported target platform for this package.

## Offline image layout

- Windows / WSL runtime images: `images/linux-amd64/*.tar`
- Ubuntu AMD64 runtime images: `images/linux-amd64/*.tar`
- Ubuntu ARM64 runtime images: `images/linux-arm64/*.tar`

The tracked archive list is stored in `scripts/common/image-archives.txt`.

## Standard startup flow

### Windows AMD64

```powershell
.\load-images.ps1
.\start-base-env.ps1 -Preset all
.\status-base-env.ps1
```

For an application-scoped startup:

```powershell
.\start-app-base.ps1 -App ieta-cdc-core
```

### Ubuntu AMD64

```bash
bash scripts/ubuntu-amd64/load-images.sh
bash scripts/ubuntu-amd64/start.sh all
bash scripts/ubuntu-amd64/status-app-base.sh ieta-cdc-core
```

### Ubuntu ARM64

```bash
bash scripts/ubuntu-arm64/load-images.sh
bash scripts/ubuntu-arm64/start.sh all
bash scripts/ubuntu-arm64/status-app-base.sh ieta-cdc-core
```

## Delivery rules

- Keep offline image archives only in local delivery media or local package directories.
- Do not commit image tar files to Git.
- Do not push image tar files to GitHub or any other remote repository.
- Treat `images/` as deployment media, not as source code.
- Update `scripts/common/image-archives.txt` whenever offline archive filenames change.

## Release directory

The shared runtime is published to:

```text
E:\CodexDev\ieta-znz-deploy-release
```

Run:

```powershell
.\publish-release.ps1
```

The destination must not already exist. The release contains both offline architecture sets and generates `release-info.json` plus `release-files.sha256`.
