@tool
extends Window

## 可视化关卡与刷怪编辑器
## 从“游戏工具 → 配置关卡...”打开。
##
## 数据格式（与 levels.json 一致）：
##   关卡：{name, scene_path, spawn_x, spawn_y, bgm, description, enemies[]}
##   单怪点：{spawn_id, mode:"point", enemy_id, x, y}
##   随机组：{spawn_id, mode:"group", enemy_id, x, y, count, scatter_x}
## 旧记录（无 mode）按 count 推断：count<=1 视为 point，count>1 视为 group（scatter_x 默认 20）。
##
## 运行时优先级：
##   - 玩家出生点：levels.json.spawn_x/spawn_y > 场景 PlayerSpawn Marker2D
##   - 怪物刷怪：EnemySpawner.spawn_enemies_for_level 支持 point/group 两种记录

const LEVELS_PATH := "res://data/levels.json"
const ENEMIES_PATH := "res://data/enemies.json"
const SCENE_DIR_HINT := "res://scenes"

var _levels: Dictionary = {}          # id_str → level dict
var _enemies_cfg: Dictionary = {}     # id_str → enemy dict
var _current_level_id: String = ""
var _selected_spawn_id: String = ""
var _preview_textures: Dictionary = {}  # enemy_id(int) → Texture2D
var _loading := false

# ---- UI: 关卡列表 ----
var _level_list: ItemList
var _level_new_btn: Button
var _level_dup_btn: Button
var _level_del_btn: Button

# ---- UI: 关卡属性 ----
var _name_edit: LineEdit
var _scene_edit: LineEdit
var _scene_browse: Button
var _spawn_x_spin: SpinBox
var _spawn_y_spin: SpinBox
var _bgm_edit: LineEdit
var _desc_edit: TextEdit

# ---- UI: 视口 ----
var _viewport_container: MapViewportContainer
var _viewport: SubViewport
var _drop_overlay: Control  # 覆盖在视口上的透明层，用于接收拖放
var _world_root: Node2D
var _markers_node: Node2D
var _map_instance: Node = null
var _zoom_slider: HSlider
var _marker_size_slider: HSlider
var _map_opacity_slider: HSlider
var _grid_check: CheckBox
var _fit_btn: Button
var _add_point_btn: Button
var _add_group_btn: Button

# ---- UI: 刷怪点列表与属性 ----
var _spawn_list: ItemList
var _spawn_props: GridContainer
var _enemy_picker: OptionButton
var _mode_picker: OptionButton
var _spawn_x_prop_spin: SpinBox
var _spawn_y_prop_spin: SpinBox
var _count_spin: SpinBox
var _scatter_slider: HSlider
var _scatter_value_label: Label
var _spawn_dup_btn: Button
var _spawn_del_btn: Button
var _enemy_palette: EnemyPaletteList  # 怪物库，可拖拽到地图

# ---- UI: 底部 ----
var _status: Label
var _save_btn: Button
var _discard_btn: Button
var _toast: Label
var _toast_timer: Timer

# ---- 视口相机状态 ----
var _pan_offset := Vector2.ZERO
var _zoom := 0.5
var _dragging_cam := false
var _dragging_spawn := false
var _dragging_player_spawn := false
var _drag_last_screen := Vector2.ZERO
var _show_grid := true
const GRID_SIZE := 64.0
var _marker_radius := 26.0  # 刷怪点/出生点圆点半径，可由工具栏滑块调节
var _map_opacity := 0.5      # 地图实例透明度，可由工具栏滑块调节
const PLAYER_SPAWN_ID := "__player_spawn__"  # 玩家出生点的哨兵 ID


func _init() -> void:
	title = "关卡编辑器"
	size = Vector2i(1360, 800)
	min_size = Vector2i(1080, 640)
	close_requested.connect(_on_close_requested)


func _on_close_requested() -> void:
	hide()


func _ready() -> void:
	_build_ui()
	_load_data()
	_refresh_level_list()


func open_editor() -> void:
	if _level_list == null:
		_build_ui()
	_load_data()
	_refresh_level_list()
	popup_centered(size)
	mode = Window.MODE_MAXIMIZED


# ============================================================
# 数据加载
# ============================================================

func _load_data() -> void:
	_levels = _read_json(LEVELS_PATH).duplicate(true)
	_enemies_cfg = _read_json(ENEMIES_PATH).duplicate(true)
	_normalize_all_levels()
	_preview_textures.clear()
	_refresh_enemy_palette()


## 刷新怪物库列表（按 ID 排序）。选中怪物库的项会同步到刷怪属性里的怪物下拉。
func _refresh_enemy_palette() -> void:
	if _enemy_palette == null:
		return
	_enemy_palette.clear()
	var keys: Array = _enemies_cfg.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var id_str := String(key)
		var enemy: Dictionary = _enemies_cfg[id_str]
		var ename := String(enemy.get("name", id_str))
		var label_text := "%s  %s" % [id_str, ename]
		_enemy_palette.add_item(label_text)
		_enemy_palette.set_item_metadata(_enemy_palette.item_count - 1, id_str)
		# 尝试加载缩略图
		var tex := _get_enemy_preview_texture(int(id_str))
		if tex != null:
			_enemy_palette.set_item_icon(_enemy_palette.item_count - 1, tex)


## 怪物库选中：同步到刷怪属性的怪物下拉，便于后续点击地图添加。
func _on_palette_selected(index: int) -> void:
	if index < 0 or index >= _enemy_palette.item_count:
		return
	var id_str := String(_enemy_palette.get_item_metadata(index))
	for i in range(_enemy_picker.item_count):
		if String(_enemy_picker.get_item_metadata(i)) == id_str:
			_enemy_picker.select(i)
			break


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK or not j.data is Dictionary:
		return {}
	return j.data


func _normalize_all_levels() -> void:
	for id_str in _levels:
		var level: Dictionary = _levels[id_str]
		level["enemies"] = _normalize_enemies(level.get("enemies", []))
		_levels[id_str] = level


## 把旧 enemies 记录补齐 spawn_id/mode/scatter_x。
func _normalize_enemies(raw: Variant) -> Array:
	if not raw is Array:
		return []
	var result: Array = []
	var existing_ids: Dictionary = {}
	var index := 0
	for entry_value in raw:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var count := int(entry.get("count", 1))
		var mode := String(entry.get("mode", "group" if count > 1 else "point"))
		var spawn_id := String(entry.get("spawn_id", ""))
		if spawn_id.is_empty():
			while true:
				spawn_id = "spawn_%d" % index
				if not existing_ids.has(spawn_id):
					break
				index += 1
		existing_ids[spawn_id] = true
		var normalized: Dictionary = {
			"spawn_id": spawn_id,
			"mode": mode,
			"enemy_id": int(entry.get("enemy_id", 0)),
			"x": float(entry.get("x", 0.0)),
			"y": float(entry.get("y", 0.0)),
		}
		if mode == "group":
			normalized["count"] = maxi(1, count)
			normalized["scatter_x"] = float(entry.get("scatter_x", 20.0))
		result.append(normalized)
		index += 1
	return result


# ============================================================
# UI 构建
# ============================================================

