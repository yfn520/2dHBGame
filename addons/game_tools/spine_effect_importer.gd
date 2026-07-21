@tool
extends Window

class DropPathEdit:
	extends LineEdit

	signal path_dropped(path: String)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return not _extract_path(data).is_empty()

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var path := _extract_path(data)
		if path.is_empty():
			return
		path = _to_res_path(path)
		text = path
		path_dropped.emit(path)

	func _extract_path(data: Variant) -> String:
		if data is Dictionary:
			var dictionary: Dictionary = data
			if dictionary.has("files"):
				var files_value: Variant = dictionary.get("files", [])
				if files_value is PackedStringArray and not files_value.is_empty():
					return String(files_value[0])
				if files_value is Array and not files_value.is_empty():
					return String(files_value[0])
			if dictionary.has("resource"):
				return String(dictionary.get("resource", ""))
			if dictionary.has("path"):
				return String(dictionary.get("path", ""))
		if data is String:
			return data
		return ""

	func _to_res_path(path: String) -> String:
		var normalized := path.replace("\\", "/")
		if normalized.begins_with("res://"):
			return normalized
		var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
		if normalized.begins_with(project_root):
			return "res://" + normalized.substr(project_root.length()).trim_prefix("/")
		return normalized

const DEFAULT_OUTPUT_DIR := "res://assets/effects"

var _dir_edit: LineEdit
var _output_edit: LineEdit
var _animation_edit: LineEdit
var _fps_spin: SpinBox
var _loop_check: CheckBox
var _scale_spin: SpinBox
var _status_label: Label
var _dir_dialog: EditorFileDialog
var _output_path_touched := false
var _syncing_output_path := false


func _init() -> void:
	title = "Import Spine Effect"
	size = Vector2i(620, 360)
	min_size = Vector2i(560, 320)
	exclusive = false
	close_requested.connect(hide)


func _ready() -> void:
	if get_child_count() > 0:
		return
	_build_ui()


func open_importer() -> void:
	if get_child_count() == 0:
		_build_ui()
	popup_centered()
	mode = Window.MODE_MAXIMIZED


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

	_dir_edit = _add_path_row(root, "spine_dir", "")
	_dir_edit.text_changed.connect(_on_dir_changed)
	_output_edit = _add_line_edit(root, "output_tscn", "")
	_output_edit.text_changed.connect(_on_output_changed)
	_animation_edit = _add_line_edit(root, "animation_name", "animation")
	_fps_spin = _add_spin(root, "fps", 15.0, 1.0, 60.0, 1.0)
	_scale_spin = _add_spin(root, "visual_scale", 1.0, 0.01, 20.0, 0.05)
	_loop_check = CheckBox.new()
	_loop_check.text = "loop animation"
	_loop_check.button_pressed = true
	root.add_child(_loop_check)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_status_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)

	var generate_button := Button.new()
	generate_button.text = "Generate TSCN"
	generate_button.pressed.connect(_on_generate_pressed)
	buttons.add_child(generate_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(hide)
	buttons.add_child(close_button)

	_dir_dialog = EditorFileDialog.new()
	_dir_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_dir_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_dir_dialog)


