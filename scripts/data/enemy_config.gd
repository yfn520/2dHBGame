class_name EnemyConfig

const CONFIG_PATH := "res://data/enemies.json"

var _enemies: Dictionary = {}
var _loaded := false


func load_config() -> void:
	if _loaded:
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法加载怪物配置: %s" % CONFIG_PATH)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("怪物配置解析失败")
		return
	var data: Dictionary = json.data
	for id_str in data:
		var enemy_id := int(id_str)
		var raw: Dictionary = data[id_str]
		_enemies[enemy_id] = _normalize_enemy(enemy_id, raw)
	_loaded = true


static func _normalize_enemy(enemy_id: int, raw: Dictionary) -> Dictionary:
	var normalized := {
		"id": enemy_id,
		"name": "",
		"asset": "",
		"character_config": "",
		"actor_scale": 1.0,
		"level": 1,
		"max_hp": 50,
		"attack": 1,
		"defense": 0,
		"move_speed": 80.0,
		"attack_range": 40.0,
		"detect_range": 200.0,
		"patrol_range": 80.0,
		"normal_skill": 0,
		"skills": [],
		"skill_weights": [],
		"drop_items": [],
		"traits": [],
		"exp": 0,
		"primary_element": "none",
		"element_damage_bonus_sources": [],
		"element_resist_rating": {},
		"element_penetration_rating": {},
		"tag_vulnerability": {},
		"element_resist_rating_modifiers": {},
		"phase_rules": [],
		"active_phase_rule_id": "",
		"active_condition_ids": [],
		"element_relation_matrix": {},
	}
	normalized.merge(raw, true)
	var compat_fields := {
		"primary_element": ["primary_element", "primaryElement"],
		"element_damage_bonus_sources": ["element_damage_bonus_sources", "elementDamageBonusSources"],
		"element_resist_rating": ["element_resist_rating", "elementResistRating"],
		"element_penetration_rating": ["element_penetration_rating", "elementPenetrationRating"],
		"tag_vulnerability": ["tag_vulnerability", "tagVulnerability"],
		"element_resist_rating_modifiers": ["element_resist_rating_modifiers", "elementResistRatingModifiers"],
		"phase_rules": ["phase_rules", "phaseRules"],
		"active_phase_rule_id": ["active_phase_rule_id", "activePhaseRuleId"],
		"active_condition_ids": ["active_condition_ids", "activeConditionIds"],
		"element_relation_matrix": ["element_relation_matrix", "elementRelationMatrix"],
	}
	for canonical_field in compat_fields:
		for source_field in compat_fields[canonical_field]:
			if raw.has(source_field):
				normalized[canonical_field] = raw[source_field]
				break
	normalized["id"] = enemy_id
	normalized["name"] = str(raw.get("name", ""))
	normalized["asset"] = str(raw.get("asset", ""))
	normalized["character_config"] = str(raw.get("character_config", ""))
	normalized["actor_scale"] = float(raw.get("actor_scale", 1.0))
	normalized["level"] = maxi(1, int(raw.get("level", raw.get("unit_level", 1))))
	normalized["max_hp"] = int(raw.get("max_hp", 50))
	normalized["attack"] = int(raw.get("attack", 1))
	normalized["defense"] = int(raw.get("defense", raw.get("armor", 0)))
	normalized["move_speed"] = float(raw.get("move_speed", 80.0))
	normalized["attack_range"] = float(raw.get("attack_range", 40.0))
	normalized["detect_range"] = float(raw.get("detect_range", 200.0))
	normalized["patrol_range"] = float(raw.get("patrol_range", 80.0))
	normalized["normal_skill"] = int(raw.get("normal_skill", 0))
	normalized["exp"] = int(raw.get("exp", 0))
	return normalized


func get_enemy(enemy_id: int) -> Dictionary:
	if not _loaded:
		load_config()
	return _enemies.get(enemy_id, {})


func get_all_enemies() -> Dictionary:
	if not _loaded:
		load_config()
	return _enemies
