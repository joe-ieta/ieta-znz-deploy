# Service Catalog

| Capability | Compose service | Image | Shared contract |
| --- | --- | --- | --- |
| `postgres` | `postgres` | `postgres:16.14` | Shared metadata/runtime database. Use separate databases, schemas, and users per application. |
| `mysql` | `mysql8` | `mysql:8.0.39` | Shared MySQL 8 with row binlog enabled for CDC scenarios. Use separate databases/users. |
| `minio` | `minio` | `pgsty/minio:RELEASE.2026-03-25T00-00-00Z` | Shared object storage. Use separate buckets/prefixes and credentials where needed. |
| `valkey` | `valkey` | `valkey/valkey:8.1.8` | Redis-compatible cache/queue primitive. Use key prefixes per application. |
| `es8` | `es8-ragflow` | `elasticsearch:8.11.3` | Elasticsearch 8 service for RAGFlow-compatible workloads. |
| `es7` | `es7-cdc` | `docker.elastic.co/elasticsearch/elasticsearch:7.17.29` | Elasticsearch 7 service for CDC/Flink ES7 connector compatibility. Optional authentication via `ES7_SECURITY_ENABLED`/`ELASTIC_PASSWORD`; no TLS transport encryption (trusted network only). |
| `flink` | `flink-jobmanager`, `flink-taskmanager` | `flink:1.20.3-scala_2.12-java17` | Shared Flink runtime. Slots/replicas/memory parameterized in `.env` (`FLINK_TASK_SLOTS=21`, `FLINK_TM_REPLICAS=3`, `FLINK_JM_MEM`, `FLINK_TM_MEM`); JobManager has a `/overview` healthcheck. `flink_lib` named volume mounted at `/opt/flink/lib/ieta` for connector jars; application-owned runner jars/connectors must be staged via `scripts/*/update-flink-lib.sh`. |
| `onlyoffice` | `onlyoffice-document-server` | `onlyoffice/documentserver:9.4.0` | Shared OnlyOffice Document Server. Applications own callback URLs and JWT alignment. |
| `llama-cpp` | `llama-cpp` | `ghcr.io/ggml-org/llama.cpp:server-b10015` | Optional model serving. Requires model files under `models/`. |
| `vllm` | `vllm` | `vllm/vllm-openai:v0.25.0` | Optional OpenAI-compatible model serving. Requires model files and suitable runtime/GPU validation. |

## Version boundary notes

- `es7` and `es8` are intentionally separate capabilities.
- `postgres` is currently PostgreSQL 16. Do not downgrade it for a single application; add compatibility notes or a separately named capability if an application cannot support PostgreSQL 16.
- LLM capabilities are not part of the default non-LLM base environment.
