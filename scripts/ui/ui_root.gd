class_name UIRoot
extends Node
## 统一 UI 管理入口：固定管理 HUD / Screen / Popup / Notification / Debug 五层。
## GameRoot 只持有本节点，不再直接挂载 HUD、角色面板、旧背包和动态 DebugLayer。

signal main_menu_changed(opened: bool, tab: StringName)
signal interact_requested()

const TAB_CHARACTER := &"character"
const TAB_EQUIPMENT := &"equipment"
const TAB_SKILLS := &"skills"
const TAB_INVENTORY := &"inventory"

var skin: UISkin

var _hud_layer: CanvasLayer
var _screen_layer: CanvasLayer
var _popup_layer: CanvasLayer
var _notification_layer: CanvasLayer
var _debug_layer: CanvasLayer

var _hud: BattleHud
var _main_menu: MainMenu
var _task_drawer: TaskDrawer
var _debug_panel: DebugPanel
var _main_ui: Control
var _touch_controls: TouchControls
var _dialogue_panel: DialoguePanel
var _interaction_prompt: Label
var _notification_label: Label
var _dialogue_previous_pause := false

var _popup_stack: Array[Control] = []
var _tooltip: Control = null
var _party_manager: PartyManager
var _enemy_spawner: Node


func _ready() -> void:
	skin = UISkin.new()
	# 加入 group，便于 combat_component 等系统在任意层级查找 UIRoot（避免依赖 tree.root 直接子节点）
	add_to_group("ui_root")
	_build_layers()
	_build_content()


## 初始化 UIRoot，由 GameRoot 调用。
func setup(party_manager: PartyManager, enemy_spawner: Node) -> void:
	_party_manager = party_manager
	_enemy_spawner = enemy_spawner
	if _hud != null:
		_hud.setup(party_manager, enemy_spawner)
	if _main_menu != null:
		_main_menu.setup(party_manager)
	if _debug_panel != null:
		_debug_panel.setup(party_manager, enemy_spawner)
	if _task_drawer != null:
		_task_drawer.setup(GameRegistry.quest_service)
	_connect_npc_services()


func set_interaction_target(npc: NpcActor) -> void:
	var available := is_instance_valid(npc)
	if _interaction_prompt != null:
		_interaction_prompt.visible = available
		_interaction_prompt.text = "E  与 %s 对话" % npc.get_display_name() if available else ""
	if _touch_controls != null:
		_touch_controls.set_interact_available(available)


# ---- 主菜单 ----

func open_main_menu(tab: StringName = TAB_EQUIPMENT) -> void:
	if _main_menu == null:
		return
	_main_menu.open(tab)


func toggle_main_menu(tab: StringName = TAB_EQUIPMENT) -> void:
	if _main_menu == null:
		return
	if _main_menu.is_open():
		if _main_menu.current_tab() == tab:
			_main_menu.close()
		else:
			_main_menu.open(tab)
	else:
		_main_menu.open(tab)


# ---- 任务抽屉 ----

func toggle_task_drawer() -> void:
	if _task_drawer == null:
		return
	_task_drawer.toggle()


# ---- 主界面 UI（资源验证） ----

func toggle_main_ui() -> void:
	if _main_ui == null:
		return
	_main_ui.visible = not _main_ui.visible
	_set_world_input_for_ui(_main_ui.visible or is_modal_open())


func is_main_ui_open() -> bool:
	return _main_ui != null and _main_ui.visible


# ---- 弹窗 ----

## 在 PopupLayer 显示一个阻塞弹窗，加入关闭栈。
func show_popup(popup: Control) -> void:
	if popup == null:
		return
	var parent := popup.get_parent()
	if parent != null and parent != _popup_layer:
		parent.remove_child(popup)
	if popup.get_parent() == null:
		_popup_layer.add_child(popup)
	_popup_stack.erase(popup)
	_popup_stack.append(popup)
	var exiting_callback := _on_popup_exiting.bind(popup)
	if not popup.tree_exiting.is_connected(exiting_callback):
		popup.tree_exiting.connect(exiting_callback)
	popup.visible = true
	_set_world_input_for_ui(true)


## 从 PopupLayer 移除指定弹窗。
func close_popup(popup: Control) -> void:
	if popup == null:
		return
	_popup_stack.erase(popup)
	if popup.get_parent() == _popup_layer:
		_popup_layer.remove_child(popup)
	popup.visible = false
	_set_world_input_for_ui(is_modal_open())


