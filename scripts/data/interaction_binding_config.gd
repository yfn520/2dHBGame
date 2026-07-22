class_name InteractionBindingConfig

const CONFIG_PATH := "res://data/npc_interaction_bindings.json"

var _bindings: Dictionary = {}


func load_config() -> void:
	_bindings.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("NPC interaction binding config is missing: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("NPC interaction binding config parse failed: %s" % CONFIG_PATH)
		return
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != 1 or not data.get("bindings", {}) is Dictionary:
		push_error("NPC interaction binding config must contain version=1 and bindings")
		return
	_bindings = (data.get("bindings", {}) as Dictionary).duplicate(true)


func get_binding(dialogue_id: String, intent_key: String) -> Dictionary:
	return (_bindings.get("%s.%s" % [dialogue_id, intent_key], {}) as Dictionary).duplicate(true)
