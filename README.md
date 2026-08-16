# ieta-znz-deploy

`ieta-znz-deploy` 是 IETA 产品族共享的第三方基础容器部署工程。它集中维护 PostgreSQL、MySQL、Elasticsearch、MinIO、Valkey、OnlyOffice、Flink、llama.cpp、vLLM 等公共基础能力，为多个业务应用提供稳定、可复用的容器运行底座。

本项目不是业务应用发布包，不包含业务应用镜像、业务数据库迁移或业务生命周期管理。

项目统一使用：

- Docker Compose 项目名：`ieta-znz-deploy`
- 共享 Docker 网络：`ieta-znz-deploy`
- Compose 文件：`docker-compose.ieta-znz-deploy.yml`

## 项目负责什么

- 选择并固定第三方容器镜像版本；
- 维护 Windows Docker Desktop、Ubuntu AMD64、Ubuntu ARM64 的镜像拉取和运维脚本；
- 提供共享网络、稳定服务名、端口、数据卷和健康检查；
- 通过 `apps/<app-id>.env` 登记业务应用所需基础能力；
- 提供容器运行和宿主机运行的连接配置模板；
- 检查 Compose 配置与镜像清单的一致性。

业务应用发布包只负责自身应用镜像、业务配置、业务迁移和应用启停，不得重复定义或发布本项目已经维护的第三方容器。

## 镜像交付方式

仓库只保存固定版本的镜像引用，不保存容器镜像 tar。安装人员通过脚本把所需镜像下载到本机 Docker：

```powershell
.\pull-images.ps1 -Platform linux/amd64
.\pull-images.ps1 -Platform linux/amd64 -IncludeLLM
```

Ubuntu：

```bash
bash scripts/ubuntu-amd64/pull-images.sh
INCLUDE_LLM=1 bash scripts/ubuntu-amd64/pull-images.sh

bash scripts/ubuntu-arm64/pull-images.sh
INCLUDE_LLM=1 bash scripts/ubuntu-arm64/pull-images.sh
```

固定版本的总清单位于 `image-list.txt`，按应用/profile 的子清单由拉取脚本使用。版本调整必须先更新 Compose、所有相关清单、服务目录和平台说明，并通过 `check-release.ps1`。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| `docs/positioning.md` | 项目定位、职责边界和稳定契约。 |
| `docs/application-integration-guide.md` | 新应用接入、开发、打包和发布要求。 |
| `docs/operations-guide.md` | 镜像下载、启动、停止、状态和故障定位。 |
| `docs/service-catalog.md` | 能力、Compose 服务、镜像版本和共享契约。 |
| `docs/open-items.md` | 当前已知问题、优化项和验收目标。 |
| `PLATFORM_SUPPORT.md` | 各目标平台和镜像引用支持情况。 |
| `BUILD_STATUS.md` | 固定镜像引用和当前验证状态。 |

## 目录结构

```text
ieta-znz-deploy/
  apps/                         # 应用到基础能力的声明清单
  docs/                         # 定位、接入、运维和待办文档
  init/                         # 基础数据库首次初始化脚本（optional/ 为可选脚本，不自动执行）
  models/                       # 可选本地模型文件，不纳入 Git
  project-env/                  # 应用连接基础环境的环境变量模板
  scripts/common/               # 能力到服务的公共清单、离线镜像归档清单
  scripts/windows/              # Windows 运维脚本
  scripts/ubuntu-amd64/         # Ubuntu AMD64 运维脚本
  scripts/ubuntu-arm64/         # Ubuntu ARM64 运维脚本
  image-list*.txt               # 固定版本镜像引用
  docker-compose.ieta-znz-deploy.yml
  .env
  check-release.ps1             # 发布前配置一致性检查
  publish-release.ps1           # 发布物组装（拒绝脏工作区，生成 release-info.json / release-files.sha256）
```

## 快速使用

Windows：

