class_name StatusSystem
extends RefCounted

## @deprecated 异常状态积累系统（设计案第8章原方案）。
## 已被 buff_manager.apply_buff_with_pity 的保底累积机制取代（设计案重构）：
##   异常 buff 现在通过技能节点 buff_ids + chance 概率施加，
##   失败时按 buff_id 累积保底概率（每次 +20%，成功清零，每秒 -0.1 衰减），
##   不再使用独立的 status_buildup 积累值。
## 本文件保留 STATUS_BUFF_ID / STATUS_TYPES 常量供映射查询和元素反应系统使用，
## apply_status_buildup / calculate_buildup / get_threshold / get_unit_type 不再被主链路调用。
##
## 历史方案（已废弃）：
## 异常不采用单次固定概率，而采用积累制：
##   实际积累 = 基础积累 × (1 + 异常强度) ÷ (1 + 目标异常抗性)
## 积累达到阈值后触发对应异常 buff。
##
## P0 实现 7 种异常：燃烧/寒冷/冻结/感电/中毒/标记/重伤
## P1 新增：侵蚀（设计案 8.2）、潮湿（设计案 9.1 元素反应前置）

const STATUS_TYPES := ["burn", "chill", "freeze", "shock", "poison", "mark", "grievous", "erosion", "wet"]

## 触发阈值（设计案 8.1）。按单位类型区分。
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


## 计算实际积累值（设计案 8.1）
## base: 基础积累值（来自技能节点 status_buildup 字段）
## intensity: 异常强度（攻击方属性，0.3 表示 30%）
## resist: 异常抗性（目标属性，0.3 表示 30%）
static func calculate_buildup(base: float, intensity: float, resist: float) -> float:
	return base * (1.0 + intensity) / (1.0 + resist)


## 根据单位类型返回触发阈值
static func get_threshold(unit_type: String) -> int:
	return int(THRESHOLDS.get(unit_type, THRESHOLDS["normal"]))


## 判断单位类型：boss / elite / normal
## P0 阶段简化判断：有 is_boss 方法返回 true 则 boss，否则 normal。
## 后续可扩展 elite 判定（如 max_hp > 阈值 或 配置 enemy_class）。
static func get_unit_type(target: Node) -> String:
	if target == null:
		return "normal"
	if target.has_method("is_boss") and target.is_boss():
		return "boss"
	return "normal"
