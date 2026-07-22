@tool
extends Window

const SKILLS_PATH := "res://data/skills.json"
const CHARACTERS_PATH := "res://data/characters.json"
const ENEMIES_PATH := "res://data/enemies.json"
const BUFFS_PATH := "res://data/buffs.json"
const SKILL_FX_ROOT := "res://assets/skill_fx"
const SkillTimeline = preload("res://addons/game_tools/skill_timeline.gd")
const CombatActionPreview = preload("res://addons/game_tools/combat_action_preview.gd")

const ACTION_TYPES := {
	"play_animation": "播放动画",
	"melee_damage": "近战伤害（判定框）",
	"area_damage": "范围伤害",
	"fullscreen_damage": "全场伤害",
	"spawn_projectile": "发射弹道",
	"play_effect": "播放特效",
	"apply_target_buff": "施加目标 Buff",
	"apply_self_buff": "施加自身 Buff",
	"heal": "治疗",
	"move_x": "水平移动",
}
const CONTROL_TYPES := {
	"wait_action_event": "等待动作事件",
	"wait_action_frame": "等待动作帧",
	"wait_hit_window": "等待攻击有效区间",
	"wait_animation_end": "等待动画结束",
	"wait_time": "等待时长",
	"end_skill": "结束技能",
}
const ORIGIN_OPTIONS := [
	{"value": "hit_window", "label": "当前有效区间中心"},
	{"value": "caster", "label": "施法者中心"},
	{"value": "socket", "label": "指定 Socket"},
	{"value": "nearest_enemy", "label": "最近敌人"},
]
const TARGET_OPTIONS := [
	{"value": "origin", "label": "节点出生位置"},
	{"value": "result", "label": "命名结果集"},
	{"value": "nearest_enemy", "label": "最近敌人"},
	{"value": "area", "label": "范围内敌人"},
	{"value": "all_enemies", "label": "全部敌人"},
]
const ATTACHMENT_LAYER_OPTIONS := [
	{"value": "front", "label": "角色前"},
	{"value": "behind", "label": "角色后"},
]
const COORD_SPACE_OPTIONS := [
	{"value": "world", "label": "世界坐标（挂场景根，受相机影响）"},
	{"value": "character_local", "label": "角色本地坐标（跟随角色移动）"},
	{"value": "fullscreen", "label": "全屏覆盖（挂 UIRoot.ScreenLayer，铺满屏幕）"},
]

## 请求打开 Buff 配置编辑器并选中指定 buff_id（<=0 表示不指定）。
signal request_open_buff(buff_id: int)

var _skills: Dictionary = {}
var _characters_config: Dictionary = {}
var _enemies_config: Dictionary = {}
var _current_skill_id := ""
var _current_hero_key := ""
var _action_data: Dictionary = {}
var _loading := false

# 左侧角色/怪物库
var _entity_tab_bar: TabBar
var _entity_list: ItemList
var _list_label: Label
var _left_panel: VBoxContainer
var _divider: Panel
var _current_entity_tab := 0  # 0=角色, 1=怪物
var _dragging_divider := false
var _preview_textures: Dictionary = {}  # id_str -> Texture2D
const _LEFT_MIN_WIDTH := 150.0
const _LEFT_MAX_WIDTH := 560.0

var _skill_select: OptionButton
var _skill_name_edit: LineEdit
var _name_edit: LineEdit
var _description_edit: LineEdit
var _cooldown_spin: SpinBox
var _node_list: ItemList
var _action_picker: OptionButton
var _control_picker: OptionButton
var _node_details: VBoxContainer
var _timeline: SkillTimeline
var _frame_slider: HSlider
var _status: Label

var _preview: CombatActionPreview
var _play_button: Button
var _is_playing := false
var _play_fps := 10.0
var _play_accumulator := 0.0
var _sprite_frames: SpriteFrames
var _preview_action := "attack"
var _visual_transform: Dictionary = {}
var _sprite_scale := 1.0

# apply_self_buff 节点详情中的特效控件引用（拖拽回写时同步显示）
var _effect_offset_x_spin: SpinBox
var _effect_offset_y_spin: SpinBox
var _effect_scale_slider: HSlider
var _effect_scale_spin: SpinBox
var _skill_fx_dialog: ConfirmationDialog
var _skill_fx_dialog_text: RichTextLabel
var _skill_fx_file_dialog: FileDialog
var _pending_skill_fx_import: Dictionary = {}


func _init() -> void:
	title = "技能节点配置"
	size = Vector2i(1280, 860)
	min_size = Vector2i(1040, 700)
	close_requested.connect(_on_close_requested)
	set_process(false)


func _on_close_requested() -> void:
	_is_playing = false
	set_process(false)
	hide()


func _ready() -> void:
	_build_ui()
	_load_skills()
	_load_character_configs()
	_refresh_entity_list()
	_rebuild_skill_select()


func open_editor() -> void:
	if _skill_select == null:
		_build_ui()
	_load_skills()
	_load_character_configs()
	_refresh_entity_list()
	_rebuild_skill_select()
	popup_centered(size)
	mode = Window.MODE_MAXIMIZED


func _build_ui() -> void:
	if _skill_select != null:
		return
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)
	# === 左侧角色/怪物库 ===
	_left_panel = VBoxContainer.new()
	_left_panel.custom_minimum_size = Vector2(320, 0)
	_left_panel.add_theme_constant_override("separation", 4)
	main.add_child(_left_panel)
	_entity_tab_bar = TabBar.new()
	_entity_tab_bar.add_tab("角色")
	_entity_tab_bar.add_tab("怪物")
	_entity_tab_bar.tab_changed.connect(_on_entity_tab_changed)
	_left_panel.add_child(_entity_tab_bar)
	_list_label = Label.new()
	_list_label.text = "角色列表"
	_left_panel.add_child(_list_label)
	_entity_list = ItemList.new()
	_entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entity_list.icon_mode = ItemList.ICON_MODE_TOP
	_entity_list.max_columns = 2
	_entity_list.fixed_icon_size = Vector2i(72, 72)
	_entity_list.fixed_column_width = 150
	_entity_list.same_column_width = true
	_entity_list.item_selected.connect(_on_entity_selected)
	_left_panel.add_child(_entity_list)
	# === 分隔条 ===
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
	# === 右侧编辑区 ===
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)
	var skill_row := HBoxContainer.new()
	right.add_child(skill_row)
	var label := Label.new()
	label.text = "技能"
	skill_row.add_child(label)
	_skill_select = OptionButton.new()
	_skill_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_select.item_selected.connect(_on_skill_selected)
	skill_row.add_child(_skill_select)
	var name_label := Label.new()
	name_label.text = "名称"
	skill_row.add_child(name_label)
	_skill_name_edit = LineEdit.new()
	_skill_name_edit.custom_minimum_size.x = 140
	_skill_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_skill_name_edit.text_changed.connect(_on_skill_name_changed)
	skill_row.add_child(_skill_name_edit)
	var new_skill_btn := Button.new()
	new_skill_btn.text = "新增技能"
	new_skill_btn.pressed.connect(_add_new_skill)
	skill_row.add_child(new_skill_btn)
	var del_skill_btn := Button.new()
	del_skill_btn.text = "删除技能"
	del_skill_btn.pressed.connect(_delete_current_skill)
	skill_row.add_child(del_skill_btn)
	var save := Button.new()
	save.text = "保存 skills.json"
	save.pressed.connect(_save_skills)
	skill_row.add_child(save)
	var import_fx := Button.new()
	import_fx.text = "导入 AI 特效包"
	import_fx.tooltip_text = "查找当前技能的独立特效包，校验后自动生成或更新 play_effect 节点"
	import_fx.pressed.connect(_open_skill_fx_bundle)
	skill_row.add_child(import_fx)

	# 基础信息（技能名称已在上方 skill_row，此处放描述和冷却）
	var base_grid := GridContainer.new()
	base_grid.columns = 2
	base_grid.add_theme_constant_override("h_separation", 12)
	base_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(base_grid)
	_description_edit = _add_line(base_grid, "技能描述", "description")
	_cooldown_spin = _add_spin(base_grid, "冷却时间", "cooldown", 0.0, 0.0, 999.0, 0.1)
	_name_edit = _skill_name_edit  # 复用 skill_row 的名称输入框，避免重复
	# 不再分页，直接把编排内容放到 right 下方
	var sequence_page := VBoxContainer.new()
	sequence_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sequence_page.add_theme_constant_override("separation", 6)
	right.add_child(sequence_page)
	var preview_timeline_row := HBoxContainer.new()
	preview_timeline_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sequence_page.add_child(preview_timeline_row)
	var preview_col := VBoxContainer.new()
	preview_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_timeline_row.add_child(preview_col)
	_preview = CombatActionPreview.new()
	_preview.custom_minimum_size = Vector2(280, 220)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.effect_offset_changed.connect(_on_effect_offset_changed)
	preview_col.add_child(_preview)
	var frame_row := HBoxContainer.new()
	preview_col.add_child(frame_row)
	var frame_label := Label.new()
	frame_label.text = "帧"
	frame_row.add_child(frame_label)
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0
	_frame_slider.max_value = 7
	_frame_slider.step = 1
	_frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_slider.value_changed.connect(_on_frame_changed)
	frame_row.add_child(_frame_slider)
	var prev_frame_btn := Button.new()
	prev_frame_btn.text = "◀"
	prev_frame_btn.tooltip_text = "上一帧"
	prev_frame_btn.pressed.connect(_prev_frame)
	frame_row.add_child(prev_frame_btn)
	var next_frame_btn := Button.new()
	next_frame_btn.text = "▶"
	next_frame_btn.tooltip_text = "下一帧"
	next_frame_btn.pressed.connect(_next_frame)
	frame_row.add_child(next_frame_btn)
	_play_button = Button.new()
	_play_button.text = "播放"
	_play_button.toggle_mode = true
	_play_button.toggled.connect(_on_play_toggled)
	frame_row.add_child(_play_button)
	_timeline = SkillTimeline.new()
	_timeline.custom_minimum_size = Vector2(300, 220)
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.frame_selected.connect(_on_timeline_frame_selected)
	_timeline.node_selected.connect(_on_timeline_node_selected)
	preview_timeline_row.add_child(_timeline)
	_node_list = ItemList.new()
	_node_list.custom_minimum_size.y = 120
	_node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_list.item_selected.connect(_on_node_selected)
	sequence_page.add_child(_node_list)
	var order := HBoxContainer.new()
	sequence_page.add_child(order)
	_add_button(order, "上移", _move_node.bind(-1))
	_add_button(order, "下移", _move_node.bind(1))
	_add_button(order, "删除选中", _delete_selected_node)
	var add_row := HBoxContainer.new()
	sequence_page.add_child(add_row)
	var action_label := Label.new()
	action_label.text = "新增动作节点"
	add_row.add_child(action_label)
	_action_picker = _make_type_picker(ACTION_TYPES)
	add_row.add_child(_action_picker)
	_add_button(add_row, "新增动作", _add_action_node)
	var control_label := Label.new()
	control_label.text = "新增控制节点"
	add_row.add_child(control_label)
	_control_picker = _make_type_picker(CONTROL_TYPES)
	add_row.add_child(_control_picker)
	_add_button(add_row, "新增控制", _add_control_node)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size.y = 180
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sequence_page.add_child(detail_scroll)
	_node_details = VBoxContainer.new()
	_node_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_node_details)
	var presets := GridContainer.new()
	presets.columns = 5
	sequence_page.add_child(presets)
	_add_button(presets, "套用普攻", _apply_melee_template)
	_add_button(presets, "套用单发弹道", _apply_projectile_template)
	_add_button(presets, "套用范围伤害", _apply_area_template)
	_add_button(presets, "套用全场伤害", _apply_fullscreen_template)
	_add_button(presets, "套用自身 Buff", _apply_self_buff_template)
	_add_button(presets, "套用三连弹道", _apply_sequence_template)
	_add_button(presets, "套用向上箭雨", _apply_rain_template)
	_add_button(presets, "套用近战+自Buff", _apply_melee_self_buff_template)
	_add_button(presets, "套用群体Buff", _apply_area_buff_template)
	_add_button(presets, "套用扇形弹道", _apply_fan_projectile_template)
	_add_button(presets, "套用事件Buff", _apply_event_buff_template)
	_add_button(presets, "套用大招", _apply_ultimate_template)
	_add_button(presets, "套用抛射弹道", _apply_ballistic_projectile_template)
	_add_button(presets, "套用位移", _apply_dash_template)
	_add_button(presets, "清空节点", _clear_nodes)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)


func _add_button(parent: Container, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)


func _make_type_picker(values: Dictionary) -> OptionButton:
	var picker := OptionButton.new()
	for type_name in values:
		# 统一显示格式：英文值 (中文注解)
		var type_label := String(values[type_name])
		var display := "%s (%s)" % [type_name, type_label]
		picker.add_item(display)
		picker.set_item_metadata(picker.item_count - 1, type_name)
	return picker


