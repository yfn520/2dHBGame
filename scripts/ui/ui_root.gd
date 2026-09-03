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

var _main_menu: MainMenu
var _task_drawer: TaskDrawer
var _quest_tracker: QuestTracker
var _debug_panel: DebugPanel
var _main_ui: Control
var _touch_controls: TouchControls
var _dialogue_panel: DialoguePanel
var _cinematic_player: CinematicPlayer
var _interaction_prompt: Label
var _coord_label: Label
var _interaction_target: Node2D
# 过场播放前主 HUD 的显隐状态，结束后恢复
var _hud_visible_before_cutscene := false
var _in_cutscene := false
var _notification_label: Label
var _dialogue_previous_pause := false

var _popup_stack: Array[Control] = []
var _tooltip: Control = null
var _party_manager: PartyManager
var _enemy_spawner: Node
var _backpack_ui: BackpackUI
var _map_panel: MapPanel


func _ready() -> void:
	skin = UISkin.new()
	# 加入 group，便于 combat_component 等系统在任意层级查找 UIRoot（避免依赖 tree.root 直接子节点）
	add_to_group("ui_root")
	_build_layers()
	_build_content()
	# 全屏过场视频播放器（kind="video" 时间轴片段）
	_cinematic_player = CinematicPlayer.new()
	_cinematic_player.finished.connect(_on_cinematic_finished)
	add_child(_cinematic_player)


## 初始化 UIRoot，由 GameRoot 调用。
func setup(party_manager: PartyManager, enemy_spawner: Node) -> void:
	_party_manager = party_manager
	_enemy_spawner = enemy_spawner
	if _main_menu != null:
		_main_menu.setup(party_manager)
	if _debug_panel != null:
		_debug_panel.setup(party_manager, enemy_spawner)
	if _task_drawer != null:
		_task_drawer.setup(GameRegistry.quest_service)
	if _quest_tracker != null:
		_quest_tracker.setup(GameRegistry.quest_service)
	if _main_ui != null and _main_ui.has_method("setup"):
		_main_ui.setup(party_manager, enemy_spawner)
	_connect_npc_services()


func set_interaction_target(target: Node2D) -> void:
	_interaction_target = target
	var available := is_instance_valid(target)
	if _interaction_prompt != null:
		_interaction_prompt.visible = available
		if available and target.has_method("get_interaction_prompt"):
			_interaction_prompt.text = target.get_interaction_prompt()
		elif available and target.has_method("get_display_name"):
			_interaction_prompt.text = "E  %s" % target.get_display_name()
		else:
			_interaction_prompt.text = ""
	if _touch_controls != null:
		_touch_controls.set_interact_available(available)


## 交互提示跟随目标 NPC 头顶，而非固定在屏幕中央。
func _process(_delta: float) -> void:
	if _coord_label != null and _coord_label.visible and _party_manager != null:
		var active := _party_manager.get_active_character()
		if active != null and is_instance_valid(active):
			_coord_label.text = "x: %.0f  y: %.0f" % [active.global_position.x, active.global_position.y]
	if _interaction_prompt == null or not _interaction_prompt.visible or not is_instance_valid(_interaction_target):
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var screen := cam.get_canvas_transform() * _interaction_target.global_position
	_interaction_prompt.position.x = screen.x - _interaction_prompt.size.x * 0.5
	_interaction_prompt.position.y = screen.y - 40.0


## 坐标显示开关（F3）
func toggle_coord_display() -> void:
	if _coord_label != null:
		_coord_label.visible = not _coord_label.visible


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


# ---- 背包界面（B 键弹出） ----

func toggle_backpack() -> void:
	if _backpack_ui == null:
		return
	_backpack_ui.toggle()
	_set_world_input_for_ui(_backpack_ui.visible)


func is_backpack_open() -> bool:
	return _backpack_ui != null and _backpack_ui.visible


# ---- 地图切换（测试） ----

func toggle_map_panel() -> void:
	if _map_panel == null:
		return
	_map_panel.toggle()
	_set_world_input_for_ui(_map_panel.is_open())


func close_map_panel() -> void:
	if _map_panel != null and _map_panel.is_open():
		_map_panel.close()
		_set_world_input_for_ui(is_modal_open())


func is_map_panel_open() -> bool:
	return _map_panel != null and _map_panel.is_open()


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


