class_name EquipmentProvider

signal equipped(slot: String, item_id: int)
signal unequipped(slot: String, item_id: int)

var equipment: EquipmentData
var inventory: InventoryData
var stats: CharacterStats
var item_config: ItemConfig


func _init(p_equipment: EquipmentData, p_inventory: InventoryData, p_stats: CharacterStats, p_config: ItemConfig) -> void:
	equipment = p_equipment
	inventory = p_inventory
	stats = p_stats
	item_config = p_config


func equip_item(item_uid: int) -> bool:
	var item := inventory.get_item_by_uid(item_uid)
	if item == null:
		return false
	var slot := item_config.get_equip_slot(item.item_id)
	if slot.is_empty():
		return false

	var old_uid := equipment.get_equipped_uid(slot)
	if old_uid != 0:
		_unequip_to_inventory(slot)

	inventory.remove_item(item_uid, -1)
	equipment.equip(slot, item_uid, item.item_id)
	equipped.emit(slot, item.item_id)
	_recalculate_stats()
	return true


func unequip_slot(slot: String) -> bool:
	return _unequip_to_inventory(slot)


func get_equipped_configs(character_id: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in EquipmentData.SLOTS:
		var item_id := equipment.get_equipped_item_id(slot, character_id)
		if item_id == 0:
			continue
		var config := item_config.get_item(item_id)
		if not config.is_empty():
			result.append(config)
	return result


func refresh_current_stats() -> void:
	_recalculate_stats()


func _unequip_to_inventory(slot: String) -> bool:
	var uid := equipment.get_equipped_uid(slot)
	if uid == 0:
		return false
	var item_id := equipment.get_equipped_item_id(slot)
	equipment.unequip(slot)
	inventory.add_item(item_id, 1, item_config)
	unequipped.emit(slot, item_id)
	_recalculate_stats()
	return true


func _recalculate_stats() -> void:
	stats.recalculate(get_equipped_configs())
