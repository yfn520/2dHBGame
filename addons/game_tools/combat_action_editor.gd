@tool
extends Window

const PreviewControl = preload("res://addons/game_tools/combat_action_preview.gd")

var _asset_paths: Array[String] = []
var _asset_select: OptionButton
var _action_select: OptionButton
var _window_select: OptionButton
var _frame_spin: SpinBox
var _right_check: CheckBox
var _preview: Control
var _fields: Dictionary = {}
var _status: Label
var _sprite_frames: SpriteFrames
var _config: Dictionary = {}
var _config_path := ""
var _sprite_scale := 1.0
var _visual_transform: Dictionary = {}
var _built := false


func open_editor() -> void:
	if not _built:
		_build_ui()
	_load_enemy_list()
	popup_centered(Vector2i(920, 720))


func _build_ui() -> void:
	_built = true
	title = "攻击判定可视化配置"
	close_requested.connect(hide)
	min_size = Vector2i(760, 600)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(root)

	var selectors := HBoxContainer.new()
	root.add_child(selectors)
	selectors.add_child(_label("资源"))
	_asset_select = OptionButton.new()
	_asset_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(_asset_select)
	_asset_select.item_selected.connect(_on_asset_selected)
	selectors.add_child(_label("动作"))
	_action_select = OptionButton.new()
	_action_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(_action_select)
	_action_select.item_selected.connect(_on_action_selected)
	selectors.add_child(_label("窗口"))
	_window_select = OptionButton.new()
	_window_select.item_selected.connect(_on_window_selected)
	selectors.add_child(_window_select)
	selectors.add_child(_label("预览帧"))
	_frame_spin = SpinBox.new()
	_frame_spin.min_value = 0
	_frame_spin.step = 1
	_frame_spin.value_changed.connect(func(_value): _refresh_preview())
	selectors.add_child(_frame_spin)
	_right_check = CheckBox.new()
	_right_check.text = "朝右"
	_right_check.toggled.connect(func(_pressed): _refresh_preview())
	selectors.add_child(_right_check)

	_preview = PreviewControl.new()
	_preview.custom_minimum_size = Vector2(600, 390)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_preview)

	var form := GridContainer.new()
	form.columns = 4
	root.add_child(form)
	_fields["start_frame"] = _add_spin(form, "起始帧", 0, 999, 1)
	_fields["end_frame"] = _add_spin(form, "结束帧", 0, 999, 1)
	_fields["forward"] = _add_spin(form, "前向距离", 0, 2000, 0.5)
	_fields["y"] = _add_spin(form, "Y 偏移", -2000, 2000, 0.5)
	_fields["width"] = _add_spin(form, "宽度", 1, 2000, 0.5)
	_fields["height"] = _add_spin(form, "高度", 1, 2000, 0.5)
	_fields["sprite_scale"] = _add_spin(form, "精灵缩放", 0.01, 20, 0.01)
	for spin in _fields.values():
		spin.value_changed.connect(func(_value): _refresh_preview())

	var footer := HBoxContainer.new()
	root.add_child(footer)
	var save_button := Button.new()
	save_button.text = "保存当前动作"
	save_button.pressed.connect(_save_action)
	footer.add_child(save_button)
	var use_frame_button := Button.new()
	use_frame_button.text = "将预览帧设为有效帧"
	use_frame_button.pressed.connect(_use_current_frame)
	footer.add_child(use_frame_button)
	var add_window_button := Button.new()
	add_window_button.text = "新增窗口"
	add_window_button.pressed.connect(_add_window)
	footer.add_child(add_window_button)
	var delete_window_button := Button.new()
	delete_window_button.text = "删除窗口"
	delete_window_button.pressed.connect(_delete_window)
	footer.add_child(delete_window_button)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_status)


func _label(text_value: String) -> Label:
	var result := Label.new()
	result.text = text_value
	return result


