extends CanvasLayer
## Unified character and inventory panel.

const TAB_INFO := "info"
const TAB_SKILL := "skill"
const TAB_EQUIPMENT := "equipment"
const TAB_INVENTORY := "inventory"
const TAB_COSTUME := "costume"
const TAB_PET := "pet"

const INVENTORY_CAPACITY := 30
const INVENTORY_COLUMNS := 5
const SLOT_SIZE := Vector2(58, 58)

const SLOT_LABELS := {
	"weapon": "武器",
	"armor": "护甲",
	"necklace": "项链",
	"ring": "戒指",
	"boots": "靴子",
	"relic": "圣物",
	"mount": "坐骑",
	"artifact": "神器",
}

const TYPE_LABELS := {
	"all": "全部",
	"weapon": "武器",
	"armor": "护甲",
	"necklace": "项链",
	"ring": "戒指",
	"boots": "靴子",
	"relic": "圣物",
	"mount": "坐骑",
	"artifact": "神器",
	"consumable": "药水",
	"material": "材料",
}

const TYPE_COLORS := {
	"weapon": Color(0.72, 0.22, 0.18),
	"armor": Color(0.56, 0.38, 0.18),
	"boots": Color(0.28, 0.52, 0.30),
	"necklace": Color(0.55, 0.38, 0.74),
	"ring": Color(0.58, 0.28, 0.72),
	"relic": Color(0.70, 0.46, 0.18),
	"mount": Color(0.32, 0.48, 0.66),
	"artifact": Color(0.76, 0.58, 0.18),
	"consumable": Color(0.20, 0.50, 0.72),
	"material": Color(0.28, 0.62, 0.42),
	"empty": Color(0.20, 0.16, 0.10),
}

var _active_tab: String = TAB_EQUIPMENT
var _inventory_filter: String = "all"
var _selected_inventory_uid: int = 0
var _selected_inventory_index: int = -1
var _current_popup_slot: String = ""

var _panel: PanelContainer
var _title_label: Label
var _name_label: Label
var _stars_label: Label
var _level_label: Label
var _exp_label: Label
var _preview_holder: Control
var _preview_sprite: AnimatedSprite2D
var _preview_fallback: Label
var _hp_value: Label
var _atk_value: Label
var _def_value: Label
var _spd_value: Label
var _equipment_buttons: Dictionary = {}
var _locked_buttons: Array[Button] = []
var _category_buttons: Dictionary = {}
var _inventory_grid: GridContainer
var _inventory_buttons: Array[Button] = []
var _capacity_label: Label
var _selected_item_label: Label
var _tab_buttons: Dictionary = {}
var _right_title: Label
var _gm_info_label: Label
var _gm_level_spin: SpinBox
var _gm_set_button: Button
var _gm_max_button: Button
var _popup: PanelContainer
var _popup_title: Label
var _popup_list: VBoxContainer
var _item_tip_panel: PanelContainer
var _item_tip_title: Label
var _item_tip_type: Label
var _item_tip_desc: Label
var _item_tip_stats: Label
var _item_tip_hint: Label


func _ready() -> void:
	visible = false
	_rebuild_layout()
	_connect_data_signals()
	_refresh_all()


func _process(_delta: float) -> void:
	if visible and _item_tip_panel != null and _item_tip_panel.visible:
		_position_item_tip()


func toggle() -> void:
	if visible:
		close()
	else:
		open_equipment_tab()


func open_equipment_tab() -> void:
	open_tab(TAB_EQUIPMENT)


func open_inventory_tab() -> void:
	open_tab(TAB_INVENTORY)


func open_tab(tab_name: String) -> void:
	visible = true
	_active_tab = tab_name
	_hide_item_tip()
	_close_popup()
	_refresh_all()


func close() -> void:
	visible = false
	_hide_item_tip()
	_close_popup()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _popup != null and _popup.visible:
				_close_popup()
			else:
				close()
			get_viewport().set_input_as_handled()
		KEY_C:
			open_equipment_tab()
			get_viewport().set_input_as_handled()
		KEY_B:
			open_inventory_tab()
			get_viewport().set_input_as_handled()


