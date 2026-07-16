@tool
extends Window

## Buff 配置编辑器。可视化编辑 res://data/buffs.json。

const CONFIG_PATH := "res://data/buffs.json"
const BuffEffectRegistry = preload("res://scripts/combat/buff_effect_registry.gd")

const CATEGORY_OPTIONS := {"buff": "增益", "debuff": "减益"}
const STACK_BEHAVIOR_OPTIONS := {"stack": "叠层", "refresh": "刷新", "independent": "独立"}

var _buffs: Dictionary = {}
var _selected_id: int = 0
var _loading := false

var _buff_list: ItemList
var _name_edit: LineEdit
var _desc_edit: TextEdit
var _category_option: OptionButton
var _duration_spin: SpinBox
var _max_stacks_spin: SpinBox
var _stack_behavior_option: OptionButton
var _icon_edit: LineEdit
var _effect_scene_edit: LineEdit
var _effects_container: VBoxContainer
var _status_label: Label

# 左右分隔拖动条
var _left_panel: VBoxContainer
var _divider: Control
var _dragging := false
const _LEFT_MIN_WIDTH := 150.0
const _LEFT_MAX_WIDTH := 560.0


func _ready() -> void:
	title = "Buff 配置编辑器"
	size = Vector2i(1100, 720)
	close_requested.connect(hide)
	_load_config()
	_build_layout()
	_refresh_buff_list()


func open_editor() -> void:
	_load_config()
	_refresh_buff_list()
	popup_centered()


# ---- 左右分隔条拖动 ----

func _on_divider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		return
	if event is InputEventMouseMotion:
		var left_x: float = _left_panel.global_position.x
		var new_width: float = event.global_position.x - left_x
		new_width = clampf(new_width, _LEFT_MIN_WIDTH, _LEFT_MAX_WIDTH)
		_left_panel.custom_minimum_size = Vector2(new_width, 0)


# ---- 数据加载 ----

func _load_config() -> void:
	_buffs.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Buff 配置解析失败: %s" % json.get_error_message())
		return
	var data := json.data as Dictionary
	for id_str in data:
		_buffs[int(id_str)] = (data[id_str] as Dictionary).duplicate(true)


