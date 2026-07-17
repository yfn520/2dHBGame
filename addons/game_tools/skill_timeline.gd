@tool
extends Control

signal frame_selected(frame: int)
signal node_selected(index: int)

const HEADER_HEIGHT := 28.0
const LANE_HEIGHT := 30.0
const NODE_ROW_HEIGHT := 26.0
const LEFT_LABEL_WIDTH := 92.0
const EVENT_LABELS := {"release": "释放", "impact": "命中", "effect": "效果"}
const NODE_LABELS := {
	"play_animation": "播放动画",
	"melee_damage": "近战伤害",
	"area_damage": "范围伤害",
	"fullscreen_damage": "全场伤害",
	"spawn_projectile": "发射弹道",
	"play_effect": "播放特效",
	"apply_target_buff": "施加目标 Buff",
	"apply_self_buff": "施加自身 Buff",
	"heal": "治疗",
	"move_x": "水平移动",
	"wait_action_event": "等待动作事件",
	"wait_action_frame": "等待动作帧",
	"wait_hit_window": "等待攻击有效区间",
	"wait_animation_end": "等待动画结束",
	"wait_time": "等待时长",
	"end_skill": "结束技能",
}
const ACTION_NODES := ["play_animation", "melee_damage", "area_damage", "fullscreen_damage", "spawn_projectile", "play_effect", "apply_target_buff", "apply_self_buff", "heal", "move_x"]

var _action: Dictionary = {}
var _nodes: Array = []
var _frame_count := 8
var _current_frame := 0
var _selected_node := -1
var _dragging_frame := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(600, 150)


func set_timeline(action: Dictionary, nodes: Array, frame_count: int, current_frame: int, selected_node := -1) -> void:
	_action = action
	_nodes = nodes
	_frame_count = maxi(1, frame_count)
	_current_frame = clampi(current_frame, 0, _frame_count - 1)
	_selected_node = selected_node
	custom_minimum_size.y = _timeline_height()
	queue_redraw()


func set_selected_node(index: int) -> void:
	_selected_node = index
	queue_redraw()