func _connect_data_signals() -> void:
	if GameRegistry.character_stats != null:
		GameRegistry.character_stats.stats_changed.connect(_refresh_stats)
	if GameRegistry.roster_data != null:
		GameRegistry.roster_data.active_character_changed.connect(func(_id: int) -> void: _refresh_all())
		GameRegistry.roster_data.character_progress_changed.connect(func(_id: int) -> void: _refresh_all())
	if GameRegistry.inventory_provider != null:
		GameRegistry.inventory_provider.item_added.connect(func(_item: ItemInstance) -> void: _refresh_inventory())
		GameRegistry.inventory_provider.item_removed.connect(func(_uid: int) -> void: _refresh_inventory())
		GameRegistry.inventory_provider.item_changed.connect(func(_item: ItemInstance) -> void: _refresh_inventory())
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.equipped.connect(_on_equipment_changed)
		GameRegistry.equipment_provider.unequipped.connect(_on_equipment_changed)


func _rebuild_layout() -> void:
	for child in get_children():
		child.queue_free()

	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.015, 0.01, 0.64)
	add_child(overlay)

	_panel = PanelContainer.new()
	_panel.name = "HeroInventoryWindow"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -480.0
	_panel.offset_top = -300.0
	_panel.offset_right = 480.0
	_panel.offset_bottom = 300.0
	_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.30, 0.20, 0.10), Color(0.70, 0.48, 0.18), 4, 8))
	add_child(_panel)

	var root_margin := MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 14)
	root_margin.add_theme_constant_override("margin_top", 8)
	root_margin.add_theme_constant_override("margin_right", 14)
	root_margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(root_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	root_margin.add_child(root_vbox)

	root_vbox.add_child(_build_header())
	root_vbox.add_child(_build_main_body())
	root_vbox.add_child(_build_bottom_tabs())
	_build_popup()
	_build_item_tip()


func _build_header() -> Control:
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 42)
	header.add_theme_stylebox_override("panel", _make_panel_style(Color(0.18, 0.28, 0.12), Color(0.50, 0.36, 0.14), 3, 8))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	header.add_child(row)

	_title_label = Label.new()
	_title_label.text = "角色"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34))
	row.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(38, 32)
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	return header


func _build_main_body() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body.add_child(_build_left_panel())
	body.add_child(_build_right_panel())
	return body


func _build_left_panel() -> Control:
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_stylebox_override("panel", _make_panel_style(Color(0.50, 0.43, 0.27), Color(0.30, 0.18, 0.08), 2, 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	left.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color(0.18, 0.08, 0.02))
	vbox.add_child(_name_label)

	_stars_label = Label.new()
	_stars_label.text = "★★★★☆"
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stars_label.add_theme_font_size_override("font_size", 20)
	_stars_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.14))
	vbox.add_child(_stars_label)

	vbox.add_child(_build_character_stage())
	vbox.add_child(_build_stats_bar())
	vbox.add_child(_build_gm_debug_section())
	return left


func _build_character_stage() -> Control:
	var holder := HBoxContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 8)

	var left_slots := VBoxContainer.new()
	left_slots.add_theme_constant_override("separation", 6)
	holder.add_child(left_slots)
	left_slots.add_child(_make_equipment_button("weapon"))
	left_slots.add_child(_make_equipment_button("armor"))
	left_slots.add_child(_make_equipment_button("necklace"))
	left_slots.add_child(_make_equipment_button("ring"))

	_preview_holder = PanelContainer.new()
	_preview_holder.custom_minimum_size = Vector2(220, 250)
	_preview_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_holder.add_theme_stylebox_override("panel", _make_panel_style(Color(0.38, 0.52, 0.38, 0.65), Color(0.24, 0.16, 0.08), 2, 8))
	holder.add_child(_preview_holder)

	var preview_layer := Control.new()
	preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_holder.add_child(preview_layer)
	_preview_sprite = AnimatedSprite2D.new()
	_preview_sprite.position = Vector2(110, 188)
	_preview_sprite.scale = Vector2(1.55, 1.55)
	preview_layer.add_child(_preview_sprite)

	_preview_fallback = Label.new()
	_preview_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_fallback.add_theme_font_size_override("font_size", 22)
	preview_layer.add_child(_preview_fallback)

	var right_slots := VBoxContainer.new()
	right_slots.add_theme_constant_override("separation", 6)
	holder.add_child(right_slots)
	right_slots.add_child(_make_equipment_button("boots"))
	right_slots.add_child(_make_equipment_button("relic"))
	right_slots.add_child(_make_equipment_button("mount"))
	right_slots.add_child(_make_equipment_button("artifact"))
	return holder


