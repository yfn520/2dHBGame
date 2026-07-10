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
var _pending_self_buff_applied := false
var _cast_id := 0
var _cast_nodes: Array = []
var _cast_node_index := 0
var _cast_waiting_node: Dictionary = {}
var _cast_wait_event := ""
var _cast_wait_animation_end := false
var _cast_animation_finished := false
var _cast_hit_window_active := false
var _cast_hit_window_detects := true
var _cast_hit_window_index := -1
var _active_window_index := -1
var _cast_consumed_events: Dictionary = {}
var _cast_hit_targets: Dictionary = {}
var _cast_cancelled := false
var _cast_cancel_reason := ""


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
		cancel_cast("state_changed")
	else:
		_on_sprite_frame_changed()


func _unhandled_input(event: InputEvent) -> void:
	if not _owner.is_in_group("player"):
		return
	if _owner.has_method("is_player_controlled") and not _owner.is_player_controlled():
		return
	if combat_state == CombatState.DEAD:
		return
	if not _buff_manager.can_act():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_J:
				_try_use_owner_skill("normal")
			KEY_K:
				_try_use_owner_skill("skill1")
			KEY_L:
				_try_use_owner_skill("skill2")
			KEY_U:
				_try_use_owner_skill("skill3")


## 尝试释放技能
func _try_use_owner_skill(slot_name: String) -> bool:
	var skill_id := 0
	if _owner != null and _owner.has_method("get_skill_for_input"):
		skill_id = int(_owner.get_skill_for_input(slot_name))
	if skill_id <= 0:
		return false
	return try_use_skill(skill_id)


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

	_cooldowns[skill_id] = float(skill.get("cooldown", 0.0))

	var anim_name: String = skill.get("animation", "attack")
	var skill_type := String(skill.get("type", "melee"))
	combat_state = CombatState.ATTACKING if skill_type == "melee" else CombatState.SKILL
	attack_started.emit(skill_id)

	_cast_id += 1
	_cast_nodes = _build_cast_nodes(skill)
	_cast_node_index = 0
	_cast_waiting_node.clear()
	_cast_wait_event = ""
	_cast_wait_animation_end = false
	_cast_animation_finished = false
	_cast_hit_window_active = false
	_cast_hit_window_detects = skill_type == "melee"
	_cast_hit_window_index = -1
	_active_window_index = -1
	_cast_consumed_events.clear()
	_cast_hit_targets.clear()
	_cast_cancelled = false
	_cast_cancel_reason = ""
	_pending_self_buff_applied = false
	_pending_skill = skill
	_pending_animation = anim_name
	_active_window_id = ""
	_pending_skill_executed = false
	_advance_cast_nodes()
	return true


func _build_cast_nodes(skill: Dictionary) -> Array:
	var configured_nodes: Array = skill.get("nodes", [])
	if not configured_nodes.is_empty():
		return configured_nodes.duplicate(true)
	var anim_name := String(skill.get("animation", "attack"))
	var skill_type := String(skill.get("type", "melee"))
	var effect_timing := String(skill.get("effect_timing", "cast_start"))
	var nodes: Array = [{"type": "play_animation", "action": anim_name}]
	if skill_type == "melee":
		nodes.append({"type": "use_action_hit_window", "action": anim_name, "detects_hits": true})
		nodes.append({"type": "wait_animation_end"})
	elif effect_timing == "active_frame":
		nodes.append({"type": "wait_action_event", "event": "release"})
		nodes.append({"type": "execute_skill_effect"})
		nodes.append({"type": "wait_animation_end"})
	elif effect_timing == "animation_end":
		nodes.append({"type": "wait_animation_end"})
		nodes.append({"type": "execute_skill_effect"})
	else:
		nodes.append({"type": "execute_skill_effect"})
		nodes.append({"type": "wait_animation_end"})
	nodes.append({"type": "end_skill"})
	return nodes


func _advance_cast_nodes() -> void:
	if _pending_skill.is_empty() or _cast_cancelled:
		return
	if not _cast_waiting_node.is_empty():
		if not _is_node_trigger_ready(_cast_waiting_node):
			return
		var waiting_node: Dictionary = _cast_waiting_node.duplicate(true)
		_cast_waiting_node.clear()
		if _execute_cast_node(waiting_node):
			return
	while _cast_node_index < _cast_nodes.size():
		var node_value = _cast_nodes[_cast_node_index]
		_cast_node_index += 1
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		var trigger := String(node.get("trigger", "immediate"))
		if trigger != "immediate" and not _is_node_trigger_ready(node):
			_cast_waiting_node = node
			return
		if _execute_cast_node(node):
			return
	_finish_cast()


