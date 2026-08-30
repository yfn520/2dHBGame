class_name SkillConfig

## 技能配置：按角色/怪物分文件存储，运行时按需加载 + 缓存。
##
## 数据布局：
##   编辑器内始终读 res://data/skills/actors/{actor_id}.json（即使 bin 存在也忽略，
##   保证改 json 立即生效）；actor_id 为 characters/enemies 配置 id（如 7001/8001）。
##   导出包读 res://data/skills/bin/{actor_id}.bin：
##   4 字节 magic "FRSP" + 1 字节版本 + var_to_bytes 的规范化技能字典（int 键）。
##
## 启动时只建立 技能ID→actorID 索引（build_index），技能本体在首次访问时
## 按 actor 加载并缓存（_actor_cache），可通过 release_actor 释放。

const ACTORS_DIR := "res://data/skills/actors"
const BIN_DIR := "res://data/skills/bin"
const BIN_MAGIC := "FRSP"
const BIN_VERSION := 1
const DAMAGE_ACTION_TYPES := ["melee_damage", "area_damage", "fullscreen_damage", "spawn_projectile"]
const LEGACY_SINGLE_DAMAGE_FIELDS := [
	"damage_channel", "damage_tag", "physical_tag", "element_override",
	"attack_coefficient", "damage_ratio", "flat_damage", "hit_count",
	"status_type", "status_buildup", "status",
]

# 技能 ID → 所属 actor（角色/怪物配置 ID）
var _skill_to_actor: Dictionary = {}
# actor ID → 该 actor 的全部技能（{skill_id: 技能对象}）
var _actor_cache: Dictionary = {}
var _loaded := false


## 兼容入口：不再全量加载技能文件，只初始化空索引。
## 真正的索引由 GameRegistry 在角色/怪物配置加载完成后调用 build_index() 建立。
func load_config() -> void:
	if _loaded:
		return
	_skill_to_actor.clear()
	_actor_cache.clear()
	_loaded = true


## 从角色/怪物配置提取技能归属，建立 技能ID→actorID 索引。
## heroes / enemies 为 id→配置行 的字典（键允许 String 或 int）。
func build_index(heroes: Dictionary, enemies: Dictionary) -> void:
	if not _loaded:
		load_config()
	_skill_to_actor.clear()
	_actor_cache.clear()
	for hero_id_value in heroes:
		var hero_value: Variant = heroes[hero_id_value]
		if not hero_value is Dictionary:
			continue
		_index_actor_skills(int(hero_id_value), _extract_hero_skill_ids(hero_value))
	for enemy_id_value in enemies:
		var enemy_value: Variant = enemies[enemy_id_value]
		if not enemy_value is Dictionary:
			continue
		_index_actor_skills(int(enemy_id_value), _extract_enemy_skill_ids(enemy_value))


