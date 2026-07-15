extends CharacterBody2D
## 怪物主体脚本
## AI状态机: IDLE → PATROL → CHASE → ATTACK → HIT → DEAD

enum AIState { IDLE, PATROL, CHASE, ATTACK, HIT, DEAD }

const CONFIG_FILE := "character_config.json"
const TARGET_SWITCH_COOLDOWN := 0.8
const TARGET_SWITCH_GAIN := 48.0
const TARGET_LOSE_MULTIPLIER := 1.5
const FACE_TARGET_DEAD_ZONE := 8.0

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var visual_root: Node2D = $CharacterActionSet
@onready var combat: Node = $CombatComponent

var _enemy_id: int = 0
var _config: Dictionary = {}       # 来自 enemies.json
var _character_config: Dictionary = {}
var _combat_actions: Dictionary = {}
var _stats: EnemyStats = null
var _party_manager: PartyManager = null
var _target: CharacterBody2D = null
var _actor_scale := 1.0

var _ai_state: AIState = AIState.IDLE
var _spawn_position: Vector2 = Vector2.ZERO
var _patrol_target: float = 0.0
var _idle_timer: float = 0.0
var _skill_index: int = 0
var _combat_anim_playing := false
var _visual_authored_x := 0.0
var _target_switch_timer: float = 0.0

# 节点驱动 AI 距离缓存：skill_id (int) → cache (Dictionary)
var _ai_caches: Dictionary = {}
var _ai_debug_text: String = ""

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func init_from_config(enemy_id: int, party_manager: PartyManager) -> void:
	_enemy_id = enemy_id
	_party_manager = party_manager
	_config = GameRegistry.enemy_config.get_enemy(enemy_id)
	if _config.is_empty():
		push_error("怪物配置不存在: %s" % enemy_id)
		return

	_actor_scale = maxf(0.01, float(_config.get("actor_scale", 1.0)))
	_load_character_config()
	_stats = EnemyStats.new(_config)
	_load_combat_actions()
	_spawn_position = global_position
	# 排除与玩家的物理碰撞（通过 HitBox/HurtBox 交互）
	if _party_manager != null:
		for member in _party_manager.get_party_members():
			add_collision_exception_with(member)
	_apply_display_config()
	_precompile_ai_caches()
	_set_ai_state(AIState.IDLE)


func get_combat_stats() -> EnemyStats:
	return _stats


func get_combat_actions() -> Dictionary:
	return _combat_actions


func get_actor_scale() -> float:
	return _actor_scale


func _load_character_config() -> void:
	_character_config = {}
	var config_path: String = _config.get("character_config", "")
	if config_path.is_empty():
		var asset_path: String = _config.get("asset", "")
		if not asset_path.is_empty():
			config_path = asset_path.path_join(CONFIG_FILE)
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) != OK:
		push_warning("怪物角色配置解析失败: %s" % config_path)
		return
	if json.data is Dictionary:
		_character_config = json.data


func _load_combat_actions() -> void:
	_combat_actions = {}
	var asset_path: String = _config.get("asset", "")
	if asset_path.is_empty():
		return
	var config_path := asset_path.path_join("combat_actions.json")
	if not FileAccess.file_exists(config_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(config_path)) != OK:
		push_warning("攻击动作配置解析失败: %s" % config_path)
		return
	if json.data is Dictionary:
		_combat_actions = json.data.get("actions", {})


func get_enemy_name() -> String:
	return _config.get("name", "未知")


func get_ai_state_name() -> String:
	match _ai_state:
		AIState.IDLE: return "IDLE"
		AIState.PATROL: return "PATROL"
		AIState.CHASE: return "CHASE"
		AIState.ATTACK: return "ATTACK"
		AIState.HIT: return "HIT"
		AIState.DEAD: return "DEAD"
		_: return "?"


func get_current_target() -> CharacterBody2D:
	return _target if _is_valid_party_target(_target) else null


func get_current_target_name() -> String:
	var target := get_current_target()
	if target == null:
		return "无"
	if target.has_method("get_party_character_id") and GameRegistry.character_config != null:
		var character_id := int(target.get_party_character_id())
		if character_id > 0:
			return GameRegistry.character_config.get_name(character_id)
	return target.name


