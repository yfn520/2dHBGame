@tool
extends Window

const DEFAULT_OUTPUT_DIR := "res://scenes/effects/projectiles"
const PROJECTILE_SCRIPT := "res://scripts/combat/projectile.gd"
const SKILLS_PATH := "res://data/skills.json"

var _key_edit: LineEdit
var _output_edit: LineEdit
var _visual_mode: OptionButton
var _texture_edit: LineEdit
var _scene_edit: LineEdit
var _collision_w: SpinBox
var _collision_h: SpinBox
var _visual_scale: SpinBox
var _speed: SpinBox
var _lifetime: SpinBox
var _max_pierce: SpinBox
var _write_skill: CheckBox
var _skill_id: SpinBox
var _damage_ratio: SpinBox
var _cooldown: SpinBox
var _animation: LineEdit
var _range: SpinBox
var _buff_on_hit: SpinBox
var _buff_chance: SpinBox
var _status_label: Label
var _file_dialog: EditorFileDialog
var _confirm_dialog: ConfirmationDialog
var _path_request: String = ""
var _output_path_touched := false
var _syncing_output_path := false


func _init() -> void:
	title = "Generate Projectile"
	size = Vector2i(560, 720)
	min_size = Vector2i(520, 620)
	exclusive = false
	close_requested.connect(hide)


func _ready() -> void:
	if get_child_count() > 0:
		return
	_build_ui()


