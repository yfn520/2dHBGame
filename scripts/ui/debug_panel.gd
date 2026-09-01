class_name DebugPanel
extends Control
## F7 调试面板，位于 DebugLayer。
## 显示 DebugDraw 开关状态、玩家/队友/怪物运行时信息。

var _party_manager: PartyManager
var _enemy_spawner: Node
var _quest_service: QuestService
var _label: Label
var _panel: PanelContainer
var _task_debug_list: VBoxContainer
var _jump_select: OptionButton
var _jump_quest_ids: Array[int] = []


func _ready() -> void:
	_build_layout()


func setup(party_manager: PartyManager, enemy_spawner: Node) -> void:
	_party_manager = party_manager
	_enemy_spawner = enemy_spawner
	_quest_service = GameRegistry.quest_service
	if _quest_service != null and not _quest_service.quest_updated.is_connected(_on_quest_updated):
		_quest_service.quest_updated.connect(_on_quest_updated)
	_populate_jump_options()
	_refresh_task_debug()


## 跳转下拉：全部主线任务（按 ID 升序 = 主线顺序）
func _populate_jump_options() -> void:
	if _jump_select == null or _quest_service == null or _quest_service.config == null:
		return
	_jump_select.clear()
	_jump_quest_ids.clear()
	var story_ids: Array[int] = []
	for id_value in _quest_service.config.get_all_quests():
		var quest: Dictionary = _quest_service.config.get_quest(int(id_value))
		if str(quest.get("quest_kind", "")) == "story_task_script":
			story_ids.append(int(id_value))
	story_ids.sort()
	for quest_id in story_ids:
		var quest: Dictionary = _quest_service.config.get_quest(quest_id)
		_jump_select.add_item("%d  %s" % [quest_id, str(quest.get("title", "任务"))])
		_jump_quest_ids.append(quest_id)


func _on_jump_pressed() -> void:
	if _quest_service == null or _jump_quest_ids.is_empty():
		return
	var selected := _jump_select.selected
	if selected < 0 or selected >= _jump_quest_ids.size():
		return
	_quest_service.debug_jump_to_quest(_jump_quest_ids[selected])
	_refresh_task_debug()


func toggle_visible() -> void:
	# 根节点创建时 visible=false，必须连根一起切；只翻内部 _panel 永远不会显示。
	visible = not visible
	if _panel != null:
		_panel.visible = visible


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
	_panel.custom_minimum_size = Vector2(520, 680)
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
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)
	content.add_child(_label)

	var separator := HSeparator.new()
	content.add_child(separator)
	# 任务跳转：跳到任意主线任务（前置强制完成 + 传送目标关卡）
	var jump_title := Label.new()
	jump_title.text = "=== 任务跳转（测试） ==="
	jump_title.add_theme_font_size_override("font_size", 15)
	content.add_child(jump_title)
	var jump_row := HBoxContainer.new()
	jump_row.add_theme_constant_override("separation", 6)
	_jump_select = OptionButton.new()
	_jump_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jump_row.add_child(_jump_select)
	var jump_button := Button.new()
	jump_button.text = "跳转"
	jump_button.custom_minimum_size.x = 64
	jump_button.pressed.connect(_on_jump_pressed)
	jump_row.add_child(jump_button)
	content.add_child(jump_row)
	var task_title := Label.new()
	task_title.text = "=== 任务卡点 ==="
	task_title.add_theme_font_size_override("font_size", 15)
	content.add_child(task_title)
	var task_hint := Label.new()
	task_hint.text = "仅开发调试：完成目标后仍走正常 ready / 交付流程"
	task_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_hint.add_theme_color_override("font_color", Color("f0c978"))
	content.add_child(task_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_task_debug_list = VBoxContainer.new()
	_task_debug_list.add_theme_constant_override("separation", 5)
	_task_debug_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_task_debug_list)


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
		var anim := str(member.get_node("CharacterActionSet/AnimatedSprite2D").animation)
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
				# 节点驱动 AI 距离调试：显示目标边缘距离 / 可用节点区间 / 当前行为
				if enemy.has_method("get_ai_debug_text"):
					lines.append(enemy.get_ai_debug_text())

	_label.text = "\n".join(lines)


func _refresh_task_debug() -> void:
	if _task_debug_list == null:
		return
	for child in _task_debug_list.get_children():
		child.queue_free()
	if _quest_service == null:
		return
	var has_visible_task := false
	for quest_value in _quest_service.get_visible_tasks():
		if not quest_value is Dictionary:
			continue
		var quest: Dictionary = quest_value
		var status := str(quest.get("status", "inactive"))
		if status not in ["active", "ready"]:
			continue
		has_visible_task = true
		var quest_id := int(quest.get("id", 0))
		var quest_box := VBoxContainer.new()
		var quest_title := Label.new()
		quest_title.text = "%d  %s  [%s]" % [quest_id, str(quest.get("title", "任务")), "可交付" if status == "ready" else "进行中"]
		quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quest_title.add_theme_color_override("font_color", Color("ffd84d") if status == "active" else Color("6fc7ff"))
		quest_box.add_child(quest_title)
		var objectives: Array = quest.get("objectives", [])
		for index in range(objectives.size()):
			if not objectives[index] is Dictionary:
				continue
			var objective: Dictionary = objectives[index]
			var objective_id := str(objective.get("id", ""))
			if objective_id.is_empty():
				continue
			var progress := _quest_service.get_objective_progress(quest_id, objective, index)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var text := Label.new()
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.text = "  %s  %d/%d" % [
				_quest_service.get_objective_text(objective),
				int(progress.get("current", 0)),
				int(progress.get("required", 1)),
			]
			row.add_child(text)
			var complete_button := Button.new()
			complete_button.text = "已完成" if bool(progress.get("complete", false)) else "完成本项"
			complete_button.disabled = bool(progress.get("complete", false))
			complete_button.custom_minimum_size.x = 82
			complete_button.pressed.connect(_on_debug_complete_pressed.bind(quest_id, objective_id))
			row.add_child(complete_button)
			if bool(progress.get("debug_completed", false)):
				var clear_button := Button.new()
				clear_button.text = "撤销"
				clear_button.custom_minimum_size.x = 52
				clear_button.pressed.connect(_on_debug_clear_pressed.bind(quest_id, objective_id))
				row.add_child(clear_button)
			quest_box.add_child(row)
		_task_debug_list.add_child(quest_box)
	if not has_visible_task:
		var empty := Label.new()
		empty.text = "当前没有进行中/可交付任务"
		empty.add_theme_color_override("font_color", Color("aaa18f"))
		_task_debug_list.add_child(empty)


func _on_debug_complete_pressed(quest_id: int, objective_id: String) -> void:
	if _quest_service != null and _quest_service.debug_complete_objective(quest_id, objective_id):
		_refresh_task_debug()


func _on_debug_clear_pressed(quest_id: int, objective_id: String) -> void:
	if _quest_service != null and _quest_service.debug_clear_objective(quest_id, objective_id):
		_refresh_task_debug()


func _on_quest_updated(_quest_id: int) -> void:
	_refresh_task_debug()


func _state_name(state) -> String:
	match state:
		0: return "IDLE"
		1: return "ATTACKING"
		2: return "SKILL"
		3: return "HIT"
		4: return "DEAD"
		_: return str(state)
