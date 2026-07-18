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
# 设计案第3章 MVP 属性扩展（base_* 镜像基类扩展字段，区分裸属性与最终属性）
var base_magic_resist: int = 0
var base_block_rate: float = 0.0
var base_dodge_rate: float = 0.0
var base_status_resist: float = 0.0
var base_skill_haste: float = 0.0
var base_armor_pen_percent: float = 0.0
var base_armor_pen_flat: int = 0
var base_magic_pen_percent: float = 0.0
var base_magic_pen_flat: int = 0
var base_heal_bonus: float = 0.0
var base_shield_bonus: float = 0.0
var base_heal_received: float = 0.0
var base_lifesteal: float = 0.0
var base_reflect_rate: float = 0.0

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
	# 扩展字段默认值（基类 recalculate 会从 base_stats dict 读取覆盖）
	magic_resist = 0
	block_rate = 0.0
	dodge_rate = 0.0
	status_resist = 0.0
	skill_haste = 0.0
	armor_pen_percent = 0.0
	armor_pen_flat = 0
	magic_pen_percent = 0.0
	magic_pen_flat = 0
	heal_bonus = 0.0
	shield_bonus = 0.0
	heal_received = 0.0
	lifesteal = 0.0
	reflect_rate = 0.0
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
	# 扩展字段 base_* 同步
	base_magic_resist = int(base_stats.get("magic_resist", base_magic_resist))
	base_block_rate = float(base_stats.get("block_rate", base_block_rate))
	base_dodge_rate = float(base_stats.get("dodge_rate", base_dodge_rate))
	base_status_resist = float(base_stats.get("status_resist", base_status_resist))
	base_skill_haste = float(base_stats.get("skill_haste", base_skill_haste))
	base_armor_pen_percent = float(base_stats.get("armor_pen_percent", base_armor_pen_percent))
	base_armor_pen_flat = int(base_stats.get("armor_pen_flat", base_armor_pen_flat))
	base_magic_pen_percent = float(base_stats.get("magic_pen_percent", base_magic_pen_percent))
	base_magic_pen_flat = int(base_stats.get("magic_pen_flat", base_magic_pen_flat))
	base_heal_bonus = float(base_stats.get("heal_bonus", base_heal_bonus))
	base_shield_bonus = float(base_stats.get("shield_bonus", base_shield_bonus))
	base_heal_received = float(base_stats.get("heal_received", base_heal_received))
	base_lifesteal = float(base_stats.get("lifesteal", base_lifesteal))
	base_reflect_rate = float(base_stats.get("reflect_rate", base_reflect_rate))

	# 返回完整 base_stats dict 给基类 recalculate 读取（扩展字段必须转发，否则 final 全 0）
	return base_stats


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
		"base_magic_resist": base_magic_resist,
		"base_block_rate": base_block_rate,
		"base_dodge_rate": base_dodge_rate,
		"base_status_resist": base_status_resist,
		"base_skill_haste": base_skill_haste,
		"base_armor_pen_percent": base_armor_pen_percent,
		"base_armor_pen_flat": base_armor_pen_flat,
		"base_magic_pen_percent": base_magic_pen_percent,
		"base_magic_pen_flat": base_magic_pen_flat,
		"base_heal_bonus": base_heal_bonus,
		"base_shield_bonus": base_shield_bonus,
		"base_heal_received": base_heal_received,
		"base_lifesteal": base_lifesteal,
		"base_reflect_rate": base_reflect_rate,
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
	base_magic_resist = int(data.get("base_magic_resist", base_magic_resist))
	base_block_rate = float(data.get("base_block_rate", base_block_rate))
	base_dodge_rate = float(data.get("base_dodge_rate", base_dodge_rate))
	base_status_resist = float(data.get("base_status_resist", base_status_resist))
	base_skill_haste = float(data.get("base_skill_haste", base_skill_haste))
	base_armor_pen_percent = float(data.get("base_armor_pen_percent", base_armor_pen_percent))
	base_armor_pen_flat = int(data.get("base_armor_pen_flat", base_armor_pen_flat))
	base_magic_pen_percent = float(data.get("base_magic_pen_percent", base_magic_pen_percent))
	base_magic_pen_flat = int(data.get("base_magic_pen_flat", base_magic_pen_flat))
	base_heal_bonus = float(data.get("base_heal_bonus", base_heal_bonus))
	base_shield_bonus = float(data.get("base_shield_bonus", base_shield_bonus))
	base_heal_received = float(data.get("base_heal_received", base_heal_received))
	base_lifesteal = float(data.get("base_lifesteal", base_lifesteal))
	base_reflect_rate = float(data.get("base_reflect_rate", base_reflect_rate))
	max_hp = base_max_hp
	hp = int(data.get("hp", max_hp))
	if hp <= 0:
		hp = max_hp
