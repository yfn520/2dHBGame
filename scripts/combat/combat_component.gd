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
# 角色受击后无敌帧计时器（0.5s），仅玩家有效；怪物受击改为瞬移后退，不加无敌
var _post_hit_iframes_timer := 0.0
const POST_HIT_IFRAMES_DURATION := 0.5
# 深渊装备代价累积器（设计案 4.3）：每秒给自己施加侵蚀 buildup
var _abyss_cost_accumulator := 0.0
# 再生特征累积器（设计案 10.1 regen）：每秒回血 2% max_hp
var _regen_accumulator := 0.0
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
# 已异步预热的特效 scene 路径集合，避免重复 ResourceLoader.load_threaded_request
var _preloaded_scenes: Dictionary = {}


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
	_skill_executor._buff_manager = _buff_manager
	# 异步预热该英雄所有技能的特效资源，避免首次释放技能时同步 load 卡顿一帧
	_preload_skill_effect_scenes()


## 扫描 _owner 的所有技能节点，对 play_effect / spawn_projectile / fullscreen_damage 引用的
## 特效 scene 异步加载（ResourceLoader.load_threaded_request），首次释放时直接从缓存命中。
## 同路径只请求一次，重复调用安全。
func _preload_skill_effect_scenes() -> void:
	if _owner == null or not _owner.has_method("get_skill_for_input"):
		return
	for slot_name in ["normal", "skill1", "skill2", "skill3"]:
		var skill_id := int(_owner.get_skill_for_input(slot_name))
		if skill_id <= 0:
			continue
		var skill: Dictionary = GameRegistry.skill_config.get_skill(skill_id)
		if skill.is_empty():
			continue
		var nodes: Array = skill.get("nodes", [])
		for node_value in nodes:
			if not (node_value is Dictionary):
				continue
			var node: Dictionary = node_value
			var scene_path := String(node.get("scene", ""))
			if scene_path.is_empty() or _preloaded_scenes.has(scene_path):
				continue
			if not ResourceLoader.exists(scene_path):
				continue
			_preloaded_scenes[scene_path] = true
			ResourceLoader.load_threaded_request(scene_path)


func _process(delta: float) -> void:
	for skill_id in _cooldowns.keys():
		_cooldowns[skill_id] = maxf(0.0, float(_cooldowns.get(skill_id, 0.0)) - delta)
	if combat_state == CombatState.DEAD:
		return
	# 深渊装备代价（设计案 4.3）：穿戴深渊装备时每秒给自己施加侵蚀 buildup
	_apply_abyss_cost(delta)
	# 再生特征（设计案 10.1 regen）：每秒回血 2% max_hp
	_apply_regen(delta)
	if _hit_stun_timer > 0.0:
		_hit_stun_timer -= delta
		if _hit_stun_timer <= 0.0 and combat_state == CombatState.HIT:
			combat_state = CombatState.IDLE
	# 角色受击后无敌帧递减
	if _post_hit_iframes_timer > 0.0:
		_post_hit_iframes_timer -= delta
		if _post_hit_iframes_timer <= 0.0:
			_post_hit_iframes_timer = 0.0
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
	if event.is_action_pressed(InputActions.ATTACK):
		_try_use_owner_skill("normal")
	elif event.is_action_pressed(InputActions.SKILL1):
		_try_use_owner_skill("skill1")
	elif event.is_action_pressed(InputActions.SKILL2):
		_try_use_owner_skill("skill2")
	elif event.is_action_pressed(InputActions.SKILL3):
		_try_use_owner_skill("skill3")


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
	if not _buff_manager.can_use_skill():
		_last_skill_attempt = "silenced"
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
	var base_cooldown := float(skill.get("cooldown", 0.0))
	var atk_speed := _get_attack_speed()
	# 技能急速：实际冷却 = 基础 / 攻速 × 100/(100+急速)（设计案 6.2 递减收益）
	var haste := _get_skill_haste()
	var haste_mult := 100.0 / (100.0 + haste) if haste > -100.0 else 1.0
	_cooldowns[skill_id] = base_cooldown / atk_speed * haste_mult if atk_speed > 0.0 else base_cooldown * haste_mult
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
		"wait_action_event", "wait_action_frame", "wait_hit_window", "wait_animation_end", "wait_time":
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
		"wait_action_frame":
			# 不依赖外部 events 配置，直接按精灵当前帧推进
			if _sprite == null:
				return false
			return _sprite.frame >= int(_waiting.get("frame", 0))
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


