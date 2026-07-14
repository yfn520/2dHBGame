extends Node
## Node-only skill runner. Control nodes advance the cast; action nodes do work.

signal hp_changed(current: int, max_hp: int)
signal died()
signal attack_started(skill_id: int)
signal took_damage(amount: int, source: Node)

enum CombatState { IDLE, ATTACKING, SKILL, HIT, DEAD }

var combat_state: CombatState = CombatState.IDLE
var _cooldowns: Dictionary = {}
var _hit_stun_timer := 0.0
var _invincible_after_hit := 0.0
var _manual_skill_input_enabled := true

var _owner: Node
var _buff_manager: BuffManager
var _skill_executor: SkillExecutor
var _stats
var _sprite: AnimatedSprite2D
var _hit_box: Area2D

var _pending_skill: Dictionary = {}
var _cast_context: SkillCastContext
var _cast_nodes: Array = []
var _cast_index := 0
var _waiting: Dictionary = {}
var _current_action := ""
var _animation_finished := false
var _consumed_events: Dictionary = {}
var _active_melee_node: Dictionary = {}
var _active_melee_window_index := -1
var _cast_serial := 0
var _is_advancing_cast := false
var _cast_elapsed := 0.0
var _cast_timeout := 5.0
var _action_elapsed := 0.0
var _action_duration := 0.0
var _last_skill_attempt := "none"


func _ready() -> void:
	_owner = get_parent()
	_buff_manager = BuffManager.new(_owner)
	add_child(_buff_manager)
	_skill_executor = SkillExecutor.new(_owner, null)
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
	var hurt_box := _owner.get_node_or_null("HurtBox")
	if hurt_box != null:
		hurt_box.setup(_owner)
		hurt_box.add_to_group("hurt_box")
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
	for skill_id in _cooldowns.keys():
		_cooldowns[skill_id] = maxf(0.0, float(_cooldowns.get(skill_id, 0.0)) - delta)
	if combat_state == CombatState.DEAD:
		return
	if _hit_stun_timer > 0.0:
		_hit_stun_timer -= delta
		if _hit_stun_timer <= 0.0 and combat_state == CombatState.HIT:
			combat_state = CombatState.IDLE
	if _invincible_after_hit > 0.0:
		_invincible_after_hit -= delta
	if _pending_skill.is_empty():
		if _hit_box != null and _hit_box.has_method("is_active") and _hit_box.is_active():
			_hit_box.deactivate()
		# Recover from an interrupted/re-entrant clear that left only the public
		# combat state behind. Otherwise AI sees SKILL forever and never casts again.
		if combat_state == CombatState.SKILL or combat_state == CombatState.ATTACKING:
			combat_state = CombatState.IDLE
			if _owner.has_method("_end_combat_anim"):
				_owner._end_combat_anim()
		return
	if combat_state != CombatState.SKILL and combat_state != CombatState.ATTACKING:
		cancel_cast("state_changed")
		return
	_cast_elapsed += delta
	_action_elapsed += delta
	if _cast_elapsed >= _cast_timeout:
		cancel_cast("timeout")
		return
	# Imported action animations can be marked as looping. In that case Godot
	# never emits animation_finished, but a skill still treats one cycle as done.
	if _action_duration > 0.0 and _action_elapsed >= _action_duration:
		_animation_finished = true
	# The actor owns its visual state and can restore idle from an
	# animation_finished listener before this component observes that signal.
	# Poll the transition as a final guard so a wait_animation_end node can never
	# leave the cast and the AI permanently locked in SKILL.
	if String(_waiting.get("type", "")) == "wait_animation_end" and _sprite != null and not _current_action.is_empty() and String(_sprite.animation) != _current_action:
		_animation_finished = true
	_refresh_active_melee_window()
	_advance_cast()


func _unhandled_input(event: InputEvent) -> void:
	if not _owner.is_in_group("player") or (_owner.has_method("is_player_controlled") and not _owner.is_player_controlled()):
		return
	if not _manual_skill_input_enabled:
		return
	if combat_state == CombatState.DEAD or not _buff_manager.can_act():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_J: _try_use_owner_skill("normal")
			KEY_K: _try_use_owner_skill("skill1")
			KEY_L: _try_use_owner_skill("skill2")
			KEY_U: _try_use_owner_skill("skill3")


