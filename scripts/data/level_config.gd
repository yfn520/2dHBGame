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
			"enemies": _normalize_enemies(raw.get("enemies", [])),
			"npcs": _normalize_npcs(raw.get("npcs", [])),
		}
	_loaded = true


func _normalize_npcs(raw_npcs: Variant) -> Array:
	if not raw_npcs is Array:
		return []
	var result: Array = []
	var index := 0
	for value in raw_npcs:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		result.append({
			"instance_id": String(entry.get("instance_id", "npc_%d" % index)),
			"npc_id": int(entry.get("npc_id", 0)),
			"x": float(entry.get("x", 0.0)),
			"y": float(entry.get("y", 0.0)),
			"facing": String(entry.get("facing", "")),
			"scale": maxf(0.01, float(entry.get("scale", 1.0))),
			"interaction_radius": maxf(0.0, float(entry.get("interaction_radius", 0.0))),
		})
		index += 1
	return result


## 把旧格式 enemies 记录规范化为带 spawn_id/mode/scatter_x 的新格式。
## 旧记录 count <= 1 视为单怪点；count > 1 视为随机组，默认 scatter_x = 20。
func _normalize_enemies(raw_enemies: Variant) -> Array:
	if not raw_enemies is Array:
		return []
	var result: Array = []
	var index := 0
	for entry_value in raw_enemies:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var count := int(entry.get("count", 1))
		var mode := String(entry.get("mode", "group" if count > 1 else "point"))
		var normalized: Dictionary = {
			"spawn_id": String(entry.get("spawn_id", "spawn_%d" % index)),
			"mode": mode,
			"enemy_id": int(entry.get("enemy_id", 0)),
			"x": float(entry.get("x", 0.0)),
			"y": float(entry.get("y", 0.0)),
		}
		if mode == "group":
			normalized["count"] = maxi(1, count)
			normalized["scatter_x"] = float(entry.get("scatter_x", 20.0))
		result.append(normalized)
		index += 1
	return result


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


## 把内存中的关卡数据写回 levels.json（关卡编辑器保存时调用）。
func save_all(levels: Dictionary) -> void:
	var data: Dictionary = {}
	for key in levels:
		var raw: Dictionary = levels[key]
		# 落盘时去掉运行时补的字段，保留旧字段兼容
		var out: Dictionary = {
			"name": raw.get("name", ""),
			"scene_path": raw.get("scene_path", ""),
			"spawn_x": int(raw.get("spawn_x", 0)),
			"spawn_y": int(raw.get("spawn_y", 0)),
			"bgm": raw.get("bgm", ""),
			"description": raw.get("description", ""),
			"enemies": raw.get("enemies", []),
			"npcs": raw.get("npcs", []),
		}
		data[str(key)] = out
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入关卡配置: %s" % CONFIG_PATH)
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	_levels = data.duplicate(true)
	_loaded = true
