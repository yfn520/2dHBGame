class_name CSCheckPacketVersion
extends NetPacket
## 检查协议版本

var packet_version: String = ""


func _init() -> void:
	packet_type = PacketDefine.CS_CHECK_PACKET_VERSION


func write_to_buffer(writer: BitWriter) -> void:
	writer.write_string(packet_version)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	packet_version = reader.read_string()


func generate_has_sign() -> bool:
	return false
