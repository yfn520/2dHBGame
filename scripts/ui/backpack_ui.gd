class_name BackpackUI
extends Control
## 背包界面：从 UiInteractionComposer 导出的 backpack.tscn 实例化。
## B 键弹出，ESC/B 关闭。包含角色精灵、装备槽、物品网格。
## 数据复用 GameRegistry.inventory_provider / equipment_data / item_config。

const SCENE_PATH := "res://assets/ui/backpack.tscn"
const DESIGN_SIZE := Vector2(760, 515)
# 拖拽滚动判定阈值（像素），超过此距离才视为拖拽而非点击
const DRAG_THRESHOLD := 5.0

# 显示分类 → 边框贴图；“任务”是独立 UI 分类，不参与装备品质排序
const QUALITY_FRAMES := {
	"普通": "res://assets/ui/item_frames/frame_normal.png",
	"优秀": "res://assets/ui/item_frames/frame_fine.png",
	"稀有": "res://assets/ui/item_frames/frame_rare.png",
	"史诗": "res://assets/ui/item_frames/frame_epic.png",
	"任务": "res://assets/ui/item_frames/frame_quest.png",
	"传说": "res://assets/ui/item_frames/frame_legend.png",
	"神话": "res://assets/ui/item_frames/frame_myth.png",
	"星辉": "res://assets/ui/item_frames/frame_starlight.png",
	"深渊": "res://assets/ui/item_frames/frame_abyss.png",
	"神圣": "res://assets/ui/item_frames/frame_holy.png",
}
const DEFAULT_FRAME_KEY := "普通"

# 12 个装备槽 UI 节点名 → 装备类型映射
const EQUIP_SLOT_MAP := [
	{slot = "hands", texture = "dynamic_image_001", button = "dynamic_image_001_click"},
	{slot = "waist", texture = "dynamic_image_001_2", button = "dynamic_image_001_2_click"},
	{slot = "ring_left", texture = "dynamic_image_001_2_2", button = "dynamic_image_001_2_2_click"},
	{slot = "ring_right", texture = "dynamic_image_001_2_2_2", button = "dynamic_image_001_2_2_2_click"},
	{slot = "accessory", texture = "dynamic_image_001_2_2_2_2", button = "dynamic_image_001_2_2_2_2_click"},
	{slot = "head", texture = "dynamic_image_001_3", button = "dynamic_image_001_3_click"},
	{slot = "necklace", texture = "dynamic_image_001_2_3", button = "dynamic_image_001_2_3_click"},
	{slot = "body", texture = "dynamic_image_001_2_2_3", button = "dynamic_image_001_2_2_3_click"},
	{slot = "legs", texture = "dynamic_image_001_2_2_2_3", button = "dynamic_image_001_2_2_2_3_click"},
	{slot = "boots", texture = "dynamic_image_001_2_2_2_2_2", button = "dynamic_image_001_2_2_2_2_2_click"},
	{slot = "weapon", texture = "equipment_weapon", button = "equipment_weapon_click"},
	{slot = "offhand", texture = "equipment_offhand", button = "equipment_offhand_click"},
]

var _scene_root: Control = null
var _sprite: AnimatedSprite2D = null
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _sprite_base_scale: Vector2 = Vector2.ONE
var _grid: GridContainer = null
var _scroll_container: ScrollContainer = null
var _item_buttons: Array[TextureButton] = []
var _item_icons: Array[TextureRect] = []
var _default_item_texture: Texture2D = null
# 品质边框贴图缓存：品质名 → Texture2D
var _frame_texture_cache: Dictionary = {}
# 物品详情弹窗
var _detail_popup: PanelContainer = null
var _detail_icon: TextureRect = null
var _detail_icon_frame: TextureRect = null
var _detail_name: Label = null
var _detail_sub: Label = null
var _detail_desc: Label = null
var _detail_equip_btn: Button = null
var _detail_discard_btn: Button = null
var _selected_uid: int = 0
# 弹窗模式：inventory=背包物品（装备/丢弃）；equipped=已装备槽（卸下）
var _popup_mode := "inventory"
var _selected_equip_slot := ""
# 悬停提示浮窗
var _tooltip: PanelContainer = null
var _tip_icon: TextureRect = null
var _tip_frame: TextureRect = null
var _tip_name: Label = null
var _tip_sub: Label = null
var _tip_desc: Label = null
var _tip_hint: Label = null
# slot_name → {texture: TextureRect, button: Button}
var _equip_slots: Dictionary = {}
var _selected_index: int = -1
# 拖拽滚动状态
var _left_btn_down: bool = false
var _is_dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_start_scroll: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	_connect_data_signals()
	get_viewport().size_changed.connect(_apply_design_scale)


