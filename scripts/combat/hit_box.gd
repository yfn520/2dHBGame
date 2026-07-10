extends Area2D
## 攻击判定区
## 普攻/技能激活时短暂开启，检测 overlapping 的 HurtBox

signal hit_detected(hurt_box: Area2D)

var _active := false
var _owner_entity: Node = null
var _hit_targets: Dictionary = {}

@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Draw valid attack windows above the always-on HurtBox debug overlay.
	z_as_relative = false
	z_index = 1100
	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	deactivate()


func _physics_process(_delta: float) -> void:
	# 补充轮询，避免攻击框和受击框在同一物理帧重叠时漏掉 area_entered。
	if _active and monitoring:
		_detect_existing_overlaps()


func setup(owner_entity: Node) -> void:
	_owner_entity = owner_entity


func configure(window: Dictionary, facing: float) -> void:
	var actor_scale := _get_actor_scale()
	var position_x: float
	if window.has("authored_x"):
		# Production data stores signed X in the default-left artwork space.
		# Default left has facing=-1; flipped right mirrors the authored coordinate.
		position_x = float(window.get("authored_x", 0.0)) * -facing
	else:
		position_x = facing * absf(float(window.get("forward", 20.0)))
	position = Vector2(position_x, float(window.get("y", 0.0))) * actor_scale
	if collision_shape.shape is RectangleShape2D:
		var rectangle := collision_shape.shape as RectangleShape2D
		rectangle.size = Vector2(
			maxf(1.0, float(window.get("width", 20.0)) * actor_scale),
			maxf(1.0, float(window.get("height", 20.0)) * actor_scale)
		)


func _get_actor_scale() -> float:
	if _owner_entity != null and _owner_entity.has_method("get_actor_scale"):
		return maxf(0.01, float(_owner_entity.get_actor_scale()))
	return 1.0


func activate(detect_hits: bool = true) -> void:
	_active = true
	_hit_targets.clear()
	monitoring = detect_hits
	collision_shape.set_deferred("disabled", not detect_hits)
	if detect_hits:
		call_deferred("_detect_existing_overlaps")


func deactivate() -> void:
	_active = false
	monitoring = false
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)


func is_active() -> bool:
	return _active


func _on_area_entered(area: Area2D) -> void:
	if not _active:
		return
	if not area.has_method("is_hurt_box") or not area.is_hurt_box():
		return
	# 防止友军伤害
	var target_owner: Node = area._owner_entity if "_owner_entity" in area else null
	if _owner_entity != null and target_owner != null:
		if _owner_entity == target_owner:
			return
		if _owner_entity.is_in_group("player") and target_owner.is_in_group("player"):
			return
		if _owner_entity.is_in_group("enemies") and target_owner.is_in_group("enemies"):
			return
	var target_id: int = target_owner.get_instance_id() if target_owner != null else area.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	hit_detected.emit(area)


func _detect_existing_overlaps() -> void:
	if not _active:
		return
	for area in get_overlapping_areas():
		_on_area_entered(area)
