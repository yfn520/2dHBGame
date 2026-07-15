class_name BuffInstance

var buff_id: int = 0
var name: String = ""
var description: String = ""
var category: String = "debuff"
var duration: float = 0.0
var remaining: float = 0.0
var max_stacks: int = 1
var stack_behavior: String = "refresh"
var stacks: int = 1
var icon: String = ""
var effect_scene: String = ""
var effects: Array = []
var source_entity: int = 0
var effect_node: Node = null


func _init(config: Dictionary, source: int = 0) -> void:
	buff_id = int(config.get("id", 0))
	name = String(config.get("name", ""))
	description = String(config.get("description", ""))
	category = String(config.get("category", "debuff"))
	duration = float(config.get("duration", 0.0))
	remaining = duration
	max_stacks = int(config.get("max_stacks", 1))
	stack_behavior = String(config.get("stack_behavior", "refresh"))
	icon = String(config.get("icon", ""))
	effect_scene = String(config.get("effect_scene", ""))
	# 深拷贝 effects（含运行时字段如 tick_timer / remaining）
	var raw_effects = config.get("effects", [])
	if raw_effects is Array:
		for effect in raw_effects:
			if effect is Dictionary:
				effects.append((effect as Dictionary).duplicate(true))
	source_entity = source


func is_expired() -> bool:
	return remaining <= 0.0


func is_dot() -> bool:
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "dot":
			return true
	return false


func get_dot_effects() -> Array:
	var result: Array = []
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "dot":
			result.append(effect)
	return result


func get_hot_effects() -> Array:
	var result: Array = []
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "hot":
			result.append(effect)
	return result


func get_shield_effects() -> Array:
	var result: Array = []
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "shield":
			result.append(effect)
	return result


func get_shield_remaining() -> int:
	var total := 0
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "shield":
			total += int(effect.get("remaining", 0))
	return total


func has_control_affect(affect: String) -> bool:
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "control":
			var affects: Array = effect.get("affects", [])
			for a in affects:
				if String(a) == affect:
					return true
	return false


func add_stack() -> bool:
	if stack_behavior == "stack":
		if stacks < max_stacks:
			stacks += 1
			remaining = duration
			_reset_shield_remaining()
			return true
		# 刷新持续时间
		remaining = duration
		_reset_shield_remaining()
		return false
	# refresh / independent: 仅刷新持续时间
	remaining = duration
	_reset_shield_remaining()
	return false


func _reset_shield_remaining() -> void:
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "shield":
			effect["remaining"] = int(effect.get("amount", 0))
