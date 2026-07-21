class_name DialogueConfig

const CONFIG_PATH := "res://data/dialogues.json"

var _dialogues: Dictionary = {}


func load_config() -> void:
	_dialogues = _read_json(CONFIG_PATH).duplicate(true)


func get_dialogue(dialogue_id: String) -> Dictionary:
	return (_dialogues.get(dialogue_id, {}) as Dictionary).duplicate(true)


func get_all_dialogues() -> Dictionary:
	return _dialogues.duplicate(true)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("对话配置解析失败: %s" % path)
		return {}
	return json.data
