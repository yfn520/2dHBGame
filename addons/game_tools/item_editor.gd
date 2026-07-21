@tool
extends Window

## 物品编辑器。可视化编辑 res://data/items.json。
## 复用 buff_editor.gd 的成熟模式：左列表 + 可拖动分隔条 + 右表单 + 底部保存。
## 支持新增/删除/编辑物品，ID 段 100001-199999。
## stats 暴露运行时支持的全部 22 个字段（base_combat_stats.gd:73-96），
## 配合属性上限钳制（99-111）做软约束，保存时只存非零值。

const CONFIG_PATH := "res://data/items.json"

# type 字段中文映射（来自 main_menu.gd:18-22，去掉 "all"）
const TYPE_OPTIONS := {
	"weapon": "武器", "armor": "护甲", "necklace": "项链", "ring": "戒指",
	"boots": "靴子", "relic": "圣物", "mount": "坐骑", "artifact": "神器",
	"consumable": "药水", "material": "材料",
}

# stats 字段配置：字段名 -> [中文label, min, max, step, is_int]
# 运行时支持的 22 个字段（base_combat_stats.gd:73-96），含属性上限钳制（99-111）
const STATS_FIELDS := {
	"max_hp": ["最大生命值", 0.0, 99999.0, 1.0, true],
	"attack": ["攻击力", 0.0, 9999.0, 1.0, true],
	"defense": ["防御力", 0.0, 9999.0, 1.0, true],
	"move_speed": ["移动速度", 0.0, 9999.0, 1.0, false],
	"crit_rate": ["暴击率", 0.0, 0.75, 0.01, false],
	"crit_damage": ["暴击伤害", 0.0, 2.5, 0.01, false],
	"attack_speed": ["攻击速度", 0.0, 2.5, 0.01, false],
	"magic_resist": ["魔法抗性", 0.0, 9999.0, 1.0, true],
	"block_rate": ["格挡率", 0.0, 0.6, 0.01, false],
	"dodge_rate": ["闪避率", 0.0, 0.35, 0.01, false],
	"status_resist": ["异常抗性", 0.0, 1.0, 0.01, false],
	"status_intensity": ["异常强度", 0.0, 2.0, 0.01, false],
	"skill_haste": ["技能急速", 0.0, 10.0, 0.01, false],
	"armor_pen_percent": ["护甲穿透%", 0.0, 0.5, 0.01, false],
	"armor_pen_flat": ["护甲穿透", 0.0, 9999.0, 1.0, true],
	"magic_pen_percent": ["法术穿透%", 0.0, 0.5, 0.01, false],
	"magic_pen_flat": ["法术穿透", 0.0, 9999.0, 1.0, true],
	"heal_bonus": ["治疗加成", 0.0, 10.0, 0.01, false],
	"shield_bonus": ["护盾加成", 0.0, 10.0, 0.01, false],
	"heal_received": ["受疗加成", -0.8, 1.0, 0.01, false],
	"lifesteal": ["生命汲取", 0.0, 0.2, 0.01, false],
	"reflect_rate": ["反伤率", 0.0, 0.5, 0.01, false],
}

const ID_MIN := 100001
const ID_MAX := 199999

# 数据缓存
var _items: Dictionary = {}   # int id -> dict
var _selected_id: int = 0
var _loading := false

# UI 控件引用
var _item_list: ItemList
var _name_edit: LineEdit
var _type_option: OptionButton
var _stackable_check: CheckBox
var _max_count_spin: SpinBox
var _heal_amount_spin: SpinBox
var _icon_edit: LineEdit
var _icon_preview: TextureRect
var _desc_edit: TextEdit
var _stats_spins: Dictionary = {}   # field_name -> SpinBox
var _status_label: Label

# 左右分隔拖动条
var _left_panel: VBoxContainer
var _divider: Control
var _dragging := false
const _LEFT_MIN_WIDTH := 150.0
const _LEFT_MAX_WIDTH := 560.0


func _ready() -> void:
	title = "物品编辑器"
	size = Vector2i(1100, 760)
	close_requested.connect(hide)
	_load_config()
	_build_layout()
	_refresh_item_list()
	if _selected_id > 0:
		_show_item_details(_selected_id)


func open_editor() -> void:
	_load_config()
	_refresh_item_list()
	if _selected_id > 0:
		_show_item_details(_selected_id)
	popup_centered()


# ---- 数据加载 ----

