class_name PlayerDataProvider

var inventory: InventoryData
var equipment: EquipmentData
var roster: CharacterRosterData
var character_config: CharacterConfigData


func _init(p_inventory: InventoryData, p_equipment: EquipmentData, p_roster: CharacterRosterData, p_character_config: CharacterConfigData) -> void:
	inventory = p_inventory
	equipment = p_equipment
	roster = p_roster
	character_config = p_character_config


func load_local() -> bool:
	var loaded := SaveManager.load_save(inventory, equipment, roster, character_config)
	if not loaded or inventory.get_items().is_empty():
		_apply_local_mock_snapshot()
	return loaded


func save_local() -> void:
	SaveManager.save(inventory, equipment, roster)


func apply_server_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("inventory"):
		inventory.from_dict(snapshot.get("inventory", {}))
	if snapshot.has("equipment"):
		equipment.from_dict(snapshot.get("equipment", {}))
	roster.apply_server_snapshot(snapshot)


func _apply_local_mock_snapshot() -> void:
	apply_server_snapshot({
		"inventory": {
			"next_uid": 40,
			"items": [
				{"uid": 1, "item_id": 100001, "count": 1},
				{"uid": 2, "item_id": 100002, "count": 1},
				{"uid": 3, "item_id": 100003, "count": 1},
				{"uid": 4, "item_id": 100004, "count": 1},
				{"uid": 5, "item_id": 100005, "count": 1},
				{"uid": 6, "item_id": 100006, "count": 1},
				{"uid": 7, "item_id": 100007, "count": 1},
				{"uid": 8, "item_id": 100008, "count": 1},
				{"uid": 9, "item_id": 100011, "count": 1},
				{"uid": 10, "item_id": 100013, "count": 1},
				{"uid": 20, "item_id": 100014, "count": 12},
				{"uid": 21, "item_id": 100015, "count": 3},
				{"uid": 30, "item_id": 100016, "count": 35},
				{"uid": 31, "item_id": 100017, "count": 18}
			]
		},
		"equipment": {
			"by_character": {
				"7001": {
				"weapon": {"uid": 101, "item_id": 100009},
				"armor": {"uid": 102, "item_id": 100010},
				"ring": {"uid": 103, "item_id": 100004}
			}
		}
	},
	"characters": {
		"7001": {"character_id": 7001, "level": 1, "exp": 60, "hp": -1}
	},
	"lineup_ids": [7001],
	"active_character_id": 7001,
	"active_index": 0
})
