class_name DialogueService
extends Node

signal dialogue_started(npc_id: int)
signal node_changed(node: Dictionary)
signal dialogue_finished(npc_id: int, completed: bool)
signal intent_selected(npc_id: int, dialogue_id: String, choice_id: String, intent_key: String)

var npc_config: NpcConfig
var dialogue_config: DialogueConfig
var quest_service: QuestService
var inventory: InventoryProvider

var current_npc_id := 0
var current_dialogue_id := ""
var current_node_id := ""
var _active := false
# 任务对话触发：命中 quest authoring.dialogue_id 时记录对话结束后要执行的任务动作
var _pending_quest_action: Dictionary = {}
# 过场自动播放：line 节点定时自动推进，choice 节点停下等输入；代际令牌使旧定时器失效
var _auto_advance := false
var _auto_gen := 0
# 当前对话是否为过场（UI 据此用纯黑背景遮住主界面）
var _cutscene := false
# 时间轴播放状态（timeline 格式对话）
var _timeline_mode := false
var _timeline: Dictionary = {}
var _tl_clips: Array = []
var _tl_idx := 0
var _tl_current: Dictionary = {}
var _tl_gate: Dictionary = {}
var _tl_gate_gen := 0
# 手动任务对白已经播过当前交互 NPC 后，遇到下一位 NPC 时收束本次对话。
# 过场不启用，避免 C1-01-B 的公共开场把柏婶/霍雷克对白截断。
var _tl_segment_speaker_seen := false


func setup(p_npc_config: NpcConfig, p_dialogue_config: DialogueConfig, p_quest_service: QuestService, p_inventory: InventoryProvider) -> void:
	npc_config = p_npc_config
	dialogue_config = p_dialogue_config
	quest_service = p_quest_service
	inventory = p_inventory
	if quest_service != null and not quest_service.objective_completed.is_connected(_on_objective_completed):
		quest_service.objective_completed.connect(_on_objective_completed)
	if quest_service != null:
		if not quest_service.quest_ready.is_connected(_on_tl_quest_signal):
			quest_service.quest_ready.connect(_on_tl_quest_signal)
		if not quest_service.quest_completed.is_connected(_on_tl_quest_signal):
			quest_service.quest_completed.connect(_on_tl_quest_signal)


func start_dialogue(npc_id: int) -> bool:
	if _active:
		return false
	var npc := npc_config.get_npc(npc_id)
	if npc.is_empty():
		push_warning("NPC 不存在: %d" % npc_id)
		return false
	# 优先播放任务剧情对话（quest authoring.dialogue_id）：交付(ready) > 进行中目标对话(active) > 接取(inactive 且已解锁)
	var quest_hook := _find_quest_dialogue_hook(npc_id)
	if not quest_hook.is_empty():
		var quest_dialogue_id := str(quest_hook.get("dialogue_id", ""))
		# 时间轴格式任务对话：从该 NPC 的时间入口进入
		if not dialogue_config.get_timeline(quest_dialogue_id).is_empty():
			return _start_timeline(quest_dialogue_id, npc_id, dialogue_config.get_timeline_entry_ms(quest_dialogue_id, str(npc_id)), false, false, quest_hook)
		push_warning("TaskScript dialogue is not timeline format: %s" % quest_dialogue_id)
		return false
	var dialogue_id := str(npc.get("dialogue_id", ""))
	if not dialogue_config.get_timeline(dialogue_id).is_empty():
		return _start_timeline(dialogue_id, npc_id, 0, false, false)
	push_warning("NPC dialogue is not timeline format: %s" % dialogue_id)
	return false


## 过场播放：不依赖 NPC/任务钩子直接播对话图（npc_id 可为 0），进入自动推进模式。
## cinematic=true 时用纯黑背景（仅开局选角）；任务过场用半透背景保留场景画面。
func start_cutscene(dialogue_id: String, npc_id: int = 0, cinematic: bool = false) -> bool:
	if _active:
		return false
	if not dialogue_config.get_timeline(dialogue_id).is_empty():
		return _start_timeline(dialogue_id, npc_id, 0, true, cinematic)
	push_warning("Cutscene dialogue is not timeline format: %s" % dialogue_id)
	return false


func is_cutscene() -> bool:
	return _active and _cutscene


## 是否处于过场播放（含开局选角与任务过场）：UI 据此隐藏主 HUD。
func is_auto_cutscene() -> bool:
	return _active and _auto_advance


