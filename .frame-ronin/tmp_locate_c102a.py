# -*- coding: utf-8 -*-
"""一次性工具：定位 C1-02-A 在 task_scripts_v2.json 中的关键行（只读，不修改）"""
import io

path = r"e:\g_selfcustom\FrameRonin-main\hengban-2\data\task_scripts_v2.json"
lines = io.open(path, encoding="utf-8").readlines()

start = None
for i, l in enumerate(lines):
    if l.strip() == '"id": "C1-02-A",':
        start = i
        break
assert start is not None

# 任务块结束：下一个同级 "id": "C1-02-B" 之前
end = len(lines)
for j in range(start + 1, len(lines)):
    if lines[j].strip().startswith('"id": "C1-02-B"'):
        end = j
        break

print("task block:", start + 1, "-", end + 1)
for i in range(start, end):
    s = lines[i].strip()
    hit = (
        '"objectiveIds"' in s
        or '"runtimeBinding"' in s
        or s in ('"type": "交互",', '"type": "战斗",', '"type": "途中",')
        or '"id": "C1-02-A-S01_event_004"' in s
        or '"id": "C1-02-A-S03_event_003"' in s
        or '"sourceNodeId": "D06"' in s
        or '"sourceNodeId": "D07"' in s
        or ('"id": "C1-02-A-S0' in s and '"stage' not in s)
    )
    if hit:
        print(i + 1, lines[i].rstrip())
