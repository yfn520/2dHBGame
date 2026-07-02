class_name CombatDebugOverlay
extends Node2D

var _entity: Node2D


func setup(entity: Node2D) -> void:
	_entity = entity
	z_as_relative = false
	z_index = 4096
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _entity == null or not is_instance_valid(_entity):
		return
	if DebugDraw.show_collision:
		_draw_shape(_entity.get_node_or_null("CollisionShape2D"), Color(0, 1, 0, 0.3))
	if DebugDraw.show_hurtbox:
		var hurt_box := _entity.get_node_or_null("HurtBox")
		if hurt_box != null:
			_draw_shape(hurt_box.get_node_or_null("CollisionShape2D"), Color(1, 1, 0, 0.3))
	if DebugDraw.show_hitbox:
		var hit_box := _entity.get_node_or_null("HitBox")
		if hit_box != null and hit_box.has_method("is_active") and hit_box.is_active():
			_draw_shape(hit_box.get_node_or_null("CollisionShape2D"), Color(1, 0, 0, 0.35))


func _draw_shape(collision: CollisionShape2D, color: Color) -> void:
	if collision == null or collision.shape == null:
		return
	var rect: Rect2
	if collision.shape is RectangleShape2D:
		var size := (collision.shape as RectangleShape2D).size
		var center := to_local(collision.global_position)
		rect = Rect2(center - size * 0.5, size)
	else:
		rect = collision.shape.get_rect()
		rect.position += to_local(collision.global_position)
	draw_rect(rect, color)
