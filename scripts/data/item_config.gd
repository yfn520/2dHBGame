class_name ItemConfig

const CONFIG_PATH := "res://data/items.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载物品配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("物品配置解析失败: %s" % json.get_error_message())
		return
	var data := json.data as Dictionary
	for item_id_str in data:
		var item_id := int(item_id_str)
		var raw: Dictionary = data[item_id_str]
		_items[item_id] = {
			"id": item_id,
			"name": raw.get("name", ""),
			"type": raw.get("type", ""),
			"description": raw.get("description", ""),
			"stackable": raw.get("stackable", false),
			"max_count": raw.get("max_count", 1),
			"stats": raw.get("stats", {}),
			"heal_amount": raw.get("heal_amount", 0),
		}
	_loaded = true


func get_item(item_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(item_id, {})


func get_all_items() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_item(item_id: int) -> bool:
	if not _loaded:
		load_config()
	return _items.has(item_id)


func get_item_type(item_id: int) -> String:
	return get_item(item_id).get("type", "")


func is_stackable(item_id: int) -> bool:
	return get_item(item_id).get("stackable", false)


func get_max_count(item_id: int) -> int:
	return get_item(item_id).get("max_count", 1)


func get_equip_slot(item_id: int) -> String:
	var item_type := get_item_type(item_id)
	# type 直接就是装备槽位名: weapon, armor, boots, accessory
	if item_type in ["weapon", "armor", "boots", "accessory"]:
		return item_type
	return ""
