# 项目定位与发布要求

## 核心定位

`ieta-znz-deploy` 用于维护和发布一个多工程、多应用共享的 Docker 基础容器运行环境。

本项目统一管理 PostgreSQL、MySQL、MinIO、Valkey、Elasticsearch、Flink、OnlyOffice 等第三方基础服务，包括固定镜像版本、离线镜像归档、Compose 定义、共享网络、持久化数据卷、健康检查以及跨平台运维入口。

业务工程只维护自身应用，不重复携带或定义本项目已提供的第三方容器。

## 项目职责

- 发布可供多个业务工程共同使用的基础容器包。
- 在 `apps/<app-id>.env` 中维护各应用依赖的基础能力和实际服务。
- 在本项目中维护按应用启动、停止、状态检查命令及相关说明。
- 维护 Windows AMD64、Linux AMD64 和 Linux ARM64 的离线加载与运维脚本。
- 统一维护 Compose 项目名、共享网络、服务名、端口、数据卷和连接模板。
- 校验 Compose、应用清单、固定镜像引用、离线归档及目标架构的一致性。

## 应用启停边界

每个业务应用通过自己的应用标识调用本项目入口：

```powershell
.\start-app-base.ps1 -App ieta-cdc-core
.\status-app-base.ps1 -App ieta-cdc-core
.\stop-app-base.ps1 -App ieta-cdc-core -Force
```

Linux 使用对应架构下的 `start-app-base.sh`、`status-app-base.sh` 和 `stop-app-base.sh`。

应用启动命令只启动其声明的基础能力。由于基础服务可能被多个应用共享，按应用停止默认拒绝执行，必须在确认没有其他应用使用后显式强制停止。应用自身的业务进程、业务镜像、迁移和回滚仍由各业务工程负责。

## 离线镜像要求

- 所有基础运行镜像必须作为 tar 归档保存在当前工程的 `images/` 目录。
- `images/linux-amd64/` 服务于 Windows AMD64（WSL）和 Linux AMD64。
- `images/linux-arm64/` 服务于 Linux ARM64。
- Windows 仅支持 AMD64，并且只通过 WSL 运行 Linux 容器；不支持 Windows ARM。
- 标准安装和启动流程只允许执行 `docker load` 和本地 `docker tag`，不得执行远端 `docker pull`。
- 离线镜像不得提交或推送到 Git、GitHub 或其他远端项目库。
- `scripts/common/image-archives.txt` 必须记录运行标签、tar 内标签和归档路径。

LLM 服务当前没有两个架构的离线镜像，因此不出现在 Compose、镜像总清单或本次发布包中。

## 发布要求

正式发布目录固定为：

```text
E:\CodexDev\ieta-znz-deploy-release
```

发布时必须：

1. 通过 `check-release.ps1` 完成 Compose、固定标签、应用服务映射、归档内容和架构校验。
2. 将脚本、Compose、应用清单、连接模板、初始化文件、文档以及两个架构的离线镜像完整复制到发布目录。
3. 不复制 `.git`、`.agents`、日志和其他开发元数据。
4. 生成 `release-info.json`，记录发布时间、源提交和支持平台；发布源必须是干净工作区，`sourceDirty` 恒为 `false`，`sourceCommit` 指向可解析的干净提交。
5. 生成 `release-files.sha256`，用于交付后的完整性校验。
6. 发布目录已存在时停止发布，避免覆盖正在使用的运行环境。

标准发布命令：

```powershell
.\publish-release.ps1
```

## 稳定契约

| 契约 | 当前值 |
| --- | --- |
| Compose 项目名 | `ieta-znz-deploy` |
| 共享网络 | `ieta-znz-deploy` |
| Compose 文件 | `docker-compose.ieta-znz-deploy.yml` |
| 应用能力清单 | `apps/<app-id>.env` |
| 能力服务映射 | `scripts/common/service-catalog.env` |
| 离线镜像映射 | `scripts/common/image-archives.txt` |
| 正式发布目录 | `E:\CodexDev\ieta-znz-deploy-release` |

新增或升级基础能力必须先在本项目中登记固定版本、准备两个 Linux 架构的离线归档、完成验证并重新发布，再由业务工程声明依赖。
