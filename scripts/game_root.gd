extends Node2D
## 游戏根节点：只持有 UIRoot 作为唯一 UI 入口，不再直接挂载 HUD、角色面板、旧背包和动态 DebugLayer。

@onready var level_container: Node2D = $LevelContainer
@onready var party_manager: PartyManager = $Player
@onready var ui_root: UIRoot = $UIRoot

var player: CharacterBody2D
var _level_manager: Node
var _enemy_spawner: Node




func _ready() -> void:
	player = party_manager.get_active_character()
	if player == null:
		push_error("[GameRoot] PartyManager 没有可用的主控角色")
		return
	party_manager.active_character_changed.connect(_on_active_character_changed)

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
	_enemy_spawner.setup(party_manager, level_container)

	# 初始化统一 UIRoot（HUD / 主菜单 / 任务抽屉 / Debug 面板均在内部构建）
	ui_root.setup(party_manager, _enemy_spawner)

	# 监听关卡加载信号
	_level_manager.level_loaded.connect(_on_level_loaded)
	_level_manager.level_unloaded.connect(_on_level_unloaded)

	# 加载首个关卡（从配置表）
	call_deferred("_load_start_level")


func _on_active_character_changed(character: CharacterBody2D) -> void:
	player = character
	if _level_manager != null:
		_level_manager.setup(level_container, player)
	if _enemy_spawner != null:
		_enemy_spawner.setup(party_manager, level_container)


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
	var level_cfg: Dictionary = GameRegistry.level_config.get_level(level_id)
	var spawns: Array = level_cfg.get("enemies", [])
	if spawns.is_empty():
		return
	_enemy_spawner.spawn_enemies_for_level(spawns)


## UI 输入统一在此处理；世界操作（Tab 切人、R 重载）保留。
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_B:
			ui_root.toggle_main_menu(UIRoot.TAB_INVENTORY)
			get_viewport().set_input_as_handled()
		KEY_C:
			ui_root.toggle_main_menu(UIRoot.TAB_EQUIPMENT)
			get_viewport().set_input_as_handled()
		KEY_TAB:
			party_manager.switch_next_character()
			get_viewport().set_input_as_handled()
		KEY_R:
			# 测试：R 键重载当前关卡
			_level_manager.reload_current()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			# 按优先级关闭：弹窗 → 任务抽屉 → 主菜单
			if ui_root.is_modal_open():
				ui_root.close_top()
				get_viewport().set_input_as_handled()
		KEY_F3:
			ui_root.toggle_debug_panel()
			get_viewport().set_input_as_handled()
		KEY_F4:
			ui_root.set_debug_draw_flags(not DebugDraw.show_collision, DebugDraw.show_hurtbox, DebugDraw.show_hitbox)
			get_viewport().set_input_as_handled()
		KEY_F5:
			ui_root.set_debug_draw_flags(DebugDraw.show_collision, not DebugDraw.show_hurtbox, DebugDraw.show_hitbox)
			get_viewport().set_input_as_handled()
		KEY_F6:
			ui_root.set_debug_draw_flags(DebugDraw.show_collision, DebugDraw.show_hurtbox, not DebugDraw.show_hitbox)
			get_viewport().set_input_as_handled()
		KEY_M:
			# 主界面 UI 资源验证：切换显隐（按 M 键）
			ui_root.toggle_main_ui()
			get_viewport().set_input_as_handled()


func _place_player_at_spawn() -> void:
	if level_container.get_child_count() == 0:
		return
	var current_level := level_container.get_child(0)
	var spawn: Marker2D = current_level.get_node_or_null("PlayerSpawn")
	if spawn != null:
		party_manager.place_party_at(spawn.global_position)
