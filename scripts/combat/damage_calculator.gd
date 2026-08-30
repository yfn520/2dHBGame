class_name DamageCalculator
extends RefCounted

const ELEMENT_SOFT_CAP := 2.0
const ELEMENT_POST_SOFT_RATE := 0.35
const ELEMENT_HARD_CAP := 10.0
const ELEMENT_LAYER_FLOOR := 0.20

## 伤害结算器（设计案第5章）。
## 实现物理/魔法/真实三防御通道、防御系数 K 公式、穿透结算、
## 暴击/格挡/闪避/标签克制/易伤 乘区分离。
##
## 计算顺序（设计案 5.4/5.6）：
##   闪避判定 → 技能基础伤害 → 攻击侧增伤 → 暴击 → 标签克制
##   → 目标易伤 → 防御后倍率(K公式) → 格挡 → 最终伤害


## 攻击侧上下文。所有数值应在传入前经过 buff 修饰与上限钳制。
class DamageContext:
	var attacker_attack: float = 0.0       # 攻击力（已 buff 修饰）
	var skill_ratio: float = 1.0           # 技能倍率
	var flat_damage: int = 0               # 技能固定值
	var can_crit: bool = true              # 是否可暴击
	var crit_rate: float = 0.0             # 暴击率（已钳制 0~0.75）
	var crit_damage: float = 1.5           # 暴击伤害（已钳制 1.0~2.5）
	var damage_channel: String = "physical"  # "physical" / "magic" / "true"
	var damage_tag: String = "slash"       # 见 DamageTags.TAGS
	var physical_tag: String = ""           # none / slash / pierce / blunt
	var use_legacy_damage_tag: bool = true  # 仅缺少 V0.2 字段的旧节点为 true
	var primary_element: String = "none"
	var element_override: String = "inherit"
	var resolved_element: String = "none"
	var damage_scope: String = "direct"
	var element_damage_bonus_sources: Array = []
	var element_penetration_rating: Dictionary = {}
	var active_condition_ids: Array = []
	var element_relation_matrix: Dictionary = {}
	var element_soft_cap: float = 2.0
	var element_post_soft_rate: float = 0.35
	var element_hard_cap: float = 10.0
	var element_layer_floor: float = 0.20
	var attacker_damage_bonus: float = 0.0 # 攻击侧增伤加算（0.2 表示 +20%）
	var attacker_lifesteal: float = 0.0    # 吸血率（0~0.2）
	var armor_pen_percent: float = 0.0     # %护甲穿透（0~0.5）
	var armor_pen_flat: int = 0            # 固定护甲穿透
	var magic_pen_percent: float = 0.0     # %魔法穿透（0~0.5）
	var magic_pen_flat: int = 0            # 固定魔法穿透
	var can_dodge: bool = true             # 本伤是否可被闪避
	var can_block: bool = true             # 本伤是否可被格挡


## 防御端上下文。由目标读取。
class DefenseContext:
	var armor: int = 0                     # 护甲
	var magic_resist: int = 0              # 魔抗
	var block_rate: float = 0.0            # 格挡率（已钳制 0~0.6）
	var dodge_rate: float = 0.0            # 闪避率（已钳制 0~0.35）
	var target_level: int = 1              # 目标等级
	var vulnerability: float = 0.0         # 目标总易伤（钳制 0~0.5）
	var tag_resistance: Dictionary = {}    # {tag: multiplier}，由敌人特征提供
	# 标签级修正（设计案 8.2 感电/标记），由 buff 的 tag_modifier effect 聚合提供：
	# tag_vulnerability: {tag: 加算易伤率}，如 {"thunder": 0.25} 表示雷电伤害 +25%
	var tag_vulnerability: Dictionary = {}
	# tag_armor_pen: {tag: 额外护甲穿透率}，如 {"pierce": 0.2} 表示穿刺标签额外无视 20% 护甲
	var tag_armor_pen: Dictionary = {}
	# 全标签易伤（设计案 8.2 侵蚀）：每层 +1% 受伤，加算到 vuln_mult
	var global_vulnerability: float = 0.0
	var primary_element: String = "none"
	var element_resist_rating: Dictionary = {}
	var element_resist_cap: float = 0.35


## 计算最终伤害。返回结构：
## { "damage": int, "dodged": bool, "blocked": bool, "crit": bool }
func calculate(ctx: DamageContext, defense: DefenseContext) -> Dictionary:
	if ctx.can_dodge and randf() < defense.dodge_rate:
		return {"damage": 0, "dodged": true, "blocked": false, "crit": false}
	var crit := ctx.can_crit and randf() < ctx.crit_rate
	var blocked := ctx.can_block and randf() < defense.block_rate
	return _calculate_hit(ctx, defense, crit, blocked)


