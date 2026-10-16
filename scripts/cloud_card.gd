class_name CloudCard
extends RefCounted
## 牌库里的一张词云：固定的符文，加上可选的词条（背景强化）。

var runes: String
var affix_id: String


func _init(p_runes: String, p_affix_id: String = "") -> void:
	runes = p_runes
	affix_id = p_affix_id


func affix() -> AffixData:
	return AffixData.by_id(affix_id) if affix_id != "" else null


func describe() -> String:
	var found := affix()
	return runes if found == null else "%s（%s：%s）" % [runes, found.name, found.description]
