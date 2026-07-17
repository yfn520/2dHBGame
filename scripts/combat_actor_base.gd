class_name CombatActorBase
extends CharacterBody2D
## 战斗角色基类：承载 player/enemy 共用的节点引用、战斗动画三件套、战斗代理三件套、
## 辅助函数、_physics_process 公共前段。子类通过 override _setup_actor_specifics / _update_actor /
## _get_idle_animation / get_combat_stats 提供各自的控制层与数据源。

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var visual_root: Node2D = $CharacterActionSet
@onready var combat: Node = $CombatComponent

var _combat_anim_playing := false
var _combat_actions: Dictionary = {}
var _visual_authored_x := 0.0
var _actor_scale := 1.0
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _ready() -> void:
	_setup_actor_base()
	_setup_actor_specifics()


func _setup_actor_base() -> void:
	var debug_overlay := CombatDebugOverlay.new()
	add_child(debug_overlay)
	debug_overlay.setup(self)
	_visual_authored_x = visual_root.position.x
	_apply_visual_facing_offset()


## 子类 override：加 group、连信号、初始化 stats 等
func _setup_actor_specifics() -> void:
	pass


func _physics_process(delta: float) -> void:
	if not _can_process_combat(delta):
		move_and_slide()
		return
	_update_actor(delta)
	move_and_slide()


## 公共前段：重力 + 战斗状态限制 + buff 控制限制。
## 返回 false 表示子类不应执行控制逻辑（基类直接 move_and_slide）。
func _can_process_combat(delta: float) -> bool:
	if combat != null and "combat_state" in combat:
		if combat.combat_state == combat.CombatState.DEAD:
			velocity = Vector2.ZERO
			return false
	if not is_on_floor():
		velocity.y += gravity * delta
	_check_combat_anim_release()
	if combat != null and "combat_state" in combat:
		if combat.combat_state == combat.CombatState.HIT:
			# 受击立即停步，避免滑步
			velocity = Vector2.ZERO
			return false
	if _combat_anim_playing:
		# 技能动画播放期间立即停步，避免移动中释放技能滑步
		velocity = Vector2.ZERO
		return false
	if combat != null and combat.has_method("get_buff_manager"):
		var buff_manager = combat.get_buff_manager()
		if buff_manager != null and not buff_manager.can_move():
			# 控制限制（眩晕/冻结等）立即停步
			velocity = Vector2.ZERO
			return false
	return true


func _check_combat_anim_release() -> void:
	if _combat_anim_playing and (sprite.animation == &"idle" or sprite.animation == &"run"):
		_combat_anim_playing = false


## 子类 override：控制层（player=输入+队友AI，enemy=怪物状态机AI）
func _update_actor(delta: float) -> void:
	pass


# === Stats 接口 ===

func get_combat_stats() -> BaseCombatStats:
	return null


func get_combat_actions() -> Dictionary:
	return _combat_actions


func get_actor_scale() -> float:
	return _actor_scale


func get_facing_sign() -> float:
	return 1.0 if sprite.flip_h else -1.0


# === 战斗动画三件套 ===

## 播放战斗动画 (由 CombatComponent 调用)
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
	var next_animation := _get_idle_animation()
	if sprite.animation != next_animation:
		sprite.play(next_animation)


## 钩子：战斗动画结束后恢复的动画。player 返回 idle/run，enemy 按 AI 状态返回。
func _get_idle_animation() -> String:
	return "idle"


func _hold_animation_last_frame() -> void:
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.pause()
	sprite.frame = maxi(0, frame_count - 1)


# === 战斗代理三件套（由 HurtBox / 弹道 / SkillExecutor 调用）===

func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true) -> void:
	if play_hit_reaction:
		velocity.x = 0.0
	if combat != null and combat.has_method("take_damage"):
		combat.take_damage(amount, source, play_hit_reaction)


func heal(amount: int) -> void:
	if combat != null and combat.has_method("heal"):
		combat.heal(amount)


## 施加 Buff (由弹道/SkillExecutor 调用)
func apply_buff_from_config(buff_cfg: Dictionary, source: int = 0) -> void:
	if combat != null and combat.has_method("apply_buff_from_config"):
		combat.apply_buff_from_config(buff_cfg, source)


# === 共用辅助 ===

## Mirror the scene-authored visual-root offset; collision boxes stay actor-local.
func _apply_visual_facing_offset() -> void:
	visual_root.position.x = -_visual_authored_x if sprite.flip_h else _visual_authored_x


func _face_direction(dir: float) -> void:
	if dir == 0.0:
		return
	var new_flip := dir > 0.0
	if sprite.flip_h != new_flip:
		sprite.flip_h = new_flip
		_apply_visual_facing_offset()


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


## 统一的移动速度读取：从 stats 取 base，过 buff 修饰
func _get_move_speed() -> float:
	var base: float = 0.0
	var stats := get_combat_stats()
	if stats != null:
		base = stats.move_speed
	if combat != null and combat.has_method("get_buff_manager"):
		var bm = combat.get_buff_manager()
		if bm != null:
			return bm.get_modified_stat("move_speed", base)
	return base
