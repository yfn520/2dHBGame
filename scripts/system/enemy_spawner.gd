extends Node
## 关卡怪物生成器
## 在关卡加载后，根据配置在指定位置生成怪物

var _scene_cache: Dictionary = {}  # enemy_id → PackedScene
var _party_manager: PartyManager
var _spawn_container: Node2D
var _active_enemies: Array[Node] = []
var _engaged_enemies: Dictionary = {}  # instance_id → is_boss
var _combat_mode := ""

signal enemy_defeated(enemy_id: int)
signal combat_started(is_boss: bool)
signal combat_ended
signal echo_cleared(chapter_id: String)

# --- 章节回响（可重刷 farming）常量 ---
const ECHO_MAX_ALIVE := 12
const ECHO_FIRST_DELAY := 2.0
const ECHO_SAFE_DISTANCE := 384.0   # 玩家距刷新点半屏宽内不刷，避免贴脸刷
const ECHO_RESPAWN_RETRY := 2.0

var _echo_active := false
var _echo_chapter_id := ""
var _echo_tier := 0
var _echo_groups: Array = []   # {enemy_id, pos, scatter_x, count, alive, next_respawn_s, initial_spawned}
var _echo_singles: Array = []  # {enemy_id, pos, spawned, alive}
var _echo_alive := 0
var _echo_first_pending := false
var _echo_timer := 0.0
var _echo_cleared_recorded := false


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


## 在指定位置生成怪物；spawn_key 非空时记录到实例上，击杀时用于持久化。
## stat_scale/exp_scale 用于章节回响的 tier 缩放（hp/atk 与 exp 乘数）。
func spawn_enemy(enemy_id: int, pos: Vector2, spawn_key := "", stat_scale := 1.0, exp_scale := 1.0) -> Node:
	var scene := _get_scene(enemy_id)
	if scene == null:
		return null

	var enemy := scene.instantiate()
	enemy.global_position = pos
	if not spawn_key.is_empty():
		enemy.set_meta("spawn_key", spawn_key)
	_spawn_container.add_child(enemy)

	if enemy.has_method("init_from_config"):
		enemy.init_from_config(enemy_id, _party_manager, stat_scale, exp_scale)

	_active_enemies.append(enemy)
	if enemy.has_signal("defeated"):
		enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
	if enemy.has_signal("combat_engagement_changed"):
		enemy.combat_engagement_changed.connect(_on_combat_engagement_changed.bind(enemy))
	enemy.tree_exiting.connect(_on_enemy_removed.bind(enemy))
	return enemy


## 在关卡中批量生成怪物
## 支持两种记录：
##   point: {mode:"point", enemy_id, x, y} 单怪点，绝不随机偏移
##   group: {mode:"group", enemy_id, x, y, count, scatter_x} 中心点 + X 轴散布
## 旧记录（无 mode）按 count 推断：count<=1 视为 point，count>1 视为 group（scatter_x 默认 20）。
## 带 spawn_key 的记录按已击杀数过滤：单怪杀过跳过，群怪只补剩余只数。
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
		var mode := str(entry.get("mode", ""))
		var count := int(entry.get("count", 1))
		var spawn_key := str(entry.get("spawn_key", ""))
		var killed := _get_kill_count(spawn_key)
		if mode.is_empty():
			mode = "group" if count > 1 else "point"
		if mode == "point":
			if killed >= 1:
				continue
			spawn_enemy(enemy_id, pos, spawn_key)
		else:
			var scatter_x := float(entry.get("scatter_x", 20.0))
			var actual_count := maxi(0, maxi(1, count) - killed)
			for _i in range(actual_count):
				var offset_x: float = randf_range(-scatter_x, scatter_x)
				spawn_enemy(enemy_id, pos + Vector2(offset_x, 0), spawn_key)


## 清除所有怪物
func clear_all() -> void:
	_engaged_enemies.clear()
	_update_combat_mode()
	_echo_active = false
	_echo_groups.clear()
	_echo_singles.clear()
	_echo_alive = 0
	_echo_first_pending = false
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
	_engaged_enemies.erase(enemy.get_instance_id())
	_update_combat_mode()


