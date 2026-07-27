class_name ChapterConfig
extends RefCounted

const CONFIG_PATH := "res://data/chapters.json"

var _chapters: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	_chapters.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("章节配置不存在: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CONFIG_PATH)) != OK or not json.data is Dictionary:
		push_error("章节配置解析失败: %s" % CONFIG_PATH)
		return
	for chapter_id in json.data:
		var raw: Dictionary = json.data[chapter_id]
		_chapters[chapter_id] = {
			"chapter_id": chapter_id,
			"order": int(raw.get("order", 0)),
			"name": str(raw.get("name", chapter_id)),
			"mood": str(raw.get("mood", "")),
			"required_previous_chapter_id": str(raw.get("required_previous_chapter_id", "")),
			"dungeon_level_ids": _to_int_array(raw.get("dungeon_level_ids", [])),
			"normal_boss_enemy_id": int(raw.get("normal_boss_enemy_id", 0)),
			"echo_boss_enemy_id": int(raw.get("echo_boss_enemy_id", 0)),
			"town_change_ids": _to_string_array(raw.get("town_change_ids", [])),
			"story_node_ids": _to_string_array(raw.get("story_node_ids", [])),
			"description": str(raw.get("description", "")),
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


func get_chapter(chapter_id: String) -> Dictionary:
	if not _loaded:
		load_config()
	return _chapters.get(chapter_id, {})


func get_all_chapters() -> Dictionary:
	if not _loaded:
		load_config()
	return _chapters


func is_valid_chapter(chapter_id: String) -> bool:
	if not _loaded:
		load_config()
	return _chapters.has(chapter_id)


func get_chapter_by_order(order: int) -> Dictionary:
	if not _loaded:
		load_config()
	for chapter_id in _chapters:
		var chapter: Dictionary = _chapters[chapter_id]
		if int(chapter.get("order", -1)) == order:
			return chapter
	return {}


func get_ordered_chapter_ids() -> Array[String]:
	if not _loaded:
		load_config()
	var entries: Array = []
	for chapter_id in _chapters:
		entries.append({"id": chapter_id, "order": int(_chapters[chapter_id].get("order", 0))})
	entries.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	var result: Array[String] = []
	for entry in entries:
		result.append(str(entry["id"]))
	return result


func get_levels_for_chapter(chapter_id: String) -> Array[int]:
	var chapter := get_chapter(chapter_id)
	if chapter.is_empty():
		return []
	return chapter.get("dungeon_level_ids", [])


func get_chapter_for_level(level_id: int) -> String:
	if not _loaded:
		load_config()
	for chapter_id in _chapters:
		var levels: Array[int] = _chapters[chapter_id].get("dungeon_level_ids", [])
		if levels.has(level_id):
			return chapter_id
	return ""
