extends CharacterBody2D
## 怪物主体脚本
## AI状态机: IDLE → PATROL → CHASE → ATTACK → HIT → DEAD

enum AIState { IDLE, PATROL, CHASE, ATTACK, HIT, DEAD }

const CONFIG_FILE := "character_config.json"

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var combat: Node = $CombatComponent

var _enemy_id: int = 0
var _config: Dictionary = {}       # 来自 enemies.json
var _stats: EnemyStats = null
var _player: CharacterBody2D = null

var _ai_state: AIState = AIState.IDLE
var _spawn_position: Vector2 = Vector2.ZERO
var _patrol_target: float = 0.0
var _idle_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _skill_index: int = 0
var _combat_anim_playing := false

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func init_from_config(enemy_id: int, player_ref: CharacterBody2D) -> void:
	_enemy_id = enemy_id
	_player = player_ref
	_config = GameRegistry.enemy_config.get_enemy(enemy_id)
	if _config.is_empty():
		push_error("怪物配置不存在: %s" % enemy_id)
		return

	_stats = EnemyStats.new(_config)
	_spawn_position = global_position
	# 排除与玩家的物理碰撞（通过 HitBox/HurtBox 交互）
	if _player != null:
		add_collision_exception_with(_player)
	_apply_display_config()
	_set_ai_state(AIState.IDLE)


func get_combat_stats() -> EnemyStats:
	return _stats


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
	# 等 CombatComponent 初始化后连接死亡信号
	call_deferred("_connect_signals")


func _connect_signals() -> void:
	if combat != null and combat.has_signal("died"):
		combat.died.connect(_on_enemy_died)


func _apply_display_config() -> void:
	var asset_path: String = _config.get("asset", "")
	var cfg_path := asset_path.path_join(CONFIG_FILE)
	if not FileAccess.file_exists(cfg_path):
		push_warning("怪物 character_config 不存在: %s" % cfg_path)
		return

	var text := FileAccess.get_file_as_string(cfg_path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return

	var cfg: Dictionary = json.data

	# 加载 SpriteFrames
	var sf_path: String = cfg.get("spriteframes", "")
	if not sf_path.is_empty() and ResourceLoader.exists(sf_path):
		var sf = load(sf_path)
		if sf != null:
			sprite.sprite_frames = sf
			sprite.play("idle")

	# 应用显示缩放和偏移
	var s: float = float(cfg.get("display_scale", 1.0))
	var offset: Dictionary = cfg.get("display_offset", {})
	var oy: float = float(offset.get("y", 0))
	var char_set := $CharacterActionSet as Node2D
	char_set.scale = Vector2(s, s)
	char_set.position = Vector2(0, oy)


func _physics_process(delta: float) -> void:
	if _config.is_empty():
		return

	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 攻击冷却
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

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

	var dist := global_position.distance_to(_player.global_position)
	var detect_range: float = _config.get("detect_range", 200.0)
	var attack_range: float = _config.get("attack_range", 40.0)

	# 玩家超出检测范围
	if dist > detect_range * 1.5:
		_set_ai_state(AIState.IDLE)
		return

	# 进入攻击范围
	if dist <= attack_range:
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

	var dist := global_position.distance_to(_player.global_position)
	var attack_range: float = _config.get("attack_range", 40.0)
	var detect_range: float = _config.get("detect_range", 200.0)

	# 玩家跑远了
	if dist > detect_range:
		_set_ai_state(AIState.IDLE)
		return

	# 玩家跑出攻击范围
	if dist > attack_range * 1.5:
		_set_ai_state(AIState.CHASE)
		return

	# 持续面向玩家
	var dir := signf(_player.global_position.x - global_position.x)
	_face_direction(dir)

	# 尝试释放技能
	if _attack_cooldown_timer <= 0.0:
		_try_use_next_skill()


## ---- 技能选择 ----

func _try_use_next_skill() -> void:
	if combat == null:
		return

	var skills: Array = _config.get("skills", [])
	var weights: Array = _config.get("skill_weights", [])
	if skills.is_empty():
		return

	# 加权随机选择技能
	var skill_id := _pick_weighted_skill(skills, weights)
	if skill_id <= 0:
		return

	# 尝试释放（CombatComponent 会处理冷却和状态）
	if combat.has_method("try_use_skill"):
		if combat.try_use_skill(skill_id):
			var skill_data = GameRegistry.skill_config.get_skill(skill_id)
			var cd: float = float(skill_data.get("cooldown", 1.0))
			_attack_cooldown_timer = cd + randf_range(0.2, 0.8)


func _pick_weighted_skill(skills: Array, weights: Array) -> int:
	if weights.is_empty() or weights.size() != skills.size():
		# 无权重，轮转
		_skill_index = (_skill_index + 1) % skills.size()
		return int(skills[_skill_index])

	# 先过滤掉冷却中的技能
	var available_ids: Array[int] = []
	var available_weights: Array[float] = []
	for i in range(skills.size()):
		var sid := int(skills[i])
		if combat._cooldowns.get(sid, 0.0) > 0.0:
			continue
		available_ids.append(sid)
		available_weights.append(float(weights[i]))

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


## ---- 辅助 ----

func _can_detect_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var dist := global_position.distance_to(_player.global_position)
	return dist <= _config.get("detect_range", 200.0)


func _pick_patrol_target() -> void:
	var patrol_range: float = _config.get("patrol_range", 80.0)
	_patrol_target = _spawn_position.x + randf_range(-patrol_range, patrol_range)
	_play_anim("run")
	_face_direction(signf(_patrol_target - global_position.x))


func _face_direction(dir: float) -> void:
	if dir == 0.0:
		return
	sprite.flip_h = dir > 0.0


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
		sprite.stop()
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
func take_damage(amount: int, source: Node = null) -> void:
	if combat != null and combat.has_method("take_damage"):
		combat.take_damage(amount, source)


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
