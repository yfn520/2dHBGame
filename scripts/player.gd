extends CharacterBody2D

const JUMP_VELOCITY := -420.0
const LADDER_SPEED := 140.0
const LADDER_SNAP_SPEED := 1400.0
const LEVEL_SIZE := Vector2i(1376, 768)
const ALLY_ENGAGE_RANGE := 260.0
const ALLY_DISENGAGE_RANGE := 360.0
const ALLY_FOLLOW_LEASH := 260.0
const ALLY_FOLLOW_RESUME_DISTANCE := 180.0
const ALLY_ATTACK_STOP_RATIO := 0.85
const ALLY_ATTACK_RESUME_RATIO := 1.15
const ALLY_ATTACK_HOLD_TIME := 0.35
const ALLY_FACE_TARGET_DEAD_ZONE := 10.0
const ALLY_FOLLOW_STOP_DISTANCE := 18.0
const ALLY_FOLLOW_SIDE_SWITCH_DISTANCE := 96.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var was_jump_pressed := false
var is_climbing_ladder := false
var current_ladder: Area2D

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var visual_root: Node2D = $CharacterActionSet
@onready var camera: Camera2D = $Camera2D
@onready var ladder_detector: Area2D = $LadderDetector
@onready var combat: Node = $CombatComponent

var _combat_anim_playing := false
var _combat_actions: Dictionary = {}
var _visual_authored_x := 0.0
var character_id: int = 0
var _player_controlled := true
var _follow_target: Node2D = null
var _ally_attack_target: Node2D = null
var _ally_attack_hold_timer: float = 0.0
var _ally_is_holding_attack := false
var _ally_hold_skill_id := 0
var _ally_returning_to_follow := false
var _ally_follow_side: float = -1.0
var _party_slot_index := 0
var _actor_scale := 1.0
var _facing_sign := 1.0
var _combat_stats = preload("res://scripts/combat/party_member_stats.gd").new()


func _ready() -> void:
	add_to_group("player")
	var debug_overlay := CombatDebugOverlay.new()
	add_child(debug_overlay)
	debug_overlay.setup(self)
	if character_id <= 0 and GameRegistry.roster_data != null:
		character_id = GameRegistry.roster_data.active_character_id
	_actor_scale = _get_configured_actor_scale()
	_apply_character_display_config()
	_refresh_combat_stats()
	if GameRegistry.roster_data != null and not GameRegistry.roster_data.character_progress_changed.is_connected(_on_roster_progress_changed):
		GameRegistry.roster_data.character_progress_changed.connect(_on_roster_progress_changed)
	if GameRegistry.equipment_provider != null:
		if not GameRegistry.equipment_provider.equipped.is_connected(_on_equipment_changed):
			GameRegistry.equipment_provider.equipped.connect(_on_equipment_changed)
		if not GameRegistry.equipment_provider.unequipped.is_connected(_on_equipment_changed):
			GameRegistry.equipment_provider.unequipped.connect(_on_equipment_changed)
	_visual_authored_x = visual_root.position.x
	_facing_sign = 1.0 if sprite.flip_h else -1.0
	_apply_visual_facing_offset()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = LEVEL_SIZE.x
	camera.limit_bottom = LEVEL_SIZE.y
	sprite.play("idle")


func set_party_character_id(value: int) -> void:
	character_id = value
	_actor_scale = _get_configured_actor_scale()
	_refresh_combat_stats()


func get_party_character_id() -> int:
	return character_id


func get_actor_scale() -> float:
	return _actor_scale


func get_facing_sign() -> float:
	return _facing_sign


func set_player_controlled(value: bool) -> void:
	_player_controlled = value
	if camera != null:
		camera.enabled = value
		if value and is_inside_tree():
			camera.make_current()
	if not value:
		is_climbing_ladder = false
		current_ladder = null


func is_player_controlled() -> bool:
	return _player_controlled


