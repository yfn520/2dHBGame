class_name QuestService
extends Node

signal quest_updated(quest_id: int)
signal quest_started(quest_id: int)
signal quest_ready(quest_id: int)
signal quest_completed(quest_id: int)
signal notification_requested(text: String)
signal stage_changed(quest_id: int, stage_id: String)
## 单个目标（key = objective id）完成时发出；供时间轴事件门控续播。
signal objective_completed(quest_id: int, objective_key: String)

var config: QuestConfig
var state: QuestStateData
var inventory: InventoryProvider
var roster: CharacterRosterData


func setup(p_config: QuestConfig, p_state: QuestStateData, p_inventory: InventoryProvider, p_roster: CharacterRosterData = null) -> void:
	config = p_config
	state = p_state
	inventory = p_inventory
	roster = p_roster
	if inventory != null:
		if not inventory.item_added.is_connected(_on_inventory_changed):
			inventory.item_added.connect(_on_inventory_changed)
		if not inventory.item_removed.is_connected(_on_inventory_changed):
			inventory.item_removed.connect(_on_inventory_changed)
		if not inventory.item_changed.is_connected(_on_inventory_changed):
			inventory.item_changed.connect(_on_inventory_changed)
	_refresh_all_ready_states()


func start_quest(quest_id: int) -> bool:
	if config == null or config.get_quest(quest_id).is_empty() or state.get_status(quest_id) != "inactive":
		return false
	if not is_quest_unlocked(quest_id):
		return false
	var quest := config.get_quest(quest_id)
	var stages: Array = quest.get("stages", [])
	var first_stage_id := str((stages[0] as Dictionary).get("id", "")) if not stages.is_empty() and stages[0] is Dictionary else ""
	state.set_entry(quest_id, {"status": "active", "counters": {}, "current_stage_id": first_stage_id})
	_refresh_ready_state(quest_id)
	quest_started.emit(quest_id)
	quest_updated.emit(quest_id)
	# quest was loaded before the state entry was written.
	if not first_stage_id.is_empty():
		stage_changed.emit(quest_id, first_stage_id)
	notification_requested.emit("已接取任务：%s" % str(quest.get("title", quest_id)))
	return true


func record_talk(npc_id: int) -> void:
	_record_event("talk", "npc_id", npc_id)


func record_kill(enemy_id: int) -> void:
	_record_event("kill", "enemy_id", enemy_id)


func record_collect(item_id: int) -> void:
	_record_event("collect", "item_id", item_id)


func record_interact(interact_id: String) -> void:
	_record_named_event("interact", interact_id)


func record_area_event(event_name: String) -> void:
	if state != null:
		state.set_flag("event:%s" % event_name, true)
	_record_named_event("area_trigger", event_name)


func record_named_event(event_name: String) -> void:
	if state != null:
		state.set_flag("event:%s" % event_name, true)
	_record_named_event("named_event", event_name)


## 教学目标按玩法触发器记账：如 trigger=basic_attack 的训练桩教学，
## 玩家施放一次普攻即完成（CombatComponent 调用）。返回是否有目标被完成。
func record_tutorial_trigger(trigger: String) -> bool:
	if config == null or state == null or trigger.is_empty():
		return false
	var completed_any := false
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		if state.get_status(quest_id) != "active":
			continue
		var quest := config.get_quest(quest_id)
		var objectives: Array = quest.get("objectives", [])
		for index in range(objectives.size()):
			if not objectives[index] is Dictionary:
				continue
			var objective: Dictionary = objectives[index]
			if str(objective.get("type", "")) != "named_event" or str(objective.get("trigger", "")) != trigger:
				continue
			if bool(get_objective_progress(quest_id, objective, index).get("complete", false)):
				continue
			record_named_event(str(objective.get("event_name", objective.get("id", ""))))
			completed_any = true
	return completed_any


func get_current_stage_id(quest_id: int) -> String:
	return state.get_current_stage_id(quest_id) if state != null else ""


