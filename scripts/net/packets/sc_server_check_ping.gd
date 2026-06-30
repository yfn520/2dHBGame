class_name SCServerCheckPing
extends NetPacket
## 服务器延迟检测

var index: int = 0


func _init() -> void:
	packet_type = PacketDefine.SC_SERVER_CHECK_PING


func write_to_buffer(writer: BitWriter) -> void:
	writer.write_signed(index, 4, true)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	index = reader.read_signed(4, need_read_sign)


func generate_has_sign() -> bool:
	return index < 0


func execute() -> void:
	# 收到服务器 ping 后回复
	print("[SC] 收到服务器 ping, index: ", index)