func get_target_distance_x() -> float:
	var target := get_current_target()
	if target == null:
		return INF
	return _edge_distance_x_to(target)


func _ready() -> void:
	add_to_group("enemies")
	var debug_overlay := CombatDebugOverlay.new()
	add_child(debug_overlay)
	debug_overlay.setup(self)
	_visual_authored_x = visual_root.position.x
	_apply_visual_facing_offset()
	# 等 CombatComponent 初始化后连接死亡信号
	call_deferred("_connect_signals")


func _connect_signals() -> void:
	if combat != null and combat.has_signal("died"):
		combat.died.connect(_on_enemy_died)


func _apply_display_config() -> void:
	var base_display_scale := float(_character_config.get("display_scale", visual_root.scale.x))
	var display_offset := _get_vector2_from_dict(_character_config.get("display_offset", {}), visual_root.position)
	visual_root.position = display_offset * _actor_scale
	visual_root.scale = Vector2.ONE * base_display_scale * _actor_scale
	_visual_authored_x = visual_root.position.x
	_apply_visual_facing_offset()

	var root_collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var body_position := _get_vector2_from_dict(
		_character_config.get("body_position", {}),
		root_collision.position if root_collision != null else Vector2.ZERO
	)
	var body_size := _get_vector2_from_dict(
		_character_config.get("body_size", {}),
		_get_rectangle_size(root_collision)
	)
	_apply_scaled_rectangle_shape(root_collision, body_position, body_size)

	var hurt_collision := get_node_or_null("HurtBox/CollisionShape2D") as CollisionShape2D
	_apply_scaled_rectangle_shape(hurt_collision, body_position, body_size)


func _get_vector2_from_dict(data, fallback: Vector2) -> Vector2:
	if data is Dictionary:
		return Vector2(
			float(data.get("x", fallback.x)),
			float(data.get("y", fallback.y))
		)
	return fallback


func _get_rectangle_size(collision_shape: CollisionShape2D) -> Vector2:
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		return (collision_shape.shape as RectangleShape2D).size
	return Vector2.ONE


func _apply_scaled_rectangle_shape(collision_shape: CollisionShape2D, base_position: Vector2, base_size: Vector2) -> void:
	if collision_shape == null:
		return
	collision_shape.position = base_position * _actor_scale
	if collision_shape.shape is RectangleShape2D:
		collision_shape.shape = collision_shape.shape.duplicate()
		var rectangle := collision_shape.shape as RectangleShape2D
		rectangle.size = Vector2(
			maxf(1.0, base_size.x * _actor_scale),
			maxf(1.0, base_size.y * _actor_scale)
		)


func _physics_process(delta: float) -> void:
	if _config.is_empty():
		return
	_target_switch_timer = maxf(0.0, _target_switch_timer - delta)
	# Keep the animation lock aligned with what is actually visible. A stale
	# true value here made enemies run/idle forever while their AI was skipped.
	if _combat_anim_playing and (sprite.animation == &"idle" or sprite.animation == &"run"):
		_combat_anim_playing = false

	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 战斗状态限制 AI
	if combat != null and "combat_state" in combat:
		if combat.combat_state == combat.CombatState.DEAD:
			velocity = Vector2.ZERO
			move_and_slide()
			return
		if combat.combat_state == combat.CombatState.HIT:
			velocity.x = move_toward(velocity.x, 0, 400 * delta)
			move_and_slide()
			return
		if _combat_anim_playing:
			velocity.x = move_toward(velocity.x, 0, 400 * delta)
			move_and_slide()
			return
	# Buff 控制效果（冰冻/麻痹/眩晕）限制移动
	if combat != null and combat.has_method("get_buff_manager"):
		var buff_manager = combat.get_buff_manager()
		if buff_manager != null and not buff_manager.can_move():
			velocity.x = move_toward(velocity.x, 0, 400 * delta)
			move_and_slide()
			return

	match _ai_state:
		AIState.IDLE:
			_update_idle(delta)
		AIState.PATROL:
			_update_patrol(delta)
		AIState.CHASE:
			_update_chase(delta)
		AIState.ATTACK:
			_update_attack(delta)

	move_and_slide()


## ---- AI 状态 ----

