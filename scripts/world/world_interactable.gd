class_name WorldInteractable
extends Node2D

var interaction_radius := 90.0
var content: Dictionary = {}
var _label: Label


func setup(data: Dictionary) -> void:
	content = data.duplicate(true)
	name = "World_%s" % str(content.get("id", "content"))
	global_position = Vector2(float(content.get("x", 0.0)), float(content.get("y", 0.0)))
	interaction_radius = float(content.get("interaction_radius", 90.0))
	_build_visual()


func get_display_name() -> String:
	return str(content.get("name", content.get("id", "互动点")))


func get_interaction_prompt() -> String:
	return "E  %s" % get_display_name()


func interact() -> bool:
	match str(content.get("type", "")):
		"pickup":
			return _collect_pickup()
		"named_event":
			return _trigger_named_event()
		"portal":
			return _use_portal()
		_:
			return false


func _collect_pickup() -> bool:
	if GameRegistry.inventory_provider == null or GameRegistry.quest_state == null:
		return false
	var state_key := "world_content:%s" % str(content.get("id", ""))
	if bool(GameRegistry.quest_state.get_flag(state_key, false)):
		return false
	var item_id := int(content.get("item_id", 0))
	var count := maxi(1, int(content.get("count", 1)))
	if item_id <= 0:
		return false
	GameRegistry.quest_state.set_flag(state_key, true)
	GameRegistry.inventory_provider.add_item(item_id, count)
	if GameRegistry.quest_service != null:
		GameRegistry.quest_service.record_collect(item_id)
		GameRegistry.quest_service.record_interact(str(content.get("id", "")))
		var event_name := str(content.get("event_name", ""))
		if not event_name.is_empty():
			GameRegistry.quest_service.record_area_event(event_name)
	var ui_root := get_tree().get_first_node_in_group("ui_root")
	if ui_root != null and ui_root.has_method("show_notification"):
		ui_root.show_notification("获得 %s ×%d" % [get_display_name(), count])
	GameRegistry.save_game()
	queue_free()
	return true


func _trigger_named_event() -> bool:
	if GameRegistry.quest_service == null or GameRegistry.quest_state == null:
		return false
	var event_name := str(content.get("event_name", "")).strip_edges()
	if event_name.is_empty() or bool(GameRegistry.quest_state.get_flag("event:%s" % event_name, false)):
		return false
	GameRegistry.quest_service.record_named_event(event_name)
	var ui_root := get_tree().get_first_node_in_group("ui_root")
	if ui_root != null and ui_root.has_method("show_notification"):
		ui_root.show_notification("已完成：%s" % get_display_name())
	GameRegistry.save_game()
	queue_free()
	return true


func _use_portal() -> bool:
	var target_level_id := int(content.get("target_level_id", -1))
	if target_level_id < 0 or GameRegistry.level_manager == null:
		return false
	GameRegistry.level_manager.load_level(target_level_id)
	return true


func _build_visual() -> void:
	var content_type := str(content.get("type", ""))
	if content_type == "portal":
		_build_portal_visual()
	else:
		var marker := Polygon2D.new()
		marker.polygon = PackedVector2Array([Vector2(-18, 0), Vector2(0, -34), Vector2(18, 0), Vector2(0, 10)])
		marker.color = Color("8ee38e") if content_type == "named_event" else Color("ffd166")
		add_child(marker)
	_label = Label.new()
	_label.text = get_display_name()
	_label.position = Vector2(-80, -64)
	_label.size = Vector2(160, 28)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


## 传送门视觉：青色光环序列帧动画（Q版手游特效库 SavantPortal），替代原菱形占位
func _build_portal_visual() -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.name = "PortalFX"
	var frames := SpriteFrames.new()
	if not frames.has_animation("portal"):
		frames.add_animation("portal")
	frames.set_animation_speed("portal", 12.0)
	var index := 1
	while ResourceLoader.exists("res://assets/effects/portal/SavantPortal_%d.png" % index):
		frames.add_frame("portal", load("res://assets/effects/portal/SavantPortal_%d.png" % index))
		index += 1
	sprite.sprite_frames = frames
	# 光环中心略高于交互点，与地面贴合
	sprite.position = Vector2(0, -12)
	sprite.play("portal")
	add_child(sprite)
