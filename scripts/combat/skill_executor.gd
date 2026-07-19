class_name SkillExecutor

## Executes only action nodes. Skills themselves no longer own combat type,
## damage, projectile, range, or buff fields.

var _owner: Node
var _stats
var _buff_manager: BuffManager


func _init(owner: Node, stats = null) -> void:
	_owner = owner
	_stats = stats


func execute_damage_area(node: Dictionary, origin: Vector2, context: SkillCastContext) -> Array[Area2D]:
	var result_key := String(node.get("result_key", "area_hit"))
	context.ensure_stream(result_key)
	var result: Array[Area2D] = []
	var shape := String(node.get("shape", "circle"))
	var radius := maxf(0.0, float(node.get("radius", 80.0)))
	var width := maxf(1.0, float(node.get("width", radius * 2.0)))
	var height := maxf(1.0, float(node.get("height", radius * 2.0)))
	for hurt_box in find_enemy_hurt_boxes():
		var delta := _hurt_box_center(hurt_box) - origin
		var inside := delta.length() <= radius if shape == "circle" else absf(delta.x) <= width * 0.5 and absf(delta.y) <= height * 0.5
		if not inside:
			continue
		apply_damage_node(node, hurt_box)
		context.publish(result_key, hurt_box)
		result.append(hurt_box)
	return result


func execute_fullscreen_damage(node: Dictionary, context: SkillCastContext) -> Array[Area2D]:
	var result_key := String(node.get("result_key", "fullscreen_hit"))
	context.ensure_stream(result_key)
	var result: Array[Area2D] = []
	for hurt_box in find_enemy_hurt_boxes():
		apply_damage_node(node, hurt_box)
		context.publish(result_key, hurt_box)
		result.append(hurt_box)
	return result


## 应用伤害节点（设计案第5章 + 第9章 元素反应）。
## node: melee_damage/area_damage/fullscreen_damage 节点
## hurt_box: 受击方 HurtBox
## skip_buildup: 反应附加伤害调用时为 true，跳过异常积累和反应触发（避免无限循环）
func apply_damage_node(node: Dictionary, hurt_box: Area2D, skip_buildup: bool = false) -> void:
	if hurt_box == null or not is_instance_valid(hurt_box):
		return
	var target: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	# 元素反应（设计案 9.2）：同次最多一种，按 REACTIONS 顺序匹配。反应附加伤害不再触发反应。
	var damage_tag := String(node.get("damage_tag", "slash"))
	var reaction := {"triggered": false}
	if not skip_buildup:
		reaction = ElementReaction.try_reaction(target, damage_tag)
	var reaction_triggered := bool(reaction.get("triggered", false))
	var reaction_effect: Dictionary = reaction.get("effect", {}) if reaction_triggered else {}
	var reaction_type := String(reaction_effect.get("type", ""))
	# 解析反应修正
	var reaction_vuln := 0.0           # damage_boost 注入到 tag_vulnerability
	var reaction_armor_pen := 0.0      # armor_pen_bonus 注入到 tag_armor_pen
	var reaction_shield_mult := 0.0    # shield_damage_boost 对最终伤害乘以加成
	var buildup_boost := 0.0           # buildup_boost 临时提升异常 buff 命中率（重构后语义）
	if reaction_triggered:
		match reaction_type:
			"damage_boost":
				reaction_vuln = float(reaction_effect.get("value", 0.0))
			"armor_pen_bonus":
				reaction_armor_pen = float(reaction_effect.get("value", 0.0))
			"shield_damage_boost":
				reaction_shield_mult = float(reaction_effect.get("value", 0.0))
			"buildup_boost":
				# 反应触发时透传 value 到 apply_buff_with_pity，叠加到异常 buff 命中率
				buildup_boost = float(reaction_effect.get("value", 0.0))
	# 计算伤害（含反应注入的临时修正）
	var result := _calculate_damage_with_reaction(node, target, reaction_vuln, reaction_armor_pen)
	# 护盾伤害加成：对最终伤害乘以加成（护盾吸收前，设计案 9.2）
	if reaction_shield_mult > 0.0:
		result["damage"] = int(roundi(float(result.get("damage", 0)) * (1.0 + reaction_shield_mult)))
	if hurt_box.has_method("take_hit"):
		hurt_box.take_hit(result, _owner)
	# 反应消耗类：在伤害结算后消耗前置 buff + 施加 debuff / 附加伤害
	if reaction_triggered and (reaction_type == "consume_both" or reaction_type == "consume_stacks"):
		if reaction_type == "consume_stacks":
			# 先读取前置 buff 当前层数（consume_pre_buff 会移除整个 buff，设计案 9.2 按实际层数结算）
			var actual_stacks := _get_pre_buff_stacks(target, reaction)
			ElementReaction.consume_pre_buff(target, reaction)
			_apply_consume_stacks_damage(reaction_effect, target, actual_stacks)
		else:  # consume_both
			ElementReaction.consume_pre_buff(target, reaction)
			_apply_reaction_debuff(reaction_effect, target)
	# 应用节点配置的异常积累 / buff（反应附加伤害跳过异常积累，但保留 buildup_boost 放大）
	_apply_optional_buff(node, hurt_box, skip_buildup, buildup_boost)
	# 吸血（设计案 7.3）：按伤害来源效率结算回血
	_apply_lifesteal(result, node)


