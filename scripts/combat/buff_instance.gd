class_name BuffInstance

var buff_id: int = 0
var buff_type: String = ""
var duration: float = 0.0
var remaining: float = 0.0
var interval: float = 0.0
var tick_timer: float = 0.0
var tick_damage: int = 0
var slow_ratio: float = 0.0
var stacks: int = 1
var max_stacks: int = 1
var effect_scene: String = ""
var source_entity: int = 0
var effect_node: Node = null


func _init(config: Dictionary, source: int = 0) -> void:
	buff_id = int(config.get("id", 0))
	buff_type = config.get("type", "")
	duration = float(config.get("duration", 0.0))
	remaining = duration
	interval = float(config.get("interval", 0.0))
	tick_timer = interval
	tick_damage = int(config.get("tick_damage", 0))
	slow_ratio = float(config.get("slow_ratio", 0.0))
	max_stacks = int(config.get("max_stacks", 1))
	effect_scene = config.get("effect_scene", "")
	source_entity = source


func is_expired() -> bool:
	return remaining <= 0.0


func is_dot() -> bool:
	return interval > 0.0 and tick_damage > 0


func add_stack() -> bool:
	if stacks < max_stacks:
		stacks += 1
		remaining = duration
		return true
	# 刷新持续时间
	remaining = duration
	return false
