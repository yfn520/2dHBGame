class_name BattleHud
extends Control
## 常驻战斗 HUD（位于 HUDLayer）。
## 左上：主控状态 + 队友条目；顶部中央：敌人信息；底部中央：技能槽；右上：入口按钮。
## 不再持有 CharacterPanel 引用，通过 UIRoot 发送语义化页面请求。

const BLUE_PLACEHOLDER_CURRENT := 100
const BLUE_PLACEHOLDER_MAX := 100
const SKILL_SLOTS := [
	{"key": "J", "slot": "normal", "fallback": "普攻"},
	{"key": "K", "slot": "skill1", "fallback": "技能1"},
	{"key": "L", "slot": "skill2", "fallback": "技能2"},
	{"key": "U", "slot": "skill3", "fallback": "技能3"},
]

var ui_root: UIRoot

var _party_manager: PartyManager
var _enemy_spawner: Node
var _active_character: CharacterBody2D
var _active_combat: Node
var _layout_signature := ""
var _refresh_timer := 0.0

var _main_name_label: Label
var _main_level_label: Label
var _main_hp_bar: ProgressBar
var _main_hp_text: Label
var _main_blue_bar: ProgressBar
var _main_blue_text: Label
var _main_avatar_holder: Control
var _main_avatar_sprite: AnimatedSprite2D
var _main_avatar_fallback: Label
var _ally_list: VBoxContainer
var _skill_buttons: Array[Button] = []
var _enemy_panel: PanelContainer
var _enemy_name_label: Label
var _enemy_hp_bar: ProgressBar
var _enemy_hp_text: Label
var _enemy_info_label: Label


func _ready() -> void:
	_build_layout()
	_connect_registry_signals()


func setup(party_manager: PartyManager, enemy_spawner: Node = null) -> void:
	_party_manager = party_manager
	_enemy_spawner = enemy_spawner
	if _party_manager != null:
		if not _party_manager.active_character_changed.is_connected(_on_active_character_changed):
			_party_manager.active_character_changed.connect(_on_active_character_changed)
		if not _party_manager.party_changed.is_connected(_on_party_changed):
			_party_manager.party_changed.connect(_on_party_changed)
		_active_character = _party_manager.get_active_character()
		_connect_active_combat()
	_rebuild_ally_cards()
	_refresh_all()


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.1
	var signature := _get_party_signature()
	if signature != _layout_signature:
		_rebuild_ally_cards()
	_refresh_all()


func _connect_registry_signals() -> void:
	if GameRegistry.character_stats != null:
		if not GameRegistry.character_stats.stats_changed.is_connected(_refresh_all):
			GameRegistry.character_stats.stats_changed.connect(_refresh_all)
	if GameRegistry.roster_data != null:
		if not GameRegistry.roster_data.character_progress_changed.is_connected(_on_roster_progress_changed):
			GameRegistry.roster_data.character_progress_changed.connect(_on_roster_progress_changed)
		if not GameRegistry.roster_data.active_character_changed.is_connected(_on_roster_active_changed):
			GameRegistry.roster_data.active_character_changed.connect(_on_roster_active_changed)
	if GameRegistry.equipment_provider != null:
		if not GameRegistry.equipment_provider.equipped.is_connected(_on_equipment_changed):
			GameRegistry.equipment_provider.equipped.connect(_on_equipment_changed)
		if not GameRegistry.equipment_provider.unequipped.is_connected(_on_equipment_changed):
			GameRegistry.equipment_provider.unequipped.connect(_on_equipment_changed)


# ---- 布局 ----

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()
	add_child(_build_main_card())
	add_child(_build_enemy_panel())
	add_child(_build_right_buttons())
	add_child(_build_bottom_panel())