func set_manual_skill_input_enabled(enabled: bool) -> void:
	_manual_skill_input_enabled = enabled


func _try_use_owner_skill(slot_name: String) -> bool:
	var skill_id := int(_owner.get_skill_for_input(slot_name)) if _owner != null and _owner.has_method("get_skill_for_input") else 0
	return try_use_skill(skill_id) if skill_id > 0 else false


func try_use_skill(skill_id: int) -> bool:
	_resolve_stats()
	if skill_id <= 0:
		_last_skill_attempt = "invalid_id"
		return false
	if combat_state != CombatState.IDLE:
		_last_skill_attempt = "state:%s" % CombatState.keys()[combat_state]
		return false
	if not _buff_manager.can_act():
		_last_skill_attempt = "cannot_act"
		return false
	var remaining_cooldown := float(_cooldowns.get(skill_id, 0.0))
	if remaining_cooldown > 0.0:
		_last_skill_attempt = "cd:%d=%.2f" % [skill_id, remaining_cooldown]
		return false
	var skill: Dictionary = GameRegistry.skill_config.get_skill(skill_id)
	if skill.is_empty():
		_last_skill_attempt = "missing:%d" % skill_id
		return false
	var nodes: Array = skill.get("nodes", [])
	if nodes.is_empty():
		_last_skill_attempt = "no_nodes:%d" % skill_id
		push_error("技能 %d 没有节点，无法施放" % skill_id)
		return false
	_last_skill_attempt = "cast:%d" % skill_id
	_cooldowns[skill_id] = float(skill.get("cooldown", 0.0))
	combat_state = CombatState.SKILL
	attack_started.emit(skill_id)
	_cast_serial += 1
	_pending_skill = skill.duplicate(true)
	_cast_context = SkillCastContext.new(_owner, skill_id)
	_cast_nodes = nodes.duplicate(true)
	_cast_index = 0
	_cast_elapsed = 0.0
	_cast_timeout = 5.0
	_action_elapsed = 0.0
	_action_duration = 0.0
	_waiting.clear()
	_current_action = ""
	_animation_finished = false
	_consumed_events.clear()
	_active_melee_node.clear()
	_active_melee_window_index = -1
	_advance_cast()
	return true


func _advance_cast() -> void:
	if _is_advancing_cast:
		return
	_is_advancing_cast = true
	_advance_cast_internal()
	_is_advancing_cast = false


func _advance_cast_internal() -> void:
	if _pending_skill.is_empty() or _cast_context == null or _cast_context.cancelled:
		return
	if not _waiting.is_empty():
		if not _is_wait_ready():
			return
		_waiting.clear()
	while _cast_index < _cast_nodes.size():
		var value: Variant = _cast_nodes[_cast_index]
		_cast_index += 1
		if not value is Dictionary:
			continue
		var node: Dictionary = value
		if _execute_node(node):
			return
	_finish_cast()


func _execute_node(node: Dictionary) -> bool:
	var node_type := String(node.get("type", ""))
	match node_type:
		"play_animation":
			_current_action = String(node.get("action", ""))
			if _current_action.is_empty():
				push_error("播放动画节点缺少 action")
				return false
			_animation_finished = false
			_action_elapsed = 0.0
			_action_duration = _get_animation_duration(_current_action)
			_cast_timeout = maxf(_cast_timeout, _cast_elapsed + maxf(1.0, _action_duration * 2.0 + 0.5))
			_cast_context.current_action = _current_action
			if _owner.has_method("play_combat_animation"):
				_owner.play_combat_animation(_current_action)
		"wait_action_event", "wait_hit_window", "wait_animation_end", "wait_time":
			_waiting = node.duplicate(true)
			if _is_wait_ready():
				_waiting.clear()
				return false
			return true
		"melee_damage":
			_begin_melee_damage(node)
		"area_damage":
			_skill_executor.execute_damage_area(node, _resolve_origin(node), _cast_context)
		"fullscreen_damage":
			_skill_executor.execute_fullscreen_damage(node, _cast_context)
		"spawn_projectile":
			_skill_executor.spawn_projectiles(node, _resolve_origin(node), _cast_context)
		"play_effect":
			_execute_effect_node(node)
		"apply_target_buff":
			_execute_target_buff_node(node)
		"apply_self_buff":
			_skill_executor.apply_self_buff(node)
		"heal":
			_execute_heal_node(node)
		"move_x":
			_execute_move_node(node)
		"end_skill":
			_finish_cast()
			return true
		_:
			push_warning("未知技能节点: %s" % node_type)
	return false