func _add_spin(parent: GridContainer, label_text: String, minimum: float, maximum: float, step_value: float) -> SpinBox:
	parent.add_child(_label(label_text))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _load_enemy_list() -> void:
	_asset_paths.clear()
	_asset_select.clear()
	_scan_asset_group("res://assets/characters", "角色")
	_scan_asset_group("res://assets/enemies", "怪物")
	if not _asset_paths.is_empty():
		_on_asset_selected(0)


func _scan_asset_group(base_path: String, label_prefix: String) -> void:
	var dir := DirAccess.open(base_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var asset_path := base_path.path_join(folder)
			var frames_path := asset_path.path_join("godot/spriteframes.tres")
			if ResourceLoader.exists(frames_path):
				_asset_paths.append(asset_path)
				_asset_select.add_item("%s / %s" % [label_prefix, folder])
		folder = dir.get_next()
	dir.list_dir_end()
func _on_asset_selected(index: int) -> void:
	if index < 0 or index >= _asset_paths.size():
		return
	var asset_path := _asset_paths[index]
	_sprite_frames = load(asset_path.path_join("godot/spriteframes.tres")) as SpriteFrames
	_config_path = asset_path.path_join("combat_actions.json")
	_config = {"version": 1, "sprite_scale": 1.0, "actions": {}}
	var character_config_path := asset_path.path_join("character_config.json")
	var display_offset := Vector2.ZERO
	if FileAccess.file_exists(character_config_path):
		var character_json := JSON.new()
		if character_json.parse(FileAccess.get_file_as_string(character_config_path)) == OK and character_json.data is Dictionary:
			_config["sprite_scale"] = float(character_json.data.get("display_scale", 1.0))
			var offset: Dictionary = character_json.data.get("display_offset", {})
			display_offset = Vector2(float(offset.get("x", 0.0)), float(offset.get("y", 0.0)))
	if FileAccess.file_exists(_config_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(_config_path)) == OK and json.data is Dictionary:
			_config = json.data
	_sprite_scale = float(_config.get("sprite_scale", 1.0))
	_visual_transform = _load_visual_transform(asset_path, display_offset)
	_fields["sprite_scale"].value = _sprite_scale
	_action_select.clear()
	if _sprite_frames != null:
		for animation_name in _sprite_frames.get_animation_names():
			_action_select.add_item(String(animation_name))
	var preferred := _find_action_index("attack")
	_action_select.select(preferred)
	_on_action_selected(preferred)


func _load_visual_transform(asset_path: String, display_offset: Vector2) -> Dictionary:
	var result := {
		"root_position": display_offset,
		"position": Vector2.ZERO,
		"offset": Vector2.ZERO,
		"scale": Vector2.ONE,
		"centered": true,
	}
	var scene_path := asset_path.path_join("godot/character_actions.tscn")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return result
	var instance := packed.instantiate()
	var sprite := instance.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		result["position"] = sprite.position
		result["offset"] = sprite.offset
		result["scale"] = sprite.scale
		result["centered"] = sprite.centered
	instance.free()
	return result


func _find_action_index(action_name: String) -> int:
	for index in range(_action_select.item_count):
		if _action_select.get_item_text(index) == action_name:
			return index
	return 0


func _on_action_selected(index: int) -> void:
	if _sprite_frames == null or index < 0 or index >= _action_select.item_count:
		return
	var action_name := _action_select.get_item_text(index)
	var count := _sprite_frames.get_frame_count(action_name)
	_frame_spin.max_value = maxi(0, count - 1)
	var default_frame := maxi(0, count / 2)
	var actions: Dictionary = _config.get("actions", {})
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	if windows.is_empty():
		windows = [_make_default_window(default_frame)]
		action["hit_windows"] = windows
		actions[action_name] = action
		_config["actions"] = actions
	_window_select.clear()
	for window_index in range(windows.size()):
		_window_select.add_item("#%d" % (window_index + 1))
	_window_select.select(0)
	_on_window_selected(0)


func _on_window_selected(index: int) -> void:
	if _action_select.item_count == 0:
		return
	var action_name := _action_select.get_item_text(_action_select.selected)
	var actions: Dictionary = _config.get("actions", {})
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	if index < 0 or index >= windows.size() or not windows[index] is Dictionary:
		return
	var window: Dictionary = windows[index]
	for key in ["start_frame", "end_frame", "forward", "y", "width", "height"]:
		_fields[key].value = float(window.get(key, 0.0))
	_frame_spin.value = float(window.get("start_frame", 0))
	_refresh_preview()


func _make_default_window(frame: int) -> Dictionary:
	return {
		"start_frame": frame,
		"end_frame": frame,
		"forward": 30.0,
		"y": 0.0,
		"width": 20.0,
		"height": 20.0,
	}


func _current_window() -> Dictionary:
	return {
		"start_frame": int(_fields["start_frame"].value),
		"end_frame": int(_fields["end_frame"].value),
		"forward": _fields["forward"].value,
		"y": _fields["y"].value,
		"width": _fields["width"].value,
		"height": _fields["height"].value,
	}


func _refresh_preview() -> void:
	if _sprite_frames == null or _action_select.item_count == 0:
		return
	var action_name := _action_select.get_item_text(_action_select.selected)
	var frame := clampi(int(_frame_spin.value), 0, maxi(0, _sprite_frames.get_frame_count(action_name) - 1))
	var texture := _sprite_frames.get_frame_texture(action_name, frame)
	_preview.set_preview(texture, _fields["sprite_scale"].value, frame, _current_window(), _right_check.button_pressed, _visual_transform)


func _use_current_frame() -> void:
	_fields["start_frame"].value = _frame_spin.value
	_fields["end_frame"].value = _frame_spin.value
	_refresh_preview()


func _add_window() -> void:
	if _action_select.item_count == 0:
		return
	var action_name := _action_select.get_item_text(_action_select.selected)
	var actions: Dictionary = _config.get("actions", {})
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	windows.append(_make_default_window(int(_frame_spin.value)))
	action["hit_windows"] = windows
	actions[action_name] = action
	_config["actions"] = actions
	_on_action_selected(_action_select.selected)
	_window_select.select(windows.size() - 1)
	_on_window_selected(windows.size() - 1)


func _delete_window() -> void:
	if _action_select.item_count == 0 or _window_select.item_count == 0:
		return
	var action_name := _action_select.get_item_text(_action_select.selected)
	var actions: Dictionary = _config.get("actions", {})
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	var index := _window_select.selected
	if index >= 0 and index < windows.size():
		windows.remove_at(index)
	if windows.is_empty():
		windows.append(_make_default_window(int(_frame_spin.value)))
	action["hit_windows"] = windows
	actions[action_name] = action
	_config["actions"] = actions
	_on_action_selected(_action_select.selected)


func _save_action() -> void:
	if _config_path.is_empty() or _action_select.item_count == 0:
		return
	var action_name := _action_select.get_item_text(_action_select.selected)
	var actions: Dictionary = _config.get("actions", {})
	var action: Dictionary = actions.get(action_name, {})
	var windows: Array = action.get("hit_windows", [])
	var index := _window_select.selected
	if index >= 0 and index < windows.size():
		windows[index] = _current_window()
	else:
		windows.append(_current_window())
	action["hit_windows"] = windows
	actions[action_name] = action
	_config["version"] = 1
	_config["sprite_scale"] = _fields["sprite_scale"].value
	_config["actions"] = actions
	var file := FileAccess.open(_config_path, FileAccess.WRITE)
	if file == null:
		_status.text = "保存失败: %s" % _config_path
		return
	file.store_string(JSON.stringify(_config, "\t") + "\n")
	_status.text = "已保存 %s / %s" % [_asset_select.get_item_text(_asset_select.selected), action_name]
