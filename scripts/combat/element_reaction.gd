class_name ElementReaction
extends RefCounted

## 元素反应系统（设计案第9章）。
## 同一次伤害最多触发一种反应（设计案 9.2.4），按 REACTIONS 数组顺序匹配第一个。
## 反应附加伤害不再施加异常积累、不再触发反应（避免无限循环）。
##
## 反应类型：
## - damage_boost: 主伤害 +X%（注入 vuln_mult，在 DamageCalculator 之前应用）
## - buildup_boost: 临时提升异常 buff 命中率 +X%（透传到 apply_buff_with_pity，叠加到 actual_chance）
## - consume_both: 消耗前置 buff + 当前攻击的异常积累，施加 debuff
## - armor_pen_bonus: 主伤害额外无视 X% 护甲（注入 tag_armor_pen）
## - shield_damage_boost: 对护盾伤害 +X%（护盾吸收前应用）
## - consume_stacks: 消耗前置 buff 的层数，每层造成 X% 攻击力附加伤害

const _DamageTags = preload("res://scripts/data/damage_tags.gd")

## 反应定义：前置状态 + 后续攻击 → 反应效果
const REACTIONS := [
	{
		"pre_status": "wet",          # 潮湿 buff 10022
		"attack_tag": "thunder",      # 雷电打潮湿
		"effect": {"type": "damage_boost", "value": 0.25},
	},
	{
		"pre_status": "wet",
		"attack_tag": "frost",        # 冰霜打潮湿 → 冻结积累 +50%
		"effect": {"type": "buildup_boost", "value": 0.50, "status": "freeze"},
	},
	{
		"pre_status": "burn",         # 燃烧 buff 10002
		"attack_tag": "frost",        # 冰霜打燃烧 → 消耗两者，护甲魔抗 -15% 4秒
		"effect": {"type": "consume_both", "debuff_id": 10023, "debuff_stacks": 1},
	},
	{
		"pre_status": "mark",         # 标记 buff 10019
		"attack_tag": "pierce",       # 穿刺打标记 → 额外无视 20% 护甲
		"effect": {"type": "armor_pen_bonus", "value": 0.20},
	},
	{
		"pre_status": "shield",       # 护盾 buff（任意 shield effect）
		"attack_tag": "blunt",        # 钝击打护盾 → 护盾伤害 +30%
		"effect": {"type": "shield_damage_boost", "value": 0.30},
	},
	{
		"pre_status": "shield",
		"attack_tag": "thunder",      # 雷电打护盾 → 护盾伤害 +30%
		"effect": {"type": "shield_damage_boost", "value": 0.30},
	},
	{
		"pre_status": "erosion",      # 侵蚀 buff 10021
		"attack_tag": "holy",         # 神圣打侵蚀 → 消耗最多3层，每层 60% 攻击力神圣伤害
		"effect": {"type": "consume_stacks", "max_stacks": 3, "per_stack_damage_ratio": 0.6},
	},
]

## buff_id → 反应前置标识（用于反查目标 active buff 是否含前置状态）
const PRE_STATUS_BUFF_ID := {
	"wet": 10022,
	"burn": 10002,
	"mark": 10019,
	"erosion": 10021,
	# shield 不是 buff_id，而是检测 effect type
}


## 尝试触发元素反应。
## target: 目标节点（用于查询 active buff）
## attack_tag: 当前攻击的标签，V0.2 可同时传入 [resolved_element, physical_tag]
## 返回反应结果 Dictionary：
##   {"triggered": bool, "effect": {...}, "pre_status": "...", "consumed_buff_id": int}
## 调用方根据 effect.type 决定如何应用（伤害修正/消耗 buff/附加伤害）
static func try_reaction(target: Node, attack_tag: Variant) -> Dictionary:
	var bm = _resolve_buff_manager(target)
	if bm == null or not bm.has_method("get_active_buffs"):
		return {"triggered": false}
	# 构建 target 的 buff_id → buff 映射
	var buff_map: Dictionary = {}
	var has_shield := false
	var attack_tags: Array = attack_tag if attack_tag is Array else [str(attack_tag)]
	for buff in bm.get_active_buffs():
		buff_map[int(buff.buff_id)] = buff
		if buff.get_shield_effects().size() > 0:
			has_shield = true
	# 按 REACTIONS 顺序匹配第一个可触发的
	for reaction in REACTIONS:
		var pre := str(reaction["pre_status"])
		var atk := str(reaction["attack_tag"])
		if not attack_tags.has(atk):
			continue
		# 检查前置状态
		if pre == "shield":
			if not has_shield:
				continue
		else:
			var pre_buff_id: int = PRE_STATUS_BUFF_ID.get(pre, 0)
			if pre_buff_id == 0 or not buff_map.has(pre_buff_id):
				continue
		# 匹配成功
		return {
			"triggered": true,
			"pre_status": pre,
			"effect": reaction["effect"],
			"target": target,
		}
	return {"triggered": false}


## 消耗前置 buff（反应触发后调用）。
## 对于 consume_both / consume_stacks 类型，移除或减层对应 buff。
static func consume_pre_buff(target: Node, reaction_result: Dictionary) -> void:
	if not bool(reaction_result.get("triggered", false)):
		return
	var effect: Dictionary = reaction_result.get("effect", {})
	var etype := str(effect.get("type", ""))
	if etype != "consume_both" and etype != "consume_stacks":
		return
	var pre := str(reaction_result.get("pre_status", ""))
	if pre == "shield":
		return  # shield 不消耗（仅触发反应）
	var pre_buff_id: int = PRE_STATUS_BUFF_ID.get(pre, 0)
	if pre_buff_id == 0:
		return
	var bm = _resolve_buff_manager(target)
	if bm == null:
		return
	if etype == "consume_both":
		# 完全移除前置 buff
		if bm.has_method("remove_buff_by_id"):
			bm.remove_buff_by_id(pre_buff_id)
	elif etype == "consume_stacks":
		var max_consume := int(effect.get("max_stacks", 1))
		if bm.has_method("remove_buff_stacks"):
			bm.remove_buff_stacks(pre_buff_id, max_consume)
		elif bm.has_method("remove_buff_by_id"):
			bm.remove_buff_by_id(pre_buff_id)


static func _resolve_buff_manager(target: Node):
	if target == null:
		return null
	if target.has_method("get_buff_manager"):
		return target.get_buff_manager()
	if "combat" in target:
		var combat_node: Variant = target.get("combat")
		if combat_node is Node and is_instance_valid(combat_node) and combat_node.has_method("get_buff_manager"):
			return combat_node.get_buff_manager()
	var combat_node := target.get_node_or_null("CombatComponent")
	return combat_node.get_buff_manager() if combat_node != null and combat_node.has_method("get_buff_manager") else null