func set_current_stage(quest_id: int, stage_id: String) -> bool:
	if config == null or state == null or stage_id.is_empty():
		return false
	for stage_value in config.get_quest(quest_id).get("stages", []):
		if stage_value is Dictionary and str(stage_value.get("id", "")) == stage_id:
			state.set_current_stage_id(quest_id, stage_id)
			stage_changed.emit(quest_id, stage_id)
			quest_updated.emit(quest_id)
			return true
	return false


func get_current_stage(quest_id: int) -> Dictionary:
	if config == null:
		return {}
	var current_id := get_current_stage_id(quest_id)
	for stage_value in config.get_quest(quest_id).get("stages", []):
		if stage_value is Dictionary and str(stage_value.get("id", "")) == current_id:
			return (stage_value as Dictionary).duplicate(true)
	return {}


func turn_in_for_npc(npc_id: int) -> Array[int]:
	var completed: Array[int] = []
	if config == null:
		return completed
	for quest_id_value in config.get_all_quests():
		var quest_id := int(quest_id_value)
		var quest := config.get_quest(quest_id)
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and turn_in_quest(quest_id):
			completed.append(quest_id)
	return completed


func turn_in_quest(quest_id: int) -> bool:
	if state.get_status(quest_id) != "ready" or not _all_objectives_complete(quest_id):
		return false
	var quest := config.get_quest(quest_id)
	var quest_objectives: Array = quest.get("objectives", [])
	for objective_index in range(quest_objectives.size()):
		var objective_value = quest_objectives[objective_index]
		if not objective_value is Dictionary:
			continue
		var objective: Dictionary = objective_value
		if str(objective.get("type", "")) == "collect" and bool(objective.get("consume_on_turn_in", false)):
			if _is_debug_objective_completed(quest_id, objective, objective_index):
				continue
			var item_id := int(objective.get("item_id", 0))
			var count := maxi(1, int(objective.get("count", 1)))
			if inventory == null or not inventory.has_item(item_id, count):
				_refresh_ready_state(quest_id)
				return false
	for objective_index in range(quest_objectives.size()):
		var objective_value = quest_objectives[objective_index]
		if objective_value is Dictionary and str(objective_value.get("type", "")) == "collect" and bool(objective_value.get("consume_on_turn_in", false)):
			if _is_debug_objective_completed(quest_id, objective_value, objective_index):
				continue
			inventory.remove_item_by_id(int(objective_value.get("item_id", 0)), maxi(1, int(objective_value.get("count", 1))))
	var entry := state.get_entry(quest_id)
	entry["status"] = "completed"
	state.set_entry(quest_id, entry)
	_apply_rewards(quest)
	_apply_progression_rewards(quest_id, quest)
	quest_completed.emit(quest_id)
	quest_updated.emit(quest_id)
	notification_requested.emit("任务完成：%s" % str(quest.get("title", quest_id)))
	return true


func get_status(quest_id: int) -> String:
	return state.get_status(quest_id) if state != null else "inactive"


func get_objective_progress(quest_id: int, objective: Dictionary, index: int) -> Dictionary:
	var required := maxi(1, int(objective.get("count", 1)))
	if _is_debug_objective_completed(quest_id, objective, index):
		return {"current": required, "required": required, "complete": true, "debug_completed": true}
	var current := 0
	if str(objective.get("type", "")) == "collect":
		current = inventory.get_count_by_id(int(objective.get("item_id", 0))) if inventory != null else 0
	else:
		var counters: Dictionary = state.get_entry(quest_id).get("counters", {})
		current = int(counters.get(_objective_key(objective, index), 0))
	return {"current": mini(current, required), "required": required, "complete": current >= required}