func _calculate_hit(ctx: DamageContext, defense: DefenseContext, crit: bool, blocked: bool) -> Dictionary:
	var base := ctx.attacker_attack * ctx.skill_ratio + float(ctx.flat_damage)
	var attacker_mult := 1.0 + ctx.attacker_damage_bonus
	var crit_mult := ctx.crit_damage if crit else 1.0
	var tag_key := _resolved_physical_tag(ctx)
	var tag_mult := float(defense.tag_resistance.get(tag_key, 1.0)) if not tag_key.is_empty() else 1.0
	var tag_vuln := float(defense.tag_vulnerability.get(tag_key, 0.0)) if not tag_key.is_empty() else 0.0
	var vuln_mult := 1.0 + clampf(defense.vulnerability + tag_vuln + defense.global_vulnerability, 0.0, 0.5)
	var element_layer := calculate_element_layer(ctx, defense)
	var def_value := _get_effective_defense(ctx, defense, tag_key)
	var k := 100 + 20 * maxi(1, defense.target_level)
	var def_mult := float(k) / float(k + def_value)
	var block_mult := 0.5 if blocked else 1.0
	var final := int(round(base * attacker_mult * crit_mult * tag_mult * vuln_mult * float(element_layer["total_multiplier"]) * def_mult * block_mult))
	final = maxi(1, final)
	return {
		"damage": final,
		"dodged": false,
		"blocked": blocked,
		"crit": crit,
		"channel": ctx.damage_channel,
		"physical_tag": tag_key if not tag_key.is_empty() else "none",
		"resolved_element": element_layer["resolved_element"],
		"element_raw_multiplier": element_layer["raw_multiplier"],
		"element_effective_multiplier": element_layer["effective_multiplier"],
		"element_relation_multiplier": element_layer["relation_multiplier"],
		"element_total_multiplier": element_layer["total_multiplier"],
	}


## 有效防御 = max(0, 防御 × (1 - %穿透) - 固定穿透)（设计案 5.2）
## 物理→护甲+护甲穿透；魔法→魔抗+魔法穿透；真实→0
## 标签穿甲（设计案 8.2 标记）：物理标签可叠加额外护甲穿透，仅影响该标签的伤害。
func _get_effective_defense(ctx: DamageContext, defense: DefenseContext, tag_key: String = "") -> int:
	# 标签级护甲穿透（仅物理通道生效，标记设计为针对护甲）
	var tag_pen := float(defense.tag_armor_pen.get(tag_key, 0.0)) if not tag_key.is_empty() else 0.0
	match ctx.damage_channel:
		"physical":
			var total_pen := clampf(ctx.armor_pen_percent + tag_pen, 0.0, 1.0)
			return maxi(0, int(float(defense.armor) * (1.0 - total_pen)) - ctx.armor_pen_flat)
		"magic":
			return maxi(0, int(float(defense.magic_resist) * (1.0 - ctx.magic_pen_percent)) - ctx.magic_pen_flat)
		"true":
			return 0
	return 0


## 用固定随机种子计算（用于单测/验证），不调用 randf。
func calculate_deterministic(ctx: DamageContext, defense: DefenseContext, rng_value: float) -> Dictionary:
	if ctx.can_dodge and rng_value < defense.dodge_rate:
		return {"damage": 0, "dodged": true, "blocked": false, "crit": false}
	var crit := ctx.can_crit and rng_value < ctx.crit_rate
	var blocked := ctx.can_block and rng_value < defense.block_rate
	return _calculate_hit(ctx, defense, crit, blocked)


