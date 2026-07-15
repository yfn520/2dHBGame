class_name AIRangeCompiler

## AI 距离编译器（节点驱动）
## 由技能编辑器与角色/怪物导入工具共用。
##
## 输入：技能 ID + 所属角色/怪物资源
## 输出：ai_range_cache，写入 skills.json 只读字段
##
## 节点 AI 距离来源：
##   melee_damage      → 前置 wait_hit_window 对应攻击框 + 身体框 + actor_scale（不可手填）
##   area_damage       → origin + radius/矩形范围 自动计算
##   spawn_projectile  → 节点 ai_min_range / ai_max_range（设计参数，不影响弹道实际飞行）
##   fullscreen_damage → 检测范围内均可起手
##   apply_target_buff → 跟随前置伤害结果，不单独决定起手距离
##   apply_self_buff / heal / play_effect → 不计入攻击距离
##
## 第一版约定：一个技能 ID 只绑定一个角色或怪物。

const POLICY_ANY_DAMAGE_NODE := "any_damage_node"
const SAFETY_MARGIN := 2.0  # 攻击框外沿再留一点余量，避免边界抖动

## 计算并返回某个技能的 ai_range_cache。
## owner_asset_path 是角色/怪物资源根目录（含 character_config.json 和 combat_actions.json）。
static func compile(skill_id: int, owner_asset_path: String) -> Dictionary:
	if owner_asset_path.is_empty():
		return _empty_cache()
	var character_config := _load_json(owner_asset_path.path_join("character_config.json"))
	if character_config.is_empty():
		push_warning("[AIRangeCompiler] 缺少 character_config.json: %s" % owner_asset_path)
		return _empty_cache()
	var combat_actions := _load_json(owner_asset_path.path_join("combat_actions.json"))
	if combat_actions.is_empty():
		push_warning("[AIRangeCompiler] 缺少 combat_actions.json: %s" % owner_asset_path)
		return _empty_cache()
	var skill: Dictionary = _load_skill(skill_id)
	if skill.is_empty():
		push_warning("[AIRangeCompiler] 技能不存在: %s" % skill_id)
		return _empty_cache()

	var actor_scale := maxf(0.01, float(_lookup_actor_scale(skill_id, owner_asset_path, character_config)))
	var body_half_width := _body_half_width(character_config, actor_scale)
	var actions: Dictionary = combat_actions.get("actions", {})

	var entries: Array = []
	var current_action := ""
	var source_hash_input := ""

	var nodes: Array = skill.get("nodes", [])
	for index in range(nodes.size()):
		var node_value: Variant = nodes[index]
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		var node_type := String(node.get("type", ""))
		source_hash_input += "%d:%s|" % [index, node_type]

		match node_type:
			"play_animation":
				current_action = String(node.get("action", ""))
				source_hash_input += "action=%s|" % current_action
			"wait_hit_window":
				# 记录当前等待的有效区间索引，供后续 melee_damage/area_damage 取用
				pass
			"melee_damage":
				var entry := _compile_melee(node, current_action, actions, body_half_width, actor_scale, index)
				if not entry.is_empty():
					entries.append(entry)
					source_hash_input += _entry_hash(entry)
			"area_damage":
				var entry := _compile_area(node, current_action, actions, body_half_width, actor_scale, index)
				if not entry.is_empty():
					entries.append(entry)
					source_hash_input += _entry_hash(entry)
			"spawn_projectile":
				var entry := _compile_projectile(node, index)
				if not entry.is_empty():
					entries.append(entry)
					source_hash_input += _entry_hash(entry)
			"fullscreen_damage":
				# 检测范围内均可起手；用一个大区间标记
				entries.append({
					"node_index": index,
					"source": "fullscreen",
					"kind": "fullscreen",
					"min_edge_distance": 0.0,
					"max_edge_distance": 99999.0,
				})
				source_hash_input += "fullscreen|"
			"apply_target_buff", "apply_self_buff", "heal", "play_effect", "move_x":
				# 不计入攻击距离
				pass
			"wait_action_event", "wait_animation_end", "wait_time", "end_skill":
				pass
			_:
				pass

	# source_hash 包含动作框、身体框、actor_scale 和节点内容
	source_hash_input += "actions=%s|" % _actions_hash(actions)
	source_hash_input += "body=%s|" % _body_hash(character_config)
	source_hash_input += "scale=%.4f" % actor_scale

	return {
		"policy": POLICY_ANY_DAMAGE_NODE,
		"source_hash": source_hash_input.sha256_text().substr(0, 16),
		"entries": entries,
	}


