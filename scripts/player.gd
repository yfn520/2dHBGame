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


func _ready() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = LEVEL_SIZE.x
	camera.limit_bottom = LEVEL_SIZE.y
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	var direction := _get_move_direction()
	var climb_direction := _get_climb_direction()
	var jump_pressed := Input.is_physical_key_pressed(KEY_SPACE)

	_update_ladder_contact()

	if is_climbing_ladder and current_ladder == null:
		_exit_ladder_state()
	elif not is_climbing_ladder and current_ladder != null and climb_direction != 0.0:
		_enter_ladder_state()

	if is_climbing_ladder:
		_handle_ladder_movement(direction, climb_direction, jump_pressed, delta)
	else:
		_handle_ground_movement(direction, jump_pressed, delta)

	if direction != 0.0:
		sprite.flip_h = direction > 0.0

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


func _update_animation(direction: float) -> void:
	var next_animation := "idle"

	if not is_climbing_ladder and absf(direction) > 0.0 and is_on_floor():
		next_animation = "run"

	if sprite.animation != next_animation:
		sprite.play(next_animation)
