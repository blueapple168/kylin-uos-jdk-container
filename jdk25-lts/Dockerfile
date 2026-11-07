# syntax=docker/dockerfile:1.4
# UOS Server 20 + Alibaba Dragonwell 25 Standard —— 单 Dockerfile 产出 amd64/arm64 双架构

ARG BASE_IMAGE_TAG=uos-server-20-1070a:latest
ARG BASE_IMAGE_REPO=ghcr.io/blueapple168
FROM ${BASE_IMAGE_REPO}/${BASE_IMAGE_TAG}

# 重新声明基础镜像参数，供后续 LABEL 等指令展开（ARG 在 FROM 之后失效）
ARG BASE_IMAGE_TAG
ARG BASE_IMAGE_REPO

# buildx 自动注入的目标架构（amd64 / arm64）。必须声明才能引用，
# 否则 set -u 下引用未定义的 TARGETARCH 会报 unbound variable
ARG TARGETARCH

# 组件版本，均从 GitHub 官方 release 下载并做 sha256 校验；
# 内网可用 MIRROR_GITHUB 指向代理，如 --build-arg MIRROR_GITHUB=https://ghproxy.example.com/https://github.com
ARG DUMB_INIT_VER=1.2.5
ARG GOSU_VER=1.20
ARG OTEL_AGENT_VER=2.33.1
ARG MIRROR_GITHUB=""

ARG OS_VERSION=20-1070a

# DRAGONWELL_RAW 写法 <版本号>+<build号>（无 build 号则只写版本，如 8.30.29）。
# 下载链路由此推导：文件名把 + 换成 .，URL 路径把 + 转义为 %2B。
ARG DRAGONWELL_RAW="25.0.4.0.4+7"

LABEL org.opencontainers.image.authors="blueapple1120@qq.com" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.base.name="${BASE_IMAGE_REPO}/${BASE_IMAGE_TAG}" \
      org.opencontainers.image.description="Alibaba Dragonwell 25 Standard JDK on UOS (multi-arch: amd64/arm64)" \
      os="UOS" \
      os.version="${OS_VERSION}" \
      os.arch="amd64,arm64" \
      component="base-image"

ARG BIN_DIR=/usr/local/bin
ARG OTEL_HOME=/opt/otel/libs

