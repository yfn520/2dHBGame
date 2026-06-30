extends Node

var item_config
var skill_config
var buff_config
var level_config
var enemy_config

var inventory_data
var equipment_data
var character_stats

var inventory_provider
var equipment_provider

var level_manager: Node


func _ready() -> void:
	item_config = load("res://scripts/data/item_config.gd").new()
	item_config.load_config()
	skill_config = load("res://scripts/data/skill_config.gd").new()
	skill_config.load_config()
	buff_config = load("res://scripts/data/buff_config.gd").new()
	buff_config.load_config()
	level_config = load("res://scripts/data/level_config.gd").new()
	level_config.load_config()
	enemy_config = load("res://scripts/data/enemy_config.gd").new()
	enemy_config.load_config()

	inventory_data = load("res://scripts/data/inventory_data.gd").new()
	equipment_data = load("res://scripts/data/equipment_data.gd").new()
	character_stats = load("res://scripts/data/character_stats.gd").new()

	inventory_provider = load("res://scripts/provider/inventory_provider.gd").new(inventory_data, item_config)
	equipment_provider = load("res://scripts/provider/equipment_provider.gd").new(equipment_data, inventory_data, character_stats, item_config)

	load("res://scripts/system/save_manager.gd").load_save(inventory_data, equipment_data, character_stats)
	equipment_provider._recalculate_stats()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		load("res://scripts/system/save_manager.gd").save(inventory_data, equipment_data, character_stats)


func save_game() -> void:
	load("res://scripts/system/save_manager.gd").save(inventory_data, equipment_data, character_stats)
