class_name UISkin
extends Resource
## 统一 UI 皮肤资源：持有共享 Theme 和语义化 Icon 映射。
## 第一阶段使用低存在感的 StyleBoxFlat 和占位 Icon 验证布局。
## 切图到位后只需替换此资源和边距配置，不修改业务页面。

@export var theme: Theme:
	set(value):
		theme = value
		emit_changed()

@export var icons: Dictionary = {}:
	set(value):
		icons = value
		emit_changed()


func _init() -> void:
	if theme == null:
		theme = _build_default_theme()
	if icons.is_empty():
		icons = _build_default_icons()


## 按语义名称获取 Icon，不存在则返回 null。
func get_icon(name: StringName) -> Texture2D:
	var value: Variant = icons.get(name, null)
	if value is Texture2D:
		return value
	return null


## 检查语义 Icon 是否存在。
func has_icon(name: StringName) -> bool:
	var value: Variant = icons.get(name, null)
	return value is Texture2D and is_instance_valid(value)


static func _build_default_theme() -> Theme:
	var t := Theme.new()

	# ---- 通用字体大小 ----
	t.set_font_size("font_size", "Label", 14)
	t.set_font_size("font_size", "Button", 14)
	t.set_font_size("font_size", "LineEdit", 14)

	# ---- 窗口背景 (Window) ----
	t.set_stylebox("panel", "Window", _flat(Color(0.18, 0.12, 0.06, 0.94), Color(0.62, 0.44, 0.18), 3, 6, 6))
	t.set_stylebox("panel", "Panel", _flat(Color(0.14, 0.09, 0.04, 0.90), Color(0.50, 0.34, 0.14), 2, 4, 4))

	# ---- HUD 卡片 ----
	t.set_stylebox("panel", "HUDCard", _flat(Color(0.16, 0.09, 0.04, 0.88), Color(0.58, 0.40, 0.16), 2, 4, 4))
	t.set_stylebox("panel", "HUDCardSmall", _flat(Color(0.14, 0.08, 0.03, 0.82), Color(0.46, 0.32, 0.14), 1, 3, 3))
	t.set_stylebox("panel", "HUDStat", _flat(Color(0.12, 0.07, 0.03, 0.92), Color(0.48, 0.32, 0.12), 1, 3, 3))

	# ---- 按钮 ----
	t.set_stylebox("normal", "HUDButton", _flat(Color(0.30, 0.18, 0.07, 0.92), Color(0.62, 0.44, 0.18), 2, 5, 5))
	t.set_stylebox("hover", "HUDButton", _flat(Color(0.40, 0.24, 0.09, 0.96), Color(0.80, 0.56, 0.24), 2, 5, 5))
	t.set_stylebox("pressed", "HUDButton", _flat(Color(0.22, 0.14, 0.06, 0.96), Color(0.50, 0.34, 0.14), 2, 5, 5))
	t.set_stylebox("disabled", "HUDButton", _flat(Color(0.14, 0.10, 0.06, 0.80), Color(0.30, 0.22, 0.14), 1, 5, 5))

	t.set_stylebox("normal", "TabButton", _flat(Color(0.20, 0.13, 0.05, 0.90), Color(0.50, 0.34, 0.14), 2, 6, 6))
	t.set_stylebox("hover", "TabButton", _flat(Color(0.30, 0.18, 0.07, 0.94), Color(0.70, 0.48, 0.20), 2, 6, 6))
	t.set_stylebox("pressed", "TabButton", _flat(Color(0.34, 0.21, 0.08, 0.96), Color(0.86, 0.60, 0.26), 2, 6, 6))
	t.set_stylebox("focus", "TabButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))

	t.set_stylebox("normal", "ItemSlot", _flat(Color(0.16, 0.10, 0.04, 0.90), Color(0.44, 0.30, 0.12), 2, 4, 4))
	t.set_stylebox("hover", "ItemSlot", _flat(Color(0.24, 0.15, 0.06, 0.94), Color(0.68, 0.46, 0.18), 2, 4, 4))
	t.set_stylebox("pressed", "ItemSlot", _flat(Color(0.28, 0.17, 0.07, 0.96), Color(0.86, 0.60, 0.24), 2, 4, 4))
	t.set_stylebox("disabled", "ItemSlot", _flat(Color(0.10, 0.07, 0.03, 0.80), Color(0.24, 0.18, 0.10), 1, 4, 4))

	t.set_stylebox("normal", "DangerButton", _flat(Color(0.40, 0.12, 0.08, 0.92), Color(0.80, 0.28, 0.18), 2, 5, 5))
	t.set_stylebox("hover", "DangerButton", _flat(Color(0.52, 0.16, 0.10, 0.96), Color(0.92, 0.38, 0.22), 2, 5, 5))
	t.set_stylebox("pressed", "DangerButton", _flat(Color(0.32, 0.10, 0.06, 0.96), Color(0.66, 0.22, 0.14), 2, 5, 5))

	# ---- 弹窗 ----
	t.set_stylebox("panel", "Popup", _flat(Color(0.14, 0.09, 0.04, 0.97), Color(0.74, 0.52, 0.20), 3, 6, 6))
	t.set_stylebox("panel", "Tooltip", _flat(Color(0.08, 0.05, 0.02, 0.96), Color(0.68, 0.46, 0.18), 2, 4, 4))

	# ---- 进度条 ----
	t.set_stylebox("background", "HUDBar", _flat(Color(0.10, 0.06, 0.03), Color(0.30, 0.20, 0.08), 1, 3, 3))
	t.set_stylebox("fill", "HUDBar", _flat(Color(0.62, 0.16, 0.12), Color.TRANSPARENT, 0, 3, 3))

	# ---- 标签颜色 ----
	t.set_color("font_color", "HUDTitle", Color(1.0, 0.86, 0.46))
	t.set_color("font_color", "HUDValue", Color(0.94, 0.92, 0.78))
	t.set_color("font_color", "HUDMuted", Color(0.72, 0.62, 0.42))
	t.set_color("font_color", "Window", Color(1.0, 0.86, 0.46))
	t.set_color("font_color", "Label", Color(0.92, 0.88, 0.74))

	# ---- 分隔线 ----
	t.set_stylebox("separator", "HSeparator", _flat(Color(0.40, 0.28, 0.12, 0.60), Color.TRANSPARENT, 0, 0, 0))
	t.set_constant("separation", "HSeparator", 6)

	return t


static func _build_default_icons() -> Dictionary:
	# 第一阶段没有真实 Icon 资源，映射全部为 null。
	# 页面通过 has_icon 判断是否显示 Icon，否则使用文字。
	# 切图到位后在此填入 Texture2D 引用或 AtlasTexture。
	return {
		&"inventory": null,
		&"task": null,
		&"close": null,
		&"character": null,
		&"equipment": null,
		&"skills": null,
		&"weapon": null,
		&"armor": null,
		&"necklace": null,
		&"ring": null,
		&"boots": null,
		&"relic": null,
		&"mount": null,
		&"artifact": null,
		&"skill_locked": null,
		&"skill_ready": null,
		&"skill_cooldown": null,
		&"arrow_right": null,
		&"arrow_left": null,
	}


static func _flat(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_w
	s.border_width_top = border_w
	s.border_width_right = border_w
	s.border_width_bottom = border_w
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = margin
	s.content_margin_top = margin
	s.content_margin_right = margin
	s.content_margin_bottom = margin
	return s