func _build_ui() -> void:
	if _level_list != null:
		return
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# 顶部工具栏
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	root.add_child(toolbar)
	_add_btn(toolbar, "新建关卡", _on_new_level)
	_add_btn(toolbar, "复制关卡", _on_duplicate_level)
	_add_btn(toolbar, "删除关卡", _on_delete_level)
	toolbar.add_child(VSeparator.new())
	_add_btn(toolbar, "加载地图", _on_reload_map)
	_fit_btn = _add_btn(toolbar, "适应窗口", _on_fit_view)
	_grid_check = CheckBox.new()
	_grid_check.text = "网格"
	_grid_check.button_pressed = true
	_grid_check.toggled.connect(_on_grid_toggled)
	toolbar.add_child(_grid_check)
	toolbar.add_child(VSeparator.new())
	var zoom_label := Label.new()
	zoom_label.text = "缩放"
	toolbar.add_child(zoom_label)
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 0.1
	_zoom_slider.max_value = 3.0
	_zoom_slider.step = 0.05
	_zoom_slider.value = _zoom
	_zoom_slider.custom_minimum_size.x = 140
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	toolbar.add_child(_zoom_slider)
	toolbar.add_child(VSeparator.new())
	var marker_label := Label.new()
	marker_label.text = "圆点"
	toolbar.add_child(marker_label)
	_marker_size_slider = HSlider.new()
	_marker_size_slider.min_value = 8.0
	_marker_size_slider.max_value = 40.0
	_marker_size_slider.step = 1.0
	_marker_size_slider.value = _marker_radius
	_marker_size_slider.custom_minimum_size.x = 100
	_marker_size_slider.value_changed.connect(_on_marker_size_changed)
	toolbar.add_child(_marker_size_slider)
	var opacity_label := Label.new()
	opacity_label.text = "地图透明"
	toolbar.add_child(opacity_label)
	_map_opacity_slider = HSlider.new()
	_map_opacity_slider.min_value = 0.1
	_map_opacity_slider.max_value = 1.0
	_map_opacity_slider.step = 0.05
	_map_opacity_slider.value = _map_opacity
	_map_opacity_slider.custom_minimum_size.x = 100
	_map_opacity_slider.value_changed.connect(_on_map_opacity_changed)
	toolbar.add_child(_map_opacity_slider)
	_add_point_btn = _add_btn(toolbar, "点击地图添加单怪点（或拖拽怪物库）", _on_enter_add_point_mode)
	_add_group_btn = _add_btn(toolbar, "点击地图添加随机组（或拖拽怪物库）", _on_enter_add_group_mode)

	# 主区域：三栏
	var main := HSplitContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	# 左栏：关卡列表 + 关卡属性
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 180
	main.add_child(left)
	left.add_child(_make_label("关卡列表", 14))
	_level_list = ItemList.new()
	_level_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_level_list.item_selected.connect(_on_level_selected)
	left.add_child(_level_list)
	var lvl_btns := HBoxContainer.new()
	left.add_child(lvl_btns)
	_level_new_btn = _add_btn(lvl_btns, "新建", _on_new_level)
	_level_dup_btn = _add_btn(lvl_btns, "复制", _on_duplicate_level)
	_level_del_btn = _add_btn(lvl_btns, "删除", _on_delete_level)
	left.add_child(_make_label("关卡属性", 13))
	var lvl_props := GridContainer.new()
	lvl_props.columns = 2
	lvl_props.add_theme_constant_override("h_separation", 6)
	lvl_props.add_theme_constant_override("v_separation", 4)
	left.add_child(lvl_props)
	_name_edit = _add_grid_line(lvl_props, "名称")
	_name_edit.text_changed.connect(_on_level_field_changed.bind("name"))
	var scene_row := HBoxContainer.new()
	lvl_props.add_child(_make_label("场景"))
	lvl_props.add_child(scene_row)
	_scene_edit = LineEdit.new()
	_scene_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_edit.text_changed.connect(_on_scene_path_changed)
	scene_row.add_child(_scene_edit)
	_scene_browse = Button.new()
	_scene_browse.text = "..."
	_scene_browse.tooltip_text = "选择关卡场景文件"
	_scene_browse.pressed.connect(_on_browse_scene)
	scene_row.add_child(_scene_browse)
	_spawn_x_spin = _add_grid_spin(lvl_props, "出生 X", -9999.0, 99999.0, 1.0)
	_spawn_x_spin.value_changed.connect(_on_level_num_changed.bind("spawn_x"))
	_spawn_y_spin = _add_grid_spin(lvl_props, "出生 Y", -9999.0, 99999.0, 1.0)
	_spawn_y_spin.value_changed.connect(_on_level_num_changed.bind("spawn_y"))
	_bgm_edit = _add_grid_line(lvl_props, "BGM")
	_bgm_edit.text_changed.connect(_on_level_field_changed.bind("bgm"))
	lvl_props.add_child(_make_label("描述"))
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(160, 50)
	_desc_edit.text_changed.connect(_on_desc_changed)
	lvl_props.add_child(_desc_edit)

	# 中栏：地图视口
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(middle)
	_viewport_container = MapViewportContainer.new()
	_viewport_container.editor = self
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.stretch = true
	_viewport_container.clip_contents = true
	middle.add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport_container.add_child(_viewport)
	_world_root = Node2D.new()
	_world_root.name = "WorldRoot"
	_viewport.add_child(_world_root)
	_markers_node = LevelMarkersOverlay.new()
	_markers_node.name = "MarkersOverlay"
	_markers_node.editor = self
	_markers_node.z_index = 4096
	_markers_node.z_as_relative = false
	_world_root.add_child(_markers_node)
	# 拖放覆盖层：接收拖放 + 转发点击事件。
	# SubViewportContainer 不会触发 _can_drop_data/_drop_data，所以用 Control 覆盖。
	# 此 Control 同时接管 gui_input（点击/滚轮/平移），转发给 _on_viewport_gui_input。
	_drop_overlay = DropOverlay.new()
	_drop_overlay.editor = self
	_drop_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_drop_overlay.gui_input.connect(_on_viewport_gui_input)
	_viewport_container.add_child(_drop_overlay)

	# 右栏：怪物地图摆放
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	main.add_child(right)
	var placement_tabs := TabContainer.new()
	placement_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(placement_tabs)
	var monster_box := VBoxContainer.new()
	monster_box.name = "怪物"
	placement_tabs.add_child(monster_box)
	monster_box.add_child(_make_label("怪物库（拖拽到地图放置）", 13))
	_enemy_palette = EnemyPaletteList.new()
	_enemy_palette.editor = self
	_enemy_palette.custom_minimum_size.y = 300
	_enemy_palette.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_enemy_palette.icon_mode = ItemList.ICON_MODE_TOP
	_enemy_palette.max_columns = 4
	_enemy_palette.fixed_icon_size = Vector2i(72, 72)
	_enemy_palette.fixed_column_width = 150
	_enemy_palette.same_column_width = true
	_enemy_palette.item_selected.connect(_on_palette_selected)
	monster_box.add_child(_enemy_palette)
	monster_box.add_child(_make_label("刷怪点列表", 14))
	_spawn_list = ItemList.new()
	_spawn_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spawn_list.item_selected.connect(_on_spawn_selected)
	monster_box.add_child(_spawn_list)
	var spawn_btns := HBoxContainer.new()
	monster_box.add_child(spawn_btns)
	_spawn_dup_btn = _add_btn(spawn_btns, "复制", _on_duplicate_spawn)
	_spawn_del_btn = _add_btn(spawn_btns, "删除", _on_delete_spawn)
	monster_box.add_child(_make_label("刷怪点属性", 13))
	_spawn_props = GridContainer.new()
	_spawn_props.columns = 2
	_spawn_props.add_theme_constant_override("h_separation", 6)
	_spawn_props.add_theme_constant_override("v_separation", 4)
	monster_box.add_child(_spawn_props)
	_enemy_picker = OptionButton.new()
	_enemy_picker.item_selected.connect(_on_spawn_field_changed)
	_spawn_props.add_child(_make_label("怪物"))
	_spawn_props.add_child(_enemy_picker)
	_mode_picker = OptionButton.new()
	_mode_picker.add_item("单怪点 (point)")
	_mode_picker.set_item_metadata(0, "point")
	_mode_picker.add_item("随机组 (group)")
	_mode_picker.set_item_metadata(1, "group")
	_mode_picker.item_selected.connect(_on_mode_changed)
	_spawn_props.add_child(_make_label("模式"))
	_spawn_props.add_child(_mode_picker)
	_spawn_x_prop_spin = _add_grid_spin(_spawn_props, "X", -9999.0, 99999.0, 1.0)
	_spawn_x_prop_spin.value_changed.connect(_on_spawn_num_changed.bind("x"))
	_spawn_y_prop_spin = _add_grid_spin(_spawn_props, "Y", -9999.0, 99999.0, 1.0)
	_spawn_y_prop_spin.value_changed.connect(_on_spawn_num_changed.bind("y"))
	_count_spin = _add_grid_spin(_spawn_props, "数量", 1.0, 99.0, 1.0)
	_count_spin.value_changed.connect(_on_spawn_num_changed.bind("count"))
	_scatter_slider = _add_grid_slider(_spawn_props, "散布 X", 0.0, 500.0, 1.0)
	_scatter_slider.value_changed.connect(_on_spawn_num_changed.bind("scatter_x"))

	# 底部状态与操作
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	_save_btn = _add_btn(bottom, "保存 levels.json", _on_save)
	_discard_btn = _add_btn(bottom, "放弃修改", _on_discard)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	# 保存成功浮层提示（短暂居中显示后自动消失）
	_toast = Label.new()
	_toast.text = ""
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", Color("4eff7a"))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_toast.add_theme_constant_override("shadow_offset_x", 1)
	_toast.add_theme_constant_override("shadow_offset_y", 1)
	_toast.add_theme_constant_override("shadow_outline_size", 2)
	_toast.visible = false
	_toast.z_index = 100
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 1.5
	_toast_timer.timeout.connect(func(): _toast.visible = false)
	add_child(_toast_timer)


