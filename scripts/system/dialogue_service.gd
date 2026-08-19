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
var _graph: Dictionary = {}
var _active := false
# 任务对话触发：命中 quest authoring.dialogue_id 时记录对话结束后要执行的任务动作
var _pending_quest_action: Dictionary = {}
# 过场自动播放：line 节点定时自动推进，choice 节点停下等输入；代际令牌使旧定时器失效
var _auto_advance := false
var _auto_gen := 0
# 当前对话是否为过场（UI 据此用纯黑背景遮住主界面）
var _cutscene := false


func setup(p_npc_config: NpcConfig, p_dialogue_config: DialogueConfig, p_quest_service: QuestService, p_inventory: InventoryProvider) -> void:
	npc_config = p_npc_config
	dialogue_config = p_dialogue_config
	quest_service = p_quest_service
	inventory = p_inventory


func start_dialogue(npc_id: int) -> bool:
	if _active:
		return false
	var npc := npc_config.get_npc(npc_id)
	if npc.is_empty():
		push_warning("NPC 不存在: %d" % npc_id)
		return false
	# 优先播放任务剧情对话（quest authoring.dialogue_id）：交付(ready) 优先于接取(inactive 且已解锁)
	var quest_hook := _find_quest_dialogue_hook(npc_id)
	if not quest_hook.is_empty():
		var quest_dialogue_id := str(quest_hook.get("dialogue_id", ""))
		var quest_graph := dialogue_config.get_dialogue(quest_dialogue_id)
		if not quest_graph.is_empty():
			current_npc_id = npc_id
			current_dialogue_id = quest_dialogue_id
			_graph = quest_graph
			_active = true
			_pending_quest_action = quest_hook
			dialogue_started.emit(npc_id)
			return _enter_node(str(quest_graph.get("entry_node", quest_graph.get("entry", ""))))
	var dialogue_id := str(npc.get("dialogue_id", ""))
	var graph := dialogue_config.get_dialogue(dialogue_id)
	if dialogue_id.is_empty() or graph.is_empty():
		push_warning("NPC %d 没有可用对话: %s" % [npc_id, dialogue_id])
		return false
	current_npc_id = npc_id
	current_dialogue_id = dialogue_id
	_graph = graph
	_active = true
	dialogue_started.emit(npc_id)
	return _enter_node(str(graph.get("entry_node", graph.get("entry", ""))))


## 过场播放：不依赖 NPC/任务钩子直接播对话图（npc_id 可为 0），进入自动推进模式。
## cinematic=true 时用纯黑背景（仅开局选角）；任务过场用半透背景保留场景画面。
func start_cutscene(dialogue_id: String, npc_id: int = 0, cinematic: bool = false) -> bool:
	if _active:
		return false
	var graph := dialogue_config.get_dialogue(dialogue_id)
	if graph.is_empty():
		push_warning("过场对话不存在: %s" % dialogue_id)
		return false
	current_npc_id = npc_id
	current_dialogue_id = dialogue_id
	_graph = graph
	_active = true
	_auto_advance = true
	_cutscene = cinematic
	dialogue_started.emit(npc_id)
	return _enter_node(str(graph.get("entry_node", graph.get("entry", ""))))


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
		# 交付优先：任务 ready 且本 NPC 是交付人
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and quest_service.get_status(quest_id) == "ready":
			return {"quest_id": quest_id, "action": "turn_in_quest", "dialogue_id": dialogue_id}
		if int(quest.get("giver_npc_id", 0)) == npc_id and quest_service.get_status(quest_id) == "inactive" and quest_service.is_quest_unlocked(quest_id):
			starters.append({"quest_id": quest_id, "action": "start_quest", "dialogue_id": dialogue_id})
	return starters[0] if not starters.is_empty() else {}