## V0.2 元素层：逐来源乘算、软上限、克制关系与元素抗性。
static func calculate_element_layer(ctx: DamageContext, defense: DefenseContext) -> Dictionary:
	var resolved := normalize_element(ctx.resolved_element)
	if resolved == "none":
		resolved = resolve_element(ctx.damage_channel, ctx.primary_element, ctx.element_override, ctx.damage_tag if ctx.use_legacy_damage_tag else "")
	if ctx.damage_channel == "true" or resolved == "none":
		return _empty_element_layer()

	var raw_multiplier := 1.0
	var matching_sources: Array = []
	for source_value in ctx.element_damage_bonus_sources:
		if not source_value is Dictionary:
			continue
		var source: Dictionary = source_value
		if normalize_element(source.get("element_tag", source.get("elementTag", "none"))) != resolved:
			continue
		var source_scope := str(source.get("damage_scope", source.get("damageScope", "all")))
		if source_scope != "all" and source_scope != ctx.damage_scope:
			continue
		var condition_id := str(source.get("condition_id", source.get("conditionId", "")))
		if not condition_id.is_empty() and not ctx.active_condition_ids.has(condition_id):
			continue
		var value := float(source.get("value", 0.0))
		raw_multiplier *= maxf(0.0, 1.0 + value)
		matching_sources.append(source)

	var soft_cap := maxf(1.0, ctx.element_soft_cap)
	var effective_multiplier := raw_multiplier
	if raw_multiplier > soft_cap:
		effective_multiplier = soft_cap + (raw_multiplier - soft_cap) * maxf(0.0, ctx.element_post_soft_rate)
	effective_multiplier = minf(maxf(0.0, ctx.element_hard_cap), effective_multiplier)

	var resistance := maxf(0.0, _element_map_value(defense.element_resist_rating, resolved))
	var penetration := maxf(0.0, _element_map_value(ctx.element_penetration_rating, resolved))
	var effective_resistance := maxf(0.0, resistance - penetration)
	var k := float(100 + 20 * maxi(1, defense.target_level))
	var resistance_reduction := effective_resistance / (effective_resistance + k)
	var capped_reduction := minf(resistance_reduction, clampf(defense.element_resist_cap, 0.0, 0.5))
	var target_element := normalize_element(defense.primary_element)
	var relation_base := _relation_base(ctx.element_relation_matrix, resolved, target_element)
	var relation_multiplier := maxf(maxf(0.0, ctx.element_layer_floor), relation_base - capped_reduction)
	return {
		"resolved_element": resolved,
		"matching_sources": matching_sources,
		"raw_multiplier": raw_multiplier,
		"effective_multiplier": effective_multiplier,
		"effective_resistance": effective_resistance,
		"resistance_reduction": capped_reduction,
		"resistance_multiplier": 1.0 - capped_reduction,
		"relation_base": relation_base,
		"relation_multiplier": relation_multiplier,
		"total_multiplier": effective_multiplier * relation_multiplier,
	}


static func resolve_element(damage_channel: String, primary_element: Variant, element_override: Variant = "inherit", legacy_damage_tag: Variant = "") -> String:
	if damage_channel == "true":
		return "none"
	var raw_override := str(element_override).to_lower()
	if raw_override in ["none", "无"]:
		return "none"
	if not raw_override.is_empty() and raw_override not in ["inherit", "继承"]:
		return normalize_element(raw_override)
	var legacy_element := normalize_element(legacy_damage_tag)
	if legacy_element != "none":
		return legacy_element
	return normalize_element(primary_element)


static func normalize_element(value: Variant) -> String:
	match str(value).to_lower():
		"fire", "火焰": return "fire"
		"frost", "ice", "冰霜": return "frost"
		"lightning", "thunder", "雷电": return "lightning"
		"holy", "神圣": return "holy"
		"poison", "毒素": return "poison"
		"abyss", "深渊": return "abyss"
	return "none"


static func reaction_element_tag(resolved_element: String) -> String:
	return "thunder" if normalize_element(resolved_element) == "lightning" else normalize_element(resolved_element)


static func _empty_element_layer() -> Dictionary:
	return {
		"resolved_element": "none",
		"matching_sources": [],
		"raw_multiplier": 1.0,
		"effective_multiplier": 1.0,
		"effective_resistance": 0.0,
		"resistance_reduction": 0.0,
		"resistance_multiplier": 1.0,
		"relation_base": 1.0,
		"relation_multiplier": 1.0,
		"total_multiplier": 1.0,
	}


static func _relation_base(matrix: Dictionary, attacker: String, defender: String) -> float:
	if attacker == "none" or defender == "none":
		return 1.0
	var attacker_key := "thunder" if attacker == "lightning" and not matrix.has(attacker) else attacker
	var row_value: Variant = matrix.get(attacker_key, {})
	if not row_value is Dictionary:
		return 1.0
	var row: Dictionary = row_value
	var defender_key := "thunder" if defender == "lightning" and not row.has(defender) else defender
	return float(row.get(defender_key, 1.0))


static func _element_map_value(values: Dictionary, element: String) -> float:
	if values.has(element):
		return float(values[element])
	if element == "lightning" and values.has("thunder"):
		return float(values["thunder"])
	return 0.0


func _resolved_physical_tag(ctx: DamageContext) -> String:
	if ctx.damage_channel == "true":
		return ""
	if ctx.damage_channel == "physical" and ctx.physical_tag in ["slash", "pierce", "blunt"]:
		return ctx.physical_tag
	if ctx.use_legacy_damage_tag and ctx.damage_tag in ["slash", "pierce", "blunt", "fire", "frost", "thunder", "lightning", "holy", "poison", "abyss"]:
		return ctx.damage_tag
	return ""
