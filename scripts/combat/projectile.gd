extends Area2D
## Runtime projectile. Its combat values come from a spawn_projectile node.

signal hit_target(hurt_box: Area2D)

var velocity := Vector2.ZERO
var projectile_gravity := 0.0
var damage := 1
var max_pierce := 0 # 0 = first target, -1 = unlimited.
var pierce_count := 0
var buff_ids: Array = []
var buff_chance := 0.0
var lifetime := 5.0
var source_entity: Node
var rotate_to_velocity := true

var _hit_targets: Dictionary = {}


func _ready() -> void:
	z_as_relative = false
	# 弹道渲染在角色/怪物（z_index=100）之上，确保箭矢等特效始终可见
	z_index = 200
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	velocity.y += projectile_gravity * delta
	if rotate_to_velocity and velocity.length_squared() > 0.001:
		rotation = velocity.angle()


func setup(direction: Vector2, speed: float, node_damage: int, pierce: int, node_buff_ids: Array = [], chance: float = 0.0, source: Node = null, life: float = 5.0, should_rotate := true) -> void:
	velocity = direction.normalized() * speed
	projectile_gravity = 0.0
	_configure(node_damage, pierce, node_buff_ids, chance, source, life, should_rotate)


func setup_ballistic(initial_velocity: Vector2, gravity_value: float, node_damage: int, pierce: int, node_buff_ids: Array = [], chance: float = 0.0, source: Node = null, life: float = 5.0, should_rotate := true) -> void:
	velocity = initial_velocity
	projectile_gravity = gravity_value
	_configure(node_damage, pierce, node_buff_ids, chance, source, life, should_rotate)


func _configure(node_damage: int, pierce: int, node_buff_ids: Array, chance: float, source: Node, life: float, should_rotate: bool) -> void:
	damage = node_damage
	max_pierce = pierce
	buff_ids = node_buff_ids
	buff_chance = chance
	source_entity = source
	lifetime = life
	rotate_to_velocity = should_rotate


func _on_area_entered(area: Area2D) -> void:
	if not area.has_method("is_hurt_box") or not area.is_hurt_box() or _is_friendly(area):
		return
	var target_id := area.get_instance_id()
	if _hit_targets.has(target_id):
		return
	_hit_targets[target_id] = true
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
