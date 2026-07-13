class_name MainMenu
extends Control
## 统一主菜单：左侧四个导航标签，右侧为当前页面。
## 注册 character / equipment / skills / inventory 四页；时装和宠物隐藏。

signal menu_changed(opened: bool, tab: StringName)

const INVENTORY_CAPACITY := 30
const INVENTORY_COLUMNS := 5
const SLOT_SIZE := Vector2(58, 58)
const WINDOW_MAX_SIZE := Vector2(1020, 620)

const SLOT_LABELS := {
	"weapon": "武器", "armor": "护甲", "necklace": "项链", "ring": "戒指",
	"boots": "靴子", "relic": "圣物", "mount": "坐骑", "artifact": "神器",
}

const TYPE_LABELS := {
	"all": "全部", "weapon": "武器", "armor": "护甲", "necklace": "项链",
	"ring": "戒指", "boots": "靴子", "relic": "圣物", "mount": "坐骑",
	"artifact": "神器", "consumable": "药水", "material": "材料",
}

const TYPE_COLORS := {
	"weapon": Color(0.86, 0.48, 0.40), "armor": Color(0.72, 0.58, 0.40),
	"boots": Color(0.48, 0.72, 0.52), "necklace": Color(0.68, 0.52, 0.82),
	"ring": Color(0.70, 0.44, 0.78), "relic": Color(0.82, 0.58, 0.34),
	"mount": Color(0.46, 0.64, 0.78), "artifact": Color(0.88, 0.70, 0.32),
	"consumable": Color(0.40, 0.68, 0.86), "material": Color(0.48, 0.78, 0.56),
}

const SKILL_SLOTS := [
	{"key": "J", "slot": "normal", "fallback": "普攻"},
	{"key": "K", "slot": "skill1", "fallback": "技能1"},
	{"key": "L", "slot": "skill2", "fallback": "技能2"},
	{"key": "U", "slot": "skill3", "fallback": "技能3"},
]

var skin: UISkin
var ui_root: UIRoot

var _party_manager: PartyManager
var _active_tab: StringName = &"equipment"
var _inventory_filter: String = "all"
var _selected_inventory_index: int = -1
var _current_popup_slot: String = ""

var _window: PanelContainer
var _tab_buttons: Dictionary = {}
var _pages: Dictionary = {}

# Character page
var _char_name_label: Label
var _char_level_label: Label
var _char_exp_label: Label
var _char_preview_sprite: AnimatedSprite2D
var _char_preview_fallback: Label
var _char_hp_label: Label
var _char_atk_label: Label
var _char_def_label: Label
var _char_spd_label: Label
var _char_stars_label: Label

# Equipment page
var _equip_buttons: Dictionary = {}
var _equip_preview_sprite: AnimatedSprite2D
var _equip_preview_fallback: Label
var _equip_name_label: Label
var _equip_hp_label: Label
var _equip_atk_label: Label
var _equip_def_label: Label
var _equip_spd_label: Label

# Skills page
var _skill_rows: Array = []

# Inventory page
var _inv_category_buttons: Dictionary = {}
var _inv_grid: GridContainer
var _inv_buttons: Array[Button] = []
var _inv_capacity_label: Label
var _inv_detail_label: Label

# Popup
var _popup: PanelContainer
var _popup_title: Label
var _popup_list: VBoxContainer

var _refresh_timer := 0.0


func _ready() -> void:
	_build_layout()
	_connect_data_signals()
	_show_page(_active_tab)


func setup(party_manager: PartyManager) -> void:
	_party_manager = party_manager


func open(tab: StringName = &"equipment") -> void:
	_active_tab = tab
	visible = true
	_show_page(tab)
	_refresh_all()


func close() -> void:
	visible = false
	if ui_root != null:
		ui_root.hide_tooltip()
	_close_popup()
	menu_changed.emit(false, _active_tab)


func is_open() -> bool:
	return visible


func current_tab() -> StringName:
	return _active_tab


func has_open_popup() -> bool:
	return _popup != null and _popup.visible


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.15
	_refresh_skills_page()
	# 更新 tooltip 位置
	if ui_root != null:
		_position_tooltip()


# ---- 布局构建 ----

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	# 半透明遮罩
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.015, 0.01, 0.55)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	# 主窗口
	_window = PanelContainer.new()
	_window.name = "MainWindow"
	_window.theme_type_variation = &"Window"
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.offset_left = -WINDOW_MAX_SIZE.x * 0.5
	_window.offset_top = -WINDOW_MAX_SIZE.y * 0.5
	_window.offset_right = WINDOW_MAX_SIZE.x * 0.5
	_window.offset_bottom = WINDOW_MAX_SIZE.y * 0.5
	add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	_window.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	root_vbox.add_child(_build_header())
	root_vbox.add_child(_build_body())
	_build_popup()


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 38)
	header.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "英雄"
	title.theme_type_variation = &"HUDTitle"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.theme_type_variation = &"HUDButton"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	return header


