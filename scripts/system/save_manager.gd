class_name SaveManager

const SAVE_PATH := "user://savegame.json"
const CURRENT_VERSION := 3


static func save(inventory: InventoryData, equipment: EquipmentData, roster: CharacterRosterData, quest_state: QuestStateData = null) -> void:
	var data := {
		"version": CURRENT_VERSION,
		"inventory": inventory.to_dict(),
		"equipment": equipment.to_dict(),
		"roster": roster.to_dict(),
		"active_character_id": roster.active_character_id,
		"lineup_ids": roster.lineup_ids,
		"world_state": quest_state.to_dict() if quest_state != null else {},
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("存档写入失败: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	print("存档已保存")


static func load_save(inventory: InventoryData, equipment: EquipmentData, roster: CharacterRosterData, character_config: CharacterConfigData, quest_state: QuestStateData = null) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		roster.setup_defaults(character_config)
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		roster.setup_defaults(character_config)
		return false
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK or not json.data is Dictionary:
		push_error("存档解析失败")
		roster.setup_defaults(character_config)
		return false
	var data: Dictionary = json.data
	var version := int(data.get("version", 0))
	inventory.from_dict(data.get("inventory", {}))
	equipment.from_dict(data.get("equipment", {}))
	if version >= 2:
		var roster_data: Dictionary = data.get("roster", {})
		if roster_data.is_empty():
			roster_data = {
				"characters": data.get("characters", {}),
				"lineup_ids": data.get("lineup_ids", []),
				"active_character_id": data.get("active_character_id", 0),
				"active_index": data.get("active_index", 0),
			}
		roster.from_dict(roster_data, character_config)
	else:
		roster.from_legacy_stats(data.get("stats", {}), character_config)
	if quest_state != null:
		quest_state.from_dict(data.get("world_state", {}) if version >= 3 else {})
	print("存档已加载")
	return true


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
