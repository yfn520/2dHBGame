class_name DamageCalculator
extends RefCounted

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


## 计算最终伤害。返回结构：
## { "damage": int, "dodged": bool, "blocked": bool, "crit": bool }
func calculate(ctx: DamageContext, defense: DefenseContext) -> Dictionary:
	# 1. 闪避判定（设计案 5.6：闪避成功不造成伤害和命中类异常积累）
	if ctx.can_dodge and randf() < defense.dodge_rate:
		return {"damage": 0, "dodged": true, "blocked": false, "crit": false}
	# 2. 技能基础伤害 = 攻击力 × 倍率 + 固定值（设计案 5.1）
	var base := ctx.attacker_attack * ctx.skill_ratio + float(ctx.flat_damage)
	# 3. 攻击侧增伤（加算乘区，设计案 5.4）
	var attacker_mult := 1.0 + ctx.attacker_damage_bonus
	# 4. 暴击判定
	var crit := ctx.can_crit and randf() < ctx.crit_rate
	var crit_mult := ctx.crit_damage if crit else 1.0
	# 5. 标签克制（由 tag_resistance 查表，默认 1.0）
	var tag_mult := float(defense.tag_resistance.get(ctx.damage_tag, 1.0))
	# 6. 目标易伤（总易伤钳制 0~0.5，设计案 5.4）+ 标签级易伤（设计案 8.2 感电）+ 全标签易伤（侵蚀）
	var vuln_mult := 1.0 + clampf(defense.vulnerability, 0.0, 0.5)
	var tag_vuln := float(defense.tag_vulnerability.get(ctx.damage_tag, 0.0))
	vuln_mult *= (1.0 + tag_vuln + defense.global_vulnerability)
	# 7. 防御后倍率（K 公式，设计案 5.3）。标签穿甲（设计案 8.2 标记）叠加到该标签的护甲穿透上。
	var def_value := _get_effective_defense(ctx, defense)
	var k := 100 + 20 * defense.target_level
	var def_mult := float(k) / float(k + def_value)
	# 8. 格挡判定（设计案 5.7：格挡默认减伤 50%）
	var blocked := ctx.can_block and randf() < defense.block_rate
	var block_mult := 0.5 if blocked else 1.0
	# 9. 最终伤害 = 基础 × 增伤 × 暴击 × 标签 × 易伤 × 防御后 × 格挡
	var final := int(round(base * attacker_mult * crit_mult * tag_mult * vuln_mult * def_mult * block_mult))
	final = maxi(1, final)  # 下限 1
	return {"damage": final, "dodged": false, "blocked": blocked, "crit": crit}


## 有效防御 = max(0, 防御 × (1 - %穿透) - 固定穿透)（设计案 5.2）
## 物理→护甲+护甲穿透；魔法→魔抗+魔法穿透；真实→0
## 标签穿甲（设计案 8.2 标记）：物理标签可叠加额外护甲穿透，仅影响该标签的伤害。
func _get_effective_defense(ctx: DamageContext, defense: DefenseContext) -> int:
	# 标签级护甲穿透（仅物理通道生效，标记设计为针对护甲）
	var tag_pen := float(defense.tag_armor_pen.get(ctx.damage_tag, 0.0))
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
	# rng_value 同时用于闪避/暴击/格挡三次判定（单测简化）
	if ctx.can_dodge and rng_value < defense.dodge_rate:
		return {"damage": 0, "dodged": true, "blocked": false, "crit": false}
	var base := ctx.attacker_attack * ctx.skill_ratio + float(ctx.flat_damage)
	var attacker_mult := 1.0 + ctx.attacker_damage_bonus
	var crit := ctx.can_crit and rng_value < ctx.crit_rate
	var crit_mult := ctx.crit_damage if crit else 1.0
	var tag_mult := float(defense.tag_resistance.get(ctx.damage_tag, 1.0))
	var vuln_mult := 1.0 + clampf(defense.vulnerability, 0.0, 0.5)
	vuln_mult *= (1.0 + float(defense.tag_vulnerability.get(ctx.damage_tag, 0.0)) + defense.global_vulnerability)
	var def_value := _get_effective_defense(ctx, defense)
	var k := 100 + 20 * defense.target_level
	var def_mult := float(k) / float(k + def_value)
	var blocked := ctx.can_block and rng_value < defense.block_rate
	var block_mult := 0.5 if blocked else 1.0
	var final := int(round(base * attacker_mult * crit_mult * tag_mult * vuln_mult * def_mult * block_mult))
	final = maxi(1, final)
	return {"damage": final, "dodged": false, "blocked": blocked, "crit": crit}
