extends Area2D
## 弹道基础脚本
## 支持直线飞行、碰撞检测、穿透

signal hit_target(hurt_box: Area2D)

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: int = 10
var max_pierce: int = 0    # 0=不穿透, -1=无限穿透
var pierce_count: int = 0
var buff_on_hit_id: int = 0
var buff_chance: float = 0.0
var lifetime: float = 5.0
var source_entity: Node = null

var _hit_targets: Array[Area2D] = []


func _ready() -> void:
	# 生命周期结束自动销毁
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func setup(dir: Vector2, spd: float, dmg: int, pierce: int, buff_id: int = 0, chance: float = 0.0, source: Node = null) -> void:
	direction = dir.normalized()
	speed = spd
	damage = dmg
	max_pierce = pierce
	buff_on_hit_id = buff_id
	buff_chance = chance
	source_entity = source


func _on_area_entered(area: Area2D) -> void:
	if not area.has_method("is_hurt_box") or not area.is_hurt_box():
		return
	if area in _hit_targets:
		return
	_hit_targets.append(area)
	# 对目标造成伤害
	if area.has_method("take_hit"):
		area.take_hit(damage, source_entity)
	# 施加 buff
	if buff_on_hit_id > 0 and randf() <= buff_chance:
		var target_owner = area._owner_entity if area.has_method("is_hurt_box") else null
		if target_owner != null and target_owner.has_method("apply_buff_from_config"):
			var config = GameRegistry.buff_config.get_buff(buff_on_hit_id)
			if not config.is_empty():
				target_owner.apply_buff_from_config(config, source_entity.get_instance_id() if source_entity else 0)
	hit_target.emit(area)
	# 穿透判定
	if max_pierce == 0:
		queue_free()
	elif max_pierce > 0:
		pierce_count += 1
		if pierce_count >= max_pierce:
			queue_free()
	# max_pierce == -1 时无限穿透，不销毁
