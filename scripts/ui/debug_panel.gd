class_name DebugPanel
extends Control
## F3 调试面板，位于 DebugLayer。
## 显示 DebugDraw 开关状态、玩家/队友/怪物运行时信息。

var _party_manager: PartyManager
var _enemy_spawner: Node
var _label: Label
var _panel: PanelContainer


func _ready() -> void:
	_build_layout()


func setup(party_manager: PartyManager, enemy_spawner: Node) -> void:
	_party_manager = party_manager
	_enemy_spawner = enemy_spawner


func toggle_visible() -> void:
	if _panel != null:
		_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if _panel != null and _panel.visible:
		_update_content()


func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	_panel = PanelContainer.new()
	_panel.name = "DebugContent"
	_panel.visible = false
	_panel.position = Vector2(10, 10)
	_panel.custom_minimum_size = Vector2(350, 400)
	_panel.theme_type_variation = &"Tooltip"
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	_label = Label.new()
	_label.theme_type_variation = &"HUDValue"
	_label.add_theme_font_size_override("font_size", 13)
	margin.add_child(_label)


func _update_content() -> void:
	if _party_manager == null:
		return
	var player := _party_manager.get_active_character()
	if player == null:
		return
	var lines: PackedStringArray = []
	var combat = player.get_node_or_null("CombatComponent")
	var stats = GameRegistry.character_stats

	lines.append("=== Debug (F3/F4/F5/F6) ===")
	lines.append("碰撞体:%s  受伤区:%s  攻击区:%s" % [
		"ON" if DebugDraw.show_collision else "off",
		"ON" if DebugDraw.show_hurtbox else "off",
		"ON" if DebugDraw.show_hitbox else "off",
	])

	lines.append("=== 玩家 ===")
	if stats != null:
		lines.append("HP: %d / %d" % [stats.hp, stats.max_hp])
		lines.append("ATK: %d  DEF: %d  SPD: %d" % [stats.attack, stats.defense, stats.move_speed])
	if combat != null:
		lines.append("状态: %s" % _state_name(combat.combat_state))
		var cooldowns: Dictionary = combat.get_cooldowns_dict() if combat.has_method("get_cooldowns_dict") else {}
		var cd_parts: PackedStringArray = []
		for sid in cooldowns:
			var cd: float = cooldowns[sid]
			var skill: Dictionary = GameRegistry.skill_config.get_skill(int(sid))
			var name: String = str(skill.get("name", sid)) if not skill.is_empty() else str(sid)
			cd_parts.append("%s:%.1fs" % [name, cd] if cd > 0 else "%s:OK" % name)
		lines.append("CD: %s" % " | ".join(cd_parts))

	lines.append("")
	lines.append("=== Party runtime ===")
	for member in _party_manager.get_party_members():
		var member_combat := member.get_node_or_null("CombatComponent")
		var member_id: int = member.get_party_character_id() if member.has_method("get_party_character_id") else 0
		var member_name: String = GameRegistry.character_config.get_name(member_id) if GameRegistry.character_config != null else str(member_id)
		var runtime: Variant = member_combat.get_debug_state() if member_combat != null and member_combat.has_method("get_debug_state") else "?"
		var anim := String(member.get_node("CharacterActionSet/AnimatedSprite2D").animation)
		var ally_runtime: Variant = member.get_ally_debug_state() if member.has_method("get_ally_debug_state") else ""
		lines.append("%s anim:%s %s %s" % [member_name, anim, runtime, ally_runtime])

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
				var e_combat: Variant = enemy.get_node_or_null("CombatComponent")
				var e_runtime: Variant = e_combat.get_debug_state() if e_combat != null and e_combat.has_method("get_debug_state") else "?"
				var target_dist: float = enemy.get_target_distance_x() if enemy.has_method("get_target_distance_x") else INF
				lines.append("[%s] HP:%s AI:%s XDist:%d TargetDist:%.1f %s" % [e_name, hp_str, ai_name, int(dist_x), target_dist, e_runtime])

	_label.text = "\n".join(lines)


func _state_name(state) -> String:
	match state:
		0: return "IDLE"
		1: return "ATTACKING"
		2: return "SKILL"
		3: return "HIT"
		4: return "DEAD"
		_: return str(state)
