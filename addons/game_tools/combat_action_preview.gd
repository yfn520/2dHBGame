@tool
extends Control

# 特效层拖拽时发射当前偏移（绘制空间绝对值，已含 visual_scale 和 body_center_y）
signal effect_offset_changed(offset: Vector2)

var frame_texture: Texture2D
var sprite_scale := 1.0
var frame_index := 0
var window_data: Dictionary = {}
var facing_right := false
var sprite_position := Vector2.ZERO
var sprite_offset := Vector2.ZERO
var sprite_node_scale := Vector2.ONE
var sprite_centered := true
var root_position := Vector2.ZERO

## Keep the actor foot/root below the vertical centre so tall sprites retain
## headroom. Every root-relative overlay uses this same display origin, so the
## authored offsets for effects, projectiles, hit boxes and ranges stay intact.
const PREVIEW_FOOT_Y_RATIO := 0.62

# 特效预览层：承载 play_effect 节点配置的特效场景实例
var _effect_layer: Node2D
var _effect_clip: Control
var _effect_scene: PackedScene
var _effect_offset := Vector2.ZERO
var _effect_active := false
var _effect_visual_scale := 1.0
## Projectile node.scale is a visual-only multiplier at runtime. Keep it
## separate from the scene-root scale so CollisionShape2D is not enlarged.
var _effect_visual_only_scale := 1.0
var _effect_is_local := false
var _effect_is_fullscreen := false
# 弹道镜像/旋转修正（spawn_projectile 的 mirror / rotation_degrees）
var _effect_mirror := false
var _effect_rotation_degrees := 0.0
var _effect_tint := Color.WHITE
var _effect_blend_mode := "normal"

# 拖拽调整 buff 特效偏移
var _dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_offset := Vector2.ZERO

# 范围指示器：可视化 apply_target_buff(area) / area_damage 的命中范围
# center_offset: 角色根坐标系下的圆心偏移（已含 visual_scale）
# radius: 命中半径（角色根坐标系）
# shape: "circle" 或 "rect"（rect 时用 _range_size 作为宽高）
var _range_active := false
var _range_center_offset := Vector2.ZERO
var _range_radius := 80.0
var _range_shape := "circle"
var _range_size := Vector2(160.0, 80.0)
var _range_rotation_degrees := 0.0


func _ready() -> void:
	# Cover-scaled fullscreen VFX may extend beyond this editor viewport.
	clip_contents = true
	_effect_clip = Control.new()
	_effect_clip.name = "EffectClip"
	_effect_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_clip.clip_contents = true
	_effect_clip.z_index = 100
	add_child(_effect_clip)
	# 创建特效层，z_index 高于精灵但仍在预览框内
	if _effect_layer == null:
		_effect_layer = Node2D.new()
		_effect_layer.name = "EffectLayer"
		# Imported scenes may use a negative z_index. Keep their preview above
		# this Control's dark background while retaining internal draw order.
		_effect_layer.z_index = 0
		_effect_clip.add_child(_effect_layer)


func set_preview(texture: Texture2D, scale_value: float, frame: int, hit_window: Dictionary, right: bool, visual: Dictionary = {}) -> void:
	frame_texture = texture
	sprite_scale = maxf(0.01, scale_value)
	frame_index = frame
	window_data = hit_window
	facing_right = right
	sprite_position = visual.get("position", Vector2.ZERO)
	sprite_offset = visual.get("offset", Vector2.ZERO)
	sprite_node_scale = visual.get("scale", Vector2.ONE)
	sprite_centered = bool(visual.get("centered", true))
	root_position = visual.get("root_position", Vector2.ZERO)
	queue_redraw()


