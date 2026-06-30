class_name BuffConfig

const CONFIG_PATH := "res://data/buffs.json"

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
		_buffs[buff_id] = {
			"id": buff_id,
			"name": raw.get("name", ""),
			"type": raw.get("type", ""),
			"duration": float(raw.get("duration", 0.0)),
			"interval": float(raw.get("interval", 0)),
			"tick_damage": int(raw.get("tick_damage", 0)),
			"slow_ratio": float(raw.get("slow_ratio", 0.0)),
			"max_stacks": int(raw.get("max_stacks", 1)),
			"effect_scene": raw.get("effect_scene", ""),
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