func _load_config() -> void:
	_items.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data := json.data as Dictionary
	for id_str in data:
		var item_id := int(id_str)
		_items[item_id] = (data[id_str] as Dictionary).duplicate(true)
	# 默认选第一个
	if _items.size() > 0:
		var ids := _items.keys()
		ids.sort()
		_selected_id = ids[0]


# ---- 布局构建 ----

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()
	# 整体竖向: 主内容区 + 底部状态栏
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 主内容区（左列表 + 右表单）
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)

	# 左侧物品列表
	_left_panel = VBoxContainer.new()
	_left_panel.custom_minimum_size = Vector2(240, 0)
	_left_panel.add_theme_constant_override("separation", 4)
	main.add_child(_left_panel)

	var list_label := Label.new()
	list_label.text = "物品列表"
	_left_panel.add_child(list_label)

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	_left_panel.add_child(_item_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	_left_panel.add_child(btn_row)

	var add_btn := Button.new()
	add_btn.text = "新增"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_add_item)
	btn_row.add_child(add_btn)

	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.pressed.connect(_on_delete_item)
	btn_row.add_child(del_btn)

	var tip_label := Label.new()
	tip_label.text = "ID 段 100001-199999\nExcel 转换会覆盖 icon 和扩展 stats"
	tip_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	tip_label.add_theme_font_size_override("font_size", 11)
	_left_panel.add_child(tip_label)

	# 可拖动分隔条
	_divider = Panel.new()
	_divider.custom_minimum_size = Vector2(6, 0)
	_divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_divider.set_default_cursor_shape(Control.CURSOR_HSIZE)
	_divider.gui_input.connect(_on_divider_gui_input)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.5, 0.5, 0.5, 0.35)
	sep_style.set_content_margin_all(0)
	_divider.add_theme_stylebox_override("panel", sep_style)
	main.add_child(_divider)

	# 右侧表单
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	main.add_child(right)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	# 保存 content 引用以便 _show_item_details 清空重建
	_content_ref = content

	# 底部状态 + 保存
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status_label)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(100, 32)
	save_btn.pressed.connect(_on_save)
	bottom.add_child(save_btn)


var _content_ref: VBoxContainer


# ---- 左右分隔条拖动 ----

func _on_divider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var w: float = _left_panel.size.x + event.relative.x
		w = clampf(w, _LEFT_MIN_WIDTH, _LEFT_MAX_WIDTH)
		_left_panel.custom_minimum_size.x = w


# ---- 列表刷新与选中 ----

func _refresh_item_list() -> void:
	_item_list.clear()
	var ids := _items.keys()
	ids.sort()
	for id in ids:
		var item: Dictionary = _items[id]
		var type_key: String = String(item.get("type", ""))
		var type_label: String = String(TYPE_OPTIONS.get(type_key, type_key))
		var name_str: String = String(item.get("name", ""))
		_item_list.add_item("%d %s %s" % [id, type_label, name_str])
		_item_list.set_item_metadata(_item_list.item_count - 1, id)
	# 选中当前 _selected_id
	if _selected_id > 0 and _items.has(_selected_id):
		for i in range(_item_list.item_count):
			if _item_list.get_item_metadata(i) == _selected_id:
				_item_list.select(i)
				break


func _on_item_selected(idx: int) -> void:
	if idx < 0 or idx >= _item_list.item_count:
		return
	var id = _item_list.get_item_metadata(idx)
	if id == null:
		return
	_selected_id = int(id)
	_show_item_details(_selected_id)


# ---- 表单构建 ----

