extends Area2D
## 受击判定区
## 常开，被 HitBox 检测到时触发受伤

signal damaged(damage: int, source: Node)

var _owner_entity: Node = null
var _collision_shape: CollisionShape2D = null


func setup(owner_entity: Node) -> void:
	_owner_entity = owner_entity
	for child in get_children():
		if child is CollisionShape2D:
			_collision_shape = child
			break
	# Debug geometry must remain visible above character sprites in either facing.
	z_as_relative = false
	z_index = 1000
	# 每帧重绘，确保朝向变化后立即更新
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func is_hurt_box() -> bool:
	return true


func take_hit(damage: int, source: Node) -> void:
	if _owner_entity != null and _owner_entity.has_method("take_damage"):
		_owner_entity.take_damage(damage, source)
	damaged.emit(damage, source)


func _draw() -> void:
	if _collision_shape == null or _collision_shape.shape == null:
		return
	var rect: Rect2
	if _collision_shape.shape is RectangleShape2D:
		var size: Vector2 = _collision_shape.shape.size
		rect = Rect2(_collision_shape.position - size * 0.5, size)
	else:
		rect = _collision_shape.shape.get_rect()
		rect.position += _collision_shape.position
	draw_rect(rect, Color(1, 1, 0, 0.3))
