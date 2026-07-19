class_name MainUI
extends Control
## 主界面 UI 资源验证场景：把 assets/UI/主界面/ 下 4 个模块的图标按区域平铺展示。
## 用于验证导出资源能正常加载、显示，并给用户一个直观的图标清单便于后续标注语义。
## 按 F8 切换显隐（由 game_root 路由到 ui_root.toggle_main_ui）。

var ui_root: Node = null

# 各模块配置：路径前缀、图标数量、展示尺寸
const _MODULES := [
	{"title": "顶部 UI（17 张 · 32x32）", "prefix": "res://assets/UI/主界面/顶部ui/godot/ui_assets/", "count": 17, "icon_size": 48, "columns": 8},
	{"title": "底部 UI（19 张 · 240x240）", "prefix": "res://assets/UI/主界面/底部ui/godot/ui_assets/", "count": 19, "icon_size": 64, "columns": 10},
	{"title": "聊天框（8 张 · 600x600）", "prefix": "res://assets/UI/主界面/聊天框/godot/ui_assets/", "count": 8, "icon_size": 96, "columns": 4},
	{"title": "任务（6 张 · 1220x1220）", "prefix": "res://assets/UI/主界面/任务/godot/ui_assets/", "count": 6, "icon_size": 160, "columns": 2},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()


## 构建布局：顶部状态栏 + 中间（左聊天框 + 右任务） + 底部技能栏。
## 4 个区域都是 Panel + 标题 + GridContainer，图标按编号顺序排列并标注编号。
## 内容总高度可能超过屏幕，外层包 ScrollContainer 避免底部技能栏被裁掉。
func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	margin.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	# 顶部状态栏（顶部ui）
	root.add_child(_build_module_panel(_MODULES[0]))

	# 中间区域：左聊天框 + 右任务
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	root.add_child(middle)
	# 左聊天框（expand_fill）
	var chat_panel := _build_module_panel(_MODULES[2])
	chat_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(chat_panel)
	# 右任务面板（固定宽度 360）
	var task_panel := _build_module_panel(_MODULES[3])
	task_panel.custom_minimum_size.x = 360.0
	middle.add_child(task_panel)

	# 底部技能栏（底部ui）
	root.add_child(_build_module_panel(_MODULES[1]))


## 为单个模块构建 Panel：标题 + GridContainer 平铺图标。
func _build_module_panel(cfg: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Panel"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)

	var title := Label.new()
	title.text = String(cfg.get("title", ""))
	title.theme_type_variation = &"HUDTitle"
	content.add_child(title)

	var grid := GridContainer.new()
	grid.columns = int(cfg.get("columns", 8))
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)

	var prefix := String(cfg.get("prefix", ""))
	var count := int(cfg.get("count", 0))
	var icon_size := float(cfg.get("icon_size", 48))
	for i in range(count):
		var icon := _load_icon(prefix, i + 1)
		grid.add_child(_make_icon_cell(icon, i + 1, icon_size))
	return panel


## 按编号加载图标 PNG。编号从 1 开始，文件名格式 001_icon_01.png。
func _load_icon(prefix: String, index: int) -> Texture2D:
	var num3 := "%03d" % index
	var num2 := "%02d" % index
	var path := "%s%s_icon_%s.png" % [prefix, num3, num2]
	if not ResourceLoader.exists(path):
		push_warning("[MainUI] 图标资源不存在: %s" % path)
		return null
	return load(path) as Texture2D


## 单个图标单元：TextureRect + 编号 Label，垂直排列。
func _make_icon_cell(texture: Texture2D, index: int, cell_size: float) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER

	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(cell_size, cell_size)
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(rect)

	var label := Label.new()
	label.text = "%03d" % index
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(label)
	return cell
