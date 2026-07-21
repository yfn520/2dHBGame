class_name QuestStateData

var quests: Dictionary = {}
var flags: Dictionary = {}


func get_status(quest_id: int) -> String:
	return String((quests.get(str(quest_id), {}) as Dictionary).get("status", "inactive"))


func get_entry(quest_id: int) -> Dictionary:
	return (quests.get(str(quest_id), {}) as Dictionary).duplicate(true)


func set_entry(quest_id: int, entry: Dictionary) -> void:
	quests[str(quest_id)] = entry.duplicate(true)


func get_flag(flag_name: String, default_value: Variant = false) -> Variant:
	return flags.get(flag_name, default_value)


func set_flag(flag_name: String, value: Variant) -> void:
	if not flag_name.is_empty():
		flags[flag_name] = value


func to_dict() -> Dictionary:
	return {"quests": quests.duplicate(true), "flags": flags.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	quests = (data.get("quests", {}) as Dictionary).duplicate(true)
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
