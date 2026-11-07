# kylin-uos-jdk-container

以国产 UOS / Kylin 系统为基础镜像制作的 JDK 运行基础镜像。

**同一份 Dockerfile 即可产出 amd64 与 arm64 两个架构的镜像**，架构差异由构建期内置变量
`TARGETARCH` 自动判别，不再维护 `-arm64` 独立目录。

---

## 目录结构

```
.
├── build.sh                 # 双架构构建入口（buildx + manifest 推送）
├── build-local.sh           # 本地单架构快速验证（--load，不推送）
├── jdk8/
│   ├── Dockerfile                        # OpenJDK 8
│   ├── Dockerfile-dragonwell-extended    # Alibaba Dragonwell 8 Extended
│   └── docker-entrypoint.sh
├── jdk17/
│   ├── Dockerfile                        # OpenJDK 17
│   ├── Dockerfile-dragonwell-standard    # Alibaba Dragonwell 17 Standard
│   └── docker-entrypoint.sh
├── jdk17-ffmpeg/
│   └── Dockerfile                        # OpenJDK 17 + FFmpeg
├── jdk21/
│   └── Dockerfile                        # Alibaba Dragonwell 21 Extended
└── jdk25-lts/
    ├── Dockerfile                        # Alibaba Dragonwell 25 Standard
    ├── Dockerfile-dragonwell-extended    # Alibaba Dragonwell 25 Extended
    ├── Dockerfile-adoptium               # Adoptium Temurin 25（UOS 基础镜像）
    └── Dockerfile-adoptium-kylinv11      # Adoptium Temurin 25（Kylin V11 基础镜像）
```

镜像内不再预置 `dumb-init`、`gosu`、`opentelemetry-javaagent.jar` 二进制，
三者均在构建期在线下载并做 sha256 校验。

---

## 构建

### 前置：启用 buildx 多架构 builder

```bash
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap
```

### 双架构构建并推送 manifest

```bash
# 构建全部变体（linux/amd64 + linux/arm64，合并为一个 manifest）
./build.sh

# 只构建 jdk17 目录下的全部变体（openjdk + dragonwell）
./build.sh jdk17

# 只构建 jdk17 的 OpenJDK 变体
./build.sh jdk17 openjdk

# 只构建 jdk25-lts 的 Temurin 变体
./build.sh jdk25-lts adoptium

# 构建所有 Dragonwell 变体
./build.sh "" dragonwell

# 指定镜像前缀与标签
IMAGE_PREFIX=registry.example.com/base/uos-jdk IMAGE_TAG=v1 ./build.sh jdk21
```

变体短名：`openjdk` / `dragonwell` / `ffmpeg` / `adoptium` / `kylin`

多架构构建产物无法 `--load` 到本地 docker，必须 `--push` 推到 registry，
再通过 manifest 让 `docker pull` 自动选择架构：

```bash
docker buildx imagetools inspect ghcr.io/blueapple168/uos-jdk:jdk17
docker pull --platform linux/arm64 ghcr.io/blueapple168/uos-jdk:jdk17
```

### 本地单架构验证

```bash
./build-local.sh jdk17
```

### 单架构手动构建（不经脚本）

```bash
docker buildx build --platform linux/arm64 -f jdk17/Dockerfile -t my/jdk17:arm64 --load jdk17
docker buildx build --platform linux/amd64 -f jdk17/Dockerfile -t my/jdk17:amd64 --load jdk17
```

---

## 构建参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `BASE_IMAGE_TAG` | `uos-server-20-1070a:latest` | 基础镜像标签，可整体切换 UOS 版本 |
| `BASE_IMAGE_REPO` | `ghcr.io/blueapple168` | 基础镜像仓库前缀，可指向私有/离线仓库 |
| `DUMB_INIT_VER` | `1.2.5` | dumb-init 版本（**不自动升级**，需手工改） |
| `GOSU_VER` | `1.20` | gosu 版本（**不自动升级**，需手工改） |
| `OTEL_AGENT_VER` | `2.33.1` | OpenTelemetry Java Agent 版本（**不自动升级**，需手工改） |
| `MIRROR_GITHUB` | 空 | GitHub 镜像代理前缀，内网构建时填写 |
| `DRAGONWELL_RAW` | 各文件内定义 | Dragonwell 版本，写法 `<版本号>+<build号>`（**自动跟踪**） |
| `JDKVER_RAW` | `25.0.5+8` | Temurin 版本，仅 adoptium 变体（**自动跟踪**） |

三者均从 GitHub 官方 release 下载并做 sha256 校验：

- dumb-init：`.../v{ver}/dumb-init_{ver}_x86_64` 与 `_aarch64`，校验文件 `sha256sums`
- gosu：`.../{ver}/gosu-amd64` 与 `gosu-arm64`，校验文件 `SHA256SUMS`
- javaagent：`.../v{ver}/opentelemetry-javaagent.jar`，校验文件 `checksums.txt`

