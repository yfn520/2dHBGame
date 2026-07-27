class_name HeroRecruitConfig
extends RefCounted

## 英雄招募配置加载器
## 对应数据表：res://data/hero_recruit_config.json
const CONFIG_PATH := "res://data/hero_recruit_config.json"

var _items: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("英雄招募配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("英雄招募配置解析失败: %s" % CONFIG_PATH)
		return
	for recruit_id in json.data:
		var raw: Dictionary = json.data[recruit_id]
		_items[recruit_id] = {
			"recruit_id": str(recruit_id),
			"hero_id": int(raw.get("hero_id", 0)),
			"hero_name": str(raw.get("hero_name", "")),
			"class_id": str(raw.get("class_id", "")),
			"recruit_chapter_id": str(raw.get("recruit_chapter_id", "")),
			"recruit_node_id": str(raw.get("recruit_node_id", "")),
			"is_fixed_party_member": bool(raw.get("is_fixed_party_member", false)),
			"force_recruit_on_chapter_enter": bool(raw.get("force_recruit_on_chapter_enter", false)),
			"description": str(raw.get("description", "")),
		}
	_loaded = true


func get_recruit_config(recruit_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _items.get(recruit_id, {})


func get_all_recruit_configs() -> Dictionary:
	if not _loaded:
		load_config()
	return _items


func is_valid_recruit_config(recruit_id: String) -> bool:
	if not _loaded:
		load_config()
	return _items.has(recruit_id)


func get_recruit_for_hero(hero_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	for recruit_id in _items:
		var recruit: Dictionary = _items[recruit_id]
		if int(recruit.get("hero_id", 0)) == hero_id:
			return recruit
	return {}


func get_recruits_for_chapter(chapter_id: String) -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for recruit_id in _items:
		var recruit: Dictionary = _items[recruit_id]
		if str(recruit.get("recruit_chapter_id", "")) == chapter_id:
			result.append(str(recruit_id))
	return result


func get_fixed_party_members() -> Array[String]:
	if not _loaded:
		load_config()
	var result: Array[String] = []
	for recruit_id in _items:
		var recruit: Dictionary = _items[recruit_id]
		if bool(recruit.get("is_fixed_party_member", false)):
			result.append(str(recruit_id))
	return result
