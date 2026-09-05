class_name WorldTaskVisual
extends Node2D

## 任务世界物件的轻量表现层。
##
## runtime_world_content.json 是由工作台发布的纯数据，不要求每个条目都先配一张专用贴图。
## 本节点按条目的 type/name/event_name 组合出可辨认的场景物：区域目标有路标和边界桩，
## 护送任务有粮车，信标/机关/证物也各有不同轮廓。这样新发布的任务条目不会退化成
## 空白触发框；后续接入正式美术时只需替换这个表现层，不会影响任务契约或碰撞逻辑。

const OUTLINE := Color("1b2430")
const ROUTE := Color(0.24, 0.82, 0.88, 0.30)
const ACCENT := Color("7ce6ed")
const WARM := Color("ffd166")

var content: Dictionary = {}


func setup(data: Dictionary) -> void:
	content = data.duplicate(true)
	name = "TaskVisual_%s" % str(content.get("id", "content"))
	var content_type := str(content.get("type", ""))
	if content_type == "area_event":
		_build_area_event()
	else:
		_build_interactable(content_type)


func _build_area_event() -> void:
	var width := maxf(120.0, float(content.get("width", 240.0)))
	_build_route(width)
	var semantic := _semantic_kind()
	match semantic:
		"escort":
			_build_cart()
		"beacon":
			_build_beacon()
		"camp":
			_build_camp()
		"gate":
			_build_gate()
		"echo":
			_build_echo_node()
		_:
			_build_waystone()
	_add_label(str(content.get("name", "任务区域")), Vector2(-100.0, -126.0), Vector2(200.0, 24.0), ACCENT)


func _build_interactable(content_type: String) -> void:
	var semantic := _semantic_kind()
	if content_type == "pickup":
		_build_pickup(semantic)
		_add_label(str(content.get("name", "任务物品")), Vector2(-82.0, -74.0), Vector2(164.0, 24.0), WARM)
		return
	match semantic:
		"beacon":
			_build_beacon()
		"windmill":
			_build_windmill()
		"bell":
			_build_bell()
		"gate":
			_build_gate()
		"echo", "star":
			_build_echo_node()
		_:
			_build_waystone()
	_add_label(str(content.get("name", "任务交互")), Vector2(-88.0, -96.0), Vector2(176.0, 24.0), Color("8ee38e"))


func _semantic_kind() -> String:
	var text := "%s %s %s" % [str(content.get("name", "")), str(content.get("event_name", "")), str(content.get("id", ""))]
	if text.contains("护送") or text.contains("粮") or text.contains("押送") or text.contains("cart") or text.contains("mail_route"):
		return "escort"
	if text.contains("信标") or text.contains("beacon") or text.contains("烛塔") or text.contains("tower"):
		return "beacon"
	if text.contains("营地") or text.contains("camp"):
		return "camp"
	if text.contains("风车") or text.contains("windmill"):
		return "windmill"
	if text.contains("钟") or text.contains("bell"):
		return "bell"
	if text.contains("门") or text.contains("gate") or text.contains("entry"):
		return "gate"
	if text.contains("星楔") or text.contains("starwedge"):
		return "star"
	if text.contains("回音") or text.contains("节点") or text.contains("锚链") or text.contains("航道"):
		return "echo"
	if str(content.get("type", "")) == "pickup":
		if text.contains("药"):
			return "medicine"
		if text.contains("导片") or text.contains("风车"):
			return "gear"
		if text.contains("信") or text.contains("页") or text.contains("记录") or text.contains("名册") or text.contains("证据"):
			return "document"
	return "marker"


func _build_route(width: float) -> void:
	# 细路线与两侧引导桩取代原来的整块调试矩形，仍然清楚地告诉玩家该往哪里走。
	_rect(Vector2(-width * 0.46, -12.0), Vector2(width * 0.92, 12.0), ROUTE)
	_rect(Vector2(-width * 0.46, -14.0), Vector2(width * 0.92, 2.0), ACCENT)
	for side_value in [-1.0, 1.0]:
		var x: float = float(side_value) * width * 0.42
		_rect(Vector2(x - 4.0, -84.0), Vector2(8.0, 78.0), Color("2b5c64"))
		_polygon(PackedVector2Array([Vector2(x - 15.0, -88.0), Vector2(x + 15.0, -88.0), Vector2(x, -112.0)]), ACCENT)


