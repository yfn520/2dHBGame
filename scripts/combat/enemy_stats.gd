class_name EnemyStats
extends BaseCombatStats
## 怪物属性对象，接口与 CharacterStats 一致，供 CombatComponent 使用。
## 从 enemies.json 读取属性，一次性构造不可重算。

var _config: Dictionary = {}
## 目标等级用于 DamageCalculator 的 K = 100 + 20 × level。
var level: int = 1
## 异常触发阈值类型：normal / elite / boss。
var status_unit_type: String = "normal"
## 敌人特征列表（设计案第10章），由 enemies.json 的 traits 字段提供
var traits: Array = []
## 基础元素抗性 + 特征/常驻修正 + 当前活动阶段修正。
var effective_element_resist_rating: Dictionary = {}
var active_phase_rule: Dictionary = {}
## 普通 0.35、明确精英 0.40、Boss 0.45、Boss 活动特殊阶段 0.50。
var element_resist_cap: float = 0.35


func _init(cfg: Dictionary) -> void:
	# 先设置默认值（enemies.json 可能缺字段），再让基类 recalculate 覆盖
	max_hp = 50
	attack = 1
	defense = 0
	move_speed = 80.0
	crit_rate = 0.0
	crit_damage = 1.5
	attack_speed = 1.0
	_config = cfg
	level = maxi(1, int(cfg.get("level", cfg.get("unit_level", 1))))
	status_unit_type = _resolve_status_unit_type(cfg)
	# 读取敌人特征（默认空数组）
	var raw_traits = cfg.get("traits", [])
	if raw_traits is Array:
		for t in raw_traits:
			traits.append(str(t))
	recalculate(false)
	# 应用特征的护甲/魔抗修正（设计案 10.1）
	var armor_mod := EnemyTraits.get_combined_armor_modifier(traits)
	var mr_mod := EnemyTraits.get_combined_magic_resist_modifier(traits)
	defense += int(round(armor_mod))
	magic_resist += int(round(mr_mod))
	# 应用 high_dodge 特征：dodge_rate +0.30（设计案 10.1）
	if traits.has("high_dodge"):
		dodge_rate = clampf(dodge_rate + 0.30, 0.0, 0.35)
	# 应用 fast 特征：attack_speed ×1.3、move_speed ×1.3（设计案 10.1）
	if traits.has("fast"):
		attack_speed = clampf(attack_speed * 1.3, 0.1, 2.5)
		move_speed *= 1.3
	refresh_effective_element_resistance()


func _get_base_stats_dict() -> Dictionary:
	return _config


func refresh_effective_element_resistance() -> void:
	effective_element_resist_rating = element_resist_rating.duplicate(true)
	# element_resist_rating_modifiers 是配置层已解析的特征/常驻修正入口。
	BaseCombatStats._add_element_map(effective_element_resist_rating, element_resist_rating_modifiers)
	active_phase_rule = {}
	var has_selected_phase := not active_phase_rule_id.is_empty()
	for rule_value in phase_rules:
		if not rule_value is Dictionary:
			continue
		var rule: Dictionary = rule_value
		if has_selected_phase and str(rule.get("id", "")) != active_phase_rule_id:
			continue
		if not has_selected_phase and not bool(rule.get("active", false)):
			continue
		active_phase_rule = rule.duplicate(true)
		BaseCombatStats._add_element_map(effective_element_resist_rating, rule.get("element_resist_rating_modifiers", {}))
		break
	var is_boss := status_unit_type == "boss"
	var is_elite := status_unit_type == "elite"
	if is_boss and not active_phase_rule.is_empty():
		element_resist_cap = 0.50
	elif is_boss:
		element_resist_cap = 0.45
	elif is_elite:
		element_resist_cap = 0.40
	else:
		element_resist_cap = 0.35


static func _resolve_status_unit_type(config: Dictionary) -> String:
	if config.has("status_unit_type") or config.has("statusUnitType"):
		return StatusSystem.normalize_unit_type(config.get("status_unit_type", config.get("statusUnitType", "normal")))
	var raw_traits: Array = config.get("traits", []) if config.get("traits", []) is Array else []
	var role := str(config.get("unit_role", "")).to_lower()
	var rank := str(config.get("enemy_rank", config.get("rank", role))).to_lower()
	if bool(config.get("is_boss", false)) or raw_traits.has("boss") or role in ["boss", "章节boss"]:
		return "boss"
	if bool(config.get("is_elite", false)) or raw_traits.has("elite") or rank in ["elite", "精英"]:
		return "elite"
	return "normal"
