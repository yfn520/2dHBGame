class_name InventoryProvider
## 背包数据访问接口
## 本地模式下直接操作 InventoryData
## 网络模式下发送 TCP 包给服务端，等回调后再更新 InventoryData

signal item_added(item: ItemInstance)
signal item_removed(uid: int)
signal item_changed(item: ItemInstance)

var inventory: InventoryData
var item_config: ItemConfig


func _init(p_inventory: InventoryData, p_config: ItemConfig) -> void:
	inventory = p_inventory
	item_config = p_config
	inventory.item_added.connect(_on_item_added)
	inventory.item_removed.connect(_on_item_removed)
	inventory.item_changed.connect(_on_item_changed)


func _on_item_added(item: ItemInstance) -> void:
	item_added.emit(item)


func _on_item_removed(uid: int) -> void:
	item_removed.emit(uid)


func _on_item_changed(item: ItemInstance) -> void:
	item_changed.emit(item)


func add_item(item_id: int, count: int = 1) -> ItemInstance:
	return inventory.add_item(item_id, count, item_config)


func remove_item(uid: int, count: int = -1) -> bool:
	return inventory.remove_item(uid, count)


func remove_item_by_id(item_id: int, count: int) -> bool:
	return inventory.remove_item_by_id(item_id, count)


func get_items() -> Array[ItemInstance]:
	return inventory.get_items()


func get_count_by_id(item_id: int) -> int:
	return inventory.get_count_by_id(item_id)


func has_item(item_id: int, count: int = 1) -> bool:
	return inventory.has_item(item_id, count)