func _build_body() -> Control:
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)

	var content := Control.new()
	content.name = "PageContainer"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size = Vector2(0, 470)
	body.add_child(content)

	# 角色、装备和背包共享同一张英雄总览；技能保留独立页面。
	_pages.clear()
	_pages[&"hero"] = _build_hero_inventory_page()
	_pages[&"skills"] = _build_skills_page()
	for page in _pages.values():
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		content.add_child(page)
	body.add_child(_build_bottom_nav())
	return body


func _build_bottom_nav() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"Panel"
	bar.custom_minimum_size = Vector2(0, 58)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	var tabs := [
		[&"character", "信息"],
		[&"skills", "技能"],
		[&"equipment", "装备"],
		[&"inventory", "背包"],
	]
	for tab_data in tabs:
		var tab_name: StringName = tab_data[0]
		var btn := Button.new()
		btn.text = String(tab_data[1])
		btn.theme_type_variation = &"TabButton"
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(150, 46)
		btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		row.add_child(btn)
		_tab_buttons[tab_name] = btn
	return bar


func _build_hero_inventory_page() -> Control:
	var page := HBoxContainer.new()
	page.name = "HeroInventoryPage"
	page.add_theme_constant_override("separation", 10)

	var left := _build_unified_character_panel()
	left.custom_minimum_size = Vector2(430, 0)
	page.add_child(left)

	var inventory := _build_inventory_page()
	inventory.custom_minimum_size = Vector2(540, 0)
	inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(inventory)
	return page


func _build_unified_character_panel() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Panel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	_equip_name_label = Label.new()
	_equip_name_label.theme_type_variation = &"HUDTitle"
	_equip_name_label.add_theme_font_size_override("font_size", 20)
	_equip_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_equip_name_label)
	_char_name_label = _equip_name_label

	_char_stars_label = Label.new()
	_char_stars_label.text = "★★★★☆"
	_char_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_char_stars_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.14))
	column.add_child(_char_stars_label)

	var stage := HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 6)
	column.add_child(stage)

	var left_slots := VBoxContainer.new()
	left_slots.add_theme_constant_override("separation", 5)
	stage.add_child(left_slots)
	for slot in ["weapon", "armor", "necklace", "ring"]:
		left_slots.add_child(_make_equip_button(slot))

	var preview_holder := PanelContainer.new()
	preview_holder.theme_type_variation = &"Panel"
	preview_holder.custom_minimum_size = Vector2(220, 270)
	preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(preview_holder)

	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_holder.add_child(preview_layer)

	_equip_preview_sprite = AnimatedSprite2D.new()
	_equip_preview_sprite.position = Vector2(110, 205)
	_equip_preview_sprite.scale = Vector2(1.55, 1.55)
	preview_layer.add_child(_equip_preview_sprite)
	_char_preview_sprite = _equip_preview_sprite

	_equip_preview_fallback = Label.new()
	_equip_preview_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_equip_preview_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_equip_preview_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_layer.add_child(_equip_preview_fallback)
	_char_preview_fallback = _equip_preview_fallback

	var right_slots := VBoxContainer.new()
	right_slots.add_theme_constant_override("separation", 5)
	stage.add_child(right_slots)
	for slot in ["boots", "relic", "mount", "artifact"]:
		right_slots.add_child(_make_equip_button(slot))

	var progress := HBoxContainer.new()
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	progress.add_theme_constant_override("separation", 10)
	column.add_child(progress)
	_char_level_label = _make_info_label("等级 1")
	_char_exp_label = _make_info_label("经验 0")
	progress.add_child(_char_level_label)
	progress.add_child(_char_exp_label)

	var stats_panel := PanelContainer.new()
	stats_panel.theme_type_variation = &"HUDStat"
	stats_panel.custom_minimum_size = Vector2(0, 42)
	column.add_child(stats_panel)
	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 4)
	stats_panel.add_child(stats_row)
	_equip_hp_label = _make_info_label("生命 0/0")
	_equip_atk_label = _make_info_label("攻击 0")
	_equip_def_label = _make_info_label("防御 0")
	_equip_spd_label = _make_info_label("速度 0")
	_char_hp_label = _equip_hp_label
	_char_atk_label = _equip_atk_label
	_char_def_label = _equip_def_label
	_char_spd_label = _equip_spd_label
	stats_row.add_child(_equip_hp_label)
	stats_row.add_child(_equip_atk_label)
	stats_row.add_child(_equip_def_label)
	stats_row.add_child(_equip_spd_label)
	return panel


