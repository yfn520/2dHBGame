class_name BitReader
## 按位读取反序列化器
## 与服务端 SerializerBitRead 保持一致的编码格式

# 无符号类型长度位所需的bit数，下标是字节数
const UNSIGNED_LENGTH_MAX_BIT: PackedByteArray = PackedByteArray([0, 3, 4, 0, 5, 0, 0, 0, 6])
# 有符号类型长度位所需的bit数
const SIGNED_LENGTH_MAX_BIT: PackedByteArray = PackedByteArray([0, 3, 4, 0, 5, 0, 0, 0, 6])

var _buffer: PackedByteArray
var _buffer_size: int = 0
var _bit_index: int = 0


func _init(buffer: PackedByteArray = PackedByteArray()) -> void:
	init_buffer(buffer)


## 初始化读取缓冲区
func init_buffer(buffer: PackedByteArray) -> void:
	_buffer = buffer
	_buffer_size = buffer.size()
	_bit_index = 0


## 设置位索引
func set_bit_index(index: int) -> void:
	_bit_index = index


## 获取当前位索引
func get_bit_index() -> int:
	return _bit_index


## 获取已读取的字节数（向上取整）
func get_read_byte_count() -> int:
	return (_bit_index + 7) >> 3


## 跳到字节末尾
func skip_to_byte_end() -> void:
	_bit_index = ((_bit_index + 7) >> 3) << 3


## 从缓冲区读取指定位数到一个字节
func _read_byte_bits(bit_count: int) -> int:
	var byte_pos: int = _bit_index >> 3
	var bit_pos: int = _bit_index & 7
	var mask: int = (1 << bit_count) - 1
	var result: int = (_buffer[byte_pos] >> bit_pos) & mask
	_bit_index += bit_count
	return result


## 读取 bool（1 bit）
func read_bool() -> bool:
	var byte_pos: int = _bit_index >> 3
	var bit_pos: int = _bit_index & 7
	var result: bool = (_buffer[byte_pos] & (1 << bit_pos)) != 0
	_bit_index += 1
	return result


## 读取无符号整数（变长编码）
func read_unsigned(byte_size: int) -> int:
	var type_length_max_bit: int = UNSIGNED_LENGTH_MAX_BIT[byte_size]
	# 读取长度位
	var bit_count: int = _read_byte_bits(type_length_max_bit)
	if bit_count == 0:
		return 0
	# 特殊处理：当长度位达到最大值时，实际位数+1
	var max_len_value: int = (1 << type_length_max_bit) - 1
	var actual_bit_count: int = bit_count
	if bit_count < max_len_value:
		actual_bit_count = bit_count - 1
	elif bit_count == max_len_value:
		actual_bit_count = bit_count  # 保持不变，读满位数
	# 读取数据位
	if actual_bit_count > 0:
		var value: int = _read_data_bits(actual_bit_count)
		# 加上最高位的1（除非是最大位数情况）
		if bit_count < max_len_value:
			value |= 1 << actual_bit_count
		return value
	else:
		return 1


## 读取有符号整数（变长编码）
func read_signed(byte_size: int, need_sign: bool) -> int:
	var type_length_max_bit: int = SIGNED_LENGTH_MAX_BIT[byte_size]
	# 读取长度位
	var bit_count: int = _read_byte_bits(type_length_max_bit)
	if bit_count == 0:
		return 0
	var actual_bit_count: int = bit_count - 1
	# 读取符号位
	var is_negative: bool = false
	if need_sign:
		var byte_pos: int = _bit_index >> 3
		var bit_pos: int = _bit_index & 7
		is_negative = (_buffer[byte_pos] & (1 << bit_pos)) != 0
		_bit_index += 1
	# 读取值
	if actual_bit_count > 0:
		var value: int = _read_data_bits(actual_bit_count)
		# 加上最高位的1
		value |= 1 << actual_bit_count
		return -value if is_negative else value
	else:
		return -1 if is_negative else 1


## 读取 float
func read_float(need_sign: bool, precision: int = 3) -> float:
	var int_value: int = read_signed(4, need_sign)
	return float(int_value) / pow(10.0, precision)


## 读取字符串
func read_string() -> String:
	var length: int = read_unsigned(4)
	if length == 0:
		return ""
	skip_to_byte_end()
	var bytes := _buffer.slice(_bit_index >> 3, (_bit_index >> 3) + length)
	_bit_index += length * 8
	return bytes.get_string_from_utf8()


## 读取原始字节缓冲区
func read_buffer(length: int) -> PackedByteArray:
	if length == 0:
		return PackedByteArray()
	skip_to_byte_end()
	var bytes := _buffer.slice(_bit_index >> 3, (_bit_index >> 3) + length)
	_bit_index += length * 8
	return bytes


## 读取数据位（返回低 bit_count 位的值）
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
