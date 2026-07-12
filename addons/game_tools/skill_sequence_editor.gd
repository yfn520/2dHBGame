@tool
extends Window

const SKILLS_PATH := "res://data/skills.json"
const SkillTimeline = preload("res://addons/game_tools/skill_timeline.gd")

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

var _skills: Dictionary = {}
var _current_skill_id := ""
var _action_data: Dictionary = {}
var _loading := false

var _skill_select: OptionButton
var _name_edit: LineEdit
var _description_edit: LineEdit
var _cooldown_spin: SpinBox
var _range_spin: SpinBox
var _node_list: ItemList
var _action_picker: OptionButton
var _control_picker: OptionButton
var _node_details: VBoxContainer
var _timeline: SkillTimeline
var _frame_slider: HSlider
var _status: Label


func _init() -> void:
	title = "技能节点配置"
	size = Vector2i(1040, 760)
	min_size = Vector2i(820, 620)
	close_requested.connect(hide)


func _ready() -> void:
	_build_ui()
	_load_skills()
	_rebuild_skill_select()


func open_editor() -> void:
	if _skill_select == null:
		_build_ui()
	_load_skills()
	_rebuild_skill_select()
	popup_centered(size)


func _build_ui() -> void:
	if _skill_select != null:
		return
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var label := Label.new()
	label.text = "技能"
	header.add_child(label)
	_skill_select = OptionButton.new()
	_skill_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_select.item_selected.connect(_on_skill_selected)
	header.add_child(_skill_select)
	var save := Button.new()
	save.text = "保存 skills.json"
	save.pressed.connect(_save_skills)
	header.add_child(save)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	var base_page := GridContainer.new()
	base_page.name = "基础"
	base_page.columns = 2
	base_page.add_theme_constant_override("h_separation", 12)
	base_page.add_theme_constant_override("v_separation", 8)
	tabs.add_child(base_page)
	_name_edit = _add_line(base_page, "技能名称", "name")
	_description_edit = _add_line(base_page, "技能描述", "description")
	_cooldown_spin = _add_spin(base_page, "冷却时间", "cooldown", 0.0, 0.0, 999.0, 0.1)
	_range_spin = _add_spin(base_page, "AI 施放距离", "cast_range", 0.0, 0.0, 9999.0, 1.0)
	var help := Label.new()
	help.text = "技能本体只配置基础信息。伤害、弹道、范围、Buff 和特效全部在节点中配置。AI 施放距离为 0 时使用角色或怪物的默认攻击距离。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_page.add_child(help)
	var filler := Control.new()
	base_page.add_child(filler)

	var sequence_page := VBoxContainer.new()
	sequence_page.name = "编排"
	sequence_page.add_theme_constant_override("separation", 8)
	tabs.add_child(sequence_page)
	_node_list = ItemList.new()
	_node_list.custom_minimum_size.y = 190
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
	detail_scroll.custom_minimum_size.y = 250
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sequence_page.add_child(detail_scroll)
	_node_details = VBoxContainer.new()
	_node_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_node_details)
	var presets := GridContainer.new()
	presets.columns = 4
	sequence_page.add_child(presets)
	_add_button(presets, "套用普攻", _apply_melee_template)
	_add_button(presets, "套用单发弹道", _apply_projectile_template)
	_add_button(presets, "套用范围伤害", _apply_area_template)
	_add_button(presets, "套用全场伤害", _apply_fullscreen_template)
	_add_button(presets, "套用自身 Buff", _apply_self_buff_template)
	_add_button(presets, "套用三连弹道", _apply_sequence_template)
	_add_button(presets, "套用向上箭雨", _apply_rain_template)
	_add_button(presets, "清空节点", _clear_nodes)

	var timeline_page := VBoxContainer.new()
	timeline_page.name = "时间轴"
	timeline_page.add_theme_constant_override("separation", 8)
	tabs.add_child(timeline_page)
	var frame_row := HBoxContainer.new()
	timeline_page.add_child(frame_row)
	var frame_label := Label.new()
	frame_label.text = "当前帧"
	frame_row.add_child(frame_label)
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0
	_frame_slider.max_value = 7
	_frame_slider.step = 1
	_frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_slider.value_changed.connect(_on_frame_changed)
	frame_row.add_child(_frame_slider)
	_timeline = SkillTimeline.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.frame_selected.connect(_on_timeline_frame_selected)
	_timeline.node_selected.connect(_on_timeline_node_selected)
	timeline_page.add_child(_timeline)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _add_button(parent: Container, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)


