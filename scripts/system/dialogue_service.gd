class_name DialogueService
extends Node

signal dialogue_started(npc_id: int)
signal node_changed(node: Dictionary)
signal dialogue_finished(npc_id: int, completed: bool)

var npc_config: NpcConfig
var dialogue_config: DialogueConfig
var quest_service: QuestService
var inventory: InventoryProvider

var current_npc_id := 0
var current_dialogue_id := ""
var current_node_id := ""
var _graph: Dictionary = {}
var _active := false


func setup(p_npc_config: NpcConfig, p_dialogue_config: DialogueConfig, p_quest_service: QuestService, p_inventory: InventoryProvider) -> void:
	npc_config = p_npc_config
	dialogue_config = p_dialogue_config
	quest_service = p_quest_service
	inventory = p_inventory


func start_dialogue(npc_id: int) -> bool:
	if _active:
		return false
	var npc := npc_config.get_npc(npc_id)
	if npc.is_empty():
		push_warning("NPC 不存在: %d" % npc_id)
		return false
	var dialogue_id := String(npc.get("dialogue_id", ""))
	var graph := dialogue_config.get_dialogue(dialogue_id)
	if dialogue_id.is_empty() or graph.is_empty():
		push_warning("NPC %d 没有可用对话: %s" % [npc_id, dialogue_id])
		return false
	current_npc_id = npc_id
	current_dialogue_id = dialogue_id
	_graph = graph
	_active = true
	dialogue_started.emit(npc_id)
	return _enter_node(String(graph.get("entry_node", graph.get("entry", ""))))


func advance() -> void:
	if not _active:
		return
	var node := get_current_node()
	var choices: Array = node.get("choices", [])
	if not choices.is_empty():
		return
	var next_id := String(node.get("next_id", node.get("next", "")))
	if next_id.is_empty():
		finish(true)
	else:
		_enter_node(next_id)


func choose(index: int) -> void:
	var node := get_current_node()
	var visible := get_visible_choices(node)
	if index < 0 or index >= visible.size():
		return
	var choice: Dictionary = visible[index]
	_execute_actions(choice.get("actions", []))
	var next_id := String(choice.get("next_id", choice.get("next", "")))
	if next_id.is_empty():
		finish(true)
	else:
		_enter_node(next_id)


func get_current_node() -> Dictionary:
	var nodes: Dictionary = _graph.get("nodes", {})
	return (nodes.get(current_node_id, {}) as Dictionary).duplicate(true)


func get_visible_choices(node: Dictionary = {}) -> Array[Dictionary]:
	if node.is_empty():
		node = get_current_node()
	var result: Array[Dictionary] = []
	for value in node.get("choices", []):
		if value is Dictionary and _conditions_pass(value.get("conditions", [])):
			result.append(value)
	return result


func is_active() -> bool:
	return _active


func finish(completed: bool = false) -> void:
	if not _active:
		return
	var npc_id := current_npc_id
	_active = false
	if completed and quest_service != null:
		quest_service.record_talk(npc_id)
		quest_service.turn_in_for_npc(npc_id)
	current_node_id = ""
	_graph = {}
	dialogue_finished.emit(npc_id, completed)


func _enter_node(node_id: String) -> bool:
	var guard := 0
	var next_id := node_id
	while guard < 64:
		guard += 1
		var nodes: Dictionary = _graph.get("nodes", {})
		var node: Dictionary = nodes.get(next_id, {})
		if node.is_empty():
			push_warning("对话节点不存在: %s/%s" % [current_dialogue_id, next_id])
			finish(false)
			return false
		current_node_id = next_id
		_execute_actions(node.get("actions", []))
		match String(node.get("type", "line")):
			"branch":
				next_id = _resolve_branch(node)
				if next_id.is_empty():
					finish(true)
					return true
			"end":
				finish(true)
				return true
			_:
				node_changed.emit(node.duplicate(true))
				return true
	push_warning("对话条件分支超过 64 次，疑似无出口循环: %s" % current_dialogue_id)
	finish(false)
	return false


func _resolve_branch(node: Dictionary) -> String:
	for value in node.get("routes", []):
		if value is Dictionary and _conditions_pass(value.get("conditions", [])):
			return String(value.get("next_id", value.get("next", "")))
	return String(node.get("default_next", ""))


func _conditions_pass(raw: Variant) -> bool:
	if not raw is Array:
		return true
	for value in raw:
		if value is Dictionary and (quest_service == null or not quest_service.evaluate_condition(value)):
			return false
	return true


func _execute_actions(raw: Variant) -> void:
	if not raw is Array:
		return
	for value in raw:
		if not value is Dictionary:
			continue
		match String(value.get("type", "")):
			"set_flag":
				quest_service.state.set_flag(String(value.get("flag", "")), value.get("value", true))
			"start_quest":
				quest_service.start_quest(int(value.get("quest_id", 0)))
			"give_item":
				if inventory != null:
					inventory.add_item(int(value.get("item_id", 0)), maxi(1, int(value.get("count", 1))))
			"close_dialogue":
				call_deferred("finish", true)
			"":
				pass
			_:
				push_warning("未知对话动作: %s" % value.get("type", ""))
