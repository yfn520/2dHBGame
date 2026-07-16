class_name CharacterStats
extends BaseCombatStats
## 角色属性（菜单场景用）：依赖注入 roster + character_config，区分 base_* 与 final，
## 支持 signal / take_damage / heal / to_dict / from_dict。
## recalculate 签名与基类一致；装备列表通过 _get_equipped_items 钩子从 GameRegistry.equipment_provider 获取。

signal stats_changed()

var base_max_hp: int = 250
var base_attack: int = 1
var base_defense: int = 0
var base_move_speed: float = 220.0
var base_crit_rate: float = 0.0
var base_crit_damage: float = 1.5
var base_attack_speed: float = 1.0

var character_id: int = 0
var level: int = 1
var exp: int = 0

var _roster: CharacterRosterData
var _character_config: CharacterConfigData


func setup(roster: CharacterRosterData, character_config: CharacterConfigData) -> void:
	_roster = roster
	_character_config = character_config
	if _roster != null and not _roster.active_character_changed.is_connected(_on_active_character_changed):
		_roster.active_character_changed.connect(_on_active_character_changed)
	if _roster != null and not _roster.character_progress_changed.is_connected(_on_character_progress_changed):
		_roster.character_progress_changed.connect(_on_character_progress_changed)
	recalculate()


func _on_active_character_changed(_character_id: int) -> void:
	recalculate()


func _on_character_progress_changed(changed_character_id: int) -> void:
	if changed_character_id == character_id:
		recalculate(false)


func recalculate(preserve_current_hp: bool = true) -> void:
	# 设置默认值（首次或 active 切换时）
	max_hp = 250
	attack = 1
	defense = 0
	move_speed = 220.0
	crit_rate = 0.0
	crit_damage = 1.5
	attack_speed = 1.0
	super.recalculate(preserve_current_hp)
	stats_changed.emit()


func _get_base_stats_dict() -> Dictionary:
	if _roster != null:
		character_id = _roster.active_character_id
		level = _roster.get_level(character_id)
		exp = _roster.get_exp(character_id)
	else:
		character_id = 0
		level = 1
		exp = 0

	var base_stats := {}
	if _character_config != null and character_id != 0:
		base_stats = _character_config.get_stats_at_level(character_id, level)

	# 同步 base_*（CharacterStats 独有：区分裸属性与最终属性）
	base_max_hp = int(base_stats.get("max_hp", base_max_hp))
	base_attack = int(base_stats.get("attack", base_attack))
	base_defense = int(base_stats.get("defense", base_defense))
	base_move_speed = float(base_stats.get("move_speed", base_move_speed))
	base_crit_rate = float(base_stats.get("crit_rate", base_crit_rate))
	base_crit_damage = float(base_stats.get("crit_damage", base_crit_damage))
	base_attack_speed = float(base_stats.get("attack_speed", base_attack_speed))

	# 返回 base_* 作为 final 的初始值（基类会读 dict 覆盖 final 字段）
	return {
		"max_hp": base_max_hp,
		"attack": base_attack,
		"defense": base_defense,
		"move_speed": base_move_speed,
		"crit_rate": base_crit_rate,
		"crit_damage": base_crit_damage,
		"attack_speed": base_attack_speed,
	}


func _get_equipped_items() -> Array:
	return _get_current_equipped_configs()


func _get_stored_hp() -> int:
	if _roster == null or character_id == 0:
		return 0
	return int(_roster.get_hp(character_id))


func _on_recalculated() -> void:
	if _roster != null and character_id != 0:
		_roster.set_hp(hp, character_id)


func take_damage(amount: int) -> int:
	var actual := maxi(1, amount - defense)
	hp = maxi(0, hp - actual)
	if _roster != null and character_id != 0:
		_roster.set_hp(hp, character_id)
	stats_changed.emit()
	return actual


func heal(amount: int) -> int:
	var actual := mini(amount, max_hp - hp)
	hp += actual
	if _roster != null and character_id != 0:
		_roster.set_hp(hp, character_id)
	stats_changed.emit()
	return actual


func _get_current_equipped_configs() -> Array[Dictionary]:
	if GameRegistry.equipment_provider != null:
		return GameRegistry.equipment_provider.get_equipped_configs()
	return []


func to_dict() -> Dictionary:
	return {
		"base_max_hp": base_max_hp,
		"base_attack": base_attack,
		"base_defense": base_defense,
		"base_move_speed": base_move_speed,
		"base_crit_rate": base_crit_rate,
		"base_crit_damage": base_crit_damage,
		"base_attack_speed": base_attack_speed,
		"hp": hp,
	}


func from_dict(data: Dictionary) -> void:
	base_max_hp = int(data.get("base_max_hp", base_max_hp))
	base_attack = int(data.get("base_attack", base_attack))
	base_defense = int(data.get("base_defense", base_defense))
	base_move_speed = float(data.get("base_move_speed", base_move_speed))
	base_crit_rate = float(data.get("base_crit_rate", base_crit_rate))
	base_crit_damage = float(data.get("base_crit_damage", base_crit_damage))
	base_attack_speed = float(data.get("base_attack_speed", base_attack_speed))
	max_hp = base_max_hp
	hp = int(data.get("hp", max_hp))
	if hp <= 0:
		hp = max_hp
