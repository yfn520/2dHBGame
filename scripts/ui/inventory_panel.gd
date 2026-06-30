extends CanvasLayer
## 背包面板
## 按 B 打开/关闭
## 所有操作通过 InventoryProvider / EquipmentProvider 完成，便于后续替换为网络请求

@onready var grid: GridContainer = $Panel/Margin/VBox/Grid

var _selected_index: int = -1
var _slot_buttons: Array[Button] = []

const SLOT_SIZE := Vector2(80, 80)


func _ready() -> void:
	# 监听数据变化，自动刷新 UI
	GameRegistry.inventory_provider.item_added.connect(_on_data_changed)
	GameRegistry.inventory_provider.item_removed.connect(_on_data_changed)
	GameRegistry.inventory_provider.item_changed.connect(_on_data_changed)
	GameRegistry.equipment_provider.equipped.connect(_on_data_changed_equipped)
	_rebuild_grid()


func _on_data_changed(_a = null) -> void:
	_refresh_grid()


func _on_data_changed_equipped(_a = "", _b = 0) -> void:
	_refresh_grid()


func toggle() -> void:
	visible = not visible
	if visible:
		_selected_index = -1
		_refresh_grid()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_B, KEY_ESCAPE:
				toggle()
				get_viewport().set_input_as_handled()
			KEY_E:
				_try_equip_selected()
				get_viewport().set_input_as_handled()
			KEY_D:
				_try_discard_selected()
				get_viewport().set_input_as_handled()


func _rebuild_grid() -> void:
	# 清空现有格子
	for child in grid.get_children():
		child.queue_free()
	_slot_buttons.clear()

	# 创建固定数量的格子(6列 x 5行 = 30格)
	var total_slots := 30
	for i in total_slots:
		var btn := Button.new()
		btn.custom_minimum_size = SLOT_SIZE
		btn.toggle_mode = true
		btn.text = ""
		btn.pressed.connect(_on_slot_pressed.bind(i))
		grid.add_child(btn)
		_slot_buttons.append(btn)

	_refresh_grid()


func _refresh_grid() -> void:
	var items = GameRegistry.inventory_provider.get_items()

	for i in _slot_buttons.size():
		var btn := _slot_buttons[i]
		if i < items.size():
			var item: ItemInstance = items[i]
			var config = GameRegistry.item_config.get_item(item.item_id)
			var item_name: String = config.get("name", "?")
			var count_text := ""
			if item.count > 1:
				count_text = "\n x%d" % item.count
			btn.text = item_name + count_text
			btn.tooltip_text = config.get("description", "")
			btn.disabled = false
		else:
			btn.text = ""
			btn.tooltip_text = ""
			btn.disabled = true
			btn.button_pressed = false

	# 恢复选中状态高亮
	_update_selection_visual()


func _on_slot_pressed(index: int) -> void:
	# 取消之前的选中
	if _selected_index >= 0 and _selected_index < _slot_buttons.size():
		_slot_buttons[_selected_index].button_pressed = false
	_selected_index = index
	_update_selection_visual()


func _update_selection_visual() -> void:
	for i in _slot_buttons.size():
		var btn := _slot_buttons[i]
		if i == _selected_index:
			btn.add_theme_color_override("font_color", Color.YELLOW)
			btn.add_theme_color_override("font_pressed_color", Color.YELLOW)
		else:
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_pressed_color")


func _try_equip_selected() -> void:
	if _selected_index < 0:
		return
	var items = GameRegistry.inventory_provider.get_items()
	if _selected_index >= items.size():
		return
	var item: ItemInstance = items[_selected_index]
	# 通过 Provider 穿戴，Provider 内部会处理从背包移除 + 穿到身上 + 重算属性
	GameRegistry.equipment_provider.equip_item(item.uid)
	_selected_index = -1
	_refresh_grid()


func _try_discard_selected() -> void:
	if _selected_index < 0:
		return
	var items = GameRegistry.inventory_provider.get_items()
	if _selected_index >= items.size():
		return
	var item: ItemInstance = items[_selected_index]
	# 通过 Provider 删除
	GameRegistry.inventory_provider.remove_item(item.uid)
	_selected_index = -1
	_refresh_grid()
