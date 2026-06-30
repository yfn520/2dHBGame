class_name SCGetItemTip
extends NetPacket
## 物品奖励提示

var item_list: Array = []  # [{item_id: int, item_count: int}]


func _init() -> void:
	packet_type = PacketDefine.SC_GET_ITEM_TIP


func write_to_buffer(writer: BitWriter) -> void:
	writer.write_unsigned(item_list.size(), 2)
	for item in item_list:
		writer.write_signed(item.item_id, 4, true)
		writer.write_signed(item.item_count, 4, true)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	var count: int = reader.read_unsigned(2)
	item_list.clear()
	for i in range(count):
		var item_id: int = reader.read_signed(4, need_read_sign)
		var item_count: int = reader.read_signed(4, need_read_sign)
		item_list.append({"item_id": item_id, "item_count": item_count})


func generate_has_sign() -> bool:
	for item in item_list:
		if item.item_id < 0 or item.item_count < 0:
			return true
	return false


func execute() -> void:
	for item in item_list:
		print("[SC] 获得物品: ID=", item.item_id, " 数量=", item.item_count)
