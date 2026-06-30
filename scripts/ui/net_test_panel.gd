extends CanvasLayer
## 网络连接测试面板

@onready var btn_connect: Button = $Panel/VBoxContainer/BtnConnect
@onready var btn_disconnect: Button = $Panel/VBoxContainer/BtnDisconnect
@onready var btn_send_ping: Button = $Panel/VBoxContainer/BtnSendPing
@onready var btn_send_login: Button = $Panel/VBoxContainer/BtnSendLogin
@onready var label_status: Label = $Panel/VBoxContainer/LabelStatus
@onready var label_log: Label = $Panel/VBoxContainer/ScrollContainer/LabelLog

var _net: TCPConnection
var _log_text: String = ""


func _ready() -> void:
	_net = TCPConnection.new()
	add_child(_net)
	
	# 连接信号
	_net.connected.connect(_on_connected)
	_net.disconnected.connect(_on_disconnected)
	_net.connection_failed.connect(_on_connection_failed)
	_net.packet_received.connect(_on_packet_received)
	
	# 按钮事件
	btn_connect.pressed.connect(_on_btn_connect)
	btn_disconnect.pressed.connect(_on_btn_disconnect)
	btn_send_ping.pressed.connect(_on_btn_send_ping)
	btn_send_login.pressed.connect(_on_btn_send_login)
	
	btn_disconnect.disabled = true
	btn_send_ping.disabled = true
	btn_send_login.disabled = true
	
	_update_status("未连接")


func _process(delta: float) -> void:
	_net.update(delta)


func _on_btn_connect() -> void:
	_add_log("正在连接服务器 127.0.0.1:50002...")
	_net.connect_to_server("127.0.0.1", 50002)
	btn_connect.disabled = true
	_update_status("连接中...")


func _on_btn_disconnect() -> void:
	_net.disconnect_from_server()


func _on_btn_send_ping() -> void:
	var ping := CSServerCheckPing.new()
	ping.index = 1
	_net.send_packet(ping)
	_add_log("发送 CSServerCheckPing")


func _on_btn_send_login() -> void:
	var login := CSLogin.new()
	login.account = "test_user"
	login.password = "123456"
	_net.send_packet(login)
	_add_log("发送 CSLogin: account=test_user")


func _on_connected() -> void:
	_update_status("已连接")
	_add_log("连接成功!")
	btn_connect.disabled = true
	btn_disconnect.disabled = false
	btn_send_ping.disabled = false
	btn_send_login.disabled = false
	
	# 自动发送版本检查
	var version := CSCheckPacketVersion.new()
	version.packet_version = PacketDefine.PACKET_VERSION
	_net.send_packet(version)
	_add_log("发送 CSCheckPacketVersion: " + PacketDefine.PACKET_VERSION)


func _on_disconnected() -> void:
	_update_status("已断开")
	_add_log("连接已断开")
	btn_connect.disabled = false
	btn_disconnect.disabled = true
	btn_send_ping.disabled = true
	btn_send_login.disabled = true


func _on_connection_failed() -> void:
	_update_status("连接失败")
	_add_log("连接失败!")
	btn_connect.disabled = false


func _on_packet_received(packet: NetPacket) -> void:
	match packet.packet_type:
		PacketDefine.SC_CHECK_PACKET_VERSION:
			var p := packet as SCCheckPacketVersion
			_add_log("收到 SCCheckPacketVersion: result=" + str(p.result))
		PacketDefine.SC_SERVER_CHECK_PING:
			var p := packet as SCServerCheckPing
			_add_log("收到 SCServerCheckPing: index=" + str(p.index))
			# 自动回复
			var reply := CSServerCheckPing.new()
			reply.index = p.index
			_net.send_packet(reply)
			_add_log("回复 CSServerCheckPing: index=" + str(p.index))
		PacketDefine.SC_CHARACTER_FULL_GAME_DATA:
			var p := packet as SCCharacterFullGameData
			_add_log("收到 SCCharacterFullGameData: HP=" + str(p.hp) + " Name=" + p.name)
		PacketDefine.SC_ATTACK:
			_add_log("收到 SCAttack")
		PacketDefine.SC_GET_ITEM_TIP:
			var p := packet as SCGetItemTip
			_add_log("收到 SCGetItemTip: " + str(p.item_list.size()) + " 个物品")
		_:
			_add_log("收到未知包: type=" + str(packet.packet_type))


func _update_status(text: String) -> void:
	label_status.text = "状态: " + text


func _add_log(text: String) -> void:
	_log_text += text + "\n"
	label_log.text = _log_text
	# 自动滚动到底部
	await get_tree().process_frame
	var scroll := label_log.get_parent() as ScrollContainer
	if scroll:
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
