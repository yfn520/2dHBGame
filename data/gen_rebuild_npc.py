# -*- coding: utf-8 -*-
"""临时：重建任务 NPC 常驻对话图为多任务路由图，写入 dialogues.json。
覆盖 npc_9001..9009, npc_9016；保留 npc_9010..9015 及全部 quest_* 图。
剧情对白复用 quest_100X 图中对应阶段节点的 text/speaker。
"""
import json, os, collections
DATA = os.path.dirname(__file__)

def load(n):
    with open(os.path.join(DATA, n), "r", encoding="utf-8") as f:
        return json.load(f)

def dump(o, n):
    with open(os.path.join(DATA, n), "w", encoding="utf-8") as f:
        json.dump(o, f, ensure_ascii=False, indent="\t")

quests = load("quests.json")
dialogues = load("dialogues.json")
bindings = load("npc_interaction_bindings.json")["bindings"]

# NPC 名
NPC_NAME = {9001:"霍雷克",9002:"柏婶",9003:"老邮差洛伯",9004:"守门兵遗响",9005:"十七号",
            9006:"埃蒙",9007:"铁壳蟹",9008:"多恩",9009:"诺瓦",9016:"伊莱"}

# 每个 NPC 负责的任务（按 quests giver 提取，保持 id 升序）
by_npc = collections.OrderedDict()
for qid in sorted(quests, key=int):
    g = int(quests[qid].get("giver_npc_id", 0))
    if g in NPC_NAME:
        by_npc.setdefault(g, []).append(int(qid))

def quest_graph(qid):
    return dialogues.get("quest_%d" % qid, {}).get("nodes", {})

def pick_text(qid, which):
    """从 quest 图提取对白：接取=opening(first line), 途中=第二个 line, 交付=delivery/末 line。"""
    nodes = quest_graph(qid)
    lines = [ (nid,d) for nid,d in nodes.items() if d.get("type")=="line" and d.get("text") ]
    if which == "inactive":
        return lines[0][1] if lines else None
    if which == "active":
        return lines[1][1] if len(lines) > 1 else (lines[0][1] if lines else None)
    if which == "ready":
        # 优先 delivery 节点，否则最后一个 line
        for nid in ("delivery","end"):
            if nid in nodes and nodes[nid].get("text"):
                return nodes[nid]
        return lines[-1][1] if lines else None
    return None

def intent_for(npc_id, qid, kind):
    """从 bindings 找该 npc+quest 的接/交 intent_key。"""
    key_kinds = {"accept":0, "turn_in":0}
    for bk, bv in bindings.items():
        npc_part, intent = bk.split(".", 1)
        if npc_part == "npc_%d" % npc_id and int(bv.get("quest_id",0)) == qid:
            if bv.get("type") == "start_quest":
                key_kinds["accept"] = intent
            elif bv.get("type") == "turn_in_quest":
                key_kinds["turn_in"] = intent
    return key_kinds

def make_node(typ, speaker, text, chapter, qid, role, next_id="", choices=None, routes=None, x=0, y=0):
    return {
        "type": typ,
        "speaker": speaker,
        "text": text,
        "text_template": text,
        "next_id": next_id,
        "default_next": "",
        "choices": choices or [],
        "routes": routes or [],
        "conditions": [],
        "actions": [],
        "story_layer": "COMMON",
        "required_lead_hero_id": 0,
        "required_hero_id": 0,
        "required_event_state": "",
        "chapter_id": chapter,
        "quest_binding": {"quest_id": qid, "role": role} if qid else {},
        "editor": {"x": x, "y": y}
    }