func _add_line(parent: GridContainer, label_text: String, field: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(_on_skill_text_changed.bind(field))
	parent.add_child(edit)
	return edit


func _add_spin(parent: GridContainer, label_text: String, field: String, default_value: float, minimum: float, maximum: float, step_value: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = default_value
	spin.value_changed.connect(_on_skill_number_changed.bind(field))
	parent.add_child(spin)
	return spin


func _load_skills() -> void:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.READ)
	if file == null:
		_skills = {}
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_status.text = "无法解析 skills.json"
		_skills = {}
		return
	_skills = (json.data as Dictionary).duplicate(true)


func _load_character_configs() -> void:
	_characters_config = _read_json(CHARACTERS_PATH).duplicate(true)
	_enemies_config = _read_json(ENEMIES_PATH).duplicate(true)


## 刷新左侧角色/怪物库列表（按 ID 排序，2 列网格 + 预览图标）。
## 未配置任何技能的实体前加「⚠」标识，方便识别待配置项。
func _refresh_entity_list() -> void:
	if _entity_list == null:
		return
	_entity_list.clear()
	var data: Dictionary = _characters_config if _current_entity_tab == 0 else _enemies_config
	var keys: Array = data.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var id_str := String(key)
		var config: Dictionary = data[id_str]
		var display_name := String(config.get("name", id_str))
		var meta := "char:%s" % id_str if _current_entity_tab == 0 else "enemy:%s" % id_str
		# 检查是否配置过技能（不含自动分配的 normal_skill）
		var has_skills := _entity_has_skills(config)
		var label_text: String
		var tooltip_text := ""
		if has_skills:
			label_text = "%s  %s" % [id_str, display_name]
		else:
			label_text = "⚠ %s  %s" % [id_str, display_name]
			tooltip_text = "该实体尚未配置任何技能，请点击后在右侧添加技能"
		_entity_list.add_item(label_text)
		_entity_list.set_item_metadata(_entity_list.item_count - 1, meta)
		if not tooltip_text.is_empty():
			_entity_list.set_item_tooltip(_entity_list.item_count - 1, tooltip_text)
		var tex := _get_entity_preview_texture(id_str, config)
		if tex != null:
			_entity_list.set_item_icon(_entity_list.item_count - 1, tex)
			# 未配置技能的实体图标加红色色调提示
			if not has_skills:
				_entity_list.set_item_icon_modulate(_entity_list.item_count - 1, Color(1.0, 0.6, 0.4))
	# 恢复选中
	if not _current_hero_key.is_empty():
		for i in range(_entity_list.item_count):
			if String(_entity_list.get_item_metadata(i)) == _current_hero_key:
				_entity_list.select(i)
				break


## 判断实体是否配置过技能（不含自动分配的 normal_skill）：
## skills 数组非空，或 skill_unlocks 中有技能 ID
func _entity_has_skills(config: Dictionary) -> bool:
	var skills_arr: Array = config.get("skills", [])
	if not skills_arr.is_empty():
		return true
	var unlocks: Dictionary = config.get("skill_unlocks", {})
	for slot in unlocks.values():
		if slot is Dictionary:
			var sid := int(slot.get("skill_id", 0))
			if sid > 0:
				return true
	return false


## 加载实体 idle 动画第一帧作为缩略图。失败时缓存 null 避免重复加载。
func _get_entity_preview_texture(id_str: String, config: Dictionary) -> Texture2D:
	if _preview_textures.has(id_str):
		return _preview_textures[id_str]
	var asset := String(config.get("asset", ""))
	if asset.is_empty():
		_preview_textures[id_str] = null
		return null
	var sf_path := asset.path_join("godot/spriteframes.tres")
	if not ResourceLoader.exists(sf_path):
		_preview_textures[id_str] = null
		return null
	var sf := load(sf_path) as SpriteFrames
	if sf == null or not sf.has_animation("idle") or sf.get_frame_count("idle") == 0:
		_preview_textures[id_str] = null
		return null
	var tex := sf.get_frame_texture("idle", 0)
	_preview_textures[id_str] = tex
	return tex


## Tab 切换：刷新列表标题和内容。
func _on_entity_tab_changed(tab: int) -> void:
	_current_entity_tab = tab
	_list_label.text = "角色列表" if tab == 0 else "怪物列表"
	_refresh_entity_list()


## 列表选中：设置 _current_hero_key 并刷新技能下拉。
func _on_entity_selected(idx: int) -> void:
	if idx < 0 or idx >= _entity_list.item_count:
		return
	_current_hero_key = String(_entity_list.get_item_metadata(idx))
	_current_skill_id = ""
	_rebuild_skill_select()


## 拖动分隔条调整左列宽度。
func _on_divider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_divider = event.pressed
	elif event is InputEventMouseMotion and _dragging_divider:
		var w: float = _left_panel.size.x + event.relative.x
		w = clampf(w, _LEFT_MIN_WIDTH, _LEFT_MAX_WIDTH)
		_left_panel.custom_minimum_size.x = w


func _get_hero_skill_ids(hero_key: String) -> Array:
	if hero_key.is_empty():
		return _skills.keys()
	var parts := hero_key.split(":")
	if parts.size() < 2:
		return []
	var config_type := parts[0]
	var hero_id := parts[1]
	var config: Dictionary
	if config_type == "char":
		config = _characters_config.get(hero_id, {})
	elif config_type == "enemy":
		config = _enemies_config.get(hero_id, {})
	else:
		return []
	var ids: Array = []
	var normal := int(config.get("normal_skill", 0))
	if normal > 0:
		ids.append(str(normal))
	for value in config.get("skills", []):
		var sid := str(int(value))
		if not ids.has(sid):
			ids.append(sid)
	for slot in (config.get("skill_unlocks", {}) as Dictionary).values():
		if slot is Dictionary:
			var sid := str(int(slot.get("skill_id", 0)))
			if not sid == "0" and not ids.has(sid):
				ids.append(sid)
	return ids


func _rebuild_skill_select() -> void:
	if _skill_select == null:
		return
	_skill_select.clear()
	var ids: Array
	if _current_hero_key.is_empty():
		ids = _skills.keys()
	else:
		ids = _get_hero_skill_ids(_current_hero_key)
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for id_value in ids:
		var skill: Dictionary = _skills.get(id_value, {})
		_skill_select.add_item("%s  %s" % [id_value, String(skill.get("name", "未命名技能"))])
		_skill_select.set_item_metadata(_skill_select.item_count - 1, String(id_value))
	if _skill_select.item_count > 0:
		var index := 0
		for candidate in range(_skill_select.item_count):
			if String(_skill_select.get_item_metadata(candidate)) == _current_skill_id:
				index = candidate
		_skill_select.select(index)
		_on_skill_selected(index)
	else:
		_current_skill_id = ""
		_clear_node_details()
		if _timeline != null:
			_timeline.set_timeline({}, [], 8, 0, -1)


func _on_skill_selected(index: int) -> void:
	if index < 0 or index >= _skill_select.item_count:
		return
	_current_skill_id = String(_skill_select.get_item_metadata(index))
	_load_skill_fields()
	_load_action_data()
	_refresh_all()


func _current_skill() -> Dictionary:
	return _skills.get(_current_skill_id, {})


func _load_skill_fields() -> void:
	var skill := _current_skill()
	_loading = true
	_name_edit.text = String(skill.get("name", ""))
	_skill_name_edit.text = String(skill.get("name", ""))
	_description_edit.text = String(skill.get("description", ""))
	_cooldown_spin.value = float(skill.get("cooldown", 0.0))
	_loading = false


func _on_skill_text_changed(value: String, field: String) -> void:
	if _loading:
		return
	_update_skill(field, value)
	if field == "name":
		_skill_name_edit.text = value
		_update_skill_select_label(_current_skill_id)


func _on_skill_name_changed(value: String) -> void:
	if _loading or _current_skill_id.is_empty():
		return
	var skill := _current_skill()
	skill["name"] = value
	_skills[_current_skill_id] = skill
	_name_edit.text = value
	_update_skill_select_label(_current_skill_id)


func _update_skill_select_label(skill_id: String) -> void:
	if _skill_select == null:
		return
	for index in range(_skill_select.item_count):
		if String(_skill_select.get_item_metadata(index)) == skill_id:
			var skill: Dictionary = _skills.get(skill_id, {})
			_skill_select.set_item_text(index, "%s  %s" % [skill_id, String(skill.get("name", "未命名技能"))])
			return


func _on_skill_number_changed(value: float, field: String) -> void:
	if _loading:
		return
	_update_skill(field, value)


func _update_skill(field: String, value: Variant) -> void:
	if _current_skill_id.is_empty():
		return
	var skill := _current_skill()
	skill[field] = value
	_skills[_current_skill_id] = skill
	if field == "name":
		_rebuild_skill_select()


func _refresh_all() -> void:
	_rebuild_node_list()
	_refresh_timeline()


func _rebuild_node_list(keep_index := -1) -> void:
	_node_list.clear()
	var nodes: Array = _current_skill().get("nodes", [])
	for index in range(nodes.size()):
		if not nodes[index] is Dictionary:
			continue
		var node: Dictionary = nodes[index]
		var type_name := String(node.get("type", ""))
		var category := "动作" if ACTION_TYPES.has(type_name) else "控制"
		_node_list.add_item("%02d  [%s] %s%s" % [index + 1, category, _node_label(type_name), _node_summary(node)])
		_node_list.set_item_tooltip(index, _node_tooltip(node))
	if _node_list.item_count > 0:
		var sel := keep_index if (keep_index >= 0 and keep_index < _node_list.item_count) else 0
		_node_list.select(sel)
		_show_node_details(sel)
	else:
		_clear_node_details()


func _node_label(type_name: String) -> String:
	return String(ACTION_TYPES.get(type_name, CONTROL_TYPES.get(type_name, type_name)))


func _node_summary(node: Dictionary) -> String:
	var type_name := String(node.get("type", ""))
	if type_name == "play_animation":
		return "  " + String(node.get("action", ""))
	if type_name == "wait_action_event":
		return "  " + String(node.get("event", ""))
	if type_name == "wait_action_frame":
		return "  帧 %d" % int(node.get("frame", 0))
	if type_name == "wait_hit_window":
		return "  #%d" % (int(node.get("hit_window_index", 0)) + 1)
	if node.has("result_key"):
		return "  -> " + String(node.get("result_key", ""))
	return ""


## 节点列表项的鼠标悬停提示：apply_self_buff / apply_target_buff 及任何带 buff_ids 的节点
## 展示 buff 名称、类别、效果、触发概率，便于一眼看清该节点会施加什么 buff。
func _node_tooltip(node: Dictionary) -> String:
	var type_name := String(node.get("type", ""))
	var buff_ids: Array = node.get("buff_ids", [])
	if buff_ids.is_empty() and not node.has("buff_id"):
		return ""
	var buffs := _read_json(BUFFS_PATH)
	var lines := PackedStringArray()
	match type_name:
		"apply_self_buff":
			lines.append("施加自身 Buff")
		"apply_target_buff":
			lines.append("施加目标 Buff（命中后挂到被击者）")
		"spawn_projectile":
			lines.append("弹道命中时附带 Buff")
		"melee_damage", "area_damage", "fullscreen_damage":
			lines.append("伤害命中时附带 Buff")
		_:
			lines.append("附带 Buff")
	var chance := float(node.get("chance", node.get("buff_chance", 1.0)))
	if chance < 1.0:
		lines.append("触发概率：%.0f%%" % (chance * 100.0))
	else:
		lines.append("触发概率：100%%")
	for id_value in buff_ids:
		var buff_id := int(id_value)
		if buff_id <= 0:
			continue
		var buff: Dictionary = buffs.get(str(buff_id), {})
		if buff.is_empty():
			lines.append("· #%d（未找到配置）" % buff_id)
			continue
		var bname := String(buff.get("name", "未命名"))
		var category := String(buff.get("category", ""))
		var desc := String(buff.get("description", ""))
		var stacks := int(buff.get("max_stacks", 1))
		var dur := float(buff.get("duration", 0.0))
		var header := "· #%d %s" % [buff_id, bname]
		if category.length() > 0:
			header += " [%s]" % category
		if stacks > 1:
			header += " 可叠%d层" % stacks
		if dur > 0.0:
			header += " %.1fs" % dur
		lines.append(header)
		if desc.length() > 0:
			lines.append("  " + desc)
	return "\n".join(lines)


func _on_node_selected(index: int) -> void:
	_show_node_details(index)
	_timeline.set_selected_node(index)
	# 选中节点变化时刷新特效预览（切到 play_effect 节点会显示其配置的特效）
	_refresh_preview()


func _selected_node_index() -> int:
	var selected := _node_list.get_selected_items()
	return int(selected[0]) if not selected.is_empty() else -1


func _clear_node_details() -> void:
	for child in _node_details.get_children():
		child.queue_free()
	_effect_offset_x_spin = null
	_effect_offset_y_spin = null
	_effect_scale_slider = null
	_effect_scale_spin = null


func _show_node_details(index: int) -> void:
	_clear_node_details()
	var nodes: Array = _current_skill().get("nodes", [])
	if index < 0 or index >= nodes.size() or not nodes[index] is Dictionary:
		return
	var node: Dictionary = nodes[index]
	var title := Label.new()
	title.text = "节点参数：%s" % _node_label(String(node.get("type", "")))
	_node_details.add_child(title)
	var form := GridContainer.new()
	form.columns = 2
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_node_details.add_child(form)
	var type_name := String(node.get("type", ""))
	match type_name:
		"play_animation": _build_animation_fields(form, node)
		"wait_action_event": _build_event_fields(form, node)
		"wait_action_frame": _build_frame_wait_fields(form, node)
		"wait_hit_window": _build_window_fields(form, node)
		"wait_time": _add_node_spin(form, "等待秒数", "seconds", node, 0.1, 0.0, 30.0, 0.05)
		"melee_damage":
			_build_damage_fields(form, node, false, false)
			_add_owner_attack_editor(form)
			_add_ai_range_readonly(form, "近战自动有效距离")
		"area_damage":
			_build_area_fields(form, node)
			_add_owner_attack_editor(form)
			_add_ai_range_readonly(form, "AOE 自动有效距离")
		"fullscreen_damage":
			_build_damage_fields(form, node, false, true)
			_add_owner_attack_editor(form)
		"spawn_projectile": _build_projectile_fields(form, node)
		"play_effect": _build_effect_fields(form, node)
		"apply_target_buff": _build_target_buff_fields(form, node)
		"apply_self_buff": _build_buff_ids_fields(form, node)
		"heal":
			_add_node_spin(form, "固定治疗", "amount", node, 0.0, 0.0, 999999.0, 1.0)
			_add_node_spin(form, "攻击倍率", "ratio", node, 0.0, 0.0, 99.0, 0.1)
		"move_x": _add_node_spin(form, "移动距离", "distance", node, 0.0, -9999.0, 9999.0, 1.0)
		_:
			var empty := Label.new()
			empty.text = "该控制节点没有额外参数。"
			form.add_child(empty)
	if type_name == "wait_action_event" and _event_names().is_empty():
		_add_external_data_warning("当前动作没有导出的事件。请在外部动作工具或 combat_actions.json 中添加事件后再使用此节点。")
	elif type_name == "wait_hit_window" and (_action_data.get("hit_windows", []) as Array).is_empty():
		_add_external_data_warning("当前动作没有攻击有效区间。请先在“配置攻击判定”中添加有效区间。")


func _add_external_data_warning(message: String) -> void:
	var warning := Label.new()
	warning.text = "提示：" + message
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_color_override("font_color", Color("ffca64"))
	_node_details.add_child(warning)


func _build_animation_fields(form: GridContainer, node: Dictionary) -> void:
	_add_node_option(form, "动作", "action", node, _action_options(), false)


func _build_event_fields(form: GridContainer, node: Dictionary) -> void:
	var options: Array = []
	for name in _event_names():
		options.append({"value": name, "label": _event_label(name)})
	if options.is_empty():
		options.append({"value": "release", "label": "release（当前动作未配置）"})
	_add_node_option(form, "动画事件", "event", node, options, false)


## 等待动作帧节点：不依赖外部 events 配置，直接按精灵当前帧推进
func _build_frame_wait_fields(form: GridContainer, node: Dictionary) -> void:
	var frame_count := _current_action_frame_count()
	var frame_spin := _add_node_spin(form, "目标帧号", "frame", node, 0.0, 0.0, float(maxi(0, frame_count - 1)), 1.0)
	# 改目标帧时同步上方动作预览：暂停播放并跳到该帧
	frame_spin.value_changed.connect(_on_frame_target_changed)
	# 只读提示当前动作帧数，避免用户输入超出范围
	var hint := Label.new()
	hint.text = "当前动作共 %d 帧（0~%d），改动会同步预览" % [frame_count, maxi(0, frame_count - 1)]
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	form.add_child(Label.new())
	form.add_child(hint)


## 等待动作帧 SpinBox 变化时：暂停播放并把上方预览帧同步到目标帧
func _on_frame_target_changed(value: float) -> void:
	# 停止播放，更新按钮状态（不触发 toggled 信号避免副作用）
	_is_playing = false
	if _play_button != null:
		_play_button.set_pressed_no_signal(false)
		_play_button.text = "播放"
	# 同步帧滑条（会触发 _on_frame_changed → 时间轴 + 预览刷新）
	if _frame_slider != null:
		_frame_slider.value = int(value)


## 读取当前预览动作的真实精灵帧数；资源未加载时回退 8
func _current_action_frame_count() -> int:
	if _sprite_frames != null and not _preview_action.is_empty() and _sprite_frames.has_animation(_preview_action):
		return _sprite_frames.get_frame_count(_preview_action)
	return 8


func _build_window_fields(form: GridContainer, node: Dictionary) -> void:
	var options: Array = []
	var windows: Array = _action_data.get("hit_windows", [])
	for index in range(windows.size()):
		options.append({"value": index, "label": "第 %d 个有效区间" % (index + 1)})
	if options.is_empty():
		options.append({"value": 0, "label": "当前动作未配置有效区间"})
	_add_node_option(form, "攻击有效区间", "hit_window_index", node, options, false)


func _build_damage_fields(form: GridContainer, node: Dictionary, include_origin: bool, include_buff: bool) -> void:
	_add_result_key(form, node)
	if include_origin:
		_add_origin_fields(form, node)
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_add_node_spin(form, "固定伤害", "flat_damage", node, 0.0, 0.0, 99999.0, 1.0)
	_build_damage_tag_fields(form, node)
	# 近战伤害不再在节点上配置 buff（统一走 apply_target_buff 节点），保留 fullscreen/area 的旧入口
	if include_buff:
		_build_buff_ids_fields(form, node)
		_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)
		_add_node_spin(form, "失败累积增量", "pity_increment", node, 0.2, 0.0, 1.0, 0.05)