func _build_main_card() -> Control:
	var column := VBoxContainer.new()
	column.name = "LeftPartyColumn"
	column.position = Vector2(10, 10)
	column.add_theme_constant_override("separation", 5)

	var card := PanelContainer.new()
	card.theme_type_variation = &"HUDCard"
	card.custom_minimum_size = Vector2(282, 96)
	column.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)

	_main_avatar_holder = PanelContainer.new()
	_main_avatar_holder.theme_type_variation = &"Panel"
	_main_avatar_holder.custom_minimum_size = Vector2(72, 72)
	row.add_child(_main_avatar_holder)
	_setup_avatar_holder(_main_avatar_holder, true)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	_main_name_label = Label.new()
	_main_name_label.theme_type_variation = &"HUDTitle"
	_main_name_label.add_theme_font_size_override("font_size", 17)
	info.add_child(_main_name_label)

	var hp_wrap := _make_bar()
	_main_hp_bar = hp_wrap["bar"]
	_main_hp_text = hp_wrap["label"]
	info.add_child(hp_wrap["root"])

	var blue_wrap := _make_bar()
	_main_blue_bar = blue_wrap["bar"]
	_main_blue_text = blue_wrap["label"]
	info.add_child(blue_wrap["root"])

	_main_level_label = Label.new()
	_main_level_label.theme_type_variation = &"HUDValue"
	_main_level_label.add_theme_font_size_override("font_size", 14)
	info.add_child(_main_level_label)

	_ally_list = VBoxContainer.new()
	_ally_list.name = "AllyCards"
	_ally_list.add_theme_constant_override("separation", 6)
	column.add_child(_ally_list)
	return column


func _build_enemy_panel() -> Control:
	_enemy_panel = PanelContainer.new()
	_enemy_panel.name = "CurrentEnemyPanel"
	_enemy_panel.theme_type_variation = &"HUDCard"
	_enemy_panel.visible = false
	_enemy_panel.anchor_left = 0.5
	_enemy_panel.anchor_right = 0.5
	_enemy_panel.anchor_top = 0.0
	_enemy_panel.anchor_bottom = 0.0
	_enemy_panel.offset_left = -150
	_enemy_panel.offset_right = 150
	_enemy_panel.offset_top = 10
	_enemy_panel.offset_bottom = 78

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 3)
	_enemy_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	_enemy_name_label = Label.new()
	_enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_name_label.theme_type_variation = &"HUDTitle"
	_enemy_name_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_enemy_name_label)

	var hp_wrap := _make_bar()
	_enemy_hp_bar = hp_wrap["bar"]
	_enemy_hp_text = hp_wrap["label"]
	vbox.add_child(hp_wrap["root"])

	_enemy_info_label = Label.new()
	_enemy_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_info_label.theme_type_variation = &"HUDMuted"
	_enemy_info_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_enemy_info_label)
	return _enemy_panel


func _setup_avatar_holder(holder: Control, is_main: bool) -> void:
	var layer_node := Control.new()
	layer_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(layer_node)

	var sprite := AnimatedSprite2D.new()
	sprite.position = Vector2(36, 59) if is_main else Vector2(22, 38)
	sprite.scale = Vector2(0.66, 0.66) if is_main else Vector2(0.38, 0.38)
	layer_node.add_child(sprite)

	var fallback := Label.new()
	fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.theme_type_variation = &"HUDTitle"
	fallback.add_theme_font_size_override("font_size", 18 if is_main else 12)
	layer_node.add_child(fallback)

	if is_main:
		_main_avatar_sprite = sprite
		_main_avatar_fallback = fallback
	else:
		holder.set_meta("avatar_sprite", sprite)
		holder.set_meta("avatar_fallback", fallback)


func _build_right_buttons() -> Control:
	var box := VBoxContainer.new()
	box.name = "RightHudButtons"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -142
	box.offset_top = 10
	box.offset_right = -10
	box.offset_bottom = 120
	box.add_theme_constant_override("separation", 5)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var inventory_btn := _make_entry_button("背包(B)")
	inventory_btn.pressed.connect(_on_inventory_pressed)
	row.add_child(inventory_btn)

	var task_btn := _make_entry_button("任务")
	task_btn.pressed.connect(_on_task_pressed)
	row.add_child(task_btn)
	return box


func _build_bottom_panel() -> Control:
	var box := VBoxContainer.new()
	box.name = "BottomCombatBar"
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 310
	box.offset_right = -310
	box.offset_top = -52
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	# 只保留技能槽，移除重复的长属性条
	var skill_row := HBoxContainer.new()
	skill_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_row.add_theme_constant_override("separation", 8)
	box.add_child(skill_row)

	_skill_buttons.clear()
	for skill_info in SKILL_SLOTS:
		var btn := Button.new()
		btn.theme_type_variation = &"HUDButton"
		btn.custom_minimum_size = Vector2(62, 42)
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = true
		skill_row.add_child(btn)
		_skill_buttons.append(btn)
	return box


func _make_entry_button(text_value: String) -> Button:
	var btn := Button.new()
	btn.text = text_value
	btn.theme_type_variation = &"HUDButton"
	btn.custom_minimum_size = Vector2(60, 54)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	return btn