```powershell
cd E:\CodexDev\ieta-znz-deploy
.\pull-images.ps1 -Platform linux/amd64 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\start-app-base.ps1 -App ieta-cdc-core -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\status-app-base.ps1 -App ieta-cdc-core -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
```

Ubuntu AMD64：

```bash
cd /opt/ieta-znz-deploy
bash scripts/ubuntu-amd64/pull-images.sh
bash scripts/ubuntu-amd64/start-app-base.sh ieta-cdc-core
bash scripts/ubuntu-amd64/status-app-base.sh ieta-cdc-core
```

Ubuntu ARM64：

```bash
cd /opt/ieta-znz-deploy
bash scripts/ubuntu-arm64/pull-images.sh
bash scripts/ubuntu-arm64/start-app-base.sh ieta-cdc-core
bash scripts/ubuntu-arm64/status-app-base.sh ieta-cdc-core
```

也可以按能力启动：

```powershell
.\start-base-env.ps1 -Profiles postgres,mysql,es7,flink
.\start-base-env.ps1 -Profiles postgres,onlyoffice
.\start-base-env.ps1 -Profiles mysql,minio,valkey,es8
```

停止整个基础环境默认保留数据：

```powershell
.\stop-base-env.ps1
```

只有明确需要销毁共享数据时才可执行：

```powershell
.\stop-base-env.ps1 -RemoveVolumes
```

## 应用接入原则

当新应用需要外部数据库、缓存、对象存储、搜索、文档服务、流处理或模型服务时，必须遵守：

1. 先确认 `docs/service-catalog.md` 是否已有兼容能力，不在应用 Compose 中复制第三方服务。
2. 在 `apps/<app-id>.env` 声明 capability 和实际依赖服务。
3. 为容器运行和宿主机运行分别提供连接模板。
4. 应用 Compose 只包含应用服务，并加入外部网络 `ieta-znz-deploy`。
5. 应用启动时先确保所需基础能力可用；应用停止时默认只停止自身服务。
6. 版本冲突必须在本项目中新增受控 capability。
7. 发布前验证 Compose、固定镜像引用、配置示例和目标平台启动结果。

完整要求见 `docs/application-integration-guide.md`。

## 当前应用基线

| App | Capabilities |
| --- | --- |
| `ragflow` | `mysql,minio,valkey,es8` |
| `ieta-cdc-core` | `postgres,mysql,es7,flink` |
| `ieta-dyna-report` | `postgres,onlyoffice` |
| `ieta-dyna-snapshot` | 当前无共享外部容器 |
| `ieta-mq-message` | 待完成依赖确认 |

## 网络契约

业务应用容器必须加入共享外部网络：

```yaml
networks:
  ieta-znz-deploy:
    external: true
    name: ieta-znz-deploy
```

容器间使用稳定服务名访问基础能力，例如 `postgres:5432`、`mysql8:3306`、`minio:9000`、`valkey:6379`。宿主机端口只用于开发和运维，不是容器间契约。

## 发布

```powershell
.\check-release.ps1          # Compose、固定镜像、镜像清单、端口一致性检查
.\publish-release.ps1        # 干净工作区 + 离线归档校验通过后在仓库同级目录生成 ieta-znz-deploy-release/
```

发布物生成在仓库同级的 `ieta-znz-deploy-release/`（如 `E:\CodexDev\ieta-znz-deploy-release`），含 `release-info.json`（`sourceDirty=false`、`sourceCommit` 可解析、`imageDelivery=local-offline-archives-only`）与覆盖全部文件的 `release-files.sha256`。离线镜像归档全部位于本项目 `images/linux-amd64`、`images/linux-arm64`，发布时按 `scripts/common/image-archives.txt` 校验归档存在且 tar 内 RepoTags 与清单登记一致。Flink 槽位/副本/内存、ES7 可选认证等运行参数与运维细节见 `docs/operations-guide.md`。
