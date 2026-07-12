class_name CharacterConfigData

const CONFIG_PATH := "res://data/characters.json"

var _characters: Dictionary = {}


func load_config() -> void:
	_characters.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("角色配置不存在: %s" % CONFIG_PATH)
		return

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("角色配置解析失败: %s" % CONFIG_PATH)
		return

	for id_value in json.data:
		var character_id := int(id_value)
		var raw: Dictionary = json.data[id_value]
		_characters[character_id] = raw.duplicate(true)


func get_character(character_id: int) -> Dictionary:
	return _characters.get(character_id, {})


func has_character(character_id: int) -> bool:
	return _characters.has(character_id)


func get_scene_path(character_id: int) -> String:
	return String(get_character(character_id).get("scene", ""))


func get_name(character_id: int) -> String:
	return String(get_character(character_id).get("name", str(character_id)))


func get_actor_scale(character_id: int) -> float:
	return maxf(0.01, float(get_character(character_id).get("actor_scale", 1.0)))


func get_max_level(character_id: int) -> int:
	return int(get_character(character_id).get("max_level", 1))


func get_normal_skill(character_id: int) -> int:
	var config := get_character(character_id)
	if config.has("normal_skill"):
		return int(config.get("normal_skill", 0))
	var legacy_skills: Array = config.get("skills", [])
	return int(legacy_skills[0]) if not legacy_skills.is_empty() else 0


func get_skill_for_slot(character_id: int, slot_name: String, _level: int = 1) -> int:
	var config := get_character(character_id)
	var unlocks: Dictionary = config.get("skill_unlocks", {})
	var slot_data = unlocks.get(slot_name, {})
	if slot_data is Dictionary:
		return int(slot_data.get("skill_id", 0))
	return int(config.get(slot_name, 0))


func get_active_skill_ids(character_id: int, level: int = 1) -> Array[int]:
	var result: Array[int] = []
	var normal_skill := get_normal_skill(character_id)
	if normal_skill > 0:
		result.append(normal_skill)
	for slot_name in ["skill1", "skill2", "skill3"]:
		var skill_id := get_skill_for_slot(character_id, slot_name, level)
		if skill_id > 0 and not result.has(skill_id):
			result.append(skill_id)
	return result


func get_ai_skill_ids(character_id: int, level: int = 1) -> Array[int]:
	var active_ids := get_active_skill_ids(character_id, level)
	var result: Array[int] = []
	var config := get_character(character_id)
	var priority: Array = config.get("ai_skill_priority", [])
	for raw_skill_id in priority:
		var skill_id := int(raw_skill_id)
		if active_ids.has(skill_id) and not result.has(skill_id):
			result.append(skill_id)
	if not priority.is_empty():
		return result
	for skill_id in active_ids:
		if not result.has(skill_id):
			result.append(skill_id)
	return result


func get_default_lineup() -> Array[int]:
	var ids: Array[int] = []
	var keys := _characters.keys()
	keys.sort()
	for key in keys:
		ids.append(int(key))
	return ids


func get_first_character_id() -> int:
	var lineup := get_default_lineup()
	return lineup[0] if not lineup.is_empty() else 0


func get_stats_at_level(character_id: int, level: int) -> Dictionary:
	var config := get_character(character_id)
	var base: Dictionary = config.get("base_stats", {})
	var growth: Dictionary = config.get("growth", {})
	var max_level := int(config.get("max_level", 1))
	var safe_level := clampi(level, 1, max_level)
	var step := safe_level - 1
	return {
		"max_hp": int(base.get("max_hp", 100)) + int(growth.get("max_hp", 0)) * step,
		"attack": int(base.get("attack", 1)) + int(growth.get("attack", 0)) * step,
		"defense": int(base.get("defense", 0)) + int(growth.get("defense", 0)) * step,
		"move_speed": float(base.get("move_speed", 220.0)) + float(growth.get("move_speed", 0.0)) * float(step),
	}


func get_all() -> Dictionary:
	return _characters.duplicate(true)
