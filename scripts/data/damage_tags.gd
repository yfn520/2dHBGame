class_name DamageTags
extends RefCounted

## V0.2 中 damage_channel 决定防御通道，physical_tag 只描述物理形态。
## 旧元素 damage_tag 继续作为兼容读取入口，新数据使用 primary_element / element_override。

const CHANNELS := ["physical", "magic", "true"]

const TAGS := [
	"slash", "pierce", "blunt",          # 物理
	"fire", "frost", "thunder", "lightning", "holy",  # 旧元素标签
	"poison", "abyss"                    # 魔法（特殊）
]

## 标签 → 防御通道映射
const CHANNEL_OF_TAG := {
	"slash": "physical", "pierce": "physical", "blunt": "physical",
	"fire": "magic", "frost": "magic", "thunder": "magic", "lightning": "magic", "holy": "magic",
	"poison": "magic", "abyss": "magic",
}

## 中文注解（供编辑器 UI 显示）
const OPTION_LABELS := {
	"slash": "斩击", "pierce": "穿刺", "blunt": "钝击",
	"fire": "火焰", "frost": "冰霜", "thunder": "雷电", "lightning": "雷电", "holy": "神圣",
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
