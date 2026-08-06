# -*- coding: utf-8 -*-
"""临时：校验重建后的 NPC 常驻图 + bindings 匹配。"""
import json, os, sys
DATA = os.path.dirname(__file__)

def load(n):
    with open(os.path.join(DATA, n), "r", encoding="utf-8") as f:
        return json.load(f)

dialogues = load("dialogues.json")
quests = load("quests.json")
bindings = load("npc_interaction_bindings.json")["bindings"]
errors = []
quest_ids = set(quests.keys())

# bindings 引用的 intent 必须能在对应 npc 图的 choice 中找到
for bk, bv in bindings.items():
    dlg, intent = bk.split(".", 1)
    if not dlg.startswith("npc_"):
        continue
    dg = dialogues.get(dlg)
    if dg is None:
        errors.append("bindings %s 但对话图 %s 不存在" % (bk, dlg)); continue
    found = False
    for nd in dg.get("nodes", {}).values():
        for c in nd.get("choices", []):
            if c.get("intent_key") == intent:
                found = True
    if not found:
        errors.append("bindings %s -> intent '%s' 在 %s 图中无对应 choice" % (bk, intent, dlg))
    if str(bv.get("quest_id")) not in quest_ids:
        errors.append("bindings %s 指向不存在任务 %s" % (bk, bv.get("quest_id")))

# 每个 npc 图：entry_node 存在、所有 next 指向存在、end 可达
for dkey, dg in dialogues.items():
    if not dkey.startswith("npc_"):
        continue
    nodes = dg.get("nodes", {})
    entry = dg.get("entry_node")
    if entry not in nodes:
        errors.append("%s entry_node %s 不存在" % (dkey, entry))
    for nid, nd in nodes.items():
        nxt = nd.get("next_id","")
        if nxt and nxt not in nodes:
            errors.append("%s/%s next -> %s 不存在" % (dkey, nid, nxt))
        for c in nd.get("choices", []):
            cn = c.get("next_id","")
            if cn and cn not in nodes:
                errors.append("%s/%s choice -> %s 不存在" % (dkey, nid, cn))
        for r in nd.get("routes", []):
            rn = r.get("next_id","")
            if rn and rn not in nodes:
                errors.append("%s/%s route -> %s 不存在" % (dkey, nid, rn))
    # 是否有 end
    has_end = any(nd.get("type")=="end" for nd in nodes.values())
    if not has_end:
        errors.append("%s 无 end 节点" % dkey)

if errors:
    print("ERRORS (%d):" % len(errors))
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("ALL PASSED: bindings=%d npc graphs=%d" % (len(bindings), sum(1 for k in dialogues if k.startswith('npc_'))))