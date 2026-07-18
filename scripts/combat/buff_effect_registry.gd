class_name BuffEffectRegistry
extends RefCounted

## Buff 效果类型注册表。集中声明 effect type 的元数据，
## 让 buff_config 解析与 buff_editor 表单生成统一从此消费。
## 新增 effect type 时只需在此处 register 一处。

const _DamageTags = preload("res://scripts/data/damage_tags.gd")

const STAT_OPTIONS := [
	"attack", "defense", "move_speed", "max_hp", "crit_rate", "crit_damage", "attack_speed",
	"magic_resist", "block_rate", "dodge_rate", "status_resist", "status_intensity", "skill_haste",
	"armor_pen_percent", "armor_pen_flat", "magic_pen_percent", "magic_pen_flat",
	"heal_bonus", "shield_bonus", "heal_received", "lifesteal", "reflect_rate", "abyss_cost"
]
const MODE_OPTIONS := ["add", "mul", "set"]
const DAMAGE_TYPE_OPTIONS := ["physical", "fire", "poison", "true"]
# 防御通道（与 DamageTags.CHANNELS 同源）。用于 dot effect 的 damage_channel 字段下拉。
const DAMAGE_CHANNEL_OPTIONS := _DamageTags.CHANNELS
# 伤害标签（与 DamageTags.TAGS 同源）。用于 tag_modifier effect 的 tag 字段下拉。
const DAMAGE_TAG_OPTIONS := _DamageTags.TAGS
const AFFECTS_OPTIONS := ["act", "move", "skill", "be_damaged"]
const CONTROL_TYPE_OPTIONS := ["stun", "freeze", "paralysis", "silence", "sleep", "invincible"]

## 英文枚举值 -> 中文注解。buff_editor 渲染 option / checkbox_group 时
## 会查此表，给显示文本追加 "(中文)" 后缀，metadata 仍保留英文键。
const OPTION_LABELS := {
	"stat": {
		"attack": "攻击", "defense": "防御", "move_speed": "移速",
		"max_hp": "最大生命", "crit_rate": "暴击率",
		"crit_damage": "暴击伤害", "attack_speed": "攻速",
		"magic_resist": "魔抗", "block_rate": "格挡率", "dodge_rate": "闪避率",
		"status_resist": "异常抗性", "status_intensity": "异常强度", "skill_haste": "技能急速",
		"armor_pen_percent": "%护甲穿透", "armor_pen_flat": "固定护甲穿透",
		"magic_pen_percent": "%魔法穿透", "magic_pen_flat": "固定魔法穿透",
		"heal_bonus": "治疗强度", "shield_bonus": "护盾强度",
		"heal_received": "受疗加成", "lifesteal": "吸血", "reflect_rate": "反伤率", "abyss_cost": "深渊代价",
	},
	"mode": {"add": "加算", "mul": "乘算", "set": "直接设置"},
	"damage_type": {"physical": "物理", "fire": "火焰", "poison": "毒", "true": "真实"},
	"damage_channel": _DamageTags.CHANNEL_LABELS,
	"damage_tag": _DamageTags.OPTION_LABELS,
	"tag": _DamageTags.OPTION_LABELS,  # tag_modifier effect 的 tag 字段（与 damage_tag 同源）
	"affects": {"act": "行动", "move": "移动", "skill": "施法", "be_damaged": "受击"},
	"control_type": {
		"stun": "眩晕", "freeze": "冻结", "paralysis": "麻痹",
		"silence": "沉默", "sleep": "沉睡", "invincible": "无敌",
	},
}


