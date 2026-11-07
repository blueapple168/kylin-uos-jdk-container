#!/usr/bin/env python3
"""把各构建产物里的 tag / JDK 版本汇总，重写 README.md 的版本表。

用法:
    update-readme.py <结果目录>    就地更新 README.md，有变化则退出码 0 并打印 changed
                                   无变化退出码 0 且不打印 changed
    update-readme.py <结果目录> --check   只检查是否需要更新，需要则退出码 10

结果目录里每个文件形如:
    {"variant":"jdk8/Dockerfile","dir":"jdk8","tag":"uos-...","java_version":"1.8.0_422"}
"""
import json
import sys
from pathlib import Path

BEGIN = "<!-- VERSIONS:BEGIN"
END = "<!-- VERSIONS:END -->"


def load(results_dir: Path) -> list[dict]:
    rows = []
    for f in sorted(results_dir.glob("*.json")):
        try:
            rows.append(json.loads(f.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError) as exc:
            print(f"跳过无法解析的 {f.name}: {exc}", file=sys.stderr)
    # 按 tag 排序，顺序稳定，避免每次提交产生无意义 diff
    rows.sort(key=lambda r: r.get("tag", ""))
    return rows


def render(rows: list[dict]) -> list[str]:
    lines = [
        f"{BEGIN} 本块由构建工作流自动重写，不要手工编辑 -->",
        "| 镜像 tag | 镜像内 `java -version` |",
        "|---|---|",
    ]
    for r in rows:
        tag = r.get("tag") or "-"
        java_ver = r.get("java_version") or "-"
        lines.append(f"| `{tag}` | `{java_ver}` |")
    lines.append(END)
    return lines


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    results_dir = Path(sys.argv[1])
    check_only = "--check" in sys.argv

    rows = load(results_dir)
    if not rows:
        print("未找到任何构建结果，跳过 README 更新", file=sys.stderr)
        return 0

    readme = Path("README.md")
    text = readme.read_text(encoding="utf-8")
    lines = text.splitlines()

    start = next((i for i, l in enumerate(lines) if l.startswith(BEGIN)), None)
    end = next((i for i, l in enumerate(lines) if l.strip() == END), None)
    if start is None or end is None or end < start:
        print("README.md 里找不到 VERSIONS 标记块，跳过", file=sys.stderr)
        return 0

    new_block = render(rows)
    new_text = "\n".join(lines[:start] + new_block + lines[end + 1:]) + "\n"

    if new_text == text:
        print("README 版本表无变化")
        return 0

    if check_only:
        print("需要更新")
        return 10

    readme.write_text(new_text, encoding="utf-8")
    print("changed")
    print(f"README 版本表已更新，共 {len(rows)} 个变体")
    return 0


if __name__ == "__main__":
    sys.exit(main())
