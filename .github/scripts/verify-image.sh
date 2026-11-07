#!/bin/sh
# 镜像功能与版本自检 —— 在目标镜像的容器内执行。
#
# 只用 POSIX sh + coreutils：Kylin minimal 等镜像没有 bash，写 bash 专有语法会直接跑不起来。
# 用法: sh verify-image.sh <系统> <系统版本> <发行版> <JDK版本> <架构> <特性>
#   例: sh verify-image.sh uos 20-1070a dragonwell 17.0.20.0.21+8 amd64 standard
# 输出: 每行 "状态<TAB>检查项<TAB>详情"，状态 ∈ PASS / FAIL / WARN / INFO
#       末行 "SUMMARY<TAB>FAIL<TAB>失败数"
set -u

EXP_OS="${1:-}"
EXP_OSVER="${2:-}"
EXP_VENDOR="${3:-}"
EXP_JDKVER="${4:-}"
EXP_ARCH="${5:-}"
EXP_FLAVOR="${6:-}"

fails=0
ok()   { printf 'PASS\t%s\t%s\n' "$1" "$2"; }
ng()   { printf 'FAIL\t%s\t%s\n' "$1" "$2"; fails=$((fails + 1)); }
wn()   { printf 'WARN\t%s\t%s\n' "$1" "$2"; }
inf()  { printf 'INFO\t%s\t%s\n' "$1" "$2"; }

# OpenJDK 变体的 JDK 版本由 UOS 仓库决定，调用方传空；这里改读镜像内 rpm 的实际 NEVRA，
# 后面用它推主版本、与 java -version 交叉验证。Dragonwell/Temurin 由调用方传入。
if [ -z "$EXP_JDKVER" ]; then
    PKG="$(rpm -qa 2>/dev/null | grep -- -openjdk-devel | head -n1 || true)"
    if [ -n "$PKG" ]; then
        EXP_JDKVER="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$PKG" 2>/dev/null | tr -d '\r\n')"
        inf "仓库 JDK 版本" "${EXP_JDKVER}"
    fi
fi

# 期望主版本：1.8.0.412.b08-5.up2 -> 1.8；25.0.5+8 -> 25；Dragonwell 8.30.29 -> 1.8
case "$EXP_JDKVER" in
    1.*)   EXP_MAJOR="1.8" ;;
    8|8.*) EXP_MAJOR="1.8" ;;
    *)     EXP_MAJOR="${EXP_JDKVER%%.*}" ;;
esac

# ---------- 1. 架构 ----------
actual_arch="$(uname -m)"
case "$EXP_ARCH" in
    amd64) want_arch="x86_64" ;;
    arm64) want_arch="aarch64" ;;
    *)     want_arch="" ;;
esac
if [ -z "$want_arch" ]; then
    inf "架构" "未知期望架构 ${EXP_ARCH}，实测 ${actual_arch}"
elif [ "$actual_arch" = "$want_arch" ]; then
    ok "架构" "${actual_arch}"
else
    ng "架构" "期望 ${want_arch}，实际 ${actual_arch}"
fi

# ---------- 2. 系统标识 ----------
if [ -r /etc/os-release ]; then
    # 用 . 引入会带进 NAME/ID/VERSION_ID/PRETTY_NAME，注意别覆盖脚本自己的变量
    os_pretty="$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')"
    os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
    os_verid="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')"
    [ -n "$os_pretty" ] || os_pretty="${os_id:-unknown}"

    haystack="$(printf '%s %s' "$os_id" "$os_pretty" | tr 'A-Z' 'a-z')"
    case "$haystack" in
        *"$EXP_OS"*) ok "系统" "${os_pretty}" ;;
        *)           ng "系统" "期望含 ${EXP_OS}，实际 ID=${os_id:-空} PRETTY=${os_pretty}" ;;
    esac
    inf "系统版本号" "VERSION_ID=${os_verid:-空}"

    # 系统版本只做提示，不做硬断言：各家 os-release 写法差异大，硬比会假失败。
    # 注意不能整段比：Kylin 的 v11-2503 里 2503 是内部构建号，os-release 只有 V11；
    # UOS 的 20-1070a 里 1070a 也不一定出现在 PRETTY_NAME。所以按段命中即算对上。
    ver_lc="$(printf '%s' "$EXP_OSVER" | tr 'A-Z' 'a-z')"
    ver_hit=""
    for k in "$ver_lc" "${ver_lc%%-*}" "${ver_lc#*-}"; do
        [ -n "$k" ] || continue
        case "$haystack" in
            *"$k"*) ver_hit="$k"; break ;;
        esac
    done
    if [ -n "$ver_hit" ]; then
        ok "系统版本" "os-release 命中 ${ver_hit}"
    else
        wn "系统版本" "os-release 中未找到 ${EXP_OSVER} 的任何片段，请人工确认"
    fi
