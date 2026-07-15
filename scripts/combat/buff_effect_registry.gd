class_name BuffEffectRegistry
extends RefCounted

## Buff 效果类型注册表。集中声明 5 种 effect type 的元数据，
## 让 buff_config 解析与 buff_editor 表单生成统一从此消费。
## 新增 effect type 时只需在此处 register 一处。

const STAT_OPTIONS := ["attack", "defense", "move_speed", "max_hp", "crit_rate", "crit_damage", "attack_speed"]
const MODE_OPTIONS := ["add", "mul", "set"]
const DAMAGE_TYPE_OPTIONS := ["physical", "fire", "poison", "true"]
const AFFECTS_OPTIONS := ["act", "move", "skill", "be_damaged"]


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
			return {
				"label": "周期伤害 (DoT)",
				"fields": [
					{"name": "interval", "label": "间隔", "kind": "float", "min": 0.0, "max": 999.0, "step": 0.1, "default": 1.0},
					{"name": "damage", "label": "伤害", "kind": "int", "min": 0.0, "max": 99999.0, "step": 1.0, "default": 5},
					{"name": "damage_type", "label": "类型", "kind": "option", "options": DAMAGE_TYPE_OPTIONS, "default": "physical"},
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
					{"name": "control_type", "label": "控制类型", "kind": "string", "default": "stun"},
					{"name": "affects", "label": "影响行为", "kind": "checkbox_group", "options": AFFECTS_OPTIONS, "default": ["act"]},
				],
			}
		_:
			return {}


static func get_all_types() -> Array:
	return ["stat_modifier", "dot", "hot", "shield", "control"]


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