## 只有怪物真正进入追击/攻击状态才算开战；同屏 Boss 优先于普通战斗。
func _on_combat_engagement_changed(engaged: bool, is_boss: bool, enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var instance_id := enemy.get_instance_id()
	if engaged:
		_engaged_enemies[instance_id] = is_boss
	else:
		_engaged_enemies.erase(instance_id)
	_update_combat_mode()


func _update_combat_mode() -> void:
	var next_mode := ""
	for is_boss_value in _engaged_enemies.values():
		if bool(is_boss_value):
			next_mode = "boss"
			break
		next_mode = "battle"
	if next_mode == _combat_mode:
		return
	_combat_mode = next_mode
	if _combat_mode.is_empty():
		combat_ended.emit()
	else:
		combat_started.emit(_combat_mode == "boss")


func _on_enemy_defeated(enemy_id: int, _enemy: Node = null) -> void:
	_record_kill(_enemy)
	_grant_drops(enemy_id)
	_record_echo_boss_kill(enemy_id, _enemy)
	_on_echo_defeated(_enemy)
	enemy_defeated.emit(enemy_id)


## 已击杀数持久化在 world_state.flags（enemy_kills:<spawn_key> → int），随存档保存；
## 无 spawn_key 的敌人（如调试生成）不记录，行为与之前一致。
func _get_kill_count(spawn_key: String) -> int:
	if spawn_key.is_empty() or GameRegistry.quest_state == null:
		return 0
	return int(GameRegistry.quest_state.get_flag("enemy_kills:%s" % spawn_key, 0))


func _record_kill(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta("spawn_key"):
		return
	if GameRegistry.quest_state == null:
		return
	var spawn_key := str(enemy.get_meta("spawn_key"))
	GameRegistry.quest_state.set_flag("enemy_kills:%s" % spawn_key, _get_kill_count(spawn_key) + 1)
	GameRegistry.save_game()


func _grant_drops(enemy_id: int) -> void:
	if GameRegistry.inventory_provider == null:
		return
	var cfg: Dictionary = GameRegistry.enemy_config.get_enemy(enemy_id)
	var raw_traits = cfg.get("traits", [])
	var is_echo := raw_traits is Array and (raw_traits as Array).has("echo")
	var drops: Array = cfg.get("drop_items", [])
	if is_echo:
		# 回响怪常规掉 farming 表；唯一装备（chance>=0.999）仅首杀保证，防农穿
		if cfg.has("echo_drop_items"):
			drops = cfg.get("echo_drop_items", [])
		if not _echo_first_kill_done(enemy_id):
			for value in cfg.get("drop_items", []):
				var unique_chance := 1.0
				if value is Dictionary:
					unique_chance = clampf(float(value.get("chance", 1.0)), 0.0, 1.0)
				if unique_chance >= 0.999:
					_add_drop(value)
			_mark_echo_first_kill(enemy_id)
	for value in drops:
		_add_drop(value)


func _add_drop(value) -> void:
	var item_id := 0
	var count := 1
	var chance := 1.0
	if value is Dictionary:
		item_id = int(value.get("item_id", 0))
		count = maxi(1, int(value.get("count", 1)))
		chance = clampf(float(value.get("chance", 1.0)), 0.0, 1.0)
	else:
		item_id = int(value)
	if item_id > 0 and randf() <= chance:
		GameRegistry.inventory_provider.add_item(item_id, count)
		var ui_root := get_tree().get_first_node_in_group("ui_root")
		if ui_root != null and ui_root.has_method("show_notification"):
			ui_root.show_notification("获得战利品 ×%d" % count)


func _echo_first_kill_done(enemy_id: int) -> bool:
	if GameRegistry.quest_state == null:
		return true
	return bool(GameRegistry.quest_state.get_flag("echo_first_kill:%d" % enemy_id, false))


func _mark_echo_first_kill(enemy_id: int) -> void:
	if GameRegistry.quest_state == null:
		return
	GameRegistry.quest_state.set_flag("echo_first_kill:%d" % enemy_id, true)
	GameRegistry.save_game()


func _record_echo_boss_kill(enemy_id: int, enemy: Node) -> void:
	if not _echo_active or enemy == null or not is_instance_valid(enemy) or not enemy.has_meta("echo_group"):
		return
	var cfg: Dictionary = GameRegistry.enemy_config.get_enemy(enemy_id)
	var traits = cfg.get("traits", [])
	if not cfg.get("is_boss", false) or not (traits is Array and (traits as Array).has("echo")):
		return
	if GameRegistry.chapter_service != null and GameRegistry.chapter_service.has_method("record_echo_boss_kill"):
		GameRegistry.chapter_service.record_echo_boss_kill(_echo_chapter_id)


# ===================== 章节回响刷怪 =====================

## 开启章节回响：不写击杀持久化（每次进图全量重刷）+ 波次重生支撑不断重刷。
func spawn_echo_for_level(table: Dictionary, tier: int, chapter_id: String) -> void:
	_echo_active = true
	_echo_chapter_id = chapter_id
	_echo_tier = tier
	_echo_groups.clear()
	_echo_singles.clear()
	_echo_alive = 0
	_echo_cleared_recorded = false
	for value in table.get("groups", []):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		_echo_groups.append({
			"enemy_id": int(entry.get("enemy_id", 0)),
			"pos": Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))),
			"scatter_x": float(entry.get("scatter_x", 24.0)),
			"respawn_s": float(entry.get("respawn_s", 45.0)),
			"count": maxi(0, int(entry.get("count", 1))),
			"alive": 0,
			"next_respawn_s": -1.0,
			"initial_spawned": false,
		})
	for key in ["elite", "boss"]:
		var single = table.get(key)
		if single is Dictionary and int(single.get("enemy_id", 0)) > 0:
			_echo_singles.append({
				"enemy_id": int(single.get("enemy_id", 0)),
				"pos": Vector2(float(single.get("x", 0)), float(single.get("y", 0))),
				"spawned": false,
				"alive": false,
			})
	_echo_first_pending = true
	_echo_timer = ECHO_FIRST_DELAY
	set_process(true)


