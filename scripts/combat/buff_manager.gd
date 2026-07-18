extends Node
class_name BuffManager

signal buff_applied(buff: BuffInstance)
signal buff_removed(buff: BuffInstance)
signal buff_ticked(buff: BuffInstance, damage: int)

var _buffs: Array[BuffInstance] = []
var _owner: Node  # 角色节点，需要有 take_damage 方法
# 异常积累制（设计案第8章）：status_type → 当前积累值
var _status_buildups: Dictionary = {}
# 触发阈值，按单位类型设置（normal/elite/boss）
var _status_threshold: int = StatusSystem.THRESHOLDS["normal"]


func _init(owner: Node) -> void:
	_owner = owner


func _process(delta: float) -> void:
	var to_remove: Array[BuffInstance] = []
	for buff in _buffs:
		buff.remaining -= delta
		if buff.is_expired():
			to_remove.append(buff)
			continue
		# DoT 跳伤害（设计案 8.3：快照 + 标签贯通）
		for effect in buff.get_dot_effects():
			effect["tick_timer"] = float(effect.get("tick_timer", 0.0)) - delta
			if float(effect.get("tick_timer", 0.0)) <= 0.0:
				effect["tick_timer"] = float(effect.get("interval", 1.0))
				var dmg_result := _calculate_dot_damage(effect, buff)
				var dmg := int(dmg_result.get("damage", 0))
				if dmg > 0 and _owner.has_method("take_damage"):
					# dmg_result 非空时 take_damage 走新链路，跳过 defense 减法（dmg 已是最终伤害）
					# source=null 使反伤不触发（DoT 不应触发反伤循环）
					_owner.take_damage(dmg, null, false, dmg_result)
				# DoT 吸血（设计案 7.3：25% 效率），回给施毒者
				_apply_dot_lifesteal(buff, dmg)
				buff_ticked.emit(buff, dmg)
		# HoT 跳治疗（设计案 7.1：应用施疗者 heal_bonus）
		for effect in buff.get_hot_effects():
			effect["tick_timer"] = float(effect.get("tick_timer", 0.0)) - delta
			if float(effect.get("tick_timer", 0.0)) <= 0.0:
				effect["tick_timer"] = float(effect.get("interval", 1.0))
				var heal_amount := int(effect.get("heal", 0))
				if _owner.has_method("heal"):
					_owner.heal(heal_amount, _resolve_healer_stats(buff))
	# 异常积累衰减（脱离攻击后每秒 -10，设计案 8.2）
	for status_type in _status_buildups.keys():
		_status_buildups[status_type] = maxf(0.0, float(_status_buildups[status_type]) - StatusSystem.BUILDUP_DECAY_PER_SEC * delta)
		if float(_status_buildups[status_type]) <= 0.0:
			_status_buildups.erase(status_type)
	for buff in to_remove:
		_remove_buff(buff)


## 设置异常触发阈值（按单位类型）
func set_status_unit_type(unit_type: String) -> void:
	_status_threshold = StatusSystem.get_threshold(unit_type)


## 异常积累施加（设计案 8.1）。
## status_type: 见 StatusSystem.STATUS_TYPES
## base: 基础积累值（来自技能节点 status_buildup）
## intensity: 攻击方异常强度
## source: 攻击者节点（用于 buff source_id）
## 特征免疫（设计案 10.1）：目标有对应异常免疫时直接 return。
## 阈值修正（设计案 10.1/15.4）：特征可放大阈值（如深渊 ×2）。
func apply_status_buildup(status_type: String, base: float, intensity: float, source: Node) -> void:
	# 特征免疫检查
	var traits: Array = []
	if _owner.has_method("get_combat_stats"):
		var stats = _owner.get_combat_stats()
		if stats != null and "traits" in stats:
			traits = stats.traits
	if not traits.is_empty():
		var immunities := EnemyTraits.get_combined_status_immunities(traits)
		if immunities.has(status_type):
			return
	# 读取目标异常抗性
	var resist := 0.0
	if _owner.has_method("get_combat_stats"):
		var stats = _owner.get_combat_stats()
		if stats != null and "status_resist" in stats:
			resist = float(stats.status_resist)
	var buildup := StatusSystem.calculate_buildup(base, intensity, resist)
	_status_buildups[status_type] = float(_status_buildups.get(status_type, 0.0)) + buildup
	# 应用特征阈值修正
	var threshold := float(_status_threshold)
	if not traits.is_empty():
		threshold *= EnemyTraits.get_combined_status_threshold_modifier(traits)
	# 达到阈值则触发对应 buff
	if float(_status_buildups[status_type]) >= threshold:
		var buff_id: int = StatusSystem.STATUS_BUFF_ID.get(status_type, 0)
		if buff_id > 0:
			var config: Dictionary = GameRegistry.buff_config.get_buff(buff_id)
			if not config.is_empty():
				var source_id := source.get_instance_id() if source != null else 0
				apply_buff(config, source_id)
		# 清空积累（或转衰减）
		_status_buildups[status_type] = 0.0


