@tool
extends Window

const SKILLS_PATH := "res://data/skills.json"
const SkillTimeline = preload("res://addons/game_tools/skill_timeline.gd")
const ACTION_NODE_TYPES := [
	"play_animation", "use_action_hit_window", "execute_skill_effect", "spawn_projectile",
	"aoe", "fullscreen", "apply_self_buff", "heal", "move_x", "play_effect",
]
const CONTROL_NODE_TYPES := ["wait_action_event", "wait_animation_end", "end_skill"]
const NODE_TYPES := ACTION_NODE_TYPES + CONTROL_NODE_TYPES
const NODE_TYPE_LABELS := {
	"play_animation": "播放动画",
	"wait_action_event": "等待动作事件",
	"wait_animation_end": "等待动画结束（阻塞）",
	"use_action_hit_window": "技能生效点（判定框）",
	"execute_skill_effect": "执行技能效果",
	"spawn_projectile": "生成弹道",
	"aoe": "范围攻击",
	"fullscreen": "全屏效果",
	"apply_self_buff": "施加自身 Buff",
	"heal": "治疗",
	"move_x": "水平移动",
	"play_effect": "播放特效",
	"end_skill": "结束技能（立即结束）",
}
const EVENT_LABELS := {
	"release": "释放",
	"impact": "命中",
	"effect": "效果",
}
const DEFAULT_EVENT_NAMES := ["release", "impact", "effect"]
const SKILL_TYPE_LABELS := {
	"melee": "近战",
	"projectile": "普通弹道",
	"penetrate": "穿透弹道",
	"aoe": "范围攻击",
	"fullscreen": "全屏效果",
	"self": "自身效果",
}
const ACTION_NODE_LABEL := "动作"
const CONTROL_NODE_LABEL := "控制"

var _skills: Dictionary = {}
var _skill_select: OptionButton
var _skill_type_select: OptionButton
var _skill_tabs: TabContainer
var _skill_name_edit: LineEdit
var _skill_description_edit: LineEdit
var _skill_animation_edit: LineEdit
var _skill_damage_spin: SpinBox
var _skill_cooldown_spin: SpinBox
var _skill_range_spin: SpinBox
var _skill_aoe_radius_spin: SpinBox
var _projectile_scene_edit: LineEdit
var _projectile_speed_spin: SpinBox
var _projectile_lifetime_spin: SpinBox
var _projectile_spawn_offset_spin: SpinBox
var _max_pierce_spin: SpinBox
var _buff_on_hit_spin: SpinBox
var _buff_chance_spin: SpinBox
var _buff_on_self_spin: SpinBox
var _loading_skill_fields := false
var _timeline: Control
var _frame_slider: HSlider
var _node_list: ItemList
var _move_up_button: Button
var _move_down_button: Button
var _node_type: OptionButton
var _hit_window_mode: OptionButton
var _hit_window_label: Label
var _node_projectile_scene_edit: LineEdit
var _projectile_config_button: Button
var _node_extra_controls: VBoxContainer
var _node_effect_section: VBoxContainer
var _node_rain_section: VBoxContainer
var _node_rain_area_controls: Array[Control] = []
var _node_effect_scene_edit: LineEdit
var _node_effect_scope_select: OptionButton
var _node_effect_offset_x: SpinBox
var _node_effect_offset_y: SpinBox
var _node_rain_mode_select: OptionButton
var _node_rain_count: SpinBox
var _node_rain_interval: SpinBox
var _node_rain_search_range: SpinBox
var _node_rain_width: SpinBox
var _node_rain_height: SpinBox
var _node_rain_flight_time: SpinBox
var _node_rain_gravity: SpinBox
var _node_rain_socket_edit: LineEdit
var _action_select: OptionButton
var _event_select: OptionButton
var _trigger_select: OptionButton
var _trigger_event_select: OptionButton
var _trigger_window_select: OptionButton
var _event_notice: Label
var _status: Label
var _current_skill_id := 0
var _ui_root: Control
var _effect_library_grid: GridContainer
var _effect_library_status: Label
var _effect_library_page_label: Label
var _effect_library_filter := "godot"
var _effect_library_page := 0
var _effect_library_items: Array[Dictionary] = []
var _effect_filter_buttons: Dictionary = {}

const EFFECT_LIBRARY_ROOTS := ["res://scenes/effects", "res://assets/effect", "res://assets/effects"]
const EFFECT_LIBRARY_PAGE_SIZE := 6
const EFFECT_LIBRARY_FILTERS := [
	{"id": "spine", "label": "Spine"},
	{"id": "unity", "label": "Unity"},
	{"id": "sequence", "label": "序列帧"},
	{"id": "godot", "label": "Godot素材"},
]


func _init() -> void:
	title = "技能节点配置"
	size = Vector2i(760, 660)
	min_size = Vector2i(720, 600)
	close_requested.connect(hide)


func _ready() -> void:
	_build_ui()
	_load_skills()
	_rebuild_skill_select()
	_rebuild_action_select()


func open_editor() -> void:
	if _action_select == null or _event_select == null or _skill_type_select == null or _skill_name_edit == null:
		_build_ui()
	_load_skills()
	_rebuild_skill_select()
	_rebuild_action_select()
	popup_centered(size)


