class_name MusicConfig

const CONFIG_PATH := "res://data/music.json"

var _tracks: Dictionary = {}  # scene_key → Dictionary
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	if not FileAccess.file_exists(CONFIG_PATH):
		# 空壳文件由网页发布创建；缺失时静默返回（BGM 是增强功能，不阻塞游戏）
		_loaded = true
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载音乐配置: %s" % CONFIG_PATH)
		_loaded = true
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("音乐配置解析失败: %s" % CONFIG_PATH)
		_loaded = true
		return
	if not json.data is Dictionary:
		push_error("音乐配置根节点必须是对象: %s" % CONFIG_PATH)
		_loaded = true
		return
	var data: Dictionary = json.data
	if str(data.get("format", "")) != "frame-ronin-music-v1":
		push_error("音乐配置格式不正确（期望 frame-ronin-music-v1）")
		_loaded = true
		return
	var tracks_value = data.get("tracks", {})
	if not tracks_value is Dictionary:
		push_error("音乐配置 tracks 必须是对象: %s" % CONFIG_PATH)
		_loaded = true
		return
	var tracks: Dictionary = tracks_value
	for scene_key in tracks:
		var raw_value = tracks[scene_key]
		if not raw_value is Dictionary:
			push_warning("音乐配置忽略无效轨: %s" % scene_key)
			continue
		var raw: Dictionary = raw_value
		_tracks[str(scene_key)] = {
			"scene_key": str(scene_key),
			"name": str(raw.get("name", "")),
			"path": str(raw.get("path", "")),
			"duration_ms": int(raw.get("duration_ms", 0)),
			"loop": bool(raw.get("loop", true)),
			"gain_db": float(raw.get("gain_db", 0.0)),
			"fade_ms": float(raw.get("fade_ms", 1200.0)),
			"source": str(raw.get("source", "generated")),
			"derived_from": str(raw.get("derived_from", "")),
			"init_noise_level": float(raw.get("init_noise_level", 0.0)),
		}
	_loaded = true


## 按 scene_key 取轨（level:<id> / main_menu / battle / boss / cutscene ...）；无则空 Dictionary。
func get_track(scene_key: String) -> Dictionary:
	load_config()
	return _tracks.get(scene_key, {})


## 关卡 BGM：优先 music.json 的 level:<id> 轨，回退 levels.json 的 bgm 字段（由 level_config 提供）。
func get_level_bgm(level_id: int, level_config = null) -> String:
	load_config()
	var scene_key := "level:%d" % level_id
	var track: Dictionary = get_track(scene_key)
	if not track.is_empty() and not str(track.get("path", "")).is_empty():
		return str(track.get("path", ""))
	if level_config != null:
		var level: Dictionary = level_config.get_level(level_id) if level_config.has_method("get_level") else {}
		return str(level.get("bgm", ""))
	return ""
