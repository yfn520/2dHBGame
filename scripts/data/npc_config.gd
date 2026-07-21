class_name NpcConfig

const CONFIG_PATH := "res://data/npcs.json"

var _npcs: Dictionary = {}


func load_config() -> void:
	_npcs.clear()
	var data := _read_json(CONFIG_PATH)
	for id_value in data:
		var id := int(id_value)
		var raw: Dictionary = data[id_value]
		_npcs[id] = {
			"id": id,
			"name": String(raw.get("name", "NPC %d" % id)),
			"asset": String(raw.get("asset", "")),
			"idle_animation": String(raw.get("idle_animation", "idle")),
			"facing": String(raw.get("facing", "right")),
			"scale": maxf(0.01, float(raw.get("scale", 1.0))),
			"interaction_radius": maxf(16.0, float(raw.get("interaction_radius", 96.0))),
			"dialogue_id": String(raw.get("dialogue_id", "")),
			"portrait": String(raw.get("portrait", "")),
			"text_key": String(raw.get("text_key", "")),
		}


func get_npc(npc_id: int) -> Dictionary:
	return (_npcs.get(npc_id, {}) as Dictionary).duplicate(true)


func get_all_npcs() -> Dictionary:
	return _npcs.duplicate(true)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("NPC 配置解析失败: %s" % path)
		return {}
	return json.data
