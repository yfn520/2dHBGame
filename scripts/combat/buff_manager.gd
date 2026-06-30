extends Node
class_name BuffManager

signal buff_applied(buff: BuffInstance)
signal buff_removed(buff: BuffInstance)
signal buff_ticked(buff: BuffInstance, damage: int)

var _buffs: Array[BuffInstance] = []
var _owner: Node  # 角色节点，需要有 take_damage 方法


func _init(owner: Node) -> void:
	_owner = owner


func _process(delta: float) -> void:
	var to_remove: Array[BuffInstance] = []
	for buff in _buffs:
		buff.remaining -= delta
		if buff.is_expired():
			to_remove.append(buff)
			continue
		# DoT 跳伤害
		if buff.is_dot():
			buff.tick_timer -= delta
			if buff.tick_timer <= 0.0:
				buff.tick_timer = buff.interval
				var dmg := buff.tick_damage * buff.stacks
				if _owner.has_method("take_damage"):
					_owner.take_damage(dmg)
				buff_ticked.emit(buff, dmg)
	for buff in to_remove:
		_remove_buff(buff)


func apply_buff(config: Dictionary, source: int = 0) -> void:
	var buff_id := int(config.get("id", 0))
	# 检查是否已有同类型 buff
	for buff in _buffs:
		if buff.buff_id == buff_id:
			buff.add_stack()
			return
	var buff := BuffInstance.new(config, source)
	_buffs.append(buff)
	_spawn_effect(buff)
	buff_applied.emit(buff)


func remove_buff_by_id(buff_id: int) -> void:
	for buff in _buffs:
		if buff.buff_id == buff_id:
			_remove_buff(buff)
			return


func remove_buff_by_type(buff_type: String) -> void:
	var to_remove: Array[BuffInstance] = []
	for buff in _buffs:
		if buff.buff_type == buff_type:
			to_remove.append(buff)
	for buff in to_remove:
		_remove_buff(buff)


func has_buff_type(buff_type: String) -> bool:
	for buff in _buffs:
		if buff.buff_type == buff_type:
			return true
	return false


func has_buff_id(buff_id: int) -> bool:
	for buff in _buffs:
		if buff.buff_id == buff_id:
			return true
	return false


func get_buff_count() -> int:
	return _buffs.size()


func get_speed_multiplier() -> float:
	var mult := 1.0
	for buff in _buffs:
		if buff.buff_type == "slow":
			mult = minf(mult, 1.0 - buff.slow_ratio)
	return mult


func can_act() -> bool:
	return not has_buff_type("stun") and not has_buff_type("freeze")


func can_move() -> bool:
	if not can_act():
		return false
	return not has_buff_type("paralysis")


func modify_damage(incoming: int) -> int:
	if has_buff_type("invincible"):
		return 0
	return incoming


func get_active_buffs() -> Array[BuffInstance]:
	return _buffs


func _remove_buff(buff: BuffInstance) -> void:
	if buff.effect_node != null and is_instance_valid(buff.effect_node):
		buff.effect_node.queue_free()
	_buffs.erase(buff)
	buff_removed.emit(buff)


func _spawn_effect(buff: BuffInstance) -> void:
	if buff.effect_scene.is_empty():
		return
	if not ResourceLoader.exists(buff.effect_scene):
		return
	var scene: PackedScene = load(buff.effect_scene)
	if scene == null:
		return
	var fx := scene.instantiate()
	buff.effect_node = fx
	_owner.add_child(fx)
