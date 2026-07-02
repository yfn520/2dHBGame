extends Node
## 战斗组件
## 挂载到角色上，管理攻击、技能释放、受伤、Buff
## 所有战斗操作通过此组件，便于后续替换为网络请求

signal hp_changed(current: int, max_hp: int)
signal died()
signal attack_started(skill_id: int)
signal took_damage(amount: int, source: Node)

# 战斗状态
enum CombatState { IDLE, ATTACKING, SKILL, HIT, DEAD }

var combat_state: CombatState = CombatState.IDLE
var _cooldowns: Dictionary = {}  # skill_id -> remaining_time
var _attack_combo_timer: float = 0.0
var _hit_stun_timer: float = 0.0
var _invincible_after_hit: float = 0.0  # 受击后短暂无敌

var _owner: Node
var _buff_manager: BuffManager
var _skill_executor: SkillExecutor
var _stats  # CharacterStats 或 EnemyStats，接口一致
var _sprite: AnimatedSprite2D
var _hit_box: Area2D
var _pending_skill: Dictionary = {}
var _pending_animation := ""
var _active_window_id := ""
var _pending_skill_executed := false


func _ready() -> void:
	_owner = get_parent()
	_buff_manager = BuffManager.new(_owner)
	add_child(_buff_manager)
	_skill_executor = SkillExecutor.new(_owner, null)
	# HitBox
	_hit_box = _owner.get_node_or_null("HitBox")
	if _hit_box != null:
		if _hit_box.has_method("setup"):
			_hit_box.setup(_owner)
		if _hit_box.has_signal("hit_detected"):
			_hit_box.hit_detected.connect(_on_hit_detected)
	_sprite = _owner.get_node_or_null("CharacterActionSet/AnimatedSprite2D")
	if _sprite != null:
		_sprite.frame_changed.connect(_on_sprite_frame_changed)
		_sprite.animation_finished.connect(_on_sprite_animation_finished)
	# HurtBox
	var hurt_box := _owner.get_node_or_null("HurtBox")
	if hurt_box != null:
		hurt_box.setup(_owner)
		hurt_box.add_to_group("hurt_box")
	# 延迟到首帧解析 stats（等 init_from_config 完成）
	call_deferred("_resolve_stats")


func _resolve_stats() -> void:
	if _stats != null:
		return
	if _owner.has_method("get_combat_stats"):
		_stats = _owner.get_combat_stats()
	if _stats == null:
		_stats = GameRegistry.character_stats
	_skill_executor._stats = _stats


func _process(delta: float) -> void:
	if combat_state == CombatState.DEAD:
		_end_melee_window()
		return

	# 冷却计时
	for skill_id in _cooldowns:
		if _cooldowns[skill_id] > 0.0:
			_cooldowns[skill_id] -= delta

	# 受击硬直
	if _hit_stun_timer > 0.0:
		_hit_stun_timer -= delta
		if _hit_stun_timer <= 0.0 and combat_state == CombatState.HIT:
			combat_state = CombatState.IDLE

	# 受击后无敌
	if _invincible_after_hit > 0.0:
		_invincible_after_hit -= delta

	# Revalidate the active window every tick. This is also the cleanup path
	# when a timer/state interruption happens without another frame_changed.
	if _pending_skill.is_empty():
		if _hit_box != null and _hit_box.has_method("is_active") and _hit_box.is_active():
			_hit_box.deactivate()
	elif combat_state != CombatState.ATTACKING and combat_state != CombatState.SKILL:
		_end_melee_window()
	else:
		_on_sprite_frame_changed()


func _unhandled_input(event: InputEvent) -> void:
	if not _owner.is_in_group("player"):
		return
	if combat_state == CombatState.DEAD:
		return
	if not _buff_manager.can_act():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_J:
				try_use_skill(1001)  # 普攻
			KEY_K:
				try_use_skill(1002)  # 技能1
			KEY_L:
				try_use_skill(1003)  # 技能2
			KEY_U:
				try_use_skill(1004)  # 技能3


## 尝试释放技能
func try_use_skill(skill_id: int) -> bool:
	_resolve_stats()
	if combat_state == CombatState.DEAD:
		return false
	if combat_state != CombatState.IDLE:
		return false
	if not _buff_manager.can_act():
		return false
	if _cooldowns.get(skill_id, 0.0) > 0.0:
		return false

	var skill: Dictionary = GameRegistry.skill_config.get_skill(skill_id)
	if skill.is_empty():
		return false

	# 设置冷却
	_cooldowns[skill_id] = float(skill.get("cooldown", 0.0))

	# 切换战斗状态
	var anim_name: String = skill.get("animation", "attack")
	var skill_type := String(skill.get("type", "melee"))
	combat_state = CombatState.ATTACKING if skill_type == "melee" else CombatState.SKILL
	attack_started.emit(skill_id)

	var use_frame_window := skill_type == "melee" or _has_configured_hit_windows(anim_name)
	if use_frame_window:
		_pending_skill = skill
		_pending_animation = anim_name
		_active_window_id = ""
		_pending_skill_executed = false
	else:
		_skill_executor.execute(skill)

	# 自身 buff
	var self_buff_id := int(skill.get("buff_on_self", 0))
	if self_buff_id > 0:
		var buff_config = GameRegistry.buff_config.get_buff(self_buff_id)
		if not buff_config.is_empty():
			_buff_manager.apply_buff(buff_config, _owner.get_instance_id())

	# 播放动画（如果有 AnimatedSprite2D）
	if _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation(anim_name)
	if use_frame_window:
		_on_sprite_frame_changed()

	# 攻击状态持续后恢复
	get_tree().create_timer(0.5).timeout.connect(_reset_combat_state)
	return true