func _show_item_details(item_id: int) -> void:
	# 清空旧表单
	if _content_ref == null:
		return
	for child in _content_ref.get_children():
		child.queue_free()
	# 重置控件引用
	_name_edit = null
	_type_option = null
	_stackable_check = null
	_max_count_spin = null
	_heal_amount_spin = null
	_icon_edit = null
	_icon_preview = null
	_desc_edit = null
	_stats_spins.clear()

	if not _items.has(item_id):
		var empty := Label.new()
		empty.text = "请从左侧选择一个物品"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_content_ref.add_child(empty)
		return

	_loading = true
	var data: Dictionary = _items[item_id]

	# 1. 基本信息
	var info_grid := _make_grid(_content_ref, "基本信息（ID 只读，其余可编辑）")
	# ID 只读
	_add_grid_readonly(info_grid, "ID（物品唯一标识，100001-199999）", "自动分配，只读", str(item_id))
	_name_edit = _add_grid_edit(info_grid, "名称 name（物品显示名）", "物品显示名", [])
	_name_edit.text = String(data.get("name", ""))
	_name_edit.text_changed.connect(_on_field_changed.bind("name"))

	_type_option = _add_grid_option(info_grid, "类型 type（决定装备槽位）", "weapon→weapon槽, consumable/material→不可装备", TYPE_OPTIONS)
	var current_type: String = String(data.get("type", "weapon"))
	for i in range(_type_option.item_count):
		if String(_type_option.get_item_metadata(i)) == current_type:
			_type_option.select(i)
			break
	_type_option.item_selected.connect(_on_type_changed)

	# stackable 单独一行
	var stack_row := HBoxContainer.new()
	stack_row.add_theme_constant_override("separation", 8)
	_content_ref.add_child(stack_row)
	_stackable_check = CheckBox.new()
	_stackable_check.text = "可堆叠 stackable（药水/材料通常可堆叠，装备不可）"
	_stackable_check.tooltip_text = "是否可堆叠"
	_stackable_check.set_pressed_no_signal(bool(data.get("stackable", false)))
	_stackable_check.toggled.connect(_on_stackable_toggled)
	stack_row.add_child(_stackable_check)

	# 继续基本信息 grid
	var info_grid2 := _make_grid(_content_ref, "")
	_max_count_spin = _add_grid_spin(info_grid2, "最大堆叠数 max_count（stackable=true 时的最大堆叠数，装备通常为 1）", "stackable=true 时的最大堆叠数", 1.0, 9999.0, 1.0)
	_max_count_spin.value = float(data.get("max_count", 1))
	_max_count_spin.value_changed.connect(_on_spin_changed.bind("max_count", true))

	_heal_amount_spin = _add_grid_spin(info_grid2, "治疗量 heal_amount（药水使用时恢复的血量，非药水填 0）", "药水使用时恢复的血量", 0.0, 99999.0, 1.0)
	_heal_amount_spin.value = float(data.get("heal_amount", 0))
	_heal_amount_spin.value_changed.connect(_on_spin_changed.bind("heal_amount", true))

	_icon_edit = _add_grid_edit(info_grid2, "图标路径 icon（如 res://assets/icons/items/100001.png）", "图标资源路径，当前可空", ["*.png ; PNG 图片", "*.jpg ; JPG 图片", "*.svg ; SVG 矢量图", "*.webp ; WebP 图片"])
	_icon_edit.text = String(data.get("icon", ""))
	_icon_edit.text_changed.connect(_on_icon_changed)

	# icon 预览（路径下方显示图标，直观些）
	_icon_preview = TextureRect.new()
	_icon_preview.custom_minimum_size = Vector2(72, 72)
	_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_content_ref.add_child(_icon_preview)

	# 2. 描述
	_add_section_header(_content_ref, "描述 description（物品介绍文本）")
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 60)
	_desc_edit.text = String(data.get("description", ""))
	_desc_edit.text_changed.connect(_on_desc_changed)
	_content_ref.add_child(_desc_edit)

	# 3. stats 属性加成
	var stats_grid := _make_grid(_content_ref, "属性加成 stats（装备时累加到角色属性，只存非零值）")
	var stats: Dictionary = data.get("stats", {})
	for field in STATS_FIELDS:
		var cfg: Array = STATS_FIELDS[field]
		var label_text: String = String(cfg[0]) + " " + field
		var spin := _add_grid_spin(stats_grid, label_text, "装备时累加到角色属性，保存时只存非零值", float(cfg[1]), float(cfg[2]), float(cfg[3]))
		spin.value = float(stats.get(field, 0))
		spin.set_meta("is_int", bool(cfg[4]))
		_stats_spins[field] = spin
		spin.value_changed.connect(_on_stats_spin_changed.bind(field))

	_loading = false
	_refresh_icon_preview()


# ---- 事件回调 ----

func _on_field_changed(new_text: String, field: String) -> void:
	if _loading or not _items.has(_selected_id):
		return
	_items[_selected_id][field] = new_text
	_refresh_item_list()

func _on_icon_changed(new_text: String) -> void:
	if _loading or not _items.has(_selected_id):
		return
	_items[_selected_id]["icon"] = new_text
	_refresh_item_list()
	_refresh_icon_preview()