func _execute_cast_node(node: Dictionary) -> bool:
	var node_type := String(node.get("type", ""))
	match node_type:
		"play_animation":
			var action := String(node.get("action", _pending_skill.get("animation", "attack")))
			_pending_animation = action
			_cast_animation_finished = false
			if _owner.has_method("play_combat_animation"):
				_owner.play_combat_animation(action)
			_on_sprite_frame_changed()
		"wait_action_event":
			_cast_wait_event = String(node.get("event", "release"))
			if _is_action_event_now(_pending_animation, _cast_wait_event):
				_consume_action_event(_pending_animation, _cast_wait_event)
				_cast_wait_event = ""
			else:
				return true
		"wait_animation_end":
			_cast_wait_animation_end = true
			return true
		"use_action_hit_window":
			_pending_animation = String(node.get("action", _pending_animation))
			_cast_hit_window_active = true
			_cast_hit_window_detects = bool(node.get("detects_hits", String(_pending_skill.get("type", "melee")) == "melee"))
			_cast_hit_window_index = int(node.get("hit_window_index", -1))
			_on_sprite_frame_changed()
		"execute_skill_effect":
			_pending_skill_executed = true
			_skill_executor.execute(_pending_skill, _get_current_effect_origin(node))
		"spawn_projectile":
			_skill_executor.execute(_pending_skill, _get_current_effect_origin(node))
		"aoe", "circle_aoe", "rect_aoe", "fullscreen", "damage", "apply_target_buff":
			_skill_executor.execute(_pending_skill, _get_current_effect_origin(node))
		"apply_self_buff", "self_buff":
			_apply_self_buff(_pending_skill)
		"heal":
			heal(int(node.get("amount", 0)))
		"move_x":
			_apply_node_move_x(node)
		"play_effect":
			_play_node_effect(node)
		"end_skill":
			_finish_cast()
			return true
		_:
			pass
	return false


func _is_node_trigger_ready(node: Dictionary) -> bool:
	var trigger := String(node.get("trigger", "immediate"))
	match trigger:
		"event":
			var event_name := String(node.get("event", "release"))
			if not _is_action_event_now(_pending_animation, event_name):
				return false
			_consume_action_event(_pending_animation, event_name)
			return true
		"hit_window":
			if _sprite == null:
				return false
			var requested_index := int(node.get("hit_window_index", -1))
			var info := _get_hit_window_info(_pending_animation, _sprite.frame, requested_index)
			if info.is_empty():
				return false
			var active_index := int(info.get("index", -1))
			var effect_window: Dictionary = info.get("window", {})
			_configure_effect_origin(effect_window, active_index)
			return true
		"animation_end":
			return _cast_animation_finished
		_:
			return true


func _configure_effect_origin(window: Dictionary, window_index: int) -> void:
	if _hit_box == null or window.is_empty():
		return
	_hit_box.configure(window, _get_facing_sign())
	_active_window_index = window_index


func _finish_cast() -> void:
	if _pending_skill.is_empty():
		return
	_end_melee_window()
	if combat_state == CombatState.ATTACKING or combat_state == CombatState.SKILL:
		combat_state = CombatState.IDLE
		if _owner.has_method("_end_combat_anim"):
			_owner._end_combat_anim()


func cancel_cast(reason: String = "cancelled") -> void:
	if _pending_skill.is_empty():
		return
	_cast_cancelled = true
	_cast_cancel_reason = reason
	_end_melee_window()
	if combat_state == CombatState.ATTACKING or combat_state == CombatState.SKILL:
		combat_state = CombatState.IDLE
		if _owner.has_method("_end_combat_anim"):
			_owner._end_combat_anim()


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
	if play_hit_reaction and not _is_current_frame_armored():
		cancel_cast("hit")

	# Buff 减伤
	amount = _buff_manager.modify_damage(amount)

	# 防御减伤
	var actual := maxi(1, amount - _stats.defense)
	_stats.hp = maxi(0, _stats.hp - actual)
	if _owner.has_method("sync_combat_hp"):
		_owner.sync_combat_hp()
	if play_hit_reaction and _stats.hp > 0:
		combat_state = CombatState.HIT
		_hit_stun_timer = 0.1
		_invincible_after_hit = 0.8
	hp_changed.emit(_stats.hp, _stats.max_hp)
	took_damage.emit(actual, source)

	if _stats.hp <= 0:
		_die()
		return

	# DoT 等持续伤害只扣血，不重复触发受击动作与移动硬直。
	if play_hit_reaction:
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
	if _owner.has_method("sync_combat_hp"):
		_owner.sync_combat_hp()
	hp_changed.emit(_stats.hp, _stats.max_hp)


