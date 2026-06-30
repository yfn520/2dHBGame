extends Area2D
## 攻击判定区
## 普攻/技能激活时短暂开启，检测 overlapping 的 HurtBox

signal hit_detected(hurt_box: Area2D)

var _active := false
var _owner_entity: Node = null


func setup(owner_entity: Node) -> void:
	_owner_entity = owner_entity


func activate(duration: float = 0.15) -> void:
	_active = true
	monitoring = true
	if duration > 0.0:
		get_tree().create_timer(duration).timeout.connect(deactivate)


func deactivate() -> void:
	_active = false
	monitoring = false


func is_active() -> bool:
	return _active


func _on_area_entered(area: Area2D) -> void:
	if not _active:
		return
	if not area.has_method("is_hurt_box") or not area.is_hurt_box():
		return
	# 防止友军伤害
	var target_owner = area._owner_entity if "_owner_entity" in area else null
	if _owner_entity != null and target_owner != null:
		if _owner_entity == target_owner:
			return
		if _owner_entity.is_in_group("player") and target_owner.is_in_group("player"):
			return
		if _owner_entity.is_in_group("enemies") and target_owner.is_in_group("enemies"):
			return
	hit_detected.emit(area)