func _build_ui() -> void:
	if _action_select != null and _event_select != null and _skill_name_edit != null:
		return
	if _ui_root != null and is_instance_valid(_ui_root):
		remove_child(_ui_root)
		_ui_root.free()
	_skill_select = null
	_skill_type_select = null
	_skill_tabs = null
	_skill_name_edit = null
	_skill_description_edit = null
	_skill_animation_edit = null
	_skill_damage_spin = null
	_skill_cooldown_spin = null
	_skill_range_spin = null
	_skill_aoe_radius_spin = null
	_projectile_scene_edit = null
	_projectile_speed_spin = null
	_projectile_lifetime_spin = null
	_projectile_spawn_offset_spin = null
	_max_pierce_spin = null
	_buff_on_hit_spin = null
	_buff_chance_spin = null
	_buff_on_self_spin = null
	_node_projectile_scene_edit = null
	_projectile_config_button = null
	_hit_window_label = null
	_node_extra_controls = null
	_node_effect_section = null
	_node_rain_section = null
	_node_rain_area_controls.clear()
	_node_effect_scene_edit = null
	_node_effect_scope_select = null
	_node_effect_offset_x = null
	_node_effect_offset_y = null
	_node_rain_mode_select = null
	_node_rain_count = null
	_node_rain_interval = null
	_node_rain_search_range = null
	_node_rain_width = null
	_node_rain_height = null
	_node_rain_flight_time = null
	_node_rain_gravity = null
	_node_rain_socket_edit = null
	_action_select = null
	_event_select = null
	_timeline = null
	var root := VBoxContainer.new()
	_ui_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(Label.new())
	(top.get_child(0) as Label).text = "技能"
	_skill_select = OptionButton.new()
	_skill_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_select.item_selected.connect(_on_skill_selected)
	top.add_child(_skill_select)
	top.add_child(Label.new())
	(top.get_child(2) as Label).text = "技能类型"
	_skill_type_select = OptionButton.new()
	_skill_type_select.item_selected.connect(_on_skill_type_selected)
	for skill_type in SKILL_TYPE_LABELS:
		_skill_type_select.add_item(SKILL_TYPE_LABELS[skill_type])
		_skill_type_select.set_item_metadata(_skill_type_select.item_count - 1, skill_type)
	top.add_child(_skill_type_select)

	var params_scroll := ScrollContainer.new()
	params_scroll.custom_minimum_size.y = 170
	params_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(params_scroll)
	var params := GridContainer.new()
	params.columns = 2
	params.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	params_scroll.add_child(params)
	_skill_name_edit = _add_skill_line_edit(params, "技能名称", "name")
	_skill_description_edit = _add_skill_line_edit(params, "技能描述", "description")
	_skill_animation_edit = _add_skill_line_edit(params, "默认动作", "animation")
	_skill_damage_spin = _add_skill_spin(params, "伤害倍率", "damage_ratio", 1.0, -99.0, 99.0, 0.1)
	_skill_cooldown_spin = _add_skill_spin(params, "冷却时间", "cooldown", 0.0, 0.0, 999.0, 0.1)
	_skill_range_spin = _add_skill_spin(params, "技能射程", "range", 0.0, 0.0, 9999.0, 1.0)
	_skill_aoe_radius_spin = _add_skill_spin(params, "范围半径", "aoe_radius", 0.0, 0.0, 9999.0, 1.0)
	_projectile_scene_edit = _add_skill_line_edit(params, "弹道场景", "projectile_scene")
	_projectile_speed_spin = _add_skill_spin(params, "弹道速度", "projectile_speed", 300.0, 0.0, 9999.0, 1.0)
	_projectile_lifetime_spin = _add_skill_spin(params, "弹道生命周期", "projectile_lifetime", 5.0, 0.0, 999.0, 0.1)
	_projectile_spawn_offset_spin = _add_skill_spin(params, "弹道出生偏移", "projectile_spawn_offset", 32.0, 0.0, 9999.0, 1.0)
	_max_pierce_spin = _add_skill_spin(params, "最大穿透数", "max_pierce", 0.0, -1.0, 9999.0, 1.0)
	_buff_on_hit_spin = _add_skill_spin(params, "命中 Buff ID", "buff_on_hit", 0.0, 0.0, 999999.0, 1.0)
	_buff_chance_spin = _add_skill_spin(params, "命中 Buff 概率", "buff_chance", 0.0, 0.0, 1.0, 0.05)
	_buff_on_self_spin = _add_skill_spin(params, "自身 Buff ID", "buff_on_self", 0.0, 0.0, 999999.0, 1.0)

	params_scroll.hide()
	root.remove_child(params_scroll)
	params_scroll.free()
	_skill_tabs = _build_skill_parameter_tabs(root)
	var timeline_tabs: TabContainer = _skill_tabs

	var timeline_page := VBoxContainer.new()
	timeline_page.name = "时间轴编辑"
	timeline_page.add_theme_constant_override("separation", 6)
	timeline_tabs.add_child(timeline_page)

	var frame_bar := HBoxContainer.new()
	root.add_child(frame_bar)
	frame_bar.add_child(Label.new())
	(frame_bar.get_child(0) as Label).text = "当前帧"
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0
	_frame_slider.max_value = 7
	_frame_slider.step = 1
	_frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_slider.value_changed.connect(_on_frame_slider_changed)
	frame_bar.add_child(_frame_slider)

	_timeline = SkillTimeline.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.custom_minimum_size = Vector2(600, 150)
	_timeline.frame_selected.connect(_on_timeline_frame_selected)
	_timeline.node_selected.connect(_on_timeline_node_selected)
	root.add_child(_timeline)

	_node_list = ItemList.new()
	_node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_list.item_selected.connect(_on_node_selected)
	root.add_child(_node_list)

	var order_buttons := HBoxContainer.new()
	root.add_child(order_buttons)
	_move_up_button = Button.new()
	_move_up_button.text = "上移"
	_move_up_button.pressed.connect(_move_selected_node_up)
	order_buttons.add_child(_move_up_button)
	_move_down_button = Button.new()
	_move_down_button.text = "下移"
	_move_down_button.pressed.connect(_move_selected_node_down)
	order_buttons.add_child(_move_down_button)
	_update_reorder_buttons()

	var controls := GridContainer.new()
	controls.columns = 2
	controls.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	controls.custom_minimum_size.x = 720
	root.add_child(controls)

	controls.add_child(Label.new())
	(controls.get_child(0) as Label).text = "节点类型"
	_node_type = OptionButton.new()
	_node_type.custom_minimum_size.x = 360
	_node_type.item_selected.connect(_on_node_type_selected)
	_node_type.add_separator("动作节点")
	for item in ACTION_NODE_TYPES:
		_node_type.add_item(String(NODE_TYPE_LABELS[item]))
		_node_type.set_item_metadata(_node_type.item_count - 1, String(item))
	_node_type.add_separator("控制节点")
	for item in CONTROL_NODE_TYPES:
		_node_type.add_item(String(NODE_TYPE_LABELS[item]))
		_node_type.set_item_metadata(_node_type.item_count - 1, String(item))
	controls.add_child(_node_type)

	controls.add_child(Label.new())
	(controls.get_child(2) as Label).text = "生效方式"
	_hit_window_mode = OptionButton.new()
	_hit_window_mode.custom_minimum_size.x = 150
	_hit_window_mode.add_item("近战伤害")
	_hit_window_mode.set_item_metadata(0, "damage")
	_hit_window_mode.add_item("弹道发射")
	_hit_window_mode.set_item_metadata(1, "projectile")
	_hit_window_mode.add_item("技能生效帧")
	_hit_window_mode.set_item_metadata(2, "effect")
	_hit_window_mode.item_selected.connect(_on_hit_window_mode_selected)
	var hit_window_controls := HBoxContainer.new()
	hit_window_controls.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hit_window_controls.custom_minimum_size.x = 540
	hit_window_controls.add_child(_hit_window_mode)
	_node_projectile_scene_edit = LineEdit.new()
	_node_projectile_scene_edit.placeholder_text = "projectile_scene"
	_node_projectile_scene_edit.custom_minimum_size.x = 260
	_node_projectile_scene_edit.text_changed.connect(_on_node_projectile_scene_changed)
	hit_window_controls.add_child(_node_projectile_scene_edit)
	_projectile_config_button = Button.new()
	_projectile_config_button.text = "弹道配置"
	_projectile_config_button.pressed.connect(_open_projectile_config)
	hit_window_controls.add_child(_projectile_config_button)
	controls.add_child(hit_window_controls)

	controls.add_child(Label.new())
	(controls.get_child(4) as Label).text = "动作"
	_action_select = OptionButton.new()
	_action_select.custom_minimum_size.x = 360
	_action_select.item_selected.connect(_on_action_selected)
	controls.add_child(_action_select)

	controls.add_child(Label.new())
	(controls.get_child(6) as Label).text = "事件"
	_event_select = OptionButton.new()
	_event_select.custom_minimum_size.x = 360
	controls.add_child(_event_select)
	var event_label_to_remove := controls.get_child(6)
	controls.remove_child(event_label_to_remove)
	event_label_to_remove.free()
	var action_label_to_remove := controls.get_child(4)
	controls.remove_child(action_label_to_remove)
	action_label_to_remove.free()
	var node_label := controls.get_child(0) as Label
	var node_selector := controls.get_child(1) as Control
	var effect_label := controls.get_child(2) as Label
	var action_selector := controls.get_child(4) as Control
	var event_selector := controls.get_child(5) as Control
	for child in [node_label, node_selector, effect_label, hit_window_controls, action_selector, event_selector]:
		controls.remove_child(child)
	controls.columns = 1
	controls.add_child(_make_node_control_row(node_label, node_selector))
	controls.add_child(_make_node_control_row(effect_label, hit_window_controls))
	var action_row_label := Label.new()
	action_row_label.text = "动作"
	controls.add_child(_make_node_control_row(action_row_label, action_selector))
	var event_row_label := Label.new()
	event_row_label.text = "事件"
	controls.add_child(_make_node_control_row(event_row_label, event_selector))
	_hit_window_label = effect_label
	_node_extra_controls = VBoxContainer.new()
	_node_extra_controls.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	controls.add_child(_node_extra_controls)
	_build_node_extra_controls(_node_extra_controls)
	var controls_wrapper := HBoxContainer.new()
	controls_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(controls_wrapper)
	root.remove_child(controls)
	controls_wrapper.add_child(controls)
	var controls_spacer := Control.new()
	controls_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_wrapper.add_child(controls_spacer)

	var trigger_controls := HBoxContainer.new()
	root.add_child(trigger_controls)
	root.move_child(controls_wrapper, root.get_children().find(trigger_controls))
	var trigger_label := Label.new()
	trigger_label.text = "节点触发"
	trigger_controls.add_child(trigger_label)
	_trigger_select = OptionButton.new()
	_trigger_select.add_item("立即执行")
	_trigger_select.set_item_metadata(0, "immediate")
	_trigger_select.add_item("动画事件")
	_trigger_select.set_item_metadata(1, "event")
	_trigger_select.add_item("攻击有效区间")
	_trigger_select.set_item_metadata(2, "hit_window")
	_trigger_select.add_item("动画结束")
	_trigger_select.set_item_metadata(3, "animation_end")
	_trigger_select.item_selected.connect(_on_trigger_mode_selected)
	trigger_controls.add_child(_trigger_select)
	var event_label := Label.new()
	event_label.text = "事件"
	trigger_controls.add_child(event_label)
	_trigger_event_select = OptionButton.new()
	_trigger_event_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trigger_controls.add_child(_trigger_event_select)
	var window_label := Label.new()
	window_label.text = "有效区间"
	trigger_controls.add_child(window_label)
	_trigger_window_select = OptionButton.new()
	_trigger_window_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trigger_controls.add_child(_trigger_window_select)
	var apply_trigger_button := Button.new()
	apply_trigger_button.text = "应用触发时机"
	apply_trigger_button.pressed.connect(_apply_selected_node_trigger)
	trigger_controls.add_child(apply_trigger_button)
	_update_trigger_controls_visibility()
	_event_notice = Label.new()
	_event_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_notice.add_theme_color_override("font_color", Color("ffca64"))
	root.add_child(_event_notice)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	var template_label := Label.new()
	template_label.text = "通用模板"
	root.add_child(template_label)
	var template_grid := GridContainer.new()
	template_grid.columns = 2
	root.add_child(template_grid)
	_add_template_button(template_grid, "套用普攻模板", _apply_melee_template)
	_add_template_button(template_grid, "套用弹道模板", _apply_projectile_template)
	_add_template_button(template_grid, "套用自身 Buff 模板", _apply_self_buff_template)
	_add_template_button(template_grid, "清空自定义节点", _clear_custom_nodes)
	var template_help := Label.new()
	template_help.text = "普攻/弹道需先在‘配置攻击判定’设置有效帧；弹道还需填写 projectile_scene；自身 Buff 需填写 buff_on_self。"
	template_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(template_help)

	var add_button := Button.new()
	add_button.text = "新增节点"
	add_button.pressed.connect(_add_node)
	buttons.add_child(add_button)
	var delete_button := Button.new()
	delete_button.text = "删除选中"
	delete_button.pressed.connect(_delete_selected_node)
	buttons.add_child(delete_button)
	var save_button := Button.new()
	save_button.text = "保存 skills.json"
	save_button.pressed.connect(_save_skills)
	buttons.add_child(save_button)

	_status = Label.new()
	root.add_child(_status)

	var lower_split := HBoxContainer.new()
	lower_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower_split.add_theme_constant_override("separation", 10)
	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 6)
	var effect_library := _build_effect_library_panel()
	effect_library.custom_minimum_size = Vector2(520, 420)
	effect_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower_split.add_child(left_column)
	lower_split.add_child(effect_library)

	for part in [frame_bar, _timeline]:
		root.remove_child(part)
		timeline_page.add_child(part)
	var lower_parts: Array[Node] = [
		_node_list, order_buttons, controls_wrapper, trigger_controls,
		_event_notice, buttons, template_label, template_grid, template_help, _status,
	]
	for part in lower_parts:
		root.remove_child(part)
		left_column.add_child(part)
	timeline_page.add_child(lower_split)
	_reload_effect_library()


