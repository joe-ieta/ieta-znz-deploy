# 发布规范与重建指南

本文档是 `ieta-znz-deploy` 的权威发布规范：标准化记录本项目依赖的原始容器来源、离线归档生成规范、
发布检查点、验证清单、外部项目（`ieta-cdc-core`）要求追踪，以及发布物意外丢失后的重建步骤。

发布物（`ieta-znz-deploy-release/`）**不提交 Git、不推送远端**；任何发布物都可以按第 7 节 runbook
从仓库任意干净提交重新生成。

## 1. 依赖的原始容器（镜像来源标准化记录）

### 1.1 固定镜像引用总表

固定引用唯一真源是 `image-list.txt`；Compose 服务定义见 `docker-compose.ieta-znz-deploy.yml`，
能力到服务映射见 `scripts/common/service-catalog.env`，profile 子清单见 `image-list.*.txt`。

| 能力 | Compose 服务 | 固定镜像引用 | 来源仓库 | linux/amd64 | linux/arm64 | 离线归档（amd64 / arm64 同名） |
| --- | --- | --- | --- | --- | --- | --- |
| `postgres` | `postgres` | `postgres:16.14` | docker.io/library/postgres | 是 | 是 | `postgres_16.tar` |
| `mysql` | `mysql8` | `mysql:8.0.39` | docker.io/library/mysql | 是 | 是 | `mysql_8.0.39.tar` |
| `minio` | `minio` | `pgsty/minio:RELEASE.2026-03-25T00-00-00Z` | docker.io/pgsty/minio | 是 | 是 | `pgsty_minio_RELEASE.2026-03-25T00-00-00Z.tar` |
| `valkey` | `valkey` | `valkey/valkey:8.1.8` | docker.io/valkey/valkey | 是 | 是 | `valkey_valkey_8.tar` |
| `es8` | `es8-ragflow` | `elasticsearch:8.11.3` | docker.io/library/elasticsearch | 是 | 是 | `elasticsearch_8.11.3.tar` |
| `es7` | `es7-cdc` | `docker.elastic.co/elasticsearch/elasticsearch:7.17.29` | docker.elastic.co（Elastic 官方仓库） | 是 | 是 | `docker.elastic.co_elasticsearch_elasticsearch_7.17.29.tar` |
| `flink` | `flink-jobmanager` / `flink-taskmanager` | `flink:1.20.3-scala_2.12-java17` | docker.io/library/flink | 是 | 是 | `flink_1.20.3-scala_2.12-java17.tar` |
| `onlyoffice` | `onlyoffice-document-server` | `onlyoffice/documentserver:9.4.0` | docker.io/onlyoffice/documentserver | 是 | 是 | `onlyoffice_documentserver_latest.tar`（历史命名，内容为固定 9.4.0） |
| `llama-cpp` | `llama-cpp` | `ghcr.io/ggml-org/llama.cpp:server-b10015` | ghcr.io | 是 | 是 | 不归档（可选 LLM，按 `-IncludeLLM`/`INCLUDE_LLM=1` 拉取） |
| `vllm` | `vllm` | `vllm/vllm-openai:v0.25.0` | docker.io/vllm/vllm-openai | 是 | 是 | 不归档（同上） |

### 1.2 镜像交付模型

- `imageDelivery=local-offline-archives-only`：发布物携带 `images/linux-amd64`、`images/linux-arm64`
  的 tar 归档，消费方离线 `docker load` 后使用；仓库本身只维护引用，不提交 tar（`/images/` 与 `*.tar`
  在 `.gitignore` 中）。
- 归档内 RepoTag **必须等于固定镜像引用**（R10）：干净环境 `docker load` 归档后 `compose up` 无需任何手动 retag。
- 归档文件命名：仓库路径中的 `/` 替换为 `_`、`:` 替换为 `_`；`onlyoffice_documentserver_latest.tar` 是唯一
  历史遗留命名，内容仍为 `onlyoffice/documentserver:9.4.0`。
- 归档清单：`scripts/common/image-archives.txt`，每行
  `<platform>|<runtime-image>|<archive-image>|<归档相对路径>`；R10 约束 `runtime-image == archive-image == image-list.txt 固定引用`。
  消费方：`load-images.ps1` / `scripts/ubuntu-{amd64,arm64}/load-images.sh`（离线装载）、`publish-release.ps1`（发布门槛）、
  `scripts/windows/regenerate-archives.ps1`（归档重建）。