func _make_equipment_button(slot: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.text = SLOT_LABELS.get(slot, slot)
	btn.tooltip_text = "点击穿戴或卸下。"
	btn.pressed.connect(_on_equipment_slot_pressed.bind(slot))
	btn.mouse_entered.connect(_show_equipment_tip.bind(slot))
	btn.mouse_exited.connect(_hide_item_tip)
	_equipment_buttons[slot] = btn
	return btn


func _make_locked_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.disabled = true
	btn.text = "%s\n锁定" % label_text
	_locked_buttons.append(btn)
	return btn


func _build_stats_bar() -> Control:
	var stats_panel := PanelContainer.new()
	stats_panel.custom_minimum_size = Vector2(0, 50)
	stats_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.78, 0.64, 0.36), Color(0.35, 0.20, 0.08), 2, 6))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	stats_panel.add_child(row)
	_hp_value = _make_stat_label("生命 0/0")
	_atk_value = _make_stat_label("攻击 0")
	_def_value = _make_stat_label("防御 0")
	_spd_value = _make_stat_label("速度 0")
	row.add_child(_hp_value)
	row.add_child(_atk_value)
	row.add_child(_def_value)
	row.add_child(_spd_value)
	return stats_panel


func _make_stat_label(text_value: String) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(92, 30)
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.12, 0.06, 0.02))
	return label


func _build_gm_debug_section() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, 58)
	box.add_theme_stylebox_override("panel", _make_panel_style(Color(0.34, 0.22, 0.12), Color(0.63, 0.44, 0.18), 1, 5))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	box.add_child(vbox)

	_gm_info_label = Label.new()
	_gm_info_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.62))
	vbox.add_child(_gm_info_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vbox.add_child(row)
	_gm_level_spin = SpinBox.new()
	_gm_level_spin.min_value = 1
	_gm_level_spin.max_value = 99
	_gm_level_spin.step = 1
	_gm_level_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_gm_level_spin)
	_gm_set_button = Button.new()
	_gm_set_button.text = "设等级"
	_gm_set_button.pressed.connect(_on_gm_set_level_pressed)
	row.add_child(_gm_set_button)
	_gm_max_button = Button.new()
	_gm_max_button.text = "满级"
	_gm_max_button.pressed.connect(_on_gm_max_level_pressed)
	row.add_child(_gm_max_button)
	return box


func _build_right_panel() -> Control:
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(480, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", _make_panel_style(Color(0.35, 0.22, 0.10), Color(0.70, 0.48, 0.18), 3, 8))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	right.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_right_title = Label.new()
	_right_title.text = "背包"
	_right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_title.add_theme_font_size_override("font_size", 18)
	_right_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.46))
	vbox.add_child(_right_title)
	vbox.add_child(_build_categories())

	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = INVENTORY_COLUMNS
	_inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override("h_separation", 5)
	_inventory_grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(_inventory_grid)
	for i in range(INVENTORY_CAPACITY):
		var btn := Button.new()
		btn.custom_minimum_size = SLOT_SIZE
		btn.toggle_mode = true
		btn.text = ""
		btn.pressed.connect(_on_inventory_slot_pressed.bind(i))
		btn.mouse_entered.connect(_show_inventory_tip.bind(i))
		btn.mouse_exited.connect(_hide_item_tip)
		_inventory_grid.add_child(btn)
		_inventory_buttons.append(btn)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)
	_selected_item_label = Label.new()
	_selected_item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_item_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.62))
	footer.add_child(_selected_item_label)
	_capacity_label = Label.new()
	_capacity_label.custom_minimum_size = Vector2(86, 28)
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capacity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_capacity_label)
	return right