## 判断缓存是否需要重建。
static func is_cache_stale(skill_id: int, owner_asset_path: String, cached: Dictionary) -> bool:
	if cached.is_empty():
		return true
	var fresh := compile(skill_id, owner_asset_path)
	return String(fresh.get("source_hash", "")) != String(cached.get("source_hash", ""))


## 从 ai_range_cache 中找出当前目标边缘距离下可用的节点索引。
static func get_castable_entries(cache: Dictionary, edge_distance: float) -> Array:
	var result: Array = []
	var entries: Array = cache.get("entries", [])
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var min_d := float(entry.get("min_edge_distance", 0.0))
		var max_d := float(entry.get("max_edge_distance", 0.0))
		if edge_distance >= min_d and edge_distance <= max_d:
			result.append(entry)
	return result


## 返回缓存中所有节点的最大起手距离（用于追击目标）。
static func get_max_engage_distance(cache: Dictionary) -> float:
	var best := 0.0
	var entries: Array = cache.get("entries", [])
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var max_d := float(entry.get("max_edge_distance", 0.0))
		if max_d > best and max_d < 99990.0:
			best = max_d
	return best


## 返回缓存中所有设置了最小起手距离的节点中最小的 max_edge_distance（用于后撤判断）。
static func get_min_retreat_distance(cache: Dictionary) -> float:
	var best := INF
	var entries: Array = cache.get("entries", [])
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var min_d := float(entry.get("min_edge_distance", 0.0))
		if min_d > 0.0:
			var max_d := float(entry.get("max_edge_distance", 0.0))
			if max_d < best:
				best = max_d
	return best


# ---- 内部 ----

static func _empty_cache() -> Dictionary:
	return {"policy": POLICY_ANY_DAMAGE_NODE, "source_hash": "", "entries": []}


static func _compile_melee(node: Dictionary, current_action: String, actions: Dictionary, body_half_width: float, actor_scale: float, node_index: int) -> Dictionary:
	var window := _resolve_hit_window(node, current_action, actions)
	if window.is_empty():
		push_warning("[AIRangeCompiler] melee_damage 节点找不到有效攻击框 (action=%s, node=%d)" % [current_action, node_index])
		return {}
	var forward := absf(float(window.get("forward", 0.0)))
	var width := maxf(1.0, float(window.get("width", 1.0)))
	var outer_edge := (forward + width * 0.5) * actor_scale
	var max_edge := maxf(0.0, outer_edge - body_half_width - SAFETY_MARGIN)
	return {
		"node_index": node_index,
		"source": "hit_window",
		"kind": "melee",
		"min_edge_distance": 0.0,
		"max_edge_distance": max_edge,
		"detail": "forward=%.1f width=%.1f scale=%.2f body_half=%.1f" % [forward, width, actor_scale, body_half_width],
	}


static func _compile_area(node: Dictionary, current_action: String, actions: Dictionary, body_half_width: float, actor_scale: float, node_index: int) -> Dictionary:
	var origin := String(node.get("origin", "hit_window"))
	var radius := maxf(0.0, float(node.get("radius", 80.0)))
	var width := maxf(1.0, float(node.get("width", radius * 2.0)))
	var height := maxf(1.0, float(node.get("height", radius * 2.0)))
	# origin = caster：从施法者中心扩展；max_edge = radius - body_half_width
	# origin = hit_window：从攻击框外沿再扩展 radius
	var origin_offset := 0.0
	if origin == "hit_window":
		var window := _resolve_hit_window(node, current_action, actions)
		if window.is_empty():
			push_warning("[AIRangeCompiler] area_damage origin=hit_window 但找不到攻击框 (action=%s, node=%d)" % [current_action, node_index])
			return {}
		origin_offset = (absf(float(window.get("forward", 0.0))) + maxf(1.0, float(window.get("width", 1.0))) * 0.5) * actor_scale
	var shape := String(node.get("shape", "circle"))
	var reach := radius if shape == "circle" else maxf(width, height) * 0.5
	var max_edge := maxf(0.0, origin_offset + reach * actor_scale - body_half_width - SAFETY_MARGIN)
	return {
		"node_index": node_index,
		"source": "area",
		"kind": "area",
		"min_edge_distance": 0.0,
		"max_edge_distance": max_edge,
		"detail": "origin=%s radius=%.1f scale=%.2f" % [origin, reach, actor_scale],
	}