func _build_left_nav() -> Control:
	var nav := PanelContainer.new()
	nav.theme_type_variation = &"Panel"
	nav.custom_minimum_size = Vector2(96, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	nav.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var tabs := [
		[&"character", "角色"],
		[&"equipment", "装备"],
		[&"skills", "技能"],
		[&"inventory", "背包"],
	]
	for tab_data in tabs:
		var tab_name: StringName = tab_data[0]
		var label_text: String = tab_data[1]
		var btn := Button.new()
		btn.text = label_text
		btn.theme_type_variation = &"TabButton"
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(84, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		vbox.add_child(btn)
		_tab_buttons[tab_name] = btn

	# 填充
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# 快捷键提示
	var hint := Label.new()
	hint.text = "B:背包\nC:装备\nEsc:关闭"
	hint.theme_type_variation = &"HUDMuted"
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)
	return nav


# ---- 角色页 ----

func _build_character_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "CharacterPage"
	page.add_theme_constant_override("separation", 8)

	# 角色名
	_char_name_label = Label.new()
	_char_name_label.theme_type_variation = &"HUDTitle"
	_char_name_label.add_theme_font_size_override("font_size", 22)
	_char_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_char_name_label)

	_char_stars_label = Label.new()
	_char_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_char_stars_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.14))
	page.add_child(_char_stars_label)

	# 预览区
	var preview_holder := PanelContainer.new()
	preview_holder.theme_type_variation = &"Panel"
	preview_holder.custom_minimum_size = Vector2(0, 180)
	preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(preview_holder)

	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_holder.add_child(preview_layer)

	_char_preview_sprite = AnimatedSprite2D.new()
	_char_preview_sprite.position = Vector2(0, 40)
	_char_preview_sprite.scale = Vector2(1.4, 1.4)
	preview_layer.add_child(_char_preview_sprite)

	_char_preview_fallback = Label.new()
	_char_preview_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_char_preview_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_char_preview_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_char_preview_fallback.add_theme_font_size_override("font_size", 22)
	preview_layer.add_child(_char_preview_fallback)

	# 等级和经验
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 12)
	page.add_child(level_row)

	_char_level_label = _make_info_label("等级 1")
	_char_exp_label = _make_info_label("经验 0")
	level_row.add_child(_char_level_label)
	level_row.add_child(_char_exp_label)

	# 核心属性
	var stats_panel := PanelContainer.new()
	stats_panel.theme_type_variation = &"HUDStat"
	stats_panel.custom_minimum_size = Vector2(0, 40)
	page.add_child(stats_panel)

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 8)
	stats_panel.add_child(stats_row)

	_char_hp_label = _make_info_label("生命 0/0")
	_char_atk_label = _make_info_label("攻击 0")
	_char_def_label = _make_info_label("防御 0")
	_char_spd_label = _make_info_label("速度 0")
	stats_row.add_child(_char_hp_label)
	stats_row.add_child(_char_atk_label)
	stats_row.add_child(_char_def_label)
	stats_row.add_child(_char_spd_label)

	# GM 调试区
	page.add_child(_build_gm_section())
	return page


func _build_gm_section() -> Control:
	var box := PanelContainer.new()
	box.theme_type_variation = &"Panel"
	box.custom_minimum_size = Vector2(0, 58)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var gm_label := Label.new()
	gm_label.text = "— GM 调试 —"
	gm_label.theme_type_variation = &"HUDMuted"
	gm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gm_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 99
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.name = "GmLevelSpin"
	row.add_child(spin)

	var set_btn := Button.new()
	set_btn.text = "设等级"
	set_btn.theme_type_variation = &"HUDButton"
	set_btn.focus_mode = Control.FOCUS_NONE
	set_btn.name = "GmSetBtn"
	set_btn.pressed.connect(_on_gm_set_level.bind(spin))
	row.add_child(set_btn)

	var max_btn := Button.new()
	max_btn.text = "满级"
	max_btn.theme_type_variation = &"HUDButton"
	max_btn.focus_mode = Control.FOCUS_NONE
	max_btn.name = "GmMaxBtn"
	max_btn.pressed.connect(_on_gm_max_level.bind(spin))
	row.add_child(max_btn)
	return box


# ---- 装备页 ----

func _build_equipment_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "EquipmentPage"
	page.add_theme_constant_override("separation", 6)

	_equip_name_label = Label.new()
	_equip_name_label.theme_type_variation = &"HUDTitle"
	_equip_name_label.add_theme_font_size_override("font_size", 18)
	_equip_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_equip_name_label)

	var holder := HBoxContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 8)
	page.add_child(holder)

	# 左侧装备槽
	var left_slots := VBoxContainer.new()
	left_slots.add_theme_constant_override("separation", 5)
	holder.add_child(left_slots)
	left_slots.add_child(_make_equip_button("weapon"))
	left_slots.add_child(_make_equip_button("armor"))
	left_slots.add_child(_make_equip_button("necklace"))
	left_slots.add_child(_make_equip_button("ring"))

	# 中间预览
	var preview_holder := PanelContainer.new()
	preview_holder.theme_type_variation = &"Panel"
	preview_holder.custom_minimum_size = Vector2(200, 240)
	preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(preview_holder)

	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_holder.add_child(preview_layer)

	_equip_preview_sprite = AnimatedSprite2D.new()
	_equip_preview_sprite.position = Vector2(100, 180)
	_equip_preview_sprite.scale = Vector2(1.5, 1.5)
	preview_layer.add_child(_equip_preview_sprite)

	_equip_preview_fallback = Label.new()
	_equip_preview_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_equip_preview_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_equip_preview_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_layer.add_child(_equip_preview_fallback)

	# 右侧装备槽
	var right_slots := VBoxContainer.new()
	right_slots.add_theme_constant_override("separation", 5)
	holder.add_child(right_slots)
	right_slots.add_child(_make_equip_button("boots"))
	right_slots.add_child(_make_equip_button("relic"))
	right_slots.add_child(_make_equip_button("mount"))
	right_slots.add_child(_make_equip_button("artifact"))

	# 属性显示
	var stats_panel := PanelContainer.new()
	stats_panel.theme_type_variation = &"HUDStat"
	stats_panel.custom_minimum_size = Vector2(0, 40)
	page.add_child(stats_panel)

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 8)
	stats_panel.add_child(stats_row)

	_equip_hp_label = _make_info_label("生命 0/0")
	_equip_atk_label = _make_info_label("攻击 0")
	_equip_def_label = _make_info_label("防御 0")
	_equip_spd_label = _make_info_label("速度 0")
	stats_row.add_child(_equip_hp_label)
	stats_row.add_child(_equip_atk_label)
	stats_row.add_child(_equip_def_label)
	stats_row.add_child(_equip_spd_label)

	var hint := Label.new()
	hint.text = "点击装备槽穿戴或卸下"
	hint.theme_type_variation = &"HUDMuted"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	page.add_child(hint)
	return page


