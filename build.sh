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

# 变体清单：目录|Dockerfile|镜像名后缀|变体短名
ALL_VARIANTS=(
    "jdk8|Dockerfile|jdk8|openjdk"
    "jdk8|Dockerfile-dragonwell-extended|jdk8-dragonwell|dragonwell"
    "jdk17|Dockerfile|jdk17|openjdk"
    "jdk17|Dockerfile-dragonwell-standard|jdk17-dragonwell|dragonwell"
    "jdk17-ffmpeg|Dockerfile|jdk17-ffmpeg|ffmpeg"
    "jdk21|Dockerfile|jdk21-dragonwell|dragonwell"
    "jdk25-lts|Dockerfile|jdk25-dragonwell|dragonwell"
    "jdk25-lts|Dockerfile-dragonwell-extended|jdk25-dragonwell-extended|dragonwell"
    "jdk25-lts|Dockerfile-adoptium|jdk25-adoptium|adoptium"
    "jdk25-lts|Dockerfile-adoptium-kylinv11|jdk25-adoptium-kylin|kylin"
)

# 第 1 个参数按目录名前缀匹配，第 2 个参数按变体短名前缀匹配
pick_variants() {
    local ver="${1:-}" name="${2:-}"
    local out=()
    for v in "${ALL_VARIANTS[@]}"; do
        IFS='|' read -r dir df suffix short <<< "${v}"
        [[ -n "${ver}"  && "${dir}"    != "${ver}"* ]] && continue
        [[ -n "${name}" && "${short}"  != "${name}"* ]] && continue
        out+=("${v}")
    done
    printf '%s\n' "${out[@]}"
}

build_one() {
    local dir="$1" df="$2" suffix="$3"
    local tag="${IMAGE_PREFIX}:${suffix}"

    # --load 只能加载单个平台，剥离多平台列表
    local platforms="${PLATFORMS}"
    [[ "${LOAD}" == "1" ]] && platforms="${PLATFORMS%%,*}"

    local cmd=(docker buildx build
        --file "${dir}/${df}"
        --platform "${platforms}"
        --tag "${tag}"
        --build-arg "DUMB_INIT_VER=${DUMB_INIT_VER:-1.2.5}"
        --build-arg "GOSU_VER=${GOSU_VER:-1.20}"
        --build-arg "OTEL_AGENT_VER=${OTEL_AGENT_VER:-2.33.1}"
        --label "org.opencontainers.image.revision=jdk-${suffix}"
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

    if [[ "${IMAGE_TAG}" != "latest" ]]; then
        cmd+=(--tag "${IMAGE_PREFIX}:${suffix}-${IMAGE_TAG}")
    fi

    cmd+=("${dir}")

    echo "------------------------------------------------------------"
    echo ">>> ${suffix}  (${dir}/${df})"
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
    IFS='|' read -r dir df suffix short <<< "${v}"
    build_one "${dir}" "${df}" "${suffix}"
done

echo
echo "完成。查看 manifest："
for v in "${VARIANTS[@]}"; do
    IFS='|' read -r dir df suffix short <<< "${v}"
    echo "  docker buildx imagetools inspect ${IMAGE_PREFIX}:${suffix}"
done
