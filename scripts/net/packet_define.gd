class_name PacketDefine
## 消息包类型定义
## 与服务端 GamePacketDefine.h 保持一致

# CS 消息 (客户端 -> 服务器)
const CS_MIN: int = 10000
const CS_CHECK_PACKET_VERSION: int = 10001
const CS_SERVER_CHECK_PING: int = 10002
const CS_ATTACK: int = 10003
const CS_LOGIN: int = 10004

# SC 消息 (服务器 -> 客户端)
const SC_MIN: int = 20000
const SC_CHECK_PACKET_VERSION: int = 20001
const SC_SERVER_CHECK_PING: int = 20002
const SC_CHARACTER_FULL_GAME_DATA: int = 20003
const SC_GET_ITEM_TIP: int = 20004
const SC_ATTACK: int = 20005

# 协议版本号 (MD5)
const PACKET_VERSION: String = "EAD600B6CBC29EBC1AA09EE872F46C46"

# FULL_FIELD_FLAG
const FULL_FIELD_FLAG: int = -1  # 0xFFFFFFFFFFFFFFFF 在 GDScript 中用 -1 表示