func _find_quest_dialogue_hook(npc_id: int) -> Dictionary:
	if quest_service == null or quest_service.config == null or dialogue_config == null:
		return {}
	var starters: Array[Dictionary] = []
	for quest_id_value in quest_service.config.get_all_quests():
		var quest: Dictionary = quest_service.config.get_quest(int(quest_id_value))
		var dialogue_id := str((quest.get("authoring", {}) as Dictionary).get("dialogue_id", ""))
		if dialogue_id.is_empty() or dialogue_config.get_dialogue(dialogue_id).is_empty():
			continue
		var quest_id := int(quest_id_value)
		# 交付优先：任务 ready 且本 NPC 是交付人。
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and quest_service.get_status(quest_id) == "ready":
			return {"quest_id": quest_id, "action": "turn_in_quest", "dialogue_id": dialogue_id, "entry_ms": dialogue_config.get_timeline_entry_ms(dialogue_id, str(npc_id))}
		# 进行中：本 NPC 是未完成的 talk 目标 → 播该 NPC 段（等待态的"事件通知"由对话收尾推进）
		if quest_service.get_status(quest_id) == "active" and _has_pending_talk_objective(quest, npc_id):
			return {"quest_id": quest_id, "action": "advance_talk", "dialogue_id": dialogue_id, "entry_ms": dialogue_config.get_timeline_entry_ms(dialogue_id, str(npc_id))}
		if int(quest.get("giver_npc_id", 0)) == npc_id and quest_service.get_status(quest_id) == "inactive" and quest_service.is_quest_unlocked(quest_id):
			starters.append({"quest_id": quest_id, "action": "start_quest", "dialogue_id": dialogue_id, "entry_ms": dialogue_config.get_timeline_entry_ms(dialogue_id, str(npc_id))})
	return starters[0] if not starters.is_empty() else {}


## 任务进行中，该 NPC 是否还有未完成的 talk 目标（用于 active 状态的目标对话钩子）
func _has_pending_talk_objective(quest: Dictionary, npc_id: int) -> bool:
	var quest_id := int(quest.get("id", 0))
	var objectives: Array = quest.get("objectives", [])
	for index in range(objectives.size()):
		if not objectives[index] is Dictionary:
			continue
		var objective: Dictionary = objectives[index]
		if str(objective.get("type", "")) == "talk" and int(objective.get("npc_id", 0)) == npc_id:
			if not bool(quest_service.get_objective_progress(quest_id, objective, index).get("complete", false)):
				return true
	return false


func advance() -> void:
	if not _active:
		return
	if _timeline_mode:
		_auto_gen += 1
		if not _tl_current.is_empty() and not _tl_current.get("choices", []).is_empty():
			return
		_tl_gate = {}
		_tl_tick()
		return
	push_warning("当前对话不是 timeline 格式，无法推进")


func choose(index: int) -> void:
	if _timeline_mode:
		_auto_gen += 1
		var visible := get_visible_choices()
		if index < 0 or index >= visible.size():
			return
		var choice: Dictionary = visible[index]
		_execute_actions(choice.get("actions", []))
		var next_clip_id := str(choice.get("nextClipId", ""))
		if not next_clip_id.is_empty():
			for clip_index in range(_tl_clips.size()):
				if str((_tl_clips[clip_index] as Dictionary).get("id", "")) == next_clip_id:
					_tl_idx = clip_index
					break
		_tl_current = {}
		_tl_tick()
		return
	push_warning("当前对话不是 timeline 格式，无法选择")


func get_current_node() -> Dictionary:
	return _tl_current.duplicate(true) if _timeline_mode else {}


func get_visible_choices(node: Dictionary = {}) -> Array[Dictionary]:
	if node.is_empty():
		# 时间轴内部保存的是原始 clip（options），UI 收到的是合成后的旧节点形状（choices）。
		# 点击按钮时没有传 node，必须先把当前 clip 合成为可选项，否则会误判为空并直接返回。
		node = _tl_synthesize_node(_tl_current) if not _tl_current.is_empty() else {}
	var result: Array[Dictionary] = []
	for value in node.get("choices", []):
		if value is Dictionary and _conditions_pass(value.get("conditions", [])) and not _is_current_protagonist_choice(value):
			result.append(value)
	return result