func _add_template_button(parent: Container, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)


func _build_effect_library_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "特效库（绑定到播放特效节点）"
	panel.add_child(title)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	_effect_filter_buttons.clear()
	for item in EFFECT_LIBRARY_FILTERS:
		var button := Button.new()
		button.text = str(item.get("label", ""))
		button.toggle_mode = true
		button.button_pressed = str(item.get("id", "")) == _effect_library_filter
		button.pressed.connect(_on_effect_filter_selected.bind(str(item.get("id", ""))))
		toolbar.add_child(button)
		_effect_filter_buttons[str(item.get("id", ""))] = button
	var refresh_button := Button.new()
	refresh_button.text = "刷新"
	refresh_button.pressed.connect(_reload_effect_library)
	toolbar.add_child(refresh_button)
	var prev_button := Button.new()
	prev_button.text = "上一页"
	prev_button.pressed.connect(_turn_effect_library_page.bind(-1))
	toolbar.add_child(prev_button)
	var next_button := Button.new()
	next_button.text = "下一页"
	next_button.pressed.connect(_turn_effect_library_page.bind(1))
	toolbar.add_child(next_button)
	_effect_library_page_label = Label.new()
	toolbar.add_child(_effect_library_page_label)
	panel.add_child(toolbar)

	var scroller := ScrollContainer.new()
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_effect_library_grid = GridContainer.new()
	_effect_library_grid.columns = 2
	_effect_library_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(_effect_library_grid)
	panel.add_child(scroller)

	_effect_library_status = Label.new()
	_effect_library_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_effect_library_status)
	return panel


func _on_effect_filter_selected(filter_id: String) -> void:
	_effect_library_filter = filter_id
	_effect_library_page = 0
	_refresh_effect_library_view()


func _turn_effect_library_page(delta: int) -> void:
	var items := _filtered_effect_library_items()
	var total_pages := maxi(1, int(ceil(float(items.size()) / float(EFFECT_LIBRARY_PAGE_SIZE))))
	_effect_library_page = clampi(_effect_library_page + delta, 0, total_pages - 1)
	_refresh_effect_library_view()


func _reload_effect_library() -> void:
	_effect_library_items.clear()
	for root_path in EFFECT_LIBRARY_ROOTS:
		_scan_effect_library(root_path, _effect_library_items)
	_effect_library_items.sort_custom(func(a, b): return str(a.get("key", "")) < str(b.get("key", "")))
	_effect_library_page = 0
	_refresh_effect_library_view()


