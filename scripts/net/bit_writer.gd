class_name BitWriter

var _buffer: PackedByteArray
var _bit_index: int = 0

func _init() -> void:
	_buffer = PackedByteArray()
	_buffer.resize(32)

func clear() -> void:
	_bit_index = 0

func get_byte_count() -> int:
	return (_bit_index + 7) >> 3

func get_bit_index() -> int:
	return _bit_index

func get_buffer() -> PackedByteArray:
	var count := get_byte_count()
	if count == 0:
		return PackedByteArray()
	return _buffer.slice(0, count)

func _ensure(need_end_byte: int) -> void:
	while _buffer.size() < need_end_byte:
		_buffer.resize(_buffer.size() * 2)

func _pos_after_bits(extra_bits: int) -> int:
	return ((_bit_index + extra_bits + 7) >> 3)

# 写入最多8位数据，支持跨字节边界（匹配C++ writeByteBits）
func _write_byte_bits(value: int, bit_count: int) -> void:
	var byte_pos: int = _bit_index >> 3
	var bit_pos: int = _bit_index & 7
	# 确保有足够空间（可能跨2个字节）
	_ensure(byte_pos + 2)
	# 读取当前16位值
	var current: int = _buffer[byte_pos] | (_buffer[byte_pos + 1] << 8)
	# 清除目标位并写入新值
	var mask: int = ((1 << bit_count) - 1) << bit_pos
	current = (current & (~mask & 0xFFFF)) | ((value & ((1 << bit_count) - 1)) << bit_pos)
	# 写回
	_buffer[byte_pos] = current & 0xFF
	_buffer[byte_pos + 1] = (current >> 8) & 0xFF
	_bit_index += bit_count

func write_bool(value: bool) -> void:
	_write_byte_bits(1 if value else 0, 1)

func _get_length_max_bit(byte_size: int) -> int:
	if byte_size <= 1:
		return 3
	elif byte_size <= 2:
		return 4
	elif byte_size <= 4:
		return 5
	else:
		return 6

func write_unsigned(value: int, byte_size: int) -> void:
	var type_len_bit: int = _get_length_max_bit(byte_size)
	_ensure(_pos_after_bits(byte_size * 8 + type_len_bit))
	var bit_count: int = _generate_bit_count(value)
	var write_count: int = bit_count
	# 匹配C++ writeUnsignedLengthBit的三种情况
	if bit_count == (1 << type_len_bit):
		write_count = bit_count - 1
	elif bit_count == (1 << type_len_bit) - 1:
		write_count = bit_count
		bit_count += 1
	_write_byte_bits(write_count, type_len_bit)
	if bit_count == 0:
		return
	var drop_threshold: int = (1 << byte_size) - 1
	if bit_count < drop_threshold:
		# 去掉最高位的1，写入bit_count-1个数据位（匹配C++ setBitZero + --bitCount）
		var data_value: int = value & ((1 << (bit_count - 1)) - 1)
		bit_count -= 1
		if bit_count > 0:
			_write_data_bits(data_value, bit_count)
	else:
		_write_data_bits(value, bit_count)

func write_signed(value: int, byte_size: int, need_sign: bool) -> void:
	var type_len_bit: int = _get_length_max_bit(byte_size)
	_ensure(_pos_after_bits(byte_size * 8 + type_len_bit + 1))
	var abs_val: int = value if value >= 0 else -value
	var bit_count: int = _generate_bit_count(abs_val)
	_write_byte_bits(bit_count, type_len_bit)
	if bit_count == 0:
		return
	if need_sign:
		_write_byte_bits(1 if value < 0 else 0, 1)
	if bit_count > 1:
		var data_value: int = abs_val & ((1 << (bit_count - 1)) - 1)
		_write_data_bits(data_value, bit_count - 1)

func write_float(value: float, need_sign: bool, precision: int = 3) -> void:
	var int_value: int = roundi(value * pow(10.0, precision))
	write_signed(int_value, 4, need_sign)

func write_string(value: String) -> void:
	var bytes := value.to_utf8_buffer()
	write_unsigned(bytes.size(), 4)
	if bytes.size() > 0:
		_fill_zero_to_byte_end()
		var byte_pos: int = _bit_index >> 3
		_ensure(byte_pos + bytes.size())
		for i in range(bytes.size()):
			_buffer[byte_pos + i] = bytes[i]
		_bit_index += bytes.size() * 8

func write_buffer(data: PackedByteArray) -> void:
	if data.size() == 0:
		return
	_fill_zero_to_byte_end()
	var byte_pos: int = _bit_index >> 3
	_ensure(byte_pos + data.size())
	for i in range(data.size()):
		_buffer[byte_pos + i] = data[i]
	_bit_index += data.size() * 8

func fill_zero_to_byte_end() -> void:
	_fill_zero_to_byte_end()

func _fill_zero_to_byte_end() -> void:
	var bit_pos: int = _bit_index & 7
	if bit_pos != 0:
		_buffer[_bit_index >> 3] &= (1 << bit_pos) - 1
		_bit_index = (_bit_index + 7) & ~7

func _generate_bit_count(value: int) -> int:
	if value == 0:
		return 0
	var count: int = 0
	var v: int = value
	while v > 0:
		count += 1
		v >>= 1
	return count

func _write_data_bits(value: int, bit_count: int) -> void:
	if bit_count <= 0:
		return
	var remaining: int = bit_count
	var src_byte: int = 0
	while remaining > 0:
		var bits_in_byte: int = mini(remaining, 8)
		var byte_val: int = (value >> (src_byte * 8)) & ((1 << bits_in_byte) - 1)
		_write_byte_bits(byte_val, bits_in_byte)
		remaining -= bits_in_byte
		src_byte += 1