func _add_btn(parent: Container, text_value: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text_value
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _make_label(text_value: String, font_size: int = 12) -> Label:
	var l := Label.new()
	l.text = text_value
	if font_size != 12:
		l.add_theme_font_size_override("font_size", font_size)
	return l


func _add_grid_line(parent: GridContainer, label_text: String) -> LineEdit:
	parent.add_child(_make_label(label_text))
	var e := LineEdit.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e


func _add_grid_spin(parent: GridContainer, label_text: String, minimum: float, maximum: float, step_value: float) -> SpinBox:
	parent.add_child(_make_label(label_text))
	var s := SpinBox.new()
	s.min_value = minimum
	s.max_value = maximum
	s.step = step_value
	s.allow_greater = true
	s.allow_lesser = true
	parent.add_child(s)
	return s


func _add_grid_slider(parent: GridContainer, label_text: String, minimum: float, maximum: float, step_value: float) -> HSlider:
	parent.add_child(_make_label(label_text))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.allow_greater = true
	row.add_child(slider)
	var val_label := Label.new()
	val_label.custom_minimum_size.x = 50
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_label)
	slider.value_changed.connect(func(v: float): val_label.text = "%.0f" % v)
	_scatter_value_label = val_label
	return slider


# ============================================================
# 关卡列表
# ============================================================

func _refresh_level_list() -> void:
	_level_list.clear()
	var keys: Array = _levels.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for id_str in keys:
		var level: Dictionary = _levels[id_str]
		_level_list.add_item("%s  %s" % [id_str, String(level.get("name", ""))])
		_level_list.set_item_metadata(_level_list.item_count - 1, id_str)
	if _current_level_id.is_empty() and not keys.is_empty():
		_current_level_id = String(keys[0])
	# 重新选中
	var select_idx := 0
	for i in range(_level_list.item_count):
		if String(_level_list.get_item_metadata(i)) == _current_level_id:
			select_idx = i
			break
	_level_list.select(select_idx)
	_on_level_selected(select_idx)


func _on_level_selected(index: int) -> void:
	if index < 0 or index >= _level_list.item_count:
		return
	_current_level_id = String(_level_list.get_item_metadata(index))
	_selected_spawn_id = ""
	_load_level_fields()
	_refresh_spawn_list()
	_load_map_for_current_level()
	_refresh_markers()


func _load_level_fields() -> void:
	if _current_level_id.is_empty():
		return
	_loading = true
	var level: Dictionary = _levels.get(_current_level_id, {})
	_name_edit.text = String(level.get("name", ""))
	_scene_edit.text = String(level.get("scene_path", ""))
	_spawn_x_spin.value = float(level.get("spawn_x", 0))
	_spawn_y_spin.value = float(level.get("spawn_y", 0))
	_bgm_edit.text = String(level.get("bgm", ""))
	_desc_edit.text = String(level.get("description", ""))
	_loading = false


func _on_level_field_changed(field: String, value: String) -> void:
	if _loading or _current_level_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	level[field] = value
	_levels[_current_level_id] = level
	if field == "name":
		_refresh_level_list()


func _on_level_num_changed(value: float, field: String) -> void:
	if _loading or _current_level_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	level[field] = int(value)
	_levels[_current_level_id] = level
	_refresh_markers()


func _on_scene_path_changed(value: String) -> void:
	if _loading or _current_level_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	level["scene_path"] = value
	_levels[_current_level_id] = level


func _on_browse_scene() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tscn", "Godot Scene")
	dialog.current_dir = SCENE_DIR_HINT
	add_child(dialog)
	dialog.file_selected.connect(_on_scene_picked.bind(dialog))
	dialog.canceled.connect(_on_dialog_closed.bind(dialog))
	dialog.popup_centered_ratio(0.95)
	dialog.mode = Window.MODE_MAXIMIZED


func _on_scene_picked(path: String, dialog: FileDialog) -> void:
	_scene_edit.text = path
	_on_scene_path_changed(path)
	_on_dialog_closed(dialog)
	_load_map_for_current_level()


func _on_dialog_closed(dialog: FileDialog) -> void:
	dialog.queue_free()


func _on_desc_changed() -> void:
	if _loading or _current_level_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	level["description"] = _desc_edit.text
	_levels[_current_level_id] = level


func _on_new_level() -> void:
	var new_id := _compute_new_level_id()
	if new_id <= 0:
		_status.text = "无法分配新关卡 ID。"
		return
	var id_str := str(new_id)
	_levels[id_str] = {
		"name": "新关卡",
		"scene_path": "",
		"spawn_x": 160,
		"spawn_y": 350,
		"bgm": "",
		"description": "",
		"enemies": [],
	}
	_current_level_id = id_str
	_refresh_level_list()
	_status.text = "已新建关卡 %s，请选择场景并保存。" % id_str