static func _compile_projectile(node: Dictionary, node_index: int) -> Dictionary:
	# 弹道节点：使用设计参数 ai_min_range / ai_max_range
	# 兼容旧字段 min_range（迁移期）
	var min_d := maxf(0.0, float(node.get("ai_min_range", node.get("min_range", 0.0))))
	var max_d := float(node.get("ai_max_range", 0.0))
	if max_d <= 0.0:
		push_warning("[AIRangeCompiler] spawn_projectile 节点缺少 ai_max_range (node=%d)" % node_index)
		return {}
	return {
		"node_index": node_index,
		"source": "projectile",
		"kind": "projectile",
		"min_edge_distance": min_d,
		"max_edge_distance": max_d,
		"detail": "ai_min=%.0f ai_max=%.0f" % [min_d, max_d],
	}


static func _resolve_hit_window(node: Dictionary, current_action: String, actions: Dictionary) -> Dictionary:
	if current_action.is_empty():
		return {}
	var action: Dictionary = actions.get(current_action, {})
	if action.is_empty():
		return {}
	var windows: Array = action.get("hit_windows", [])
	if windows.is_empty():
		return {}
	var index := int(node.get("hit_window_index", 0))
	if index < 0 or index >= windows.size():
		index = 0
	var window_value: Variant = windows[index]
	if window_value is Dictionary:
		return window_value
	return {}


static func _body_half_width(character_config: Dictionary, actor_scale: float) -> float:
	var body_size: Dictionary = character_config.get("body_size", {})
	var width := float(body_size.get("x", character_config.get("body_box", {}).get("width", 24.0)))
	return maxf(1.0, width * 0.5) * actor_scale


## 查找技能所属角色/怪物的 actor_scale。
## 优先用外部表（characters.json / enemies.json）的 actor_scale，
## 其次用 character_config 内的字段（兼容老数据）。
static func _lookup_actor_scale(skill_id: int, owner_asset_path: String, character_config: Dictionary) -> float:
	# 先尝试在 characters.json / enemies.json 中匹配 asset 路径
	var registry_paths := ["res://data/characters.json", "res://data/enemies.json"]
	for table_path in registry_paths:
		var table := _load_json(table_path)
		for key in table:
			var row_value: Variant = table[key]
			if not row_value is Dictionary:
				continue
			var row: Dictionary = row_value
			var asset := String(row.get("asset", ""))
			if asset == owner_asset_path:
				if row.has("actor_scale"):
					return float(row.get("actor_scale", 1.0))
	# character_config 里没有 actor_scale（这是外部表字段），默认 1.0
	return 1.0


static func _load_skill(skill_id: int) -> Dictionary:
	var config_path := "res://data/skills.json"
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	var key := str(skill_id)
	if not data.has(key):
		return {}
	var raw: Dictionary = data[key]
	return {
		"id": skill_id,
		"nodes": raw.get("nodes", []),
	}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func _actions_hash(actions: Dictionary) -> String:
	# 只取与技能相关的 action 的 hit_windows 关键字段
	# 简化：用所有 actions 的 hit_windows 的 forward/width/y
	var parts := ""
	for action_name in actions:
		var action: Dictionary = actions.get(action_name, {})
		var windows: Array = action.get("hit_windows", [])
		if windows.is_empty():
			continue
		parts += action_name + ":"
		for w_value in windows:
			if not w_value is Dictionary:
				continue
			var w: Dictionary = w_value
			parts += "%.1f,%.1f,%.1f,%.1f;" % [float(w.get("forward", 0.0)), float(w.get("width", 0.0)), float(w.get("y", 0.0)), float(w.get("authored_x", 0.0))]
		parts += "|"
	return parts


static func _body_hash(character_config: Dictionary) -> String:
	var body_size: Dictionary = character_config.get("body_size", {})
	return "%.1f,%.1f" % [float(body_size.get("x", 0.0)), float(body_size.get("y", 0.0))]


static func _entry_hash(entry: Dictionary) -> String:
	return "%s:%s:%.1f-%.1f|" % [String(entry.get("kind", "")), String(entry.get("source", "")), float(entry.get("min_edge_distance", 0.0)), float(entry.get("max_edge_distance", 0.0))]
