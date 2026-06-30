class_name EquipmentData

signal equipped(slot: String, item_uid: int, item_id: int)
signal unequipped(slot: String, item_uid: int, item_id: int)

const SLOTS := ["weapon", "armor", "boots", "accessory"]

# slot -> { "uid": int, "item_id": int }
var _equipped: Dictionary = {}


func get_equipped_uid(slot: String) -> int:
	var data: Dictionary = _equipped.get(slot, {})
	return int(data.get("uid", 0))


func get_equipped_item_id(slot: String) -> int:
	var data: Dictionary = _equipped.get(slot, {})
	return int(data.get("item_id", 0))


func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()


# ---- 穿戴 ----

func equip(slot: String, item_uid: int, item_id: int) -> bool:
	if not slot in SLOTS:
		push_error("无效的装备槽位: %s" % slot)
		return false
	_equipped[slot] = { "uid": item_uid, "item_id": item_id }
	equipped.emit(slot, item_uid, item_id)
	return true


func unequip(slot: String) -> Dictionary:
	var data: Dictionary = _equipped.get(slot, {})
	if data.is_empty():
		return {}
	var uid := int(data.get("uid", 0))
	var item_id := int(data.get("item_id", 0))
	_equipped.erase(slot)
	unequipped.emit(slot, uid, item_id)
	return { "uid": uid, "item_id": item_id }


func get_slot_for_type(item_type: String) -> String:
	if item_type in SLOTS:
		return item_type
	return ""


# ---- 存档 ----

func to_dict() -> Dictionary:
	return {
		"equipped": _equipped.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_equipped.clear()
	var raw: Dictionary = data.get("equipped", {})
	for slot in raw:
		var entry: Dictionary = raw[slot]
		_equipped[slot] = {
			"uid": int(entry.get("uid", 0)),
			"item_id": int(entry.get("item_id", 0)),
		}
