@tool
extends Window

const SKILLS_PATH := "res://data/skills.json"
const CHARACTERS_PATH := "res://data/characters.json"
const ENEMIES_PATH := "res://data/enemies.json"
const BUFFS_PATH := "res://data/buffs.json"
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

var _skills: Dictionary = {}
var _characters_config: Dictionary = {}
var _enemies_config: Dictionary = {}
var _current_skill_id := ""
var _current_hero_key := ""
var _action_data: Dictionary = {}
var _loading := false

var _hero_select: OptionButton
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


func _init() -> void:
	title = "技能节点配置"
	size = Vector2i(1040, 860)
	min_size = Vector2i(820, 700)
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
	_rebuild_hero_select()
	_rebuild_skill_select()


func open_editor() -> void:
	if _skill_select == null:
		_build_ui()
	_load_skills()
	_load_character_configs()
	_rebuild_hero_select()
	_rebuild_skill_select()
	popup_centered(size)


func _build_ui() -> void:
	if _skill_select != null:
		return
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var hero_row := HBoxContainer.new()
	root.add_child(hero_row)
	var hero_label := Label.new()
	hero_label.text = "英雄"
	hero_row.add_child(hero_label)
	_hero_select = OptionButton.new()
	_hero_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_select.item_selected.connect(_on_hero_selected)
	hero_row.add_child(_hero_select)
	var save := Button.new()
	save.text = "保存 skills.json"
	save.pressed.connect(_save_skills)
	hero_row.add_child(save)

	var skill_row := HBoxContainer.new()
	root.add_child(skill_row)
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
	var help := Label.new()
	help.text = "技能本体只配置基础信息。伤害、弹道、范围、Buff 和特效全部在节点中配置。AI 距离由节点和攻击框自动计算，保存时生成 ai_range_cache。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_page.add_child(help)
	var filler := Control.new()
	base_page.add_child(filler)

	var sequence_page := VBoxContainer.new()
	sequence_page.name = "编排"
	sequence_page.add_theme_constant_override("separation", 6)
	tabs.add_child(sequence_page)
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


func _load_character_configs() -> void:
	_characters_config = _read_json(CHARACTERS_PATH).duplicate(true)
	_enemies_config = _read_json(ENEMIES_PATH).duplicate(true)


func _rebuild_hero_select() -> void:
	if _hero_select == null:
		return
	_hero_select.clear()
	_hero_select.add_item("全部技能")
	_hero_select.set_item_metadata(0, "")
	var char_ids: Array = _characters_config.keys()
	char_ids.sort_custom(func(a, b): return int(a) < int(b))
	for id in char_ids:
		var config: Dictionary = _characters_config[id]
		var display_name := String(config.get("name", "未命名"))
		_hero_select.add_item("[英雄] %s  %s" % [id, display_name])
		_hero_select.set_item_metadata(_hero_select.item_count - 1, "char:%s" % id)
	var enemy_ids: Array = _enemies_config.keys()
	enemy_ids.sort_custom(func(a, b): return int(a) < int(b))
	for id in enemy_ids:
		var config: Dictionary = _enemies_config[id]
		var display_name := String(config.get("name", "未命名"))
		_hero_select.add_item("[怪物] %s  %s" % [id, display_name])
		_hero_select.set_item_metadata(_hero_select.item_count - 1, "enemy:%s" % id)
	if _hero_select.item_count > 0:
		var index := 0
		for candidate in range(_hero_select.item_count):
			if String(_hero_select.get_item_metadata(candidate)) == _current_hero_key:
				index = candidate
		_hero_select.select(index)


func _on_hero_selected(index: int) -> void:
	if index < 0 or index >= _hero_select.item_count:
		return
	_current_hero_key = String(_hero_select.get_item_metadata(index))
	_current_skill_id = ""
	_rebuild_skill_select()


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
			_build_damage_fields(form, node, false)
			_add_ai_range_readonly(form, "近战自动有效距离")
		"area_damage":
			_build_area_fields(form, node)
			_add_ai_range_readonly(form, "AOE 自动有效距离")
		"fullscreen_damage": _build_damage_fields(form, node, false)
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


