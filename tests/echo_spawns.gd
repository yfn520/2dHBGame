extends SceneTree
## 章节回响数据守卫（纯数据解析，不依赖 autoload，可安全 headless 运行）。
## 运行：godot --headless --path . --script tests/echo_spawns.gd

const ECHO_PATH := "res://data/echo_spawns.json"
const ENEMIES_PATH := "res://data/enemies.json"
const CHAPTERS_PATH := "res://data/chapters.json"
const SPAWNER_PATH := "res://scripts/system/enemy_spawner.gd"
const CHAPTER_SERVICE_PATH := "res://scripts/system/chapter_service.gd"


func _init() -> void:
	var failures: Array[String] = []
	var echo := _read_json(ECHO_PATH)
	var enemies := _read_json(ENEMIES_PATH)
	var chapters := _read_json(CHAPTERS_PATH)
	if echo.is_empty() or enemies.is_empty() or chapters.is_empty():
		_report(["回响/敌人/章节数据读取失败"])
		return
	var levels = echo.get("levels", {})
	if not levels is Dictionary:
		_report(["echo_spawns.levels 必须是对象"])
		return
	if levels.size() < 6:
		failures.append("回响表关卡数 %d < 6" % levels.size())
	_check_runtime_guardrails(failures)
	for level_id in levels:
		var table = levels[level_id]
		if not table is Dictionary:
			failures.append("echo_spawns[%s] 必须是对象" % level_id)
			continue
		var chapter_id := str(table.get("chapter_id", ""))
		var entries: Array = []
		for group in (table.get("groups", []) if table.get("groups") is Array else []):
			if group is Dictionary:
				entries.append(["group", int(group.get("enemy_id", 0))])
		for key in ["elite", "boss"]:
			var single = table.get(key)
			if single is Dictionary:
				entries.append([key, int(single.get("enemy_id", 0))])
		if entries.is_empty():
			failures.append("echo_spawns[%s] 没有任何刷怪条目" % level_id)
		for entry in entries:
			var kind := str(entry[0])
			var enemy_id := int(entry[1])
			var enemy = enemies.get(str(enemy_id), {})
			if not enemy is Dictionary or enemy.is_empty():
				failures.append("echo_spawns[%s].%s 敌人不存在: %d" % [level_id, kind, enemy_id])
				continue
			# group 复用剧情怪（不带 echo trait）；只有 elite/boss 是回响变体
			if kind != "group":
				var traits = enemy.get("traits", [])
				if not traits is Array or not (traits as Array).has("echo"):
					failures.append("echo_spawns[%s].%s %d traits 必须含 echo" % [level_id, kind, enemy_id])
			if kind == "boss":
				if not bool(enemy.get("is_boss", false)):
					failures.append("echo_spawns[%s].boss %d 必须 is_boss" % [level_id, enemy_id])
				if not (enemy.get("echo_drop_items", []) is Array) or (enemy.get("echo_drop_items", []) as Array).is_empty():
					failures.append("echo_spawns[%s].boss %d 缺少 echo_drop_items（防农穿）" % [level_id, enemy_id])
				if not _has_first_kill_unique_and_repeat_drop(enemy):
					failures.append("echo_spawns[%s].boss %d 缺首杀唯一掉落或 0.08 回响复刷掉落" % [level_id, enemy_id])
				var chapter = chapters.get(chapter_id, {})
				if int(chapter.get("echo_boss_enemy_id", 0)) != enemy_id:
					failures.append("chapters[%s].echo_boss_enemy_id 与回响表 boss 不一致" % chapter_id)
	_report(failures)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


## enemy_spawner 引用了 autoload，headless 下不能实例化；以源码契约守住回响行为。
func _check_runtime_guardrails(failures: Array[String]) -> void:
	if not FileAccess.file_exists(SPAWNER_PATH):
		failures.append("找不到回响刷怪器：%s" % SPAWNER_PATH)
		return
	var source := FileAccess.get_file_as_string(SPAWNER_PATH)
	for required in [
		"func spawn_echo_for_level(",
		"func _try_respawn_echo_waves(",
		"func _spawn_echo_group_until_full(",
		"group[\"next_respawn_s\"] = maxf(0.0, float(group.get(\"respawn_s\", 45.0)))",
		"_spawn_container.add_child(enemy)",
	]:
		if not source.contains(required):
			failures.append("EnemySpawner 缺少回响运行时契约：%s" % required)
	# Echo 怪没有 spawn_key，必须仍挂进关卡树；否则会生成不可见的游离节点。
	var spawn_key_block := "if not spawn_key.is_empty():\n\t\tenemy.set_meta(\"spawn_key\", spawn_key)\n\t_spawn_container.add_child(enemy)"
	if not source.contains(spawn_key_block):
		failures.append("EnemySpawner 必须无条件 add_child，回响怪才能实际进图")
	for required in ["record_echo_boss_kill"]:
		if not source.contains(required):
			failures.append("EnemySpawner 缺少回响 Boss 计数契约：%s" % required)
	var chapter_service_source := _read_source(CHAPTER_SERVICE_PATH)
	if not chapter_service_source.contains("func get_echo_boss_kills(") or not chapter_service_source.contains("func record_echo_boss_kill(") or not chapter_service_source.contains("echo_boss_kills:"):
		failures.append("ChapterService 缺少回响 Boss 持久化计数 API")


func _has_first_kill_unique_and_repeat_drop(enemy: Dictionary) -> bool:
	var unique_ids: Dictionary = {}
	for value in enemy.get("drop_items", []):
		if value is Dictionary and float(value.get("chance", 0.0)) >= 0.999:
			unique_ids[int(value.get("item_id", 0))] = true
	# 原 Boss 没有 chance=1 唯一装备时无需伪造首杀规则；仍保留材料/货币 farming 表。
	if unique_ids.is_empty():
		return true
	for value in enemy.get("echo_drop_items", []):
		if value is Dictionary and is_equal_approx(float(value.get("chance", 0.0)), 0.08) and unique_ids.has(int(value.get("item_id", 0))):
			return true
	return false


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _report(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[echo_spawns] OK")
		quit(0)
		return
	for failure in failures:
		push_error("[echo_spawns] %s" % failure)
	quit(1)