func set_current_frame(frame: int) -> void:
	_current_frame = clampi(frame, 0, _frame_count - 1)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("171b22"), true)
	var width := maxf(1.0, size.x - LEFT_LABEL_WIDTH)
	var frame_width := width / float(maxi(1, _frame_count - 1))
	var lanes := ["帧", "动画事件", "有效区间"]
	for lane_index in range(lanes.size()):
		var y := float(lane_index) * LANE_HEIGHT
		draw_rect(Rect2(0, y, size.x, LANE_HEIGHT), Color("202631") if lane_index % 2 == 0 else Color("1b2029"), true)
		draw_string(ThemeDB.fallback_font, Vector2(9, y + 20), lanes[lane_index], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c7ced9"))
	var node_y := _node_area_y()
	draw_rect(Rect2(0, node_y, size.x, _node_area_height()), Color("202631"), true)
	draw_string(ThemeDB.fallback_font, Vector2(9, node_y + 20), "技能节点", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c7ced9"))
	for index in range(_nodes.size()):
		var row_y := node_y + float(index) * NODE_ROW_HEIGHT
		if index % 2 == 1:
			draw_rect(Rect2(LEFT_LABEL_WIDTH, row_y, size.x - LEFT_LABEL_WIDTH, NODE_ROW_HEIGHT), Color("1b2029"), true)
		draw_line(Vector2(LEFT_LABEL_WIDTH, row_y + NODE_ROW_HEIGHT), Vector2(size.x, row_y + NODE_ROW_HEIGHT), Color("303846"), 1.0)
	for frame in range(_frame_count):
		var x := LEFT_LABEL_WIDTH + float(frame) * frame_width
		var color := Color("465267") if frame % 5 == 0 else Color("303846")
		draw_line(Vector2(x, HEADER_HEIGHT), Vector2(x, node_y + _node_area_height()), color, 1.0)
		if frame % 5 == 0 or frame == _frame_count - 1:
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, 17), str(frame), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9aa6b6"))
	var cursor_x := LEFT_LABEL_WIDTH + float(_current_frame) * frame_width
	draw_line(Vector2(cursor_x, 0), Vector2(cursor_x, node_y + _node_area_height()), Color("64b5f6"), 2.0)
	_draw_events(frame_width)
	_draw_windows(frame_width)
	_draw_nodes(frame_width)


func _draw_events(frame_width: float) -> void:
	for value in _action.get("events", []):
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		var x := LEFT_LABEL_WIDTH + float(int(event.get("frame", 0))) * frame_width
		draw_circle(Vector2(x, LANE_HEIGHT + 15), 5.0, Color("ffca64"))
		draw_string(ThemeDB.fallback_font, Vector2(x + 7, LANE_HEIGHT + 20), String(EVENT_LABELS.get(String(event.get("name", "")), event.get("name", "事件"))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ffca64"))


func _draw_windows(frame_width: float) -> void:
	var windows: Array = _action.get("hit_windows", [])
	for index in range(windows.size()):
		if not windows[index] is Dictionary:
			continue
		var window: Dictionary = windows[index]
		var start_frame := int(window.get("start_frame", 0))
		var end_frame := int(window.get("end_frame", start_frame))
		var x := LEFT_LABEL_WIDTH + float(start_frame) * frame_width
		var rect_width := maxf(frame_width, float(end_frame - start_frame + 1) * frame_width)
		draw_rect(Rect2(x, LANE_HEIGHT * 2 + 5, rect_width, LANE_HEIGHT - 10), Color(0.3, 0.72, 0.48, 0.72), true)
		draw_string(ThemeDB.fallback_font, Vector2(x + 5, LANE_HEIGHT * 2 + 23), "#%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _draw_nodes(frame_width: float) -> void:
	var frames := _node_frames()
	for index in range(_nodes.size()):
		if not _nodes[index] is Dictionary:
			continue
		var node: Dictionary = _nodes[index]
		var x := LEFT_LABEL_WIDTH + float(frames[index]) * frame_width
		var row_y := _node_area_y() + float(index) * NODE_ROW_HEIGHT
		var color := Color("64b5f6") if index == _selected_node else Color("b18cff")
		draw_circle(Vector2(x, row_y + NODE_ROW_HEIGHT * 0.5), 6.0, color)
		var label_x := clampf(x + 10.0, LEFT_LABEL_WIDTH + 8.0, maxf(LEFT_LABEL_WIDTH + 8.0, size.x - 210.0))
		draw_string(ThemeDB.fallback_font, Vector2(label_x, row_y + 18), "%02d [%s] %s" % [index + 1, "动作" if ACTION_NODES.has(String(node.get("type", ""))) else "控制", String(NODE_LABELS.get(String(node.get("type", "")), node.get("type", "节点")))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _node_frames() -> Array[int]:
	var result: Array[int] = []
	var cursor := 0
	for value in _nodes:
		var node: Dictionary = value if value is Dictionary else {}
		var node_type := String(node.get("type", ""))
		if node_type == "wait_action_event":
			cursor = _event_frame(String(node.get("event", "release")), cursor)
		elif node_type == "wait_action_frame":
			cursor = int(node.get("frame", cursor))
		elif node_type == "wait_hit_window":
			cursor = _window_frame(int(node.get("hit_window_index", 0)), cursor)
		elif node_type == "wait_animation_end" or node_type == "end_skill":
			cursor = _frame_count - 1
		result.append(cursor)
	return result


func _event_frame(event_name: String, fallback: int) -> int:
	for value in _action.get("events", []):
		if value is Dictionary and String(value.get("name", "")) == event_name:
			return int(value.get("frame", fallback))
	return fallback


func _window_frame(index: int, fallback: int) -> int:
	var windows: Array = _action.get("hit_windows", [])
	if index >= 0 and index < windows.size() and windows[index] is Dictionary:
		return int((windows[index] as Dictionary).get("start_frame", fallback))
	return fallback


func _timeline_height() -> float:
	return LANE_HEIGHT * 3.0 + _node_area_height()


func _node_area_height() -> float:
	return maxf(1.0, float(_nodes.size())) * NODE_ROW_HEIGHT


func _node_area_y() -> float:
	return LANE_HEIGHT * 3.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_frame = event.pressed
		if event.pressed:
			_pick(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging_frame:
		_pick_frame(event.position.x)
		accept_event()


func _pick(position: Vector2) -> void:
	_pick_frame(position.x)
	var row := int(floor((position.y - _node_area_y()) / NODE_ROW_HEIGHT))
	if row >= 0 and row < _nodes.size():
		node_selected.emit(row)


func _pick_frame(x: float) -> void:
	var width := maxf(1.0, size.x - LEFT_LABEL_WIDTH)
	var frame_width := width / float(maxi(1, _frame_count - 1))
	_current_frame = clampi(roundi((x - LEFT_LABEL_WIDTH) / frame_width), 0, _frame_count - 1)
	frame_selected.emit(_current_frame)
	queue_redraw()
