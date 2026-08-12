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
- 决策：健康检查与 es7-cdc 一致改为携带 `elastic:${ELASTIC_PASSWORD}` 基础认证，无认证模式服务端忽略凭据，启用认证模式不再因 401 误判 unhealthy。
- 实现：`docker-compose.ieta-znz-deploy.yml` 中 `es8-ragflow`、`es7-cdc` 健康检查统一使用 `curl -fs -u elastic:${ELASTIC_PASSWORD} http://localhost:9200`。
- 验收：启用认证后容器能够稳定进入 healthy；错误密码时检查明确失败。

### OI-003 Dyna Report 容器模板中的 OnlyOffice 地址

- 状态：open
- 现状：`project-env/ieta-dyna-report.env` 是容器运行模板，但 Document Server 地址为 `http://127.0.0.1:8088`。
- 风险：应用运行在容器内时，`127.0.0.1` 指向应用容器自身，与共享网络契约不一致。
- 目标：确认应用真实部署拓扑；容器间连接改用 `http://onlyoffice-document-server`，宿主机模板继续使用宿主机端口。
- 验收：容器运行和宿主机运行两种模式均完成文档编辑与回调验证。

### OI-004 镜像引用和 Git 边界

- 状态：done
- 决策：源码 Git 只维护固定版本引用、离线归档映射和平台说明；镜像 tar 保存在本地工程及发布目录，但不提交到远端项目库。
- 实现：启动脚本从 `images/` 执行本地加载；兼容保留的 `pull-images` 入口不再联网；`.gitignore` 排除本地 tar。
- 验收：Git 暂存内容不包含镜像二进制，`check-release.ps1` 能拒绝浮动运行标签，并检查 Compose、镜像清单、离线归档标签和架构一致。

## P1

### OI-005 固定镜像版本

- 状态：done
- 实现：PostgreSQL、Valkey、OnlyOffice 以及其余已发布基础服务均使用明确版本或构建标签；`latest` 和通用主版本标签仅作为 tar 内部源标签，由离线加载脚本映射到固定运行标签。
- 当前基线：`postgres:16.14`、`valkey/valkey:8.1.8`、`onlyoffice/documentserver:9.4.0`。
- 后续：正式升级仍应评估兼容性，并可进一步记录 registry digest。

### OI-006 平台支持文档与构建状态一致性

- 状态：done
- 实现：`BUILD_STATUS.md` 改为镜像引用和校验状态，`PLATFORM_SUPPORT.md` 改为 registry manifest 平台支持；不再维护 tar 大小和 SHA256。
- 验收：两份文档使用同一组固定版本引用，并明确区分 manifest 支持与运行级验证。

### OI-007 跨平台脚本能力对齐

- 状态：in-progress
- 实现：三平台 `status-app-base` 已统一为"服务 healthy + `HOST_PROBES` 宿主机端口探测 + 非零退出码"语义；`flink-jobmanager`/`flink-taskmanager` 已补充健康检查。
- 剩余：Ubuntu 启动脚本尚无 Windows 等价的启动前端口预检（`Test-RequiredPortsAvailable`）。
- 验收：三平台对配置错误、端口冲突和启动失败具有一致语义。

### OI-008 应用清单与环境模板完整性

- 状态：open
- 现状：RAGFlow 清单的 `HOST_ENV_TEMPLATE` 指向容器模板且缺少独立 host 文件；Dyna Snapshot 和 MQ Message 尚无完整模板，MQ Message 的依赖仍待确认。
- 目标：为所有已接入应用提供有效的 container/host 模板，或明确声明不适用；增加自动校验。
- 验收：清单引用的文件都存在，所有 `REQUIRED_SERVICES` 都能在 Compose 中解析。

### OI-009 服务就绪和运行级验收

- 状态：in-progress
- 实现：`flink-jobmanager`（`/overview`）、`flink-taskmanager`（进程检查）已增加健康检查；三平台状态脚本按 healthy + 宿主机探测判定成功。
- 剩余：OnlyOffice 仍无健康检查；尚未形成各平台全量启动、健康、持久化和应用连接的统一验收记录，Flink 槽位/内存参数化的运行级验证（`/overview` 变化）待执行。
- 目标：建立按 capability 的 smoke test，覆盖首次启动、重复启动、重启、数据保留和真实客户端连接。
- 验收：每个目标平台发布前生成可追溯的测试结果。

### OI-010 数据隔离和最小权限

- 状态：in-progress
- 实现：`init/postgres/02-cdc-roles.sh` 提供可选最小权限账号（`ieta_core`/`ieta_cdc_writer`/`ieta_cdc_ops`），密码经 `.env` → compose 环境注入，未配置时自动跳过；文档明确超级用户仅限开发联调。
- 剩余：连接模板仍默认使用 `postgres`/root 示例值；MySQL 应用账号和 RAGFlow/Dyna Report 账号的最小权限治理未落地。
- 目标：每个应用使用独立 database/schema、用户和最小权限；业务迁移回归应用发布包。
- 验收：应用运行不依赖数据库超级用户，撤销某应用账号不会影响其他应用。

### OI-011 初始化和升级机制

- 状态：open
- 现状：`init/` 仅在空 volume 首次启动时执行；后续修改不会自动作用于已有环境。
- 目标：明确基础初始化的版本边界，并为需要升级的公共配置提供幂等、可审计流程。
- 验收：从上一发布版本升级时不要求删除 volume，且失败后有恢复说明。

### OI-012 发布校验自动化

- 状态：in-progress
- 实现：`check-release.ps1` 已增加应用模板文件存在性、`HOST_PROBES` 变量存在性、`.env` 与宿主机模板端口一致性（`HOST_PORT_MAP`）、`FLINK_TOTAL_SLOTS` 与 `.env` 槽位总量一致性校验；`publish-release.ps1` 已拒绝非干净工作区发布（`sourceDirty` 恒为 false）。
- 剩余：Linux shell 语法检查、敏感信息检查和远端 registry manifest 检查尚未纳入。
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
- 现状：llama.cpp 和 vLLM 已从当前 Compose 与镜像清单中移除，避免纯离线安装时出现远端拉取。
- 目标：明确 CPU/GPU、模型格式、模型来源、许可证、显存/内存和平台兼容要求。
- 验收：准备 AMD64 和 ARM64 离线归档，登记固定标签映射，并在目标硬件上完成独立 profile 的端到端验证后再接入。

### OI-015 可观测性与共享服务责任

- 状态：open
- 现状：当前主要依赖 `docker compose ps` 和容器日志，没有统一指标、日志保留或告警约定。
- 目标：定义共享基础服务的监控指标、日志位置、告警责任和应用侧关联信息。
- 验收：常见故障能够从统一入口定位到服务、应用和数据边界。

## 当前命名基线

项目当前统一使用：

- 项目、安装目录和发布物：`ieta-znz-deploy`；
- Compose 项目名：`ieta-znz-deploy`；
- Docker 网络：`ieta-znz-deploy`；
- Compose 文件：`docker-compose.ieta-znz-deploy.yml`；
- 网络环境变量：`IETA_ZNZ_DEPLOY_NETWORK`。

新增脚本、配置和文档必须遵循该命名基线。
