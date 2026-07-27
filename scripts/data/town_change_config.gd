class_name TownChangeConfig
extends RefCounted

## 城镇变更配置加载器
## 对应数据表：res://data/town_changes.json
const CONFIG_PATH := "res://data/town_changes.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("城镇变更配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("城镇变更配置解析失败: %s" % CONFIG_PATH)
		return
	for change_id in json.data:
		var raw: Dictionary = json.data[change_id]
		_items[change_id] = {
			"town_change_id": str(change_id),
			"chapter_id": str(raw.get("chapter_id", "")),
			"trigger_node_id": str(raw.get("trigger_node_id", "")),
			"target_level_id": int(raw.get("target_level_id", 0)),
			"scene_patch": _to_dict(raw.get("scene_patch", {})),
			"npc_placement_patch": _to_array(raw.get("npc_placement_patch", [])),
			"description": str(raw.get("description", "")),
		}
	_loaded = true


func _to_dict(raw) -> Dictionary:
	if not raw is Dictionary:
		return {}
	return raw


func _to_array(raw) -> Array:
	if not raw is Array:
		return []
	return raw


func get_town_change(change_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(change_id, {})


func get_all_town_changes() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_town_change(change_id: String) -> bool:
	if not _loaded:
		load_config()
	return _items.has(change_id)


func get_changes_for_chapter(chapter_id: String) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for change_id in _items:
		var change: Dictionary = _items[change_id]
		if str(change.get("chapter_id", "")) == chapter_id:
			result.append(str(change_id))
	return result


func get_changes_for_level(level_id: int) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for change_id in _items:
		var change: Dictionary = _items[change_id]
		if int(change.get("target_level_id", 0)) == level_id:
			result.append(str(change_id))
	return result


func get_changes_triggered_by_node(node_id: String) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for change_id in _items:
		var change: Dictionary = _items[change_id]
		if str(change.get("trigger_node_id", "")) == node_id:
			result.append(str(change_id))
	return result
