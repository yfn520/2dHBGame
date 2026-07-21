class_name NpcSpawner
extends Node

var _spawn_container: Node2D
var _active_npcs: Array[NpcActor] = []


func setup(spawn_container: Node2D) -> void:
	_spawn_container = spawn_container


func spawn_npcs_for_level(spawns: Array) -> void:
	clear_all()
	if _spawn_container == null or GameRegistry.npc_config == null:
		return
	for value in spawns:
		if not value is Dictionary:
			continue
		var placement: Dictionary = value
		var npc_id := int(placement.get("npc_id", 0))
		var config := GameRegistry.npc_config.get_npc(npc_id)
		if config.is_empty():
			push_warning("跳过不存在的 NPC 摆放: %d" % npc_id)
			continue
		var npc := NpcActor.new()
		_spawn_container.add_child(npc)
		npc.setup(config, placement)
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


func refresh_indicators() -> void:
	for npc in get_active_npcs():
		npc.refresh_quest_indicator()


func _on_npc_removed(npc: NpcActor) -> void:
	_active_npcs.erase(npc)