RUN set -euxo pipefail; \
    # ---- 0. 架构判别 ----
    case "${TARGETARCH:-amd64}" in \
        amd64) DW_ARCH=x64;     DUMB_INIT_ASSET="dumb-init_${DUMB_INIT_VER}_x86_64";  GOSU_ASSET="gosu-amd64" ;; \
        arm64) DW_ARCH=aarch64; DUMB_INIT_ASSET="dumb-init_${DUMB_INIT_VER}_aarch64"; GOSU_ASSET="gosu-arm64" ;; \
        *) echo "ERROR: unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    GH="${MIRROR_GITHUB:-https://github.com}"; \
    DUMB_INIT_BASE="${GH}/Yelp/dumb-init/releases/download/v${DUMB_INIT_VER}"; \
    GOSU_BASE="${GH}/tianon/gosu/releases/download/${GOSU_VER}"; \
    OTEL_BASE="${GH}/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VER}"; \
    echo "==> TARGETARCH=${TARGETARCH}  DW_ARCH=${DW_ARCH}  os.version=${OS_VERSION}"; \
    \
    # ---- 1. 推导 Dragonwell 下载地址 ----
    FILE_VER=$(echo "$DRAGONWELL_RAW" | tr '+' '.'); \
    URL_PATH=$(echo "$DRAGONWELL_RAW" | sed 's/+/%2B/g'); \
    JDK_URL="https://dragonwell.oss-cn-shanghai.aliyuncs.com/${URL_PATH}/Alibaba_Dragonwell_Standard_${FILE_VER}_${DW_ARCH}_linux.tar.gz"; \
    \
    # ---- 2. 仓库配置 ----
    sed -i 's/\$StateMode/ufu/g' /etc/yum.repos.d/UnionTechOS.repo; \
    \
    # ---- 3. 安装软件包 ----
    yum makecache; \
    yum install -y --setopt=install_weak_deps=false --nogpgcheck --nodocs \
        tar \
        gzip \
        curl; \
    \
    # ---- 4. 下载并解压 Dragonwell JDK ----
    mkdir -p /usr/lib/jvm "${OTEL_HOME}" /app; \
    echo "Downloading: ${JDK_URL}"; \
    curl -Lf --retry 5 --retry-delay 2 --connect-timeout 15 "$JDK_URL" -o /tmp/jdk.tar.gz; \
    # 用 sed 而非 head: head 会提前关闭管道让 tar 收到 SIGPIPE(141)，
    # 在 set -o pipefail + set -e 下会直接终止构建
    JDK_DIR=$(tar -tzf /tmp/jdk.tar.gz | sed -n '1s|/.*$||p'); \
    tar -xzf /tmp/jdk.tar.gz -C /usr/lib/jvm/; \
    rm -f /tmp/jdk.tar.gz; \
    mv "/usr/lib/jvm/${JDK_DIR}" /usr/lib/jvm/java-25-dragonwell; \
    \
    # ---- 5. 设置默认 Java ----
    update-alternatives --install /usr/bin/java  java  /usr/lib/jvm/java-25-dragonwell/bin/java  1000; \
    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-25-dragonwell/bin/javac 1000; \
    update-alternatives --install /usr/bin/jar   jar   /usr/lib/jvm/java-25-dragonwell/bin/jar   1000; \
    update-alternatives --install /usr/bin/jps   jps   /usr/lib/jvm/java-25-dragonwell/bin/jps   1000; \
    \
    # ---- 6. 安装 dumb-init + gosu ----
    mkdir -p /tmp/chk "${BIN_DIR}"; \
    cd /; \
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 \
        "${DUMB_INIT_BASE}/sha256sums" -o /tmp/chk/dumb-init.sums; \
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 \
        "${DUMB_INIT_BASE}/${DUMB_INIT_ASSET}" -o "/tmp/chk/${DUMB_INIT_ASSET}"; \
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 \
        "${GOSU_BASE}/SHA256SUMS" -o /tmp/chk/gosu.sums; \
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 \
        "${GOSU_BASE}/${GOSU_ASSET}" -o "/tmp/chk/${GOSU_ASSET}"; \
    cd /tmp/chk; \
    grep " \*\?${DUMB_INIT_ASSET}\$" dumb-init.sums | sha256sum -c -; \
    grep " \*\?${GOSU_ASSET}\$" gosu.sums | sha256sum -c -; \
    install -m 0755 "/tmp/chk/${DUMB_INIT_ASSET}" "${BIN_DIR}/dumb-init"; \
    install -m 0755 "/tmp/chk/${GOSU_ASSET}" "${BIN_DIR}/gosu"; \
    cd /; \
    \
    # ---- 7. 下载 OpenTelemetry Java Agent 并校验 ----
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 \
        "${OTEL_BASE}/checksums.txt" -o /tmp/chk/otel.sums; \
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 \
        "${OTEL_BASE}/opentelemetry-javaagent.jar" -o "${OTEL_HOME}/opentelemetry-javaagent.jar"; \
    cd "${OTEL_HOME}"; \
    grep " \*\?opentelemetry-javaagent.jar\$" /tmp/chk/otel.sums > /tmp/chk/jar.sums; \
    # 必须先确认校验条目非空，否则空输入会让 sha256sum 静默通过
    test -s /tmp/chk/jar.sums; \
    sha256sum -c /tmp/chk/jar.sums; \
    chmod 0644 "${OTEL_HOME}/opentelemetry-javaagent.jar"; \
    cd /; \
    \
    # ---- 8. 清理构建垃圾 ----
    rm -rf /tmp/chk; \
    yum clean all; \
    rm -rf /var/cache/yum/* \
           /var/cache/dnf/* \
           /var/log/yum.log \
           /var/log/dnf.log \
           /var/log/dnf.librepo.log \
           /usr/lib/jvm/java-25-dragonwell/lib/src.zip \
           /usr/lib/jvm/java-25-dragonwell/src.zip \
           /var/tmp/* \
           /tmp/*; \
    \
    # ---- 9. 产物自检 ----
    /usr/lib/jvm/java-25-dragonwell/bin/java -version; \
    "${BIN_DIR}/dumb-init" --version; \
    "${BIN_DIR}/gosu" --version; \
    test -s "${OTEL_HOME}/opentelemetry-javaagent.jar"

COPY --chmod=755 docker-entrypoint.sh ${BIN_DIR}/docker-entrypoint.sh

# 堆占容器内存 75%，余 25% 留给 Metaspace / 线程栈 / DirectBuffer，降低 OOMKilled 概率
ENV JAVA_HOME=/usr/lib/jvm/java-25-dragonwell
ENV PATH=$JAVA_HOME/bin:$PATH \
    CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar \
    TZ=Asia/Shanghai \
    JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UseZGC \
               -XX:+ZUncommit \
               -XX:ZUncommitDelay=300 \
               -XX:+HeapDumpOnOutOfMemoryError" \
    SECURERANDOM="-Djava.security.egd=file:/dev/./urandom" \
    JAVA_FILENAME_CODING="-Dsun.jnu.encoding=UTF-8 \
                          -Dfile.encoding=UTF-8 \
                          -Duser.country=CN \
                          -Duser.language=zh" \
    OTEL_HOME=/opt/otel/libs \
    JDK_CERT_URLS="" \
    RUN_ARGS="" \
    APP_NAME="app" \
    APP_USER="app"

ARG BIN_DIR=/usr/local/bin
RUN set -euxo pipefail; \
    echo "${TZ}" > /etc/timezone; \
    groupadd -r "${APP_USER}" -g 1000; \
    useradd -r -u 1000 -g "${APP_USER}" -d "/${APP_USER}" -s /bin/bash "${APP_USER}"; \
    chown -R "${APP_USER}:${APP_USER}" "/${APP_USER}" /opt/otel; \
    chmod +x "${BIN_DIR}"/*; \
    echo '. ~/.bashrc' > "/${APP_USER}/.bash_profile"; \
    echo '. /etc/profile' > "/${APP_USER}/.bashrc"

WORKDIR /${APP_USER}

ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "/usr/local/bin/docker-entrypoint.sh"]

CMD ["/bin/sh", "-c", "java ${JAVA_OPTS} ${SECURERANDOM} ${JAVA_FILENAME_CODING} -jar ${APP_NAME}.jar ${RUN_ARGS}"]