## 调试工具：只标记目标进度，不伪造区域/战斗/物品事件；后续仍沿用正常 ready/交付流程。
func debug_complete_objective(quest_id: int, objective_id: String) -> bool:
	if config == null or state == null or objective_id.is_empty():
		return false
	if state.get_status(quest_id) not in ["active", "ready"]:
		return false
	var quest := config.get_quest(quest_id)
	var found := false
	for objective_value in quest.get("objectives", []):
		if objective_value is Dictionary and str(objective_value.get("id", "")) == objective_id:
			found = true
			break
	if not found or _is_debug_objective_completed_by_id(quest_id, objective_id):
		return false
	var entry := state.get_entry(quest_id)
	var completed: Array = entry.get("debug_completed_objectives", []) as Array
	completed.append(objective_id)
	entry["debug_completed_objectives"] = completed
	state.set_entry(quest_id, entry)
	objective_completed.emit(quest_id, objective_id)
	_refresh_ready_state(quest_id)
	quest_updated.emit(quest_id)
	GameRegistry.save_game()
	return true


func debug_clear_objective(quest_id: int, objective_id: String) -> bool:
	if state == null or objective_id.is_empty():
		return false
	var entry := state.get_entry(quest_id)
	var completed: Array = entry.get("debug_completed_objectives", []) as Array
	if not completed.has(objective_id):
		return false
	completed.erase(objective_id)
	entry["debug_completed_objectives"] = completed
	state.set_entry(quest_id, entry)
	_refresh_ready_state(quest_id)
	quest_updated.emit(quest_id)
	GameRegistry.save_game()
	return true


func _is_debug_objective_completed(quest_id: int, objective: Dictionary, index: int) -> bool:
	return _is_debug_objective_completed_by_id(quest_id, _objective_key(objective, index))


func _is_debug_objective_completed_by_id(quest_id: int, objective_id: String) -> bool:
	if state == null:
		return false
	var completed: Array = state.get_entry(quest_id).get("debug_completed_objectives", []) as Array
	return completed.has(objective_id)


func get_visible_tasks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if config == null:
		return result
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var status := state.get_status(quest_id)
		if status in ["active", "ready", "completed"]:
			var quest := config.get_quest(quest_id)
			quest["status"] = status
			result.append(quest)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("id", 0)) < int(b.get("id", 0)))
	return result


func has_available_quest(npc_id: int) -> bool:
	if config == null:
		return false
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var quest := config.get_quest(quest_id)
		if int(quest.get("giver_npc_id", 0)) == npc_id and state.get_status(quest_id) == "inactive" and is_quest_unlocked(quest_id):
			return true
	return false


## 任务是否满足接取前置：required_quest_ids 全部需为已完成状态（DAG 前置，支持多前置）。
func _mainline_quest_ids() -> Array[int]:
	var ids: Array[int] = []
	if config == null:
		return ids
	for id_value in config.get_all_quests():
		var quest := config.get_quest(int(id_value))
		if str(quest.get("quest_kind", "story_task_script")) == "story_task_script":
			ids.append(int(id_value))
	ids.sort()
	return ids


func _previous_mainline_quest_id(quest_id: int) -> int:
	var ids := _mainline_quest_ids()
	var index := ids.find(quest_id)
	return ids[index - 1] if index > 0 else 0


## 任务必须同时满足显式前置和主线顺序；即使旧 quests.json 漏写 required_quest_ids，也不能越过上一条主线。
func is_quest_unlocked(quest_id: int) -> bool:
	if config == null or state == null:
		return true
	var quest := config.get_quest(quest_id)
	for req_value in quest.get("required_quest_ids", []):
		if state.get_status(int(req_value)) != "completed":
			return false
	var previous_mainline_id := _previous_mainline_quest_id(quest_id)
	if previous_mainline_id > 0 and state.get_status(previous_mainline_id) != "completed":
		return false
	return true