func _build_cart() -> void:
	# 粮种车：木底盘、两只车轮、装满粮袋的车斗。底部对齐任务点地面。
	_rect(Vector2(-68.0, -40.0), Vector2(130.0, 34.0), Color("8b5a2b"))
	_rect(Vector2(-62.0, -34.0), Vector2(118.0, 6.0), Color("d49a54"))
	_rect(Vector2(55.0, -19.0), Vector2(48.0, 7.0), Color("6d4425"))
	for x in [-46.0, -12.0, 22.0, 48.0]:
		_polygon(PackedVector2Array([Vector2(x - 15.0, -40.0), Vector2(x + 14.0, -40.0), Vector2(x + 11.0, -68.0), Vector2(x - 11.0, -68.0)]), Color("d9c474"))
		_polygon(PackedVector2Array([Vector2(x - 9.0, -68.0), Vector2(x + 7.0, -68.0), Vector2(x, -76.0)]), Color("f0dc8a"))
	_wheel(Vector2(-42.0, -3.0), 18.0)
	_wheel(Vector2(42.0, -3.0), 18.0)
	_rect(Vector2(-72.0, -7.0), Vector2(146.0, 5.0), OUTLINE)


func _build_beacon() -> void:
	_rect(Vector2(-5.0, -92.0), Vector2(10.0, 88.0), Color("704b32"))
	_rect(Vector2(-14.0, -72.0), Vector2(28.0, 5.0), Color("b88a4c"))
	_polygon(PackedVector2Array([Vector2(-17.0, -94.0), Vector2(0.0, -132.0), Vector2(17.0, -94.0)]), Color("ffb347"))
	_polygon(PackedVector2Array([Vector2(-8.0, -94.0), Vector2(0.0, -116.0), Vector2(8.0, -94.0)]), Color("fff3a3"))
	_circle(Vector2.ZERO + Vector2(0.0, -105.0), 28.0, Color(1.0, 0.68, 0.25, 0.16), 16)


func _build_camp() -> void:
	_polygon(PackedVector2Array([Vector2(-66.0, -8.0), Vector2(-18.0, -82.0), Vector2(30.0, -8.0)]), Color("537b70"))
	_polygon(PackedVector2Array([Vector2(-18.0, -82.0), Vector2(50.0, -8.0), Vector2(30.0, -8.0)]), Color("365754"))
	_rect(Vector2(40.0, -35.0), Vector2(36.0, 27.0), Color("815536"))
	_polygon(PackedVector2Array([Vector2(42.0, -35.0), Vector2(58.0, -60.0), Vector2(75.0, -35.0)]), Color("d49248"))
	_circle(Vector2(58.0, -41.0), 19.0, Color(1.0, 0.55, 0.22, 0.20), 14)


func _build_gate() -> void:
	_rect(Vector2(-58.0, -104.0), Vector2(16.0, 100.0), Color("617080"))
	_rect(Vector2(42.0, -104.0), Vector2(16.0, 100.0), Color("617080"))
	_rect(Vector2(-58.0, -104.0), Vector2(116.0, 17.0), Color("8aa0af"))
	_polygon(PackedVector2Array([Vector2(-51.0, -107.0), Vector2(0.0, -142.0), Vector2(51.0, -107.0)]), Color("6f8795"))
	_polygon(PackedVector2Array([Vector2(-36.0, -10.0), Vector2(-36.0, -79.0), Vector2(36.0, -79.0), Vector2(36.0, -10.0)]), Color("263b48"))


func _build_echo_node() -> void:
	_circle(Vector2(0.0, -26.0), 42.0, Color(0.34, 0.78, 0.96, 0.16), 18)
	_polygon(PackedVector2Array([Vector2(0.0, -116.0), Vector2(27.0, -47.0), Vector2(0.0, -8.0), Vector2(-27.0, -47.0)]), Color("59b8dc"))
	_polygon(PackedVector2Array([Vector2(0.0, -102.0), Vector2(12.0, -50.0), Vector2(0.0, -22.0), Vector2(-12.0, -50.0)]), Color("c8f5ff"))
	_rect(Vector2(-38.0, -8.0), Vector2(76.0, 7.0), Color("315264"))


func _build_waystone() -> void:
	_polygon(PackedVector2Array([Vector2(-26.0, -6.0), Vector2(-19.0, -83.0), Vector2(0.0, -104.0), Vector2(19.0, -83.0), Vector2(26.0, -6.0)]), Color("486270"))
	_polygon(PackedVector2Array([Vector2(-8.0, -76.0), Vector2(0.0, -91.0), Vector2(8.0, -76.0), Vector2(0.0, -61.0)]), ACCENT)
	_rect(Vector2(-38.0, -7.0), Vector2(76.0, 7.0), Color("2e4652"))


func _build_windmill() -> void:
	_polygon(PackedVector2Array([Vector2(-28.0, -6.0), Vector2(-18.0, -103.0), Vector2(18.0, -103.0), Vector2(28.0, -6.0)]), Color("8c6f4f"))
	_circle(Vector2(0.0, -108.0), 13.0, Color("d8c19a"), 12)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var tip := Vector2(cos(angle), sin(angle)) * 51.0
		var side := Vector2(cos(angle + 0.42), sin(angle + 0.42)) * 20.0
		_polygon(PackedVector2Array([Vector2.ZERO + Vector2(0.0, -108.0), Vector2(0.0, -108.0) + tip, Vector2(0.0, -108.0) + side]), Color("d9c8a7"))