## 2. 离线镜像归档生成规范

### 2.1 前置条件

- Docker 可用且能访问 registry（本机代理不可用时先恢复网络）；
- 磁盘空间：两平台 8 个镜像约 15GB 以上（onlyoffice 单平台约 3.5GB）；
- 归档与清单一致性由 `scripts/windows/regenerate-archives.ps1` 全自动处理。

### 2.2 标准流程（含 containerd 陷阱）

Docker Desktop 使用 containerd 镜像存储：直接 `docker pull --platform <p> <tag>` 会把 tag 合并为
多架构索引，随后 `docker save <tag>` 可能报
`unable to create manifests file: NotFound: content digest ... not found`（缺少另一架构的子清单）。
因此标准流程是 **按平台 manifest digest 拉取 + 重打 pinned tag + save**：

1. `docker manifest inspect <固定引用>` → 取 `os=linux, architecture=<arch>`（排除 `variant=v7`）的 digest；
2. `docker image rm <固定引用>`（清除可能存在的多架构索引 tag）；
3. `docker pull <仓库>@<digest>`（单平台内容入本地存储）；
4. `docker tag <仓库>@<digest> <固定引用>`（tag 指向单平台镜像）；
5. `docker save <固定引用> -o <归档路径>`。

### 2.3 自动化脚本

```powershell
.\scripts\windows\regenerate-archives.ps1        # 按 image-archives.txt 全量幂等重建
```

- 跳过已通过校验的归档（校验：tar 内 RepoTags == 清单标签、config 架构 == 目录平台）；
- 先 arm64 后 amd64，结束时本地镜像仓保留 amd64 镜像；
- 网络抖动自动重试（默认 8 次 × 10s），可用于代理不稳的现场。

### 2.4 归档校验标准

每个归档必须同时满足：文件存在且非空；`manifest.json` 的 `RepoTags` 含清单登记的固定引用；
`manifest.json` 的 `Config` 指向的 config 文件 `architecture` 与所在平台目录一致（amd64/arm64）。

## 3. 发布规范与检查点

### 3.1 版本与标签

- 分支：`main`；标签：`v<major>.<minor>.<patch>`（现有 `v0.0.1` 初始基线、`v0.1.0` R1-R9 需求批次）。
- 发布 = 干净提交 + 标签 + 推送 main 与标签 + 生成发布物。发布物不入 Git。

### 3.2 检查点 A：`check-release.ps1`（发布前配置一致性）

| 检查点 | 内容 | 失败行为 |
| --- | --- | --- |
| A1 Compose 配置 | 全 profile `docker compose config --quiet` | 抛错 |
| A2 固定标签 | 所有 Compose 镜像必须带显式 tag，拒绝 `latest`、`server`、仅主版本等浮动标签 | 抛错 |
| A3 镜像清单一致 | Compose 镜像集合 == `image-list.txt` | 列出差异并抛错 |
| A4 端口一致性 | `.env` 的 `POSTGRES_PORT`/`MYSQL_PORT`/`ES7_CDC_PORT`/`FLINK_REST_PORT` 与各 `project-env/*.host.env`（含 URL 内端口）一致（R5） | 列出差异并抛错 |

### 3.3 检查点 B：`publish-release.ps1`（发布门槛与组装）

按顺序执行，任一失败即拒绝发布：

| 检查点 | 内容 | 失败行为 |
| --- | --- | --- |
| B1 工作区干净 | `git status --porcelain` 为空；`release-info.json` 的 `sourceDirty` 恒为 false（R6） | 拒绝发布 |
| B2 配置检查 | 执行 `check-release.ps1`（A1-A4） | 拒绝发布 |
| B3 归档清单 | `scripts/common/image-archives.txt` 存在、每行 4 列（platform/runtime-image/archive-image/path） | 拒绝发布 |
| B4 归档标签固定 | runtime-image 与 archive-image 相等且必须属于 `image-list.txt` 固定引用（R10）；路径必须位于平台对应目录 | 拒绝发布 |
| B5 归档完整性 | 归档存在、非空、tar 内 RepoTags 与 archive-image 一致、镜像架构与 platform 一致；每个平台必须覆盖全部基础固定镜像 | 拒绝发布 |
| B6 组装 | 复制仓库内容到同级目录 `<父目录>\ieta-znz-deploy-release`（`-OutDir` 可覆盖） | 抛错 |

