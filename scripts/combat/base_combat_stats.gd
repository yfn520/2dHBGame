class_name BaseCombatStats
extends RefCounted
## 战斗属性基类：承载 8 个战斗属性 + is_alive + recalculate 模板方法。
## 子类通过 override _get_base_stats_dict / _get_equipped_items / _get_stored_hp / _on_recalculated
## 提供各自的数据源（构造 dict / GameRegistry 单例 / 注入引用）。

const ELEMENT_ALIASES := {
	"none": "none",
	"fire": "fire",
	"frost": "frost",
	"lightning": "lightning",
	"thunder": "lightning",
	"holy": "holy",
	"poison": "poison",
	"abyss": "abyss",
	"火焰": "fire",
	"冰霜": "frost",
	"雷电": "lightning",
	"神圣": "holy",
	"毒素": "poison",
	"深渊": "abyss",
	"无": "none",
}

var max_hp: int = 0
var hp: int = 0
var attack: int = 0
var defense: int = 0
var move_speed: float = 0.0
var crit_rate: float = 0.0
var crit_damage: float = 1.5
var attack_speed: float = 1.0
# 设计案第3章 MVP 属性扩展
var magic_resist: int = 0           # 魔抗
var block_rate: float = 0.0         # 格挡率（0~0.6）
var dodge_rate: float = 0.0         # 闪避率（0~0.35）
var status_resist: float = 0.0      # 异常抗性（0~1.0）
var status_intensity: float = 0.0    # 异常强度（攻击方，0~2.0，放大施加的 buildup）
var status_unit_type: String = "normal" # normal / elite / boss，决定异常触发阈值
var skill_haste: float = 0.0        # 技能急速
var armor_pen_percent: float = 0.0  # %护甲穿透（0~0.5）
var armor_pen_flat: int = 0         # 固定护甲穿透
var magic_pen_percent: float = 0.0  # %魔法穿透（0~0.5）
var magic_pen_flat: int = 0         # 固定魔法穿透
var heal_bonus: float = 0.0         # 治疗强度（加算乘区）
var shield_bonus: float = 0.0       # 护盾强度（加算乘区）
var heal_received: float = 0.0      # 受疗加成（0~1.0）
var lifesteal: float = 0.0          # 吸血（0~0.2）
var reflect_rate: float = 0.0       # 反伤率（0~0.5，反伤上限 8% 攻击者最大生命）
var abyss_cost: float = 0.0         # 深渊装备代价：每秒给自己施加的侵蚀 buildup（设计案 4.3）
# V0.2 元素与单位规则字段。数组/字典在每次 recalculate 时重新构造，避免重复累计。
var primary_element: String = "none"
var element_damage_bonus_sources: Array = []
var element_resist_rating: Dictionary = {}
var element_penetration_rating: Dictionary = {}
var tag_vulnerability: Dictionary = {}
var element_resist_rating_modifiers: Dictionary = {}
var phase_rules: Array = []
var active_phase_rule_id: String = ""
var active_condition_ids: Array = []
var element_relation_matrix: Dictionary = {}


func is_alive() -> bool:
	return hp > 0