## 计算伤害并注入元素反应的临时修正（设计案 9.2）。
## reaction_vuln: damage_boost 加到当前标签的 tag_vulnerability
## reaction_armor_pen: armor_pen_bonus 加到当前标签的 tag_armor_pen
func _calculate_damage_with_reaction(node: Dictionary, target: Node, reaction_vuln: float, reaction_armor_pen: float) -> Dictionary:
	var ctx := _build_damage_context(node, target)
	var defense := _build_defense_context(target)
	if reaction_vuln > 0.0:
		var tag_vuln: Dictionary = defense.tag_vulnerability
		tag_vuln[ctx.damage_tag] = float(tag_vuln.get(ctx.damage_tag, 0.0)) + reaction_vuln
		defense.tag_vulnerability = tag_vuln
	if reaction_armor_pen > 0.0:
		var tag_pen: Dictionary = defense.tag_armor_pen
		tag_pen[ctx.damage_tag] = float(tag_pen.get(ctx.damage_tag, 0.0)) + reaction_armor_pen
		defense.tag_armor_pen = tag_pen
	var calc := DamageCalculator.new()
	return calc.calculate(ctx, defense)


## 读取前置 buff 的当前层数（consume_stacks 用，在 consume_pre_buff 移除前调用）。
## 找不到 buff 时返回 1（保底结算 1 层）。
func _get_pre_buff_stacks(target: Node, reaction: Dictionary) -> int:
	var pre := String(reaction.get("pre_status", ""))
	if pre.is_empty() or pre == "shield":
		return 1
	var pre_buff_id: int = ElementReaction.PRE_STATUS_BUFF_ID.get(pre, 0)
	if pre_buff_id == 0 or target == null or not target.has_method("get_buff_manager"):
		return 1
	var bm = target.get_buff_manager()
	if bm == null or not bm.has_method("get_active_buffs"):
		return 1
	for buff in bm.get_active_buffs():
		if int(buff.buff_id) == pre_buff_id:
			return int(buff.stacks)
	return 1


## 反应消耗类：施加 debuff（consume_both 用，例如燃烧+冰霜 → 融化 10023）。
func _apply_reaction_debuff(reaction_effect: Dictionary, target: Node) -> void:
	var debuff_id := int(reaction_effect.get("debuff_id", 0))
	if debuff_id <= 0 or target == null:
		return
	if not target.has_method("apply_buff_from_config"):
		return
	var config: Dictionary = GameRegistry.buff_config.get_buff(debuff_id)
	if config.is_empty():
		return
	var source_id := _owner.get_instance_id() if _owner != null else 0
	target.apply_buff_from_config(config, source_id)


## 反应消耗层数附加伤害（consume_stacks 用，例如侵蚀+神圣 → 每层 60% 攻击力神圣伤害）。
## actual_stacks: 前置 buff 被消耗前的实际层数；按 min(actual, max_stacks) 结算。
## 附加伤害为真实通道，不触发反伤/异常积累/反应（source=null + play_hit_reaction=false）。
func _apply_consume_stacks_damage(reaction_effect: Dictionary, target: Node, actual_stacks: int) -> void:
	if target == null or not target.has_method("take_damage"):
		return
	var max_stacks := int(reaction_effect.get("max_stacks", 1))
	var per_stack_ratio := float(reaction_effect.get("per_stack_damage_ratio", 0.0))
	if per_stack_ratio <= 0.0:
		return
	var effective_stacks := mini(actual_stacks, max_stacks)
	if effective_stacks <= 0:
		return
	var base_attack := 1.0
	if _stats != null and "attack" in _stats:
		base_attack = float(_stats.attack)
	if _buff_manager != null:
		base_attack = _buff_manager.get_modified_stat("attack", base_attack)
	var bonus_damage := int(roundi(base_attack * per_stack_ratio * float(effective_stacks)))
	if bonus_damage <= 0:
		return
	# 附加伤害：真实通道（不被防御减免），source=null 避免反伤循环，play_hit_reaction=false 避免受击动画
	# damage_result 标记 channel=true 让 take_damage 走新链路跳过 defense 减法
	target.take_damage(bonus_damage, null, false, {"damage": bonus_damage, "channel": "true"})