func _make_equip_button(slot: String) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = &"ItemSlot"
	btn.custom_minimum_size = SLOT_SIZE
	btn.text = SLOT_LABELS.get(slot, slot)
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = "点击穿戴或卸下。"
	btn.pressed.connect(_on_equipment_slot_pressed.bind(slot))
	btn.mouse_entered.connect(_show_equipment_tip.bind(slot))
	btn.mouse_exited.connect(_on_mouse_exited_tip)
	_equip_buttons[slot] = btn
	return btn


# ---- 技能页 ----

func _build_skills_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "SkillsPage"
	page.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "技能 (J / K / L / U)"
	title.theme_type_variation = &"HUDTitle"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)

	_skill_rows.clear()
	for skill_info in SKILL_SLOTS:
		var row_panel := PanelContainer.new()
		row_panel.theme_type_variation = &"HUDCard"
		row_panel.custom_minimum_size = Vector2(0, 64)
		page.add_child(row_panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_panel.add_child(row)

		var key_label := Label.new()
		key_label.text = String(skill_info["key"])
		key_label.theme_type_variation = &"HUDTitle"
		key_label.add_theme_font_size_override("font_size", 20)
		key_label.custom_minimum_size = Vector2(36, 0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(key_label)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)

		var name_label := Label.new()
		name_label.theme_type_variation = &"HUDValue"
		info.add_child(name_label)

		var desc_label := Label.new()
		desc_label.theme_type_variation = &"HUDMuted"
		desc_label.add_theme_font_size_override("font_size", 12)
		info.add_child(desc_label)

		_skill_rows.append({"key": skill_info["key"], "slot": skill_info["slot"], "fallback": skill_info["fallback"], "name_label": name_label, "desc_label": desc_label})

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer)

	var hint := Label.new()
	hint.text = "菜单打开时 J/K/L/U 施法被屏蔽"
	hint.theme_type_variation = &"HUDMuted"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	page.add_child(hint)
	return page


# ---- 背包页 ----

func _build_inventory_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "InventoryPage"
	page.add_theme_constant_override("separation", 6)

	# 分类
	var cat_row := GridContainer.new()
	cat_row.columns = 6
	cat_row.add_theme_constant_override("h_separation", 4)
	cat_row.add_theme_constant_override("v_separation", 4)
	page.add_child(cat_row)
	for type_name in ["all", "weapon", "armor", "necklace", "ring", "boots", "relic", "mount", "artifact", "consumable", "material"]:
		var btn := Button.new()
		btn.text = TYPE_LABELS.get(type_name, type_name)
		btn.theme_type_variation = &"TabButton"
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(64, 30)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_category_pressed.bind(type_name))
		cat_row.add_child(btn)
		_inv_category_buttons[type_name] = btn

	# 物品网格
	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(grid_scroll)

	_inv_grid = GridContainer.new()
	_inv_grid.columns = INVENTORY_COLUMNS
	_inv_grid.add_theme_constant_override("h_separation", 5)
	_inv_grid.add_theme_constant_override("v_separation", 5)
	grid_scroll.add_child(_inv_grid)

	for i in range(INVENTORY_CAPACITY):
		var btn := Button.new()
		btn.theme_type_variation = &"ItemSlot"
		btn.custom_minimum_size = SLOT_SIZE
		btn.toggle_mode = true
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_inventory_slot_pressed.bind(i))
		btn.mouse_entered.connect(_show_inventory_tip.bind(i))
		btn.mouse_exited.connect(_on_mouse_exited_tip)
		_inv_grid.add_child(btn)
		_inv_buttons.append(btn)

	# 底部
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	page.add_child(footer)

	_inv_detail_label = Label.new()
	_inv_detail_label.theme_type_variation = &"HUDMuted"
	_inv_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_inv_detail_label)

	_inv_capacity_label = Label.new()
	_inv_capacity_label.custom_minimum_size = Vector2(86, 28)
	_inv_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inv_capacity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_inv_capacity_label.theme_type_variation = &"HUDValue"
	footer.add_child(_inv_capacity_label)
	return page


# ---- 弹窗 ----

