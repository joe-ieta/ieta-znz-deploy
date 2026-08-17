# ieta-znz-deploy 运维指南

## 1. 定位

`ieta-znz-deploy` 是 IETA 产品族的第三方基础容器部署工程。它维护固定版本的公共基础容器引用、共享网络、持久化数据卷和运维脚本，不发布业务应用容器，也不在 Git 仓库中保存镜像 tar。

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
4. 拉取目标平台镜像。
5. 执行发布配置检查。

Windows AMD64：

```powershell
.\pull-images.ps1 -Platform linux/amd64 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\check-release.ps1 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
```

Ubuntu AMD64：

```bash
bash scripts/ubuntu-amd64/pull-images.sh
```

Ubuntu ARM64：

```bash
bash scripts/ubuntu-arm64/pull-images.sh
```

LLM 镜像体积和硬件要求较高，默认不拉取。需要时使用 Windows 的 `-IncludeLLM` 或 Linux 的 `INCLUDE_LLM=1`。

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
| Flink REST | `http://flink-jobmanager:8081`（宿主机 `127.0.0.1:19081`） |
| OnlyOffice | `http://onlyoffice-document-server` |

宿主机运行应用时使用 `project-env/*.host.env`。`.env` 中 `POSTGRES_PORT`、`MYSQL_PORT`、`ES7_CDC_PORT`、`FLINK_REST_PORT` 与各 `project-env/*.host.env` 的对应端口必须一致，`check-release.ps1` 与 `publish-release.ps1` 会拒绝不一致的发布。

## 8. Flink 容量与运行参数

Flink 参数全部通过 `.env` 注入 `FLINK_PROPERTIES`，修改后执行：

```powershell
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml up -d flink-jobmanager flink-taskmanager
```

| `.env` 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `FLINK_TASK_SLOTS` | `21` | 每个 TaskManager 的槽位数。CDC Core 容量门禁 `sync.cdc.capacity.minimum-flink-free-slots=20` 要求每次提交时 `/overview` 的 `slots-available >= 21`，因此默认值不低于 21。 |
| `FLINK_TM_REPLICAS` | `3` | TaskManager 副本数。默认 3 与 CDC Core Green 安装器对齐，避免单 TaskManager 故障导致其上全部作业同时失败。 |
| `FLINK_JM_MEM` | `1600m` | `jobmanager.memory.process.size`。 |
| `FLINK_TM_MEM` | `4g` | `taskmanager.memory.process.size`。每 TaskManager 20 槽约需 3~5GB，默认 21 槽配 4g。 |

总槽位 = `FLINK_TASK_SLOTS` × `FLINK_TM_REPLICAS`（默认 63），在 `apps/ieta-cdc-core.env` 的 `FLINK_TOTAL_SLOTS` 与 `project-env/ieta-cdc-core.host.env` 注释中声明，供消费方核对容量门禁。修改槽位或副本数后 `docker compose up -d`，用 `curl http://127.0.0.1:19081/overview` 核对 `slots-total` / `slots-available`。

多 TaskManager 部署方式：

1. 修改 `.env` 的 `FLINK_TM_REPLICAS` 后 `docker compose up -d`（推荐，默认即 3 副本）；
2. 或临时调整：`docker compose up -d --scale flink-taskmanager=5`；
3. 或使用 `docker-compose.override.yml` 覆盖 `deploy.replicas`。

资源受限的小型环境可显式设置 `FLINK_TM_REPLICAS=1`。注意故障域影响：单 TaskManager 故障（容器退出、宿主机资源耗尽）会使该 TM 上的全部 CDC 作业同时失败，仅建议在开发或明确接受该风险的场景使用。

## 9. Flink 连接器、Runner 与 flink_lib 卷

