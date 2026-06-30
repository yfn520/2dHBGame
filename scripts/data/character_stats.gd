class_name CharacterStats

signal stats_changed()

# 基础属性
var base_max_hp: int = 250
var base_attack: int = 1
var base_defense: int = 0
var base_move_speed: float = 220.0

# 当前属性(基础 + 装备加成)
var max_hp: int = 250
var hp: int = 250
var attack: int = 1
var defense: int = 0
var move_speed: float = 220.0


func recalculate(equipped_items: Array[Dictionary]) -> void:
	max_hp = base_max_hp
	attack = base_attack
	defense = base_defense
	move_speed = base_move_speed

	for equip_info in equipped_items:
		var item_stats: Dictionary = equip_info.get("stats", {})
		max_hp += int(item_stats.get("max_hp", 0))
		attack += int(item_stats.get("attack", 0))
		defense += int(item_stats.get("defense", 0))
		move_speed += float(item_stats.get("move_speed", 0.0))

	# hp 不能超过 max_hp
	if hp > max_hp:
		hp = max_hp
	stats_changed.emit()


func take_damage(amount: int) -> int:
	var actual := maxi(1, amount - defense)
	hp = maxi(0, hp - actual)
	stats_changed.emit()
	return actual


func heal(amount: int) -> int:
	var actual := mini(amount, max_hp - hp)
	hp += actual
	stats_changed.emit()
	return actual


func is_alive() -> bool:
	return hp > 0


# ---- 存档 ----

func to_dict() -> Dictionary:
	return {
		"base_max_hp": base_max_hp,
		"base_attack": base_attack,
		"base_defense": base_defense,
		"base_move_speed": base_move_speed,
		"hp": hp,
	}


func from_dict(data: Dictionary) -> void:
	base_max_hp = int(data.get("base_max_hp", 250))
	base_attack = int(data.get("base_attack", 1))
	base_defense = int(data.get("base_defense", 0))
	base_move_speed = float(data.get("base_move_speed", 220.0))
	# 先同步 max_hp，再读 hp，确保不超出
	max_hp = base_max_hp
	hp = int(data.get("hp", max_hp))
	if hp <= 0:
		hp = max_hp  # 死过或无存档时满血复活
