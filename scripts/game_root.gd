extends Node2D
## 游戏根节点：只持有 UIRoot 作为唯一 UI 入口，不再直接挂载 HUD、角色面板、旧背包和动态 DebugLayer。

const TEST_SETTINGS_PATH := "res://data/test_settings.json"

@onready var level_container: Node2D = $LevelContainer
@onready var party_manager: PartyManager = $Player
@onready var ui_root: UIRoot = $UIRoot

var player: CharacterBody2D
var _level_manager: Node
var _enemy_spawner: Node
var _npc_spawner: NpcSpawner
var _interaction_manager: InteractionManager
var _world_content_spawner: WorldContentSpawner
var _party_retry_pending := false
var _quest_world_refresh_pending := false
var _story_bootstrap_pending := false




func _ready() -> void:
	GameRegistry.game_root = self
	player = party_manager.get_active_character()
	if player == null:
		push_error("[GameRoot] PartyManager 没有可用的主控角色")
		return
	party_manager.active_character_changed.connect(_on_active_character_changed)
	party_manager.party_changed.connect(_on_party_changed)
	_on_party_changed()

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
	_enemy_spawner.enemy_defeated.connect(_on_enemy_defeated)
	_enemy_spawner.combat_started.connect(_on_combat_started)
	_enemy_spawner.combat_ended.connect(_on_combat_ended)

	# NPC 与交互管理器独立于战斗角色，关卡切换时按配置重建。
	_npc_spawner = NpcSpawner.new()
	_npc_spawner.name = "NpcSpawner"
	add_child(_npc_spawner)
	_npc_spawner.setup(level_container)
	_world_content_spawner = WorldContentSpawner.new()
	_world_content_spawner.name = "WorldContentSpawner"
	add_child(_world_content_spawner)
	_world_content_spawner.setup(level_container)

	# 初始化统一 UIRoot（HUD / 主菜单 / 任务抽屉 / Debug 面板均在内部构建）
	ui_root.setup(party_manager, _enemy_spawner)
	_interaction_manager = InteractionManager.new()
	_interaction_manager.name = "InteractionManager"
	add_child(_interaction_manager)
	_interaction_manager.setup(party_manager, _npc_spawner, ui_root, _world_content_spawner)
	ui_root.interact_requested.connect(_interaction_manager.try_interact)
	if GameRegistry.quest_service != null:
		GameRegistry.quest_service.quest_updated.connect(_on_quest_updated)
		GameRegistry.quest_service.quest_started.connect(_on_quest_world_state_changed)
		GameRegistry.quest_service.quest_completed.connect(_on_quest_world_state_changed)
		GameRegistry.quest_service.stage_changed.connect(_on_quest_stage_changed)

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


func _on_party_changed() -> void:
	for member in party_manager.get_party_members():
		var combat := member.get_node_or_null("CombatComponent")
		if combat != null and combat.has_signal("died") and not combat.died.is_connected(_on_party_member_died):
			combat.died.connect(_on_party_member_died)


func _on_party_member_died() -> void:
	call_deferred("_check_party_wipe")


func _check_party_wipe() -> void:
	if _party_retry_pending or not party_manager.get_alive_party_members().is_empty():
		return
	_party_retry_pending = true
	ui_root.show_notification("队伍全灭，正在返回本关入口……")
	get_tree().create_timer(1.5).timeout.connect(_retry_from_level_start)


func _retry_from_level_start() -> void:
	if _level_manager == null:
		_party_retry_pending = false
		return
	var level_id: int = int(_level_manager.get_current_level_id())
	var config: Dictionary = GameRegistry.level_config.get_level(level_id)
	var spawn: Vector2 = Vector2(float(config.get("spawn_x", 160)), float(config.get("spawn_y", 350)))
	party_manager.respawn_party(spawn)
	_level_manager.reload_current()
	_party_retry_pending = false


func _load_start_level() -> void:
	var saved_level_id := int(GameRegistry.quest_state.get_flag("current_level_id", -1)) if GameRegistry.quest_state != null else -1
	if saved_level_id >= 0 and not GameRegistry.level_config.get_level(saved_level_id).is_empty():
		_level_manager.load_level(saved_level_id)
		return
	var debug_level_id := _get_debug_start_level_id()
	if debug_level_id > 0:
		var debug_level: Dictionary = GameRegistry.level_config.get_level(debug_level_id)
		if not debug_level.is_empty():
			print("[GameRoot] 使用测试出生关卡: %s (%s)" % [
				debug_level.get("name", ""),
				debug_level_id,
			])
			_level_manager.load_level(debug_level_id)
			return
		push_warning("[GameRoot] 测试出生关卡不存在，改用默认首关: %d" % debug_level_id)
	var first: Dictionary = GameRegistry.level_config.get_first_level()
	if not first.is_empty():
		_level_manager.load_level(int(first.get("id", 1)))
	else:
		# 配置表为空时使用场景中已有的关卡
		_place_player_at_spawn()