内网无外网时，通过 `MIRROR_GITHUB` 指向可达的镜像代理：

```bash
MIRROR_GITHUB=https://ghproxy.example.com/https://github.com ./build.sh jdk17
```

---

## 自动化：GitHub Actions

工作流文件：`.github/workflows/docker-build-jdk-uos.yml`

### 触发方式

| 触发 | 行为 |
|---|---|
| push 到 master（改 `jdk*/Dockerfile*`、`jdk*/docker-entrypoint.sh`、`build.sh`） | 按变更文件精确匹配变体，构建并推送双架构 manifest |
| pull_request 到 master | 只跑 `detect` 做矩阵校验，不推镜像 |
| schedule（每日 UTC 02:00 / 北京 10:00） | 检查上游 JDK 新版本，有更新则升级并重建 |
| workflow_dispatch | 手动指定 `variant`（如 `jdk17`、`jdk25-adoptium`）或勾选 `check_upstream` |

### 版本自动跟踪

定时任务会检查以下上游的**最新稳定版**（排除 draft / prerelease）：

| 变体 | 上游仓库 | 跟踪的 ARG |
|---|---|---|
| `jdk8-dragonwell` | dragonwell-project/dragonwell8 (`extended`) | `DRAGONWELL_RAW` |
| `jdk17-dragonwell` | dragonwell-project/dragonwell17 (`standard`) | `DRAGONWELL_RAW` |
| `jdk21-dragonwell` | dragonwell-project/dragonwell21 (`standard`) | `DRAGONWELL_RAW` |
| `jdk25-dragonwell` | dragonwell-project/dragonwell25 (`standard`) | `DRAGONWELL_RAW` |
| `jdk25-dragonwell-extended` | dragonwell-project/dragonwell25 (`extended`) | `DRAGONWELL_RAW` |
| `jdk25-adoptium` / `jdk25-adoptium-kylin` | adoptium/temurin25-binaries | `JDKVER_RAW` |

要点：

- Dragonwell 的 `standard` 与 `extended` 是两条独立产品线，版本号不同，**按产品线分别跟踪**，不会互相覆盖。
- Temurin 只认 GA 版 tag（`jdk-25.0.6+9`），带 `-ea` 的抢先版一律排除，避免未 GA 构建流入生产镜像。
- 检测到新版本时：改写对应 ARG → 提交 commit 回 master → **只重建确实落后的变体**（非全量）。
- `dumb-init` / `gosu` / `otel-agent` **不参与**自动升级，需要时手工修改 ARG（这三个组件的校验文件格式随版本变动，自动升级风险高于收益）。

> 注：GitHub API 未认证请求限额 60 次/小时，workflow 会显式传入 `GITHUB_TOKEN`（限额 1000 次/小时）。
> 若所有跟踪源都查询失败，`detect` job 会直接失败而非静默通过——防止定任务长期"空转成功"却漏掉新版本。

---

## 运行时约定

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `JAVA_OPTS` | 见下 | JVM 参数，堆占位统一 `-XX:MaxRAMPercentage=75.0` |
| `APP_NAME` | `app` | 启动的 jar 文件名（不含 `.jar`） |
| `APP_USER` | `app` | 运行用户（uid/gid 1000） |
| `RUN_ARGS` | 空 | 传给应用的启动参数 |
| `OTEL_APP_NAME` | 空 | 非空时自动挂载 javaagent 并开启 OTLP 上报 |
| `JDK_CERT_URLS` | 空 | 逗号分隔的证书 URL，启动时导入 cacerts |

内存占位统一为容器 limit 的 **75%**，其余 25% 留给 Metaspace、线程栈、
DirectBuffer 与本地库，降低 OOMKilled 概率。如需调整，覆盖 `JAVA_OPTS` 即可。

JVM 参数分档：

- JDK 8 / Dragonwell 8 / Dragonwell 17：`-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`
- JDK 17 / JDK 17+FFmpeg：上述 + `-XX:+UnlockExperimentalVMOptions -XX:+UseZGC`
- JDK 21 / JDK 25 / Temurin 25：上述 + `-XX:+ZUncommit -XX:ZUncommitDelay=300 -XX:+HeapDumpOnOutOfMemoryError`

---

## 镜像清理

构建过程在主 RUN 层内完成清理，不留残留：

- `yum/microdnf clean all`，删除 `/var/cache/{yum,dnf,microdnf}`
- 删除 `/var/log/{yum,dnf}.log`、`/var/tmp/*`、`/tmp/*`
- 删除 JDK 自带的 `src.zip`（Dragonwell / Temurin 变体）
- 下载与校验用的临时目录 `/tmp/chk` 全部清除

---

## License

见 [LICENSE](LICENSE)。
