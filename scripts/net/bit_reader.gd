class_name BitReader

var _buffer: PackedByteArray
var _buffer_size: int = 0
var _bit_index: int = 0

func _init(buffer: PackedByteArray = PackedByteArray()) -> void:
	init_buffer(buffer)

func init_buffer(buffer: PackedByteArray) -> void:
	_buffer = buffer
	_buffer_size = buffer.size()
	_bit_index = 0

func set_bit_index(index: int) -> void:
	_bit_index = index

func get_bit_index() -> int:
	return _bit_index

func get_read_byte_count() -> int:
	return (_bit_index + 7) >> 3

func skip_to_byte_end() -> void:
	_bit_index = ((_bit_index + 7) >> 3) << 3

func _read_byte_bits(bit_count: int) -> int:
	var byte_pos: int = _bit_index >> 3
	var bit_pos: int = _bit_index & 7
	# 读取16位，支持跨字节边界（匹配C++ readByteBits使用short*）
	var current: int = _buffer[byte_pos]
	if byte_pos + 1 < _buffer_size:
		current |= _buffer[byte_pos + 1] << 8
	var result: int = (current >> bit_pos) & ((1 << bit_count) - 1)
	_bit_index += bit_count
	return result

func read_bool() -> bool:
	var byte_pos: int = _bit_index >> 3
	var bit_pos: int = _bit_index & 7
	var result: bool = (_buffer[byte_pos] & (1 << bit_pos)) != 0
	_bit_index += 1
	return result

func _get_length_max_bit(byte_size: int) -> int:
	if byte_size <= 1:
		return 3
	elif byte_size <= 2:
		return 4
	elif byte_size <= 4:
		return 5
	else:
		return 6

func read_unsigned(byte_size: int) -> int:
	var type_len_bit: int = _get_length_max_bit(byte_size)
	var bit_count: int = _read_byte_bits(type_len_bit)
	# 匹配C++ readUnsignedLengthBit: 当长度位值等于(1<<TYPE_LENGTH_MAX_BIT)-1时,实际数据位+1
	# 比如ushort类型,长度位4bit,最大表示15,当读到15时,实际要读16bit数据
	if bit_count == (1 << type_len_bit) - 1:
		bit_count += 1
	if bit_count == 0:
		return 0
	var drop_threshold: int = (1 << byte_size) - 1
	if bit_count < drop_threshold:
		# 先减1（写入时丢弃了最高位的1）
		bit_count -= 1
		var value: int = 0
		if bit_count > 0:
			value = _read_data_bits(bit_count)
		# 加回最高位的1
		value |= 1 << bit_count
		return value
	else:
		return _read_data_bits(bit_count)

func read_signed(byte_size: int, need_sign: bool) -> int:
	var type_len_bit: int = _get_length_max_bit(byte_size)
	var bit_count: int = _read_byte_bits(type_len_bit)
	if bit_count == 0:
		return 0
	var is_negative: bool = false
	if need_sign:
		var byte_pos: int = _bit_index >> 3
		var bit_pos: int = _bit_index & 7
		is_negative = (_buffer[byte_pos] & (1 << bit_pos)) != 0
		_bit_index += 1
	# 有符号：总是减1（写入时总是丢弃最高位），bitCount==1 时直接返回
	if bit_count > 1:
		bit_count -= 1
		var value: int = _read_data_bits(bit_count)
		value |= 1 << bit_count
		return -value if is_negative else value
	else:
		return -1 if is_negative else 1

func read_float(need_sign: bool, precision: int = 3) -> float:
	var int_value: int = read_signed(4, need_sign)
	return float(int_value) / pow(10.0, precision)

func read_string() -> String:
	var length: int = read_unsigned(4)
	if length == 0:
		return ""
	skip_to_byte_end()
	var bytes := _buffer.slice(_bit_index >> 3, (_bit_index >> 3) + length)
	_bit_index += length * 8
	return bytes.get_string_from_utf8()

func read_buffer(length: int) -> PackedByteArray:
	if length == 0:
		return PackedByteArray()
	skip_to_byte_end()
	var bytes := _buffer.slice(_bit_index >> 3, (_bit_index >> 3) + length)
	_bit_index += length * 8
	return bytes

func _read_data_bits(bit_count: int) -> int:
	var value: int = 0
	var remaining: int = bit_count
	var dst_byte: int = 0
	while remaining > 0:
		var bits_in_byte: int = mini(remaining, 8)
		var byte_val: int = _read_byte_bits(bits_in_byte)
		value |= byte_val << (dst_byte * 8)
		remaining -= bits_in_byte
		dst_byte += 1
	return value
