class_name PlayerDataProvider

var inventory: InventoryData
var equipment: EquipmentData
var roster: CharacterRosterData
var character_config: CharacterConfigData
var quest_state: QuestStateData
var chapter_state: ChapterStateData
var _loaded_local_save := false


func _init(p_inventory: InventoryData, p_equipment: EquipmentData, p_roster: CharacterRosterData, p_character_config: CharacterConfigData, p_quest_state: QuestStateData = null, p_chapter_state: ChapterStateData = null) -> void:
	inventory = p_inventory
	equipment = p_equipment
	roster = p_roster
	character_config = p_character_config
	quest_state = p_quest_state
	chapter_state = p_chapter_state


func load_local() -> bool:
	_loaded_local_save = SaveManager.load_save(inventory, equipment, roster, character_config, quest_state, chapter_state)
	if not _loaded_local_save or inventory.get_items().is_empty():
		_apply_local_mock_snapshot()
	return _loaded_local_save


func has_loaded_local_save() -> bool:
	return _loaded_local_save


func save_local() -> void:
	SaveManager.save(inventory, equipment, roster, quest_state, chapter_state)


func apply_server_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("inventory"):
		inventory.from_dict(snapshot.get("inventory", {}))
	if snapshot.has("equipment"):
		equipment.from_dict(snapshot.get("equipment", {}))
	roster.apply_server_snapshot(snapshot)
	if quest_state != null and snapshot.has("world_state"):
		quest_state.from_dict(snapshot.get("world_state", {}))


func _apply_local_mock_snapshot() -> void:
	apply_server_snapshot({
		"inventory": {
			"next_uid": 1,
			"items": []
		},
		"equipment": {
			"by_character": {}
		},
		"characters": {
			"7001": {"character_id": 7001, "level": 1, "exp": 60, "hp": -1}
		},
		"lineup_ids": [7001],
		"active_character_id": 7001,
		"active_index": 0
	})