func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.name = "EquipSelectPopup"
	_popup.theme_type_variation = &"Popup"
	_popup.visible = false
	_popup.custom_minimum_size = Vector2(340, 300)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.offset_left = -170
	_popup.offset_top = -150
	_popup.offset_right = 170
	_popup.offset_bottom = 150

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_popup_title = Label.new()
	_popup_title.theme_type_variation = &"HUDTitle"
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_popup_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	_popup_list = VBoxContainer.new()
	_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_popup_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_popup_list)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.theme_type_variation = &"HUDButton"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)


# ---- 页面切换 ----

func _show_page(tab: StringName) -> void:
	_active_tab = tab
	var page_name: StringName = &"skills" if tab == &"skills" else &"hero"
	for tab_name in _pages:
		_pages[tab_name].visible = tab_name == page_name
	for tab_name in _tab_buttons:
		_tab_buttons[tab_name].button_pressed = tab_name == tab
	if visible:
		menu_changed.emit(true, tab)
	_refresh_all()


# ---- 数据刷新 ----

func _refresh_all() -> void:
	_refresh_character_page()
	_refresh_equipment_page()
	_refresh_skills_page()
	_refresh_inventory_page()


func _refresh_character_page() -> void:
	var character_id := _get_active_character_id()
	var character_name := str(character_id)
	if GameRegistry.character_config != null:
		character_name = GameRegistry.character_config.get_name(character_id)
	_char_name_label.text = character_name

	var level := 1
	var exp := 0
	var max_level := 99
	if GameRegistry.roster_data != null:
		level = GameRegistry.roster_data.get_level(character_id)
		exp = GameRegistry.roster_data.get_exp(character_id)
	if GameRegistry.character_config != null:
		max_level = GameRegistry.character_config.get_max_level(character_id)
	_char_level_label.text = "等级 %d" % level
	_char_exp_label.text = "经验 %d" % exp
	_char_stars_label.text = "★★★★☆"

	if GameRegistry.character_stats != null:
		var stats = GameRegistry.character_stats
		_char_hp_label.text = "生命 %d/%d" % [stats.hp, stats.max_hp]
		_char_atk_label.text = "攻击 %d" % stats.attack
		_char_def_label.text = "防御 %d" % stats.defense
		_char_spd_label.text = "速度 %d" % int(stats.move_speed)

	# 预览
	_set_preview(_char_preview_sprite, _char_preview_fallback, character_id)
	# 更新 GM 控件
	for page_key in _pages:
		var page: Control = _pages[page_key]
		if page.name == "CharacterPage":
			var spin: Node = page.get_node_or_null("GmLevelSpin")
			if spin is SpinBox:
				spin.max_value = max_level
				spin.value = level


func _refresh_equipment_page() -> void:
	var character_id := _get_active_character_id()
	var character_name := str(character_id)
	if GameRegistry.character_config != null:
		character_name = GameRegistry.character_config.get_name(character_id)
	_equip_name_label.text = character_name

	_set_preview(_equip_preview_sprite, _equip_preview_fallback, character_id)

	if GameRegistry.character_stats != null:
		var stats = GameRegistry.character_stats
		_equip_hp_label.text = "生命 %d/%d" % [stats.hp, stats.max_hp]
		_equip_atk_label.text = "攻击 %d" % stats.attack
		_equip_def_label.text = "防御 %d" % stats.defense
		_equip_spd_label.text = "速度 %d" % int(stats.move_speed)

	if GameRegistry.equipment_data == null or GameRegistry.item_config == null:
		return
	for slot in EquipmentData.SLOTS:
		var btn: Button = _equip_buttons.get(slot)
		if btn == null:
			continue
		var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot)
		if item_id == 0:
			btn.text = "%s\n空" % SLOT_LABELS.get(slot, slot)
			btn.icon = skin.get_icon(StringName(slot)) if skin != null else null
			btn.tooltip_text = "点击从背包选择。"
			btn.add_theme_color_override("font_color", Color(0.72, 0.60, 0.40))
		else:
			var config: Dictionary = GameRegistry.item_config.get_item(item_id)
			btn.text = "%s\n%s" % [SLOT_LABELS.get(slot, slot), _short_name(String(config.get("name", str(item_id))), 7)]
			btn.icon = _load_item_icon(config)
			btn.tooltip_text = "%s\n%s" % [String(config.get("description", "")), _format_stats(config.get("stats", {}))]
			btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))


