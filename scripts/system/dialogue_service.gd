class_name DialogueService
extends Node

signal dialogue_started(npc_id: int)
signal node_changed(node: Dictionary)
signal dialogue_finished(npc_id: int, completed: bool)
signal intent_selected(npc_id: int, dialogue_id: String, choice_id: String, intent_key: String)
## 时间轴等待区域/命名事件时，允许玩家回到场景中完成外部交互。
signal world_event_gate_changed(available: bool)

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
var _world_event_gate_open := false
# 手动任务对白已经播过当前交互 NPC 后，遇到下一位 NPC 时收束本次对话。
# 过场不启用，避免 C1-01-B 的公共开场把柏婶/霍雷克对白截断。
var _tl_segment_speaker_seen := false
# 自动续播（世界事件目标完成触发）的停止线：到达该毫秒的第一个台词片段前收束对话，
# 把后续内容留给玩家主动与 NPC 对话（-1 = 不限，播到自然结束）。
var _tl_stop_before_ms := -1


## 当前时间轴是否在等待玩家通过场景交互或区域触发完成事件。
func is_waiting_for_world_event() -> bool:
	if not _active or not _timeline_mode or _tl_gate.is_empty():
		return false
	return str(_tl_gate.get("eventType", "")) in ["area_event", "named_event", "objective"]


## 给系统 UI 的玩家操作提示；技术事件名仍保留在时间轴/调试信息中，不直接冒充 NPC 台词。
func get_world_event_prompt() -> String:
	if _tl_gate.is_empty():
		return "请完成场景交互。"
	var event_type := str(_tl_gate.get("eventType", ""))
	var event_name := str(_tl_gate.get("eventName", ""))
	if event_name == "prologue_warm_meal":
		return "请靠近热粥并按 E。"
	if event_type == "area_event":
		return "请前往目标区域。"
	if event_type == "objective":
		return "请完成当前任务目标。"
	return "请完成场景交互。"


func _set_world_event_gate_open(available: bool) -> void:
	if _world_event_gate_open == available:
		return
	_world_event_gate_open = available
	world_event_gate_changed.emit(available)


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
		# 时间轴格式任务对话：用钩子解析好的入口（ready 交付段用 turn_in_entries，
		# 不能回退普通入口，否则喝粥后交付会从开场旁白重播）。
		if not dialogue_config.get_timeline(quest_dialogue_id).is_empty():
			return _start_timeline(quest_dialogue_id, npc_id, int(quest_hook.get("entry_ms", 0)), false, false, quest_hook)
		push_warning("TaskScript dialogue is not timeline format: %s" % quest_dialogue_id)
		return false
	var dialogue_id := str(npc.get("dialogue_id", ""))
	if not dialogue_config.get_timeline(dialogue_id).is_empty():
		return _start_timeline(dialogue_id, npc_id, 0, false, false)
	push_warning("NPC dialogue is not timeline format: %s" % dialogue_id)
	return false


