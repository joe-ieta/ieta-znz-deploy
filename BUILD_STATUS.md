# Build Status

Generated on 2026-08-12.

## Release model

This repository is prepared as an offline base runtime package.
Shared service images are stored as local archive files under `images/`.
Normal package delivery loads those archives into the local Docker image store.

The package does not rely on pulling images from a remote registry during standard delivery.
The image archives are local deployment media and must not be pushed to any remote repository.

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

The canonical image reference list is `image-list.txt`.
The offline archive list is `scripts/common/image-archives.txt`.

## Compatibility declarations (CDC consumer)

Declared against the CDC Core consumer baseline (docs: ZNZ 容器环境模式启动说明, CDC 200 表汇聚阶段部署与容量配置指南). Validation status: `declared` means no runtime evidence recorded in this repository; `validated` means verified evidence exists.

| Item | Declaration | Status |
| --- | --- | --- |
| Flink runtime | `flink:1.20.3-scala_2.12-java17` (Java 17 JRE); Runner JAR is a Java 11-compiled artifact running on the Java 17 runtime. Flink 1.20 is a supported runtime for the declared connector versions below. | declared — runtime validation pending (OI-009) |
| PostgreSQL CDC connector | 3.6.0 on Flink 1.20 | declared |
| MySQL CDC connector | 3.6.0 on Flink 1.20 | declared |
| JDBC connector | 3.3.0 on Flink 1.20 | declared |
| Elasticsearch 7 connector | 3.1.0 (targets ES 7.x) on Flink 1.20 | declared |
| Source/target boundary | PostgreSQL `16.14` and MySQL `8.0.39` as CDC source/target. Known boundary: the shared `mysql8` service fixes `server-id=1`; a fixed single server-id is only valid while one CDC consumer shares the source at a time — multi-task shared-source scenarios require per-task server-id ranges (consumer-side conflict detection fails closed on overlap). | declared |
| ES7 capacity | `ES_JAVA_OPTS=-Xms512m -Xmx512m` and `ES7_MEM_LIMIT=2GB` are development-level sizing; multi-table/aggregation workloads must raise these values, and the `es7-cdc` mem_limit keeps the JVM heap below the container limit. | declared |
| Flink capacity | `FLINK_TASK_SLOTS=21` single-TaskManager default satisfies the Core default gate (`slots-available >= 21`) for one concurrent job only; 200-job phase needs `>= 221` total slots (`FLINK_TASK_SLOTS * FLINK_TM_REPLICAS`, scaled via `--scale flink-taskmanager=N`). | declared — runtime validation pending (OI-009) |

## Current verification

- Compose file: `docker-compose.ieta-znz-deploy.yml`
- Compose project and network: `ieta-znz-deploy`
- Full-profile Compose configuration: checked by `check-release.ps1`
- Compose/image-list consistency: checked by `check-release.ps1`
- Floating tag rejection: checked by `check-release.ps1`
- Offline archive manifest presence: checked by `check-release.ps1`
- Offline archive file presence for `linux/amd64`: checked by `check-release.ps1`
- Offline archive file presence for `linux/arm64`: checked by `check-release.ps1`
- Every Compose image is mapped to a local archive for both supported Linux architectures: checked by `check-release.ps1`
- App template file existence and `HOST_PROBES`/`HOST_PORT_MAP` validity: checked by `check-release.ps1`
- `.env` ports vs `project-env/*.host.env` consistency: checked by `check-release.ps1`
- `FLINK_TOTAL_SLOTS` vs `.env` slot totals: checked by `check-release.ps1`
- Clean-worktree release mapping (`sourceDirty=false`): enforced by `publish-release.ps1`

Runtime and application-level validation gaps remain recorded in `docs/open-items.md`.
