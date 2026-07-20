class_name TouchControls
extends CanvasLayer
## 手机端触屏控件层：虚拟摇杆 + 跳跃 + 辅助按钮（背包/装备/切人/取消）。
## 仅在触屏可用或强制开启时显示，PC 上默认隐藏。
##
## 桥接方式：
## - 持续型（跳跃）：button_down/button_up → Input.action_press/action_release
## - 瞬时型（菜单/切人/取消）：pressed → Input.parse_input_event(InputEventAction)
##
## 技能按钮不在本层，由 BattleHud 现有的 4 个按钮承担（见 Step 4）。

const FORCE_TOUCH_SETTING := "application/run/force_touch_controls"
const TouchJoystickScript := preload("res://scripts/ui/virtual_joystick.gd")

var _joystick: TouchJoystick
var _jump_button: Button
var _inventory_button: Button
var _equipment_button: Button
var _switch_button: Button
var _cancel_button: Button
var _root_panel: Control
var _active: bool = false


func _ready() -> void:
	layer = 15  # 高于 HUD(10)，低于 ScreenLayer(20)，菜单/弹窗打开时自然遮盖
	_build_layout()
	_apply_visibility()


func _apply_visibility() -> void:
	_active = _is_touch_input_active()
	_root_panel.visible = _active


func _is_touch_input_active() -> bool:
	# 移动平台：自动启用触屏控件
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	# PC 平台：只看 force_touch_controls 开关
	# （不依赖 DisplayServer.is_touchscreen_available()，因为触屏笔记本会让它误判为 true）
	var force_flag: bool = ProjectSettings.get_setting(FORCE_TOUCH_SETTING, false)
	return force_flag


## 在弹窗/菜单打开时隐藏控件，避免误触。由 UIRoot 调用。
func set_controls_visible(visible_flag: bool) -> void:
	if not _active:
		return
	_root_panel.visible = visible_flag


func _build_layout() -> void:
	_root_panel = Control.new()
	_root_panel.name = "TouchControlsRoot"
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_panel)

	# 虚拟摇杆（左下）
	_joystick = TouchJoystickScript.new()
	_joystick.name = "VirtualJoystick"
	_root_panel.add_child(_joystick)

	# 跳跃按钮（右下，大）
	_jump_button = _make_button("跳跃", 110, 110)
	_jump_button.anchor_left = 1.0
	_jump_button.anchor_top = 1.0
	_jump_button.anchor_right = 1.0
	_jump_button.anchor_bottom = 1.0
	_jump_button.offset_left = -260.0
	_jump_button.offset_top = -150.0
	_jump_button.offset_right = -140.0
	_jump_button.offset_bottom = -30.0
	_jump_button.add_theme_font_size_override("font_size", 22)
	_jump_button.button_down.connect(_on_jump_down)
	_jump_button.button_up.connect(_on_jump_up)
	_root_panel.add_child(_jump_button)

	# 辅助按钮组（右侧，跳跃按钮上方）
	var side := VBoxContainer.new()
	side.anchor_left = 1.0
	side.anchor_top = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -260.0
	side.offset_top = -340.0
	side.offset_right = -140.0
	side.offset_bottom = -170.0
	side.add_theme_constant_override("separation", 8)
	_root_panel.add_child(side)

	_inventory_button = _make_action_button("背包", InputActions.TOGGLE_INVENTORY)
	side.add_child(_inventory_button)
	_equipment_button = _make_action_button("装备", InputActions.TOGGLE_EQUIPMENT)
	side.add_child(_equipment_button)
	_switch_button = _make_action_button("切人", InputActions.SWITCH_CHARACTER)
	side.add_child(_switch_button)
	_cancel_button = _make_action_button("返回", InputActions.CANCEL)
	side.add_child(_cancel_button)


func _make_button(text: String, w: float, h: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(w, h)
	btn.add_theme_font_size_override("font_size", 16)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


func _make_action_button(text: String, action: String) -> Button:
	var btn := _make_button(text, 120, 44)
	btn.pressed.connect(_emit_action.bind(action))
	return btn


func _on_jump_down() -> void:
	Input.action_press(InputActions.JUMP, 1.0)


func _on_jump_up() -> void:
	Input.action_release(InputActions.JUMP)


func _emit_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	Input.parse_input_event(event)
