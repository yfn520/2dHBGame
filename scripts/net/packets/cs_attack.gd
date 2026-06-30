class_name CSAttack
extends NetPacket
## 请求攻击

var target_guid_list: Array = []
var skill_id: int = 0
var timestamp: int = 0


func _init() -> void:
	packet_type = PacketDefine.CS_ATTACK


func write_to_buffer(writer: BitWriter) -> void:
	# 写入目标GUID列表
	writer.write_unsigned(target_guid_list.size(), 2)
	for guid in target_guid_list:
		writer.write_signed(guid, 8, true)
	# 写入技能ID
	writer.write_signed(skill_id, 4, true)
	# 写入时间戳
	writer.write_signed(timestamp, 8, true)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	# 读取目标GUID列表
	var count: int = reader.read_unsigned(2)
	target_guid_list.clear()
	for i in range(count):
		target_guid_list.append(reader.read_signed(8, need_read_sign))
	# 读取技能ID
	skill_id = reader.read_signed(4, need_read_sign)
	# 读取时间戳
	timestamp = reader.read_signed(8, need_read_sign)


func generate_has_sign() -> bool:
	if skill_id < 0 or timestamp < 0:
		return true
	for guid in target_guid_list:
		if guid < 0:
			return true
	return false