func _build() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[BackpackUI] 无法加载场景: %s" % SCENE_PATH)
		return
	_scene_root = packed.instantiate() as Control
	if _scene_root == null:
		push_warning("[BackpackUI] 场景根节点不是 Control")
		return
	add_child(_scene_root)
	_scene_root.mouse_filter = Control.MOUSE_FILTER_STOP

	# 角色精灵：记录网页编排器中设置的基准位置和缩放（作为脚点）
	_sprite = _scene_root.get_node_or_null("%player_sprite") as AnimatedSprite2D
	if _sprite != null:
		_sprite_base_pos = _sprite.position
		_sprite_base_scale = _sprite.scale

	# 物品网格
	_grid = _scene_root.get_node_or_null("%scroll_grid_001_content") as GridContainer
	if _grid != null:
		for child in _grid.get_children():
			var btn := child as TextureButton
			if btn != null:
				_item_buttons.append(btn)
				if _default_item_texture == null:
					_default_item_texture = btn.texture_normal
				btn.pressed.connect(_on_item_pressed.bind(_item_buttons.size() - 1))
				btn.mouse_entered.connect(_on_slot_hover.bind(_item_buttons.size() - 1))
				btn.mouse_exited.connect(_hide_item_tooltip)
				_item_icons.append(_attach_slot_icon(btn))

	# 滚动容器：支持左键拖拽滚动
	_scroll_container = _scene_root.get_node_or_null("%scroll_grid_001") as ScrollContainer
	if _scroll_container != null:
		_scroll_container.gui_input.connect(_on_scroll_gui_input)
		# TextureButton 设为 PASS，使鼠标事件传播到 ScrollContainer 以处理拖拽
		for btn in _item_buttons:
			btn.mouse_filter = Control.MOUSE_FILTER_PASS

	# 装备槽
	for entry in EQUIP_SLOT_MAP:
		var e: Dictionary = entry
		var tex := _scene_root.get_node_or_null("%%%s" % e["texture"]) as TextureRect
		var btn := _scene_root.get_node_or_null("%%%s" % e["button"]) as Button
		if tex != null and btn != null:
			var slot_name: String = e["slot"]
			# 底框保留，装备图标作为上层叠加
			_equip_slots[slot_name] = {texture = tex, button = btn, icon = _attach_slot_icon(tex)}
			btn.pressed.connect(_on_equip_slot_pressed.bind(slot_name))
			btn.mouse_entered.connect(_on_equip_slot_hover.bind(slot_name))
			btn.mouse_exited.connect(_hide_item_tooltip)

	_build_detail_popup()
	_build_item_tooltip()
	_apply_design_scale()


func _connect_data_signals() -> void:
	if GameRegistry.inventory_provider != null:
		GameRegistry.inventory_provider.item_added.connect(func(_item: ItemInstance) -> void: _refresh_inventory())
		GameRegistry.inventory_provider.item_removed.connect(func(_uid: int) -> void: _refresh_inventory())
		GameRegistry.inventory_provider.item_changed.connect(func(_item: ItemInstance) -> void: _refresh_inventory())
	if GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.equipped.connect(func(_slot: String, _item_id: int) -> void: _refresh_all())
		GameRegistry.equipment_provider.unequipped.connect(func(_slot: String, _item_id: int) -> void: _refresh_all())
	if GameRegistry.roster_data != null:
		GameRegistry.roster_data.active_character_changed.connect(func(_id: int) -> void: _refresh_all())