func _set_ai_state(new_state: AIState) -> void:
	_ai_state = new_state
	match new_state:
		AIState.IDLE:
			_idle_timer = randf_range(1.0, 3.0)
			velocity.x = 0.0
			_play_anim("idle")
		AIState.PATROL:
			_pick_patrol_target()
		AIState.CHASE:
			_play_anim("run")
		AIState.ATTACK:
			velocity.x = 0.0
			_play_anim("idle")


func _update_idle(delta: float) -> void:
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		# 检测玩家
		if _can_detect_player():
			_set_ai_state(AIState.CHASE)
		else:
			_set_ai_state(AIState.PATROL)


func _get_move_speed() -> float:
	var base := 80.0
	if _config != null:
		base = float(_config.get("move_speed", base))
	if combat != null and combat.has_method("get_buff_manager"):
		var bm = combat.get_buff_manager()
		if bm != null:
			return bm.get_modified_stat("move_speed", base)
	return base


func _update_patrol(_delta: float) -> void:
	var dir := signf(_patrol_target - global_position.x)
	if absf(global_position.x - _patrol_target) < 4.0:
		_set_ai_state(AIState.IDLE)
		return

	velocity.x = dir * _get_move_speed()
	_face_direction(dir)

	# 巡逻中检测到玩家
	if _can_detect_player():
		_set_ai_state(AIState.CHASE)


func _update_chase(_delta: float) -> void:
	_refresh_target()
	if _target == null or not is_instance_valid(_target):
		_set_ai_state(AIState.IDLE)
		return

	var dist := _distance_x_to_target()
	var detect_range: float = _config.get("detect_range", 200.0)

	# 玩家超出检测范围
	if dist > detect_range * 1.5:
		_set_ai_state(AIState.IDLE)
		return

	# 节点驱动：若任一冷却完成的伤害节点区间能命中当前距离，立即起手
	if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.IDLE:
		if _try_use_next_skill(dist):
			velocity.x = 0.0
			return

	# 若已到达最近可用最大距离，切到 ATTACK 等待冷却
	var nearest_engage := _get_nearest_engage_distance(dist)
	if nearest_engage > 0.0 and dist <= nearest_engage:
		_set_ai_state(AIState.ATTACK)
		return

	# 追击
	var dir := signf(_target.global_position.x - global_position.x)
	velocity.x = dir * _get_move_speed() * 1.2
	_face_target(_target)
	_play_anim("run")
	_ai_debug_text = "追击至 %.0f（当前 %.0f）" % [nearest_engage, dist]


func _update_attack(_delta: float) -> void:
	_refresh_target()
	if _target == null or not is_instance_valid(_target):
		_set_ai_state(AIState.IDLE)
		return

	var dist := _distance_x_to_target()
	var detect_range: float = _config.get("detect_range", 200.0)

	# 玩家跑远了
	if dist > detect_range:
		_set_ai_state(AIState.IDLE)
		return

	# 持续面向玩家
	_face_target(_target)

	# 尝试释放技能（只在战斗状态空闲时）
	if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.IDLE:
		if _try_use_next_skill(dist):
			velocity.x = 0.0
			return

	# 若目标太近且只有设了最小距离的远程节点可用：短距离后撤
	var retreat_target := _get_retreat_distance(dist)
	if retreat_target > 0.0 and dist < retreat_target:
		var dir := -signf(_target.global_position.x - global_position.x)
		velocity.x = dir * _get_move_speed() * 0.8
		_ai_debug_text = "后撤至 %.0f（当前 %.0f）" % [retreat_target, dist]
		return

	# 若目标超出所有可用最大距离：回追
	var max_engage := _get_max_engage_distance()
	if max_engage > 0.0 and dist > max_engage * 1.25:
		_set_ai_state(AIState.CHASE)
		return

	velocity.x = 0.0
	_ai_debug_text = "等待冷却（当前 %.0f）" % dist


## ---- 技能选择（节点驱动） ----

func _try_use_next_skill(distance_x: float) -> bool:
	if combat == null:
		return false

	var skills := _get_configured_skill_ids()
	var weights := _get_configured_skill_weights(skills)
	if skills.is_empty():
		return false

	var skill_id := _pick_weighted_skill(skills, weights, distance_x)
	if skill_id <= 0:
		return false

	if combat.has_method("try_use_skill"):
		return combat.try_use_skill(skill_id)
	return false