func _is_wait_ready() -> bool:
	var wait_type := String(_waiting.get("type", ""))
	match wait_type:
		"wait_action_event":
			var event_name := String(_waiting.get("event", "release"))
			if not _is_action_event_now(_current_action, event_name):
				return false
			_consume_action_event(_current_action, event_name)
			return true
		"wait_hit_window":
			if _sprite == null:
				return false
			var info := _get_hit_window_info(_current_action, _sprite.frame, int(_waiting.get("hit_window_index", 0)))
			if info.is_empty():
				info = _get_passed_hit_window_info(_current_action, _sprite.frame, int(_waiting.get("hit_window_index", 0)))
			if info.is_empty():
				return false
			_enter_hit_window(info)
			return true
		"wait_animation_end":
			return _animation_finished
		"wait_time":
			if not bool(_waiting.get("timer_started", false)):
				_waiting["timer_started"] = true
				var serial := _cast_serial
				get_tree().create_timer(maxf(0.0, float(_waiting.get("seconds", 0.1)))).timeout.connect(_resume_after_time.bind(serial))
			return false
		"wait_time_done":
			return true
	return true


func _resume_after_time(serial: int) -> void:
	if serial != _cast_serial or _pending_skill.is_empty():
		return
	_waiting = {"type": "wait_time_done"}
	_advance_cast()


func _begin_melee_damage(node: Dictionary) -> void:
	if _cast_context.active_window.is_empty() or _hit_box == null:
		push_error("近战伤害节点必须放在等待攻击有效区间之后")
		return
	_cast_context.ensure_stream(String(node.get("result_key", "melee_hit")))
	_active_melee_node = node.duplicate(true)
	_active_melee_window_index = _cast_context.active_window_index
	_hit_box.configure(_cast_context.active_window, _get_facing_sign())
	_hit_box.activate(true)


func _enter_hit_window(info: Dictionary) -> void:
	var window: Dictionary = info.get("window", {})
	var index := int(info.get("index", -1))
	_cast_context.active_window = window
	_cast_context.active_window_index = index
	if _hit_box != null:
		_hit_box.configure(window, _get_facing_sign())
		_cast_context.current_anchor = _hit_box.global_position
	elif _owner is Node2D:
		_cast_context.current_anchor = (_owner as Node2D).global_position


func _refresh_active_melee_window() -> void:
	if _active_melee_node.is_empty() or _sprite == null or _hit_box == null:
		return
	var info := _get_hit_window_info(_current_action, _sprite.frame, _active_melee_window_index)
	if info.is_empty():
		_hit_box.deactivate()
		_active_melee_node.clear()
		_active_melee_window_index = -1
		return
	_enter_hit_window(info)


func _execute_effect_node(node: Dictionary) -> void:
	var target_mode := String(node.get("target", "origin"))
	if target_mode == "result" or target_mode == "last_result":
		_cast_context.subscribe(String(node.get("result_key", "last_result")), Callable(self, "_spawn_effect_on_target").bind(node.duplicate(true)), String(node.get("delivery", "each_hit")))
		return
	var targets := _skill_executor.resolve_targets(node, _resolve_origin(node), _cast_context)
	if not targets.is_empty():
		for target in targets:
			_spawn_effect_on_target(target, node)
		return
	_spawn_effect_at(_resolve_origin(node), node)