# ---- 显隐控制 ----

func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_refresh_all()
	_apply_design_scale()


func close() -> void:
	_hide_detail_popup()
	_hide_item_tooltip()
	visible = false


func is_open() -> bool:
	return visible


# ---- 数据刷新 ----

func _refresh_all() -> void:
	_refresh_sprite()
	_refresh_equipment()
	_refresh_inventory()


func _refresh_sprite() -> void:
	if _sprite == null:
		return
	var character_id := _get_active_character_id()
	var scene_path := ""
	if GameRegistry.character_config != null:
		scene_path = GameRegistry.character_config.get_scene_path(character_id)
	if scene_path.is_empty():
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var src_sprite := instance.get_node_or_null("CharacterActionSet/AnimatedSprite2D") as AnimatedSprite2D
	var action_set := instance.get_node_or_null("CharacterActionSet") as Node2D
	if src_sprite != null and src_sprite.sprite_frames != null:
		_sprite.sprite_frames = src_sprite.sprite_frames
		# 复制精灵对齐属性（centered / offset），确保与角色原始配置一致
		_sprite.centered = src_sprite.centered
		_sprite.offset = src_sprite.offset
		# 读取 CharacterActionSet 的变换（脚点→精灵原点的偏移 + 角色缩放）
		var action_pos := Vector2.ZERO
		var action_scale := Vector2.ONE
		if action_set != null:
			action_pos = action_set.position
			action_scale = action_set.scale
		# 基准位置 = 脚点（网页编排器中设置的位置）；
		# 精灵位置 = 脚点 + 角色偏移 × 用户缩放
		# 最终缩放 = 角色缩放 × 用户缩放
		_sprite.position = _sprite_base_pos + action_pos * _sprite_base_scale
		_sprite.scale = action_scale * _sprite_base_scale
		var anim := "idle"
		if not _sprite.sprite_frames.has_animation(anim):
			var names := _sprite.sprite_frames.get_animation_names()
			if not names.is_empty():
				anim = str(names[0])
		_sprite.animation = anim
		_sprite.frame = 0
		_sprite.play()
	instance.queue_free()


func _refresh_equipment() -> void:
	if GameRegistry.equipment_data == null or GameRegistry.item_config == null:
		return
	for slot_name in _equip_slots:
		var entry: Dictionary = _equip_slots[slot_name]
		var icon_rect: TextureRect = entry["icon"]
		var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot_name)
		if item_id == 0:
			icon_rect.visible = false
		else:
			var config: Dictionary = GameRegistry.item_config.get_item(item_id)
			icon_rect.texture = _load_item_icon(config)
			icon_rect.visible = icon_rect.texture != null
	# 详情弹窗对着的已装备槽被卸下（其他途径）时同步关闭
	if _popup_mode == "equipped" and _detail_popup != null and _detail_popup.visible:
		if GameRegistry.equipment_data.get_equipped_item_id(_selected_equip_slot) == 0:
			_hide_detail_popup()


func _refresh_inventory() -> void:
	_hide_item_tooltip()
	var items: Array[ItemInstance] = []
	if GameRegistry.inventory_provider != null:
		items = GameRegistry.inventory_provider.get_items()
	for i in range(_item_buttons.size()):
		var btn: TextureButton = _item_buttons[i]
		var icon_rect: TextureRect = _item_icons[i]
		if i < items.size():
			var item: ItemInstance = items[i]
			var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
			# 底框 = 品质边框（下层），物品图标作为子节点叠加在上层
			var frame := _get_quality_frame(str(config.get("quality", DEFAULT_FRAME_KEY)))
			btn.texture_normal = frame if frame != null else _default_item_texture
			icon_rect.texture = _load_item_icon(config)
			icon_rect.visible = true
			btn.tooltip_text = str(config.get("name", str(item.item_id)))
		else:
			btn.texture_normal = _default_item_texture
			icon_rect.visible = false
			btn.tooltip_text = ""
	# 详情弹窗打开时物品被移除（如任务回收），同步关掉
	if _popup_mode == "inventory" and _detail_popup != null and _detail_popup.visible and GameRegistry.inventory_provider != null:
		if GameRegistry.inventory_provider.inventory.get_item_by_uid(_selected_uid) == null:
			_hide_detail_popup()