func _pick_weighted_skill(skills: Array, weights: Array, distance_x: float) -> int:
	# 过滤：冷却完成 + 任一伤害节点区间能命中当前距离
	var available_ids: Array[int] = []
	var available_weights: Array[float] = []
	var cooldowns: Dictionary = combat.get_cooldowns_dict() if combat != null and combat.has_method("get_cooldowns_dict") else {}
	for i in range(skills.size()):
		var sid := int(skills[i])
		if float(cooldowns.get(sid, 0.0)) > 0.0:
			continue
		var cache := _get_ai_cache(sid)
		if cache.is_empty():
			continue
		var castable := AIRangeCompiler.get_castable_entries(cache, distance_x)
		if castable.is_empty():
			continue
		available_ids.append(sid)
		available_weights.append(float(weights[i]) if weights.size() == skills.size() else 1.0)

	if available_ids.is_empty():
		return 0

	var total := 0.0
	for w in available_weights:
		total += w
	var roll := randf() * total
	var accum := 0.0
	for i in range(available_ids.size()):
		accum += available_weights[i]
		if roll <= accum:
			return available_ids[i]
	return available_ids[0]


## 返回当前距离下最近的可起手最大距离（用于追击目标）。
func _get_nearest_engage_distance(distance_x: float) -> float:
	var best := 0.0
	for sid in _get_configured_skill_ids():
		if combat != null and combat._cooldowns.get(sid, 0.0) > 0.0:
			continue
		var cache := _get_ai_cache(sid)
		if cache.is_empty():
			continue
		for entry_value in cache.get("entries", []):
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var max_d := float(entry.get("max_edge_distance", 0.0))
			if max_d < 99990.0 and max_d >= distance_x and (best == 0.0 or max_d < best):
				best = max_d
	return best


## 返回所有冷却中技能的最大可起手距离（用于判断是否需要回追）。
func _get_max_engage_distance() -> float:
	var best := 0.0
	for sid in _get_configured_skill_ids():
		var cache := _get_ai_cache(sid)
		if cache.is_empty():
			continue
		var max_d := AIRangeCompiler.get_max_engage_distance(cache)
		if max_d > best:
			best = max_d
	return best


## 若目标过近且只有设了最小距离的远程节点可用，返回需后撤到的距离。
func _get_retreat_distance(distance_x: float) -> float:
	var best := 0.0
	for sid in _get_configured_skill_ids():
		if combat != null and combat._cooldowns.get(sid, 0.0) > 0.0:
			continue
		var cache := _get_ai_cache(sid)
		if cache.is_empty():
			continue
		var min_retreat := AIRangeCompiler.get_min_retreat_distance(cache)
		if min_retreat != INF and distance_x < min_retreat and min_retreat > best:
			best = min_retreat
	return best


## 获取技能的 ai_range_cache；为空时惰性编译。
func _get_ai_cache(skill_id: int) -> Dictionary:
	if _ai_caches.has(skill_id):
		return _ai_caches[skill_id]
	var cache: Dictionary = GameRegistry.skill_config.get_ai_range_cache(skill_id)
	if cache.is_empty() or cache.get("entries", []).is_empty():
		cache = _compile_ai_cache(skill_id)
	_ai_caches[skill_id] = cache
	return cache


## 运行时惰性编译：用自身资源（asset 路径 + combat_actions + actor_scale）计算缓存。
func _compile_ai_cache(skill_id: int) -> Dictionary:
	var asset_path: String = _config.get("asset", "")
	if asset_path.is_empty():
		return {}
	return AIRangeCompiler.compile(skill_id, asset_path)


## 初始化时预编译所有已配置技能的 ai_range_cache。
func _precompile_ai_caches() -> void:
	for sid in _get_configured_skill_ids():
		_ai_caches[sid] = _get_ai_cache(sid)