static func get_type_info(type_str: String) -> Dictionary:
	match type_str:
		"stat_modifier":
			return {
				"label": "属性修改",
				"fields": [
					{"name": "stat", "label": "属性", "kind": "option", "options": STAT_OPTIONS, "default": "attack"},
					{"name": "mode", "label": "模式", "kind": "option", "options": MODE_OPTIONS, "default": "add"},
					{"name": "value", "label": "数值", "kind": "float", "min": -9999.0, "max": 9999.0, "step": 0.1, "default": 10.0},
				],
			}
		"dot":
			# DoT（设计案 8.3 持续伤害快照）：
			# - damage: 固定值（旧字段，无 attack_ratio 时 fallback 用）
			# - attack_ratio: 攻击力倍率（如 0.20 = 20% 攻击力），施加时快照 snapshot_attack
			# - damage_tag / damage_channel: 接入完整伤害链路（含目标魔抗/标签克制）
			# 持续伤害默认 can_crit=false / can_dodge=false / can_block=false（设计案 8.3）
			return {
				"label": "周期伤害 (DoT)",
				"fields": [
					{"name": "interval", "label": "间隔", "kind": "float", "min": 0.0, "max": 999.0, "step": 0.1, "default": 1.0},
					{"name": "damage", "label": "固定伤害", "kind": "int", "min": 0.0, "max": 99999.0, "step": 1.0, "default": 5},
					{"name": "attack_ratio", "label": "攻击力倍率", "kind": "float", "min": 0.0, "max": 5.0, "step": 0.05, "default": 0.0},
					{"name": "damage_tag", "label": "伤害标签", "kind": "option", "options": DAMAGE_TAG_OPTIONS, "default": "slash"},
				{"name": "damage_channel", "label": "防御通道", "kind": "option", "options": DAMAGE_CHANNEL_OPTIONS, "default": "physical"},
				],
			}
		"hot":
			return {
				"label": "周期治疗 (HoT)",
				"fields": [
					{"name": "interval", "label": "间隔", "kind": "float", "min": 0.0, "max": 999.0, "step": 0.1, "default": 1.0},
					{"name": "heal", "label": "治疗", "kind": "int", "min": 0.0, "max": 99999.0, "step": 1.0, "default": 10},
				],
			}
		"shield":
			return {
				"label": "护盾",
				"fields": [
					{"name": "amount", "label": "吸收量", "kind": "int", "min": 0.0, "max": 99999.0, "step": 10.0, "default": 100},
				],
			}
		"control":
			return {
				"label": "控制效果",
				"fields": [
					{"name": "control_type", "label": "控制类型", "kind": "option", "options": CONTROL_TYPE_OPTIONS, "default": "stun"},
					{"name": "affects", "label": "影响行为", "kind": "checkbox_group", "options": AFFECTS_OPTIONS, "default": ["act"]},
				],
			}
		"tag_modifier":
			# 标签级修正（设计案 8.2 感电/标记）：
			# - vuln_bonus：目标受到该标签伤害时额外 +X%（标签易伤）
			# - armor_pen_bonus：攻击方用该标签打该目标时额外无视 X% 护甲（标签穿甲）
			# 二者均可为 0，表示该 effect 只做其中一项。
			return {
				"label": "标签修正",
				"fields": [
					{"name": "tag", "label": "伤害标签", "kind": "option", "options": DAMAGE_TAG_OPTIONS, "default": "thunder"},
					{"name": "vuln_bonus", "label": "标签易伤", "kind": "float", "min": -0.9, "max": 5.0, "step": 0.05, "default": 0.0},
					{"name": "armor_pen_bonus", "label": "标签穿甲", "kind": "float", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.0},
				],
			}
		"vulnerability_modifier":
			# 全标签易伤（设计案 8.2 侵蚀）：每层 +X% 受到所有伤害。
			# 与 tag_modifier 的区别：tag_modifier 针对单标签，vulnerability_modifier 针对所有标签。
			# value × stacks 作为 global_vulnerability 加算到 vuln_mult。
			return {
				"label": "全标签易伤",
				"fields": [
					{"name": "value", "label": "每层易伤", "kind": "float", "min": 0.0, "max": 1.0, "step": 0.01, "default": 0.01},
				],
			}
		_:
			return {}


static func get_all_types() -> Array:
	return ["stat_modifier", "dot", "hot", "shield", "control", "tag_modifier", "vulnerability_modifier"]


## 返回 option / checkbox_group 项的显示文本：英文值 + 中文注解。
## 无中文映射时回退为原值。metadata 仍存英文键，不影响 JSON 存储。
static func get_option_label(field_name: String, value: String) -> String:
	var labels: Dictionary = OPTION_LABELS.get(field_name, {})
	if labels.has(value):
		return "%s (%s)" % [value, labels[value]]
	return value


## 把原始 JSON 字典解析为运行时字典（含 tick_timer/remaining 运行时字段）
static func parse_effect(raw: Dictionary) -> Dictionary:
	var type_str := String(raw.get("type", ""))
	var parsed := {"type": type_str}
	var info := get_type_info(type_str)
	for field in info.get("fields", []):
		var fname := String(field.get("name", ""))
		var kind := String(field.get("kind", ""))
		match kind:
			"option":
				parsed[fname] = String(raw.get(fname, ""))
			"float":
				parsed[fname] = float(raw.get(fname, 0.0))
			"int":
				parsed[fname] = int(raw.get(fname, 0))
			"string":
				parsed[fname] = String(raw.get(fname, ""))
			"checkbox_group":
				var arr: Array = raw.get(fname, [])
				var arr_str: Array[String] = []
				for v in arr:
					arr_str.append(String(v))
				parsed[fname] = arr_str
	# 运行时字段（不在 schema 内，由 effect type 决定）
	match type_str:
		"dot", "hot":
			parsed["tick_timer"] = float(parsed.get("interval", 1.0))
		"shield":
			parsed["remaining"] = int(parsed.get("amount", 0))
	return parsed


## 根据 type_str 生成带默认值的 effect 字典（供 buff_editor 新增效果时使用）
static func make_default_effect(type_str: String) -> Dictionary:
	var new_effect := {"type": type_str}
	var info := get_type_info(type_str)
	for field in info.get("fields", []):
		var fname := String(field.get("name", ""))
		var kind := String(field.get("kind", ""))
		match kind:
			"checkbox_group":
				# 数组类型必须深拷贝，避免所有实例共享同一引用
				var default_arr: Array = field.get("default", [])
				var copy: Array = []
				for v in default_arr:
					copy.append(String(v))
				new_effect[fname] = copy
			"option":
				new_effect[fname] = String(field.get("default", ""))
			"float":
				new_effect[fname] = float(field.get("default", 0.0))
			"int":
				new_effect[fname] = int(field.get("default", 0))
			"string":
				new_effect[fname] = String(field.get("default", ""))
	return new_effect
