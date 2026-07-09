extends RefCounted

var character_id: int = 0
var level: int = 1
var exp: int = 0

var max_hp: int = 100
var hp: int = 100
var attack: int = 1
var defense: int = 0
var move_speed: float = 220.0


func setup(p_character_id: int) -> void:
	character_id = p_character_id
	recalculate(false)


func recalculate(preserve_current_hp: bool = true) -> void:
	if character_id <= 0:
		return
	var roster = GameRegistry.roster_data
	var config = GameRegistry.character_config
	if roster != null:
		roster.ensure_character(character_id)
		level = roster.get_level(character_id)
		exp = roster.get_exp(character_id)

	var stats: Dictionary = {}
	if config != null:
		stats = config.get_stats_at_level(character_id, level)
	max_hp = int(stats.get("max_hp", max_hp))
	attack = int(stats.get("attack", attack))
	defense = int(stats.get("defense", defense))
	move_speed = float(stats.get("move_speed", move_speed))

	if GameRegistry.equipment_provider != null:
		for equip_info in GameRegistry.equipment_provider.get_equipped_configs(character_id):
			var item_stats: Dictionary = equip_info.get("stats", {})
			max_hp += int(item_stats.get("max_hp", 0))
			attack += int(item_stats.get("attack", 0))
			defense += int(item_stats.get("defense", 0))
			move_speed += float(item_stats.get("move_speed", 0.0))

	var stored_hp := roster.get_hp(character_id) if roster != null else -1
	if stored_hp > 0:
		hp = mini(stored_hp, max_hp)
	elif preserve_current_hp and hp > 0:
		hp = mini(hp, max_hp)
	else:
		hp = max_hp
	if roster != null:
		roster.set_hp(hp, character_id)


func sync_hp_to_roster() -> void:
	if GameRegistry.roster_data != null and character_id > 0:
		GameRegistry.roster_data.set_hp(hp, character_id)


func is_alive() -> bool:
	return hp > 0
