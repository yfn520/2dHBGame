class_name ItemInstance

var uid: int = 0
var item_id: int = 0
var count: int = 0


func _init(p_uid: int = 0, p_item_id: int = 0, p_count: int = 0) -> void:
	uid = p_uid
	item_id = p_item_id
	count = p_count


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"item_id": item_id,
		"count": count,
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	return ItemInstance.new(
		int(data.get("uid", 0)),
		int(data.get("item_id", 0)),
		int(data.get("count", 0)),
	)