func _build_area_fields(form: GridContainer, node: Dictionary) -> void:
	_add_result_key(form, node)
	_add_origin_fields(form, node)
	_add_node_option(form, "形状", "shape", node, [{"value": "circle", "label": "圆形"}, {"value": "rect", "label": "矩形"}], true)
	_add_node_spin(form, "半径", "radius", node, 80.0, 0.0, 9999.0, 1.0)
	if String(node.get("shape", "circle")) == "rect":
		_add_node_spin(form, "宽度", "width", node, 160.0, 1.0, 9999.0, 1.0)
		_add_node_spin(form, "高度", "height", node, 80.0, 1.0, 9999.0, 1.0)
	_build_damage_fields_without_result(form, node)


func _build_damage_fields_without_result(form: GridContainer, node: Dictionary) -> void:
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_add_node_spin(form, "固定伤害", "flat_damage", node, 0.0, 0.0, 99999.0, 1.0)
	_build_damage_tag_fields(form, node)
	_build_buff_ids_fields(form, node)
	_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)
	_add_node_spin(form, "失败累积增量", "pity_increment", node, 0.2, 0.0, 1.0, 0.05)


## 伤害标签与通道、可暴击/可闪避/可格挡 配置（设计案第4/5章）
func _build_damage_tag_fields(form: GridContainer, node: Dictionary) -> void:
	# 防御通道：物理/魔法/真实
	var channel_options: Array = []
	for ch in DamageTags.CHANNELS:
		channel_options.append({"value": ch, "label": DamageTags.get_channel_label(ch)})
	_add_node_option(form, "防御通道", "damage_channel", node, channel_options, false)
	# 伤害标签：按当前通道过滤
	var current_channel := String(node.get("damage_channel", "physical"))
	var tag_options: Array = []
	for tag in DamageTags.get_tags_by_channel(current_channel):
		tag_options.append({"value": tag, "label": DamageTags.get_tag_label(tag)})
	if tag_options.is_empty():
		for tag in DamageTags.TAGS:
			tag_options.append({"value": tag, "label": DamageTags.get_tag_label(tag)})
	_add_node_option(form, "伤害标签", "damage_tag", node, tag_options, false)
	# 可暴击/可闪避/可格挡（是/否下拉，缺省"是"）
	var bool_options := [{"value": true, "label": "是"}, {"value": false, "label": "否"}]
	_add_node_option(form, "可暴击", "can_crit", node, bool_options, false)
	_add_node_option(form, "可闪避", "can_dodge", node, bool_options, false)
	_add_node_option(form, "可格挡", "can_block", node, bool_options, false)


func _build_projectile_fields(form: GridContainer, node: Dictionary) -> void:
	_add_result_key(form, node)
	_add_node_scene_picker(form, "弹道场景", "scene", node)
	_add_node_spin(form, "缩放", "scale", node, 1.0, 0.01, 20.0, 0.05)
	_add_origin_fields(form, node)
	_add_node_option(form, "轨迹", "trajectory", node, [{"value": "straight", "label": "直线"}, {"value": "ballistic", "label": "抛物线"}], true)
	_add_node_option(form, "瞄准/落点", "aim_mode", node, [{"value": "facing_elevation", "label": "朝向 + 仰角"}, {"value": "nearest_enemy", "label": "指向最近敌人"}, {"value": "enemy_area", "label": "敌人附近区域"}, {"value": "forward_area", "label": "施法者前方区域"}], true)
	_add_node_option(form, "发射方式", "emission", node, [{"value": "single", "label": "单发"}, {"value": "sequence", "label": "连续"}, {"value": "fan", "label": "扇形齐射"}, {"value": "area_rain", "label": "区域落雨"}], true)
	_add_node_spin(form, "最小施法距离", "ai_min_range", node, 0.0, 0.0, 9999.0, 1.0)
	var max_range_spin := _add_node_spin(form, "最大施法距离", "ai_max_range", node, 0.0, 0.0, 9999.0, 1.0)
	if float(node.get("ai_max_range", 0.0)) <= 0.0:
		# 上一行是 label，这行是 spin → 在 spin 后追加感叹号提示
		var warn := Label.new()
		warn.text = "⚠"
		warn.add_theme_color_override("font_color", Color("ffca64"))
		warn.tooltip_text = "未配置最大施法距离：AI 不会释放此弹道技能。请填入一个合理距离（如 280）。"
		form.add_child(warn)
		# SpinBox 值变化时动态显隐感叹号
		max_range_spin.value_changed.connect(func(v: float) -> void:
			warn.visible = (v <= 0.0))
	_add_node_spin(form, "速度", "speed", node, 300.0, 1.0, 9999.0, 1.0)
	_add_node_spin(form, "生命周期", "lifetime", node, 5.0, 0.1, 99.0, 0.1)
	_add_node_spin(form, "最大穿透数", "max_pierce", node, 0.0, -1.0, 99.0, 1.0)
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_build_buff_ids_fields(form, node)
	_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)
	_add_node_spin(form, "失败累积增量", "pity_increment", node, 0.2, 0.0, 1.0, 0.05)
	var emission := String(node.get("emission", "single"))
	var aim := String(node.get("aim_mode", "facing_elevation"))
	if aim == "facing_elevation" or emission == "fan":
		_add_node_spin(form, "仰角（正值向上）", "elevation_degrees", node, 0.0, -89.0, 89.0, 1.0)
	if emission == "sequence" or emission == "fan" or emission == "area_rain":
		_add_node_spin(form, "弹道数量", "count", node, 3.0, 1.0, 99.0, 1.0)
	if emission == "sequence" or emission == "area_rain":
		_add_node_spin(form, "发射间隔", "interval", node, 0.15, 0.0, 10.0, 0.01)
	if emission == "fan":
		_add_node_spin(form, "散射角", "spread_degrees", node, 20.0, 0.0, 180.0, 1.0)
	if emission == "area_rain":
		_add_node_spin(form, "索敌范围", "target_search_range", node, 500.0, 1.0, 9999.0, 1.0)
		_add_node_spin(form, "区域宽度", "area_width", node, 260.0, 1.0, 9999.0, 1.0)
		_add_node_spin(form, "区域高度", "area_height", node, 90.0, 1.0, 9999.0, 1.0)
		_add_node_spin(form, "抛射高度", "arc_height", node, 180.0, 1.0, 9999.0, 1.0)
		_add_node_spin(form, "重力", "gravity", node, 900.0, 0.0, 9999.0, 10.0)
		_add_node_spin(form, "前方落点距离", "forward_distance", node, 250.0, 1.0, 9999.0, 1.0)
	elif String(node.get("trajectory", "straight")) == "ballistic":
		_add_node_spin(form, "重力", "gravity", node, 900.0, 0.0, 9999.0, 10.0)
	# 弹道视觉修正：镜像/旋转（对齐运行时 projectile.visual_mirror / visual_rotation_degrees）
	var mirror_label := Label.new()
	mirror_label.text = "镜像"
	form.add_child(mirror_label)
	var mirror_check := CheckBox.new()
	mirror_check.button_pressed = bool(node.get("mirror", false))
	mirror_check.toggled.connect(func(v: bool) -> void: _update_node("mirror", v, false))
	form.add_child(mirror_check)
	_add_node_spin(form, "旋转角度", "rotation_degrees", node, 0.0, -360.0, 360.0, 1.0)


func _build_effect_fields(form: GridContainer, node: Dictionary) -> void:
	_add_node_scene_picker(form, "特效场景", "scene", node)
	_add_effect_metadata_helper(form, node)
	# 坐标系选择：world / character_local / fullscreen
	# 默认 character_local（向后兼容旧的 attachment_meta.json 自动填充）
	var coord_space := String(node.get("coordinate_space", "character_local"))
	_add_node_option(form, "坐标系", "coordinate_space", node, COORD_SPACE_OPTIONS, false)
	# 全屏模式下隐藏 target/origin/offset/attachment_layer（运行时忽略），只保留 duration
	if coord_space == "fullscreen":
		var hint := Label.new()
		hint.text = "全屏模式：特效按 cover 方式铺满 viewport，单次播放后自动销毁；循环动画按 duration 秒销毁。"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Color("ffca64"))
		form.add_child(Label.new())
		form.add_child(hint)
		_add_node_spin(form, "持续秒数（循环动画用）", "duration", node, 2.0, 0.1, 30.0, 0.1)
		_add_effect_event_helper(form, node)
		return
	_add_node_option(form, "目标", "target", node, TARGET_OPTIONS, true)
	if String(node.get("target", "origin")) == "result":
		_add_node_line(form, "结果集", "result_key", node)
		_add_node_option(form, "触发频率", "delivery", node, [{"value": "each_hit", "label": "每次命中"}, {"value": "each_target", "label": "每个目标一次"}], false)
	else:
		_add_origin_fields(form, node)
	_add_node_spin(form, "偏移 X", "offset_x", node, 0.0, -9999.0, 9999.0, 1.0)
	_add_node_spin(form, "偏移 Y", "offset_y", node, 0.0, -9999.0, 9999.0, 1.0)
	_add_node_spin(form, "非阻塞延迟 ms", "delay_ms", node, 0.0, 0.0, 10000.0, 10.0)
	_add_node_spin(form, "特效缩放", "effect_scale", node, 1.0, 0.05, 12.0, 0.05)
	_add_node_spin(form, "旋转角度", "rotation_degrees", node, 0.0, -720.0, 720.0, 1.0)
	_add_node_spin(form, "透明度", "opacity", node, 1.0, 0.0, 1.0, 0.05)
	_add_node_spin(form, "生命周期 ms", "lifetime_ms", node, 0.0, 0.0, 30000.0, 50.0)
	_add_node_option(form, "附着层级", "attachment_layer", node, ATTACHMENT_LAYER_OPTIONS, false)
	var follow_check := CheckBox.new()
	follow_check.text = "跟随挂载对象"
	follow_check.button_pressed = bool(node.get("follow_target", true))
	follow_check.toggled.connect(func(value: bool) -> void: _update_node("follow_target", value, false))
	form.add_child(Label.new())
	form.add_child(follow_check)
	var mirror_facing_check := CheckBox.new()
	mirror_facing_check.text = "跟随角色朝向镜像"
	mirror_facing_check.button_pressed = bool(node.get("mirror_with_facing", true))
	mirror_facing_check.toggled.connect(func(value: bool) -> void: _update_node("mirror_with_facing", value, false))
	form.add_child(Label.new())
	form.add_child(mirror_facing_check)
	if not String(node.get("source_bundle_id", "")).is_empty():
		var source_label := Label.new()
		source_label.text = "AI 特效包来源"
		form.add_child(source_label)
		var source_value := Label.new()
		source_value.text = "%s / %s" % [String(node.get("source_bundle_id", "")), String(node.get("source_track_id", ""))]
		source_value.selectable = true
		form.add_child(source_value)
	_add_effect_event_helper(form, node)