func _execute_target_buff_node(node: Dictionary) -> void:
	var target_mode := String(node.get("target", "result"))
	if target_mode == "result" or target_mode == "last_result":
		_cast_context.subscribe(String(node.get("result_key", "last_result")), Callable(self, "_apply_buff_to_target").bind(node.duplicate(true)), String(node.get("delivery", "each_hit")))
		return
	for target in _skill_executor.resolve_targets(node, _resolve_origin(node), _cast_context):
		_apply_buff_to_target(target, node)


func _spawn_effect_on_target(target: Area2D, node: Dictionary) -> void:
	if target != null and is_instance_valid(target):
		_spawn_effect_at(target.global_position, node)


func _spawn_effect_at(position_value: Vector2, node: Dictionary) -> void:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var effect := packed.instantiate()
	var offset := Vector2(float(node.get("offset_x", 0.0)), float(node.get("offset_y", 0.0)))
	var coord_space := String(node.get("coordinate_space", "world"))
	var scene := _owner.get_tree().current_scene if _owner != null and _owner.get_tree() != null else null
	if effect is Node2D and coord_space == "character_local" and _owner is Node2D:
		# Action attachments use frame-pixel coordinates relative to the character foot.
		# Keep them parented to the actor so they follow movement, and mirror exactly when
		# the source character sprite is flipped.
		var effect_node := effect as Node2D
		var visual_root := _owner.get_node_or_null("CharacterActionSet") as Node2D
		var visual_scale := absf(visual_root.scale.x) if visual_root != null and not is_zero_approx(visual_root.scale.x) else 1.0
		var mirror_x := -1.0 if _sprite != null and _sprite.flip_h else 1.0
		_owner.add_child(effect_node)
		effect_node.position = Vector2(offset.x * mirror_x * visual_scale, offset.y * visual_scale)
		effect_node.scale = effect_node.scale * Vector2(visual_scale, visual_scale)
		if effect_node is AnimatedSprite2D and _sprite != null:
			# 效果场景可烘焙水平镜像（flip_h），与角色朝向取异或，使特效内部镜像独立于角色朝向。
			(effect_node as AnimatedSprite2D).flip_h = (effect_node as AnimatedSprite2D).flip_h != _sprite.flip_h
		elif mirror_x < 0.0:
			effect_node.scale.x *= -1.0
		# The character visuals are a sibling at z=100 in imported actor scenes.
		# Resolve front/behind relative to that node rather than relative to the world root.
		var visual_z := visual_root.z_index if visual_root != null else (_sprite.z_index if _sprite != null else 0)
		var attachment_layer := String(node.get("attachment_layer", "front"))
		effect_node.z_as_relative = true
		effect_node.z_index = visual_z + (-1 if attachment_layer == "behind" else 1)
		return
	if scene == null:
		effect.queue_free()
		return
	scene.add_child(effect)
	if effect is Node2D:
		# World-space effects keep the previous behavior and do not follow the caster.
		(effect as Node2D).global_position = position_value + offset


func _apply_buff_to_target(target: Area2D, node: Dictionary) -> void:
	_skill_executor.apply_target_buff(node, target)


func _execute_heal_node(node: Dictionary) -> void:
	var amount := int(node.get("amount", 0))
	if amount <= 0:
		amount = _skill_executor.calculate_damage(float(node.get("ratio", 0.0)))
	heal(amount)


func _execute_move_node(node: Dictionary) -> void:
	if _owner is Node2D:
		(_owner as Node2D).global_position.x += float(node.get("distance", node.get("delta_x", 0.0))) * _get_facing_sign()


func _resolve_origin(node: Dictionary) -> Vector2:
	var origin_type := String(node.get("origin", "hit_window"))
	if origin_type == "socket":
		var socket_position: Variant = _get_socket_position(_current_action, String(node.get("socket", "")), _sprite.frame if _sprite != null else 0)
		if socket_position is Vector2:
			return socket_position
	if origin_type == "caster" and _owner is Node2D:
		return (_owner as Node2D).global_position
	if origin_type == "nearest_enemy":
		var target := _skill_executor.find_nearest_enemy(float(node.get("target_search_range", 99999.0)))
		if target != null:
			return target.global_position
	if _cast_context != null:
		return _cast_context.current_anchor
	return (_owner as Node2D).global_position if _owner is Node2D else Vector2.ZERO