## 模板方法：子类提供基础 dict + 装备列表 + stored hp，基类统一算最终值与 hp 封顶。
## 用当前字段值作为 fallback，子类可在 init/setup 中设置默认值。
func recalculate(preserve_current_hp: bool = true) -> void:
	var base_stats: Dictionary = _get_base_stats_dict()
	var equipped_items: Array = _get_equipped_items()

	max_hp = int(base_stats.get("max_hp", max_hp))
	attack = int(base_stats.get("attack", attack))
	defense = int(_first_value(base_stats, ["defense", "armor"], defense))
	move_speed = float(base_stats.get("move_speed", move_speed))
	crit_rate = float(base_stats.get("crit_rate", crit_rate))
	crit_damage = float(base_stats.get("crit_damage", crit_damage))
	attack_speed = float(base_stats.get("attack_speed", attack_speed))
	# 设计案第3章 MVP 属性扩展
	magic_resist = int(base_stats.get("magic_resist", magic_resist))
	block_rate = float(base_stats.get("block_rate", block_rate))
	dodge_rate = float(base_stats.get("dodge_rate", dodge_rate))
	status_resist = float(base_stats.get("status_resist", status_resist))
	status_intensity = float(_first_value(base_stats, ["status_intensity", "statusPower"], status_intensity))
	status_unit_type = StatusSystem.normalize_unit_type(_first_value(base_stats, ["status_unit_type", "statusUnitType"], status_unit_type))
	skill_haste = float(base_stats.get("skill_haste", skill_haste))
	armor_pen_percent = float(base_stats.get("armor_pen_percent", armor_pen_percent))
	armor_pen_flat = int(base_stats.get("armor_pen_flat", armor_pen_flat))
	magic_pen_percent = float(base_stats.get("magic_pen_percent", magic_pen_percent))
	magic_pen_flat = int(base_stats.get("magic_pen_flat", magic_pen_flat))
	heal_bonus = float(_first_value(base_stats, ["heal_bonus", "healingPower"], heal_bonus))
	shield_bonus = float(_first_value(base_stats, ["shield_bonus", "shieldPower"], shield_bonus))
	heal_received = float(_first_value(base_stats, ["heal_received", "receivedHealing"], heal_received))
	lifesteal = float(base_stats.get("lifesteal", lifesteal))
	reflect_rate = float(base_stats.get("reflect_rate", reflect_rate))
	abyss_cost = float(base_stats.get("abyss_cost", abyss_cost))
	primary_element = _normalize_element_id(_first_value(base_stats, ["primary_element", "primaryElement"], "none"))
	element_damage_bonus_sources = _normalize_element_sources(_first_value(base_stats, ["element_damage_bonus_sources", "elementDamageBonusSources"], []))
	element_resist_rating = _normalize_element_map(_first_value(base_stats, ["element_resist_rating", "elementResistRating"], {}))
	element_penetration_rating = _normalize_element_map(_first_value(base_stats, ["element_penetration_rating", "elementPenetrationRating"], {}))
	tag_vulnerability = _normalize_number_map(_first_value(base_stats, ["tag_vulnerability", "tagVulnerability"], {}))
	element_resist_rating_modifiers = _normalize_element_map(_first_value(base_stats, ["element_resist_rating_modifiers", "elementResistRatingModifiers"], {}))
	phase_rules = _normalize_phase_rules(_first_value(base_stats, ["phase_rules", "phaseRules"], []))
	active_phase_rule_id = str(_first_value(base_stats, ["active_phase_rule_id", "activePhaseRuleId"], ""))
	active_condition_ids = _normalize_string_array(_first_value(base_stats, ["active_condition_ids", "activeConditionIds"], []))
	element_relation_matrix = _normalize_element_relation_matrix(_first_value(base_stats, ["element_relation_matrix", "elementRelationMatrix"], {}))

	for equip_info in equipped_items:
		if not equip_info is Dictionary:
			continue
		var item_stats_value: Variant = equip_info.get("stats", {})
		if not item_stats_value is Dictionary or (item_stats_value as Dictionary).is_empty():
			item_stats_value = equip_info.get("compiled_stats", {})
		var item_stats: Dictionary = item_stats_value if item_stats_value is Dictionary else {}
		max_hp += int(item_stats.get("max_hp", 0))
		attack += int(item_stats.get("attack", 0))
		defense += int(_first_value(item_stats, ["defense", "armor"], 0))
		move_speed += float(item_stats.get("move_speed", 0.0))
		crit_rate += float(item_stats.get("crit_rate", 0.0))
		crit_damage += float(item_stats.get("crit_damage", 0.0))
		attack_speed += float(item_stats.get("attack_speed", 0.0))
		# 装备扩展属性（默认 0，旧装备不破）
		magic_resist += int(item_stats.get("magic_resist", 0))
		block_rate += float(item_stats.get("block_rate", 0.0))
		dodge_rate += float(item_stats.get("dodge_rate", 0.0))
		status_resist += float(item_stats.get("status_resist", 0.0))
		status_intensity += float(_first_value(item_stats, ["status_intensity", "statusPower"], 0.0))
		skill_haste += float(item_stats.get("skill_haste", 0.0))
		armor_pen_percent += float(item_stats.get("armor_pen_percent", 0.0))
		armor_pen_flat += int(item_stats.get("armor_pen_flat", 0))
		magic_pen_percent += float(item_stats.get("magic_pen_percent", 0.0))
		magic_pen_flat += int(item_stats.get("magic_pen_flat", 0))
		heal_bonus += float(_first_value(item_stats, ["heal_bonus", "healingPower"], 0.0))
		shield_bonus += float(_first_value(item_stats, ["shield_bonus", "shieldPower"], 0.0))
		heal_received += float(_first_value(item_stats, ["heal_received", "receivedHealing"], 0.0))
		lifesteal += float(item_stats.get("lifesteal", 0.0))
		reflect_rate += float(item_stats.get("reflect_rate", 0.0))
		abyss_cost += float(item_stats.get("abyss_cost", 0.0))
		_append_element_sources(element_damage_bonus_sources, _first_value(equip_info, ["element_damage_bonus_sources", "elementDamageBonusSources"], _first_value(item_stats, ["element_damage_bonus_sources", "elementDamageBonusSources"], [])))
		_add_element_map(element_resist_rating, _first_value(equip_info, ["element_resist_rating", "elementResistRating"], _first_value(item_stats, ["element_resist_rating", "elementResistRating"], {})))
		_add_element_map(element_penetration_rating, _first_value(equip_info, ["element_penetration_rating", "elementPenetrationRating"], _first_value(item_stats, ["element_penetration_rating", "elementPenetrationRating"], {})))
		_add_number_map(tag_vulnerability, _first_value(equip_info, ["tag_vulnerability", "tagVulnerability"], _first_value(item_stats, ["tag_vulnerability", "tagVulnerability"], {})))
		_add_element_map(element_resist_rating_modifiers, _first_value(equip_info, ["element_resist_rating_modifiers", "elementResistRatingModifiers"], _first_value(item_stats, ["element_resist_rating_modifiers", "elementResistRatingModifiers"], {})))

	# 属性上限钳制（设计案第3.3节）
	crit_rate = clampf(crit_rate, 0.0, 0.75)
	crit_damage = clampf(crit_damage, 1.0, 2.5)
	block_rate = clampf(block_rate, 0.0, 0.6)
	dodge_rate = clampf(dodge_rate, 0.0, 0.35)
	attack_speed = clampf(attack_speed, 0.1, 2.5)
	armor_pen_percent = clampf(armor_pen_percent, 0.0, 0.5)
	magic_pen_percent = clampf(magic_pen_percent, 0.0, 0.5)
	lifesteal = clampf(lifesteal, 0.0, 0.2)
	reflect_rate = clampf(reflect_rate, 0.0, 0.5)
	abyss_cost = maxf(0.0, abyss_cost)  # 深渊装备代价 ≥0（每秒侵蚀 buildup）
	status_resist = clampf(status_resist, 0.0, 1.0)
	status_intensity = clampf(status_intensity, 0.0, 2.0)
	heal_received = clampf(heal_received, -0.8, 1.0)  # 下限 -0.8 保底 20% 治疗（设计案7.1）

	var stored_hp: int = _get_stored_hp()
	if stored_hp > 0:
		hp = mini(stored_hp, max_hp)
	elif preserve_current_hp and hp > 0:
		hp = mini(hp, max_hp)
	else:
		hp = max_hp

	_on_recalculated()


