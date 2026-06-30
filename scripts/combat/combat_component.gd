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


func _ready() -> void:
	_owner = get_parent()
	_buff_manager = BuffManager.new(_owner)
	add_child(_buff_manager)
	_skill_executor = SkillExecutor.new(_owner, null)
	# HitBox
	var hit_box := _owner.get_node_or_null("HitBox")
	if hit_box != null:
		if hit_box.has_method("setup"):
			hit_box.setup(_owner)
		if hit_box.has_signal("hit_detected"):
			hit_box.hit_detected.connect(_on_hit_detected)
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
	# 冷却计时
	for skill_id in _cooldowns:
		if _cooldowns[skill_id] > 0.0:
			_cooldowns[skill_id] -= delta

	# 受击硬直
	if _hit_stun_timer > 0.0:
		_hit_stun_timer -= delta
		if _hit_stun_timer <= 0.0:
			combat_state = CombatState.IDLE

	# 受击后无敌
	if _invincible_after_hit > 0.0:
		_invincible_after_hit -= delta


func _unhandled_input(event: InputEvent) -> void:
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
	combat_state = CombatState.SKILL if skill_id != 1001 else CombatState.ATTACKING
	attack_started.emit(skill_id)

	# 执行技能
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

	# 攻击状态持续后恢复
	get_tree().create_timer(0.4).timeout.connect(_reset_combat_state)
	return true


## 受到伤害
func take_damage(amount: int, source: Node = null) -> void:
	_resolve_stats()
	if combat_state == CombatState.DEAD:
		return
	if _stats == null:
		return
	if _invincible_after_hit > 0.0:
		return
	if _buff_manager.has_buff_type("invincible"):
		return

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

	# 受击硬直 + 短暂无敌
	combat_state = CombatState.HIT
	_hit_stun_timer = 0.6
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
	combat_state = CombatState.DEAD
	died.emit()
	if _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("dead")


func _reset_combat_state() -> void:
	if combat_state == CombatState.ATTACKING or combat_state == CombatState.SKILL:
		combat_state = CombatState.IDLE


func _on_hit_detected(hurt_box: Area2D) -> void:
	# HitBox 碰到 HurtBox 时（melee 近战命中）
	# 伤害已在 SkillExecutor 中处理，这里只做额外逻辑
	pass
