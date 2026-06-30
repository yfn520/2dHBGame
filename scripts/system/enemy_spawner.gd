extends Node
## 关卡怪物生成器
## 在关卡加载后，根据配置在指定位置生成怪物

const ENEMY_SCENE := "res://scenes/enemy.tscn"

var _enemy_scene: PackedScene
var _player: CharacterBody2D
var _spawn_container: Node2D
var _active_enemies: Array[Node] = []


func _ready() -> void:
	_enemy_scene = load(ENEMY_SCENE) as PackedScene


func setup(player: CharacterBody2D, spawn_container: Node2D) -> void:
	_player = player
	_spawn_container = spawn_container


## 在指定位置生成怪物
func spawn_enemy(enemy_id: int, pos: Vector2) -> Node:
	if _enemy_scene == null:
		push_error("怪物场景加载失败")
		return null

	var enemy := _enemy_scene.instantiate()
	enemy.global_position = pos
	_spawn_container.add_child(enemy)

	if enemy.has_method("init_from_config"):
		enemy.init_from_config(enemy_id, _player)

	_active_enemies.append(enemy)
	# 怪物死亡时从列表移除
	enemy.tree_exiting.connect(_on_enemy_removed.bind(enemy))
	return enemy


## 在关卡中批量生成怪物
func spawn_enemies_for_level(spawns: Array[Dictionary]) -> void:
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