for npc_id, qlist in by_npc.items():
    nodes = {}
    routes = []  # router routes
    y = 0
    for qid in qlist:
        qcfg = quests[str(qid)]
        chapter = qcfg.get("chapter_id", "")
        title = qcfg.get("title", "")
        intents = intent_for(npc_id, qid, None)

        # 接取
        d = pick_text(qid, "inactive")
        sp = d.get("speaker","") or NPC_NAME[npc_id]
        tx = d.get("text","")
        nodes["q%d_inactive_greeting" % qid] = make_node("line", sp, tx, chapter, qid, "inactive", "q%d_inactive_choice" % qid, x=100, y=y)
        acc_intent = intents["accept"]
        nodes["q%d_inactive_choice" % qid] = make_node("branch", "", "", chapter, qid, "inactive",
            choices=[
                {"id":"accept_%d" % qid, "intent_key": acc_intent, "text":"我愿意接下「%s」。" % title, "next_id":"q%d_inactive_end" % qid, "text_template":"我愿意接下「%s」。" % title},
                {"id":"leave_%d" % qid, "text":"我暂时不接，先告辞。", "next_id":"q%d_inactive_end" % qid, "text_template":"我暂时不接，先告辞。"},
            ], x=320, y=y)
        nodes["q%d_inactive_end" % qid] = make_node("end", "", "", chapter, qid, "inactive", x=540, y=y)

        # 途中
        d = pick_text(qid, "active")
        sp = d.get("speaker","") or NPC_NAME[npc_id]
        tx = d.get("text","")
        nodes["q%d_active" % qid] = make_node("line", sp, tx, chapter, qid, "active", "q%d_active_end" % qid, x=100, y=y+120)
        nodes["q%d_active_end" % qid] = make_node("end", "", "", chapter, qid, "active", x=320, y=y+120)

        # 交付
        d = pick_text(qid, "ready")
        sp = d.get("speaker","") or NPC_NAME[npc_id]
        tx = d.get("text","")
        nodes["q%d_ready_greeting" % qid] = make_node("line", sp, tx, chapter, qid, "ready", "q%d_ready_choice" % qid, x=100, y=y+240)
        turn_intent = intents["turn_in"]
        nodes["q%d_ready_choice" % qid] = make_node("branch", "", "", chapter, qid, "ready",
            choices=[
                {"id":"turnin_%d" % qid, "intent_key": turn_intent, "text":"确认交付「%s」。" % title, "next_id":"q%d_ready_end" % qid, "text_template":"确认交付「%s」。" % title},
                {"id":"hold_%d" % qid, "text":"我稍后再来交付。", "next_id":"q%d_ready_end" % qid, "text_template":"我稍后再来交付。"},
            ], x=320, y=y+240)
        nodes["q%d_ready_end" % qid] = make_node("end", "", "", chapter, qid, "ready", x=540, y=y+240)

        # router routes：inactive → active → ready
        routes.append({"conditions":[{"type":"quest_state","quest_id":qid,"state":"inactive"}], "next_id":"q%d_inactive_greeting" % qid})
        routes.append({"conditions":[{"type":"quest_state","quest_id":qid,"state":"active"}], "next_id":"q%d_active" % qid})
        routes.append({"conditions":[{"type":"quest_state","quest_id":qid,"state":"ready"}], "next_id":"q%d_ready_greeting" % qid})
        y += 360

    # 全部完成后的闲聊
    nodes["completed_greeting"] = make_node("line", NPC_NAME[npc_id], "（你走过，他点了点头。）后续若有事，再找我。", "chapter_1", qlist[0], "completed", "completed_end", x=100, y=y)
    nodes["completed_end"] = make_node("end", "", "", "chapter_1", qlist[0], "completed", x=320, y=y)
    routes.append({"conditions":[], "next_id":"completed_greeting"})

    # router 节点
    nodes["quest_state_router"] = {
        "type": "branch", "speaker": "", "text": "", "text_template": "",
        "next_id": "", "default_next": "completed_greeting",
        "choices": [], "routes": routes, "conditions": [], "actions": [],
        "story_layer": "COMMON", "required_lead_hero_id": 0, "required_hero_id": 0,
        "required_event_state": "", "chapter_id": quests[str(qlist[0])].get("chapter_id",""),
        "quest_binding": {}, "editor": {"x": 0, "y": 0}
    }

    dialogues["npc_%d" % npc_id] = {
        "entry_node": "quest_state_router",
        "chapter_id": quests[str(qlist[0])].get("chapter_id",""),
        "story_node_id": "",
        "nodes": nodes
    }
    print("rebuilt npc_%d (%s) -> quests %s" % (npc_id, NPC_NAME[npc_id], qlist))

dump(dialogues, "dialogues.json")
print("done")