## 施加 Buff（从配置）
func apply_buff_from_config(config: Dictionary, source: int = 0) -> void:
	_buff_manager.apply_buff(config, source)
	var buff_type := String(config.get("type", ""))
	if buff_type == "stun" or buff_type == "freeze":
		cancel_cast(buff_type)


## 获取 BuffManager
func get_buff_manager() -> BuffManager:
	return _buff_manager


## 是否存活
func is_alive() -> bool:
	return combat_state != CombatState.DEAD


func _die() -> void:
	cancel_cast("dead")
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
	if _pending_skill.is_empty() or _sprite == null:
		return
	if String(_sprite.animation) != _pending_animation:
		cancel_cast("animation_changed")
		return
	if not _cast_wait_event.is_empty() and _is_action_event_now(_pending_animation, _cast_wait_event):
		_consume_action_event(_pending_animation, _cast_wait_event)
		_cast_wait_event = ""
		_advance_cast_nodes()
	if not _cast_waiting_node.is_empty():
		var waiting_trigger := String(_cast_waiting_node.get("trigger", "immediate"))
		if waiting_trigger == "event" or waiting_trigger == "hit_window":
			_advance_cast_nodes()
			if not _cast_waiting_node.is_empty():
				return
	if not _cast_hit_window_active or _hit_box == null:
		return
	var info := _get_hit_window_info(_pending_animation, _sprite.frame)
	if info.is_empty():
		_active_window_id = ""
		_active_window_index = -1
		_hit_box.deactivate()
		return
	var window: Dictionary = info.get("window", {})
	var window_index := int(info.get("index", -1))
	if _cast_hit_window_index >= 0 and window_index != _cast_hit_window_index:
		_active_window_id = ""
		_active_window_index = -1
		_hit_box.deactivate()
		return
	var window_id := "%s:%d:%d" % [
		_pending_animation,
		int(window.get("start_frame", 0)),
		int(window.get("end_frame", 0)),
	]
	window_id += ":%d" % window_index
	if window_id == _active_window_id:
		return
	_active_window_id = window_id
	_active_window_index = window_index
	var facing := _get_facing_sign()
	_hit_box.configure(window, facing)
	var detects_hits := _cast_hit_window_detects
	_hit_box.activate(detects_hits)
	if String(_pending_skill.get("effect_timing", "cast_start")) == "active_frame":
		_apply_self_buff(_pending_skill)
	if not detects_hits and not _pending_skill_executed:
		_pending_skill_executed = true
		_skill_executor.execute(_pending_skill, _hit_box.global_position)


func _on_sprite_animation_finished() -> void:
	if _sprite == null or String(_sprite.animation) != _pending_animation:
		return
	_cast_animation_finished = true
	if _cast_wait_animation_end:
		_cast_wait_animation_end = false
		_advance_cast_nodes()
	elif not _cast_waiting_node.is_empty():
		_advance_cast_nodes()
	else:
		_finish_cast()


func _end_melee_window() -> void:
	_pending_skill = {}
	_pending_animation = ""
	_active_window_id = ""
	_pending_skill_executed = false
	_pending_self_buff_applied = false
	_cast_nodes = []
	_cast_node_index = 0
	_cast_waiting_node.clear()
	_cast_wait_event = ""
	_cast_wait_animation_end = false
	_cast_animation_finished = false
	_cast_hit_window_active = false
	_cast_hit_window_detects = true
	_cast_hit_window_index = -1
	_active_window_index = -1
	_cast_consumed_events.clear()
	_cast_hit_targets.clear()
	if _hit_box != null:
		_hit_box.deactivate()


func _apply_self_buff(skill: Dictionary) -> void:
	if _pending_self_buff_applied:
		return
	var self_buff_id := int(skill.get("buff_on_self", 0))
	if self_buff_id <= 0:
		return
	var buff_config: Dictionary = GameRegistry.buff_config.get_buff(self_buff_id)
	if buff_config.is_empty():
		return
	_pending_self_buff_applied = true
	_buff_manager.apply_buff(buff_config, _owner.get_instance_id())


func _get_hit_window_info(animation_name: String, frame: int, requested_index: int = -1) -> Dictionary:
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
	for window_index in range(windows.size()):
		var candidate = windows[window_index]
		if requested_index >= 0 and window_index != requested_index:
			continue
		if candidate is Dictionary:
			var start_frame := int(candidate.get("start_frame", 0))
			var end_frame := int(candidate.get("end_frame", start_frame))
			if frame >= start_frame and frame <= end_frame:
				return {"window": candidate, "index": window_index}
	return {}


