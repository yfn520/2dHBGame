extends Node
## 关卡管理器
## 负责关卡加载/卸载、玩家传送、关卡切换

signal level_loading(level_id: int, level_name: String)
signal level_loaded(level_id: int, level_name: String)
signal level_unloaded(level_id: int)

var _current_level_id: int = -1
var _level_container: Node2D
var _player: CharacterBody2D
var _current_level_bounds := Rect2()
var _has_current_level_bounds := false
var _current_ground_line_y := 605.0


func setup(level_container: Node2D, player: CharacterBody2D) -> void:
	_level_container = level_container
	_player = player
	# 切换主控英雄后，新英雄的 Camera2D 也必须继承当前关卡边界。
	if _has_current_level_bounds:
		_apply_camera_bounds(_current_level_bounds, _current_ground_line_y)


func get_current_level_id() -> int:
	return _current_level_id


func get_current_level_config() -> Dictionary:
	if _current_level_id < 0:
		return {}
	return GameRegistry.level_config.get_level(_current_level_id)


## 加载指定关卡（卸载当前关卡后加载新关卡）
func load_level(level_id: int, spawn_override: Vector2 = Vector2.ZERO) -> void:
	var config: Dictionary = GameRegistry.level_config.get_level(level_id)
	if config.is_empty():
		push_error("关卡不存在: %s" % level_id)
		return

	var scene_path: String = config.get("scene_path", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("关卡场景不存在: %s" % scene_path)
		return

	level_loading.emit(level_id, config.get("name", ""))

	# 卸载当前关卡
	_unload_current()

	# 加载新关卡场景
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("加载关卡场景失败: %s" % scene_path)
		return

	var level_instance := scene.instantiate()
	level_instance.name = "CurrentLevel"
	_level_container.add_child(level_instance)
	_current_level_id = level_id
	if GameRegistry.quest_state != null:
		GameRegistry.quest_state.set_flag("current_level_id", level_id)

	# 传送玩家到出生点
	# 优先级：spawn_override > levels.json.spawn_x/spawn_y > 场景 PlayerSpawn Marker2D
	if _player != null:
		var spawn_pos: Vector2
		if spawn_override != Vector2.ZERO:
			spawn_pos = spawn_override
		elif config.has("spawn_x") and config.has("spawn_y") and (int(config.get("spawn_x", 0)) != 0 or int(config.get("spawn_y", 0)) != 0):
			# JSON 配置了出生点，以 JSON 为准；场景里的 PlayerSpawn 仅作旧数据回退
			spawn_pos = Vector2(
				float(config.get("spawn_x", 160)),
				float(config.get("spawn_y", 350))
			)
		else:
			# 旧 JSON 未配置出生坐标时，回退到场景中的 PlayerSpawn
			var spawn: Marker2D = level_instance.get_node_or_null("PlayerSpawn")
			if spawn != null:
				spawn_pos = spawn.global_position
			else:
				spawn_pos = Vector2(160, 350)
		if _player.get_parent() != null and _player.get_parent().has_method("place_party_at"):
			_player.get_parent().place_party_at(spawn_pos)
		else:
			_player.global_position = spawn_pos

	# 根据关卡场景的 Sprite2D 整体边界动态设置玩家相机边界
	# （覆盖 player.gd 里的 1536×864 默认边界，支持任意宽度的横向拼接地图）
	_apply_camera_limits(level_instance)
	_play_level_bgm(level_id)

	level_loaded.emit(level_id, config.get("name", ""))
	GameRegistry.save_game()


## 传送到指定关卡的指定坐标
func teleport_to(level_id: int, pos: Vector2) -> void:
	load_level(level_id, pos)


## 扫描关卡场景里所有 Sprite2D 的世界 AABB，算出整体边界并设置玩家相机 limit。
## 使用 Sprite2D 的实际局部矩形和 global_transform，兼容缩放、翻转及父节点变换。
func _apply_camera_limits(level_instance: Node) -> void:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for child in level_instance.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if (
			sprite == null
			or sprite.texture == null
			or bool(sprite.get_meta("camera_bounds_excluded", false))
		):
			continue
		var local_rect := sprite.get_rect()
		var transform := sprite.global_transform
		var corners := [
			transform * local_rect.position,
			transform * Vector2(local_rect.end.x, local_rect.position.y),
			transform * local_rect.end,
			transform * Vector2(local_rect.position.x, local_rect.end.y),
		]
		for corner: Vector2 in corners:
			min_x = minf(min_x, corner.x)
			min_y = minf(min_y, corner.y)
			max_x = maxf(max_x, corner.x)
			max_y = maxf(max_y, corner.y)
	if is_inf(min_x):
		_has_current_level_bounds = false
		return
	_current_level_bounds = Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x, max_y - min_y)
	)
	_current_ground_line_y = clampf(
		float(level_instance.get_meta("ground_line_y", 605.0)),
		432.0,
		777.0
	)
	_has_current_level_bounds = true
	_apply_camera_bounds(_current_level_bounds, _current_ground_line_y)


func _apply_camera_bounds(bounds: Rect2, ground_line_y: float = 605.0) -> void:
	if _player == null:
		return
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera == null:
		return
	camera.limit_left = floori(bounds.position.x)
	camera.limit_top = floori(bounds.position.y)
	camera.limit_right = ceili(bounds.end.x)
	camera.limit_bottom = ceili(bounds.end.y)
	camera.zoom = Vector2.ONE
	camera.limit_smoothed = true
	if _player.has_method("configure_level_camera"):
		_player.configure_level_camera(bounds, ground_line_y)
	else:
		camera.reset_smoothing()
	print("[LevelManager] camera limits: L=%d T=%d R=%d B=%d (player y=%f, camera offset=%s)" % [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom, _player.global_position.y, str(camera.position)])


## 重新加载当前关卡（死亡重生等）
func reload_current() -> void:
	if _current_level_id >= 0:
		load_level(_current_level_id)


## 战斗结束后恢复当前关卡 BGM；由 EnemySpawner 的聚合脱战事件调用。
func restore_level_bgm() -> void:
	if _current_level_id >= 0:
		_play_level_bgm(_current_level_id)


## 关卡音乐优先由 data/music.json 驱动，兼容旧 levels.json.bgm。
## BGM 缺失时停止上一关的轨，避免跨关卡残留；加载失败只由 AudioManager 告警，不阻塞切图。
func _play_level_bgm(level_id: int) -> void:
	if GameRegistry.music_config == null:
		return
	var track: Dictionary = GameRegistry.music_config.get_track("level:%d" % level_id)
	var path: String = GameRegistry.music_config.get_level_bgm(level_id, GameRegistry.level_config)
	if path.is_empty():
		AudioManager.stop_bgm()
		return
	AudioManager.play_bgm(
		path,
		float(track.get("gain_db", 0.0)),
		float(track.get("fade_ms", 1200.0)),
		bool(track.get("loop", true)),
	)


func _unload_current() -> void:
	if _level_container.get_child_count() > 0:
		var old_level := _level_container.get_child(0)
		var old_id := _current_level_id
		_level_container.remove_child(old_level)
		old_level.queue_free()
		level_unloaded.emit(old_id)
	_current_level_id = -1
	_has_current_level_bounds = false
	_current_ground_line_y = 605.0