func _make_type_picker(values: Dictionary) -> OptionButton:
	var picker := OptionButton.new()
	for type_name in values:
		picker.add_item(String(values[type_name]))
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


func _rebuild_skill_select() -> void:
	if _skill_select == null:
		return
	_skill_select.clear()
	var ids: Array = _skills.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for id_value in ids:
		var skill: Dictionary = _skills[id_value]
		_skill_select.add_item("%s  %s" % [id_value, String(skill.get("name", "未命名技能"))])
		_skill_select.set_item_metadata(_skill_select.item_count - 1, String(id_value))
	if _skill_select.item_count > 0:
		var index := 0
		for candidate in range(_skill_select.item_count):
			if String(_skill_select.get_item_metadata(candidate)) == _current_skill_id:
				index = candidate
		_skill_select.select(index)
		_on_skill_selected(index)


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
	_description_edit.text = String(skill.get("description", ""))
	_cooldown_spin.value = float(skill.get("cooldown", 0.0))
	_range_spin.value = float(skill.get("cast_range", 0.0))
	_loading = false


func _on_skill_text_changed(value: String, field: String) -> void:
	if _loading:
		return
	_update_skill(field, value)


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


func _rebuild_node_list() -> void:
	_node_list.clear()
	var nodes: Array = _current_skill().get("nodes", [])
	for index in range(nodes.size()):
		if not nodes[index] is Dictionary:
			continue
		var node: Dictionary = nodes[index]
		var type_name := String(node.get("type", ""))
		var category := "动作" if ACTION_TYPES.has(type_name) else "控制"
		_node_list.add_item("%02d  [%s] %s%s" % [index + 1, category, _node_label(type_name), _node_summary(node)])
	if _node_list.item_count > 0:
		_node_list.select(0)
		_show_node_details(0)
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
	if type_name == "wait_hit_window":
		return "  #%d" % (int(node.get("hit_window_index", 0)) + 1)
	if node.has("result_key"):
		return "  -> " + String(node.get("result_key", ""))
	return ""


func _on_node_selected(index: int) -> void:
	_show_node_details(index)
	_timeline.set_selected_node(index)


func _selected_node_index() -> int:
	var selected := _node_list.get_selected_items()
	return int(selected[0]) if not selected.is_empty() else -1


func _clear_node_details() -> void:
	for child in _node_details.get_children():
		child.queue_free()


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
		"wait_hit_window": _build_window_fields(form, node)
		"wait_time": _add_node_spin(form, "等待秒数", "seconds", node, 0.1, 0.0, 30.0, 0.05)
		"melee_damage": _build_damage_fields(form, node, false)
		"area_damage": _build_area_fields(form, node)
		"fullscreen_damage": _build_damage_fields(form, node, false)
		"spawn_projectile": _build_projectile_fields(form, node)
		"play_effect": _build_effect_fields(form, node)
		"apply_target_buff": _build_target_buff_fields(form, node)
		"apply_self_buff": _add_node_spin(form, "Buff ID", "buff_id", node, 0.0, 0.0, 999999.0, 1.0)
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


func _build_window_fields(form: GridContainer, node: Dictionary) -> void:
	var options: Array = []
	var windows: Array = _action_data.get("hit_windows", [])
	for index in range(windows.size()):
		options.append({"value": index, "label": "第 %d 个有效区间" % (index + 1)})
	if options.is_empty():
		options.append({"value": 0, "label": "当前动作未配置有效区间"})
	_add_node_option(form, "攻击有效区间", "hit_window_index", node, options, false)


func _build_damage_fields(form: GridContainer, node: Dictionary, include_origin: bool) -> void:
	_add_result_key(form, node)
	if include_origin:
		_add_origin_fields(form, node)
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_add_node_spin(form, "附加 Buff ID", "buff_id", node, 0.0, 0.0, 999999.0, 1.0)
	_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)


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
	_add_node_spin(form, "附加 Buff ID", "buff_id", node, 0.0, 0.0, 999999.0, 1.0)
	_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)


