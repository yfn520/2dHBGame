class_name DialoguePanel
extends Control

var _speaker: Label
var _body: Label
var _portrait: TextureRect
var _portrait_frame: PanelContainer
var _choices: VBoxContainer
var _choices_frame: PanelContainer
var _continue_button: Button
var _slot: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_layout()
	var viewport := get_viewport()
	if viewport != null:
		if not viewport.size_changed.is_connected(_apply_viewport_layout):
			viewport.size_changed.connect(_apply_viewport_layout)
	call_deferred("_apply_viewport_layout")


func show_node(node: Dictionary, npc: Dictionary) -> void:
	visible = true
	var speaker := String(node.get("speaker", "")).strip_edges()
	_speaker.text = speaker if not speaker.is_empty() else String(npc.get("name", "NPC"))
	_body.text = String(node.get("text", ""))
	_load_portrait(String(node.get("portrait", npc.get("portrait", ""))))
	for child in _choices.get_children():
		child.queue_free()
	var visible_choices: Array = GameRegistry.dialogue_service.get_visible_choices(node)
	if _body.text.strip_edges().is_empty() and not visible_choices.is_empty():
		_body.text = "请选择回应。"
	for index in range(visible_choices.size()):
		var choice: Dictionary = visible_choices[index]
		var button := Button.new()
		button.text = "%d.  %s" % [index + 1, String(choice.get("text", "选项 %d" % (index + 1)))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 56
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", Color(0.94, 0.92, 0.82))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.42))
		button.add_theme_stylebox_override("normal", _make_choice_style(Color(0.04, 0.05, 0.07, 0.78), Color(0.40, 0.34, 0.20, 0.75)))
		button.add_theme_stylebox_override("hover", _make_choice_style(Color(0.18, 0.14, 0.07, 0.94), Color(0.96, 0.73, 0.26, 0.95), 2))
		button.add_theme_stylebox_override("pressed", _make_choice_style(Color(0.29, 0.20, 0.08, 0.96), Color(1.0, 0.82, 0.36), 2))
		button.add_theme_stylebox_override("focus", _make_choice_style(Color(0.18, 0.14, 0.07, 0.94), Color(1.0, 0.82, 0.36), 2))
		button.pressed.connect(GameRegistry.dialogue_service.choose.bind(index))
		_choices.add_child(button)
	_choices_frame.visible = not visible_choices.is_empty()
	_continue_button.visible = visible_choices.is_empty()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.4)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	# Bottom dialogue strip: portrait left, dialogue in the centre and choices
	# on the right. Keeping the content in a fixed-height, clipped strip prevents
	# a long generated line from expanding this modal into a full-height column.
	_slot = Control.new()
	_slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_slot)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.theme_type_variation = &"Window"
	panel.clip_contents = true
	_slot.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18 if side == "top" or side == "bottom" else 24)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	# Left: portrait framed as part of the dialogue card.
	_portrait_frame = PanelContainer.new()
	_portrait_frame.custom_minimum_size = Vector2(152, 152)
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_portrait_frame.add_theme_stylebox_override("panel", _make_frame_style(Color(0.03, 0.03, 0.04, 0.90), Color(0.78, 0.60, 0.22, 0.88), 2, 8))
	row.add_child(_portrait_frame)
	var portrait_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		portrait_margin.add_theme_constant_override("margin_%s" % side, 6)
	_portrait_frame.add_child(portrait_margin)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(132, 132)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_margin.add_child(_portrait)
	# Centre: the actual spoken line. It must not determine the panel's height.
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 22)
	_speaker.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	content.add_child(_speaker)
	_body = Label.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 18)
	_body.max_lines_visible = 4
	_body.clip_text = true
	_body.custom_minimum_size = Vector2(0, 0)
	content.add_child(_body)
	_continue_button = Button.new()
	_continue_button.text = "继续 ▶"
	_continue_button.custom_minimum_size = Vector2(112, 40)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_continue_button.pressed.connect(GameRegistry.dialogue_service.advance)
	content.add_child(_continue_button)
	# Right: a dedicated response card instead of bare buttons on the backdrop.
	_choices_frame = PanelContainer.new()
	_choices_frame.custom_minimum_size = Vector2(330, 0)
	_choices_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choices_frame.add_theme_stylebox_override("panel", _make_frame_style(Color(0.02, 0.025, 0.035, 0.88), Color(0.67, 0.52, 0.22, 0.82), 1, 10))
	row.add_child(_choices_frame)
	var choices_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		choices_margin.add_theme_constant_override("margin_%s" % side, 12)
	_choices_frame.add_child(choices_margin)
	var choices_layout := VBoxContainer.new()
	choices_layout.add_theme_constant_override("separation", 8)
	choices_margin.add_child(choices_layout)
	var choices_title := Label.new()
	choices_title.text = "选择回应"
	choices_title.add_theme_font_size_override("font_size", 14)
	choices_title.add_theme_color_override("font_color", Color(0.86, 0.72, 0.36, 0.92))
	choices_layout.add_child(choices_title)
	_choices = VBoxContainer.new()
	_choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choices.add_theme_constant_override("separation", 8)
	choices_layout.add_child(_choices)


func _apply_viewport_layout() -> void:
	var viewport := get_viewport()
	if viewport == null or _slot == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# Controls placed directly under CanvasLayer do not have a Control parent
	# that can resolve percentage anchors. Use explicit viewport coordinates.
	position = Vector2.ZERO
	size = viewport_size
	# The dark dialogue strip is a full-width cinematic layer. Its internal
	# MarginContainer still keeps portraits and choices away from screen edges.
	_slot.position = Vector2(0, viewport_size.y * 0.64)
	_slot.size = Vector2(viewport_size.x, viewport_size.y * 0.30)


func _load_portrait(path: String) -> void:
	if not path.is_empty() and ResourceLoader.exists(path):
		_portrait.texture = load(path) as Texture2D
	else:
		_portrait.texture = null
	_portrait.visible = _portrait.texture != null
	_portrait_frame.visible = _portrait.visible


func _make_frame_style(background: Color, border: Color, border_width := 1, radius := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	return style


func _make_choice_style(background: Color, border: Color, border_width := 1) -> StyleBoxFlat:
	var style := _make_frame_style(background, border, border_width, 6)
	style.set_content_margin_all(12)
	return style


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	if event.is_action_pressed(InputActions.CANCEL):
		GameRegistry.dialogue_service.finish(false)
		viewport.set_input_as_handled()
	elif event.is_action_pressed(InputActions.INTERACT) and _continue_button.visible:
		GameRegistry.dialogue_service.advance()
		viewport.set_input_as_handled()