func _add_effect_metadata_helper(form: GridContainer, node: Dictionary) -> void:
	var label := Label.new()
	label.text = "附着元数据"
	form.add_child(label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(row)
	var status_label := Label.new()
	status_label.text = "未检测"
	status_label.add_theme_color_override("font_color", Color("888888"))
	row.add_child(status_label)
	var detect_btn := Button.new()
	detect_btn.text = "检测并应用"
	detect_btn.tooltip_text = "读取场景同目录的 attachment_meta.json，自动填入偏移、坐标空间和角色前后层级"
	detect_btn.pressed.connect(_on_detect_attachment_meta.bind(status_label))
	row.add_child(detect_btn)
	# Auto-detect on first render
	_check_attachment_meta(node, status_label)


func _add_effect_event_helper(form: GridContainer, node: Dictionary) -> void:
	var label := Label.new()
	label.text = "事件前置节点"
	form.add_child(label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(row)
	var hint_label := Label.new()
	var event_hint := _get_effect_event_hint(node)
	if event_hint.is_empty():
		hint_label.text = "无事件提示"
		hint_label.add_theme_color_override("font_color", Color("888888"))
	else:
		hint_label.text = "建议事件：%s" % event_hint
	row.add_child(hint_label)
	var insert_btn := Button.new()
	insert_btn.text = "插入等待事件节点"
	insert_btn.tooltip_text = "在当前播放特效节点前插入一个 wait_action_event 节点"
	insert_btn.disabled = event_hint.is_empty()
	insert_btn.pressed.connect(_on_insert_wait_event_before_current.bind(event_hint))
	row.add_child(insert_btn)


func _on_detect_attachment_meta(status_label: Label) -> void:
	var index := _selected_node_index()
	if index < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index >= nodes.size():
		return
	var node: Dictionary = nodes[index]
	_apply_attachment_meta(node, status_label)


func _check_attachment_meta(node: Dictionary, status_label: Label) -> void:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty():
		status_label.text = "未选择场景"
		return
	var meta_path := scene_path.get_base_dir().path_join("attachment_meta.json")
	if not FileAccess.file_exists(meta_path):
		status_label.text = "无附着元数据"
		return
	status_label.text = "已检测到元数据（点击应用）"
	status_label.add_theme_color_override("font_color", Color("88ff88"))


func _apply_attachment_meta(node: Dictionary, status_label: Label) -> void:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty():
		status_label.text = "未选择场景"
		return
	var meta_path := scene_path.get_base_dir().path_join("attachment_meta.json")
	if not FileAccess.file_exists(meta_path):
		status_label.text = "无附着元数据"
		return
	var meta := _read_json(meta_path)
	if meta.is_empty():
		status_label.text = "元数据读取失败"
		return
	# Auto-fill the runtime fields required by an action attachment.
	node["origin"] = "caster"
	node["target"] = "origin"
	node["coordinate_space"] = String(meta.get("coordinateSpace", "character_local"))
	var local_offset: Dictionary = meta.get("characterOffset", {})
	node["offset_x"] = float(local_offset.get("x", 0.0))
	node["offset_y"] = float(local_offset.get("y", 0.0))
	node["attachment_layer"] = String(meta.get("layer", "front"))
	node["attachment_blend_mode"] = String(meta.get("blendMode", "normal"))
	var box_size: Dictionary = meta.get("boxSize", {})
	node["attachment_box_width"] = float(box_size.get("width", 0.0))
	node["attachment_box_height"] = float(box_size.get("height", 0.0))
	status_label.text = "已应用：偏移(%.0f, %.0f)，%s" % [node["offset_x"], node["offset_y"], "角色前" if node["attachment_layer"] == "front" else "角色后"]
	status_label.add_theme_color_override("font_color", Color("88ff88"))
	# Persist and rebuild
	var index := _selected_node_index()
	if index >= 0:
		var skill := _current_skill()
		var nodes: Array = skill.get("nodes", [])
		if index < nodes.size():
			nodes[index] = node
			skill["nodes"] = nodes
			_skills[_current_skill_id] = skill
			_show_node_details(index)
			_rebuild_node_list_keep(index)
			_refresh_timeline()


func _get_effect_event_hint(node: Dictionary) -> String:
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty():
		return ""
	var meta_path := scene_path.get_base_dir().path_join("attachment_meta.json")
	if not FileAccess.file_exists(meta_path):
		return ""
	var meta := _read_json(meta_path)
	if meta.is_empty():
		return ""
	return String(meta.get("eventHint", meta.get("event_hint", "")))


func _on_insert_wait_event_before_current(event_name: String) -> void:
	if event_name.is_empty():
		return
	var index := _selected_node_index()
	if index < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	var wait_node := {"type": "wait_action_event", "event": event_name}
	nodes.insert(index, wait_node)
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	# Select the effect node (now at index+1)
	_rebuild_node_list_keep(index + 1)
	_show_node_details(index + 1)
	_refresh_timeline()


func _build_target_buff_fields(form: GridContainer, node: Dictionary) -> void:
	_add_node_option(form, "目标", "target", node, TARGET_OPTIONS, true)
	if String(node.get("target", "result")) == "result":
		_add_node_line(form, "结果集", "result_key", node)
		_add_node_option(form, "触发频率", "delivery", node, [{"value": "each_hit", "label": "每次命中"}, {"value": "each_target", "label": "每个目标一次"}], false)
	else:
		_add_origin_fields(form, node)
		if String(node.get("target", "")) == "area":
			_add_node_spin(form, "范围半径", "radius", node, 80.0, 0.0, 9999.0, 1.0)
	# Buff 列表 + 施加概率（与 apply_self_buff 一致，从 buffs.json 全量取）
	_build_buff_ids_fields(form, node)
	_add_node_spin(form, "施加概率", "chance", node, 1.0, 0.0, 1.0, 0.05)
	_add_node_spin(form, "失败累积增量", "pity_increment", node, 0.2, 0.0, 1.0, 0.05)


func _add_result_key(form: GridContainer, node: Dictionary) -> void:
	_add_node_line(form, "结果集名称", "result_key", node)


func _add_origin_fields(form: GridContainer, node: Dictionary) -> void:
	_add_node_option(form, "出生/中心", "origin", node, ORIGIN_OPTIONS, true)
	if String(node.get("origin", "hit_window")) == "socket":
		_add_node_line(form, "Socket 名称", "socket", node)


func _add_node_line(form: GridContainer, label_text: String, field: String, node: Dictionary) -> void:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = String(node.get(field, ""))
	edit.text_changed.connect(_on_node_text_changed.bind(field))
	form.add_child(edit)


func _add_node_scene_picker(form: GridContainer, label_text: String, field: String, node: Dictionary) -> void:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(row)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = String(node.get(field, ""))
	edit.text_changed.connect(_on_node_text_changed.bind(field))
	edit.name = "ScenePathEdit_%s" % field
	row.add_child(edit)
	var browse_btn := Button.new()
	browse_btn.text = "选择..."
	browse_btn.pressed.connect(_open_scene_picker.bind(edit, field))
	row.add_child(browse_btn)


func _add_node_spin(form: GridContainer, label_text: String, field: String, node: Dictionary, default_value: float, minimum: float, maximum: float, step_value: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = float(node.get(field, default_value))
	spin.value_changed.connect(_on_node_number_changed.bind(field))
	form.add_child(spin)
	return spin


## 添加 HSlider + SpinBox 联动控件编辑数值字段（Slider 占主体，SpinBox 显示精确值）。
## 通过成员变量 _effect_scale_slider / _effect_scale_spin 暴露引用以便外部同步。
func _add_node_slider(form: GridContainer, label_text: String, field: String, node: Dictionary, default_value: float, minimum: float, maximum: float, step_value: float) -> void:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var container := HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.value = float(node.get(field, default_value))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = float(node.get(field, default_value))
	spin.custom_minimum_size.x = 70
	# 双向同步：slider 变化时更新 spin 并写回字段；spin 变化时反之
	slider.value_changed.connect(func(v: float) -> void:
		if _effect_scale_spin != null and is_instance_valid(_effect_scale_spin):
			_effect_scale_spin.value = v
		_on_node_number_changed(v, field))
	spin.value_changed.connect(func(v: float) -> void:
		if _effect_scale_slider != null and is_instance_valid(_effect_scale_slider):
			_effect_scale_slider.value = v
		_on_node_number_changed(v, field))
	container.add_child(slider)
	container.add_child(spin)
	form.add_child(container)
	_effect_scale_slider = slider
	_effect_scale_spin = spin


## 编辑当前技能所属角色/怪物的攻击力（attack）。伤害 = attack × damage_ratio。
## 改动直接写回 characters.json / enemies.json，无需另开编辑器。
func _add_owner_attack_editor(form: GridContainer) -> void:
	var label := Label.new()
	label.text = "攻击力（所属角色/怪物）"
	form.add_child(label)
	var info := _find_skill_owner_row(int(_current_skill_id))
	if info.is_empty():
		var none_label := Label.new()
		none_label.text = "未找到所属角色/怪物"
		none_label.add_theme_color_override("font_color", Color("ff9800"))
		form.add_child(none_label)
		return
	var row: Dictionary = info["row"]
	var table_key: String = info["key"]
	var table_path: String = info["table_path"]
	var owner_name := String(row.get("name", table_key))
	var attack := float(row.get("attack", 1.0))
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 99999.0
	spin.step = 1.0
	spin.value = attack
	spin.suffix = "  (%s)" % owner_name
	spin.value_changed.connect(_on_owner_attack_changed.bind(table_path, table_key))
	form.add_child(spin)


## 在 characters.json / enemies.json 中查找技能所属的整行数据及表路径。
## 返回 {"row": Dictionary, "key": String, "table_path": String}，未找到返回空 Dictionary。
func _find_skill_owner_row(skill_id: int) -> Dictionary:
	for table_path in [CHARACTERS_PATH, ENEMIES_PATH]:
		var table := _load_json(table_path)
		for key in table:
			var row_value: Variant = table[key]
			if not row_value is Dictionary:
				continue
			var row: Dictionary = row_value
			var asset := String(row.get("asset", ""))
			if asset.is_empty():
				continue
			if int(row.get("normal_skill", 0)) == skill_id:
				return {"row": row, "key": key, "table_path": table_path}
			for sid_value in row.get("skills", []):
				if int(sid_value) == skill_id:
					return {"row": row, "key": key, "table_path": table_path}
			for unlock_key in row.get("skill_unlocks", {}):
				var unlock: Dictionary = (row.get("skill_unlocks", {}) as Dictionary).get(unlock_key, {})
				if int(unlock.get("skill_id", 0)) == skill_id:
					return {"row": row, "key": key, "table_path": table_path}
			for sid_value in row.get("ai_skill_priority", []):
				if int(sid_value) == skill_id:
					return {"row": row, "key": key, "table_path": table_path}
	return {}


## 攻击力 SpinBox 改动回调：写回对应表配置并保存。
func _on_owner_attack_changed(value: float, table_path: String, table_key: String) -> void:
	if _loading:
		return
	var table: Dictionary = _load_json(table_path)
	if not table.has(table_key):
		return
	var row: Dictionary = table[table_key]
	row["attack"] = value
	table[table_key] = row
	_save_config_file(table_path, table)
	# 同步刷新内存缓存
	if table_path == CHARACTERS_PATH:
		_characters_config = table.duplicate(true)
	elif table_path == ENEMIES_PATH:
		_enemies_config = table.duplicate(true)
	_status.text = "已更新 %s 的攻击力为 %.0f" % [table_key, value]


## 只读显示：用当前技能所属资源即时编译 ai_range_cache，展示该节点类型的自动距离。
func _add_ai_range_readonly(form: GridContainer, label_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var value_label := Label.new()
	value_label.text = _compute_ai_range_preview()
	value_label.tooltip_text = "保存技能后写回 skills.json 的 ai_range_cache"
	form.add_child(value_label)


## 用当前技能所属角色/怪物资源编译 ai_range_cache，返回可读字符串。
func _compute_ai_range_preview() -> String:
	if _current_skill_id.is_empty():
		return "未选中技能"
	var owner_asset := _find_skill_owner_asset(int(_current_skill_id))
	if owner_asset.is_empty():
		return "未找到所属角色/怪物"
	var cache := AIRangeCompiler.compile(int(_current_skill_id), owner_asset)
	var entries: Array = cache.get("entries", [])
	if entries.is_empty():
		return "无可用距离（缺少攻击框或起手距离）"
	var parts: PackedStringArray = []
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var kind := String(entry.get("kind", ""))
		var min_d := float(entry.get("min_edge_distance", 0.0))
		var max_d := float(entry.get("max_edge_distance", 0.0))
		if max_d >= 99990.0:
			parts.append("%s: 检测范围内均可" % kind)
		else:
			parts.append("%s: %.0f~%.0f" % [kind, min_d, max_d])
	return "; ".join(parts)


func _add_node_option(form: GridContainer, label_text: String, field: String, node: Dictionary, options: Array, rebuild: bool) -> void:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var option := OptionButton.new()
	for value in options:
		# 统一显示格式：英文值 (中文注解)。
		# 空 value（如「无」选项）只显示 label，避免 " (无)" 的前导空格
		var raw_value := str(value.get("value", ""))
		var raw_label := str(value.get("label", raw_value))
		var display: String
		if raw_value.is_empty():
			display = raw_label
		elif raw_label.is_empty():
			display = raw_value
		else:
			display = "%s (%s)" % [raw_value, raw_label]
		option.add_item(display)
		option.set_item_metadata(option.item_count - 1, value.get("value", ""))
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == str(node.get(field, option.get_item_metadata(0))):
			option.select(index)
	option.item_selected.connect(_on_node_option_selected.bind(field, rebuild, option))
	form.add_child(option)


## apply_self_buff / apply_target_buff / 伤害附带 buff 节点的多 buff 列表表单：
## 把节点字段从旧 buff_id (int) 迁移到 buff_ids (Array[int])，
## 每行一个 buff 下拉 + 删除按钮，底部一个"添加 Buff"按钮。
func _build_buff_ids_fields(form: GridContainer, node: Dictionary) -> void:
	# 数据迁移：旧 buff_id (int) → 新 buff_ids (Array[int])
	if not node.has("buff_ids"):
		if node.has("buff_id"):
			var legacy := int(node.get("buff_id", 0))
			node["buff_ids"] = [legacy] if legacy > 0 else []
			node.erase("buff_id")
		else:
			node["buff_ids"] = []
		var idx := _selected_node_index()
		if idx >= 0:
			var skill := _current_skill()
			var nodes: Array = skill.get("nodes", [])
			if idx < nodes.size() and nodes[idx] is Dictionary:
				nodes[idx] = node
				skill["nodes"] = nodes
				_skills[_current_skill_id] = skill

	var label := Label.new()
	label.text = "Buff IDs"
	form.add_child(label)

	var list_container := VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 4)
	form.add_child(list_container)

	var buff_ids: Array = node.get("buff_ids", [])
	for i in range(buff_ids.size()):
		list_container.add_child(_make_buff_ids_row(i, int(buff_ids[i])))

	var add_btn := Button.new()
	add_btn.text = "添加 Buff"
	add_btn.pressed.connect(_on_buff_ids_add)
	var edit_buff_btn := Button.new()
	edit_buff_btn.text = "→ Buff编辑器"
	edit_buff_btn.tooltip_text = "打开 Buff 配置编辑器并选中当前节点配置的第一个 Buff"
	edit_buff_btn.pressed.connect(_on_jump_to_buff_editor)
	var buff_btn_row := HBoxContainer.new()
	buff_btn_row.add_theme_constant_override("separation", 4)
	buff_btn_row.add_child(add_btn)
	buff_btn_row.add_child(edit_buff_btn)
	list_container.add_child(buff_btn_row)

	# apply_self_buff 节点：特效偏移微调 + 缩放 Slider（选中 buff 有 effect_scene 时可在预览中直接拖拽）
	if String(node.get("type", "")) == "apply_self_buff":
		_effect_offset_x_spin = _add_node_spin(form, "特效偏移 X", "effect_offset_x", node, 0.0, -9999.0, 9999.0, 1.0)
		_effect_offset_y_spin = _add_node_spin(form, "特效偏移 Y", "effect_offset_y", node, 0.0, -9999.0, 9999.0, 1.0)
		_add_node_slider(form, "特效缩放", "effect_scale", node, 1.0, 0.1, 3.0, 0.05)
		var drag_tip := Label.new()
		drag_tip.text = "提示：在预览窗口中按住左键拖拽特效可直接调整偏移"
		drag_tip.add_theme_color_override("font_color", Color("9aa0a6"))
		drag_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		form.add_child(drag_tip)
		form.add_child(Control.new())


func _make_buff_ids_row(row_index: int, current_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item("0 - 无")
	option.set_item_metadata(0, 0)
	var buffs := _read_json(BUFFS_PATH)
	var buff_ids: Array = buffs.keys()
	buff_ids.sort_custom(func(a, b): return int(a) < int(b))
	for id_str in buff_ids:
		var buff: Dictionary = buffs[id_str]
		var buff_id := int(id_str)
		var display_name := String(buff.get("name", "未命名"))
		option.add_item("%d - %s" % [buff_id, display_name])
		option.set_item_metadata(option.item_count - 1, buff_id)
	for index in range(option.item_count):
		if int(option.get_item_metadata(index)) == current_id:
			option.select(index)
			break
	option.item_selected.connect(_on_buff_ids_changed.bind(row_index, option))
	row.add_child(option)

	var del_btn := Button.new()
	del_btn.text = "×"
	del_btn.custom_minimum_size = Vector2(28, 28)
	del_btn.pressed.connect(_on_buff_ids_remove.bind(row_index))
	row.add_child(del_btn)
	return row


func _on_buff_ids_changed(item_index: int, row_index: int, option: OptionButton) -> void:
	var new_id := int(option.get_item_metadata(item_index))
	var node_idx := _selected_node_index()
	if node_idx < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if node_idx >= nodes.size() or not nodes[node_idx] is Dictionary:
		return
	var node: Dictionary = nodes[node_idx]
	var arr: Array = node.get("buff_ids", [])
	if row_index >= 0 and row_index < arr.size():
		arr[row_index] = new_id
		node["buff_ids"] = arr
		nodes[node_idx] = node
		skill["nodes"] = nodes
		_skills[_current_skill_id] = skill
	_rebuild_node_list_keep(node_idx)
	_refresh_preview()


func _on_buff_ids_add() -> void:
	var node_idx := _selected_node_index()
	if node_idx < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if node_idx >= nodes.size() or not nodes[node_idx] is Dictionary:
		return
	var node: Dictionary = nodes[node_idx]
	var arr: Array = node.get("buff_ids", [])
	arr.append(0)
	node["buff_ids"] = arr
	nodes[node_idx] = node
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	_show_node_details(node_idx)
	_rebuild_node_list_keep(node_idx)


## 跳转到 Buff 配置编辑器，选中当前节点配置的第一个有效 buff。
func _on_jump_to_buff_editor() -> void:
	var node_idx := _selected_node_index()
	if node_idx < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if node_idx >= nodes.size() or not nodes[node_idx] is Dictionary:
		return
	var node: Dictionary = nodes[node_idx]
	var buff_ids: Array = node.get("buff_ids", [])
	for id_value in buff_ids:
		var bid := int(id_value)
		if bid > 0:
			request_open_buff.emit(bid)
			return
	request_open_buff.emit(0)


func _on_buff_ids_remove(row_index: int) -> void:
	var node_idx := _selected_node_index()
	if node_idx < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if node_idx >= nodes.size() or not nodes[node_idx] is Dictionary:
		return
	var node: Dictionary = nodes[node_idx]
	var arr: Array = node.get("buff_ids", [])
	if row_index >= 0 and row_index < arr.size():
		arr.remove_at(row_index)
		node["buff_ids"] = arr
		nodes[node_idx] = node
		skill["nodes"] = nodes
		_skills[_current_skill_id] = skill
		_show_node_details(node_idx)
		_rebuild_node_list_keep(node_idx)


func _open_scene_picker(edit: LineEdit, field: String) -> void:
	var dialog := EditorFileDialog.new()
	dialog.title = "选择场景文件"
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tscn, *.scn ; Scene")
	dialog.file_selected.connect(func(path: String) -> void:
		edit.text = path
		_on_node_text_changed(path, field)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	add_child(dialog)
	var current := edit.text
	if current.begins_with("res://") and current.contains("/"):
		var dir := current.get_base_dir()
		var file := current.get_file()
		dialog.current_dir = dir
		dialog.current_file = file
	else:
		dialog.current_dir = "res://"
		dialog.current_file = ""
	dialog.popup_centered_ratio(0.95)
	dialog.mode = Window.MODE_MAXIMIZED


func _on_node_text_changed(value: String, field: String) -> void:
	_update_node(field, value, false)


func _on_node_number_changed(value: float, field: String) -> void:
	_update_node(field, value, false)


func _on_node_option_selected(index: int, field: String, rebuild: bool, option: OptionButton) -> void:
	if index >= 0 and index < option.item_count:
		_update_node(field, option.get_item_metadata(index), rebuild)


func _update_node(field: String, value: Variant, rebuild := false) -> void:
	var index := _selected_node_index()
	if index < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index >= nodes.size() or not nodes[index] is Dictionary:
		return
	var node: Dictionary = nodes[index]
	if value is String and String(value).is_empty():
		node.erase(field)
	else:
		node[field] = value
	nodes[index] = node
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	if field == "action" and String(node.get("type", "")) == "play_animation":
		_reload_action_preview(String(value))
	if rebuild:
		_show_node_details(index)
	_rebuild_node_list_keep(index)
	_refresh_timeline()
	_refresh_preview()


func _reload_action_preview(action_name: String) -> void:
	if action_name.is_empty():
		return
	_preview_action = action_name
	var asset_path := _find_asset_path_for_skill(int(_current_skill_id))
	if asset_path.is_empty():
		return
	var combat_path := asset_path.path_join("combat_actions.json")
	var data := _read_json(combat_path)
	_action_data = (data.get("actions", {}) as Dictionary).get(action_name, {})


func _rebuild_node_list_keep(index: int) -> void:
	_rebuild_node_list(index)


func _add_action_node() -> void:
	_add_node_from_picker(_action_picker)


func _add_control_node() -> void:
	_add_node_from_picker(_control_picker)


func _add_node_from_picker(picker: OptionButton) -> void:
	if _current_skill_id.is_empty() or picker.selected < 0:
		return
	var type_name := String(picker.get_item_metadata(picker.selected))
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	# 在当前选中节点之后插入；无选中时追加到末尾
	var insert_index := _selected_node_index()
	if insert_index < 0:
		insert_index = nodes.size()
	else:
		insert_index += 1
	nodes.insert(insert_index, _default_node(type_name))
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	_rebuild_node_list_keep(insert_index)
	_show_node_details(insert_index)
	_refresh_timeline()


func _default_node(type_name: String) -> Dictionary:
	match type_name:
		"play_animation": return {"type": type_name, "action": _default_action()}
		"wait_action_event": return {"type": type_name, "event": "release"}
		"wait_action_frame": return {"type": type_name, "frame": 0}
		"wait_hit_window": return {"type": type_name, "hit_window_index": 0}
		"melee_damage": return {"type": type_name, "result_key": "melee_hit", "damage_ratio": 1.0}
		"area_damage": return {"type": type_name, "result_key": "area_hit", "origin": "hit_window", "shape": "circle", "radius": 80.0, "damage_ratio": 1.0}
		"fullscreen_damage": return {"type": type_name, "result_key": "fullscreen_hit", "damage_ratio": 1.0}
		"spawn_projectile": return {"type": type_name, "result_key": "projectile_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "ai_min_range": 0.0, "ai_max_range": 280.0, "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.0, "scale": 1.0, "mirror": false, "rotation_degrees": 0.0}
		"play_effect": return {"type": type_name, "scene": "", "target": "origin", "delay_ms": 0, "anchor": "origin", "follow_target": true, "mirror_with_facing": true, "lifetime_ms": 0, "effect_scale": 1.0, "rotation_degrees": 0.0, "opacity": 1.0, "tint": "#ffffff"}
		"apply_target_buff": return {"type": type_name, "target": "result", "result_key": "last_result", "buff_ids": [], "chance": 1.0}
		"apply_self_buff": return {"type": type_name, "buff_ids": []}
		"heal": return {"type": type_name, "amount": 10}
		"move_x": return {"type": type_name, "distance": 32.0}
		"wait_time": return {"type": type_name, "seconds": 0.1}
	return {"type": type_name}


func _delete_selected_node() -> void:
	var index := _selected_node_index()
	if index < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	nodes.remove_at(index)
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	_rebuild_node_list()
	_refresh_timeline()


func _move_node(delta: int) -> void:
	var index := _selected_node_index()
	var target := index + delta
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index < 0 or target < 0 or target >= nodes.size():
		return
	var swap: Variant = nodes[index]
	nodes[index] = nodes[target]
	nodes[target] = swap
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	_rebuild_node_list_keep(target)
	_show_node_details(target)
	_refresh_timeline()


func _apply_template(nodes: Array, message: String) -> void:
	if _current_skill_id.is_empty():
		return
	var skill := _current_skill()
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	_status.text = message
	_rebuild_node_list()
	_refresh_timeline()


func _apply_melee_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "melee_damage", "result_key": "melee_hit", "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用普攻模板。")


func _apply_projectile_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "projectile_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "ai_min_range": 0.0, "ai_max_range": 280.0, "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用单发弹道模板，请填写弹道场景。")


func _apply_area_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "area_damage", "result_key": "area_hit", "origin": "hit_window", "shape": "circle", "radius": 80.0, "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用范围伤害模板。")


func _apply_fullscreen_template() -> void:
	var action := _default_action()
	# 全屏伤害模板：含一个全屏覆盖特效节点，用户只需选择 scene 即可看到满屏特效
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "wait_hit_window", "hit_window_index": 0},
		{"type": "fullscreen_damage", "result_key": "fullscreen_hit", "damage_ratio": 1.0},
		{"type": "play_effect", "scene": "", "coordinate_space": "fullscreen", "target": "origin", "duration": 2.0},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用全场伤害模板（含全屏特效节点，请选择特效场景）。")


func _apply_self_buff_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "apply_self_buff", "buff_ids": []}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用自身 Buff 模板。")


func _apply_sequence_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "arrow_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "sequence", "count": 3, "interval": 0.15, "ai_min_range": 0.0, "ai_max_range": 320.0, "speed": 420.0, "lifetime": 2.0, "damage_ratio": 0.8}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用三连弹道模板，请填写弹道场景。")


