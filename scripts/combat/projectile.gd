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

var _hit_targets: Dictionary = {}
var _visual_sprite: AnimatedSprite2D


func _ready() -> void:
	z_as_relative = false
	# 弹道渲染在角色/怪物（z_index=100）之上，确保箭矢等特效始终可见
	z_index = 200
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	area_entered.connect(_on_area_entered)
	# 缓存 Visual 子节点的 AnimatedSprite2D 用于镜像翻转
	_visual_sprite = _find_visual_sprite()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	velocity.y += projectile_gravity * delta
	if rotate_to_velocity and velocity.length_squared() > 0.001:
		rotation = velocity.angle() + deg_to_rad(visual_rotation_degrees)
	elif not rotate_to_velocity:
		rotation = deg_to_rad(visual_rotation_degrees)
	# 镜像 flip_h：不旋转模式下按飞行方向自动翻转，再 XOR 节点配置的 mirror 修正。
	# 旋转模式下 auto_flip 始终为 false，仅用 mirror 手动翻转。
	if _visual_sprite != null:
		var auto_flip := false
		if not rotate_to_velocity and flip_to_velocity and velocity.length_squared() > 0.001:
			auto_flip = velocity.x < 0.0
		_visual_sprite.flip_h = auto_flip != visual_mirror


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


func setup_ballistic(initial_velocity: Vector2, gravity_value: float, _node_damage: int, _pierce: int, _node_buff_ids: Array = [], _chance: float = 0.0, source: Node = null, life: float = 5.0, should_rotate := true) -> void:
	velocity = initial_velocity
	projectile_gravity = gravity_value
	source_entity = source
	lifetime = life
	rotate_to_velocity = should_rotate


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
	visual_mirror = bool(node.get("mirror", false))
	visual_rotation_degrees = float(node.get("rotation_degrees", 0.0))


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
	hit_target.emit(area)
	if max_pierce == 0:
		queue_free()
	elif max_pierce > 0:
		pierce_count += 1
		if pierce_count >= max_pierce:
			queue_free()


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
