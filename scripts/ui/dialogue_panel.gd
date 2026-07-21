class_name DialoguePanel
extends Control

var _speaker: Label
var _body: Label
var _portrait: TextureRect
var _choices: VBoxContainer
var _continue_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_layout()


func show_node(node: Dictionary, npc: Dictionary) -> void:
	visible = true
	_speaker.text = String(node.get("speaker", npc.get("name", "NPC")))
	_body.text = String(node.get("text", ""))
	_load_portrait(String(node.get("portrait", npc.get("portrait", ""))))
	for child in _choices.get_children():
		child.queue_free()
	var visible_choices: Array = GameRegistry.dialogue_service.get_visible_choices(node) as Array
	for index in range(visible_choices.size()):
		var choice: Dictionary = visible_choices[index]
		var button := Button.new()
		button.text = String(choice.get("text", "选项 %d" % (index + 1)))
		button.custom_minimum_size.y = 42
		button.pressed.connect(GameRegistry.dialogue_service.choose.bind(index))
		_choices.add_child(button)
	_continue_button.visible = visible_choices.is_empty()


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_top = 0.62
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.94
	panel.theme_type_variation = &"Window"
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(150, 150)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 24)
	content.add_child(_speaker)
	_body = Label.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 18)
	content.add_child(_body)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	content.add_child(_choices)
	_continue_button = Button.new()
	_continue_button.text = "继续"
	_continue_button.custom_minimum_size = Vector2(120, 42)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_continue_button.pressed.connect(GameRegistry.dialogue_service.advance)
	content.add_child(_continue_button)


func _load_portrait(path: String) -> void:
	_portrait.texture = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null
	_portrait.visible = _portrait.texture != null


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(InputActions.CANCEL):
		GameRegistry.dialogue_service.finish(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.INTERACT) and _continue_button.visible:
		GameRegistry.dialogue_service.advance()
		get_viewport().set_input_as_handled()