## 根据 _icon_edit.text 的路径加载图标并显示到 _icon_preview。
## 路径为空或资源不存在时清空预览。
func _refresh_icon_preview() -> void:
	if _icon_preview == null:
		return
	var path := ""
	if _icon_edit != null:
		path = _icon_edit.text.strip_edges()
	if path.is_empty():
		_icon_preview.texture = null
		return
	if not path.begins_with("res://"):
		_icon_preview.texture = null
		return
	if not ResourceLoader.exists(path):
		_icon_preview.texture = null
		return
	var tex := load(path) as Texture2D
	_icon_preview.texture = tex

func _on_type_changed(_idx: int) -> void:
	if _loading or not _items.has(_selected_id) or _type_option == null:
		return
	var type_key: String = String(_type_option.get_item_metadata(_type_option.selected))
	_items[_selected_id]["type"] = type_key
	_refresh_item_list()

func _on_stackable_toggled(pressed: bool) -> void:
	if _loading or not _items.has(_selected_id):
		return
	_items[_selected_id]["stackable"] = pressed

func _on_spin_changed(value: float, field: String, is_int: bool) -> void:
	if _loading or not _items.has(_selected_id):
		return
	_items[_selected_id][field] = int(value) if is_int else value

func _on_stats_spin_changed(value: float, field: String) -> void:
	if _loading or not _items.has(_selected_id):
		return
	var stats: Dictionary = _items[_selected_id].get("stats", {})
	var spin: SpinBox = _stats_spins.get(field)
	if spin != null and bool(spin.get_meta("is_int", false)):
		stats[field] = int(value)
	else:
		stats[field] = value
	_items[_selected_id]["stats"] = stats

func _on_desc_changed() -> void:
	if _loading or not _items.has(_selected_id) or _desc_edit == null:
		return
	_items[_selected_id]["description"] = _desc_edit.text


# ---- 新增/删除 ----

func _on_add_item() -> void:
	var max_id := ID_MIN - 1
	for id in _items:
		max_id = maxi(max_id, int(id))
	var new_id := max_id + 1
	if new_id > ID_MAX:
		_status_label.text = "物品 ID 段已满（%d-%d）" % [ID_MIN, ID_MAX]
		return
	_items[new_id] = {
		"name": "新物品",
		"type": "weapon",
		"description": "",
		"stackable": false,
		"max_count": 1,
		"heal_amount": 0,
		"stats": {},
		"icon": "",
	}
	_selected_id = new_id
	_refresh_item_list()
	_show_item_details(new_id)
	_status_label.text = "新增物品 ID %d（需点保存写入 JSON）" % new_id


