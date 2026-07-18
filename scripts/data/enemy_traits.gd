class_name EnemyTraits
extends RefCounted

## 敌人特征系统（设计案第10章）。
## P0 实现 5 种 MVP 特征：肉身/重甲/构造体/亡灵/护盾。
## P1 补齐 8 种：甲壳/高魔抗/快速/高闪避/再生/深渊/后排施法/群体。
## 每种特征提供：护甲修正、魔抗修正、标签倍率表、异常免疫列表、异常阈值修正（可选）。
## abyss 标签（设计案 4.3）也在 tag_multipliers 中体现：深渊特征怪受 abyss 标签伤害正常，其他标签部分减免。

const TRAITS := [
	"flesh", "heavy_armor", "construct", "undead", "shielded",
	"shell", "high_mr", "fast", "high_dodge", "regen", "abyss", "back_caster", "swarm"
]

const TRAIT_DATA := {
	"flesh": {
		"label": "肉身",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"slash": 1.15, "fire": 1.15, "poison": 1.15,
			"pierce": 1.0, "blunt": 1.0, "frost": 1.0, "thunder": 1.0, "holy": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"heavy_armor": {
		"label": "重甲",
		"armor_modifier": 50.0,
		"magic_resist_modifier": -10.0,
		"tag_multipliers": {
			"slash": 0.9, "pierce": 0.8, "blunt": 1.25,
			"fire": 1.0, "frost": 1.0, "thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"construct": {
		"label": "构造体",
		"armor_modifier": 30.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"blunt": 1.25, "thunder": 1.25, "poison": 0.0,
			"slash": 1.0, "pierce": 1.0, "fire": 1.0, "frost": 1.0, "holy": 1.0, "abyss": 1.0,
		},
		"status_immunities": ["poison"],
	},
	"undead": {
		"label": "亡灵",
		"armor_modifier": 10.0,
		"magic_resist_modifier": 10.0,
		"tag_multipliers": {
			"holy": 1.30, "fire": 1.15, "poison": 0.0,
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "frost": 1.0, "thunder": 1.0, "abyss": 1.0,
		},
		"status_immunities": ["poison"],
	},
	"shielded": {
		"label": "护盾",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"blunt": 1.30, "thunder": 1.30,
			"slash": 1.0, "pierce": 1.0, "fire": 1.0, "frost": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	# === P1 新增 8 种 ===
	"shell": {
		# 甲壳：正面减伤简化为常驻物理减伤（slash/pierce 0.85），钝击克制
		"label": "甲壳",
		"armor_modifier": 20.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"slash": 0.85, "pierce": 0.85, "blunt": 1.20,
			"fire": 1.0, "frost": 1.0, "thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"high_mr": {
		# 高魔抗：高魔抗、较低护甲
		"label": "高魔抗",
		"armor_modifier": -10.0,
		"magic_resist_modifier": 40.0,
		"tag_multipliers": {
			"fire": 0.85, "frost": 0.85, "thunder": 0.85, "holy": 0.85, "poison": 0.85,
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"fast": {
		# 快速：高移速/高攻速（数值修正，不改 AI）；闪避略高
		"label": "快速",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "fire": 1.0, "frost": 1.0,
			"thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"high_dodge": {
		# 高闪避：基础 dodge_rate 由 enemy_stats 读取后加 0.30（通过 stat_modifier 字段）
		"label": "高闪避",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "fire": 1.0, "frost": 1.0,
			"thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"regen": {
		# 再生：每秒回血 2% max_hp（由 enemy_stats._process 处理）
		"label": "再生",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "fire": 1.0, "frost": 1.0,
			"thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"abyss": {
		# 深渊：高异常抗性（status_threshold_modifier ×2）、免疫侵蚀、受神圣伤害加成
		"label": "深渊",
		"armor_modifier": 20.0,
		"magic_resist_modifier": 20.0,
		"tag_multipliers": {
			"holy": 1.30, "abyss": 0.5,
			"slash": 0.9, "pierce": 0.9, "blunt": 0.9, "fire": 0.9, "frost": 0.9,
			"thunder": 0.9, "poison": 0.9,
		},
		"status_immunities": ["erosion"],
		"status_threshold_modifier": 2.0,  # 异常阈值 ×2，更难触发异常
	},
	"back_caster": {
		# 后排施法：保持距离（AI 层 attack_range +50%，数值层无修正）
		"label": "后排施法",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 10.0,
		"tag_multipliers": {
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "fire": 1.0, "frost": 1.0,
			"thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
	"swarm": {
		# 群体：配置层特征（数量多），单位本身无数值修正
		"label": "群体",
		"armor_modifier": 0.0,
		"magic_resist_modifier": 0.0,
		"tag_multipliers": {
			"slash": 1.0, "pierce": 1.0, "blunt": 1.0, "fire": 1.0, "frost": 1.0,
			"thunder": 1.0, "holy": 1.0, "poison": 1.0, "abyss": 1.0,
		},
		"status_immunities": [],
	},
}


## 获取特征的中文标签
static func get_trait_label(trait_id: String) -> String:
	var data: Dictionary = TRAIT_DATA.get(trait_id, {})
	return String(data.get("label", trait_id))


## 聚合多个特征的标签倍率表（主特征 + 次要特征）。
## 同一标签多次出现时取乘法叠加。
static func get_combined_tag_multipliers(traits: Array) -> Dictionary:
	var result: Dictionary = {}
	for trait_id in traits:
		var data: Dictionary = TRAIT_DATA.get(String(trait_id), {})
		var mults: Dictionary = data.get("tag_multipliers", {})
		for tag in mults:
			var mult := float(mults[tag])
			if result.has(tag):
				result[tag] = float(result[tag]) * mult
			else:
				result[tag] = mult
	return result


## 聚合多个特征的护甲修正
static func get_combined_armor_modifier(traits: Array) -> float:
	var total := 0.0
	for trait_id in traits:
		var data: Dictionary = TRAIT_DATA.get(String(trait_id), {})
		total += float(data.get("armor_modifier", 0.0))
	return total


## 聚合多个特征的魔抗修正
static func get_combined_magic_resist_modifier(traits: Array) -> float:
	var total := 0.0
	for trait_id in traits:
		var data: Dictionary = TRAIT_DATA.get(String(trait_id), {})
		total += float(data.get("magic_resist_modifier", 0.0))
	return total


## 聚合多个特征的异常免疫列表
static func get_combined_status_immunities(traits: Array) -> Array:
	var result: Array = []
	for trait_id in traits:
		var data: Dictionary = TRAIT_DATA.get(String(trait_id), {})
		var immunities: Array = data.get("status_immunities", [])
		for status in immunities:
			if not result.has(status):
				result.append(status)
	return result


## 聚合多个特征的异常阈值修正（设计案 10.1 / 15.4）。
## 返回乘数（默认 1.0），如深渊特征 ×2 使异常更难触发。
static func get_combined_status_threshold_modifier(traits: Array) -> float:
	var mult := 1.0
	for trait_id in traits:
		var data: Dictionary = TRAIT_DATA.get(String(trait_id), {})
		mult *= float(data.get("status_threshold_modifier", 1.0))
	return mult