### 3.4 发布物布局与元数据

```
ieta-znz-deploy-release/
  release-info.json        # createdAt / sourceCommit / sourceDirty=false / imageDelivery / filesHashList
  release-files.sha256     # 覆盖除自身外全部文件的 SHA-256（相对路径）
  apps/ docs/ init/ project-env/ scripts/ images/linux-amd64/ images/linux-arm64/
  *.ps1 *.md *.txt *.yml .env
```

### 3.5 发布执行序列

```powershell
.\check-release.ps1                                        # 检查点 A
git add <变更文件>; git commit -m "..."                     # 必须提交，B1 要求干净
git tag -a v<version> -m "..."; git push origin main v<version>
.\scripts\windows\regenerate-archives.ps1                  # 归档重建（幂等）
.\publish-release.ps1                                      # 检查点 B + 生成发布物
```

## 4. 验证清单

### 4.1 静态验证（每次变更必做）

- PowerShell：`[System.Management.Automation.Language.Parser]::ParseFile` 无错误（`check-release.ps1`、`publish-release.ps1`、`scripts/windows/*.ps1`）；
- Bash：`bash -n` 通过（`scripts/ubuntu-amd64/*.sh`、`scripts/ubuntu-arm64/*.sh`）；
- Compose：`docker compose config --quiet` 通过；抽查插值结果（`FLINK_TASK_SLOTS=21`、`deploy.replicas: 3`、内存项注入、es7 认证 healthcheck 的 `$$` 转义保留）；
- 端口一致性负例：人为改错 `host.env` 端口后 `check-release.ps1` 拒绝并指明差异文件；
- 归档标签负例：`image-archives.txt` 写一个非固定标签后 `publish-release.ps1` 拒绝（B4）。

### 4.2 归档验证

`regenerate-archives.ps1` 每次保存后自校验（标签 + 架构）；发布时 B5 再校验一次。

### 4.3 发布物完整性验证

```powershell
Get-Content <发布物>\release-files.sha256 | % { ... }   # 逐项重算 SHA-256，必须 0 失配
```

- `release-info.json`：`sourceDirty=false`、`sourceCommit` 可用 `git show` 解析、`createdAt` 为发布日期；
- `images/linux-amd64` 与 `images/linux-arm64` 各 8 个归档。

### 4.4 运行级验收（发布前在目标平台执行，结果记录到 `BUILD_STATUS.md`）

- R1：改 `.env` 槽位/副本后 `up -d`，`/overview` 的 `slots-total`/`slots-available` 变化；默认 3 个 TaskManager；
- R2：改内存变量重启后 Flink Web/日志反映新内存；
- R3：按 README 清单放置 connector 后 Flink SQL 可加载；容器重建后按指引重传 Runner；
- R4：Flink 未就绪时 `status-app-base.sh` 返回非零，就绪时返回零并输出各端口状态；
- R7：`.env` 开 `ES7_SECURITY_ENABLED=true` 后带凭证可访问、无凭证被拒；
- R10：干净 Docker 环境仅用发布物归档 + compose 即可 `up -d`，无需手动 retag；
- R11：按 README 首启清单从干净环境到提交第一个 CDC 任务无缺失步骤。

## 5. 外部项目要求追踪（ieta-cdc-core）

要求单：`E:\CodexDev\ieta-cdc-core\docs\operations\ieta-znz-deploy-requirements.md`。
消费方只读依赖发布物；发布物不完整或不可用的问题按该要求单返回，由本仓库重新发布。

