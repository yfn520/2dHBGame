class_name LevelConfig

const CONFIG_PATH := "res://data/levels.json"

var _levels: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载关卡配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("关卡配置解析失败")
		return
	var data: Dictionary = json.data
	for id_str in data:
		var level_id := int(id_str)
		var raw: Dictionary = data[id_str]
		_levels[level_id] = {
			"id": level_id,
			"name": raw.get("name", ""),
			"scene_path": raw.get("scene_path", ""),
			"spawn_x": int(raw.get("spawn_x", 0)),
			"spawn_y": int(raw.get("spawn_y", 0)),
			"bgm": raw.get("bgm", ""),
			"description": raw.get("description", ""),
			"enemies": raw.get("enemies", []),
		}
	_loaded = true


func get_level(level_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	return _levels.get(level_id, {})


func get_all_levels() -> Dictionary:
	if not _loaded:
		load_config()
	return _levels


func get_first_level() -> Dictionary:
	if not _loaded:
		load_config()
	if _levels.is_empty():
		return {}
	return _levels.values()[0]


func get_level_count() -> int:
	if not _loaded:
		load_config()
	return _levels.size()
