class_name EventStateConfig
extends RefCounted

## 事件状态配置加载器
## 对应数据表：res://data/event_states.json
const CONFIG_PATH := "res://data/event_states.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("事件状态配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("事件状态配置解析失败: %s" % CONFIG_PATH)
		return
	for event_id in json.data:
		var raw: Dictionary = json.data[event_id]
		_items[event_id] = {
			"event_id": str(event_id),
			"chapter_id": str(raw.get("chapter_id", "")),
			"node_id": str(raw.get("node_id", "")),
			"current_state": str(raw.get("current_state", "")),
			"replacement_node_id": str(raw.get("replacement_node_id", "")),
			"states": _to_string_array(raw.get("states", [])),
			"description": str(raw.get("description", "")),
		}
	_loaded = true


func _to_string_array(raw) -> Array[String]:
	var result: Array[String] = []
	if not raw is Array:
		return result
	for v in raw:
		result.append(str(v))
	return result


func get_event_state(event_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(event_id, {})


func get_all_event_states() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_event_state(event_id: String) -> bool:
	if not _loaded:
		load_config()
	return _items.has(event_id)


func get_event_for_node(node_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	for event_id in _items:
		var evt: Dictionary = _items[event_id]
		if str(evt.get("node_id", "")) == node_id:
			return evt
	return {}


func get_current_state(event_id: String) -> String:
	var evt := get_event_state(event_id)
	if evt.is_empty():
		return ""
	return str(evt.get("current_state", ""))


func get_replacement_node_id(event_id: String) -> String:
	var evt := get_event_state(event_id)
	if evt.is_empty():
		return ""
	return str(evt.get("replacement_node_id", ""))