func get_ally_debug_state() -> String:
	var target_name := "-"
	var target_distance := INF
	if _is_valid_enemy_target(_ally_attack_target):
		target_name = _ally_attack_target.name
		target_distance = _edge_distance_x_to(_ally_attack_target)
	return "controlled:%s target:%s dist:%s returning:%s hold:%s" % [
		str(_player_controlled), target_name,
		("-" if is_inf(target_distance) else "%.1f" % target_distance),
		str(_ally_returning_to_follow), str(_ally_is_holding_attack)
	]


func set_follow_target(target: Node2D, slot_index: int = 0) -> void:
	_follow_target = target
	_party_slot_index = slot_index
	if _follow_target != null and is_instance_valid(_follow_target):
		var dx: float = global_position.x - _follow_target.global_position.x
		if absf(dx) > ALLY_FOLLOW_STOP_DISTANCE:
			_ally_follow_side = signf(dx)


func get_combat_stats():
	return _combat_stats


func refresh_combat_stats() -> void:
	_refresh_combat_stats()


func sync_combat_hp() -> void:
	if _combat_stats != null:
		_combat_stats.sync_hp_to_roster()


func _refresh_combat_stats() -> void:
	if character_id <= 0:
		return
	_combat_stats.setup(character_id)


func _on_roster_progress_changed(changed_character_id: int) -> void:
	if changed_character_id == character_id:
		_refresh_combat_stats()


func _on_equipment_changed(_slot: String = "", _item_id: int = 0) -> void:
	_refresh_combat_stats()


func get_skill_for_input(slot_name: String) -> int:
	if GameRegistry.character_config == null:
		return 0
	var current_level: int = int(_combat_stats.level) if _combat_stats != null else 1
	if slot_name == "normal":
		return GameRegistry.character_config.get_normal_skill(character_id)
	return GameRegistry.character_config.get_skill_for_slot(character_id, slot_name, current_level)


func get_ai_skill_candidates() -> Array[int]:
	if GameRegistry.character_config == null:
		return []
	if GameRegistry.character_config.has_method("get_ai_skill_ids"):
		return GameRegistry.character_config.get_ai_skill_ids(character_id, _combat_stats.level)
	return GameRegistry.character_config.get_active_skill_ids(character_id, _combat_stats.level)


