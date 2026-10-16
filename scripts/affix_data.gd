class_name AffixData
extends RefCounted
## 词条：词云背景上的强化效果。
## 放置类在词云放上句子时立即生效；覆盖类要等这张词云的符文被某个法术用上才生效。

const PLACE := "place"
const COVER := "cover"

var id: String
var name: String
var description: String
var trigger: String
var icon: String


func _init(p_id: String, p_name: String, p_description: String, p_trigger: String, p_icon: String) -> void:
	id = p_id
	name = p_name
	description = p_description
	trigger = p_trigger
	icon = p_icon


static func catalog() -> Array[AffixData]:
	return [
		AffixData.new("sturdy", "坚固", "放上句子时，获得 1 点护盾", PLACE, "icon_shield"),
		AffixData.new("insight", "灵光", "放上句子时，构句时间 +3 秒", PLACE, "icon_hourglass"),
		AffixData.new("blazing", "炽热", "被法术用上时，伤害 +2", COVER, "icon_fire"),
		AffixData.new("gilded", "金边", "被法术用上时，获得 1 金币", COVER, "icon_coin"),
		AffixData.new("resonant", "共鸣", "被两个以上法术共用时，伤害 +3", COVER, "tile_shared"),
	]


static func by_id(affix_id: String) -> AffixData:
	for affix in catalog():
		if affix.id == affix_id:
			return affix
	return null