else
    ng "系统" "缺少 /etc/os-release"
fi

# ---------- 3. JDK 版本 ----------
jv="$(java -version 2>&1 | sed -n '1s/.*version "\([^"]*\)".*/\1/p')"
if [ -z "$jv" ]; then
    ng "JDK 版本" "java -version 无输出或格式异常"
else
    case "$jv" in
        "$EXP_MAJOR".*|"$EXP_MAJOR"_*) ok "JDK 版本" "${jv}（主版本 ${EXP_MAJOR}）" ;;
        *)                             ng "JDK 版本" "期望主版本 ${EXP_MAJOR}，实际 ${jv}" ;;
    esac
fi

jcv="$(javac -version 2>&1 | sed -n '1s/^javac //p')"
if [ -n "$jcv" ]; then
    case "$jcv" in
        "$EXP_MAJOR".*|"$EXP_MAJOR"_*) ok "javac 版本" "${jcv}" ;;
        *)                             ng "javac 版本" "与 java 不一致，javac=${jcv}" ;;
    esac
else
    ng "javac 版本" "javac 不可用（devel 包缺失？）"
fi

# java.vendor 走 -XshowSettings，输出在 stderr
jprops="$(java -XshowSettings:properties -version 2>&1)"
vendor="$(printf '%s\n' "$jprops" | sed -n 's/^[[:space:]]*java\.vendor = //p' | head -n1)"
jhome="$(printf '%s\n' "$jprops" | sed -n 's/^[[:space:]]*java\.home = //p' | head -n1)"
inf "java.vendor" "${vendor:-取不到}"
inf "java.home" "${jhome:-取不到}"

vendor_lc="$(printf '%s' "$vendor" | tr 'A-Z' 'a-z')"
case "$EXP_VENDOR" in
    temurin)
        case "$vendor_lc" in
            *adoptium*|*temurin*) ok "JDK 发行商" "${vendor}" ;;
            *)                    ng "JDK 发行商" "期望 Adoptium/Temurin，实际 ${vendor:-空}" ;;
        esac
        ;;
    dragonwell)
        case "$vendor_lc" in
            *alibaba*|*dragonwell*) ok "JDK 发行商" "${vendor}" ;;
            *)                      ng "JDK 发行商" "期望 Alibaba/Dragonwell，实际 ${vendor:-空}" ;;
        esac
        ;;
    *)
        inf "JDK 发行商" "openjdk 变体不校验 vendor（UOS 仓库构建，vendor 字符串不固定）"
        ;;
esac

