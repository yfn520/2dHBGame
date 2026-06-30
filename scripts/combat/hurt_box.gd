extends Area2D
## 受击判定区
## 常开，被 HitBox 检测到时触发受伤

signal damaged(damage: int, source: Node)

var _owner_entity: Node = null


func setup(owner_entity: Node) -> void:
	_owner_entity = owner_entity


func is_hurt_box() -> bool:
	return true


func take_hit(damage: int, source: Node) -> void:
	if _owner_entity != null and _owner_entity.has_method("take_damage"):
		_owner_entity.take_damage(damage, source)
	damaged.emit(damage, source)
