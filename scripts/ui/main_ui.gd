class_name MainUI
extends Control
## 主界面 UI：从 GameTool Godot UI 交互编排导出的 .tscn 实例化。
## 按 M 键打开（由 game_root 路由到 ui_root.toggle_main_ui）。
## 场景设计画布为 1920×1080，运行时等比缩放居中适配视口。
## 按钮通过 scene-unique names（%button_001 等）连接到 ui_root 的菜单开关。

const SCENE_PATH := "res://assets/ui/ui_main_lp.tscn"
const DESIGN_SIZE := Vector2(1920, 1080)

var ui_root: Node = null

var _scene_root: Control = null
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible and not _built:
		_build()
		_built = true


func _build() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[MainUI] 无法加载场景: %s" % SCENE_PATH)
		return
	_scene_root = packed.instantiate() as Control
	if _scene_root == null:
		push_warning("[MainUI] 场景根节点不是 Control")
		return
	add_child(_scene_root)
	_connect_buttons()
	get_viewport().size_changed.connect(_apply_design_scale)
	_apply_design_scale()


func _connect_buttons() -> void:
	if _scene_root == null or ui_root == null:
		return
	# 按钮命名对照（来自 .tscn）：
	# button_001=角色  button_002=背包  button_003=技能
	# button_004=任务  button_005=好友  button_006=商店
	# button_007=底图  button_009=设置
	_bind_button("button_001", Callable(self, "_on_character_button"))
	_bind_button("button_002", Callable(self, "_on_inventory_button"))
	_bind_button("button_003", Callable(self, "_on_skills_button"))
	_bind_button("button_004", Callable(self, "_on_task_button"))


func _bind_button(node_name: String, callback: Callable) -> void:
	var btn := _scene_root.get_node_or_null(NodePath("%" + node_name))
	if btn == null:
		return
	if btn is TextureButton:
		if not btn.pressed.is_connected(callback):
			btn.pressed.connect(callback)
	elif btn is Button:
		if not btn.pressed.is_connected(callback):
			btn.pressed.connect(callback)


func _on_character_button() -> void:
	if ui_root != null:
		ui_root.toggle_main_menu(ui_root.TAB_CHARACTER)

func _on_inventory_button() -> void:
	if ui_root != null:
		ui_root.toggle_main_menu(ui_root.TAB_INVENTORY)

func _on_skills_button() -> void:
	if ui_root != null:
		ui_root.toggle_main_menu(ui_root.TAB_SKILLS)

func _on_task_button() -> void:
	if ui_root != null:
		ui_root.toggle_task_drawer()


func _apply_design_scale() -> void:
	if _scene_root == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	# contain 模式：等比缩放并居中，保证 1920×1080 设计画布完整可见
	var scale_val: float = min(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	_scene_root.scale = Vector2(scale_val, scale_val)
	_scene_root.position = (vp - DESIGN_SIZE * scale_val) * 0.5