## 供 F3 调试面板读取。
func get_ai_debug_text() -> String:
	var target := get_current_target()
	if target == null:
		return "AI: 无目标"
	var dist := _edge_distance_x_to(target)
	var text := "AI: %s\n目标边缘距离: %.0f\n%s" % [get_ai_state_name(), dist, _ai_debug_text]
	text += "\n可用节点:"
	var cooldowns: Dictionary = {}
	if combat != null and combat.has_method("get_cooldowns_dict"):
		cooldowns = combat.get_cooldowns_dict()
	for sid in _get_configured_skill_ids():
		var cache := _get_ai_cache(sid)
		if cache.is_empty():
			continue
		var on_cd := float(cooldowns.get(sid, 0.0)) > 0.0
		var skill: Dictionary = GameRegistry.skill_config.get_skill(sid)
		var sname := String(skill.get("name", str(sid)))
		for entry_value in cache.get("entries", []):
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var min_d := float(entry.get("min_edge_distance", 0.0))
			var max_d := float(entry.get("max_edge_distance", 0.0))
			var kind := String(entry.get("kind", ""))
			var status := "冷却中" if on_cd else ("可释放" if dist >= min_d and dist <= max_d else ("太远" if dist > max_d else "太近"))
			text += "\n  · %s/%s: %.0f~%.0f %s" % [sname, kind, min_d, max_d, status]
	return text


## ---- 辅助 ----

func _can_detect_player() -> bool:
	_refresh_target()
	if _target == null or not is_instance_valid(_target):
		return false
	var dist := _distance_x_to_target()
	return dist <= _config.get("detect_range", 200.0)


func _distance_x_to_target() -> float:
	if _target == null or not is_instance_valid(_target):
		return INF
	return _edge_distance_x_to(_target)


func _edge_distance_x_to(target: Node2D) -> float:
	if target == null or not is_instance_valid(target):
		return INF
	var center_distance := absf(target.global_position.x - global_position.x)
	return maxf(0.0, center_distance - _combat_half_width(self) - _combat_half_width(target))