func _satisfy_passed_hit_window() -> void:
	# Called when the combat animation has ended before the hit window was detected.
	# Since the animation finished, all hit windows have been passed. Enter the
	# requested hit window directly so that spawn_projectile (origin="hit_window")
	# and other nodes can use _cast_context.current_anchor.
	if _owner == null or not _owner.has_method("get_combat_actions"):
		_waiting.clear()
		return
	var actions: Dictionary = _owner.get_combat_actions()
	var action: Dictionary = actions.get(_current_action, {})
	var windows: Array = action.get("hit_windows", [])
	var requested_index := int(_waiting.get("hit_window_index", -1))
	for index in range(windows.size()):
		if requested_index >= 0 and index != requested_index:
			continue
		if windows[index] is Dictionary:
			_enter_hit_window({"window": windows[index], "index": index})
			_waiting.clear()
			return
	# No matching hit window found; still clear the wait and set a fallback anchor
	if _owner is Node2D:
		_cast_context.current_anchor = (_owner as Node2D).global_position
	_waiting.clear()


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
	var delay_ms := maxi(0, int(node.get("delay_ms", 0)))
	if delay_ms > 0:
		var scheduled := node.duplicate(true)
		scheduled["delay_ms"] = 0
		get_tree().create_timer(float(delay_ms) / 1000.0).timeout.connect(_execute_delayed_effect_node.bind(scheduled), CONNECT_ONE_SHOT)
		return
	var targets := _skill_executor.resolve_targets(node, _resolve_origin(node), _cast_context)
	if not targets.is_empty():
		for target in targets:
			_spawn_effect_on_target(target, node)
		return
	_spawn_effect_at(_resolve_origin(node), node)


func _execute_delayed_effect_node(node: Dictionary) -> void:
	if _owner == null or not is_instance_valid(_owner) or combat_state == CombatState.DEAD:
		return
	_execute_effect_node(node)


func _execute_target_buff_node(node: Dictionary) -> void:
	var target_mode := String(node.get("target", "result"))
	if target_mode == "result" or target_mode == "last_result":
		_cast_context.subscribe(String(node.get("result_key", "last_result")), Callable(self, "_apply_buff_to_target").bind(node.duplicate(true)), String(node.get("delivery", "each_hit")))
		return
	var origin := _resolve_origin(node)
	var targets := _skill_executor.resolve_targets(node, origin, _cast_context)
	for target in targets:
		_apply_buff_to_target(target, node)