func _finish_cast() -> void:
	if _pending_skill.is_empty():
		return
	_clear_cast(false)
	if combat_state == CombatState.SKILL or combat_state == CombatState.ATTACKING:
		combat_state = CombatState.IDLE
		if _owner.has_method("_end_combat_anim"):
			_owner._end_combat_anim()


func cancel_cast(_reason: String = "cancelled") -> void:
	if _pending_skill.is_empty():
		return
	if _cast_context != null:
		_cast_context.cancelled = true
	_clear_cast(true)
	if combat_state == CombatState.SKILL or combat_state == CombatState.ATTACKING:
		combat_state = CombatState.IDLE
		if _owner.has_method("_end_combat_anim"):
			_owner._end_combat_anim()


func _clear_cast(_cancelled: bool) -> void:
	_cast_serial += 1
	_pending_skill.clear()
	_cast_nodes.clear()
	_cast_index = 0
	_waiting.clear()
	_current_action = ""
	_animation_finished = false
	_consumed_events.clear()
	_active_melee_node.clear()
	_active_melee_window_index = -1
	_cast_elapsed = 0.0
	_cast_timeout = 5.0
	_action_elapsed = 0.0
	_action_duration = 0.0
	if _hit_box != null:
		_hit_box.deactivate()
	_cast_context = null


func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true) -> void:
	_resolve_stats()
	if combat_state == CombatState.DEAD or _stats == null or _invincible_after_hit > 0.0 or _buff_manager.has_buff_type("invincible"):
		return
	if play_hit_reaction and not _is_current_frame_armored():
		cancel_cast("hit")
	amount = _buff_manager.modify_damage(amount)
	var actual := maxi(1, amount - int(_stats.defense))
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
	elif play_hit_reaction and _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("hit")


func heal(amount: int) -> void:
	_resolve_stats()
	if _stats == null:
		return
	_stats.hp = mini(_stats.max_hp, _stats.hp + maxi(0, amount))
	if _owner.has_method("sync_combat_hp"):
		_owner.sync_combat_hp()
	hp_changed.emit(_stats.hp, _stats.max_hp)


func apply_buff_from_config(config: Dictionary, source: int = 0) -> void:
	_buff_manager.apply_buff(config, source)
	var buff_type := String(config.get("type", ""))
	if buff_type == "stun" or buff_type == "freeze":
		cancel_cast(buff_type)


func get_buff_manager() -> BuffManager:
	return _buff_manager


func get_cooldowns_dict() -> Dictionary:
	return _cooldowns.duplicate()


func get_debug_state() -> String:
	var wait_type := String(_waiting.get("type", "-"))
	var action := _current_action if not _current_action.is_empty() else "-"
	var frame := _sprite.frame if _sprite != null else -1
	return "%s wait:%s action:%s frame:%d node:%d/%d try:%s" % [
		CombatState.keys()[combat_state], wait_type, action, frame, _cast_index, _cast_nodes.size(), _last_skill_attempt
	]


func is_alive() -> bool:
	return combat_state != CombatState.DEAD


func _die() -> void:
	cancel_cast("dead")
	_hit_stun_timer = 0.0
	combat_state = CombatState.DEAD
	died.emit()
	if _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("dead")


func _on_sprite_frame_changed() -> void:
	if _pending_skill.is_empty() or _sprite == null:
		return
	if not _current_action.is_empty() and String(_sprite.animation) != _current_action:
		# The actor may restore idle in its own animation_finished callback before
		# this component receives the same signal. Treat that transition as the
		# pending action ending instead of leaving the cast in SKILL forever.
		if String(_waiting.get("type", "")) == "wait_animation_end":
			_animation_finished = true
			_advance_cast()
			return
		cancel_cast("animation_changed")
		return
	_refresh_active_melee_window()
	_advance_cast()


func _on_sprite_animation_finished() -> void:
	if _pending_skill.is_empty() or _sprite == null:
		return
	# Do not require sprite.animation to still equal _current_action here. Other
	# listeners can synchronously restore idle before this callback runs.
	_animation_finished = true
	_advance_cast()


