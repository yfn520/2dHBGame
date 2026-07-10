@tool
extends Control

signal frame_selected(frame: int)
signal node_selected(index: int)

const HEADER_HEIGHT := 28.0
const LANE_HEIGHT := 32.0
const NODE_ROW_HEIGHT := 26.0
const LEFT_LABEL_WIDTH := 92.0
const EVENT_LABELS := {
	"release": "释放",
	"impact": "命中",
	"effect": "效果",
}
const NODE_LABELS := {
	"play_animation": "播放动画",
	"wait_action_event": "等待动作事件",
	"wait_animation_end": "等待动画结束（阻塞）",
	"use_action_hit_window": "攻击/技能生效点",
	"execute_skill_effect": "执行技能效果",
	"spawn_projectile": "弹道发射",
	"aoe": "范围攻击",
	"fullscreen": "全屏效果",
	"apply_self_buff": "施加自身 Buff",
	"heal": "治疗",
	"move_x": "水平移动",
	"play_effect": "播放特效",
	"end_skill": "结束技能（立即结束）",
}

var _action: Dictionary = {}
var _nodes: Array = []
var _skill_type := ""
var _frame_count := 8
var _current_frame := 0
var _selected_node := -1
var _dragging_frame := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(600, 150)
	set_process_input(true)


