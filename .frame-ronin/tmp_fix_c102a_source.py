# -*- coding: utf-8 -*-
"""C1-02-A 网页侧数据修复（task_scripts_v2.json）：
1. S01/S03 阶段补 objectiveIds
2. S02 阶段加 runtimeBinding.autoplayAfterTalkNpcId（对话收尾自动过场触发器）
3. S01 stage_exit 片段加 close_dialogue（伊莱对话在 D02 后收束，不再内联播途中段）
4. S03 裸 objective 门补 objectiveKey=kill_8001 + close_dialogue（拆除死锁雷，兼作途中过场收束点）
"""
import io

path = r"e:\g_selfcustom\FrameRonin-main\hengban-2\data\task_scripts_v2.json"
with io.open(path, encoding="utf-8") as f:
    lines = f.readlines()

CLIP_IND = "\t" * 8      # 片段属性缩进
ACT_IND = "\t" * 9       # actions 数组元素
ACT_PROP = "\t" * 10     # 动作属性
STAGE_IND = "\t" * 5     # 阶段属性

def expect(lineno, fragment):
    actual = lines[lineno - 1]
    assert fragment in actual, "line %d mismatch: %r" % (lineno, actual)
    return actual

# --- 自底向上编辑 ---

# 5) 7861: S03_event_003 片段末尾加 objectiveKey + close_dialogue
expect(7861, '"nodeId": "C1-02-A.D06"')
assert lines[7861 - 1].rstrip().endswith('"C1-02-A.D06"')  # 末属性无逗号
lines[7861 - 1] = lines[7861 - 1].replace('"C1-02-A.D06"', '"C1-02-A.D06",')
lines.insert(7861, "".join([
    CLIP_IND + '"objectiveKey": "kill_8001",\n',
    CLIP_IND + '"actions": [\n',
    ACT_IND + '{\n',
    ACT_PROP + '"type": "close_dialogue"\n',
    ACT_IND + '}\n',
    CLIP_IND + ']\n',
]))

# 4) 7788: S03 objectiveIds
expect(7788, '"objectiveIds": []')
lines[7788 - 1] = STAGE_IND + '"objectiveIds": [\n' + STAGE_IND + '\t"kill_8001"\n' + STAGE_IND + '],\n'

# 3) 7504: S02 objectiveIds 保持空，追加 runtimeBinding
expect(7504, '"objectiveIds": []')
lines.insert(7504, "".join([
    STAGE_IND + '"runtimeBinding": {\n',
    STAGE_IND + '\t"autoplayAfterTalkNpcId": 9016\n',
    STAGE_IND + '},\n',
]))

# 2) 7473: S01_event_004 加 close_dialogue（伊莱段收束点）
expect(7473, '"nextStageId": "C1-02-A-S02"')
assert lines[7473 - 1].rstrip().endswith('"C1-02-A-S02"')
lines[7473 - 1] = lines[7473 - 1].replace('"C1-02-A-S02"', '"C1-02-A-S02",')
lines.insert(7473, "".join([
    CLIP_IND + '"actions": [\n',
    ACT_IND + '{\n',
    ACT_PROP + '"type": "close_dialogue"\n',
    ACT_IND + '}\n',
    CLIP_IND + ']\n',
]))

# 1) 7387: S01 objectiveIds
expect(7387, '"objectiveIds": []')
lines[7387 - 1] = STAGE_IND + '"objectiveIds": [\n' + STAGE_IND + '\t"talk_9020",\n' + STAGE_IND + '\t"talk_9016"\n' + STAGE_IND + '],\n'

with io.open(path, "w", encoding="utf-8", newline="") as f:
    f.writelines(lines)

# 验证 JSON 合法
import json
with io.open(path, encoding="utf-8") as f:
    data = json.load(f)
task = [t for t in data["tasks"] if t.get("id") == "C1-02-A"][0]
for st in task["stages"]:
    print(st["id"], "objectiveIds=", st["objectiveIds"], "runtimeBinding=", st.get("runtimeBinding"))
    for c in st["performance"]["clips"]:
        if c.get("kind") == "event":
            print("   ", c.get("id"), c.get("eventType"), "objectiveKey=", c.get("objectiveKey"), "actions=", c.get("actions"))
print("OK")