## 吸血结算（设计案 7.3）。
## 单体直接伤害（melee/projectile）=100%效率；范围伤害（area/fullscreen）=33%效率；
## DoT 在 buff_manager 单独处理（25%效率）；反伤不吸血。
func _apply_lifesteal(result: Dictionary, node: Dictionary) -> void:
	if _owner == null or not _owner.has_method("heal"):
		return
	var lifesteal := _get_attacker_lifesteal()
	if lifesteal <= 0.0:
		return
	# 闪避/格挡到 0 伤害不吸血
	var damage := int(result.get("damage", 0))
	if damage <= 0:
		return
	var node_type := String(node.get("type", ""))
	var efficiency := _get_lifesteal_efficiency(node_type)
	var heal_amount := int(roundi(float(damage) * lifesteal * efficiency))
	if heal_amount <= 0:
		return
	_owner.heal(heal_amount, _stats)


## 读取攻击者吸血率（buff 修饰 + 钳制 0~0.2）
func _get_attacker_lifesteal() -> float:
	var lifesteal := 0.0
	if _stats != null and "lifesteal" in _stats:
		lifesteal = float(_stats.lifesteal)
	if _buff_manager != null:
		lifesteal = _buff_manager.get_modified_stat("lifesteal", lifesteal)
	return clampf(lifesteal, 0.0, 0.2)


## 吸血来源效率（设计案 7.3）
func _get_lifesteal_efficiency(node_type: String) -> float:
	match node_type:
		"melee_damage", "spawn_projectile":
			return 1.0       # 单体直接
		"area_damage", "fullscreen_damage":
			return 0.33      # 范围
		_:
			return 1.0


func apply_target_buff(node: Dictionary, hurt_box: Area2D, skip_buildup: bool = false, buildup_boost: float = 0.0) -> void:
	if hurt_box == null or not is_instance_valid(hurt_box):
		return
	var target: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target == null:
		return
	# 反应附加伤害跳过概率判定（设计案 9.2：避免无限循环），直接施加
	if skip_buildup:
		var skip_buff_ids := _read_buff_ids(node)
		if skip_buff_ids.is_empty() or not target.has_method("apply_buff_from_config"):
			return
		var skip_source_id := _owner.get_instance_id() if _owner != null else 0
		for buff_id in skip_buff_ids:
			var skip_config: Dictionary = GameRegistry.buff_config.get_buff(int(buff_id))
			if not skip_config.is_empty():
				target.apply_buff_from_config(skip_config, skip_source_id)
		return
	# 统一走保底累积：异常 buff（config 配了 status_type）失败累积 pity，非异常 buff 纯概率
	var chance := float(node.get("chance", node.get("buff_chance", 1.0)))
	# 失败时累积概率增量（节点未配置时为 -1，由 buff_manager 回落到 PITY_INCREMENT 默认值）
	var pity_increment := float(node.get("pity_increment", -1.0))
	var buff_ids := _read_buff_ids(node)
	if buff_ids.is_empty():
		return
	# target 是角色节点（Player/Enemy），buff_manager 在其 combat 子节点（CombatComponent）上
	var target_bm = null
	if "combat" in target:
		var combat_node = target.get("combat")
		if combat_node != null and combat_node.has_method("get_buff_manager"):
			target_bm = combat_node.get_buff_manager()
	if target_bm == null and target.has_method("get_buff_manager"):
		target_bm = target.get_buff_manager()
	if target_bm == null:
		return
	var source_id := _owner.get_instance_id() if _owner != null else 0
	for buff_id in buff_ids:
		var config: Dictionary = GameRegistry.buff_config.get_buff(int(buff_id))
		if not config.is_empty():
			if target_bm.has_method("apply_buff_with_pity"):
				target_bm.apply_buff_with_pity(config, chance, source_id, buildup_boost, pity_increment)
			elif randf() <= chance and target.has_method("apply_buff_from_config"):
				# fallback：无保底累积方法时走旧概率链路
				target.apply_buff_from_config(config, source_id)


