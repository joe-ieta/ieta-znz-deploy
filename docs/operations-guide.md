# ieta-znz-deploy 运维指南

## 1. 定位

`ieta-znz-deploy` 是面向多个业务工程的共享 Docker 基础容器包。它维护固定版本、离线镜像归档、共享网络、持久化数据卷，以及按应用划分的启停和状态命令。镜像 tar 保存在本地发布介质中，但不纳入 Git 或任何远端项目库。

## 2. 基础规则

- 业务应用容器加入外部 Docker 网络 `ieta-znz-deploy`。
- 容器间通过 Compose 服务名访问基础能力。
- 主机端口只用于本机调试和运维访问。
- 第三方镜像必须使用 `image-list.txt` 和 Compose 中的固定版本引用。
- `stop` 默认不能删除 volume；数据销毁必须显式执行。
- Elasticsearch 7 和 Elasticsearch 8 按版本边界独立维护。

## 3. 安装前检查

1. 安装 Docker 和 Docker Compose。
2. 确认宿主机架构和目标容器平台。
3. 修改 `.env` 中的示例密码和冲突端口。
4. 确认目标平台的离线镜像归档完整。
5. 执行发布配置检查。

Windows AMD64：

```powershell
.\load-images.ps1 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\check-release.ps1 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
```

Ubuntu AMD64：

```bash
bash scripts/ubuntu-amd64/load-images.sh
```

Ubuntu ARM64：

```bash
bash scripts/ubuntu-arm64/load-images.sh
```

Windows 只支持 AMD64，并通过 WSL 运行 Linux 容器；Windows ARM 不受支持。LLM 服务当前未纳入基础包，不能通过本项目启动。

## 4. 按应用启动

Windows：

```powershell
.\start-app-base.ps1 -App ieta-cdc-core -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\status-app-base.ps1 -App ieta-cdc-core -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
```

Ubuntu：

```bash
bash scripts/ubuntu-amd64/start-app-base.sh ieta-cdc-core
bash scripts/ubuntu-amd64/status-app-base.sh ieta-cdc-core

bash scripts/ubuntu-arm64/start-app-base.sh ieta-cdc-core
bash scripts/ubuntu-arm64/status-app-base.sh ieta-cdc-core
```

`status-app-base` 以"必需服务全部 `healthy`（无健康检查的服务为 `running`）且 `HOST_PROBES` 声明的宿主机端口探测成功"为成功标准，任一失败返回非零退出码。探测端口取自根目录 `.env`（唯一事实来源），应用清单只声明端口变量名和探测方式。

## 5. 按能力启动

```powershell
.\start-base-env.ps1 -Profiles postgres,mysql,es7,flink
.\start-base-env.ps1 -Profiles postgres,onlyoffice
.\start-base-env.ps1 -Profiles mysql,minio,valkey,es8
```

能力与服务对应关系见 `scripts/common/service-catalog.env`。

## 6. 停止策略

停止整个基础环境并保留数据：

```powershell
.\stop-base-env.ps1
```

按应用停止会影响共享服务，默认拒绝；确认没有其他应用使用后才允许：

```powershell
.\stop-app-base.ps1 -App ieta-cdc-core -Force
```

只在确认销毁全部共享数据时使用：

```powershell
.\stop-base-env.ps1 -RemoveVolumes
```

## 7. 端口和连接

默认宿主机端口在 `.env` 中维护。容器内连接使用：

| 能力 | 容器内地址 |
| --- | --- |
| PostgreSQL | `postgres:5432` |
| MySQL | `mysql8:3306` |
| MinIO | `minio:9000` |
| Valkey | `valkey:6379` |
| Elasticsearch 8 | `http://es8-ragflow:9200` |
| Elasticsearch 7 | `http://es7-cdc:9200` |
| Flink REST | `http://flink-jobmanager:8081` |
| OnlyOffice | `http://onlyoffice-document-server` |

宿主机运行应用时使用 `project-env/*.host.env`。

## 8. Flink 容量与连接器

### 8.1 槽位与内存参数

| 变量（.env） | 默认值 | 含义 |
| --- | ---: | --- |
| `FLINK_TASK_SLOTS` | 21 | 每个 TaskManager 的槽位数；CDC Core 默认容量门禁要求提交前 `/overview` 空闲槽 `>= 21` |
| `FLINK_TM_REPLICAS` | 1 | TaskManager 副本数部署意图声明，实际生效用 `--scale` |
| `FLINK_JM_MEMORY` | 2g | `jobmanager.memory.process.size` |
| `FLINK_TM_MEMORY` | 5g | `taskmanager.memory.process.size`（容量指南建议每 20 槽约 3~5GB） |

