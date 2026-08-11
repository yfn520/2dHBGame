class_name BackpackUI
extends Control
## 背包界面：从 UiInteractionComposer 导出的 backpack.tscn 实例化。
## B 键弹出，ESC/B 关闭。包含角色精灵、装备槽、物品网格。
## 数据复用 GameRegistry.inventory_provider / equipment_data / item_config。

const SCENE_PATH := "res://assets/ui/backpack.tscn"
const DESIGN_SIZE := Vector2(760, 515)
# 拖拽滚动判定阈值（像素），超过此距离才视为拖拽而非点击
const DRAG_THRESHOLD := 5.0

# 10 个装备槽 UI 节点名 → 装备类型映射（前 8 个有效，后 2 个预留）
const EQUIP_SLOT_MAP := [
	{slot = "weapon", texture = "dynamic_image_001", button = "dynamic_image_001_click"},
	{slot = "armor", texture = "dynamic_image_001_2", button = "dynamic_image_001_2_click"},
	{slot = "necklace", texture = "dynamic_image_001_2_2", button = "dynamic_image_001_2_2_click"},
	{slot = "ring", texture = "dynamic_image_001_2_2_2", button = "dynamic_image_001_2_2_2_click"},
	{slot = "boots", texture = "dynamic_image_001_2_2_2_2", button = "dynamic_image_001_2_2_2_2_click"},
	{slot = "relic", texture = "dynamic_image_001_3", button = "dynamic_image_001_3_click"},
	{slot = "mount", texture = "dynamic_image_001_2_3", button = "dynamic_image_001_2_3_click"},
	{slot = "artifact", texture = "dynamic_image_001_2_2_3", button = "dynamic_image_001_2_2_3_click"},
]

var _scene_root: Control = null
var _sprite: AnimatedSprite2D = null
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _sprite_base_scale: Vector2 = Vector2.ONE
var _grid: GridContainer = null
var _scroll_container: ScrollContainer = null
var _item_buttons: Array[TextureButton] = []
var _default_item_texture: Texture2D = null
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
			_equip_slots[slot_name] = {texture = tex, button = btn}
			btn.pressed.connect(_on_equip_slot_pressed.bind(slot_name))

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
	visible = false
	_selected_index = -1


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
		var tex: TextureRect = entry["texture"]
		var item_id: int = GameRegistry.equipment_data.get_equipped_item_id(slot_name)
		if item_id == 0:
			tex.texture = _default_item_texture
		else:
			var config: Dictionary = GameRegistry.item_config.get_item(item_id)
			var icon := _load_item_icon(config)
			tex.texture = icon if icon != null else _default_item_texture


func _refresh_inventory() -> void:
	var items: Array[ItemInstance] = []
	if GameRegistry.inventory_provider != null:
		items = GameRegistry.inventory_provider.get_items()
	for i in range(_item_buttons.size()):
		var btn: TextureButton = _item_buttons[i]
		if i < items.size():
			var item: ItemInstance = items[i]
			var config: Dictionary = GameRegistry.item_config.get_item(item.item_id)
			var icon := _load_item_icon(config)
			btn.texture_normal = icon if icon != null else _default_item_texture
			btn.tooltip_text = str(config.get("name", str(item.item_id)))
		else:
			btn.texture_normal = _default_item_texture
			btn.tooltip_text = ""


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
	var item: ItemInstance = items[index]
	_selected_index = index
	if GameRegistry.item_config != null and GameRegistry.equipment_provider != null:
		if GameRegistry.item_config.get_equip_slot(item.item_id) != "":
			GameRegistry.equipment_provider.equip_item(item.uid)
			_selected_index = -1


func _on_equip_slot_pressed(slot_name: String) -> void:
	if GameRegistry.equipment_data == null:
		return
	var equipped_uid: int = GameRegistry.equipment_data.get_equipped_uid(slot_name)
	if equipped_uid != 0 and GameRegistry.equipment_provider != null:
		GameRegistry.equipment_provider.unequip_slot(slot_name)


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
