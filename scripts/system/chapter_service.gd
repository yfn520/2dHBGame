class_name ChapterService
extends Node

## 章节推进服务：管理章节解锁、正史完成、回响切换。
## 设计案 §7/§8：6 章主线，首次通关后副本改刷"守护者回响"。

signal chapter_unlocked(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal echo_mode_unlocked(chapter_id: String)

var _chapter_config: ChapterConfig
var _completed_normal: Dictionary = {}  # chapter_id -> bool 正史是否完成
var _echo_unlocked: Dictionary = {}     # chapter_id -> bool 回响是否开启
var _current_chapter_id: String = ""


func setup(chapter_config: ChapterConfig) -> void:
	_chapter_config = chapter_config
	# 默认解锁序章
	var ordered := _chapter_config.get_ordered_chapter_ids()
	if not ordered.is_empty():
		_current_chapter_id = ordered[0]


func get_current_chapter() -> String:
	return _current_chapter_id


func set_current_chapter(chapter_id: String) -> void:
	if _chapter_config.is_valid_chapter(chapter_id):
		_current_chapter_id = chapter_id


func is_chapter_unlocked(chapter_id: String) -> bool:
	# 序章永远解锁
	if chapter_id == "prologue":
		return true
	var chapter := _chapter_config.get_chapter(chapter_id)
	if chapter.is_empty():
		return false
	var required := str(chapter.get("required_previous_chapter_id", ""))
	if required.is_empty():
		return true
	return _completed_normal.get(required, false)


func is_normal_completed(chapter_id: String) -> bool:
	return _completed_normal.get(chapter_id, false)


func is_echo_unlocked(chapter_id: String) -> bool:
	return _echo_unlocked.get(chapter_id, false)


## 关卡 → 章节（按 chapters.json 的 dungeon_level_ids 反查；json 数字在 GDScript 里是 float，统一转 int 比较）。
func get_chapter_for_level(level_id: int) -> String:
	if _chapter_config == null:
		return ""
	for chapter_id in _chapter_config.get_ordered_chapter_ids():
		var chapter := _chapter_config.get_chapter(str(chapter_id))
		var levels = chapter.get("dungeon_level_ids", [])
		if levels is Array:
			for value in levels:
				if int(value) == level_id:
					return str(chapter_id)
	return ""


func get_chapter_name(chapter_id: String) -> String:
	if _chapter_config == null:
		return ""
	return str(_chapter_config.get_chapter(chapter_id).get("name", ""))


## 回响整图通关次数（world_state flags，随存档）。
func get_echo_clears(chapter_id: String) -> int:
	if GameRegistry.quest_state == null:
		return 0
	return int(GameRegistry.quest_state.get_flag("echo_clears:%s" % chapter_id, 0))


## 回响整图清完 +1（enemy_spawner 全灭时调用）。
func record_echo_clear(chapter_id: String) -> void:
	if chapter_id.is_empty() or GameRegistry.quest_state == null:
		return
	GameRegistry.quest_state.set_flag("echo_clears:%s" % chapter_id, get_echo_clears(chapter_id) + 1)
	GameRegistry.save_game()


## 回响 Boss 击杀次数（world_state flags，供成就、统计和后续任务读取）。
func get_echo_boss_kills(chapter_id: String) -> int:
	if GameRegistry.quest_state == null:
		return 0
	return int(GameRegistry.quest_state.get_flag("echo_boss_kills:%s" % chapter_id, 0))


func record_echo_boss_kill(chapter_id: String) -> void:
	if chapter_id.is_empty() or GameRegistry.quest_state == null:
		return
	GameRegistry.quest_state.set_flag("echo_boss_kills:%s" % chapter_id, get_echo_boss_kills(chapter_id) + 1)
	GameRegistry.save_game()


## 完成章节正史（首次通关调用）。会自动开启该章回响，并解锁下一章。
func complete_chapter_normal(chapter_id: String) -> void:
	if _completed_normal.get(chapter_id, false):
		return
	_completed_normal[chapter_id] = true
	_echo_unlocked[chapter_id] = true
	chapter_completed.emit(chapter_id)
	echo_mode_unlocked.emit(chapter_id)
	# 自动推进当前章节到下一章
	var ordered := _chapter_config.get_ordered_chapter_ids()
	var idx := ordered.find(chapter_id)
	if idx >= 0 and idx + 1 < ordered.size():
		_current_chapter_id = ordered[idx + 1]
		chapter_unlocked.emit(_current_chapter_id)


## 获取当前章节生效的节点集合（正史 vs 回响）。
## 返回该章节的 story_node_ids，若某节点有 repeat_replacement_node_id 且回响已开启，则替换为回响节点。
func get_active_node_ids(chapter_id: String) -> Array[String]:
	var chapter := _chapter_config.get_chapter(chapter_id)
	if chapter.is_empty():
		return []
	var node_ids: Array[String] = chapter.get("story_node_ids", [])
	if not is_echo_unlocked(chapter_id):
		return node_ids
	# 回响已开启：替换有 repeat_replacement_node_id 的节点
	var result: Array[String] = []
	# 需要访问 story_node_config，通过 GameRegistry 获取
	var story_node_config: StoryNodeConfig = null
	if GameRegistry != null and GameRegistry.get("story_node_config") != null:
		story_node_config = GameRegistry.story_node_config
	for node_id in node_ids:
		var replacement := ""
		if story_node_config != null:
			var node := story_node_config.get_story_node(node_id)
			replacement = str(node.get("repeat_replacement_node_id", ""))
		if replacement.is_empty():
			result.append(node_id)
		else:
			result.append(replacement)
	return result


## 判断节点在当前存档是否可见（前置条件校验）。
func is_node_visible(node_id: String, story_node_config: StoryNodeConfig, protagonist_hero_id: int, pact_legacy_stage: int) -> bool:
	if story_node_config == null:
		return true
	var node := story_node_config.get_story_node(node_id)
	if node.is_empty():
		return false
	# 主角前置
	var required_lead := int(node.get("required_lead_hero_id", 0))
	if required_lead != 0 and protagonist_hero_id != required_lead:
		return false
	# 英雄前置（暂用 required_hero_id，后续接 roster）
	var required_hero := int(node.get("required_hero_id", 0))
	if required_hero != 0:
		# TODO: 检查英雄是否在阵容
		pass
	# 主契阶段前置
	var required_stage := int(node.get("required_pact_stage", 0))
	if required_stage > 0 and pact_legacy_stage < required_stage:
		return false
	# 章节前置
	var chapter_id := str(node.get("chapter_id", ""))
	if not chapter_id.is_empty() and not is_chapter_unlocked(chapter_id):
		return false
	return true


func to_dict() -> Dictionary:
	return {
		"completed_normal": _completed_normal.duplicate(true),
		"echo_unlocked": _echo_unlocked.duplicate(true),
		"current_chapter_id": _current_chapter_id,
	}


func from_dict(data: Dictionary) -> void:
	_completed_normal = data.get("completed_normal", {}).duplicate(true)
	_echo_unlocked = data.get("echo_unlocked", {}).duplicate(true)
	_current_chapter_id = str(data.get("current_chapter_id", ""))
