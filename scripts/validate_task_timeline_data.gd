extends SceneTree

const QUESTS_PATH := "res://data/quests.json"
const DIALOGUES_PATH := "res://data/dialogues.json"


func _initialize() -> void:
	var quests := _read_json(QUESTS_PATH)
	var dialogues := _read_json(DIALOGUES_PATH)
	var quest_service_script = load("res://scripts/system/quest_service.gd")
	var dialogue_service_script = load("res://scripts/system/dialogue_service.gd")
	if quest_service_script == null or dialogue_service_script == null:
		_fail("changed Godot runtime script failed to load")
	if quests.size() != 85:
		_fail("expected 85 quests, got %d" % quests.size())
	if dialogues.size() < 85:
		_fail("expected at least 85 dialogues, got %d" % dialogues.size())
	for dialogue_id in dialogues:
		var dialogue: Dictionary = dialogues[dialogue_id]
		if str(dialogue.get("format", "")) != "timeline":
			_fail("dialogue is not timeline: %s" % dialogue_id)
		if _contains_legacy_graph_fields(dialogue):
			_fail("legacy graph field remains: %s" % dialogue_id)
		if _contains_legacy_task_ids(dialogue):
			_fail("legacy task id remains: %s" % dialogue_id)
	var pilot_quest: Dictionary = quests.get("21020", {})
	var pilot_previous: Dictionary = quests.get("21012", {})
	var pilot_followup: Dictionary = quests.get("21021", {})
	var pilot_dialogue: Dictionary = dialogues.get("task_c1_02_a", {})
	if pilot_quest.is_empty() or pilot_dialogue.is_empty():
		_fail("pilot C1-02-A is missing")
	if not _has_numeric_id(pilot_quest.get("required_quest_ids", []), 21012):
		_fail("pilot C1-02-A does not require C1-01-C")
	if not _has_numeric_id(pilot_followup.get("required_quest_ids", []), 21020):
		_fail("pilot C1-02-B does not require C1-02-A")
	if pilot_previous.is_empty():
		_fail("pilot C1-01-C is missing")
	if pilot_quest.get("stages", []).is_empty() or pilot_dialogue.get("clips", []).is_empty():
		_fail("pilot C1-02-A has no stages or clips")
	print("timeline data ok: quests=%d dialogues=%d pilot_clips=%d" % [quests.size(), dialogues.size(), pilot_dialogue.get("clips", []).size()])
	quit()


func _read_json(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		_fail("invalid json: %s" % path)
	return json.data


func _contains_legacy_graph_fields(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key) in ["nodes", "entry_node", "next_id", "next_node"]:
				return true
			if _contains_legacy_graph_fields(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_legacy_graph_fields(item):
				return true
	return false


func _contains_legacy_task_ids(value: Variant, key_name: String = "") -> bool:
	if value is Dictionary:
		for key in value:
			if _contains_legacy_task_ids(value[key], str(key)):
				return true
	elif value is Array:
		for item in value:
			if _contains_legacy_task_ids(item, key_name):
				return true
	elif value is int or value is float:
		var numeric := int(value)
		if key_name in ["quest_id", "questId", "required_quest_id", "requiredQuestId"] and numeric >= 1001 and numeric <= 1030:
			return true
	return false


func _has_numeric_id(value: Variant, expected: int) -> bool:
	if not value is Array:
		return false
	for item in value:
		if int(item) == expected:
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