# ---- 布局 ----

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()
	# 整体竖向布局：顶部主内容区 + 底部状态栏
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 主内容区（左列表 + 右表单）占满剩余空间
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)

	# 左侧 buff 列表
	_left_panel = VBoxContainer.new()
	_left_panel.custom_minimum_size = Vector2(240, 0)
	_left_panel.add_theme_constant_override("separation", 4)
	main.add_child(_left_panel)

	var list_label := Label.new()
	list_label.text = "Buff 列表"
	_left_panel.add_child(list_label)

	_buff_list = ItemList.new()
	_buff_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_buff_list.item_selected.connect(_on_buff_selected)
	_left_panel.add_child(_buff_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	_left_panel.add_child(btn_row)

	var add_btn := Button.new()
	add_btn.text = "新增"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_add_buff)
	btn_row.add_child(add_btn)

	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.pressed.connect(_on_delete_buff)
	btn_row.add_child(del_btn)

	# 可拖动分隔条：鼠标悬停变为左右伸缩标识，拖动调整左框宽度
	_divider = Panel.new()
	_divider.custom_minimum_size = Vector2(6, 0)
	_divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_divider.set_default_cursor_shape(Control.CURSOR_HSIZE)
	_divider.gui_input.connect(_on_divider_gui_input)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.5, 0.5, 0.5, 0.35)
	sep_style.set_content_margin_all(0)
	_divider.add_theme_stylebox_override("panel", sep_style)
	main.add_child(_divider)

	# 右侧编辑面板
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	main.add_child(right)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	# 基本信息
	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 6)
	info_grid.add_theme_constant_override("v_separation", 4)
	content.add_child(info_grid)

	_name_edit = _add_grid_edit(info_grid, "名称")
	_name_edit.text_changed.connect(_on_field_changed.bind("name"))

	_category_option = _add_grid_option(info_grid, "类别", CATEGORY_OPTIONS)
	_category_option.item_selected.connect(_on_option_changed.bind("category"))

	_duration_spin = _add_grid_spin(info_grid, "持续时间", 0.0, 9999.0, 0.5)
	_duration_spin.value_changed.connect(_on_spin_changed.bind("duration"))

	_max_stacks_spin = _add_grid_spin(info_grid, "最大层数", 1.0, 999.0, 1.0)
	_max_stacks_spin.value_changed.connect(_on_spin_changed.bind("max_stacks"))

	_stack_behavior_option = _add_grid_option(info_grid, "叠加方式", STACK_BEHAVIOR_OPTIONS)
	_stack_behavior_option.item_selected.connect(_on_option_changed.bind("stack_behavior"))

	_icon_edit = _add_grid_edit(info_grid, "图标路径", PackedStringArray(["*.png ; PNG 图片", "*.jpg ; JPG 图片", "*.svg ; SVG 矢量图", "*.webp ; WebP 图片"]))
	_icon_edit.text_changed.connect(_on_field_changed.bind("icon"))

	_effect_scene_edit = _add_grid_edit(info_grid, "特效场景", PackedStringArray(["*.tscn ; 场景文件", "*.scn ; 场景文件"]))
	_effect_scene_edit.text_changed.connect(_on_field_changed.bind("effect_scene"))

	# 描述
	var desc_label := Label.new()
	desc_label.text = "描述"
	content.add_child(desc_label)

	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 44)
	_desc_edit.text_changed.connect(_on_desc_changed)
	content.add_child(_desc_edit)

	# 效果列表
	var effects_header := HBoxContainer.new()
	effects_header.add_theme_constant_override("separation", 6)
	content.add_child(effects_header)

	var effects_label := Label.new()
	effects_label.text = "效果列表"
	effects_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effects_header.add_child(effects_label)

	var add_effect_btn := Button.new()
	add_effect_btn.text = "添加效果"
	add_effect_btn.pressed.connect(_on_add_effect)
	effects_header.add_child(add_effect_btn)

	_effects_container = VBoxContainer.new()
	_effects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_container.add_theme_constant_override("separation", 4)
	content.add_child(_effects_container)

	# 底部状态 + 保存（作为 root 的最后一个子项，自然位于底部）
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status_label)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(100, 32)
	save_btn.pressed.connect(_on_save)
	bottom.add_child(save_btn)


func _add_grid_edit(parent: GridContainer, label_text: String, browse_filters: PackedStringArray = []) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(220, 0)
	if not browse_filters.is_empty():
		# 第二列：输入框 + 浏览按钮，合成 HBox 保持 grid 两列结构
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 4)
		hbox.add_child(edit)
		var btn := Button.new()
		btn.text = "浏览"
		btn.custom_minimum_size = Vector2(60, 0)
		btn.tooltip_text = "打开项目资源选择框"
		btn.pressed.connect(_on_browse_resource.bind(edit, browse_filters))
		hbox.add_child(btn)
		parent.add_child(hbox)
	else:
		parent.add_child(edit)
	return edit


# 打开 Godot 项目资源选择对话框（EditorFileDialog）。
# 选中后把 res:// 路径回填到 LineEdit，触发 text_changed 同步数据。
func _on_browse_resource(edit: LineEdit, filters: PackedStringArray) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.filters = filters
	# 定位到当前路径所在目录
	var current := edit.text.strip_edges()
	if current.begins_with("res://"):
		dialog.current_dir = current.get_base_dir()
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		edit.text = path
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_clamped(Vector2i(900, 600))


