class_name QuestService
extends Node

signal quest_updated(quest_id: int)
signal quest_started(quest_id: int)
signal quest_ready(quest_id: int)
signal quest_completed(quest_id: int)
signal notification_requested(text: String)

var config: QuestConfig
var state: QuestStateData
var inventory: InventoryProvider


func setup(p_config: QuestConfig, p_state: QuestStateData, p_inventory: InventoryProvider) -> void:
	config = p_config
	state = p_state
	inventory = p_inventory
	if inventory != null:
		if not inventory.item_added.is_connected(_on_inventory_changed):
			inventory.item_added.connect(_on_inventory_changed)
		if not inventory.item_removed.is_connected(_on_inventory_changed):
			inventory.item_removed.connect(_on_inventory_changed)
		if not inventory.item_changed.is_connected(_on_inventory_changed):
			inventory.item_changed.connect(_on_inventory_changed)
	_refresh_all_ready_states()


func start_quest(quest_id: int) -> bool:
	if config == null or config.get_quest(quest_id).is_empty() or state.get_status(quest_id) != "inactive":
		return false
	state.set_entry(quest_id, {"status": "active", "counters": {}})
	_refresh_ready_state(quest_id)
	quest_started.emit(quest_id)
	quest_updated.emit(quest_id)
	var quest := config.get_quest(quest_id)
	notification_requested.emit("已接取任务：%s" % String(quest.get("title", quest_id)))
	return true


func record_talk(npc_id: int) -> void:
	_record_event("talk", "npc_id", npc_id)


func record_kill(enemy_id: int) -> void:
	_record_event("kill", "enemy_id", enemy_id)


func turn_in_for_npc(npc_id: int) -> Array[int]:
	var completed: Array[int] = []
	if config == null:
		return completed
	for quest_id_value in config.get_all_quests():
		var quest_id := int(quest_id_value)
		var quest := config.get_quest(quest_id)
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and turn_in_quest(quest_id):
			completed.append(quest_id)
	return completed


func turn_in_quest(quest_id: int) -> bool:
	if state.get_status(quest_id) != "ready" or not _all_objectives_complete(quest_id):
		return false
	var quest := config.get_quest(quest_id)
	for objective_value in quest.get("objectives", []):
		if not objective_value is Dictionary:
			continue
		var objective: Dictionary = objective_value
		if String(objective.get("type", "")) == "collect" and bool(objective.get("consume_on_turn_in", false)):
			var item_id := int(objective.get("item_id", 0))
			var count := maxi(1, int(objective.get("count", 1)))
			if inventory == null or not inventory.has_item(item_id, count):
				_refresh_ready_state(quest_id)
				return false
	for objective_value in quest.get("objectives", []):
		if objective_value is Dictionary and String(objective_value.get("type", "")) == "collect" and bool(objective_value.get("consume_on_turn_in", false)):
			inventory.remove_item_by_id(int(objective_value.get("item_id", 0)), maxi(1, int(objective_value.get("count", 1))))
	var entry := state.get_entry(quest_id)
	entry["status"] = "completed"
	state.set_entry(quest_id, entry)
	_apply_rewards(quest)
	quest_completed.emit(quest_id)
	quest_updated.emit(quest_id)
	notification_requested.emit("任务完成：%s" % String(quest.get("title", quest_id)))
	return true


func get_status(quest_id: int) -> String:
	return state.get_status(quest_id) if state != null else "inactive"


func get_objective_progress(quest_id: int, objective: Dictionary, index: int) -> Dictionary:
	var required := maxi(1, int(objective.get("count", 1)))
	var current := 0
	if String(objective.get("type", "")) == "collect":
		current = inventory.get_count_by_id(int(objective.get("item_id", 0))) if inventory != null else 0
	else:
		var counters: Dictionary = state.get_entry(quest_id).get("counters", {})
		current = int(counters.get(_objective_key(objective, index), 0))
	return {"current": mini(current, required), "required": required, "complete": current >= required}


