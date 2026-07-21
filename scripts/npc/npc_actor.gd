class_name NpcActor
extends Node2D

## NPC 实体：实例化 npc_visual.tscn，不做任何视觉位置计算。
## 所有布局（脚底锚点、标签位置、缩放）在工具端生成 npc_visual.tscn 时写好。

var npc_id := 0
var instance_id := ""
var interaction_radius := 96.0

var _visual: Node2D
var _sprite: AnimatedSprite2D
var _name_label: Label
var _quest_label: Label


func setup(config: Dictionary, placement: Dictionary) -> bool:
	npc_id = int(config.get("id", 0))
	instance_id = String(placement.get("instance_id", ""))
	if npc_id <= 0 or instance_id.is_empty():
		push_error("NPC 实例缺少 npc_id 或 instance_id")
		return false
	name = instance_id
	interaction_radius = float(placement.get("interaction_radius", 0.0))
	global_position = Vector2(float(placement.get("x", 0.0)), float(placement.get("y", 0.0)))
	scale = Vector2.ONE * float(placement.get("scale", 1.0))
	if not _load_visual(config):
		return false
	_build_interaction_area()
	var facing := String(placement.get("facing", config.get("default_facing", "right")))
	_sprite.flip_h = facing == "left"
	_update_name_label(config)
	refresh_quest_indicator()
	return true


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


## 实例化 npc_visual.tscn；所有视觉布局已在生成时写好，这里只取节点引用。
func _load_visual(config: Dictionary) -> bool:
	var asset := config.get("asset_data", {}) as Dictionary
	var visual_path := String(asset.get("visual_scene", ""))
	if visual_path.is_empty() or not ResourceLoader.exists(visual_path):
		push_error("NPC %d visual_scene 无效: %s" % [npc_id, visual_path])
		return false
	var scene := load(visual_path) as PackedScene
	if scene == null:
		push_error("NPC %d 无法加载 visual_scene: %s" % [npc_id, visual_path])
		return false
	var instance := scene.instantiate()
	if not instance is Node2D:
		instance.queue_free()
		push_error("NPC %d visual_scene 根节点必须是 Node2D" % npc_id)
		return false
	_visual = instance as Node2D
	add_child(_visual)
	_sprite = _visual.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		push_error("NPC %d visual_scene 缺少 AnimatedSprite2D" % npc_id)
		_visual.queue_free()
		return false
	var default_animation := String(asset.get("default_animation", ""))
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(default_animation):
		push_error("NPC %d 缺少默认动画: %s" % [npc_id, default_animation])
		_visual.queue_free()
		return false
	_sprite.play(default_animation)
	_name_label = _visual.get_node_or_null("NameLabel") as Label
	_quest_label = _visual.get_node_or_null("QuestLabel") as Label
	if _name_label == null or _quest_label == null:
		push_error("NPC %d visual_scene must contain NameLabel and QuestLabel" % npc_id)
		_visual.queue_free()
		return false
	return true


## InteractionArea 的 radius 来自 placement 数据（运行时决定），不放 npc_visual.tscn。
func _build_interaction_area() -> void:
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


func _update_name_label(config: Dictionary) -> void:
	if _name_label == null:
		return
	_name_label.text = String(config.get("name", "NPC"))
