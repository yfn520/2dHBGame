@tool
class_name PartyManager
extends Node2D

signal active_character_changed(character: CharacterBody2D)
signal party_changed()

@export_category("上阵配置")
@export var lineup_character_ids: Array[int] = [7001]
@export_range(0, 8, 1) var initial_active_index := 0

const ASSIST_TARGET_DURATION := 6.0
# 初始站位与 player.gd 的跟随距离保持一致（ALLY_FOLLOW_BASE_DISTANCE/SLOT_GAP），
# 避免切人/重生后队友又叠回任务 NPC 身前。
const ALLY_FOLLOW_BASE_DISTANCE := 64.0
const ALLY_FOLLOW_SLOT_GAP := 40.0
# 关卡宽度（与 player.gd LEVEL_SIZE.x 一致）：队友站位偏移可能把人推到关卡宽度之外，
# 那里没有任何地面，落下去就是“掉没了”。在开始下落的起点（放置/重生）钆制 x，不做运行时持续判坑。
const LEVEL_WIDTH := 1536.0
const EDGE_MARGIN := 24.0

## 关卡范围钆制：队友站位可能因偏移超出关卡宽度（如主角贴边时队友偏移 42~102px），
## 范围外没有任何地面。在下落的起点控制 x，而不是运行时持续判坑。
func _clamp_to_level(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, EDGE_MARGIN, LEVEL_WIDTH - EDGE_MARGIN), pos.y)

var active_character: CharacterBody2D
var active_index := -1
var active_character_id := 0

var _assist_target: Node2D = null
var _assist_target_timer := 0.0

var _party_members: Array[CharacterBody2D] = []
var _member_by_id: Dictionary = {}
var _editor_preview: Node2D
var _preview_signature := ""
var _manual_skill_input_enabled := true
var _rebuilding_from_roster := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_refresh_editor_preview()
		return
	_sync_lineup_to_roster()
	_spawn_lineup()
	var start_index := initial_active_index
	if switch_character(clampi(start_index, 0, maxi(0, lineup_character_ids.size() - 1))):
		place_party_at(global_position)
	if GameRegistry.roster_data != null and not GameRegistry.roster_data.roster_changed.is_connected(_on_roster_changed):
		GameRegistry.roster_data.roster_changed.connect(_on_roster_changed)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		var signature := _get_preview_signature()
		if signature != _preview_signature:
			_refresh_editor_preview()
		return
	if _assist_target_timer > 0.0:
		_assist_target_timer -= delta
		if _assist_target_timer <= 0.0:
			_assist_target = null


