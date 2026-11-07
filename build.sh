#!/usr/bin/env bash
# 单 Dockerfile 双架构构建脚本
#
# 用法：
#   ./build.sh                       # 构建全部变体（amd64 + arm64，推送 manifest）
#   ./build.sh jdk17                 # 只构建 jdk17 变体
#   ./build.sh jdk17 openjdk         # 只构建 jdk17 的 openjdk 变体
#   ./build.sh --load jdk17          # 加载到本地 docker（单架构，--load 不支持多架构）
#   ./build.sh --no-push jdk17       # 只构建不推送
#
# 环境变量：
#   IMAGE_PREFIX     镜像前缀，默认 ghcr.io/blueapple168/uos-jdk
#   IMAGE_TAG        标签，默认 latest（非 latest 时额外打一个 <变体>-<tag>）
#   PLATFORMS        目标架构，默认 linux/amd64,linux/arm64
#   PUSH             1 推送（默认）0 不推送
#   BASE_IMAGE_TAG / DUMB_INIT_VER / GOSU_VER / OTEL_AGENT_VER / MIRROR_GITHUB  透传为 build-arg
#
# 前置：多架构构建需先创建 builder，且必须推送 registry（本地 --load 只能单架构）
#   docker buildx create --name multiarch --driver docker-container --use
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_PREFIX="${IMAGE_PREFIX:-ghcr.io/blueapple168/uos-jdk}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-1}"

LOAD=0
NO_PUSH=0
ARGS=()
for a in "$@"; do
    case "${a}" in
        --load)    LOAD=1 ;;
        --no-push) NO_PUSH=1 ;;
        -*)        echo "unknown option: ${a}" >&2; exit 2 ;;
        *)         ARGS+=("${a}") ;;
    esac
done

# 变体注册表由构建与验证 workflow 共用，字段含义见 .github/variants.txt 头部注释
mapfile -t ALL_VARIANTS < <(grep -vE '^[[:space:]]*(#|$)' .github/variants.txt)
if [[ ${#ALL_VARIANTS[@]} -eq 0 ]]; then
    echo "未读到任何变体，检查 .github/variants.txt" >&2
    exit 1
fi

# 读 Dockerfile 里 ARG 的默认值并去掉两侧引号
get_arg() {
    local file="$1" name="$2"
    sed -nE "s/^ARG[[:space:]]+${name}=([^ #]+).*/\1/p" "${file}" \
        | head -n1 \
        | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

# 查 UOS 仓库里 java-*-openjdk-devel 的当前版本。
# OpenJDK 变体的版本由仓库决定，构建前只能进基础镜像问 yum，否则算不出 tag。
UOS_BASE_IMAGE="${UOS_BASE_IMAGE:-ghcr.io/blueapple168/uos-server-20-1070a:latest}"
declare -A UOS_VER_CACHE=()
uos_jdk_version() {   # $1=包名，如 java-17-openjdk-devel
    local pkg="$1" ver=""
    if [[ -n "${UOS_VER_CACHE[$pkg]:-}" ]]; then
        printf '%s' "${UOS_VER_CACHE[$pkg]}"
        return 0
    fi
    docker pull -q "${UOS_BASE_IMAGE}" >/dev/null 2>&1 || {
        echo "拉取基础镜像失败: ${UOS_BASE_IMAGE}" >&2; return 1; }
    ver="$(docker run --rm --entrypoint sh "${UOS_BASE_IMAGE}" -c "
        sed -i 's/\$StateMode/ufu/g' /etc/yum.repos.d/UnionTechOS.repo 2>/dev/null || true
        yum makecache -q >/dev/null 2>&1 || true
        yum list available ${pkg} 2>/dev/null | awk '/^${pkg}/{print \$2}' | tail -n1
    " | tr -d '\r\n')"
    # yum list 的版本带 epoch 前缀（如 1:1.8.0.422...），Docker tag 不允许冒号，去掉它
    ver="${ver#*:}"
    [[ -n "${ver}" ]] || { echo "查不到 ${pkg} 的版本" >&2; return 1; }
    UOS_VER_CACHE[$pkg]="${ver}"
    printf '%s' "${ver}"
}

# 按「系统-系统版本-发行版-JDK版本[-特性]」拼 tag，这是镜像唯一的 tag。
# Dragonwell / Temurin 的版本来自 Dockerfile ARG；
# OpenJDK 的版本进 UOS 基础镜像问 yum 得到（与构建时 yum install 装到的版本一致）。
# Docker tag 不允许 +，换成 -
make_tag() {
    local dir="$1" df="$2" os="$3" osver="$4" vendor="$5" flavor="$6"
    local jdkver=""
    case "${vendor}" in
        openjdk)
            local pkg
            pkg="$(grep -oE 'java-[0-9.]+-openjdk-devel' "${dir}/${df}" | head -n1)"
            [[ -n "${pkg}" ]] || { echo "找不到 java-*-openjdk-devel 包名: ${dir}/${df}" >&2; return 1; }
            jdkver="$(uos_jdk_version "${pkg}")" || return 1
            ;;
        dragonwell) jdkver="$(get_arg "${dir}/${df}" DRAGONWELL_RAW)" ;;
        temurin)    jdkver="$(get_arg "${dir}/${df}" JDKVER_RAW)" ;;
        *) echo "unknown vendor: ${vendor}" >&2; return 1 ;;
    esac
    [[ -n "${jdkver}" ]] || { echo "cannot parse JDK version: ${dir}/${df}" >&2; return 1; }
    jdkver="${jdkver//+/-}"
    local t="${os}-${osver}-${vendor}-${jdkver}"
    [[ -n "${flavor}" ]] && t="${t}-${flavor}"
    printf '%s' "${t}"
}

