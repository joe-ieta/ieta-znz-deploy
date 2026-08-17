# Open Items

本文档记录 `ieta-znz-deploy` 当前已确认的问题和后续优化项。优先级定义：

- P0：影响安全、基础可用性或首版交付，发布前应优先解决；
- P1：影响一致性、可维护性或应用接入质量；
- P2：能力增强和长期治理。

状态使用 `open`、`in-progress`、`done`。完成事项应在提交中更新状态并记录验证证据，不直接删除历史条目。

## P0

### OI-001 生产凭据和初始化密码治理

- 状态：open
- 现状：根目录 `.env`、`project-env/` 和 `init/mysql/01-init.sql` 存在简单且重复的默认密码；MySQL 应用用户密码硬编码在 SQL 中，单独修改 `.env` 不能完成统一换密。
- 风险：误用默认值会造成未授权访问；模板、初始化脚本和实际部署值容易漂移。
- 目标：提交内容只保留明确的开发示例或变量占位符；生产值从部署环境、安全文件或密钥系统注入；应用使用独立最小权限账号。
- 验收：从空 volume 部署时不依赖源码中的生产密码；换密流程有文档且不会要求重建全部业务数据。

### OI-002 Elasticsearch 8 健康检查与认证不一致

- 状态：done
- 决策：健康检查携带 `elastic:${ELASTIC_PASSWORD}` 基础认证；无认证模式服务端忽略凭据，启用认证模式不再因 401 误判 unhealthy。
- 实现：`docker-compose.ieta-znz-deploy.yml` 中 `es8-ragflow` 健康检查使用 `curl -fs -u elastic:${ELASTIC_PASSWORD} http://localhost:9200`；`es7-cdc` 按 `ES7_SECURITY_ENABLED` 条件化携带凭据（2026-08-16）。
- 验收：启用认证后容器能够稳定进入 healthy，错误密码时检查明确失败。

### OI-003 Dyna Report 容器模板中的 OnlyOffice 地址

- 状态：open
- 现状：`project-env/ieta-dyna-report.env` 是容器运行模板，但 Document Server 地址为 `http://127.0.0.1:8088`。
- 风险：应用运行在容器内时，`127.0.0.1` 指向应用容器自身，与共享网络契约不一致。
- 目标：确认应用真实部署拓扑；容器间连接改用 `http://onlyoffice-document-server`，宿主机模板继续使用宿主机端口。
- 验收：容器运行和宿主机运行两种模式均完成文档编辑与回调验证。

### OI-004 镜像引用和 Git 边界

- 状态：done
- 决策：仓库只维护固定版本镜像引用、拉取脚本和平台说明，不提交或发布镜像 tar。
- 实现：`pull-images.ps1` 和各 Ubuntu 平台脚本使用 `docker pull --platform`；`.gitignore` 排除本地 tar；启动脚本不再加载 tar。
- 验收：首版 Git 暂存内容不包含镜像二进制，`check-release.ps1` 能拒绝浮动标签并检查 Compose 与 `image-list.txt` 一致。

## P1

### OI-005 固定镜像版本

- 状态：done
- 实现：PostgreSQL、Valkey、OnlyOffice、llama.cpp、vLLM 以及其余基础服务均使用明确版本或构建标签；`latest` 和通用 `server` 标签已移除。
- 当前基线：`postgres:16.14`、`valkey/valkey:8.1.8`、`onlyoffice/documentserver:9.4.0`、`ghcr.io/ggml-org/llama.cpp:server-b10015`、`vllm/vllm-openai:v0.25.0`。
- 后续：正式升级仍应评估兼容性，并可进一步记录 registry digest。

### OI-006 平台支持文档与构建状态一致性

- 状态：done
- 实现：`BUILD_STATUS.md` 改为镜像引用和校验状态，`PLATFORM_SUPPORT.md` 改为 registry manifest 平台支持；不再维护 tar 大小和 SHA256。
- 验收：两份文档使用同一组固定版本引用，并明确区分 manifest 支持与运行级验证。

### OI-007 跨平台脚本能力对齐