func _apply_rain_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "rain_hit", "scene": "", "origin": "hit_window", "trajectory": "ballistic", "aim_mode": "enemy_area", "emission": "area_rain", "count": 12, "interval": 0.08, "ai_min_range": 0.0, "ai_max_range": 380.0, "target_search_range": 500.0, "area_width": 260.0, "area_height": 90.0, "arc_height": 180.0, "gravity": 900.0, "speed": 360.0, "lifetime": 3.0, "damage_ratio": 0.7}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用斜向上箭雨模板，请填写弹道场景。")


func _apply_melee_self_buff_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "wait_hit_window", "hit_window_index": 0},
		{"type": "melee_damage", "result_key": "melee_hit", "damage_ratio": 1.0,
		 "damage_channel": "physical", "damage_tag": "slash"},
		{"type": "apply_self_buff", "buff_ids": []},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用近战+自Buff模板。")


func _apply_area_buff_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "play_effect", "coordinate_space": "character_local",
		 "target": "origin", "scene": ""},
		{"type": "wait_hit_window", "hit_window_index": 0},
		{"type": "apply_target_buff", "target": "area", "origin": "caster",
		 "radius": 200.0, "chance": 1.0, "buff_ids": []},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用群体Buff模板，请填写 buff_ids 与特效场景。")


func _apply_fan_projectile_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "wait_hit_window", "hit_window_index": 0},
		{"type": "play_effect", "coordinate_space": "character_local",
		 "target": "origin", "scene": ""},
		{"type": "spawn_projectile", "emission": "fan", "trajectory": "straight",
		 "count": 3, "spread_degrees": 20.0, "max_pierce": 20,
		 "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.5,
		 "damage_channel": "magic", "damage_tag": "fire", "scene": ""},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用扇形弹道模板，请填写弹道场景。")


func _apply_event_buff_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "play_effect", "coordinate_space": "character_local",
		 "target": "origin", "scene": ""},
		{"type": "wait_action_event", "event": "release"},
		{"type": "apply_self_buff", "buff_ids": []},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用事件Buff模板，需动作配置 release 事件。")