func apply_self_buff(node: Dictionary) -> void:
	if _owner == null or not _owner.has_method("apply_buff_from_config"):
		return
	var buff_ids := _read_buff_ids(node)
	var source_id := _owner.get_instance_id() if _owner != null else 0
	# 节点可配置 effect_offset_x/y 微调 buff 特效位置、effect_scale 缩放特效，注入到 config 副本传递给 buff_manager
	var has_offset := node.has("effect_offset_x") or node.has("effect_offset_y")
	var has_scale := node.has("effect_scale")
	for buff_id in buff_ids:
		var config: Dictionary = GameRegistry.buff_config.get_buff(int(buff_id))
		if not config.is_empty():
			if has_offset or has_scale:
				config = config.duplicate(true)
				if node.has("effect_offset_x"):
					config["effect_offset_x"] = float(node.get("effect_offset_x", 0.0))
				if node.has("effect_offset_y"):
					config["effect_offset_y"] = float(node.get("effect_offset_y", 0.0))
				if has_scale:
					config["effect_scale"] = maxf(0.01, float(node.get("effect_scale", 1.0)))
			_owner.apply_buff_from_config(config, source_id)


## 读取节点的 buff_ids 数组，兼容旧 buff_id 单值字段。
func _read_buff_ids(node: Dictionary) -> Array:
	var result: Array = []
	if node.has("buff_ids"):
		var raw = node.get("buff_ids", [])
		if raw is Array:
			for v in raw:
				result.append(int(v))
	elif node.has("buff_id"):
		var legacy := int(node.get("buff_id", 0))
		if legacy > 0:
			result.append(legacy)
	return result


func spawn_projectiles(node: Dictionary, origin: Vector2, context: SkillCastContext) -> void:
	if context.cancelled or _owner == null or not is_instance_valid(_owner):
		return
	var result_key := String(node.get("result_key", "projectile_hit"))
	context.ensure_stream(result_key)
	var emission := String(node.get("emission", "single"))
	match emission:
		"sequence":
			_spawn_sequence(node, origin, context, result_key)
		"fan":
			_spawn_fan(node, origin, context, result_key)
		"area_rain":
			_spawn_area_rain(node, origin, context, result_key)
		_:
			_spawn_straight(node, origin, _straight_direction(node), context, result_key)


func resolve_targets(node: Dictionary, origin: Vector2, context: SkillCastContext) -> Array[Area2D]:
	var target_mode := String(node.get("target", "origin"))
	match target_mode:
		"result", "last_result":
			return context.get_targets(String(node.get("result_key", "last_result")), String(node.get("delivery", "each_target")))
		"nearest_enemy":
			var nearest := find_nearest_enemy(float(node.get("target_search_range", 99999.0)))
			return [nearest] if nearest != null else []
		"area":
			return _find_area_targets(origin, node)
		"all_enemies":
			return find_enemy_hurt_boxes()
	return []


func find_enemy_hurt_boxes() -> Array[Area2D]:
	var result: Array[Area2D] = []
	if _owner == null or _owner.get_tree() == null:
		return result
	for node in _owner.get_tree().get_nodes_in_group("hurt_box"):
		if node is Area2D and not _is_friendly(node as Area2D):
			result.append(node as Area2D)
	return result


func find_nearest_enemy(max_range := INF) -> Area2D:
	var closest: Area2D = null
	var closest_distance := max_range
	if not _owner is Node2D:
		return null
	for hurt_box in find_enemy_hurt_boxes():
		var distance := (_owner as Node2D).global_position.distance_to(hurt_box.global_position)
		if distance <= closest_distance:
			closest_distance = distance
			closest = hurt_box
	return closest


func calculate_damage(ratio: float) -> int:
	# 兼容旧调用（弹道等无法在 spawn 时拿到目标防御的场景）。
	# 仅计算攻击侧原始伤害（含暴击），不含防御减法。
	# 新代码应使用 calculate_damage_full 走完整 DamageCalculator 链路。
	var ctx := _build_damage_context({"damage_ratio": ratio}, null)
	# 无目标时跳过闪避/格挡/防御，仅做攻击侧 + 暴击
	var base := ctx.attacker_attack * ctx.skill_ratio + float(ctx.flat_damage)
	var attacker_mult := 1.0 + ctx.attacker_damage_bonus
	var crit := ctx.can_crit and randf() < ctx.crit_rate
	var crit_mult := ctx.crit_damage if crit else 1.0
	var final := maxi(1, roundi(base * attacker_mult * crit_mult))
	return final


## 完整伤害计算（设计案第5章）。读取节点 damage_channel/damage_tag/flat_damage 等字段，
## 构造 DamageContext + DefenseContext 调用 DamageCalculator。
## 返回 {"damage": int, "dodged": bool, "blocked": bool, "crit": bool}。
func calculate_damage_full(node: Dictionary, target: Node) -> Dictionary:
	var ctx := _build_damage_context(node, target)
	var defense := _build_defense_context(target)
	var calc := DamageCalculator.new()
	return calc.calculate(ctx, defense)


