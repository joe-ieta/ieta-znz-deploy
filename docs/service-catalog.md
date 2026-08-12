# Service Catalog

| Capability | Compose service | Image | Shared contract |
| --- | --- | --- | --- |
| `postgres` | `postgres` | `postgres:16.14` | Shared metadata/runtime database. Use separate databases, schemas, and users per application. |
| `mysql` | `mysql8` | `mysql:8.0.39` | Shared MySQL 8 with row binlog enabled for CDC scenarios. Use separate databases/users. |
| `minio` | `minio` | `pgsty/minio:RELEASE.2026-03-25T00-00-00Z` | Shared object storage. Use separate buckets/prefixes and credentials where needed. |
| `valkey` | `valkey` | `valkey/valkey:8.1.8` | Redis-compatible cache/queue primitive. Use key prefixes per application. |
| `es8` | `es8-ragflow` | `elasticsearch:8.11.3` | Elasticsearch 8 service for RAGFlow-compatible workloads. |
| `es7` | `es7-cdc` | `docker.elastic.co/elasticsearch/elasticsearch:7.17.29` | Elasticsearch 7 service for CDC/Flink ES7 connector compatibility. Auth is optional via `.env` `ES7_SECURITY_ENABLED`/`ELASTIC_PASSWORD`; no TLS transport encryption. |
| `flink` | `flink-jobmanager`, `flink-taskmanager` | `flink:1.20.3-scala_2.12-java17` | Shared Flink runtime. Slots/memory are parametrized via `.env` (`FLINK_TASK_SLOTS`, `FLINK_TM_REPLICAS`, `FLINK_JM_MEMORY`, `FLINK_TM_MEMORY`). Application-owned runner jars/connectors must be staged into the `flink_lib` volume (see operations-guide §8). |
| `onlyoffice` | `onlyoffice-document-server` | `onlyoffice/documentserver:9.4.0` | Shared OnlyOffice Document Server. Applications own callback URLs and JWT alignment. |

## Version boundary notes

- `es7` and `es8` are intentionally separate capabilities.
- `postgres` is currently PostgreSQL 16. Do not downgrade it for a single application; add compatibility notes or a separately named capability if an application cannot support PostgreSQL 16.
- LLM capabilities are not registered because the required AMD64 and ARM64 offline archives are not part of the current delivery.