static func _first_value(source: Dictionary, keys: Array, fallback: Variant) -> Variant:
	for key in keys:
		if source.has(key):
			return source[key]
	return fallback


static func _normalize_element_id(value: Variant) -> String:
	return str(ELEMENT_ALIASES.get(str(value).to_lower(), "none"))


static func _normalize_element_map(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for raw_key in value:
		var canonical := _normalize_element_id(raw_key)
		if canonical == "none":
			continue
		if not result.has(canonical) or str(raw_key).to_lower() == canonical:
			result[canonical] = float(value[raw_key])
	return result


static func _normalize_number_map(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for key in value:
		result[str(key)] = float(value[key])
	return result


static func _normalize_element_sources(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	var index := 0
	for source_value in value:
		index += 1
		if not source_value is Dictionary:
			continue
		var source: Dictionary = (source_value as Dictionary).duplicate(true)
		var element := _normalize_element_id(_first_value(source, ["element_tag", "elementTag"], "none"))
		if element == "none":
			continue
		var source_id := str(_first_value(source, ["source_id", "sourceId"], ""))
		if source_id.is_empty():
			source_id = "source_%d" % index
		var scope := str(_first_value(source, ["damage_scope", "damageScope"], "all"))
		if scope not in ["all", "direct", "dot", "reaction", "summon"]:
			scope = "all"
		source["source_id"] = source_id
		source["element_tag"] = element
		source["damage_scope"] = scope
		source["value"] = float(source.get("value", 0.0))
		source["condition_id"] = str(_first_value(source, ["condition_id", "conditionId"], ""))
		result.append(source)
	return result


static func _normalize_phase_rules(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for rule_value in value:
		if not rule_value is Dictionary:
			continue
		var rule: Dictionary = (rule_value as Dictionary).duplicate(true)
		rule["id"] = str(_first_value(rule, ["id", "phase_id"], ""))
		rule["element_resist_rating_modifiers"] = _normalize_element_map(_first_value(rule, ["element_resist_rating_modifiers", "elementResistRatingModifiers"], {}))
		result.append(rule)
	return result


static func _normalize_string_array(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for item in value:
		result.append(str(item))
	return result


static func _normalize_element_relation_matrix(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for attacker_value in value:
		var attacker := _normalize_element_id(attacker_value)
		var row_value: Variant = value[attacker_value]
		if not row_value is Dictionary:
			continue
		var row: Dictionary = {}
		for defender_value in row_value:
			var defender := _normalize_element_id(defender_value)
			row[defender] = float(row_value[defender_value])
		result[attacker] = row
	return result


static func _append_element_sources(target: Array, value: Variant) -> void:
	for source in _normalize_element_sources(value):
		target.append(source)


static func _add_element_map(target: Dictionary, value: Variant) -> void:
	var additions := _normalize_element_map(value)
	for key in additions:
		target[key] = float(target.get(key, 0.0)) + float(additions[key])


static func _add_number_map(target: Dictionary, value: Variant) -> void:
	var additions := _normalize_number_map(value)
	for key in additions:
		target[key] = float(target.get(key, 0.0)) + float(additions[key])


# === 子类 override 的钩子 ===

## 返回基础属性 dict（enemies.json 配置 / characters.json 的 stats_at_level 段）
func _get_base_stats_dict() -> Dictionary:
	return {}


## 返回装备列表 [{stats: {max_hp, attack, ...}}, ...]；EnemyStats 返回 []
func _get_equipped_items() -> Array:
	return []


## 返回持久层存储的 hp（roster.hp）；EnemyStats 返回 0
func _get_stored_hp() -> int:
	return 0


## recalculate 完成后的钩子（同步 roster / emit 信号等）
func _on_recalculated() -> void:
	pass
