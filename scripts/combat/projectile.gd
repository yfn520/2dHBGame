extends Area2D
## Runtime projectile. Its combat values come from a spawn_projectile node.
## P1 改造：弹道命中时通过 _on_hit_callback 走完整 apply_damage_node 链路
## （含元素反应、异常积累、标签贯通、防御通道），不再预计算 int 伤害。

signal hit_target(hurt_box: Area2D)

var velocity := Vector2.ZERO
var projectile_gravity := 0.0
var damage := 1  # 保留字段以兼容旧调用，但新链路不再使用
var max_pierce := 0 # 0 = first target, -1 = unlimited.
var pierce_count := 0
var buff_ids: Array = []
var buff_chance := 0.0
var lifetime := 5.0
var source_entity: Node
var rotate_to_velocity := true
# 弹道三类音效（spawn_audio/flight_audio/hit_audio）。
# 通过 setup_with_node 从 spawn_projectile 节点读取。
var spawn_audio_path := ""
var flight_audio_path := ""
var hit_audio_path := ""
var spawn_audio_gain_db := 0.0
var spawn_audio_pitch_variation := 0.0
var flight_audio_gain_db := 0.0
var flight_audio_pitch_variation := 0.0
var hit_audio_gain_db := 0.0
var hit_audio_pitch_variation := 0.0
# flight_audio 循环播放的通道 id，弹道销毁/命中时停止。
var _flight_audio_channel := -1
# 非对称素材（如箭矢）需要按飞行方向镜像 flip_h。
# 导出已将素材统一规范为「朝右」，向左飞时 flip_h = true。
var flip_to_velocity := true
# P1 新链路：spawn_projectile 节点字典 + 命中回调，命中时走 apply_damage_node
var damage_node: Dictionary = {}
var on_hit_callback: Callable = Callable()
var _has_new_link := false
# 节点配置的视觉镜像/旋转修正（spawn_projectile 的 mirror / rotation_degrees 字段）
var visual_mirror := false
var visual_rotation_degrees := 0.0
# 节点配置的实例层缩放倍率（spawn_projectile 的 scale 字段）。
# 运行时应用：Visual.scale = baked_displayScale × visual_scale_multiplier
var visual_scale_multiplier := 1.0
var visual_tint := Color.WHITE
var visual_blend_mode := "normal"
# Imported GameTool bundles are authored from the actor's default (left-facing)
# pose. Their offset/rotation are baked into the scene, so mirror them from the
# actor facing instead of guessing from velocity every frame.
var mirror_with_source_facing := false
var _locked_source_flip := false

var _hit_targets: Dictionary = {}
var _visual_sprite: AnimatedSprite2D
var _visual_root: Node2D
var _visual_root_base_scale := Vector2.ONE
var _visual_nodes_cached := false
# GameTool 导出时 baked 到子节点的 flip_h（素材规范层，朝右素材 baked 成朝左）。
# rotate_to_velocity=true 时需基于此值抵消，否则 rotation 会让 baked 朝向反转。
var _visual_sprite_base_flip := false


func _ready() -> void:
	z_as_relative = false
	# 弹道渲染在角色/怪物（z_index=100）之上，确保箭矢等特效始终可见
	z_index = 200
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	area_entered.connect(_on_area_entered)
	# 缓存 Visual 子节点的 AnimatedSprite2D 用于镜像翻转
	_cache_visual_nodes()
	# setup_with_node() normally runs before add_child(). Apply again in
	# _ready() so no render frame can expose the raw TSCN orientation.
	_apply_visual_transform()
	_apply_visual_style()
	# 弹道音效：spawn 在 _ready 播放（此时位置已对齐发射点）；flight 启动循环
	_play_spawn_audio()
	_start_flight_audio()


## 播放弹道发射音效（spawn_audio），跟随弹道自身位置。
func _play_spawn_audio() -> void:
	if spawn_audio_path.is_empty():
		return
	AudioManager.play_sfx_2d_by_path(spawn_audio_path, self, spawn_audio_gain_db, spawn_audio_pitch_variation)


