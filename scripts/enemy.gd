extends CharacterBody2D
## 怪物主体脚本
## AI状态机: IDLE → PATROL → CHASE → ATTACK → HIT → DEAD

enum AIState { IDLE, PATROL, CHASE, ATTACK, HIT, DEAD }

const CONFIG_FILE := "character_config.json"

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var visual_root: Node2D = $CharacterActionSet
@onready var combat: Node = $CombatComponent

var _enemy_id: int = 0
var _config: Dictionary = {}       # 来自 enemies.json
var _combat_actions: Dictionary = {}
var _stats: EnemyStats = null
var _player: CharacterBody2D = null

var _ai_state: AIState = AIState.IDLE
var _spawn_position: Vector2 = Vector2.ZERO
var _patrol_target: float = 0.0
var _idle_timer: float = 0.0
var _skill_index: int = 0
var _combat_anim_playing := false
var _visual_authored_x := 0.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func init_from_config(enemy_id: int, player_ref: CharacterBody2D) -> void:
	_enemy_id = enemy_id
	_player = player_ref
	_config = GameRegistry.enemy_config.get_enemy(enemy_id)
	if _config.is_empty():
		push_error("怪物配置不存在: %s" % enemy_id)
		return

	_stats = EnemyStats.new(_config)
	_load_combat_actions()
	_spawn_position = global_position
	# 排除与玩家的物理碰撞（通过 HitBox/HurtBox 交互）
	if _player != null:
		add_collision_exception_with(_player)
	_apply_display_config()
	_set_ai_state(AIState.IDLE)


func get_combat_stats() -> EnemyStats:
	return _stats


func get_combat_actions() -> Dictionary:
	return _combat_actions


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
	# 模板场景已包含 sprite，这里只从 config 读取 display_scale/display_offset
	# 如果需要自动调整 CharacterActionSet 的位置/缩放，取消下面注释
	# 否则由你在编辑器里手动调整
	pass


func _physics_process(delta: float) -> void:
	if _config.is_empty():
		return

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


func _update_patrol(_delta: float) -> void:
	var dir := signf(_patrol_target - global_position.x)
	if absf(global_position.x - _patrol_target) < 4.0:
		_set_ai_state(AIState.IDLE)
		return

	velocity.x = dir * _config.get("move_speed", 80.0)
	_face_direction(dir)

	# 巡逻中检测到玩家
	if _can_detect_player():
		_set_ai_state(AIState.CHASE)


func _update_chase(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_set_ai_state(AIState.IDLE)
		return

	var dist := _distance_x_to_player()
	var detect_range: float = _config.get("detect_range", 200.0)
	# attack_range is the preferred stopping distance, not the damage radius.
	var preferred_range: float = _config.get("attack_range", 40.0)

	# 玩家超出检测范围
	if dist > detect_range * 1.5:
		_set_ai_state(AIState.IDLE)
		return

	# A ready ranged/dash skill may interrupt pursuit once. After its animation
	# ends, this state keeps closing toward preferred_range while it is on CD.
	if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.IDLE:
		if _try_use_next_skill(dist, preferred_range):
			velocity.x = 0.0
			return

	# Only stop when the preferred distance is reached and at least one configured
	# skill can actually be used from here. This prevents bad range data from
	# leaving an enemy idle just outside all of its attacks.
	if dist <= preferred_range and _has_skill_for_distance(dist, preferred_range):
		_set_ai_state(AIState.ATTACK)
		return

	# 追击
	var dir := signf(_player.global_position.x - global_position.x)
	velocity.x = dir * _config.get("move_speed", 80.0) * 1.2
	_face_direction(dir)
	_play_anim("run")


func _update_attack(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_set_ai_state(AIState.IDLE)
		return

	var dist := _distance_x_to_player()
	var preferred_range: float = _config.get("attack_range", 40.0)
	var detect_range: float = _config.get("detect_range", 200.0)

	# 玩家跑远了
	if dist > detect_range:
		_set_ai_state(AIState.IDLE)
		return

	# 玩家跑出攻击范围
	if dist > preferred_range * 1.25:
		_set_ai_state(AIState.CHASE)
		return

	# 持续面向玩家
	var dir := signf(_player.global_position.x - global_position.x)
	_face_direction(dir)

	# 尝试释放技能（只在战斗状态空闲时）
	if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.IDLE:
		_try_use_next_skill(dist, preferred_range)


## ---- 技能选择 ----

func _try_use_next_skill(distance_x: float, preferred_range: float) -> bool:
	if combat == null:
		return false

	var skills: Array = _config.get("skills", [])
	var weights: Array = _config.get("skill_weights", [])
	if skills.is_empty():
		return false

	# 加权随机选择技能
	var skill_id := _pick_weighted_skill(skills, weights, distance_x, preferred_range)
	if skill_id <= 0:
		return false

	# 尝试释放（CombatComponent 会处理冷却和状态）
	if combat.has_method("try_use_skill"):
		return combat.try_use_skill(skill_id)
	return false


func _pick_weighted_skill(skills: Array, weights: Array, distance_x: float, preferred_range: float) -> int:
	# Filter by cooldown and each skill's usable X-axis range, then keep weighted randomness.
	var available_ids: Array[int] = []
	var available_weights: Array[float] = []
	for i in range(skills.size()):
		var sid := int(skills[i])
		if combat._cooldowns.get(sid, 0.0) > 0.0:
			continue
		var skill: Dictionary = GameRegistry.skill_config.get_skill(sid)
		if skill.is_empty():
			continue
		var usable_range := _get_skill_usable_range(skill, preferred_range)
		if distance_x > usable_range:
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


func _has_skill_for_distance(distance_x: float, preferred_range: float) -> bool:
	var skills: Array = _config.get("skills", [])
	for raw_skill_id in skills:
		var skill: Dictionary = GameRegistry.skill_config.get_skill(int(raw_skill_id))
		if not skill.is_empty() and distance_x <= _get_skill_usable_range(skill, preferred_range):
			return true
	return false


func _get_skill_usable_range(skill: Dictionary, preferred_range: float) -> float:
	var usable_range := float(skill.get("range", 0.0))
	return preferred_range if usable_range <= 0.0 else usable_range


## ---- 辅助 ----

func _can_detect_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var dist := _distance_x_to_player()
	return dist <= _config.get("detect_range", 200.0)


func _distance_x_to_player() -> float:
	if _player == null or not is_instance_valid(_player):
		return INF
	return absf(_player.global_position.x - global_position.x)


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
		sprite.play(target_animation)
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


## 施加 Buff
func apply_buff_from_config(buff_cfg: Dictionary, source: int = 0) -> void:
	if combat != null and combat.has_method("apply_buff_from_config"):
		combat.apply_buff_from_config(buff_cfg, source)


## 死亡回调
func _on_enemy_died() -> void:
	_set_ai_state(AIState.DEAD)
	velocity = Vector2.ZERO
	# 死亡动画后延迟移除
	get_tree().create_timer(1.0).timeout.connect(queue_free)
