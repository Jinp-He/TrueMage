class_name CharacterData
extends RefCounted
## 可选角色：初始生命、初始法术和初始牌库。

var id: String
var name: String
var max_hp: int
var spell_ids: Array[String]
## 每项为 [符文, 词条 id]，词条为空表示普通词云。
var deck: Array


func _init(p_id: String, p_name: String, p_max_hp: int, p_spell_ids: Array[String], p_deck: Array) -> void:
	id = p_id
	name = p_name
	max_hp = p_max_hp
	spell_ids = p_spell_ids
	deck = p_deck


func build_deck() -> Array[CloudCard]:
	var cards: Array[CloudCard] = []
	for entry: Array in deck:
		cards.append(CloudCard.new(entry[0], entry[1]))
	return cards


static func catalog() -> Array[CharacterData]:
	return [
		# 塑能法师：火焰箭 ac、护甲术 ccb、雷霆打击 bba，首尾相接成一圈：
		# accbbac 里 ac → ccb → bba → ac 依次共用一个符文，四次触发。
		CharacterData.new("evoker", "塑能法师", 30, ["fire_arrow", "thunder_strike", "armor"], [
			["a", "blazing"], ["a", ""], ["a", ""],
			["b", ""], ["b", ""],
			["cb", ""], ["bb", ""], ["ba", ""],
			["c", "sturdy"], ["c", ""], ["c", ""],
			["cc", ""],
		]),
	]


static func by_id(character_id: String) -> CharacterData:
	for character in catalog():
		if character.id == character_id:
			return character
	return null