func _build_damage_fields(form: GridContainer, node: Dictionary, include_origin: bool) -> void:
	_add_result_key(form, node)
	if include_origin:
		_add_origin_fields(form, node)
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_build_buff_ids_fields(form, node)
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
	_build_buff_ids_fields(form, node)
	_add_node_spin(form, "Buff 概率", "buff_chance", node, 0.0, 0.0, 1.0, 0.05)


func _build_projectile_fields(form: GridContainer, node: Dictionary) -> void:
	_add_result_key(form, node)
	_add_node_scene_picker(form, "弹道场景", "scene", node)
	_add_origin_fields(form, node)
	_add_node_option(form, "轨迹", "trajectory", node, [{"value": "straight", "label": "直线"}, {"value": "ballistic", "label": "抛物线"}], true)
	_add_node_option(form, "瞄准/落点", "aim_mode", node, [{"value": "facing_elevation", "label": "朝向 + 仰角"}, {"value": "nearest_enemy", "label": "指向最近敌人"}, {"value": "enemy_area", "label": "敌人附近区域"}, {"value": "forward_area", "label": "施法者前方区域"}], true)
	_add_node_option(form, "发射方式", "emission", node, [{"value": "single", "label": "单发"}, {"value": "sequence", "label": "连续"}, {"value": "fan", "label": "扇形齐射"}, {"value": "area_rain", "label": "区域落雨"}], true)
	_add_node_spin(form, "AI 最小起手距离", "ai_min_range", node, 0.0, 0.0, 9999.0, 1.0)
	_add_node_spin(form, "AI 最大起手距离", "ai_max_range", node, 0.0, 0.0, 9999.0, 1.0)
	_add_node_spin(form, "速度", "speed", node, 300.0, 1.0, 9999.0, 1.0)
	_add_node_spin(form, "生命周期", "lifetime", node, 5.0, 0.1, 99.0, 0.1)
	_add_node_spin(form, "最大穿透数", "max_pierce", node, 0.0, -1.0, 99.0, 1.0)
	_add_node_spin(form, "伤害倍率", "damage_ratio", node, 1.0, 0.0, 99.0, 0.1)
	_build_buff_ids_fields(form, node)
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
	_add_node_scene_picker(form, "特效场景", "scene", node)
	_add_effect_metadata_helper(form, node)
	_add_node_option(form, "目标", "target", node, TARGET_OPTIONS, true)
	if String(node.get("target", "origin")) == "result":
		_add_node_line(form, "结果集", "result_key", node)
		_add_node_option(form, "触发频率", "delivery", node, [{"value": "each_hit", "label": "每次命中"}, {"value": "each_target", "label": "每个目标一次"}], false)
	else:
		_add_origin_fields(form, node)
	_add_node_spin(form, "偏移 X", "offset_x", node, 0.0, -9999.0, 9999.0, 1.0)
	_add_node_spin(form, "偏移 Y", "offset_y", node, 0.0, -9999.0, 9999.0, 1.0)
	_add_node_option(form, "附着层级", "attachment_layer", node, ATTACHMENT_LAYER_OPTIONS, false)
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
	_build_buff_ids_fields(form, node)
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
		option.add_item(String(value.get("label", value.get("value", ""))))
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
	list_container.add_child(add_btn)


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
	dialog.popup_centered_ratio(0.7)


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
		"wait_action_frame": return {"type": type_name, "frame": 0}
		"wait_hit_window": return {"type": type_name, "hit_window_index": 0}
		"melee_damage": return {"type": type_name, "result_key": "melee_hit", "damage_ratio": 1.0}
		"area_damage": return {"type": type_name, "result_key": "area_hit", "origin": "hit_window", "shape": "circle", "radius": 80.0, "damage_ratio": 1.0}
		"fullscreen_damage": return {"type": type_name, "result_key": "fullscreen_hit", "damage_ratio": 1.0}
		"spawn_projectile": return {"type": type_name, "result_key": "projectile_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.0}
		"play_effect": return {"type": type_name, "scene": "", "target": "origin"}
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
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "spawn_projectile", "result_key": "projectile_hit", "scene": "", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用单发弹道模板，请填写弹道场景。")


func _apply_area_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "area_damage", "result_key": "area_hit", "origin": "hit_window", "shape": "circle", "radius": 80.0, "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用范围伤害模板。")


