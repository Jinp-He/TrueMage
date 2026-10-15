class_name SpellData
extends RefCounted
## 一个法术：咒式（符文序列）加上被识别时触发的效果。
## 咒式可以在咒语商店里强化：追加火符文（a、b）提高伤害，追加盾符文（c、d）增加护盾，
## 移除符文让咒式更好拼，但效果随之降低。

const FIRE_RUNES := ["a", "b"]
const RUNES := ["a", "b", "c", "d"]
## 每追加或移除一个符文，对应效果变化的数值。
const RUNE_POWER := 3
const MIN_PATTERN_LENGTH := 2

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


static func is_fire(rune: String) -> bool:
	return rune in FIRE_RUNES


func is_attack() -> bool:
	return damage > 0


func copy() -> SpellData:
	return SpellData.new(id, name, pattern, {"damage": damage, "shield": shield, "heal": heal}, icon, cost)


## 在咒式末尾追加一个符文。
func add_rune(rune: String) -> void:
	pattern += rune
	if is_fire(rune):
		damage += RUNE_POWER
	else:
		shield += RUNE_POWER


## 移除咒式里第 index 个符文。优先削减该符文对应的效果；法术没有这项效果时削减它的主效果。
## 已有的效果最低保留 1 点。
func remove_rune(index: int) -> void:
	var rune := pattern[index]
	pattern = pattern.erase(index)
	var key := "damage" if is_fire(rune) else "shield"
	if get(key) == 0:
		key = main_effect()
	set(key, maxi(1, get(key) - RUNE_POWER))


func main_effect() -> String:
	if damage >= shield and damage >= heal:
		return "damage"
	return "shield" if shield >= heal else "heal"


func effect_text() -> String:
	var parts: PackedStringArray = []
	if damage > 0:
		parts.append("造成 %d 点伤害" % damage)
	if shield > 0:
		parts.append("获得 %d 点护盾" % shield)
	if heal > 0:
		parts.append("恢复 %d 点生命" % heal)
	return "，".join(parts)


## 和另一个版本相比，哪些效果变了，例如“伤害 8→11”。
func change_text(before: SpellData) -> String:
	var parts: PackedStringArray = []
	for entry: Array in [["伤害", before.damage, damage], ["护盾", before.shield, shield], ["治疗", before.heal, heal]]:
		if entry[1] != entry[2]:
			parts.append("%s %d→%d" % entry)
	return "  ".join(parts)


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