func _build_projectile_fields(form: GridContainer, node: Dictionary) -> void:
	_add_result_key(form, node)
	_add_node_line(form, "弹道场景", "scene", node)
	_add_origin_fields(form, node)
	_add_node_option(form, "轨迹", "trajectory", node, [{"value": "straight", "label": "直线"}, {"value": "ballistic", "label": "抛物线"}], true)
	_add_node_option(form, "瞄准/落点", "aim_mode", node, [{"value": "facing_elevation", "label": "朝向 + 仰角"}, {"value": "nearest_enemy", "label": "指向最近敌人"}, {"value": "enemy_area", "label": "敌人附近区域"}, {"value": "forward_area", "label": "施法者前方区域"}], true)
	_add_node_option(form, "发射方式", "emission", node, [{"value": "single", "label": "单发"}, {"value": "sequence", "label": "连续"}, {"value": "fan", "label": "扇形齐射"}, {"value": "area_rain", "label": "区域落雨"}], true)
	_add_node_spin(form, "最小施放距离", "min_range", node, 0.0, 0.0, 9999.0, 1.0)
	_add_node_spin(form, "速度", "speed", node, 300.0, 1.0, 9999.0, 1.0)
	_add_node_spin(form, "生命周期", "lifetime", node, 5.0, 0.1, 99.0, 0.1)
	_add_node_spin(form, "最大穿透数", "max_pierce", node, 0.0, -1.0, 99.0, 1.0)
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_add_node_spin(form, "附加 Buff ID", "buff_id", node, 0.0, 0.0, 999999.0, 1.0)
	_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)
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


func _build_effect_fields(form: GridContainer, node: Dictionary) -> void:
	_add_node_line(form, "特效场景", "scene", node)
	_add_node_option(form, "目标", "target", node, TARGET_OPTIONS, true)
	if String(node.get("target", "origin")) == "result":
		_add_node_line(form, "结果集", "result_key", node)
		_add_node_option(form, "触发频率", "delivery", node, [{"value": "each_hit", "label": "每次命中"}, {"value": "each_target", "label": "每个目标一次"}], false)
	else:
		_add_origin_fields(form, node)
	_add_node_spin(form, "偏移 X", "offset_x", node, 0.0, -9999.0, 9999.0, 1.0)
	_add_node_spin(form, "偏移 Y", "offset_y", node, 0.0, -9999.0, 9999.0, 1.0)


func _build_target_buff_fields(form: GridContainer, node: Dictionary) -> void:
	_add_node_option(form, "目标", "target", node, TARGET_OPTIONS, true)
	if String(node.get("target", "result")) == "result":
		_add_node_line(form, "结果集", "result_key", node)
		_add_node_option(form, "触发频率", "delivery", node, [{"value": "each_hit", "label": "每次命中"}, {"value": "each_target", "label": "每个目标一次"}], false)
	else:
		_add_origin_fields(form, node)
	_add_node_spin(form, "Buff ID", "buff_id", node, 0.0, 0.0, 999999.0, 1.0)
	_add_node_spin(form, "施加概率", "chance", node, 1.0, 0.0, 1.0, 0.05)


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


func _add_node_spin(form: GridContainer, label_text: String, field: String, node: Dictionary, default_value: float, minimum: float, maximum: float, step_value: float) -> void:
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


func _add_node_option(form: GridContainer, label_text: String, field: String, node: Dictionary, options: Array, rebuild: bool) -> void:
	var label := Label.new()
	label.text = label_text
	form.add_child(label)
	var option := OptionButton.new()
	for value in options:
		option.add_item(String(value.get("label", value.get("value", ""))))
		option.set_item_metadata(option.item_count - 1, value.get("value", ""))
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == str(node.get(field, option.get_item_metadata(0))):
			option.select(index)
	option.item_selected.connect(_on_node_option_selected.bind(field, rebuild, option))
	form.add_child(option)


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
	if rebuild:
		_show_node_details(index)
	_rebuild_node_list_keep(index)
	_refresh_timeline()


func _rebuild_node_list_keep(index: int) -> void:
	_rebuild_node_list()
	if index >= 0 and index < _node_list.item_count:
		_node_list.select(index)


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
	nodes.append(_default_node(type_name))
	skill["nodes"] = nodes
	_skills[_current_skill_id] = skill
	_rebuild_node_list_keep(nodes.size() - 1)
	_show_node_details(nodes.size() - 1)
	_refresh_timeline()


