extends CharacterBody2D

const JUMP_VELOCITY := -420.0
const LADDER_SPEED := 140.0
const LADDER_SNAP_SPEED := 1400.0
const LEVEL_SIZE := Vector2i(1376, 768)

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var was_jump_pressed := false
var is_climbing_ladder := false
var current_ladder: Area2D

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var ladder_detector: Area2D = $LadderDetector
@onready var combat: Node = $CombatComponent

var _combat_anim_playing := false
var _combat_actions: Dictionary = {}
var _sprite_authored_x := 0.0


func _ready() -> void:
	add_to_group("player")
	_apply_character_display_config()
	_sprite_authored_x = sprite.position.x
	_apply_sprite_facing_offset()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = LEVEL_SIZE.x
	camera.limit_bottom = LEVEL_SIZE.y
	sprite.play("idle")


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
	# CharacterActionSet transform is scene-authored. Reapplying the config value
	# here used to overwrite player.tscn's 0.5 scale with 1.0 at runtime, while
	# enemies stayed at 0.5, separating visible feet from collision geometry.


func get_combat_actions() -> Dictionary:
	return _combat_actions


func _load_combat_actions(asset_path: String, character_config: Dictionary) -> void:
	_combat_actions = {}
	var config_path: String = character_config.get("combat_actions", asset_path.path_join("combat_actions.json"))
	if not FileAccess.file_exists(config_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) == OK and json.data is Dictionary:
		_combat_actions = json.data.get("actions", {})


func _physics_process(delta: float) -> void:
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
		var new_flip := direction > 0.0
		if sprite.flip_h != new_flip:
			sprite.flip_h = new_flip
			_apply_sprite_facing_offset()

	_update_animation(direction)

	was_jump_pressed = jump_pressed
	move_and_slide()


func _handle_ground_movement(direction: float, jump_pressed: bool, delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	velocity.x = direction * GameRegistry.character_stats.move_speed

	if jump_pressed and not was_jump_pressed and is_on_floor():
		velocity.y = JUMP_VELOCITY


func _handle_ladder_movement(direction: float, climb_direction: float, jump_pressed: bool, delta: float) -> void:
	if current_ladder != null:
		global_position.x = move_toward(global_position.x, _get_ladder_center_x(current_ladder), LADDER_SNAP_SPEED * delta)

	velocity.x = 0.0
	velocity.y = climb_direction * LADDER_SPEED

	if jump_pressed and not was_jump_pressed:
		_exit_ladder_state()
		velocity.x = direction * GameRegistry.character_stats.move_speed
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


## Debug 绘制碰撞框
func _draw() -> void:
	if DebugDraw.show_collision:
		var col = $CollisionShape2D
		if col != null and col.shape != null:
			var s: Vector2 = col.shape.size
			draw_rect(Rect2(col.position - s * 0.5, s), Color(0, 1, 0, 0.3))
	if DebugDraw.show_hurtbox:
		_draw_debug_box("HurtBox", Color(1, 1, 0, 0.3))
	if DebugDraw.show_hitbox:
		_draw_debug_box("HitBox", Color(1, 0, 0, 0.35))


func _draw_debug_box(box_name: String, color: Color) -> void:
	var box := get_node_or_null(box_name)
	if box == null:
		return
	if box_name == "HitBox" and (not box.has_method("is_active") or not box.is_active()):
		return
	for child in box.get_children():
		if child is CollisionShape2D and child.shape != null:
			if child.shape is RectangleShape2D:
				var s: Vector2 = child.shape.size
				var center := to_local(child.global_position)
				draw_rect(Rect2(center - s * 0.5, s), color)


func _process(_delta: float) -> void:
	queue_redraw()


## Mirror the authored sprite-node offset with the artwork. Collision boxes stay actor-local.
func _apply_sprite_facing_offset() -> void:
	sprite.position.x = -_sprite_authored_x if sprite.flip_h else _sprite_authored_x


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
func play_combat_animation(anim_name: String) -> void:
	var target_animation := anim_name
	if not sprite.sprite_frames.has_animation(target_animation):
		if target_animation == "hit" and sprite.sprite_frames.has_animation("hurt"):
			target_animation = "hurt"
	if sprite.sprite_frames.has_animation(target_animation):
		_combat_anim_playing = true
		sprite.play(target_animation)
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