## 在槽位（背包格子/装备槽）上叠加图标层，绘制在底框之上，四周内缩露出边框。
func _attach_slot_icon(host: Control) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "slot_icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5
	icon.offset_top = 5
	icon.offset_right = -5
	icon.offset_bottom = -5
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.visible = false
	host.add_child(icon)
	return icon


func _get_quality_frame(quality: String) -> Texture2D:
	if not QUALITY_FRAMES.has(quality):
		quality = DEFAULT_FRAME_KEY
	if not _frame_texture_cache.has(quality):
		var path: String = QUALITY_FRAMES[quality]
		_frame_texture_cache[quality] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _frame_texture_cache[quality]


# ---- 交互 ----

## ScrollContainer 左键拖拽滚动：鼠标左键按下后移动超过阈值则拖拽滚动，
## 未超过阈值则视为点击（由 TextureButton 的 pressed 信号正常处理）。
func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_btn_down = true
			_is_dragging = false
			_drag_start_pos = event.position
			_drag_start_scroll = Vector2(
				float(_scroll_container.scroll_horizontal),
				float(_scroll_container.scroll_vertical)
			)
		else:
			_left_btn_down = false
			_is_dragging = false
	elif event is InputEventMouseMotion and _left_btn_down:
		var mouse_event := event as InputEventMouseMotion
		var delta := mouse_event.position - _drag_start_pos
		if not _is_dragging and delta.length() >= DRAG_THRESHOLD:
			_is_dragging = true
		if _is_dragging:
			# 内容跟随鼠标移动（自然滚动方向）
			_scroll_container.scroll_horizontal = int(_drag_start_scroll.x - delta.x)
			_scroll_container.scroll_vertical = int(_drag_start_scroll.y - delta.y)


func _on_item_pressed(index: int) -> void:
	# 拖拽过程中的松手不触发点击
	if _is_dragging:
		return
	var items: Array[ItemInstance] = []
	if GameRegistry.inventory_provider != null:
		items = GameRegistry.inventory_provider.get_items()
	if index < 0 or index >= items.size():
		return
	_selected_index = index
	_show_detail_popup(items[index], _item_buttons[index])


# ---- 物品详情弹窗 ----

## 运行时构建详情弹窗：图标（带品质边框）+ 名称/品质/描述 + 装备/丢弃/关闭。
func _build_detail_popup() -> void:
	if _scene_root == null:
		return
	_detail_popup = PanelContainer.new()
	_detail_popup.name = "item_detail_popup"
	_detail_popup.visible = false
	_detail_popup.position = Vector2(24, 110)
	_detail_popup.custom_minimum_size = Vector2(256, 0)
	_detail_popup.z_index = 20
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.14, 0.09, 0.04, 0.97)
	panel_style.border_color = Color(0.74, 0.52, 0.20)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 10
	_detail_popup.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_detail_popup.add_child(vbox)

	# 顶部：图标 + 名称/品质
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vbox.add_child(head)
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(48, 48)
	head.add_child(icon_holder)
	_detail_icon_frame = TextureRect.new()
	_detail_icon_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_icon_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_detail_icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_detail_icon_frame)
	_detail_icon = TextureRect.new()
	_detail_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_icon.offset_left = 4
	_detail_icon.offset_top = 4
	_detail_icon.offset_right = -4
	_detail_icon.offset_bottom = -4
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_detail_icon)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	_detail_name = Label.new()
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.86, 0.46))
	_detail_name.add_theme_font_size_override("font_size", 15)
	title_box.add_child(_detail_name)
	_detail_sub = Label.new()
	_detail_sub.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
	_detail_sub.add_theme_font_size_override("font_size", 12)
	title_box.add_child(_detail_sub)

	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(236, 0)
	_detail_desc.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	_detail_desc.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_detail_desc)

	# 底部按钮
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)
	_detail_equip_btn = _make_popup_button("装备", btn_row)
	_detail_equip_btn.pressed.connect(_on_detail_equip_pressed)
	_detail_discard_btn = _make_popup_button("丢弃", btn_row)
	_detail_discard_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_detail_discard_btn.pressed.connect(_on_detail_discard_pressed)
	var close_btn := _make_popup_button("关闭", btn_row)
	close_btn.pressed.connect(_hide_detail_popup)

	_scene_root.add_child(_detail_popup)