func _on_duplicate_level() -> void:
	if _current_level_id.is_empty():
		return
	var src: Dictionary = _levels.get(_current_level_id, {})
	if src.is_empty():
		return
	var new_id := _compute_new_level_id()
	var id_str := str(new_id)
	var copy: Dictionary = src.duplicate(true)
	# 复制时重生成 spawn_id 避免冲突
	var new_enemies: Array = []
	var i := 0
	for entry_value in copy.get("enemies", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = (entry_value as Dictionary).duplicate(true)
		entry["spawn_id"] = "spawn_%d" % i
		new_enemies.append(entry)
		i += 1
	copy["enemies"] = new_enemies
	copy["name"] = String(copy.get("name", "")) + " 副本"
	_levels[id_str] = copy
	_current_level_id = id_str
	_refresh_level_list()
	_status.text = "已复制为关卡 %s。" % id_str


func _on_delete_level() -> void:
	if _current_level_id.is_empty():
		return
	_levels.erase(_current_level_id)
	_current_level_id = ""
	_selected_spawn_id = ""
	_refresh_level_list()
	_status.text = "已删除关卡（点击保存后生效）。"


func _compute_new_level_id() -> int:
	var max_id := 0
	for id_str in _levels:
		var id := int(id_str)
		if id > max_id:
			max_id = id
	return max_id + 1


# ============================================================
# 刷怪点列表与属性
# ============================================================

func _refresh_spawn_list() -> void:
	_spawn_list.clear()
	if _current_level_id.is_empty():
		_refresh_spawn_props()
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	var enemies: Array = level.get("enemies", [])
	var select_idx := -1
	for i in range(enemies.size()):
		var entry: Dictionary = enemies[i]
		var spawn_id := String(entry.get("spawn_id", ""))
		var enemy_id := int(entry.get("enemy_id", 0))
		var mode := String(entry.get("mode", "point"))
		var ename := _enemy_display_name(enemy_id)
		var label_text := "%s  [%s]  %s" % [spawn_id, mode, ename]
		if mode == "group":
			label_text += " x%d" % int(entry.get("count", 1))
		_spawn_list.add_item(label_text)
		_spawn_list.set_item_metadata(i, spawn_id)
		if spawn_id == _selected_spawn_id:
			select_idx = i
	if select_idx >= 0:
		_spawn_list.select(select_idx)
	_refresh_spawn_props()


func _on_spawn_selected(index: int) -> void:
	if index < 0 or index >= _spawn_list.item_count:
		return
	_selected_spawn_id = String(_spawn_list.get_item_metadata(index))
	_refresh_spawn_props()
	_refresh_markers()


func _refresh_spawn_props() -> void:
	_loading = true
	# 刷新怪物下拉
	_enemy_picker.clear()
	var enemy_keys: Array = _enemies_cfg.keys()
	enemy_keys.sort_custom(func(a, b): return int(a) < int(b))
	var pick_idx := 0
	var select_enemy_idx := -1
	for i in range(enemy_keys.size()):
		var id_str := String(enemy_keys[i])
		var enemy: Dictionary = _enemies_cfg[id_str]
		var ename := String(enemy.get("name", id_str))
		_enemy_picker.add_item("%s  %s" % [id_str, ename])
		_enemy_picker.set_item_metadata(i, id_str)
	var entry := _get_selected_spawn()
	if entry.is_empty():
		_mode_picker.select(0)
		_spawn_x_prop_spin.value = 0
		_spawn_y_prop_spin.value = 0
		_count_spin.value = 1
		_scatter_slider.value = 20
		_scatter_value_label.text = "20"
		_loading = false
		return
	# 选中当前 enemy_id
	for i in range(_enemy_picker.item_count):
		if String(_enemy_picker.get_item_metadata(i)) == str(int(entry.get("enemy_id", 0))):
			select_enemy_idx = i
			break
	if select_enemy_idx >= 0:
		_enemy_picker.select(select_enemy_idx)
	var mode := String(entry.get("mode", "point"))
	_mode_picker.select(0 if mode == "point" else 1)
	_spawn_x_prop_spin.value = float(entry.get("x", 0))
	_spawn_y_prop_spin.value = float(entry.get("y", 0))
	_count_spin.value = int(entry.get("count", 1))
	_scatter_slider.value = float(entry.get("scatter_x", 20))
	_scatter_value_label.text = "%.0f" % _scatter_slider.value
	_loading = false


func _get_selected_spawn() -> Dictionary:
	if _current_level_id.is_empty() or _selected_spawn_id.is_empty():
		return {}
	var level: Dictionary = _levels.get(_current_level_id, {})
	for entry_value in level.get("enemies", []):
		if not entry_value is Dictionary:
			continue
		if String((entry_value as Dictionary).get("spawn_id", "")) == _selected_spawn_id:
			return entry_value
	return {}


func _on_spawn_field_changed(_index: int) -> void:
	if _loading or _selected_spawn_id.is_empty():
		return
	var entry := _get_selected_spawn()
	if entry.is_empty():
		return
	var id_str := String(_enemy_picker.get_selected_metadata())
	entry["enemy_id"] = int(id_str)
	_update_selected_spawn(entry)
	_refresh_spawn_list()
	_refresh_markers()


func _on_mode_changed(_index: int) -> void:
	if _loading or _selected_spawn_id.is_empty():
		return
	var entry := _get_selected_spawn()
	if entry.is_empty():
		return
	var mode := String(_mode_picker.get_selected_metadata())
	entry["mode"] = mode
	if mode == "group" and not entry.has("count"):
		entry["count"] = 1
	if mode == "group" and not entry.has("scatter_x"):
		entry["scatter_x"] = 20.0
	_update_selected_spawn(entry)
	_refresh_spawn_list()
	_refresh_markers()


func _on_spawn_num_changed(value: float, field: String) -> void:
	if _loading or _selected_spawn_id.is_empty():
		return
	var entry := _get_selected_spawn()
	if entry.is_empty():
		return
	if field == "x" or field == "y" or field == "scatter_x":
		entry[field] = value
	elif field == "count":
		entry["count"] = int(value)
	_update_selected_spawn(entry)
	_refresh_spawn_list()
	_refresh_markers()


func _update_selected_spawn(entry: Dictionary) -> void:
	if _current_level_id.is_empty() or _selected_spawn_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	var enemies: Array = level.get("enemies", [])
	for i in range(enemies.size()):
		if not enemies[i] is Dictionary:
			continue
		if String((enemies[i] as Dictionary).get("spawn_id", "")) == _selected_spawn_id:
			enemies[i] = entry
			break
	level["enemies"] = enemies
	_levels[_current_level_id] = level


func _on_duplicate_spawn() -> void:
	if _current_level_id.is_empty() or _selected_spawn_id.is_empty():
		return
	var entry := _get_selected_spawn()
	if entry.is_empty():
		return
	var new_entry: Dictionary = entry.duplicate(true)
	var new_id := _compute_new_spawn_id()
	new_entry["spawn_id"] = new_id
	new_entry["x"] = float(new_entry.get("x", 0)) + 40
	var level: Dictionary = _levels.get(_current_level_id, {})
	var enemies: Array = level.get("enemies", [])
	enemies.append(new_entry)
	level["enemies"] = enemies
	_levels[_current_level_id] = level
	_selected_spawn_id = new_id
	_refresh_spawn_list()
	_refresh_markers()


func _on_delete_spawn() -> void:
	if _current_level_id.is_empty() or _selected_spawn_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	var enemies: Array = level.get("enemies", [])
	var filtered: Array = []
	for entry_value in enemies:
		if not entry_value is Dictionary:
			continue
		if String((entry_value as Dictionary).get("spawn_id", "")) == _selected_spawn_id:
			continue
		filtered.append(entry_value)
	level["enemies"] = filtered
	_levels[_current_level_id] = level
	_selected_spawn_id = ""
	_refresh_spawn_list()
	_refresh_markers()


func _compute_new_spawn_id() -> String:
	var level: Dictionary = _levels.get(_current_level_id, {})
	var existing: Dictionary = {}
	for entry_value in level.get("enemies", []):
		if entry_value is Dictionary:
			existing[String((entry_value as Dictionary).get("spawn_id", ""))] = true
	var index := 0
	while true:
		var candidate := "spawn_%d" % index
		if not existing.has(candidate):
			return candidate
		index += 1
	return "spawn_0"  # fallback，理论上不会执行到这里


# ============================================================
# 添加刷怪点模式
# ============================================================

var _add_mode := ""  # "", "point", "group"

func _on_enter_add_point_mode() -> void:
	_add_mode = "point"
	_status.text = "点击地图位置添加单怪点（ESC 取消）"


func _on_enter_add_group_mode() -> void:
	_add_mode = "group"
	_status.text = "点击地图位置添加随机组（ESC 取消）"


func _cancel_add_mode() -> void:
	if not _add_mode.is_empty():
		_add_mode = ""
		_status.text = ""


## 在地图世界坐标处添加一个刷怪点。默认使用当前怪物下拉里选中的敌人。
func _add_spawn_at(world_pos: Vector2, mode: String) -> void:
	if _current_level_id.is_empty():
		return
	var enemy_id := 0
	if _enemy_picker.item_count > 0:
		enemy_id = int(_enemy_picker.get_selected_metadata())
	if enemy_id == 0 and not _enemies_cfg.is_empty():
		# 没选过怪，默认第一个
		var keys: Array = _enemies_cfg.keys()
		keys.sort_custom(func(a, b): return int(a) < int(b))
		enemy_id = int(keys[0])
	var spawn_id := _compute_new_spawn_id()
	var entry: Dictionary = {
		"spawn_id": spawn_id,
		"mode": mode,
		"enemy_id": enemy_id,
		"x": world_pos.x,
		"y": world_pos.y,
	}
	if mode == "group":
		entry["count"] = 1
		entry["scatter_x"] = 20.0
	var level: Dictionary = _levels.get(_current_level_id, {})
	var enemies: Array = level.get("enemies", [])
	enemies.append(entry)
	level["enemies"] = enemies
	_levels[_current_level_id] = level
	_selected_spawn_id = spawn_id
	_refresh_spawn_list()
	_refresh_markers()


# ============================================================
# 拖拽放置：从怪物库拖到地图
# ============================================================

## 判断是否能放置怪物，且当前有关卡。
func _can_drop_spawn_at(_screen_pos: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var d: Dictionary = data
	if String(d.get("type", "")) != "enemy_spawn":
		return false
	return not _current_level_id.is_empty()


## 放置：在落点创建刷怪点。模式由当前 _mode_picker 决定（默认 point）。
func _drop_spawn_at(screen_pos: Vector2, data: Variant) -> void:
	if not _can_drop_spawn_at(screen_pos, data):
		return
	var d: Dictionary = data
	var world_pos := _screen_to_world(screen_pos)
	var enemy_id := int(d.get("enemy_id", 0))
	if enemy_id == 0:
		return
	# 模式取当前下拉选择；默认 point
	var mode := "point"
	if _mode_picker.item_count > 0:
		mode = String(_mode_picker.get_selected_metadata())
	# 同步怪物下拉到该敌人
	for i in range(_enemy_picker.item_count):
		if String(_enemy_picker.get_item_metadata(i)) == str(enemy_id):
			_enemy_picker.select(i)
			break
	var spawn_id := _compute_new_spawn_id()
	var entry: Dictionary = {
		"spawn_id": spawn_id,
		"mode": mode,
		"enemy_id": enemy_id,
		"x": world_pos.x,
		"y": world_pos.y,
	}
	if mode == "group":
		entry["count"] = 1
		entry["scatter_x"] = 20.0
	var level: Dictionary = _levels.get(_current_level_id, {})
	var enemies: Array = level.get("enemies", [])
	enemies.append(entry)
	level["enemies"] = enemies
	_levels[_current_level_id] = level
	_selected_spawn_id = spawn_id
	_status.text = "已放置 %s 于 (%.0f, %.0f)" % [_enemy_display_name(enemy_id), world_pos.x, world_pos.y]
	_refresh_spawn_list()
	_refresh_markers()


# ============================================================
# 地图加载与视口
# ============================================================

func _load_map_for_current_level() -> void:
	if _map_instance != null:
		_map_instance.queue_free()
		_map_instance = null
	if _current_level_id.is_empty():
		_status.text = "未选择关卡"
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	var scene_path := String(level.get("scene_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_status.text = "关卡场景未配置或不存在：%s" % scene_path
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_status.text = "无法加载场景：%s" % scene_path
		return
	_map_instance = packed.instantiate()
	_world_root.add_child(_map_instance)
	_apply_map_opacity()
	# 确保标记层始终在地图之上
	if is_instance_valid(_markers_node):
		_world_root.move_child(_markers_node, -1)
	_status.text = "已加载地图：%s" % scene_path
	# 适应窗口
	call_deferred("_on_fit_view")


func _on_reload_map() -> void:
	_load_map_for_current_level()
	_refresh_markers()


func _on_zoom_changed(value: float) -> void:
	_zoom = clampf(value, 0.05, 5.0)
	_apply_view_transform()


func _on_grid_toggled(button_pressed: bool) -> void:
	_show_grid = button_pressed
	_refresh_markers()


func _on_marker_size_changed(value: float) -> void:
	_marker_radius = clampf(value, 4.0, 60.0)
	_refresh_markers()


func _on_map_opacity_changed(value: float) -> void:
	_map_opacity = clampf(value, 0.0, 1.0)
	_apply_map_opacity()


func _apply_map_opacity() -> void:
	if _map_instance != null and is_instance_valid(_map_instance):
		if _map_instance is CanvasItem:
			(_map_instance as CanvasItem).modulate = Color(1, 1, 1, _map_opacity)
		else:
			_map_instance.set("modulate", Color(1, 1, 1, _map_opacity))


func _apply_view_transform() -> void:
	if not is_instance_valid(_world_root):
		return
	_world_root.position = _pan_offset
	_world_root.scale = Vector2(_zoom, _zoom)
	_refresh_markers()


## 适应窗口：把整个地图内容缩放到视口可见区域。
func _on_fit_view() -> void:
	if _map_instance == null or not is_instance_valid(_map_instance):
		return
	var rect := _compute_map_rect()
	if rect.size == Vector2.ZERO:
		return
	var vp_size := _viewport_container.size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	var margin := 60.0
	var zoom_x := (vp_size.x - margin * 2) / rect.size.x
	var zoom_y := (vp_size.y - margin * 2) / rect.size.y
	_zoom = clampf(minf(zoom_x, zoom_y), 0.05, 5.0)
	if _zoom_slider != null:
		_zoom_slider.value = _zoom
	# 把 rect 中心放到视口中心
	_pan_offset = vp_size * 0.5 - (rect.position + rect.size * 0.5) * _zoom
	_apply_view_transform()


func _compute_map_rect() -> Rect2:
	if _map_instance == null or not is_instance_valid(_map_instance):
		return Rect2()
	# 优先使用场景 PlayerSpawn + TileMap 节点的并集包围盒
	var rect := Rect2()
	var first := true
	_collect_node_rect(_map_instance, rect, first)
	if not first and rect.size != Vector2.ZERO:
		return rect
	# 回退：用关卡配置里的刷怪点 + 出生点
	var level: Dictionary = _levels.get(_current_level_id, {})
	var points: Array = [Vector2(float(level.get("spawn_x", 0)), float(level.get("spawn_y", 0)))]
	for entry_value in level.get("enemies", []):
		if entry_value is Dictionary:
			points.append(Vector2(float((entry_value as Dictionary).get("x", 0)), float((entry_value as Dictionary).get("y", 0))))
	if points.size() == 1:
		return Rect2(points[0], Vector2(400, 300))
	rect = Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	rect = rect.grow(120)
	return rect


func _collect_node_rect(node: Node, rect: Rect2, first: bool) -> void:
	if node is CanvasItem:
		var ci := node as CanvasItem
		if ci is Sprite2D:
			var tex := (ci as Sprite2D).texture
			if tex != null:
				var r := Rect2(ci.global_position - tex.get_size() * 0.5, tex.get_size())
				if first:
					rect = r
				else:
					rect = rect.merge(r)
		elif ci is TileMap:
			var tm := ci as TileMap
			var used := tm.get_used_rect()
			if used.size != Vector2i.ZERO:
				var cell_size := tm.tile_set.tile_size if tm.tile_set != null else Vector2i(16, 16)
				var r := Rect2(used.position * cell_size, used.size * cell_size)
				if first:
					rect = r
				else:
					rect = rect.merge(r)
		elif ci is Node2D:
			# 没有更具体信息时，按 Node2D 的位置加点
			if first:
				rect = Rect2(ci.global_position, Vector2.ZERO)
			else:
				rect = rect.expand(ci.global_position)
	for child in node.get_children():
		_collect_node_rect(child, rect, first)


# ============================================================
# 视口交互（拖拽、缩放、点击）
# ============================================================

func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var world_pos := _screen_to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.1, 0.05, 5.0)
			_zoom_slider.value = _zoom
			_apply_view_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom * 0.9, 0.05, 5.0)
			_zoom_slider.value = _zoom
			_apply_view_transform()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_RIGHT and not _is_clicking_spawn_marker(world_pos)):
			# 中键或右键空白处：拖拽平移
			if mb.pressed:
				_dragging_cam = true
				_drag_last_screen = mb.position
				_cancel_add_mode()
			else:
				_dragging_cam = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if not _add_mode.is_empty():
					_add_spawn_at(world_pos, _add_mode)
					_add_mode = ""
					_status.text = "已添加刷怪点"
					return
				var spawn_id := _find_spawn_at(world_pos)
				if spawn_id == PLAYER_SPAWN_ID:
					# 拖拽玩家出生点
					_dragging_player_spawn = true
					_dragging_spawn = false
					_selected_spawn_id = ""
					_refresh_spawn_list()
					_refresh_spawn_props()
					_refresh_markers()
				elif not spawn_id.is_empty():
					_selected_spawn_id = spawn_id
					_dragging_spawn = true
					_drag_last_screen = mb.position
					_refresh_spawn_list()
					_refresh_spawn_props()
					_refresh_markers()
				else:
					# 点空白：取消选中
					_selected_spawn_id = ""
					_dragging_player_spawn = false
					_refresh_spawn_list()
					_refresh_spawn_props()
					_refresh_markers()
			else:
				_dragging_spawn = false
				_dragging_player_spawn = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# 右键刷怪点：删除（玩家出生点不可删）
			var spawn_id := _find_spawn_at(world_pos)
			if spawn_id != PLAYER_SPAWN_ID and not spawn_id.is_empty():
				_selected_spawn_id = spawn_id
				_on_delete_spawn()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_cam:
			_pan_offset += mm.relative
			_apply_view_transform()
		elif _dragging_player_spawn:
			# 拖动玩家出生点
			var world_pos := _screen_to_world(mm.position)
			if not _current_level_id.is_empty():
				var level: Dictionary = _levels.get(_current_level_id, {})
				level["spawn_x"] = int(world_pos.x)
				level["spawn_y"] = int(world_pos.y)
				_levels[_current_level_id] = level
				# 同步左栏 SpinBox（避免回写触发循环）
				_loading = true
				_spawn_x_spin.value = int(world_pos.x)
				_spawn_y_spin.value = int(world_pos.y)
				_loading = false
				_refresh_markers()
		elif _dragging_spawn and not _selected_spawn_id.is_empty():
			var world_pos := _screen_to_world(mm.position)
			var entry := _get_selected_spawn()
			if not entry.is_empty():
				entry["x"] = world_pos.x
				entry["y"] = world_pos.y
				_update_selected_spawn(entry)
				_refresh_spawn_props()
				_refresh_markers()
	elif event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and ek.keycode == KEY_ESCAPE:
			_cancel_add_mode()
		elif ek.pressed and ek.keycode == KEY_DELETE:
			if not _selected_spawn_id.is_empty():
				_on_delete_spawn()


## 屏幕（视口容器内）坐标 → 世界坐标
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - _pan_offset) / maxf(0.0001, _zoom)


