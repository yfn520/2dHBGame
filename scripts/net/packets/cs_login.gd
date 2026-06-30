class_name CSLogin
extends NetPacket
## 请求登录

var account: String = ""
var password: String = ""


func _init() -> void:
	packet_type = PacketDefine.CS_LOGIN


func write_to_buffer(writer: BitWriter) -> void:
	writer.write_string(account)
	writer.write_string(password)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	account = reader.read_string()
	password = reader.read_string()


func generate_has_sign() -> bool:
	return false
