#!/usr/bin/env python3
"""反馈数据修正（可复跑、幂等、带备份）：

1. 关卡传送点尽量安排在地图最左：前进门统一移到 x=320（回城门保持 200，二者错开）。
2. 任务 26060（灰面骑士）补 autoplay_segments：与其对话收尾后自动播 C6-06-A 过场，
   修复「NPC 出来了但没有相关剧情」（story_auto_play._try_autoplay_segments 机制已存在，缺数据）。
"""
from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
WORLD = PROJECT / "data" / "runtime_world_content.json"
DIALOGUES = PROJECT / "data" / "dialogues.json"

FORWARD_GATE_X = 320.0
RETURN_GATE_X = 200.0


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dump(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    world = load(WORLD)
    dialogues = load(DIALOGUES)

    backup = PROJECT / ".frame-ronin" / "backups" / "feedback_data" / datetime.now().strftime("%Y%m%d_%H%M%S")
    backup.mkdir(parents=True, exist_ok=True)
    shutil.copy2(WORLD, backup / WORLD.name)
    shutil.copy2(DIALOGUES, backup / DIALOGUES.name)

    moved = 0
    for level_id, level in (world.get("levels") or {}).items():
        for item in level.get("interactables") or []:
            if item.get("type") != "portal":
                continue
            gate = str(item.get("id", ""))
            target_x = RETURN_GATE_X if gate.startswith("gate_town") else FORWARD_GATE_X
            if float(item.get("x", 0)) != target_x:
                item["x"] = target_x
                moved += 1

    timeline = dialogues.get("task_c6_06_a")
    segments_added = 0
    if isinstance(timeline, dict):
        segments = timeline.get("autoplay_segments")
        if not isinstance(segments, list):
            segments = []
            timeline["autoplay_segments"] = segments
        have = {(int(s.get("npc_id", 0)), int(s.get("entry_ms", 0))) for s in segments if isinstance(s, dict)}
        for npc_id, entry_ms in ((9036, 0), (9002, 73240)):
            if (npc_id, entry_ms) not in have:
                segments.append({"npc_id": npc_id, "entry_ms": entry_ms})
                segments_added += 1

    dump(WORLD, world)
    dump(DIALOGUES, dialogues)
    print("备份:", backup)
    print("传送点左移:", moved, "| 补 autoplay_segments:", segments_added)


if __name__ == "__main__":
    main()
