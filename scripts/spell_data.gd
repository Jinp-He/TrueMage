class_name SpellData
extends RefCounted
## 一个法术：咒式（符文序列）加上被识别时触发的效果。
## 咒式可以在咒语商店里强化：追加任意符文都会提高这个法术的主效果，移除符文则让咒式更好拼、主效果降低。
## 选哪个符文不影响效果，只影响它更容易和哪些咒式连上。
##
## 符文的主题倾向是编写咒语表时的参考，咒式可以自由混用符文：
##   a 火焰（伤害）  b 雷霆（穿透伤害）  c 护盾  d 治疗  e 金币
## 每个咒语以主题符文为主，首尾的其他符文用来和别的咒语接上。

const RUNES := ["a", "b", "c", "d", "e"]
## 仅用于显示：暖色符文用橙色牌和橙色云，冷色符文用蓝色。
const WARM_RUNES := ["a", "b", "e"]
## 每追加或移除一个符文，主效果变化的数值。
const EFFECT_STEP := {"damage": 3, "shield": 3, "heal": 2, "gold": 1}
const MIN_PATTERN_LENGTH := 2

var id: String
var name: String
var pattern: String
var damage: int
## 雷霆系：伤害无视敌人的防御。
var pierce: bool
var shield: int
var heal: int
## 每次触发获得的金币。
var gold: int
var icon: String
var cost: int


func _init(p_id: String, p_name: String, p_pattern: String, effects: Dictionary, p_icon: String, p_cost: int) -> void:
	id = p_id
	name = p_name
	pattern = p_pattern
	damage = effects.get("damage", 0)
	pierce = effects.get("pierce", false)
	shield = effects.get("shield", 0)
	heal = effects.get("heal", 0)
	gold = effects.get("gold", 0)
	icon = p_icon
	cost = p_cost


static func is_warm(rune: String) -> bool:
	return rune in WARM_RUNES


func is_attack() -> bool:
	return damage > 0


func copy() -> SpellData:
	var effects := {"damage": damage, "pierce": pierce, "shield": shield, "heal": heal, "gold": gold}
	return SpellData.new(id, name, pattern, effects, icon, cost)


## 在咒式末尾追加一个符文，主效果提高。
func add_rune(rune: String) -> void:
	pattern += rune
	var key := main_effect()
	set(key, get(key) + EFFECT_STEP[key])


## 移除咒式里第 index 个符文，主效果降低，最低保留 1 点。
func remove_rune(index: int) -> void:
	pattern = pattern.erase(index)
	var key := main_effect()
	set(key, maxi(1, get(key) - EFFECT_STEP[key]))


## 伤害、护盾、治疗中数值最大的一项；只产金币的法术主效果是金币。
func main_effect() -> String:
	if damage == 0 and shield == 0 and heal == 0:
		return "gold"
	if damage >= shield and damage >= heal:
		return "damage"
	return "shield" if shield >= heal else "heal"


func effect_text() -> String:
	var parts: PackedStringArray = []
	if damage > 0:
		parts.append("造成 %d 点%s伤害" % [damage, "穿透" if pierce else ""])
	if shield > 0:
		parts.append("获得 %d 点护盾" % shield)
	if heal > 0:
		parts.append("恢复 %d 点生命" % heal)
	if gold > 0:
		parts.append("获得 %d 金币" % gold)
	return "，".join(parts)


## 和另一个版本相比，哪些效果变了，例如“伤害 8→11”。
func change_text(before: SpellData) -> String:
	var parts: PackedStringArray = []
	var entries := [["伤害", before.damage, damage], ["护盾", before.shield, shield],
		["治疗", before.heal, heal], ["金币", before.gold, gold]]
	for entry: Array in entries:
		if entry[1] != entry[2]:
			parts.append("%s %d→%d" % entry)
	return "  ".join(parts)


## 咒语区括号上的短标签，例如“火球 · 8”。
func bracket_text() -> String:
	var values: PackedStringArray = []
	for value in [damage, shield, heal, gold]:
		if value > 0:
			values.append(str(value))
	return "%s · %s" % [name.trim_suffix("术"), "/".join(values)]


static func catalog() -> Array[SpellData]:
	return [
		# a 火焰：最直接的伤害。火球以 c 结尾，可以接护盾系。
		SpellData.new("fire_arrow", "火焰箭", "aa", {"damage": 3}, "icon_fire", 3),
		SpellData.new("fireball", "火球术", "aaac", {"damage": 8}, "mascot_fireball", 6),
		SpellData.new("ember", "余烬术", "ca", {"damage": 3}, "icon_fire", 4),
		SpellData.new("blaze", "烈焰术", "acaa", {"damage": 9}, "mascot_fireball", 7),
		SpellData.new("meteor", "陨星术", "abaa", {"damage": 13}, "mascot_fireball", 10),
		# b 雷霆：穿透伤害，专克防御意图。雷击以 a 开头，可以接在火焰后面。
		SpellData.new("zap", "电击术", "bb", {"damage": 3, "pierce": true}, "mascot_spark", 4),
		SpellData.new("thunder_strike", "雷霆打击", "abab", {"damage": 8, "pierce": true}, "mascot_spark", 7),
		SpellData.new("bolt", "雷击术", "abb", {"damage": 6, "pierce": true}, "mascot_spark", 6),
		SpellData.new("chain", "连锁闪电", "babb", {"damage": 9, "pierce": true}, "mascot_spark", 8),
		SpellData.new("storm", "雷暴术", "cbbb", {"damage": 11, "pierce": true}, "mascot_spark", 9),
		# c 护盾：以 c 开头的可以接在火球后面，棘甲把护盾接回雷霆。
		SpellData.new("armor", "护甲术", "ccc", {"shield": 6}, "mascot_shield", 4),
		SpellData.new("ward", "结界术", "acc", {"shield": 7}, "icon_shield", 5),
		SpellData.new("thorn", "棘甲术", "cb", {"shield": 4, "damage": 2}, "icon_shield", 5),
		SpellData.new("bulwark", "壁垒术", "ccdc", {"shield": 11}, "mascot_shield", 8),
		# d 治疗：从护盾或火焰过渡过来。
		SpellData.new("mend", "愈合术", "dd", {"heal": 3}, "icon_heart_large", 4),
		SpellData.new("revive", "复苏术", "cdd", {"heal": 5}, "icon_heart_large", 6),
		SpellData.new("drain", "汲取术", "add", {"damage": 3, "heal": 3}, "icon_heart_large", 7),
		SpellData.new("lifeward", "生命结界", "dcd", {"shield": 5, "heal": 3}, "mascot_shield", 7),
		# e 金币：占用句子位置换取经济，局内越早买越赚。
		SpellData.new("coin", "招财术", "ee", {"gold": 1}, "icon_coin", 4),
		SpellData.new("midas", "点金术", "aee", {"damage": 3, "gold": 1}, "icon_coin", 6),
		SpellData.new("treasure", "聚宝术", "eece", {"gold": 3}, "icon_coin", 8),
	]


static func by_id(spell_id: String) -> SpellData:
	for spell in catalog():
		if spell.id == spell_id:
			return spell
	return null
