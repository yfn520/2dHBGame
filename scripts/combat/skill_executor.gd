class_name SkillExecutor

## Executes only action nodes. Skills themselves no longer own combat type,
## damage, projectile, range, or buff fields.

var _owner: Node
var _stats


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
		var delta := hurt_box.global_position - origin
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


func apply_damage_node(node: Dictionary, hurt_box: Area2D) -> void:
	if hurt_box == null or not is_instance_valid(hurt_box):
		return
	var damage := calculate_damage(float(node.get("damage_ratio", 1.0)))
	if hurt_box.has_method("take_hit"):
		hurt_box.take_hit(damage, _owner)
	_apply_optional_buff(node, hurt_box)


func apply_target_buff(node: Dictionary, hurt_box: Area2D) -> void:
	if hurt_box == null or not is_instance_valid(hurt_box):
		return
	var chance := float(node.get("chance", node.get("buff_chance", 1.0)))
	if randf() > chance:
		return
	var buff_id := int(node.get("buff_id", 0))
	if buff_id <= 0:
		return
	var target: Node = hurt_box._owner_entity if "_owner_entity" in hurt_box else null
	if target != null and target.has_method("apply_buff_from_config"):
		var config: Dictionary = GameRegistry.buff_config.get_buff(buff_id)
		if not config.is_empty():
			target.apply_buff_from_config(config, _owner.get_instance_id() if _owner != null else 0)


func apply_self_buff(node: Dictionary) -> void:
	var buff_id := int(node.get("buff_id", 0))
	if buff_id <= 0 or _owner == null or not _owner.has_method("apply_buff_from_config"):
		return
	var config: Dictionary = GameRegistry.buff_config.get_buff(buff_id)
	if not config.is_empty():
		_owner.apply_buff_from_config(config, _owner.get_instance_id())


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
	var attack := 1.0
	if _stats != null and "attack" in _stats:
		attack = float(_stats.attack)
	return maxi(1, roundi(attack * ratio))


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
	_setup_projectile(projectile, node, direction, speed, context, result_key)


func _spawn_ballistic(node: Dictionary, origin: Vector2, velocity: Vector2, gravity: float, context: SkillCastContext, result_key: String) -> void:
	var projectile := _instantiate_projectile(node)
	if projectile == null:
		return
	projectile.global_position = origin
	var damage := calculate_damage(float(node.get("damage_ratio", 1.0)))
	var pierce := int(node.get("max_pierce", 0))
	var buff_id := int(node.get("buff_id", 0))
	var chance := float(node.get("buff_chance", 0.0))
	var lifetime := float(node.get("lifetime", 5.0))
	var rotate_visual := bool(node.get("rotate_to_velocity", true))
	if projectile.has_method("setup_ballistic"):
		projectile.setup_ballistic(velocity, gravity, damage, pierce, buff_id, chance, _owner, lifetime, rotate_visual)
	_connect_projectile_result(projectile, context, result_key)
	_add_projectile_to_scene(projectile)


func _instantiate_projectile(node: Dictionary) -> Node2D:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("弹道节点缺少可加载的 scene: %s" % scene_path)
		return null
	var packed := load(scene_path) as PackedScene
	return packed.instantiate() as Node2D if packed != null else null


func _setup_projectile(projectile: Node2D, node: Dictionary, direction: Vector2, speed: float, context: SkillCastContext, result_key: String) -> void:
	var damage := calculate_damage(float(node.get("damage_ratio", 1.0)))
	var pierce := int(node.get("max_pierce", 0))
	var buff_id := int(node.get("buff_id", 0))
	var chance := float(node.get("buff_chance", 0.0))
	var lifetime := float(node.get("lifetime", 5.0))
	var rotate_visual := bool(node.get("rotate_to_velocity", true))
	if projectile.has_method("setup"):
		projectile.setup(direction, speed, damage, pierce, buff_id, chance, _owner, lifetime, rotate_visual)
	_connect_projectile_result(projectile, context, result_key)
	_add_projectile_to_scene(projectile)


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
		if hurt_box.global_position.distance_to(origin) <= radius:
			result.append(hurt_box)
	return result


func _apply_optional_buff(node: Dictionary, hurt_box: Area2D) -> void:
	var buff_id := int(node.get("buff_id", 0))
	if buff_id <= 0 or randf() > float(node.get("buff_chance", 0.0)):
		return
	apply_target_buff({"buff_id": buff_id, "chance": 1.0}, hurt_box)


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
