extends Node

var item_config
var skill_config
var buff_config
var level_config
var enemy_config
var character_config
var npc_config
var npc_placement_config
var dialogue_config
var quest_config

var inventory_data
var equipment_data
var roster_data
var character_stats
var quest_state

var inventory_provider
var equipment_provider
var player_data_provider
var quest_service
var dialogue_service

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
	character_config = load("res://scripts/data/character_config_data.gd").new()
	character_config.load_config()
	dialogue_config = load("res://scripts/data/dialogue_config.gd").new()
	dialogue_config.load_config()
	npc_config = load("res://scripts/data/npc_config.gd").new()
	npc_config.load_config(dialogue_config)
	npc_placement_config = load("res://scripts/data/npc_placement_config.gd").new()
	npc_placement_config.load_config()
	quest_config = load("res://scripts/data/quest_config.gd").new()
	quest_config.load_config()

	inventory_data = load("res://scripts/data/inventory_data.gd").new()
	equipment_data = load("res://scripts/data/equipment_data.gd").new()
	roster_data = load("res://scripts/data/character_roster_data.gd").new()
	character_stats = load("res://scripts/data/character_stats.gd").new()
	quest_state = load("res://scripts/data/quest_state_data.gd").new()

	inventory_provider = load("res://scripts/provider/inventory_provider.gd").new(inventory_data, item_config)
	equipment_provider = load("res://scripts/provider/equipment_provider.gd").new(equipment_data, inventory_data, character_stats, item_config)
	player_data_provider = load("res://scripts/provider/player_data_provider.gd").new(inventory_data, equipment_data, roster_data, character_config, quest_state)

	player_data_provider.load_local()
	quest_service = load("res://scripts/system/quest_service.gd").new()
	add_child(quest_service)
	quest_service.setup(quest_config, quest_state, inventory_provider)
	dialogue_service = load("res://scripts/system/dialogue_service.gd").new()
	add_child(dialogue_service)
	dialogue_service.setup(npc_config, dialogue_config, quest_service, inventory_provider)
	character_stats.setup(roster_data, character_config)
	equipment_provider.refresh_current_stats()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	player_data_provider.save_local()
