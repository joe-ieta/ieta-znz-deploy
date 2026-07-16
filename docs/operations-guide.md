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
| Flink REST | `http://flink-jobmanager:8081` |
| OnlyOffice | `http://onlyoffice-document-server` |

宿主机运行应用时使用 `project-env/*.host.env`。

## 8. 常见问题

端口冲突：修改 `.env` 中的宿主机端口，不修改容器内端口或服务名。

镜像缺失：运行对应平台的 `pull-images` 脚本。脚本只执行 `docker pull --platform`，不生成 tar。

镜像版本调整：必须同时更新 Compose、`image-list.txt`、对应 profile 清单、`docs/service-catalog.md`、`BUILD_STATUS.md` 和 `PLATFORM_SUPPORT.md`。

服务未启动：

```powershell
.\status-app-base.ps1 -App ieta-cdc-core
docker compose --project-name ieta-znz-deploy -f docker-compose.ieta-znz-deploy.yml ps
```

数据异常：不要直接删除 volume。先完成备份，再决定是否执行 `-RemoveVolumes`。