func _apply_ultimate_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "play_effect", "coordinate_space": "fullscreen",
		 "target": "origin", "scene": "", "duration": 2.0},
		{"type": "play_effect", "coordinate_space": "character_local",
		 "origin": "caster", "target": "origin", "scene": ""},
		{"type": "wait_hit_window", "hit_window_index": 0},
		{"type": "fullscreen_damage", "damage_channel": "magic",
		 "damage_tag": "fire", "damage_ratio": 3.0},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用大招模板，请填写两个特效场景。")


func _apply_ballistic_projectile_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "wait_hit_window", "hit_window_index": 0},
		{"type": "spawn_projectile", "trajectory": "ballistic", "emission": "single",
		 "aim_mode": "enemy_area", "arc_height": 100.0, "gravity": 900.0,
		 "speed": 360.0, "lifetime": 3.0, "damage_ratio": 1.5, "scene": ""},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用抛射弹道模板，请填写弹道场景。")


func _apply_dash_template() -> void:
	var action := _default_action()
	_apply_template([
		{"type": "play_animation", "action": action},
		{"type": "wait_action_frame", "frame": 0},
		{"type": "move_x", "distance": 64.0},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用位移模板。")


func _clear_nodes() -> void:
	_apply_template([], "已清空节点。保存前请重新配置有效技能流程。")


func _load_action_data() -> void:
	_action_data = {}
	_sprite_frames = null
	_visual_transform = {}
	_sprite_scale = 1.0
	var asset_path := _find_asset_path_for_skill(int(_current_skill_id))
	if asset_path.is_empty():
		_status.text = "未找到该技能所属角色资源。"
		_refresh_preview()
		return
	var combat_path := asset_path.path_join("combat_actions.json")
	var data := _read_json(combat_path)
	var action := _default_action()
	_preview_action = action
	_action_data = (data.get("actions", {}) as Dictionary).get(action, {})
	_sprite_scale = float(data.get("sprite_scale", 1.0))
	var sf_path := asset_path.path_join("godot/spriteframes.tres")
	if ResourceLoader.exists(sf_path):
		_sprite_frames = load(sf_path) as SpriteFrames
	_visual_transform = _load_visual_transform(asset_path)
	_status.text = "动作数据源：%s" % combat_path
	_refresh_preview()


func _find_asset_path_for_skill(skill_id: int) -> String:
	for config_path in [CHARACTERS_PATH, ENEMIES_PATH]:
		var configs := _read_json(config_path)
		for key in configs:
			var config: Dictionary = configs[key]
			if _config_uses_skill(config, skill_id):
				return String(config.get("asset", ""))
	return ""


func _load_visual_transform(asset_path: String) -> Dictionary:
	var result := {
		"root_position": Vector2.ZERO,
		"position": Vector2.ZERO,
		"offset": Vector2.ZERO,
		"scale": Vector2.ONE,
		"centered": true,
		"visual_scale": 1.0,
		"body_center_y": -50.0,
	}
	var character_config_path := asset_path.path_join("character_config.json")
	if FileAccess.file_exists(character_config_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(character_config_path)) == OK and json.data is Dictionary:
			var cfg: Dictionary = json.data
			var offset: Dictionary = cfg.get("display_offset", {})
			result["root_position"] = Vector2(float(offset.get("x", 0.0)), float(offset.get("y", 0.0)))
			# display_scale 是角色视觉缩放，运行时 visual_scale = absf(CharacterActionSet.scale.x)
			# 预览直接读 character_config 的 display_scale，避免依赖角色主场景文件
			result["visual_scale"] = absf(float(cfg.get("display_scale", 1.0)))
			# body_position.y 对应运行时 CollisionShape2D.position.y，用于模拟 buff 特效抬到身体中心
			var body_pos: Dictionary = cfg.get("body_position", {})
			if body_pos.has("y"):
				result["body_center_y"] = float(body_pos.get("y", -50.0))
			else:
				var body_box: Dictionary = cfg.get("body_box", {})
				if body_box.has("yOffset"):
					result["body_center_y"] = float(body_box.get("yOffset", -50.0))
	var scene_path := asset_path.path_join("godot/character_actions.tscn")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return result
	var instance := packed.instantiate()
	# character_actions.tscn 的根节点就是 CharacterActionSet
	var action_set := instance as Node2D
	if action_set != null and action_set.name == "CharacterActionSet":
		result["visual_scale"] = absf(action_set.scale.x)
	var sprite := instance.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		result["position"] = sprite.position
		result["offset"] = sprite.offset
		result["scale"] = sprite.scale
		result["centered"] = sprite.centered
	# 若根节点不是 CharacterActionSet，尝试作为子节点查找
	if action_set == null or action_set.name != "CharacterActionSet":
		var found := instance.get_node_or_null("CharacterActionSet") as Node2D
		if found != null:
			result["visual_scale"] = absf(found.scale.x)
	instance.free()
	return result


func _refresh_preview() -> void:
	if _preview == null:
		return
	if _sprite_frames == null or _preview_action.is_empty():
		_preview.set_preview(null, 1.0, 0, {}, false, _visual_transform)
		_refresh_effect_preview()
		_refresh_range_indicator()
		return
	var count := _sprite_frames.get_frame_count(_preview_action)
	if count == 0:
		_preview.set_preview(null, 1.0, 0, {}, false, _visual_transform)
		_refresh_effect_preview()
		_refresh_range_indicator()
		return
	var frame := clampi(int(_frame_slider.value), 0, count - 1)
	var texture := _sprite_frames.get_frame_texture(_preview_action, frame)
	var window: Dictionary = {}
	var windows: Array = _action_data.get("hit_windows", [])
	if not windows.is_empty() and windows[0] is Dictionary:
		window = windows[0]
	# 朝左（与素材默认朝向一致，对齐 combat_action_editor 预览）
	_preview.set_preview(texture, _sprite_scale, frame, window, false, _visual_transform)
	_refresh_effect_preview()
	_refresh_range_indicator()


## 根据当前选中节点刷新挂载预览（play_effect 特效 / spawn_projectile 弹道）。
## 位置计算对齐真实运行时：
## - play_effect character_local: position = (offset.x * mirror_x * visual_scale, offset.y * visual_scale)，挂角色根
## - play_effect world: position = origin + offset，挂场景根
## - spawn_projectile: global_position = origin，挂场景根，方向由 aim_mode 决定
func _refresh_effect_preview() -> void:
	if _preview == null:
		return
	var node := _selected_node()
	if node.is_empty():
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var type_name := String(node.get("type", ""))
	if type_name != "play_effect" and type_name != "spawn_projectile" and type_name != "apply_self_buff":
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var scene_path := ""
	if type_name == "apply_self_buff":
		# 从第一个 buff 配置读取 effect_scene
		var buff_ids: Array = node.get("buff_ids", [])
		if buff_ids.is_empty():
			_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
			return
		var first_id := int(buff_ids[0])
		if first_id <= 0:
			_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
			return
		var buffs := _read_json(BUFFS_PATH)
		var buff: Dictionary = buffs.get(str(first_id), {})
		scene_path = String(buff.get("effect_scene", ""))
	else:
		scene_path = String(node.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var visual_scale: float = float(_visual_transform.get("visual_scale", 1.0))
	# 预览固定朝左（facing_right=false，与素材默认朝向一致）；运行时 flip_h=false 朝左，mirror_x=+1
	var mirror_x := 1.0
	if type_name == "play_effect":
		var offset := Vector2(float(node.get("offset_x", 0.0)), float(node.get("offset_y", 0.0)))
		var coord_space := String(node.get("coordinate_space", "world"))
		# character_local: 挂角色根，position = offset * mirror_x * visual_scale
		# world: 挂场景根，global_position = origin(角色根) + offset
		var effect_offset := Vector2(offset.x * mirror_x * visual_scale, offset.y * visual_scale) if coord_space == "character_local" else offset
		_preview.set_effect(packed, effect_offset, true, visual_scale, coord_space == "character_local")
	elif type_name == "apply_self_buff":
		# apply_self_buff: 挂角色根，运行时 _spawn_effect 先抬到身体中心（body_center_y）再叠加 effect_offset
		# 预览对齐运行时：offset.y 先叠加 body_center_y，再乘 visual_scale
		# 特效缩放 = 角色视觉缩放 × 节点 effect_scale（与 buff_manager._spawn_effect 应用 scale 一致）
		var body_center_y := float(_visual_transform.get("body_center_y", -50.0))
		var offset := Vector2(float(node.get("effect_offset_x", 0.0)), float(node.get("effect_offset_y", 0.0)))
		var effect_offset := Vector2(offset.x * mirror_x * visual_scale, (offset.y + body_center_y) * visual_scale)
		var effect_scale := float(node.get("effect_scale", 1.0))
		_preview.set_effect(packed, effect_offset, true, visual_scale * effect_scale, true)
	else:
		# spawn_projectile: 挂场景根，global_position = origin
		# origin 由字段决定：hit_window → hit_box 位置；caster → 角色根；socket → 帧坐标
		# 预览中统一用 hit_window 偏移（若有）否则用角色根（origin）
		# origin 偏移乘 visual_scale：角色缩放时 hit_window/forward 位置也等比缩放
		# 弹道缩放 = 角色视觉缩放 × 节点 scale 字段（与运行时 skill_executor._instantiate_projectile 一致）
		var origin_offset := _resolve_preview_origin(node) * visual_scale
		var node_scale := float(node.get("scale", 1.0))
		_preview.set_effect(packed, origin_offset, true, visual_scale * node_scale, false)
		_preview.set_effect_orientation(bool(node.get("mirror", false)), float(node.get("rotation_degrees", 0.0)))


## 根据当前选中节点刷新命中范围指示器（apply_target_buff 的 area / area_damage）。
## 圆心 = 角色根 + origin 偏移（caster→0, hit_window→forward/y），半径/尺寸来自节点字段。
## 半径/尺寸在运行时角色坐标系下生效；预览中乘 visual_scale 后再由 preview 乘 zoom 绘制。
func _refresh_range_indicator() -> void:
	if _preview == null:
		return
	var node := _selected_node()
	if node.is_empty():
		_preview.set_range_indicator(false, Vector2.ZERO, 0.0)
		return
	var type_name := String(node.get("type", ""))
	var visual_scale := float(_visual_transform.get("visual_scale", 1.0))
	var center_offset := _resolve_preview_origin(node) * visual_scale
	if type_name == "apply_target_buff":
		if String(node.get("target", "")) != "area":
			_preview.set_range_indicator(false, Vector2.ZERO, 0.0)
			return
		var radius := float(node.get("radius", 80.0))
		_preview.set_range_indicator(true, center_offset, radius, "circle")
	elif type_name == "area_damage":
		var shape := String(node.get("shape", "circle"))
		var radius := float(node.get("radius", 80.0))
		var size := Vector2(float(node.get("width", 160.0)), float(node.get("height", 80.0)))
		_preview.set_range_indicator(true, center_offset, radius, shape, size)
	else:
		_preview.set_range_indicator(false, Vector2.ZERO, 0.0)


## 预览窗口拖拽特效时的回调：从绘制空间绝对偏移反推节点 effect_offset_x/y 并写回。
## 不调用 _refresh_preview() —— preview 内部已自行更新位置，避免重建实例打断拖拽。
## SpinBox 用 set_value_no_signal 同步显示，避免触发 value_changed -> _update_node -> refresh 链路。
## 坐标换算（对齐 _refresh_effect_preview 的 apply_self_buff 分支）：
##   effect_offset.x = offset.x * mirror_x * visual_scale   →   offset.x = effect_offset.x / (mirror_x * visual_scale)
##   effect_offset.y = (offset.y + body_center_y) * visual_scale   →   offset.y = effect_offset.y / visual_scale - body_center_y
func _on_effect_offset_changed(effect_offset: Vector2) -> void:
	var index := _selected_node_index()
	if index < 0:
		return
	var skill := _current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index >= nodes.size() or not nodes[index] is Dictionary:
		return
	var node: Dictionary = nodes[index]
	if String(node.get("type", "")) != "apply_self_buff":
		return
	var visual_scale: float = float(_visual_transform.get("visual_scale", 1.0))
	if visual_scale <= 0.01:
		visual_scale = 1.0
	var body_center_y := float(_visual_transform.get("body_center_y", -50.0))
	# 预览固定朝左，mirror_x = +1
	var new_x := effect_offset.x / visual_scale
	var new_y := effect_offset.y / visual_scale - body_center_y
	node["effect_offset_x"] = new_x
	node["effect_offset_y"] = new_y
	nodes[index] = node
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	if _effect_offset_x_spin != null and is_instance_valid(_effect_offset_x_spin):
		_effect_offset_x_spin.set_value_no_signal(new_x)
	if _effect_offset_y_spin != null and is_instance_valid(_effect_offset_y_spin):
		_effect_offset_y_spin.set_value_no_signal(new_y)


## 预览中解析 spawn_projectile 的 origin 偏移（相对角色根）。
## hit_window: 取第一个 hit_window 的 forward/y（与预览绘制的命中框一致）
## caster/socket/nearest_enemy: 用角色根（零偏移）
func _resolve_preview_origin(node: Dictionary) -> Vector2:
	var origin_type := String(node.get("origin", "hit_window"))
	if origin_type == "hit_window":
		var windows: Array = _action_data.get("hit_windows", [])
		if not windows.is_empty() and windows[0] is Dictionary:
			var w: Dictionary = windows[0]
			var forward := float(w.get("forward", 0.0))
			var y := float(w.get("y", 0.0))
			# 预览固定朝左，forward 正方向即 -X（命中框在角色左侧）
			return Vector2(-absf(forward), y)
	if origin_type == "caster":
		# 抬到身体中心：读 _visual_transform.body_center_y（对应运行时 CollisionShape2D.position.y）
		var body_center_y := float(_visual_transform.get("body_center_y", 0.0))
		return Vector2(0.0, body_center_y)
	# socket / nearest_enemy 在预览中用角色根（零偏移）
	return Vector2.ZERO


func _selected_node() -> Dictionary:
	var index := _selected_node_index()
	if index < 0:
		return {}
	var nodes: Array = _current_skill().get("nodes", [])
	if index >= nodes.size() or not nodes[index] is Dictionary:
		return {}
	return nodes[index]


func _prev_frame() -> void:
	var frame := int(_frame_slider.value)
	var max_frame := int(_frame_slider.max_value)
	_frame_slider.value = wrapi(frame - 1, 0, max_frame + 1)


func _next_frame() -> void:
	var frame := int(_frame_slider.value)
	var max_frame := int(_frame_slider.max_value)
	_frame_slider.value = wrapi(frame + 1, 0, max_frame + 1)


func _on_play_toggled(pressed: bool) -> void:
	_is_playing = pressed
	_play_button.text = "暂停" if pressed else "播放"
	set_process(pressed)
	if pressed:
		_play_accumulator = 0.0


func _process(delta: float) -> void:
	if not _is_playing or _sprite_frames == null:
		return
	_play_accumulator += delta
	var frame_interval := 1.0 / _play_fps
	while _play_accumulator >= frame_interval:
		_play_accumulator -= frame_interval
		var frame := int(_frame_slider.value)
		var max_frame := int(_frame_slider.max_value)
		_frame_slider.value = wrapi(frame + 1, 0, max_frame + 1)


func _refresh_timeline() -> void:
	if _timeline == null:
		return
	var frame_count := _frame_count_for_action(_action_data)
	_frame_slider.max_value = frame_count - 1
	_frame_slider.value = clampf(_frame_slider.value, 0, frame_count - 1)
	_timeline.set_timeline(_action_data, _current_skill().get("nodes", []), frame_count, int(_frame_slider.value), _selected_node_index())
	_refresh_preview()


func _frame_count_for_action(action: Dictionary) -> int:
	var max_frame := 7
	for value in action.get("events", []):
		if value is Dictionary:
			max_frame = maxi(max_frame, int(value.get("frame", 0)) + 4)
	for value in action.get("hit_windows", []):
		if value is Dictionary:
			max_frame = maxi(max_frame, int(value.get("end_frame", 0)) + 4)
	return max_frame + 1


func _on_frame_changed(value: float) -> void:
	_timeline.set_current_frame(int(value))
	_refresh_preview()


func _on_timeline_frame_selected(frame: int) -> void:
	_frame_slider.set_value_no_signal(frame)
	_refresh_preview()


func _on_timeline_node_selected(index: int) -> void:
	if index >= 0 and index < _node_list.item_count:
		_node_list.select(index)
		_show_node_details(index)


func _default_action() -> String:
	for node in _current_skill().get("nodes", []):
		if node is Dictionary and String(node.get("type", "")) == "play_animation":
			return String(node.get("action", "attack"))
	return "attack"


func _action_options() -> Array:
	var result: Array = []
	var asset_path := _find_asset_path_for_skill(int(_current_skill_id))
	var combat_path := asset_path.path_join("combat_actions.json")
	var actions: Dictionary = _read_json(combat_path).get("actions", {})
	for action_name in actions.keys():
		result.append({"value": String(action_name), "label": String(action_name)})
	if result.is_empty():
		result.append({"value": "attack", "label": "attack"})
	return result


func _event_names() -> Array:
	var result: Array = []
	for value in _action_data.get("events", []):
		if value is Dictionary:
			var name := String(value.get("name", ""))
			if not name.is_empty() and not result.has(name):
				result.append(name)
	return result


func _event_label(name: String) -> String:
	return String({"release": "释放", "impact": "命中", "effect": "效果"}.get(name, name))


func _config_uses_skill(config: Dictionary, skill_id: int) -> bool:
	if int(config.get("normal_skill", 0)) == skill_id:
		return true
	for value in config.get("skills", []):
		if int(value) == skill_id:
			return true
	for slot in (config.get("skill_unlocks", {}) as Dictionary).values():
		if slot is Dictionary and int(slot.get("skill_id", 0)) == skill_id:
			return true
	return false


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data


func _add_new_skill() -> void:
	var new_id := _compute_new_skill_id()
	if new_id <= 0:
		_status.text = "无法分配新技能 ID。"
		return
	var id_str := str(new_id)
	# 默认命名：当前选中实体 ID + _skill（如 8001_skill）；未选实体时回退「新技能」
	var default_name := "新技能"
	if not _current_hero_key.is_empty():
		var parts := _current_hero_key.split(":")
		if parts.size() >= 2:
			default_name = "%s_skill" % parts[1]
	var new_skill := {
		"name": default_name,
		"description": "",
		"cooldown": 1.0,
		"nodes": [
			{"type": "play_animation", "action": "attack"},
			{"type": "wait_hit_window", "hit_window_index": 0},
			{"type": "melee_damage", "result_key": "new_hit", "damage_ratio": 1.0},
			{"type": "wait_animation_end"},
			{"type": "end_skill"}
		]
	}
	_skills[id_str] = new_skill
	if not _current_hero_key.is_empty():
		_link_skill_to_hero(_current_hero_key, new_id)
	_save_skills_silent()
	_current_skill_id = id_str
	_rebuild_skill_select()
	_load_skill_fields()
	_load_action_data()
	_refresh_all()
	_refresh_entity_list()
	if not _current_hero_key.is_empty():
		_status.text = "已创建技能 %s 并关联到当前英雄，已保存 skills.json 和角色配置。" % id_str
	else:
		_status.text = "已创建技能 %s，已保存 skills.json。请在基础页填写名称和参数。" % id_str


func _delete_current_skill() -> void:
	if _current_skill_id.is_empty():
		_status.text = "请先选择要删除的技能。"
		return
	var skill: Dictionary = _skills.get(_current_skill_id, {})
	var skill_name := String(skill.get("name", ""))
	var id_int := int(_current_skill_id)
	var affected_heroes := _find_heroes_using_skill(id_int)
	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "删除技能"
	var msg := "确认删除技能 %s (%s)？" % [_current_skill_id, skill_name]
	if not affected_heroes.is_empty():
		msg += "\n该技能被以下角色/怪物引用，删除后会自动从它们的技能列表中移除：\n" + ", ".join(affected_heroes)
	confirm_dialog.dialog_text = msg
	confirm_dialog.confirmed.connect(_do_delete_current_skill.bind(id_int))
	add_child(confirm_dialog)
	confirm_dialog.popup_centered(Vector2i(520, 220))


func _do_delete_current_skill(skill_id: int) -> void:
	var id_str := str(skill_id)
	_skills.erase(id_str)
	_save_skills_silent()
	_unlink_skill_from_all_heroes(skill_id)
	_current_skill_id = ""
	_rebuild_skill_select()
	_refresh_entity_list()
	_status.text = "已删除技能 %s，已保存 skills.json 和角色配置。" % id_str


func _find_heroes_using_skill(skill_id: int) -> Array:
	var result: Array = []
	for id_str in _characters_config.keys():
		var config: Dictionary = _characters_config[id_str]
		if _config_uses_skill(config, skill_id):
			result.append("[英雄] %s %s" % [id_str, String(config.get("name", ""))])
	for id_str in _enemies_config.keys():
		var config: Dictionary = _enemies_config[id_str]
		if _config_uses_skill(config, skill_id):
			result.append("[怪物] %s %s" % [id_str, String(config.get("name", ""))])
	return result


func _unlink_skill_from_all_heroes(skill_id: int) -> void:
	var chars_changed := false
	for id_str in _characters_config.keys():
		var config: Dictionary = _characters_config[id_str]
		if _remove_skill_from_config(config, skill_id):
			_characters_config[id_str] = config
			chars_changed = true
	if chars_changed:
		_save_config_file(CHARACTERS_PATH, _characters_config)
	var enemies_changed := false
	for id_str in _enemies_config.keys():
		var config: Dictionary = _enemies_config[id_str]
		if _remove_skill_from_config(config, skill_id):
			_enemies_config[id_str] = config
			enemies_changed = true
	if enemies_changed:
		_save_config_file(ENEMIES_PATH, _enemies_config)


func _remove_skill_from_config(config: Dictionary, skill_id: int) -> bool:
	var changed := false
	if int(config.get("normal_skill", 0)) == skill_id:
		config["normal_skill"] = 0
		changed = true
	var skills: Array = config.get("skills", [])
	var filtered: Array = []
	for value in skills:
		if int(value) != skill_id:
			filtered.append(value)
	if filtered.size() != skills.size():
		config["skills"] = filtered
		changed = true
	var unlocks: Dictionary = config.get("skill_unlocks", {})
	var slots_to_remove: Array = []
	for slot_key in unlocks.keys():
		var slot: Dictionary = unlocks[slot_key]
		if int(slot.get("skill_id", 0)) == skill_id:
			slots_to_remove.append(slot_key)
	for slot_key in slots_to_remove:
		unlocks.erase(slot_key)
	if not slots_to_remove.is_empty():
		config["skill_unlocks"] = unlocks
		changed = true
	return changed


func _compute_new_skill_id() -> int:
	var base_id := 0
	if not _current_hero_key.is_empty():
		var hero_ids := _get_hero_skill_ids(_current_hero_key)
		if not hero_ids.is_empty():
			for id_str in hero_ids:
				base_id = maxi(base_id, int(id_str))
			base_id += 1
		else:
			var parts := _current_hero_key.split(":")
			if parts.size() >= 2:
				var config_type := parts[0]
				var hero_id := int(parts[1])
				if config_type == "char":
					base_id = 6000 + (hero_id - 7001) * 10 + 1
				elif config_type == "enemy":
					base_id = 50000 + (hero_id - 8001) * 10 + 1
	else:
		for id_str in _skills.keys():
			base_id = maxi(base_id, int(id_str))
		base_id += 1
	while _skills.has(str(base_id)):
		base_id += 1
	return base_id


func _link_skill_to_hero(hero_key: String, skill_id: int) -> void:
	var parts := hero_key.split(":")
	if parts.size() < 2:
		return
	var config_type := parts[0]
	var hero_id := parts[1]
	if config_type == "char":
		var config: Dictionary = _characters_config.get(hero_id, {})
		var skills: Array = config.get("skills", [])
		var already := false
		for value in skills:
			if int(value) == skill_id:
				already = true
				break
		if not already:
			skills.append(float(skill_id))
		config["skills"] = skills
		_characters_config[hero_id] = config
		_save_config_file(CHARACTERS_PATH, _characters_config)
	elif config_type == "enemy":
		var config: Dictionary = _enemies_config.get(hero_id, {})
		var skills: Array = config.get("skills", [])
		var already := false
		for value in skills:
			if int(value) == skill_id:
				already = true
				break
		if not already:
			skills.append(float(skill_id))
		config["skills"] = skills
		_enemies_config[hero_id] = config
		_save_config_file(ENEMIES_PATH, _enemies_config)


func _save_config_file(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "无法写入 %s" % path
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")


func _save_skills_silent() -> void:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_skills, "\t") + "\n")


func _save_skills() -> void:
	# 保存前为当前技能生成 ai_range_cache
	var compiled_summary := ""
	if not _current_skill_id.is_empty():
		var owner_asset := _find_skill_owner_asset(int(_current_skill_id))
		if not owner_asset.is_empty():
			var cache := AIRangeCompiler.compile(int(_current_skill_id), owner_asset)
			var skill: Dictionary = _skills.get(_current_skill_id, {})
			skill["ai_range_cache"] = cache
			_skills[_current_skill_id] = skill
			compiled_summary = _format_cache_summary(cache)
		else:
			compiled_summary = "（未找到所属角色/怪物，未生成 ai_range_cache）"
	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "无法写入 skills.json"
		return
	file.store_string(JSON.stringify(_skills, "\t") + "\n")
	_status.text = "已保存 skills.json。%s" % compiled_summary
	_refresh_entity_list()


func _format_cache_summary(cache: Dictionary) -> String:
	var entries: Array = cache.get("entries", [])
	if entries.is_empty():
		return "ai_range_cache 为空。"
	var parts: PackedStringArray = []
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var kind := String(entry.get("kind", ""))
		var min_d := float(entry.get("min_edge_distance", 0.0))
		var max_d := float(entry.get("max_edge_distance", 0.0))
		if max_d >= 99990.0:
			parts.append("%s:检测范围内均可" % kind)
		else:
			parts.append("%s:%.0f~%.0f" % [kind, min_d, max_d])
	return "ai_range_cache: " + ", ".join(parts)


## 在 characters.json / enemies.json 中查找技能所属资源路径。
func _find_skill_owner_asset(skill_id: int) -> String:
	for table_path in [CHARACTERS_PATH, ENEMIES_PATH]:
		var table := _load_json(table_path)
		for key in table:
			var row_value: Variant = table[key]
			if not row_value is Dictionary:
				continue
			var row: Dictionary = row_value
			var asset := String(row.get("asset", ""))
			if asset.is_empty():
				continue
			if int(row.get("normal_skill", 0)) == skill_id:
				return asset
			for sid_value in row.get("skills", []):
				if int(sid_value) == skill_id:
					return asset
			for unlock_key in row.get("skill_unlocks", {}):
				var unlock: Dictionary = (row.get("skill_unlocks", {}) as Dictionary).get(unlock_key, {})
				if int(unlock.get("skill_id", 0)) == skill_id:
					return asset
			for sid_value in row.get("ai_skill_priority", []):
				if int(sid_value) == skill_id:
					return asset
	return ""


## Finds the independent AI VFX package for the selected skill and previews the
## exact play_effect nodes that will be imported. The web tool never writes
## skills.json directly; this editor remains the only authoritative writer.
func _open_skill_fx_bundle() -> void:
	if _current_skill_id.is_empty():
		_status.text = "请先选择技能，再导入 AI 特效包。"
		return
	var matches: Array[String] = []
	if DirAccess.dir_exists_absolute(SKILL_FX_ROOT):
		for folder_name in DirAccess.get_directories_at(SKILL_FX_ROOT):
			var manifest_path := SKILL_FX_ROOT.path_join(String(folder_name)).path_join("skill_fx_bundle.json")
			var manifest := _read_json(manifest_path)
			if String(manifest.get("format", "")) == "frame-ronin-skill-fx-bundle-v1" and String(manifest.get("skill_id", "")) == _current_skill_id:
				matches.append(manifest_path)
	if matches.size() == 1:
		_prepare_skill_fx_import(matches[0])
		return
	if matches.size() > 1:
		matches.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
		_prepare_skill_fx_import(matches[0])
		_status.text = "检测到多个特效包，已选择最近修改的一份：%s" % matches[0]
		return
	_open_skill_fx_file_dialog()


func _open_skill_fx_file_dialog() -> void:
	if _skill_fx_file_dialog == null:
		_skill_fx_file_dialog = FileDialog.new()
		_skill_fx_file_dialog.title = "选择 skill_fx_bundle.json"
		_skill_fx_file_dialog.access = FileDialog.ACCESS_RESOURCES
		_skill_fx_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_skill_fx_file_dialog.filters = PackedStringArray(["*.json ; Skill FX Bundle"])
		_skill_fx_file_dialog.file_selected.connect(_prepare_skill_fx_import)
		add_child(_skill_fx_file_dialog)
	_skill_fx_file_dialog.current_dir = SKILL_FX_ROOT
	_skill_fx_file_dialog.popup_centered_ratio(0.72)


func _prepare_skill_fx_import(manifest_path: String) -> void:
	var manifest := _read_json(manifest_path)
	var validation_error := _validate_skill_fx_manifest(manifest)
	if not validation_error.is_empty():
		_status.text = "特效包校验失败：%s" % validation_error
		return
	var build_result := _build_skill_fx_nodes(manifest)
	var build_error := String(build_result.get("error", ""))
	if not build_error.is_empty():
		_status.text = "特效包无法导入：%s" % build_error
		return
	_pending_skill_fx_import = {
		"manifest": manifest,
		"manifest_path": manifest_path,
		"nodes": build_result.get("nodes", []),
		"track_count": int(build_result.get("track_count", 0)),
	}
	_show_skill_fx_confirmation(manifest, build_result)


func _validate_skill_fx_manifest(manifest: Dictionary) -> String:
	if manifest.is_empty() or String(manifest.get("format", "")) != "frame-ronin-skill-fx-bundle-v1":
		return "不是 frame-ronin-skill-fx-bundle-v1 文件"
	if int(manifest.get("version", 0)) != 1:
		return "仅支持版本 1"
	if String(manifest.get("skill_id", "")) != _current_skill_id:
		return "包内 skill_id 与当前技能不一致"
	var bundle_id := String(manifest.get("bundle_id", ""))
	if bundle_id.is_empty():
		return "缺少 bundle_id"
	var expected_action_hash := String(manifest.get("action_hash", ""))
	var owner_asset := _find_skill_owner_asset(int(_current_skill_id))
	if owner_asset.is_empty():
		return "无法定位技能所属角色或怪物"
	var combat_path := owner_asset.path_join("combat_actions.json")
	if expected_action_hash.is_empty() or not FileAccess.file_exists(combat_path):
		return "缺少动作配置或动作哈希"
	if FileAccess.get_sha256(combat_path) != expected_action_hash:
		return "combat_actions.json 已变化，请回网页重新连接项目并导出"
	var has_existing_bundle_nodes := false
	for value in _current_skill().get("nodes", []):
		if value is Dictionary and String(value.get("source_bundle_id", "")) == bundle_id:
			has_existing_bundle_nodes = true
			break
	var expected_skill_hash := String(manifest.get("skill_hash", ""))
	if not has_existing_bundle_nodes and (expected_skill_hash.is_empty() or FileAccess.get_sha256(SKILLS_PATH) != expected_skill_hash):
		return "skills.json 已变化，请回网页重新连接项目并导出"
	var tracks: Array = manifest.get("tracks", [])
	if tracks.is_empty():
		return "特效包没有轨道"
	var ids: Dictionary = {}
	var events := _event_names()
	var hit_windows: Array = _action_data.get("hit_windows", [])
	var clean_node_count := 0
	for value in _current_skill().get("nodes", []):
		if value is Dictionary and String(value.get("source_bundle_id", "")).is_empty():
			clean_node_count += 1
	for value in tracks:
		if not value is Dictionary:
			return "轨道必须是对象"
		var track: Dictionary = value
		var track_id := String(track.get("id", ""))
		if track_id.is_empty() or ids.has(track_id):
			return "轨道 ID 为空或重复：%s" % track_id
		ids[track_id] = true
		var asset: Dictionary = track.get("asset", {})
		var scene_path := String(asset.get("scene_path", ""))
		if not scene_path.begins_with("res://"):
			scene_path = "res://" + scene_path
		if not scene_path.begins_with("res://assets/skill_fx/%s/" % bundle_id):
			return "轨道资源越出自身特效包：%s" % track_id
		if not ResourceLoader.exists(scene_path):
			return "特效场景不存在或尚未导入：%s" % scene_path
		var trigger: Dictionary = track.get("trigger", {})
		match String(trigger.get("type", "")):
			"skill_start":
				pass
			"action_event":
				if not events.has(String(trigger.get("event", ""))):
					return "不存在动作事件：%s" % String(trigger.get("event", ""))
			"hit_window_start":
				if int(trigger.get("hit_window_index", -1)) < 0 or int(trigger.get("hit_window_index", -1)) >= hit_windows.size():
					return "攻击窗口索引无效：%s" % track_id
			"after_skill_node":
				if int(trigger.get("node_index", -1)) < 0 or int(trigger.get("node_index", -1)) >= clean_node_count:
					return "技能节点索引无效：%s" % track_id
			_:
				return "不支持的触发方式：%s" % String(trigger.get("type", ""))
	return ""


func _build_skill_fx_nodes(manifest: Dictionary) -> Dictionary:
	var bundle_id := String(manifest.get("bundle_id", ""))
	var skill := _current_skill()
	var nodes: Array = []
	# A skill has one active imported package. Strip previous imported VFX nodes,
	# while retaining every gameplay/control node byte-for-byte.
	for value in skill.get("nodes", []):
		if value is Dictionary and String(value.get("source_bundle_id", "")).is_empty():
			nodes.append(value.duplicate(true))
	var play_animation_index := -1
	for index in range(nodes.size()):
		if nodes[index] is Dictionary and String(nodes[index].get("type", "")) == "play_animation":
			play_animation_index = index
			break
	if play_animation_index < 0:
		return {"error": "当前技能没有 play_animation 节点"}
	var descriptors: Array[Dictionary] = []
	for value in manifest.get("tracks", []):
		var track: Dictionary = value
		var trigger: Dictionary = track.get("trigger", {})
		var trigger_type := String(trigger.get("type", ""))
		var base_index := play_animation_index
		var delay_ms := int(trigger.get("offset_ms", 0))
		var anchor_node: Dictionary = nodes[play_animation_index]
		if trigger_type == "action_event":
			var event_name := String(trigger.get("event", ""))
			var event_wait_index := _find_wait_node(nodes, "wait_action_event", "event", event_name)
			if event_wait_index >= 0:
				base_index = event_wait_index
				anchor_node = nodes[event_wait_index]
			else:
				delay_ms += _action_event_time_ms(event_name)
		elif trigger_type == "hit_window_start":
			var window_index := int(trigger.get("hit_window_index", 0))
			var hit_wait_index := _find_wait_node(nodes, "wait_hit_window", "hit_window_index", window_index)
			if hit_wait_index >= 0:
				base_index = hit_wait_index
				anchor_node = nodes[hit_wait_index]
			else:
				delay_ms += _hit_window_time_ms(window_index)
		elif trigger_type == "after_skill_node":
			base_index = int(trigger.get("node_index", 0))
			anchor_node = nodes[base_index]
		var effect_node := _skill_fx_track_to_node(track, bundle_id, anchor_node, max(0, delay_ms))
		descriptors.append({"base_index": base_index, "node": effect_node})
	# Descending insertion keeps all original gameplay node indexes stable.
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("base_index", 0)) > int(b.get("base_index", 0)))
	for descriptor in descriptors:
		nodes.insert(int(descriptor.get("base_index", 0)) + 1, descriptor.get("node", {}))
	return {"nodes": nodes, "track_count": descriptors.size(), "error": ""}


