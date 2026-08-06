# -*- coding: utf-8 -*-
"""临时：提取 quest_ 对话图概况 + quest giver/turn_in 映射，用于重建 NPC 常驻图。"""
import json, os
DATA = os.path.dirname(__file__)

def load(n):
    with open(os.path.join(DATA, n), "r", encoding="utf-8") as f:
        return json.load(f)

quests = load("quests.json")
dialogues = load("dialogues.json")

print("=== quest giver/turn_in ===")
for qid in sorted(quests, key=int):
    q = quests[qid]
    print("%s %s | giver=%s turnin=%s | kind=%s" % (qid, q.get("title",""), q.get("giver_npc_id"), q.get("turn_in_npc_id"), q.get("quest_kind")))

print("\n=== quest_ 对话图概况 ===")
for dkey, dg in sorted(dialogues.items()):
    if not dkey.startswith("quest_"):
        continue
    nodes = dg.get("nodes", {})
    chain = []
    for nid, nd in nodes.items():
        t = nd.get("type","")
        sp = nd.get("speaker","")
        tx = nd.get("text","")
        if len(tx) > 36: tx = tx[:33] + "..."
        chain.append("%s[%s:%s]%s" % (nid, t, sp, tx))
    print("%s | entry=%s | %d nodes" % (dkey, dg.get("entry_node"), len(nodes)))
    for c in chain:
        print("   ", c)