## 按优先级关闭最上层：弹窗 → 任务抽屉 → 主菜单 → 背包 → 主界面 UI。
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
	if _backpack_ui != null and _backpack_ui.is_open():
		_backpack_ui.close()
		_set_world_input_for_ui(false)
		return
	if is_map_panel_open():
		close_map_panel()
		return
	if _main_ui != null and _main_ui.visible:
		_main_ui.visible = false
		_set_world_input_for_ui(false)


func is_modal_open() -> bool:
	# 注意：常驻战斗 HUD（_main_ui）默认可见，不是模态层，不能计入阻塞，
	# 否则会一直阻断 NPC 交互（需按 ESC 关闭 HUD 才能触发对话）。
	# M 键切换主界面显隐时由 toggle_main_ui 单独用 _main_ui.visible 控制世界输入。
	return not _popup_stack.is_empty() or (_main_menu != null and _main_menu.is_open()) or (_task_drawer != null and _task_drawer.is_open()) or (_backpack_ui != null and _backpack_ui.visible) or is_map_panel_open()


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
	# 交互提示（HUDLayer）：锚点置 0，由 _process 按 NPC 头顶世界坐标定位。
	_interaction_prompt = Label.new()
	_interaction_prompt.name = "InteractionPrompt"
	_interaction_prompt.anchor_left = 0.0
	_interaction_prompt.anchor_top = 0.0
	_interaction_prompt.anchor_right = 0.0
	_interaction_prompt.anchor_bottom = 0.0
	_interaction_prompt.size = Vector2(360, 32)
	_interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interaction_prompt.add_theme_font_size_override("font_size", 18)
	_interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_interaction_prompt.add_theme_constant_override("outline_size", 6)
	_interaction_prompt.visible = false
	_hud_layer.add_child(_interaction_prompt)

	# 坐标显示（左下角，F3 切换）：供摆放/触发点调试核对
	_coord_label = Label.new()
	_coord_label.name = "CoordLabel"
	_coord_label.anchor_left = 0.0
	_coord_label.anchor_top = 1.0
	_coord_label.anchor_right = 0.0
	_coord_label.anchor_bottom = 1.0
	_coord_label.offset_left = 12
	_coord_label.offset_top = -32
	_coord_label.offset_right = 280
	_coord_label.offset_bottom = -8
	_coord_label.add_theme_font_size_override("font_size", 14)
	_coord_label.add_theme_color_override("font_color", Color("b8f3ff"))
	_coord_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_coord_label.add_theme_constant_override("outline_size", 4)
	_coord_label.visible = true
	_hud_layer.add_child(_coord_label)

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

	# 主界面 UI（资源验证）：常驻 HUD，替换原 BattleHud
	_main_ui = preload("res://scripts/ui/main_ui.gd").new()
	_main_ui.name = "MainUI"
	_main_ui.theme = skin.theme
	_main_ui.ui_root = self
	_main_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_ui.visible = true
	_hud_layer.add_child(_main_ui)

	# 常驻任务追踪面板：显示进行中任务及目标数量，不阻塞世界输入。
	_quest_tracker = preload("res://scripts/ui/quest_tracker.gd").new()
	_quest_tracker.name = "QuestTracker"
	_quest_tracker.theme = skin.theme
	_quest_tracker.visible = false
	_hud_layer.add_child(_quest_tracker)

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

	# 背包界面（B 键弹出）：从 UiInteractionComposer 导出的 backpack.tscn 实例化
	_backpack_ui = preload("res://scripts/ui/backpack_ui.gd").new()
	_backpack_ui.name = "BackpackUI"
	_backpack_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backpack_ui.visible = false
	_screen_layer.add_child(_backpack_ui)

	# 地图切换测试面板（F2 打开）
	_map_panel = preload("res://scripts/ui/map_panel.gd").new()
	_map_panel.name = "MapPanel"
	_map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_panel.visible = true
	_screen_layer.add_child(_map_panel)


