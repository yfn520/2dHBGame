class_name InteractionManager
extends Node

var _party_manager: PartyManager
var _npc_spawner: NpcSpawner
var _world_spawner: WorldContentSpawner
var _ui_root: UIRoot
var _target: Node2D


func setup(party_manager: PartyManager, npc_spawner: NpcSpawner, ui_root: UIRoot, world_spawner: WorldContentSpawner = null) -> void:
	_party_manager = party_manager
	_npc_spawner = npc_spawner
	_ui_root = ui_root
	_world_spawner = world_spawner
	set_process(true)


func _process(_delta: float) -> void:
	# #region debug-point H1:interaction
	if DebugSink != null and Engine.get_process_frames() % 60 == 0:
		var _active := _npc_spawner != null and _npc_spawner.get_active_npcs().size()
		var _player := _party_manager.get_active_character() if _party_manager != null else null
		var _dists: Array = []
		if _player != null and _npc_spawner != null:
			for _n in _npc_spawner.get_active_npcs():
				_dists.append({"id": _n.npc_id, "d": round(_player.global_position.distance_to(_n.global_position)), "r": _n.interaction_radius, "valid": is_instance_valid(_n)})
		DebugSink.report("H1", "process-dbg", {"active": _active, "player": _player.global_position if _player else null, "dists": _dists, "target": _target.name if is_instance_valid(_target) else null})
	# #endregion
	if _party_manager == null or _npc_spawner == null or GameRegistry.dialogue_service == null:
		_set_target(null)
		return
	var waiting_for_world_event: bool = GameRegistry.dialogue_service.has_method("is_waiting_for_world_event") \
		and GameRegistry.dialogue_service.is_waiting_for_world_event()
	if (GameRegistry.dialogue_service.is_active() and not waiting_for_world_event) \
		or ((_ui_root != null and _ui_root.is_modal_open()) and not waiting_for_world_event):
		_set_target(null)
		return
	var player := _party_manager.get_active_character()
	if player == null:
		_set_target(null)
		return
	var nearest: Node2D = null
	var nearest_distance := INF
	if not waiting_for_world_event:
		for npc in _npc_spawner.get_active_npcs():
			var distance := player.global_position.distance_to(npc.global_position)
			if distance <= npc.interaction_radius and distance < nearest_distance:
				nearest = npc
				nearest_distance = distance
	if _world_spawner != null:
		for interactable in _world_spawner.get_active_interactables():
			var distance := player.global_position.distance_to(interactable.global_position)
			if distance <= interactable.interaction_radius and distance < nearest_distance:
				nearest = interactable
				nearest_distance = distance
	_set_target(nearest)


func try_interact() -> bool:
	if not is_instance_valid(_target):
		return false
	var target := _target
	_set_target(null)
	if target is NpcActor:
		return GameRegistry.dialogue_service.start_dialogue((target as NpcActor).npc_id)
	if target.has_method("interact"):
		return bool(target.interact())
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.INTERACT) and try_interact():
		get_viewport().set_input_as_handled()


func _set_target(next: Node2D) -> void:
	if _target == next:
		return
	_target = next
	if _ui_root != null:
		_ui_root.set_interaction_target(_target)
