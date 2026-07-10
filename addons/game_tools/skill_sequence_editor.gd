@tool
extends Window

const SKILLS_PATH := "res://data/skills.json"

var _skills: Dictionary = {}
var _skill_select: OptionButton
var _node_list: ItemList
var _node_type: OptionButton
var _action_select: OptionButton
var _event_select: OptionButton
var _status: Label
var _current_skill_id := 0


func _init() -> void:
	title = "技能节点配置"
	size = Vector2i(760, 560)
	min_size = Vector2i(720, 500)
	close_requested.connect(hide)


func _ready() -> void:
	_build_ui()
	_load_skills()
	_rebuild_skill_select()
	_rebuild_action_select()


func open_editor() -> void:
	if _skill_select == null:
		_build_ui()
	_load_skills()
	_rebuild_skill_select()
	_rebuild_action_select()
	popup_centered(size)


func _build_ui() -> void:
	if _skill_select != null:
		return
	var root := VBoxContainer.new()
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

	_node_list = ItemList.new()
	_node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_node_list)

	var controls := GridContainer.new()
	controls.columns = 2
	root.add_child(controls)

	controls.add_child(Label.new())
	(controls.get_child(0) as Label).text = "节点类型"
	_node_type = OptionButton.new()
	for item in ["play_animation", "wait_action_event", "wait_animation_end", "use_action_hit_window", "execute_skill_effect", "spawn_projectile", "aoe", "fullscreen", "apply_self_buff", "heal", "move_x", "play_effect", "end_skill"]:
		_node_type.add_item(item)
	controls.add_child(_node_type)

	controls.add_child(Label.new())
	(controls.get_child(2) as Label).text = "动作"
	_action_select = OptionButton.new()
	_action_select.item_selected.connect(_on_action_selected)
	controls.add_child(_action_select)

	controls.add_child(Label.new())
	(controls.get_child(4) as Label).text = "事件"
	_event_select = OptionButton.new()
	controls.add_child(_event_select)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
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
	_current_skill_id = _skill_select.get_item_id(index)
	_rebuild_node_list()
	var skill := _get_current_skill()
	var anim := String(skill.get("animation", "attack"))
	_select_option_by_text(_action_select, anim)
	_rebuild_event_select(anim)


func _get_current_skill() -> Dictionary:
	return _skills.get(str(_current_skill_id), {})


func _rebuild_node_list() -> void:
	_node_list.clear()
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	for index in range(nodes.size()):
		var node: Dictionary = nodes[index]
		_node_list.add_item("%02d  %s  %s" % [index + 1, String(node.get("type", "")), _summarize_node(node)])


func _summarize_node(node: Dictionary) -> String:
	match String(node.get("type", "")):
		"play_animation", "use_action_hit_window":
			return String(node.get("action", ""))
		"wait_action_event":
			return String(node.get("event", ""))
		"heal":
			return str(int(node.get("amount", 0)))
		"move_x":
			return str(float(node.get("delta_x", node.get("distance", 0.0))))
		_:
			return ""


func _add_node() -> void:
	if _current_skill_id <= 0:
		return
	var skill := _get_current_skill()
	var nodes: Array = skill.get("nodes", [])
	var type_name := _node_type.get_item_text(_node_type.selected)
	var action_name := _action_select.get_item_text(_action_select.selected) if _action_select.item_count > 0 else String(skill.get("animation", "attack"))
	var event_name := _event_select.get_item_text(_event_select.selected) if _event_select.item_count > 0 else "release"
	var node := {"type": type_name}
	match type_name:
		"play_animation", "use_action_hit_window":
			node["action"] = action_name
			if type_name == "use_action_hit_window":
				node["detects_hits"] = true
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


func _save_skills() -> void:
	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "无法写入 %s" % SKILLS_PATH
		return
	file.store_string(JSON.stringify(_skills, "\t") + "\n")
	_status.text = "已保存 %s" % SKILLS_PATH


func _rebuild_action_select() -> void:
	_action_select.clear()
	var names := _collect_action_names()
	for name in names:
		_action_select.add_item(name)
	if _action_select.item_count == 0:
		_action_select.add_item("attack")


func _on_action_selected(index: int) -> void:
	if index < 0:
		return
	_rebuild_event_select(_action_select.get_item_text(index))


func _rebuild_event_select(action_name: String) -> void:
	_event_select.clear()
	var names := _collect_event_names(action_name)
	if names.is_empty():
		names = ["release", "impact", "effect"]
	for name in names:
		_event_select.add_item(name)


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
	for path in _find_combat_action_files():
		var data := _read_json(path)
		var actions: Dictionary = data.get("actions", {})
		var action: Dictionary = actions.get(action_name, {})
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
