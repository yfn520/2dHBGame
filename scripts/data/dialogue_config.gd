class_name DialogueConfig

const CONFIG_PATH := "res://data/dialogues.json"

var _dialogues: Dictionary = {}


func load_config() -> void:
	_dialogues = _read_json(CONFIG_PATH).duplicate(true)


func get_dialogue(dialogue_id: String) -> Dictionary:
	return (_dialogues.get(dialogue_id, {}) as Dictionary).duplicate(true)


func get_all_dialogues() -> Dictionary:
	return _dialogues.duplicate(true)


## 读取时间轴格式对话（tracks + clips + entries；仅 timeline 格式返回，节点图格式返回空）。
func get_timeline(dialogue_id: String) -> Dictionary:
	var dialogue := get_dialogue(dialogue_id)
	if str(dialogue.get("format", "")) != "timeline":
		return {}
	return dialogue


## 时间轴格式：某 NPC 的入口时间点（毫秒）；无则回退 entry_ms/0。
func get_timeline_entry_ms(dialogue_id: String, key: String) -> int:
	var timeline := get_timeline(dialogue_id)
	if timeline.is_empty():
		return 0
	var entries: Dictionary = timeline.get("entries", {})
	if entries.has(key):
		return int(entries.get(key, 0))
	return int(timeline.get("entry_ms", 0))


## 时间轴格式：某 NPC 的交付专用入口（毫秒）——任务 ready 后 turn_in 从交付段开始，
## 不重播该 NPC 首句台词所在的追踪段（如仓库看守的领装备段）。
## 无 turn_in_entries 时回退普通入口（行为与旧版一致）。
func get_timeline_turn_in_entry_ms(dialogue_id: String, key: String) -> int:
	var timeline := get_timeline(dialogue_id)
	if timeline.is_empty():
		return 0
	var entries: Dictionary = timeline.get("turn_in_entries", {})
	if entries.has(key):
		return int(entries.get(key, 0))
	return get_timeline_entry_ms(dialogue_id, key)


## 时间轴格式：某阶段第一个片段的时间点（毫秒）；阶段不存在返回 -1。
## 用于对话中断后从任务当前阶段接播，而不是重播接取台词。
func get_timeline_stage_entry_ms(dialogue_id: String, stage_id: String) -> int:
	var timeline := get_timeline(dialogue_id)
	if timeline.is_empty() or stage_id.is_empty():
		return -1
	var first_ms := -1
	for clip_value in (timeline.get("clips", []) as Array):
		if not clip_value is Dictionary:
			continue
		if str((clip_value as Dictionary).get("stageId", "")) != stage_id:
			continue
		var clip_ms := int((clip_value as Dictionary).get("startMs", 0))
		if first_ms < 0 or clip_ms < first_ms:
			first_ms = clip_ms
	return first_ms


func get_dialogue_chapter_id(dialogue_id: String) -> String:
	var dialogue := get_dialogue(dialogue_id)
	return str(dialogue.get("chapter_id", ""))


func get_dialogue_story_node_id(dialogue_id: String) -> String:
	var dialogue := get_dialogue(dialogue_id)
	return str(dialogue.get("story_node_id", ""))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("对话配置解析失败: %s" % path)
		return {}
	return json.data