func _is_current_protagonist_choice(choice: Dictionary) -> bool:
	if quest_service == null or quest_service.roster == null:
		return false
	var choice_hero_id := 0
	match str(choice.get("intent_key", "")):
		"select_second_leon": choice_hero_id = 7001
		"select_second_luna": choice_hero_id = 7002
		"select_second_mia": choice_hero_id = 7003
	return choice_hero_id > 0 and choice_hero_id == quest_service.roster.get_protagonist_hero_id()


func _can_dispatch_intent(intent_key: String) -> bool:
	if quest_service == null or GameRegistry.interaction_binding_config == null:
		return true
	var binding: Dictionary = GameRegistry.interaction_binding_config.get_binding(current_dialogue_id, intent_key)
	match str(binding.get("type", "")):
		"start_quest":
			var quest_id := int(binding.get("quest_id", 0))
			return quest_service.get_status(quest_id) == "inactive" and quest_service.is_quest_unlocked(quest_id)
		"turn_in_quest":
			return quest_service.get_status(int(binding.get("quest_id", 0))) == "ready"
	return true


func is_active() -> bool:
	return _active


func finish(completed: bool = false) -> void:
	if not _active:
		return
	var npc_id := current_npc_id
	_active = false
	_auto_advance = false
	_cutscene = false
	_auto_gen += 1
	_timeline_mode = false
	_timeline = {}
	_tl_clips = []
	_tl_idx = 0
	_tl_current = {}
	_tl_gate = {}
	_tl_gate_gen += 1
	_tl_segment_speaker_seen = false
	if completed and quest_service != null:
		quest_service.record_talk(npc_id)
		# 任务剧情对话正常结束后执行接取/交付
		if not _pending_quest_action.is_empty():
			var quest_id := int(_pending_quest_action.get("quest_id", 0))
			match str(_pending_quest_action.get("action", "")):
				"start_quest":
					if quest_service.get_status(quest_id) == "inactive":
						quest_service.start_quest(quest_id)
				"turn_in_quest":
					if quest_service.get_status(quest_id) == "ready":
						quest_service.turn_in_quest(quest_id)
				"advance_talk":
					# 目标对话收尾：talk 已在上面 record_talk 推进；若任务因此刚 ready
					# 且本 NPC 就是交付人（如仓库看守领取+交付连播），当场交付完成
					var quest := quest_service.config.get_quest(quest_id)
					if quest_service.get_status(quest_id) == "ready" and int(quest.get("turn_in_npc_id", 0)) == npc_id:
						quest_service.turn_in_quest(quest_id)
	_pending_quest_action = {}
	current_node_id = ""
	dialogue_finished.emit(npc_id, completed)


func _conditions_pass(raw: Variant) -> bool:
	if not raw is Array:
		return true
	for value in raw:
		if value is Dictionary and (quest_service == null or not quest_service.evaluate_condition(value)):
			return false
	return true


func _execute_actions(raw: Variant) -> void:
	if not raw is Array:
		return
	for value in raw:
		if not value is Dictionary:
			continue
		match str(value.get("type", "")):
			"set_flag":
				quest_service.state.set_flag(str(value.get("flag", "")), value.get("value", true))
			"start_quest":
				quest_service.start_quest(int(value.get("quest_id", 0)))
			"give_item":
				if inventory != null:
					inventory.add_item(int(value.get("item_id", 0)), maxi(1, int(value.get("count", 1))))
			"set_protagonist":
				# 序章三选一：写入存档级主角标记并立即落盘；
				# hero_id<=0 为“跳过选角”，兜底用当前上场角色（gameroot 场景配置的默认主角）。
				if quest_service != null and quest_service.roster != null:
					var hero_id := int(value.get("hero_id", 0))
					if hero_id <= 0:
						hero_id = int(quest_service.roster.active_character_id)
					if hero_id <= 0:
						hero_id = 7002
					quest_service.roster.set_protagonist(hero_id)
					quest_service.state.set_flag("LeadHero", hero_id)
					quest_service.state.set_flag("PartyStage", "Solo")
					if GameRegistry.chapter_service != null:
						GameRegistry.chapter_service.complete_chapter_normal("prologue")
					GameRegistry.save_game()
			"set_second_hero", "recruit_hero":
				if quest_service != null and quest_service.roster != null:
					var hero_id := int(value.get("hero_id", 0))
					if hero_id != quest_service.roster.get_protagonist_hero_id():
						quest_service.roster.recruit_hero(hero_id, true)
						quest_service.state.set_flag("SecondHero", hero_id)
						quest_service.state.set_flag("PartyStage", "Duo")
						GameRegistry.save_game()
			"complete_chapter":
				var chapter_id := str(value.get("chapter_id", ""))
				if not chapter_id.is_empty() and GameRegistry.chapter_service != null:
					GameRegistry.chapter_service.complete_chapter_normal(chapter_id)
					GameRegistry.save_game()
			"actor_move":
				_execute_actor_move(value)
			"actor_animation":
				_execute_actor_animation(value)
			"actor_visibility":
				_execute_actor_visibility(value)
			"close_dialogue":
				call_deferred("finish", true)
			"":
				pass
			_:
				push_warning("未知对话动作: %s" % value.get("type", ""))