func _build_bell() -> void:
	_rect(Vector2(-42.0, -104.0), Vector2(10.0, 100.0), Color("66513c"))
	_rect(Vector2(32.0, -104.0), Vector2(10.0, 100.0), Color("66513c"))
	_rect(Vector2(-42.0, -104.0), Vector2(84.0, 12.0), Color("9e7a4e"))
	_polygon(PackedVector2Array([Vector2(-24.0, -88.0), Vector2(0.0, -116.0), Vector2(24.0, -88.0), Vector2(19.0, -45.0), Vector2(-19.0, -45.0)]), Color("e0ad49"))
	_circle(Vector2(0.0, -40.0), 7.0, OUTLINE, 10)


func _build_pickup(semantic: String) -> void:
	if _build_pickup_item_icon():
		return
	match semantic:
		"medicine":
			_rect(Vector2(-27.0, -43.0), Vector2(54.0, 37.0), Color("b56a4a"))
			_rect(Vector2(-7.0, -53.0), Vector2(14.0, 12.0), Color("f0ddbf"))
			_rect(Vector2(-13.0, -28.0), Vector2(26.0, 8.0), Color("f5e6cb"))
			_rect(Vector2(-4.0, -38.0), Vector2(8.0, 27.0), Color("f5e6cb"))
		"gear":
			_circle(Vector2(0.0, -37.0), 29.0, Color("b7ced6"), 12)
			_circle(Vector2(0.0, -37.0), 10.0, Color("4a6875"), 12)
		"document":
			_polygon(PackedVector2Array([Vector2(-27.0, -60.0), Vector2(20.0, -60.0), Vector2(28.0, -51.0), Vector2(28.0, -8.0), Vector2(-27.0, -8.0)]), Color("e7d7a1"))
			_rect(Vector2(-17.0, -45.0), Vector2(33.0, 4.0), Color("9f7c4a"))
			_rect(Vector2(-17.0, -33.0), Vector2(24.0, 4.0), Color("9f7c4a"))
		_:
			_polygon(PackedVector2Array([Vector2(-30.0, -14.0), Vector2(-20.0, -55.0), Vector2(0.0, -69.0), Vector2(20.0, -55.0), Vector2(30.0, -14.0)]), Color("b8874e"))
			_polygon(PackedVector2Array([Vector2(-20.0, -55.0), Vector2(0.0, -69.0), Vector2(20.0, -55.0), Vector2(0.0, -39.0)]), Color("dfbd72"))
	_circle(Vector2(0.0, -37.0), 42.0, Color(1.0, 0.82, 0.35, 0.12), 16)


func _build_pickup_item_icon() -> bool:
	# items.json 的 icon 路径只有在真实 PNG 已生成时才使用；缺图时保留语义占位物，
	# 让新发布的任务不会因为美术尚未补齐而变成不可见或报资源加载错误。
	if GameRegistry.item_config == null:
		return false
	var item_id := int(content.get("item_id", 0))
	if item_id <= 0:
		return false
	var item: Dictionary = GameRegistry.item_config.get_item(item_id)
	var icon_path := str(item.get("icon", ""))
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return false
	var texture := load(icon_path) as Texture2D
	if texture == null:
		return false
	var source_size := texture.get_size()
	var scale_factor := 84.0 / maxf(source_size.x, source_size.y)
	var icon := Sprite2D.new()
	icon.name = "TaskPickupItemIcon"
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(0.0, -43.0)
	icon.scale = Vector2.ONE * scale_factor
	add_child(icon)
	_circle(Vector2(0.0, -12.0), 43.0, Color(1.0, 0.82, 0.35, 0.14), 16)
	return true


func _wheel(center: Vector2, radius: float) -> void:
	_circle(center, radius, Color("3b302b"), 14)
	_circle(center, radius * 0.56, Color("9d7047"), 14)
	_circle(center, radius * 0.20, Color("e2c28b"), 12)


func _rect(top_left: Vector2, size: Vector2, color: Color) -> void:
	_polygon(PackedVector2Array([
		top_left,
		top_left + Vector2(size.x, 0.0),
		top_left + size,
		top_left + Vector2(0.0, size.y),
	]), color)


func _circle(center: Vector2, radius: float, color: Color, points: int) -> void:
	var polygon := PackedVector2Array()
	for index in range(points):
		polygon.append(center + Vector2(cos(TAU * float(index) / float(points)), sin(TAU * float(index) / float(points))) * radius)
	_polygon(polygon, color)


func _polygon(points: PackedVector2Array, color: Color) -> void:
	var node := Polygon2D.new()
	node.polygon = points
	node.color = color
	add_child(node)


func _add_label(text: String, position_value: Vector2, size_value: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
