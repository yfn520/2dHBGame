class_name CharacterStats

signal stats_changed()

var character_id: int = 0
var level: int = 1
var exp: int = 0

var base_max_hp: int = 250
var base_attack: int = 1
var base_defense: int = 0
var base_move_speed: float = 220.0

var max_hp: int = 250
var hp: int = 250
var attack: int = 1
var defense: int = 0
var move_speed: float = 220.0

var _roster: CharacterRosterData
var _character_config: CharacterConfigData


func setup(roster: CharacterRosterData, character_config: CharacterConfigData) -> void:
	_roster = roster
	_character_config = character_config
	if _roster != null and not _roster.active_character_changed.is_connected(_on_active_character_changed):
		_roster.active_character_changed.connect(_on_active_character_changed)
	if _roster != null and not _roster.character_progress_changed.is_connected(_on_character_progress_changed):
		_roster.character_progress_changed.connect(_on_character_progress_changed)
	recalculate([])


func _on_active_character_changed(_character_id: int) -> void:
	recalculate(_get_current_equipped_configs())


func _on_character_progress_changed(changed_character_id: int) -> void:
	if changed_character_id == character_id:
		recalculate(_get_current_equipped_configs(), false)


func recalculate(equipped_items: Array[Dictionary], preserve_current_hp: bool = true) -> void:
	if _roster != null:
		character_id = _roster.active_character_id
		level = _roster.get_level(character_id)
		exp = _roster.get_exp(character_id)
	else:
		character_id = 0
		level = 1
		exp = 0

	var base_stats := {}
	if _character_config != null and character_id != 0:
		base_stats = _character_config.get_stats_at_level(character_id, level)

	base_max_hp = int(base_stats.get("max_hp", base_max_hp))
	base_attack = int(base_stats.get("attack", base_attack))
	base_defense = int(base_stats.get("defense", base_defense))
	base_move_speed = float(base_stats.get("move_speed", base_move_speed))

	var old_hp := hp
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

	var stored_hp: int = int(_roster.get_hp(character_id)) if _roster != null and character_id != 0 else -1
	if stored_hp > 0:
		hp = mini(stored_hp, max_hp)
	elif preserve_current_hp and old_hp > 0:
		hp = mini(old_hp, max_hp)
	else:
		hp = max_hp

	if _roster != null and character_id != 0:
		_roster.set_hp(hp, character_id)
	stats_changed.emit()


func take_damage(amount: int) -> int:
	var actual := maxi(1, amount - defense)
	hp = maxi(0, hp - actual)
	if _roster != null and character_id != 0:
		_roster.set_hp(hp, character_id)
	stats_changed.emit()
	return actual


func heal(amount: int) -> int:
	var actual := mini(amount, max_hp - hp)
	hp += actual
	if _roster != null and character_id != 0:
		_roster.set_hp(hp, character_id)
	stats_changed.emit()
	return actual


func is_alive() -> bool:
	return hp > 0


func _get_current_equipped_configs() -> Array[Dictionary]:
	if GameRegistry.equipment_provider != null:
		return GameRegistry.equipment_provider.get_equipped_configs()
	return []


func to_dict() -> Dictionary:
	return {
		"base_max_hp": base_max_hp,
		"base_attack": base_attack,
		"base_defense": base_defense,
		"base_move_speed": base_move_speed,
		"hp": hp,
	}


func from_dict(data: Dictionary) -> void:
	base_max_hp = int(data.get("base_max_hp", base_max_hp))
	base_attack = int(data.get("base_attack", base_attack))
	base_defense = int(data.get("base_defense", base_defense))
	base_move_speed = float(data.get("base_move_speed", base_move_speed))
	max_hp = base_max_hp
	hp = int(data.get("hp", max_hp))
	if hp <= 0:
		hp = max_hp