# === 时间轴播放（timeline 格式对话） ===

func _story_actor_matches(actor: Node, action: Dictionary) -> bool:
	var actor_kind := str(action.get("actor_kind", "npc"))
	if actor_kind == "player" or actor_kind == "hero":
		if not actor.is_in_group("player"):
			return false
	else:
		if not actor.is_in_group("npc_actor"):
			return false
	var instance_id := str(action.get("instance_id", "")).strip_edges()
	if not instance_id.is_empty() and str(actor.get("instance_id")) != instance_id:
		return false
	var actor_id := int(action.get("actor_id", 0))
	if actor_id > 0:
		if actor_kind == "hero":
			if actor.has_method("get_party_character_id") and int(actor.call("get_party_character_id")) != actor_id:
				return false
		elif int(actor.get("npc_id")) != actor_id:
			return false
	return true


func _resolve_story_actor(action: Dictionary) -> Node:
	var actor_kind := str(action.get("actor_kind", "npc"))
	var group_name := "player" if actor_kind == "player" or actor_kind == "hero" else "npc_actor"
	for actor in get_tree().get_nodes_in_group(group_name):
		if actor is Node and _story_actor_matches(actor, action):
			return actor
	return null


func _execute_actor_move(action: Dictionary) -> void:
	var actor := _resolve_story_actor(action)
	if actor == null:
		push_warning("动作轨道找不到移动目标: %s" % action)
		return
	var target := Vector2(float(action.get("x", actor.global_position.x)), float(action.get("y", actor.global_position.y)))
	var duration_ms := maxi(0, int(action.get("duration_ms", 0)))
	if action.has("from_x") and action.has("from_y"):
		actor.global_position = Vector2(float(action.get("from_x", actor.global_position.x)), float(action.get("from_y", actor.global_position.y)))
	if duration_ms == 0:
		actor.global_position = target
	elif actor.has_method("move_story_to"):
		actor.call("move_story_to", target, duration_ms)
	else:
		var tween := actor.create_tween()
		tween.tween_property(actor, "global_position", target, float(duration_ms) / 1000.0)


func _execute_actor_animation(action: Dictionary) -> void:
	var actor := _resolve_story_actor(action)
	if actor == null:
		push_warning("动作轨道找不到动画目标: %s" % action)
		return
	var animation := str(action.get("animation", "")).strip_edges()
	if animation.is_empty():
		return
	var loop := bool(action.get("loop", false))
	var speed_scale := maxf(0.05, float(action.get("speed_scale", 1.0)))
	if actor.has_method("play_story_animation"):
		actor.call("play_story_animation", animation, loop, speed_scale)
		return
	var sprite := actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(animation):
		sprite.speed_scale = speed_scale
		sprite.play(animation)
	else:
		push_warning("动作轨道找不到动画资源 %s: %s" % [animation, action])


func _execute_actor_visibility(action: Dictionary) -> void:
	var actor := _resolve_story_actor(action)
	if actor == null:
		push_warning("动作轨道找不到显隐目标: %s" % action)
		return
	actor.visible = bool(action.get("visible", true))