## 该 NPC 是否关联进行中的任务。交付状态由 has_ready_quest 单独处理。
## 按阶段过滤：多 NPC 任务只亮前置目标已完成的目标 NPC（与 DialogueService
## _has_pending_talk_objective 同规则），避免霍雷克和仓库看守同时亮感叹号。
func has_active_quest(npc_id: int) -> bool:
	if config == null:
		return false
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var quest := config.get_quest(quest_id)
		if state.get_status(quest_id) != "active":
			continue
		var objectives: Array = quest.get("objectives", [])
		var has_stages := not (quest.get("stages", []) as Array).is_empty()
		for index in range(objectives.size()):
			if not objectives[index] is Dictionary:
				continue
			var objective: Dictionary = objectives[index]
			if str(objective.get("type", "")) != "talk" or int(objective.get("npc_id", 0)) != npc_id:
				continue
			if bool(get_objective_progress(quest_id, objective, index).get("complete", false)):
				continue
			# 目标所在阶段的前置目标未全部完成 → 尚未解锁，不亮（无 stages 数据时不过滤）
			if has_stages and not is_objective_stage_reachable(quest, quest_id, str(objective.get("id", ""))):
				continue
			return true
	return false


## 目标是否已完成（按 objective id 查找；未登记的目标视为已完成，保持宽松）。
func _objective_complete_by_id(quest: Dictionary, quest_id: int, objective_id: String) -> bool:
	var objectives: Array = quest.get("objectives", [])
	for index in range(objectives.size()):
		if objectives[index] is Dictionary and str((objectives[index] as Dictionary).get("id", "")) == objective_id:
			return bool(get_objective_progress(quest_id, objectives[index], index).get("complete", false))
	return true


## 目标所在阶段是否已解锁：前置阶段的目标全部完成即可触发，不依赖阶段指针。
## 阶段指针（current_stage_id）只在时间轴对话播放时同步——手动任务接取后停在
## 首阶段（如 C1-01-D 教学完成后仍停在 S01），后续 NPC 的 talk 钩子与感叹号
## 会被一直拦截，只能落到 NPC 个人对白上（用户反馈的“找柏婶却播旧台词”）。
## 改按目标完成度判定：前置阶段全清 = 解锁，与对话播放进度解耦。
func is_objective_stage_reachable(quest: Dictionary, quest_id: int, objective_id: String) -> bool:
	var stages: Array = quest.get("stages", [])
	if stages.is_empty():
		return true
	var target_order := -1
	for index in range(stages.size()):
		if not stages[index] is Dictionary:
			continue
		if ((stages[index] as Dictionary).get("objective_ids", []) as Array).has(objective_id):
			target_order = index
			break
	if target_order <= 0:
		return true
	for index in range(target_order):
		if not stages[index] is Dictionary:
			continue
		for prior_objective_id in (stages[index] as Dictionary).get("objective_ids", []):
			if not _objective_complete_by_id(quest, quest_id, str(prior_objective_id)):
				return false
	return true


## 供 HUD / 任务抽屉共用的目标描述，避免向玩家暴露配置 ID。
func get_objective_text(objective: Dictionary) -> String:
	match str(objective.get("type", "")):
		"talk":
			var npc_id := int(objective.get("npc_id", 0))
			var npc_name := "NPC"
			if GameRegistry.npc_config != null:
				npc_name = str(GameRegistry.npc_config.get_npc(npc_id).get("name", npc_name))
			return "与%s对话" % npc_name
		"kill":
			var enemy_id := int(objective.get("enemy_id", 0))
			var enemy_name := "目标"
			if GameRegistry.enemy_config != null:
				enemy_name = str(GameRegistry.enemy_config.get_enemy(enemy_id).get("name", enemy_name))
			return "击败%s" % enemy_name
		"collect":
			var item_id := int(objective.get("item_id", 0))
			var item_name := "任务物品"
			if GameRegistry.item_config != null:
				item_name = str(GameRegistry.item_config.get_item(item_id).get("name", item_name))
			return "收集%s" % item_name
		"interact", "pickup":
			return str(objective.get("name", "完成交互"))
		"area_trigger":
			return str(objective.get("name", "到达目标区域"))
		"named_event":
			# 教学等玩法目标（如“完成基础战斗/技能教学（训练桩）”），原文由编排台写入 name 字段。
			return str(objective.get("name", "完成目标"))
		_:
			return "完成目标"


func has_ready_quest(npc_id: int) -> bool:
	if config == null:
		return false
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		var quest := config.get_quest(quest_id)
		if int(quest.get("turn_in_npc_id", 0)) == npc_id and state.get_status(quest_id) == "ready":
			return true
	return false


