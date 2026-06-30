class_name SCAttack
extends NetPacket
## 攻击结果回复（无字段）


func _init() -> void:
	packet_type = PacketDefine.SC_ATTACK


func write_to_buffer(writer: BitWriter) -> void:
	pass


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	pass


func generate_has_sign() -> bool:
	return false


func execute() -> void:
	print("[SC] 攻击成功")
