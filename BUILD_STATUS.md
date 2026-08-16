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
- `check-release.ps1` also enforces `.env` host ports (POSTGRES_PORT, MYSQL_PORT, ES7_CDC_PORT, FLINK_REST_PORT) against `project-env/*.host.env` (added 2026-08-16)
- `publish-release.ps1` refuses a dirty worktree, verifies offline archive RepoTags against `scripts/common/image-archives.txt`, and writes `release-info.json` with `sourceDirty=false` plus `release-files.sha256` (added 2026-08-16)
- `flink-jobmanager` healthcheck (`/overview`) and Linux `status-app-base.sh` healthy/host-probe checks added (added 2026-08-16)
- Note: the local `images/` archives in the current workspace were produced before the tag pinning baseline (e.g. `postgres:16`, `valkey/valkey:8`, `onlyoffice/documentserver:latest`) and will be rejected by `publish-release.ps1`. Regenerate the archives from the pinned references before the next publish (`scripts/common/image-archives.txt` records the required RepoTags).

Runtime and application-level validation gaps remain recorded in `docs/open-items.md`.

## CDC Core compatibility declarations (Flink / databases / Elasticsearch 7)

The following declarations describe how the fixed runtime versions interact with the CDC Core
consumer's connectors and runner artifacts. Status "declared" means the compatibility claim is
recorded and version-pinned; runtime-level validation of the running CDC pipeline remains an
open release-verification item (`docs/open-items.md` OI-009).

### Flink 1.20.3-scala_2.12-java17 (Java 17)

| Component | Version | Compatibility declaration | Status |
| --- | --- | --- | --- |
| Flink runtime | `flink:1.20.3-scala_2.12-java17` (Java 17) | Baseline for all CDC Core Flink jobs. | declared |
| PostgreSQL CDC connector | 3.6.0 | Connector 3.x series is built for Flink 1.20 and runs on the Java 17 runtime. | declared |
| MySQL CDC connector | 3.6.0 | Connector 3.x series is built for Flink 1.20 and runs on the Java 17 runtime. | declared |
| JDBC connector | 3.3.0 | Flink 1.20-compatible release; used for CDC targets. | declared |
| Elasticsearch 7 connector | 3.1.0 | Targets Elasticsearch 7; paired with `es7-cdc` (7.17.29). | declared |
| Runner JAR (Java 11 bytecode) | consumer artifact | Java 17 JVM runs Java 11 class files (major version 55 < 61); no `--add-exports` expectation from this project. | declared |

### PostgreSQL 16.14 and MySQL 8.0.39 as CDC source/target

- PostgreSQL 16.14 serves as the CDC metadata database (`ieta_cdc_core`) and is in scope for the
  PostgreSQL CDC connector 3.6.0 source feature set (PostgreSQL 10-16 line).
- MySQL 8.0.39 runs with row-based binlog (`--binlog-format=ROW`, `--binlog-row-image=FULL`) and
  `--server-id=1`. `server-id=1` is the MySQL instance's own server id; when several CDC jobs
  consume the same shared source, each job's MySQL CDC source must be configured with a distinct
  client server-id to avoid replication channel conflicts. This deployment does not limit the
  number of consuming jobs.
- `init/mysql/01-init.sql` creates `ieta_cdc` with privileges on `ieta_cdc_core` as a development
  baseline; production should replace it with least-privilege accounts (see operations guide).

### Elasticsearch 7 capacity

- `es7-cdc` runs with `ES_JAVA_OPTS=-Xms512m -Xmx512m` (heap) and `ES7_MEM_LIMIT=2GB` (container
  memory limit; Elasticsearch also uses off-heap and mmap memory within that limit).
- The default sizing targets moderate CDC ES-sink workloads. For multi-table aggregation phases
  (e.g. the 200-table convergence stage), monitor heap pressure and raise `ES7_MEM_LIMIT` while
  adjusting `ES_JAVA_OPTS` (heap at roughly half the limit, e.g. 4GB limit with `-Xms2g -Xmx2g`)
  before scaling out. `ES_JAVA_OPTS` is currently fixed in the Compose file and is changed there.

