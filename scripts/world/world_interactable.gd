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
	var ui_root := get_tree().get_first_node_in_group("ui_root")
	if ui_root != null and ui_root.has_method("show_notification"):
		ui_root.show_notification("获得 %s ×%d" % [get_display_name(), count])
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
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([Vector2(-18, 0), Vector2(0, -34), Vector2(18, 0), Vector2(0, 10)])
	marker.color = Color("7ee8fa") if str(content.get("type", "")) == "portal" else Color("ffd166")
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