func _start_timeline(dialogue_id: String, npc_id: int, entry_ms: int, auto_advance: bool, cutscene: bool, quest_action: Dictionary = {}) -> bool:
	var timeline := dialogue_config.get_timeline(dialogue_id)
	if timeline.is_empty():
		return false
	current_npc_id = npc_id
	current_dialogue_id = dialogue_id
	_timeline = timeline
	_tl_clips = (timeline.get("clips", []) as Array).duplicate()
	_tl_clips.sort_custom(func(a, b): return int(a.get("startMs", 0)) < int(b.get("startMs", 0)))
	_timeline_mode = true
	_active = true
	_auto_advance = auto_advance
	_cutscene = cutscene
	_pending_quest_action = quest_action
	_tl_idx = 0
	_tl_current = {}
	_tl_gate = {}
	_tl_gate_gen += 1
	_tl_segment_speaker_seen = false
	while _tl_idx < _tl_clips.size() and int((_tl_clips[_tl_idx] as Dictionary).get("startMs", 0)) < entry_ms:
		_tl_idx += 1
	dialogue_started.emit(npc_id)
	_tl_tick()
	return true


func _tl_clip_active(clip: Dictionary) -> bool:
	return _conditions_pass(clip.get("conditions", []))


func _tl_is_manual_npc_boundary(clip: Dictionary) -> bool:
	if _cutscene or _pending_quest_action.is_empty() or not _tl_segment_speaker_seen:
		return false
	var action := str(_pending_quest_action.get("action", ""))
	if action not in ["start_quest", "advance_talk", "turn_in_quest"]:
		return false
	var kind := str(clip.get("kind", ""))
	if kind not in ["line", "narration"] or str(clip.get("speaker_kind", "")) != "npc":
		return false
	var speaker_id := int(clip.get("speaker_id", 0))
	return speaker_id > 0 and speaker_id != current_npc_id


func _tl_synthesize_node(clip: Dictionary) -> Dictionary:
	var choices: Array = []
	var options: Array = clip.get("options", [])
	for option in options:
		if option is Dictionary:
			choices.append({
				"id": option.get("id", ""),
				"intent_key": "",
				"text": option.get("text", ""),
				"conditions": option.get("conditions", []),
				"actions": option.get("actions", []),
				"nextClipId": option.get("nextClipId", ""),
				"next_id": "",
			})
	return {
		"id": str(clip.get("id", "")),
		"type": "branch" if not choices.is_empty() else "line",
		"speaker": clip.get("speaker", ""),
		"speaker_kind": clip.get("speaker_kind", ""),
		"speaker_id": int(clip.get("speaker_id", 0)),
		"text": clip.get("text", ""),
		"choices": choices,
	}


## 迁移旧对白图时，end 节点会变成没有文本的 stage_action 标记。
## 这类标记只用于保留拓扑，不能停在 UI 上等待玩家再次点击“继续”。
func _tl_is_empty_marker(clip: Dictionary) -> bool:
	var kind := str(clip.get("kind", ""))
	if kind not in ["black_screen", "subtitle", "narration", "stage_action"]:
		return false
	return str(clip.get("text", "")).strip_edges().is_empty() and (clip.get("actions", []) as Array).is_empty()


func _tl_gate_satisfied(clip: Dictionary) -> bool:
	match str(clip.get("eventType", "")):
		"area_event", "named_event":
			if quest_service == null or quest_service.state == null:
				return false
			var event_name := str(clip.get("eventName", clip.get("payload", "")))
			return bool(quest_service.state.get_flag("event:%s" % event_name, false)) or bool(quest_service.state.get_flag(event_name, false))
		"stage_enter":
			return quest_service != null and quest_service.get_current_stage_id(int(clip.get("questId", 0))) == str(clip.get("stageId", ""))
		"stage_exit":
			# 阶段退出标记位于当前阶段末尾；下一阶段的 stage_enter 再负责切换当前阶段。
			return quest_service != null and quest_service.get_current_stage_id(int(clip.get("questId", 0))) == str(clip.get("stageId", ""))
		"quest_state":
			if quest_service == null or quest_service.config == null:
				return false
			var qid := int(clip.get("questId", 0))
			var expected := str(clip.get("questState", "ready"))
			var current := quest_service.get_status(qid)
			return current == expected or (expected == "ready" and current == "completed")
		"objective":
			if quest_service == null or quest_service.config == null:
				return false
			var quest := quest_service.config.get_quest(int(clip.get("questId", 0)))
			var objectives: Array = quest.get("objectives", [])
			var key := str(clip.get("objectiveKey", ""))
			for index in range(objectives.size()):
				if objectives[index] is Dictionary and str((objectives[index] as Dictionary).get("id", "")) == key:
					return bool(quest_service.get_objective_progress(int(clip.get("questId", 0)), objectives[index], index).get("complete", false))
			return false
		_:
			return false


