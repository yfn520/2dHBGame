class_name CharacterRosterData

signal roster_changed()
signal active_character_changed(character_id: int)
signal character_progress_changed(character_id: int)

const DEFAULT_CHARACTER_ID := 1001

var characters: Dictionary = {}
var lineup_ids: Array[int] = []
var active_character_id: int = DEFAULT_CHARACTER_ID
var active_index: int = 0


func setup_defaults(config_data: CharacterConfigData) -> void:
	if lineup_ids.is_empty():
		lineup_ids = config_data.get_default_lineup()
	if lineup_ids.is_empty():
		lineup_ids = [DEFAULT_CHARACTER_ID]
	for character_id in lineup_ids:
		ensure_character(character_id)
	if active_character_id == 0 or not characters.has(str(active_character_id)):
		active_character_id = lineup_ids[clampi(active_index, 0, lineup_ids.size() - 1)]
	active_index = maxi(0, lineup_ids.find(active_character_id))
	roster_changed.emit()
	active_character_changed.emit(active_character_id)


func ensure_character(character_id: int, level: int = 1, exp: int = 0, hp: int = -1) -> void:
	var key := str(character_id)
	if characters.has(key):
		return
	characters[key] = {
		"character_id": character_id,
		"level": maxi(1, level),
		"exp": maxi(0, exp),
		"hp": hp,
	}


func has_character(character_id: int) -> bool:
	return characters.has(str(character_id))


func get_character_data(character_id: int) -> Dictionary:
	return characters.get(str(character_id), {})


func get_active_character_data() -> Dictionary:
	return get_character_data(active_character_id)


func get_level(character_id: int = 0) -> int:
	var id := active_character_id if character_id == 0 else character_id
	return int(get_character_data(id).get("level", 1))


func get_exp(character_id: int = 0) -> int:
	var id := active_character_id if character_id == 0 else character_id
	return int(get_character_data(id).get("exp", 0))


func get_hp(character_id: int = 0) -> int:
	var id := active_character_id if character_id == 0 else character_id
	return int(get_character_data(id).get("hp", -1))


func set_hp(value: int, character_id: int = 0) -> void:
	var id := active_character_id if character_id == 0 else character_id
	ensure_character(id)
	var data: Dictionary = characters[str(id)]
	if int(data.get("hp", -1)) == value:
		return
	data["hp"] = value
	characters[str(id)] = data
	character_progress_changed.emit(id)


func set_level(value: int, character_id: int = 0, reset_exp: bool = true) -> void:
	var id := active_character_id if character_id == 0 else character_id
	ensure_character(id)
	var max_level := 99
	if GameRegistry.character_config != null:
		max_level = maxi(1, GameRegistry.character_config.get_max_level(id))
	var data: Dictionary = characters[str(id)]
	var new_level := clampi(value, 1, max_level)
	if int(data.get("level", 1)) == new_level and (not reset_exp or int(data.get("exp", 0)) == 0):
		return
	data["level"] = new_level
	if reset_exp:
		data["exp"] = 0
	data["hp"] = -1
	characters[str(id)] = data
	character_progress_changed.emit(id)
	if id == active_character_id:
		active_character_changed.emit(id)
	roster_changed.emit()


func add_exp(amount: int, character_id: int = 0) -> void:
	if amount <= 0:
		return
	var id := active_character_id if character_id == 0 else character_id
	ensure_character(id)
	var data: Dictionary = characters[str(id)]
	var current_level := int(data.get("level", 1))
	var max_level := 99
	if GameRegistry.character_config != null:
		max_level = maxi(1, GameRegistry.character_config.get_max_level(id))
	var current_exp := int(data.get("exp", 0)) + amount
	while current_level < max_level:
		var need := _get_exp_to_next_level(current_level)
		if current_exp < need:
			break
		current_exp -= need
		current_level += 1
	data["level"] = current_level
	data["exp"] = 0 if current_level >= max_level else current_exp
	if current_level >= max_level:
		data["exp"] = 0
	characters[str(id)] = data
	character_progress_changed.emit(id)
	if id == active_character_id:
		active_character_changed.emit(id)
	roster_changed.emit()


func add_exp_to_lineup(amount: int) -> void:
	if amount <= 0:
		return
	for id in lineup_ids:
		add_exp(amount, id)


func _get_exp_to_next_level(current_level: int) -> int:
	return maxi(1, current_level * 100)