func _build_categories() -> Control:
	var row := GridContainer.new()
	row.columns = 6
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	for type_name in ["all", "weapon", "armor", "necklace", "ring", "boots", "relic", "mount", "artifact", "consumable", "material"]:
		var btn := Button.new()
		btn.text = TYPE_LABELS.get(type_name, type_name)
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(64, 34)
		btn.pressed.connect(_on_category_pressed.bind(type_name))
		row.add_child(btn)
		_category_buttons[type_name] = btn
	return row


func _build_bottom_tabs() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 50)
	row.add_theme_constant_override("separation", 6)
	var tabs := [
		[TAB_INFO, "信息"],
		[TAB_SKILL, "技能"],
		[TAB_EQUIPMENT, "装备"],
		[TAB_INVENTORY, "背包"],
		[TAB_COSTUME, "时装"],
		[TAB_PET, "宠物"],
	]
	for tab_data in tabs:
		var tab_name: String = String(tab_data[0])
		var label_text: String = String(tab_data[1])
		var btn := Button.new()
		btn.text = label_text
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(120, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_tab_pressed.bind(tab_name))
		row.add_child(btn)
		_tab_buttons[tab_name] = btn
	return row


func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.name = "EquipSelectPopup"
	_popup.visible = false
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.offset_left = -180.0
	_popup.offset_top = -150.0
	_popup.offset_right = 180.0
	_popup.offset_bottom = 150.0
	_popup.add_theme_stylebox_override("panel", _make_panel_style(Color(0.25, 0.16, 0.08), Color(0.84, 0.58, 0.22), 3, 8))
	add_child(_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	_popup_title = Label.new()
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.46))
	vbox.add_child(_popup_title)
	_popup_list = VBoxContainer.new()
	_popup_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_popup_list)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)


func _build_item_tip() -> void:
	_item_tip_panel = PanelContainer.new()
	_item_tip_panel.name = "ItemTipPanel"
	_item_tip_panel.visible = false
	_item_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_tip_panel.custom_minimum_size = Vector2(250, 0)
	_item_tip_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.12, 0.075, 0.035, 0.96), Color(0.88, 0.62, 0.24), 2, 6))
	add_child(_item_tip_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_item_tip_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	_item_tip_title = Label.new()
	_item_tip_title.add_theme_font_size_override("font_size", 17)
	_item_tip_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.38))
	vbox.add_child(_item_tip_title)

	_item_tip_type = Label.new()
	_item_tip_type.add_theme_color_override("font_color", Color(0.74, 0.62, 0.42))
	vbox.add_child(_item_tip_type)

	_item_tip_desc = Label.new()
	_item_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_tip_desc.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	vbox.add_child(_item_tip_desc)

	_item_tip_stats = Label.new()
	_item_tip_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_tip_stats.add_theme_color_override("font_color", Color(0.64, 0.96, 0.55))
	vbox.add_child(_item_tip_stats)

	_item_tip_hint = Label.new()
	_item_tip_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_tip_hint.add_theme_color_override("font_color", Color(0.66, 0.76, 0.92))
	vbox.add_child(_item_tip_hint)


func _make_panel_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style


func _on_tab_pressed(tab_name: String) -> void:
	_active_tab = tab_name
	_hide_item_tip()
	_close_popup()
	_refresh_tab_state()


func _on_category_pressed(type_name: String) -> void:
	_inventory_filter = type_name
	_selected_inventory_uid = 0
	_selected_inventory_index = -1
	_hide_item_tip()
	_refresh_inventory()


func _on_equipment_slot_pressed(slot: String) -> void:
	if GameRegistry.equipment_data == null:
		return
	var equipped_uid: int = GameRegistry.equipment_data.get_equipped_uid(slot)
	if equipped_uid != 0:
		if GameRegistry.equipment_provider != null:
			GameRegistry.equipment_provider.unequip_slot(slot)
		return
	_open_equip_popup(slot)


func _on_inventory_slot_pressed(index: int) -> void:
	var items := _get_filtered_items()
	if index < 0 or index >= items.size():
		return
	var item: ItemInstance = items[index]
	_selected_inventory_uid = item.uid
	_selected_inventory_index = index
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	var item_type: String = String(config.get("type", ""))
	if GameRegistry.item_config.get_equip_slot(item.item_id) != "" and GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.equip_item(item.uid)
		_selected_inventory_uid = 0
		_selected_inventory_index = -1
	else:
		_refresh_inventory()


