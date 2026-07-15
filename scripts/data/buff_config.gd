class_name BuffConfig

const CONFIG_PATH := "res://data/buffs.json"
const BuffEffectRegistry = preload("res://scripts/combat/buff_effect_registry.gd")

var _buffs: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载Buff配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("Buff配置解析失败: %s" % json.get_error_message())
		return
	var data := json.data as Dictionary
	for id_str in data:
		var buff_id := int(id_str)
		var raw: Dictionary = data[id_str]
		var effects_raw: Array = raw.get("effects", [])
		var effects: Array = []
		for effect in effects_raw:
			if effect is Dictionary:
				effects.append(BuffEffectRegistry.parse_effect(effect as Dictionary))
		_buffs[buff_id] = {
			"id": buff_id,
			"name": String(raw.get("name", "")),
			"description": String(raw.get("description", "")),
			"category": String(raw.get("category", "debuff")),
			"duration": float(raw.get("duration", 0.0)),
			"max_stacks": int(raw.get("max_stacks", 1)),
			"stack_behavior": String(raw.get("stack_behavior", "refresh")),
			"icon": String(raw.get("icon", "")),
			"effect_scene": String(raw.get("effect_scene", "")),
			"effects": effects,
		}
	_loaded = true


func get_buff(buff_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	return _buffs.get(buff_id, {})


func get_all_buffs() -> Dictionary:
	if not _loaded:
		load_config()
	return _buffs


func is_valid_buff(buff_id: int) -> bool:
	return not get_buff(buff_id).is_empty()


func get_buffs_by_category(category: String) -> Array:
	var result: Array = []
	if not _loaded:
		load_config()
	for buff_id in _buffs:
		var buff: Dictionary = _buffs[buff_id]
		if String(buff.get("category", "")) == category:
			result.append(buff)
	return result