func _find_wait_node(nodes: Array, type_name: String, field: String, expected: Variant) -> int:
	for index in range(nodes.size()):
		if not nodes[index] is Dictionary:
			continue
		var node: Dictionary = nodes[index]
		if String(node.get("type", "")) == type_name and node.get(field) == expected:
			return index
	return -1


func _action_event_time_ms(event_name: String) -> int:
	for value in _action_data.get("events", []):
		if value is Dictionary and String(value.get("name", "")) == event_name:
			return roundi(float(value.get("frame", 0)) / maxf(1.0, _play_fps) * 1000.0)
	return 0


func _hit_window_time_ms(window_index: int) -> int:
	var windows: Array = _action_data.get("hit_windows", [])
	if window_index < 0 or window_index >= windows.size() or not windows[window_index] is Dictionary:
		return 0
	return roundi(float(windows[window_index].get("start_frame", 0)) / maxf(1.0, _play_fps) * 1000.0)


func _skill_fx_track_to_node(track: Dictionary, bundle_id: String, anchor_node: Dictionary, delay_ms: int) -> Dictionary:
	var asset: Dictionary = track.get("asset", {})
	var transform: Dictionary = track.get("transform", {})
	var offset: Dictionary = transform.get("offset", {})
	var scene_path := String(asset.get("scene_path", ""))
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	var coordinate_space := String(track.get("space", "world"))
	var anchor := String(track.get("anchor", "origin"))
	var target := "origin"
	var result_key := ""
	if String(track.get("phase", "")) == "impact" and anchor_node.has("result_key"):
		target = "result"
		result_key = String(anchor_node.get("result_key", "last_result"))
	var node := {
		"type": "play_effect",
		"scene": scene_path,
		"coordinate_space": coordinate_space,
		"target": target,
		"origin": "caster" if coordinate_space == "character_local" else "hit_window",
		"offset_x": float(offset.get("x", 0.0)),
		"offset_y": float(offset.get("y", 0.0)),
		"delay_ms": delay_ms,
		"anchor": anchor,
		"follow_target": coordinate_space == "character_local",
		"mirror_with_facing": String(track.get("direction", "facing")) == "facing",
		"lifetime_ms": int(track.get("duration_ms", 500)),
		"effect_scale": float(transform.get("scale", 1.0)),
		"rotation_degrees": float(transform.get("rotation_degrees", 0.0)),
		"opacity": float(transform.get("opacity", 1.0)),
		"tint": String(transform.get("tint", "#ffffff")),
		"attachment_layer": "behind" if int(track.get("layer", 1)) < 0 else "front",
		"source_bundle_id": bundle_id,
		"source_track_id": String(track.get("id", "")),
	}
	if target == "result":
		node["result_key"] = result_key
	if anchor not in ["origin", "foot", "body_center", "weapon", "hand"]:
		node["origin"] = "socket"
		node["socket"] = anchor
	if coordinate_space == "fullscreen":
		node["duration"] = maxf(0.05, float(track.get("duration_ms", 500)) / 1000.0)
	return node