func _add_grid_spin(parent: GridContainer, label_text: String, min_val: float, max_val: float, step_val: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.allow_greater = true
	spin.allow_lesser = true
	parent.add_child(spin)
	return spin


func _add_grid_option(parent: GridContainer, label_text: String, options: Dictionary) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	var idx := 0
	for key in options:
		option.add_item("%s - %s" % [key, options[key]], idx)
		option.set_item_metadata(idx, key)
		idx += 1
	parent.add_child(option)
	return option


# ---- 列表刷新 ----

func _refresh_buff_list() -> void:
	_buff_list.clear()
	var sorted_ids: Array = _buffs.keys()
	sorted_ids.sort()
	for buff_id in sorted_ids:
		var buff: Dictionary = _buffs[buff_id]
		var name_str := String(buff.get("name", ""))
		var category := String(buff.get("category", "debuff"))
		var prefix := "[增]" if category == "buff" else "[减]"
		_buff_list.add_item("%s %d %s" % [prefix, buff_id, name_str])
		_buff_list.set_item_metadata(_buff_list.item_count - 1, buff_id)
	if _selected_id > 0:
		for i in range(_buff_list.item_count):
			if int(_buff_list.get_item_metadata(i)) == _selected_id:
				_buff_list.select(i)
				break
	elif _buff_list.item_count > 0:
		_buff_list.select(0)
		_on_buff_selected(0)


func _on_buff_selected(index: int) -> void:
	var buff_id := int(_buff_list.get_item_metadata(index))
	_selected_id = buff_id
	_show_buff_details(buff_id)


func _show_buff_details(buff_id: int) -> void:
	_loading = true
	var buff: Dictionary = _buffs.get(buff_id, {})
	if buff.is_empty():
		_loading = false
		return
	_name_edit.text = String(buff.get("name", ""))
	_desc_edit.text = String(buff.get("description", ""))
	_category_option.select(_option_index_for_key(_category_option, String(buff.get("category", "debuff"))))
	_duration_spin.value = float(buff.get("duration", 0.0))
	_max_stacks_spin.value = int(buff.get("max_stacks", 1))
	_stack_behavior_option.select(_option_index_for_key(_stack_behavior_option, String(buff.get("stack_behavior", "refresh"))))
	_icon_edit.text = String(buff.get("icon", ""))
	_effect_scene_edit.text = String(buff.get("effect_scene", ""))
	_refresh_effects(buff.get("effects", []))
	_loading = false


func _option_index_for_key(option: OptionButton, key: String) -> int:
	for i in range(option.item_count):
		if String(option.get_item_metadata(i)) == key:
			return i
	return 0


# ---- 效果列表 ----

func _refresh_effects(effects: Array) -> void:
	for child in _effects_container.get_children():
		child.queue_free()
	for effect in effects:
		if effect is Dictionary:
			_effects_container.add_child(_make_effect_row(effect))


func _make_effect_row(effect: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.set_meta("effect", effect)

	var type_option := OptionButton.new()
	var idx := 0
	for type_key in BuffEffectRegistry.get_all_types():
		var info := BuffEffectRegistry.get_type_info(String(type_key))
		type_option.add_item("%s - %s" % [type_key, info.get("label", type_key)], idx)
		type_option.set_item_metadata(idx, type_key)
		idx += 1
	type_option.select(_effect_type_index(String(effect.get("type", ""))))
	type_option.item_selected.connect(_on_effect_type_changed.bind(row))
	type_option.custom_minimum_size = Vector2(140, 0)
	row.add_child(type_option)

	var fields_container := HBoxContainer.new()
	fields_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_container.add_theme_constant_override("separation", 4)
	fields_container.name = "FieldsContainer"
	row.add_child(fields_container)

	_populate_effect_fields(fields_container, effect)

	var del_btn := Button.new()
	del_btn.text = "×"
	del_btn.custom_minimum_size = Vector2(28, 28)
	del_btn.pressed.connect(_on_delete_effect.bind(row))
	row.add_child(del_btn)

	return row


func _effect_type_index(type_str: String) -> int:
	var all_types: Array = BuffEffectRegistry.get_all_types()
	for i in range(all_types.size()):
		if String(all_types[i]) == type_str:
			return i
	return 0


func _populate_effect_fields(container: HBoxContainer, effect: Dictionary) -> void:
	for child in container.get_children():
		child.queue_free()
	var type_str := String(effect.get("type", ""))
	var info := BuffEffectRegistry.get_type_info(type_str)
	for field in info.get("fields", []):
		var fname := String(field.get("name", ""))
		var flabel := String(field.get("label", fname))
		var kind := String(field.get("kind", ""))
		match kind:
			"option":
				var options: Array = field.get("options", [])
				_add_field_option(container, flabel, options, String(effect.get(fname, "")), fname)
			"float":
				_add_field_spin(container, flabel, float(effect.get(fname, 0.0)), float(field.get("min", 0.0)), float(field.get("max", 9999.0)), float(field.get("step", 0.1)), fname, "float")
			"int":
				_add_field_spin(container, flabel, float(int(effect.get(fname, 0))), float(field.get("min", 0.0)), float(field.get("max", 9999.0)), float(field.get("step", 1.0)), fname, "int")
			"string":
				_add_field_edit(container, flabel, String(effect.get(fname, "")), fname)
			"checkbox_group":
				var options: Array = field.get("options", [])
				var current: Array = effect.get(fname, [])
				for affect_opt in options:
					var checkbox := CheckBox.new()
					checkbox.text = BuffEffectRegistry.get_option_label(fname, String(affect_opt))
					checkbox.button_pressed = String(affect_opt) in current
					checkbox.toggled.connect(_on_affects_toggled.bind(container, String(affect_opt)))
					container.add_child(checkbox)


func _add_field_option(container: HBoxContainer, label_text: String, options: Array, current: String, field_name: String) -> void:
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	var option := OptionButton.new()
	for i in range(options.size()):
		option.add_item(BuffEffectRegistry.get_option_label(field_name, String(options[i])), i)
		option.set_item_metadata(i, options[i])
	option.select(options.find(current) if current in options else 0)
	option.item_selected.connect(_on_effect_field_option_changed.bind(container, field_name, option))
	container.add_child(option)


func _add_field_spin(container: HBoxContainer, label_text: String, current: float, min_val: float, max_val: float, step_val: float, field_name: String, kind: String = "float") -> void:
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = current
	spin.value_changed.connect(_on_effect_field_spin_changed.bind(container, field_name, kind))
	container.add_child(spin)


func _add_field_edit(container: HBoxContainer, label_text: String, current: String, field_name: String) -> void:
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	var edit := LineEdit.new()
	edit.text = current
	edit.custom_minimum_size = Vector2(100, 0)
	edit.text_changed.connect(_on_effect_field_text_changed.bind(container, field_name))
	container.add_child(edit)


# ---- 事件回调 ----

func _on_field_changed(new_text: String, field_name: String) -> void:
	if _loading or _selected_id == 0:
		return
	_buffs[_selected_id][field_name] = new_text
	_refresh_buff_list()


func _on_desc_changed() -> void:
	if _loading or _selected_id == 0:
		return
	_buffs[_selected_id]["description"] = _desc_edit.text


func _on_option_changed(index: int, field_name: String) -> void:
	if _loading or _selected_id == 0:
		return
	var option := _category_option if field_name == "category" else _stack_behavior_option
	_buffs[_selected_id][field_name] = option.get_item_metadata(index)
	_refresh_buff_list()


func _on_spin_changed(value: float, field_name: String) -> void:
	if _loading or _selected_id == 0:
		return
	if field_name == "duration":
		_buffs[_selected_id]["duration"] = value
	elif field_name == "max_stacks":
		_buffs[_selected_id]["max_stacks"] = int(value)


func _on_add_buff() -> void:
	var max_id := 1000
	for buff_id in _buffs:
		max_id = maxi(max_id, buff_id)
	var new_id := max_id + 1
	_buffs[new_id] = {
		"name": "新 Buff",
		"description": "",
		"category": "debuff",
		"duration": 3.0,
		"max_stacks": 1,
		"stack_behavior": "refresh",
		"icon": "",
		"effect_scene": "",
		"effects": [],
	}
	_selected_id = new_id
	_refresh_buff_list()
	_show_buff_details(new_id)


func _on_delete_buff() -> void:
	if _selected_id == 0:
		return
	_buffs.erase(_selected_id)
	_selected_id = 0
	_refresh_buff_list()


func _on_add_effect() -> void:
	if _selected_id == 0:
		return
	var effects: Array = _buffs[_selected_id].get("effects", [])
	effects.append(BuffEffectRegistry.make_default_effect("stat_modifier"))
	_buffs[_selected_id]["effects"] = effects
	_refresh_effects(effects)


func _on_delete_effect(row: HBoxContainer) -> void:
	if _selected_id == 0:
		return
	var effects: Array = _buffs[_selected_id].get("effects", [])
	var idx := row.get_index()
	if idx >= 0 and idx < effects.size():
		effects.remove_at(idx)
	_buffs[_selected_id]["effects"] = effects
	_refresh_effects(effects)


func _on_effect_type_changed(index: int, row: HBoxContainer) -> void:
	if _loading or _selected_id == 0:
		return
	var type_option := row.get_child(0) as OptionButton
	var new_type := String(type_option.get_item_metadata(index))
	var effects: Array = _buffs[_selected_id].get("effects", [])
	var idx := row.get_index()
	if idx < 0 or idx >= effects.size():
		return
	var new_effect := BuffEffectRegistry.make_default_effect(new_type)
	effects[idx] = new_effect
	_buffs[_selected_id]["effects"] = effects
	# 重建该行的字段
	var fields_container := row.get_child(1) as HBoxContainer
	_populate_effect_fields(fields_container, new_effect)


func _on_effect_field_option_changed(index: int, container: HBoxContainer, field_name: String, option: OptionButton) -> void:
	if _loading or _selected_id == 0:
		return
	var row := container.get_parent() as HBoxContainer
	var effects: Array = _buffs[_selected_id].get("effects", [])
	var idx := row.get_index()
	if idx < 0 or idx >= effects.size():
		return
	effects[idx][field_name] = option.get_item_metadata(index)
	_buffs[_selected_id]["effects"] = effects


func _on_effect_field_spin_changed(value: float, container: HBoxContainer, field_name: String, kind: String) -> void:
	if _loading or _selected_id == 0:
		return
	var row := container.get_parent() as HBoxContainer
	var effects: Array = _buffs[_selected_id].get("effects", [])
	var idx := row.get_index()
	if idx < 0 or idx >= effects.size():
		return
	if kind == "int":
		effects[idx][field_name] = int(value)
	else:
		effects[idx][field_name] = value
	_buffs[_selected_id]["effects"] = effects


func _on_effect_field_text_changed(new_text: String, container: HBoxContainer, field_name: String) -> void:
	if _loading or _selected_id == 0:
		return
	var row := container.get_parent() as HBoxContainer
	var effects: Array = _buffs[_selected_id].get("effects", [])
	var idx := row.get_index()
	if idx < 0 or idx >= effects.size():
		return
	effects[idx][field_name] = new_text
	_buffs[_selected_id]["effects"] = effects


func _on_affects_toggled(pressed: bool, container: HBoxContainer, affect: String) -> void:
	if _loading or _selected_id == 0:
		return
	var row := container.get_parent() as HBoxContainer
	var effects: Array = _buffs[_selected_id].get("effects", [])
	var idx := row.get_index()
	if idx < 0 or idx >= effects.size():
		return
	var affects: Array = effects[idx].get("affects", [])
	if pressed and affect not in affects:
		affects.append(affect)
	elif not pressed and affect in affects:
		affects.erase(affect)
	effects[idx]["affects"] = affects
	_buffs[_selected_id]["effects"] = effects


# ---- 保存 ----

func _on_save() -> void:
	var sorted_ids: Array = _buffs.keys()
	sorted_ids.sort()
	var data: Dictionary = {}
	for buff_id in sorted_ids:
		var buff: Dictionary = _buffs[buff_id]
		buff["id"] = buff_id
		data[str(buff_id)] = buff
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		_status_label.text = "写入失败"
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	# 同步内存中的 BuffConfig
	var lc = GameRegistry.get("buff_config") if GameRegistry.get("buff_config") != null else null
	if lc != null and lc.has_method("load_config"):
		lc._loaded = false
		lc.load_config()
	_status_label.text = "已保存 %d 个 buff" % data.size()
	_show_save_success(data.size())


func _show_save_success(count: int) -> void:
	var overlay := Label.new()
	overlay.text = "保存成功"
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 28)
	overlay.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.9))
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 0.3).set_delay(1.2)
	tween.tween_callback(overlay.queue_free)