## 查询当前积累值（供 UI 显示）
func get_status_buildup(status_type: String) -> float:
	return float(_status_buildups.get(status_type, 0.0))


## 查询异常触发阈值
func get_status_threshold() -> int:
	return _status_threshold


func apply_buff(config: Dictionary, source: int = 0) -> void:
	var buff_id := int(config.get("id", 0))
	var behavior := String(config.get("stack_behavior", "refresh"))
	# 计算施盾者护盾强度（设计案 7.2），用于 shield effect 吸收量加成
	var shield_bonus := _resolve_shield_bonus(source)
	# 护盾总量上限检查（设计案 7.2：不超过 max_hp × 60%）
	if _has_shield_effect(config) and not _can_apply_shield(shield_bonus, config):
		return
	# 攻击方快照数据（DoT 用）：攻击力 + 增伤 + 穿透
	var attacker_snapshot := _build_attacker_snapshot(source)
	# independent: 每次施加都创建独立实例，不与已有同 ID buff 叠加
	if behavior != "independent":
		for buff in _buffs:
			if buff.buff_id == buff_id:
				# 叠加时同步施盾者 shield_bonus 到已有实例
				buff.shield_bonus = shield_bonus
				# 叠加时刷新 DoT 快照（用最新施加者的攻击力）
				_inject_dot_snapshot(buff, attacker_snapshot)
				buff.add_stack()
				buff_applied.emit(buff)
				return
	var buff := BuffInstance.new(config, source)
	buff.shield_bonus = shield_bonus
	buff._reset_shield_remaining()
	_inject_dot_snapshot(buff, attacker_snapshot)
	_buffs.append(buff)
	_spawn_effect(buff)
	buff_applied.emit(buff)


## 构建攻击方快照（设计案 8.3）：攻击力 + 增伤 + 穿透，供 DoT 每跳使用。
func _build_attacker_snapshot(source: int) -> Dictionary:
	var snap := {"attack": 0.0, "damage_bonus": 0.0, "armor_pen_percent": 0.0, "armor_pen_flat": 0, "magic_pen_percent": 0.0, "magic_pen_flat": 0}
	var source_stats = null
	if source == 0:
		if _owner.has_method("get_combat_stats"):
			source_stats = _owner.get_combat_stats()
	else:
		var source_node := instance_from_id(source)
		if source_node != null and is_instance_valid(source_node) and source_node.has_method("get_combat_stats"):
			source_stats = source_node.get_combat_stats()
	if source_stats == null:
		return snap
	if "attack" in source_stats:
		snap["attack"] = float(source_stats.attack)
	if "armor_pen_percent" in source_stats:
		snap["armor_pen_percent"] = clampf(float(source_stats.armor_pen_percent), 0.0, 0.5)
	if "armor_pen_flat" in source_stats:
		snap["armor_pen_flat"] = int(source_stats.armor_pen_flat)
	if "magic_pen_percent" in source_stats:
		snap["magic_pen_percent"] = clampf(float(source_stats.magic_pen_percent), 0.0, 0.5)
	if "magic_pen_flat" in source_stats:
		snap["magic_pen_flat"] = int(source_stats.magic_pen_flat)
	return snap


## 将攻击方快照注入到 buff 的 DoT effects（设计案 8.3）。
## 仅对含 attack_ratio 的 dot effect 生效；纯固定值 DoT 不需快照。
func _inject_dot_snapshot(buff: BuffInstance, snap: Dictionary) -> void:
	for effect in buff.effects:
		if not (effect is Dictionary):
			continue
		if String(effect.get("type", "")) != "dot":
			continue
		var ratio := float(effect.get("attack_ratio", 0.0))
		if ratio <= 0.0:
			continue  # 纯固定值 DoT，跳过快照
		effect["snapshot_attack"] = float(snap.get("attack", 0.0))
		effect["snapshot_bonus"] = float(snap.get("damage_bonus", 0.0))
		effect["snapshot_armor_pen_percent"] = float(snap.get("armor_pen_percent", 0.0))
		effect["snapshot_armor_pen_flat"] = int(snap.get("armor_pen_flat", 0))
		effect["snapshot_magic_pen_percent"] = float(snap.get("magic_pen_percent", 0.0))
		effect["snapshot_magic_pen_flat"] = int(snap.get("magic_pen_flat", 0))


