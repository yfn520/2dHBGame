#!/usr/bin/env python3
"""生成章节回响数据：enemies.json 追加 12 条回响怪 + data/echo_spawns.json + chapters.json 回响 Boss 改指。

可复跑（幂等：先移除旧的回响 id 再写入）；改动前备份到 .frame-ronin/backups/echo_data/<ts>/。
数值规则（见规划）：回响精英 = 该章剧情怪均值 ×2.2；回响 Boss = 原 Boss ×1.6、exp ×1.5；
Boss 唯一掉落（chance>=0.999）仅首杀保证，常规掉 echo_drop_items（材料/货币 + 原装备 0.08）。
"""
from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
ENEMIES = PROJECT / "data" / "enemies.json"
CHAPTERS = PROJECT / "data" / "chapters.json"
ECHO_SPAWNS = PROJECT / "data" / "echo_spawns.json"
WORLD = PROJECT / "data" / "runtime_world_content.json"

# 章 → (level, 怪群[(id,count)], 精英资产来源 id, 精英名, 原 Boss id, 回响 Boss id, 回响精英 id)
CHAPTERS_SPEC = [
    ("chapter_1", 1, [(8001, 4), (8003, 3), (8002, 2)], 8033, "回响·牧原守卫", 8027, 8050, 8040),
    ("chapter_2", 2, [(8013, 4), (8020, 2), (8004, 2)], 8013, "回响·亡魂领主", 8028, 8051, 8041),
    ("chapter_3", 3, [(8002, 5), (8025, 2), (8024, 2)], 8025, "回响·构装督导", 8029, 8052, 8042),
    ("chapter_4", 4, [(8026, 4), (8015, 3), (8019, 2)], 8021, "回响·潮卫", 8030, 8053, 8043),
    ("chapter_5", 5, [(8007, 4), (8016, 2), (8011, 2)], 8033, "回响·烬骑士长", 8031, 8054, 8044),
    ("chapter_6", 6, [(8023, 4), (8036, 2), (8038, 2)], 8038, "回响·神庭执剑", 8032, 8055, 8045),
]
# 每章 farming 掉落（材料/货币），索引按章错开
MAT_POOL = ["100128", "100129", "100130", "100131", "100132", "100133", "100144", "100145", "100146", "100147", "100148", "100149"]
CUR_POOL = ["100124", "100125", "100172", "100173", "100174", "100175"]
# 章节基准等级（设计常量表）：tier = clamp((party_avg - base)/8 + clears/3, 0, 10)
BASE_LEVELS = [6, 12, 18, 24, 30, 36]


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dump(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    enemies = load(ENEMIES)
    chapters = load(CHAPTERS)
    world = load(WORLD)

    backup = PROJECT / ".frame-ronin" / "backups" / "echo_data" / datetime.now().strftime("%Y%m%d_%H%M%S")
    backup.mkdir(parents=True, exist_ok=True)
    for src in (ENEMIES, CHAPTERS):
        shutil.copy2(src, backup / src.name)
    if ECHO_SPAWNS.is_file():
        shutil.copy2(ECHO_SPAWNS, backup / ECHO_SPAWNS.name)

    # 幂等：先清掉旧的回响 id
    for key in [k for k in enemies if k.startswith("804") or k.startswith("805")]:
        if int(key) >= 8040:
            del enemies[key]

    echo_spawns: dict = {}
    for index, (chapter_id, level_id, groups, elite_src, elite_name, boss_id, echo_boss_id, elite_id) in enumerate(CHAPTERS_SPEC):
        story = [enemies[str(gid)] for gid, _ in groups if str(gid) in enemies]
        avg_hp = sum(float(e.get("max_hp", 50)) for e in story) / max(1, len(story))
        avg_atk = sum(float(e.get("attack", 1)) for e in story) / max(1, len(story))
        avg_exp = sum(float(e.get("exp", 10)) for e in story) / max(1, len(story))
        base_level = BASE_LEVELS[index]

        # --- 回响精英 ---
        src = enemies[str(elite_src)]
        mat = MAT_POOL[(index * 2) % len(MAT_POOL)]
        mat2 = MAT_POOL[(index * 2 + 1) % len(MAT_POOL)]
        cur = CUR_POOL[index % len(CUR_POOL)]
        enemies[str(elite_id)] = {
            "asset": src.get("asset"),
            "attack": round(avg_atk * 2.2, 1),
            "attack_range": src.get("attack_range", 80),
            "chapter_id": chapter_id,
            "character_config": src.get("character_config"),
            "defense": round(avg_atk * 0.6, 1),
            "detect_range": src.get("detect_range", 300),
            "drop_items": [
                {"chance": 0.9, "count": 2, "item_id": int(mat)},
                {"chance": 0.6, "count": 1, "item_id": int(cur)},
            ],
            "exp": int(round(avg_exp * 3)),
            "is_boss": False,
            "max_hp": round(avg_hp * 2.2, 1),
            "move_speed": src.get("move_speed", 80),
            "name": elite_name,
            "normal_skill": src.get("normal_skill"),
            "patrol_range": src.get("patrol_range", 120),
            "skill_weights": src.get("skill_weights", [100]),
            "skills": src.get("skills", []),
            "traits": ["elite", "echo"],
        }

        # --- 回响 Boss ---
        boss = enemies[str(boss_id)]
        unique_drops = boss.get("drop_items", [])
        echo_drops = [
            {"chance": 1.0, "count": 3, "item_id": int(mat)},
            {"chance": 1.0, "count": 2, "item_id": int(mat2)},
            {"chance": 1.0, "count": 2, "item_id": int(cur)},
        ]
        for value in unique_drops:
            item_id = int(value.get("item_id", 0)) if isinstance(value, dict) else int(value)
            if item_id > 0:
                echo_drops.append({"chance": 0.08, "count": 1, "item_id": item_id})
        echo_boss = dict(boss)
        echo_boss["name"] = "回响·%s" % boss.get("name", "")
        echo_boss["max_hp"] = round(float(boss.get("max_hp", 1000)) * 1.6, 1)
        echo_boss["attack"] = round(float(boss.get("attack", 10)) * 1.6, 1)
        echo_boss["exp"] = int(round(float(boss.get("exp", 100)) * 1.5))
        echo_boss["traits"] = list(dict.fromkeys(list(boss.get("traits", [])) + ["echo"]))
        echo_boss["drop_items"] = unique_drops          # 仅首杀保证
        echo_boss["echo_drop_items"] = echo_drops       # 常规 farming 掉落
        echo_boss["chapter_id"] = chapter_id
        enemies[str(echo_boss_id)] = echo_boss

        # --- 刷怪表（坐标参考剧情摆位做偏移） ---
        world_enemies = ((world.get("levels") or {}).get(str(level_id)) or {}).get("enemies") or []
        story_pos = {int(x.get("enemy_id", 0)): (float(x.get("x", 0)), float(x.get("y", 0))) for x in world_enemies}
        default_y = 700.0
        group_entries = []
        offsets = (-150.0, 0.0, 150.0)
        for gi, (gid, count) in enumerate(groups):
            px, py = story_pos.get(gid, (1800.0 + gi * 400.0, default_y))
            group_entries.append({
                "enemy_id": gid,
                "count": count,
                "x": px + offsets[gi % len(offsets)],
                "y": py,
                "scatter_x": 24.0,
                "respawn_s": 45,
            })
        elite_pos = story_pos.get(boss_id, (3000.0, default_y))
        echo_spawns[str(level_id)] = {
            "chapter_id": chapter_id,
            "chapter_base_level": base_level,
            "groups": group_entries,
            "elite": {"enemy_id": elite_id, "x": elite_pos[0] - 400.0, "y": elite_pos[1]},
            "boss": {"enemy_id": echo_boss_id, "x": elite_pos[0], "y": elite_pos[1]},
        }

        chapter = chapters.get(chapter_id)
        if isinstance(chapter, dict):
            chapter["echo_boss_enemy_id"] = echo_boss_id

    dump(ENEMIES, enemies)
    dump(CHAPTERS, chapters)
    dump(ECHO_SPAWNS, {"version": 1, "format": "frame-ronin-echo-spawns-v1", "levels": echo_spawns})
    print("备份:", backup)
    print("回响怪:", sorted(k for k in enemies if int(k) >= 8040))
    print("回响表关卡:", sorted(echo_spawns, key=int))


if __name__ == "__main__":
    main()
