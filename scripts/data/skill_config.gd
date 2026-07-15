class_name SkillConfig

const CONFIG_PATH := "res://data/skills.json"

var _skills: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载技能配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("技能配置解析失败: %s" % json.get_error_message())
		return
	for id_string in (json.data as Dictionary):
		var raw_value: Variant = (json.data as Dictionary)[id_string]
		if not raw_value is Dictionary:
			push_error("技能 %s 不是对象" % id_string)
			continue
		var raw: Dictionary = raw_value
		var nodes_value: Variant = raw.get("nodes", [])
		if not nodes_value is Array or (nodes_value as Array).is_empty():
			push_error("技能 %s 缺少 nodes；新技能系统不再提供旧格式回退" % id_string)
			continue
		var cache_value: Variant = raw.get("ai_range_cache", {})
		var ai_cache: Dictionary = cache_value if cache_value is Dictionary else {}
		_skills[int(id_string)] = {
			"id": int(id_string),
			"name": String(raw.get("name", "")),
			"description": String(raw.get("description", "")),
			"cooldown": float(raw.get("cooldown", 0.0)),
			"cast_range": float(raw.get("cast_range", 0.0)),
			"nodes": (nodes_value as Array).duplicate(true),
			"ai_range_cache": ai_cache.duplicate(true),
		}
	_loaded = true


func get_skill(skill_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	var skill: Dictionary = _skills.get(skill_id, {})
	return skill.duplicate(true)


func get_all_skills() -> Dictionary:
	if not _loaded:
		load_config()
	return _skills.duplicate(true)


func is_valid_skill(skill_id: int) -> bool:
	return not get_skill(skill_id).is_empty()


## 返回技能的 ai_range_cache（节点驱动 AI 距离缓存）。
func get_ai_range_cache(skill_id: int) -> Dictionary:
	var skill: Dictionary = get_skill(skill_id)
	return skill.get("ai_range_cache", {}) if not skill.is_empty() else {}


## 将更新后的 ai_range_cache 写回 skills.json 并刷新内存。
func save_ai_range_cache(skill_id: int, cache: Dictionary) -> void:
	if not _loaded:
		load_config()
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取技能配置用于写回: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("技能配置解析失败: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	var key := str(skill_id)
	if not data.has(key):
		return
	var raw: Dictionary = data[key]
	raw["ai_range_cache"] = cache
	data[key] = raw
	var out := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if out == null:
		push_error("无法写入技能配置: %s" % CONFIG_PATH)
		return
	out.store_string(JSON.stringify(data, "\t") + "\n")
	# 刷新内存缓存
	if _skills.has(skill_id):
		_skills[skill_id]["ai_range_cache"] = cache.duplicate(true)
