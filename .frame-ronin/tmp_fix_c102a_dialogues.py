# -*- coding: utf-8 -*-
"""C1-02-A godot 侧数据同步（dialogues.json task_c1_02_a），与编译产物语义一致：
1. S01 stage_exit 加 close_dialogue（伊莱对话 D02 后收束）
2. S03 裸 objective 门补 objectiveKey=kill_8001 + close_dialogue，删除编译器追加的重复等待门
3. turn_in_entries 9016: 44800 -> 37720（交付播 S04 战后收尾对白）
4. 新增 autoplay_segments（伊莱对话收尾后从 9520 接 S02 途中过场）
"""
import io
import json

path = r"e:\g_selfcustom\FrameRonin-main\hengban-2\data\dialogues.json"
with io.open(path, encoding="utf-8") as f:
    data = json.load(f)

tl = data["task_c1_02_a"]
clips = tl["clips"]
assert tl.get("format") == "timeline"

# 1+2: 事件片段改造
kept = []
for clip in clips:
    cid = clip.get("id", "")
    if cid == "C1-02-A-S03_objective_003":
        # 编译器追加的重复等待门（与裸门同 startMs，数组末尾错位）：裸门已补 key，删除
        continue
    if cid == "C1-02-A-S01_event_004":
        clip["actions"] = [{"type": "close_dialogue"}]
    if cid == "C1-02-A-S03_event_003":
        clip["objectiveKey"] = "kill_8001"
        clip["questId"] = 21020
        clip["actions"] = [{"type": "close_dialogue"}]
    kept.append(clip)
tl["clips"] = kept

# 3: 交付入口 -> S04 起点（播战后收尾对白）
assert tl.get("turn_in_entries") == {"9016": 44800}
tl["turn_in_entries"] = {"9016": 37720}

# 4: 自动播放段（S02 起点 9520，伊莱对话收尾触发）
tl["autoplay_segments"] = [{"npc_id": 9016, "entry_ms": 9520}]

with io.open(path, "w", encoding="utf-8", newline="") as f:
    json.dump(data, f, ensure_ascii=False, indent="\t")
    f.write("\n")

# 验证
with io.open(path, encoding="utf-8") as f:
    check = json.load(f)
ctl = check["task_c1_02_a"]
print("clip count:", len(ctl["clips"]))
for i, c in enumerate(ctl["clips"]):
    if c.get("kind") == "event":
        print(i, c.get("startMs"), c.get("eventType"), "key=", c.get("objectiveKey"), "actions=", c.get("actions"))
print("turn_in_entries:", ctl["turn_in_entries"])
print("autoplay_segments:", ctl["autoplay_segments"])
print("entries:", ctl.get("entries"))
# startMs 唯一性（避免运行时排序歧义）
ms = [c.get("startMs", 0) for c in ctl["clips"]]
dups = sorted({m for m in ms if ms.count(m) > 1})
print("duplicate startMs:", dups)
print("OK")
