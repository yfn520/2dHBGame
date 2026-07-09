extends Node
## 关卡管理器
## 负责关卡加载/卸载、玩家传送、关卡切换

signal level_loading(level_id: int, level_name: String)
signal level_loaded(level_id: int, level_name: String)
signal level_unloaded(level_id: int)

var _current_level_id: int = -1
var _level_container: Node2D
var _player: CharacterBody2D


func setup(level_container: Node2D, player: CharacterBody2D) -> void:
	_level_container = level_container
	_player = player


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

	# 传送玩家到出生点
	if _player != null:
		var spawn_pos: Vector2
		if spawn_override != Vector2.ZERO:
			spawn_pos = spawn_override
		else:
			var spawn: Marker2D = level_instance.get_node_or_null("PlayerSpawn")
			if spawn != null:
				spawn_pos = spawn.global_position
			else:
				# 使用配置表中的坐标
				spawn_pos = Vector2(
					float(config.get("spawn_x", 160)),
					float(config.get("spawn_y", 350))
				)
		if _player.get_parent() != null and _player.get_parent().has_method("place_party_at"):
			_player.get_parent().place_party_at(spawn_pos)
		else:
			_player.global_position = spawn_pos

	level_loaded.emit(level_id, config.get("name", ""))


## 传送到指定关卡的指定坐标
func teleport_to(level_id: int, pos: Vector2) -> void:
	load_level(level_id, pos)


## 重新加载当前关卡（死亡重生等）
func reload_current() -> void:
	if _current_level_id > 0:
		load_level(_current_level_id)


func _unload_current() -> void:
	if _level_container.get_child_count() > 0:
		var old_level := _level_container.get_child(0)
		var old_id := _current_level_id
		_level_container.remove_child(old_level)
		old_level.queue_free()
		level_unloaded.emit(old_id)
	_current_level_id = -1
