#!/usr/bin/env python3
"""统一 headless 测试入口（Harness 反馈循环核心）。

遍历 tests/*.gd（跳过 .uid），逐个以 godot --headless 运行，收集退出码汇总。
每个测试脚本约定：extends SceneTree，通过 quit(0)=通过 / quit(1)=失败。

godot 可执行文件解析顺序（三级）：
  1. 命令行参数 --godot <path>
  2. 环境变量 GODOT_BIN
  3. 项目内 tools/godot_bin.txt（首行非注释行）
  4. PATH 中的 godot / godot4
都没有则明确报错并给出设置指引。

用法：
  python tools/run_tests.py                 # 跑全部 tests/*.gd
  python tools/run_tests.py party_clamp_and_fall   # 只跑名字包含该子串的测试
  python tools/run_tests.py --godot E:\\g_selfcustom\\Godot_v4.7-stable_win64.exe
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent  # hengban-2/
TESTS_DIR = PROJECT / "tests"
GODOT_BIN_FILE = Path(__file__).resolve().parent / "godot_bin.txt"


def resolve_godot(cli_path: str | None) -> Path | None:
    candidates: list[Path] = []
    if cli_path:
        candidates.append(Path(cli_path))
    env = os.environ.get("GODOT_BIN", "").strip()
    if env:
        candidates.append(Path(env))
    if GODOT_BIN_FILE.is_file():
        for line in GODOT_BIN_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                candidates.append(Path(line))
    for name in ("godot", "godot4", "godot4.7"):
        found = shutil.which(name)
        if found:
            candidates.append(Path(found))
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="运行 hengban-2 headless 测试")
    parser.add_argument("filter", nargs="?", default="", help="测试文件名子串过滤")
    parser.add_argument("--godot", default=None, help="godot 可执行文件路径（优先于 GODOT_BIN 环境变量）")
    args = parser.parse_args()

    godot = resolve_godot(args.godot)
    if godot is None:
        print("[run_tests] 找不到 godot 可执行文件。设置方式（任选其一）：", file=sys.stderr)
        print(f"  1. python tools/run_tests.py --godot <path>   例：--godot E:\\g_selfcustom\\Godot_v4.7-stable_win64.exe", file=sys.stderr)
        print("  2. set GODOT_BIN=<path>（环境变量）", file=sys.stderr)
        print(f"  3. 把路径写入 {GODOT_BIN_FILE}（首行）", file=sys.stderr)
        return 2

    scripts = sorted(p for p in TESTS_DIR.glob("*.gd") if args.filter in p.name)
    if not scripts:
        print(f"[run_tests] tests/ 下没有匹配 '{args.filter}' 的测试脚本")
        return 0

    print(f"[run_tests] godot: {godot}")
    passed: list[str] = []
    failed: list[tuple[str, str]] = []
    for script in scripts:
        print(f"--- {script.name} ---", flush=True)
        proc = subprocess.run(
            [str(godot), "--headless", "--path", str(PROJECT), "--script", f"tests/{script.name}"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
        )
        output = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode == 0:
            passed.append(script.name)
            tail = [line for line in output.splitlines() if line.strip()][-3:]
            for line in tail:
                print(f"    {line}")
        else:
            failed.append((script.name, output))
            print(f"    FAIL (exit {proc.returncode})")
            for line in output.splitlines()[-12:]:
                print(f"    {line}")

    print(f"\n[run_tests] 汇总：PASS {len(passed)} / FAIL {len(failed)} / 共 {len(scripts)}")
    for name, _ in failed:
        print(f"  FAIL: {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