func _spawn_effect_on_target(target: Area2D, node: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var delay_ms := maxi(0, int(node.get("delay_ms", 0)))
	if delay_ms > 0:
		var scheduled := node.duplicate(true)
		scheduled["delay_ms"] = 0
		get_tree().create_timer(float(delay_ms) / 1000.0).timeout.connect(_spawn_effect_on_target.bind(target, scheduled), CONNECT_ONE_SHOT)
		return
	# target 通常是受击者的 HurtBox；真正要挂载的角色/怪物节点存在 _owner_entity 上。
	# 透传给 _spawn_effect_at，使 character_local 模式下的 attachment 能挂到被击者身上。
	var target_owner: Node = target.get("_owner_entity") if "_owner_entity" in target else null
	_spawn_effect_at(target.global_position, node, target_owner)

## 在指定位置生成特效。
## target_owner 仅在 coordinate_space == "character_local" 且为 Node2D 时生效：
## 优先把 attachment 挂到 target_owner（被击者），否则回落到 _owner（施法者）。
## 这保证了"弹道命中后挂受击特效"可以挂到被击者身上，跟随被击者移动并按其朝向镜像。
func _spawn_effect_at(position_value: Vector2, node: Dictionary, target_owner: Node = null) -> void:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var effect := packed.instantiate()
	var offset := Vector2(float(node.get("offset_x", 0.0)), float(node.get("offset_y", 0.0)))
	var coord_space := String(node.get("coordinate_space", "world"))
	if coord_space == "character_local" and not bool(node.get("follow_target", true)):
		coord_space = "world"
	_apply_imported_effect_transform(effect, node)

	# 全屏特效：挂到 UIRoot 的 ScreenLayer，按 cover 模式铺满 viewport，单次播放后自动销毁。
	# 忽略 offset 和 visual_scale（运行时按 viewport 自适应），不受相机移动影响。
	if coord_space == "fullscreen":
		_spawn_fullscreen_effect(effect, node)
		return

	var scene := _owner.get_tree().current_scene if _owner != null and _owner.get_tree() != null else null

	# 选定挂载根：character_local 模式下优先挂到被击者（target_owner），
	# 没有则回落到施法者（_owner）。其余模式下挂到当前场景根。
	var attach_root: Node2D = null
	if coord_space == "character_local":
		if target_owner != null and target_owner is Node2D:
			attach_root = target_owner as Node2D
		elif _owner is Node2D:
			attach_root = _owner as Node2D

	# visual_scale 与朝向镜像都按挂载根计算，使 attachment 与被挂者尺寸/朝向一致。
	# attach_root 为 null（world 坐标）时回落到施法者 _owner 的视觉缩放，保持原行为。
	var scale_root: Node2D = attach_root if attach_root != null else (_owner as Node2D if _owner is Node2D else null)
	var attach_sprite: AnimatedSprite2D = null
	if scale_root != null:
		attach_sprite = scale_root.get_node_or_null("CharacterActionSet/AnimatedSprite2D") as AnimatedSprite2D
	var visual_root := scale_root.get_node_or_null("CharacterActionSet") as Node2D if scale_root != null else null
	var visual_scale := absf(visual_root.scale.x) if visual_root != null and not is_zero_approx(visual_root.scale.x) else 1.0

	if effect is Node2D and coord_space == "character_local" and attach_root != null:
		# Action attachments use frame-pixel coordinates relative to the character foot.
		# Keep them parented to the actor so they follow movement, and mirror exactly when
		# the attach root sprite is flipped.
		var effect_node := effect as Node2D
		offset += _resolve_effect_anchor_offset(node, attach_root)
		var mirror_enabled := bool(node.get("mirror_with_facing", true))
		var mirror_x := -1.0 if mirror_enabled and attach_sprite != null and attach_sprite.flip_h else 1.0
		attach_root.add_child(effect_node)
		effect_node.position = Vector2(offset.x * mirror_x * visual_scale, offset.y * visual_scale)
		effect_node.scale = effect_node.scale * Vector2(visual_scale, visual_scale)
		if effect_node is AnimatedSprite2D and mirror_enabled and attach_sprite != null:
			# 效果场景可烘焙水平镜像（flip_h），与挂载根朝向取异或，使特效内部镜像独立于挂载根朝向。
			(effect_node as AnimatedSprite2D).flip_h = (effect_node as AnimatedSprite2D).flip_h != attach_sprite.flip_h
		elif mirror_x < 0.0:
			effect_node.scale.x *= -1.0
		# The character visuals are a sibling at z=100 in imported actor scenes.
		# Resolve front/behind relative to that node rather than relative to the world root.
		var visual_z := visual_root.z_index if visual_root != null else (attach_sprite.z_index if attach_sprite != null else 0)
		var attachment_layer := String(node.get("attachment_layer", "front"))
		effect_node.z_as_relative = true
		effect_node.z_index = visual_z + (-1 if attachment_layer == "behind" else 1)
		_schedule_imported_effect_lifetime(effect_node, node)
		return
	if scene == null:
		effect.queue_free()
		return
	scene.add_child(effect)
	if effect is Node2D:
		# World-space effects: 同样应用挂载根视觉缩放，使特效大小与角色缩放一致
		# tscn 中烘焙的 position（来自 GameTool 的 spawnOffset）作为附加偏移，
		# 与技能节点的 offset_x/offset_y 叠加，使设计期偏移在运行时生效。
		var baked_offset := (effect as Node2D).position
		(effect as Node2D).global_position = position_value + (offset + baked_offset) * visual_scale
		(effect as Node2D).scale *= Vector2(visual_scale, visual_scale)
		_schedule_imported_effect_lifetime(effect as Node2D, node)


func _apply_imported_effect_transform(effect: Node, node: Dictionary) -> void:
	if effect is not Node2D:
		return
	var effect_node := effect as Node2D
	var authored_scale := clampf(float(node.get("effect_scale", 1.0)), 0.05, 12.0)
	effect_node.scale *= Vector2(authored_scale, authored_scale)
	effect_node.rotation += deg_to_rad(float(node.get("rotation_degrees", 0.0)))
	var tint := Color.from_string(String(node.get("tint", "#ffffff")), Color.WHITE)
	tint.a *= clampf(float(node.get("opacity", 1.0)), 0.0, 1.0)
	effect_node.modulate *= tint


func _resolve_effect_anchor_offset(node: Dictionary, attach_root: Node2D) -> Vector2:
	var anchor := String(node.get("anchor", "origin"))
	if anchor == "origin" or anchor == "foot":
		return Vector2.ZERO
	if anchor == "body_center" and attach_root.has_method("get_body_center_y"):
		return Vector2(0.0, float(attach_root.get_body_center_y()))
	if attach_root != _owner:
		return Vector2.ZERO
	var socket_name := String(node.get("socket", anchor))
	var socket_position: Variant = _get_socket_position(_current_action, socket_name, _sprite.frame if _sprite != null else 0)
	if socket_position is Vector2:
		return (socket_position as Vector2) - attach_root.global_position
	return Vector2.ZERO


func _schedule_imported_effect_lifetime(effect: Node2D, node: Dictionary) -> void:
	var lifetime_ms := int(node.get("lifetime_ms", 0))
	if lifetime_ms <= 0 or effect.get_tree() == null:
		return
	effect.get_tree().create_timer(float(lifetime_ms) / 1000.0).timeout.connect(effect.queue_free, CONNECT_ONE_SHOT)


## 全屏特效：挂到 UIRoot 的 ScreenLayer（z=20），按 cover 模式铺满 viewport。
## 单次播放完成后自动 queue_free；循环特效按 node.duration（秒）销毁，缺省 2.0 秒。
func _spawn_fullscreen_effect(effect: Node, node: Dictionary) -> void:
	if effect is not Node2D:
		effect.queue_free()
		return
	var effect_node := effect as Node2D
	# 通过 group 查找 UIRoot（UIRoot 是 GameRoot 的子节点，不是 tree.root 的直接子节点）
	# 用 group 避免依赖层级结构，任意嵌套位置都能找到
	var tree := _owner.get_tree() if _owner != null else null
	if tree == null:
		effect_node.queue_free()
		return
	var ui_root := tree.get_first_node_in_group("ui_root") as UIRoot
	if ui_root == null or ui_root.get_screen_layer() == null:
		# 回落：找不到 UIRoot 时挂到 current_scene，但会受相机影响（仅作兜底）
		if tree.current_scene != null:
			tree.current_scene.add_child(effect_node)
		else:
			effect_node.queue_free()
			return
	else:
		ui_root.get_screen_layer().add_child(effect_node)
	# 计算 cover 缩放：取 viewport 尺寸与特效首帧尺寸的较大比例
	var viewport_size := get_viewport().get_visible_rect().size
	# 读特效首帧尺寸：AnimatedSprite2D 的 sprite_frames 首帧纹理
	var frame_size := Vector2(viewport_size)
	if effect_node is AnimatedSprite2D:
		var sprite := effect_node as AnimatedSprite2D
		var frames := sprite.sprite_frames
		if frames != null and frames.has_animation(sprite.animation):
			var anim_frames := frames.get_frame_count(sprite.animation)
			if anim_frames > 0:
				var tex := frames.get_frame_texture(sprite.animation, 0)
				if tex != null:
					frame_size = tex.get_size()
	# CanvasLayer 子节点坐标系：左上角为原点，position = viewport 中心
	# ScreenLayer 默认 follow_viewport_enabled=false，不受相机影响，特效始终居中
	effect_node.position = viewport_size * 0.5
	var cover_scale := maxf(viewport_size.x / frame_size.x, viewport_size.y / frame_size.y)
	effect_node.scale = Vector2(cover_scale, cover_scale)
	# 自动销毁：循环特效按 duration，单次按 animation_finished
	var is_loop := false
	if effect_node is AnimatedSprite2D:
		var frames2 := (effect_node as AnimatedSprite2D).sprite_frames
		if frames2 != null and frames2.has_animation((effect_node as AnimatedSprite2D).animation):
			is_loop = frames2.get_animation_loop((effect_node as AnimatedSprite2D).animation)
	if is_loop:
		var duration := float(node.get("duration", 2.0))
		# 用 SceneTreeTimer 延迟销毁，不阻塞技能流程
		var timer := get_tree().create_timer(duration)
		timer.timeout.connect(effect_node.queue_free)
	else:
		if effect_node is AnimatedSprite2D:
			(effect_node as AnimatedSprite2D).animation_finished.connect(effect_node.queue_free)
		else:
			# 非 AnimatedSprite2D 无法监听完成，回落到 2 秒销毁
			var timer2 := get_tree().create_timer(2.0)
			timer2.timeout.connect(effect_node.queue_free)


func _apply_buff_to_target(target: Area2D, node: Dictionary) -> void:
	_skill_executor.apply_target_buff(node, target)


func _execute_heal_node(node: Dictionary) -> void:
	var amount := int(node.get("amount", 0))
	if amount <= 0:
		amount = _skill_executor.calculate_damage(float(node.get("ratio", 0.0)))
	# 技能 heal 节点：施疗者=自身，传入自身 stats 供 heal() 读 heal_bonus
	heal(amount, _stats)


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
		var base_pos := (_owner as Node2D).global_position
		# 抬到身体中心：读 HurtBox/CollisionShape2D.position.y（角色根坐标系，负值）
		if _owner.has_method("get_body_center_y"):
			return base_pos + Vector2(0.0, _owner.get_body_center_y())
		return base_pos
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


func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true, damage_result: Dictionary = {}) -> void:
	_resolve_stats()
	# 无敌判定：死亡 / buff 控制（冰冻等） / 角色受击后无敌帧（0.5s）
	if combat_state == CombatState.DEAD or _stats == null or _buff_manager.is_invincible():
		return
	if _post_hit_iframes_timer > 0.0:
		return
	# 闪避成功：不造成伤害和命中类异常积累（设计案 5.7）
	if damage_result.has("dodged") and bool(damage_result.get("dodged", false)):
		_play_dodge_reaction()
		return
	if play_hit_reaction and not _is_current_frame_armored():
		cancel_cast("hit")
	# 护盾吸收（设计案 7.2：护盾承受最终伤害）
	amount = _buff_manager.modify_damage(amount)
	if amount <= 0:
		return
	# 新链路（damage_result 非空）：amount 已是最终伤害，跳过 defense 减法
	# 旧链路（damage_result 为空）：做 defense 减法兼容
	var actual := amount
	if damage_result.is_empty():
		var defense := _get_defense()
		actual = maxi(1, amount - int(defense))
	_stats.hp = maxi(0, _stats.hp - actual)
	if _owner.has_method("sync_combat_hp"):
		_owner.sync_combat_hp()
	if play_hit_reaction and _stats.hp > 0:
		# 格挡反应优先于普通受击
		if damage_result.has("blocked") and bool(damage_result.get("blocked", false)):
			_play_block_reaction()
		else:
			combat_state = CombatState.HIT
			_hit_stun_timer = 0.15
			# 怪物受击：瞬移后退 12px（无无敌帧，可被连续命中）
			# 角色受击：不后退，但获得 0.5s 无敌帧避免连续受击
			if _owner != null and _owner.is_in_group("enemies"):
				_apply_hit_knockback(source)
			elif _owner != null and _owner.is_in_group("player"):
				_post_hit_iframes_timer = POST_HIT_IFRAMES_DURATION
	hp_changed.emit(_stats.hp, _stats.max_hp)
	took_damage.emit(actual, source)
	# 反伤（设计案 7.4）：实际受伤后回调攻击者，上限 8% 攻击者最大生命
	_apply_reflect_damage(actual, source)
	if _stats.hp <= 0:
		_die()
	elif play_hit_reaction and _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("hit")


