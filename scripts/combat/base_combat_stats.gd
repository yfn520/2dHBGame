class_name BaseCombatStats
extends RefCounted
## 战斗属性基类：承载 8 个战斗属性 + is_alive + recalculate 模板方法。
## 子类通过 override _get_base_stats_dict / _get_equipped_items / _get_stored_hp / _on_recalculated
## 提供各自的数据源（构造 dict / GameRegistry 单例 / 注入引用）。

var max_hp: int = 0
var hp: int = 0
var attack: int = 0
var defense: int = 0
var move_speed: float = 0.0
var crit_rate: float = 0.0
var crit_damage: float = 1.5
var attack_speed: float = 1.0


func is_alive() -> bool:
	return hp > 0


## 模板方法：子类提供基础 dict + 装备列表 + stored hp，基类统一算最终值与 hp 封顶。
## 用当前字段值作为 fallback，子类可在 init/setup 中设置默认值。
func recalculate(preserve_current_hp: bool = true) -> void:
	var base_stats: Dictionary = _get_base_stats_dict()
	var equipped_items: Array = _get_equipped_items()

	max_hp = int(base_stats.get("max_hp", max_hp))
	attack = int(base_stats.get("attack", attack))
	defense = int(base_stats.get("defense", defense))
	move_speed = float(base_stats.get("move_speed", move_speed))
	crit_rate = float(base_stats.get("crit_rate", crit_rate))
	crit_damage = float(base_stats.get("crit_damage", crit_damage))
	attack_speed = float(base_stats.get("attack_speed", attack_speed))

	for equip_info in equipped_items:
		if not equip_info is Dictionary:
			continue
		var item_stats: Dictionary = equip_info.get("stats", {})
		max_hp += int(item_stats.get("max_hp", 0))
		attack += int(item_stats.get("attack", 0))
		defense += int(item_stats.get("defense", 0))
		move_speed += float(item_stats.get("move_speed", 0.0))
		crit_rate += float(item_stats.get("crit_rate", 0.0))
		crit_damage += float(item_stats.get("crit_damage", 0.0))
		attack_speed += float(item_stats.get("attack_speed", 0.0))

	var stored_hp: int = _get_stored_hp()
	if stored_hp > 0:
		hp = mini(stored_hp, max_hp)
	elif preserve_current_hp and hp > 0:
		hp = mini(hp, max_hp)
	else:
		hp = max_hp

	_on_recalculated()


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
