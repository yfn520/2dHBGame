class_name StoryNodeConfig
extends RefCounted

## 故事节点配置加载器
## 对应数据表：res://data/story_nodes.json
const CONFIG_PATH := "res://data/story_nodes.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("故事节点配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("故事节点配置解析失败: %s" % CONFIG_PATH)
		return
	for node_id in json.data:
		var raw: Dictionary = json.data[node_id]
		_items[node_id] = {
			"story_node_id": str(node_id),
			"title": str(raw.get("title", "")),
			"subtitle": str(raw.get("subtitle", "")),
			"node_type": str(raw.get("node_type", "common")),
			"chapter_id": str(raw.get("chapter_id", "")),
			"story_layer": str(raw.get("story_layer", "")),
			"route": str(raw.get("route", "all")),
			"required_lead_hero_id": int(raw.get("required_lead_hero_id", 0)),
			"required_hero_id": int(raw.get("required_hero_id", 0)),
			"required_event_state": str(raw.get("required_event_state", "")),
			"required_pact_stage": int(raw.get("required_pact_stage", 0)),
			"dialogue_id": str(raw.get("dialogue_id", "")),
			"quest_id": str(raw.get("quest_id", "")),
			"level_id": int(raw.get("level_id", 0)),
			"gear_drops": _to_int_array(raw.get("gear_drops", [])),
			"town_change_ids": _to_string_array(raw.get("town_change_ids", [])),
			"next_node_ids": _to_string_array(raw.get("next_node_ids", [])),
			"repeat_replacement_node_id": str(raw.get("repeat_replacement_node_id", "")),
			"summary": str(raw.get("summary", "")),
			"editor": _to_editor_dict(raw.get("editor", {})),
		}
	_loaded = true


func _to_int_array(raw) -> Array[int]:
	var result: Array[int] = []
	if not raw is Array:
		return result
	for v in raw:
		result.append(int(v))
	return result


func _to_string_array(raw) -> Array[String]:
	var result: Array[String] = []
	if not raw is Array:
		return result
	for v in raw:
		result.append(str(v))
	return result


func _to_editor_dict(raw) -> Dictionary:
	if not raw is Dictionary:
		return {"x": 0, "y": 0}
	return {
		"x": int(raw.get("x", 0)),
		"y": int(raw.get("y", 0)),
	}


func get_story_node(node_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(node_id, {})


func get_all_story_nodes() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_story_node(node_id: String) -> bool:
	if not _loaded:
		load_config()
	return _items.has(node_id)


func get_nodes_for_chapter(chapter_id: String) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for node_id in _items:
		var node: Dictionary = _items[node_id]
		if str(node.get("chapter_id", "")) == chapter_id:
			result.append(str(node_id))
	return result


func get_nodes_by_route(route: String) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for node_id in _items:
		var node: Dictionary = _items[node_id]
		if str(node.get("route", "all")) == route:
			result.append(str(node_id))
	return result


func get_nodes_by_layer(layer: String) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for node_id in _items:
		var node: Dictionary = _items[node_id]
		if str(node.get("story_layer", "")) == layer:
			result.append(str(node_id))
	return result


func get_next_nodes(node_id: String) -> Array[String]:
	var node := get_story_node(node_id)
	if node.is_empty():
		return []
	return node.get("next_node_ids", [])
