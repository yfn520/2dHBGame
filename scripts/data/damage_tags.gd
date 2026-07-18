class_name DamageTags
extends RefCounted

## 伤害标签与防御通道定义（设计案第4章）。
## 物理标签：斩击/穿刺/钝击（走护甲）
## 魔法标签：火焰/冰霜/雷电/神圣/毒素/深渊（走魔抗）
## 真实：无标签（无防御结算）

const CHANNELS := ["physical", "magic", "true"]

const TAGS := [
	"slash", "pierce", "blunt",          # 物理
	"fire", "frost", "thunder", "holy",  # 魔法
	"poison", "abyss"                    # 魔法（特殊）
]

## 标签 → 防御通道映射
const CHANNEL_OF_TAG := {
	"slash": "physical", "pierce": "physical", "blunt": "physical",
	"fire": "magic", "frost": "magic", "thunder": "magic", "holy": "magic",
	"poison": "magic", "abyss": "magic",
}

## 中文注解（供编辑器 UI 显示）
const OPTION_LABELS := {
	"slash": "斩击", "pierce": "穿刺", "blunt": "钝击",
	"fire": "火焰", "frost": "冰霜", "thunder": "雷电", "holy": "神圣",
	"poison": "毒素", "abyss": "深渊",
}

const CHANNEL_LABELS := {
	"physical": "物理", "magic": "魔法", "true": "真实",
}


## 返回某通道下的所有标签（供编辑器按通道过滤下拉）
static func get_tags_by_channel(channel: String) -> Array:
	var result: Array = []
	for tag in TAGS:
		if CHANNEL_OF_TAG.get(tag, "") == channel:
			result.append(tag)
	return result


## 获取标签的中文显示文本
static func get_tag_label(tag: String) -> String:
	return OPTION_LABELS.get(tag, tag)


## 获取通道的中文显示文本
static func get_channel_label(channel: String) -> String:
	return CHANNEL_LABELS.get(channel, channel)
