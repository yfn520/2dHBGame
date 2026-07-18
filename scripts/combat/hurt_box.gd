extends Area2D
## 受击判定区
## 常开，被 HitBox 检测到时触发受伤

signal damaged(damage: int, source: Node)

var _owner_entity: Node = null


func setup(owner_entity: Node) -> void:
	_owner_entity = owner_entity


func is_hurt_box() -> bool:
	return true


func take_hit(damage_data: Variant, source: Node) -> void:
	# 兼容两种入参：
	# - int（旧弹道链路）：仅原始伤害，由 take_damage 做 defense 减法
	# - Dictionary（新 skill_executor 链路）：含 damage/dodged/blocked/crit，damage 已是最终值
	if damage_data is Dictionary:
		var result: Dictionary = damage_data
		if _owner_entity != null and _owner_entity.has_method("take_damage"):
			_owner_entity.take_damage(int(result.get("damage", 0)), source, true, result)
		damaged.emit(int(result.get("damage", 0)), source)
	else:
		var amount := int(damage_data)
		if _owner_entity != null and _owner_entity.has_method("take_damage"):
			_owner_entity.take_damage(amount, source)
		damaged.emit(amount, source)
