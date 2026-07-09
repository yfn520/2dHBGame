class_name EquipmentData

signal equipped(slot: String, item_uid: int, item_id: int)
signal unequipped(slot: String, item_uid: int, item_id: int)

const SLOTS := ["weapon", "armor", "boots", "accessory"]

var _equipped_by_character: Dictionary = {}


func get_current_character_id() -> int:
	if GameRegistry.roster_data != null:
		return int(GameRegistry.roster_data.active_character_id)
	return CharacterRosterData.DEFAULT_CHARACTER_ID


func get_equipped_uid(slot: String, character_id: int = 0) -> int:
	var data := _get_slot_data(slot, character_id)
	return int(data.get("uid", 0))


func get_equipped_item_id(slot: String, character_id: int = 0) -> int:
	var data := _get_slot_data(slot, character_id)
	return int(data.get("item_id", 0))


func get_all_equipped(character_id: int = 0) -> Dictionary:
	var id := _resolve_character_id(character_id)
	return _equipped_by_character.get(str(id), {}).duplicate(true)


func equip(slot: String, item_uid: int, item_id: int, character_id: int = 0) -> bool:
	if not slot in SLOTS:
		push_error("无效的装备槽位: %s" % slot)
		return false
	var id := _resolve_character_id(character_id)
	var key := str(id)
	var equipped_slots: Dictionary = _equipped_by_character.get(key, {})
	equipped_slots[slot] = {"uid": item_uid, "item_id": item_id}
	_equipped_by_character[key] = equipped_slots
	equipped.emit(slot, item_uid, item_id)
	return true


func unequip(slot: String, character_id: int = 0) -> Dictionary:
	var id := _resolve_character_id(character_id)
	var key := str(id)
	var equipped: Dictionary = _equipped_by_character.get(key, {})
	var data: Dictionary = equipped.get(slot, {})
	if data.is_empty():
		return {}
	var uid := int(data.get("uid", 0))
	var item_id := int(data.get("item_id", 0))
	equipped.erase(slot)
	_equipped_by_character[key] = equipped
	unequipped.emit(slot, uid, item_id)
	return {"uid": uid, "item_id": item_id}


func get_slot_for_type(item_type: String) -> String:
	if item_type in SLOTS:
		return item_type
	return ""


func to_dict() -> Dictionary:
	return {
		"by_character": _equipped_by_character.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_equipped_by_character.clear()
	if data.has("by_character"):
		var raw: Dictionary = data.get("by_character", {})
		for character_id in raw:
			_equipped_by_character[str(character_id)] = _normalize_equipped(raw[character_id])
	else:
		# v1 旧格式：只有一套装备，迁移到默认角色。
		_equipped_by_character[str(CharacterRosterData.DEFAULT_CHARACTER_ID)] = _normalize_equipped(data.get("equipped", {}))


func _get_slot_data(slot: String, character_id: int) -> Dictionary:
	var id := _resolve_character_id(character_id)
	var equipped: Dictionary = _equipped_by_character.get(str(id), {})
	return equipped.get(slot, {})


func _resolve_character_id(character_id: int) -> int:
	return get_current_character_id() if character_id == 0 else character_id


func _normalize_equipped(raw_value) -> Dictionary:
	var result: Dictionary = {}
	if not raw_value is Dictionary:
		return result
	for slot in raw_value:
		var entry: Dictionary = raw_value[slot]
		result[String(slot)] = {
			"uid": int(entry.get("uid", 0)),
			"item_id": int(entry.get("item_id", 0)),
		}
	return result
