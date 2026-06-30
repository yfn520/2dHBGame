class_name BitWriter
## 按位写入序列化器
## 与服务端 SerializerBitWrite 保持一致的编码格式

# 无符号类型长度位所需的bit数，下标是字节数 (1=byte, 2=ushort, 4=uint, 8=ullong)
const UNSIGNED_LENGTH_MAX_BIT: PackedByteArray = PackedByteArray([0, 3, 4, 0, 5, 0, 0, 0, 6])
# 有符号类型长度位所需的bit数
const SIGNED_LENGTH_MAX_BIT: PackedByteArray = PackedByteArray([0, 3, 4, 0, 5, 0, 0, 0, 6])

var _buffer: PackedByteArray
var _bit_index: int = 0


func _init(capacity: int = 32) -> void:
	_buffer.resize(capacity)


## 清空缓冲区，重置位索引
func clear() -> void:
	_bit_index = 0


## 获取当前已写入的字节数（向上取整）
func get_byte_count() -> int:
	return (_bit_index + 7) >> 3


## 获取当前位索引
func get_bit_index() -> int:
	return _bit_index


## 获取底层缓冲区的副本
func get_buffer() -> PackedByteArray:
	var count := get_byte_count()
	if count == 0:
		return PackedByteArray()
	return _buffer.slice(0, count)


## 确保缓冲区有足够空间
func _ensure_capacity(need_bits: int) -> void:
	var need_bytes: int = (need_bits + 7) >> 3
	while _buffer.size() < need_bytes:
		_buffer.resize(_buffer.size() * 2)


## 将一个字节的指定位数写入缓冲区
func _write_byte_bits(value: int, bit_count: int) -> void:
	var byte_pos: int = _bit_index >> 3
	var bit_pos: int = _bit_index & 7
	# 清除目标位
	var mask: int = ((1 << bit_count) - 1) << bit_pos
	_buffer[byte_pos] = (_buffer[byte_pos] & (~mask & 0xFF)) | ((value & ((1 << bit_count) - 1)) << bit_pos)
	_bit_index += bit_count


## 写入 bool（1 bit）
func write_bool(value: bool) -> void:
	_ensure_capacity(1)
	if value:
		_buffer[_bit_index >> 3] |= 1 << (_bit_index & 7)
	else:
		_buffer[_bit_index >> 3] &= ~(1 << (_bit_index & 7))
	_bit_index += 1


## 写入无符号整数（变长编码）
func write_unsigned(value: int, byte_size: int) -> void:
	_ensure_capacity(byte_size * 8 + 8)
	var bit_count: int = _generate_bit_count(value, byte_size)
	var type_length_max_bit: int = UNSIGNED_LENGTH_MAX_BIT[byte_size]
	# 写入长度位
	var write_bit_count: int = bit_count
	var max_len_value: int = (1 << type_length_max_bit) - 1
	if bit_count == (1 << type_length_max_bit):
		write_bit_count = bit_count - 1
	elif bit_count == max_len_value:
		write_bit_count = bit_count
		# 不需要额外调整
	_write_byte_bits(write_bit_count, type_length_max_bit)
	# 写入数据位（去掉最高位的1）
	if bit_count > 0:
		_write_data_bits(value, bit_count - 1)


## 写入有符号整数（变长编码）
func write_signed(value: int, byte_size: int, need_sign: bool) -> void:
	_ensure_capacity(byte_size * 8 + 8)
	var abs_value: int = value if value >= 0 else -value
	var bit_count: int = _generate_bit_count(abs_value, byte_size)
	# 写入长度位
	var type_length_max_bit: int = SIGNED_LENGTH_MAX_BIT[byte_size]
	_write_byte_bits(bit_count, type_length_max_bit)
	if bit_count == 0:
		return
	# 写入符号位
	if need_sign:
		_ensure_capacity(1)
		if value < 0:
			_buffer[_bit_index >> 3] |= 1 << (_bit_index & 7)
		else:
			_buffer[_bit_index >> 3] &= ~(1 << (_bit_index & 7)
		_bit_index += 1
	# 写入值（去掉最高位的1，因为读取时可以推断回来）
	if bit_count > 1:
		_write_data_bits(abs_value, bit_count - 1)


## 写入 float（先乘以 10^precision 转为 int，再按有符号写入）
func write_float(value: float, need_sign: bool, precision: int = 3) -> void:
	var int_value: int = roundi(value * pow(10.0, precision))
	write_signed(int_value, 4, need_sign)


## 写入字符串（先写长度 uint，再写字节数据）
func write_string(value: String) -> void:
	var bytes := value.to_utf8_buffer()
	write_unsigned(bytes.size(), 4)
	if bytes.size() > 0:
		_fill_zero_to_byte_end()
		_ensure_capacity(bytes.size() * 8)
		var byte_pos: int = _bit_index >> 3
		for i in range(bytes.size()):
			_buffer[byte_pos + i] = bytes[i]
		_bit_index += bytes.size() * 8


## 写入原始字节缓冲区（先对齐到字节边界，再按字节写入）
func write_buffer(data: PackedByteArray) -> void:
	if data.size() == 0:
		return
	_fill_zero_to_byte_end()
	_ensure_capacity(data.size() * 8)
	var byte_pos: int = _bit_index >> 3
	for i in range(data.size()):
		_buffer[byte_pos + i] = data[i]
	_bit_index += data.size() * 8


## 将当前字节剩余的位填充为0，位索引移动到字节末尾
func fill_zero_to_byte_end() -> void:
	_fill_zero_to_byte_end()


func _fill_zero_to_byte_end() -> void:
	var bit_pos: int = _bit_index & 7
	if bit_pos != 0:
		# 清除当前字节中未使用的高位
		_buffer[_bit_index >> 3] &= (1 << bit_pos) - 1
		_bit_index = (_bit_index + 7) & ~7


## 计算值需要多少个 bit 来表示（最高位1的下标+1）
func _generate_bit_count(value: int, byte_size: int) -> int:
	if value == 0:
		return 0
	var max_bits: int = byte_size * 8
	var count: int = 0
	var v: int = value
	while v > 0:
		count += 1
		v >>= 1
	return mini(count, max_bits)


## 写入数据位（value 的低 bit_count 位，不含最高位的1）
func _write_data_bits(value: int, bit_count: int) -> void:
	if bit_count <= 0:
		return
	_ensure_capacity(bit_count)
	# 逐字节写入
	var remaining: int = bit_count
	var src_byte: int = 0
	while remaining > 0:
		var bits_in_byte: int = mini(remaining, 8)
		var byte_val: int = (value >> (src_byte * 8)) & ((1 << bits_in_byte) - 1)
		_write_byte_bits(byte_val, bits_in_byte)
		remaining -= bits_in_byte
		src_byte += 1
