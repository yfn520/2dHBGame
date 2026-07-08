class_name EnemyConfig

const CONFIG_PATH := "res://data/enemies.json"

var _enemies: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载怪物配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("怪物配置解析失败")
		return
	var data: Dictionary = json.data
	for id_str in data:
		var enemy_id := int(id_str)
		var raw: Dictionary = data[id_str]
		_enemies[enemy_id] = {
			"id": enemy_id,
			"name": raw.get("name", ""),
			"asset": raw.get("asset", ""),
			"character_config": raw.get("character_config", ""),
			"actor_scale": float(raw.get("actor_scale", 1.0)),
			"max_hp": int(raw.get("max_hp", 50)),
			"attack": int(raw.get("attack", 1)),
			"defense": int(raw.get("defense", 0)),
			"move_speed": float(raw.get("move_speed", 80.0)),
			"attack_range": float(raw.get("attack_range", 40.0)),
			"detect_range": float(raw.get("detect_range", 200.0)),
			"patrol_range": float(raw.get("patrol_range", 80.0)),
			"skills": raw.get("skills", []),
			"skill_weights": raw.get("skill_weights", []),
			"drop_items": raw.get("drop_items", []),
			"exp": int(raw.get("exp", 0)),
		}
	_loaded = true


func get_enemy(enemy_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	return _enemies.get(enemy_id, {})


func get_all_enemies() -> Dictionary:
	if not _loaded:
		load_config()
	return _enemies
