class_name CSServerCheckPing
extends NetPacket
## 回复服务器延迟检测

var index: int = 0


func _init() -> void:
	packet_type = PacketDefine.CS_SERVER_CHECK_PING


func write_to_buffer(writer: BitWriter) -> void:
	writer.write_signed(index, 4, true)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	index = reader.read_signed(4, need_read_sign)


func generate_has_sign() -> bool:
	return index < 0
