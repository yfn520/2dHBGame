class_name NpcSpawner
extends Node

var _spawn_container: Node2D
var _active_npcs: Array[NpcActor] = []
var _spawn_errors: Array[String] = []


func setup(spawn_container: Node2D) -> void:
	_spawn_container = spawn_container


func spawn_npcs_for_level(level_id: int) -> void:
	clear_all()
	_spawn_errors.clear()
	if _spawn_container == null or GameRegistry.npc_config == null or GameRegistry.npc_placement_config == null:
		_record_spawn_error("NPC spawner is missing its container or configuration")
		return
	var spawns: Array[Dictionary] = GameRegistry.npc_placement_config.get_for_level(level_id)
	for value in spawns:
		if not value is Dictionary:
			continue
		var placement: Dictionary = value
		var npc_id := int(placement.get("npc_id", 0))
		var config: Dictionary = GameRegistry.npc_config.get_npc(npc_id)
		if config.is_empty():
			_record_spawn_error("Placement %s references invalid NPC %d" % [String(placement.get("instance_id", "")), npc_id])
			continue
		var npc := NpcActor.new()
		_spawn_container.add_child(npc)
		if not npc.setup(config, placement):
			_record_spawn_error("NPC instance failed to spawn: %s" % String(placement.get("instance_id", "")))
			npc.queue_free()
			continue
		_active_npcs.append(npc)
		npc.tree_exiting.connect(_on_npc_removed.bind(npc))


func clear_all() -> void:
	for npc in _active_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	_active_npcs.clear()


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


func _on_npc_removed(npc: NpcActor) -> void:
	_active_npcs.erase(npc)


func _record_spawn_error(error: String) -> void:
	_spawn_errors.append(error)
	push_error(error)
