class_name TaskDrawer
extends Control
## 右侧抽屉式任务面板。任务系统未实现时展示真实空状态。

signal drawer_changed(opened: bool)

const DRAWER_WIDTH := 340.0
const SLIDE_SPEED := 8.0

var skin: UISkin
var ui_root: UIRoot

var _panel: PanelContainer
var _content: VBoxContainer
var _open: bool = false
var _current_x: float = DRAWER_WIDTH


func _ready() -> void:
	_build_layout()
	_update_position(true)


func _process(delta: float) -> void:
	var target := 0.0 if _open else DRAWER_WIDTH
	_current_x = lerpf(_current_x, target, clampf(delta * SLIDE_SPEED, 0.0, 1.0))
	_update_position(false)


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	drawer_changed.emit(true)


func close() -> void:
	_open = false
	drawer_changed.emit(false)


func is_open() -> bool:
	return _open


func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	# 半透明遮罩（点击关闭）
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.015, 0.01, 0.40)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	_panel = PanelContainer.new()
	_panel.name = "DrawerPanel"
	_panel.theme_type_variation = &"Window"
	_panel.custom_minimum_size = Vector2(DRAWER_WIDTH, 0)
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -DRAWER_WIDTH
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	margin.add_child(_content)

	# 标题栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_content.add_child(header)

	var title := Label.new()
	title.text = "任务"
	title.theme_type_variation = &"HUDTitle"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.theme_type_variation = &"HUDButton"
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	_content.add_child(sep)

	# 空状态（任务系统未实现）
	_build_empty_state()


func _build_empty_state() -> void:
	var empty_box := VBoxContainer.new()
	empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(empty_box)

	var icon_label := Label.new()
	icon_label.text = "◎"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 40)
	icon_label.add_theme_color_override("font_color", Color(0.50, 0.42, 0.28))
	empty_box.add_child(icon_label)

	var hint := Label.new()
	hint.text = "暂无任务"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.theme_type_variation = &"HUDTitle"
	hint.add_theme_font_size_override("font_size", 18)
	empty_box.add_child(hint)

	var desc := Label.new()
	desc.text = "任务系统尚在开发中，敬请期待。"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.theme_type_variation = &"HUDMuted"
	desc.add_theme_font_size_override("font_size", 13)
	empty_box.add_child(desc)


func _update_position(instant: bool) -> void:
	if _panel == null:
		return
	if instant:
		_current_x = 0.0 if _open else DRAWER_WIDTH
	# 通过移动整个 Control 的锚点偏移来实现滑入/滑出
	_panel.position.x = _current_x
	# 遮罩只在打开时响应
	var overlay := get_node_or_null("Overlay")
	if overlay != null:
		overlay.visible = _open or _current_x < DRAWER_WIDTH - 1.0


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