> **首次启动必做**（CDC Core 场景按此顺序操作，缺一步会导致任务提交失败，
> 例如 `Could not find any factory for identifier 'postgres-cdc'` 或 `FLINK_RUNNER_JAR_NOT_FOUND`）：
>
> 1. **放置 connector jar 到 `flink_lib`**（容器内 `/opt/flink/lib/ieta`）：
>    - PostgreSQL CDC connector（如 `flink-sql-connector-postgres-cdc-3.6.0.jar`）；
>    - JDBC connector（如 `flink-connector-jdbc-3.3.0.jar`）；
>    - JDBC 驱动（如 `postgresql-42.x.jar`，视目标库补充 MySQL 驱动）；
>    - **警告：不要放置非 SQL shaded 版 `flink-connector-elasticsearch7-*.jar`**，它与 Flink SQL 的工厂加载机制冲突；ES7 写入请使用消费方指定的 SQL 兼容版本。
>
>    Linux 用 `scripts/ubuntu-amd64/update-flink-lib.sh <jar>...`（arm64 用 `scripts/ubuntu-arm64/`），
>    或等价命令：`docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml cp <jar> flink-jobmanager:/opt/flink/lib/ieta/`。
> 2. **重启 Flink**（TaskManager 自动重连）：
>    `docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml restart flink-taskmanager flink-jobmanager`
> 3. **验证 Flink 就绪**：`curl http://127.0.0.1:19081/overview` 返回正常；按需核对 `slots-total`/`slots-available`。
> 4. **上传 Runner JAR**（REST `POST /jars/upload` 或 Web UI），记录返回的 jarId；
>    **核对**：`curl http://127.0.0.1:19081/jars` 包含该 jarId。
> 5. **创建/绑定数据源并提交 CDC 任务**；若提示 configured jarId 不可用，先重传 Runner 并 rebind 后再提交。
>
> **触发条件**：JobManager 容器重建（`up -d --force-recreate`、崩溃自愈、镜像升级、宿主机重启拉起新容器）后，
> `/jars` 上传目录被清空——必须重新上传 Runner 并 rebind；`flink_lib` 中的 connector 不受影响，无需重放。

`flink_lib` 是 Compose 命名卷，挂载到 `flink-jobmanager` 与全部 `flink-taskmanager` 副本的 `/opt/flink/lib/ieta`。生命周期：

| 操作 | `flink_lib` 是否保留 |
| --- | --- |
| 容器重建（`up -d --force-recreate`、崩溃自愈、镜像升级） | 保留 |
| `docker compose restart` / `stop` / `start` | 保留 |
| `docker compose down`（`stop-base-env.sh` 不带参数） | 保留 |
| `docker compose down -v` / `stop-base-env.sh -RemoveVolumes` / `docker volume rm` | 删除 |

放置或更新 connector（Linux）：

```bash
bash scripts/ubuntu-amd64/update-flink-lib.sh /path/to/flink-sql-connector-postgres-cdc-3.6.0.jar
bash scripts/ubuntu-arm64/update-flink-lib.sh /path/to/flink-sql-connector-mysql-cdc-3.6.0.jar
```

脚本用 `docker compose cp` 写入 `flink_lib`，随后按提示重启 Flink（TaskManager 自动重连 JobManager）：

```bash
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml restart flink-taskmanager flink-jobmanager
```

Runner JAR 一致性检查：

- 通过 Flink REST/Web UI 上传 Runner 后，记录返回的 jarId（`GET /jars` 或上传响应）。
- 上传的 JAR 存放在 JobManager 容器内部存储中，容器重建后会丢失；`flink_lib` 中的 connector 不受影响。
- JobManager 容器重建后执行 `curl http://127.0.0.1:19081/jars` 复核 jarId；与任务绑定的 jarId 不可用（页面提示 configured jarId not found）时必须重新上传并重新绑定任务。
- 长期方案：将 Runner JAR 也放入 `flink_lib` 并改用 class 方式提交，或纳入应用发布包的 JAR 管理流程。

## 10. Elasticsearch 7 可选认证