func _on_equipment_changed(_slot: String = "", _item_id: int = 0) -> void:
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_refresh_all()


func _open_equip_popup(slot: String) -> void:
	_hide_item_tip()
	_current_popup_slot = slot
	_popup_title.text = "选择%s" % SLOT_LABELS.get(slot, slot)
	_rebuild_popup_list(slot)
	_popup.visible = true


func _close_popup() -> void:
	if _popup == null:
		return
	_popup.visible = false
	_current_popup_slot = ""
	for child in _popup_list.get_children():
		child.queue_free()


func _rebuild_popup_list(slot: String) -> void:
	for child in _popup_list.get_children():
		child.queue_free()
	var found := false
	if GameRegistry.inventory_provider == null or GameRegistry.item_config == null:
		return
	var items: Array[ItemInstance] = GameRegistry.inventory_provider.get_items()
	for item in items:
		var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
		if String(config.get("type", "")) != slot:
			continue
		found = true
		var btn := Button.new()
		btn.text = "%s  %s" % [String(config.get("name", str(item.item_id))), _format_stats(config.get("stats", {}))]
		btn.pressed.connect(_on_popup_item_selected.bind(item.uid))
		_popup_list.add_child(btn)
	if not found:
		var label := Label.new()
		label.text = "背包中没有该槽位装备。"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_popup_list.add_child(label)


func _on_popup_item_selected(item_uid: int) -> void:
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.equip_item(item_uid)
	_close_popup()


func _refresh_all() -> void:
	_hide_item_tip()
	_refresh_character_header()
	_refresh_preview()
	_refresh_stats()
	_refresh_equipment()
	_refresh_inventory()
	_refresh_gm_debug()
	_refresh_tab_state()


func _refresh_character_header() -> void:
	var character_id := _get_active_character_id()
	var character_name := str(character_id)
	if GameRegistry.character_config != null:
		character_name = GameRegistry.character_config.get_name(character_id)
	_name_label.text = character_name
	var level := 1
	var exp := 0
	if GameRegistry.roster_data != null:
		level = GameRegistry.roster_data.get_level(character_id)
		exp = GameRegistry.roster_data.get_exp(character_id)
	_level_label = null
	_exp_label = null
	_title_label.text = "角色"
	_stars_label.text = "等级%d   经验:%d   ★★★★☆" % [level, exp]


func _refresh_preview() -> void:
	var character_id := _get_active_character_id()
	var scene_path := ""
	if GameRegistry.character_config != null:
		scene_path = GameRegistry.character_config.get_scene_path(character_id)
	_preview_sprite.visible = false
	_preview_fallback.visible = true
	_preview_fallback.text = str(character_id)
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var sprite := instance.get_node_or_null("CharacterActionSet/AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null:
		_preview_sprite.sprite_frames = sprite.sprite_frames
		var anim := "idle"
		if not _preview_sprite.sprite_frames.has_animation(anim):
			var names := _preview_sprite.sprite_frames.get_animation_names()
			if not names.is_empty():
				anim = String(names[0])
		_preview_sprite.animation = anim
		_preview_sprite.frame = 0
		_preview_sprite.play()
		_preview_sprite.visible = true
		_preview_fallback.visible = false
	instance.queue_free()


func _refresh_stats() -> void:
	if GameRegistry.character_stats == null or _hp_value == null:
		return
	var stats = GameRegistry.character_stats
	_hp_value.text = "生命 %d/%d" % [stats.hp, stats.max_hp]
	_atk_value.text = "攻击 %d" % stats.attack
	_def_value.text = "防御 %d" % stats.defense
	_spd_value.text = "速度 %d" % int(stats.move_speed)


func _refresh_equipment() -> void:
	_hide_item_tip()
	if GameRegistry.equipment_data == null or GameRegistry.item_config == null:
		return
	for slot in EquipmentData.SLOTS:
		var btn: Button = _equipment_buttons.get(slot)
		if btn == null:
			continue
		var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot)
		if item_id == 0:
			btn.text = "%s\n空" % SLOT_LABELS.get(slot, slot)
			btn.icon = null
			btn.tooltip_text = "点击从背包选择。"
			btn.add_theme_color_override("font_color", Color(0.88, 0.76, 0.56))
		else:
			var config: Dictionary = GameRegistry.item_config.get_item(item_id)
			btn.text = "%s\n%s" % [SLOT_LABELS.get(slot, slot), _short_name(String(config.get("name", str(item_id))), 7)]
			btn.icon = _load_item_icon(config)
			btn.tooltip_text = "%s\n%s" % [String(config.get("description", "")), _format_stats(config.get("stats", {}))]
			btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))


