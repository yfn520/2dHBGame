extends Area2D
## 攻击判定区
## 普攻/技能激活时短暂开启，检测 overlapping 的 HurtBox

signal hit_detected(hurt_box: Area2D)

var _active := false


func activate(duration: float = 0.15) -> void:
	_active = true
	monitoring = true
	# duration 后自动关闭
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
	if area.has_method("is_hurt_box") and area.is_hurt_box():
		hit_detected.emit(area)
