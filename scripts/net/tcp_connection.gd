class_name TCPConnection
## TCP 连接管理器
## 处理与服务器的 TCP 通信，包括连接、发送、接收和包解析

# 连接状态
enum NetState {
	NONE,
	CONNECTING,
	CONNECTED,
}

# 信号
signal connected()
signal disconnected()
signal packet_received(packet: NetPacket)
signal connection_failed()

# 配置
var host: String = "127.0.0.1"
var port: int = 8888

# 内部状态
var _tcp: StreamPeerTCP = null
var _state: NetState = NetState.NONE
var _send_sequence: int = 0
var _recv_sequence: int = 0
var _send_buffer: BitWriter = BitWriter.new()
var _recv_buffer: PackedByteArray = PackedByteArray()
var _packet_factory: Dictionary = {}  # packet_type -> Callable


func _init() -> void:
	_register_packets()


## 注册所有消息包类型
func _register_packets() -> void:
	# CS 消息包
	_register_packet(PacketDefine.CS_CHECK_PACKET_VERSION, func(): return CSCheckPacketVersion.new())
	_register_packet(PacketDefine.CS_SERVER_CHECK_PING, func(): return CSServerCheckPing.new())
	_register_packet(PacketDefine.CS_ATTACK, func(): return CSAttack.new())
	_register_packet(PacketDefine.CS_LOGIN, func(): return CSLogin.new())
	# SC 消息包
	_register_packet(PacketDefine.SC_CHECK_PACKET_VERSION, func(): return SCCheckPacketVersion.new())
	_register_packet(PacketDefine.SC_SERVER_CHECK_PING, func(): return SCServerCheckPing.new())
	_register_packet(PacketDefine.SC_CHARACTER_FULL_GAME_DATA, func(): return SCCharacterFullGameData.new())
	_register_packet(PacketDefine.SC_GET_ITEM_TIP, func(): return SCGetItemTip.new())
	_register_packet(PacketDefine.SC_ATTACK, func(): return SCAttack.new())


## 注册单个消息包类型
func _register_packet(packet_type: int, factory: Callable) -> void:
	_packet_factory[packet_type] = factory


## 连接到服务器
func connect_to_server(connect_host: String = host, connect_port: int = port) -> void:
	if _state != NetState.NONE:
		return
	host = connect_host
	port = connect_port
	_tcp = StreamPeerTCP.new()
	_tcp.set_no_delay(true)
	_state = NetState.CONNECTING
	var err := _tcp.connect_to_host(host, port)
	if err != OK:
		print("[TCP] 连接失败: ", error_string(err))
		_state = NetState.NONE
		connection_failed.emit()


## 断开连接
func disconnect_from_server() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
	_tcp = null
	_state = NetState.NONE
	_send_sequence = 0
	_recv_sequence = 0
	disconnected.emit()


## 发送消息包
func send_packet(packet: NetPacket) -> void:
	if _state != NetState.CONNECTED:
		print("[TCP] 未连接，无法发送消息")
		return
	# 序列化包体
	_send_buffer.clear()
	packet.write_to_buffer(_send_buffer)
	var body_data: PackedByteArray = _send_buffer.get_buffer()
	var body_size: int = body_data.size()
	# 加密包体
	_send_sequence += 1
	if body_size > 0:
		var param: int = NetEncrypt.calc_encrypt_param(packet.get_packet_type(), body_size, _send_sequence)
		NetEncrypt.encrypt_data(body_data, 0, body_size, param)
	# 构造完整包数据
	var writer := BitWriter.new()
	# 包头
	writer.write_unsigned(body_size, 4)  # bodySize
	writer.write_unsigned(CRC16Util.generate_crc16_value(body_size), 2)  # bodySizeCRC
	writer.write_unsigned(packet.get_packet_type(), 2)  # packetType
	writer.write_unsigned(_send_sequence, 4)  # sequence
	writer.write_bool(packet.has_sign_bit())  # hasSign
	# fieldFlag
	var use_flag: bool = packet.field_flag != PacketDefine.FULL_FIELD_FLAG
	writer.write_bool(use_flag)
	if use_flag:
		# fieldFlag 作为 ullong 写入（8字节无符号）
		_write_ulong(writer, packet.field_flag)
	# 包体数据
	writer.write_buffer(body_data)
	# 对齐到字节边界
	writer.fill_zero_to_byte_end()
	# 整体 CRC16
	var packet_data: PackedByteArray = writer.get_buffer()
	var total_crc: int = CRC16Util.generate_crc16_buffer(packet_data)
	# 写入总 CRC16
	var crc_writer := BitWriter.new()
	crc_writer.write_buffer(packet_data)
	crc_writer.write_unsigned(total_crc, 2)
	var final_data: PackedByteArray = crc_writer.get_buffer()
	# 发送
	_tcp.put_data(final_data)


