class_name WorldAreaTrigger
extends Area2D

## 世界区域触发器：玩家进入矩形区域后，把配置中的事件交给 QuestService。
## 触发器本身不推进剧情；时间轴的 area_event 门负责决定下一段何时放行。

var content: Dictionary = {}
var _fired := false


func setup(data: Dictionary) -> void:
	content = data.duplicate(true)
	name = "AreaEvent_%s" % str(content.get("id", "trigger"))
	global_position = Vector2(float(content.get("x", 0.0)), float(content.get("y", 0.0)))
	collision_layer = 0
	# 玩家 CharacterBody2D 未显式设置 collision_layer，默认在第 1 层
	#（第 2 层是梯子，见 LadderDetector）；掩码必须覆盖第 1 层才会触发，
	# 只写 2 的话 body_entered 永远不会命中玩家（hub_street_walk 曾因此全图走完也不触发）。
	collision_mask = 1 | 2
	monitoring = true
	monitorable = false
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(
		maxf(1.0, float(content.get("width", 180.0))),
		maxf(1.0, float(content.get("height", 220.0))),
	)
	shape_node.shape = rectangle
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	_build_debug_visual()


func _on_body_entered(body: Node2D) -> void:
	if _fired or body == null or not body.is_in_group("player"):
		return
	var event_name := str(content.get("event_name", "")).strip_edges()
	if event_name.is_empty() or GameRegistry.quest_service == null:
		return
	_fired = true
	GameRegistry.quest_service.record_area_event(event_name)
	GameRegistry.save_game()
	var ui_root := get_tree().get_first_node_in_group("ui_root")
	if ui_root != null and ui_root.has_method("show_notification"):
		ui_root.show_notification("已进入：%s" % str(content.get("name", event_name)))


func _build_debug_visual() -> void:
	if not bool(content.get("debug_visible", false)):
		return
	var width := maxf(1.0, float(content.get("width", 180.0)))
	var height := maxf(1.0, float(content.get("height", 220.0)))
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([
		Vector2(-width * 0.5, -height * 0.5),
		Vector2(width * 0.5, -height * 0.5),
		Vector2(width * 0.5, height * 0.5),
		Vector2(-width * 0.5, height * 0.5),
	])
	marker.color = Color(0.35, 0.85, 0.95, 0.12)
	add_child(marker)
	var label := Label.new()
	label.text = str(content.get("name", content.get("event_name", "区域触发")))
	label.position = Vector2(-width * 0.5, -height * 0.5 - 28.0)
	label.size = Vector2(width, 24.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("b8f3ff"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
