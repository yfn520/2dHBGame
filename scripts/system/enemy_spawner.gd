extends Node
## 关卡怪物生成器
## 在关卡加载后，根据配置在指定位置生成怪物

var _scene_cache: Dictionary = {}  # enemy_id → PackedScene
var _party_manager: PartyManager
var _spawn_container: Node2D
var _active_enemies: Array[Node] = []

signal enemy_defeated(enemy_id: int)


func setup(party_manager: PartyManager, spawn_container: Node2D) -> void:
	_party_manager = party_manager
	_spawn_container = spawn_container


## 根据 enemy_id 加载对应的模板场景
func _get_scene(enemy_id: int) -> PackedScene:
	if enemy_id in _scene_cache:
		return _scene_cache[enemy_id]

	var cfg: Dictionary = GameRegistry.enemy_config.get_enemy(enemy_id)
	if cfg.is_empty():
		push_error("怪物配置不存在: %d" % enemy_id)
		return null

	var asset_path: String = cfg.get("asset", "")
	if asset_path.is_empty():
		push_error("怪物资源目录未配置: %d" % enemy_id)
		return null
	var scene_name := asset_path.get_file()
	var scene_path := asset_path.path_join("godot/%s.tscn" % scene_name)
	if not ResourceLoader.exists(scene_path):
		push_error("怪物模板场景不存在: %s" % scene_path)
		return null

	var scene: PackedScene = load(scene_path)
	_scene_cache[enemy_id] = scene
	return scene


## 在指定位置生成怪物
func spawn_enemy(enemy_id: int, pos: Vector2) -> Node:
	var scene := _get_scene(enemy_id)
	if scene == null:
		return null

	var enemy := scene.instantiate()
	enemy.global_position = pos
	_spawn_container.add_child(enemy)

	if enemy.has_method("init_from_config"):
		enemy.init_from_config(enemy_id, _party_manager)

	_active_enemies.append(enemy)
	if enemy.has_signal("defeated"):
		enemy.defeated.connect(_on_enemy_defeated)
	enemy.tree_exiting.connect(_on_enemy_removed.bind(enemy))
	return enemy


## 在关卡中批量生成怪物
## 支持两种记录：
##   point: {mode:"point", enemy_id, x, y} 单怪点，绝不随机偏移
##   group: {mode:"group", enemy_id, x, y, count, scatter_x} 中心点 + X 轴散布
## 旧记录（无 mode）按 count 推断：count<=1 视为 point，count>1 视为 group（scatter_x 默认 20）。
func spawn_enemies_for_level(spawns: Array) -> void:
	for spawn_data in spawns:
		if not spawn_data is Dictionary:
			continue
		var entry: Dictionary = spawn_data
		var enemy_id := int(entry.get("enemy_id", 0))
		var pos := Vector2(
			float(entry.get("x", 0)),
			float(entry.get("y", 0))
		)
		var mode := String(entry.get("mode", ""))
		var count := int(entry.get("count", 1))
		if mode.is_empty():
			mode = "group" if count > 1 else "point"
		if mode == "point":
			spawn_enemy(enemy_id, pos)
		else:
			var scatter_x := float(entry.get("scatter_x", 20.0))
			var actual_count := maxi(1, count)
			for _i in range(actual_count):
				var offset_x: float = randf_range(-scatter_x, scatter_x)
				spawn_enemy(enemy_id, pos + Vector2(offset_x, 0))


## 清除所有怪物
func clear_all() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()


func get_active_count() -> int:
	return _active_enemies.size()


func get_active_enemies() -> Array[Node]:
	var result: Array[Node] = []
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			result.append(enemy)
	return result


func _on_enemy_removed(enemy: Node) -> void:
	_active_enemies.erase(enemy)


func _on_enemy_defeated(enemy_id: int) -> void:
	enemy_defeated.emit(enemy_id)