func _get_debug_start_level_id() -> int:
	if not OS.is_debug_build() or not FileAccess.file_exists(TEST_SETTINGS_PATH):
		return 0
	var file := FileAccess.open(TEST_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return 0
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("[GameRoot] 测试出生关卡配置解析失败，改用默认首关")
		return 0
	return int((json.data as Dictionary).get("start_level_id", 0))


func _on_level_loaded(level_id: int, level_name: String) -> void:
	print("[GameRoot] 关卡已加载: %s (%s)" % [level_name, level_id])
	# 生成怪物（测试用：在关卡中生成几只 slime）
	_spawn_level_enemies(level_id)
	_spawn_level_npcs(level_id)
	_world_content_spawner.spawn_for_level(level_id)
	# 首个关卡就绪后触发开局选角/过场自动链（内部保证只执行一次）
	if not _story_bootstrap_pending:
		_story_bootstrap_pending = true
		call_deferred("_bootstrap_story")
	# 进入关卡时尝试恢复属于该关卡的自动链（排在 bootstrap 之后执行）
	if GameRegistry.story_auto_play != null:
		GameRegistry.story_auto_play.on_level_loaded(level_id)


func _bootstrap_story() -> void:
	_story_bootstrap_pending = false
	if GameRegistry.story_auto_play != null:
		GameRegistry.story_auto_play.bootstrap()


## 等主控角色落地（供剧情系统在播放"保留场景画面"的过场前调用）。
## 对话暂停游戏是约定：不先等落地，暂停会把人物冻结在半空。
## 3 秒兜底，防止极端情况下永不落地导致剧情不播。
func wait_player_landed() -> void:
	var elapsed := 0.0
	while player != null and is_instance_valid(player) and not player.is_on_floor() and elapsed < 3.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _on_level_unloaded(_level_id: int) -> void:
	_enemy_spawner.clear_all()
	_npc_spawner.clear_all()
	_world_content_spawner.clear_all()


func _spawn_level_enemies(level_id: int) -> void:
	var level_cfg: Dictionary = GameRegistry.level_config.get_level(level_id)
	var spawns: Array = []
	var index := 0
	for value in level_cfg.get("enemies", []):
		if value is Dictionary:
			spawns.append(_tag_spawn_key(value, level_id, "s", index))
			index += 1
	index = 0
	for value in _world_content_spawner.get_enemy_spawns(level_id):
		if value is Dictionary:
			spawns.append(_tag_spawn_key(value, level_id, "d", index))
			index += 1
	# 章节回响：首通后该章副本改刷回响表（替换剧情摆位），支撑无限重刷
	var chapter_id := ""
	if GameRegistry.chapter_service != null:
		chapter_id = GameRegistry.chapter_service.get_chapter_for_level(level_id)
	if chapter_id != "" and GameRegistry.chapter_service.is_echo_unlocked(chapter_id):
		var table := _echo_table_for_level(level_id)
		if not table.is_empty():
			_enemy_spawner.spawn_echo_for_level(table, _echo_tier_for(chapter_id, table), chapter_id)
			_notify_echo_enter(chapter_id)
			return
	if spawns.is_empty():
		return
	_enemy_spawner.spawn_enemies_for_level(spawns)


var _echo_spawns_cache: Dictionary = {}


## 读 data/echo_spawns.json（缓存一次）。
func _echo_table_for_level(level_id: int) -> Dictionary:
	if _echo_spawns_cache.is_empty():
		var path := "res://data/echo_spawns.json"
		if FileAccess.file_exists(path):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
				_echo_spawns_cache = (json.data as Dictionary).get("levels", {})
		else:
			push_warning("echo_spawns.json 不存在，章节回响不可用")
	var table = _echo_spawns_cache.get(str(level_id), {})
	return table if table is Dictionary else {}


## tier = clamp((队伍平均等级 - 章基准) / 8 + 回响通关次数 / 3, 0, 10)
func _echo_tier_for(chapter_id: String, table: Dictionary) -> int:
	var avg := 1
	if GameRegistry.roster_data != null:
		var ids: Array = GameRegistry.roster_data.lineup_ids
		var sum := 0
		for id in ids:
			sum += GameRegistry.roster_data.get_level(int(id))
		avg = maxi(1, int(round(float(sum) / float(maxi(1, ids.size())))))
	var base := int(table.get("chapter_base_level", 1))
	var clears := 0
	if GameRegistry.chapter_service != null:
		clears = GameRegistry.chapter_service.get_echo_clears(chapter_id)
	return clampi(int(floor(float(avg - base) / 8.0)) + int(clears / 3), 0, 10)


func _notify_echo_enter(chapter_id: String) -> void:
	var ui_root := get_tree().get_first_node_in_group("ui_root")
	if ui_root == null or not ui_root.has_method("show_notification"):
		return
	var chapter_name := ""
	var clears := 0
	if GameRegistry.chapter_service != null:
		chapter_name = GameRegistry.chapter_service.get_chapter_name(chapter_id)
		clears = GameRegistry.chapter_service.get_echo_clears(chapter_id)
	ui_root.show_notification("回响·%s · 第 %d 轮" % [chapter_name if chapter_name != "" else chapter_id, clears + 1])


## 给生成条目打上稳定 spawn 标识：静态配置与动态内容分命名空间，
## 优先用数据里的 spawn_id，缺失时退回条目下标（静态顺序稳定，动态条目均配有 spawn_id）。
func _tag_spawn_key(entry: Dictionary, level_id: int, source: String, index: int) -> Dictionary:
	var result := entry.duplicate(true)
	result["spawn_key"] = "l%d_%s_%s" % [level_id, source, str(entry.get("spawn_id", "idx%d" % index))]
	return result


func _spawn_level_npcs(level_id: int) -> void:
	_npc_spawner.spawn_npcs_for_level(level_id)


func _on_enemy_defeated(enemy_id: int) -> void:
	if GameRegistry.quest_service != null:
		GameRegistry.quest_service.record_kill(enemy_id)


func _on_combat_started(is_boss: bool) -> void:
	if GameRegistry.music_config == null:
		return
	var scene_key := "boss" if is_boss else "battle"
	var track: Dictionary = GameRegistry.music_config.get_track(scene_key)
	# Boss 未单独发布时退回普通战斗曲；两者都缺失则继续播放关卡曲。
	if track.is_empty() and is_boss:
		track = GameRegistry.music_config.get_track("battle")
	if track.is_empty():
		return
	var path := str(track.get("path", ""))
	if path.is_empty():
		return
	AudioManager.play_bgm(
		path,
		float(track.get("gain_db", 0.0)),
		float(track.get("fade_ms", 700.0)),
		bool(track.get("loop", true)),
	)


func _on_combat_ended() -> void:
	if _level_manager != null and _level_manager.has_method("restore_level_bgm"):
		_level_manager.restore_level_bgm()


func _on_quest_updated(_quest_id: int) -> void:
	# 进度更新（例如击杀 +1）只刷新 NPC 标识和 HUD。不能重建敌人，否则
	# 每杀一只任务怪都会清场并重新生成整批怪物。
	if _npc_spawner != null:
		_npc_spawner.refresh_indicators()


func _on_quest_world_state_changed(_quest_id: int) -> void:
	# 只有接取/交付造成任务阶段变化时，才重建受条件控制的世界内容。
	# 信号也可能从物理回调链发出，因此仍延迟到安全帧并合并重复请求。
	if _quest_world_refresh_pending:
		return
	_quest_world_refresh_pending = true
	call_deferred("_refresh_world_after_quest_update")


func _on_quest_stage_changed(_quest_id: int, _stage_id: String) -> void:
	# 阶段进入也会改变世界内容（例如战斗阶段的任务刷怪），
	# 不能只在接取/交付时刷新。
	_on_quest_world_state_changed(_quest_id)


func _refresh_world_after_quest_update() -> void:
	if not is_inside_tree():
		_quest_world_refresh_pending = false
		return
	if _npc_spawner != null:
		_npc_spawner.refresh_indicators()
	if _world_content_spawner != null:
		_world_content_spawner.refresh()
	if _enemy_spawner != null and _level_manager != null:
		_enemy_spawner.clear_all()
		_spawn_level_enemies(_level_manager.get_current_level_id())
	_quest_world_refresh_pending = false


## UI 输入统一在此处理；世界操作（Tab 切人、R 重载）保留。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(InputActions.TOGGLE_INVENTORY):
		ui_root.toggle_backpack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.TOGGLE_EQUIPMENT):
		ui_root.toggle_main_menu(UIRoot.TAB_EQUIPMENT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.SWITCH_CHARACTER):
		party_manager.switch_next_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.RELOAD_LEVEL):
		# 测试：R 键重载当前关卡
		_level_manager.reload_current()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CANCEL):
		# 按优先级关闭：弹窗 → 任务抽屉 → 主菜单
		if ui_root.is_modal_open():
			ui_root.close_top()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.TOGGLE_DEBUG):
		ui_root.toggle_debug_panel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		# F4/F5/F6 调试开关保留物理键（开发专用，无需触屏化）
		match event.keycode:
			KEY_F4:
				ui_root.set_debug_draw_flags(not DebugDraw.show_collision, DebugDraw.show_hurtbox, DebugDraw.show_hitbox)
				get_viewport().set_input_as_handled()
			KEY_F5:
				ui_root.set_debug_draw_flags(DebugDraw.show_collision, not DebugDraw.show_hurtbox, DebugDraw.show_hitbox)
				get_viewport().set_input_as_handled()
			KEY_F6:
				ui_root.set_debug_draw_flags(DebugDraw.show_collision, DebugDraw.show_hurtbox, not DebugDraw.show_hitbox)
				get_viewport().set_input_as_handled()
			KEY_F2:
				# 地图切换测试面板
				ui_root.toggle_map_panel()
				get_viewport().set_input_as_handled()
			KEY_F3:
				# 玩家坐标显示开关（摆放/触发点调试）
				ui_root.toggle_coord_display()
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
