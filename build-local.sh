#!/usr/bin/env bash
# 本地快速验证：只构建当前宿主架构并加载到本地 docker，不推送
#   ./build-local.sh          # 构建 jdk17 验证
#   ./build-local.sh jdk21    # 构建指定变体
set -euo pipefail
cd "$(dirname "$0")"

export PUSH=0
case "$(uname -m)" in
    x86_64|amd64)  export PLATFORMS=linux/amd64 ;;
    aarch64|arm64) export PLATFORMS=linux/arm64 ;;
    *) echo "unsupported host arch: $(uname -m)" >&2; exit 1 ;;
esac

echo ">>> 宿主架构 $(uname -m) → 平台 ${PLATFORMS}"
exec ./build.sh --load "$@"
