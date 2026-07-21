class_name QuestConfig

const CONFIG_PATH := "res://data/quests.json"

var _quests: Dictionary = {}


func load_config() -> void:
	_quests.clear()
	var data := _read_json(CONFIG_PATH)
	for id_value in data:
		var id := int(id_value)
		var raw: Dictionary = data[id_value]
		raw = raw.duplicate(true)
		raw["id"] = id
		raw["title"] = String(raw.get("title", "任务 %d" % id))
		raw["description"] = String(raw.get("description", ""))
		raw["giver_npc_id"] = int(raw.get("giver_npc_id", 0))
		raw["turn_in_npc_id"] = int(raw.get("turn_in_npc_id", raw["giver_npc_id"]))
		raw["objectives"] = raw.get("objectives", []) if raw.get("objectives", []) is Array else []
		raw["rewards"] = raw.get("rewards", {}) if raw.get("rewards", {}) is Dictionary else {}
		_quests[id] = raw


func get_quest(quest_id: int) -> Dictionary:
	return (_quests.get(quest_id, {}) as Dictionary).duplicate(true)


func get_all_quests() -> Dictionary:
	return _quests.duplicate(true)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("任务配置解析失败: %s" % path)
		return {}
	return json.data
