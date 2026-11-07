#!/usr/bin/env python3
"""把各变体/架构的验证结果汇总成 Markdown 报告。

用法:
    summarize.py <结果目录>                 输出 Markdown 报告
    summarize.py <结果目录> --total-fails   只输出失败检查项总数（供 CI 判退出码）
"""
import json
import sys
from pathlib import Path


def load(results_dir: Path) -> list[dict]:
    items = []
    for f in sorted(results_dir.glob("*.json")):
        try:
            items.append(json.loads(f.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError) as exc:
            print(f"跳过无法解析的 {f.name}: {exc}", file=sys.stderr)
    # 按 JDK 版本、发行版、架构排序，报告更好读
    items.sort(key=lambda x: (x.get("vendor", ""), x.get("jdkver", ""), x.get("tag", ""), x.get("arch", "")))
    return items


def status_of(item: dict) -> str:
    checks = item.get("checks", [])
    if any(c["status"] == "FAIL" for c in checks):
        return "FAIL"
    if any(c["status"] == "WARN" for c in checks):
        return "WARN"
    return "PASS"


def badge(status: str) -> str:
    return {"PASS": "✅ 通过", "WARN": "⚠️ 有告警", "FAIL": "❌ 失败"}.get(status, status)


def emit_report(items: list[dict]) -> None:
    total = len(items)
    n_pass = sum(1 for i in items if status_of(i) == "PASS")
    n_warn = sum(1 for i in items if status_of(i) == "WARN")
    n_fail = sum(1 for i in items if status_of(i) == "FAIL")

    print("## 镜像功能与版本验证报告\n")
    print(f"共验证 **{total}** 个镜像实例（变体 × 架构）："
          f"✅ 通过 {n_pass} ／ ⚠️ 告警 {n_warn} ／ ❌ 失败 {n_fail}\n")

    print("### 总览\n")
    print("| 镜像 tag | 架构 | 发行版 | 期望 JDK | 实际 java 版本 | 结果 |")
    print("|---|---|---|---|---|---|")
    for item in items:
        actual = next((c["detail"] for c in item.get("checks", [])
                       if c["item"] == "JDK 版本"), "-")
        # 详情里带了「（主版本 X）」的说明，报告里只留版本号
        actual = actual.split("（")[0].strip()
        st = status_of(item)
        print(f"| `{item.get('tag','')}` | {item.get('arch','')} "
              f"| {item.get('vendor','')} | {item.get('jdkver','')} | {actual} | {badge(st)} |")

    # 只列失败与告警，通过的项不必刷屏
    problems = [(i, c) for i in items for c in i.get("checks", [])
                if c["status"] in ("FAIL", "WARN")]
    print("\n### 失败与告警明细\n")
    if not problems:
        print("无。所有检查项均通过。\n")
    else:
        print("| 镜像 | 架构 | 状态 | 检查项 | 详情 |")
        print("|---|---|---|---|---|")
        for item, check in problems:
            print(f"| `{item.get('tag','')}` | {item.get('arch','')} | {check['status']} "
                  f"| {check['item']} | {check['detail']} |")
        print()

    # 信息性采集项单独一张表，方便人工核对系统版本这类不便硬断言的内容
    infos = [(i, c) for i in items for c in i.get("checks", []) if c["status"] == "INFO"]
    if infos:
        print("### 采集信息\n")
        print("| 镜像 | 架构 | 项目 | 值 |")
        print("|---|---|---|---|")
        for item, check in infos:
            print(f"| `{item.get('tag','')}` | {item.get('arch','')} | {check['item']} | {check['detail']} |")
        print()


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    results_dir = Path(sys.argv[1])
    if not results_dir.is_dir():
        print(f"结果目录不存在: {results_dir}", file=sys.stderr)
        return 2

    items = load(results_dir)
    if not items:
        print("未找到任何结果文件", file=sys.stderr)
        if "--total-fails" in sys.argv:
            print(1)
            return 0
        print("## 镜像功能与版本验证报告\n\n未找到任何结果文件，请检查验证 job 是否执行。")
        return 0

    if "--total-fails" in sys.argv:
        print(sum(i.get("fails", 0) for i in items))
        return 0

    emit_report(items)
    return 0


if __name__ == "__main__":
    sys.exit(main())
