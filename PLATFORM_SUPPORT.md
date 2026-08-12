# Platform Support

Target platforms:

- Windows AMD64, using WSL and Docker Desktop, for `linux/amd64` containers only
- Ubuntu AMD64, for `linux/amd64` containers
- Ubuntu ARM64, for `linux/arm64` containers

Windows on ARM is not a supported target platform.

## Offline archive support

| Archive set | Runtime platform | Notes |
| --- | --- | --- |
| `images/linux-amd64/*.tar` | Windows AMD64 via WSL, Ubuntu AMD64 | Standard offline base runtime delivery |
| `images/linux-arm64/*.tar` | Ubuntu ARM64 | Standard offline base runtime delivery |

## Pinned image reference support

| Image | linux/amd64 | linux/arm64 | Notes |
| --- | --- | --- | --- |
| `postgres:16.14` | yes | yes | PostgreSQL 16.14 |
| `mysql:8.0.39` | yes | yes | Required by RAGFlow and CDC profiles |
| `pgsty/minio:RELEASE.2026-03-25T00-00-00Z` | yes | yes | Shared object storage |
| `valkey/valkey:8.1.8` | yes | yes | Redis-compatible shared service |
| `elasticsearch:8.11.3` | yes | yes | RAGFlow-compatible ES8 service |
| `docker.elastic.co/elasticsearch/elasticsearch:7.17.29` | yes | yes | CDC/Flink ES7 compatibility service |
| `flink:1.20.3-scala_2.12-java17` | yes | yes | Shared Flink runtime |
| `onlyoffice/documentserver:9.4.0` | yes | yes | Offline archive currently uses a local `latest` tar filename |

Registry manifest availability and offline package availability are different checks.
This file records platform support boundaries for the delivered runtime package.

LLM services are excluded from the current Compose baseline because their AMD64 and ARM64 offline archives are not bundled.

## Offline load commands

Windows AMD64:

```powershell
.\load-images.ps1
```

Ubuntu AMD64:

```bash
bash scripts/ubuntu-amd64/load-images.sh
```

Ubuntu ARM64:

```bash
bash scripts/ubuntu-arm64/load-images.sh
```
