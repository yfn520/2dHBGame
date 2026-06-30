extends CanvasLayer
## 角色面板
## 按 C 打开/关闭
## 点击装备槽: 已穿戴→卸下, 空槽→弹出选择列表

const SLOT_LABELS := {
	"weapon": "武器",
	"armor": "护甲",
	"boots": "靴子",
	"accessory": "饰品",
}

const SLOT_COLORS := {
	"weapon": Color(0.9, 0.3, 0.3),
	"armor": Color(0.3, 0.5, 0.9),
	"boots": Color(0.3, 0.8, 0.3),
	"accessory": Color(0.9, 0.7, 0.2),
}

@onready var hp_value: Label = $Panel/Margin/VBox/StatsSection/HPRow/HPValue
@onready var atk_value: Label = $Panel/Margin/VBox/StatsSection/AtkRow/AtkValue
@onready var def_value: Label = $Panel/Margin/VBox/StatsSection/DefRow/DefValue
@onready var spd_value: Label = $Panel/Margin/VBox/StatsSection/SpdRow/SpdValue

@onready var slot_weapon: Button = $Panel/Margin/VBox/EquipSection/SlotWeapon
@onready var slot_armor: Button = $Panel/Margin/VBox/EquipSection/SlotArmor
@onready var slot_boots: Button = $Panel/Margin/VBox/EquipSection/SlotBoots
@onready var slot_accessory: Button = $Panel/Margin/VBox/EquipSection/SlotAccessory

@onready var popup: PanelContainer = $Popup
@onready var popup_title: Label = $Popup/PMargin/PVBox/PTitle
@onready var popup_list: VBoxContainer = $Popup/PMargin/PVBox/PList
@onready var popup_close: Button = $Popup/PMargin/PVBox/PClose

var _slot_buttons: Dictionary = {}
var _current_popup_slot: String = ""


func _ready() -> void:
	_slot_buttons = {
		"weapon": slot_weapon,
		"armor": slot_armor,
		"boots": slot_boots,
		"accessory": slot_accessory,
	}
	# 槽位按钮
	slot_weapon.pressed.connect(_on_slot_clicked.bind("weapon"))
	slot_armor.pressed.connect(_on_slot_clicked.bind("armor"))
	slot_boots.pressed.connect(_on_slot_clicked.bind("boots"))
	slot_accessory.pressed.connect(_on_slot_clicked.bind("accessory"))
	# 弹窗关闭
	popup_close.pressed.connect(_close_popup)
	# 监听数据变化
	GameRegistry.character_stats.stats_changed.connect(_refresh_stats)
	GameRegistry.equipment_provider.equipped.connect(_on_equipment_changed)
	GameRegistry.equipment_provider.unequipped.connect(_on_equipment_changed)
	_refresh_all()


func _on_equipment_changed(_slot: String = "", _item_id: int = 0) -> void:
	_refresh_all()


func toggle() -> void:
	visible = not visible
	if visible:
		_close_popup()
		_refresh_all()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_C or event.keycode == KEY_ESCAPE:
			if popup.visible:
				_close_popup()
			else:
				toggle()
			get_viewport().set_input_as_handled()


# ---- 槽位点击 ----

func _on_slot_clicked(slot: String) -> void:
	var equipped_uid := GameRegistry.equipment_data.get_equipped_uid(slot)
	if equipped_uid != 0:
		# 已穿戴 → 卸下
		GameRegistry.equipment_provider.unequip_slot(slot)
	else:
		# 空槽 → 打开选择弹窗
		_open_popup_for_slot(slot)


# ---- 弹窗 ----

func _open_popup_for_slot(slot: String) -> void:
	_current_popup_slot = slot
	popup_title.text = "选择[%s]" % SLOT_LABELS.get(slot, slot)
	_rebuild_popup_list()
	popup.visible = true


func _close_popup() -> void:
	popup.visible = false
	_current_popup_slot = ""
	# 清空弹窗列表
	for child in popup_list.get_children():
		child.queue_free()


func _rebuild_popup_list() -> void:
	for child in popup_list.get_children():
		child.queue_free()

	# 从背包中筛选该类型的装备
	var items := GameRegistry.inventory_provider.get_items()
	var found := false
	for item in items:
		var config := GameRegistry.item_config.get_item(item.item_id)
		if config.get("type", "") != _current_popup_slot:
			continue
		found = true
		var btn := Button.new()
		var stats_text := _format_stats(config.get("stats", {}))
		btn.text = "%s  %s" % [config.get("name", "?"), stats_text]
		btn.pressed.connect(_on_popup_item_selected.bind(item.uid))
		popup_list.add_child(btn)

	if not found:
		var lbl := Label.new()
		lbl.text = "背包中没有该类型装备"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup_list.add_child(lbl)


func _on_popup_item_selected(item_uid: int) -> void:
	GameRegistry.equipment_provider.equip_item(item_uid)
	_close_popup()


# ---- 刷新 ----

func _refresh_all() -> void:
	_refresh_stats()
	_refresh_equipment()


func _refresh_stats() -> void:
	var stats := GameRegistry.character_stats
	hp_value.text = "%d / %d" % [stats.hp, stats.max_hp]
	atk_value.text = str(stats.attack)
	def_value.text = str(stats.defense)
	spd_value.text = str(int(stats.move_speed))


func _refresh_equipment() -> void:
	for slot in EquipmentData.SLOTS:
		var btn: Button = _slot_buttons.get(slot)
		if btn == null:
			continue
		var item_id := GameRegistry.equipment_data.get_equipped_item_id(slot)
		var label_name: String = SLOT_LABELS.get(slot, slot)
		var color: Color = SLOT_COLORS.get(slot, Color.WHITE)
		if item_id == 0:
			btn.text = "[%s]  空" % label_name
			btn.tooltip_text = "点击从背包选择"
			btn.remove_theme_color_override("font_color")
			btn.remove_theme_color_override("font_hover_color")
		else:
			var config := GameRegistry.item_config.get_item(item_id)
			var item_name: String = config.get("name", "?")
			var stats_text := _format_stats(config.get("stats", {}))
			btn.text = "[%s]  %s  %s" % [label_name, item_name, stats_text]
			btn.tooltip_text = config.get("description", "") + "\n点击卸下"
			btn.add_theme_color_override("font_color", color)
			btn.add_theme_color_override("font_hover_color", color)


func _format_stats(stats: Dictionary) -> String:
	if stats.is_empty():
		return ""
	var parts: PackedStringArray = []
	if stats.has("attack"):
		parts.append("攻+%d" % int(stats["attack"]))
	if stats.has("defense"):
		parts.append("防+%d" % int(stats["defense"]))
	if stats.has("max_hp"):
		parts.append("血+%d" % int(stats["max_hp"]))
	if stats.has("move_speed"):
		parts.append("速+%d" % int(stats["move_speed"]))
	return "(%s)" % ", ".join(parts)