func _refresh_inventory() -> void:
	_hide_item_tip()
	if _inventory_grid == null:
		return
	for type_name in _category_buttons:
		var btn: Button = _category_buttons[type_name]
		btn.button_pressed = String(type_name) == _inventory_filter
	var items := _get_filtered_items()
	var total_count := 0
	if GameRegistry.inventory_provider != null:
		total_count = GameRegistry.inventory_provider.get_items().size()
	for i in range(_inventory_buttons.size()):
		var btn := _inventory_buttons[i]
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
			btn.add_theme_stylebox_override("normal", _make_slot_style(item_type, false))
			btn.add_theme_stylebox_override("pressed", _make_slot_style(item_type, true))
			btn.add_theme_stylebox_override("hover", _make_slot_style(item_type, true))
		else:
			btn.disabled = true
			btn.text = ""
			btn.icon = null
			btn.tooltip_text = ""
			btn.add_theme_stylebox_override("normal", _make_slot_style("empty", false))
			btn.add_theme_stylebox_override("pressed", _make_slot_style("empty", false))
			btn.add_theme_stylebox_override("hover", _make_slot_style("empty", true))
	if _capacity_label != null:
		_capacity_label.text = "%d/%d" % [total_count, INVENTORY_CAPACITY]
	_refresh_selected_item_text(items)


func _refresh_selected_item_text(items: Array[ItemInstance]) -> void:
	if _selected_item_label == null:
		return
	if _selected_inventory_index < 0 or _selected_inventory_index >= items.size():
		_selected_item_label.text = "选择物品。点击装备会直接穿到当前角色。"
		return
	var item: ItemInstance = items[_selected_inventory_index]
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	_selected_item_label.text = "%s  %s" % [
		String(config.get("name", str(item.item_id))),
		_format_stats(config.get("stats", {})),
	]


func _refresh_gm_debug() -> void:
	if _gm_info_label == null or GameRegistry.roster_data == null:
		return
	var character_id: int = _get_active_character_id()
	var level: int = GameRegistry.roster_data.get_level(character_id)
	var exp: int = GameRegistry.roster_data.get_exp(character_id)
	var max_level := 99
	var character_name := str(character_id)
	if GameRegistry.character_config != null:
		max_level = GameRegistry.character_config.get_max_level(character_id)
		character_name = GameRegistry.character_config.get_name(character_id)
	_gm_info_label.text = "%s (%d)  等级%d  经验:%d" % [character_name, character_id, level, exp]
	_gm_level_spin.max_value = max_level
	_gm_level_spin.value = level


func _refresh_tab_state() -> void:
	for tab_name in _tab_buttons:
		var btn: Button = _tab_buttons[tab_name]
		btn.button_pressed = String(tab_name) == _active_tab
	if _right_title == null:
		return
	match _active_tab:
		TAB_INFO:
			_right_title.text = "信息"
			_selected_item_label.text = "角色基础信息显示在左侧。"
		TAB_SKILL:
			_right_title.text = "技能"
			_selected_item_label.text = "技能页预留，下一步接技能展示。"
		TAB_EQUIPMENT:
			_right_title.text = "装备"
			_selected_item_label.text = "点击左侧装备槽，或点击背包装备直接穿戴。"
		TAB_INVENTORY:
			_right_title.text = "背包"
			_refresh_inventory()
		TAB_COSTUME:
			_right_title.text = "时装"
			_selected_item_label.text = "时装页预留。"
		TAB_PET:
			_right_title.text = "宠物"
			_selected_item_label.text = "宠物页预留。"


