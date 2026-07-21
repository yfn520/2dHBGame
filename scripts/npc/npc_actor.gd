class_name NpcActor
extends Node2D

var npc_id := 0
var instance_id := ""
var interaction_radius := 96.0

var _sprite: AnimatedSprite2D
var _name_label: Label
var _quest_label: Label


func setup(config: Dictionary, placement: Dictionary) -> bool:
	npc_id = int(config.get("id", 0))
	instance_id = String(placement.get("instance_id", "npc_%d" % npc_id))
	name = instance_id
	interaction_radius = float(placement.get("interaction_radius", 0.0))
	if interaction_radius <= 0.0:
		interaction_radius = float(config.get("interaction_radius", 96.0))
	global_position = Vector2(float(placement.get("x", 0.0)), float(placement.get("y", 0.0)))
	var authored_scale := maxf(0.01, float(placement.get("scale", config.get("scale", 1.0))))
	scale = Vector2.ONE * authored_scale
	_build_nodes(config)
	var facing := String(placement.get("facing", ""))
	if facing.is_empty():
		facing = String(config.get("facing", "right"))
	_sprite.flip_h = facing == "left"
	return _load_visual(config)


func get_display_name() -> String:
	return _name_label.text if _name_label != null else "NPC"


func refresh_quest_indicator() -> void:
	if _quest_label == null or GameRegistry.quest_service == null:
		return
	if GameRegistry.quest_service.has_ready_quest(npc_id):
		_quest_label.text = "?"
		_quest_label.modulate = Color("58c7ff")
	elif GameRegistry.quest_service.has_available_quest(npc_id):
		_quest_label.text = "!"
		_quest_label.modulate = Color("ffd84d")
	else:
		_quest_label.text = ""


func _build_nodes(config: Dictionary) -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = true
	add_child(_sprite)

	var area := Area2D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = 0
	add_child(area)
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape_node.shape = circle
	area.add_child(shape_node)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = String(config.get("name", "NPC"))
	_name_label.position = Vector2(-80, 8)
	_name_label.size = Vector2(160, 26)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 4)
	add_child(_name_label)

	_quest_label = Label.new()
	_quest_label.name = "QuestIndicator"
	_quest_label.position = Vector2(-24, -142)
	_quest_label.size = Vector2(48, 44)
	_quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_label.add_theme_font_size_override("font_size", 32)
	_quest_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_quest_label.add_theme_constant_override("outline_size", 6)
	add_child(_quest_label)
	refresh_quest_indicator()


func _load_visual(config: Dictionary) -> bool:
	var asset := String(config.get("asset", ""))
	var frames_path := asset.path_join("godot/spriteframes.tres")
	if asset.is_empty() or not ResourceLoader.exists(frames_path):
		push_warning("NPC %d 素材不存在: %s" % [npc_id, frames_path])
		return false
	var frames := load(frames_path) as SpriteFrames
	if frames == null:
		return false
	_sprite.sprite_frames = frames
	var idle := String(config.get("idle_animation", "idle"))
	if not frames.has_animation(idle):
		idle = String(frames.get_animation_names()[0]) if not frames.get_animation_names().is_empty() else ""
	if idle.is_empty():
		return false
	_sprite.play(idle)
	# 当前角色导出以 240x240 为基准，脚底约在图像下方；NPC 根节点代表脚底。
	_sprite.position.y = -120.0
	return true
