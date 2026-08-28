class_name NpcSpawner
extends Node

## NPC 生成器：进图时按 npc_placements.json 生成该图 NPC。
## 摆放条目可带 spawn_condition（旗标/任务门控），任务状态变化时增量刷新：
## - { "flag": "X", "equals": true }：旗标为真才生成（equals=false 则取反）
## - { "not_flag": "X" }：旗标未写入才生成
## - { "quest_id": 21030, "states": ["active"] }：任务处于指定状态才生成
## - { "quests": [...] }：多个任务门控取或（同一 NPC 服务多个任务）
## states 支持 "unlocked"（已解锁且未完成），让接取 NPC 在任务开启前就在场。
## 刷新时保留正在对话的 NPC，避免对话中途销毁其 actor。

var _spawn_container: Node2D
var _active_npcs: Array[NpcActor] = []
var _active_by_instance: Dictionary = {}
var _spawn_errors: Array[String] = []
var _current_level_id := -1


func setup(spawn_container: Node2D) -> void:
	_spawn_container = spawn_container
	if GameRegistry.quest_service != null and not GameRegistry.quest_service.quest_updated.is_connected(_on_quest_updated):
		GameRegistry.quest_service.quest_updated.connect(_on_quest_updated)


func spawn_npcs_for_level(level_id: int) -> void:
	_current_level_id = level_id
	clear_all()
	_spawn_errors.clear()
	if _spawn_container == null or GameRegistry.npc_config == null or GameRegistry.npc_placement_config == null:
		_record_spawn_error("NPC spawner is missing its container or configuration")
		return
	var spawns: Array = GameRegistry.npc_placement_config.get_for_level(level_id)
	for value in spawns:
		if not value is Dictionary:
			continue
		var placement: Dictionary = value
		if not _condition_pass(placement):
			continue
		_spawn_one(placement)


func clear_all() -> void:
	for npc in _active_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_active_npcs.clear()
	_active_by_instance.clear()


func get_active_npcs() -> Array[NpcActor]:
	var result: Array[NpcActor] = []
	for npc in _active_npcs:
		if is_instance_valid(npc):
			result.append(npc)
	return result


func get_spawn_errors() -> Array[String]:
	return _spawn_errors.duplicate()


func refresh_indicators() -> void:
	for npc in get_active_npcs():
		npc.refresh_quest_indicator()


func _spawn_one(placement: Dictionary) -> void:
	var npc_id := int(placement.get("npc_id", 0))
	var instance_id := str(placement.get("instance_id", ""))
	var config: Dictionary = GameRegistry.npc_config.get_npc(npc_id)
	if config.is_empty():
		_record_spawn_error("Placement %s references invalid NPC %d" % [instance_id, npc_id])
		return
	var npc := NpcActor.new()
	_spawn_container.add_child(npc)
	if not npc.setup(config, placement):
		_record_spawn_error("NPC instance failed to spawn: %s" % instance_id)
		npc.queue_free()
		return
	_active_npcs.append(npc)
	_active_by_instance[instance_id] = npc
	npc.tree_exiting.connect(_on_npc_removed.bind(npc))


func _condition_pass(placement: Dictionary) -> bool:
	var cond: Variant = placement.get("spawn_condition", null)
	if cond == null or not cond is Dictionary:
		return true
	var condition := cond as Dictionary
	if GameRegistry.quest_state == null:
		return false
	if condition.has("flag"):
		var actual := bool(GameRegistry.quest_state.get_flag(str(condition.get("flag", "")), false))
		return actual == bool(condition.get("equals", true))
	if condition.has("not_flag"):
		return not bool(GameRegistry.quest_state.get_flag(str(condition.get("not_flag", "")), false))
	if condition.has("quests"):
		for quest_gate in condition.get("quests", []):
			if quest_gate is Dictionary and _quest_gate_pass(quest_gate):
				return true
		return false
	if int(condition.get("quest_id", 0)) > 0:
		return _quest_gate_pass(condition)
	return true


func _quest_gate_pass(condition: Dictionary) -> bool:
	if int(condition.get("quest_id", 0)) <= 0:
		return false
	if GameRegistry.quest_service == null:
		return false
	var quest_id := int(condition.get("quest_id", 0))
	var status: String = GameRegistry.quest_service.get_status(quest_id)
	var states: Array = condition.get("states", ["active"])
	for state_value in states:
		var expected := str(state_value)
		if expected == "unlocked":
			if status != "completed" and GameRegistry.quest_service.is_quest_unlocked(quest_id):
				return true
		elif status == expected:
			return true
	return false


func _on_quest_updated(_quest_id: int) -> void:
	if _current_level_id >= 0:
		call_deferred("_refresh_conditions")


## 增量刷新：撤下条件不再满足的（正在对话的除外），补刷新满足条件的，不整体重建。
func _refresh_conditions() -> void:
	if _spawn_container == null or GameRegistry.npc_placement_config == null:
		return
	var talking_npc_id := 0
	if GameRegistry.dialogue_service != null:
		talking_npc_id = int(GameRegistry.dialogue_service.current_npc_id)
	var desired := {}
	var spawns: Array = GameRegistry.npc_placement_config.get_for_level(_current_level_id)
	for value in spawns:
		if value is Dictionary and _condition_pass(value):
			desired[str(value.get("instance_id", ""))] = value
	for instance_id in _active_by_instance.keys():
		var npc: NpcActor = _active_by_instance[instance_id]
		if not is_instance_valid(npc):
			_active_by_instance.erase(instance_id)
			_active_npcs.erase(npc)
			continue
		if desired.has(instance_id):
			continue
		if talking_npc_id != 0 and npc.npc_id == talking_npc_id:
			continue
		npc.queue_free()
		_active_npcs.erase(npc)
		_active_by_instance.erase(instance_id)
	for instance_id in desired:
		if _active_by_instance.has(instance_id):
			continue
		_spawn_one(desired[instance_id])


func _on_npc_removed(npc: NpcActor) -> void:
	_active_npcs.erase(npc)
	for instance_id in _active_by_instance.keys():
		if _active_by_instance[instance_id] == npc:
			_active_by_instance.erase(instance_id)
			break


func _record_spawn_error(error: String) -> void:
	_spawn_errors.append(error)
	push_error(error)
