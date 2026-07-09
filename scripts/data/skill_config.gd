class_name SkillConfig

const CONFIG_PATH := "res://data/skills.json"

var _skills: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载技能配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("技能配置解析失败: %s" % json.get_error_message())
		return
	var data := json.data as Dictionary
	for id_str in data:
		var skill_id := int(id_str)
		var raw: Dictionary = data[id_str]
		_skills[skill_id] = {
			"id": skill_id,
			"name": raw.get("name", ""),
			"description": raw.get("description", ""),
			"type": raw.get("type", "melee"),
			"effect_timing": raw.get("effect_timing", "cast_start"),
			"damage_ratio": float(raw.get("damage_ratio", 1.0)),
			"cooldown": float(raw.get("cooldown", 0.0)),
			"animation": raw.get("animation", "attack"),
			"range": float(raw.get("range", 0)),
			"projectile_scene": raw.get("projectile_scene", ""),
			"projectile_speed": float(raw.get("projectile_speed", 300.0)),
			"projectile_lifetime": float(raw.get("projectile_lifetime", 5.0)),
			"projectile_spawn_offset": float(raw.get("projectile_spawn_offset", 32.0)),
			"max_pierce": int(raw.get("max_pierce", 0)),
			"aoe_radius": float(raw.get("aoe_radius", 0)),
			"buff_on_hit": int(raw.get("buff_on_hit", 0)),
			"buff_chance": float(raw.get("buff_chance", 0.0)),
			"buff_on_self": int(raw.get("buff_on_self", 0)),
		}
	_loaded = true


func get_skill(skill_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	return _skills.get(skill_id, {})


func get_all_skills() -> Dictionary:
	if not _loaded:
		load_config()
	return _skills


func is_valid_skill(skill_id: int) -> bool:
	return not get_skill(skill_id).is_empty()