## 受到伤害
func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true) -> void:
	_resolve_stats()
	if combat_state == CombatState.DEAD:
		return
	if _stats == null:
		return
	if _invincible_after_hit > 0.0:
		return
	if _buff_manager.has_buff_type("invincible"):
		return
	if play_hit_reaction:
		_end_melee_window()

	# Buff 减伤
	amount = _buff_manager.modify_damage(amount)

	# 防御减伤
	var actual := maxi(1, amount - _stats.defense)
	_stats.hp = maxi(0, _stats.hp - actual)
	hp_changed.emit(_stats.hp, _stats.max_hp)
	took_damage.emit(actual, source)

	if _stats.hp <= 0:
		_die()
		return

	# DoT 等持续伤害只扣血，不重复触发受击动作与移动硬直。
	if play_hit_reaction:
		combat_state = CombatState.HIT
		_hit_stun_timer = 0.1
		_invincible_after_hit = 0.8
		if _owner.has_method("play_combat_animation"):
			_owner.play_combat_animation("hit")


## 获取冷却字典（供 debug 面板使用）
func get_cooldowns_dict() -> Dictionary:
	return _cooldowns.duplicate()


## 治疗
func heal(amount: int) -> void:
	_resolve_stats()
	if _stats == null:
		return
	var actual := mini(amount, _stats.max_hp - _stats.hp)
	_stats.hp += actual
	hp_changed.emit(_stats.hp, _stats.max_hp)


## 施加 Buff（从配置）
func apply_buff_from_config(config: Dictionary, source: int = 0) -> void:
	_buff_manager.apply_buff(config, source)


## 获取 BuffManager
func get_buff_manager() -> BuffManager:
	return _buff_manager


## 是否存活
func is_alive() -> bool:
	return combat_state != CombatState.DEAD


func _die() -> void:
	_end_melee_window()
	_hit_stun_timer = 0.0
	combat_state = CombatState.DEAD
	died.emit()
	if _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("dead")


func _reset_combat_state() -> void:
	if combat_state == CombatState.ATTACKING or combat_state == CombatState.SKILL:
		combat_state = CombatState.IDLE
		if _owner.has_method("_end_combat_anim"):
			_owner._end_combat_anim()


func _on_sprite_frame_changed() -> void:
	if _pending_skill.is_empty() or _sprite == null or _hit_box == null:
		return
	if String(_sprite.animation) != _pending_animation:
		_end_melee_window()
		return
	var window := _get_hit_window(_pending_animation, _sprite.frame)
	if window.is_empty():
		_active_window_id = ""
		_hit_box.deactivate()
		return
	var window_id := "%s:%d:%d" % [
		_pending_animation,
		int(window.get("start_frame", 0)),
		int(window.get("end_frame", 0)),
	]
	if window_id == _active_window_id:
		return
	_active_window_id = window_id
	var facing := _get_facing_sign()
	_hit_box.configure(window, facing)
	var skill_type := String(_pending_skill.get("type", "melee"))
	var detects_hits := skill_type == "melee"
	_hit_box.activate(detects_hits)
	if not detects_hits and not _pending_skill_executed:
		_pending_skill_executed = true
		_skill_executor.execute(_pending_skill)


func _on_sprite_animation_finished() -> void:
	if _sprite == null or String(_sprite.animation) != _pending_animation:
		return
	_end_melee_window()


func _end_melee_window() -> void:
	_pending_skill = {}
	_pending_animation = ""
	_active_window_id = ""
	_pending_skill_executed = false
	if _hit_box != null:
		_hit_box.deactivate()


func _get_hit_window(animation_name: String, frame: int) -> Dictionary:
	var actions: Dictionary = {}
	if _owner.has_method("get_combat_actions"):
		actions = _owner.get_combat_actions()
	var action: Dictionary = actions.get(animation_name, {})
	var windows: Array = action.get("hit_windows", [])
	if windows.is_empty():
		var frame_count := _sprite.sprite_frames.get_frame_count(animation_name)
		var hit_frame := maxi(0, frame_count / 2)
		var attack_range := float(_pending_skill.get("range", 40.0))
		windows = [{
			"start_frame": hit_frame,
			"end_frame": hit_frame,
			"forward": attack_range * 0.75,
			"y": 0.0,
			"width": attack_range * 0.5,
			"height": 24.0,
		}]
	for candidate in windows:
		if candidate is Dictionary:
			var start_frame := int(candidate.get("start_frame", 0))
			var end_frame := int(candidate.get("end_frame", start_frame))
			if frame >= start_frame and frame <= end_frame:
				return candidate
	return {}


func _has_configured_hit_windows(animation_name: String) -> bool:
	if not _owner.has_method("get_combat_actions"):
		return false
	var actions: Dictionary = _owner.get_combat_actions()
	var action: Dictionary = actions.get(animation_name, {})
	var windows: Array = action.get("hit_windows", [])
	return not windows.is_empty()


func _get_facing_sign() -> float:
	if _sprite != null:
		return 1.0 if _sprite.flip_h else -1.0
	return 1.0


func _on_hit_detected(hurt_box: Area2D) -> void:
	if _pending_skill.is_empty() or String(_pending_skill.get("type", "melee")) != "melee":
		return
	_skill_executor.apply_melee_hit(_pending_skill, hurt_box)