## 过场播放：不依赖 NPC/任务钩子直接播对话图（npc_id 可为 0），进入自动推进模式。
## cinematic=true 时用纯黑背景（仅开局选角）；任务过场用半透背景保留场景画面。
## entry_ms：从时间轴指定毫秒处入场（自动播放段，如 C1-02-A 途中对白从 S02 起点接播）。
func start_cutscene(dialogue_id: String, npc_id: int = 0, cinematic: bool = false, entry_ms: int = 0) -> bool:
	if _active:
		return false
	if not dialogue_config.get_timeline(dialogue_id).is_empty():
		return _start_timeline(dialogue_id, npc_id, entry_ms, true, cinematic)
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
		# 用交付专用入口（turn_in_entries → 交付段），不重播追踪段（如仓库看守的领装备段）。
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and quest_service.get_status(quest_id) == "ready":
			return {"quest_id": quest_id, "action": "turn_in_quest", "dialogue_id": dialogue_id, "entry_ms": dialogue_config.get_timeline_turn_in_entry_ms(dialogue_id, str(npc_id))}
		# 进行中：本 NPC 是未完成的 talk 目标 → 播该 NPC 段（等待态的"事件通知"由对话收尾推进）
		if quest_service.get_status(quest_id) == "active" and _has_pending_talk_objective(quest, npc_id, quest_id):
			# 中断续播：从任务当前阶段的起点接播，不重播已听过的接取台词
			#（阶段指针由上次播放的 _sync_timeline_stage 写入）。
			var talk_entry_ms := dialogue_config.get_timeline_entry_ms(dialogue_id, str(npc_id))
			var stage_entry_ms := dialogue_config.get_timeline_stage_entry_ms(dialogue_id, quest_service.get_current_stage_id(quest_id))
			# 阶段入口与 NPC 入口取较深者：同一阶段内有多个 NPC 时（如 C0-07-A 杂货商人→药水商人→柏婶），
			# 与该 NPC 对话应从他自己的台词段接播，而不是把整个阶段从别人的台词重播一遍。
			if stage_entry_ms >= 0:
				talk_entry_ms = maxi(talk_entry_ms, stage_entry_ms)
			# 本阶段的世界事件门已完成（旗标已置）→ 旁白已由自动续播过：
			# 跳过门后的旁白，从第一句台词接播，直接进入与该 NPC 的对话内容。
			var fired_gate_ms := -1
			for clip_value in (dialogue_config.get_timeline(dialogue_id).get("clips", []) as Array):
				if not clip_value is Dictionary:
					continue
				var clip := clip_value as Dictionary
				var clip_ms := int(clip.get("startMs", 0))
				if clip_ms < talk_entry_ms:
					continue
				if str(clip.get("kind", "")) == "event" and str(clip.get("eventType", "")) in ["area_event", "named_event"] \
						and quest_service.state != null \
						and bool(quest_service.state.get_flag("event:%s" % str(clip.get("eventName", "")), false)):
					fired_gate_ms = clip_ms
				elif fired_gate_ms >= 0 and str(clip.get("kind", "")) == "line":
					talk_entry_ms = clip_ms
					break
			return {"quest_id": quest_id, "action": "advance_talk", "dialogue_id": dialogue_id, "entry_ms": talk_entry_ms}
		if int(quest.get("giver_npc_id", 0)) == npc_id and quest_service.get_status(quest_id) == "inactive" and quest_service.is_quest_unlocked(quest_id):
			starters.append({"quest_id": quest_id, "action": "start_quest", "dialogue_id": dialogue_id, "entry_ms": dialogue_config.get_timeline_entry_ms(dialogue_id, str(npc_id))})
	return starters[0] if not starters.is_empty() else {}


