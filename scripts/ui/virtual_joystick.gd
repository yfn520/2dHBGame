class_name TouchJoystick
extends Control
## 虚拟摇杆：处理 InputEventScreenTouch / InputEventScreenDrag，
## 输出归一化向量，并通过 InputMap 注入 MOVE_LEFT/RIGHT/UP/DOWN。
## 仅在触屏可用或编辑器强制预览时启用；PC 鼠标模拟触屏也能用。
##
## 默认布局：左下角圆形区域，半径 = max_radius。

signal joystick_changed(direction: Vector2)

@export var max_radius: float = 96.0
@export var dead_zone: float = 0.18

var _base_position: Vector2 = Vector2.ZERO
var _thumb_offset: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _active: bool = false

var _base_color: Color = Color(1.0, 1.0, 1.0, 0.18)
var _thumb_color: Color = Color(1.0, 1.0, 1.0, 0.45)
var _edge_color: Color = Color(1.0, 1.0, 1.0, 0.55)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 默认左下角：240x240，留 32px 边距
	if anchor_left == 0.0 and anchor_right == 0.0 and anchor_top == 0.0 and anchor_bottom == 0.0:
		anchor_left = 0.0
		anchor_top = 1.0
		anchor_right = 0.0
		anchor_bottom = 1.0
		offset_left = 32.0
		offset_top = -272.0
		offset_right = 272.0
		offset_bottom = -32.0
	_base_position = size * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_begin_touch(event.position, event.index)
		elif not event.pressed and event.index == _touch_index:
			_end_touch()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_touch(event.position)


func _begin_touch(position: Vector2, index: int) -> void:
	_touch_index = index
	_active = true
	_base_position = position
	_thumb_offset = Vector2.ZERO
	_update_thumb_visual()


func _update_touch(position: Vector2) -> void:
	var delta: Vector2 = position - _base_position
	var len: float = delta.length()
	if len > max_radius:
		delta = delta.normalized() * max_radius
	_thumb_offset = delta
	_update_thumb_visual()
	_emit_direction(_get_normalized_direction())


func _end_touch() -> void:
	_touch_index = -1
	_active = false
	_thumb_offset = Vector2.ZERO
	_update_thumb_visual()
	_emit_direction(Vector2.ZERO)
	# 释放所有方向 action
	_release_action(InputActions.MOVE_LEFT)
	_release_action(InputActions.MOVE_RIGHT)
	_release_action(InputActions.MOVE_UP)
	_release_action(InputActions.MOVE_DOWN)


func _get_normalized_direction() -> Vector2:
	var raw: Vector2 = _thumb_offset / max_radius
	if raw.length() < dead_zone:
		return Vector2.ZERO
	if raw.length() > 1.0:
		return raw.normalized()
	return raw


func _emit_direction(dir: Vector2) -> void:
	# 注入到 InputMap（动作按下/释放根据阈值切换）
	_set_action_state(InputActions.MOVE_LEFT, dir.x < -dead_zone)
	_set_action_state(InputActions.MOVE_RIGHT, dir.x > dead_zone)
	_set_action_state(InputActions.MOVE_UP, dir.y < -dead_zone)
	_set_action_state(InputActions.MOVE_DOWN, dir.y > dead_zone)
	joystick_changed.emit(dir)


func _set_action_state(action: String, pressed: bool) -> void:
	if pressed:
		if not Input.is_action_pressed(action):
			Input.action_press(action, 1.0)
	else:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _release_action(action: String) -> void:
	if Input.is_action_pressed(action):
		Input.action_release(action)


func _update_thumb_visual() -> void:
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = _base_position if _active else size * 0.5
	# 外圈底座
	draw_circle(center, max_radius, _base_color)
	draw_arc(center, max_radius, 0.0, TAU, 48, _edge_color, 2.0)
	# 摇杆头
	var thumb_pos: Vector2 = center + _thumb_offset
	draw_circle(thumb_pos, max_radius * 0.42, _thumb_color)
	draw_arc(thumb_pos, max_radius * 0.42, 0.0, TAU, 36, _edge_color, 1.5)