func _refresh_skills_page() -> void:
	var character_id := _get_active_character_id()
	var level := 1
	if GameRegistry.roster_data != null:
		level = GameRegistry.roster_data.get_level(character_id)
	var active_char := _party_manager.get_active_character() if _party_manager != null else null
	var cooldowns := {}
	if active_char != null:
		var combat := active_char.get_node_or_null("CombatComponent")
		if combat != null and combat.has_method("get_cooldowns_dict"):
			cooldowns = combat.get_cooldowns_dict()

	for row_data in _skill_rows:
		var slot_name: String = row_data["slot"]
		var key_label: String = row_data["key"]
		var name_label: Label = row_data["name_label"]
		var desc_label: Label = row_data["desc_label"]
		var skill_id := 0
		if GameRegistry.character_config != null:
			if slot_name == "normal":
				skill_id = GameRegistry.character_config.get_normal_skill(character_id)
			else:
				skill_id = GameRegistry.character_config.get_skill_for_slot(character_id, slot_name, level)
		if skill_id <= 0:
			name_label.text = "%s · 未配置" % key_label
			desc_label.text = "该槽位尚未解锁或配置技能。"
		else:
			var skill: Dictionary = GameRegistry.skill_config.get_skill(skill_id)
			var sname := String(skill.get("name", row_data["fallback"]))
			var cd := float(cooldowns.get(skill_id, 0.0))
			if cd > 0.05:
				name_label.text = "%s · %s (%.1fs)" % [key_label, sname, cd]
			else:
				name_label.text = "%s · %s" % [key_label, sname]
			var desc := String(skill.get("description", ""))
			var cd_max := float(skill.get("cooldown", 0.0))
			desc_label.text = "%s  冷却:%.1fs" % [desc, cd_max] if not desc.is_empty() else "冷却:%.1fs" % cd_max


func _refresh_inventory_page() -> void:
	if _inv_grid == null:
		return
	# 更新分类高亮
	for type_name in _inv_category_buttons:
		var btn: Button = _inv_category_buttons[type_name]
		btn.button_pressed = String(type_name) == _inventory_filter

	var items := _get_filtered_items()
	var total_count := 0
	if GameRegistry.inventory_provider != null:
		total_count = GameRegistry.inventory_provider.get_items().size()

	for i in range(_inv_buttons.size()):
		var btn := _inv_buttons[i]
		btn.button_pressed = i == _selected_inventory_index
		if i < items.size():
			var item: ItemInstance = items[i]
			var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
			var item_type: String = String(config.get("type", "empty"))
			var item_name: String = String(config.get("name", str(item.item_id)))
			var count_text := ""
			if item.count > 1:
				count_text = "\nx%d" % item.count
			btn.disabled = false
			btn.text = "%s%s" % [_short_name(item_name, 6), count_text]
			btn.icon = _load_item_icon(config)
			btn.tooltip_text = String(config.get("description", ""))
			btn.add_theme_color_override("font_color", TYPE_COLORS.get(item_type, Color(0.80, 0.70, 0.50)))
		else:
			btn.disabled = true
			btn.text = ""
			btn.icon = null
			btn.tooltip_text = ""
			btn.remove_theme_color_override("font_color")

	if _inv_capacity_label != null:
		_inv_capacity_label.text = "%d/%d" % [total_count, INVENTORY_CAPACITY]
	_refresh_selected_item_text(items)


func _refresh_selected_item_text(items: Array[ItemInstance]) -> void:
	if _inv_detail_label == null:
		return
	if _selected_inventory_index < 0 or _selected_inventory_index >= items.size():
		_inv_detail_label.text = "选择物品查看详情。点击装备槽可穿戴。"
		return
	var item: ItemInstance = items[_selected_inventory_index]
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	_inv_detail_label.text = "%s  %s" % [
		String(config.get("name", str(item.item_id))),
		_format_stats(config.get("stats", {})),
	]


# ---- 事件处理 ----

func _on_tab_pressed(tab: StringName) -> void:
	_show_page(tab)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _on_equipment_slot_pressed(slot: String) -> void:
	_open_equip_popup(slot)


func _on_inventory_slot_pressed(index: int) -> void:
	_selected_inventory_index = index
	var items := _get_filtered_items()
	if index >= 0 and index < items.size():
		var item: ItemInstance = items[index]
		# 如果是装备，直接穿戴
		if GameRegistry.item_config != null and not GameRegistry.item_config.get_equip_slot(item.item_id).is_empty():
			if GameRegistry.equipment_provider != null:
				GameRegistry.equipment_provider.equip_item(item.uid)
				_selected_inventory_index = -1
	_refresh_inventory_page()


func _on_category_pressed(type_name: String) -> void:
	_inventory_filter = type_name
	_selected_inventory_index = -1
	_refresh_inventory_page()


func _on_gm_set_level(spin: SpinBox) -> void:
	if GameRegistry.roster_data == null:
		return
	GameRegistry.roster_data.set_level(int(spin.value))
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_refresh_all()


func _on_gm_max_level(spin: SpinBox) -> void:
	if GameRegistry.roster_data == null or GameRegistry.character_config == null:
		return
	var character_id: int = _get_active_character_id()
	GameRegistry.roster_data.set_level(GameRegistry.character_config.get_max_level(character_id), character_id)
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_refresh_all()


# ---- 弹窗 ----

func _open_equip_popup(slot: String) -> void:
	if ui_root != null:
		ui_root.hide_tooltip()
	# 如果当前槽位有装备，卸下
	if GameRegistry.equipment_data != null and GameRegistry.equipment_provider != null:
		var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot)
		if item_id != 0:
			GameRegistry.equipment_provider.unequip_slot(slot)
			_refresh_equipment_page()
			return
	# 否则打开选择弹窗
	_current_popup_slot = slot
	_popup_title.text = "选择%s" % SLOT_LABELS.get(slot, slot)
	_rebuild_popup_list(slot)
	_popup.visible = true
	if ui_root != null:
		ui_root.show_popup(_popup)