## 反伤结算（设计案 7.4）。
## 反伤率 = max(自身 reflect_rate, buff 修饰后)，反伤量 = actual × 反伤率
## 上限 = 8% × 攻击者最大生命（防止小怪反死高血量玩家）
## 反伤不触发命中类异常积累、不再触发反伤（避免无限循环）
func _apply_reflect_damage(actual: int, source: Node) -> void:
	if actual <= 0 or source == null or not is_instance_valid(source):
		return
	if not source.has_method("take_damage"):
		return
	var reflect_rate := float(_stats.reflect_rate) if "reflect_rate" in _stats else 0.0
	if _buff_manager != null:
		reflect_rate = _buff_manager.get_modified_stat("reflect_rate", reflect_rate)
	reflect_rate = clampf(reflect_rate, 0.0, 0.5)
	if reflect_rate <= 0.0:
		return
	var reflect := int(roundi(float(actual) * reflect_rate))
	if reflect <= 0:
		return
	# 上限：8% × 攻击者最大生命
	var source_max_hp := 0
	if source.has_method("get_combat_stats"):
		var source_stats = source.get_combat_stats()
		if source_stats != null and "max_hp" in source_stats:
			source_max_hp = int(source_stats.max_hp)
	if source_max_hp > 0:
		var cap := int(roundi(float(source_max_hp) * 0.08))
		reflect = mini(reflect, cap)
	if reflect > 0:
		# 反伤为真实通道（不被防御减免），不触发反伤循环（source=_owner 避免再次反伤）
		# damage_result 标记 channel=true 让 take_damage 走新链路跳过 defense 减法
		source.take_damage(reflect, _owner, false, {"damage": reflect, "channel": "true"})


