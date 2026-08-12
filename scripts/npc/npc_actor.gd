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
	instance_id = str(placement.get("instance_id", ""))
	if npc_id <= 0 or instance_id.is_empty():
		push_error("NPC 实例缺少 npc_id 或 instance_id")
		return false
	name = instance_id
	interaction_radius = float(placement.get("interaction_radius", 0.0))
	global_position = Vector2(float(placement.get("x", 0.0)), float(placement.get("y", 0.0)))
	# 根节点保持世界单位；交互范围不应随 NPC 的纯视觉缩放而改变。
	var placement_scale := maxf(0.01, float(placement.get("scale", 1.0)))
	if not _load_visual(config):
		return false
	# 统一体型 auto-clamp：按帧纹理高度把视觉缩放收敛到 [140,200] 目标体型。
	# placement.scale 现作为 auto-clamp 之上的可选微调倍率（默认 1.0）。
	var authored_height := _read_authored_visual_height()
	var display_scale := EntityAutoScaler.compute_scale(authored_height, placement_scale) if authored_height > 0.0 else placement_scale
	_visual.scale = Vector2.ONE * display_scale
	_build_interaction_area()
	var facing := str(placement.get("facing", config.get("default_facing", "right")))
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
		# 圆圈：目标已完成，可向该 NPC 交付。
		_quest_label.text = "○"
		_quest_label.modulate = Color("58c7ff")
	elif GameRegistry.quest_service.has_active_quest(npc_id):
		# 感叹号：该 NPC 对应的任务正在进行。
		_quest_label.text = "!"
		_quest_label.modulate = Color("ffd84d")
	elif GameRegistry.quest_service.has_available_quest(npc_id):
		# 问号：有满足前置、现在可接取的任务。
		_quest_label.text = "?"
		_quest_label.modulate = Color("f1e7bd")
	else:
		_quest_label.text = ""


## 实例化 npc_visual.tscn；所有视觉布局已在生成时写好，这里只取节点引用。
func _load_visual(config: Dictionary) -> bool:
	var asset := config.get("asset_data", {}) as Dictionary
	var visual_path := str(asset.get("visual_scene", ""))
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
	var default_animation := str(asset.get("default_animation", ""))
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(default_animation):
		push_error("NPC %d 缺少默认动画: %s" % [npc_id, default_animation])
		_visual.queue_free()
		return false
	_sprite.play(default_animation)
	# 切帧速度统一减半，让 idle 动作更舒缓
	_sprite.speed_scale = 0.5
	_name_label = _visual.get_node_or_null("NameLabel") as Label
	_quest_label = _visual.get_node_or_null("QuestLabel") as Label
	if _name_label == null or _quest_label == null:
		push_error("NPC %d visual_scene must contain NameLabel and QuestLabel" % npc_id)
		_visual.queue_free()
		return false
	return true


## 读取 NPC authored 视觉高度：取默认动画首帧纹理高度（帧画布尺寸）。
## 用于 EntityAutoScaler 把视觉缩放收敛到统一目标体型。资源缺失返回 0（不 clamp）。
func _read_authored_visual_height() -> float:
	if _sprite == null or _sprite.sprite_frames == null:
		return 0.0
	var anim: StringName = _sprite.animation if not _sprite.animation.is_empty() else "idle"
	if not _sprite.sprite_frames.has_animation(anim) or _sprite.sprite_frames.get_frame_count(anim) == 0:
		return 0.0
	var tex := _sprite.sprite_frames.get_frame_texture(anim, 0)
	if tex == null:
		return 0.0
	return float(tex.get_height())


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
	_name_label.text = str(config.get("name", "NPC"))
