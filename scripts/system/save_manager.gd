class_name SaveManager
## 存档管理器
## 所有需要持久化的数据都通过这里读写

const SAVE_PATH := "user://savegame.json"


static func save(inventory: InventoryData, equipment: EquipmentData, stats: CharacterStats) -> void:
	var data := {
		"version": 1,
		"inventory": inventory.to_dict(),
		"equipment": equipment.to_dict(),
		"stats": stats.to_dict(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("存档写入失败: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "\t"))
	print("存档已保存")


static func load_save(inventory: InventoryData, equipment: EquipmentData, stats: CharacterStats) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("存档解析失败")
		return false
	var data: Dictionary = json.data
	if int(data.get("version", 0)) != 1:
		push_error("存档版本不兼容")
		return false
	inventory.from_dict(data.get("inventory", {}))
	equipment.from_dict(data.get("equipment", {}))
	stats.from_dict(data.get("stats", {}))
	print("存档已加载")
	return true


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