| 编号 | 优先级 | 要求 | 实现位置 | 状态 |
| --- | --- | --- | --- | --- |
| R1 | P0 | Flink 槽位参数化（≥21）+ 3 TM 副本默认 + 总槽位声明 | `.env`（`FLINK_TASK_SLOTS=21`/`FLINK_TM_REPLICAS=3`）、compose `deploy.replicas`、`apps/ieta-cdc-core.env`（`FLINK_TOTAL_SLOTS`） | 已实现 |
| R2 | P1 | JM/TM 内存参数化 | `.env`（`FLINK_JM_MEM`/`FLINK_TM_MEM`）、compose `FLINK_PROPERTIES` | 已实现 |
| R2-EXT | P0 | JM Metaspace 参数化（默认 ≥512m）与 checkpoint/restart 默认配置（键与 Green 安装器基线一致） | `.env`（`FLINK_JM_METASPACE=1g`/`FLINK_CK_INTERVAL=60s`）、compose `FLINK_PROPERTIES`、`flink_checkpoints` 命名卷 + 入口 chown、运维指南 §8 | 已实现 |
| R3 | P1 | flink_lib 生命周期 + connector 放置脚本 + Runner 一致性检查 | `docs/operations-guide.md` §9、`scripts/ubuntu-{amd64,arm64}/update-flink-lib.sh` | 已实现 |
| R4 | P1 | Flink healthcheck + 宿主机连通性检查 | compose `flink-jobmanager.healthcheck`、Linux `status-app-base.sh`（healthy + `HOST_PROBES`） | 已实现 |
| R5 | P1 | host.env 与 .env 端口一致性校验 | `check-release.ps1` A4 | 已实现 |
| R6 | P1 | sourceDirty 恒为 false | `publish-release.ps1` B1 | 已实现 |
| R7 | P2 | es7-cdc 可选认证 + TLS 边界声明 | `.env` `ES7_SECURITY_ENABLED`、compose、运维指南 §10 | 已实现 |
| R8 | P2 | 最小权限账号（可选） | `init/postgres/optional/01-ieta-cdc-minimal-privileges.sql`、运维指南 §11 | 已实现 |
| R9 | P2 | 版本兼容性验证证据 | `BUILD_STATUS.md`「CDC Core compatibility declarations」 | 已记录（运行级验证待目标平台执行） |
| R10 | P0 | 归档 RepoTag == Compose 固定引用 | 归档按固定引用 `docker save` 重建、`publish-release.ps1` B4/B5 | 已实现 |
| R11 | P1 | Flink 首启必做清单进入入口文档 | README「Flink 首次启动必做（CDC Core）」、运维指南 §9、`update-flink-lib.sh` usage | 已实现 |

## 6. 发布物重建 runbook（丢失恢复）

发布物目录被删除或损坏时，从 Git 干净提交完全重建：

1. 取得干净源码：`git clone` 或 `git checkout <tag>`（如 `v0.1.0`），确认 `git status` 干净；
2. 确认 Docker 可用、registry 可达（代理不可用先恢复网络）；
3. 重建离线归档：`powershell -ExecutionPolicy Bypass -File scripts\windows\regenerate-archives.ps1`（幂等；网络抖动自动重试）；
4. 发布前检查：`.\check-release.ps1`；
5. 生成发布物：`.\publish-release.ps1`（输出到仓库同级 `ieta-znz-deploy-release/`）；
6. 验证发布物：按第 4.3 节逐项复核 `release-files.sha256` 与 `release-info.json`（`sourceDirty=false`、`sourceCommit` 可解析）；
7. 交付消费方，运行级验收按第 4.4 节执行并把结果记录到 `BUILD_STATUS.md`。

已知现场问题与对策：

- `docker save` 报 `unable to create manifests file: NotFound: content digest ...`：containerd 多架构索引陷阱，改用第 2.2 节 digest 流程（脚本已内置）；
- registry 访问 `EOF`/超时：本机代理抖动，脚本自动重试；
- 中文输出乱码：按本机顶层约束，PowerShell 命令前置 UTF-8 编码设置（见全局 `~/.config/opencode/AGENTS.md`）。

## 7. 变更管理

新增 capability 或升级镜像版本时，除第 1.1 节表格涉及的清单（Compose、`image-list*.txt`、`service-catalog.env`、
`docs/service-catalog.md`、`PLATFORM_SUPPORT.md`、`BUILD_STATUS.md`）外，还必须：

1. 更新 `scripts/common/image-archives.txt`（新镜像两平台归档路径 + 固定引用）；
2. 用 `regenerate-archives.ps1` 生成归档并通过 B4/B5；
3. 按第 3.5 节执行发布序列并完成第 4 节验证。