func _close_popup() -> void:
	if _popup == null:
		return
	if ui_root != null:
		ui_root.close_popup(_popup)
	elif _popup.get_parent() != null:
		_popup.get_parent().remove_child(_popup)
	_popup.visible = false
	_current_popup_slot = ""
	for child in _popup_list.get_children():
		child.queue_free()


func _rebuild_popup_list(slot: String) -> void:
	for child in _popup_list.get_children():
		child.queue_free()
	if GameRegistry.inventory_provider == null or GameRegistry.item_config == null:
		return
	var found := false
	var items: Array[ItemInstance] = GameRegistry.inventory_provider.get_items()
	for item in items:
		var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
		if String(config.get("type", "")) != slot:
			continue
		found = true
		var btn := Button.new()
		btn.theme_type_variation = &"HUDButton"
		btn.text = "%s  %s" % [String(config.get("name", str(item.item_id))), _format_stats(config.get("stats", {}))]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_popup_item_selected.bind(item.uid))
		_popup_list.add_child(btn)
	if not found:
		var label := Label.new()
		label.text = "背包中没有该槽位装备。"
		label.theme_type_variation = &"HUDMuted"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_popup_list.add_child(label)


func _on_popup_item_selected(item_uid: int) -> void:
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.equip_item(item_uid)
	_close_popup()
	_refresh_all()


# ---- Tooltip ----

func _show_equipment_tip(slot: String) -> void:
	if not visible or GameRegistry.equipment_data == null or GameRegistry.item_config == null:
		return
	var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot)
	var tip := _build_tip()
	if item_id == 0:
		_set_tip(tip, "%s槽" % SLOT_LABELS.get(slot, slot), "空装备槽", "当前没有穿戴装备。", "", "点击后从背包选择对应装备。")
	else:
		var config: Dictionary = GameRegistry.item_config.get_item(item_id)
		_set_tip(tip, String(config.get("name", "?")), TYPE_LABELS.get(String(config.get("type", "")), ""), String(config.get("description", "")), _format_stats(config.get("stats", {})), "点击卸下。")
	if ui_root != null:
		ui_root.show_tooltip(tip)


func _show_inventory_tip(index: int) -> void:
	if not visible or GameRegistry.item_config == null:
		return
	var items := _get_filtered_items()
	if index < 0 or index >= items.size():
		return
	var item: ItemInstance = items[index]
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	var hint := "点击选择。"
	if GameRegistry.item_config.get_equip_slot(item.item_id) != "":
		hint = "点击穿戴到当前角色。"
	var tip := _build_tip()
	var type_text: String = TYPE_LABELS.get(String(config.get("type", "")), "")
	if item.count > 1:
		type_text += "  x%d" % item.count
	_set_tip(tip, String(config.get("name", "?")), type_text, String(config.get("description", "")), _format_stats(config.get("stats", {})), hint)
	if ui_root != null:
		ui_root.show_tooltip(tip)


func _on_mouse_exited_tip() -> void:
	if ui_root != null:
		ui_root.hide_tooltip()


func _build_tip() -> PanelContainer:
	var tip := PanelContainer.new()
	tip.theme_type_variation = &"Tooltip"
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.custom_minimum_size = Vector2(240, 0)
	var margin := MarginContainer.new()
	margin.name = "TipMargin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	tip.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "TipVBox"
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	var title := Label.new()
	title.theme_type_variation = &"HUDTitle"
	title.add_theme_font_size_override("font_size", 17)
	title.name = "TipTitle"
	vbox.add_child(title)
	var type_l := Label.new()
	type_l.theme_type_variation = &"HUDMuted"
	type_l.name = "TipType"
	vbox.add_child(type_l)
	var desc_l := Label.new()
	desc_l.theme_type_variation = &"HUDValue"
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.name = "TipDesc"
	vbox.add_child(desc_l)
	var stats_l := Label.new()
	stats_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_l.add_theme_color_override("font_color", Color(0.64, 0.96, 0.55))
	stats_l.name = "TipStats"
	vbox.add_child(stats_l)
	var hint_l := Label.new()
	hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_l.add_theme_color_override("font_color", Color(0.66, 0.76, 0.92))
	hint_l.name = "TipHint"
	vbox.add_child(hint_l)
	return tip


func _set_tip(tip: PanelContainer, title: String, type_text: String, desc: String, stats: String, hint: String) -> void:
	var vbox := tip.get_node_or_null("TipMargin/TipVBox") as VBoxContainer
	if vbox == null:
		push_error("_set_tip: TipVBox not found in tip (tip=%s)" % [tip])
		return
	(vbox.get_node_or_null("TipTitle") as Label).text = title
	(vbox.get_node_or_null("TipType") as Label).text = type_text
	(vbox.get_node_or_null("TipDesc") as Label).text = desc
	(vbox.get_node_or_null("TipStats") as Label).text = "属性: %s" % stats if not stats.is_empty() else ""
	(vbox.get_node_or_null("TipHint") as Label).text = hint