func advance() -> void:
	if not _active:
		return
	_auto_gen += 1  # 手动推进使待处理的自动定时器失效
	var node := get_current_node()
	var choices: Array = node.get("choices", [])
	if not choices.is_empty():
		return
	var next_id := str(node.get("next_id", node.get("next", "")))
	if next_id.is_empty():
		finish(true)
	else:
		_enter_node(next_id)


func choose(index: int) -> void:
	var node := get_current_node()
	var visible := get_visible_choices(node)
	if index < 0 or index >= visible.size():
		return
	var choice: Dictionary = visible[index]
	var intent_key := str(choice.get("intent_key", "")).strip_edges()
	if not intent_key.is_empty() and not _can_dispatch_intent(intent_key):
		# 状态可能在对话打开后发生变化；在真正选择时再校验一次，
		# 避免播放“已接取/已交付”的后续节点却没有实际改变任务状态。
		finish(false)
		return
	if not intent_key.is_empty():
		intent_selected.emit(current_npc_id, current_dialogue_id, str(choice.get("id", "")), intent_key)
	_execute_actions(choice.get("actions", []))
	var next_id := str(choice.get("next_id", choice.get("next", "")))
	if next_id.is_empty():
		finish(true)
	else:
		_enter_node(next_id)


func get_current_node() -> Dictionary:
	var nodes: Dictionary = _graph.get("nodes", {})
	return (nodes.get(current_node_id, {}) as Dictionary).duplicate(true)


func get_visible_choices(node: Dictionary = {}) -> Array[Dictionary]:
	if node.is_empty():
		node = get_current_node()
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
	_pending_quest_action = {}
	current_node_id = ""
	_graph = {}
	dialogue_finished.emit(npc_id, completed)


func _enter_node(node_id: String) -> bool:
	var guard := 0
	var next_id := node_id
	while guard < 64:
		guard += 1
		var nodes: Dictionary = _graph.get("nodes", {})
		var node: Dictionary = nodes.get(next_id, {})
		if node.is_empty():
			push_warning("对话节点不存在: %s/%s" % [current_dialogue_id, next_id])
			finish(false)
			return false
		current_node_id = next_id
		_execute_actions(node.get("actions", []))
		match str(node.get("type", "line")):
			"branch":
				# A branch with player choices must be presented to the UI. Only
				# route-only branches are resolved automatically.
				if not get_visible_choices(node).is_empty():
					_auto_gen += 1  # 选项等待玩家输入，不自动推进
					node_changed.emit(node.duplicate(true))
					return true
				next_id = _resolve_branch(node)
				if next_id.is_empty():
					finish(true)
					return true
			"end":
				finish(true)
				return true
			_:
				node_changed.emit(node.duplicate(true))
				_schedule_auto_advance(node)
				return true
	push_warning("对话条件分支超过 64 次，疑似无出口循环: %s" % current_dialogue_id)
	finish(false)
	return false


func _resolve_branch(node: Dictionary) -> String:
	for value in node.get("routes", []):
		if value is Dictionary and _conditions_pass(value.get("conditions", [])):
			return str(value.get("next_id", value.get("next", "")))
	return str(node.get("default_next", ""))


## 过场自动推进：按台词长度定时 advance；代际令牌保证手动推进/选项/结束后的旧定时器作废。
func _schedule_auto_advance(node: Dictionary) -> void:
	if not _auto_advance:
		return
	_auto_gen += 1
	var gen := _auto_gen
	var text_len := float(str(node.get("text", "")).length())
	var delay := clampf(0.8 + text_len * 0.11, 1.6, 7.0)
	get_tree().create_timer(delay).timeout.connect(_auto_step.bind(gen))


func _auto_step(gen: int) -> void:
	if gen != _auto_gen or not _active or not _auto_advance:
		return
	var node := get_current_node()
	if not node.get("choices", []).is_empty():
		return
	advance()


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
			"close_dialogue":
				call_deferred("finish", true)
			"":
				pass
			_:
				push_warning("未知对话动作: %s" % value.get("type", ""))
