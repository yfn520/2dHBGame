class_name BaseCombatStats
extends RefCounted
## 战斗属性基类：承载 8 个战斗属性 + is_alive + recalculate 模板方法。
## 子类通过 override _get_base_stats_dict / _get_equipped_items / _get_stored_hp / _on_recalculated
## 提供各自的数据源（构造 dict / GameRegistry 单例 / 注入引用）。

var max_hp: int = 0
var hp: int = 0
var attack: int = 0
var defense: int = 0
var move_speed: float = 0.0
var crit_rate: float = 0.0
var crit_damage: float = 1.5
var attack_speed: float = 1.0
# 设计案第3章 MVP 属性扩展
var magic_resist: int = 0           # 魔抗
var block_rate: float = 0.0         # 格挡率（0~0.6）
var dodge_rate: float = 0.0         # 闪避率（0~0.35）
var status_resist: float = 0.0      # 异常抗性（0~1.0）
var status_intensity: float = 0.0    # 异常强度（攻击方，0~2.0，放大施加的 buildup）
var skill_haste: float = 0.0        # 技能急速
var armor_pen_percent: float = 0.0  # %护甲穿透（0~0.5）
var armor_pen_flat: int = 0         # 固定护甲穿透
var magic_pen_percent: float = 0.0  # %魔法穿透（0~0.5）
var magic_pen_flat: int = 0         # 固定魔法穿透
var heal_bonus: float = 0.0         # 治疗强度（加算乘区）
var shield_bonus: float = 0.0       # 护盾强度（加算乘区）
var heal_received: float = 0.0      # 受疗加成（0~1.0）
var lifesteal: float = 0.0          # 吸血（0~0.2）
var reflect_rate: float = 0.0       # 反伤率（0~0.5，反伤上限 8% 攻击者最大生命）
var abyss_cost: float = 0.0         # 深渊装备代价：每秒给自己施加的侵蚀 buildup（设计案 4.3）


func is_alive() -> bool:
	return hp > 0