func _apply_fullscreen_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "fullscreen_damage", "result_key": "fullscreen_hit", "damage_ratio": 1.0}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用全场伤害模板。")


func _apply_self_buff_template() -> void:
	var action := _default_action()
	_apply_template([{"type": "play_animation", "action": action}, {"type": "wait_hit_window", "hit_window_index": 0}, {"type": "apply_self_buff", "buff_ids": []}, {"type": "wait_animation_end"}, {"type": "end_skill"}], "已套用自身 Buff 模板。")


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
		_preview.set_preview(null, 1.0, 0, {}, true, _visual_transform)
		_refresh_effect_preview()
		return
	var count := _sprite_frames.get_frame_count(_preview_action)
	if count == 0:
		_preview.set_preview(null, 1.0, 0, {}, true, _visual_transform)
		_refresh_effect_preview()
		return
	var frame := clampi(int(_frame_slider.value), 0, count - 1)
	var texture := _sprite_frames.get_frame_texture(_preview_action, frame)
	var window: Dictionary = {}
	var windows: Array = _action_data.get("hit_windows", [])
	if not windows.is_empty() and windows[0] is Dictionary:
		window = windows[0]
	_preview.set_preview(texture, _sprite_scale, frame, window, true, _visual_transform)
	_refresh_effect_preview()


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
	if type_name != "play_effect" and type_name != "spawn_projectile":
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var scene_path := String(node.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_preview.set_effect(null, Vector2.ZERO, false, 1.0, false)
		return
	var visual_scale: float = float(_visual_transform.get("visual_scale", 1.0))
	# 预览固定朝右（facing_right=true）；运行时 flip_h=true 朝右，mirror_x=1
	var mirror_x := 1.0
	if type_name == "play_effect":
		var offset := Vector2(float(node.get("offset_x", 0.0)), float(node.get("offset_y", 0.0)))
		var coord_space := String(node.get("coordinate_space", "world"))
		# character_local: 挂角色根，position = offset * mirror_x * visual_scale
		# world: 挂场景根，global_position = origin(角色根) + offset
		var effect_offset := Vector2(offset.x * mirror_x * visual_scale, offset.y * visual_scale) if coord_space == "character_local" else offset
		_preview.set_effect(packed, effect_offset, true, visual_scale, coord_space == "character_local")
	else:
		# spawn_projectile: 挂场景根，global_position = origin
		# origin 由字段决定：hit_window → hit_box 位置；caster → 角色根；socket → 帧坐标
		# 预览中统一用 hit_window 偏移（若有）否则用角色根（origin）
		# origin 偏移乘 visual_scale：角色缩放时 hit_window/forward 位置也等比缩放
		var origin_offset := _resolve_preview_origin(node) * visual_scale
		_preview.set_effect(packed, origin_offset, true, visual_scale, false)


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
			# 预览固定朝右，forward 正方向即 +X
			return Vector2(absf(forward), y)
	# caster / socket / nearest_enemy 在预览中均用角色根（零偏移）
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
	var new_skill := {
		"name": "新技能",
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
					base_id = 3000 + (hero_id - 1001) * 100 + 1
				elif config_type == "enemy":
					base_id = 2000 + (hero_id - 1001) * 100 + 1
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
