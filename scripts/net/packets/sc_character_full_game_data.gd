class_name SCCharacterFullGameData
extends NetPacket
## 角色完整数据（支持可选字段）

# 字段索引
enum Field {
	HP = 0,
	MAX_HP = 1,
	NAME = 2,
}

var hp: int = 0
var max_hp: int = 0
var name: String = ""

# 字段有效标记
var _valid_fields: int = 0


func _init() -> void:
	packet_type = PacketDefine.SC_CHARACTER_FULL_GAME_DATA
	# 所有字段都是可选的
	field_flag = 0


func set_field_valid(field: int) -> void:
	_valid_fields |= 1 << field
	field_flag = _valid_fields


func is_field_valid(field: int) -> bool:
	return (_valid_fields & (1 << field)) != 0


func write_to_buffer(writer: BitWriter) -> void:
	if is_field_valid(Field.HP):
		writer.write_signed(hp, 4, true)
	if is_field_valid(Field.MAX_HP):
		writer.write_signed(max_hp, 4, true)
	if is_field_valid(Field.NAME):
		writer.write_string(name)


func read_from_buffer(reader: BitReader, need_read_sign: bool, recv_field_flag: int) -> void:
	_valid_fields = recv_field_flag
	if is_field_valid(Field.HP):
		hp = reader.read_signed(4, need_read_sign)
	if is_field_valid(Field.MAX_HP):
		max_hp = reader.read_signed(4, need_read_sign)
	if is_field_valid(Field.NAME):
		name = reader.read_string()


func generate_has_sign() -> bool:
	if is_field_valid(Field.HP) and hp < 0:
		return true
	if is_field_valid(Field.MAX_HP) and max_hp < 0:
		return true
	return false


func execute() -> void:
	print("[SC] 角色数据: HP=", hp, "/", max_hp, " Name=", name)