func set_lineup(ids: Array[int]) -> void:
	lineup_ids.clear()
	for id in ids:
		if id <= 0:
			continue
		lineup_ids.append(id)
		ensure_character(id)
	if lineup_ids.is_empty():
		lineup_ids.append(DEFAULT_CHARACTER_ID)
		ensure_character(DEFAULT_CHARACTER_ID)
	if not lineup_ids.has(active_character_id):
		active_index = 0
		active_character_id = lineup_ids[0]
	else:
		active_index = lineup_ids.find(active_character_id)
	roster_changed.emit()


func set_active_by_index(index: int) -> bool:
	if index < 0 or index >= lineup_ids.size():
		return false
	active_index = index
	active_character_id = lineup_ids[index]
	ensure_character(active_character_id)
	active_character_changed.emit(active_character_id)
	roster_changed.emit()
	return true


func set_active_character_id(character_id: int) -> bool:
	var index := lineup_ids.find(character_id)
	if index < 0:
		return false
	return set_active_by_index(index)


func apply_server_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("characters"):
		characters.clear()
		var raw_characters = snapshot.get("characters", {})
		if raw_characters is Dictionary:
			for id_value in raw_characters:
				var id := int(id_value)
				var raw: Dictionary = raw_characters[id_value]
				characters[str(id)] = {
					"character_id": id,
					"level": int(raw.get("level", 1)),
					"exp": int(raw.get("exp", 0)),
					"hp": int(raw.get("hp", -1)),
				}
		elif raw_characters is Array:
			for raw_value in raw_characters:
				if not raw_value is Dictionary:
					continue
				var raw: Dictionary = raw_value
				var id := int(raw.get("character_id", raw.get("id", 0)))
				if id <= 0:
					continue
				characters[str(id)] = {
					"character_id": id,
					"level": int(raw.get("level", 1)),
					"exp": int(raw.get("exp", 0)),
					"hp": int(raw.get("hp", -1)),
				}
	if snapshot.has("lineup_ids"):
		var ids: Array[int] = []
		for id_value in snapshot.get("lineup_ids", []):
			ids.append(int(id_value))
		set_lineup(ids)
	if snapshot.has("active_character_id"):
		active_character_id = int(snapshot.get("active_character_id", active_character_id))
	if snapshot.has("active_index"):
		active_index = int(snapshot.get("active_index", active_index))
	if not lineup_ids.is_empty() and not lineup_ids.has(active_character_id):
		active_character_id = lineup_ids[clampi(active_index, 0, lineup_ids.size() - 1)]
	active_index = maxi(0, lineup_ids.find(active_character_id))
	ensure_character(active_character_id)
	roster_changed.emit()
	active_character_changed.emit(active_character_id)


func to_dict() -> Dictionary:
	return {
		"characters": characters.duplicate(true),
		"lineup_ids": lineup_ids.duplicate(),
		"active_character_id": active_character_id,
		"active_index": active_index,
	}


func from_dict(data: Dictionary, config_data: CharacterConfigData = null) -> void:
	characters.clear()
	var raw_characters: Dictionary = data.get("characters", {})
	for id_value in raw_characters:
		var id := int(id_value)
		var raw: Dictionary = raw_characters[id_value]
		characters[str(id)] = {
			"character_id": id,
			"level": int(raw.get("level", 1)),
			"exp": int(raw.get("exp", 0)),
			"hp": int(raw.get("hp", -1)),
		}
	lineup_ids.clear()
	for id_value in data.get("lineup_ids", []):
		lineup_ids.append(int(id_value))
	active_character_id = int(data.get("active_character_id", DEFAULT_CHARACTER_ID))
	active_index = int(data.get("active_index", 0))
	if config_data != null:
		setup_defaults(config_data)


func from_legacy_stats(data: Dictionary, config_data: CharacterConfigData) -> void:
	characters.clear()
	lineup_ids = config_data.get_default_lineup()
	if lineup_ids.is_empty():
		lineup_ids = [DEFAULT_CHARACTER_ID]
	active_character_id = lineup_ids[0]
	active_index = 0
	var legacy_hp := int(data.get("hp", data.get("base_max_hp", -1)))
	for character_id in lineup_ids:
		ensure_character(character_id, 1, 0, legacy_hp if character_id == active_character_id else -1)
	roster_changed.emit()
	active_character_changed.emit(active_character_id)