## 从施盾者 stats 读取 shield_bonus（施盾者侧乘区，设计案 7.2）。
## source 是 instance_id；反查失败时返回 0。
func _resolve_shield_bonus(source: int) -> float:
	if source == 0:
		# 自施：读自身 shield_bonus
		if _owner.has_method("get_combat_stats"):
			var stats = _owner.get_combat_stats()
			if stats != null and "shield_bonus" in stats:
				return clampf(float(stats.shield_bonus), 0.0, 5.0)
		return 0.0
	var source_node := instance_from_id(source)
	if source_node == null or not is_instance_valid(source_node):
		return 0.0
	if source_node.has_method("get_combat_stats"):
		var stats = source_node.get_combat_stats()
		if stats != null and "shield_bonus" in stats:
			return clampf(float(stats.shield_bonus), 0.0, 5.0)
	return 0.0


## 判断 config 是否含 shield effect
func _has_shield_effect(config: Dictionary) -> bool:
	var effects = config.get("effects", [])
	if not (effects is Array):
		return false
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "shield":
			return true
	return false


## 护盾总量上限检查（设计案 7.2：总护盾 ≤ max_hp × 60%）。
## shield_bonus 用于估算新护盾的实际吸收量。
func _can_apply_shield(shield_bonus: float, config: Dictionary) -> bool:
	var max_hp := 0
	if _owner.has_method("get_combat_stats"):
		var stats = _owner.get_combat_stats()
		if stats != null and "max_hp" in stats:
			max_hp = int(stats.max_hp)
	if max_hp <= 0:
		return true  # 无 max_hp 信息时不拦截
	var cap := int(roundi(float(max_hp) * 0.6))
	var current := get_total_shield()
	# 估算新护盾实际吸收量
	var new_amount := 0
	for effect in config.get("effects", []):
		if effect is Dictionary and String(effect.get("type", "")) == "shield":
			new_amount += int(roundi(float(int(effect.get("amount", 0))) * (1.0 + shield_bonus)))
	return current + new_amount <= cap


## 聚合所有 active buff 的护盾剩余量
func get_total_shield() -> int:
	var total := 0
	for buff in _buffs:
		for effect in buff.get_shield_effects():
			total += int(effect.get("remaining", 0))
	return total


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


## 从 buff.source_entity（instance_id）反查施疗者 stats，用于 HoT 应用 heal_bonus。
## 施疗者可能已死亡/离开场景，反查失败时返回 null（heal 按自疗处理）。
func _resolve_healer_stats(buff: BuffInstance):
	if buff.source_entity == 0:
		return null
	var source_node := instance_from_id(buff.source_entity)
	if source_node == null or not is_instance_valid(source_node):
		return null
	if source_node.has_method("get_combat_stats"):
		return source_node.get_combat_stats()
	return null


## DoT 吸血（设计案 7.3：25% 效率）。每跳伤害回给施毒者。
func _apply_dot_lifesteal(buff: BuffInstance, dmg: int) -> void:
	if buff.source_entity == 0 or dmg <= 0:
		return
	var source_node := instance_from_id(buff.source_entity)
	if source_node == null or not is_instance_valid(source_node):
		return
	if not source_node.has_method("heal"):
		return
	var stats = null
	if source_node.has_method("get_combat_stats"):
		stats = source_node.get_combat_stats()
	if stats == null or not "lifesteal" in stats:
		return
	var lifesteal := clampf(float(stats.lifesteal), 0.0, 0.2)
	if lifesteal <= 0.0:
		return
	var heal_amount := int(roundi(float(dmg) * lifesteal * 0.25))
	if heal_amount > 0:
		source_node.heal(heal_amount, stats)


