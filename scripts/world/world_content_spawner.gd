class_name WorldContentSpawner
extends Node

const CONFIG_PATH := "res://data/runtime_world_content.json"

var _level_container: Node2D
var _active: Array[WorldInteractable] = []
var _data: Dictionary = {}
var _current_level_id := -1


func setup(level_container: Node2D) -> void:
	_level_container = level_container
	_load_config()


func spawn_for_level(level_id: int) -> void:
	clear_all()
	_current_level_id = level_id
	var level_data := get_level_content(level_id)
	for value in level_data.get("interactables", []):
		if value is Dictionary and _conditions_pass(value):
			var state_key := "world_content:%s" % str(value.get("id", ""))
			if str(value.get("type", "")) == "pickup" and bool(GameRegistry.quest_state.get_flag(state_key, false)):
				continue
			var interactable := WorldInteractable.new()
			_level_container.add_child(interactable)
			interactable.setup(value)
			_active.append(interactable)


func refresh() -> void:
	if _current_level_id >= 0:
		spawn_for_level(_current_level_id)


func get_active_interactables() -> Array[WorldInteractable]:
	var result: Array[WorldInteractable] = []
	for interactable in _active:
		if is_instance_valid(interactable):
			result.append(interactable)
	return result


func get_enemy_spawns(level_id: int) -> Array:
	var result: Array = []
	for value in get_level_content(level_id).get("enemies", []):
		if value is Dictionary and _conditions_pass(value):
			result.append(value.duplicate(true))
	return result


func get_level_content(level_id: int) -> Dictionary:
	var levels: Dictionary = _data.get("levels", {})
	return (levels.get(str(level_id), {}) as Dictionary).duplicate(true)


func clear_all() -> void:
	for interactable in _active:
		if is_instance_valid(interactable):
			interactable.queue_free()
	_active.clear()


func _conditions_pass(data: Dictionary) -> bool:
	var quest_id := int(data.get("required_quest_id", 0))
	if quest_id <= 0:
		return true
	if GameRegistry.quest_service == null:
		return false
	var allowed: Array = data.get("required_quest_states", ["active", "ready", "completed"])
	var status := GameRegistry.quest_service.get_status(quest_id)
	if not allowed.has(status):
		return false
	# 世界内容可以绑定到任务阶段，而不是只绑定任务 active 状态。
	# 例如 C1-02-A 的史莱姆必须等到 S03 战斗阶段进入后才出现，
	# 否则玩家刚接任务就会看到战斗目标，且跳过前置对话。
	var required_stage_id := str(data.get("required_stage_id", ""))
	if not required_stage_id.is_empty():
		return GameRegistry.quest_service.get_current_stage_id(quest_id) == required_stage_id
	return true


func _load_config() -> void:
	_data = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) == OK and json.data is Dictionary:
		_data = json.data
	else:
		push_error("Runtime world content parse failed: %s" % CONFIG_PATH)