## 每帧更新（处理接收和连接状态）
func update(delta: float) -> void:
	if _tcp == null:
		return
	_tcp.poll()
	# 检查连接状态
	if _state == NetState.CONNECTING:
		var status := _tcp.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_state = NetState.CONNECTED
			connected.emit()
			print("[TCP] 已连接到 ", host, ":", port)
		elif status == StreamPeerTCP.STATUS_ERROR:
			_state = NetState.NONE
			connection_failed.emit()
			print("[TCP] 连接失败")
	# 接收数据
	if _state == NetState.CONNECTED:
		_process_receive()


## 处理接收数据
func _process_receive() -> void:
	var available: int = _tcp.get_available_bytes()
	if available <= 0:
		return
	var data := _tcp.get_data(available)
	if data[0] != OK:
		return
	var received: PackedByteArray = data[1]
	_recv_buffer.append_array(received)
	# 循环解析包
	while _recv_buffer.size() > 0:
		var result := _try_parse_packet()
		if result == null:
			break
		var packet: NetPacket = result
		if packet != null:
			packet.execute()
			packet_received.emit(packet)


## 尝试从接收缓冲区解析一个包
func _try_parse_packet() -> NetPacket:
	if _recv_buffer.size() < 4:
		return null
	var reader := BitReader.new(_recv_buffer)
	# 读取 bodySize
	var body_size: int = reader.read_unsigned(4)
	if body_size < 0:
		return null
	# 读取 bodySizeCRC
	var body_size_crc: int = reader.read_unsigned(2)
	if CRC16Util.generate_crc16_value(body_size) != body_size_crc:
		print("[TCP] bodySize CRC 校验失败")
		_recv_buffer = PackedByteArray()
		return null
	# 读取 packetType
	var packet_type: int = reader.read_unsigned(2)
	# 读取 sequence
	var sequence: int = reader.read_unsigned(4)
	# 读取 hasSign
	var has_sign: bool = reader.read_bool()
	# 读取 useFieldFlag
	var use_flag: bool = reader.read_bool()
	var field_flag: int = PacketDefine.FULL_FIELD_FLAG
	if use_flag:
		field_flag = _read_ulong(reader)
	# 读取包体数据
	var body_data: PackedByteArray = PackedByteArray()
	if body_size > 0:
		# 检查是否有足够的数据
		reader.skip_to_byte_end()
		var current_byte: int = reader.get_read_byte_count()
		if _recv_buffer.size() < current_byte + body_size:
			return null  # 数据不足
		body_data = _recv_buffer.slice(current_byte, current_byte + body_size)
		reader.set_bit_index((current_byte + body_size) * 8)
	# 对齐到字节边界
	reader.skip_to_byte_end()
	# 读取总 CRC16
	var current_byte: int = reader.get_read_byte_count()
	if _recv_buffer.size() < current_byte + 2:
		return null  # 数据不足
	var crc_reader := BitReader.new(_recv_buffer.slice(current_byte))
	var total_crc: int = crc_reader.read_unsigned(2)
	# 验证 CRC16
	var check_data: PackedByteArray = _recv_buffer.slice(0, current_byte)
	if CRC16Util.generate_crc16_buffer(check_data) != total_crc:
		print("[TCP] 总 CRC16 校验失败")
		_recv_buffer = _recv_buffer.slice(current_byte + 2)
		return null
	# 解密包体
	if body_size > 0:
		var param: int = NetEncrypt.calc_encrypt_param(packet_type, body_size, sequence)
		NetEncrypt.decrypt_data(body_data, 0, body_size, param)
	# 验证序列号
	_recv_sequence += 1
	if sequence != _recv_sequence and _recv_sequence != 1:
		print("[TCP] 序列号不匹配: 期望 ", _recv_sequence, " 收到 ", sequence)
	# 创建包对象
	if not _packet_factory.has(packet_type):
		print("[TCP] 未知包类型: ", packet_type)
		_recv_buffer = _recv_buffer.slice(current_byte + 2)
		return null
	var packet: NetPacket = _packet_factory[packet_type].call()
	if body_size > 0:
		var body_reader := BitReader.new(body_data)
		packet.read_from_buffer(body_reader, has_sign, field_flag)
	# 移除已消费的数据
	_recv_buffer = _recv_buffer.slice(current_byte + 2)
	return packet


## 写入 ullong 值（8字节无符号）
func _write_ulong(writer: BitWriter, value: int) -> void:
	# 分成两个 uint 写入
	writer.write_unsigned(value & 0xFFFFFFFF, 4)
	writer.write_unsigned((value >> 32) & 0xFFFFFFFF, 4)


## 读取 ullong 值（8字节无符号）
func _read_ulong(reader: BitReader) -> int:
	var low: int = reader.read_unsigned(4)
	var high: int = reader.read_unsigned(4)
	return low | (high << 32)


## 获取连接状态
func get_state() -> NetState:
	return _state


## 是否已连接
func is_connected() -> bool:
	return _state == NetState.CONNECTED
