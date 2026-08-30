extends SceneTree

const DamageCalculatorScript = preload("res://scripts/combat/damage_calculator.gd")
const CombatComponentScript = preload("res://scripts/combat/combat_component.gd")
const SkillExecutorScript = preload("res://scripts/combat/skill_executor.gd")
const BuffManagerScript = preload("res://scripts/combat/buff_manager.gd")
const BuffInstanceScript = preload("res://scripts/combat/buff_instance.gd")
const ElementReactionScript = preload("res://scripts/combat/element_reaction.gd")
const BuffConfigScript = preload("res://scripts/data/buff_config.gd")


class TestCombatBridge:
	extends Node
	var manager

	func get_buff_manager():
		return manager


class TestTarget:
	extends Node
	var combat: Node
	var stats

	func get_combat_stats():
		return stats


class TestStats:
	extends RefCounted
	var attack: int = 100
	var defense: int = 100
	var magic_resist: int = 80
	var level: int = 1
	var primary_element: String = "none"
	var element_damage_bonus_sources: Array = []
	var element_resist_rating: Dictionary = {}
	var element_penetration_rating: Dictionary = {}
	var element_resist_rating_modifiers: Dictionary = {}
	var tag_vulnerability: Dictionary = {}
	var active_condition_ids: Array = []
	var element_relation_matrix: Dictionary = {}
	var armor_pen_percent: float = 0.0
	var armor_pen_flat: int = 0
	var magic_pen_percent: float = 0.0
	var magic_pen_flat: int = 0
	var status_resist: float = 0.0
	var status_intensity: float = 0.0
	var status_unit_type: String = "normal"