## 从自身属性 + 节点字段构造攻击侧上下文。
func _build_damage_context(node: Dictionary, _target: Node) -> DamageCalculator.DamageContext:
	var ctx := DamageCalculator.DamageContext.new()
	# 攻击力（buff 修饰）
	var base_attack := 1.0
	if _stats != null and "attack" in _stats:
		base_attack = float(_stats.attack)
	var attack := base_attack
	if _buff_manager != null:
		attack = _buff_manager.get_modified_stat("attack", base_attack)
	ctx.attacker_attack = attack
	# 技能倍率与固定值
	ctx.skill_ratio = float(node.get("damage_ratio", node.get("attack_coefficient", 1.0)))
	ctx.flat_damage = int(node.get("flat_damage", 0))
	# 暴击（buff 修饰 + 钳制）
	var crit_rate := 0.0
	var crit_damage := 1.5
	if _stats != null:
		crit_rate = float(_stats.crit_rate) if "crit_rate" in _stats else 0.0
		crit_damage = float(_stats.crit_damage) if "crit_damage" in _stats else 1.5
	if _buff_manager != null:
		crit_rate = _buff_manager.get_modified_stat("crit_rate", crit_rate)
		crit_damage = _buff_manager.get_modified_stat("crit_damage", crit_damage)
	ctx.crit_rate = clampf(crit_rate, 0.0, 0.75)
	ctx.crit_damage = clampf(crit_damage, 1.0, 2.5)
	ctx.can_crit = bool(node.get("can_crit", true))
	# 伤害通道与标签（缺省兼容旧技能：物理/斩击）
	ctx.damage_channel = String(node.get("damage_channel", "physical"))
	ctx.damage_tag = String(node.get("damage_tag", "slash"))
	# 攻击侧增伤（暂无独立字段，预留 buff 注入）
	ctx.attacker_damage_bonus = 0.0
	# 穿透（buff 修饰）
	if _stats != null:
		ctx.armor_pen_percent = clampf(float(_stats.armor_pen_percent) if "armor_pen_percent" in _stats else 0.0, 0.0, 0.5)
		ctx.armor_pen_flat = int(_stats.armor_pen_flat) if "armor_pen_flat" in _stats else 0
		ctx.magic_pen_percent = clampf(float(_stats.magic_pen_percent) if "magic_pen_percent" in _stats else 0.0, 0.0, 0.5)
		ctx.magic_pen_flat = int(_stats.magic_pen_flat) if "magic_pen_flat" in _stats else 0
	if _buff_manager != null:
		ctx.armor_pen_percent = clampf(_buff_manager.get_modified_stat("armor_pen_percent", ctx.armor_pen_percent), 0.0, 0.5)
		ctx.magic_pen_percent = clampf(_buff_manager.get_modified_stat("magic_pen_percent", ctx.magic_pen_percent), 0.0, 0.5)
	# 吸血（P0 仅携带，P1 生效）
	if _stats != null:
		ctx.attacker_lifesteal = clampf(float(_stats.lifesteal) if "lifesteal" in _stats else 0.0, 0.0, 0.2)
	# 可闪避/可格挡（缺省 true）
	ctx.can_dodge = bool(node.get("can_dodge", true))
	ctx.can_block = bool(node.get("can_block", true))
	return ctx