func evaluate_condition(condition: Dictionary) -> bool:
	match str(condition.get("type", "")):
		"quest_state":
			var quest_id := int(condition.get("quest_id", 0))
			var expected_state := str(condition.get("state", "inactive"))
			if state.get_status(quest_id) != expected_state:
				return false
			# NPC 对话里的 inactive 分支就是“可接取任务”分支。仅有未接取
			# 状态还不够，所有前置任务也必须完成，避免展示一个必然派发失败的选项。
			return expected_state != "inactive" or is_quest_unlocked(quest_id)
		"flag_equals":
			# 数值旗标按数值比较：存档写入的是 int（如 LeadHero=7002），
			# 而 JSON 解析出的条件值是 float，若统一 str() 会出现 "7002" != "7002.0" 导致分支全部不命中；
			# 非数值（字符串/未写入的 bool 默认值）仍按字符串比较。
			var flag_actual: Variant = state.get_flag(str(condition.get("flag", "")))
			var flag_expected: Variant = condition.get("value", true)
			var actual_is_num := typeof(flag_actual) == TYPE_INT or typeof(flag_actual) == TYPE_FLOAT
			var expected_is_num := typeof(flag_expected) == TYPE_INT or typeof(flag_expected) == TYPE_FLOAT
			if actual_is_num and expected_is_num:
				return float(flag_actual) == float(flag_expected)
			return str(flag_actual) == str(flag_expected)
		"item_count":
			return inventory != null and inventory.get_count_by_id(int(condition.get("item_id", 0))) >= int(condition.get("count", 1))
		"area_event", "named_event":
			var event_name := str(condition.get("event_name", ""))
			return bool(state.get_flag("event:%s" % event_name, false)) or bool(state.get_flag(event_name, false))
		"lead_hero":
			return roster != null and roster.get_protagonist_hero_id() == int(condition.get("hero_id", 0))
		"":
			return true
		_:
			push_warning("未知对话条件: %s" % condition.get("type", ""))
			return false


func _record_event(objective_type: String, id_field: String, target_id: int) -> void:
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		if state.get_status(quest_id) != "active":
			continue
		var quest := config.get_quest(quest_id)
		var entry := state.get_entry(quest_id)
		var counters: Dictionary = entry.get("counters", {})
		var changed := false
		var completed: Array[String] = []
		var objectives: Array = quest.get("objectives", [])
		for index in range(objectives.size()):
			if not objectives[index] is Dictionary:
				continue
			var objective: Dictionary = objectives[index]
			if str(objective.get("type", "")) != objective_type or int(objective.get(id_field, 0)) != target_id:
				continue
			var key := _objective_key(objective, index)
			var required := maxi(1, int(objective.get("count", 1)))
			var was_complete := int(counters.get(key, 0)) >= required
			counters[key] = mini(required, int(counters.get(key, 0)) + 1)
			changed = true
			if not was_complete and int(counters.get(key, 0)) >= required:
				completed.append(key)
		if changed:
			entry["counters"] = counters
			state.set_entry(quest_id, entry)
			_refresh_ready_state(quest_id)
			quest_updated.emit(quest_id)
			for key in completed:
				objective_completed.emit(quest_id, key)


