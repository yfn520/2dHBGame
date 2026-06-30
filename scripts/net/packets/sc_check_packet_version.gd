class_name SCCheckPacketVersion
extends NetPacket
## 版本检查结果

var result: bool = false


func _init() -> void:
	packet_type = PacketDefine.SC_CHECK_PACKET_VERSION


func write_to_buffer(writer: BitWriter) -> void:
	writer.write_bool(result)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	result = reader.read_bool()


func generate_has_sign() -> bool:
	return false


func execute() -> void:
	print("[SC] 版本检查结果: ", "成功" if result else "失败")