## 任务进行中，该 NPC 是否还有未完成的 talk 目标（用于 active 状态的目标对话钩子）。
## 阶段引导：目标所在阶段的前置目标未全部完成时不可触发——玩家跳过霍雷克直接找
## 仓库看守时不会误播后续段，感叹号（QuestService.has_active_quest 同规则）同步。
## 注意不比较 current_stage_id：阶段指针只在时间轴播放时同步，手动任务接取后停在
## 首阶段（如 C1-01-D 教学完成后仍停在 S01），按指针过滤会把柏婶的 talk 钩子
## 一直拦下、落到个人对白上；按前置目标完成度判定则与对话播放进度解耦。
func _has_pending_talk_objective(quest: Dictionary, npc_id: int, quest_id := 0) -> bool:
	var resolved_id := quest_id if quest_id > 0 else int(quest.get("id", 0))
	var objectives: Array = quest.get("objectives", [])
	for index in range(objectives.size()):
		if not objectives[index] is Dictionary:
			continue
		var objective: Dictionary = objectives[index]
		if str(objective.get("type", "")) != "talk" or int(objective.get("npc_id", 0)) != npc_id:
			continue
		if bool(quest_service.get_objective_progress(resolved_id, objective, index).get("complete", false)):
			continue
		# 目标所在阶段的前置目标未全部完成 → 尚未解锁，跳过（无 stages 数据时不过滤）
		if quest_service != null and not (quest.get("stages", []) as Array).is_empty() \
			and not quest_service.is_objective_stage_reachable(quest, resolved_id, str(objective.get("id", ""))):
			continue
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
	_set_world_event_gate_open(false)
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
	_tl_stop_before_ms = -1
	if completed and quest_service != null:
		var quest_id := int(_pending_quest_action.get("quest_id", 0))
		var action := str(_pending_quest_action.get("action", ""))
		# 先接取再记账：接取对话的收尾同样算作与接取 NPC 的一次对话
		#（如 C1-02-A 的 talk_9020），否则玩家要对搜救员再说一遍话才记账
		if action == "start_quest" and quest_service.get_status(quest_id) == "inactive":
			quest_service.start_quest(quest_id)
		quest_service.record_talk(npc_id)
		# 任务剧情对话正常结束后执行交付
		if not _pending_quest_action.is_empty():
			match action:
				"turn_in_quest":
					if quest_service.get_status(quest_id) == "ready":
						quest_service.turn_in_quest(quest_id)
				"advance_talk", "start_quest":
					# 目标对话收尾：talk 已在上面 record_talk 推进；若任务因此刚 ready
					# 且本 NPC 就是交付人（如仓库看守领取+交付连播），当场交付完成。
					# start_quest 同理：接取对话当场走到可交付（如 C0-02-A 认门到喷泉
					# 广场后名单段已在对话里播过），直接结算，不让玩家再点一次重播。
					if quest_service.config != null:
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
					var give_id := int(value.get("item_id", 0))
					var give_count := maxi(1, int(value.get("count", 1)))
					inventory.add_item(give_id, give_count)
					# 与世界拾取/战利品一致：对话内发放（如按职业领装备）也要提示玩家并落盘，
					# 否则装备悄悄入包且对话中途退出会丢。
					var item_name := str(give_id)
					if GameRegistry.item_config != null:
						item_name = str(GameRegistry.item_config.get_item(give_id).get("name", item_name))
					var ui_root := get_tree().get_first_node_in_group("ui_root")
					if ui_root != null and ui_root.has_method("show_notification"):
						ui_root.show_notification("获得 %s ×%d" % [item_name, give_count])
					GameRegistry.save_game()
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
	_tl_stop_before_ms = int(quest_action.get("stop_before_ms", -1))
	# 接取对话开场即生效：start_quest 立刻执行，任务面板马上出现目标指引。
	# 原来拖到对话收尾才接取——接取对话中途要在世界门（如“走到喷泉广场”）停留，
	# 期间任务还是 inactive，面板空白，玩家不知道该干嘛。
	if not quest_action.is_empty() and str(quest_action.get("action", "")) == "start_quest" \
			and quest_service != null:
		var start_quest_id := int(quest_action.get("quest_id", 0))
		if start_quest_id > 0 and quest_service.get_status(start_quest_id) == "inactive":
			quest_service.start_quest(start_quest_id)
	_tl_idx = 0
	_tl_current = {}
	_tl_gate = {}
	_set_world_event_gate_open(false)
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
		"stage_enter", "stage_exit":
			# 阶段门只对进行中/可交付任务有意义：接取对话播放中任务尚未 active
			#（start_quest 在对话收尾才执行，current_stage_id 未写入），已完成任务
			# 的重播同理。此时硬等阶段匹配只会死锁（如 C1-01-D 接取段卡在 S01
			# 退出标记——点继续无响应），直接放行。
			if quest_service == null:
				return false
			var stage_quest_id := int(clip.get("questId", 0))
			if quest_service.get_status(stage_quest_id) not in ["active", "ready"]:
				return true
			return quest_service.get_current_stage_id(stage_quest_id) == str(clip.get("stageId", ""))
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
		if _tl_stop_before_ms >= 0 and int(clip.get("startMs", 0)) >= _tl_stop_before_ms:
			# 自动续播只覆盖世界门后的旁白：到第一句台词为止收束（不记账），
			# 玩家主动与 NPC 对话后从该片段继续（advance_talk 入口同样跳过旁白）。
			finish(false)
			return
		var kind := str(clip.get("kind", ""))
		_sync_timeline_stage(clip)
		_execute_actions(clip.get("actions", []))
		# close_dialogue 在时间轴内即时收尾：延迟到帧末会让同帧后续片段继续过门/显示。
		# C1-02-A 途中过场需要在等待目标门处收束，不能滑入战后段（该段留给交付入口播）。
		for action_value in (clip.get("actions", []) as Array):
			if action_value is Dictionary and str((action_value as Dictionary).get("type", "")) == "close_dialogue":
				finish(true)
				return
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
					# 任务状态门（如「等待可交付」）不满足时直接收束对话：状态要靠玩家
					# 回场景推进（喝粥/战斗/收集）。挂在对话框里等会被点击/自动推进跳过
					#（门后内容提前播出）；关框后记账 talk，状态达标由 turn_in 入口重新触发。
					if str(clip.get("eventType", "")) == "quest_state":
						finish(true)
						return
					_tl_current = {}
					_tl_gate = clip
					_set_world_event_gate_open(is_waiting_for_world_event())
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
	var current_stage_id := quest_service.get_current_stage_id(quest_id)
	if quest_service.get_status(quest_id) in ["active", "ready"] and current_stage_id != stage_id:
		# 自动开场对白按阶段完成目标：进入下一阶段时，上一阶段的 NPC 对话
		# 已经在画面上播放完，不能等整条时间轴（后面的世界事件）结束才记账。
		# 否则玩家看到对白已结束，但 HUD 仍显示“与柏婶对话 0/1”，
		# 重新进入时还会从旧入口重播。
		if _auto_advance and not current_stage_id.is_empty():
			_record_stage_talk_objectives(quest_id, current_stage_id)
		quest_service.set_current_stage(quest_id, stage_id)


