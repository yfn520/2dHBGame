class_name SkillExecutor
## 技能执行器
## 根据技能类型(melee/projectile/penetrate/aoe/fullscreen/self)执行不同的伤害逻辑

var _owner: Node
var _stats  # CharacterStats 或 EnemyStats


func _init(owner: Node, stats = null) -> void:
	_owner = owner
	_stats = stats


func execute(skill: Dictionary, origin_position: Variant = null, node_context: Dictionary = {}) -> Array[Area2D]:
	var skill_type: String = skill.get("type", "melee")
	match skill_type:
		"melee":
			return _execute_melee(skill)
		"projectile", "penetrate":
			return _execute_projectile(skill, origin_position, node_context)
		"aoe":
			return _execute_aoe(skill)
		"fullscreen":
			return _execute_fullscreen(skill)
		"self":
			_execute_self(skill)
	return []


func _execute_melee(_skill: Dictionary) -> Array[Area2D]:
	# 近战由 CombatComponent 在动画有效帧触发。
	return []


func apply_melee_hit(skill: Dictionary, hurt_box: Area2D) -> void:
	_apply_damage_to_target(skill, hurt_box)


func _execute_projectile(skill: Dictionary, origin_position: Variant = null, node_context: Dictionary = {}) -> Array[Area2D]:
	var scene_path: String = skill.get("projectile_scene", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("弹道场景不存在: %s" % scene_path)
		return []
	if String(node_context.get("projectile_mode", "single")) == "area_rain":
		_spawn_area_rain(skill, origin_position, node_context)
		return []
	var scene: PackedScene = load(scene_path)
	var proj: Node2D = scene.instantiate()
	var facing := _get_facing()
	if origin_position is Vector2:
		proj.global_position = origin_position
	else:
		var spawn_offset := float(skill.get("projectile_spawn_offset", 32.0))
		proj.global_position = _owner.global_position + facing * spawn_offset
	var dmg := _calc_damage(skill)
	var pierce := int(skill.get("max_pierce", 0))
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	var projectile_speed := float(skill.get("projectile_speed", 300.0))
	var projectile_lifetime := float(skill.get("projectile_lifetime", 5.0))
	if proj.has_method("setup"):
		proj.setup(facing, projectile_speed, dmg, pierce, buff_id, buff_chance, _owner, projectile_lifetime)
	# 弹道翻转朝向
	if facing.x < 0:
		proj.scale.x = -absf(proj.scale.x)
	_owner.get_tree().current_scene.add_child(proj)
	return []


func _spawn_area_rain(skill: Dictionary, origin_position: Variant, node_context: Dictionary) -> void:
	var scene_path := String(skill.get("projectile_scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("区域弹道场景不存在: %s" % scene_path)
		return
	var origin: Vector2 = _owner.global_position
	if origin_position is Vector2:
		origin = origin_position
	var center := _find_area_rain_center(skill, node_context)
	var count := maxi(1, int(node_context.get("projectile_count", 12)))
	var interval := maxf(0.0, float(node_context.get("projectile_interval", 0.05)))
	for index in range(count):
		var timer := _owner.get_tree().create_timer(interval * float(index))
		timer.timeout.connect(_spawn_area_rain_projectile.bind(skill.duplicate(true), origin, center, node_context.duplicate(true)))


func _spawn_area_rain_projectile(skill: Dictionary, origin: Vector2, center: Vector2, node_context: Dictionary) -> void:
	if not is_instance_valid(_owner):
		return
	var scene_path := String(skill.get("projectile_scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var scene: PackedScene = load(scene_path)
	var proj: Node2D = scene.instantiate()
	var width := maxf(1.0, float(node_context.get("area_width", 240.0)))
	var height := maxf(1.0, float(node_context.get("area_height", 80.0)))
	var landing := center + Vector2(randf_range(-width * 0.5, width * 0.5), randf_range(-height * 0.5, height * 0.5))
	var flight_time := maxf(0.1, float(node_context.get("flight_time", 0.9)))
	var gravity_value := float(node_context.get("gravity", 900.0))
	var initial_velocity := (landing - origin) / flight_time - Vector2(0.0, 0.5 * gravity_value * flight_time)
	proj.global_position = origin
	var dmg := _calc_damage(skill)
	var pierce := int(skill.get("max_pierce", 0))
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	var lifetime := float(skill.get("projectile_lifetime", 5.0))
	if proj.has_method("setup_ballistic"):
		proj.setup_ballistic(initial_velocity, gravity_value, dmg, pierce, buff_id, buff_chance, _owner, lifetime)
	elif proj.has_method("setup"):
		proj.setup(initial_velocity.normalized(), initial_velocity.length(), dmg, pierce, buff_id, buff_chance, _owner, lifetime)
	if initial_velocity.x < 0.0:
		proj.scale.x = -absf(proj.scale.x)
	_owner.get_tree().current_scene.add_child(proj)


func _find_area_rain_center(skill: Dictionary, node_context: Dictionary) -> Vector2:
	var search_range: float = maxf(1.0, float(node_context.get("target_search_range", skill.get("range", 500.0))))
	var best: Vector2 = _owner.global_position + _get_facing() * search_range
	var best_distance: float = INF
	for hurt_box in _find_all_hurt_boxes():
		if _is_friendly(hurt_box):
			continue
		var distance: float = _owner.global_position.distance_to(hurt_box.global_position)
		if distance <= search_range and distance < best_distance:
			best_distance = distance
			best = hurt_box.global_position
	return best


func _execute_aoe(skill: Dictionary) -> Array[Area2D]:
	var radius: float = float(skill.get("aoe_radius", 80.0))
	var dmg := _calc_damage(skill)
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	var all_hurt_boxes := _find_all_hurt_boxes()
	var hit_targets: Array[Area2D] = []
	for hb in all_hurt_boxes:
		if _is_friendly(hb):
			continue
		var dist: float = _owner.global_position.distance_to(hb.global_position)
		if dist <= radius:
			hb.take_hit(dmg, _owner)
			hit_targets.append(hb)
			if buff_id > 0 and randf() <= buff_chance:
				_try_apply_buff(hb, buff_id)
	return hit_targets


func _execute_fullscreen(skill: Dictionary) -> Array[Area2D]:
	var dmg := _calc_damage(skill)
	var buff_id := int(skill.get("buff_on_hit", 0))
	var buff_chance := float(skill.get("buff_chance", 0.0))
	var all_hurt_boxes := _find_all_hurt_boxes()
	var hit_targets: Array[Area2D] = []
	for hb in all_hurt_boxes:
		if _is_friendly(hb):
			continue
		hb.take_hit(dmg, _owner)
		hit_targets.append(hb)
		if buff_id > 0 and randf() <= buff_chance:
			_try_apply_buff(hb, buff_id)
	return hit_targets


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