func get_visible_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if config == null:
		return result
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var status := state.get_status(quest_id)
		if status in ["active", "ready", "completed"]:
			var quest := config.get_quest(quest_id)
			quest["status"] = status
			result.append(quest)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("id", 0)) < int(b.get("id", 0)))
	return result


func has_available_quest(npc_id: int) -> bool:
	if config == null:
		return false
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var quest := config.get_quest(quest_id)
		if int(quest.get("giver_npc_id", 0)) == npc_id and state.get_status(quest_id) == "inactive":
			return true
	return false


func has_ready_quest(npc_id: int) -> bool:
	if config == null:
		return false
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var quest := config.get_quest(quest_id)
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and state.get_status(quest_id) == "ready":
			return true
	return false


func evaluate_condition(condition: Dictionary) -> bool:
	match String(condition.get("type", "")):
		"quest_state":
			return state.get_status(int(condition.get("quest_id", 0))) == String(condition.get("state", "inactive"))
		"flag_equals":
			return state.get_flag(String(condition.get("flag", ""))) == condition.get("value", true)
		"item_count":
			return inventory != null and inventory.get_count_by_id(int(condition.get("item_id", 0))) >= int(condition.get("count", 1))
		"":
			return true
		_:
			push_warning("未知对话条件: %s" % condition.get("type", ""))
			return false


func _record_event(objective_type: String, id_field: String, target_id: int) -> void:
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		if state.get_status(quest_id) != "active":
			continue
		var quest := config.get_quest(quest_id)
		var entry := state.get_entry(quest_id)
		var counters: Dictionary = entry.get("counters", {})
		var changed := false
		var objectives: Array = quest.get("objectives", [])
		for index in range(objectives.size()):
			if not objectives[index] is Dictionary:
				continue
			var objective: Dictionary = objectives[index]
			if String(objective.get("type", "")) != objective_type or int(objective.get(id_field, 0)) != target_id:
				continue
			var key := _objective_key(objective, index)
			var required := maxi(1, int(objective.get("count", 1)))
			counters[key] = mini(required, int(counters.get(key, 0)) + 1)
			changed = true
		if changed:
			entry["counters"] = counters
			state.set_entry(quest_id, entry)
			_refresh_ready_state(quest_id)
			quest_updated.emit(quest_id)


func _refresh_all_ready_states() -> void:
	if config == null or state == null:
		return
	for id_value in config.get_all_quests():
		_refresh_ready_state(int(id_value))


func _refresh_ready_state(quest_id: int) -> void:
	var status := state.get_status(quest_id)
	if status not in ["active", "ready"]:
		return
	var next_status := "ready" if _all_objectives_complete(quest_id) else "active"
	if next_status == status:
		return
	var entry := state.get_entry(quest_id)
	entry["status"] = next_status
	state.set_entry(quest_id, entry)
	if next_status == "ready":
		quest_ready.emit(quest_id)
		notification_requested.emit("任务目标已完成，可回去交付")
	quest_updated.emit(quest_id)


func _all_objectives_complete(quest_id: int) -> bool:
	var objectives: Array = config.get_quest(quest_id).get("objectives", [])
	if objectives.is_empty():
		return true
	for index in range(objectives.size()):
		if objectives[index] is Dictionary and not bool(get_objective_progress(quest_id, objectives[index], index).get("complete", false)):
			return false
	return true


func _objective_key(objective: Dictionary, index: int) -> String:
	var explicit := String(objective.get("id", ""))
	return explicit if not explicit.is_empty() else "%s_%d" % [String(objective.get("type", "objective")), index]


func _apply_rewards(quest: Dictionary) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	for item_value in rewards.get("items", []):
		if item_value is Dictionary and inventory != null:
			inventory.add_item(int(item_value.get("item_id", 0)), maxi(1, int(item_value.get("count", 1))))
	for flag_value in rewards.get("flags", []):
		if flag_value is Dictionary:
			state.set_flag(String(flag_value.get("flag", "")), flag_value.get("value", true))


func _on_inventory_changed(_value: Variant) -> void:
	_refresh_all_ready_states()