func _combat_half_width(node: Node) -> float:
	if node == null:
		return 0.0
	var shape_node := node.get_node_or_null("HurtBox/CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rectangle := shape_node.shape as RectangleShape2D
		return absf(rectangle.size.x * shape_node.global_scale.x) * 0.5
	return 0.0


func _refresh_target() -> void:
	var detect_range: float = _config.get("detect_range", 200.0)
	var nearest := _find_nearest_party_member()
	if _is_valid_party_target(_target):
		var current_dist := _edge_distance_x_to(_target)
		if current_dist <= detect_range * TARGET_LOSE_MULTIPLIER:
			if nearest == null or nearest == _target:
				return
			var nearest_dist := _edge_distance_x_to(nearest)
			if nearest_dist <= 0.0 and current_dist > 0.0:
				_target = nearest
				_target_switch_timer = TARGET_SWITCH_COOLDOWN
				return
			if _target_switch_timer > 0.0:
				return
			if nearest_dist + TARGET_SWITCH_GAIN < current_dist:
				_target = nearest
				_target_switch_timer = TARGET_SWITCH_COOLDOWN
			return
	_target = nearest
	_target_switch_timer = TARGET_SWITCH_COOLDOWN


func _find_nearest_party_member() -> CharacterBody2D:
	if _party_manager == null or not is_instance_valid(_party_manager):
		return null
	var best: CharacterBody2D = null
	var best_dist := INF
	for member in _party_manager.get_alive_party_members():
		if not is_instance_valid(member):
			continue
		var dist := _edge_distance_x_to(member)
		if dist < best_dist:
			best_dist = dist
			best = member
	return best


func _is_valid_party_target(target: CharacterBody2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var combat_node: Node = target.get_node_or_null("CombatComponent")
	if combat_node != null and "combat_state" in combat_node and combat_node.combat_state == combat_node.CombatState.DEAD:
		return false
	return true


func _get_configured_skill_ids() -> Array[int]:
	var result: Array[int] = []
	var normal_skill := int(_config.get("normal_skill", 0))
	if normal_skill > 0:
		result.append(normal_skill)
	for skill_value in _config.get("skills", []):
		var skill_id := int(skill_value)
		if skill_id > 0 and not result.has(skill_id):
			result.append(skill_id)
	return result


func _get_configured_skill_weights(skill_ids: Array[int]) -> Array[float]:
	var result: Array[float] = []
	var raw_extra_skills: Array = _config.get("skills", [])
	var raw_weights: Array = _config.get("skill_weights", [])
	for skill_id in skill_ids:
		if skill_id == int(_config.get("normal_skill", 0)):
			result.append(float(_config.get("normal_skill_weight", 100.0)))
			continue
		var index := raw_extra_skills.find(skill_id)
		result.append(float(raw_weights[index]) if index >= 0 and index < raw_weights.size() else 100.0)
	return result


func _pick_patrol_target() -> void:
	var patrol_range: float = _config.get("patrol_range", 80.0)
	_patrol_target = _spawn_position.x + randf_range(-patrol_range, patrol_range)
	_play_anim("run")
	_face_direction(signf(_patrol_target - global_position.x))


func _face_direction(dir: float) -> void:
	if dir == 0.0:
		return
	var new_flip := dir > 0.0
	if sprite.flip_h != new_flip:
		sprite.flip_h = new_flip
		_apply_visual_facing_offset()


func _face_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var dx: float = target.global_position.x - global_position.x
	if absf(dx) <= FACE_TARGET_DEAD_ZONE:
		return
	_face_direction(signf(dx))


func _apply_visual_facing_offset() -> void:
	visual_root.position.x = -_visual_authored_x if sprite.flip_h else _visual_authored_x


func _play_anim(anim_name: String) -> void:
	if _combat_anim_playing:
		return
	# 非循环动画未播完时不切换
	if not sprite.sprite_frames.get_animation_loop(sprite.animation) and sprite.is_playing():
		return
	if sprite.animation != anim_name:
		sprite.play(anim_name)


## 播放战斗动画 (由 CombatComponent 调用)
func play_combat_animation(anim_name: String) -> void:
	var target_animation := anim_name
	if not sprite.sprite_frames.has_animation(target_animation):
		if target_animation == "hit" and sprite.sprite_frames.has_animation("hurt"):
			target_animation = "hurt"
	if sprite.sprite_frames.has_animation(target_animation):
		_combat_anim_playing = true
		sprite.animation = target_animation
		sprite.stop()
		sprite.frame = 0
		sprite.play()
		if not sprite.animation_finished.is_connected(_on_combat_anim_finished):
			sprite.animation_finished.connect(_on_combat_anim_finished)
	else:
		_combat_anim_playing = true
		get_tree().create_timer(0.3).timeout.connect(_end_combat_anim)


func _on_combat_anim_finished() -> void:
	_end_combat_anim()


func _end_combat_anim() -> void:
	_combat_anim_playing = false
	if sprite.animation_finished.is_connected(_on_combat_anim_finished):
		sprite.animation_finished.disconnect(_on_combat_anim_finished)

	# 死亡后不再恢复动画
	if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.DEAD:
		_hold_animation_last_frame()
		return

	# 攻击/受击结束后恢复移动动画，避免停在末帧
	var target_animation := "idle"
	if _ai_state == AIState.CHASE or _ai_state == AIState.PATROL:
		target_animation = "run"
	if _ai_state == AIState.ATTACK:
		target_animation = "idle"
	if sprite.animation != target_animation:
		sprite.play(target_animation)


## 受伤 (由 HurtBox 调用)
func _hold_animation_last_frame() -> void:
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.pause()
	sprite.frame = maxi(0, frame_count - 1)


func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true) -> void:
	if play_hit_reaction:
		velocity.x = 0.0
	if combat != null and combat.has_method("take_damage"):
		combat.take_damage(amount, source, play_hit_reaction)


func heal(amount: int) -> void:
	if combat != null and combat.has_method("heal"):
		combat.heal(amount)


## 施加 Buff
func apply_buff_from_config(buff_cfg: Dictionary, source: int = 0) -> void:
	if combat != null and combat.has_method("apply_buff_from_config"):
		combat.apply_buff_from_config(buff_cfg, source)


## 死亡回调
func _on_enemy_died() -> void:
	_set_ai_state(AIState.DEAD)
	velocity = Vector2.ZERO
	if GameRegistry.roster_data != null:
		GameRegistry.roster_data.add_exp_to_lineup(int(_config.get("exp", 0)))
	# 死亡动画后延迟移除
	get_tree().create_timer(1.0).timeout.connect(queue_free)