func _connect_npc_services() -> void:
	if GameRegistry.dialogue_service != null:
		if not GameRegistry.dialogue_service.dialogue_started.is_connected(_on_dialogue_started):
			GameRegistry.dialogue_service.dialogue_started.connect(_on_dialogue_started)
		if not GameRegistry.dialogue_service.node_changed.is_connected(_on_dialogue_node_changed):
			GameRegistry.dialogue_service.node_changed.connect(_on_dialogue_node_changed)
		if not GameRegistry.dialogue_service.dialogue_finished.is_connected(_on_dialogue_finished):
			GameRegistry.dialogue_service.dialogue_finished.connect(_on_dialogue_finished)
		if not GameRegistry.dialogue_service.world_event_gate_changed.is_connected(_on_world_event_gate_changed):
			GameRegistry.dialogue_service.world_event_gate_changed.connect(_on_world_event_gate_changed)
		if not GameRegistry.dialogue_service.video_clip_started.is_connected(_on_cinematic_video_started):
			GameRegistry.dialogue_service.video_clip_started.connect(_on_cinematic_video_started)
	if GameRegistry.quest_service != null and not GameRegistry.quest_service.notification_requested.is_connected(_show_notification):
		GameRegistry.quest_service.notification_requested.connect(_show_notification)


func _on_dialogue_started(_npc_id: int) -> void:
	set_interaction_target(null)
	# 过场（开局选角）用纯黑背景；任务过场保持半透保留场景画面
	var cinematic: bool = GameRegistry.dialogue_service.is_cutscene()
	_dialogue_panel.set_cinematic(cinematic)
	# 过场（含任务过场）隐藏主 HUD（角色栏/技能栏/图标），避免画面错乱；普通对话保留
	_in_cutscene = GameRegistry.dialogue_service.is_auto_cutscene()
	if _in_cutscene and _main_ui != null and _main_ui.visible:
		_hud_visible_before_cutscene = true
		_main_ui.visible = false
	_dialogue_previous_pause = get_tree().paused
	show_popup(_dialogue_panel)
	get_tree().paused = true


func _on_dialogue_node_changed(node: Dictionary) -> void:
	var npc: Dictionary = GameRegistry.npc_config.get_npc(GameRegistry.dialogue_service.current_npc_id) as Dictionary
	# 头像由落表时就确定的 speaker_kind/speaker_id 直接决定；
	# 仅没有身份字段的旧数据才回退按名字解析
	node["portrait"] = _resolve_speaker_portrait(node, npc)
	_dialogue_panel.show_node(node, npc)


func _on_world_event_gate_changed(available: bool) -> void:
	if available:
		# 时间轴仍保持 active，但玩家需要回到场景中移动/战斗；对白框必须退出，不能挡住交互点。
		if _dialogue_panel != null:
			_dialogue_panel.set_waiting_for_world_event(true, "")
			if _popup_stack.has(_dialogue_panel):
				close_popup(_dialogue_panel)
			else:
				_dialogue_panel.visible = false
		if _in_cutscene and _main_ui != null:
			_main_ui.visible = true
		get_tree().paused = false
	elif GameRegistry.dialogue_service != null and GameRegistry.dialogue_service.is_active():
		# 事件完成后重新打开对白框，暂停场景并继续播放后续时间轴对白。
		if _dialogue_panel != null:
			show_popup(_dialogue_panel)
			_dialogue_panel.set_waiting_for_world_event(false, "")
		if _in_cutscene and _main_ui != null:
			_main_ui.visible = false
		get_tree().paused = true


const _HERO_SPEAKER_PORTRAIT_IDS := {"莱昂": 7001, "露娜": 7002, "米娅": 7003}


func _resolve_speaker_portrait(node: Dictionary, npc: Dictionary) -> String:
	match str(node.get("speaker_kind", "")):
		"protagonist":
			return _protagonist_portrait(npc)
		"hero":
			var hero_portrait := _character_portrait_path(int(node.get("speaker_id", 0)))
			return hero_portrait if not hero_portrait.is_empty() else str(npc.get("portrait", ""))
		"npc":
			# speaker_id=0 是未登记的群像角色，沿用当前交互 NPC 头像
			var speaker_npc: Dictionary = GameRegistry.npc_config.get_npc(int(node.get("speaker_id", 0))) as Dictionary
			var speaker_portrait := str(speaker_npc.get("portrait", ""))
			return speaker_portrait if not speaker_portrait.is_empty() else str(npc.get("portrait", ""))
		"narrator":
			# 旁白/过场没有说话人，不显示任何头像
			return ""
	return _legacy_resolve_speaker_portrait(str(node.get("speaker", "")).strip_edges(), npc)