- 状态：in-progress
- 实现：三平台 `status-app-base` 均以"服务 healthy + `HOST_PROBES` 宿主机端口探测"为成功标准并输出各端口状态，失败返回非零退出码（Linux 2026-08-16；Windows `status-app-base.ps1` 同步补齐）。
- 剩余：Windows 启动脚本提供端口预检，Ubuntu 脚本尚无等价端口预检。
- 目标：统一 Windows、Ubuntu AMD64、Ubuntu ARM64 的端口检查、profile 选择、状态和失败返回码。
- 验收：三平台对配置错误、端口冲突和启动失败具有一致语义。

### OI-008 应用清单与环境模板完整性

- 状态：open
- 现状：RAGFlow 清单的 `HOST_ENV_TEMPLATE` 指向容器模板且缺少独立 host 文件；Dyna Snapshot 和 MQ Message 尚无完整模板，MQ Message 的依赖仍待确认。
- 目标：为所有已接入应用提供有效的 container/host 模板，或明确声明不适用；增加自动校验。
- 验收：清单引用的文件都存在，所有 `REQUIRED_SERVICES` 都能在 Compose 中解析。

### OI-009 服务就绪和运行级验收

- 状态：open
- 现状：Compose 能通过静态配置校验，但尚未形成各平台全量启动、健康、持久化和应用连接的统一验收记录。已补齐：`flink-jobmanager` 的 `/overview` healthcheck（2026-08-16）；Linux `status-app-base.sh` 以"服务 healthy + 宿主机端口探测"为成功标准并输出各端口状态（`HOST_PROBES` 声明于应用清单）。OnlyOffice 和 LLM 等服务仍缺健康检查，运行级验收矩阵待建立。
- 目标：建立按 capability 的 smoke test，覆盖首次启动、重复启动、重启、数据保留和真实客户端连接。
- 验收：每个目标平台发布前生成可追溯的测试结果。

### OI-010 数据隔离和最小权限

- 状态：open
- 现状：部分连接模板直接使用 PostgreSQL `postgres` 或 MySQL root 密码，初始化脚本承担了少量应用库创建。已补齐：`init/postgres/optional/01-ieta-cdc-minimal-privileges.sql`（可选、默认不执行）按消费方容量指南提供 `ieta_core`/`ieta_cdc_writer`/`ieta_cdc_ops` 角色分离，运维文档明确"超级用户仅限开发联调"。应用默认仍使用超级用户模板，切换为最小权限账号尚未落地。
- 目标：每个应用使用独立 database/schema、用户和最小权限；业务迁移回归应用发布包。
- 验收：应用运行不依赖数据库超级用户，撤销某应用账号不会影响其他应用。

### OI-011 初始化和升级机制

- 状态：open
- 现状：`init/` 仅在空 volume 首次启动时执行；后续修改不会自动作用于已有环境。
- 目标：明确基础初始化的版本边界，并为需要升级的公共配置提供幂等、可审计流程。
- 验收：从上一发布版本升级时不要求删除 volume，且失败后有恢复说明。

### OI-012 发布校验自动化

- 状态：open
- 现状：`check-release.ps1` 已校验 Compose、固定标签、镜像总清单一致性，并新增 `.env` 与 `project-env/*.host.env` 端口一致性（2026-08-16）；新增 `publish-release.ps1` 拒绝脏工作区发布并校验离线归档 RepoTags。尚未覆盖 Linux shell 语法、应用清单引用、敏感信息检查和可选 registry manifest 检查。
- 目标：增加跨平台脚本静态检查、应用清单引用检查、敏感信息检查和可选 registry manifest 检查。
- 验收：CI 或发布脚本能对首版交付要求给出明确成功/失败结果。

### OI-013 备份、恢复和容量运维

- 状态：open
- 现状：文档提醒不要随意删除 volume，但尚无 PostgreSQL、MySQL、MinIO、Elasticsearch、OnlyOffice 的备份恢复流程和容量阈值。
- 目标：定义备份范围、恢复演练、保留周期、磁盘预警和数据销毁流程。
- 验收：至少完成一次空机恢复演练并记录恢复点目标。

## P2

