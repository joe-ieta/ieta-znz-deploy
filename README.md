# ieta-znz-deploy

`ieta-znz-deploy` 用于维护和发布 IETA 多工程、多应用共享的 Docker 基础容器包。它集中维护 PostgreSQL、MySQL、Elasticsearch、MinIO、Valkey、OnlyOffice、Flink 等公共基础能力，为多个业务应用提供稳定、可复用的离线容器运行底座。

各业务工程的基础能力声明以及对应的启动、停止、状态命令和说明统一在本项目中维护。本项目不包含业务应用镜像、业务数据库迁移或业务进程生命周期管理。

项目统一使用：

- Docker Compose 项目名：`ieta-znz-deploy`
- 共享 Docker 网络：`ieta-znz-deploy`
- Compose 文件：`docker-compose.ieta-znz-deploy.yml`

## 项目负责什么

- 选择并固定第三方容器镜像版本；
- 维护 Windows AMD64（WSL）、Linux AMD64、Linux ARM64 的离线镜像加载和运维脚本；
- 提供共享网络、稳定服务名、端口、数据卷和健康检查；
- 通过 `apps/<app-id>.env` 登记业务应用所需基础能力；
- 提供容器运行和宿主机运行的连接配置模板；
- 检查 Compose 配置与镜像清单的一致性。

业务应用发布包只负责自身应用镜像、业务配置、业务迁移和应用启停，不得重复定义或发布本项目已经维护的第三方容器。

## 离线交付与发布

所有基础镜像以 tar 归档保存在当前工程的 `images/` 目录。标准运行流程只从本地执行 `docker load`，不从远端仓库拉取镜像；`images/` 不纳入 Git，也不得推送到任何远端项目库。

Windows AMD64：

```powershell
.\load-images.ps1
```

Linux：

```bash
bash scripts/ubuntu-amd64/load-images.sh
bash scripts/ubuntu-arm64/load-images.sh
```

Windows 仅支持 AMD64，并通过 WSL 运行 Linux 容器；不支持 Windows ARM。LLM 服务当前未纳入基础包，只有在两个架构的离线镜像准备完整后才能重新接入。

正式运行环境发布到 `E:\CodexDev\ieta-znz-deploy-release`：

```powershell
.\publish-release.ps1
```

发布脚本会先执行配置和离线归档校验，再复制完整运行包并生成 `release-info.json` 与 `release-files.sha256`。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| `docs/positioning.md` | 项目定位、职责边界和稳定契约。 |
| `docs/application-integration-guide.md` | 新应用接入、开发、打包和发布要求。 |
| `docs/operations-guide.md` | 离线镜像加载、启动、停止、状态和故障定位。 |
| `docs/service-catalog.md` | 能力、Compose 服务、镜像版本和共享契约。 |
| `docs/open-items.md` | 当前已知问题、优化项和验收目标。 |
| `PLATFORM_SUPPORT.md` | 各目标平台和镜像引用支持情况。 |
| `BUILD_STATUS.md` | 固定镜像引用和当前验证状态。 |

## 目录结构

```text
ieta-znz-deploy/
  apps/                         # 应用到基础能力的声明清单
  docs/                         # 定位、接入、运维和待办文档
  init/                         # 基础数据库首次初始化脚本
  models/                       # 可选本地模型文件，不纳入 Git
  project-env/                  # 应用连接基础环境的环境变量模板
  scripts/common/               # 能力到服务的公共清单
  scripts/windows/              # Windows 运维脚本
  scripts/ubuntu-amd64/         # Ubuntu AMD64 运维脚本
  scripts/ubuntu-arm64/         # Ubuntu ARM64 运维脚本
  images/                       # 本地离线镜像归档，不纳入 Git
  image-list*.txt               # 固定版本镜像引用
  docker-compose.ieta-znz-deploy.yml
  .env
```

## 快速使用

Windows AMD64（WSL）：

```powershell
cd E:\CodexDev\ieta-znz-deploy-release
.\load-images.ps1 -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\start-app-base.ps1 -App ieta-cdc-core -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
.\status-app-base.ps1 -App ieta-cdc-core -DockerExe 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
```

Ubuntu AMD64：

```bash
cd /opt/ieta-znz-deploy
bash scripts/ubuntu-amd64/load-images.sh
bash scripts/ubuntu-amd64/start-app-base.sh ieta-cdc-core
bash scripts/ubuntu-amd64/status-app-base.sh ieta-cdc-core
```

Ubuntu ARM64：

```bash
cd /opt/ieta-znz-deploy
bash scripts/ubuntu-arm64/load-images.sh
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
