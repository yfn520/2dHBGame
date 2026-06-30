class_name InventoryData

signal item_added(item: ItemInstance)
signal item_removed(uid: int)
signal item_changed(item: ItemInstance)

var _items: Array[ItemInstance] = []
var _next_uid: int = 1

# ---- 查询 ----

func get_items() -> Array[ItemInstance]:
	return _items


func get_item_by_uid(uid: int) -> ItemInstance:
	for item in _items:
		if item.uid == uid:
			return item
	return null


func get_item_by_id(item_id: int) -> ItemInstance:
	for item in _items:
		if item.item_id == item_id:
			return item
	return null


func get_count_by_id(item_id: int) -> int:
	var total := 0
	for item in _items:
		if item.item_id == item_id:
			total += item.count
	return total


# ---- 修改 ----

func add_item(item_id: int, count: int, config: ItemConfig) -> ItemInstance:
	if count <= 0:
		return null
	if not config.is_valid_item(item_id):
		push_error("无效的物品ID: %s" % item_id)
		return null

	# 可堆叠: 尝试合并到已有格子
	if config.is_stackable(item_id):
		var existing := get_item_by_id(item_id)
		if existing != null:
			var max_count := config.get_max_count(item_id)
			var can_add := mini(count, max_count - existing.count)
			if can_add > 0:
				existing.count += can_add
				item_changed.emit(existing)
				count -= can_add
			if count <= 0:
				return existing
		# 剩余部分创建新格子
		var max_count := config.get_max_count(item_id)
		var new_count := mini(count, max_count)
		var item := ItemInstance.new(_next_uid, item_id, new_count)
		_next_uid += 1
		_items.append(item)
		item_added.emit(item)
		return item
	else:
		# 不可堆叠: 每个一格
		var last_item: ItemInstance = null
		for i in count:
			var item := ItemInstance.new(_next_uid, item_id, 1)
			_next_uid += 1
			_items.append(item)
			item_added.emit(item)
			last_item = item
		return last_item


func remove_item(uid: int, count: int = -1) -> bool:
	var item := get_item_by_uid(uid)
	if item == null:
		return false
	if count < 0 or count >= item.count:
		_items.erase(item)
		item_removed.emit(uid)
	else:
		item.count -= count
		item_changed.emit(item)
	return true


func remove_item_by_id(item_id: int, count: int) -> bool:
	var remaining := count
	while remaining > 0:
		var item := get_item_by_id(item_id)
		if item == null:
			return false
		if item.count <= remaining:
			remaining -= item.count
			_items.erase(item)
			item_removed.emit(item.uid)
		else:
			item.count -= remaining
			remaining = 0
			item_changed.emit(item)
	return true


func has_item(item_id: int, count: int = 1) -> bool:
	return get_count_by_id(item_id) >= count


# ---- 存档 ----

func to_dict() -> Dictionary:
	var arr := []
	for item in _items:
		arr.append(item.to_dict())
	return {
		"items": arr,
		"next_uid": _next_uid,
	}


func from_dict(data: Dictionary) -> void:
	_items.clear()
	_next_uid = int(data.get("next_uid", 1))
	for item_data in data.get("items", []):
		_items.append(ItemInstance.from_dict(item_data))