func _record_named_event(objective_type: String, event_name: String) -> void:
	if config == null or state == null:
		return
	for id_value in config.get_all_quests():
		var quest_id := int(id_value)
		if state.get_status(quest_id) != "active":
			continue
		var quest := config.get_quest(quest_id)
		var entry := state.get_entry(quest_id)
		var counters: Dictionary = entry.get("counters", {})
		var changed := false
		var completed: Array[String] = []
		var objectives: Array = quest.get("objectives", [])
		for index in range(objectives.size()):
			if not objectives[index] is Dictionary:
				continue
			var objective: Dictionary = objectives[index]
			var objective_type_value := str(objective.get("type", ""))
			if objective_type_value != objective_type and not (objective_type == "area_trigger" and objective_type_value == "area_trigger"):
				continue
			var expected := str(objective.get("event_name", objective.get("name", objective.get("id", ""))))
			if expected != event_name:
				continue
			var key := _objective_key(objective, index)
			var required := maxi(1, int(objective.get("count", 1)))
			var was_complete := int(counters.get(key, 0)) >= required
			counters[key] = mini(required, int(counters.get(key, 0)) + 1)
			changed = true
			if not was_complete and int(counters.get(key, 0)) >= required:
				completed.append(key)
		if changed:
			entry["counters"] = counters
			state.set_entry(quest_id, entry)
			_refresh_ready_state(quest_id)
			quest_updated.emit(quest_id)
			for key in completed:
				objective_completed.emit(quest_id, key)


func _refresh_all_ready_states() -> void:
	if config == null or state == null:
		return
	for id_value in config.get_all_quests():
		_refresh_ready_state(int(id_value))


func _refresh_ready_state(quest_id: int) -> void:
	var status := state.get_status(quest_id)
	if status not in ["active", "ready"]:
		return
	var next_status := "ready" if _all_objectives_complete(quest_id) else "active"
	if next_status == status:
		return
	var entry := state.get_entry(quest_id)
	entry["status"] = next_status
	state.set_entry(quest_id, entry)
	if next_status == "ready":
		quest_ready.emit(quest_id)
		# 自动续播/自动结算任务没有“回 NPC 交付”这一步，避免在最后一段
		# 剧情对白播放前给玩家错误提示。
		if not bool(config.get_quest(quest_id).get("auto_complete", false)):
			notification_requested.emit("任务目标已完成，可回去交付")
	quest_updated.emit(quest_id)


func _all_objectives_complete(quest_id: int) -> bool:
	var objectives: Array = config.get_quest(quest_id).get("objectives", [])
	if objectives.is_empty():
		return true
	for index in range(objectives.size()):
		if objectives[index] is Dictionary and not bool(get_objective_progress(quest_id, objectives[index], index).get("complete", false)):
			return false
	return true


func _objective_key(objective: Dictionary, index: int) -> String:
	var explicit := str(objective.get("id", ""))
	return explicit if not explicit.is_empty() else "%s_%d" % [str(objective.get("type", "objective")), index]


func _apply_rewards(quest: Dictionary) -> void:
	var rewards: Dictionary = quest.get("rewards", {})
	for item_value in rewards.get("items", []):
		if item_value is Dictionary and inventory != null:
			inventory.add_item(int(item_value.get("item_id", 0)), maxi(1, int(item_value.get("count", 1))))
	for flag_value in rewards.get("flags", []):
		# 兼容两种写法：字符串即 flag 名（置 true），Dictionary 为 {"flag", "value"}。
		if flag_value is String or flag_value is StringName:
			state.set_flag(str(flag_value), true)
		elif flag_value is Dictionary:
			state.set_flag(str(flag_value.get("flag", "")), flag_value.get("value", true))


func _apply_progression_rewards(quest_id: int, quest: Dictionary) -> void:
	if quest_id == 1004 and roster != null:
		state.set_flag("PartyStage", "Duo")
	if quest_id == 1007 and roster != null:
		var recruited_id := roster.recruit_remaining_prologue_hero()
		if recruited_id > 0:
			state.set_flag("ThirdHero", recruited_id)
		state.set_flag("PartyStage", "Trio")
	var chapter_id := str(quest.get("completes_chapter", ""))
	if chapter_id.is_empty():
		match quest_id:
			1008: chapter_id = "chapter_1"
			1012: chapter_id = "chapter_2"
			1030: chapter_id = "chapter_6"
	if not chapter_id.is_empty() and GameRegistry.chapter_service != null:
		GameRegistry.chapter_service.complete_chapter_normal(chapter_id)
		state.set_flag("chapter_completed:%s" % chapter_id, true)
	GameRegistry.save_game()


func _on_inventory_changed(_value: Variant) -> void:
	_refresh_all_ready_states()