# ---------- 4. JAVA_HOME ----------
if [ -n "${JAVA_HOME:-}" ]; then
    if [ -x "${JAVA_HOME}/bin/java" ]; then
        ok "JAVA_HOME" "${JAVA_HOME}"
    else
        ng "JAVA_HOME" "${JAVA_HOME} 下没有可执行的 bin/java"
    fi
    case "$jhome" in
        "$JAVA_HOME"|"$JAVA_HOME"/*) ok "java.home 一致性" "与 JAVA_HOME 相符" ;;
        *)
            # JAVA_HOME 常是指向真实版本目录的符号链接（如 java-17-openjdk -> java-17-openjdk-17.0.9...x86_64），
            # java.home 报的是解析后的真实路径，归一化后再比，否则每次都误报
            if [ -n "$jhome" ] && [ "$(readlink -f "$JAVA_HOME" 2>/dev/null || printf '%s' "$JAVA_HOME")" = "$jhome" ]; then
                ok "java.home 一致性" "JAVA_HOME 为符号链接，解析后与 java.home 一致"
            else
                wn "java.home 一致性" "java.home=${jhome:-空}，JAVA_HOME=${JAVA_HOME}"
            fi
            ;;
    esac
else
    ng "JAVA_HOME" "环境变量未设置"
fi

# ---------- 5. 编译并运行 ----------
tmpd="$(mktemp -d 2>/dev/null || printf '/tmp/vchk.%s' "$$")"
mkdir -p "$tmpd" 2>/dev/null || true
if [ -w "$tmpd" ]; then
    cat > "${tmpd}/Hello.java" <<'JAVA'
public class Hello {
    public static void main(String[] args) {
        System.out.println("HELLO-" + System.getProperty("java.specification.version"));
    }
}
JAVA
    if javac -d "$tmpd" "${tmpd}/Hello.java" >/dev/null 2>&1; then
        hello_out="$(java -cp "$tmpd" Hello 2>&1)"
        case "$hello_out" in
            HELLO-*) ok "编译运行" "javac 编译 + java 执行成功，输出 ${hello_out}" ;;
            *)       ng "编译运行" "执行输出异常: ${hello_out}" ;;
        esac
    else
        ng "编译运行" "javac 编译失败"
    fi
    rm -rf "$tmpd"
else
    ng "编译运行" "临时目录不可写: ${tmpd}"
fi

# ---------- 6. JVM 容器参数 ----------
# JAVA_OPTS 里的 -XX:MaxRAMPercentage 不会自动生效，必须显式带上才能看到实际值。
# 顺带验证 JAVA_OPTS 本身能被这个 JDK 接受：JDK 8 的 MaxRAMPercentage 是 experimental，
# 少了 -XX:+UnlockExperimentalVMOptions 会直接报 Unrecognized VM option 而起不来，
# 这类问题只有真跑一遍才能发现，所以命令失败要判 FAIL 而不是记个 WARN 放过。
if mrp_out="$(java ${JAVA_OPTS:-} -XX:+PrintFlagsFinal -version 2>&1)"; then
    mrp="$(printf '%s\n' "$mrp_out" \
            | sed -n 's/.*MaxRAMPercentage[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' | head -n1)"
    if [ -n "$mrp" ]; then
        case "$mrp" in
            75|75.0|75.000000) ok "MaxRAMPercentage" "${mrp}（符合 75.0 预期）" ;;
            *)                 wn "MaxRAMPercentage" "实际 ${mrp}，预期 75.0" ;;
        esac
    else
        wn "MaxRAMPercentage" "JAVA_OPTS 可执行但未输出该参数"
    fi
else
    ng "MaxRAMPercentage" "带 JAVA_OPTS 启动 java 失败（该 JDK 可能不支持其中某个参数）"
    printf 'INFO\tJAVA_OPTS 启动报错\t%s\n' "$(printf '%s' "$mrp_out" | head -n2 | tr '\n' ' ')"
fi

# ---------- 7. 运行时组件 ----------
if dumb-init --version >/dev/null 2>&1; then
    ok "dumb-init" "$(dumb-init --version 2>&1 | head -n1)"
else
    ng "dumb-init" "不可执行"
fi

if gosu --version >/dev/null 2>&1; then
    ok "gosu" "$(gosu --version 2>&1 | head -n1)"
else
    ng "gosu" "不可执行"
fi

idout="$(id app 2>&1)"
case "$idout" in
    *"uid=1000"*) ok "app 用户" "${idout}" ;;
    *)            ng "app 用户" "期望 uid=1000，实际 ${idout}" ;;
esac

if [ -s /opt/otel/libs/opentelemetry-javaagent.jar ]; then
    ok "OTel Agent" "$(wc -c < /opt/otel/libs/opentelemetry-javaagent.jar) 字节"
else
    ng "OTel Agent" "缺失或为空"
fi

if [ -x /usr/local/bin/docker-entrypoint.sh ]; then
    ok "entrypoint" "可执行"
else
    ng "entrypoint" "不可执行或不存在"
fi

# ---------- 8. 时区与字符集 ----------
tzfile="$(cat /etc/timezone 2>/dev/null || true)"
if [ "$tzfile" = "Asia/Shanghai" ]; then
    ok "时区" "Asia/Shanghai"
else
    wn "时区" "/etc/timezone=${tzfile:-空}，预期 Asia/Shanghai"
fi

if locale -a 2>/dev/null | grep -qi 'zh_CN'; then
    ok "中文 locale" "已安装"
else
    inf "中文 locale" "未安装中文语言包（不影响 JVM 运行，仅记录）"
fi

# ---------- 9. 变体特性 ----------
if [ "$EXP_FLAVOR" = "ffmpeg" ]; then
    if ffmpeg -version >/dev/null 2>&1; then
        ok "FFmpeg" "$(ffmpeg -version 2>&1 | head -n1)"
    else
        ng "FFmpeg" "不可执行"
    fi
fi

if java --list-modules >/dev/null 2>&1; then
    ok "JDK 模块" "$(java --list-modules 2>/dev/null | wc -l) 个"
else
    inf "JDK 模块" "该版本不支持 --list-modules（JDK 8）"
fi

printf 'SUMMARY\tFAIL\t%s\n' "$fails"