func _make_bar() -> Dictionary:
	var root := PanelContainer.new()
	root.theme_type_variation = &"HUDStat"
	root.custom_minimum_size = Vector2(176, 18)

	var bar := ProgressBar.new()
	bar.theme_type_variation = &"HUDBar"
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	root.add_child(bar)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"HUDValue"
	label.add_theme_font_size_override("font_size", 12)
	root.add_child(label)
	return {"root": root, "bar": bar, "label": label}


# ---- 事件 ----

func _on_active_character_changed(character: CharacterBody2D) -> void:
	_active_character = character
	_connect_active_combat()
	_rebuild_ally_cards()
	_refresh_all()


func _on_party_changed() -> void:
	if _party_manager != null:
		_active_character = _party_manager.get_active_character()
	_connect_active_combat()
	_rebuild_ally_cards()
	_refresh_all()


func _on_roster_progress_changed(_character_id: int) -> void:
	_rebuild_ally_cards()
	_refresh_all()


func _on_roster_active_changed(_character_id: int) -> void:
	_refresh_all()


func _on_equipment_changed(_slot: String = "", _item_id: int = 0) -> void:
	_refresh_all()


func _connect_active_combat() -> void:
	if _active_character == null:
		_active_combat = null
		return
	_active_combat = _active_character.get_node_or_null("CombatComponent")
	if _active_combat != null and _active_combat.has_signal("hp_changed"):
		if not _active_combat.hp_changed.is_connected(_on_active_hp_changed):
			_active_combat.hp_changed.connect(_on_active_hp_changed)


func _on_active_hp_changed(_current: int, _max_hp: int) -> void:
	_refresh_all()


func _on_inventory_pressed() -> void:
	if ui_root != null:
		ui_root.toggle_main_menu(UIRoot.TAB_INVENTORY)


func _on_task_pressed() -> void:
	if ui_root != null:
		ui_root.toggle_task_drawer()


# ---- 队友卡 ----

func _rebuild_ally_cards() -> void:
	if _ally_list == null:
		return
	for child in _ally_list.get_children():
		child.queue_free()
	_layout_signature = _get_party_signature()
	if _party_manager == null:
		return
	for member in _party_manager.get_party_members():
		if not is_instance_valid(member) or member == _active_character:
			continue
		_ally_list.add_child(_make_ally_card(member))


func _make_ally_card(member: CharacterBody2D) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"HUDCardSmall"
	card.custom_minimum_size = Vector2(228, 56)
	card.set_meta("member", member)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)

	var avatar := PanelContainer.new()
	avatar.theme_type_variation = &"Panel"
	avatar.custom_minimum_size = Vector2(44, 44)
	row.add_child(avatar)
	_setup_avatar_holder(avatar, false)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.theme_type_variation = &"HUDTitle"
	info.add_child(name_label)

	var hp_wrap := _make_bar()
	info.add_child(hp_wrap["root"])

	var level_label := Label.new()
	level_label.theme_type_variation = &"HUDMuted"
	info.add_child(level_label)

	card.set_meta("avatar_holder", avatar)
	card.set_meta("name_label", name_label)
	card.set_meta("hp_bar", hp_wrap["bar"])
	card.set_meta("hp_label", hp_wrap["label"])
	card.set_meta("level_label", level_label)
	_refresh_ally_card(card)
	return card


# ---- 刷新 ----

func _refresh_all() -> void:
	_refresh_main_card()
	_refresh_ally_cards()
	_refresh_enemy_panel()
	_refresh_skills()


func _refresh_main_card() -> void:
	if _active_character == null:
		return
	var character_id := _get_member_character_id(_active_character)
	var stats = _get_active_stats()
	var level := _get_member_level(_active_character)
	var character_name := _get_character_name(character_id)
	_main_name_label.text = character_name
	_main_level_label.text = "等级 %d" % level
	if stats != null:
		var hp := int(stats.hp)
		var max_hp := maxi(1, int(stats.max_hp))
		_main_hp_bar.max_value = max_hp
		_main_hp_bar.value = clampi(hp, 0, max_hp)
		_main_hp_text.text = "%d/%d" % [hp, max_hp]
	_main_blue_bar.max_value = BLUE_PLACEHOLDER_MAX
	_main_blue_bar.value = BLUE_PLACEHOLDER_CURRENT
	_main_blue_text.text = "%d/%d" % [BLUE_PLACEHOLDER_CURRENT, BLUE_PLACEHOLDER_MAX]
	_set_avatar(_main_avatar_sprite, _main_avatar_fallback, _active_character, character_name, false)