`.env` 中设置 `ES7_SECURITY_ENABLED=true` 即启用 `es7-cdc` 的 `xpack.security`（用户 `elastic`，密码 `ELASTIC_PASSWORD`）。默认 `false`，无认证。

- 启用后健康检查自动携带 `elastic:${ELASTIC_PASSWORD}`；`status-app-base.sh` 的宿主机探测同理。
- 消费方（CDC Core）在 ES 数据源中配置 username/password 即可连接。
- 安全边界：当前部署无 TLS 传输加密，HTTP 端口上的认证凭据与数据均为明文传输，仅在受信网络内启用；对外暴露需要自行在边界加 TLS 或网络隔离。

## 11. 最小权限数据库账号

默认初始化仅创建数据库，连接模板使用 `postgres` 超级用户——**超级用户仅限开发联调，生产需自行治理**。

可选的最小权限脚本位于 `init/postgres/optional/01-ieta-cdc-minimal-privileges.sql`（默认不自动执行）。角色分离与 CDC Core 容量指南对齐：

| 角色 | 权限 |
| --- | --- |
| `ieta_core` | `ieta_cdc_core` 库 owner：DDL+DML |
| `ieta_cdc_writer` | 仅 DML（表级 SELECT/INSERT/UPDATE/DELETE，含 `ieta_core` 未来建表的默认权限） |
| `ieta_cdc_ops` | 只读（`pg_read_all_data`）+ 监控（`pg_monitor`） |

已有环境一次性应用：

```bash
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml \
  exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 \
  < init/postgres/optional/01-ieta-cdc-minimal-privileges.sql
```

新环境可把该文件复制到 `init/postgres/` 再首次启动空卷。使用前必须替换脚本中的占位密码。

## 12. 发布

```powershell
.\publish-release.ps1 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
```

发布物生成在仓库同级的 `ieta-znz-deploy-release/`（如 `E:\CodexDev\ieta-znz-deploy-release`），也可用 `-OutDir` 指定其他位置。发布前必须满足（不满足即拒绝发布）：

- Git 工作区干净（`sourceDirty=false` 是硬性要求，`sourceCommit` 指向可解析的干净提交）；
- `check-release.ps1` 全部通过（Compose 配置、固定镜像标签、镜像总清单、`.env` 与 `project-env/*.host.env` 端口一致性）；
- `scripts/common/image-archives.txt` 中列出的 `images/linux-amd64`、`images/linux-arm64` 归档齐全，tar 内 RepoTags 与清单登记一致，**且每个标签必须等于 Compose/`image-list.txt` 的固定镜像引用**。归档按固定引用 `docker save` 生成，干净离线环境 `docker load` 归档后 `compose up` 无需手动 retag。

发布产物 `ieta-znz-deploy-release/` 含 `release-info.json`（`createdAt`、`sourceCommit`、`sourceDirty=false`、`imageDelivery=local-offline-archives-only`）与覆盖全部文件的 `release-files.sha256`。消费方只读依赖该发布物，校验失败时返回本仓库处理并重新发布。

镜像来源标准记录、归档生成规范（`scripts/windows/regenerate-archives.ps1`）、全部检查点、验证清单与发布物丢失后的重建步骤，见 `docs/release-specification.md`。

## 13. 常见问题

端口冲突：修改 `.env` 中的宿主机端口，不修改容器内端口或服务名。

镜像缺失：运行对应平台的 `pull-images` 脚本。脚本只执行 `docker pull --platform`，不生成 tar。

镜像版本调整：必须同时更新 Compose、`image-list.txt`、对应 profile 清单、`docs/service-catalog.md`、`BUILD_STATUS.md` 和 `PLATFORM_SUPPORT.md`。

服务未启动：

```powershell
.\status-app-base.ps1 -App ieta-cdc-core
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml ps
```

数据异常：不要直接删除 volume。先完成备份，再决定是否执行 `-RemoveVolumes`。
