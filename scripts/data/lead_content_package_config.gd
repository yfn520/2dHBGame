class_name LeadContentPackageConfig
extends RefCounted

## 主角内容包配置加载器
## 对应数据表：res://data/lead_content_packages.json
const CONFIG_PATH := "res://data/lead_content_packages.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("主角内容包配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("主角内容包配置解析失败: %s" % CONFIG_PATH)
		return
	for package_id in json.data:
		var raw: Dictionary = json.data[package_id]
		_items[package_id] = {
			"package_id": str(package_id),
			"owner_lead_hero_id": str(raw.get("owner_lead_hero_id", "")),
			"prologue_variant_id": str(raw.get("prologue_variant_id", "")),
			"profession_quest_id": str(raw.get("profession_quest_id", "")),
			"pact_legacy_id": str(raw.get("pact_legacy_id", "")),
			"chapter_reaction_set_id": str(raw.get("chapter_reaction_set_id", "")),
			"chapter5_truth_node_id": str(raw.get("chapter5_truth_node_id", "")),
			"final_execution_node_id": str(raw.get("final_execution_node_id", "")),
			"description": str(raw.get("description", "")),
		}
	_loaded = true


func get_package(package_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(package_id, {})


func get_all_packages() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_package(package_id: String) -> bool:
	if not _loaded:
		load_config()
	return _items.has(package_id)


func get_package_for_lead(lead_hero_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	for package_id in _items:
		var package: Dictionary = _items[package_id]
		if str(package.get("owner_lead_hero_id", "")) == lead_hero_id:
			return package
	return {}
