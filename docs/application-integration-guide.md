# 应用接入与发布指南

## 1. 适用范围

当业务应用需要 PostgreSQL、MySQL、Elasticsearch、MinIO、Valkey、OnlyOffice、Flink 或其他外部容器时，应优先接入 `ieta-znz-deploy`。

代码、文档、安装目录、发布说明、Docker Compose 项目名和共享网络统一使用 `ieta-znz-deploy`。

业务应用发布包只负责应用镜像、配置、业务迁移和应用启停。不得复制本项目已经维护的第三方服务定义或镜像。

## 2. 接入前的能力判断

1. 列出应用运行时真实需要的外部能力及兼容版本。
2. 查询 `docs/service-catalog.md` 和 `scripts/common/service-catalog.env`。
3. 已有兼容 capability 时直接复用。
4. 已有服务版本不兼容时，不得强行复用，也不得在应用包中私自增加第三方容器；应先在本项目新增独立、受控的 capability。
5. 仅开发期使用、尚未形成部署依赖的组件，不应提前登记为生产 capability。

Elasticsearch 7 和 Elasticsearch 8 是版本边界处理的现有示例。

## 3. 开发要求

### 3.1 登记应用能力

在 `apps/<app-id>.env` 增加声明：

```text
APP_ID=my-app
APP_NAME=My App
CAPABILITIES=postgres,minio,valkey
REQUIRED_SERVICES=postgres,minio,valkey
CONTAINER_NETWORK=ieta-znz-deploy
HOST_ENV_TEMPLATE=project-env/my-app.host.env
CONTAINER_ENV_TEMPLATE=project-env/my-app.env
HOST_PROBES=POSTGRES_PORT:tcp,MINIO_PORT:http:/
HOST_PORT_MAP=POSTGRES_PORT=POSTGRES_PORT,MINIO_PORT=MINIO_ENDPOINT
NOTES=说明用途、数据隔离方式和特殊依赖
```

要求：

- `CAPABILITIES` 只能使用能力目录中存在的 id；
- `REQUIRED_SERVICES` 必须与 Compose 的实际服务名一致；
- `HOST_PROBES`（可选，推荐）声明状态检查的宿主机端口探测：`<.env端口变量>:<tcp|http>[/路径]`，端口值从 `.env` 读取，不得硬编码；
- `HOST_PORT_MAP`（可选，宿主机运行应用时推荐）声明 `.env` 端口变量与宿主机模板键的对应关系，发布校验保证两边端口一致，避免修改 `.env` 端口后模板漂移；
- 没有外部依赖时保留清单并明确说明，不伪造 capability；
- 新增 capability 时同步更新 Compose、能力目录、服务目录、平台支持和构建状态。

### 3.2 提供两类连接模板

在 `project-env/` 中分别提供：

- `<app-id>.env`：应用运行在容器中时使用，连接地址必须使用共享服务名；
- `<app-id>.host.env`：应用运行在宿主机时使用，连接地址使用宿主机端口。

容器模板示例：

```text
POSTGRES_URL=jdbc:postgresql://postgres:5432/my_app
REDIS_HOST=valkey
MINIO_ENDPOINT=http://minio:9000
```

宿主机模板示例：

```text
POSTGRES_URL=jdbc:postgresql://127.0.0.1:15432/my_app
REDIS_HOST=127.0.0.1
MINIO_ENDPOINT=http://127.0.0.1:9000
```

模板中只能放示例值或变量占位符。生产密码、令牌、证书和私钥必须通过部署环境注入，不得提交真实凭据。

### 3.3 应用 Compose 只定义应用服务

应用 Compose 必须引用外部网络：

```yaml
services:
  my-app:
    image: my-app:1.0.0
    networks:
      - ieta-znz-deploy

networks:
  ieta-znz-deploy:
    external: true
    name: ieta-znz-deploy
```

禁止在应用 Compose 中再次定义 `postgres`、`mysql`、`elasticsearch`、`minio`、`valkey`、`onlyoffice/documentserver` 等基础服务。

### 3.4 数据和账号隔离

共享容器不等于共享业务数据：