func _refresh_ally_cards() -> void:
	if _ally_list == null:
		return
	for card in _ally_list.get_children():
		_refresh_ally_card(card as PanelContainer)


func _refresh_ally_card(card: PanelContainer) -> void:
	if card == null:
		return
	var member = card.get_meta("member", null)
	if member == null or not is_instance_valid(member):
		card.modulate = Color(0.55, 0.55, 0.55, 0.7)
		return
	var character_id := _get_member_character_id(member)
	var name_label := card.get_meta("name_label") as Label
	var hp_bar := card.get_meta("hp_bar") as ProgressBar
	var hp_label := card.get_meta("hp_label") as Label
	var level_label := card.get_meta("level_label") as Label
	var avatar := card.get_meta("avatar_holder") as Control
	var stats = _get_member_stats(member)
	var character_name := _get_character_name(character_id)
	if name_label != null:
		name_label.text = character_name
	if level_label != null:
		level_label.text = "等级 %d" % _get_member_level(member)
	if hp_bar != null and hp_label != null and stats != null:
		var hp := int(stats.hp)
		var max_hp := maxi(1, int(stats.max_hp))
		hp_bar.max_value = max_hp
		hp_bar.value = clampi(hp, 0, max_hp)
		hp_label.text = "%d/%d" % [hp, max_hp]
	if avatar != null:
		var sprite := avatar.get_meta("avatar_sprite") as AnimatedSprite2D
		var fallback := avatar.get_meta("avatar_fallback") as Label
		_set_avatar(sprite, fallback, member, character_name, stats != null and int(stats.hp) <= 0)
	card.modulate = Color(0.55, 0.55, 0.55, 0.76) if stats != null and int(stats.hp) <= 0 else Color.WHITE


func _refresh_skills() -> void:
	if _active_character == null:
		return
	var character_id := _get_member_character_id(_active_character)
	var level := _get_member_level(_active_character)
	var cooldowns := {}
	if _active_combat != null and _active_combat.has_method("get_cooldowns_dict"):
		cooldowns = _active_combat.get_cooldowns_dict()
	for i in range(_skill_buttons.size()):
		var btn := _skill_buttons[i]
		var slot_info: Dictionary = SKILL_SLOTS[i]
		var skill_id := _get_skill_id(character_id, String(slot_info["slot"]), level)
		var name := String(slot_info["fallback"])
		if skill_id > 0 and GameRegistry.skill_config != null:
			var skill: Dictionary = GameRegistry.skill_config.get_skill(skill_id)
			if not skill.is_empty():
				name = String(skill.get("name", name))
		var cd := float(cooldowns.get(skill_id, 0.0))
		btn.disabled = skill_id <= 0
		if skill_id <= 0:
			btn.text = "%s\n未配置" % String(slot_info["key"])
		elif cd > 0.05:
			btn.text = "%s\n%s\n%.1fs" % [String(slot_info["key"]), _short_name(name, 4), cd]
		else:
			btn.text = "%s\n%s" % [String(slot_info["key"]), _short_name(name, 5)]


func _refresh_enemy_panel() -> void:
	if _enemy_panel == null:
		return
	var enemy := _select_current_enemy()
	if enemy == null:
		_enemy_panel.visible = false
		return
	var stats = enemy.get_combat_stats() if enemy.has_method("get_combat_stats") else null
	if stats == null:
		_enemy_panel.visible = false
		return
	_enemy_panel.visible = true
	_enemy_name_label.text = enemy.get_enemy_name() if enemy.has_method("get_enemy_name") else enemy.name
	var hp := int(stats.hp)
	var max_hp := maxi(1, int(stats.max_hp))
	_enemy_hp_bar.max_value = max_hp
	_enemy_hp_bar.value = clampi(hp, 0, max_hp)
	_enemy_hp_text.text = "%d/%d" % [hp, max_hp]
	var ai_name: String = enemy.get_ai_state_name() if enemy.has_method("get_ai_state_name") else "?"
	var target_name: String = enemy.get_current_target_name() if enemy.has_method("get_current_target_name") else "无"
	var dist: int = enemy.get_target_distance_x() if enemy.has_method("get_target_distance_x") else INF
	var dist_text := "-" if is_inf(dist) else str(int(dist))
	_enemy_info_label.text = "状态：%s    目标：%s    距离：%s" % [
		_translate_ai_state(ai_name),
		target_name,
		dist_text,
	]