## 显示悬停提示（非阻塞，不入栈）。
func show_tooltip(tip: Control) -> void:
	hide_tooltip()
	if tip == null:
		return
	_tooltip = tip
	_popup_layer.add_child(tip)


func hide_tooltip() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.get_parent().remove_child(_tooltip) if _tooltip.get_parent() != null else null
		_tooltip.queue_free()
	_tooltip = null


## 按优先级关闭最上层：弹窗 → 任务抽屉 → 主菜单 → 主界面 UI。
func close_top() -> void:
	if not _popup_stack.is_empty():
		var top: Control = _popup_stack.back()
		if top == _dialogue_panel and GameRegistry.dialogue_service != null:
			GameRegistry.dialogue_service.finish(false)
			return
		close_popup(top)
		return
	if _task_drawer != null and _task_drawer.is_open():
		_task_drawer.close()
		return
	if _main_menu != null and _main_menu.is_open():
		_main_menu.close()
		return
	if _main_ui != null and _main_ui.visible:
		_main_ui.visible = false
		_set_world_input_for_ui(false)


func is_modal_open() -> bool:
	return not _popup_stack.is_empty() or (_main_menu != null and _main_menu.is_open()) or (_task_drawer != null and _task_drawer.is_open()) or (_main_ui != null and _main_ui.visible)


func is_main_menu_open() -> bool:
	return _main_menu != null and _main_menu.is_open()


func is_popup_open() -> bool:
	return not _popup_stack.is_empty()


## 菜单打开时屏蔽手动技能输入并隐藏触屏控件。
func _set_world_input_for_ui(open: bool) -> void:
	if _party_manager != null and _party_manager.has_method("set_manual_skill_input_enabled"):
		_party_manager.set_manual_skill_input_enabled(not open)
	if _touch_controls != null:
		_touch_controls.set_controls_visible(not open)


func _on_main_menu_changed(opened: bool, tab: StringName) -> void:
	_set_world_input_for_ui(opened or (_task_drawer != null and _task_drawer.is_open()))
	main_menu_changed.emit(opened, tab)


func _on_task_drawer_changed(opened: bool) -> void:
	_set_world_input_for_ui(opened or (_main_menu != null and _main_menu.is_open()))


func _on_popup_exiting(popup: Control) -> void:
	_popup_stack.erase(popup)
	_set_world_input_for_ui(is_modal_open())


# ---- Debug ----

func toggle_debug_panel() -> void:
	if _debug_panel != null:
		_debug_panel.toggle_visible()


func set_debug_draw_flags(collision: bool, hurtbox: bool, hitbox: bool) -> void:
	DebugDraw.show_collision = collision
	DebugDraw.show_hurtbox = hurtbox
	DebugDraw.show_hitbox = hitbox


## 返回 ScreenLayer（z=20），供全屏特效等系统挂载不受相机影响的节点。
func get_screen_layer() -> CanvasLayer:
	return _screen_layer


# ---- 构建 ----

func _build_layers() -> void:
	_hud_layer = _make_layer("HUDLayer", 10)
	_screen_layer = _make_layer("ScreenLayer", 20)
	_popup_layer = _make_layer("PopupLayer", 30)
	_notification_layer = _make_layer("NotificationLayer", 40)
	_debug_layer = _make_layer("DebugLayer", 100)
	add_child(_hud_layer)
	add_child(_screen_layer)
	add_child(_popup_layer)
	add_child(_notification_layer)
	add_child(_debug_layer)