func _make_popup_button(text: String, parent: Container) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(64, 26)
	btn.add_theme_font_size_override("font_size", 13)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.30, 0.18, 0.07, 0.92)
	normal.border_color = Color(0.62, 0.44, 0.18)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.40, 0.24, 0.09, 0.96)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.22, 0.14, 0.06, 0.96)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.94, 0.92, 0.78))
	parent.add_child(btn)
	return btn


func _show_detail_popup(item: ItemInstance, anchor: Control) -> void:
	if _detail_popup == null or GameRegistry.item_config == null:
		return
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	if config.is_empty():
		return
	_popup_mode = "inventory"
	_selected_uid = item.uid
	_fill_detail(config, item.count)
	# 装备按钮仅对可装备物品显示；丢弃按钮尊重配置里的 is_droppable（任务物品不可丢）
	_detail_equip_btn.text = "装备"
	_detail_equip_btn.visible = GameRegistry.equipment_provider != null \
		and GameRegistry.item_config.get_equip_slot(item.item_id) != ""
	_detail_discard_btn.visible = bool(config.get("is_droppable", true))
	_hide_item_tooltip()
	_detail_popup.visible = true
	_place_panel_near(_detail_popup, anchor)


## 已装备槽位的详情：按钮为卸下，不可丢弃。
func _show_equipped_detail(slot_name: String, item_id: int, anchor: Control) -> void:
	if _detail_popup == null or GameRegistry.item_config == null:
		return
	var config: Dictionary = GameRegistry.item_config.get_item(item_id)
	if config.is_empty():
		return
	_popup_mode = "equipped"
	_selected_equip_slot = slot_name
	_fill_detail(config, 1)
	_detail_equip_btn.text = "卸下"
	_detail_equip_btn.visible = GameRegistry.equipment_provider != null
	_detail_discard_btn.visible = false
	_hide_item_tooltip()
	_detail_popup.visible = true
	_place_panel_near(_detail_popup, anchor)


func _fill_detail(config: Dictionary, count: int) -> void:
	var quality := str(config.get("quality", DEFAULT_FRAME_KEY))
	_detail_icon_frame.texture = _get_quality_frame(quality)
	_detail_icon.texture = _load_item_icon(config)
	_detail_name.text = str(config.get("name", ""))
	var sub := quality
	var type_text := str(config.get("type", ""))
	if not type_text.is_empty():
		sub += " · " + type_text
	if count > 1:
		sub += " · ×%d" % count
	_detail_sub.text = sub
	var desc := str(config.get("description", ""))
	var stats_text := _format_stats(config)
	if not stats_text.is_empty():
		desc = (desc + "\n" if not desc.is_empty() else "") + stats_text
	_detail_desc.text = desc
	_detail_desc.visible = not desc.is_empty()


## 属性行：攻击/防御等平值 + 比率类转百分比。
const STAT_LABELS := {
	"attack": "攻击", "defense": "防御", "max_hp": "生命", "move_speed": "移速",
	"skill_haste": "急速",
}
const STAT_PERCENT_LABELS := {
	"crit_rate": "暴击", "block_rate": "格挡", "reflect_rate": "反弹",
	"magic_pen_percent": "法穿",
}