## 记录队伍集火目标（主控角色最近命中的敌人），并刷新有效期。
func set_assist_target(enemy: Node2D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_assist_target = enemy
	_assist_target_timer = ASSIST_TARGET_DURATION


## 队伍集火目标；无效或不存在时返回 null。
func get_assist_target() -> Node2D:
	if _assist_target != null and is_instance_valid(_assist_target):
		return _assist_target
	return null


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
	pos = _clamp_to_level(pos)
	var facing := 1.0
	if active_character != null and active_character.has_method("get_facing_sign"):
		facing = float(active_character.get_facing_sign())
	var slot := 0
	for i in range(_party_members.size()):
		var member := _party_members[i]
		if not is_instance_valid(member):
			continue
		if member == active_character:
			member.global_position = pos
		else:
			var distance := ALLY_FOLLOW_BASE_DISTANCE + float(slot) * ALLY_FOLLOW_SLOT_GAP
			member.global_position = _clamp_to_level(pos + Vector2(-facing * distance, 0.0))
			slot += 1
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
	# 队伍重建会实例化一名带默认 Camera2D 偏移的新主控。信号监听者通常会
	# 更新 LevelManager，但这里再显式重套一次当前关卡边界，保证在剧情暂停/延迟
	# 重建期间也不会回退到预制体的 -175 偏移而露出地图底部。
	if GameRegistry.level_manager != null and GameRegistry.level_manager.has_method("refresh_active_camera"):
		GameRegistry.level_manager.refresh_active_camera()
	return true


func switch_next_character() -> bool:
	if _party_members.is_empty():
		return false
	return switch_character((active_index + 1) % _party_members.size())


func refresh_party_stats() -> void:
	for member in get_party_members():
		if member.has_method("refresh_combat_stats"):
			member.refresh_combat_stats()


func rebuild_from_roster(spawn_position: Vector2 = Vector2.INF) -> void:
	if _rebuilding_from_roster or GameRegistry.roster_data == null:
		return
	_rebuilding_from_roster = true
	var previous_position := global_position
	if is_instance_valid(active_character):
		previous_position = active_character.global_position
	var previous_active_id: int = int(GameRegistry.roster_data.active_character_id)
	lineup_character_ids = GameRegistry.roster_data.lineup_ids.duplicate()
	_spawn_lineup()
	var next_index: int = lineup_character_ids.find(previous_active_id)
	if next_index < 0:
		next_index = 0
	if not _party_members.is_empty():
		# 先在目标位置摆好新主控，再启用它的 Camera2D。若先 switch，开启了
		# position smoothing 的相机会从世界原点滑向玩家，地图会暂时只露出右下角。
		active_character = _party_members[next_index]
		active_index = next_index
		active_character_id = int(lineup_character_ids[next_index])
		place_party_at(previous_position if spawn_position == Vector2.INF else spawn_position)
		switch_character(next_index)
	_rebuilding_from_roster = false


func respawn_party(spawn_position: Vector2) -> void:
	if GameRegistry.roster_data != null:
		for character_id in GameRegistry.roster_data.lineup_ids:
			GameRegistry.roster_data.set_hp(-1, character_id)
	rebuild_from_roster(spawn_position)


## 控制玩家手动技能输入（J/K/L/U）是否生效。
## 只影响玩家输入，不影响队友 AI、敌人和弹道。
func set_manual_skill_input_enabled(enabled: bool) -> void:
	_manual_skill_input_enabled = enabled
	for member in get_party_members():
		var combat := member.get_node_or_null("CombatComponent")
		if combat != null and combat.has_method("set_manual_skill_input_enabled"):
			combat.set_manual_skill_input_enabled(enabled)


func is_manual_skill_input_enabled() -> bool:
	return _manual_skill_input_enabled


func _spawn_lineup() -> void:
	for member in _party_members:
		if is_instance_valid(member):
			var old_camera := member.get_node_or_null("Camera2D") as Camera2D
			if old_camera != null:
				old_camera.enabled = false
			member.queue_free()
	_party_members.clear()
	_member_by_id.clear()
	active_character = null
	active_index = -1
	active_character_id = 0
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
		# 预制体中的 Camera2D 默认 enabled。阵容全部生成并完成站位之前，
		# 不允许任何新成员抢占当前相机。
		var member_camera := member.get_node_or_null("Camera2D") as Camera2D
		if member_camera != null:
			member_camera.enabled = false
		add_child(member)
		member.global_position = _clamp_to_level(global_position + Vector2(-32.0 * float(i), 0.0))
		_party_members.append(member)
		_member_by_id[character_id] = member
		if GameRegistry.roster_data != null:
			GameRegistry.roster_data.ensure_character(character_id)
	_apply_party_collision_exceptions()
	party_changed.emit()


func _apply_control_modes() -> void:
	var follow_slot := 0
	for i in range(_party_members.size()):
		var member := _party_members[i]
		if not is_instance_valid(member):
			continue
		var is_active := member == active_character
		if member.has_method("set_player_controlled"):
			member.set_player_controlled(is_active)
		if member.has_method("set_follow_target"):
			member.set_follow_target(active_character if not is_active else null, follow_slot)
			if not is_active:
				follow_slot += 1
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
	var loaded_from_save := false
	if GameRegistry.player_data_provider != null and GameRegistry.player_data_provider.has_method("has_loaded_local_save"):
		loaded_from_save = GameRegistry.player_data_provider.has_loaded_local_save()
	if not loaded_from_save:
		# 新存档以 GameRoot/Player Inspector 中配置的阵容为启动来源。
		# CharacterRosterData 的默认值和本地 mock 仅用于数据兜底，不能覆盖场景配置。
		var ids := lineup_character_ids.duplicate()
		if ids.is_empty():
			ids = GameRegistry.character_config.get_default_lineup()
		GameRegistry.roster_data.set_lineup(ids)
		GameRegistry.roster_data.set_active_by_index(clampi(initial_active_index, 0, maxi(0, ids.size() - 1)))
	elif GameRegistry.roster_data.lineup_ids.is_empty():
		var ids := lineup_character_ids.duplicate()
		if ids.is_empty():
			ids = GameRegistry.character_config.get_default_lineup()
		GameRegistry.roster_data.set_lineup(ids)
	lineup_character_ids = GameRegistry.roster_data.lineup_ids.duplicate()


func _on_roster_changed() -> void:
	if _rebuilding_from_roster or lineup_character_ids == GameRegistry.roster_data.lineup_ids:
		return
	call_deferred("rebuild_from_roster")


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
	return str(config.get("scene", ""))
