extends Label
class_name DamageNumber
## 伤害飘字：在受击者头顶生成，向上飘动并淡出后销毁。


## 弹出伤害数字：world_pos 应为受击者头顶上方位置
func popup(value: int, world_pos: Vector2, is_crit: bool = false) -> void:
	text = str(value)
	# 轻微随机 x 偏移避免多个数字重叠；y 由 spawner 定位到头顶
	global_position = world_pos + Vector2(randf_range(-10.0, 10.0), 0.0)
	# 统一红色（第一版不区分暴击）
	modulate = Color.RED
	var tween := create_tween()
	tween.set_parallel(true)
	# 向上飘 40 像素
	tween.tween_property(self, "global_position:y", global_position.y - 40.0, 0.6)
	# 同时淡出
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	# 飘完销毁
	tween.chain().tween_callback(queue_free)