## 受击瞬移：往后退一小段距离（约 12px）。
## source 为空时（如 DoT）朝当前朝向反方向退。
func _apply_hit_knockback(source: Node) -> void:
	if _owner == null:
		return
	var dir := Vector2.ZERO
	if source != null and is_instance_valid(source):
		dir = (_owner.global_position - source.global_position).normalized()
	if dir == Vector2.ZERO:
		var facing: float = 1.0
		if _owner.has_method("get_facing_sign"):
			facing = float(_owner.get_facing_sign())
		dir = Vector2(-facing, 0.0)
	_owner.global_position += dir * 12.0


## 深渊装备代价（设计案 4.3）。
## 穿戴深渊装备时 abyss_cost > 0，每秒给自己施加侵蚀 buildup。
## 自己攻击自己（source=_owner），buildup 公式与正常一致。
func _apply_abyss_cost(delta: float) -> void:
	if _stats == null or not "abyss_cost" in _stats:
		return
	var cost := float(_stats.abyss_cost)
	if cost <= 0.0:
		return
	_abyss_cost_accumulator += delta
	if _abyss_cost_accumulator < 1.0:
		return
	# 每秒施加一次
	_abyss_cost_accumulator = 0.0
	if _buff_manager != null and _buff_manager.has_method("apply_status_buildup"):
		_buff_manager.apply_status_buildup("erosion", cost, 0.0, _owner)