func _tl_tick() -> void:
	if not _active or not _timeline_mode:
		return
	while _tl_idx < _tl_clips.size():
		var clip: Dictionary = _tl_clips[_tl_idx]
		if not _tl_clip_active(clip):
			_tl_idx += 1
			continue
		if _tl_is_manual_npc_boundary(clip):
			finish(true)
			return
		var kind := str(clip.get("kind", ""))
		_sync_timeline_stage(clip)
		_execute_actions(clip.get("actions", []))
		if _tl_is_empty_marker(clip):
			_tl_idx += 1
			continue
		if kind == "event":
			_tl_idx += 1
			var event_type := str(clip.get("eventType", "wait"))
			# 交付 NPC 的最后一句对白后，时间轴常会放一个
			# quest_state=ready 门。talk 目标原本在 finish(true) 才记账，
			# 如果此处先等待 ready，就会形成“要完成对话才能继续、要继续
			# 才能完成对话”的死锁。先把当前交付 NPC 的 talk 记账，
			# 让任务进入 ready，再继续 stage_exit 和正常交付收尾。
			_prepare_turn_in_gate(event_type, clip)
			if str(clip.get("eventMode", "wait")) == "optional" and not _tl_gate_satisfied(clip):
				continue
			match event_type:
				"wait":
					_tl_current = {}
					if _auto_advance:
						_schedule_tl_advance(maxi(200, int(clip.get("durationMs", 1500))))
					else:
						_tl_gate = clip
					return
				"custom":
					_tl_current = {}
					_tl_gate = clip
					return
				_:
					if _tl_gate_satisfied(clip):
						continue
					_tl_current = {}
					_tl_gate = clip
					return
		_tl_current = clip
		current_node_id = str(clip.get("id", ""))
		node_changed.emit(_tl_synthesize_node(clip))
		if kind in ["line", "narration"] and str(clip.get("speaker_kind", "")) == "npc" and int(clip.get("speaker_id", 0)) > 0:
			_tl_segment_speaker_seen = true
		_tl_idx += 1
		if _auto_advance and kind != "choice":
			_schedule_tl_advance(maxi(200, int(clip.get("durationMs", 1200))))
		return
	finish(true)


func _sync_timeline_stage(clip: Dictionary) -> void:
	if quest_service == null:
		return
	var quest_id := int(_pending_quest_action.get("quest_id", clip.get("questId", 0)))
	var stage_id := str(clip.get("stageId", ""))
	if quest_id <= 0 or stage_id.is_empty():
		return
	if quest_service.get_status(quest_id) in ["active", "ready"] and quest_service.get_current_stage_id(quest_id) != stage_id:
		quest_service.set_current_stage(quest_id, stage_id)


func _prepare_turn_in_gate(event_type: String, clip: Dictionary) -> void:
	if event_type != "quest_state" or str(clip.get("questState", "ready")) != "ready":
		return
	if quest_service == null or _pending_quest_action.is_empty():
		return
	var action := str(_pending_quest_action.get("action", ""))
	if action not in ["advance_talk", "turn_in_quest"]:
		return
	var quest_id := int(_pending_quest_action.get("quest_id", clip.get("questId", 0)))
	var quest := quest_service.config.get_quest(quest_id) if quest_service.config != null else {}
	if quest.is_empty() or int(quest.get("turn_in_npc_id", 0)) != current_npc_id:
		return
	if quest_service.get_status(quest_id) == "active":
		quest_service.record_talk(current_npc_id)


func _schedule_tl_advance(delay_ms: int) -> void:
	_auto_gen += 1
	var gen := _auto_gen
	get_tree().create_timer(float(maxi(0, delay_ms)) / 1000.0).timeout.connect(_tl_auto_step.bind(gen))


func _tl_auto_step(gen: int) -> void:
	if gen != _auto_gen or not _active or not _timeline_mode:
		return
	_tl_tick()


func _on_objective_completed(_quest_id: int, _objective_key: String) -> void:
	_tl_resume_if_gate_satisfied()


func _on_tl_quest_signal(_quest_id: int) -> void:
	_tl_resume_if_gate_satisfied()


func _tl_resume_if_gate_satisfied() -> void:
	if not _active or not _timeline_mode or _tl_gate.is_empty():
		return
	if _tl_gate_satisfied(_tl_gate):
		_tl_gate = {}
		_tl_tick()