func _on_delete_item() -> void:
	if not _items.has(_selected_id):
		return
	var item_name: String = String(_items[_selected_id].get("name", ""))
	# 简单确认对话框
	var dialog := ConfirmationDialog.new()
	dialog.title = "删除物品"
	dialog.dialog_text = "确认删除物品 %d %s ？（需点保存写入 JSON）" % [_selected_id, item_name]
	add_child(dialog)
	dialog.confirmed.connect(func():
		_items.erase(_selected_id)
		_selected_id = 0
		if _items.size() > 0:
			var ids := _items.keys()
			ids.sort()
			_selected_id = ids[0]
		_refresh_item_list()
		if _selected_id > 0:
			_show_item_details(_selected_id)
		else:
			_show_item_details(0)
		_status_label.text = "已删除（需点保存写入 JSON）"
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered(Vector2i(360, 120))


# ---- 保存逻辑 ----

func _on_save() -> void:
	# 收集当前编辑物品的改动到 _items（防止最后编辑的未保存）
	if not _loading and _selected_id > 0 and _items.has(_selected_id):
		_collect_current_item_changes(_selected_id)

	# 按 id 升序重建字典，stats 只存非零值
	var sorted_ids: Array = _items.keys()
	sorted_ids.sort()
	var data: Dictionary = {}
	for item_id in sorted_ids:
		var item: Dictionary = _items[item_id]
		# 清理 stats 非零值
		var clean_stats: Dictionary = {}
		var raw_stats: Dictionary = item.get("stats", {})
		for field in raw_stats:
			var val = raw_stats[field]
			if float(val) != 0.0:
				clean_stats[field] = val
		item["stats"] = clean_stats
		data[str(item_id)] = item

	# 写文件
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		_status_label.text = "写入失败: " + CONFIG_PATH
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()

	# 重载运行时配置（编辑器模式下 GameRegistry 可能未运行，需判空）
	_reload_item_config()

	_status_label.text = "已保存 %d 个物品" % data.size()


func _collect_current_item_changes(item_id: int) -> void:
	if not _items.has(item_id):
		return
	var data: Dictionary = _items[item_id]
	if _name_edit != null:
		data["name"] = _name_edit.text
	if _type_option != null:
		data["type"] = String(_type_option.get_item_metadata(_type_option.selected))
	if _stackable_check != null:
		data["stackable"] = _stackable_check.is_pressed()
	if _max_count_spin != null:
		data["max_count"] = int(_max_count_spin.value)
	if _heal_amount_spin != null:
		data["heal_amount"] = int(_heal_amount_spin.value)
	if _icon_edit != null:
		data["icon"] = _icon_edit.text
	if _desc_edit != null:
		data["description"] = _desc_edit.text
	# stats
	var stats: Dictionary = data.get("stats", {})
	for field in _stats_spins:
		var spin: SpinBox = _stats_spins[field]
		if spin == null:
			continue
		var is_int: bool = bool(spin.get_meta("is_int", false))
		stats[field] = int(spin.value) if is_int else spin.value
	data["stats"] = stats


func _reload_item_config() -> void:
	if Engine.is_editor_hint():
		# 编辑器模式下 GameRegistry 可能未运行，尝试通过节点树查找
		var root := Engine.get_main_loop() as SceneTree
		if root == null:
			return
		var reg = root.root.get_node_or_null("/root/GameRegistry")
		if reg == null:
			return
		var cfg = reg.get("item_config") if reg.get("item_config") != null else null
		if cfg != null and cfg.has_method("load_config"):
			cfg._loaded = false
			cfg.load_config()
	else:
		var reg = Engine.get_singleton("GameRegistry") if Engine.has_singleton("GameRegistry") else null
		if reg == null:
			return
		var cfg = reg.get("item_config") if reg.get("item_config") != null else null
		if cfg != null and cfg.has_method("load_config"):
			cfg._loaded = false
			cfg.load_config()


# ---- 辅助函数 ----

func _add_section_header(parent: Node, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	parent.add_child(header)


func _make_grid(parent: Node, title: String) -> GridContainer:
	if not title.is_empty():
		_add_section_header(parent, title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _add_grid_readonly(parent: GridContainer, label_text: String, tooltip: String, value: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	var val_label := Label.new()
	val_label.text = value
	val_label.tooltip_text = tooltip
	val_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(val_label)


func _add_grid_edit(parent: GridContainer, label_text: String, tooltip: String, browse_filters: PackedStringArray) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.tooltip_text = tooltip
	edit.custom_minimum_size = Vector2(220, 0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not browse_filters.is_empty():
		var hbox := HBoxContainer.new()
		hbox.add_child(edit)
		var btn := Button.new()
		btn.text = "浏览"
		btn.tooltip_text = "浏览资源"
		btn.pressed.connect(_on_browse_resource.bind(edit, browse_filters))
		hbox.add_child(btn)
		parent.add_child(hbox)
	else:
		parent.add_child(edit)
	return edit


func _add_grid_spin(parent: GridContainer, label_text: String, tooltip: String, min_v: float, max_v: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.tooltip_text = tooltip
	spin.custom_minimum_size = Vector2(140, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.allow_lesser = true
	spin.allow_greater = true
	parent.add_child(spin)
	return spin


func _add_grid_option(parent: GridContainer, label_text: String, tooltip: String, options_dict: Dictionary) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	var option := OptionButton.new()
	option.tooltip_text = tooltip
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx := 0
	for key in options_dict:
		option.add_item("%s (%s)" % [String(options_dict[key]), String(key)])
		option.set_item_metadata(idx, key)
		idx += 1
	parent.add_child(option)
	return option


func _on_browse_resource(edit: LineEdit, filters: PackedStringArray) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	for f in filters:
		dialog.add_filter(f.get_slice(" ; ", 0), f.get_slice(" ; ", 1))
	dialog.current_path = edit.text if not edit.text.is_empty() else "res://"
	dialog.file_selected.connect(func(path: String):
		edit.text = path
		# 程序化设置 text 不触发 text_changed，需手动 emit
		edit.emit_signal("text_changed", path)
		dialog.queue_free()
	)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))