## 再生特征（设计案 10.1 regen）。
## 每秒回血 2% max_hp，不触发 heal_bonus/heal_received（视为被动恢复）。
func _apply_regen(delta: float) -> void:
	if _stats == null or not "traits" in _stats:
		return
	if not _stats.traits.has("regen"):
		return
	_regen_accumulator += delta
	if _regen_accumulator < 1.0:
		return
	_regen_accumulator = 0.0
	var regen_amount := int(roundi(float(_stats.max_hp) * 0.02))
	if regen_amount > 0 and _stats.hp < _stats.max_hp:
		_stats.hp = mini(_stats.max_hp, _stats.hp + regen_amount)
		if _owner.has_method("sync_combat_hp"):
			_owner.sync_combat_hp()
		hp_changed.emit(_stats.hp, _stats.max_hp)


## 闪避反应（设计案 5.7）。P0 仅做状态切换，后续可扩展动画。
func _play_dodge_reaction() -> void:
	if _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("dodge")


## 格挡反应（设计案 5.7）。P0 仅做状态切换，后续可扩展动画。
func _play_block_reaction() -> void:
	if _owner.has_method("play_combat_animation"):
		_owner.play_combat_animation("block")


## 治疗（设计案 7.1）。
## amount: 基础治疗量（HoT 传 effect.heal，技能 heal 节点传 amount）
## healer_stats: 施疗者 stats（用于读取 heal_bonus 施疗者侧乘区）。
##   传 null 时按自疗处理，读取自身 heal_bonus。
## 最终治疗 = amount × (1 + 施疗者 heal_bonus) × max(0.2, 1 + 目标 heal_received)
func heal(amount: int, healer_stats = null) -> void:
	_resolve_stats()
	if _stats == null:
		return
	# 施疗者侧：治疗强度 heal_bonus（加算乘区）
	var heal_bonus := 0.0
	if healer_stats != null and "heal_bonus" in healer_stats:
		heal_bonus = float(healer_stats.heal_bonus)
	elif _buff_manager != null:
		# 自疗或未传施疗者：读取自身 heal_bonus
		heal_bonus = _buff_manager.get_modified_stat("heal_bonus", float(_stats.heal_bonus) if "heal_bonus" in _stats else 0.0)
	var base := float(amount) * (1.0 + heal_bonus)
	# 目标侧：受疗加成 heal_received（负值=重伤削弱，正值=增强），保底 20%
	var heal_mult := 1.0
	if _buff_manager != null:
		heal_mult = 1.0 + _buff_manager.get_modified_stat("heal_received", 0.0)
	heal_mult = maxf(0.2, heal_mult)
	var actual := int(roundi(base * heal_mult))
	_stats.hp = mini(_stats.max_hp, _stats.hp + maxi(0, actual))
	if _owner.has_method("sync_combat_hp"):
		_owner.sync_combat_hp()
	hp_changed.emit(_stats.hp, _stats.max_hp)