func _format_stats(config: Dictionary) -> String:
	var lines: Array[String] = []
	var stats: Dictionary = config.get("stats", {})
	for key in STAT_LABELS:
		if stats.has(key) and float(stats[key]) != 0.0:
			lines.append("%s +%d" % [STAT_LABELS[key], int(stats[key])])
	for key in STAT_PERCENT_LABELS:
		if stats.has(key) and float(stats[key]) != 0.0:
			lines.append("%s +%d%%" % [STAT_PERCENT_LABELS[key], int(round(float(stats[key]) * 100.0))])
	var heal := int(config.get("heal_amount", 0))
	if heal > 0:
		lines.append("恢复 +%d" % heal)
	return "\n".join(lines)


## 把浮窗放到被点击/悬停槽位的上方（上方空间不够时放到下方），并收进窗口范围内。
func _place_panel_near(panel: Control, anchor: Control) -> void:
	if panel == null or anchor == null or _scene_root == null:
		return
	var slot_pos: Vector2 = _scene_root.get_global_transform().affine_inverse() * anchor.global_position
	panel.reset_size()
	var sz := panel.get_combined_minimum_size()
	var x := clampf(slot_pos.x + anchor.size.x * 0.5 - sz.x * 0.5, 8.0, DESIGN_SIZE.x - sz.x - 8.0)
	var y := slot_pos.y - sz.y - 6.0
	if y < 8.0:
		y = minf(slot_pos.y + anchor.size.y + 6.0, DESIGN_SIZE.y - sz.y - 8.0)
	panel.position = Vector2(x, y)


func _hide_detail_popup() -> void:
	if _detail_popup != null:
		_detail_popup.visible = false
	_selected_uid = 0
	_selected_equip_slot = ""
	_selected_index = -1


func _on_detail_equip_pressed() -> void:
	if GameRegistry.equipment_provider == null:
		return
	if _popup_mode == "equipped":
		if not _selected_equip_slot.is_empty() and GameRegistry.equipment_provider.unequip_slot(_selected_equip_slot):
			GameRegistry.save_game()
	else:
		if _selected_uid != 0 and GameRegistry.equipment_provider.equip_item(_selected_uid):
			GameRegistry.save_game()
	_hide_detail_popup()


func _on_detail_discard_pressed() -> void:
	if _selected_uid == 0 or GameRegistry.inventory_provider == null:
		return
	# 丢弃即整格消失
	if GameRegistry.inventory_provider.remove_item(_selected_uid):
		GameRegistry.save_game()
	_hide_detail_popup()


# ---- 悬停提示浮窗 ----

## 运行时构建悬停浮窗：图标（带品质边框）+ 名称/品质/描述/属性 + 操作提示，无按钮。
func _build_item_tooltip() -> void:
	if _scene_root == null:
		return
	_tooltip = PanelContainer.new()
	_tooltip.name = "item_tooltip"
	_tooltip.visible = false
	_tooltip.custom_minimum_size = Vector2(236, 0)
	_tooltip.z_index = 19
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.14, 0.09, 0.04, 0.97)
	panel_style.border_color = Color(0.74, 0.52, 0.20)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 10
	_tooltip.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	_tooltip.add_child(vbox)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	vbox.add_child(head)
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(44, 44)
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon_holder)
	_tip_frame = TextureRect.new()
	_tip_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tip_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_tip_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_tip_frame)
	_tip_icon = TextureRect.new()
	_tip_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tip_icon.offset_left = 4
	_tip_icon.offset_top = 4
	_tip_icon.offset_right = -4
	_tip_icon.offset_bottom = -4
	_tip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_tip_icon)
	var title_box := VBoxContainer.new()
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	_tip_name = Label.new()
	_tip_name.add_theme_color_override("font_color", Color(1.0, 0.86, 0.46))
	_tip_name.add_theme_font_size_override("font_size", 14)
	title_box.add_child(_tip_name)
	_tip_sub = Label.new()
	_tip_sub.add_theme_color_override("font_color", Color(0.72, 0.62, 0.42))
	_tip_sub.add_theme_font_size_override("font_size", 11)
	title_box.add_child(_tip_sub)

	_tip_desc = Label.new()
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_desc.custom_minimum_size = Vector2(216, 0)
	_tip_desc.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	_tip_desc.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_tip_desc)

	_tip_hint = Label.new()
	_tip_hint.add_theme_color_override("font_color", Color(0.55, 0.72, 1.0))
	_tip_hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_tip_hint)

	_scene_root.add_child(_tooltip)