## 从目标读取防御端数据。
func _build_defense_context(target: Node) -> DamageCalculator.DefenseContext:
	var defense := DamageCalculator.DefenseContext.new()
	if target == null:
		return defense
	# 读取目标的 combat_component stats + buff_manager
	var target_stats = null
	var target_buff_manager = null
	if target.has_method("get_combat_stats"):
		target_stats = target.get_combat_stats()
	if target.has_method("get_buff_manager"):
		target_buff_manager = target.get_buff_manager()
	# 护甲/魔抗（buff 修饰）
	var armor := 0
	var magic_resist := 0
	if target_stats != null:
		armor = int(target_stats.defense) if "defense" in target_stats else 0  # 旧字段 defense 兼容
		magic_resist = int(target_stats.magic_resist) if "magic_resist" in target_stats else 0
	if target_buff_manager != null:
		armor = int(target_buff_manager.get_modified_stat("defense", float(armor)))
		magic_resist = int(target_buff_manager.get_modified_stat("magic_resist", float(magic_resist)))
	defense.armor = armor
	defense.magic_resist = magic_resist
	# 格挡/闪避（buff 修饰 + 钳制）
	var block_rate := 0.0
	var dodge_rate := 0.0
	if target_stats != null:
		block_rate = float(target_stats.block_rate) if "block_rate" in target_stats else 0.0
		dodge_rate = float(target_stats.dodge_rate) if "dodge_rate" in target_stats else 0.0
	if target_buff_manager != null:
		block_rate = target_buff_manager.get_modified_stat("block_rate", block_rate)
		dodge_rate = target_buff_manager.get_modified_stat("dodge_rate", dodge_rate)
	defense.block_rate = clampf(block_rate, 0.0, 0.6)
	defense.dodge_rate = clampf(dodge_rate, 0.0, 0.35)
	# 目标等级（若目标无 level 字段，默认 1）
	if target_stats != null and "level" in target_stats:
		defense.target_level = int(target_stats.level)
	# 目标易伤（预留，buff 可施加 vulnerability stat_modifier；P0 暂无独立字段）
	defense.vulnerability = 0.0
	# 标签抗性：由敌人特征提供（设计案 10.1）
	if target_stats != null and "traits" in target_stats:
		var target_traits: Array = target_stats.traits
		defense.tag_resistance = EnemyTraits.get_combined_tag_multipliers(target_traits)
	# 标签级修正（设计案 8.2 感电/标记）+ 全标签易伤（设计案 8.2 侵蚀）：从目标 active buffs 聚合
	if target_buff_manager != null and target_buff_manager.has_method("get_active_buffs"):
		var tag_vuln: Dictionary = {}
		var tag_pen: Dictionary = {}
		var global_vuln := 0.0
		for buff in target_buff_manager.get_active_buffs():
			for effect in buff.effects:
				if not (effect is Dictionary):
					continue
				var etype := String(effect.get("type", ""))
				if etype == "tag_modifier":
					var etag := String(effect.get("tag", ""))
					if etag.is_empty():
						continue
					var vb := float(effect.get("vuln_bonus", 0.0))
					var ap := float(effect.get("armor_pen_bonus", 0.0))
					tag_vuln[etag] = float(tag_vuln.get(etag, 0.0)) + vb
					tag_pen[etag] = float(tag_pen.get(etag, 0.0)) + ap
				elif etype == "vulnerability_modifier":
					# 侵蚀：每层 +value% 全标签易伤
					var per_stack := float(effect.get("value", 0.0))
					global_vuln += per_stack * float(buff.stacks)
		defense.tag_vulnerability = tag_vuln
		defense.tag_armor_pen = tag_pen
		defense.global_vulnerability = global_vuln
	return defense



func _spawn_sequence(node: Dictionary, origin: Vector2, context: SkillCastContext, result_key: String) -> void:
	var count := maxi(1, int(node.get("count", 3)))
	var interval := maxf(0.0, float(node.get("interval", 0.15)))
	for index in range(count):
		if index == 0:
			_spawn_straight(node, origin, _straight_direction(node), context, result_key)
			continue
		var timer := _owner.get_tree().create_timer(interval * float(index))
		timer.timeout.connect(_spawn_delayed_straight.bind(node.duplicate(true), origin, context, result_key))


func _spawn_delayed_straight(node: Dictionary, origin: Vector2, context: SkillCastContext, result_key: String) -> void:
	if context.cancelled:
		return
	_spawn_straight(node, origin, _straight_direction(node), context, result_key)


func _spawn_fan(node: Dictionary, origin: Vector2, context: SkillCastContext, result_key: String) -> void:
	var count := maxi(1, int(node.get("count", 3)))
	var spread := float(node.get("spread_degrees", 20.0))
	for index in range(count):
		var factor := 0.5 if count == 1 else float(index) / float(count - 1)
		var angle_offset := lerpf(-spread * 0.5, spread * 0.5, factor)
		_spawn_straight(node, origin, _straight_direction(node, angle_offset), context, result_key)


func _spawn_area_rain(node: Dictionary, origin: Vector2, context: SkillCastContext, result_key: String) -> void:
	var count := maxi(1, int(node.get("count", 12)))
	var interval := maxf(0.0, float(node.get("interval", 0.08)))
	var center := _find_area_rain_center(node)
	for index in range(count):
		if index == 0:
			_spawn_area_rain_arrow(node, origin, center, context, result_key)
			continue
		var timer := _owner.get_tree().create_timer(interval * float(index))
		timer.timeout.connect(_spawn_delayed_rain.bind(node.duplicate(true), origin, center, context, result_key))


func _spawn_delayed_rain(node: Dictionary, origin: Vector2, center: Vector2, context: SkillCastContext, result_key: String) -> void:
	if context.cancelled:
		return
	_spawn_area_rain_arrow(node, origin, center, context, result_key)


