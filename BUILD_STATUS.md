# Build Status

Generated on 2026-07-16.

## Release model

The Git repository contains Docker Compose configuration, pinned image references, pull scripts and operational documentation. Container image tar files are not source artifacts and are not committed or published with the repository.

Users download images into the local Docker image store before startup:

```powershell
.\pull-images.ps1 -Platform linux/amd64
.\pull-images.ps1 -Platform linux/amd64 -IncludeLLM
```

Compose can also pull a missing referenced image during startup, but explicit pull scripts are preferred for installation preflight and predictable failure reporting.

## Pinned image references

| Capability | Image reference |
| --- | --- |
| PostgreSQL | `postgres:16.14` |
| MySQL | `mysql:8.0.39` |
| MinIO | `pgsty/minio:RELEASE.2026-03-25T00-00-00Z` |
| Valkey | `valkey/valkey:8.1.8` |
| Elasticsearch 8 | `elasticsearch:8.11.3` |
| Elasticsearch 7 | `docker.elastic.co/elasticsearch/elasticsearch:7.17.29` |
| Flink | `flink:1.20.3-scala_2.12-java17` |
| OnlyOffice | `onlyoffice/documentserver:9.4.0` |
| llama.cpp | `ghcr.io/ggml-org/llama.cpp:server-b10015` |
| vLLM | `vllm/vllm-openai:v0.25.0` |

The canonical combined list is `image-list.txt`. Profile-specific lists are used by the pull scripts.

## Current verification

- Compose file: `docker-compose.ieta-znz-deploy.yml`
- Compose project and network: `ieta-znz-deploy`
- Full-profile Compose configuration: passed on 2026-07-16
- Compose/image-list consistency: checked by `check-release.ps1`
- Floating tag rejection: checked by `check-release.ps1`
- OnlyOffice 9.4.0 manifest: linux/amd64 and linux/arm64 confirmed
- llama.cpp server-b10015 manifest: linux/amd64 and linux/arm64 confirmed
- vLLM v0.25.0 manifest: linux/amd64 and linux/arm64 confirmed

Runtime and application-level validation gaps remain recorded in `docs/open-items.md`.