## 模板方法：子类提供基础 dict + 装备列表 + stored hp，基类统一算最终值与 hp 封顶。
## 用当前字段值作为 fallback，子类可在 init/setup 中设置默认值。
func recalculate(preserve_current_hp: bool = true) -> void:
	var base_stats: Dictionary = _get_base_stats_dict()
	var equipped_items: Array = _get_equipped_items()

	max_hp = int(base_stats.get("max_hp", max_hp))
	attack = int(base_stats.get("attack", attack))
	defense = int(base_stats.get("defense", defense))
	move_speed = float(base_stats.get("move_speed", move_speed))
	crit_rate = float(base_stats.get("crit_rate", crit_rate))
	crit_damage = float(base_stats.get("crit_damage", crit_damage))
	attack_speed = float(base_stats.get("attack_speed", attack_speed))
	# 设计案第3章 MVP 属性扩展
	magic_resist = int(base_stats.get("magic_resist", magic_resist))
	block_rate = float(base_stats.get("block_rate", block_rate))
	dodge_rate = float(base_stats.get("dodge_rate", dodge_rate))
	status_resist = float(base_stats.get("status_resist", status_resist))
	status_intensity = float(base_stats.get("status_intensity", status_intensity))
	skill_haste = float(base_stats.get("skill_haste", skill_haste))
	armor_pen_percent = float(base_stats.get("armor_pen_percent", armor_pen_percent))
	armor_pen_flat = int(base_stats.get("armor_pen_flat", armor_pen_flat))
	magic_pen_percent = float(base_stats.get("magic_pen_percent", magic_pen_percent))
	magic_pen_flat = int(base_stats.get("magic_pen_flat", magic_pen_flat))
	heal_bonus = float(base_stats.get("heal_bonus", heal_bonus))
	shield_bonus = float(base_stats.get("shield_bonus", shield_bonus))
	heal_received = float(base_stats.get("heal_received", heal_received))
	lifesteal = float(base_stats.get("lifesteal", lifesteal))
	reflect_rate = float(base_stats.get("reflect_rate", reflect_rate))
	abyss_cost = float(base_stats.get("abyss_cost", abyss_cost))

	for equip_info in equipped_items:
		if not equip_info is Dictionary:
			continue
		var item_stats: Dictionary = equip_info.get("stats", {})
		max_hp += int(item_stats.get("max_hp", 0))
		attack += int(item_stats.get("attack", 0))
		defense += int(item_stats.get("defense", 0))
		move_speed += float(item_stats.get("move_speed", 0.0))
		crit_rate += float(item_stats.get("crit_rate", 0.0))
		crit_damage += float(item_stats.get("crit_damage", 0.0))
		attack_speed += float(item_stats.get("attack_speed", 0.0))
		# 装备扩展属性（默认 0，旧装备不破）
		magic_resist += int(item_stats.get("magic_resist", 0))
		block_rate += float(item_stats.get("block_rate", 0.0))
		dodge_rate += float(item_stats.get("dodge_rate", 0.0))
		status_resist += float(item_stats.get("status_resist", 0.0))
		status_intensity += float(item_stats.get("status_intensity", 0.0))
		skill_haste += float(item_stats.get("skill_haste", 0.0))
		armor_pen_percent += float(item_stats.get("armor_pen_percent", 0.0))
		armor_pen_flat += int(item_stats.get("armor_pen_flat", 0))
		magic_pen_percent += float(item_stats.get("magic_pen_percent", 0.0))
		magic_pen_flat += int(item_stats.get("magic_pen_flat", 0))
		heal_bonus += float(item_stats.get("heal_bonus", 0.0))
		shield_bonus += float(item_stats.get("shield_bonus", 0.0))
		heal_received += float(item_stats.get("heal_received", 0.0))
		lifesteal += float(item_stats.get("lifesteal", 0.0))
		reflect_rate += float(item_stats.get("reflect_rate", 0.0))
		abyss_cost += float(item_stats.get("abyss_cost", 0.0))

	# 属性上限钳制（设计案第3.3节）
	crit_rate = clampf(crit_rate, 0.0, 0.75)
	crit_damage = clampf(crit_damage, 1.0, 2.5)
	block_rate = clampf(block_rate, 0.0, 0.6)
	dodge_rate = clampf(dodge_rate, 0.0, 0.35)
	attack_speed = clampf(attack_speed, 0.1, 2.5)
	armor_pen_percent = clampf(armor_pen_percent, 0.0, 0.5)
	magic_pen_percent = clampf(magic_pen_percent, 0.0, 0.5)
	lifesteal = clampf(lifesteal, 0.0, 0.2)
	reflect_rate = clampf(reflect_rate, 0.0, 0.5)
	abyss_cost = maxf(0.0, abyss_cost)  # 深渊装备代价 ≥0（每秒侵蚀 buildup）
	status_resist = clampf(status_resist, 0.0, 1.0)
	status_intensity = clampf(status_intensity, 0.0, 2.0)
	heal_received = clampf(heal_received, -0.8, 1.0)  # 下限 -0.8 保底 20% 治疗（设计案7.1）

	var stored_hp: int = _get_stored_hp()
	if stored_hp > 0:
		hp = mini(stored_hp, max_hp)
	elif preserve_current_hp and hp > 0:
		hp = mini(hp, max_hp)
	else:
		hp = max_hp

	_on_recalculated()


# === 子类 override 的钩子 ===

## 返回基础属性 dict（enemies.json 配置 / characters.json 的 stats_at_level 段）
func _get_base_stats_dict() -> Dictionary:
	return {}


## 返回装备列表 [{stats: {max_hp, attack, ...}}, ...]；EnemyStats 返回 []
func _get_equipped_items() -> Array:
	return []


## 返回持久层存储的 hp（roster.hp）；EnemyStats 返回 0
func _get_stored_hp() -> int:
	return 0


## recalculate 完成后的钩子（同步 roster / emit 信号等）
func _on_recalculated() -> void:
	pass
