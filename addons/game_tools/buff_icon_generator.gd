@tool
extends Window

## Buff 图标生成器。
## 读取 res://data/buffs.json，为每个 buff 生成 32×32 PNG 图标
## （按类别上色 + 中文名首字），存到 res://assets/icons/buffs/<id>.png，
## 并回写 buffs.json 的 icon 字段。可重复执行。

const CONFIG_PATH := "res://data/buffs.json"
const ICON_DIR := "res://assets/icons/buffs/"
const ICON_SIZE := 64

var _log: RichTextLabel


func _ready() -> void:
	title = "Buff 图标生成器"
	size = Vector2i(420, 380)
	close_requested.connect(hide)
	_build_layout()


func open_generator() -> void:
	popup_centered()
	_run()


# ---- 布局 ----

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var hint := Label.new()
	hint.text = "为 res://data/buffs.json 中每个 buff 生成 32×32 图标，\n存到 res://assets/icons/buffs/，并回写 icon 字段。"
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)

	var btn := Button.new()
	btn.text = "重新生成"
	btn.pressed.connect(_run)
	root.add_child(btn)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 240)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log)


# ---- 主流程 ----

func _run() -> void:
	_log.clear()
	_log_line("开始生成...")
	DirAccess.make_dir_recursive_absolute(ICON_DIR)

	if not FileAccess.file_exists(CONFIG_PATH):
		_log_line("[color=red]找不到 buffs.json[/color]")
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		_log_line("[color=red]读取 buffs.json 失败[/color]")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_log_line("[color=red]解析失败: %s[/color]" % json.get_error_message())
		return

	var data: Dictionary = json.data
	var generated := 0
	for id_str in data:
		var buff: Dictionary = data[id_str]
		var name := String(buff.get("name", id_str))
		var category := String(buff.get("category", "debuff"))
		var icon_path := ICON_DIR + "%s.png" % id_str
		var ok := await _render_and_save(name, category, icon_path)
		if ok:
			buff["icon"] = icon_path
			generated += 1
			_log_line("[color=green]✓[/color] %s - %s" % [id_str, name])
		else:
			_log_line("[color=red]✗ %s - %s[/color]" % [id_str, name])

	# 按 id 升序写回 buffs.json
	var keys: Array = data.keys()
	keys.sort()
	var sorted: Dictionary = {}
	for k in keys:
		sorted[k] = data[k]
	var wf := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if wf == null:
		_log_line("[color=red]写回 buffs.json 失败[/color]")
		return
	wf.store_string(JSON.stringify(sorted, "\t") + "\n")
	EditorInterface.get_resource_filesystem().scan()
	_log_line("[color=green]完成：生成 %d 个图标，已回写 buffs.json[/color]" % generated)


# ---- 渲染单个图标 ----

func _render_and_save(buff_name: String, category: String, res_path: String) -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(ICON_SIZE, ICON_SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.55, 0.25, 1.0) if category == "buff" else Color(0.6, 0.2, 0.2, 1.0)
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = Color(0.1, 0.1, 0.1, 0.85)
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.text = buff_name.substr(0, 1) if not buff_name.is_empty() else "?"
	panel.add_child(label)

	vp.add_child(panel)
	add_child(vp)

	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(res_path)
	var err := img.save_png(abs_path)

	remove_child(vp)
	vp.queue_free()
	return err == OK


func _log_line(text: String) -> void:
	_log.append_text(text + "\n")