func _protagonist_portrait(npc: Dictionary) -> String:
	var hero_id := 0
	if GameRegistry.quest_service != null and GameRegistry.quest_service.roster != null:
		var roster: CharacterRosterData = GameRegistry.quest_service.roster as CharacterRosterData
		hero_id = roster.get_protagonist_hero_id()
		# 存档尚未写入主角标记（如序章选角前）时，用当前操控角色兜底，
		# 否则会一路回退到当前 NPC 头像，出现主角说话却显示 NPC 脸的错位。
		if hero_id <= 0:
			hero_id = roster.active_character_id
		if hero_id <= 0:
			hero_id = CharacterRosterData.DEFAULT_CHARACTER_ID
	if hero_id > 0:
		var hero_portrait := _character_portrait_path(hero_id)
		if not hero_portrait.is_empty():
			return hero_portrait
	return str(npc.get("portrait", ""))


## 旧数据（无 speaker_kind 字段）兜底：按说话者名字解析。
## 主角/三英雄用角色头像，具名 NPC 用各自头像，旁白回退当前 NPC。
func _legacy_resolve_speaker_portrait(speaker: String, npc: Dictionary) -> String:
	if speaker.is_empty() or speaker == "旁白":
		return ""
	var hero_id := 0
	if speaker == "主角":
		if GameRegistry.quest_service != null and GameRegistry.quest_service.roster != null:
			var roster: CharacterRosterData = GameRegistry.quest_service.roster as CharacterRosterData
			hero_id = roster.get_protagonist_hero_id()
			# 存档尚未写入主角标记（如序章选角前）时，用当前操控角色兜底，
			# 否则会一路回退到当前 NPC 头像，出现主角说话却显示 NPC 脸的错位。
			if hero_id <= 0:
				hero_id = roster.active_character_id
			if hero_id <= 0:
				hero_id = CharacterRosterData.DEFAULT_CHARACTER_ID
	elif _HERO_SPEAKER_PORTRAIT_IDS.has(speaker):
		hero_id = int(_HERO_SPEAKER_PORTRAIT_IDS[speaker])
	if hero_id > 0:
		var hero_portrait := _character_portrait_path(hero_id)
		if not hero_portrait.is_empty():
			return hero_portrait
	if GameRegistry.npc_config != null:
		for npc_id in GameRegistry.npc_config.get_all_npcs():
			var entry: Dictionary = GameRegistry.npc_config.get_all_npcs()[npc_id]
			if str(entry.get("name", "")) == speaker and not str(entry.get("portrait", "")).is_empty():
				return str(entry.get("portrait", ""))
	return str(npc.get("portrait", ""))


func _character_portrait_path(character_id: int) -> String:
	if GameRegistry.character_config == null:
		return ""
	var config: Dictionary = GameRegistry.character_config.get_character(character_id)
	var cc_path := str(config.get("character_config", ""))
	if cc_path.is_empty() or not FileAccess.file_exists(cc_path):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(cc_path)) == OK and json.data is Dictionary:
		return str(json.data.get("portrait", ""))
	return ""


## kind="video" 片段开始：盖住对白面板，全屏播放过场演出（视频 / 图+文）
func _on_cinematic_video_started(clip: Dictionary) -> void:
	if _dialogue_panel != null:
		_dialogue_panel.visible = false
	if _cinematic_player != null:
		_cinematic_player.play_clip(clip)


## 过场视频播放完成/被跳过：恢复对白面板并推进时间轴
func _on_cinematic_finished() -> void:
	if _dialogue_panel != null:
		_dialogue_panel.visible = true
	if GameRegistry.dialogue_service != null:
		GameRegistry.dialogue_service.tl_video_finished()


func _on_dialogue_finished(_npc_id: int, _completed: bool) -> void:
	close_popup(_dialogue_panel)
	# 过场结束后恢复主 HUD 与电影遮罩状态
	if _in_cutscene:
		_in_cutscene = false
		if _hud_visible_before_cutscene and _main_ui != null:
			_main_ui.visible = true
		_hud_visible_before_cutscene = false
	get_tree().paused = _dialogue_previous_pause


## 公开的短暂提示（供未实现功能按钮等弹「功能开发中」提示）。
func show_notification(text: String) -> void:
	_show_notification(text)


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