## 从 character_config.json 读取 display_scale / display_offset 并应用
func _apply_character_display_config() -> void:
	# sprite_frames 路径 → 角色目录 → config 路径
	var sf_path: String = sprite.sprite_frames.resource_path
	var config_path := sf_path.get_base_dir().get_base_dir().path_join("character_config.json")
	if not FileAccess.file_exists(config_path):
		return

	var text := FileAccess.get_file_as_string(config_path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return

	var cfg: Dictionary = json.data
	_load_combat_actions(config_path.get_base_dir(), cfg)
	var base_display_scale := float(cfg.get("display_scale", visual_root.scale.x))
	var display_offset := _get_vector2_from_dict(cfg.get("display_offset", {}), visual_root.position)
	visual_root.position = display_offset * _actor_scale
	visual_root.scale = Vector2.ONE * base_display_scale * _actor_scale

	var root_collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var body_position := _get_vector2_from_dict(
		cfg.get("body_position", {}),
		root_collision.position if root_collision != null else Vector2.ZERO
	)
	var body_size := _get_vector2_from_dict(
		cfg.get("body_size", {}),
		_get_rectangle_size(root_collision)
	)
	_apply_scaled_rectangle_shape(root_collision, body_position, body_size)

	var hurt_collision := get_node_or_null("HurtBox/CollisionShape2D") as CollisionShape2D
	_apply_scaled_rectangle_shape(hurt_collision, body_position, body_size)


func get_combat_actions() -> Dictionary:
	return _combat_actions


func _get_configured_actor_scale() -> float:
	if character_id > 0 and GameRegistry.character_config != null:
		return GameRegistry.character_config.get_actor_scale(character_id)
	return 1.0


func _get_vector2_from_dict(data, fallback: Vector2) -> Vector2:
	if data is Dictionary:
		return Vector2(
			float(data.get("x", fallback.x)),
			float(data.get("y", fallback.y))
		)
	return fallback


func _get_rectangle_size(collision_shape: CollisionShape2D) -> Vector2:
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		return (collision_shape.shape as RectangleShape2D).size
	return Vector2.ONE


func _apply_scaled_rectangle_shape(collision_shape: CollisionShape2D, base_position: Vector2, base_size: Vector2) -> void:
	if collision_shape == null:
		return
	collision_shape.position = base_position * _actor_scale
	if collision_shape.shape is RectangleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		var rectangle := collision_shape.shape as RectangleShape2D
		rectangle.size = Vector2(
			maxf(1.0, base_size.x * _actor_scale),
			maxf(1.0, base_size.y * _actor_scale)
		)


func _load_combat_actions(asset_path: String, character_config: Dictionary) -> void:
	_combat_actions = {}
	var config_path: String = character_config.get("combat_actions", asset_path.path_join("combat_actions.json"))
	if not FileAccess.file_exists(config_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) == OK and json.data is Dictionary:
		_combat_actions = json.data.get("actions", {})


func _physics_process(delta: float) -> void:
	if not _player_controlled:
		_update_ally_ai(delta)
		move_and_slide()
		return
	# 战斗状态限制移动
	var can_move := true
	if combat != null and "combat_state" in combat:
		if combat.combat_state == combat.CombatState.DEAD:
			velocity = Vector2.ZERO
			move_and_slide()
			return
		if combat.combat_state == combat.CombatState.HIT:
			can_move = false
		# Combat state may reset before the visual action finishes, so the
		# animation itself is the authoritative movement lock.
		if _combat_anim_playing:
			can_move = false

	var direction := _get_move_direction()
	var climb_direction := _get_climb_direction()
	var jump_pressed := Input.is_physical_key_pressed(KEY_SPACE)

	_update_ladder_contact()

	if can_move:
		if is_climbing_ladder and current_ladder == null:
			_exit_ladder_state()
		elif not is_climbing_ladder and current_ladder != null and climb_direction != 0.0:
			_enter_ladder_state()

		if is_climbing_ladder:
			_handle_ladder_movement(direction, climb_direction, jump_pressed, delta)
		else:
			_handle_ground_movement(direction, jump_pressed, delta)
	else:
		# 战斗状态中减速停下
		velocity.x = 0.0

	if can_move and direction != 0.0:
		_face_direction(direction)

	_update_animation(direction)

	was_jump_pressed = jump_pressed
	move_and_slide()


func _handle_ground_movement(direction: float, jump_pressed: bool, delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	velocity.x = direction * _combat_stats.move_speed

	if jump_pressed and not was_jump_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY


func _handle_ladder_movement(direction: float, climb_direction: float, jump_pressed: bool, delta: float) -> void:
	if current_ladder != null:
		global_position.x = move_toward(global_position.x, _get_ladder_center_x(current_ladder), LADDER_SNAP_SPEED * delta)

	velocity.x = 0.0
	velocity.y = climb_direction * LADDER_SPEED

	if jump_pressed and not was_jump_pressed:
		_exit_ladder_state()
		velocity.x = direction * _combat_stats.move_speed
		velocity.y = JUMP_VELOCITY
	elif current_ladder == null:
		_exit_ladder_state()
	elif climb_direction == 0.0 and is_on_floor():
		_exit_ladder_state()


func _get_move_direction() -> float:
	var direction := 0.0

	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0

	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		direction += 1.0

	return direction


func _get_climb_direction() -> float:
	var direction := 0.0

	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		direction -= 1.0

	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		direction += 1.0

	return direction


func _update_ladder_contact() -> void:
	var ladders := ladder_detector.get_overlapping_areas()
	current_ladder = ladders[0] if not ladders.is_empty() else null


func _enter_ladder_state() -> void:
	is_climbing_ladder = true
	velocity = Vector2.ZERO


func _exit_ladder_state() -> void:
	is_climbing_ladder = false


func _get_ladder_center_x(ladder: Area2D) -> float:
	for child in ladder.get_children():
		if child is CollisionShape2D:
			return child.global_position.x

	return ladder.global_position.x


## Mirror the scene-authored visual-root offset; collision boxes stay actor-local.
func _apply_visual_facing_offset() -> void:
	visual_root.position.x = -_visual_authored_x if sprite.flip_h else _visual_authored_x


func _update_animation(direction: float) -> void:
	if _combat_anim_playing:
		return
	# 死亡或受击状态下不切换动画
	if combat != null and "combat_state" in combat:
		if combat.combat_state == combat.CombatState.DEAD:
			return
		if combat.combat_state == combat.CombatState.HIT:
			return
	# 当前动画是非循环（hurt/attack等）且未播放完，不切换
	if not sprite.sprite_frames.get_animation_loop(sprite.animation) and sprite.is_playing():
		return
	var next_animation := "idle"
	if not is_climbing_ladder and absf(direction) > 0.0 and is_on_floor():
		next_animation = "run"
	if sprite.animation != next_animation:
		sprite.play(next_animation)


## 播放战斗动画 (由 CombatComponent 调用)
func _update_ally_ai(delta: float) -> void:
	_ally_attack_hold_timer = maxf(0.0, _ally_attack_hold_timer - delta)
	# Visual state can be restored by another animation callback before our
	# combat callback runs. Idle/run always means the combat movement lock ended.
	if _combat_anim_playing and (sprite.animation == &"idle" or sprite.animation == &"run"):
		_combat_anim_playing = false
	var can_act := true
	if combat != null and "combat_state" in combat:
		if combat.combat_state == combat.CombatState.DEAD:
			velocity = Vector2.ZERO
			return
		if combat.combat_state == combat.CombatState.HIT or _combat_anim_playing:
			can_act = false
	if not is_on_floor():
		velocity.y += gravity * delta
	var target: Node2D = _get_ally_attack_target()
	if target != null:
		if can_act:
			_update_ally_attack(target)
		else:
			_face_attack_target(target)
			velocity.x = 0.0
	else:
		_clear_ally_attack_hold()
		_update_ally_follow(delta)
	_update_animation(signf(velocity.x))


func _update_ally_follow(delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		velocity.x = 0.0
		return
	var leader_facing := 1.0
	if _follow_target.has_method("get_facing_sign"):
		leader_facing = float(_follow_target.get_facing_sign())
	elif _follow_target.has_node("CharacterActionSet/AnimatedSprite2D"):
		var leader_sprite: AnimatedSprite2D = _follow_target.get_node("CharacterActionSet/AnimatedSprite2D")
		leader_facing = 1.0 if leader_sprite.flip_h else -1.0
	var leader_dist: float = absf(_follow_target.global_position.x - global_position.x)
	if leader_dist > ALLY_FOLLOW_SIDE_SWITCH_DISTANCE:
		_ally_follow_side = -leader_facing
	elif _ally_follow_side == 0.0:
		_ally_follow_side = -leader_facing
	var desired_x := _follow_target.global_position.x + _ally_follow_side * (42.0 + float(_party_slot_index) * 30.0)
	var dx := desired_x - global_position.x
	if absf(dx) <= ALLY_FOLLOW_STOP_DISTANCE:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		return
	var dir := signf(dx)
	_face_direction(dir)
	velocity.x = dir * minf(_combat_stats.move_speed * 0.95, maxf(40.0, absf(dx) * 6.0))


func _update_ally_attack(target: Node2D) -> void:
	var dx := target.global_position.x - global_position.x
	var dist := _edge_distance_x_to(target)
	var skill_id := _pick_ready_ai_skill(dist)
	var skill_range := _get_ally_skill_engage_distance(skill_id, 44.0)
	var stop_range := maxf(18.0, skill_range * ALLY_ATTACK_STOP_RATIO)
	var resume_range := maxf(stop_range + 8.0, skill_range * ALLY_ATTACK_RESUME_RATIO)
	if _ally_is_holding_attack and skill_id != _ally_hold_skill_id:
		_clear_ally_attack_hold()
	var dir := signf(dx)
	if dir == 0.0:
		dir = -_facing_sign
	_face_attack_target(target)
	if dist <= stop_range:
		_ally_is_holding_attack = true
		_ally_hold_skill_id = skill_id
		_ally_attack_hold_timer = ALLY_ATTACK_HOLD_TIME
	if _ally_is_holding_attack and (dist <= resume_range or _ally_attack_hold_timer > 0.0):
		velocity.x = 0.0
		if combat != null and combat.has_method("try_use_skill") and skill_id > 0:
			combat.try_use_skill(skill_id)
		return
	_ally_is_holding_attack = false
	if dist > stop_range:
		velocity.x = dir * _combat_stats.move_speed
		return
	velocity.x = 0.0
	if combat != null and combat.has_method("try_use_skill") and skill_id > 0:
		combat.try_use_skill(skill_id)


func _pick_ready_ai_skill(distance_x: float) -> int:
	if combat == null:
		return 0
	# 节点驱动：任一伤害节点区间能命中当前距离即可起手
	var cooldowns: Dictionary = combat.get_cooldowns_dict() if combat.has_method("get_cooldowns_dict") else {}
	for skill_id in get_ai_skill_candidates():
		if float(cooldowns.get(skill_id, 0.0)) > 0.0:
			continue
		var cache := _get_ally_ai_cache(skill_id)
		if cache.is_empty():
			continue
		if not AIRangeCompiler.get_castable_entries(cache, distance_x).is_empty():
			return skill_id
	return get_skill_for_input("normal")


## 返回技能的最大起手距离（用于队友停步距离）。
func _get_ally_skill_engage_distance(skill_id: int, fallback: float) -> float:
	if skill_id <= 0 or GameRegistry.skill_config == null:
		return fallback
	var cache := _get_ally_ai_cache(skill_id)
	if cache.is_empty():
		return fallback
	var max_d := AIRangeCompiler.get_max_engage_distance(cache)
	return fallback if max_d <= 0.0 else max_d


## 队友的 ai_range_cache；为空时惰性编译（用自身角色资源）。
func _get_ally_ai_cache(skill_id: int) -> Dictionary:
	if GameRegistry.skill_config == null:
		return {}
	var cache: Dictionary = GameRegistry.skill_config.get_ai_range_cache(skill_id)
	if not cache.is_empty() and not cache.get("entries", []).is_empty():
		return cache
	# 惰性编译：从 characters.json 取 asset 路径
	if GameRegistry.character_config == null:
		return cache
	var char_data: Dictionary = GameRegistry.character_config.get_character(character_id)
	var asset_path: String = String(char_data.get("asset", ""))
	if asset_path.is_empty():
		return cache
	return AIRangeCompiler.compile(skill_id, asset_path)


func _find_nearest_enemy(max_range: float) -> Node2D:
	var best: Node2D = null
	var best_dist := max_range
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Node2D:
			continue
		if node.is_queued_for_deletion():
			continue
		if node.has_method("get_combat_stats"):
			var stats = node.get_combat_stats()
			if stats != null and stats.hp <= 0:
				continue
		var enemy_combat := node.get_node_or_null("CombatComponent")
		if enemy_combat != null and "combat_state" in enemy_combat and enemy_combat.combat_state == enemy_combat.CombatState.DEAD:
			continue
		var enemy := node as Node2D
		var dist := _edge_distance_x_to(enemy)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _get_ally_attack_target() -> Node2D:
	if _follow_target == null or not is_instance_valid(_follow_target):
		_ally_returning_to_follow = false
		return _find_nearest_enemy(ALLY_ENGAGE_RANGE)
	var leader_dist: float = 0.0
	leader_dist = absf(_follow_target.global_position.x - global_position.x)
	if leader_dist > ALLY_FOLLOW_LEASH:
		_ally_returning_to_follow = true
		_ally_attack_target = null
		_clear_ally_attack_hold()
		return null
	if _ally_returning_to_follow:
		if leader_dist > ALLY_FOLLOW_RESUME_DISTANCE:
			_ally_attack_target = null
			_clear_ally_attack_hold()
			return null
		_ally_returning_to_follow = false
	if _is_valid_enemy_target(_ally_attack_target):
		var target_dist := _edge_distance_x_to(_ally_attack_target)
		if target_dist <= ALLY_DISENGAGE_RANGE:
			return _ally_attack_target
	_clear_ally_attack_hold()
	_ally_attack_target = _find_nearest_enemy(ALLY_ENGAGE_RANGE)
	if _ally_attack_target == null:
		_clear_ally_attack_hold()
	return _ally_attack_target


func _clear_ally_attack_hold() -> void:
	_ally_is_holding_attack = false
	_ally_attack_hold_timer = 0.0
	_ally_hold_skill_id = 0


func _is_valid_enemy_target(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("get_combat_stats"):
		var stats = target.get_combat_stats()
		if stats != null and stats.hp <= 0:
			return false
	return true


func _edge_distance_x_to(target: Node2D) -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var center_distance := absf(target.global_position.x - global_position.x)
	return maxf(0.0, center_distance - _combat_half_width(self) - _combat_half_width(target))


func _combat_half_width(node: Node) -> float:
	if node == null:
		return 0.0
	var shape_node := node.get_node_or_null("HurtBox/CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rectangle := shape_node.shape as RectangleShape2D
		return absf(rectangle.size.x * shape_node.global_scale.x) * 0.5
	return 0.0


func _face_direction(dir: float) -> void:
	if dir == 0.0:
		return
	_facing_sign = signf(dir)
	var new_flip := dir > 0.0
	if sprite.flip_h != new_flip:
		sprite.flip_h = new_flip
		_apply_visual_facing_offset()


func _face_attack_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var dx: float = target.global_position.x - global_position.x
	if absf(dx) <= ALLY_FACE_TARGET_DEAD_ZONE:
		return
	_face_direction(signf(dx))


func play_combat_animation(anim_name: String) -> void:
	var target_animation := anim_name
	if not sprite.sprite_frames.has_animation(target_animation):
		if target_animation == "hit" and sprite.sprite_frames.has_animation("hurt"):
			target_animation = "hurt"
	if sprite.sprite_frames.has_animation(target_animation):
		_combat_anim_playing = true
		sprite.animation = target_animation
		sprite.stop()
		sprite.frame = 0
		sprite.play()
		if not sprite.animation_finished.is_connected(_on_combat_anim_finished):
			sprite.animation_finished.connect(_on_combat_anim_finished)
	else:
		_combat_anim_playing = true
		get_tree().create_timer(0.3).timeout.connect(_end_combat_anim)


func _on_combat_anim_finished() -> void:
	_end_combat_anim()


func _end_combat_anim() -> void:
	_combat_anim_playing = false
	if sprite.animation_finished.is_connected(_on_combat_anim_finished):
		sprite.animation_finished.disconnect(_on_combat_anim_finished)

	# 死亡后不再恢复动画
	if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.DEAD:
		_hold_animation_last_frame()
		return

	# 攻击/受击结束后恢复移动动画，避免停在末帧
	var next_animation := "idle"
	var direction := _get_move_direction()
	if not is_climbing_ladder and absf(direction) > 0.0 and is_on_floor():
		next_animation = "run"
	if sprite.animation != next_animation:
		sprite.play(next_animation)


## 受伤 (由 HurtBox 调用)
func _hold_animation_last_frame() -> void:
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.pause()
	sprite.frame = maxi(0, frame_count - 1)


func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true) -> void:
	if play_hit_reaction:
		velocity.x = 0.0
	if combat != null and combat.has_method("take_damage"):
		combat.take_damage(amount, source, play_hit_reaction)


## 施加 Buff (由弹道/SkillExecutor 调用)
func apply_buff_from_config(config: Dictionary, source: int = 0) -> void:
	if combat != null and combat.has_method("apply_buff_from_config"):
		combat.apply_buff_from_config(config, source)