func _select_current_enemy() -> Node:
	if _enemy_spawner == null or not is_instance_valid(_enemy_spawner):
		return null
	var enemies: Array[Node] = []
	if _enemy_spawner.has_method("get_active_enemies"):
		enemies = _enemy_spawner.get_active_enemies()
	var best: Node = null
	var best_score := INF
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var stats = enemy.get_combat_stats() if enemy.has_method("get_combat_stats") else null
		if stats == null or int(stats.hp) <= 0:
			continue
		var dist_to_active := INF
		if _active_character != null and is_instance_valid(_active_character):
			dist_to_active = absf(enemy.global_position.x - _active_character.global_position.x)
		var score := dist_to_active
		var target = enemy.get_current_target() if enemy.has_method("get_current_target") else null
		if target == _active_character:
			score -= 10000.0
		elif target != null and is_instance_valid(target):
			score -= 5000.0
		if enemy.has_method("get_ai_state_name"):
			var ai_name := String(enemy.get_ai_state_name())
			if ai_name == "ATTACK":
				score -= 1000.0
			elif ai_name == "CHASE":
				score -= 500.0
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _translate_ai_state(ai_name: String) -> String:
	match ai_name:
		"IDLE": return "待机"
		"PATROL": return "巡逻"
		"CHASE": return "追击"
		"ATTACK": return "攻击"
		"HIT": return "受击"
		"DEAD": return "死亡"
		_: return ai_name


func _set_avatar(sprite: AnimatedSprite2D, fallback: Label, member: CharacterBody2D, character_name: String, dimmed: bool) -> void:
	if sprite == null or fallback == null:
		return
	sprite.visible = false
	fallback.visible = true
	fallback.text = character_name.substr(0, 1) if not character_name.is_empty() else "?"
	if member == null or not is_instance_valid(member):
		return
	var source := member.get_node_or_null("CharacterActionSet/AnimatedSprite2D") as AnimatedSprite2D
	if source == null or source.sprite_frames == null:
		return
	sprite.sprite_frames = source.sprite_frames
	var anim := "idle"
	if not sprite.sprite_frames.has_animation(anim):
		var names := sprite.sprite_frames.get_animation_names()
		if names.is_empty():
			return
		anim = String(names[0])
	sprite.animation = anim
	sprite.frame = 0
	sprite.play()
	sprite.modulate = Color(0.45, 0.45, 0.45, 0.75) if dimmed else Color.WHITE
	sprite.visible = true
	fallback.visible = false


# ---- 辅助 ----

func _get_active_stats():
	var member_stats = _get_member_stats(_active_character)
	if member_stats != null:
		return member_stats
	if GameRegistry.character_stats != null:
		return GameRegistry.character_stats
	return null


func _get_member_stats(member: CharacterBody2D):
	if member == null or not is_instance_valid(member):
		return null
	if member.has_method("get_combat_stats"):
		return member.get_combat_stats()
	return null


func _get_member_character_id(member: CharacterBody2D) -> int:
	if member != null and member.has_method("get_party_character_id"):
		return member.get_party_character_id()
	return 0


func _get_member_level(member: CharacterBody2D) -> int:
	var character_id := _get_member_character_id(member)
	if GameRegistry.roster_data != null and character_id > 0:
		return GameRegistry.roster_data.get_level(character_id)
	return 1


func _get_character_name(character_id: int) -> String:
	if GameRegistry.character_config != null and character_id > 0:
		return GameRegistry.character_config.get_name(character_id)
	return str(character_id)


func _get_skill_id(character_id: int, slot_name: String, level: int) -> int:
	if GameRegistry.character_config == null or character_id <= 0:
		return 0
	if slot_name == "normal":
		return GameRegistry.character_config.get_normal_skill(character_id)
	return GameRegistry.character_config.get_skill_for_slot(character_id, slot_name, level)


func _get_party_signature() -> String:
	if _party_manager == null:
		return ""
	var ids: PackedStringArray = []
	var active_id := 0
	if _party_manager.get_active_character() != null:
		active_id = _get_member_character_id(_party_manager.get_active_character())
	for member in _party_manager.get_party_members():
		if is_instance_valid(member):
			ids.append(str(_get_member_character_id(member)))
	return "%d|%s" % [active_id, "|".join(ids)]


func _short_name(value: String, max_len: int) -> String:
	if value.length() <= max_len:
		return value
	return value.substr(0, max_len)