## 设置特效预览。对齐真实运行时 combat_component._spawn_effect_at 的坐标逻辑。
## - scene: 特效场景；null 则隐藏
## - offset: 已按 coordinate_space 计算好的偏移（character_local 已乘 visual_scale 和 mirror_x）
## - active: 是否显示
## - visual_scale: 角色视觉缩放（character_local 模式下特效整体 scale 也乘以此值）
## - is_local: true=character_local（挂角色根，跟随移动）；false=world（落 origin + offset）
func set_effect(scene: PackedScene, offset: Vector2, active: bool, visual_scale: float, is_local: bool, is_fullscreen: bool = false, visual_only_scale: float = 1.0, tint: Color = Color.WHITE, blend_mode: String = "normal") -> void:
	_effect_scene = scene
	_effect_offset = offset
	_effect_active = active and scene != null
	_effect_visual_scale = maxf(0.01, visual_scale)
	_effect_visual_only_scale = maxf(0.01, visual_only_scale)
	_effect_is_local = is_local
	_effect_is_fullscreen = is_fullscreen
	_effect_tint = tint
	_effect_blend_mode = blend_mode
	_effect_mirror = false
	_effect_rotation_degrees = 0.0
	_rebuild_effect_instance()
	queue_redraw()


## 设置弹道特效的镜像/旋转修正（spawn_projectile 节点的 mirror / rotation_degrees）。
func set_effect_orientation(mirror: bool, rotation_degrees: float) -> void:
	_effect_mirror = mirror
	_effect_rotation_degrees = rotation_degrees
	_rebuild_effect_instance()
	queue_redraw()


## 设置命中范围指示器。
## - active: 是否显示
## - center_offset: 圆心相对角色根的偏移（已乘 visual_scale，预览绘制空间）
## - radius: 圆形半径（角色根坐标系，未乘 visual_scale）
## - shape: "circle" 或 "rect"
## - size: rect 模式下的宽高（角色根坐标系）
## radius/size 不在此方法内乘 visual_scale，绘制时统一乘 zoom + visual_scale
func set_range_indicator(active: bool, center_offset: Vector2, radius: float, shape: String = "circle", size: Vector2 = Vector2(160.0, 80.0), rotation_degrees: float = 0.0) -> void:
	_range_active = active
	_range_center_offset = center_offset
	_range_radius = maxf(0.0, radius)
	_range_shape = shape
	_range_size = size
	_range_rotation_degrees = rotation_degrees
	queue_redraw()


# 鼠标在特效附近按下并拖动时，实时调整 _effect_offset 并发射 delta 信号给编辑器回写。
# 由技能编辑器按节点类型回写；preview_position 模式下播放特效和弹道都可直接拖动定位。
func _gui_input(event: InputEvent) -> void:
	if not _effect_active or _effect_layer == null:
		return
	# Fullscreen effects are always centred and cover the preview viewport.
	# Their authored node offset is intentionally not editable by dragging.
	if _effect_is_fullscreen:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var zoom := _compute_zoom()
			var origin := _preview_origin()
			var effect_pos := origin + _effect_offset * zoom
			# 鼠标距特效中心 80px 内开始拖拽（给手柄式交互留足容差）
			if event.position.distance_to(effect_pos) <= 80.0:
				_dragging = true
				_drag_start_mouse = event.position
				_drag_start_offset = _effect_offset
				accept_event()
		else:
			if _dragging:
				_dragging = false
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var zoom := _compute_zoom()
		var delta: Vector2 = (event.position - _drag_start_mouse) / zoom
		_effect_offset = _drag_start_offset + delta
		var origin := _preview_origin()
		_effect_layer.position = origin + _effect_offset * zoom
		queue_redraw()
		effect_offset_changed.emit(_effect_offset)
		accept_event()


func _compute_zoom() -> float:
	if frame_texture == null:
		return 1.0
	var texture_size := frame_texture.get_size()
	var world_size := texture_size * sprite_scale
	var available := size - Vector2(32, 52)
	var zoom := minf(available.x / world_size.x, available.y / world_size.y)
	return maxf(0.01, zoom)


func _preview_origin() -> Vector2:
	return Vector2(size.x * 0.5, size.y * PREVIEW_FOOT_Y_RATIO)


