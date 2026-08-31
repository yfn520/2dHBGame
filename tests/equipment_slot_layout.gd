extends SceneTree

const EquipmentDataScript = preload("res://scripts/data/equipment_data.gd")
const ItemConfigScript = preload("res://scripts/data/item_config.gd")

const EXPECTED_SLOTS := ["head", "necklace", "body", "legs", "boots", "hands", "waist", "ring_left", "ring_right", "accessory", "weapon", "offhand"]


func _init() -> void:
	var failures: Array[String] = []
	_expect(EquipmentDataScript.SLOTS == EXPECTED_SLOTS, "12-slot order", failures)

	var items = ItemConfigScript.new()
	items.load_config()
	_expect(items.get_equip_slot(100018) == "offhand", "Leon pact legacy uses offhand", failures)
	_expect(items.get_equip_slot(100019) == "weapon", "Luna pact legacy uses main weapon", failures)
	_expect(items.get_equip_slot(100020) == "offhand", "Mia pact legacy uses offhand", failures)
	_expect(items.can_equip_in_slot(100004, "ring_left"), "ring fits left ring slot", failures)
	_expect(items.can_equip_in_slot(100004, "ring_right"), "ring fits right ring slot", failures)
	_expect(not items.can_equip_in_slot(100004, "accessory"), "ring does not fit accessory slot", failures)

	if failures.is_empty():
		print("EQUIPMENT_SLOT_LAYOUT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