### OI-014 LLM 能力交付边界

- 状态：open
- 现状：llama.cpp 和 vLLM 已使用固定镜像引用并可由 `-IncludeLLM`/`INCLUDE_LLM=1` 拉取，但 `models/` 为空，GPU/runtime 条件未形成验证矩阵。
- 目标：明确 CPU/GPU、模型格式、模型来源、许可证、显存/内存和平台兼容要求。
- 验收：LLM profile 具有独立说明和目标硬件上的端到端验证。

### OI-015 可观测性与共享服务责任

- 状态：open
- 现状：当前主要依赖 `docker compose ps` 和容器日志，没有统一指标、日志保留或告警约定。
- 目标：定义共享基础服务的监控指标、日志位置、告警责任和应用侧关联信息。
- 验收：常见故障能够从统一入口定位到服务、应用和数据边界。

## 需求批次记录

### OI-016 ieta-cdc-core 发布物能力要求（R1-R9）落地

- 状态：done
- 来源：`ieta-cdc-core` 消费方 `docs/operations/ieta-znz-deploy-requirements.md`。
- 实现：
  - R1：`FLINK_TASK_SLOTS=21`（不低于 21）、`FLINK_TM_REPLICAS=3` 默认 3 个 TaskManager 副本，`apps/ieta-cdc-core.env` 声明 `FLINK_TOTAL_SLOTS=63`；
  - R2：`FLINK_JM_MEM`/`FLINK_TM_MEM` 注入 `FLINK_PROPERTIES`；
  - R3：`flink_lib` 卷生命周期文档化，`scripts/ubuntu-{amd64,arm64}/update-flink-lib.sh` 放置 connector，Runner JAR 重建后一致性检查指引；
  - R4：`flink-jobmanager` healthcheck（`/overview`），Linux `status-app-base.sh` 增加 healthy 判定与宿主机端口探测（15432/19200/19081）；
  - R5：`check-release.ps1` 校验 `.env` 与 `project-env/*.host.env` 端口一致；
  - R6：`publish-release.ps1` 拒绝脏工作区，`release-info.json` 的 `sourceDirty` 恒为 false 并记录 `sourceCommit`；发布物生成在仓库同级 `ieta-znz-deploy-release/`，离线归档按 `scripts/common/image-archives.txt` 校验（存在性 + tar 内 RepoTags + 必须属于固定镜像引用）；
  - R7：`ES7_SECURITY_ENABLED`/`ELASTIC_PASSWORD` 环境变量化，健康检查与宿主机探测感知认证，文档声明无 TLS 边界；
  - R8：可选最小权限脚本与角色分离说明（`ieta_core`/`ieta_cdc_writer`/`ieta_cdc_ops`）；
  - R9：`BUILD_STATUS.md` 补充 Flink/connector/PG/MySQL/ES7 兼容性声明与验证状态；
  - R10：`images/linux-{amd64,arm64}` 归档按固定引用 `docker save` 重新生成（tar 内 RepoTag == Compose pinned tag），`publish-release.ps1` 拒绝未列入 `image-list.txt` 的归档标签；
  - R11：README 与运维指南新增"Flink 首次启动必做"清单（connector 放置与 ES7 shaded jar 警告、重启、Runner 上传/核对/rebind、容器重建触发条件），`update-flink-lib.sh` 用法进入 README 主流程。
- 验证：静态校验（compose 配置、脚本语法、端口一致性逻辑）通过；归档已按固定引用重建并逐项核验（标签/架构）；运行级验收（`/overview` 槽位随配置变化、内存配置生效、认证切换、连接器加载）由发布方在目标平台执行并记录到 `BUILD_STATUS.md`。

## 当前命名基线

项目当前统一使用：

- 项目、安装目录和发布物：`ieta-znz-deploy`；
- Compose 项目名：`ieta-znz-deploy`；
- Docker 网络：`ieta-znz-deploy`；
- Compose 文件：`docker-compose.ieta-znz-deploy.yml`；
- 网络环境变量：`IETA_ZNZ_DEPLOY_NETWORK`。

新增脚本、配置和文档必须遵循该命名基线。
