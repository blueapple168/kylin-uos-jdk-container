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
├── .github/
│   ├── variants.txt                      # 变体注册表，构建与验证工作流共用
│   ├── scripts/
│   │   ├── verify-image.sh               # 容器内自检脚本（POSIX sh）
│   │   └── summarize.py                  # 验证结果汇总为 Markdown 报告
│   └── workflows/
│       ├── docker-build-jdk-uos.yml      # 构建并推送双架构 manifest
│       └── verify-images.yml             # 实际启动容器验证功能与版本
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
│   └── Dockerfile                        # Alibaba Dragonwell 21 Standard
└── jdk25-lts/
    ├── Dockerfile                        # Alibaba Dragonwell 25 Standard
    ├── Dockerfile-dragonwell-extended    # Alibaba Dragonwell 25 Extended
    ├── Dockerfile-adoptium               # Adoptium Temurin 25（UOS 基础镜像）
    └── Dockerfile-adoptium-kylinv11      # Adoptium Temurin 25（Kylin V11 基础镜像）
```

镜像内不再预置 `dumb-init`、`gosu`、`opentelemetry-javaagent.jar` 二进制，
三者均在构建期在线下载并做 sha256 校验。

---

## 镜像 tag 命名

格式：`{系统}-{系统版本}-{发行版}-{JDK版本}[-{特性}]`

每个变体**只产出一个 tag**。不推历史短名（`jdk8` 之类），也不推 `<tag>-<sha>`，
registry 上就是下面这 10 条，干净可枚举。

- Dragonwell / Temurin 的版本取自 Dockerfile 的 ARG（`DRAGONWELL_RAW` / `JDKVER_RAW`）
- OpenJDK 的版本由 UOS 仓库决定：构建前进基础镜像问 `yum list available`，
  装完再复核镜像里的 NEVRA，两者不符直接失败，**tag 承诺什么版本，镜像里就是什么版本**
- Docker tag 不允许 `+`，一律替换为 `-`（如 `25.0.5+8` → `25.0.5-8`）
- `-{特性}` 仅用于区分同系统同 JDK 的功能变体（如 `-ffmpeg`）
- 变体清单集中维护在 `.github/variants.txt`，构建与验证两个工作流共用

构建时关闭了 buildx 的 provenance 与 SBOM，否则每个 tag 会额外挂两个
`unknown/unknown` 的 attestation manifest，在 registry 页面上显示成一堆 `sha256:xxx` 条目。

<!-- VERSIONS:BEGIN 本块由构建工作流自动重写，不要手工编辑 -->
| 镜像 tag | 镜像内 `java -version` |
|---|---|
| `kylin-v11-2503-temurin-25.0.5-8` | `25.0.5` |
| `uos-20-1070a-dragonwell-17.0.20.0.21-8-standard` | `17.0.20` |
| `uos-20-1070a-dragonwell-21.0.12.0.12-8-standard` | `21.0.12.0.12` |
| `uos-20-1070a-dragonwell-25.0.4.0.4-7-extended` | `25.0.4.0.4` |
| `uos-20-1070a-dragonwell-25.0.4.0.4-7-standard` | `25.0.4.0.4` |
| `uos-20-1070a-dragonwell-8.30.29-extended` | `1.8.0_502` |
| `uos-20-1070a-openjdk-1.8.0.422.b05-0.up2.uelc20.01` | `1.8.0_422` |
| `uos-20-1070a-openjdk-17.0.9.0.9-2.0.2.uelc20.01` | `17.0.9` |
| `uos-20-1070a-openjdk-17.0.9.0.9-2.0.2.uelc20.01-ffmpeg` | `17.0.9` |
| `uos-20-1070a-temurin-25.0.5-8` | `25.0.5` |
<!-- VERSIONS:END -->

> 这张表由构建工作流在补打完规范 tag 后自动重写，值取自镜像里实际装上的 JDK。
> OpenJDK 两行带 `.uelc20.01` 这类发行后缀，是 UOS 仓库的真实 NEVRA；
> 仓库升级 JDK 后重建，tag 与这张表都会跟着变，不需要手工改。
> 功能层面的验证结果（编译运行、MaxRAMPercentage、entrypoint 链路等）见
> Actions 里 `镜像功能与版本验证` 的 job summary。

每次构建只推这一个 tag。旧的 `jdk8`、`jdk17-dragonwell` 等短名已下线，
需要的话按上表的完整 tag 引用。

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

OpenJDK 变体（`jdk8` / `jdk17` / `jdk17-ffmpeg`）的 JDK 版本**不在 Dockerfile 里写死**，
直接 `yum install java-*-openjdk-devel` 装 UOS 仓库当前版本。构建前会先进基础镜像
`yum list available` 查出当前版本用来拼 tag，装完再用 `rpm -q --qf '%{VERSION}-%{RELEASE}'`
复核镜像里的 NEVRA，两者不符直接失败——这样 tag 永远等于镜像里真实存在的版本，
仓库升级 JDK 后下次构建 tag 自动跟着变，不需要改任何文件。

Dragonwell / Temurin 是自己下载的，版本由 ARG 决定，构建前就能算出 tag。

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
| push 到 main（改 `jdk*/Dockerfile*`、`jdk*/docker-entrypoint.sh`、`build.sh`） | 按变更文件精确匹配变体，构建并推送双架构 manifest |
| pull_request 到 main | 只跑 `detect` 做矩阵校验，不推镜像 |
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
- 检测到新版本时：改写对应 ARG → 提交 commit 回 main → **只重建确实落后的变体**（非全量）。
- `dumb-init` / `gosu` / `otel-agent` **不参与**自动升级，需要时手工修改 ARG（这三个组件的校验文件格式随版本变动，自动升级风险高于收益）。

> 注：GitHub API 未认证请求限额 60 次/小时，workflow 会显式传入 `GITHUB_TOKEN`（限额 1000 次/小时）。
> 若所有跟踪源都查询失败，`detect` job 会直接失败而非静默通过——防止定任务长期"空转成功"却漏掉新版本。

---

## 自动化：镜像功能与版本验证

工作流文件：`.github/workflows/verify-images.yml`

构建成功不代表镜像能用——包名写错、JDK 版本漂移、entrypoint 链路断掉都可能在构建
"成功"的情况下发生。这个工作流把每个变体、每个架构**实际启动起来**逐项检查。

### 触发方式

| 触发 | 行为 |
|---|---|
| `workflow_run`（构建工作流完成后） | 自动全量验证 10 变体 × 2 架构 |
| `workflow_dispatch` | 手动跑，`variant` 可填完整 tag 只验证一个，`platforms` 可只选单架构 |
| schedule（每日 UTC 04:00 / 北京 12:00） | 巡检，防止镜像被覆盖或上游漂移 |

### 检查项

| 类别 | 项目 |
|---|---|
| 系统 | `/etc/os-release` 的 ID 与 PRETTY_NAME、`uname -m` 架构 |
| JDK | `java -version` / `javac -version` 主版本、`java.vendor` 发行商、`JAVA_HOME` 与 `java.home` 一致性 |
| 功能 | 现场写 `Hello.java` → `javac` 编译 → `java` 运行，输出校验；JDK 9+ 的模块数 |
| JVM 参数 | 带 `JAVA_OPTS` 时 `MaxRAMPercentage` 实际为 75.0 |
| 运行时组件 | `dumb-init --version`、`gosu --version`、`app` 用户 uid=1000、OTel Agent jar |
| 链路 | 默认 entrypoint 跑 `id`，输出 `uid=1000(app)` 说明 dumb-init → entrypoint → gosu 全通 |
| 环境 | 时区 `Asia/Shanghai`、中文 locale |
| 特性 | `ffmpeg` 变体额外检查 `ffmpeg -version` |

另有一个 `tag-check` job，用 registry API 校验 registry 上只有这 10 个 tag（多一个都报错），
且每个 tag 的 manifest 只含 `linux/amd64` + `linux/arm64`，没有 attestation 残留。

> 镜像里不写 JDK 版本的 label。版本只作为 tag 的一部分用来区分镜像，
> 需要看实际版本时以容器内 `java -version` 或 tag 为准。

检查脚本在 `.github/scripts/verify-image.sh`，只用 POSIX sh + coreutils
（Kylin minimal 没有 bash，写 bash 专有语法会直接跑不起来）。

结果汇总在 job summary 的 Markdown 报告里，同时上传 `verify-report` artifact；
任何检查项 FAIL 会让工作流整体失败。

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