总槽位 = `FLINK_TASK_SLOTS × FLINK_TM_REPLICAS`。`apps/ieta-cdc-core.env` 中的 `FLINK_TOTAL_SLOTS` 是供消费方核对容量门禁的声明，发布校验保证它与 `.env` 一致。

默认 21 槽（单 TaskManager）在"保留 20 个空闲槽"的门禁下只允许同时运行 1 个 Job，用于功能与边界验证。200 表生产阶段至少需要 221 个总槽位，建议 240 个并分布到多个 TaskManager：

```bash
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml \
  --profile flink up -d --scale flink-taskmanager=12
```

调整 `.env` 槽位/内存变量后重启 Flink：`docker compose restart flink-jobmanager flink-taskmanager`；随后通过 `http://<host>:<FLINK_REST_PORT>/overview` 核对 `slots-total` 与 `slots-available` 是否变化，并按需 `docker compose up -d --scale` 调整副本数。

### 8.2 flink_lib 卷生命周期

`flink_lib` 是 Compose 命名卷，挂载到 `/opt/flink/lib/ieta`（Flink 类路径递归包含该目录下的 jar）。

| 操作 | flink_lib 是否保留 |
| --- | --- |
| 容器重建 / `docker compose restart` / `up -d` | 保留 |
| `docker compose down`（本项目 `stop-base-env.ps1`） | 保留 |
| `stop-base-env.ps1 -RemoveVolumes`（`down --volumes`） | **删除**，需重新放置连接器 |

### 8.3 Connector 放置与 Runner JAR 一致性

Connector（PostgreSQL CDC、MySQL CDC、JDBC、ES7）与 Runner 等应用 JAR 由业务应用负责放置，可使用本项目复制脚本：

```bash
bash scripts/ubuntu-amd64/copy-flink-connectors.sh /path/to/connector-jars
bash scripts/ubuntu-arm64/copy-flink-connectors.sh /path/to/connector-jars
```

```powershell
.\scripts\windows\copy-flink-connectors.ps1 -SourceDir D:\path\to\connector-jars
```

脚本把 `*.jar` 复制进 `flink_lib` 卷并自动重启 JobManager/TaskManager（连接器在 JVM 启动时加载，必须先放置再重启），随后用 `curl -fs http://127.0.0.1:19081/overview` 验证 Flink 就绪。

Runner JAR 通过 Flink REST 上传时保存在 JobManager 容器文件系统，**不持久化**：容器重建后 `GET /jars` 返回的 jar id 会变化。上传后立即核对真实 jar id 并通过数据源 ETag/If-Match 绑定；容器重建后必须按消费方文档重新上传并重新核对。

## 9. Elasticsearch 7 安全边界

`es7-cdc` 默认无认证（`xpack.security.enabled=false`）。可选开启认证：`.env` 设置 `ES7_SECURITY_ENABLED=true`，`elastic` 用户密码取 `ELASTIC_PASSWORD`，CDC Core 的 ES 数据源通过 username/password 认证连接。当前边界为**仅认证、无 TLS 传输加密**（`xpack.security.http.ssl.enabled=false`），生产网络必须自行保证传输安全。

## 10. 数据库最小权限账号（可选）

`init/postgres/02-cdc-roles.sh` 提供可选的最小权限账号，仅在空 volume 首次初始化时执行。在 `.env` 设置 `IETA_CORE_PASSWORD`、`IETA_CDC_WRITER_PASSWORD`、`IETA_CDC_OPS_PASSWORD` 后启用；任一为空则脚本自动跳过。

| 角色 | 权限 |
| --- | --- |
| `ieta_core` | 拥有 `ieta_cdc` schema（DDL+DML） |
| `ieta_cdc_writer` | 对 schema `ieta_cdc` 的表 DML、序列使用 |
| `ieta_cdc_ops` | 只读 |

默认 `postgres` 超级用户仅限开发联调；生产必须使用独立最小权限账号，并按消费方容量指南进行角色治理。

## 11. 常见问题

端口冲突：修改 `.env` 中的宿主机端口，不修改容器内端口或服务名。

镜像缺失：确认发布包中的对应架构 tar 完整，然后运行 `load-images.ps1` 或对应平台的 `load-images.sh`。兼容保留的 `pull-images` 入口也只调用本地加载，不访问远端仓库。

镜像版本调整：必须同时更新 Compose、`image-list.txt`、对应 profile 清单、`docs/service-catalog.md`、`BUILD_STATUS.md` 和 `PLATFORM_SUPPORT.md`。

服务未启动：

```powershell
.\status-app-base.ps1 -App ieta-cdc-core
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml ps
```

数据异常：不要直接删除 volume。先完成备份，再决定是否执行 `-RemoveVolumes`。