func _spawn_area_rain_arrow(node: Dictionary, origin: Vector2, center: Vector2, context: SkillCastContext, result_key: String) -> void:
	var width := maxf(1.0, float(node.get("area_width", 260.0)))
	var height := maxf(1.0, float(node.get("area_height", 90.0)))
	var landing := center + Vector2(randf_range(-width * 0.5, width * 0.5), randf_range(-height * 0.5, height * 0.5))
	var gravity := maxf(0.0, float(node.get("gravity", 900.0)))
	var velocity := _ballistic_velocity(origin, landing, gravity, float(node.get("arc_height", 180.0)), float(node.get("speed", 360.0)))
	_spawn_ballistic(node, origin, velocity, gravity, context, result_key)


func _spawn_straight(node: Dictionary, origin: Vector2, direction: Vector2, context: SkillCastContext, result_key: String) -> void:
	var speed := maxf(1.0, float(node.get("speed", 300.0)))
	if String(node.get("trajectory", "straight")) == "ballistic":
		_spawn_ballistic(node, origin, direction * speed, maxf(0.0, float(node.get("gravity", 900.0))), context, result_key)
		return
	var projectile := _instantiate_projectile(node)
	if projectile == null:
		return
	projectile.global_position = origin
	_setup_projectile_with_node(projectile, node, direction, speed, context, result_key)


func _spawn_ballistic(node: Dictionary, origin: Vector2, velocity: Vector2, gravity: float, context: SkillCastContext, result_key: String) -> void:
	var projectile := _instantiate_projectile(node)
	if projectile == null:
		return
	projectile.global_position = origin
	# P1 新链路：弹道命中通过 setup_with_node 走 apply_damage_node
	var lifetime := float(node.get("lifetime", 5.0))
	var rotate_visual := bool(node.get("rotate_to_velocity", true))
	if projectile.has_method("setup_with_node"):
		projectile.setup_with_node(Vector2.ZERO, 0.0, node, _owner, lifetime, rotate_visual, Callable(self, "_on_projectile_hit_full"), true, velocity, gravity)
	_connect_projectile_result(projectile, context, result_key)
	_add_projectile_to_scene(projectile)


func _instantiate_projectile(node: Dictionary) -> Node2D:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("弹道节点缺少可加载的 scene: %s" % scene_path)
		return null
	var packed := load(scene_path) as PackedScene
	var projectile := packed.instantiate() as Node2D if packed != null else null
	if projectile != null:
		# 应用角色视觉缩放，使弹道大小与角色缩放一致
		var vscale := _get_visual_scale()
		if not is_zero_approx(vscale) and not is_equal_approx(vscale, 1.0):
			projectile.scale *= Vector2(vscale, vscale)
		# 应用技能节点配置的弹道缩放（视觉与碰撞盒同步缩放）
		var node_scale := float(node.get("scale", 1.0))
		if not is_zero_approx(node_scale) and not is_equal_approx(node_scale, 1.0):
			projectile.scale *= Vector2(node_scale, node_scale)
	return projectile


## 读取角色 CharacterActionSet 的视觉缩放，用于弹道/特效等比缩放。
func _get_visual_scale() -> float:
	if _owner == null:
		return 1.0
	var visual_root := _owner.get_node_or_null("CharacterActionSet") as Node2D
	if visual_root != null and not is_zero_approx(visual_root.scale.x):
		return absf(visual_root.scale.x)
	return 1.0


func _setup_projectile_with_node(projectile: Node2D, node: Dictionary, direction: Vector2, speed: float, context: SkillCastContext, result_key: String) -> void:
	var lifetime := float(node.get("lifetime", 5.0))
	var rotate_visual := bool(node.get("rotate_to_velocity", true))
	# P1 新链路：弹道命中通过 setup_with_node 走 apply_damage_node
	if projectile.has_method("setup_with_node"):
		projectile.setup_with_node(direction, speed, node, _owner, lifetime, rotate_visual, Callable(self, "_on_projectile_hit_full"))
	_connect_projectile_result(projectile, context, result_key)
	_add_projectile_to_scene(projectile)


## P1 新链路回调：弹道命中时走 apply_damage_node（含反应/异常积累/标签贯通/吸血）。
## 节点 type 标记为 spawn_projectile 让 _apply_lifesteal 按 100% 效率吸血。
func _on_projectile_hit_full(hurt_box: Area2D, node: Dictionary, _source: Node) -> void:
	# 用节点副本，type 设为 spawn_projectile 让吸血效率判断走单体路径
	var node_copy: Dictionary = node.duplicate(true)
	node_copy["type"] = "spawn_projectile"
	apply_damage_node(node_copy, hurt_box)


func _connect_projectile_result(projectile: Node2D, context: SkillCastContext, result_key: String) -> void:
	if projectile.has_signal("hit_target"):
		projectile.connect("hit_target", Callable(self, "_on_projectile_hit").bind(context, result_key))


func _on_projectile_hit(hurt_box: Area2D, context: SkillCastContext, result_key: String) -> void:
	context.publish(result_key, hurt_box)