func _scan_effect_library(path: String, result: Array[Dictionary]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child_path := path.path_join(name)
		if dir.current_is_dir():
			_scan_effect_library(child_path, result)
		elif _is_effect_library_file(name):
			var item := _make_effect_library_item(child_path)
			if not item.is_empty():
				result.append(item)
		name = dir.get_next()


func _is_effect_library_file(file_name: String) -> bool:
	var ext := file_name.get_extension().to_lower()
	return ["tscn", "scn", "png", "webp", "jpg", "jpeg", "tres"].has(ext)


func _make_effect_library_item(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var scene_path := path if ["tscn", "scn"].has(ext) else _find_effect_scene_for_visual(path)
	var category := _effect_category_for_path(path, ext)
	var key := path.trim_prefix("res://")
	var display_path := scene_path if not scene_path.is_empty() else path
	return {
		"key": key,
		"category": category,
		"scene": scene_path,
		"preview": path if ["png", "webp", "jpg", "jpeg"].has(ext) else "",
		"display_path": display_path,
	}


func _effect_category_for_path(path: String, ext: String) -> String:
	var lower := path.to_lower()
	if lower.contains("spine"):
		return "spine"
	if lower.contains("unity"):
		return "unity"
	if ["png", "webp", "jpg", "jpeg", "tres"].has(ext):
		return "sequence"
	return "godot"


func _find_effect_scene_for_visual(path: String) -> String:
	var dir_path := path.get_base_dir()
	var base_name := path.get_file().get_basename()
	for candidate in [
		dir_path.path_join(base_name + ".tscn"),
		dir_path.path_join(base_name + "_visual.tscn"),
		dir_path.path_join("effect.tscn"),
		dir_path.path_join("visual.tscn"),
		dir_path.path_join("fireball_visual.tscn"),
	]:
		if ResourceLoader.exists(candidate):
			return candidate
	return ""


func _filtered_effect_library_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _effect_library_items:
		if str(item.get("category", "godot")) == _effect_library_filter:
			result.append(item)
	return result


func _refresh_effect_library_view() -> void:
	if _effect_library_grid == null:
		return
	for child in _effect_library_grid.get_children():
		child.queue_free()
	for key in _effect_filter_buttons.keys():
		var button: Button = _effect_filter_buttons[key]
		if is_instance_valid(button):
			button.set_pressed_no_signal(str(key) == _effect_library_filter)
	var items := _filtered_effect_library_items()
	var total_pages := maxi(1, int(ceil(float(items.size()) / float(EFFECT_LIBRARY_PAGE_SIZE))))
	_effect_library_page = clampi(_effect_library_page, 0, total_pages - 1)
	if _effect_library_page_label != null:
		_effect_library_page_label.text = "当前分类 %d 项 · 第 %d / %d 页" % [items.size(), _effect_library_page + 1, total_pages]
	var start := _effect_library_page * EFFECT_LIBRARY_PAGE_SIZE
	var end := mini(items.size(), start + EFFECT_LIBRARY_PAGE_SIZE)
	for index in range(start, end):
		_effect_library_grid.add_child(_make_effect_card(items[index]))
	if _effect_library_status != null:
		_effect_library_status.text = "绑定会写入当前节点的 scene；纯图片需要同目录存在 .tscn 才能直接绑定。"


func _make_effect_card(item: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(240, 160)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = str(item.get("key", ""))
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var bind_button := Button.new()
	bind_button.text = "绑定"
	bind_button.disabled = str(item.get("scene", "")).is_empty()
	bind_button.pressed.connect(_bind_effect_library_item.bind(item))
	top.add_child(bind_button)
	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(220, 82)
	box.add_child(preview_box)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var preview_path := str(item.get("preview", ""))
	if not preview_path.is_empty() and ResourceLoader.exists(preview_path):
		preview.texture = load(preview_path)
	preview_box.add_child(preview)
	var path_label := Label.new()
	path_label.text = str(item.get("display_path", ""))
	path_label.clip_text = true
	box.add_child(path_label)
	return card


func _bind_effect_library_item(item: Dictionary) -> void:
	var scene_path := str(item.get("scene", ""))
	if scene_path.is_empty():
		_status.text = "该资源还没有可绑定的 .tscn 场景。"
		return
	var index := _selected_node_index()
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index < 0:
		var node := {"type": "play_effect", "scene": scene_path}
		nodes.append(node)
		index = nodes.size() - 1
	else:
		if index >= nodes.size() or not nodes[index] is Dictionary:
			return
		var node: Dictionary = nodes[index]
		node["type"] = "play_effect"
		node["scene"] = scene_path
		nodes[index] = node
	skill["nodes"] = nodes
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()
	_node_list.select(index)
	_on_node_selected(index)
	_status.text = "已绑定特效：%s" % scene_path


func _add_skill_line_edit(parent: Container, label_text: String, field_name: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(_on_skill_text_changed.bind(field_name))
	parent.add_child(edit)
	return edit


func _add_skill_spin(parent: Container, label_text: String, field_name: String, default_value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = default_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_skill_number_changed.bind(field_name))
	parent.add_child(spin)
	return spin


func _make_node_control_row(label: Label, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size.x = 130
	row.add_child(label)
	row.add_child(control)
	return row


func _build_node_extra_controls(parent: VBoxContainer) -> void:
	_node_effect_section = VBoxContainer.new()
	parent.add_child(_node_effect_section)
	_node_effect_scene_edit = _add_node_extra_line(_node_effect_section, "特效场景", "scene")
	_node_effect_scope_select = _add_node_extra_option(_node_effect_section, "生成目标", "target_scope", ["判定框/Socket", "本次命中目标"] , ["effect_origin", "last_hit_targets"])
	_node_effect_offset_x = _add_node_extra_spin(_node_effect_section, "特效偏移 X", "offset_x", 0.0, -9999.0, 9999.0, 1.0)
	_node_effect_offset_y = _add_node_extra_spin(_node_effect_section, "特效偏移 Y", "offset_y", 0.0, -9999.0, 9999.0, 1.0)

	_node_rain_section = VBoxContainer.new()
	parent.add_child(_node_rain_section)
	_node_rain_mode_select = _add_node_extra_option(_node_rain_section, "弹道模式", "projectile_mode", ["单发直线", "区域落雨"], ["single", "area_rain"])
	_node_rain_area_controls = []
	_node_rain_count = _add_node_extra_spin(_node_rain_section, "弹道数量", "projectile_count", 12.0, 1.0, 999.0, 1.0)
	_node_rain_area_controls.append(_node_rain_count.get_parent() as Control)
	_node_rain_interval = _add_node_extra_spin(_node_rain_section, "发射间隔", "projectile_interval", 0.05, 0.0, 10.0, 0.01)
	_node_rain_area_controls.append(_node_rain_interval.get_parent() as Control)
	_node_rain_search_range = _add_node_extra_spin(_node_rain_section, "索敌范围", "target_search_range", 500.0, 1.0, 9999.0, 1.0)
	_node_rain_area_controls.append(_node_rain_search_range.get_parent() as Control)
	_node_rain_width = _add_node_extra_spin(_node_rain_section, "区域宽度", "area_width", 240.0, 1.0, 9999.0, 1.0)
	_node_rain_area_controls.append(_node_rain_width.get_parent() as Control)
	_node_rain_height = _add_node_extra_spin(_node_rain_section, "区域高度", "area_height", 80.0, 1.0, 9999.0, 1.0)
	_node_rain_area_controls.append(_node_rain_height.get_parent() as Control)
	_node_rain_flight_time = _add_node_extra_spin(_node_rain_section, "飞行时间", "flight_time", 0.9, 0.1, 10.0, 0.05)
	_node_rain_area_controls.append(_node_rain_flight_time.get_parent() as Control)
	_node_rain_gravity = _add_node_extra_spin(_node_rain_section, "重力", "gravity", 900.0, 0.0, 9999.0, 10.0)
	_node_rain_area_controls.append(_node_rain_gravity.get_parent() as Control)
	_node_rain_socket_edit = _add_node_extra_line(_node_rain_section, "发射 Socket", "socket")


func _add_node_extra_line(parent: Container, label_text: String, field_name: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size.x = 420
	edit.text_changed.connect(_on_node_extra_text_changed.bind(field_name))
	parent.add_child(_make_node_control_row(_make_node_label(label_text), edit))
	return edit


func _add_node_extra_spin(parent: Container, label_text: String, field_name: String, default_value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.custom_minimum_size.x = 180
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = default_value
	spin.value_changed.connect(_on_node_extra_number_changed.bind(field_name))
	parent.add_child(_make_node_control_row(_make_node_label(label_text), spin))
	return spin


func _add_node_extra_option(parent: Container, label_text: String, field_name: String, labels: Array, values: Array) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.x = 240
	for index in range(labels.size()):
		option.add_item(str(labels[index]))
		option.set_item_metadata(index, values[index])
	option.item_selected.connect(_on_node_extra_option_selected.bind(field_name))
	parent.add_child(_make_node_control_row(_make_node_label(label_text), option))
	return option


func _make_node_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label


func _build_skill_parameter_tabs(root: VBoxContainer) -> TabContainer:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 170
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var base := GridContainer.new()
	base.name = "基础"
	base.columns = 2
	base.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(base)
	_skill_name_edit = _add_skill_line_edit(base, "技能名称", "name")
	_skill_description_edit = _add_skill_line_edit(base, "技能描述", "description")
	_skill_animation_edit = _add_skill_line_edit(base, "默认动作", "animation")

	var numbers := GridContainer.new()
	numbers.name = "数值"
	numbers.columns = 2
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(numbers)
	_skill_damage_spin = _add_skill_spin(numbers, "伤害倍率", "damage_ratio", 1.0, -99.0, 99.0, 0.1)
	_skill_cooldown_spin = _add_skill_spin(numbers, "冷却时间", "cooldown", 0.0, 0.0, 999.0, 0.1)
	_skill_range_spin = _add_skill_spin(numbers, "技能射程", "range", 0.0, 0.0, 9999.0, 1.0)
	_skill_aoe_radius_spin = _add_skill_spin(numbers, "范围半径", "aoe_radius", 0.0, 0.0, 9999.0, 1.0)

	var projectile := GridContainer.new()
	projectile.name = "弹道"
	projectile.columns = 2
	projectile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(projectile)
	_projectile_scene_edit = _add_skill_line_edit(projectile, "弹道场景", "projectile_scene")
	_projectile_speed_spin = _add_skill_spin(projectile, "弹道速度", "projectile_speed", 300.0, 0.0, 9999.0, 1.0)
	_projectile_lifetime_spin = _add_skill_spin(projectile, "弹道生命周期", "projectile_lifetime", 5.0, 0.0, 999.0, 0.1)
	_projectile_spawn_offset_spin = _add_skill_spin(projectile, "弹道出生偏移", "projectile_spawn_offset", 32.0, 0.0, 9999.0, 1.0)
	_max_pierce_spin = _add_skill_spin(projectile, "最大穿透数", "max_pierce", 0.0, -1.0, 9999.0, 1.0)

	var buffs := GridContainer.new()
	buffs.name = "Buff"
	buffs.columns = 2
	buffs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(buffs)
	_buff_on_hit_spin = _add_skill_spin(buffs, "命中 Buff ID", "buff_on_hit", 0.0, 0.0, 999999.0, 1.0)
	_buff_chance_spin = _add_skill_spin(buffs, "命中 Buff 概率", "buff_chance", 0.0, 0.0, 1.0, 0.05)
	_buff_on_self_spin = _add_skill_spin(buffs, "自身 Buff ID", "buff_on_self", 0.0, 0.0, 999999.0, 1.0)
	return tabs


func _load_skills() -> void:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.READ)
	if file == null:
		_status.text = "无法读取 %s" % SKILLS_PATH
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK or not json.data is Dictionary:
		_status.text = "skills.json 解析失败"
		return
	_skills = json.data


func _rebuild_skill_select() -> void:
	if _skill_select == null or _action_select == null or _skill_name_edit == null:
		return
	_skill_select.clear()
	var ids: Array = _skills.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for id_value in ids:
		var id := int(id_value)
		var skill: Dictionary = _skills[id_value]
		_skill_select.add_item("%d %s" % [id, String(skill.get("name", ""))], id)
	if _skill_select.item_count > 0:
		_skill_select.select(0)
		_on_skill_selected(0)


func _on_skill_selected(index: int) -> void:
	if _skill_select == null or _action_select == null:
		return
	_current_skill_id = _skill_select.get_item_id(index)
	_rebuild_node_list()
	var skill := _get_current_skill()
	_load_skill_fields(skill)
	_select_option_by_metadata(_skill_type_select, String(skill.get("type", "melee")))
	var anim := String(skill.get("animation", "attack"))
	_select_option_by_text(_action_select, anim)
	_rebuild_event_select(anim)
	_set_default_hit_window_mode(String(skill.get("type", "melee")))
	_refresh_trigger_options()
	_select_option_by_metadata(_trigger_select, "immediate")
	_update_trigger_controls_visibility()
	_refresh_event_notice(anim)
	_refresh_timeline()


func _on_skill_type_selected(index: int) -> void:
	if _skill_type_select == null or _current_skill_id <= 0 or index < 0:
		return
	var skill_type := str(_skill_type_select.get_item_metadata(index))
	if skill_type.is_empty():
		return
	var skill := _get_current_skill()
	skill["type"] = skill_type
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()
	_refresh_timeline()
	_status.text = "已更新技能类型：%s（点击保存 skills.json 后写入）" % SKILL_TYPE_LABELS.get(skill_type, skill_type)


func _load_skill_fields(skill: Dictionary) -> void:
	_loading_skill_fields = true
	if _skill_name_edit != null:
		_skill_name_edit.text = str(skill.get("name", ""))
	if _skill_description_edit != null:
		_skill_description_edit.text = str(skill.get("description", ""))
	if _skill_animation_edit != null:
		_skill_animation_edit.text = str(skill.get("animation", "attack"))
	if _skill_damage_spin != null:
		_skill_damage_spin.value = float(skill.get("damage_ratio", 1.0))
	if _skill_cooldown_spin != null:
		_skill_cooldown_spin.value = float(skill.get("cooldown", 0.0))
	if _skill_range_spin != null:
		_skill_range_spin.value = float(skill.get("range", 0.0))
	if _skill_aoe_radius_spin != null:
		_skill_aoe_radius_spin.value = float(skill.get("aoe_radius", 0.0))
	if _projectile_scene_edit != null:
		_projectile_scene_edit.text = str(skill.get("projectile_scene", ""))
	if _node_projectile_scene_edit != null:
		_node_projectile_scene_edit.text = str(skill.get("projectile_scene", ""))
	if _projectile_speed_spin != null:
		_projectile_speed_spin.value = float(skill.get("projectile_speed", 300.0))
	if _projectile_lifetime_spin != null:
		_projectile_lifetime_spin.value = float(skill.get("projectile_lifetime", 5.0))
	if _projectile_spawn_offset_spin != null:
		_projectile_spawn_offset_spin.value = float(skill.get("projectile_spawn_offset", 32.0))
	if _max_pierce_spin != null:
		_max_pierce_spin.value = float(skill.get("max_pierce", 0))
	if _buff_on_hit_spin != null:
		_buff_on_hit_spin.value = float(skill.get("buff_on_hit", 0))
	if _buff_chance_spin != null:
		_buff_chance_spin.value = float(skill.get("buff_chance", 0.0))
	if _buff_on_self_spin != null:
		_buff_on_self_spin.value = float(skill.get("buff_on_self", 0))
	_loading_skill_fields = false


func _on_skill_text_changed(value: String, field_name: String) -> void:
	if _loading_skill_fields or _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	skill[field_name] = value
	_skills[str(_current_skill_id)] = skill
	if field_name == "projectile_scene" and _node_projectile_scene_edit != null:
		_node_projectile_scene_edit.text = value
	if field_name == "animation":
		_rebuild_action_select()
		_select_option_by_text(_action_select, value)
		_rebuild_event_select(value)
		_refresh_trigger_options()
		_refresh_event_notice(value)
		_refresh_timeline()


func _on_skill_number_changed(value: float, field_name: String) -> void:
	if _loading_skill_fields or _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	if field_name == "max_pierce" or field_name.ends_with("_id"):
		skill[field_name] = int(value)
	else:
		skill[field_name] = value
	_skills[str(_current_skill_id)] = skill


func _get_current_skill() -> Dictionary:
	return _skills.get(str(_current_skill_id), {})


func _rebuild_node_list() -> void:
	_node_list.clear()
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	for index in range(nodes.size()):
		var node: Dictionary = nodes[index]
		var type_name := String(node.get("type", ""))
		_node_list.add_item("%02d  [%s] %s  %s" % [index + 1, _node_category(type_name), _node_type_label_for_node(node), _summarize_node(node)])
	_update_reorder_buttons()
	_refresh_timeline()


func _on_node_selected(index: int) -> void:
	_update_reorder_buttons()
	_load_selected_node_controls(index)
	_load_selected_node_trigger(index)
	_timeline.set_selected_node(index)


func _load_selected_node_controls(index: int) -> void:
	if _node_list == null or _node_type == null:
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index < 0 or index >= nodes.size() or not nodes[index] is Dictionary:
		return
	var node: Dictionary = nodes[index]
	var type_name := String(node.get("type", ""))
	_select_option_by_metadata(_node_type, type_name)
	_update_hit_window_mode_visibility()
	var action_name := String(node.get("action", skill.get("animation", "attack")))
	_select_option_by_text(_action_select, action_name)
	if type_name == "use_action_hit_window":
		var mode := "effect"
		if bool(node.get("detects_hits", false)):
			mode = "damage"
		elif String(skill.get("type", "")) == "projectile" or String(skill.get("type", "")) == "penetrate":
			mode = "projectile"
		_select_option_by_metadata(_hit_window_mode, mode)
		_update_hit_window_mode_visibility()
	if type_name == "wait_action_event":
		_select_option_by_metadata(_event_select, String(node.get("event", "release")))
	if _node_projectile_scene_edit != null:
		_node_projectile_scene_edit.text = str(skill.get("projectile_scene", ""))
	_update_hit_window_mode_visibility()
	_load_node_extra_controls(node)


func _on_node_type_selected(_index: int) -> void:
	_update_hit_window_mode_visibility()
	if _node_extra_controls != null:
		_refresh_node_extra_visibility()


func _on_hit_window_mode_selected(_index: int) -> void:
	_update_hit_window_mode_visibility()


func _on_node_projectile_scene_changed(value: String) -> void:
	if _loading_skill_fields or _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	skill["projectile_scene"] = value
	_skills[str(_current_skill_id)] = skill
	if _projectile_scene_edit != null:
		_projectile_scene_edit.text = value


func _open_projectile_config() -> void:
	if _skill_tabs == null:
		return
	for index in range(_skill_tabs.get_tab_count()):
		if _skill_tabs.get_tab_title(index) == "弹道":
			_skill_tabs.current_tab = index
			return


func _update_hit_window_mode_visibility() -> void:
	if _hit_window_mode == null or _node_type == null:
		return
	var type_name := String(_node_type.get_item_metadata(_node_type.selected))
	_hit_window_mode.visible = type_name == "use_action_hit_window"
	if _hit_window_label != null:
		_hit_window_label.visible = _hit_window_mode.visible
	var is_projectile := type_name == "spawn_projectile" or (_hit_window_mode.visible and String(_hit_window_mode.get_item_metadata(_hit_window_mode.selected)) == "projectile")
	if _node_projectile_scene_edit != null:
		_node_projectile_scene_edit.visible = is_projectile
	if _projectile_config_button != null:
		_projectile_config_button.visible = is_projectile
	if _node_extra_controls != null:
		_refresh_node_extra_visibility()


func _refresh_node_extra_visibility() -> void:
	if _node_type == null or _node_effect_section == null or _node_rain_section == null:
		return
	var type_name := String(_node_type.get_item_metadata(_node_type.selected))
	_node_effect_section.visible = type_name == "play_effect"
	_node_rain_section.visible = type_name == "spawn_projectile"
	var rain_mode := String(_node_rain_mode_select.get_item_metadata(_node_rain_mode_select.selected)) if _node_rain_mode_select.item_count > 0 else "single"
	for control in _node_rain_area_controls:
		if is_instance_valid(control):
			control.visible = rain_mode == "area_rain"


func _load_node_extra_controls(node: Dictionary) -> void:
	if _node_effect_scene_edit == null:
		return
	_loading_skill_fields = true
	_node_effect_scene_edit.text = str(node.get("scene", node.get("effect_scene", "")))
	_select_option_by_metadata(_node_effect_scope_select, String(node.get("target_scope", "effect_origin")))
	_node_effect_offset_x.value = float(node.get("offset_x", 0.0))
	_node_effect_offset_y.value = float(node.get("offset_y", 0.0))
	_select_option_by_metadata(_node_rain_mode_select, String(node.get("projectile_mode", "single")))
	_node_rain_count.value = float(node.get("projectile_count", 12.0))
	_node_rain_interval.value = float(node.get("projectile_interval", 0.05))
	_node_rain_search_range.value = float(node.get("target_search_range", 500.0))
	_node_rain_width.value = float(node.get("area_width", 240.0))
	_node_rain_height.value = float(node.get("area_height", 80.0))
	_node_rain_flight_time.value = float(node.get("flight_time", 0.9))
	_node_rain_gravity.value = float(node.get("gravity", 900.0))
	_node_rain_socket_edit.text = str(node.get("socket", ""))
	_loading_skill_fields = false
	_refresh_node_extra_visibility()


func _update_selected_node_field(field_name: String, value: Variant) -> void:
	if _loading_skill_fields or _current_skill_id <= 0:
		return
	var index := _selected_node_index()
	if index < 0:
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index >= nodes.size() or not nodes[index] is Dictionary:
		return
	var node: Dictionary = nodes[index]
	if value is String and str(value).is_empty():
		node.erase(field_name)
	else:
		node[field_name] = value
	nodes[index] = node
	skill["nodes"] = nodes
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()
	_node_list.select(index)


func _on_node_extra_text_changed(value: String, field_name: String) -> void:
	_update_selected_node_field(field_name, value)


func _on_node_extra_number_changed(value: float, field_name: String) -> void:
	_update_selected_node_field(field_name, value)


func _on_node_extra_option_selected(index: int, field_name: String) -> void:
	var option: OptionButton = _node_rain_mode_select if field_name == "projectile_mode" else _node_effect_scope_select
	if option == null or index < 0 or index >= option.item_count:
		return
	_update_selected_node_field(field_name, option.get_item_metadata(index))
	_refresh_node_extra_visibility()


func _on_frame_slider_changed(value: float) -> void:
	if _timeline != null:
		_timeline.set_current_frame(int(value))


func _on_timeline_frame_selected(frame: int) -> void:
	if _frame_slider != null:
		_frame_slider.set_value_no_signal(frame)


func _on_timeline_node_selected(index: int) -> void:
	if _node_list == null or index < 0 or index >= _node_list.item_count:
		return
	_node_list.select(index)
	_on_node_selected(index)


func _refresh_timeline() -> void:
	if _timeline == null or _action_select == null:
		return
	var action_name := _action_select.get_item_text(_action_select.selected) if _action_select.item_count > 0 else String(_get_current_skill().get("animation", "attack"))
	var action := _get_action_data(action_name)
	var frame_count := _get_action_frame_count(action)
	var current_frame := int(_frame_slider.value) if _frame_slider != null else 0
	if _frame_slider != null:
		_frame_slider.max_value = maxi(1, frame_count - 1)
		_frame_slider.value = clampi(current_frame, 0, frame_count - 1)
	_timeline.set_timeline(action, _get_current_skill().get("nodes", []), frame_count, current_frame, _selected_node_index(), String(_get_current_skill().get("type", "")))


func _get_action_data(action_name: String) -> Dictionary:
	var source_path := _get_action_source_path()
	if not source_path.is_empty():
		var source_data := _read_json(source_path)
		var source_actions: Dictionary = source_data.get("actions", {})
		if source_actions.has(action_name) and source_actions[action_name] is Dictionary:
			return source_actions[action_name]
	for path in _find_combat_action_files():
		var data := _read_json(path)
		var actions: Dictionary = data.get("actions", {})
		if actions.has(action_name) and actions[action_name] is Dictionary:
			return actions[action_name]
	return {}


func _get_action_source_path() -> String:
	if _current_skill_id <= 0:
		return ""
	for config_path in ["res://data/characters.json", "res://data/enemies.json"]:
		var data := _read_json(config_path)
		for value in data.values():
			if not value is Dictionary:
				continue
			var entry: Dictionary = value
			if not _config_contains_skill(entry, _current_skill_id):
				continue
			var asset_path := String(entry.get("asset", ""))
			var action_path := asset_path.path_join("combat_actions.json")
			if not asset_path.is_empty() and FileAccess.file_exists(action_path):
				return action_path
	return ""


func _config_contains_skill(config: Dictionary, skill_id: int) -> bool:
	if int(config.get("normal_skill", 0)) == skill_id:
		return true
	for value in config.get("skills", []):
		if int(value) == skill_id:
			return true
	var unlocks: Dictionary = config.get("skill_unlocks", {})
	for value in unlocks.values():
		if value is Dictionary and int((value as Dictionary).get("skill_id", 0)) == skill_id:
			return true
	return false


func _get_action_frame_count(action: Dictionary) -> int:
	var max_frame := 7
	for value in action.get("events", []):
		if value is Dictionary:
			max_frame = maxi(max_frame, int(value.get("frame", 0)) + 2)
	for value in action.get("hit_windows", []):
		if value is Dictionary:
			max_frame = maxi(max_frame, int(value.get("end_frame", 0)) + 2)
	return max_frame + 1


func _selected_node_index() -> int:
	if _node_list == null:
		return -1
	var selected := _node_list.get_selected_items()
	return int(selected[0]) if not selected.is_empty() else -1


func _set_default_hit_window_mode(skill_type: String) -> void:
	if _hit_window_mode == null:
		return
	var mode := "effect"
	if skill_type == "melee":
		mode = "damage"
	elif skill_type == "projectile" or skill_type == "penetrate":
		mode = "projectile"
	_select_option_by_metadata(_hit_window_mode, mode)
	_update_hit_window_mode_visibility()


func _update_reorder_buttons() -> void:
	if _move_up_button == null or _move_down_button == null or _node_list == null:
		return
	var selected := _node_list.get_selected_items()
	if selected.is_empty():
		_move_up_button.disabled = true
		_move_down_button.disabled = true
		return
	var index := int(selected[0])
	var count := _node_list.item_count
	_move_up_button.disabled = index <= 0
	_move_down_button.disabled = index >= count - 1


func _summarize_node(node: Dictionary) -> String:
	match String(node.get("type", "")):
		"play_animation", "use_action_hit_window":
			return String(node.get("action", ""))
		"wait_action_event":
			return _event_label(String(node.get("event", "")))
		"heal":
			return str(int(node.get("amount", 0)))
		"move_x":
			return str(float(node.get("delta_x", node.get("distance", 0.0))))
		_:
			return ""


func _node_type_label_for_node(node: Dictionary) -> String:
	var type_name := String(node.get("type", ""))
	if type_name != "use_action_hit_window":
		return _node_type_label(type_name)
	if bool(node.get("detects_hits", false)):
		return "近战伤害（判定框）"
	var skill_type := String(_get_current_skill().get("type", ""))
	if skill_type == "projectile" or skill_type == "penetrate":
		return "弹道发射（判定框中心）"
	return "技能生效帧（判定框）"


func _add_node() -> void:
	if _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	var type_name := String(_node_type.get_item_metadata(_node_type.selected))
	var action_name := _action_select.get_item_text(_action_select.selected) if _action_select.item_count > 0 else String(skill.get("animation", "attack"))
	var event_name := str(_event_select.get_item_metadata(_event_select.selected)) if _event_select.item_count > 0 else "release"
	var node := {"type": type_name}
	match type_name:
		"play_animation", "use_action_hit_window":
			node["action"] = action_name
			if type_name == "use_action_hit_window":
				# 近战技能必须开启命中检测，避免界面残留选择生成无伤普攻。
				node["detects_hits"] = String(skill.get("type", "melee")) == "melee" or String(_hit_window_mode.get_item_metadata(_hit_window_mode.selected)) == "damage"
		"wait_action_event":
			node["event"] = event_name
		"heal":
			node["amount"] = 10
		"move_x":
			node["delta_x"] = 32.0
	nodes.append(node)
	skill["nodes"] = nodes
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()


func _delete_selected_node() -> void:
	var selected := _node_list.get_selected_items()
	if selected.is_empty():
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	var index := int(selected[0])
	if index >= 0 and index < nodes.size():
		nodes.remove_at(index)
		skill["nodes"] = nodes
		_skills[str(_current_skill_id)] = skill
		_rebuild_node_list()


func _move_selected_node_up() -> void:
	_move_selected_node(-1)


func _move_selected_node_down() -> void:
	_move_selected_node(1)


func _move_selected_node(delta: int) -> void:
	if _current_skill_id <= 0:
		return
	var selected := _node_list.get_selected_items()
	if selected.is_empty():
		return
	var current_index := int(selected[0])
	var target_index := current_index + delta
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	if current_index < 0 or current_index >= nodes.size():
		return
	if target_index < 0 or target_index >= nodes.size():
		return

	var moved_node = nodes[current_index]
	nodes[current_index] = nodes[target_index]
	nodes[target_index] = moved_node
	skill["nodes"] = nodes
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()
	_node_list.select(target_index)
	_node_list.ensure_current_is_visible()
	_on_node_selected(target_index)
	_update_reorder_buttons()


func _apply_melee_template() -> void:
	var action := _selected_action_name()
	_apply_template("melee", [
		{"type": "play_animation", "action": action},
		{"type": "use_action_hit_window", "action": action, "detects_hits": true, "trigger": "hit_window", "hit_window_index": 0},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用普攻模板：有效帧判定攻击伤害。")


func _apply_projectile_template() -> void:
	var action := _selected_action_name()
	_apply_template("projectile", [
		{"type": "play_animation", "action": action},
		{"type": "use_action_hit_window", "action": action, "detects_hits": false, "trigger": "hit_window", "hit_window_index": 0},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用弹道模板：有效帧从判定框中心发射，弹道参数仍使用技能配置。")


func _apply_self_buff_template() -> void:
	var action := _selected_action_name()
	_apply_template("self", [
		{"type": "play_animation", "action": action},
		{"type": "use_action_hit_window", "action": action, "detects_hits": false, "trigger": "hit_window", "hit_window_index": 0},
		{"type": "wait_animation_end"},
		{"type": "end_skill"},
	], "已套用自身 Buff 模板：有效帧施加 buff_on_self。")


func _clear_custom_nodes() -> void:
	if _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	skill.erase("nodes")
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()
	_status.text = "已清空自定义节点，将使用技能类型的默认流程。"


func _selected_action_name() -> String:
	if _action_select != null and _action_select.item_count > 0 and _action_select.selected >= 0:
		return _action_select.get_item_text(_action_select.selected)
	return String(_get_current_skill().get("animation", "attack"))


func _apply_template(skill_type: String, nodes: Array, message: String) -> void:
	if _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	skill["type"] = skill_type
	if skill_type == "melee":
		for node_value in nodes:
			if node_value is Dictionary and String(node_value.get("type", "")) == "use_action_hit_window":
				node_value["detects_hits"] = true
	skill["nodes"] = nodes
	_skills[str(_current_skill_id)] = skill
	_select_option_by_metadata(_skill_type_select, skill_type)
	_rebuild_node_list()
	_status.text = message


func _save_skills() -> void:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "无法写入 %s" % SKILLS_PATH
		return
	file.store_string(JSON.stringify(_skills, "\t") + "\n")
	_status.text = "已保存 %s" % SKILLS_PATH


func _rebuild_action_select() -> void:
	if _action_select == null:
		return
	_action_select.clear()
	var names := _collect_action_names()
	for name in names:
		_action_select.add_item(name)
	if _action_select.item_count == 0:
		_action_select.add_item("attack")


func _on_action_selected(index: int) -> void:
	if index < 0:
		return
	var action_name := _action_select.get_item_text(index)
	_rebuild_event_select(action_name)
	_refresh_trigger_options()
	_refresh_event_notice(action_name)
	_refresh_timeline()


func _rebuild_event_select(action_name: String) -> void:
	if _event_select == null:
		return
	_event_select.clear()
	var names := _collect_event_names(action_name)
	if names.is_empty():
		_event_select.add_item("当前动作未配置事件")
		_event_select.set_item_disabled(0, true)
		return
	for name in names:
		_event_select.add_item(_event_label(name))
		_event_select.set_item_metadata(_event_select.item_count - 1, name)
	if _event_select.item_count > 0:
		_event_select.select(0)


func _refresh_trigger_options() -> void:
	if _action_select == null or _trigger_event_select == null or _trigger_window_select == null:
		return
	var action_name := _action_select.get_item_text(_action_select.selected) if _action_select.item_count > 0 else ""
	_trigger_event_select.clear()
	var names := _collect_event_names(action_name)
	if names.is_empty():
		_trigger_event_select.add_item("当前动作未配置事件")
		_trigger_event_select.set_item_disabled(0, true)
	else:
		for name in names:
			_trigger_event_select.add_item(_event_label(name))
			_trigger_event_select.set_item_metadata(_trigger_event_select.item_count - 1, name)
	_trigger_window_select.clear()
	var action := _get_action_data(action_name)
	var windows: Array = action.get("hit_windows", [])
	for index in range(windows.size()):
		_trigger_window_select.add_item("第 %d 个有效区间" % (index + 1))
		_trigger_window_select.set_item_metadata(_trigger_window_select.item_count - 1, index)
	if _trigger_event_select.item_count > 0:
		_trigger_event_select.select(0)
	if _trigger_window_select.item_count > 0:
		_trigger_window_select.select(0)
	_update_trigger_controls_visibility()
func _refresh_event_notice(action_name: String) -> void:
	if _event_notice == null:
		return
	var configured := _collect_event_names(action_name)
	var source_path := _get_action_source_path()
	var missing: Array = []
	for event_name in DEFAULT_EVENT_NAMES:
		if not configured.has(event_name):
			missing.append(_event_label(event_name))
	if missing.is_empty():
		if source_path.is_empty():
			_event_notice.text = "动作数据源：未找到对应资源的 combat_actions.json"
		else:
			_event_notice.text = "动作数据源：%s" % source_path
	else:
		_event_notice.text = "提示：当前动作未配置 %s 事件。事件下拉只显示外部 JSON 已导出的事件，请在外部工具或 combat_actions.json 中补充。\n数据源：%s" % ["、".join(missing), source_path if not source_path.is_empty() else "未找到对应资源"]


func _load_selected_node_trigger(index: int) -> void:
	if _trigger_select == null or _node_list == null:
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index < 0 or index >= nodes.size() or not nodes[index] is Dictionary:
		return
	_refresh_trigger_options()
	var node: Dictionary = nodes[index]
	var trigger := String(node.get("trigger", "immediate"))
	_select_option_by_metadata(_trigger_select, trigger)
	if trigger == "event":
		_select_option_by_metadata(_trigger_event_select, String(node.get("event", "release")))
	elif trigger == "hit_window":
		_select_option_by_metadata(_trigger_window_select, int(node.get("hit_window_index", 0)))
	_update_trigger_controls_visibility()


func _on_trigger_mode_selected(_index: int) -> void:
	_update_trigger_controls_visibility()


func _update_trigger_controls_visibility() -> void:
	if _trigger_select == null:
		return
	var trigger := String(_trigger_select.get_item_metadata(_trigger_select.selected))
	_trigger_event_select.visible = trigger == "event"
	_trigger_window_select.visible = trigger == "hit_window"
	var parent := _trigger_select.get_parent()
	(parent.get_child(2) as Control).visible = _trigger_event_select.visible
	(parent.get_child(4) as Control).visible = _trigger_window_select.visible


func _apply_selected_node_trigger() -> void:
	if _current_skill_id <= 0 or _trigger_select == null:
		return
	var index := _selected_node_index()
	if index < 0:
		_status.text = "请先选择一个技能节点。"
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	if index >= nodes.size() or not nodes[index] is Dictionary:
		return
	var node: Dictionary = nodes[index]
	var trigger := String(_trigger_select.get_item_metadata(_trigger_select.selected))
	if trigger == "immediate":
		node.erase("trigger")
		node.erase("event")
		node.erase("hit_window_index")
	elif trigger == "event":
		if _trigger_event_select.item_count == 0:
			_status.text = "当前动作没有可用的动画事件。"
			return
		var event_name := String(_trigger_event_select.get_item_metadata(_trigger_event_select.selected))
		if event_name.is_empty():
			_status.text = "当前动作没有可用的动画事件。"
			return
		node["trigger"] = "event"
		node["event"] = event_name
		node.erase("hit_window_index")
	elif trigger == "hit_window":
		if _trigger_window_select.item_count == 0:
			_status.text = "当前动作没有攻击有效区间，请先在攻击判定工具中添加。"
			return
		node["trigger"] = "hit_window"
		node["hit_window_index"] = int(_trigger_window_select.get_item_metadata(_trigger_window_select.selected))
		node.erase("event")
	else:
		node["trigger"] = "animation_end"
		node.erase("event")
		node.erase("hit_window_index")
	nodes[index] = node
	skill["nodes"] = nodes
	_skills[str(_current_skill_id)] = skill
	_rebuild_node_list()
	_node_list.select(index)
	_on_node_selected(index)
	_load_selected_node_trigger(index)
	_timeline.set_selected_node(index)
	_status.text = "已应用节点触发时机，保存后写入 skills.json。"


func _node_category(type_name: String) -> String:
	return ACTION_NODE_LABEL if ACTION_NODE_TYPES.has(type_name) else CONTROL_NODE_LABEL


func _node_type_label(type_name: String) -> String:
	return String(NODE_TYPE_LABELS.get(type_name, type_name))


func _event_label(event_name: String) -> String:
	return String(EVENT_LABELS.get(event_name, event_name))


func _collect_action_names() -> Array:
	var result: Array = []
	for path in _find_combat_action_files():
		var data := _read_json(path)
		var actions: Dictionary = data.get("actions", {})
		for name in actions.keys():
			if not result.has(String(name)):
				result.append(String(name))
	result.sort()
	return result


func _collect_event_names(action_name: String) -> Array:
	var result: Array = []
	var action := _get_action_data(action_name)
	for value in action.get("events", []):
		if value is Dictionary:
			var name := String((value as Dictionary).get("name", ""))
			if not name.is_empty() and not result.has(name):
				result.append(name)
	result.sort()
	return result


func _find_combat_action_files() -> Array:
	var result: Array = []
	_scan_for_combat_actions("res://assets", result)
	return result


func _scan_for_combat_actions(path: String, result: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			_scan_for_combat_actions(child, result)
		elif name == "combat_actions.json":
			result.append(child)
		name = dir.get_next()
	dir.list_dir_end()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {}
	return json.data


func _select_option_by_text(option: OptionButton, text: String) -> void:
	for index in range(option.item_count):
		if option.get_item_text(index) == text:
			option.select(index)
			return


func _select_option_by_metadata(option: OptionButton, value: Variant) -> void:
	for index in range(option.item_count):
		# 外部 JSON 或占位选项可能没有 metadata，使用 str() 可安全处理 null。
		if str(option.get_item_metadata(index)) == str(value):
			option.select(index)
			return