func _on_slot_hover(index: int) -> void:
	if GameRegistry.inventory_provider == null or GameRegistry.item_config == null:
		return
	var items: Array[ItemInstance] = GameRegistry.inventory_provider.get_items()
	if index < 0 or index >= items.size():
		_hide_item_tooltip()
		return
	var item: ItemInstance = items[index]
	var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
	var hint := "点击穿戴到当前角色。" if GameRegistry.item_config.get_equip_slot(item.item_id) != "" else "点击查看详情。"
	_show_item_tooltip(config, item.count, hint, _item_buttons[index])


func _on_equip_slot_hover(slot_name: String) -> void:
	if GameRegistry.equipment_data == null or GameRegistry.item_config == null:
		return
	var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot_name)
	if item_id == 0:
		_hide_item_tooltip()
		return
	var config: Dictionary = GameRegistry.item_config.get_item(item_id)
	var entry: Dictionary = _equip_slots.get(slot_name, {})
	_show_item_tooltip(config, 1, "点击查看详情，可卸下。", entry.get("texture"))


func _show_item_tooltip(config: Dictionary, count: int, hint: String, anchor: Control) -> void:
	if _tooltip == null or config.is_empty():
		return
	# 详情弹窗打开时不叠悬浮窗
	if _detail_popup != null and _detail_popup.visible:
		_hide_item_tooltip()
		return
	var quality := str(config.get("quality", DEFAULT_FRAME_KEY))
	_tip_frame.texture = _get_quality_frame(quality)
	_tip_icon.texture = _load_item_icon(config)
	_tip_name.text = str(config.get("name", ""))
	var sub := quality
	var type_text := str(config.get("type", ""))
	if not type_text.is_empty():
		sub += " · " + type_text
	if count > 1:
		sub += " · ×%d" % count
	_tip_sub.text = sub
	var desc := str(config.get("description", ""))
	var stats_text := _format_stats(config)
	if not stats_text.is_empty():
		desc = (desc + "\n" if not desc.is_empty() else "") + stats_text
	_tip_desc.text = desc
	_tip_desc.visible = not desc.is_empty()
	_tip_hint.text = hint
	_tip_hint.visible = not hint.is_empty()
	_tooltip.visible = true
	_place_panel_near(_tooltip, anchor)


func _hide_item_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _on_equip_slot_pressed(slot_name: String) -> void:
	if GameRegistry.equipment_data == null:
		return
	var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot_name)
	if item_id == 0:
		return
	var entry: Dictionary = _equip_slots.get(slot_name, {})
	_show_equipped_detail(slot_name, item_id, entry.get("texture"))


# ---- 辅助 ----

func _get_active_character_id() -> int:
	if GameRegistry.roster_data != null:
		return int(GameRegistry.roster_data.active_character_id)
	return CharacterRosterData.DEFAULT_CHARACTER_ID


func _load_item_icon(config: Dictionary) -> Texture2D:
	var icon_path := str(config.get("icon", ""))
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return null
	return load(icon_path) as Texture2D


func _apply_design_scale() -> void:
	if _scene_root == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var scale_val: float = min(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	_scene_root.scale = Vector2(scale_val, scale_val)
	_scene_root.position = (vp - DESIGN_SIZE * scale_val) * 0.5