func _rebuild_effect_instance() -> void:
	if _effect_layer == null:
		return
	for child in _effect_layer.get_children():
		child.queue_free()
	if not _effect_active or _effect_scene == null:
		return
	var instance := _effect_scene.instantiate()
	if instance != null:
		_effect_layer.add_child(instance)
		# 应用角色视觉缩放：character_local 模式对齐运行时 effect_node.scale *= visual_scale
		# world 模式（弹道）运行时不缩放，但预览中按用户期望也应用，使弹道视觉与角色缩放一致
		if instance is Node2D:
			var node2d := instance as Node2D
			node2d.modulate *= _effect_tint
			_apply_preview_blend(node2d, _effect_blend_mode)
			if not _effect_is_fullscreen:
				node2d.scale *= Vector2(_effect_visual_scale, _effect_visual_scale)
			# spawn_projectile.scale belongs to the Visual child only. Scaling the
			# Area2D root here also scaled CollisionShape2D and made the editor box
			# disagree with both the web preview and skill_executor runtime.
			var projectile_visual := node2d.get_node_or_null("Visual") as Node2D
			if projectile_visual != null and not is_equal_approx(_effect_visual_only_scale, 1.0):
				projectile_visual.scale *= Vector2(_effect_visual_only_scale, _effect_visual_only_scale)
			# Inspector preview stays on frame 0: export rebuilds the atlas so this
			# is the first frame in the user-selected playback sequence.
			if node2d is AnimatedSprite2D:
				(node2d as AnimatedSprite2D).stop()
				(node2d as AnimatedSprite2D).frame = 0
			# 弹道镜像/旋转修正（spawn_projectile 的 mirror / rotation_degrees）
			node2d.rotation = deg_to_rad(_effect_rotation_degrees)
			if _effect_mirror:
				if projectile_visual != null:
					projectile_visual.scale.x *= -1.0
				else:
					node2d.scale.x *= -1.0


func _apply_preview_blend(node: Node, requested: String) -> void:
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if requested == "add" else CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA if requested == "screen" else CanvasItemMaterial.BLEND_MODE_MIX
		canvas_item.material = material
	for child in node.get_children():
		_apply_preview_blend(child, requested)


func _find_effect_frame_size(node: Node) -> Vector2:
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
			var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
			if frame_count > 0:
				var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, clampi(sprite.frame, 0, frame_count - 1))
				if texture != null:
					return texture.get_size()
	elif node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			return sprite.texture.get_size()
	for child in node.get_children():
		var child_size := _find_effect_frame_size(child)
		if child_size.x > 0.0 and child_size.y > 0.0:
			return child_size
	return Vector2.ZERO


func _effect_frame_size() -> Vector2:
	if _effect_layer == null:
		return Vector2.ZERO
	for child in _effect_layer.get_children():
		var frame_size := _find_effect_frame_size(child)
		if frame_size.x > 0.0 and frame_size.y > 0.0:
			return frame_size
	return Vector2.ZERO