func _get_hit_window(animation_name: String, frame: int) -> Dictionary:
	var info := _get_hit_window_info(animation_name, frame)
	return info.get("window", {})


func _has_configured_hit_windows(animation_name: String) -> bool:
	if not _owner.has_method("get_combat_actions"):
		return false
	var actions: Dictionary = _owner.get_combat_actions()
	var action: Dictionary = actions.get(animation_name, {})
	var windows: Array = action.get("hit_windows", [])
	return not windows.is_empty()


func _get_action_data(animation_name: String) -> Dictionary:
	if _owner == null or not _owner.has_method("get_combat_actions"):
		return {}
	var actions: Dictionary = _owner.get_combat_actions()
	return actions.get(animation_name, {})


func _is_action_event_now(animation_name: String, event_name: String) -> bool:
	if _sprite == null or event_name.is_empty():
		return false
	var consumed_key := "%s:%s:%d" % [animation_name, event_name, _sprite.frame]
	if _cast_consumed_events.has(consumed_key):
		return false
	var action := _get_action_data(animation_name)
	for value in action.get("events", []):
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		if String(event.get("name", "")) == event_name and int(event.get("frame", -1)) == _sprite.frame:
			return true
	return false


func _consume_action_event(animation_name: String, event_name: String) -> void:
	if _sprite == null:
		return
	var consumed_key := "%s:%s:%d" % [animation_name, event_name, _sprite.frame]
	_cast_consumed_events[consumed_key] = true


func _is_current_frame_armored() -> bool:
	if _pending_animation.is_empty() or _sprite == null:
		return false
	var action := _get_action_data(_pending_animation)
	for value in action.get("armor_windows", []):
		if not value is Dictionary:
			continue
		var window: Dictionary = value
		var start_frame := int(window.get("start_frame", 0))
		var end_frame := int(window.get("end_frame", start_frame))
		if _sprite.frame >= start_frame and _sprite.frame <= end_frame:
			return true
	return false


func _get_current_effect_origin(node: Dictionary) -> Variant:
	var socket_name := String(node.get("socket", ""))
	if not socket_name.is_empty():
		var socket_pos : Vector2= _get_socket_position(_pending_animation, socket_name, _sprite.frame if _sprite != null else 0)
		if socket_pos is Vector2:
			return socket_pos
	if _hit_box != null:
		return _hit_box.global_position
	return _owner.global_position if _owner is Node2D else null


func _get_socket_position(animation_name: String, socket_name: String, frame: int) -> Variant:
	var action := _get_action_data(animation_name)
	var sockets: Dictionary = action.get("sockets", {})
	var frames: Array = sockets.get(socket_name, [])
	if frames.is_empty():
		return null
	var best: Dictionary = {}
	for value in frames:
		if not value is Dictionary:
			continue
		var socket: Dictionary = value
		if int(socket.get("frame", -1)) <= frame:
			best = socket
		else:
			break
	if best.is_empty():
		best = frames[0]
	var local := Vector2(float(best.get("x", 0.0)) * _get_facing_sign(), float(best.get("y", 0.0)))
	if _owner is Node2D:
		return (_owner as Node2D).global_position + local
	return local


func _apply_node_move_x(node: Dictionary) -> void:
	if not _owner is Node2D:
		return
	var delta_x := float(node.get("delta_x", node.get("distance", 0.0))) * _get_facing_sign()
	(_owner as Node2D).global_position.x += delta_x


func _play_node_effect(node: Dictionary) -> void:
	var scene_path := String(node.get("scene", node.get("effect_scene", "")))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var scene: PackedScene = load(scene_path)
	var fx := scene.instantiate()
	if fx is Node2D:
		(fx as Node2D).global_position = _get_current_effect_origin(node)
	_owner.get_tree().current_scene.add_child(fx)


func _get_facing_sign() -> float:
	if _sprite != null:
		return 1.0 if _sprite.flip_h else -1.0
	return 1.0


func _on_hit_detected(hurt_box: Area2D) -> void:
	if _pending_skill.is_empty() or String(_pending_skill.get("type", "melee")) != "melee":
		return
	var hit_key := hurt_box.get_instance_id()
	if _cast_hit_targets.has(hit_key):
		return
	_cast_hit_targets[hit_key] = true
	_skill_executor.apply_melee_hit(_pending_skill, hurt_box)
