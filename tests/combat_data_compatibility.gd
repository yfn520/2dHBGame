extends SceneTree

const CharacterConfigDataScript = preload("res://scripts/data/character_config_data.gd")
const EnemyConfigScript = preload("res://scripts/data/enemy_config.gd")
const EnemyStatsScript = preload("res://scripts/combat/enemy_stats.gd")
const ItemConfigScript = preload("res://scripts/data/item_config.gd")
const SkillConfigScript = preload("res://scripts/data/skill_config.gd")


class TestStats:
	extends BaseCombatStats
	var base_data: Dictionary = {}
	var equipment_data: Array = []

	func _get_base_stats_dict() -> Dictionary:
		return base_data

	func _get_equipped_items() -> Array:
		return equipment_data


func _init() -> void:
	var failures: Array[String] = []
	_test_base_stats(failures)
	_test_config_passthrough(failures)
	_test_skill_passthrough(failures)
	_test_skill_damage_node_fallbacks(failures)
	_test_enemy_resistance(failures)
	if failures.is_empty():
		print("COMBAT_DATA_COMPATIBILITY_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_base_stats(failures: Array[String]) -> void:
	var stats := TestStats.new()
	stats.base_data = {
		"max_hp": 100,
		"armor": 12,
		"statusPower": 0.2,
		"primaryElement": "thunder",
		"elementDamageBonusSources": [{"sourceId": "unit_base", "elementTag": "thunder", "damageScope": "all", "value": 0.2}],
		"elementResistRating": {"fire": 10, "thunder": 4},
		"elementPenetrationRating": {"lightning": 3},
		"tagVulnerability": {"slash": 0.1},
		"elementResistRatingModifiers": {"fire": 1},
		"phaseRules": [{"phase_id": "rage", "active": true, "elementResistRatingModifiers": {"thunder": 7}}],
		"activePhaseRuleId": "rage",
		"activeConditionIds": ["rage"],
		"elementRelationMatrix": {"thunder": {"fire": 1.2}},
	}
	stats.equipment_data = [{
		"compiled_stats": {"armor": 3, "statusPower": 0.1, "element_penetration_rating": {"thunder": 2}},
		"element_damage_bonus_sources": [{"source_id": "equipment:1:fire", "element_tag": "fire", "damage_scope": "direct", "value": 0.15}],
		"element_resist_rating": {"fire": 5},
		"tag_vulnerability": {"slash": 0.05},
	}]
	stats.recalculate(false)
	_expect(stats.defense == 15, "armor/compiled_stats compatibility", failures)
	_expect(is_equal_approx(stats.status_intensity, 0.3), "legacy statusPower compatibility", failures)
	_expect(stats.primary_element == "lightning", "legacy thunder normalization", failures)
	_expect(stats.element_damage_bonus_sources.size() == 2, "unit + equipment element sources", failures)
	_expect(stats.element_damage_bonus_sources[0].get("element_tag") == "lightning", "element source normalization", failures)
	_expect(is_equal_approx(float(stats.element_resist_rating.get("fire", 0.0)), 15.0), "element resistance aggregation", failures)
	_expect(is_equal_approx(float(stats.element_penetration_rating.get("lightning", 0.0)), 5.0), "element penetration aggregation", failures)
	_expect(is_equal_approx(float(stats.tag_vulnerability.get("slash", 0.0)), 0.15), "tag vulnerability aggregation", failures)
	_expect(stats.phase_rules[0].get("id") == "rage", "phase id compatibility", failures)
	_expect(is_equal_approx(float(stats.phase_rules[0].get("element_resist_rating_modifiers", {}).get("lightning", 0.0)), 7.0), "phase element map normalization", failures)
	_expect(is_equal_approx(float(stats.element_relation_matrix.get("lightning", {}).get("fire", 0.0)), 1.2), "element relation compatibility", failures)
	stats.recalculate(false)
	_expect(stats.element_damage_bonus_sources.size() == 2, "recalculate must not duplicate element sources", failures)
	_expect(is_equal_approx(float(stats.element_resist_rating.get("fire", 0.0)), 15.0), "recalculate must not duplicate element ratings", failures)


func _test_config_passthrough(failures: Array[String]) -> void:
	var characters = CharacterConfigDataScript.new()
	characters._characters[7001] = {
		"max_level": 10,
		"base_stats": {"armor": 20, "primaryElement": "fire", "elementResistRating": {"fire": 7}},
		"growth": {"armor": 2},
	}
	var character_stats: Dictionary = characters.get_stats_at_level(7001, 3)
	_expect(character_stats.get("defense") == 24, "character armor growth compatibility", failures)
	_expect(character_stats.get("primary_element") == "fire", "character primary element passthrough", failures)
	_expect(character_stats.get("element_resist_rating", {}).get("fire") == 7, "character element map passthrough", failures)

	var enemy: Dictionary = EnemyConfigScript._normalize_enemy(9001, {
		"name": "future enemy",
		"unit_level": 12,
		"armor": 9,
		"primaryElement": "holy",
		"elementResistRating": {"holy": 11},
		"future_enemy_field": {"keep": true},
	})
	_expect(enemy.get("defense") == 9, "enemy armor compatibility", failures)
	_expect(enemy.get("level") == 12, "enemy unit_level compatibility", failures)
	_expect(enemy.get("primary_element") == "holy", "enemy canonical element field", failures)
	_expect(enemy.get("element_resist_rating", {}).get("holy") == 11, "enemy canonical element map", failures)
	_expect(enemy.get("future_enemy_field", {}).get("keep") == true, "enemy unknown field passthrough", failures)

	var item: Dictionary = ItemConfigScript._normalize_item(1001, {
		"name": "structured item",
		"type": "weapon",
		"equipment_schema_version": 2,
		"compiled_stats": {"armor": 6},
		"affixes": [{"affix_id": "fire_1"}],
		"elementDamageBonusSources": [{"sourceId": "equipment:1001:fire_1", "elementTag": "fire", "value": 0.2}],
		"elementResistRating": {"fire": 8},
		"future_item_field": "keep",
	})
	_expect(item.get("stats", {}).get("armor") == 6, "compiled_stats fallback", failures)
	_expect(item.get("affixes", []).size() == 1, "structured affix passthrough", failures)
	_expect(item.get("element_damage_bonus_sources", []).size() == 1, "compiled equipment element source passthrough", failures)
	_expect(item.get("element_resist_rating", {}).get("fire") == 8, "compiled equipment element rating passthrough", failures)
	_expect(item.get("future_item_field") == "keep", "item unknown field passthrough", failures)


func _test_skill_passthrough(failures: Array[String]) -> void:
	var config = SkillConfigScript.new()
	var raw_node := {
		"type": "melee_damage",
		"damage_tag": "thunder",
		"physical_tag": "blunt",
		"element_override": "lightning",
		"hit_count": 3,
		"damage_scope": "direct",
		"affected_by_attack_speed": true,
		"status_type": "shock",
		"status_buildup": 50,
		"status": {"type": "shock", "buildup": 50},
		"future_node_field": "keep",
	}
	var normalized: Dictionary = config._normalize_actor_data({"42": {
		"name": "compat skill",
		"cooldown": 3,
		"damage_tag": "thunder",
		"affected_by_attack_speed": true,
		"future_skill_field": "keep",
		"nodes": [raw_node],
	}}, "test")
	var skill: Dictionary = normalized.get(42, {})
	var node: Dictionary = skill.get("nodes", [])[0]
	_expect(skill.get("damage_tag") == "thunder", "legacy top-level damage_tag passthrough", failures)
	_expect(skill.get("affected_by_attack_speed") == true, "skill attack-speed flag passthrough", failures)
	_expect(skill.get("future_skill_field") == "keep", "skill unknown field passthrough", failures)
	for field in ["damage_tag", "physical_tag", "element_override", "hit_count", "damage_scope", "affected_by_attack_speed", "status_type", "status_buildup", "status", "future_node_field"]:
		_expect(node.has(field), "skill node field passthrough: %s" % field, failures)
	raw_node["physical_tag"] = "slash"
	_expect(node.get("physical_tag") == "blunt", "skill nodes must be deep duplicated", failures)


func _test_skill_damage_node_fallbacks(failures: Array[String]) -> void:
	var config = SkillConfigScript.new()
	var damage_nodes := [{
		"node_id": "mixed_1",
		"attack_coefficient": 1.25,
		"flat_damage": 7,
		"damage_channel": "physical",
		"damage_tag": "pierce",
		"physical_tag": "pierce",
		"element_override": "poison",
		"hit_count": 2,
		"status": {"type": "poison", "buildup": 30},
		"future_damage_field": "keep",
	}, {
		"type": "fullscreen_damage",
		"damage_ratio": 0.5,
		"damage_channel": "magic",
		"physical_tag": "none",
		"element_override": "frost",
	}]
	var normalized: Dictionary = config._normalize_actor_data({
		"51": {
			"name": "damage_nodes fallback",
			"cooldown": 4,
			"cast_range": 135,
			"nodes": [],
			"damage_nodes": damage_nodes,
		},
		"52": {
			"name": "legacy single fallback",
			"cooldown": 2,
			"cast_range": 90,
			"damage_channel": "magic",
			"damage_tag": "fire",
			"attack_coefficient": 1.6,
			"flat_damage": 9,
			"physical_tag": "none",
			"element_override": "fire",
			"hit_count": 3,
			"status": {"type": "burn", "buildup": 40},
			"future_legacy_field": "keep",
		},
		"53": {
			"name": "existing nodes win",
			"nodes": [{"type": "area_damage", "damage_ratio": 2.0}],
			"damage_nodes": [{"attack_coefficient": 99.0}],
		},
	}, "test")
	var multi_nodes: Array = normalized.get(51, {}).get("nodes", [])
	_expect(multi_nodes.size() == 2, "all damage_nodes must enter runtime nodes", failures)
	if multi_nodes.size() == 2:
		var first: Dictionary = multi_nodes[0]
		var second: Dictionary = multi_nodes[1]
		_expect(first.get("type") == "area_damage", "untyped damage node runtime type", failures)
		_expect(is_equal_approx(float(first.get("damage_ratio", 0.0)), 1.25), "attack_coefficient to damage_ratio", failures)
		_expect(first.get("radius") == 135.0, "damage node cast_range to area radius", failures)
		for field in ["damage_tag", "physical_tag", "element_override", "hit_count", "status", "future_damage_field"]:
			_expect(first.has(field), "damage_nodes field passthrough: %s" % field, failures)
		_expect(second.get("type") == "fullscreen_damage", "explicit damage action type preserved", failures)
	var legacy_nodes: Array = normalized.get(52, {}).get("nodes", [])
	_expect(legacy_nodes.size() == 1, "legacy single damage must generate one runtime node", failures)
	if legacy_nodes.size() == 1:
		var legacy: Dictionary = legacy_nodes[0]
		_expect(legacy.get("type") == "area_damage", "legacy single runtime type", failures)
		_expect(is_equal_approx(float(legacy.get("damage_ratio", 0.0)), 1.6), "legacy attack_coefficient mapping", failures)
		_expect(legacy.get("radius") == 90.0, "legacy cast_range to area radius", failures)
		for field in ["damage_tag", "physical_tag", "element_override", "hit_count", "status", "future_legacy_field"]:
			_expect(legacy.has(field), "legacy single field passthrough: %s" % field, failures)
	var existing_nodes: Array = normalized.get(53, {}).get("nodes", [])
	_expect(existing_nodes.size() == 1 and is_equal_approx(float(existing_nodes[0].get("damage_ratio", 0.0)), 2.0), "non-empty nodes must remain authoritative", failures)
	damage_nodes[0]["physical_tag"] = "slash"
	if multi_nodes.size() == 2:
		_expect(multi_nodes[0].get("physical_tag") == "pierce", "generated runtime nodes must be deep duplicated", failures)


func _test_enemy_resistance(failures: Array[String]) -> void:
	var boss = EnemyStatsScript.new({
		"is_boss": true,
		"level": 18,
		"element_resist_rating": {"fire": 10},
		"element_resist_rating_modifiers": {"fire": 5},
		"phase_rules": [{"id": "rage", "element_resist_rating_modifiers": {"fire": 7}}],
		"active_phase_rule_id": "rage",
	})
	_expect(is_equal_approx(float(boss.effective_element_resist_rating.get("fire", 0.0)), 22.0), "boss effective element resistance", failures)
	_expect(boss.active_phase_rule.get("id") == "rage", "phase id selects rule without active flag", failures)
	_expect(boss.level == 18, "enemy stats level passthrough", failures)
	_expect(boss.status_unit_type == "boss", "boss status threshold type", failures)
	_expect(is_equal_approx(boss.element_resist_cap, 0.50), "boss active phase resistance cap", failures)
	var plain_boss = EnemyStatsScript.new({"is_boss": true})
	_expect(is_equal_approx(plain_boss.element_resist_cap, 0.45), "boss resistance cap", failures)
	var elite = EnemyStatsScript.new({"is_elite": true})
	_expect(is_equal_approx(elite.element_resist_cap, 0.40), "explicit elite resistance cap", failures)
	_expect(elite.status_unit_type == "elite", "elite status threshold type", failures)
	var explicit_elite = EnemyStatsScript.new({"status_unit_type": "elite"})
	_expect(explicit_elite.status_unit_type == "elite", "explicit status unit type passthrough", failures)
	var unmarked = EnemyStatsScript.new({"name": "精英但无可靠标记"})
	_expect(is_equal_approx(unmarked.element_resist_cap, 0.35), "unmarked enemy defaults to normal cap", failures)
	_expect(unmarked.status_unit_type == "normal", "unmarked enemy status threshold type", failures)
	_expect(unmarked.level == 1, "enemy stats default level", failures)


func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