func _make_layer(name: String, layer_num: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = name
	layer.layer = layer_num
	return layer


func _build_content() -> void:
	# HUD
	_hud = preload("res://scripts/ui/battle_hud.gd").new()
	_hud.name = "BattleHud"
	_hud.theme = skin.theme
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.ui_root = self
	_hud_layer.add_child(_hud)
	_interaction_prompt = Label.new()
	_interaction_prompt.name = "InteractionPrompt"
	_interaction_prompt.anchor_left = 0.5
	_interaction_prompt.anchor_top = 0.72
	_interaction_prompt.anchor_right = 0.5
	_interaction_prompt.anchor_bottom = 0.72
	_interaction_prompt.offset_left = -180
	_interaction_prompt.offset_top = -24
	_interaction_prompt.offset_right = 180
	_interaction_prompt.offset_bottom = 24
	_interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interaction_prompt.add_theme_font_size_override("font_size", 18)
	_interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_interaction_prompt.add_theme_constant_override("outline_size", 6)
	_interaction_prompt.visible = false
	_hud_layer.add_child(_interaction_prompt)

	# 主菜单
	_main_menu = preload("res://scripts/ui/main_menu.gd").new()
	_main_menu.name = "MainMenu"
	_main_menu.theme = skin.theme
	_main_menu.skin = skin
	_main_menu.ui_root = self
	_main_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_menu.visible = false
	_main_menu.menu_changed.connect(_on_main_menu_changed)
	_screen_layer.add_child(_main_menu)

	# 任务抽屉
	_task_drawer = preload("res://scripts/ui/task_drawer.gd").new()
	_task_drawer.name = "TaskDrawer"
	_task_drawer.theme = skin.theme
	_task_drawer.skin = skin
	_task_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_task_drawer.visible = false
	_task_drawer.drawer_changed.connect(_on_task_drawer_changed)
	_screen_layer.add_child(_task_drawer)

	_dialogue_panel = preload("res://scripts/ui/dialogue_panel.gd").new()
	_dialogue_panel.name = "DialoguePanel"
	_dialogue_panel.theme = skin.theme
	_dialogue_panel.visible = false
	_popup_layer.add_child(_dialogue_panel)

	# Debug 面板
	_debug_panel = preload("res://scripts/ui/debug_panel.gd").new()
	_debug_panel.name = "DebugPanel"
	_debug_panel.theme = skin.theme
	_debug_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_panel.visible = false
	_debug_layer.add_child(_debug_panel)

	# 主界面 UI（资源验证）
	_main_ui = preload("res://scripts/ui/main_ui.gd").new()
	_main_ui.name = "MainUI"
	_main_ui.theme = skin.theme
	_main_ui.ui_root = self
	_main_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_ui.visible = false
	_screen_layer.add_child(_main_ui)

	# 触屏控件（CanvasLayer，layer=15）
	_touch_controls = TouchControls.new()
	_touch_controls.name = "TouchControls"
	_touch_controls.interact_pressed.connect(func(): interact_requested.emit())
	add_child(_touch_controls)

	_notification_label = Label.new()
	_notification_label.name = "NpcNotification"
	_notification_label.anchor_left = 0.5
	_notification_label.anchor_right = 0.5
	_notification_label.offset_left = -260
	_notification_label.offset_top = 54
	_notification_label.offset_right = 260
	_notification_label.offset_bottom = 96
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.add_theme_font_size_override("font_size", 18)
	_notification_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_notification_label.add_theme_constant_override("outline_size", 5)
	_notification_label.visible = false
	_notification_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_notification_layer.add_child(_notification_label)


func _connect_npc_services() -> void:
	if GameRegistry.dialogue_service != null:
		if not GameRegistry.dialogue_service.dialogue_started.is_connected(_on_dialogue_started):
			GameRegistry.dialogue_service.dialogue_started.connect(_on_dialogue_started)
		if not GameRegistry.dialogue_service.node_changed.is_connected(_on_dialogue_node_changed):
			GameRegistry.dialogue_service.node_changed.connect(_on_dialogue_node_changed)
		if not GameRegistry.dialogue_service.dialogue_finished.is_connected(_on_dialogue_finished):
			GameRegistry.dialogue_service.dialogue_finished.connect(_on_dialogue_finished)
	if GameRegistry.quest_service != null and not GameRegistry.quest_service.notification_requested.is_connected(_show_notification):
		GameRegistry.quest_service.notification_requested.connect(_show_notification)


func _on_dialogue_started(_npc_id: int) -> void:
	set_interaction_target(null)
	_dialogue_previous_pause = get_tree().paused
	show_popup(_dialogue_panel)
	get_tree().paused = true


func _on_dialogue_node_changed(node: Dictionary) -> void:
	var npc: Dictionary = GameRegistry.npc_config.get_npc(GameRegistry.dialogue_service.current_npc_id)
	_dialogue_panel.show_node(node, npc)


func _on_dialogue_finished(_npc_id: int, _completed: bool) -> void:
	close_popup(_dialogue_panel)
	get_tree().paused = _dialogue_previous_pause


func _show_notification(text: String) -> void:
	if _notification_label == null:
		return
	_notification_label.text = text
	_notification_label.visible = true
	var expected := text
	get_tree().create_timer(2.5, true).timeout.connect(func():
		if is_instance_valid(_notification_label) and _notification_label.text == expected:
			_notification_label.visible = false
	)