func _show_skill_fx_confirmation(manifest: Dictionary, build_result: Dictionary) -> void:
	if _skill_fx_dialog == null:
		_skill_fx_dialog = ConfirmationDialog.new()
		_skill_fx_dialog.title = "导入 AI 技能特效包"
		_skill_fx_dialog.ok_button_text = "备份并导入"
		_skill_fx_dialog.cancel_button_text = "取消"
		_skill_fx_dialog.confirmed.connect(_apply_pending_skill_fx_import)
		_skill_fx_dialog.canceled.connect(_refresh_effect_preview)
		_skill_fx_dialog_text = RichTextLabel.new()
		_skill_fx_dialog_text.custom_minimum_size = Vector2(620, 320)
		_skill_fx_dialog_text.fit_content = true
		_skill_fx_dialog.add_child(_skill_fx_dialog_text)
		add_child(_skill_fx_dialog)
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % String((manifest.get("proposal", {}) as Dictionary).get("title", manifest.get("bundle_id", ""))))
	lines.append(String((manifest.get("proposal", {}) as Dictionary).get("summary", "")))
	lines.append("")
	lines.append("将导入 %d 条 play_effect 节点：" % int(build_result.get("track_count", 0)))
	for value in manifest.get("tracks", []):
		if value is Dictionary:
			lines.append("• %s / %s / %s" % [String(value.get("title", value.get("id", ""))), String(value.get("phase", "")), String((value.get("trigger", {}) as Dictionary).get("type", ""))])
	lines.append("")
	lines.append("玩法、伤害、Buff、位移和消耗节点不会被修改。再次导入同一技能包会更新原特效节点。")
	_skill_fx_dialog_text.text = "\n".join(lines)
	# Preview the first package scene in the existing action preview before confirmation.
	var tracks: Array = manifest.get("tracks", [])
	if not tracks.is_empty() and tracks[0] is Dictionary:
		var first: Dictionary = tracks[0]
		var asset: Dictionary = first.get("asset", {})
		var scene_path := String(asset.get("scene_path", ""))
		if not scene_path.begins_with("res://"):
			scene_path = "res://" + scene_path
		var packed := load(scene_path) as PackedScene
		var transform: Dictionary = first.get("transform", {})
		var offset: Dictionary = transform.get("offset", {})
		if packed != null:
			_preview.set_effect(packed, Vector2(float(offset.get("x", 0.0)), float(offset.get("y", 0.0))), true, float(transform.get("scale", 1.0)), String(first.get("space", "world")) == "character_local")
	_skill_fx_dialog.popup_centered(Vector2i(680, 430))


func _apply_pending_skill_fx_import() -> void:
	if _pending_skill_fx_import.is_empty():
		return
	var backup_path := _backup_skills_for_skill_fx()
	if backup_path.is_empty():
		_status.text = "无法备份 skills.json，已取消导入。"
		return
	var skill := _current_skill()
	skill["nodes"] = (_pending_skill_fx_import.get("nodes", []) as Array).duplicate(true)
	_skills[_current_skill_id] = skill
	_save_skills()
	var count := int(_pending_skill_fx_import.get("track_count", 0))
	_status.text = "已导入 %d 条 AI 特效节点。备份：%s" % [count, backup_path]
	_pending_skill_fx_import.clear()
	_rebuild_node_list()
	_refresh_timeline()
	_refresh_effect_preview()


func _backup_skills_for_skill_fx() -> String:
	if not FileAccess.file_exists(SKILLS_PATH):
		return ""
	var timestamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var backup_dir := "res://.frame-ronin/backups/skill-fx/%s" % timestamp
	var absolute_dir := ProjectSettings.globalize_path(backup_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		return ""
	var source := FileAccess.open(SKILLS_PATH, FileAccess.READ)
	var target_path := backup_dir.path_join("skills.json")
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if source == null or target == null:
		return ""
	target.store_buffer(source.get_buffer(source.get_length()))
	return target_path


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data