## 计算单次 DoT 伤害（设计案 8.3：快照 + 标签贯通）。
## - 有 attack_ratio + snapshot：基础伤害 = snapshot_attack × ratio × (1 + snapshot_bonus)
## - 无快照（旧数据 fallback）：基础伤害 = effect.damage
## - 有 damage_tag/damage_channel：走 DamageCalculator 完整链路（含目标魔抗/标签克制/穿甲）
## - 无标签：直接返回基础伤害（兼容旧 dot，take_damage 旧链路做 defense 减法）
## 持续伤害默认 can_crit=false / can_dodge=false / can_block=false。
## stacks 作为最终伤害乘数。
func _calculate_dot_damage(effect: Dictionary, buff: BuffInstance) -> Dictionary:
	var ratio := float(effect.get("attack_ratio", 0.0))
	var base_damage := 0
	var has_snapshot := effect.has("snapshot_attack") and ratio > 0.0
	if has_snapshot:
		var snapshot_attack := float(effect.get("snapshot_attack", 0.0))
		var snapshot_bonus := float(effect.get("snapshot_bonus", 0.0))
		base_damage = int(roundi(snapshot_attack * ratio * (1.0 + snapshot_bonus)))
	else:
		base_damage = int(effect.get("damage", 0))
	# 无标签：直接返回（兼容旧 dot，take_damage 旧链路做 defense 减法）
	var damage_tag := String(effect.get("damage_tag", ""))
	var damage_channel := String(effect.get("damage_channel", ""))
	if damage_tag.is_empty() and damage_channel.is_empty():
		return {"damage": base_damage * buff.stacks, "dodged": false, "blocked": false, "crit": false}
	# 有标签：走 DamageCalculator 完整链路
	var ctx := DamageCalculator.DamageContext.new()
	ctx.attacker_attack = float(effect.get("snapshot_attack", 0.0)) if has_snapshot else 0.0
	ctx.skill_ratio = ratio if has_snapshot else 0.0
	ctx.flat_damage = base_damage if not has_snapshot else 0
	ctx.can_crit = false  # 持续伤害默认不暴击（设计案 8.3）
	ctx.crit_rate = 0.0
	ctx.crit_damage = 1.0
	ctx.damage_channel = damage_channel if not damage_channel.is_empty() else "physical"
	ctx.damage_tag = damage_tag if not damage_tag.is_empty() else "slash"
	ctx.attacker_damage_bonus = float(effect.get("snapshot_bonus", 0.0))
	ctx.armor_pen_percent = float(effect.get("snapshot_armor_pen_percent", 0.0))
	ctx.armor_pen_flat = int(effect.get("snapshot_armor_pen_flat", 0))
	ctx.magic_pen_percent = float(effect.get("snapshot_magic_pen_percent", 0.0))
	ctx.magic_pen_flat = int(effect.get("snapshot_magic_pen_flat", 0))
	ctx.can_dodge = false  # 持续伤害默认不可闪避
	ctx.can_block = false  # 持续伤害默认不可格挡
	var defense := _build_dot_defense_context()
	var calc := DamageCalculator.new()
	var result := calc.calculate(ctx, defense)
	# stacks 作为最终乘数
	result["damage"] = int(result.get("damage", 0)) * buff.stacks
	return result


## 构建目标的 DefenseContext（DoT 用，从 _owner 读取防御数据）
func _build_dot_defense_context() -> DamageCalculator.DefenseContext:
	var defense := DamageCalculator.DefenseContext.new()
	if not _owner.has_method("get_combat_stats"):
		return defense
	var stats = _owner.get_combat_stats()
	if stats == null:
		return defense
	defense.armor = int(stats.defense) if "defense" in stats else 0
	defense.magic_resist = int(stats.magic_resist) if "magic_resist" in stats else 0
	defense.block_rate = 0.0  # DoT 不可格挡
	defense.dodge_rate = 0.0  # DoT 不可闪避
	defense.target_level = int(stats.level) if "level" in stats else 1
	if "traits" in stats:
		defense.tag_resistance = EnemyTraits.get_combined_tag_multipliers(stats.traits)
	# DoT 也应读取目标 active buff 的 tag_modifier（感电/标记）+ vulnerability_modifier（侵蚀）
	if _owner.has_method("get_buff_manager"):
		var bm = _owner.get_buff_manager()
		if bm != null and bm.has_method("get_active_buffs"):
			var tag_vuln: Dictionary = {}
			var tag_pen: Dictionary = {}
			var global_vuln := 0.0
			for buff in bm.get_active_buffs():
				for eff in buff.effects:
					if not (eff is Dictionary):
						continue
					var etype := String(eff.get("type", ""))
					if etype == "tag_modifier":
						var etag := String(eff.get("tag", ""))
						if etag.is_empty():
							continue
						tag_vuln[etag] = float(tag_vuln.get(etag, 0.0)) + float(eff.get("vuln_bonus", 0.0))
						tag_pen[etag] = float(tag_pen.get(etag, 0.0)) + float(eff.get("armor_pen_bonus", 0.0))
					elif etype == "vulnerability_modifier":
						global_vuln += float(eff.get("value", 0.0)) * float(buff.stacks)
			defense.tag_vulnerability = tag_vuln
			defense.tag_armor_pen = tag_pen
			defense.global_vulnerability = global_vuln
	return defense