func _process(delta: float) -> void:
	if not _echo_active:
		return
	_echo_timer -= delta
	if _echo_first_pending:
		if _echo_timer <= 0.0:
			_echo_first_pending = false
			_spawn_echo_initial()
		return
	_try_respawn_echo_waves(delta)


func _echo_stat_scales() -> Dictionary:
	return {
		"stat": 1.0 + 0.15 * float(_echo_tier),
		"exp": 1.0 + 0.25 * float(_echo_tier),
	}


func _spawn_echo_unit(enemy_id: int, pos: Vector2, scatter_x: float, group_index: int) -> bool:
	var scales := _echo_stat_scales()
	var offset_x := randf_range(-scatter_x, scatter_x) if scatter_x > 0.0 else 0.0
	var enemy := spawn_enemy(enemy_id, pos + Vector2(offset_x, 0), "", scales["stat"], scales["exp"])
	if enemy == null:
		return false
	enemy.set_meta("echo_group", group_index)
	_echo_alive += 1
	return true


func _spawn_echo_initial() -> void:
	for i in range(_echo_singles.size()):
		if _echo_alive >= ECHO_MAX_ALIVE:
			break
		var single: Dictionary = _echo_singles[i]
		if not bool(single["spawned"]):
			if _spawn_echo_unit(int(single["enemy_id"]), single["pos"], 0.0, -1 - i):
				single["spawned"] = true
				single["alive"] = true
	for gi in range(_echo_groups.size()):
		var group: Dictionary = _echo_groups[gi]
		_spawn_echo_group_until_full(group, gi)
		if int(group["alive"]) >= int(group["count"]):
			group["initial_spawned"] = true
		else:
			# 一次首刷被全图上限截断时，后续按安全距离重试补齐。
			group["next_respawn_s"] = 0.0


func _try_respawn_echo_waves(delta: float) -> void:
	var player: Node = _party_manager.get_active_character() if _party_manager != null else null
	for gi in range(_echo_groups.size()):
		var group: Dictionary = _echo_groups[gi]
		var next_respawn_s := float(group.get("next_respawn_s", -1.0))
		if next_respawn_s < 0.0:
			continue
		next_respawn_s = maxf(0.0, next_respawn_s - delta)
		group["next_respawn_s"] = next_respawn_s
		if next_respawn_s > 0.0:
			continue
		if _echo_alive >= ECHO_MAX_ALIVE:
			group["next_respawn_s"] = ECHO_RESPAWN_RETRY
			continue
		if player != null and is_instance_valid(player) and player.global_position.distance_to(group["pos"]) < ECHO_SAFE_DISTANCE:
			group["next_respawn_s"] = ECHO_RESPAWN_RETRY
			continue
		_spawn_echo_group_until_full(group, gi)
		if int(group["alive"]) >= int(group["count"]):
			group["initial_spawned"] = true
			group["next_respawn_s"] = -1.0
		else:
			group["next_respawn_s"] = ECHO_RESPAWN_RETRY


func _spawn_echo_group_until_full(group: Dictionary, group_index: int) -> void:
	while int(group["alive"]) < int(group["count"]) and _echo_alive < ECHO_MAX_ALIVE:
		if not _spawn_echo_unit(int(group["enemy_id"]), group["pos"], float(group["scatter_x"]), group_index):
			break
		group["alive"] = int(group["alive"]) + 1


func _on_echo_defeated(enemy: Node) -> void:
	if not _echo_active or enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.has_meta("echo_group"):
		return
	var group_index := int(enemy.get_meta("echo_group"))
	_echo_alive = maxi(0, _echo_alive - 1)
	if group_index >= 0 and group_index < _echo_groups.size():
		var group: Dictionary = _echo_groups[group_index]
		group["alive"] = maxi(0, int(group["alive"]) - 1)
		if int(group["alive"]) == 0:
			# 群怪整组消灭后，按数据表的 respawn_s 重生；精英和 Boss 不在图内重生。
			group["next_respawn_s"] = maxf(0.0, float(group.get("respawn_s", 45.0)))
	else:
		var single_index := -1 - group_index
		if single_index >= 0 and single_index < _echo_singles.size():
			_echo_singles[single_index]["alive"] = false
	_check_echo_cleared()


## 首轮整图清完（群怪全部首刷且死完 + 精英/Boss 死完）→ 记一次回响通关。
## 计数后仍保留群怪波次重生，支持同一张地图内的持续刷怪。
func _check_echo_cleared() -> void:
	if _echo_cleared_recorded or _echo_first_pending:
		return
	if _echo_alive > 0:
		return
	for group in _echo_groups:
		if not bool(group.get("initial_spawned", false)):
			return
	for single in _echo_singles:
		if not bool(single["spawned"]) or bool(single["alive"]):
			return
	_echo_cleared_recorded = true
	if GameRegistry.chapter_service != null and GameRegistry.chapter_service.has_method("record_echo_clear"):
		GameRegistry.chapter_service.record_echo_clear(_echo_chapter_id)
	echo_cleared.emit(_echo_chapter_id)
