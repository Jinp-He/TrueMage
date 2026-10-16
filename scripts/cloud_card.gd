class_name CloudCard
extends RefCounted
## 牌库里的一张词云：固定的符文，加上可选的词条（背景强化）。

## 杂念：敌人塞进抽牌堆的干扰词云，不属于任何咒式，只在当场对决里存在。
const JUNK_RUNE := "x"

var runes: String
var affix_id: String


func _init(p_runes: String, p_affix_id: String = "") -> void:
	runes = p_runes
	affix_id = p_affix_id


func affix() -> AffixData:
	return AffixData.by_id(affix_id) if affix_id != "" else null


func is_junk() -> bool:
	return runes == JUNK_RUNE


func describe() -> String:
	if is_junk():
		return "x（杂念：不属于任何咒式）"
	var found := affix()
	return runes if found == null else "%s（%s：%s）" % [runes, found.name, found.description]
