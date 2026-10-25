class_name SpellData
extends RefCounted
## 当前法术均按连续咒式识别，允许重叠出现。
## a 开头偏向输出，a 结尾偏向辅助；火焰亲和持续本场战斗。

const RUNES := ["a", "b", "c", "d", "e"]
## 仅用于显示：暖色符文用橙色牌和橙色云，冷色符文用蓝色。
const WARM_RUNES := ["a", "b", "e"]
const EFFECT_STEP := {"damage": 4, "shield": 4, "heal": 4, "gold": 1, "fire_affinity": 1, "damage_per_affinity": 1, "shield_per_affinity": 1}
const MIN_PATTERN_LENGTH := 2
const EXACT := "exact"

var id: String
var name: String
var pattern: String
var rule: String
var damage: int
var fire_affinity: int
var damage_per_affinity: int
var shield_per_affinity: int
var self_damage: int
var random_bonus: int
## 保留通用存档字段，当前七种法术均不使用穿透、治疗或金币效果。
var pierce: bool
var shield: int
var heal: int
## 每次触发获得的金币。
var gold: int
var icon: String
var cost: int


func _init(p_id: String, p_name: String, p_pattern: String, effects: Dictionary, p_icon: String, p_cost: int, p_rule: String = EXACT) -> void:
	id = p_id
	name = p_name
	pattern = p_pattern
	rule = p_rule
	damage = effects.get("damage", 0)
	fire_affinity = effects.get("fire_affinity", 0)
	damage_per_affinity = effects.get("damage_per_affinity", 0)
	shield_per_affinity = effects.get("shield_per_affinity", 0)
	self_damage = effects.get("self_damage", 0)
	random_bonus = effects.get("random_bonus", 0)
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
	var effects := {"damage": damage, "pierce": pierce, "shield": shield, "heal": heal, "gold": gold, "fire_affinity": fire_affinity, "damage_per_affinity": damage_per_affinity, "shield_per_affinity": shield_per_affinity, "self_damage": self_damage, "random_bonus": random_bonus}
	return SpellData.new(id, name, pattern, effects, icon, cost, rule)


func rune_choice_matters() -> bool:
	return true

func can_add_rune(max_length: int) -> bool:
	return pattern.length() < max_length

func can_remove_rune() -> bool:
	return pattern.length() > MIN_PATTERN_LENGTH

func add_rune(rune: String) -> void:
	pattern += rune
	var key := main_effect()
	set(key, get(key) + EFFECT_STEP[key])

func remove_rune(index: int) -> void:
	if not can_remove_rune():
		return
	pattern = pattern.erase(index)
	var key := main_effect()
	set(key, maxi(1, get(key) - EFFECT_STEP[key]))

func pattern_bbcode() -> String:
	return _rune_bb(pattern)

static func _rune_bb(runes: String) -> String:
	return "[b]%s[/b]" % UiKit.rune_bbcode(runes)


## 纯文本版本，用于提示文字。
func pattern_text() -> String:
	return pattern

func offer_runes() -> String:
	return pattern

func main_effect() -> String:
	if fire_affinity > 0:
		return "fire_affinity"
	if shield_per_affinity > 0:
		return "shield_per_affinity"
	return "damage" if damage > 0 else "shield"

func effect_text() -> String:
	var parts: PackedStringArray = []
	if self_damage > 0:
		parts.append("失去 %d 点生命" % self_damage)
	if damage > 0:
		if random_bonus > 0:
			parts.append("各 50%%：%d / %d 点伤害" % [damage, damage + random_bonus])
		elif damage_per_affinity > 0:
			parts.append("%d＋%s火焰亲和伤害" % [damage, "" if damage_per_affinity == 1 else "%d×" % damage_per_affinity])
		else:
			parts.append("%d 点火焰伤害" % damage)
	if shield > 0:
		parts.append("%d 点护盾" % shield)
	if shield_per_affinity > 0:
		parts.append("获得 %s火焰亲和护盾" % ("" if shield_per_affinity == 1 else "%d×" % shield_per_affinity))
	if fire_affinity > 0:
		parts.append("火焰亲和 +%d" % fire_affinity)
	return "，".join(parts)

## 和另一个版本相比，哪些效果变了，例如“伤害 8→11”。
func change_text(before: SpellData) -> String:
	var parts: PackedStringArray = []
	var entries := [["伤害", before.damage, damage], ["护盾", before.shield, shield],
		["治疗", before.heal, heal], ["金币", before.gold, gold], ["火焰亲和", before.fire_affinity, fire_affinity], ["亲和护盾倍率", before.shield_per_affinity, shield_per_affinity]]
	for entry: Array in entries:
		if entry[1] != entry[2]:
			parts.append("%s %d→%d" % entry)
	return "  ".join(parts)


## 咒语区括号上的短标签，例如“火球 · 8”。mult 是这次触发的倍率。
func bracket_text(mult: int = 1) -> String:
	if random_bonus > 0:
		return "%s · %d/%d" % [name.trim_suffix("术"), damage * mult, (damage + random_bonus) * mult]
	if damage_per_affinity > 0:
		return "%s · %d＋亲和" % [name, damage * mult]
	if shield_per_affinity > 0:
		return "%s · 亲和护盾" % name
	var values: PackedStringArray = []
	for value in [damage, shield, heal, gold, fire_affinity, shield_per_affinity]:
		if value > 0:
			values.append(str(value * mult))
	return "%s · %s" % [name.trim_suffix("术"), "/".join(values)]


static func catalog() -> Array[SpellData]:
	return [
		SpellData.new("kindle", "引火术", "ca", {"fire_affinity": 2}, "icon_fire", 4),
		SpellData.new("fire_arrow", "火焰箭", "ac", {"damage": 3, "damage_per_affinity": 1}, "icon_fire", 3),
		SpellData.new("fireball", "火球术", "aa", {"damage": 5}, "spell_fire", 5),
		SpellData.new("shield", "护盾术", "cc", {"shield": 5}, "spell_shield", 4),
		SpellData.new("bloodflame", "血焰术", "ab", {"damage": 6, "self_damage": 1}, "icon_fire", 4),
		SpellData.new("warmth", "余温术", "ba", {"shield_per_affinity": 1}, "icon_shield", 4),
		SpellData.new("wildfire", "跃火术", "ad", {"damage": 3, "random_bonus": 3}, "spell_fire", 4),
	]


static func by_id(spell_id: String) -> SpellData:
	for spell in catalog():
		if spell.id == spell_id:
			return spell
	return null
