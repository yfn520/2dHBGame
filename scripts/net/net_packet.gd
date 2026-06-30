class_name NetPacket
## 网络消息包基类
## 所有 CS/SC 消息包都继承此类

var packet_type: int = 0
var has_sign: bool = false
var field_flag: int = PacketDefine.FULL_FIELD_FLAG


## 序列化包体到 BitWriter
func write_to_buffer(writer: BitWriter) -> void:
	pass


## 从 BitReader 反序列化包体
func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	pass


## 生成 hasSign（检查是否有负数字段）
func generate_has_sign() -> bool:
	return false


## 获取包类型
func get_packet_type() -> int:
	return packet_type


## 是否有符号位
func has_sign_bit() -> bool:
	return has_sign


## 执行包逻辑（在主线程调用）
func execute() -> void:
	pass