func _default_node(type_name: String) -> Dictionary:
	match type_name:
		"play_animation": return {"type": type_name, "action": _default_action()}
		"wait_action_event": return {"type": type_name, "event": "release"}
		"wait_hit_window": return {"type": type_name, "hit_window_index": 0}
		"melee_damage": return {"type": type_name, "result_key": "melee_hit", "damage_ratio": 1.0}
		"area_damage": return {"type": type_name, "result_key": "area_hit", "origin": "hit_window", "shape": "circle", "radius": 80.0, "damage_ratio": 1.0}
		"fullscreen_damage": return {"type": type_name, "result_key": "fullscreen_hit", "damage_ratio": 1.0}
		"spawn_projectile": return {"type": type_name, "result_key": "projectile_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.0}
		"play_effect": return {"type": type_name, "scene": "", "target": "origin"}
		"apply_target_buff": return {"type": type_name, "target": "result", "result_key": "last_result", "buff_id": 0, "chance": 1.0}
		"apply_self_buff": return {"type": type_name, "buff_id": 0}
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
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "projectile_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用单发弹道模板，请填写弹道场景。")


func _apply_area_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "area_damage", "result_key": "area_hit", "origin": "hit_window", "shape": "circle", "radius": 80.0, "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用范围伤害模板。")


func _apply_fullscreen_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "fullscreen_damage", "result_key": "fullscreen_hit", "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用全场伤害模板。")


func _apply_self_buff_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "apply_self_buff", "buff_id": 0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用自身 Buff 模板。")


func _apply_sequence_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "arrow_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "sequence", "count": 3, "interval": 0.15, "speed": 420.0, "lifetime": 2.0, "damage_ratio": 0.8}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用三连弹道模板，请填写弹道场景。")


func _apply_rain_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "rain_hit", "scene": "", "origin": "hit_window", "trajectory": "ballistic", "aim_mode": "enemy_area", "emission": "area_rain", "count": 12, "interval": 0.08, "target_search_range": 500.0, "area_width": 260.0, "area_height": 90.0, "arc_height": 180.0, "gravity": 900.0, "speed": 360.0, "lifetime": 3.0, "damage_ratio": 0.7}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用斜向上箭雨模板，请填写弹道场景。")


func _clear_nodes() -> void:
	_apply_template([], "已清空节点。保存前请重新配置有效技能流程。")


func _load_action_data() -> void:
	_action_data = {}
	var path := _find_action_path_for_skill(int(_current_skill_id))
	if path.is_empty():
		_status.text = "未找到该技能所属资源的 combat_actions.json。"
		return
	var data := _read_json(path)
	var action := _default_action()
	_action_data = (data.get("actions", {}) as Dictionary).get(action, {})
	_status.text = "动作数据源：%s" % path


func _refresh_timeline() -> void:
	if _timeline == null:
		return
	var action := _default_action()
	if not action.is_empty():
		var path := _find_action_path_for_skill(int(_current_skill_id))
		var data := _read_json(path)
		_action_data = (data.get("actions", {}) as Dictionary).get(action, {})
	var frame_count := _frame_count_for_action(_action_data)
	_frame_slider.max_value = frame_count - 1
	_frame_slider.value = clampf(_frame_slider.value, 0, frame_count - 1)
	_timeline.set_timeline(_action_data, _current_skill().get("nodes", []), frame_count, int(_frame_slider.value), _selected_node_index())


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


func _on_timeline_frame_selected(frame: int) -> void:
	_frame_slider.set_value_no_signal(frame)


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
	var path := _find_action_path_for_skill(int(_current_skill_id))
	var actions: Dictionary = _read_json(path).get("actions", {})
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


func _find_action_path_for_skill(skill_id: int) -> String:
	for path in ["res://data/characters.json", "res://data/enemies.json"]:
		var configs := _read_json(path)
		for key in configs:
			var config: Dictionary = configs[key]
			if _config_uses_skill(config, skill_id):
				var asset := String(config.get("asset", ""))
				var action_path := asset.path_join("combat_actions.json")
				if FileAccess.file_exists(action_path):
					return action_path
	return ""


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


func _save_skills() -> void:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "无法写入 skills.json"
		return
	file.store_string(JSON.stringify(_skills, "\t") + "\n")
	_status.text = "已保存 skills.json。"
