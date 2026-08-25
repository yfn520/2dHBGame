class_name StoryAutoPlay
extends Node
## 开局选角 + 纯对白任务自动链：
## - 新档首关加载后播放选角对话 opening_lead_choice（可跳过，跳过用场景配置的默认主角）；
## - 链推进只跟随"刚完成的任务"：下一任务的 required_quest_ids 必须包含刚完成的任务，
##   避免前置为空（事件触发型）的任务被自动链跨章节抢跑；
## - 启动时只恢复真正的续点（有前置且已解锁）或链上第一个任务；
## - 链不再跨关卡传送玩家（仅开局首次允许定位到首任务场景），其余在对应场景内触发。

const OPENING_DIALOGUE_ID := "opening_lead_choice"
const OPENING_FLAG := "opening_done"

var quest_service: QuestService
var dialogue_service: DialogueService

var _bootstrapped := false
var _playing_quest_id := 0
var _opening_pending := false
# 开局首次启动链时允许一次场景定位；之后链不再替玩家切关卡
var _opening_positioned := false


func setup(p_quest_service: QuestService, p_dialogue_service: DialogueService) -> void:
	quest_service = p_quest_service
	dialogue_service = p_dialogue_service
	dialogue_service.dialogue_finished.connect(_on_dialogue_finished)
	# 任务完成（含手动玩法任务）后尝试推进自动链：只接续"以该任务为前置"的下一任务
	quest_service.quest_completed.connect(_on_quest_completed)
	# auto_start 挑战段（纯战斗/收集、无接取 NPC）：目标达成（ready）即自动交付
	quest_service.quest_ready.connect(_on_quest_ready)


## auto_complete 任务的 ready 即完成（auto_start 挑战段打完即过）。
## auto_play 过场任务播放中不抢跑：由对话收尾统一处理，避免完成通知早于过场弹出。
func _on_quest_ready(quest_id: int) -> void:
	if quest_service == null or quest_service.config == null:
		return
	if _playing_quest_id == quest_id:
		return
	var quest: Dictionary = quest_service.config.get_quest(quest_id)
	if quest.is_empty() or not bool(quest.get("auto_complete", false)):
		return
	quest_service.turn_in_quest(quest_id)


func _on_quest_completed(quest_id: int) -> void:
	call_deferred("_advance_chain", quest_id)


## 玩家进入某关卡时，尝试恢复属于该关卡的自动链（场景门槛停下后的唤醒点）。
func on_level_loaded(level_id: int) -> void:
	call_deferred("_advance_chain", -1, level_id)


## 首关加载完成后由 GameRoot 调用（只生效一次）。
func bootstrap() -> void:
	if _bootstrapped:
		return
	_bootstrapped = true
	if quest_service == null or dialogue_service == null or quest_service.state == null:
		return
	if dialogue_service.is_active():
		return
	if not bool(quest_service.state.get_flag(OPENING_FLAG, false)):
		quest_service.state.set_flag(OPENING_FLAG, true)
		GameRegistry.save_game()
		# 已选过主角的老存档直接进任务链；未选角则先播选角对话
		if quest_service.roster != null and quest_service.roster.get_protagonist_hero_id() > 0:
			call_deferred("_chain_entry")
		else:
			_opening_pending = true
			# 选角用纯黑电影模式；任务过场不加，保留场景画面
			if not dialogue_service.start_cutscene(OPENING_DIALOGUE_ID, 0, true):
				_opening_pending = false
				call_deferred("_chain_entry")
		return
	call_deferred("_chain_entry")


## 启动入口：先恢复上次被打断的自动任务（active 但对话未播完），再尝试推进链。
func _chain_entry() -> void:
	if _resume_interrupted():
		return
	_advance_chain()


## 重新播放卡在 active 的自动任务过场（退出游戏时对话被中断的情况）。
func _resume_interrupted() -> bool:
	if dialogue_service.is_active() or quest_service == null or quest_service.config == null:
		return false
	var ids: Dictionary = quest_service.config.get_all_quests()
	var sorted_ids: Array[int] = []
	for value in ids.keys():
		sorted_ids.append(int(value))
	sorted_ids.sort()
	for quest_id in sorted_ids:
		var quest: Dictionary = quest_service.config.get_quest(quest_id)
		if not bool(quest.get("auto_play", false)):
			continue
		if quest_service.get_status(quest_id) != "active":
			continue
		var dialogue_id := str((quest.get("authoring", {}) as Dictionary).get("dialogue_id", ""))
		if dialogue_id.is_empty():
			continue
		_playing_quest_id = quest_id
		if not dialogue_service.start_cutscene(dialogue_id, int(quest.get("giver_npc_id", 0))):
			_playing_quest_id = 0
		return true
	return false


func _on_dialogue_finished(npc_id: int, completed: bool) -> void:
	# 手动任务的自动播放段（时间轴 autoplay_segments）：目标 NPC 对话收尾后接下一段过场，
	# 与开场选角/自动链状态无关，延后到 finish 清理完成再尝试。
	if completed:
		call_deferred("_try_autoplay_segments", npc_id)
	# 选角对话结束 → 进入自动链
	if _opening_pending:
		_opening_pending = false
		if completed:
			call_deferred("_advance_chain")
		return
	if not completed or _playing_quest_id <= 0:
		_playing_quest_id = 0
		return
	var quest_id := _playing_quest_id
	_playing_quest_id = 0
	if quest_service == null or quest_service.config == null:
		return
	var quest: Dictionary = quest_service.config.get_quest(quest_id)
	if quest.is_empty():
		return
	# 过场播完视为与接取 NPC 完成了一次对话，推进 talk 目标
	var giver := int(quest.get("giver_npc_id", 0))
	if giver > 0:
		quest_service.record_talk(giver)
	if bool(quest.get("auto_complete", false)) and quest_service.get_status(quest_id) == "ready":
		# turn_in_quest 会发 quest_completed → _on_quest_completed 负责接续下一任务
		quest_service.turn_in_quest(quest_id)


