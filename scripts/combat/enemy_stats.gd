class_name EnemyStats
extends BaseCombatStats
## 怪物属性对象，接口与 CharacterStats 一致，供 CombatComponent 使用。
## 从 enemies.json 读取属性，一次性构造不可重算。

var _config: Dictionary = {}
## 敌人特征列表（设计案第10章），由 enemies.json 的 traits 字段提供
var traits: Array = []


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
	# 读取敌人特征（默认空数组）
	var raw_traits = cfg.get("traits", [])
	if raw_traits is Array:
		for t in raw_traits:
			traits.append(String(t))
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


func _get_base_stats_dict() -> Dictionary:
	return _config