## 启动弹道飞行循环音效（flight_audio），保存通道 id 供销毁时停止。
func _start_flight_audio() -> void:
	if flight_audio_path.is_empty():
		return
	_flight_audio_channel = AudioManager.play_sfx_2d_by_path(flight_audio_path, self, flight_audio_gain_db, flight_audio_pitch_variation, true)


## 停止飞行循环音效（命中/销毁时调用）。
func _stop_flight_audio() -> void:
	if _flight_audio_channel > 0:
		AudioManager.stop(_flight_audio_channel)
		_flight_audio_channel = -1


## 弹道销毁前清理：停止飞行循环音效。
func _exit_tree() -> void:
	_stop_flight_audio()


func _physics_process(delta: float) -> void:
	_update_projectile_transform(delta, true)


func _apply_visual_transform() -> void:
	_update_projectile_transform(0.0, false)


func _apply_visual_style() -> void:
	_cache_visual_nodes()
	if _visual_root == null:
		return
	var canvas_items: Array[CanvasItem] = [_visual_root]
	for child in _visual_root.find_children("*", "CanvasItem", true, false):
		if child is CanvasItem:
			canvas_items.append(child as CanvasItem)
	if visual_tint.r >= 0.999 and visual_tint.g >= 0.999 and visual_tint.b >= 0.999:
		# 白色 tint：只需 modulate 处理 opacity
		_visual_root.modulate = visual_tint
		var blend_mode := CanvasItemMaterial.BLEND_MODE_MIX
		if visual_blend_mode == "add":
			blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		elif visual_blend_mode == "screen":
			blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		for canvas_item in canvas_items:
			var material := canvas_item.material as CanvasItemMaterial
			if material != null:
				material = material.duplicate() as CanvasItemMaterial
			else:
				material = CanvasItemMaterial.new()
			material.blend_mode = blend_mode
			canvas_item.material = material
	else:
		# 非白色 tint：用 shader 做颜色替换（对齐网页侧 source-atop 行为）
		var render_mode := "blend_mix"
		if visual_blend_mode == "add":
			render_mode = "blend_add"
		elif visual_blend_mode == "screen":
			render_mode = "blend_premul_alpha"
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nrender_mode %s;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n    vec4 c = texture(TEXTURE, UV);\n    COLOR = vec4(tint.rgb, c.a * tint.a);\n}" % render_mode
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tint", visual_tint)
		for canvas_item in canvas_items:
			canvas_item.material = mat


func _update_projectile_transform(delta: float, advance_motion: bool) -> void:
	_cache_visual_nodes()
	if advance_motion:
		position += velocity * delta
		velocity.y += projectile_gravity * delta
	# rotation 始终应用到 Area2D（和之前一致），让 CollisionShape2D 也跟着旋转
	# - rotate_to_velocity=true：rotation = velocity.angle() + rotation_degrees（对齐飞行方向）
	# - rotate_to_velocity=false：rotation = rotation_degrees（固定值）
	#   mirror_with_facing 通过 rotation 镜像（180 - deg）实现，不通过 scale.x 翻转
	#   这样 scale.x 翻转只用于抵消 baked flip_h，不会让 rotation 视觉反向
	if rotate_to_velocity:
		if velocity.length_squared() > 0.001:
			rotation = velocity.angle() + deg_to_rad(visual_rotation_degrees)
		else:
			rotation = deg_to_rad(visual_rotation_degrees)
	else:
		var deg := visual_rotation_degrees
		if mirror_with_source_facing:
			# 镜像时 rotation 变换：θ → 180° + θ
			# 例如 -160°（朝左略上）镜像后 → 20°（朝右略下），保持视觉对称
			# 推导：朝右素材 + (-160°) = 朝左略上；朝右素材 + 20° = 朝右略下（关于 Y 轴对称）
			# visual_mirror=true 表示弹道已镜像（朝左），source_flip=true 表示角色朝右
			# 当两者状态一致（source_flip == visual_mirror）时，朝向相反 → 需镜像 rotation
			var extra := _locked_source_flip == visual_mirror
			if extra:
				deg = 180.0 + deg
		elif flip_to_velocity:
			var auto_flip := velocity.length_squared() > 0.001 and velocity.x < 0.0
			if auto_flip != visual_mirror:
				deg = 180.0 + deg
		rotation = deg_to_rad(deg)
	# 镜像 + 缩放：should_mirror 始终抵消 baked flip_h（baked 后素材朝左，翻转成朝右）
	# 素材朝右后，rotation 才能正确对齐（朝右素材 rotation=0 朝右，rotation=π 朝左）
	if _visual_root != null:
		var sign_x := -1.0
		_visual_root.scale = Vector2(absf(_visual_root_base_scale.x) * visual_scale_multiplier * sign_x, absf(_visual_root_base_scale.y) * visual_scale_multiplier)


