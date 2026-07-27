class_name DialogueConfig

const CONFIG_PATH := "res://data/dialogues.json"

var _dialogues: Dictionary = {}


func load_config() -> void:
	_dialogues = _read_json(CONFIG_PATH).duplicate(true)


func get_dialogue(dialogue_id: String) -> Dictionary:
	return (_dialogues.get(dialogue_id, {}) as Dictionary).duplicate(true)


func get_all_dialogues() -> Dictionary:
	return _dialogues.duplicate(true)


func get_dialogue_chapter_id(dialogue_id: String) -> String:
	var dialogue := get_dialogue(dialogue_id)
	return str(dialogue.get("chapter_id", ""))


func get_dialogue_story_node_id(dialogue_id: String) -> String:
	var dialogue := get_dialogue(dialogue_id)
	return str(dialogue.get("story_node_id", ""))


func get_node_story_layer(dialogue_id: String, node_id: String) -> String:
	var dialogue := get_dialogue(dialogue_id)
	var nodes: Dictionary = dialogue.get("nodes", {})
	var node: Dictionary = nodes.get(node_id, {})
	return str(node.get("story_layer", "COMMON"))


func get_node_required_lead(dialogue_id: String, node_id: String) -> int:
	var dialogue := get_dialogue(dialogue_id)
	var nodes: Dictionary = dialogue.get("nodes", {})
	var node: Dictionary = nodes.get(node_id, {})
	return int(node.get("required_lead_hero_id", 0))


func get_node_required_hero(dialogue_id: String, node_id: String) -> int:
	var dialogue := get_dialogue(dialogue_id)
	var nodes: Dictionary = dialogue.get("nodes", {})
	var node: Dictionary = nodes.get(node_id, {})
	return int(node.get("required_hero_id", 0))


func get_node_required_event_state(dialogue_id: String, node_id: String) -> String:
	var dialogue := get_dialogue(dialogue_id)
	var nodes: Dictionary = dialogue.get("nodes", {})
	var node: Dictionary = nodes.get(node_id, {})
	return str(node.get("required_event_state", ""))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("对话配置解析失败: %s" % path)
		return {}
	return json.data
