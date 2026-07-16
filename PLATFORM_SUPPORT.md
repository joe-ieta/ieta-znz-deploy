# Platform Support

Target platforms:

- Windows Docker Desktop: linux/amd64 containers.
- Ubuntu AMD64: linux/amd64 containers.
- Ubuntu ARM64: linux/arm64 containers.

## Image reference support

| Image | linux/amd64 | linux/arm64 | Notes |
| --- | --- | --- | --- |
| `postgres:16.14` | yes | yes | PostgreSQL 16.14. |
| `mysql:8.0.39` | yes | yes | Required by RAGFlow and CDC profiles. |
| `pgsty/minio:RELEASE.2026-03-25T00-00-00Z` | yes | yes | Shared object storage. |
| `valkey/valkey:8.1.8` | yes | yes | Redis-compatible shared service. |
| `elasticsearch:8.11.3` | yes | yes | RAGFlow-compatible ES8 service. |
| `docker.elastic.co/elasticsearch/elasticsearch:7.17.29` | yes | yes | CDC/Flink ES7 compatibility service. |
| `flink:1.20.3-scala_2.12-java17` | yes | yes | Shared Flink runtime. |
| `onlyoffice/documentserver:9.4.0` | yes | yes | Manifest checked on 2026-07-16. |
| `ghcr.io/ggml-org/llama.cpp:server-b10015` | yes | yes | CPU server manifest checked on 2026-07-16. |
| `vllm/vllm-openai:v0.25.0` | yes | yes | Manifest checked; GPU/runtime/model compatibility still requires host validation. |

“yes” means that the referenced registry manifest exposes the platform. It does not by itself mean that every capability has completed application-level runtime validation on that platform.

## Download

Windows:

```powershell
.\pull-images.ps1 -Platform linux/amd64
.\pull-images.ps1 -Platform linux/amd64 -IncludeLLM
```

Ubuntu:

```bash
bash scripts/ubuntu-amd64/pull-images.sh
INCLUDE_LLM=1 bash scripts/ubuntu-amd64/pull-images.sh

bash scripts/ubuntu-arm64/pull-images.sh
INCLUDE_LLM=1 bash scripts/ubuntu-arm64/pull-images.sh
```

The scripts pull fixed image references into the local Docker image store. They do not create tar files.
