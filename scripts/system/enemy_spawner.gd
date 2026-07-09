extends Node
## 关卡怪物生成器
## 在关卡加载后，根据配置在指定位置生成怪物

var _scene_cache: Dictionary = {}  # enemy_id → PackedScene
var _party_manager: PartyManager
var _spawn_container: Node2D
var _active_enemies: Array[Node] = []


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
	enemy.tree_exiting.connect(_on_enemy_removed.bind(enemy))
	return enemy


## 在关卡中批量生成怪物
func spawn_enemies_for_level(spawns: Array) -> void:
	for spawn_data in spawns:
		var enemy_id := int(spawn_data.get("enemy_id", 0))
		var pos := Vector2(
			float(spawn_data.get("x", 0)),
			float(spawn_data.get("y", 0))
		)
		var count := int(spawn_data.get("count", 1))
		for i in range(count):
			var offset_x := randf_range(-20.0, 20.0) if count > 1 else 0.0
			spawn_enemy(enemy_id, pos + Vector2(offset_x, 0))


## 清除所有怪物
func clear_all() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()


func get_active_count() -> int:
	return _active_enemies.size()


func _on_enemy_removed(enemy: Node) -> void:
	_active_enemies.erase(enemy)
