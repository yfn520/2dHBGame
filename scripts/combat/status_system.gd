class_name StatusSystem
extends RefCounted

## V0.2 异常状态积累系统（设计案第9章）。
## 新伤害节点使用 status_type + status_buildup：
##   实际积累 = 基础积累 × (1 + 异常强度) ÷ (1 + 目标异常抗性)
## 积累达到阈值后触发对应异常 buff。
## 旧 buff_ids + chance 仍由 BuffManager 保底概率链路兼容，但不是新数据真值。
##
## P0 实现 7 种异常：燃烧/寒冷/冻结/感电/中毒/标记/重伤
## P1 新增：侵蚀（设计案 8.2）、潮湿（设计案 9.1 元素反应前置）

const STATUS_TYPES := ["burn", "chill", "freeze", "shock", "poison", "mark", "grievous", "erosion", "wet"]
const STATUS_ALIASES := {
	"burn": "burn", "燃烧": "burn",
	"chill": "chill", "寒冷": "chill",
	"freeze": "freeze", "冻结": "freeze",
	"shock": "shock", "感电": "shock",
	"poison": "poison", "中毒": "poison",
	"mark": "mark", "标记": "mark",
	"grievous": "grievous", "重伤": "grievous",
	"erosion": "erosion", "侵蚀": "erosion",
	"wet": "wet", "潮湿": "wet",
	"none": "", "无": "",
}

## 触发阈值（设计案 9.1）。按单位类型区分。
const THRESHOLDS := {
	"normal": 100,
	"elite": 150,
	"boss": 250,
	# 潮湿作为元素反应前置，阈值较低（设计案 9.1）
	"wet_normal": 50,
}

## 异常类型 → 对应的 buff_id（在 buffs.json 中配置）
const STATUS_BUFF_ID := {
	"burn": 10002,       # 燃烧
	"chill": 10017,      # 寒冷
	"freeze": 10003,     # 冻结
	"shock": 10018,      # 感电
	"poison": 10001,     # 中毒
	"mark": 10019,       # 标记
	"grievous": 10020,   # 重伤
	"erosion": 10021,    # 侵蚀（P1 新增，设计案 8.2）
	"wet": 10022,        # 潮湿（P1 新增，元素反应前置，设计案 9.1）
}

## 脱离攻击后的积累衰减速率（每秒）
const BUILDUP_DECAY_PER_SEC := 10.0


static func normalize_status_type(value: Variant) -> String:
	return str(STATUS_ALIASES.get(str(value).strip_edges().to_lower(), ""))


static func normalize_unit_type(value: Variant) -> String:
	var normalized := str(value).strip_edges().to_lower()
	if normalized in ["boss", "章节boss"]:
		return "boss"
	if normalized in ["elite", "精英"]:
		return "elite"
	return "normal"


## 计算实际积累值（设计案 9.1）
## base: 基础积累值（来自技能节点 status_buildup 字段）
## intensity: 异常强度（攻击方属性，0.3 表示 30%）
## resist: 异常抗性（目标属性，0.3 表示 30%）
static func calculate_buildup(base: float, intensity: float, resist: float) -> float:
	return base * (1.0 + intensity) / (1.0 + resist)


## 根据单位类型返回触发阈值
static func get_threshold(unit_type: String, status_type: String = "") -> int:
	var normalized_unit := normalize_unit_type(unit_type)
	if normalized_unit == "normal" and normalize_status_type(status_type) == "wet":
		return int(THRESHOLDS["wet_normal"])
	return int(THRESHOLDS.get(normalized_unit, THRESHOLDS["normal"]))


## 判断单位类型：优先读取属性对象显式 status_unit_type，再兼容旧 is_boss 方法。
static func get_unit_type(target: Node) -> String:
	if target == null:
		return "normal"
	if target.has_method("get_combat_stats"):
		var stats = target.get_combat_stats()
		if stats != null and "status_unit_type" in stats:
			return normalize_unit_type(stats.status_unit_type)
	if target.has_method("is_boss") and target.is_boss():
		return "boss"
	return "normal"