func _add_projectile_to_scene(projectile: Node2D) -> void:
	var scene := _owner.get_tree().current_scene if _owner != null and _owner.get_tree() != null else null
	if scene != null:
		scene.add_child(projectile)


func _straight_direction(node: Dictionary, offset_degrees := 0.0) -> Vector2:
	var aim_mode := String(node.get("aim_mode", "facing_elevation"))
	if aim_mode == "nearest_enemy":
		var target := find_nearest_enemy(float(node.get("target_search_range", 99999.0)))
		if target != null and _owner is Node2D:
			return (target.global_position - (_owner as Node2D).global_position).normalized()
	var facing := _get_facing().x
	var elevation := deg_to_rad(float(node.get("elevation_degrees", 0.0)) + offset_degrees)
	return Vector2(facing * cos(elevation), -sin(elevation)).normalized()


func _find_area_rain_center(node: Dictionary) -> Vector2:
	var search_range := maxf(1.0, float(node.get("target_search_range", 500.0)))
	if String(node.get("aim_mode", "enemy_area")) == "enemy_area":
		var target := find_nearest_enemy(search_range)
		if target != null:
			return target.global_position
	if _owner is Node2D:
		return (_owner as Node2D).global_position + _get_facing() * float(node.get("forward_distance", search_range * 0.5))
	return Vector2.ZERO


func _ballistic_velocity(origin: Vector2, landing: Vector2, gravity: float, arc_height: float, fallback_speed: float) -> Vector2:
	if gravity <= 0.0:
		return (landing - origin).normalized() * fallback_speed
	var apex_y := minf(origin.y, landing.y) - maxf(1.0, arc_height)
	var rise := maxf(0.0, origin.y - apex_y)
	var fall := maxf(0.0, landing.y - apex_y)
	var up_time := sqrt(2.0 * rise / gravity)
	var down_time := sqrt(2.0 * fall / gravity)
	var total_time := maxf(0.08, up_time + down_time)
	return Vector2((landing.x - origin.x) / total_time, -sqrt(2.0 * gravity * rise))


func _find_area_targets(origin: Vector2, node: Dictionary) -> Array[Area2D]:
	var result: Array[Area2D] = []
	var radius := maxf(0.0, float(node.get("radius", 80.0)))
	for hurt_box in find_enemy_hurt_boxes():
		if _hurt_box_center(hurt_box).distance_to(origin) <= radius:
			result.append(hurt_box)
	return result


## 获取 hurt_box 的身体中心位置（对齐 origin=caster 的身体中心参考系）。
## hurt_box.global_position 是 HurtBox 节点位置（= 角色根/脚底），
## 叠加 _owner_entity.get_body_center_y() 抬到身体中心，与 _resolve_origin(caster) 一致。
func _hurt_box_center(hurt_box: Area2D) -> Vector2:
	var pos := hurt_box.global_position
	var target_owner: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target_owner != null and target_owner.has_method("get_body_center_y"):
		pos.y += float(target_owner.get_body_center_y())
	return pos


## 伤害节点附加 buff（设计案 7.3 + 9.2，重构后统一走保底累积）。
## skip_buildup: 反应附加伤害调用时为 true，跳过概率判定直接施加
## buildup_boost: 元素反应临时命中率加成（如潮湿+冰霜 +50%），透传到 apply_buff_with_pity
func _apply_optional_buff(node: Dictionary, hurt_box: Area2D, skip_buildup: bool = false, buildup_boost: float = 0.0) -> void:
	# 读取伤害节点配置的 buff_chance 和 buff_ids，复用 apply_target_buff 的保底累积链路
	var buff_chance := float(node.get("buff_chance", 0.0))
	var buff_ids := _read_buff_ids(node)
	if buff_ids.is_empty():
		return
	# 透传节点配置的 pity_increment（失败时累积概率增量）
	var pity_increment := float(node.get("pity_increment", -1.0))
	apply_target_buff({"buff_ids": buff_ids, "chance": buff_chance, "pity_increment": pity_increment}, hurt_box, skip_buildup, buildup_boost)


func _get_facing() -> Vector2:
	var sprite: AnimatedSprite2D = _owner.get_node_or_null("CharacterActionSet/AnimatedSprite2D") if _owner != null else null
	if sprite != null:
		return Vector2.RIGHT if sprite.flip_h else Vector2.LEFT
	return Vector2.RIGHT


func _is_friendly(hurt_box: Area2D) -> bool:
	var target: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target == null or _owner == null:
		return false
	return target == _owner \
		or (_owner.is_in_group("player") and target.is_in_group("player")) \
		or (_owner.is_in_group("enemies") and target.is_in_group("enemies"))