- 数据库按应用创建独立 database/schema 和最小权限用户；
- MinIO 按应用划分 bucket/prefix 和凭据；
- Valkey 使用明确的 key prefix，必要时使用独立实例或受控 capability；
- Elasticsearch 使用独立 index 前缀、alias 和生命周期策略；
- 应用不得依赖基础容器的 root/admin 账号作为长期运行账号。

业务表结构、索引模板和数据迁移由应用自身版本化管理，不放入基础容器首次初始化脚本。

### 3.5 启停和就绪

- 应用启动脚本先调用对应平台的 `start-app-base` 入口，再启动应用自身服务；
- “容器已创建”不等于“服务已就绪”，应用必须对依赖服务执行带超时的就绪检查；
- 应用停止默认只停止自身服务；
- 共享基础服务只有在确认没有其他应用使用时才能定向停止；
- 删除 volume 必须是显式、可审计的数据销毁动作。

## 4. 打包要求

业务应用发布包应包含：

- 应用镜像或二进制；
- 应用 Compose、环境变量模板和启停脚本；
- 业务迁移、版本说明、回滚说明；
- 所依赖的 capability 清单；
- 兼容的 `ieta-znz-deploy` 最低版本或明确的基础能力版本要求；
- 安装前检查和启动后验证脚本。

业务应用发布包不得包含：

- 第三方镜像 tar、镜像导出文件或其他镜像二进制副本；
- 重复的第三方 Compose 服务；
- 基础环境共享数据卷；
- 真实生产凭据；
- 仅在开发机成立的固定绝对路径。

业务应用和 `ieta-znz-deploy` 必须保持为两个边界清晰、可独立升级的发布单元。安装时先通过本项目脚本加载发布包内的离线固定版本镜像，再启动业务应用所需 capability；安装过程不得访问远端镜像仓库。

## 5. 新增或升级基础能力的发布要求

当应用需要新增 capability 或升级第三方版本时，应先在本项目完成：

1. 更新 `docker-compose.ieta-znz-deploy.yml` 和 `scripts/common/service-catalog.env`。
2. 更新 `docs/service-catalog.md`，说明版本、用途、兼容边界和迁移影响。
3. 在 `image-list.txt` 和对应 profile 清单中登记固定版本引用，禁止使用 `latest`、仅主版本或其他浮动标签。
4. 为 Linux AMD64 和 Linux ARM64 准备本地镜像归档，验证归档内架构并更新 `BUILD_STATUS.md`。
5. 更新 `PLATFORM_SUPPORT.md` 的验证结论。
6. 验证 Compose 配置、健康检查、数据持久化、重复启停和应用连接。
7. 运行 `publish-release.ps1`，将可校验的完整离线交付物发布到 `E:\CodexDev\ieta-znz-deploy-release`。
8. 最后再在业务应用发布中声明依赖该版本。

## 6. 发布前检查清单

### 本项目

- Compose 全 profile 配置校验通过；
- 所有声明 capability 都能映射到真实服务；
- 应用清单中的 `REQUIRED_SERVICES` 均存在；
- Compose 和 `image-list.txt` 使用一致的固定版本镜像引用；
- Compose 中的每个镜像都具有 AMD64 和 ARM64 本地离线归档；
- 健康检查与实际认证方式一致；
- 文档、平台状态和构建清单一致；
- 没有向 Git 或其他远端项目库提交真实凭据、模型、镜像 tar 或其他镜像二进制副本。

### 业务应用

- 应用 Compose 没有重复第三方服务；
- 应用容器已加入 `ieta-znz-deploy`；
- 容器模板使用服务名，宿主机模板使用宿主机端口；
- 启动前检查基础能力，启动后验证真实连接；
- 停止和卸载不会默认停止共享服务或删除共享数据；
- 业务迁移支持升级和失败回滚；
- 发布说明明确基础环境的最低兼容版本。

## 7. 当前应用基线

| 应用 | 基础能力 | 状态 |
| --- | --- | --- |
| `ragflow` | `mysql,minio,valkey,es8` | 已登记 |
| `ieta-cdc-core` | `postgres,mysql,es7,flink` | 已登记 |
| `ieta-dyna-report` | `postgres,onlyoffice` | 已登记 |
| `ieta-dyna-snapshot` | 无外部容器 | 当前基线为 SQLite/local file storage |
| `ieta-mq-message` | 待确认 | 发布前必须补齐依赖清单 |
