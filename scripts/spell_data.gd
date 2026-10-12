class_name SpellData
extends RefCounted
## 一个法术：咒式（符文序列）加上被识别时触发的效果。

var id: String
var name: String
var pattern: String
var damage: int
var shield: int
var heal: int
var icon: String
var cost: int


func _init(p_id: String, p_name: String, p_pattern: String, effects: Dictionary, p_icon: String, p_cost: int) -> void:
	id = p_id
	name = p_name
	pattern = p_pattern
	damage = effects.get("damage", 0)
	shield = effects.get("shield", 0)
	heal = effects.get("heal", 0)
	icon = p_icon
	cost = p_cost


func is_attack() -> bool:
	return damage > 0


func effect_text() -> String:
	var parts: PackedStringArray = []
	if damage > 0:
		parts.append("造成 %d 点伤害" % damage)
	if shield > 0:
		parts.append("获得 %d 点护盾" % shield)
	if heal > 0:
		parts.append("恢复 %d 点生命" % heal)
	return "，".join(parts)


## 咒语区括号上的短标签，例如“火球 · 8”。
func bracket_text() -> String:
	var values: PackedStringArray = []
	for value in [damage, shield, heal]:
		if value > 0:
			values.append(str(value))
	return "%s · %s" % [name.trim_suffix("术"), "/".join(values)]


static func catalog() -> Array[SpellData]:
	return [
		SpellData.new("spark", "火花术", "aa", {"damage": 2}, "mascot_spark", 3),
		SpellData.new("fireball", "火球术", "aabc", {"damage": 8}, "mascot_fireball", 6),
		SpellData.new("armor", "护甲术", "cd", {"shield": 6}, "mascot_shield", 4),
		SpellData.new("ember", "余烬术", "ab", {"damage": 3}, "icon_fire", 4),
		SpellData.new("chain", "连焰术", "aba", {"damage": 5}, "mascot_spark", 6),
		SpellData.new("bolt", "雷击术", "bcd", {"damage": 7}, "mascot_spark", 7),
		SpellData.new("meteor", "陨星术", "abcd", {"damage": 12}, "mascot_fireball", 10),
		SpellData.new("ward", "结界术", "dc", {"shield": 5}, "icon_shield", 4),
		SpellData.new("bulwark", "壁垒术", "dcd", {"shield": 10}, "mascot_shield", 7),
		SpellData.new("mend", "愈合术", "da", {"heal": 3}, "icon_heart_large", 5),
		SpellData.new("drain", "汲取术", "cda", {"damage": 4, "heal": 3}, "icon_heart_large", 8),
		SpellData.new("thorn", "棘甲术", "bd", {"damage": 2, "shield": 4}, "icon_shield", 6),
	]


static func by_id(spell_id: String) -> SpellData:
	for spell in catalog():
		if spell.id == spell_id:
			return spell
	return null
