extends Node
## 全局游戏数据注册表(AutoLoad 单例，类名由 project.godot 注册)
## 持有所有数据模型和 Provider，作为单一入口
## 挂载到 AutoLoad 即可全局访问

var item_config: ItemConfig
var skill_config: SkillConfig
var buff_config: BuffConfig

var inventory_data: InventoryData
var equipment_data: EquipmentData
var character_stats: CharacterStats

var inventory_provider: InventoryProvider
var equipment_provider: EquipmentProvider


func _ready() -> void:
	item_config = ItemConfig.new()
	item_config.load_config()
	skill_config = SkillConfig.new()
	skill_config.load_config()
	buff_config = BuffConfig.new()
	buff_config.load_config()

	inventory_data = InventoryData.new()
	equipment_data = EquipmentData.new()
	character_stats = CharacterStats.new()

	inventory_provider = InventoryProvider.new(inventory_data, item_config)
	equipment_provider = EquipmentProvider.new(equipment_data, inventory_data, character_stats, item_config)

	# 尝试加载存档
	SaveManager.load_save(inventory_data, equipment_data, character_stats)

	# 有装备时需要重算属性
	equipment_provider._recalculate_stats()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save(inventory_data, equipment_data, character_stats)


## 保存存档
func save_game() -> void:
	SaveManager.save(inventory_data, equipment_data, character_stats)
