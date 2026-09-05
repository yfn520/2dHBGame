class_name MapPanel
extends Control
## 地图切换测试面板（F2 打开）
## 列出全部关卡，点击即可切换，便于测试完整任务流程时的关卡跳转。

var ui_root: Node = null

var _panel: PanelContainer
var _list: VBoxContainer
var _current_label: Label
var _level_buttons: Dictionary = {}  # Button -> level_id


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layout()
	_refresh()


func setup(p_ui_root: Node) -> void:
	ui_root = p_ui_root


func _process(_delta: float) -> void:
	# 不能在这里每帧 _refresh()：_refresh 会销毁并重建全部按钮，
	# 点击还没完成按钮就被 queue_free 了，导致所有关卡按钮点不动。
	pass


func toggle() -> void:
	if _panel == null:
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh()


func is_open() -> bool:
	return _panel != null and _panel.visible


func close() -> void:
	if _panel != null:
		_panel.visible = false


func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	_panel = PanelContainer.new()
	_panel.name = "MapContent"
	_panel.visible = false
	_panel.position = Vector2(120, 80)
	_panel.custom_minimum_size = Vector2(560, 620)
	_panel.theme_type_variation = &"Popup"
	add_child(_panel)

	var outer := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(outer)

	var main_col := VBoxContainer.new()
	main_col.add_theme_constant_override("separation", 8)
	outer.add_child(main_col)

	_current_label = Label.new()
	_current_label.theme_type_variation = &"HUDTitle"
	_current_label.add_theme_font_size_override("font_size", 16)
	main_col.add_child(_current_label)

	var sep := HSeparator.new()
	main_col.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_col.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	main_col.add_child(bottom)

	var hint := Label.new()
	hint.text = "点击关卡切换  |  F2 关闭"
	hint.theme_type_variation = &"HUDMuted"
	hint.add_theme_font_size_override("font_size", 12)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.theme_type_variation = &"DangerButton"
	close_btn.pressed.connect(func(): close())
	bottom.add_child(close_btn)


func _refresh() -> void:
	if GameRegistry.level_config == null:
		return
	var levels: Dictionary = GameRegistry.level_config.get_all_levels()
	var current_id := -1
	if GameRegistry.level_manager != null:
		current_id = GameRegistry.level_manager.get_current_level_id()

	_current_label.text = "地图切换（测试）  |  当前关卡: %s" % _level_name(current_id)

	# 重建关卡列表
	for child in _list.get_children():
		child.queue_free()
	_level_buttons.clear()

	var ids := levels.keys()
	ids.sort()

	for id_value in ids:
		var level_id := int(id_value)
		var cfg: Dictionary = levels[id_value]
		var is_current := level_id == current_id
		var btn := Button.new()
		btn.theme_type_variation = &"HUDButton"
		btn.text = "%s  %s" % [level_id, cfg.get("name", "未命名")]
		if is_current:
			btn.text = "▶ " + btn.text
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = cfg.get("scene_path", "")
		btn.pressed.connect(_on_level_pressed.bind(level_id))
		_list.add_child(btn)
		_level_buttons[level_id] = btn


func _on_level_pressed(level_id: int) -> void:
	if GameRegistry.level_manager == null:
		return
	GameRegistry.level_manager.load_level(level_id)
	close()


func _level_name(level_id: int) -> String:
	if GameRegistry.level_config == null:
		return "?"
	var cfg: Dictionary = GameRegistry.level_config.get_level(level_id)
	if cfg.is_empty():
		return "?"
	var level_name := str(cfg.get("name", "?"))
	if GameRegistry.chapter_service != null:
		var chapter_id: String = GameRegistry.chapter_service.get_chapter_for_level(level_id)
		if not chapter_id.is_empty() and GameRegistry.chapter_service.is_echo_unlocked(chapter_id):
			return "%s · 回响" % level_name
	return level_name