func _add_labeled(parent: Control, label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return control


func _add_line_edit(parent: Control, label_text: String, default_value: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default_value
	return _add_labeled(parent, label_text, edit) as LineEdit


func _add_path_row(parent: Control, label_text: String, default_value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var edit := DropPathEdit.new()
	edit.text = default_value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.path_dropped.connect(_on_dir_selected)
	row.add_child(edit)
	var browse := Button.new()
	browse.text = "..."
	browse.pressed.connect(_open_dir_dialog)
	row.add_child(browse)
	return edit


func _add_spin(parent: Control, label_text: String, default_value: float, min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = default_value
	return _add_labeled(parent, label_text, spin) as SpinBox


func _open_dir_dialog() -> void:
	_dir_dialog.popup_centered_ratio(0.95)
	_dir_dialog.mode = Window.MODE_MAXIMIZED


func _on_dir_selected(path: String) -> void:
	var dir_path := _normalize_spine_dir_path(path)
	_dir_edit.text = dir_path
	_on_dir_changed(dir_path)


func _on_dir_changed(path: String) -> void:
	path = _normalize_spine_dir_path(path)
	if _output_path_touched:
		return
	var folder := path.get_file()
	if folder.is_empty():
		folder = "spine_effect"
	_syncing_output_path = true
	# 若 spine 源目录已在 res://assets/effects/ 下，visual.tscn 与源同级；
	# 否则默认导出到 res://assets/effects/<folder>/<folder>_visual.tscn
	if path.begins_with(DEFAULT_OUTPUT_DIR + "/"):
		_output_edit.text = path.path_join("%s_visual.tscn" % folder.to_snake_case())
	else:
		_output_edit.text = "%s/%s/%s_visual.tscn" % [DEFAULT_OUTPUT_DIR, folder.to_snake_case(), folder.to_snake_case()]
	_syncing_output_path = false


func _normalize_spine_dir_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return normalized
	if FileAccess.file_exists(normalized):
		return normalized.get_base_dir()
	return normalized


func _on_output_changed(_text: String) -> void:
	if _syncing_output_path:
		return
	_output_path_touched = true


func _on_generate_pressed() -> void:
	_status_label.text = ""
	var error := _validate()
	if not error.is_empty():
		_status_label.text = error
		return
	var result := _generate_scene()
	_status_label.text = result


func _validate() -> String:
	var dir_path := _normalize_spine_dir_path(_dir_edit.text)
	if dir_path.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		return "spine_dir must be a valid res:// folder."
	if _output_edit.text.is_empty() or not _output_edit.text.begins_with("res://") or not _output_edit.text.ends_with(".tscn"):
		return "output_tscn must be a res:// .tscn path."
	if _find_file_with_extension(dir_path, "atlas").is_empty():
		return "No .atlas file found in spine_dir."
	if _find_file_with_extension(dir_path, "png").is_empty():
		return "No .png file found in spine_dir."
	if _find_file_with_extension(dir_path, "json").is_empty():
		return "No .json file found in spine_dir."
	return ""


func _generate_scene() -> String:
	var dir_path := _normalize_spine_dir_path(_dir_edit.text)
	var atlas_path := _find_file_with_extension(dir_path, "atlas")
	var json_path := _find_file_with_extension(dir_path, "json")
	var png_path := _find_file_with_extension(dir_path, "png")
	var regions := _parse_atlas(atlas_path)
	regions = _order_regions_from_spine_json(json_path, _animation_edit.text.strip_edges(), regions)
	if regions.is_empty():
		return "No atlas regions parsed."

	var image := Image.new()
	if image.load(png_path) != OK:
		return "Failed to load atlas png."

	var frames := SpriteFrames.new()
	var animation_name := _animation_edit.text.strip_edges()
	if animation_name.is_empty():
		animation_name = "animation"
	if not frames.has_animation(animation_name):
		frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, float(_fps_spin.value))
	frames.set_animation_loop(animation_name, _loop_check.button_pressed)

	for region in regions:
		var texture := ImageTexture.create_from_image(_extract_region(image, region))
		frames.add_frame(animation_name, texture)

	var root := Node2D.new()
	root.name = _output_edit.text.get_file().get_basename().to_pascal_case()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = frames
	sprite.animation = animation_name
	sprite.autoplay = animation_name
	sprite.scale = Vector2.ONE * float(_scale_spin.value)
	root.add_child(sprite)
	sprite.owner = root

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_edit.text.get_base_dir()))
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.free()
		return "Failed to pack scene: %s" % pack_err
	var save_err := ResourceSaver.save(packed, _output_edit.text)
	root.free()
	if save_err != OK:
		return "Failed to save scene: %s" % save_err
	EditorInterface.get_resource_filesystem().scan()
	return "Generated: %s (%d frames)" % [_output_edit.text, regions.size()]


func _find_file_with_extension(dir_path: String, extension: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == extension:
			dir.list_dir_end()
			return dir_path.path_join(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return ""


func _parse_atlas(atlas_path: String) -> Array[Dictionary]:
	var lines := FileAccess.get_file_as_string(atlas_path).split("\n")
	var regions: Array[Dictionary] = []
	var current: Dictionary = {}
	var reading_region := false
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line.is_empty():
			continue
		if not line.contains(":"):
			if reading_region and current.has("name") and current.has("xy") and current.has("size"):
				regions.append(current)
			current = {"name": line, "rotate": false}
			reading_region = true
			continue
		if not reading_region:
			continue
		var parts := line.split(":", false, 1)
		var key := String(parts[0]).strip_edges()
		var value := String(parts[1]).strip_edges()
		match key:
			"rotate":
				current["rotate"] = value == "true"
			"xy":
				current["xy"] = _parse_vector2i(value)
			"size":
				current["size"] = _parse_vector2i(value)
	if reading_region and current.has("name") and current.has("xy") and current.has("size"):
		regions.append(current)
	regions.sort_custom(_sort_region_by_name)
	return regions


func _order_regions_from_spine_json(json_path: String, animation_name: String, regions: Array[Dictionary]) -> Array[Dictionary]:
	if json_path.is_empty() or not FileAccess.file_exists(json_path):
		return regions
	var text := FileAccess.get_file_as_string(json_path)
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return regions
	var data: Dictionary = parser.data
	var animations: Dictionary = data.get("animations", {})
	var selected_name := animation_name
	if selected_name.is_empty():
		selected_name = "animation"
	if not animations.has(selected_name):
		if animations.has("animation"):
			selected_name = "animation"
		elif not animations.is_empty():
			selected_name = String(animations.keys()[0])
		else:
			return regions
	var animation: Dictionary = animations.get(selected_name, {})
	var slots: Dictionary = animation.get("slots", {})
	if slots.is_empty():
		return regions

	var frame_names: Array[String] = []
	for slot_name in slots:
		var slot: Dictionary = slots[slot_name]
		for frame in slot.get("attachment", []):
			if frame is Dictionary:
				var frame_name := String(frame.get("name", ""))
				if not frame_name.is_empty():
					frame_names.append(frame_name)
	if frame_names.is_empty():
		return regions

	var by_name: Dictionary = {}
	for region in regions:
		by_name[String(region.get("name", ""))] = region

	var ordered: Array[Dictionary] = []
	for frame_name in frame_names:
		if by_name.has(frame_name):
			ordered.append(by_name[frame_name])
	if ordered.is_empty():
		return regions
	return ordered


func _parse_vector2i(value: String) -> Vector2i:
	var parts := value.split(",", false)
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(String(parts[0]).strip_edges()), int(String(parts[1]).strip_edges()))


func _sort_region_by_name(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("name", "")) < String(b.get("name", ""))


func _extract_region(image: Image, region: Dictionary) -> Image:
	var xy: Vector2i = region.get("xy", Vector2i.ZERO)
	var size: Vector2i = region.get("size", Vector2i.ZERO)
	var cropped := image.get_region(Rect2i(xy, size))
	if bool(region.get("rotate", false)):
		return _rotate_clockwise(cropped)
	return cropped


func _rotate_clockwise(source: Image) -> Image:
	var result := Image.create(source.get_height(), source.get_width(), false, source.get_format())
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			result.set_pixel(source.get_height() - 1 - y, x, source.get_pixel(x, y))
	return result
