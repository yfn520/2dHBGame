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
		for effect in buff.get_dot_effects():
			effect["tick_timer"] = float(effect.get("tick_timer", 0.0)) - delta
			if float(effect.get("tick_timer", 0.0)) <= 0.0:
				effect["tick_timer"] = float(effect.get("interval", 1.0))
				var dmg := int(effect.get("damage", 0)) * buff.stacks
				if _owner.has_method("take_damage"):
					_owner.take_damage(dmg, null, false)
				buff_ticked.emit(buff, dmg)
		# HoT 跳治疗
		for effect in buff.get_hot_effects():
			effect["tick_timer"] = float(effect.get("tick_timer", 0.0)) - delta
			if float(effect.get("tick_timer", 0.0)) <= 0.0:
				effect["tick_timer"] = float(effect.get("interval", 1.0))
				var heal_amount := int(effect.get("heal", 0))
				if _owner.has_method("heal"):
					_owner.heal(heal_amount)
	for buff in to_remove:
		_remove_buff(buff)


func apply_buff(config: Dictionary, source: int = 0) -> void:
	var buff_id := int(config.get("id", 0))
	var behavior := String(config.get("stack_behavior", "refresh"))
	# independent: 每次施加都创建独立实例，不与已有同 ID buff 叠加
	if behavior != "independent":
		for buff in _buffs:
			if buff.buff_id == buff_id:
				buff.add_stack()
				buff_applied.emit(buff)
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
		for effect in buff.effects:
			if effect is Dictionary and String(effect.get("type", "")) == "control" \
			   and String(effect.get("control_type", "")) == buff_type:
				to_remove.append(buff)
				break
	for buff in to_remove:
		_remove_buff(buff)


func dispel(category: String, count: int = -1) -> void:
	var to_remove: Array[BuffInstance] = []
	for buff in _buffs:
		if buff.category == category:
			to_remove.append(buff)
			if count > 0 and to_remove.size() >= count:
				break
	for buff in to_remove:
		_remove_buff(buff)


func has_buff_type(buff_type: String) -> bool:
	for buff in _buffs:
		for effect in buff.effects:
			if effect is Dictionary and String(effect.get("type", "")) == "control" \
			   and String(effect.get("control_type", "")) == buff_type:
				return true
	return false


func has_buff_id(buff_id: int) -> bool:
	for buff in _buffs:
		if buff.buff_id == buff_id:
			return true
	return false


func get_buff_count() -> int:
	return _buffs.size()


func can_act() -> bool:
	for buff in _buffs:
		if buff.has_control_affect("act"):
			return false
	return true


func can_move() -> bool:
	if not can_act():
		return false
	for buff in _buffs:
		if buff.has_control_affect("move"):
			return false
	return true


func can_use_skill() -> bool:
	if not can_act():
		return false
	for buff in _buffs:
		if buff.has_control_affect("skill"):
			return false
	return true


func is_invincible() -> bool:
	for buff in _buffs:
		if buff.has_control_affect("be_damaged"):
			return true
	return false


func get_modified_stat(stat_name: String, base_value: float) -> float:
	var value := base_value
	# 先应用 add（加法）
	for buff in _buffs:
		for effect in buff.effects:
			if effect is Dictionary and String(effect.get("type", "")) == "stat_modifier" \
			   and String(effect.get("stat", "")) == stat_name \
			   and String(effect.get("mode", "")) == "add":
				value += float(effect.get("value", 0.0)) * buff.stacks
	# 再应用 mul（乘法）
	for buff in _buffs:
		for effect in buff.effects:
			if effect is Dictionary and String(effect.get("type", "")) == "stat_modifier" \
			   and String(effect.get("stat", "")) == stat_name \
			   and String(effect.get("mode", "")) == "mul":
				value *= float(effect.get("value", 1.0))
	# 最后应用 set（覆盖）
	for buff in _buffs:
		for effect in buff.effects:
			if effect is Dictionary and String(effect.get("type", "")) == "stat_modifier" \
			   and String(effect.get("stat", "")) == stat_name \
			   and String(effect.get("mode", "")) == "set":
				value = float(effect.get("value", value))
	return value


func modify_damage(incoming: int) -> int:
	if is_invincible():
		return 0
	var remaining := incoming
	# 扣除护盾
	for buff in _buffs:
		for effect in buff.get_shield_effects():
			var shield_remaining := int(effect.get("remaining", 0))
			if shield_remaining <= 0:
				continue
			var absorbed := mini(shield_remaining, remaining)
			effect["remaining"] = shield_remaining - absorbed
			remaining -= absorbed
			if remaining <= 0:
				return 0
	return remaining


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
		push_warning("Buff effect_scene 引用不存在: %s (buff_id=%d)" % [buff.effect_scene, buff.buff_id])
		return
	var scene: PackedScene = load(buff.effect_scene)
	if scene == null:
		push_warning("Buff effect_scene 加载失败: %s (buff_id=%d)" % [buff.effect_scene, buff.buff_id])
		return
	var fx := scene.instantiate()
	buff.effect_node = fx
	_owner.add_child(fx)
	if fx is Node2D:
		var node2d := fx as Node2D
		# 角色原点在脚底，把 buff 特效抬到身体中心，避免出现在脚底
		node2d.position.y = _get_body_center_y()
		# 叠加技能节点 apply_self_buff 配置的微调偏移：
		# x 按朝向镜像（对齐预览 mirror_x），y 不翻转（垂直方向不受朝向影响）
		var facing := _get_owner_facing_sign()
		node2d.position.x += buff.effect_offset.x * facing
		node2d.position.y += buff.effect_offset.y
		# 应用技能节点配置的特效缩放（默认 1.0）
		node2d.scale *= Vector2(buff.effect_scale, buff.effect_scale)
		# 渲染在角色身前，避免被角色遮挡（与 combat_component 的 attachment_layer=front 一致）
		var visual_root := _owner.get_node_or_null("CharacterActionSet") as Node2D
		var visual_z := visual_root.z_index if visual_root != null else 0
		node2d.z_as_relative = true
		node2d.z_index = visual_z + 1


## 读取角色 CollisionShape2D 的纵向中心（相对原点），用于把 buff 特效抬到身体高度。
## 角色原点通常在脚底，碰撞盒中心即身体中心。
func _get_body_center_y() -> float:
	var col := _owner.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or col.shape == null:
		return -50.0
	return col.position.y


## 读取角色当前朝向符号：1.0=朝右，-1.0=朝左。对齐 combat_actor_base.get_facing_sign。
## 用于把预览中按朝右配置的 effect_offset.x 在朝左时翻转。
func _get_owner_facing_sign() -> float:
	if _owner != null and _owner.has_method("get_facing_sign"):
		return float(_owner.get_facing_sign())
	return 1.0
