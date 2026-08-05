@tool
extends RefCounted

## 打包技能数据为运行时二进制：
## 遍历 res://data/skills/actors/{actor_id}.json → var_to_bytes → res://data/skills/bin/{actor_id}.bin
## bin 文件头："FRSP"（4 字节魔数）+ 1 字节版本号 + var_to_bytes 数据。
## bin 仅供发布包运行时读取，编辑器工具自身永远不读 bin。

const ACTORS_DIR := "res://data/skills/actors"
const BIN_DIR := "res://data/skills/bin"
const CHARACTERS_PATH := "res://data/characters.json"
const ENEMIES_PATH := "res://data/enemies.json"
const BIN_MAGIC := "FRSP"
const BIN_VERSION := 1


## 执行打包。返回 {"ok": bool, "message": String}，message 为人类可读摘要（含警告列表）。
static func pack_all() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	# 1. 读取所有 actor 技能文件
	var actor_skills: Dictionary = {}  # actor_id -> Dictionary(skill_id -> skill)
	var dir := DirAccess.open(ACTORS_DIR)
	if dir == null:
		return {"ok": false, "message": "技能目录不存在：%s\n请先把技能数据拆分为每角色一个文件。" % ACTORS_DIR}
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var actor_id := int(file_name.get_basename())
		if actor_id <= 0:
			warnings.append("文件名不是有效 actor_id，已跳过：%s" % file_name)
			continue
		var path := ACTORS_DIR.path_join(file_name)
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
			errors.append("无法解析：%s" % path)
			continue
		actor_skills[actor_id] = json.data
	if actor_skills.is_empty() and errors.is_empty():
		return {"ok": false, "message": "%s 下没有任何技能文件。" % ACTORS_DIR}
	# 2. 校验：characters/enemies 引用的技能是否都存在；孤儿技能列提示
	var all_skill_ids: Dictionary = {}  # skill_id(int) -> true
	var skill_owner: Dictionary = {}  # skill_id(int) -> actor_id
	for actor_id in actor_skills:
		for skill_id in (actor_skills[actor_id] as Dictionary).keys():
			var sid := int(skill_id)
			if skill_owner.has(sid) and int(skill_owner[sid]) != int(actor_id):
				warnings.append("技能 %d 同时存在于 %d 和 %d 两个文件" % [sid, int(skill_owner[sid]), int(actor_id)])
			skill_owner[sid] = actor_id
			all_skill_ids[sid] = true
	var referenced := _collect_referenced_skill_ids()  # skill_id(int) -> Array[String] 引用来源
	var missing: Array[String] = []
	for skill_id in referenced.keys():
		if not all_skill_ids.has(skill_id):
			missing.append("%d（%s）" % [int(skill_id), ", ".join(referenced[skill_id])])
	if not missing.is_empty():
		missing.sort()
		warnings.append("引用了但技能文件里不存在：\n  " + "\n  ".join(missing))
	var orphan: Array[String] = []
	for skill_id in all_skill_ids.keys():
		if not referenced.has(skill_id):
			orphan.append(str(skill_id))
	if not orphan.is_empty():
		orphan.sort_custom(func(a, b): return int(a) < int(b))
		warnings.append("存在但无任何角色/怪物引用（孤儿）：\n  " + ", ".join(orphan))
	# 3. 写 bin：魔数 + 版本 + var_to_bytes
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BIN_DIR))
	var skill_count := 0
	for actor_id in actor_skills:
		var skills: Dictionary = actor_skills[actor_id]
		var bin_path := BIN_DIR.path_join("%d.bin" % actor_id)
		var file := FileAccess.open(bin_path, FileAccess.WRITE)
		if file == null:
			errors.append("无法写入：%s" % bin_path)
			continue
		file.store_buffer(BIN_MAGIC.to_utf8_buffer())
		file.store_8(BIN_VERSION)
		file.store_buffer(var_to_bytes(skills))
		skill_count += skills.size()
	# 4. 摘要
	var lines: Array[String] = []
	lines.append("已打包 %d 个角色/怪物，共 %d 个技能 → %s" % [actor_skills.size(), skill_count, BIN_DIR])
	for w in warnings:
		lines.append("警告：" + w)
	for e in errors:
		lines.append("错误：" + e)
	return {"ok": errors.is_empty(), "message": "\n".join(lines)}


## 收集 characters.json / enemies.json 里引用的全部技能 id。
## 返回 {skill_id(int): Array[String] 引用来源}。
static func _collect_referenced_skill_ids() -> Dictionary:
	var result: Dictionary = {}
	_collect_from_table(CHARACTERS_PATH, "角色", result)
	_collect_from_table(ENEMIES_PATH, "怪物", result)
	return result


static func _collect_from_table(table_path: String, type_label: String, result: Dictionary) -> void:
	var table := _read_json(table_path)
	for key in table:
		var row_value: Variant = table[key]
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var source := "%s %s（%s）" % [type_label, key, String(row.get("name", row.get("hero_name", "")))]
		var normal := int(row.get("normal_skill", 0))
		if normal > 0:
			_add_ref(result, normal, source)
		for value in row.get("skills", []):
			_add_ref(result, int(value), source)
		for slot in (row.get("skill_unlocks", {}) as Dictionary).values():
			if slot is Dictionary:
				_add_ref(result, int(slot.get("skill_id", 0)), source)
		# skill_weights 元素通常是纯权重数值（与 skills 平行）；仅当元素是 {skill_id, weight} 字典时才算引用
		for weight_value in row.get("skill_weights", []):
			if weight_value is Dictionary:
				_add_ref(result, int(weight_value.get("skill_id", 0)), source)
		for value in row.get("ai_skill_priority", []):
			_add_ref(result, int(value), source)


static func _add_ref(result: Dictionary, skill_id: int, source: String) -> void:
	if skill_id <= 0:
		return
	if not result.has(skill_id):
		result[skill_id] = []
	(result[skill_id] as Array).append(source)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data
