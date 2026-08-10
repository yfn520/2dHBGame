class_name EnemyHpBar
extends Control
## 怪物血条独立预设：可绑定一个敌人并显示其名字 + 血条 + 血值。
## 两种形态：完整（含名字，用于顶部中央）/ 紧凑（仅小血条，用于怪物头顶投影）。
## 由 MainUI 负责实例化与每帧定位（顶部中央锚定 / 世界投影）。

var _enemy: Node = null
var _compact := false

var _name_label: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"HUDCard"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.theme_type_variation = &"HUDTitle"
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	var bar_wrap := PanelContainer.new()
	bar_wrap.theme_type_variation = &"HUDStat"
	bar_wrap.custom_minimum_size = Vector2(200, 16)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_wrap)

	_hp_bar = ProgressBar.new()
	_hp_bar.theme_type_variation = &"HUDBar"
	_hp_bar.show_percentage = false
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_hp_bar)

	_hp_text = Label.new()
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.theme_type_variation = &"HUDValue"
	_hp_text.add_theme_font_size_override("font_size", 12)
	_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_hp_text)


## 绑定敌人；传 null 则清空并隐藏。
func set_enemy(enemy: Node) -> void:
	_enemy = enemy
	if _enemy == null or not is_instance_valid(_enemy):
		hide()
		return
	show()
	refresh()


## 切换紧凑形态（仅小血条，隐藏名字）。
func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if _name_label != null:
		_name_label.visible = not _compact
	if hp_bar_wrap() != null:
		hp_bar_wrap().custom_minimum_size = Vector2(120, 10) if _compact else Vector2(200, 16)


func hp_bar_wrap() -> PanelContainer:
	if _hp_bar == null:
		return null
	return _hp_bar.get_parent() as PanelContainer


## 返回预设内容实际尺寸（用于头顶血条在世界投影时居中/上移）。
func get_content_size() -> Vector2:
	if _panel != null:
		return _panel.size
	return Vector2.ZERO


func clear_enemy() -> void:
	_enemy = null
	hide()


func refresh() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	var stats = _enemy.get_combat_stats() if _enemy.has_method("get_combat_stats") else null
	if stats == null:
		return
	var hp := int(stats.hp)
	var max_hp := maxi(1, int(stats.max_hp))
	_hp_bar.max_value = max_hp
	_hp_bar.value = clampi(hp, 0, max_hp)
	_hp_text.text = "%d/%d" % [hp, max_hp]
	if not _compact and _name_label != null:
		_name_label.text = _enemy.get_enemy_name() if _enemy.has_method("get_enemy_name") else _enemy.name