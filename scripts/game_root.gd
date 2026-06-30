extends Node2D

@onready var level_container: Node2D = $LevelContainer
@onready var player: CharacterBody2D = $Player
@onready var inventory_panel: CanvasLayer = $InventoryPanel
@onready var character_panel: CanvasLayer = $CharacterPanel

var _level_manager: Node
var _enemy_spawner: Node


func _ready() -> void:
	# 创建并注册 LevelManager
	_level_manager = load("res://scripts/system/level_manager.gd").new()
	_level_manager.name = "LevelManager"
	add_child(_level_manager)
	_level_manager.setup(level_container, player)
	GameRegistry.level_manager = _level_manager

	# 创建怪物生成器
	_enemy_spawner = load("res://scripts/system/enemy_spawner.gd").new()
	_enemy_spawner.name = "EnemySpawner"
	add_child(_enemy_spawner)
	_enemy_spawner.setup(player, level_container)

	# 监听关卡加载信号
	_level_manager.level_loaded.connect(_on_level_loaded)
	_level_manager.level_unloaded.connect(_on_level_unloaded)

	# 加载首个关卡（从配置表）
	call_deferred("_load_start_level")


func _load_start_level() -> void:
	var first: Dictionary = GameRegistry.level_config.get_first_level()
	if not first.is_empty():
		_level_manager.load_level(int(first.get("id", 1)))
	else:
		# 配置表为空时使用场景中已有的关卡
		_place_player_at_spawn()


func _on_level_loaded(level_id: int, level_name: String) -> void:
	print("[GameRoot] 关卡已加载: %s (%s)" % [level_name, level_id])
	# 生成怪物（测试用：在关卡中生成几只 slime）
	_spawn_level_enemies(level_id)


func _on_level_unloaded(_level_id: int) -> void:
	_enemy_spawner.clear_all()


func _spawn_level_enemies(level_id: int) -> void:
	# 从关卡配置读取怪物生成点，或使用默认测试生成
	var level_cfg: Dictionary = GameRegistry.level_config.get_level(level_id)
	var spawns: Array = level_cfg.get("enemies", [])
	if spawns.is_empty():
		# 默认测试生成：在玩家出生点附近生成 2 只 slime
		var spawn_pos := player.global_position + Vector2(200, 0)
		_enemy_spawner.spawn_enemy(1001, spawn_pos)
		_enemy_spawner.spawn_enemy(1001, spawn_pos + Vector2(80, 0))
	else:
		_enemy_spawner.spawn_enemies_for_level(spawns)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if inventory_panel.is_open() or character_panel.is_open():
		return
	match event.keycode:
		KEY_B:
			inventory_panel.toggle()
			get_viewport().set_input_as_handled()
		KEY_C:
			character_panel.toggle()
			get_viewport().set_input_as_handled()
		KEY_R:
			# 测试：R 键重载当前关卡
			_level_manager.reload_current()
			get_viewport().set_input_as_handled()


func _place_player_at_spawn() -> void:
	if level_container.get_child_count() == 0:
		return
	var current_level := level_container.get_child(0)
	var spawn: Marker2D = current_level.get_node_or_null("PlayerSpawn")
	if spawn != null:
		player.global_position = spawn.global_position
