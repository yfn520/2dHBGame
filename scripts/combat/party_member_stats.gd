extends BaseCombatStats
## 队友战斗属性：从 GameRegistry 单例读取角色配置 + 装备加成，同步 hp 到 roster。

var character_id: int = 0
var level: int = 1
var exp: int = 0


func setup(p_character_id: int) -> void:
	character_id = p_character_id
	# 设置默认值（基类默认为 0）
	max_hp = 100
	attack = 1
	defense = 0
	move_speed = 220.0
	crit_rate = 0.0
	crit_damage = 1.5
	attack_speed = 1.0
	recalculate(false)


func recalculate(preserve_current_hp: bool = true) -> void:
	if character_id <= 0:
		return
	super.recalculate(preserve_current_hp)
	sync_hp_to_roster()


func sync_hp_to_roster() -> void:
	if GameRegistry.roster_data != null and character_id > 0:
		GameRegistry.roster_data.set_hp(hp, character_id)


func _get_base_stats_dict() -> Dictionary:
	if character_id <= 0:
		return {}
	var roster = GameRegistry.roster_data
	var config = GameRegistry.character_config
	if roster != null:
		roster.ensure_character(character_id)
		level = roster.get_level(character_id)
		exp = roster.get_exp(character_id)
	if config == null:
		return {}
	return config.get_stats_at_level(character_id, level)


func _get_equipped_items() -> Array:
	if GameRegistry.equipment_provider == null:
		return []
	return GameRegistry.equipment_provider.get_equipped_configs(character_id)


func _get_stored_hp() -> int:
	if GameRegistry.roster_data == null or character_id <= 0:
		return 0
	return int(GameRegistry.roster_data.get_hp(character_id))
