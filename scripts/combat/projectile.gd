extends Area2D
## Basic straight-line projectile with hit detection and pierce support.

signal hit_target(hurt_box: Area2D)

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var velocity: Vector2 = Vector2.ZERO
var projectile_gravity: float = 0.0
var damage: int = 10
var max_pierce: int = 0 # 0 = no pierce, -1 = infinite pierce
var pierce_count: int = 0
var buff_on_hit_id: int = 0
var buff_chance: float = 0.0
var lifetime: float = 5.0
var source_entity: Node = null

var _hit_targets: Array[Area2D] = []


func _ready() -> void:
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	velocity.y += projectile_gravity * delta


func setup(dir: Vector2, spd: float, dmg: int, pierce: int, buff_id: int = 0, chance: float = 0.0, source: Node = null, life: float = 5.0) -> void:
	direction = dir.normalized()
	speed = spd
	velocity = direction * speed
	projectile_gravity = 0.0
	damage = dmg
	max_pierce = pierce
	buff_on_hit_id = buff_id
	buff_chance = chance
	source_entity = source
	lifetime = life


func setup_ballistic(initial_velocity: Vector2, projectile_gravity: float, dmg: int, pierce: int, buff_id: int = 0, chance: float = 0.0, source: Node = null, life: float = 5.0) -> void:
	velocity = initial_velocity
	direction = initial_velocity.normalized()
	speed = initial_velocity.length()
	self.projectile_gravity = projectile_gravity
	damage = dmg
	max_pierce = pierce
	buff_on_hit_id = buff_id
	buff_chance = chance
	source_entity = source
	lifetime = life


func _on_area_entered(area: Area2D) -> void:
	if not area.has_method("is_hurt_box") or not area.is_hurt_box():
		return
	if _is_friendly(area):
		return
	if area in _hit_targets:
		return
	_hit_targets.append(area)
	if area.has_method("take_hit"):
		area.take_hit(damage, source_entity)
	if buff_on_hit_id > 0 and randf() <= buff_chance:
		_try_apply_buff(area)
	hit_target.emit(area)
	if max_pierce == 0:
		queue_free()
	elif max_pierce > 0:
		pierce_count += 1
		if pierce_count >= max_pierce:
			queue_free()


func _try_apply_buff(hurt_box: Area2D) -> void:
	var target_owner = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target_owner == null or not target_owner.has_method("apply_buff_from_config"):
		return
	var config = GameRegistry.buff_config.get_buff(buff_on_hit_id)
	if not config.is_empty():
		target_owner.apply_buff_from_config(config, source_entity.get_instance_id() if source_entity else 0)


func _is_friendly(hurt_box: Area2D) -> bool:
	var target_owner = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target_owner == null or source_entity == null:
		return false
	if target_owner == source_entity:
		return true
	if source_entity.is_in_group("player") and target_owner.is_in_group("player"):
		return true
	if source_entity.is_in_group("enemies") and target_owner.is_in_group("enemies"):
		return true
	return false
