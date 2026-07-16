class_name EnemyStats
extends BaseCombatStats
## 怪物属性对象，接口与 CharacterStats 一致，供 CombatComponent 使用。
## 从 enemies.json 读取属性，一次性构造不可重算。

var _config: Dictionary = {}


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
	recalculate(false)


func _get_base_stats_dict() -> Dictionary:
	return _config