func _on_hit_detected(hurt_box: Area2D) -> void:
	if _active_melee_node.is_empty() or _cast_context == null:
		return
	_skill_executor.apply_damage_node(_active_melee_node, hurt_box)
	_cast_context.publish(String(_active_melee_node.get("result_key", "melee_hit")), hurt_box)


func _get_hit_window_info(action_name: String, frame: int, requested_index: int = -1) -> Dictionary:
	if _owner == null or not _owner.has_method("get_combat_actions"):
		return {}
	var actions: Dictionary = _owner.get_combat_actions()
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	for index in range(windows.size()):
		if requested_index >= 0 and index != requested_index:
			continue
		if not windows[index] is Dictionary:
			continue
		var window: Dictionary = windows[index]
		var start_frame := int(window.get("start_frame", 0))
		var end_frame := int(window.get("end_frame", start_frame))
		if frame >= start_frame and frame <= end_frame:
			return {"window": window, "index": index}
	return {}


func _get_passed_hit_window_info(action_name: String, frame: int, requested_index: int = -1) -> Dictionary:
	if _owner == null or not _owner.has_method("get_combat_actions"):
		return {}
	var actions: Dictionary = _owner.get_combat_actions()
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	for index in range(windows.size()):
		if requested_index >= 0 and index != requested_index:
			continue
		if not windows[index] is Dictionary:
			continue
		var window: Dictionary = windows[index]
		var end_frame := int(window.get("end_frame", int(window.get("start_frame", 0))))
		if frame > end_frame:
			return {"window": window, "index": index}
	return {}


func _is_action_event_now(action_name: String, event_name: String) -> bool:
	if _sprite == null:
		return false
	var key := "%s:%s:%d" % [action_name, event_name, _sprite.frame]
	if _consumed_events.has(key):
		return false
	var action := _get_action_data(action_name)
	for value in action.get("events", []):
		if value is Dictionary and String(value.get("name", "")) == event_name and int(value.get("frame", -1)) == _sprite.frame:
			return true
	return false


func _consume_action_event(action_name: String, event_name: String) -> void:
	if _sprite != null:
		_consumed_events["%s:%s:%d" % [action_name, event_name, _sprite.frame]] = true


func _get_action_data(action_name: String) -> Dictionary:
	if _owner == null or not _owner.has_method("get_combat_actions"):
		return {}
	return (_owner.get_combat_actions() as Dictionary).get(action_name, {})


func _get_animation_duration(action_name: String) -> float:
	if _sprite == null or _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(action_name):
		return 0.5
	var frame_count := _sprite.sprite_frames.get_frame_count(action_name)
	var speed := _sprite.sprite_frames.get_animation_speed(action_name)
	if frame_count <= 0 or speed <= 0.0:
		return 0.5
	var duration := 0.0
	for frame_index in range(frame_count):
		duration += _sprite.sprite_frames.get_frame_duration(action_name, frame_index) / speed
	return maxf(0.05, duration)


func _get_socket_position(action_name: String, socket_name: String, frame: int) -> Variant:
	if socket_name.is_empty():
		return null
	var sockets: Dictionary = _get_action_data(action_name).get("sockets", {})
	var frames: Array = sockets.get(socket_name, [])
	if frames.is_empty():
		return null
	var selected: Dictionary = frames[0] if frames[0] is Dictionary else {}
	for value in frames:
		if value is Dictionary and int(value.get("frame", -1)) <= frame:
			selected = value
	var local := Vector2(float(selected.get("x", 0.0)) * _get_facing_sign(), float(selected.get("y", 0.0)))
	return (_owner as Node2D).global_position + local if _owner is Node2D else local


func _is_current_frame_armored() -> bool:
	if _sprite == null or _current_action.is_empty():
		return false
	for value in _get_action_data(_current_action).get("armor_windows", []):
		if value is Dictionary and _sprite.frame >= int(value.get("start_frame", 0)) and _sprite.frame <= int(value.get("end_frame", 0)):
			return true
	return false


func _get_facing_sign() -> float:
	return 1.0 if _sprite != null and _sprite.flip_h else -1.0
