class_name NpcPlacementConfig

const CONFIG_PATH := "res://data/npc_placements.json"

var _levels: Dictionary = {}
var _errors: Array[String] = []


func load_config() -> void:
	_levels.clear()
	_errors.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("NPC 摆放文件不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("NPC 摆放文件解析失败: %s" % CONFIG_PATH)
		return
	var data := json.data as Dictionary
	if int(data.get("version", 0)) != 1 or not data.get("levels", {}) is Dictionary:
		push_error("NPC 摆放文件版本或 levels 字段无效: %s" % CONFIG_PATH)
		return
	var levels := data.get("levels", {}) as Dictionary
	for level_id in levels:
		var entries: Variant = levels[level_id]
		if not entries is Array:
			_errors.append("关卡 %s 的 NPC 摆放必须是数组" % level_id)
			continue
		var normalized: Array[Dictionary] = []
		var seen: Dictionary = {}
		for value in entries:
			if not value is Dictionary:
				_errors.append("Level %s contains a non-object NPC placement" % level_id)
				continue
			var entry := value as Dictionary
			var allowed_fields := ["instance_id", "npc_id", "x", "y", "facing", "scale", "interaction_radius"]
			var unsupported := false
			for field in entry:
				if String(field) not in allowed_fields:
					_errors.append("Level %s NPC placement contains unsupported field: %s" % [level_id, field])
					unsupported = true
					break
			if unsupported:
				continue
			if not entry.get("instance_id") is String or not _is_number(entry.get("npc_id")) or not _is_number(entry.get("x")) or not _is_number(entry.get("y")) or not entry.get("facing") is String or not _is_number(entry.get("scale")) or not _is_number(entry.get("interaction_radius")):
				_errors.append("Level %s NPC placement has invalid field types" % level_id)
				continue
			var instance_id := String(entry.get("instance_id", "")).strip_edges()
			var npc_id := int(entry.get("npc_id", 0))
			var facing := String(entry.get("facing", ""))
			var scale_value := float(entry.get("scale", 0.0))
			var radius := float(entry.get("interaction_radius", 0.0))
			if not _is_slug(instance_id) or seen.has(instance_id) or npc_id <= 0 or facing not in ["left", "right"] or scale_value <= 0.0 or radius < 16.0:
				_errors.append("关卡 %s 存在无效 NPC 摆放: %s" % [level_id, instance_id])
				continue
			seen[instance_id] = true
			normalized.append({"instance_id": instance_id, "npc_id": npc_id, "x": float(entry.get("x", 0.0)), "y": float(entry.get("y", 0.0)), "facing": facing, "scale": scale_value, "interaction_radius": radius})
		_levels[int(level_id)] = normalized
	for error in _errors:
		push_error(error)


func get_for_level(level_id: int) -> Array[Dictionary]:
	return (_levels.get(level_id, []) as Array).duplicate(true)


func get_errors() -> Array[String]:
	return _errors.duplicate()


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_slug(value: String) -> bool:
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(value) != null
