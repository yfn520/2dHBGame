extends SceneTree
## BGM 配置与播放 API 的 headless 守卫。
##
## headless 限制（踩过的坑，勿改回）：
##   1. `godot --headless --script` 下 autoload 标识符（AudioManager / GameRegistry）不可用，
##      直接引用会 Compile Error；引用了 GameRegistry 的脚本（enemy_spawner / level_manager）
##      连 load() 都会编译失败、方法列表为空。故这些脚本一律用**源码文本断言**。
##   2. 不要 preload()：那是编译期依赖，比 load() 更早失败。
##   3. data config 类是 RefCounted，调 free() 会运行时报错并中断 _init（导致不 quit 而挂死）。
## 运行：godot --headless --path . --script tests/music_config.gd

const AUDIO_MANAGER_PATH := "res://scripts/system/audio_manager.gd"
const LEVEL_MANAGER_PATH := "res://scripts/system/level_manager.gd"
const ENEMY_SPAWNER_PATH := "res://scripts/system/enemy_spawner.gd"


func _init() -> void:
	var failures: Array[String] = []

	# --- 1. 播放 API：源码断言（audio_manager 引用 autoload，headless 下不实例化） ---
	var audio_source := _read_source(AUDIO_MANAGER_PATH)
	if audio_source.is_empty():
		failures.append("无法读取 %s" % AUDIO_MANAGER_PATH)
	else:
		for required in ["func play_bgm(", "func stop_bgm(", "func get_current_bgm("]:
			if not audio_source.contains(required):
				failures.append("AudioManager 缺少 %s" % required.trim_prefix("func ").trim_suffix("("))
		# BGM 必须走独立总线与独立播放器，不能复用 SFX 池（池会因多音节策略打断长音频）
		if not audio_source.contains("BUS_BGM"):
			failures.append("AudioManager 的 BGM 未使用 BUS_BGM 总线")
		if not audio_source.contains("_bgm_active_player"):
			failures.append("AudioManager 缺少独立 BGM 播放器")
		# 对白/过场会暂停整棵树：BGM 播放器与淡入淡出 tween 必须暂停免疫，否则对话时 BGM 被冻住
		if not audio_source.contains("PROCESS_MODE_ALWAYS"):
			failures.append("BGM 播放器未设置 PROCESS_MODE_ALWAYS（对白暂停时 BGM 会停）")
		if not audio_source.contains("TWEEN_PAUSE_PROCESS"):
			failures.append("BGM 淡入淡出 tween 未设置暂停免疫")
		# 混音约定守卫：运行时建总线（项目不依赖 default_bus_layout.tres）
		if not audio_source.contains("func _ensure_buses("):
			failures.append("AudioManager 缺少 _ensure_buses（运行时建总线）")
		for bus_spec in ["\"BGM\", \"db\": -10.0", "\"SFX\", \"db\": 0.0", "\"UI\", \"db\": -6.0"]:
			if not audio_source.contains(bus_spec):
				failures.append("AudioManager 总线约定缺少 %s" % bus_spec)

	# --- 2. 关卡/战斗钩子：源码断言（两个脚本都引用 GameRegistry，load() 会编译失败） ---
	var level_source := _read_source(LEVEL_MANAGER_PATH)
	if level_source.is_empty():
		failures.append("无法读取 %s" % LEVEL_MANAGER_PATH)
	else:
		for required in ["func restore_level_bgm(", "func _play_level_bgm(", "play_bgm(", "stop_bgm("]:
			if not level_source.contains(required):
				failures.append("LevelManager 缺少 %s" % required)
	var spawner_source := _read_source(ENEMY_SPAWNER_PATH)
	if spawner_source.is_empty():
		failures.append("无法读取 %s" % ENEMY_SPAWNER_PATH)
	else:
		for required in ["signal combat_started", "signal combat_ended"]:
			if not spawner_source.contains(required):
				failures.append("EnemySpawner 缺少 %s" % required)

	# --- 3. MusicConfig 真实行为（RefCounted，不依赖 autoload，可安全实例化） ---
	var config_script = load("res://scripts/data/music_config.gd")
	if config_script == null:
		failures.append("无法加载 scripts/data/music_config.gd")
	else:
		var config = config_script.new()
		config.load_config()
		if not config.has_method("get_track") or not config.has_method("get_level_bgm"):
			failures.append("MusicConfig 缺少查询方法")
		# music.json 允许尚未发布（首次发布前不存在）；存在时逐关校验路径可解析
		var levels_script = load("res://scripts/data/level_config.gd")
		if levels_script != null:
			var levels = levels_script.new()
			levels.load_config()
			for level_id in levels.get_all_levels():
				var resolved_path: String = config.get_level_bgm(int(level_id), levels)
				if resolved_path.is_empty():
					continue
				if not ResourceLoader.exists(resolved_path):
					failures.append("关卡 %s 的 BGM 资源不存在：%s" % [level_id, resolved_path])
				var track: Dictionary = config.get_track("level:%s" % level_id)
				if not track.is_empty() and str(track.get("path", "")) != resolved_path:
					failures.append("关卡 %s 的 music.json 与 levels.json 回退路径不一致" % level_id)
	_report(failures)


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[music_config] OK")
		quit(0)
		return
	for failure in failures:
		push_error("[music_config] %s" % failure)
	quit(1)