func _record_stage_talk_objectives(quest_id: int, stage_id: String) -> void:
	if quest_service == null or quest_service.config == null:
		return
	var quest := quest_service.config.get_quest(quest_id)
	if quest.is_empty():
		return
	var objective_ids: Array = []
	for stage_value in quest.get("stages", []):
		if stage_value is Dictionary and str((stage_value as Dictionary).get("id", "")) == stage_id:
			objective_ids = (stage_value as Dictionary).get("objective_ids", []) as Array
			break
	for objective_value in quest.get("objectives", []):
		if not objective_value is Dictionary:
			continue
		var objective := objective_value as Dictionary
		if str(objective.get("id", "")) not in objective_ids:
			continue
		if str(objective.get("type", "")) == "talk":
			quest_service.record_talk(int(objective.get("npc_id", 0)))


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


func _on_objective_completed(quest_id: int, objective_key: String) -> void:
	if _active:
		_tl_resume_if_gate_satisfied()
		return
	# 对话没在播（玩家此前点掉了）：目标在世界中完成后自动以过场形式
	# 从对应事件门续播后续对白（如 C0-02-A 走到喷泉广场 → 途中旁白 → 交付段），
	# 不让玩家再点一次 NPC 从接取台词重看。
	_try_autoplay_objective_segment(quest_id, objective_key)


## 世界事件类目标完成时，从时间轴中该事件的门位置自动续播。
## 以 advance_talk 身份播放：ready 门放行前记账 talk，收尾当场结算交付。
func _try_autoplay_objective_segment(quest_id: int, objective_key: String) -> void:
	if quest_service == null or quest_service.config == null or dialogue_config == null:
		return
	if quest_service.get_status(quest_id) != "active":
		return
	var quest := quest_service.config.get_quest(quest_id)
	if quest.is_empty():
		return
	var event_type := ""
	var event_name := ""
	for objective_value in (quest.get("objectives", []) as Array):
		if not objective_value is Dictionary:
			continue
		var objective := objective_value as Dictionary
		if str(objective.get("id", "")) != objective_key:
			continue
		match str(objective.get("type", "")):
			"area_trigger":
				event_type = "area_event"
			"named_event":
				event_type = "named_event"
		event_name = str(objective.get("event_name", ""))
		break
	if event_type.is_empty() or event_name.is_empty():
		return
	var dialogue_id := str((quest.get("authoring", {}) as Dictionary).get("dialogue_id", ""))
	if dialogue_id.is_empty():
		return
	var timeline := dialogue_config.get_timeline(dialogue_id)
	if timeline.is_empty():
		return
	for clip_value in (timeline.get("clips", []) as Array):
		if not clip_value is Dictionary:
			continue
		var clip := clip_value as Dictionary
		if str(clip.get("kind", "")) != "event" or str(clip.get("eventType", "")) != event_type:
			continue
		if str(clip.get("eventName", clip.get("payload", ""))) != event_name:
			continue
		var npc_id := int(quest.get("turn_in_npc_id", 0))
		if npc_id <= 0:
			npc_id = int(quest.get("giver_npc_id", 0))
		# 自动续播只播门后的旁白氛围段：到第一句台词（主角/NPC 对话内容）为止收束，
		# 之后由玩家主动与 NPC 对话继续（advance_talk 入口会跳过这段旁白）。
		var gate_start_ms := int(clip.get("startMs", 0))
		var stop_before_ms := -1
		for line_value in (timeline.get("clips", []) as Array):
			if not line_value is Dictionary:
				continue
			var line_ms := int((line_value as Dictionary).get("startMs", 0))
			if line_ms >= gate_start_ms and str((line_value as Dictionary).get("kind", "")) == "line":
				stop_before_ms = line_ms
				break
		_start_timeline(dialogue_id, npc_id, gate_start_ms, true, false, {"action": "advance_talk", "quest_id": quest_id, "stop_before_ms": stop_before_ms})
		return


func _on_tl_quest_signal(_quest_id: int) -> void:
	_tl_resume_if_gate_satisfied()


func _tl_resume_if_gate_satisfied() -> void:
	if not _active or not _timeline_mode or _tl_gate.is_empty():
		return
	if _tl_gate_satisfied(_tl_gate):
		var gate_clip := _tl_gate
		_tl_gate = {}
		_set_world_event_gate_open(false)
		_apply_world_gate_narration_limit(gate_clip)
		_tl_tick()


## 世界门（区域/命名事件）放行后只自动播门后的旁白氛围段：
## 到第一句台词为止收束对话，主角观察/交付段留给玩家主动与 NPC 对话继续。
func _apply_world_gate_narration_limit(gate_clip: Dictionary) -> void:
	if str(gate_clip.get("eventType", "")) not in ["area_event", "named_event"]:
		return
	var gate_ms := int(gate_clip.get("startMs", 0))
	for clip_value in _tl_clips:
		if not clip_value is Dictionary:
			continue
		var clip := clip_value as Dictionary
		if int(clip.get("startMs", 0)) >= gate_ms and str(clip.get("kind", "")) == "line":
			_tl_stop_before_ms = int(clip.get("startMs", 0))
			return
