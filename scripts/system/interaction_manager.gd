class_name InteractionManager
extends Node

var _party_manager: PartyManager
var _npc_spawner: NpcSpawner
var _ui_root: UIRoot
var _target: NpcActor


func setup(party_manager: PartyManager, npc_spawner: NpcSpawner, ui_root: UIRoot) -> void:
	_party_manager = party_manager
	_npc_spawner = npc_spawner
	_ui_root = ui_root
	set_process(true)


func _process(_delta: float) -> void:
	if _party_manager == null or _npc_spawner == null or GameRegistry.dialogue_service == null:
		_set_target(null)
		return
	if GameRegistry.dialogue_service.is_active() or (_ui_root != null and _ui_root.is_modal_open()):
		_set_target(null)
		return
	var player := _party_manager.get_active_character()
	if player == null:
		_set_target(null)
		return
	var nearest: NpcActor = null
	var nearest_distance := INF
	for npc in _npc_spawner.get_active_npcs():
		var distance := player.global_position.distance_to(npc.global_position)
		if distance <= npc.interaction_radius and distance < nearest_distance:
			nearest = npc
			nearest_distance = distance
	_set_target(nearest)


func try_interact() -> bool:
	if not is_instance_valid(_target):
		return false
	var npc_id := _target.npc_id
	_set_target(null)
	return GameRegistry.dialogue_service.start_dialogue(npc_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.INTERACT) and try_interact():
		get_viewport().set_input_as_handled()


func _set_target(next: NpcActor) -> void:
	if _target == next:
		return
	_target = next
	if _ui_root != null:
		_ui_root.set_interaction_target(_target)