## 世界坐标 → 屏幕坐标
func _world_to_screen(world_pos: Vector2) -> Vector2:
	return world_pos * _zoom + _pan_offset


func _is_clicking_spawn_marker(world_pos: Vector2) -> bool:
	return not _find_spawn_at(world_pos).is_empty()


## 返回世界坐标处命中的标记 ID（容差按当前缩放调整）。
## 返回 PLAYER_SPAWN_ID 表示玩家出生点；否则返回刷怪点 spawn_id；空字符串表示未命中。
func _find_spawn_at(world_pos: Vector2) -> String:
	if _current_level_id.is_empty():
		return ""
	var level: Dictionary = _levels.get(_current_level_id, {})
	var best_id := ""
	var best_dist := _marker_radius / _zoom
	# 优先检测玩家出生点
	var player_pos := Vector2(float(level.get("spawn_x", 0)), float(level.get("spawn_y", 0)))
	var pd := player_pos.distance_to(world_pos)
	if pd <= best_dist:
		best_dist = pd
		best_id = PLAYER_SPAWN_ID
	for entry_value in level.get("enemies", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var p := Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
		var d := p.distance_to(world_pos)
		if d <= best_dist:
			best_dist = d
			best_id = String(entry.get("spawn_id", ""))
	return best_id


# ============================================================
# 刷怪点标记绘制（由 _markers_node._draw 调用）
# ============================================================

func _refresh_markers() -> void:
	if is_instance_valid(_markers_node):
		_markers_node.queue_redraw()


func _draw_markers(canvas_item: CanvasItem) -> void:
	if _current_level_id.is_empty():
		return
	var level: Dictionary = _levels.get(_current_level_id, {})
	# 网格
	if _show_grid:
		var vp_size := _viewport_container.size
		# 网格在 world_root 局部坐标里画，因此用世界范围
		var visible_world := Rect2(
			_screen_to_world(Vector2.ZERO),
			_screen_to_world(vp_size) - _screen_to_world(Vector2.ZERO)
		)
		var start_x := floorf(visible_world.position.x / GRID_SIZE) * GRID_SIZE
		var end_x := visible_world.position.x + visible_world.size.x
		var start_y := floorf(visible_world.position.y / GRID_SIZE) * GRID_SIZE
		var end_y := visible_world.position.y + visible_world.size.y
		var grid_color := Color(1, 1, 1, 0.18)
		var x := start_x
		while x <= end_x:
			canvas_item.draw_line(Vector2(x, start_y), Vector2(x, end_y), grid_color, 1.0 / _zoom)
			x += GRID_SIZE
		var y := start_y
		while y <= end_y:
			canvas_item.draw_line(Vector2(start_x, y), Vector2(end_x, y), grid_color, 1.0 / _zoom)
			y += GRID_SIZE
	# 玩家出生点
	var spawn_pos := Vector2(float(level.get("spawn_x", 0)), float(level.get("spawn_y", 0)))
	_draw_player_spawn_marker(canvas_item, spawn_pos)
	# 刷怪点
	for entry_value in level.get("enemies", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var p := Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
		var spawn_id := String(entry.get("spawn_id", ""))
		var enemy_id := int(entry.get("enemy_id", 0))
		var ename := _enemy_display_name(enemy_id)
		var mode := String(entry.get("mode", "point"))
		var is_selected := spawn_id == _selected_spawn_id
		var color := Color("ff6b6b") if mode == "point" else Color("f7b955")
		var ring_radius := _marker_radius / _zoom
		# 散布范围框（scatter_x 有值时绘制，不限模式）
		var scatter_x := float(entry.get("scatter_x", 0.0))
		if scatter_x > 0.0:
			var count := int(entry.get("count", 1))
			# 散布只影响 X 方向，高度固定为略大于圆点
			var box_half_h := ring_radius + 6.0 / _zoom
			var band_color := Color(color.r, color.g, color.b, 0.10)
			var border_color := Color(color.r, color.g, color.b, 0.7)
			var line_w := 2.0 / _zoom
			var rect := Rect2(p.x - scatter_x, p.y - box_half_h, scatter_x * 2, box_half_h * 2)
			# 半透明填充
			canvas_item.draw_rect(rect, band_color, true)
			# 实线边框
			canvas_item.draw_rect(rect, border_color, false, line_w)
			# 中心十字（标记中心点）
			var cross_len := 6.0 / _zoom
			canvas_item.draw_line(p - Vector2(cross_len, 0), p + Vector2(cross_len, 0), border_color, line_w)
			canvas_item.draw_line(p - Vector2(0, cross_len), p + Vector2(0, cross_len), border_color, line_w)
			# 散布范围文字（框上方）
			var font := ThemeDB.fallback_font
			var font_size := maxi(8, int(10.0 / _zoom))
			var scatter_label := "±%dpx" % int(scatter_x)
			canvas_item.draw_string(font, Vector2(p.x - scatter_x, p.y - box_half_h - 2.0 / _zoom), scatter_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color.r, color.g, color.b, 0.9))
			# 数量角标（右上角小圆 + 数字，仅 group 且数量>1）
			if mode == "group" and count > 1:
				var badge_r := 8.0 / _zoom
				var badge_pos := p + Vector2(ring_radius * 0.7, -ring_radius * 0.7)
				canvas_item.draw_circle(badge_pos, badge_r, Color("ff5252"))
				canvas_item.draw_circle(badge_pos, badge_r, Color(1, 1, 1, 0.6), false, 1.0 / _zoom)
				var badge_font_size := maxi(7, int(9.0 / _zoom))
				var count_text := str(count)
				var text_w := font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_CENTER, -1, badge_font_size).x
				canvas_item.draw_string(font, badge_pos - Vector2(text_w * 0.5, -badge_font_size * 0.3), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_font_size, Color.WHITE)
		# 标记圆
		if is_selected:
			canvas_item.draw_circle(p, ring_radius + 4.0 / _zoom, Color("ffffff", 0.5))
		canvas_item.draw_circle(p, ring_radius, color)
		canvas_item.draw_circle(p, ring_radius, Color(1, 1, 1, 0.9), false, 2.0 / _zoom)
		# 怪物缩略图
		var tex := _get_enemy_preview_texture(enemy_id)
		if tex != null:
			var tex_size := tex.get_size()
			var max_dim := (_marker_radius * 1.8) / _zoom
			var s := minf(max_dim / tex_size.x, max_dim / tex_size.y)
			var draw_size := tex_size * s
			canvas_item.draw_texture_rect(tex, Rect2(p - draw_size * 0.5, draw_size), false)
		# 标签
		var count_str := ""
		if mode == "group":
			count_str = " x%d" % int(entry.get("count", 1))
		var label_line1 := "%s%s" % [ename, count_str]
		var label_line2 := "[%s]" % str(enemy_id)
		var font := ThemeDB.fallback_font
		var font_size := int(12.0 / _zoom)
		font_size = maxi(8, font_size)
		var label_offset := Vector2(ring_radius + 4.0 / _zoom, -ring_radius - 4.0 / _zoom)
		# 背景描边（便于阅读）
		for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			canvas_item.draw_string(font, p + label_offset + offset / _zoom, label_line1, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
			canvas_item.draw_string(font, p + label_offset + offset / _zoom + Vector2(0, font_size), label_line2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
		canvas_item.draw_string(font, p + label_offset, label_line1, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))
		canvas_item.draw_string(font, p + label_offset + Vector2(0, font_size), label_line2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))


