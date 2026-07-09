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
	return SaveManager.load_save(inventory, equipment, roster, character_config)


func save_local() -> void:
	SaveManager.save(inventory, equipment, roster)


func apply_server_snapshot(snapshot: Dictionary) -> void:
	if snapshot.has("inventory"):
		inventory.from_dict(snapshot.get("inventory", {}))
	if snapshot.has("equipment"):
		equipment.from_dict(snapshot.get("equipment", {}))
	roster.apply_server_snapshot(snapshot)
