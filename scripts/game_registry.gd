extends Node

var item_config
var skill_config
var buff_config
var level_config
var music_config
var enemy_config
var character_config
var npc_config
var npc_placement_config
var dialogue_config
var quest_config
var interaction_binding_config

# 剧情系统配置（阶段1 新增）
var chapter_config
var story_node_config
var event_state_config
var town_change_config
var pact_legacy_config
var lead_content_package_config
var hero_recruit_config

var inventory_data
var equipment_data
var roster_data
var character_stats
var quest_state

# 剧情运行时数据（阶段2 新增）
var chapter_state

var inventory_provider
var equipment_provider
var player_data_provider
var quest_service
var dialogue_service
var npc_interaction_dispatcher
var chapter_service
var story_auto_play
# 游戏根节点（game_root.gd 在 _ready 时写入），供剧情系统访问主控角色状态
var game_root

var level_manager: Node
var _quest_save_scheduled := false


func _ready() -> void:
	item_config = load("res://scripts/data/item_config.gd").new()
	item_config.load_config()
	buff_config = load("res://scripts/data/buff_config.gd").new()
	buff_config.load_config()
	level_config = load("res://scripts/data/level_config.gd").new()
	level_config.load_config()
	music_config = load("res://scripts/data/music_config.gd").new()
	music_config.load_config()
	enemy_config = load("res://scripts/data/enemy_config.gd").new()
	enemy_config.load_config()
	character_config = load("res://scripts/data/character_config_data.gd").new()
	character_config.load_config()
	# 技能配置按 actor 分文件按需加载：先建空索引，再在角色/怪物配置就绪后建立 技能ID→actorID 索引
	skill_config = load("res://scripts/data/skill_config.gd").new()
	skill_config.load_config()
	skill_config.build_index(character_config.get_all(), enemy_config.get_all_enemies())
	dialogue_config = load("res://scripts/data/dialogue_config.gd").new()
	dialogue_config.load_config()
	interaction_binding_config = load("res://scripts/data/interaction_binding_config.gd").new()
	interaction_binding_config.load_config()
	npc_config = load("res://scripts/data/npc_config.gd").new()
	npc_config.load_config(dialogue_config)
	npc_placement_config = load("res://scripts/data/npc_placement_config.gd").new()
	npc_placement_config.load_config()
	quest_config = load("res://scripts/data/quest_config.gd").new()
	quest_config.load_config()

	# 剧情系统配置加载（阶段1 新增）
	chapter_config = load("res://scripts/data/chapter_config.gd").new()
	chapter_config.load_config()
	story_node_config = load("res://scripts/data/story_node_config.gd").new()
	story_node_config.load_config()
	event_state_config = load("res://scripts/data/event_state_config.gd").new()
	event_state_config.load_config()
	town_change_config = load("res://scripts/data/town_change_config.gd").new()
	town_change_config.load_config()
	pact_legacy_config = load("res://scripts/data/pact_legacy_config.gd").new()
	pact_legacy_config.load_config()
	lead_content_package_config = load("res://scripts/data/lead_content_package_config.gd").new()
	lead_content_package_config.load_config()
	hero_recruit_config = load("res://scripts/data/hero_recruit_config.gd").new()
	hero_recruit_config.load_config()

	inventory_data = load("res://scripts/data/inventory_data.gd").new()
	equipment_data = load("res://scripts/data/equipment_data.gd").new()
	roster_data = load("res://scripts/data/character_roster_data.gd").new()
	character_stats = load("res://scripts/data/character_stats.gd").new()
	quest_state = load("res://scripts/data/quest_state_data.gd").new()
	chapter_state = load("res://scripts/data/chapter_state_data.gd").new()

	# 章节推进服务（阶段2 新增）：须在 load_local 之前装配，
	# 否则读档时 chapter_state 尚无 chapter_service 可恢复。
	chapter_service = load("res://scripts/system/chapter_service.gd").new()
	add_child(chapter_service)
	chapter_service.setup(chapter_config)
	chapter_state.chapter_service = chapter_service

	inventory_provider = load("res://scripts/provider/inventory_provider.gd").new(inventory_data, item_config)
	equipment_provider = load("res://scripts/provider/equipment_provider.gd").new(equipment_data, inventory_data, character_stats, item_config)
	player_data_provider = load("res://scripts/provider/player_data_provider.gd").new(inventory_data, equipment_data, roster_data, character_config, quest_state, chapter_state)

	player_data_provider.load_local()
	quest_service = load("res://scripts/system/quest_service.gd").new()
	add_child(quest_service)
	quest_service.setup(quest_config, quest_state, inventory_provider, roster_data)
	dialogue_service = load("res://scripts/system/dialogue_service.gd").new()
	add_child(dialogue_service)
	dialogue_service.setup(npc_config, dialogue_config, quest_service, inventory_provider)
	npc_interaction_dispatcher = load("res://scripts/system/npc_interaction_dispatcher.gd").new()
	add_child(npc_interaction_dispatcher)
	npc_interaction_dispatcher.setup(dialogue_service, interaction_binding_config, quest_service)
	# 开局选角 + 纯对白任务自动链（由 GameRoot 首关加载后触发 bootstrap）
	story_auto_play = load("res://scripts/system/story_auto_play.gd").new()
	add_child(story_auto_play)
	story_auto_play.setup(quest_service, dialogue_service)
	quest_service.quest_updated.connect(_on_quest_updated)
	# 穿戴装备 → 任务事件记账（如 C0-05-A「穿上借出的装备」）
	equipment_provider.equipped.connect(_on_equipment_equipped)

	character_stats.setup(roster_data, character_config)
	equipment_provider.refresh_current_stats()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	player_data_provider.save_local()


func _on_quest_updated(_quest_id: int) -> void:
	if _quest_save_scheduled:
		return
	_quest_save_scheduled = true
	get_tree().create_timer(0.25).timeout.connect(_flush_quest_save)


func _on_equipment_equipped(_slot: String, _item_id: int) -> void:
	if quest_service != null:
		quest_service.record_named_event("equip_gear")


func _flush_quest_save() -> void:
	_quest_save_scheduled = false
	if player_data_provider != null:
		save_game()