func _cache_visual_nodes() -> void:
	if _visual_nodes_cached:
		return
	_visual_nodes_cached = true
	_visual_sprite = _find_visual_sprite()
	_visual_root = get_node_or_null("Visual") as Node2D
	if _visual_root != null:
		_visual_root_base_scale = _visual_root.scale
	if _visual_sprite != null:
		_visual_sprite_base_flip = _visual_sprite.flip_h


func _find_visual_sprite() -> AnimatedSprite2D:
	# 弹道场景结构：Area2D > Visual/VisualScene(AnimatedSprite2D)
	var visual_root := get_node_or_null("Visual")
	if visual_root == null:
		return null
	for child in visual_root.get_children():
		if child is AnimatedSprite2D:
			return child
	return visual_root as AnimatedSprite2D


func setup(direction: Vector2, speed: float, _node_damage: int, _pierce: int, _node_buff_ids: Array = [], _chance: float = 0.0, source: Node = null, life: float = 5.0, should_rotate := true) -> void:
	velocity = direction.normalized() * speed
	projectile_gravity = 0.0
	# 旧链路参数保留兼容（_node_damage/_pierce/_node_buff_ids/_chance 加下划线标记未使用），
	# 真正的配置在 setup_with_node 中通过 damage_node 传递
	source_entity = source
	lifetime = life
	rotate_to_velocity = should_rotate
	_apply_visual_transform()


func setup_ballistic(initial_velocity: Vector2, gravity_value: float, _node_damage: int, _pierce: int, _node_buff_ids: Array = [], _chance: float = 0.0, source: Node = null, life: float = 5.0, should_rotate := true) -> void:
	velocity = initial_velocity
	projectile_gravity = gravity_value
	source_entity = source
	lifetime = life
	rotate_to_velocity = should_rotate
	_apply_visual_transform()


## P1 新链路：传入完整 spawn_projectile 节点 + 命中回调。
## 回调签名：callback(hurt_box: Area2D, node: Dictionary, source: Node) -> void
## 由 skill_executor.apply_damage_node 走完整伤害链路（含反应/异常积累/标签贯通）。
func setup_with_node(direction: Vector2, speed: float, node: Dictionary, source: Node, life: float, should_rotate: bool, callback: Callable, is_ballistic: bool = false, initial_velocity: Vector2 = Vector2.ZERO, gravity_value: float = 0.0) -> void:
	if is_ballistic:
		velocity = initial_velocity
		projectile_gravity = gravity_value
	else:
		velocity = direction.normalized() * speed
		projectile_gravity = 0.0
	damage_node = node.duplicate(true)
	source_entity = source
	lifetime = life
	rotate_to_velocity = should_rotate
	on_hit_callback = callback
	_has_new_link = true
	# 兼容字段：保留 max_pierce/buff_ids/buff_chance 让 _on_area_entered 的穿透/buff 逻辑能继续工作
	max_pierce = int(node.get("max_pierce", 0))
	buff_ids = _read_buff_ids_compat(node)
	buff_chance = float(node.get("buff_chance", 0.0))
	# 读取弹道三类音效配置（spawn_audio/flight_audio/hit_audio 子字典）
	var spawn_audio_cfg: Dictionary = node.get("spawn_audio", {})
	spawn_audio_path = str(spawn_audio_cfg.get("audio_path", ""))
	spawn_audio_gain_db = float(spawn_audio_cfg.get("gain_db", 0.0))
	spawn_audio_pitch_variation = float(spawn_audio_cfg.get("pitch_variation", 0.0))
	var flight_audio_cfg: Dictionary = node.get("flight_audio", {})
	flight_audio_path = str(flight_audio_cfg.get("audio_path", ""))
	flight_audio_gain_db = float(flight_audio_cfg.get("gain_db", 0.0))
	flight_audio_pitch_variation = float(flight_audio_cfg.get("pitch_variation", 0.0))
	var hit_audio_cfg: Dictionary = node.get("hit_audio", {})
	hit_audio_path = str(hit_audio_cfg.get("audio_path", ""))
	hit_audio_gain_db = float(hit_audio_cfg.get("gain_db", 0.0))
	hit_audio_pitch_variation = float(hit_audio_cfg.get("pitch_variation", 0.0))
	visual_mirror = bool(node.get("mirror", false))
	visual_rotation_degrees = float(node.get("rotation_degrees", 0.0))
	visual_scale_multiplier = float(node.get("scale", 1.0))
	visual_tint = Color.from_string(str(node.get("tint", "#ffffff")), Color.WHITE)
	visual_tint.a *= clampf(float(node.get("opacity", 1.0)), 0.0, 1.0)
	visual_blend_mode = str(node.get("attachment_blend_mode", "normal"))
	mirror_with_source_facing = bool(node.get("mirror_with_facing", false))
	flip_to_velocity = bool(node.get("flip_to_velocity", true))
	_locked_source_flip = false
	if source_entity != null:
		var source_sprite := source_entity.get_node_or_null("CharacterActionSet/AnimatedSprite2D") as AnimatedSprite2D
		_locked_source_flip = source_sprite != null and source_sprite.flip_h
	# The projectile is configured before it enters the scene tree. Applying the
	# final launch transform here prevents one raw-TSCN frame from being drawn.
	_apply_visual_transform()
	_apply_visual_style()


