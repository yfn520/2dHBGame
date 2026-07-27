class_name PactLegacyConfig
extends RefCounted

## 契约遗物配置加载器
## 对应数据表：res://data/pact_legacies.json
const CONFIG_PATH := "res://data/pact_legacies.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("契约遗物配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("契约遗物配置解析失败: %s" % CONFIG_PATH)
		return
	for legacy_id in json.data:
		var raw: Dictionary = json.data[legacy_id]
		_items[legacy_id] = {
			"pact_legacy_id": str(legacy_id),
			"owner_lead_hero_id": str(raw.get("owner_lead_hero_id", "")),
			"item_id": int(raw.get("item_id", 0)),
			"name": str(raw.get("name", "")),
			"acquire_quest_id": str(raw.get("acquire_quest_id", "")),
			"combat_effect_id": str(raw.get("combat_effect_id", "")),
			"exploration_effect_id": str(raw.get("exploration_effect_id", "")),
			"event_option_tag": str(raw.get("event_option_tag", "")),
			"current_upgrade_stage": int(raw.get("current_upgrade_stage", 0)),
			"max_upgrade_stage": int(raw.get("max_upgrade_stage", 0)),
			"upgrade_stage_chapters": _to_string_array(raw.get("upgrade_stage_chapters", [])),
			"upgrade_stage_names": _to_string_array(raw.get("upgrade_stage_names", [])),
			"upgrade_story_node_ids": _to_string_array(raw.get("upgrade_story_node_ids", [])),
			"is_tradable": bool(raw.get("is_tradable", false)),
			"is_droppable": bool(raw.get("is_droppable", false)),
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


func get_pact_legacy(legacy_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(legacy_id, {})


func get_all_pact_legacies() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_pact_legacy(legacy_id: String) -> bool:
	if not _loaded:
		load_config()
	return _items.has(legacy_id)


func get_pact_legacy_for_lead(lead_hero_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	for legacy_id in _items:
		var legacy: Dictionary = _items[legacy_id]
		if str(legacy.get("owner_lead_hero_id", "")) == lead_hero_id:
			return legacy
	return {}


func get_pact_legacy_for_item(item_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	for legacy_id in _items:
		var legacy: Dictionary = _items[legacy_id]
		if int(legacy.get("item_id", 0)) == item_id:
			return legacy
	return {}


func get_upgrade_stage(legacy_id: String) -> int:
	var legacy := get_pact_legacy(legacy_id)
	if legacy.is_empty():
		return 0
	return int(legacy.get("current_upgrade_stage", 0))


func get_upgrade_stage_name(legacy_id: String, stage: int) -> String:
	var legacy := get_pact_legacy(legacy_id)
	if legacy.is_empty():
		return ""
	var names: Array[String] = legacy.get("upgrade_stage_names", [])
	if stage < 0 or stage >= names.size():
		return ""
	return str(names[stage])


func get_upgrade_story_node(legacy_id: String, stage: int) -> String:
	var legacy := get_pact_legacy(legacy_id)
	if legacy.is_empty():
		return ""
	var nodes: Array[String] = legacy.get("upgrade_story_node_ids", [])
	if stage < 0 or stage >= nodes.size():
		return ""
	return str(nodes[stage])
