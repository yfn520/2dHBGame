class_name SkillExecutor
## 技能执行器
## 根据技能类型(melee/projectile/penetrate/aoe/fullscreen/self)执行不同的伤害逻辑

var _owner: Node
var _stats  # CharacterStats 或 EnemyStats


func _init(owner: Node, stats = null) -> void:
	_owner = owner
	_stats = stats


func execute(skill: Dictionary) -> void:
	var skill_type: String = skill.get("type", "melee")
	match skill_type:
		"melee":
			_execute_melee(skill)
		"projectile", "penetrate":
			_execute_projectile(skill)
		"aoe":
			_execute_aoe(skill)
		"fullscreen":
			_execute_fullscreen(skill)
		"self":
			_execute_self(skill)


func _execute_melee(skill: Dictionary) -> void:
	# 近战由 CombatComponent 在动画有效帧触发。
	pass


func apply_melee_hit(skill: Dictionary, hurt_box: Area2D) -> void:
	_apply_damage_to_target(skill, hurt_box)


func _execute_projectile(skill: Dictionary) -> void:
	var scene_path: String = skill.get("projectile_scene", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("弹道场景不存在: %s" % scene_path)
		return
	var scene: PackedScene = load(scene_path)
	var proj: Node2D = scene.instantiate()
	proj.global_position = _owner.global_position
	var facing := _get_facing()
	var dmg := _calc_damage(skill)
	var pierce := int(skill.get("max_pierce", 0))
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	if proj.has_method("setup"):
		proj.setup(facing, 300.0, dmg, pierce, buff_id, buff_chance, _owner)
	# 弹道翻转朝向
	if facing.x < 0:
		proj.scale.x = -absf(proj.scale.x)
	_owner.get_tree().current_scene.add_child(proj)


func _execute_aoe(skill: Dictionary) -> void:
	var radius: float = float(skill.get("aoe_radius", 80.0))
	var dmg := _calc_damage(skill)
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	var all_hurt_boxes := _find_all_hurt_boxes()
	for hb in all_hurt_boxes:
		if _is_friendly(hb):
			continue
		var dist: float = _owner.global_position.distance_to(hb.global_position)
		if dist <= radius:
			hb.take_hit(dmg, _owner)
			if buff_id > 0 and randf() <= buff_chance:
				_try_apply_buff(hb, buff_id)


func _execute_fullscreen(skill: Dictionary) -> void:
	var dmg := _calc_damage(skill)
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	var all_hurt_boxes := _find_all_hurt_boxes()
	for hb in all_hurt_boxes:
		if _is_friendly(hb):
			continue
		hb.take_hit(dmg, _owner)
		if buff_id > 0 and randf() <= buff_chance:
			_try_apply_buff(hb, buff_id)


func _execute_self(skill: Dictionary) -> void:
	# 对自身施加 buff
	var buff_id := int(skill.get("buff_on_self", 0))
	if buff_id > 0 and _owner.has_method("apply_buff_from_config"):
		var config = GameRegistry.buff_config.get_buff(buff_id)
		if not config.is_empty():
			_owner.apply_buff_from_config(config, _owner.get_instance_id())
	# 自身治疗
	var ratio := float(skill.get("damage_ratio", 0.0))
	if ratio < 0.0:
		# 负倍率 = 治疗
		var heal_amount: int = int(absf(ratio) * float(_owner.stats.attack)) if _owner.has_method("get") else 0
		if _owner.has_method("heal"):
			_owner.heal(heal_amount)


func _apply_damage_to_target(skill: Dictionary, hurt_box: Area2D) -> void:
	var dmg := _calc_damage(skill)
	hurt_box.take_hit(dmg, _owner)
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	if buff_id > 0 and randf() <= buff_chance:
		_try_apply_buff(hurt_box, buff_id)


func _try_apply_buff(hurt_box: Area2D, buff_id: int) -> void:
	var target = hurt_box._owner_entity if hurt_box.get("_owner_entity") else null
	if target != null and target.has_method("apply_buff_from_config"):
		var config = GameRegistry.buff_config.get_buff(buff_id)
		if not config.is_empty():
			target.apply_buff_from_config(config, _owner.get_instance_id())


func _calc_damage(skill: Dictionary) -> int:
	var ratio := float(skill.get("damage_ratio", 1.0))
	var base_atk := 1
	if _stats != null:
		base_atk = _stats.attack
	elif "character_stats" in GameRegistry:
		base_atk = GameRegistry.character_stats.attack
	return int(float(base_atk) * ratio)


func _get_facing() -> Vector2:
	var sprite_node = _owner.get_node_or_null("CharacterActionSet/AnimatedSprite2D")
	if sprite_node == null and "sprite" in _owner:
		sprite_node = _owner.sprite
	if sprite_node != null:
		# flip_h=true 表示水平翻转（面朝右），flip_h=false 表示默认（面朝左）
		return Vector2.RIGHT if sprite_node.flip_h else Vector2.LEFT
	return Vector2.RIGHT


func _find_all_hurt_boxes() -> Array[Area2D]:
	var result: Array[Area2D] = []
	var tree := _owner.get_tree()
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("hurt_box"):
		if node is Area2D:
			result.append(node)
	return result


func _is_friendly(hurt_box: Area2D) -> bool:
	var target_owner = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target_owner == null or _owner == null:
		return false
	if target_owner == _owner:
		return true
	if _owner.is_in_group("player") and target_owner.is_in_group("player"):
		return true
	if _owner.is_in_group("enemies") and target_owner.is_in_group("enemies"):
		return true
	return false