func _read_buff_ids_compat(node: Dictionary) -> Array:
	var result: Array = []
	if node.has("buff_ids"):
		var raw = node.get("buff_ids", [])
		if raw is Array:
			for v in raw:
				result.append(int(v))
	elif node.has("buff_id"):
		var legacy := int(node.get("buff_id", 0))
		if legacy > 0:
			result.append(legacy)
	return result


func _on_area_entered(area: Area2D) -> void:
	if not area.has_method("is_hurt_box") or not area.is_hurt_box() or _is_friendly(area):
		return
	var target_id := area.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
	# P1 新链路：通过回调走 apply_damage_node（含反应/异常积累/标签贯通/吸血）
	if _has_new_link and on_hit_callback.is_valid():
		on_hit_callback.call(area, damage_node, source_entity)
	else:
		# 旧链路：直接传 int 给 hurt_box（兼容未迁移的调用）
		if area.has_method("take_hit"):
			area.take_hit(damage, source_entity)
		if not buff_ids.is_empty() and randf() <= buff_chance:
			_apply_buff(area)
	# 命中音效：跟随弹道自身位置（命中瞬间弹道与目标几乎重合）
	_play_hit_audio()
	hit_target.emit(area)
	if max_pierce == 0:
		queue_free()
	elif max_pierce > 0:
		pierce_count += 1
		if pierce_count >= max_pierce:
			queue_free()


## 播放弹道命中音效（hit_audio），跟随弹道自身位置。
func _play_hit_audio() -> void:
	if hit_audio_path.is_empty():
		return
	AudioManager.play_sfx_2d_by_path(hit_audio_path, self, hit_audio_gain_db, hit_audio_pitch_variation)


func _apply_buff(hurt_box: Area2D) -> void:
	var target_owner: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target_owner == null or not target_owner.has_method("apply_buff_from_config"):
		return
	var source_id := source_entity.get_instance_id() if source_entity != null else 0
	for buff_id in buff_ids:
		var config: Dictionary = GameRegistry.buff_config.get_buff(int(buff_id))
		if not config.is_empty():
			target_owner.apply_buff_from_config(config, source_id)


func _is_friendly(hurt_box: Area2D) -> bool:
	var target_owner: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target_owner == null or source_entity == null:
		return false
	return target_owner == source_entity \
		or (source_entity.is_in_group("player") and target_owner.is_in_group("player")) \
		or (source_entity.is_in_group("enemies") and target_owner.is_in_group("enemies"))