func apply_buff_from_config(config: Dictionary, source: int = 0) -> void:
	_buff_manager.apply_buff(config, source)
	# 控制效果打断施法
	var effects: Array = config.get("effects", [])
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "control":
			var affects: Array = effect.get("affects", [])
			if "act" in affects or "skill" in affects:
				cancel_cast(String(effect.get("control_type", "control")))
				break


func get_buff_manager() -> BuffManager:
	return _buff_manager


func _get_attack_speed() -> float:
	if _stats == null or not ("attack_speed" in _stats):
		return 1.0
	var base_as := float(_stats.attack_speed)
	return _buff_manager.get_modified_stat("attack_speed", base_as)


## 技能急速（设计案 6.2）。buff 可修饰 skill_haste。
func _get_skill_haste() -> float:
	if _stats == null or not ("skill_haste" in _stats):
		return 0.0
	var base_haste := float(_stats.skill_haste)
	if _buff_manager == null:
		return base_haste
	return _buff_manager.get_modified_stat("skill_haste", base_haste)


func _get_defense() -> float:
	if _stats == null or not ("defense" in _stats):
		return 0.0
	return _buff_manager.get_modified_stat("defense", float(_stats.defense))


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
		var wait_type := String(_waiting.get("type", ""))
		# play_combat_animation 内部调用 sprite.stop() 会在动画切换前触发 frame_changed，
		# 此时 _waiting 为空（play_animation 节点仍在执行中），不应取消施放。
		if wait_type.is_empty():
			return
		if wait_type == "wait_animation_end":
			_animation_finished = true
			_advance_cast()
			return
		# Timer-based waits should not be cancelled by animation changes
		if wait_type == "wait_time" or wait_type == "wait_time_done":
			return
		# Animation has finished, so any hit window or action event has been passed.
		# Satisfy the wait instead of cancelling the cast, otherwise spawn_projectile
		# and play_effect nodes after the wait would be silently skipped.
		if wait_type == "wait_hit_window":
			_satisfy_passed_hit_window()
			_advance_cast()
			return
		if wait_type == "wait_action_event":
			_waiting.clear()
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