func _on_gm_set_level_pressed() -> void:
	if GameRegistry.roster_data == null:
		return
	GameRegistry.roster_data.set_level(int(_gm_level_spin.value))
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_refresh_all()


func _on_gm_max_level_pressed() -> void:
	if GameRegistry.roster_data == null or GameRegistry.character_config == null:
		return
	var character_id: int = _get_active_character_id()
	GameRegistry.roster_data.set_level(GameRegistry.character_config.get_max_level(character_id), character_id)
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.refresh_current_stats()
	_refresh_all()


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


func _show_equipment_tip(slot: String) -> void:
	if GameRegistry.equipment_data == null or GameRegistry.item_config == null:
		return
	var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot)
	if item_id == 0:
		_show_slot_tip(slot)
		return
	var config: Dictionary = GameRegistry.item_config.get_item(item_id)
	_show_item_tip(config, 1, "点击卸下。")


func _show_inventory_tip(index: int) -> void:
	if GameRegistry.item_config == null:
		return
	var items := _get_filtered_items()
	if index < 0 or index >= items.size():
		return
	var item: ItemInstance = items[index]
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	var hint := "点击选择。"
	if GameRegistry.item_config.get_equip_slot(item.item_id) != "":
		hint = "点击穿戴到当前角色。"
	_show_item_tip(config, item.count, hint)


func _show_slot_tip(slot: String) -> void:
	if _item_tip_panel == null:
		return
	_item_tip_title.text = "%s槽" % SLOT_LABELS.get(slot, slot)
	_item_tip_type.text = "空装备槽"
	_item_tip_desc.text = "当前没有穿戴装备。"
	_item_tip_stats.text = ""
	_item_tip_hint.text = "点击后从背包选择对应装备。"
	_item_tip_panel.visible = true
	_position_item_tip()


func _show_item_tip(config: Dictionary, count: int, hint: String) -> void:
	if _item_tip_panel == null or config.is_empty():
		return
	var item_type := String(config.get("type", ""))
	var slot : String = GameRegistry.item_config.get_equip_slot(int(config.get("id", 0))) if GameRegistry.item_config != null else ""
	_item_tip_title.text = String(config.get("name", "?"))
	_item_tip_type.text = "%s%s" % [
		TYPE_LABELS.get(item_type, item_type),
		"  x%d" % count if count > 1 else ""
	]
	if not slot.is_empty():
		_item_tip_type.text += "  槽位:%s" % SLOT_LABELS.get(slot, slot)
	_item_tip_desc.text = String(config.get("description", ""))
	var stats_text := _format_stats(config.get("stats", {}))
	_item_tip_stats.text = "属性: %s" % stats_text if not stats_text.is_empty() else ""
	_item_tip_hint.text = hint
	_item_tip_panel.visible = true
	_position_item_tip()


func _hide_item_tip() -> void:
	if _item_tip_panel != null:
		_item_tip_panel.visible = false


func _position_item_tip() -> void:
	if _item_tip_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var desired_size := _item_tip_panel.get_combined_minimum_size()
	if desired_size.x <= 0.0:
		desired_size.x = 250.0
	var mouse_pos := get_viewport().get_mouse_position()
	var pos := mouse_pos + Vector2(18, 18)
	if pos.x + desired_size.x > viewport_size.x:
		pos.x = mouse_pos.x - desired_size.x - 18
	if pos.y + desired_size.y > viewport_size.y:
		pos.y = mouse_pos.y - desired_size.y - 18
	pos.x = clampf(pos.x, 4.0, maxf(4.0, viewport_size.x - desired_size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, viewport_size.y - desired_size.y - 4.0))
	_item_tip_panel.position = pos


func _get_active_character_id() -> int:
	if GameRegistry.roster_data != null:
		return int(GameRegistry.roster_data.active_character_id)
	return CharacterRosterData.DEFAULT_CHARACTER_ID


func _make_slot_style(item_type: String, selected: bool) -> StyleBoxFlat:
	var base: Color = TYPE_COLORS.get(item_type, TYPE_COLORS["empty"])
	var bg := base.darkened(0.35)
	var border := base.lightened(0.25)
	if selected:
		border = Color(1.0, 0.86, 0.28)
	return _make_panel_style(bg, border, 3 if selected else 2, 5)


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
