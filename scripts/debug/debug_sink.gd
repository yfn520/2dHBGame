## 注册为 autoload 单例（project.godot），名称与类声明冲突会导致 "Cannot call non-static"，
## 故不使用 class_name，通过 autoload 名 DebugSink 访问实例。
extends Node

## 调试用 HTTP 上报辅助（仅调试会话使用，确认后删除）。
## 通过 POST 上报事件到 Debug Server，使用 HTTPRequest 异步发送，不阻塞主线程。

const _DEFAULT_URL := "http://127.0.0.1:7777/event"
const _SESSION := "npc-chat-not-trigger"

var _url := _DEFAULT_URL


func _ready() -> void:
	var env_path := "res://../.dbg/npc-chat-not-trigger.env"
	if FileAccess.file_exists(env_path):
		var text := FileAccess.get_file_as_string(env_path)
		for line in text.split("\n"):
			if line.begins_with("DEBUG_SERVER_URL="):
				_url = line.get_slice("=", 1).strip_edges()
				break


func report(hypothesis_id: String, msg: String, data: Dictionary = {}) -> void:
	var req := HTTPRequest.new()
	req.timeout = 2.0
	add_child(req)
	var body := JSON.stringify({
		"sessionId": _SESSION,
		"runId": "pre-fix",
		"hypothesisId": hypothesis_id,
		"location": msg,
		"msg": "[DEBUG] " + msg,
		"data": data,
	})
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	req.request(_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)