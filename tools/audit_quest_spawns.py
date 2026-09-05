#!/usr/bin/env python3
"""审计世界刷怪条目与任务的对齐关系（可复跑，只读不改）。

检查 runtime_world_content.json 的 enemies 条目：
  1. required_quest_id 必须存在于 quests.json；
  2. required_stage_ids / required_stage_id 若存在，必须是该任务 stages 里的 id；
  3. 条目坐标落在关卡画布内（0..4096 x, 0..864 y）；
  4. 汇总每关刷怪点 x 范围 vs 关卡入口（传送点）x，提示「进图位置与刷怪点距离」。

用途：排查「任务怪没生成」类反馈时先跑它，区分数据问题 vs 位置/持久化问题。
"""
from __future__ import annotations

import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    world = load(PROJECT / "data" / "runtime_world_content.json")
    quests = load(PROJECT / "data" / "quests.json")
    world_interact = world.get("levels") or {}
    problems: list[str] = []
    total = 0
    for level_id, level in world_interact.items():
        spawns = level.get("enemies") or []
        xs = [float(e.get("x", 0)) for e in spawns if isinstance(e, dict)]
        portals = [
            float(i.get("x", 0))
            for i in (level.get("interactables") or [])
            if isinstance(i, dict) and i.get("type") == "portal"
        ]
        entry_x = min(portals) if portals else 0.0
        for entry in spawns:
            if not isinstance(entry, dict):
                continue
            total += 1
            qid = str(entry.get("required_quest_id", 0))
            quest = quests.get(qid, {})
            if not quest:
                problems.append(f"level {level_id}: 条目 {entry.get('spawn_id')} 的 quest {qid} 不存在")
                continue
            stage_ids = [s.get("id") for s in quest.get("stages", [])]
            gates = entry.get("required_stage_ids") or (
                [entry["required_stage_id"]] if entry.get("required_stage_id") else []
            )
            missing = [g for g in gates if g not in stage_ids]
            if missing:
                problems.append(f"level {level_id}: 条目 {entry.get('spawn_id')} 阶段门不存在: {missing}")
            x = float(entry.get("x", 0))
            y = float(entry.get("y", 0))
            if not (0 <= x <= 4096 and 0 <= y <= 864):
                problems.append(f"level {level_id}: 条目 {entry.get('spawn_id')} 坐标越界 ({x}, {y})")
        if spawns:
            print(
                f"level {level_id}: 刷怪 {len(spawns)} 条 | x 范围 {min(xs):.0f}~{max(xs):.0f} | 入口 x={entry_x:.0f} | 距入口最远 {max(xs) - entry_x:.0f}px"
            )
    print("刷怪条目总数:", total, "| 问题:", len(problems))
    for p in problems:
        print("  !", p)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