func _fullscreen_preview_rect() -> Rect2:
	var target_ratio := 16.0 / 9.0
	var viewport_size := size
	if viewport_size.x / maxf(1.0, viewport_size.y) > target_ratio:
		viewport_size.x = viewport_size.y * target_ratio
	else:
		viewport_size.y = viewport_size.x / target_ratio
	return Rect2((size - viewport_size) * 0.5, viewport_size)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("171b22"), true)
	if frame_texture == null:
		draw_string(ThemeDB.fallback_font, Vector2(20, 32), "没有可预览的动画帧", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		return
	var texture_size := frame_texture.get_size()
	var world_size := texture_size * sprite_scale
	var available := size - Vector2(32, 52)
	var zoom := minf(available.x / world_size.x, available.y / world_size.y)
	zoom = maxf(0.01, zoom)
	var origin := _preview_origin()
	var visual_origin := origin + root_position * zoom + sprite_position * sprite_scale * zoom
	var draw_scale := zoom * sprite_scale
	var horizontal_scale := (-draw_scale if facing_right else draw_scale) * sprite_node_scale.x
	var vertical_scale := draw_scale * sprite_node_scale.y
	var texture_origin := sprite_offset
	if sprite_centered:
		texture_origin -= texture_size * 0.5
	draw_set_transform(visual_origin, 0.0, Vector2(horizontal_scale, vertical_scale))
	draw_texture(frame_texture, texture_origin)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 特效层定位：对齐真实运行时——特效挂在角色根节点（_owner，即脚部/origin）下，
	# 本地 position = offset * visual_scale * mirror_x。
	# 因此 effect_origin = origin（角色根）+ effect_offset * zoom，
	# 不包含 root_position（那是 CharacterActionSet 的视觉偏移，特效不挂在其下）。
	if _effect_active and _effect_layer != null:
		if _effect_is_fullscreen:
			var viewport_rect := _fullscreen_preview_rect()
			var effect_size := _effect_frame_size()
			var fit_scale := 1.0
			if effect_size.x > 0.0 and effect_size.y > 0.0:
				fit_scale = minf(viewport_rect.size.x / effect_size.x, viewport_rect.size.y / effect_size.y)
			_effect_clip.position = viewport_rect.position
			_effect_clip.size = viewport_rect.size
			_effect_layer.position = viewport_rect.size * 0.5
			_effect_layer.scale = Vector2(fit_scale, fit_scale)
		else:
			_effect_clip.position = Vector2.ZERO
			_effect_clip.size = size
			var effect_origin := origin + _effect_offset * zoom
			_effect_layer.position = effect_origin
			_effect_layer.scale = Vector2(zoom, zoom)
		_effect_clip.visible = true
		_effect_layer.visible = true
		# 特效场景内部若含 GPUParticles2D / AnimationPlayer 会自动播放
	else:
		if _effect_clip != null:
			_effect_clip.visible = false
		if _effect_layer != null:
			_effect_layer.visible = false
	draw_line(origin + Vector2(-8, 0), origin + Vector2(8, 0), Color("64b5f6"), 1.0)
	draw_line(origin + Vector2(0, -8), origin + Vector2(0, 8), Color("64b5f6"), 1.0)
	var start_frame := int(window_data.get("start_frame", -1))
	var end_frame := int(window_data.get("end_frame", -1))
	if frame_index >= start_frame and frame_index <= end_frame:
		var direction := 1.0 if facing_right else -1.0
		var hit_x := direction * absf(float(window_data.get("forward", 0.0)))
		if window_data.has("authored_x"):
			hit_x = float(window_data.get("authored_x", 0.0)) * -direction
		var center := origin + Vector2(
			hit_x,
			float(window_data.get("y", 0.0))
		) * zoom
		var hit_size := Vector2(
			float(window_data.get("width", 1.0)),
			float(window_data.get("height", 1.0))
		) * zoom
		draw_rect(Rect2(center - hit_size * 0.5, hit_size), Color(1.0, 0.2, 0.2, 0.22), true)
		draw_rect(Rect2(center - hit_size * 0.5, hit_size), Color("ff5252"), false, 2.0)
	# 命中范围指示器：apply_target_buff(area) / area_damage 节点的可视化
	# 圆心 = origin（角色根）+ center_offset * visual_scale，绘制时再乘 zoom
	# 半径/尺寸也乘 visual_scale * zoom，对齐运行时角色缩放下范围的实际大小
	if _range_active:
		var visual_scale_for_range := _effect_visual_scale if _effect_active else 1.0
		var range_center := origin + _range_center_offset * zoom
		var ring_color := Color("4caf50")
		var fill_color := Color(0.30, 0.69, 0.31, 0.15)
		if _range_shape == "rect":
			var rect_size := _range_size * visual_scale_for_range * zoom
			draw_set_transform(range_center, deg_to_rad(_range_rotation_degrees), Vector2.ONE)
			draw_rect(Rect2(-rect_size * 0.5, rect_size), fill_color, true)
			draw_rect(Rect2(-rect_size * 0.5, rect_size), ring_color, false, 1.5)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var r := _range_radius * visual_scale_for_range * zoom
			draw_circle(range_center, r, fill_color)
			# draw_circle 不支持描边，用多段线模拟空心圆
			var point_count := 48
			var prev := range_center + Vector2(r, 0)
			for i in range(1, point_count + 1):
				var angle := TAU * float(i) / float(point_count)
				var next := range_center + Vector2(cos(angle), sin(angle)) * r
				draw_line(prev, next, ring_color, 1.5)
				prev = next
	var direction_text := "朝右" if facing_right else "朝左（素材默认）"
	draw_string(ThemeDB.fallback_font, Vector2(14, 24), "帧 %d · %s · Sprite位置(%.1f, %.1f)" % [frame_index, direction_text, sprite_position.x, sprite_position.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e8eaed"))