# 第 1 个参数按目录名前缀匹配，第 2 个参数按变体短名前缀匹配
pick_variants() {
    local ver="${1:-}" name="${2:-}"
    local out=()
    for v in "${ALL_VARIANTS[@]}"; do
        IFS='|' read -r dir df suffix short v_os v_osver v_vendor v_flavor <<< "${v}"
        [[ -n "${ver}"  && "${dir}"    != "${ver}"* ]] && continue
        [[ -n "${name}" && "${short}"  != "${name}"* ]] && continue
        out+=("${v}")
    done
    printf '%s\n' "${out[@]}"
}

build_one() {
    local dir="$1" df="$2" suffix="$3" tag_name="$4"
    [[ -n "${tag_name}" ]] || { echo "缺少规范 tag: ${dir}/${df}" >&2; return 1; }

    # --load 只能加载单个平台，剥离多平台列表
    local platforms="${PLATFORMS}"
    [[ "${LOAD}" == "1" ]] && platforms="${PLATFORMS%%,*}"

    # 镜像只打一个 tag：系统-系统版本-发行版-JDK版本[-特性]
    # --provenance=false --sbom=false：否则每个 tag 会多挂两个 unknown/unknown 的
    # attestation manifest，在 registry 页面上显示成一堆 sha256 条目
    local cmd=(docker buildx build
        --file "${dir}/${df}"
        --platform "${platforms}"
        --tag "${IMAGE_PREFIX}:${tag_name}"
        --provenance=false
        --sbom=false
        --build-arg "DUMB_INIT_VER=${DUMB_INIT_VER:-1.2.5}"
        --build-arg "GOSU_VER=${GOSU_VER:-1.20}"
        --build-arg "OTEL_AGENT_VER=${OTEL_AGENT_VER:-2.33.1}"
    )

    if [[ -n "${MIRROR_GITHUB:-}" ]]; then
        cmd+=(--build-arg "MIRROR_GITHUB=${MIRROR_GITHUB}")
    fi
    if [[ -n "${BASE_IMAGE_REPO:-}" ]]; then
        cmd+=(--build-arg "BASE_IMAGE_REPO=${BASE_IMAGE_REPO}")
    fi
    if [[ -n "${BASE_IMAGE_TAG:-}" ]]; then
        cmd+=(--build-arg "BASE_IMAGE_TAG=${BASE_IMAGE_TAG}")
    fi

    if [[ "${LOAD}" == "1" ]]; then
        cmd+=(--load)
    elif [[ "${PUSH}" == "1" && "${NO_PUSH}" == "0" ]]; then
        cmd+=(--push)
    fi

    cmd+=("${dir}")

    echo "------------------------------------------------------------"
    echo ">>> ${suffix}  (${dir}/${df})"
    echo ">>> tag: ${tag_name}"
    echo ">>> platforms: ${platforms}"
    echo "------------------------------------------------------------"
    "${cmd[@]}"
}

mapfile -t VARIANTS < <(pick_variants "${ARGS[0]:-}" "${ARGS[1]:-}")
if [[ ${#VARIANTS[@]} -eq 0 ]]; then
    echo "no variant matched: ${ARGS[*]:-}" >&2
    exit 1
fi

for v in "${VARIANTS[@]}"; do
    IFS='|' read -r dir df suffix short v_os v_osver v_vendor v_flavor <<< "${v}"
    new_tag="$(make_tag "${dir}" "${df}" "${v_os}" "${v_osver}" "${v_vendor}" "${v_flavor}")"
    build_one "${dir}" "${df}" "${suffix}" "${new_tag}"
done

echo
echo "完成。查看 manifest："
for v in "${VARIANTS[@]}"; do
    IFS='|' read -r dir df suffix short v_os v_osver v_vendor v_flavor <<< "${v}"
    tag="$(make_tag "${dir}" "${df}" "${v_os}" "${v_osver}" "${v_vendor}" "${v_flavor}")"
    echo "  docker buildx imagetools inspect ${IMAGE_PREFIX}:${tag}"
done
