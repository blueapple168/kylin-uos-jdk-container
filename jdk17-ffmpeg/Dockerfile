# syntax=docker/dockerfile:1.4
# UOS Server 20 + OpenJDK 17 + FFmpeg —— 单 Dockerfile 产出 amd64/arm64 双架构

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

LABEL org.opencontainers.image.authors="blueapple1120@qq.com" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.base.name="${BASE_IMAGE_REPO}/${BASE_IMAGE_TAG}" \
      org.opencontainers.image.description="UOS ${OS_VERSION} JDK 17 (OpenJDK) with FFmpeg Optimized Base Image (multi-arch: amd64/arm64)" \
      os="UOS" \
      os.version="${OS_VERSION}" \
      os.arch="amd64,arm64" \
      component="base-image"

ARG BIN_DIR=/usr/local/bin
ARG OTEL_HOME=/opt/otel/libs

RUN set -euxo pipefail; \
    # ---- 0. 架构判别 ----
    case "${TARGETARCH:-amd64}" in \
        amd64) DUMB_INIT_ASSET="dumb-init_${DUMB_INIT_VER}_x86_64";  GOSU_ASSET="gosu-amd64" ;; \
        arm64) DUMB_INIT_ASSET="dumb-init_${DUMB_INIT_VER}_aarch64"; GOSU_ASSET="gosu-arm64" ;; \
        *) echo "ERROR: unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    GH="${MIRROR_GITHUB:-https://github.com}"; \
    DUMB_INIT_BASE="${GH}/Yelp/dumb-init/releases/download/v${DUMB_INIT_VER}"; \
    GOSU_BASE="${GH}/tianon/gosu/releases/download/${GOSU_VER}"; \
    OTEL_BASE="${GH}/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VER}"; \
    echo "==> TARGETARCH=${TARGETARCH}  os.version=${OS_VERSION}"; \
    \
    # ---- 1. 仓库配置 ----
    sed -i 's/\$StateMode/ufu/g' /etc/yum.repos.d/UnionTechOS.repo; \
    \
    # ---- 2. 安装软件包 ----
    # 不锁 JDK 版本：版本由 UOS 仓库决定，构建后从镜像里读出实际版本再补打规范 tag
    yum makecache; \
    yum install -y --setopt=install_weak_deps=false --nogpgcheck --nodocs \
        java-17-openjdk-devel \
        copy-jdk-configs \
        yasm \
        ffmpeg \
        tar \
        curl; \
    \
    # ---- 3. 安装 dumb-init + gosu ----
    mkdir -p /tmp/chk "${BIN_DIR}" "${OTEL_HOME}" /app; \
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
    # ---- 4. 下载 OpenTelemetry Java Agent 并校验 ----
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
    # ---- 5. 清理构建垃圾 ----
    rm -rf /tmp/chk; \
    yum clean all; \
    rm -rf /var/cache/yum/* \
           /var/cache/dnf/* \
           /var/log/yum.log \
           /var/log/dnf.log \
           /var/log/dnf.librepo.log \
           /var/tmp/* \
           /tmp/*; \
    \
    # ---- 6. 产物自检 ----
    "${BIN_DIR}/dumb-init" --version; \
    "${BIN_DIR}/gosu" --version; \
    test -s "${OTEL_HOME}/opentelemetry-javaagent.jar"; \
    /usr/lib/jvm/java-17-openjdk/bin/java -version; \
    ffmpeg -version | sed -n '1p'

COPY --chmod=755 docker-entrypoint.sh ${BIN_DIR}/docker-entrypoint.sh

# 堆占容器内存 75%，余 25% 留给 Metaspace / 线程栈 / DirectBuffer，降低 OOMKilled 概率
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH=$JAVA_HOME/bin:$PATH \
    TZ=Asia/Shanghai \
    JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UnlockExperimentalVMOptions \
               -XX:+UseZGC" \
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