## 时间轴 autoplay_segments：与指定 NPC 的对话收尾后，自动从段起点接过场播放。
## C1-02-A 的芦苇滩途中对白（S02）没有任何目标/入口钩子，不自动接播会永久丢失。
## 播前写旗标保证只触发一次；过场自身收尾（npc_id=0）不会命中任何段，无自触发环。
func _try_autoplay_segments(npc_id: int) -> void:
	if npc_id <= 0 or quest_service == null or quest_service.config == null or quest_service.state == null:
		return
	if dialogue_service == null or dialogue_service.is_active():
		return
	for id_value in quest_service.config.get_all_quests():
		var quest_id := int(id_value)
		if quest_service.get_status(quest_id) != "active":
			continue
		var quest: Dictionary = quest_service.config.get_quest(quest_id)
		var dialogue_id := str((quest.get("authoring", {}) as Dictionary).get("dialogue_id", ""))
		if dialogue_id.is_empty():
			continue
		var timeline: Dictionary = dialogue_service.dialogue_config.get_timeline(dialogue_id)
		if timeline.is_empty():
			continue
		for segment_value in timeline.get("autoplay_segments", []):
			if not segment_value is Dictionary:
				continue
			var segment: Dictionary = segment_value
			if int(segment.get("npc_id", 0)) != npc_id:
				continue
			var entry_ms := int(segment.get("entry_ms", 0))
			var flag_key := "autoplay_segment:%s:%d" % [dialogue_id, entry_ms]
			if bool(quest_service.state.get_flag(flag_key, false)):
				continue
			quest_service.state.set_flag(flag_key, true)
			GameRegistry.save_game()
			dialogue_service.start_cutscene(dialogue_id, 0, false, entry_ms)
			return


## 推进自动链。trigger_quest_id >= 0 时只接续"以该任务为前置"的自动任务；
## 无触发（启动/选角后）时只恢复有前置的续点或链上第一个任务，不抢跑事件触发型任务；
## only_level_id >= 0 时只处理属于该关卡的任务（玩家进入关卡时的恢复）。
## 链任务含两类：auto_play（过场：接取+播对话）与 auto_start（挑战段：仅自动接取，不播对话）。
func _advance_chain(trigger_quest_id: int = -1, only_level_id: int = -1) -> void:
	if quest_service == null or quest_service.config == null or dialogue_service == null:
		return
	if dialogue_service.is_active():
		return
	var ids: Dictionary = quest_service.config.get_all_quests()
	var sorted_ids: Array[int] = []
	for value in ids.keys():
		sorted_ids.append(int(value))
	sorted_ids.sort()
	var first_auto_id := -1
	for quest_id in sorted_ids:
		var q: Dictionary = quest_service.config.get_quest(quest_id)
		if bool(q.get("auto_play", false)) or bool(q.get("auto_start", false)):
			first_auto_id = quest_id
			break
	for quest_id in sorted_ids:
		var quest: Dictionary = quest_service.config.get_quest(quest_id)
		var is_auto_play := bool(quest.get("auto_play", false))
		var is_auto_start := bool(quest.get("auto_start", false))
		if not is_auto_play and not is_auto_start:
			continue
		if quest_service.get_status(quest_id) != "inactive":
			continue
		if not quest_service.is_quest_unlocked(quest_id):
			continue
		if only_level_id >= 0 and int(quest.get("level_id", -1)) != only_level_id:
			continue
		# 链推进门槛：跟随刚完成的任务；启动时只允许链首任务或"前置齐全"的续点
		var required: Array = quest.get("required_quest_ids", []) as Array
		if trigger_quest_id >= 0:
			var requires_trigger := false
			for req in required:
				if int(req) == trigger_quest_id:
					requires_trigger = true
					break
			if not requires_trigger:
				continue
		elif required.is_empty() and quest_id != first_auto_id:
			continue
		# 场景门槛：仅开局首次允许定位到首任务场景；之后链不跨关卡传送
		if GameRegistry.level_manager != null:
			var level_id := int(quest.get("level_id", -1))
			if level_id >= 0 and int(GameRegistry.level_manager.get_current_level_id()) != level_id:
				if _opening_positioned:
					quest_service.notification_requested.emit("剧情过场将在对应场景继续")
					return
				GameRegistry.level_manager.load_level(level_id)
		_opening_positioned = true
		if not quest_service.start_quest(quest_id):
			continue
		# auto_start 挑战段：只接取不播过场（目标由玩家战斗/收集推进，ready 即自动交付）
		if not is_auto_play:
			return
		var dialogue_id := str((quest.get("authoring", {}) as Dictionary).get("dialogue_id", ""))
		if dialogue_id.is_empty():
			continue
		_playing_quest_id = quest_id
		if not dialogue_service.start_cutscene(dialogue_id, int(quest.get("giver_npc_id", 0))):
			_playing_quest_id = 0
		return