func get_skill(skill_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	if not _skill_to_actor.has(skill_id):
		push_error("技能 %d 不在索引中（未归属任何角色/怪物）" % skill_id)
		return {}
	var actor_id := int(_skill_to_actor[skill_id])
	var skills := _load_actor(actor_id)
	var skill: Dictionary = skills.get(skill_id, {})
	if skill.is_empty():
		push_error("技能 %d 在 actor %d 的配置中不存在或无效" % [skill_id, actor_id])
		return {}
	return skill.duplicate(true)


## 加载索引涉及的所有 actor 并合并返回。仅编辑器/调试工具使用。
func get_all_skills() -> Dictionary:
	if not _loaded:
		load_config()
	var merged: Dictionary = {}
	var actor_ids: Array = []
	for skill_id in _skill_to_actor:
		var actor_id := int(_skill_to_actor[skill_id])
		if not actor_ids.has(actor_id):
			actor_ids.append(actor_id)
	for actor_id in actor_ids:
		var skills := _load_actor(actor_id)
		for skill_id in skills:
			merged[skill_id] = (skills[skill_id] as Dictionary).duplicate(true)
	return merged


func is_valid_skill(skill_id: int) -> bool:
	return not get_skill(skill_id).is_empty()


## 返回技能的 ai_range_cache（节点驱动 AI 距离缓存）。
func get_ai_range_cache(skill_id: int) -> Dictionary:
	var skill: Dictionary = get_skill(skill_id)
	return skill.get("ai_range_cache", {}) if not skill.is_empty() else {}


## 将更新后的 ai_range_cache 写回该技能所属 actor 的 json 文件并刷新内存缓存。
## 非编辑器环境（导出包）不写 res://，直接返回。
func save_ai_range_cache(skill_id: int, cache: Dictionary) -> void:
	if not OS.has_feature("editor"):
		return
	if not _loaded:
		load_config()
	if not _skill_to_actor.has(skill_id):
		push_error("ai_range_cache 写回失败：技能 %d 不在索引中" % skill_id)
		return
	var actor_id := int(_skill_to_actor[skill_id])
	var path := _actor_json_path(actor_id)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取技能配置用于写回: %s" % path)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("技能配置解析失败: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	var key := str(skill_id)
	if not data.has(key):
		return
	var raw: Dictionary = data[key]
	raw["ai_range_cache"] = cache
	data[key] = raw
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_error("无法写入技能配置: %s" % path)
		return
	out.store_string(JSON.stringify(data, "\t") + "\n")
	# 刷新内存缓存
	if _actor_cache.has(actor_id):
		var skills: Dictionary = _actor_cache[actor_id]
		if skills.has(skill_id):
			skills[skill_id]["ai_range_cache"] = cache.duplicate(true)


## 释放某个 actor 的技能缓存（如怪物离场时调用）。索引保留，再次访问会重新加载。
func release_actor(actor_id: int) -> void:
	_actor_cache.erase(actor_id)


# ---- 内部 ----

func _actor_json_path(actor_id: int) -> String:
	return "%s/%d.json" % [ACTORS_DIR, actor_id]


func _actor_bin_path(actor_id: int) -> String:
	return "%s/%d.bin" % [BIN_DIR, actor_id]


func _index_actor_skills(actor_id: int, skill_ids: Array) -> void:
	for skill_id in skill_ids:
		if _skill_to_actor.has(skill_id):
			var existing := int(_skill_to_actor[skill_id])
			if existing != actor_id:
				push_warning("技能 %d 同时属于 actor %d 和 %d，以先见为准" % [skill_id, existing, actor_id])
			continue
		_skill_to_actor[skill_id] = actor_id


static func _collect_id(ids: Array, skill_id: int) -> void:
	if skill_id > 0 and not ids.has(skill_id):
		ids.append(skill_id)


## 英雄技能来源：normal_skill + skill_unlocks 各 slot + skills 数组（若有）。
func _extract_hero_skill_ids(config: Dictionary) -> Array:
	var ids: Array = []
	_collect_id(ids, int(config.get("normal_skill", 0)))
	var unlocks: Dictionary = config.get("skill_unlocks", {})
	for slot_key in unlocks:
		var slot_value: Variant = unlocks[slot_key]
		if slot_value is Dictionary:
			_collect_id(ids, int((slot_value as Dictionary).get("skill_id", 0)))
		else:
			_collect_id(ids, int(slot_value))
	for skill_value in config.get("skills", []):
		_collect_id(ids, int(skill_value))
	return ids


## 怪物技能来源：normal_skill + skills + skill_weights。
## skill_weights 当前数据是与 skills 对齐的纯权重数组，不是技能 id；
## 仅兼容 {skill_id, weight} 字典形式，数值元素按权重跳过。
func _extract_enemy_skill_ids(config: Dictionary) -> Array:
	var ids: Array = []
	_collect_id(ids, int(config.get("normal_skill", 0)))
	for skill_value in config.get("skills", []):
		_collect_id(ids, int(skill_value))
	for weight_value in config.get("skill_weights", []):
		if weight_value is Dictionary:
			_collect_id(ids, int((weight_value as Dictionary).get("skill_id", 0)))
	return ids


## 加载并缓存某个 actor 的全部技能。
func _load_actor(actor_id: int) -> Dictionary:
	if _actor_cache.has(actor_id):
		return _actor_cache[actor_id]
	var skills: Dictionary = {}
	if OS.has_feature("editor"):
		# 编辑器内永远读 json，改动立即生效（忽略 bin）
		skills = _load_actor_json(actor_id)
		if skills.is_empty():
			push_error("无法加载 actor %d 的技能配置: %s" % [actor_id, _actor_json_path(actor_id)])
	else:
		skills = _load_actor_bin(actor_id)
		if skills.is_empty():
			push_error("actor %d 的技能 bin 缺失或校验失败，回退尝试 json" % actor_id)
			skills = _load_actor_json(actor_id)
	_actor_cache[actor_id] = skills
	return skills


func _load_actor_json(actor_id: int) -> Dictionary:
	var path := _actor_json_path(actor_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("技能配置解析失败: %s (%s)" % [path, json.get_error_message()])
		return {}
	return _normalize_actor_data(json.data, path)


func _load_actor_bin(actor_id: int) -> Dictionary:
	var path := _actor_bin_path(actor_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() < 5:
		push_error("技能 bin 过短: %s" % path)
		return {}
	if file.get_buffer(4).get_string_from_ascii() != BIN_MAGIC:
		push_error("技能 bin magic 校验失败: %s" % path)
		return {}
	if file.get_8() != BIN_VERSION:
		push_error("技能 bin 版本不支持: %s" % path)
		return {}
	var data: Variant = bytes_to_var(file.get_buffer(file.get_length() - file.get_position()))
	if not data is Dictionary:
		push_error("技能 bin 数据不是字典: %s" % path)
		return {}
	# bin 存的是发布管线生成的规范化字典（int 键），此处只做节点校验兜底
	return _normalize_actor_data(data, path)


## 逐条校验并规范化一个 actor 的技能数据（id 键允许 String 或 int）。
func _normalize_actor_data(data: Dictionary, source_path: String) -> Dictionary:
	var skills: Dictionary = {}
	for id_value in data:
		var raw_value: Variant = data[id_value]
		if not raw_value is Dictionary:
			push_error("技能 %s 不是对象 (%s)" % [id_value, source_path])
			continue
		var raw: Dictionary = raw_value
		var nodes_value: Variant = raw.get("nodes", [])
		var runtime_nodes: Array = (nodes_value as Array).duplicate(true) if nodes_value is Array and not (nodes_value as Array).is_empty() else _build_compat_damage_nodes(raw)
		if runtime_nodes.is_empty():
			push_error("技能 %s 缺少可执行 nodes 或兼容伤害字段 (%s)" % [id_value, source_path])
			continue
		var cache_value: Variant = raw.get("ai_range_cache", {})
		var ai_cache: Dictionary = cache_value if cache_value is Dictionary else {}
		var skill_id := int(id_value)
		var normalized: Dictionary = raw.duplicate(true)
		normalized["id"] = skill_id
		normalized["name"] = str(raw.get("name", ""))
		normalized["description"] = str(raw.get("description", ""))
		normalized["cooldown"] = float(raw.get("cooldown", 0.0))
		normalized["cast_range"] = float(raw.get("cast_range", 0.0))
		normalized["nodes"] = runtime_nodes
		normalized["ai_range_cache"] = ai_cache.duplicate(true)
		skills[skill_id] = normalized
	return skills


## 兼容设计案 16.1：仅在现有 action nodes 缺失/为空时，将 damage_nodes 或旧顶层
## 单段伤害字段转换为 SkillExecutor 可直接执行的 action nodes。
func _build_compat_damage_nodes(raw: Dictionary) -> Array:
	var result: Array = []
	var damage_nodes_value: Variant = raw.get("damage_nodes", [])
	if damage_nodes_value is Array:
		for node_value in damage_nodes_value:
			if node_value is Dictionary:
				result.append(_to_damage_action_node(node_value, raw))
	if not result.is_empty():
		return result
	if not _has_legacy_single_damage(raw):
		return result
	var legacy_node := raw.duplicate(true)
	legacy_node.erase("nodes")
	legacy_node.erase("damage_nodes")
	legacy_node.erase("ai_range_cache")
	result.append(_to_damage_action_node(legacy_node, raw))
	return result


func _to_damage_action_node(raw_node: Dictionary, skill: Dictionary) -> Dictionary:
	var node := raw_node.duplicate(true)
	if not node.has("damage_ratio"):
		if node.has("attack_coefficient"):
			node["damage_ratio"] = float(node.get("attack_coefficient", 1.0))
		elif node.has("attackCoefficient"):
			node["damage_ratio"] = float(node.get("attackCoefficient", 1.0))
	var node_type := str(node.get("type", ""))
	if node_type not in DAMAGE_ACTION_TYPES:
		# 抽象 damage_nodes 没有动画/命中窗口信息；area_damage 可在施法时直接执行。
		node["type"] = "area_damage"
	if str(node.get("type", "")) == "area_damage" and not node.has("radius"):
		var cast_range := float(skill.get("cast_range", 0.0))
		if cast_range > 0.0:
			node["radius"] = cast_range
	return node


func _has_legacy_single_damage(raw: Dictionary) -> bool:
	for field in LEGACY_SINGLE_DAMAGE_FIELDS:
		if not raw.has(field):
			continue
		if field != "damage_channel" or str(raw.get(field, "")) in ["physical", "magic", "true"]:
			return true
	return false