func set_timeline(action: Dictionary, nodes: Array, frame_count: int, current_frame: int, selected_node: int = -1, skill_type: String = "") -> void:
	_action = action
	_nodes = nodes
	_skill_type = skill_type
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
	var timeline_width := maxf(1.0, size.x - LEFT_LABEL_WIDTH)
	var frame_width := timeline_width / float(maxi(1, _frame_count - 1))
	var lanes := ["帧", "动画事件", "有效区间"]
	for lane_index in range(lanes.size()):
		var y := float(lane_index) * LANE_HEIGHT
		draw_rect(Rect2(0, y, size.x, LANE_HEIGHT), Color("202631") if lane_index % 2 == 0 else Color("1b2029"), true)
		draw_string(ThemeDB.fallback_font, Vector2(10, y + 21), lanes[lane_index], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("c7ced9"))
	var node_y := _node_area_y()
	draw_rect(Rect2(0, node_y, size.x, _node_area_height()), Color("202631"), true)
	draw_string(ThemeDB.fallback_font, Vector2(10, node_y + 21), "技能节点", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("c7ced9"))
	for index in range(_nodes.size()):
		var row_y := node_y + float(index) * NODE_ROW_HEIGHT
		if index % 2 == 1:
			draw_rect(Rect2(LEFT_LABEL_WIDTH, row_y, size.x - LEFT_LABEL_WIDTH, NODE_ROW_HEIGHT), Color("1b2029"), true)
		draw_line(Vector2(LEFT_LABEL_WIDTH, row_y + NODE_ROW_HEIGHT), Vector2(size.x, row_y + NODE_ROW_HEIGHT), Color("303846"), 1.0)
	for frame in range(_frame_count):
		var x := LEFT_LABEL_WIDTH + float(frame) * frame_width
		var line_color := Color("303846") if frame % 5 != 0 else Color("465267")
		draw_line(Vector2(x, HEADER_HEIGHT), Vector2(x, node_y + _node_area_height()), line_color, 1.0)
		if frame % 5 == 0 or frame == _frame_count - 1:
			draw_string(ThemeDB.fallback_font, Vector2(x + 3, 18), str(frame), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9aa6b6"))
	var current_x := LEFT_LABEL_WIDTH + float(_current_frame) * frame_width
	draw_line(Vector2(current_x, 0), Vector2(current_x, node_y + _node_area_height()), Color("64b5f6"), 2.0)
	_draw_events(frame_width)
	_draw_windows(frame_width)
	_draw_nodes(frame_width)


func _draw_events(frame_width: float) -> void:
	var events: Array = _action.get("events", [])
	for value in events:
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		var frame := int(event.get("frame", 0))
		var x := LEFT_LABEL_WIDTH + float(frame) * frame_width
		draw_circle(Vector2(x, LANE_HEIGHT + 16), 5.0, Color("ffca64"))
		draw_string(ThemeDB.fallback_font, Vector2(x + 7, LANE_HEIGHT + 21), _event_label(String(event.get("name", "event"))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ffca64"))


func _draw_windows(frame_width: float) -> void:
	var windows: Array = _action.get("hit_windows", [])
	for index in range(windows.size()):
		if not windows[index] is Dictionary:
			continue
		var window: Dictionary = windows[index]
		var start_frame := int(window.get("start_frame", 0))
		var end_frame := int(window.get("end_frame", start_frame))
		var x := LEFT_LABEL_WIDTH + float(start_frame) * frame_width
		var width := maxf(frame_width, float(end_frame - start_frame + 1) * frame_width)
		draw_rect(Rect2(x, LANE_HEIGHT * 2 + 5, width, LANE_HEIGHT - 10), Color(0.3, 0.72, 0.48, 0.72), true)
		draw_string(ThemeDB.fallback_font, Vector2(x + 5, LANE_HEIGHT * 2 + 25), "#%d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _draw_nodes(frame_width: float) -> void:
	for index in range(_nodes.size()):
		if not _nodes[index] is Dictionary:
			continue
		var node: Dictionary = _nodes[index]
		var frame := _node_frame(node)
		var x := LEFT_LABEL_WIDTH + float(frame) * frame_width
		var color := Color("64b5f6") if index == _selected_node else Color("b18cff")
		var row_y := _node_area_y() + float(index) * NODE_ROW_HEIGHT
		var label_x := clampf(x + 10.0, LEFT_LABEL_WIDTH + 8.0, maxf(LEFT_LABEL_WIDTH + 8.0, size.x - 190.0))
		draw_circle(Vector2(x, row_y + NODE_ROW_HEIGHT * 0.5), 6.0, color)
		if absf(label_x - x) > 10.0:
			draw_line(Vector2(x + 7.0, row_y + NODE_ROW_HEIGHT * 0.5), Vector2(label_x - 3.0, row_y + NODE_ROW_HEIGHT * 0.5), color, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(label_x, row_y + 18), "%02d  %s" % [index + 1, _node_display_name(node)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _timeline_height() -> float:
	return LANE_HEIGHT * 3.0 + maxf(1.0, float(_nodes.size())) * NODE_ROW_HEIGHT


func _node_area_height() -> float:
	return maxf(1.0, float(_nodes.size())) * NODE_ROW_HEIGHT


func _node_area_y() -> float:
	return LANE_HEIGHT * 3.0


func _node_frame(node: Dictionary) -> int:
	var trigger := String(node.get("trigger", "immediate"))
	if trigger == "immediate" and String(node.get("type", "")) == "use_action_hit_window":
		var default_windows: Array = _action.get("hit_windows", [])
		if not default_windows.is_empty() and default_windows[0] is Dictionary:
			return int((default_windows[0] as Dictionary).get("start_frame", 0))
	match trigger:
		"event":
			var event_name := String(node.get("event", "release"))
			for value in _action.get("events", []):
				if value is Dictionary and String(value.get("name", "")) == event_name:
					return int(value.get("frame", 0))
		"hit_window":
			var windows: Array = _action.get("hit_windows", [])
			var index := clampi(int(node.get("hit_window_index", 0)), 0, maxi(0, windows.size() - 1))
			if index < windows.size() and windows[index] is Dictionary:
				return int((windows[index] as Dictionary).get("start_frame", 0))
		"animation_end":
			return _frame_count - 1
	return 0


func _node_display_name(node: Dictionary) -> String:
	var type_name := String(node.get("type", "节点"))
	if type_name == "use_action_hit_window":
		if bool(node.get("detects_hits", false)):
			return "近战伤害（判定框）"
		if _skill_type == "projectile" or _skill_type == "penetrate":
			return "弹道发射（判定框中心）"
	return String(NODE_LABELS.get(type_name, type_name))


func _event_label(event_name: String) -> String:
	return String(EVENT_LABELS.get(event_name, event_name))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_frame = event.pressed
		if event.pressed:
			_pick_at_position(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging_frame:
		_pick_frame(event.position.x)
		accept_event()


func _pick_at_position(position: Vector2) -> void:
	_pick_frame(position.x)
	var node_y := _node_area_y()
	if position.y < node_y:
		return
	var timeline_width := maxf(1.0, size.x - LEFT_LABEL_WIDTH)
	var frame_width := timeline_width / float(maxi(1, _frame_count - 1))
	var row := int(floor((position.y - node_y) / NODE_ROW_HEIGHT))
	if row < 0 or row >= _nodes.size():
		return
	var marker_x := LEFT_LABEL_WIDTH + float(_node_frame(_nodes[row])) * frame_width
	if absf(position.x - marker_x) <= 18.0 or position.x >= LEFT_LABEL_WIDTH:
		_selected_node = row
		node_selected.emit(row)
		queue_redraw()


func _pick_frame(x: float) -> void:
	var timeline_width := maxf(1.0, size.x - LEFT_LABEL_WIDTH)
	var frame_width := timeline_width / float(maxi(1, _frame_count - 1))
	var frame := roundi((x - LEFT_LABEL_WIDTH) / frame_width)
	frame = clampi(frame, 0, _frame_count - 1)
	_current_frame = frame
	frame_selected.emit(frame)
	queue_redraw()
