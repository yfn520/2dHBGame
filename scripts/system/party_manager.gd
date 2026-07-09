@tool
class_name PartyManager
extends Node2D

signal active_character_changed(character: CharacterBody2D)
signal party_changed()

@export_category("上阵配置")
@export var lineup_character_ids: Array[int] = [1001, 1002]
@export_range(0, 8, 1) var initial_active_index := 0

var active_character: CharacterBody2D
var active_index := -1
var active_character_id := 0

var _party_members: Array[CharacterBody2D] = []
var _member_by_id: Dictionary = {}
var _editor_preview: Node2D
var _preview_signature := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_refresh_editor_preview()
		return
	_sync_lineup_to_roster()
	_spawn_lineup()
	var start_index := initial_active_index
	if GameRegistry.roster_data != null:
		start_index = GameRegistry.roster_data.active_index
	switch_character(clampi(start_index, 0, maxi(0, lineup_character_ids.size() - 1)))


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var signature := _get_preview_signature()
	if signature != _preview_signature:
		_refresh_editor_preview()


func get_active_character() -> CharacterBody2D:
	return active_character


func get_active_character_id() -> int:
	return active_character_id


func get_party_members() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for member in _party_members:
		if is_instance_valid(member):
			result.append(member)
	return result


func get_alive_party_members() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for member in get_party_members():
		var combat := member.get_node_or_null("CombatComponent")
		if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.DEAD:
			continue
		result.append(member)
	return result


func place_party_at(pos: Vector2) -> void:
	for i in range(_party_members.size()):
		var member := _party_members[i]
		if not is_instance_valid(member):
			continue
		member.global_position = pos + Vector2(-32.0 * float(i), 0.0)
		member.velocity = Vector2.ZERO


func switch_character(index: int) -> bool:
	if index < 0 or index >= _party_members.size():
		push_warning("[PartyManager] 无效的上阵角色索引: %d" % index)
		return false
	var member := _party_members[index]
	if not is_instance_valid(member):
		return false
	active_character = member
	active_index = index
	active_character_id = lineup_character_ids[index]
	if GameRegistry.roster_data != null:
		GameRegistry.roster_data.set_active_by_index(index)
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_apply_control_modes()
	active_character_changed.emit(active_character)
	return true


func switch_next_character() -> bool:
	if _party_members.is_empty():
		return false
	return switch_character((active_index + 1) % _party_members.size())


func refresh_party_stats() -> void:
	for member in get_party_members():
		if member.has_method("refresh_combat_stats"):
			member.refresh_combat_stats()


func _spawn_lineup() -> void:
	for member in _party_members:
		if is_instance_valid(member):
			member.queue_free()
	_party_members.clear()
	_member_by_id.clear()
	for i in range(lineup_character_ids.size()):
		var character_id := int(lineup_character_ids[i])
		var scene_path := _get_scene_path_for_id(character_id)
		if scene_path.is_empty():
			push_error("[PartyManager] 角色 %d 没有配置可用预制体" % character_id)
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			push_error("[PartyManager] 加载角色预制体失败: %s" % scene_path)
			continue
		var instance := scene.instantiate()
		if not instance is CharacterBody2D:
			push_error("[PartyManager] 上阵预制体根节点必须是 CharacterBody2D: %s" % scene_path)
			instance.queue_free()
			continue
		var member := instance as CharacterBody2D
		member.name = "%s_%d" % [GameRegistry.character_config.get_name(character_id), character_id]
		if member.has_method("set_party_character_id"):
			member.set_party_character_id(character_id)
		add_child(member)
		member.global_position = global_position + Vector2(-32.0 * float(i), 0.0)
		_party_members.append(member)
		_member_by_id[character_id] = member
		if GameRegistry.roster_data != null:
			GameRegistry.roster_data.ensure_character(character_id)
	_apply_party_collision_exceptions()
	party_changed.emit()


func _apply_control_modes() -> void:
	for i in range(_party_members.size()):
		var member := _party_members[i]
		if not is_instance_valid(member):
			continue
		var is_active := member == active_character
		if member.has_method("set_player_controlled"):
			member.set_player_controlled(is_active)
		if member.has_method("set_follow_target"):
			member.set_follow_target(active_character if not is_active else null, i)
		if member.has_method("refresh_combat_stats"):
			member.refresh_combat_stats()


func _apply_party_collision_exceptions() -> void:
	for a in _party_members:
		for b in _party_members:
			if a == b:
				continue
			if is_instance_valid(a) and is_instance_valid(b):
				a.add_collision_exception_with(b)


func _sync_lineup_to_roster() -> void:
	if GameRegistry.roster_data == null:
		return
	var ids := lineup_character_ids.duplicate()
	if ids.is_empty():
		ids = GameRegistry.character_config.get_default_lineup()
	if GameRegistry.roster_data.lineup_ids != ids:
		GameRegistry.roster_data.set_lineup(ids)
	lineup_character_ids = GameRegistry.roster_data.lineup_ids.duplicate()


func _get_preview_signature() -> String:
	var ids := PackedStringArray()
	for id in lineup_character_ids:
		ids.append(str(id))
	return "%d|%s" % [initial_active_index, "|".join(ids)]


func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_preview_signature = _get_preview_signature()
	if _editor_preview != null and is_instance_valid(_editor_preview):
		_editor_preview.free()
		_editor_preview = null
	if lineup_character_ids.is_empty():
		return
	var index := clampi(initial_active_index, 0, lineup_character_ids.size() - 1)
	var scene_path := _get_scene_path_for_id(lineup_character_ids[index])
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	if not instance is Node2D:
		instance.free()
		return
	_editor_preview = instance as Node2D
	_editor_preview.name = "当前主控预览"
	_editor_preview.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_editor_preview)
	_editor_preview.owner = null


func _get_scene_path_for_id(character_id: int) -> String:
	if Engine.is_editor_hint():
		return _get_scene_path_from_json(character_id)
	if GameRegistry.character_config != null:
		return GameRegistry.character_config.get_scene_path(character_id)
	return _get_scene_path_from_json(character_id)


func _get_scene_path_from_json(character_id: int) -> String:
	var config_path := "res://data/characters.json"
	if not FileAccess.file_exists(config_path):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) != OK or not json.data is Dictionary:
		return ""
	var data: Dictionary = json.data
	var config: Dictionary = data.get(str(character_id), {})
	return String(config.get("scene", ""))