func _init() -> void:
	var failures: Array[String] = []
	_test_legacy_damage(failures)
	_test_element_bonus_and_caps(failures)
	_test_element_relation_and_resistance(failures)
	_test_true_damage_bypass(failures)
	_test_cooldown_split(failures)
	_test_true_damage_reaction_bypass(failures)
	_test_reaction_stack_consumption(failures)
	_test_legacy_dot_finalization(failures)
	_test_dot_snapshot_and_live_defense(failures)
	_test_status_buildup_compatibility(failures)
	_test_buff_config_status_compatibility(failures)
	_test_status_thresholds(failures)
	if failures.is_empty():
		print("COMBAT_FORMULA_COMPATIBILITY_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _base_context():
	var ctx := DamageCalculatorScript.DamageContext.new()
	ctx.attacker_attack = 100.0
	ctx.skill_ratio = 1.0
	ctx.can_crit = false
	ctx.can_dodge = false
	ctx.can_block = false
	return ctx


func _test_legacy_damage(failures: Array[String]) -> void:
	var ctx := _base_context()
	ctx.damage_tag = "slash"
	var defense := DamageCalculatorScript.DefenseContext.new()
	defense.tag_resistance = {"slash": 1.15}
	var result := DamageCalculatorScript.new().calculate_deterministic(ctx, defense, 1.0)
	_expect(int(result.get("damage", 0)) == 115, "legacy damage_tag result changed", failures)
	_expect(str(result.get("resolved_element", "")) == "none", "legacy physical damage should have no element by default", failures)


func _test_element_bonus_and_caps(failures: Array[String]) -> void:
	var ctx := _base_context()
	ctx.use_legacy_damage_tag = false
	ctx.physical_tag = "slash"
	ctx.primary_element = "fire"
	ctx.resolved_element = "fire"
	ctx.element_damage_bonus_sources = [
		{"source_id": "talent", "element_tag": "fire", "damage_scope": "all", "value": 0.20},
		{"source_id": "equipment", "element_tag": "fire", "damage_scope": "direct", "value": 0.15},
		{"source_id": "relic", "element_tag": "fire", "damage_scope": "all", "value": 0.10},
		{"source_id": "wrong_element", "element_tag": "frost", "damage_scope": "all", "value": 9.0},
	]
	var defense := DamageCalculatorScript.DefenseContext.new()
	var layer := DamageCalculatorScript.calculate_element_layer(ctx, defense)
	_expect_close(float(layer["raw_multiplier"]), 1.518, "element sources must multiply independently", failures)
	_expect(int(DamageCalculatorScript.new().calculate_deterministic(ctx, defense, 1.0).get("damage", 0)) == 152, "element multiplier not applied to final damage", failures)

	ctx.element_damage_bonus_sources = [{"source_id": "soft", "element_tag": "fire", "value": 1.75}]
	layer = DamageCalculatorScript.calculate_element_layer(ctx, defense)
	_expect_close(float(layer["effective_multiplier"]), 2.2625, "element soft cap formula", failures)
	ctx.element_damage_bonus_sources = [{"source_id": "hard", "element_tag": "fire", "value": 29.0}]
	layer = DamageCalculatorScript.calculate_element_layer(ctx, defense)
	_expect_close(float(layer["effective_multiplier"]), 10.0, "element hard cap formula", failures)


func _test_element_relation_and_resistance(failures: Array[String]) -> void:
	var ctx := _base_context()
	ctx.use_legacy_damage_tag = false
	ctx.damage_channel = "magic"
	ctx.resolved_element = "fire"
	ctx.element_relation_matrix = {"fire": {"frost": 0.80}}
	ctx.element_penetration_rating = {"fire": 0.0}
	var defense := DamageCalculatorScript.DefenseContext.new()
	defense.primary_element = "frost"
	defense.target_level = 1
	defense.element_resist_rating = {"fire": 21.1764705882}
	defense.element_resist_cap = 0.35
	var layer := DamageCalculatorScript.calculate_element_layer(ctx, defense)
	_expect_close(float(layer["resistance_reduction"]), 0.15, "element resistance conversion", failures)
	_expect_close(float(layer["relation_multiplier"]), 0.65, "relation minus resistance formula", failures)
	ctx.element_penetration_rating = {"fire": 999.0}
	layer = DamageCalculatorScript.calculate_element_layer(ctx, defense)
	_expect_close(float(layer["effective_resistance"]), 0.0, "element penetration must not create negative resistance", failures)


func _test_true_damage_bypass(failures: Array[String]) -> void:
	var ctx := _base_context()
	ctx.damage_channel = "true"
	ctx.primary_element = "fire"
	ctx.element_override = "fire"
	ctx.resolved_element = "fire"
	ctx.element_damage_bonus_sources = [{"source_id": "huge", "element_tag": "fire", "value": 9.0}]
	var defense := DamageCalculatorScript.DefenseContext.new()
	defense.primary_element = "frost"
	defense.element_resist_rating = {"fire": 9999.0}
	defense.armor = 9999
	defense.magic_resist = 9999
	var result := DamageCalculatorScript.new().calculate_deterministic(ctx, defense, 1.0)
	_expect(int(result.get("damage", 0)) == 100, "true damage must bypass defense and element layer", failures)
	_expect(str(result.get("resolved_element", "")) == "none", "true damage resolved_element must be none", failures)


func _test_cooldown_split(failures: Array[String]) -> void:
	_expect_close(CombatComponentScript.calculate_cooldown_duration(9.0, 2.0, 100.0, true), 0.5, "basic attack interval must only use attack speed", failures)
	_expect_close(CombatComponentScript.calculate_cooldown_duration(10.0, 2.0, 100.0, false), 5.0, "skill cooldown must ignore attack speed", failures)
	_expect_close(CombatComponentScript.calculate_cooldown_duration(10.0, 2.0, 100.0, false, true), 2.5, "explicit attack-speed skill cooldown", failures)


func _test_true_damage_reaction_bypass(failures: Array[String]) -> void:
	var executor = SkillExecutorScript.new(null)
	var tags: Array = executor._get_reaction_tags({"damage_channel": "true", "damage_tag": "thunder"})
	_expect(tags.is_empty(), "true damage legacy tag must not trigger reactions", failures)


func _test_reaction_stack_consumption(failures: Array[String]) -> void:
	var target := TestTarget.new()
	var bridge := TestCombatBridge.new()
	var manager = BuffManagerScript.new(target)
	bridge.manager = manager
	target.combat = bridge
	var erosion := {"id": 10021, "name": "erosion", "duration": 10.0, "max_stacks": 10, "stack_behavior": "stack", "effects": []}
	for _index in range(5):
		manager.apply_buff(erosion)
	var reaction := ElementReactionScript.try_reaction(target, ["holy"])
	_expect(bool(reaction.get("triggered", false)), "reaction must resolve owner combat buff manager", failures)
	ElementReactionScript.consume_pre_buff(target, reaction)
	var active: Array = manager.get_active_buffs()
	_expect(active.size() == 1 and int(active[0].stacks) == 2, "consume_stacks must preserve stacks above max_consume", failures)
	manager.free()
	bridge.free()
	target.free()


func _test_legacy_dot_finalization(failures: Array[String]) -> void:
	var owner := Node.new()
	var manager = BuffManagerScript.new(owner)
	var buff = BuffInstanceScript.new({"id": 1, "duration": 1.0})
	var result: Dictionary = manager._calculate_dot_damage({"damage": 12}, buff)
	_expect(int(result.get("damage", 0)) == 12 and not bool(result.get("finalized", true)), "legacy untagged DoT must use old defense path", failures)
	manager.free()
	owner.free()


func _test_dot_snapshot_and_live_defense(failures: Array[String]) -> void:
	var target := TestTarget.new()
	target.stats = TestStats.new()
	var bridge := TestCombatBridge.new()
	var manager = BuffManagerScript.new(target)
	bridge.manager = manager
	target.combat = bridge
	manager.apply_buff({
		"id": 2,
		"duration": 10.0,
		"effects": [
			{"type": "stat_modifier", "stat": "attack", "mode": "mul", "value": 0.5},
			{"type": "stat_modifier", "stat": "defense", "mode": "mul", "value": 0.5},
			{"type": "stat_modifier", "stat": "magic_resist", "mode": "mul", "value": 0.75},
			{"type": "tag_modifier", "tag": "pierce", "vuln_bonus": 0.2, "armor_pen_bonus": 0.1},
			{"type": "vulnerability_modifier", "value": 0.03},
		],
	})
	var snapshot: Dictionary = manager._build_attacker_snapshot(target.get_instance_id())
	_expect_close(float(snapshot.get("attack", 0.0)), 50.0, "DoT snapshot must include source attack modifiers", failures)
	var defense = manager._build_dot_defense_context()
	_expect(defense.armor == 50 and defense.magic_resist == 60, "DoT defense must read live target modifiers", failures)
	var executor = SkillExecutorScript.new(null)
	var direct_defense = executor._build_defense_context(target)
	_expect(direct_defense.armor == 50 and direct_defense.magic_resist == 60, "direct damage must resolve target combat buff manager", failures)
	_expect_close(float(direct_defense.tag_vulnerability.get("pierce", 0.0)), 0.2, "direct damage tag modifier bridge", failures)
	_expect_close(float(direct_defense.global_vulnerability), 0.03, "direct damage vulnerability bridge", failures)
	manager.free()
	bridge.free()
	target.free()


func _test_status_buildup_compatibility(failures: Array[String]) -> void:
	var source := TestTarget.new()
	source.stats = TestStats.new()
	source.stats.status_intensity = 0.5
	var target := TestTarget.new()
	target.stats = TestStats.new()
	target.stats.status_resist = 0.25
	target.stats.element_resist_rating = {"fire": 99999.0}
	var bridge := TestCombatBridge.new()
	var manager = BuffManagerScript.new(target)
	bridge.manager = manager
	target.combat = bridge
	var executor = SkillExecutorScript.new(source, source.stats)
	var nested_status: Dictionary = executor._read_status_payload({"status": {"type": "燃烧", "buildup": 20.0}})
	_expect(str(nested_status.get("type", "")) == "burn" and is_equal_approx(float(nested_status.get("buildup", 0.0)), 20.0), "nested status payload compatibility", failures)
	executor._apply_optional_status_buildup({"status_type": "burn", "status_buildup": 20.0}, target, false, 0.5)
	_expect_close(manager.get_status_buildup("burn"), 36.0, "status buildup formula and reaction boost", failures)
	executor._apply_optional_status_buildup({"status_type": "burn", "status_buildup": 20.0}, target, true, 0.5)
	_expect_close(manager.get_status_buildup("burn"), 36.0, "reaction extra damage must skip status buildup", failures)
	manager.free()
	bridge.free()
	target.free()
	source.free()


func _test_buff_config_status_compatibility(failures: Array[String]) -> void:
	var config = BuffConfigScript.new()
	config.load_config()
	_expect(str(config.get_buff(10002).get("status_type", "")) == "burn", "buff config must preserve burn status_type", failures)
	_expect(str(config.get_buff(10024).get("status_type", "")) == "burn", "alternate burn buff status_type", failures)
	_expect(str(config.get_buff(20017).get("status_type", "invalid")) == "", "status_type none must normalize empty", failures)


func _test_status_thresholds(failures: Array[String]) -> void:
	var owner := Node.new()
	var manager = BuffManagerScript.new(owner)
	manager.set_status_unit_type("normal")
	_expect(manager.get_status_threshold() == 100 and manager.get_status_threshold("wet") == 50, "normal status thresholds", failures)
	manager.set_status_unit_type("elite")
	_expect(manager.get_status_threshold() == 150, "elite status threshold", failures)
	manager.set_status_unit_type("boss")
	_expect(manager.get_status_threshold() == 250, "boss status threshold", failures)
	manager.free()
	owner.free()


func _expect(value: bool, message: String, failures: Array[String]) -> void:
	if not value:
		failures.append(message)


func _expect_close(actual: float, expected: float, message: String, failures: Array[String]) -> void:
	if absf(actual - expected) > 0.0001:
		failures.append("%s: got %.6f expected %.6f" % [message, actual, expected])
