extends Node2D

@onready var level_container: Node2D = $LevelContainer
@onready var player: CharacterBody2D = $Player
@onready var inventory_panel: CanvasLayer = $InventoryPanel
@onready var character_panel: CanvasLayer = $CharacterPanel

var _level_manager: Node
var _enemy_spawner: Node
var _debug_label: Label




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

	# 创建 Debug 面板
	_setup_debug_panel()

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
	var level_cfg: Dictionary = GameRegistry.level_config.get_level(level_id)
	var spawns: Array = level_cfg.get("enemies", [])
	if spawns.is_empty():
		return
	_enemy_spawner.spawn_enemies_for_level(spawns)


func _process(_delta: float) -> void:
	if _debug_label != null and _debug_label.visible:
		_update_debug_panel()


func _setup_debug_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugLayer"
	layer.layer = 100
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "DebugPanel"
	panel.position = Vector2(10, 10)
	panel.size = Vector2(350, 400)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	panel.add_child(_debug_label)


func _update_debug_panel() -> void:
	var lines: PackedStringArray = []
	var combat = player.get_node_or_null("CombatComponent")
	var stats = GameRegistry.character_stats

	# ---- Debug 开关状态 ----
	lines.append("=== Debug (F3/F4/F5/F6) ===")
	lines.append("碰撞体:%s  受伤区:%s  攻击区:%s" % [
		"ON" if DebugDraw.show_collision else "off",
		"ON" if DebugDraw.show_hurtbox else "off",
		"ON" if DebugDraw.show_hitbox else "off",
	])

	# ---- 玩家信息 ----
	lines.append("=== 玩家 ===")
	if stats != null:
		lines.append("HP: %d / %d" % [stats.hp, stats.max_hp])
		lines.append("ATK: %d  DEF: %d  SPD: %d" % [stats.attack, stats.defense, stats.move_speed])
	if combat != null:
		lines.append("状态: %s" % _state_name(combat.combat_state))
		# 技能冷却
		var cooldowns: Dictionary = combat.get_cooldowns_dict()
		var skill_names := {1001: "普攻", 1002: "火球术", 1003: "旋风斩", 1004: "冰霜箭"}
		var cd_parts: PackedStringArray = []
		for sid in cooldowns:
			var cd: float = cooldowns[sid]
			var name: String = skill_names.get(sid, str(sid))
			cd_parts.append("%s:%.1fs" % [name, cd] if cd > 0 else "%s:OK" % name)
		lines.append("CD: %s" % " | ".join(cd_parts))

	# ---- 怪物信息 ----
	lines.append("")
	lines.append("=== 怪物 ===")
	if _enemy_spawner != null:
		var enemies: Array = _enemy_spawner._active_enemies
		if enemies.is_empty():
			lines.append("(无)")
		else:
			for enemy in enemies:
				if not is_instance_valid(enemy):
					continue
				var dist_x := absf(player.global_position.x - enemy.global_position.x)
				var e_stats = enemy.get_combat_stats() if enemy.has_method("get_combat_stats") else null
				var hp_str := "?"
				if e_stats != null:
					hp_str = "%d/%d" % [e_stats.hp, e_stats.max_hp]
				var ai_name: String = enemy.get_ai_state_name() if enemy.has_method("get_ai_state_name") else "?"
				var e_name: String = enemy.get_enemy_name() if enemy.has_method("get_enemy_name") else "?"
				lines.append("[%s] HP:%s AI:%s XDist:%d" % [e_name, hp_str, ai_name, int(dist_x)])

	_debug_label.text = "\n".join(lines)


func _state_name(state) -> String:
	match state:
		0: return "IDLE"
		1: return "ATTACKING"
		2: return "SKILL"
		3: return "HIT"
		4: return "DEAD"
		_: return str(state)


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
		KEY_F3:
			_debug_label.get_parent().visible = not _debug_label.get_parent().visible
			get_viewport().set_input_as_handled()
		KEY_F4:
			DebugDraw.show_collision = not DebugDraw.show_collision
			get_viewport().set_input_as_handled()
		KEY_F5:
			DebugDraw.show_hurtbox = not DebugDraw.show_hurtbox
			get_viewport().set_input_as_handled()
		KEY_F6:
			DebugDraw.show_hitbox = not DebugDraw.show_hitbox
			get_viewport().set_input_as_handled()


func _place_player_at_spawn() -> void:
	if level_container.get_child_count() == 0:
		return
	var current_level := level_container.get_child(0)
	var spawn: Marker2D = current_level.get_node_or_null("PlayerSpawn")
	if spawn != null:
		player.global_position = spawn.global_position