func _position_tooltip() -> void:
	if ui_root == null or ui_root._tooltip == null or not is_instance_valid(ui_root._tooltip):
		return
	var tip: Control = ui_root._tooltip
	var viewport_size := get_viewport().get_visible_rect().size
	var desired_size := tip.get_combined_minimum_size()
	if desired_size.x <= 0.0:
		desired_size.x = 240.0
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(18, 18)
	if pos.x + desired_size.x > viewport_size.x:
		pos.x = mouse_pos.x - desired_size.x - 18
	if pos.y + desired_size.y > viewport_size.y:
		pos.y = mouse_pos.y - desired_size.y - 18
	pos.x = clampf(pos.x, 4.0, maxf(4.0, viewport_size.x - desired_size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, viewport_size.y - desired_size.y - 4.0))
	tip.position = pos


# ---- 数据信号 ----

func _connect_data_signals() -> void:
	if GameRegistry.character_stats != null:
		if not GameRegistry.character_stats.stats_changed.is_connected(_refresh_all):
			GameRegistry.character_stats.stats_changed.connect(_refresh_all)
	if GameRegistry.roster_data != null:
		if not GameRegistry.roster_data.active_character_changed.is_connected(_on_roster_changed):
			GameRegistry.roster_data.active_character_changed.connect(_on_roster_changed)
		if not GameRegistry.roster_data.character_progress_changed.is_connected(_on_roster_changed):
			GameRegistry.roster_data.character_progress_changed.connect(_on_roster_changed)
	if GameRegistry.inventory_provider != null:
		if not GameRegistry.inventory_provider.item_added.is_connected(_on_inventory_changed):
			GameRegistry.inventory_provider.item_added.connect(_on_inventory_changed)
		if not GameRegistry.inventory_provider.item_removed.is_connected(_on_inventory_changed):
			GameRegistry.inventory_provider.item_removed.connect(_on_inventory_changed)
		if not GameRegistry.inventory_provider.item_changed.is_connected(_on_inventory_changed):
			GameRegistry.inventory_provider.item_changed.connect(_on_inventory_changed)
	if GameRegistry.equipment_provider != null:
		if not GameRegistry.equipment_provider.equipped.is_connected(_on_equipment_changed):
			GameRegistry.equipment_provider.equipped.connect(_on_equipment_changed)
		if not GameRegistry.equipment_provider.unequipped.is_connected(_on_equipment_changed):
			GameRegistry.equipment_provider.unequipped.connect(_on_equipment_changed)


func _on_roster_changed(_id: int) -> void:
	_refresh_all()


func _on_inventory_changed(_item) -> void:
	_refresh_inventory_page()


func _on_equipment_changed(_slot: String = "", _item_id: int = 0) -> void:
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_refresh_all()


# ---- 辅助 ----

func _make_info_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme_type_variation = &"HUDValue"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(92, 28)
	return label


func _set_preview(sprite: AnimatedSprite2D, fallback: Label, character_id: int) -> void:
	var scene_path := ""
	if GameRegistry.character_config != null:
		scene_path = GameRegistry.character_config.get_scene_path(character_id)
	sprite.visible = false
	fallback.visible = true
	fallback.text = str(character_id)
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var src_sprite := instance.get_node_or_null("CharacterActionSet/AnimatedSprite2D") as AnimatedSprite2D
	if src_sprite != null and src_sprite.sprite_frames != null:
		sprite.sprite_frames = src_sprite.sprite_frames
		var anim := "idle"
		if not sprite.sprite_frames.has_animation(anim):
			var names := sprite.sprite_frames.get_animation_names()
			if not names.is_empty():
				anim = String(names[0])
		sprite.animation = anim
		sprite.frame = 0
		sprite.play()
		sprite.visible = true
		fallback.visible = false
	instance.queue_free()


func _get_active_character_id() -> int:
	if GameRegistry.roster_data != null:
		return int(GameRegistry.roster_data.active_character_id)
	return CharacterRosterData.DEFAULT_CHARACTER_ID


func _get_filtered_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	if GameRegistry.inventory_provider == null or GameRegistry.item_config == null:
		return result
	var items: Array[ItemInstance] = GameRegistry.inventory_provider.get_items()
	for item in items:
		var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
		var item_type: String = String(config.get("type", ""))
		if _inventory_filter == "all" or item_type == _inventory_filter:
			result.append(item)
	return result


func _short_name(value: String, max_len: int) -> String:
	if value.length() <= max_len:
		return value
	return value.substr(0, max_len)


func _format_stats(stats_value) -> String:
	if not stats_value is Dictionary:
		return ""
	var stats: Dictionary = stats_value
	if stats.is_empty():
		return ""
	var parts: PackedStringArray = []
	if stats.has("attack"):
		parts.append("攻击+%d" % int(stats["attack"]))
	if stats.has("defense"):
		parts.append("防御+%d" % int(stats["defense"]))
	if stats.has("max_hp"):
		parts.append("生命+%d" % int(stats["max_hp"]))
	if stats.has("move_speed"):
		parts.append("速度+%d" % int(stats["move_speed"]))
	return " ".join(parts)


func _load_item_icon(config: Dictionary) -> Texture2D:
	var icon_path := String(config.get("icon", ""))
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path) as Texture2D