func open_generator() -> void:
	if get_child_count() == 0:
		_build_ui()
	popup_centered()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.custom_minimum_size = Vector2(480, 0)
	scroll.add_child(form)

	_key_edit = _add_line_edit(form, "projectile_key", "fireball")
	_key_edit.text_changed.connect(_on_key_changed)
	_output_edit = _add_path_row(form, "output_path", "", "output")
	_on_key_changed(_key_edit.text)
	_output_edit.text_changed.connect(_on_output_path_changed)

	_visual_mode = _add_option(form, "visual_mode", ["Texture", "PackedScene"])
	_visual_mode.item_selected.connect(_on_visual_mode_changed)
	_texture_edit = _add_path_row(form, "texture_path", "", "texture")
	_scene_edit = _add_path_row(form, "visual_scene_path", "", "scene")

	_collision_w = _add_spin(form, "collision_width", 24.0, 1.0, 512.0, 1.0)
	_collision_h = _add_spin(form, "collision_height", 24.0, 1.0, 512.0, 1.0)
	_visual_scale = _add_spin(form, "visual_scale", 1.0, 0.01, 20.0, 0.05)
	_speed = _add_spin(form, "projectile_speed", 300.0, 1.0, 3000.0, 10.0)
	_lifetime = _add_spin(form, "projectile_lifetime", 5.0, 0.1, 60.0, 0.1)
	_max_pierce = _add_spin(form, "max_pierce", 0.0, -1.0, 99.0, 1.0)

	_write_skill = CheckBox.new()
	_write_skill.text = "write/update skills.json"
	form.add_child(_write_skill)

	_skill_id = _add_spin(form, "skill_id", 1002.0, 1.0, 999999.0, 1.0)
	_damage_ratio = _add_spin(form, "节点伤害倍率", 1.5, -99.0, 99.0, 0.1)
	_cooldown = _add_spin(form, "cooldown", 3.0, 0.0, 999.0, 0.1)
	_animation = _add_line_edit(form, "播放动画 action", "skill1")
	_range = _add_spin(form, "AI 施放距离", 300.0, 0.0, 3000.0, 10.0)
	_buff_on_hit = _add_spin(form, "节点 Buff ID", 0.0, 0.0, 999999.0, 1.0)
	_buff_chance = _add_spin(form, "节点 Buff 概率", 0.0, 0.0, 1.0, 0.05)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_status_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)

	var generate_button := Button.new()
	generate_button.text = "Generate"
	generate_button.pressed.connect(_on_generate_pressed)
	buttons.add_child(generate_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(hide)
	buttons.add_child(close_button)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirm Overwrite"
	_confirm_dialog.confirmed.connect(_generate_now)
	add_child(_confirm_dialog)

	_on_visual_mode_changed(0)


func _add_labeled(parent: Control, label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return control


func _add_line_edit(parent: Control, label_text: String, default_value: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default_value
	return _add_labeled(parent, label_text, edit) as LineEdit


func _add_path_row(parent: Control, label_text: String, default_value: String, request: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = default_value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var browse := Button.new()
	browse.text = "..."
	browse.pressed.connect(_open_file_dialog.bind(request))
	row.add_child(browse)
	return edit


func _add_spin(parent: Control, label_text: String, default_value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = default_value
	return _add_labeled(parent, label_text, spin) as SpinBox


func _add_option(parent: Control, label_text: String, items: Array[String]) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	return _add_labeled(parent, label_text, option) as OptionButton


func _on_key_changed(text: String) -> void:
	if _output_path_touched:
		return
	var key := _sanitize_key(text)
	if key.is_empty():
		key = "projectile"
	_syncing_output_path = true
	_output_edit.text = "%s/%s.tscn" % [DEFAULT_OUTPUT_DIR, key]
	_syncing_output_path = false


func _on_output_path_changed(_text: String) -> void:
	if _syncing_output_path:
		return
	_output_path_touched = true


func _on_visual_mode_changed(index: int) -> void:
	var is_texture := index == 0
	_texture_edit.editable = is_texture
	_scene_edit.editable = not is_texture


func _open_file_dialog(request: String) -> void:
	_path_request = request
	_file_dialog.clear_filters()
	match request:
		"texture":
			_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.add_filter("*.png, *.webp, *.jpg, *.jpeg, *.tres ; Texture")
		"scene":
			_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.add_filter("*.tscn, *.scn ; Scene")
		"output":
			_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
			_file_dialog.add_filter("*.tscn ; Scene")
	_file_dialog.popup_centered(Vector2i(900, 650))


func _on_file_selected(path: String) -> void:
	match _path_request:
		"texture":
			_texture_edit.text = path
		"scene":
			_scene_edit.text = path
		"output":
			_output_path_touched = true
			_output_edit.text = path


func _on_generate_pressed() -> void:
	_status_label.text = ""
	var error := _validate()
	if not error.is_empty():
		_status_label.text = error
		return
	if FileAccess.file_exists(_output_edit.text):
		_confirm_dialog.dialog_text = "Output file already exists. Overwrite?\n%s" % _output_edit.text
		_confirm_dialog.popup_centered()
		return
	_generate_now()


func _validate() -> String:
	if _sanitize_key(_key_edit.text).is_empty():
		return "projectile_key cannot be empty."
	if not _output_edit.text.begins_with("res://") or not _output_edit.text.ends_with(".tscn"):
		return "output_path must be a res:// .tscn file."
	if _visual_mode.selected == 0:
		if _texture_edit.text.is_empty() or not ResourceLoader.exists(_texture_edit.text):
			return "Texture mode requires a valid texture_path."
	else:
		if _scene_edit.text.is_empty() or not ResourceLoader.exists(_scene_edit.text):
			return "PackedScene mode requires a valid visual_scene_path."
	if _write_skill.button_pressed and int(_skill_id.value) <= 0:
		return "skill_id must be greater than 0 when writing skills.json."
	return ""


func _generate_now() -> void:
	var root := Area2D.new()
	root.name = _sanitize_key(_key_edit.text).to_pascal_case()
	root.collision_layer = 4
	root.collision_mask = 8
	var script := load(PROJECTILE_SCRIPT) as Script
	if script != null:
		root.set_script(script)

	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(float(_collision_w.value), float(_collision_h.value))
	shape_node.shape = rect
	root.add_child(shape_node)
	shape_node.owner = root

	if _visual_mode.selected == 0:
		var sprite := Sprite2D.new()
		sprite.name = "Visual"
		sprite.texture = load(_texture_edit.text) as Texture2D
		sprite.scale = Vector2.ONE * float(_visual_scale.value)
		root.add_child(sprite)
		sprite.owner = root
	else:
		var scene := load(_scene_edit.text) as PackedScene
		var visual_root := Node2D.new()
		visual_root.name = "Visual"
		visual_root.scale = Vector2.ONE * float(_visual_scale.value)
		root.add_child(visual_root)
		visual_root.owner = root

		var visual_scene := scene.instantiate()
		visual_scene.name = "VisualScene"
		visual_root.add_child(visual_scene)
		visual_scene.owner = root

	var output_path := _output_edit.text
	var dir_path := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.free()
		_status_label.text = "Failed to pack projectile scene: %s" % pack_err
		return
	var save_err := ResourceSaver.save(packed, output_path)
	root.free()
	if save_err != OK:
		_status_label.text = "Failed to save projectile scene: %s" % save_err
		return

	if _write_skill.button_pressed:
		var skill_error := _write_skill_config(output_path)
		if not skill_error.is_empty():
			_status_label.text = skill_error
			EditorInterface.get_resource_filesystem().scan()
			return

	EditorInterface.get_resource_filesystem().scan()
	_status_label.text = "Generated: %s" % output_path


func _write_skill_config(projectile_scene: String) -> String:
	var data: Dictionary = {}
	if FileAccess.file_exists(SKILLS_PATH):
		var json := JSON.new()
		var err := json.parse(FileAccess.get_file_as_string(SKILLS_PATH))
		if err != OK or not json.data is Dictionary:
			return "Failed to parse skills.json."
		data = json.data

	var id := str(int(_skill_id.value))
	data[id] = {
		"name": _key_edit.text,
		"description": "Generated projectile skill.",
		"cooldown": float(_cooldown.value),
		"cast_range": float(_range.value),
		"nodes": [
			{"type": "play_animation", "action": _animation.text},
			{"type": "wait_hit_window", "hit_window_index": 0},
			{
				"type": "spawn_projectile",
				"result_key": "%s_hit" % _sanitize_key(_key_edit.text),
				"scene": projectile_scene,
				"origin": "hit_window",
				"trajectory": "straight",
				"aim_mode": "facing_elevation",
				"emission": "single",
				"speed": float(_speed.value),
				"lifetime": float(_lifetime.value),
				"max_pierce": int(_max_pierce.value),
				"damage_ratio": float(_damage_ratio.value),
				"buff_id": int(_buff_on_hit.value),
				"buff_chance": float(_buff_chance.value),
			},
			{"type": "wait_animation_end"},
			{"type": "end_skill"},
		],
	}

	var file := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if file == null:
		return "Failed to write skills.json."
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return ""


func _sanitize_key(value: String) -> String:
	var result := value.strip_edges().to_snake_case()
	result = result.replace("/", "_").replace("\\", "_").replace(" ", "_")
	return result