## 绘制玩家出生点标记：菱形 + 十字 + 标签，区别于圆形刷怪点。
func _draw_player_spawn_marker(canvas_item: CanvasItem, p: Vector2) -> void:
	var r := _marker_radius / _zoom
	var color := Color("4ea7ff")
	# 外圈高亮（被拖拽时）
	if _dragging_player_spawn:
		canvas_item.draw_circle(p, r + 5.0 / _zoom, Color(1, 1, 1, 0.4))
	# 菱形
	var pts := PackedVector2Array([
		p + Vector2(0, -r),
		p + Vector2(r, 0),
		p + Vector2(0, r),
		p + Vector2(-r, 0),
	])
	canvas_item.draw_colored_polygon(pts, color)
	canvas_item.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.9), 2.0 / _zoom)
	# 十字
	var cross := r * 0.5
	canvas_item.draw_line(p + Vector2(-cross, 0), p + Vector2(cross, 0), Color(1, 1, 1, 0.8), 1.5 / _zoom)
	canvas_item.draw_line(p + Vector2(0, -cross), p + Vector2(0, cross), Color(1, 1, 1, 0.8), 1.5 / _zoom)
	# 标签
	var font := ThemeDB.fallback_font
	var font_size := maxi(8, int(12.0 / _zoom))
	var label := "玩家出生点"
	# 描边
	for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		canvas_item.draw_string(font, p + Vector2(r + 4.0 / _zoom, r * 0.3) + offset / _zoom, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
	canvas_item.draw_string(font, p + Vector2(r + 4.0 / _zoom, r * 0.3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## 获取怪物 idle 第一帧作为缩略图（带缓存）。
func _get_enemy_preview_texture(enemy_id: int) -> Texture2D:
	if _preview_textures.has(enemy_id):
		return _preview_textures[enemy_id]
	if _enemies_cfg.is_empty():
		return null
	var id_str := str(enemy_id)
	if not _enemies_cfg.has(id_str):
		return null
	var enemy: Dictionary = _enemies_cfg[id_str]
	var asset := String(enemy.get("asset", ""))
	if asset.is_empty():
		_preview_textures[enemy_id] = null
		return null
	var sf_path := asset.path_join("godot/spriteframes.tres")
	if not ResourceLoader.exists(sf_path):
		_preview_textures[enemy_id] = null
		return null
	var sf := load(sf_path) as SpriteFrames
	if sf == null or not sf.has_animation("idle") or sf.get_frame_count("idle") == 0:
		_preview_textures[enemy_id] = null
		return null
	var tex := sf.get_frame_texture("idle", 0)
	_preview_textures[enemy_id] = tex
	return tex


func _enemy_display_name(enemy_id: int) -> String:
	var id_str := str(enemy_id)
	if _enemies_cfg.has(id_str):
		return String(_enemies_cfg[id_str].get("name", id_str))
	return "未知#%d" % enemy_id


# ============================================================
# 保存与放弃
# ============================================================

func _on_save() -> void:
	var error := _validate_all()
	if not error.is_empty():
		_status.text = "校验失败：%s" % error
		return
	# 落盘前清理引用了已删除怪物的刷怪点
	var removed_count := _cleanup_orphaned_spawns()
	# 落盘前再次规范化字段
	for id_str in _levels:
		_levels[id_str]["enemies"] = _normalize_enemies(_levels[id_str].get("enemies", []))
	var data: Dictionary = {}
	var keys: Array = _levels.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var level: Dictionary = _levels[key]
		data[key] = {
			"name": String(level.get("name", "")),
			"scene_path": String(level.get("scene_path", "")),
			"spawn_x": int(level.get("spawn_x", 0)),
			"spawn_y": int(level.get("spawn_y", 0)),
			"bgm": String(level.get("bgm", "")),
			"description": String(level.get("description", "")),
			"enemies": level.get("enemies", []),
		}
	var file := FileAccess.open(LEVELS_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "无法写入 levels.json"
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	# 同步内存中的 LevelConfig
	var lc = GameRegistry.get("level_config") if GameRegistry.get("level_config") != null else null
	if lc != null and lc.has_method("load_config"):
		lc.load_config()
	var msg := "已保存 levels.json（%d 个关卡）" % data.size()
	if removed_count > 0:
		msg += "，清理了 %d 个引用已删除怪物的刷怪点" % removed_count
		_refresh_spawn_list()
		_refresh_markers()
	_status.text = msg
	_show_toast("保存成功")
	# 刷新文件系统
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _on_discard() -> void:
	_levels.clear()
	_enemies_cfg.clear()
	_preview_textures.clear()
	_current_level_id = ""
	_selected_spawn_id = ""
	_load_data()
	_refresh_level_list()
	_status.text = "已放弃未保存修改。"


## 居中浮层提示，1.5 秒后自动消失。
func _show_toast(text_value: String) -> void:
	if _toast == null:
		return
	_toast.text = text_value
	_toast.visible = true
	_toast_timer.stop()
	_toast_timer.start()


## 校验所有关卡数据。返回非空字符串表示有错误，阻止保存。
## 注意：引用已删除怪物的刷怪点不在此处阻止保存，而是在保存时自动清理。
func _validate_all() -> String:
	for id_str in _levels:
		var level: Dictionary = _levels[id_str]
		var scene_path := String(level.get("scene_path", ""))
		if scene_path.is_empty():
			return "关卡 %s 未配置场景路径" % id_str
		if not ResourceLoader.exists(scene_path):
			return "关卡 %s 场景不存在：%s" % [id_str, scene_path]
		var enemies: Array = level.get("enemies", [])
		for entry_value in enemies:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var mode := String(entry.get("mode", "point"))
			if mode == "group":
				var count := int(entry.get("count", 1))
				if count < 1:
					return "关卡 %s 随机组 %s 数量必须 ≥ 1" % [id_str, String(entry.get("spawn_id", ""))]
	return ""


## 清理所有关卡中引用了已删除怪物的刷怪点，返回被清理的条数。
func _cleanup_orphaned_spawns() -> int:
	var removed := 0
	for id_str in _levels:
		var level: Dictionary = _levels[id_str]
		var enemies: Array = level.get("enemies", [])
		var kept: Array = []
		for entry_value in enemies:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var enemy_id := int(entry.get("enemy_id", 0))
			if not _enemies_cfg.has(str(enemy_id)):
				removed += 1
				continue
			kept.append(entry)
		level["enemies"] = kept
	return removed


# ============================================================
# 内部类：刷怪点标记绘制
# ============================================================

class LevelMarkersOverlay:
	extends Node2D
	var editor: Node = null  # 指向 LevelEditor，避免循环依赖

	func _draw() -> void:
		if editor == null or not editor.has_method("_draw_markers"):
			return
		editor._draw_markers(self)


# ============================================================
# 内部类：怪物库（可拖拽到地图）
# ============================================================

class EnemyPaletteList:
	extends ItemList
	var editor: Node = null

	func _get_drag_data(_pos: Vector2) -> Variant:
		var idx := get_item_at_position(_pos, true)
		if idx < 0:
			return null
		var enemy_id := int(get_item_metadata(idx))
		# 拖拽预览
		var preview := Label.new()
		preview.text = "放置: %s" % get_item_text(idx)
		preview.add_theme_color_override("font_color", Color.WHITE)
		preview.add_theme_stylebox_override("normal", _make_preview_style())
		set_drag_preview(preview)
		return {
			"type": "enemy_spawn",
			"enemy_id": enemy_id,
		}

	static func _make_preview_style() -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.1, 0.1, 0.12, 0.9)
		s.border_color = Color(0.4, 0.6, 1.0, 0.9)
		s.set_border_width_all(1)
		s.set_content_margin_all(6)
		return s


# ============================================================
# 内部类：地图视口容器（接受拖拽放置）
# ============================================================

class MapViewportContainer:
	extends SubViewportContainer
	var editor: Node = null


# ============================================================
# 内部类：拖放覆盖层（SubViewportContainer 不触发拖放，需用 Control 覆盖层接收）
# ============================================================

class DropOverlay:
	extends Control
	var editor: Node = null

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if editor == null or not editor.has_method("_can_drop_spawn_at"):
			return false
		return editor._can_drop_spawn_at(_pos, data)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if editor == null or not editor.has_method("_drop_spawn_at"):
			return
		editor._drop_spawn_at(_pos, data)
