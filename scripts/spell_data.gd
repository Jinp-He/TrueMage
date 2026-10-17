class_name SpellData
extends RefCounted
## 一个法术：咒式（符文序列）加上被识别时触发的效果。
## 咒式可以在咒语商店里强化：追加任意符文都会提高这个法术的主效果，移除符文则让咒式更好拼、主效果降低。
## 选哪个符文不影响效果，只影响它更容易和哪些咒式连上。
##
## 符文的主题倾向是编写咒语表时的参考，咒式可以自由混用符文：
##   a 火焰（伤害）  b 雷霆（穿透伤害）  c 护盾  d 治疗  e 金币
## 每个咒语以主题符文为主，首尾的其他符文用来和别的咒语接上。
##
## 除了必须原样连续出现的固定咒式，还有几种条件咒式（rule），pattern 的含义随之变化：
##   BOOKEND 首尾呼应：pattern 是首尾两个符文，例如 "aa" 表示 a…a；中间每有一个符文效果算一倍。
##   VARIETY 多样：pattern 的长度 N 表示连续 N 个互不相同的符文（内容用 "?" 占位）。
##   COUNT   计数：pattern 里的符文在句中凑齐就触发一次，不必相连，例如 "bbb" 是任意 3 个 b。
##   ABSENT  缺席：句中一个 pattern 里的符文都没有时触发一次。
## 越容易达成的条件，数值越小。

const RUNES := ["a", "b", "c", "d", "e"]
## 仅用于显示：暖色符文用橙色牌和橙色云，冷色符文用蓝色。
const WARM_RUNES := ["a", "b", "e"]
## 每追加或移除一个符文，主效果变化的数值。
## 数值曲线：以两符文 3 点为基准，L 符文 3(L-1)+1，即 3 / 7 / 11 / 15……每多一个符文 +4，
## 保证长咒式一次触发比在同样的格子里塞短咒语更值。
##
## 同一法术可以和自己重叠触发，所以咒语表里的咒式最多和自己共用首尾一个符文（如 acaa 可写成 acaacaa），
## 不用 aa、ccc、abab 这种能大段自我重叠的咒式，否则一串相同符文就能反复触发。
const EFFECT_STEP := {"damage": 4, "shield": 4, "heal": 4, "gold": 1}
const MIN_PATTERN_LENGTH := 2

const EXACT := "exact"
const BOOKEND := "bookend"
const VARIETY := "variety"
const COUNT := "count"
const ABSENT := "absent"

var id: String
var name: String
var pattern: String
var rule: String
var damage: int
## 雷霆系：伤害无视敌人的防御。
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
	return SpellData.new(id, name, pattern, effects, icon, cost, rule)


## 追加符文时选哪个符文是否有区别。多样型只看长度，首尾型不改咒式，都不用选符文。
func rune_choice_matters() -> bool:
	return rule in [EXACT, COUNT, ABSENT]


func can_add_rune(max_length: int) -> bool:
	match rule:
		VARIETY:
			return pattern.length() < RUNES.size()
		ABSENT:
			return pattern.length() < RUNES.size() - 1
		BOOKEND:
			return true
	return pattern.length() < max_length


func can_remove_rune() -> bool:
	match rule:
		BOOKEND:
			return false
		VARIETY:
			return pattern.length() > 3
		ABSENT:
			return pattern.length() > 1
	return pattern.length() > MIN_PATTERN_LENGTH


## 在咒式末尾追加一个符文，条件更难达成，主效果提高。
## 首尾型的咒式不变，改为提高“中间每个符文”的倍率。
func add_rune(rune: String) -> void:
	match rule:
		VARIETY:
			pattern += "?"
		ABSENT:
			if rune in pattern:
				return
			pattern += rune
		BOOKEND:
			pass
		_:
			pattern += rune
	var key := main_effect()
	set(key, get(key) + _effect_step(key))


## 移除咒式里第 index 个符文，条件更好达成，主效果降低，最低保留 1 点。
func remove_rune(index: int) -> void:
	if not can_remove_rune():
		return
	pattern = pattern.erase(index)
	var key := main_effect()
	set(key, maxi(1, get(key) - _effect_step(key)))


func _effect_step(key: String) -> int:
	return 1 if rule == BOOKEND else EFFECT_STEP[key]


## 咒式的显示文本（BBCode）：符文着色并用 [b] 套上符文字体，条件型会写出条件。
func pattern_bbcode() -> String:
	match rule:
		BOOKEND:
			return "%s[color=#8a7f70]…[/color]%s" % [_rune_bb(pattern[0]), _rune_bb(pattern[1])]
		VARIETY:
			return "连续 %d 种不同符文" % pattern.length()
		COUNT:
			return "%s[font_size=18]（可分散）[/font_size]" % _rune_bb(pattern)
		ABSENT:
			return "句中没有 %s" % _rune_bb(pattern)
	return _rune_bb(pattern)


static func _rune_bb(runes: String) -> String:
	return "[b]%s[/b]" % UiKit.rune_bbcode(runes)


## 纯文本版本，用于提示文字。
func pattern_text() -> String:
	match rule:
		BOOKEND:
			return "%s…%s" % [pattern[0], pattern[1]]
		VARIETY:
			return "连续%d种不同" % pattern.length()
		COUNT:
			return "%s（可分散）" % pattern
		ABSENT:
			return "没有%s" % pattern
	return pattern


## 商店里截取词云时可用的符文：只有咒式里写出的符文才有意义。
func offer_runes() -> String:
	return pattern if rule in [EXACT, BOOKEND, COUNT] else ""


## 伤害、护盾、治疗中数值最大的一项；只产金币的法术主效果是金币。
func main_effect() -> String:
	if damage == 0 and shield == 0 and heal == 0:
		return "gold"
	if damage >= shield and damage >= heal:
		return "damage"
	return "shield" if shield >= heal else "heal"


func effect_text() -> String:
	var parts: PackedStringArray = []
	var prefix := "中间每个符文" if rule == BOOKEND else ""
	if damage > 0:
		parts.append("造成 %d 点%s伤害" % [damage, "穿透" if pierce else ""])
	if shield > 0:
		parts.append("获得 %d 点护盾" % shield)
	if heal > 0:
		parts.append("恢复 %d 点生命" % heal)
	if gold > 0:
		parts.append("获得 %d 金币" % gold)
	return prefix + "，".join(parts)


## 和另一个版本相比，哪些效果变了，例如“伤害 8→11”。
func change_text(before: SpellData) -> String:
	var parts: PackedStringArray = []
	var entries := [["伤害", before.damage, damage], ["护盾", before.shield, shield],
		["治疗", before.heal, heal], ["金币", before.gold, gold]]
	for entry: Array in entries:
		if entry[1] != entry[2]:
			parts.append("%s %d→%d" % entry)
	return "  ".join(parts)


## 咒语区括号上的短标签，例如“火球 · 8”。mult 是这次触发的倍率（首尾型按中间符文数）。
func bracket_text(mult: int = 1) -> String:
	var values: PackedStringArray = []
	for value in [damage, shield, heal, gold]:
		if value > 0:
			values.append(str(value * mult))
	return "%s · %s" % [name.trim_suffix("术"), "/".join(values)]


static func catalog() -> Array[SpellData]:
	return [
		# a 火焰：最直接的伤害。火焰箭和火球以 c 结尾，可以接护盾系。
		SpellData.new("fire_arrow", "火焰箭", "ac", {"damage": 3}, "icon_fire", 3),
		SpellData.new("fireball", "火球术", "aaac", {"damage": 11}, "mascot_fireball", 6),
		SpellData.new("ember", "余烬术", "ca", {"damage": 3}, "icon_fire", 4),
		SpellData.new("blaze", "烈焰术", "acaa", {"damage": 11}, "mascot_fireball", 7),
		SpellData.new("meteor", "陨星术", "abaa", {"damage": 14}, "mascot_fireball", 10),
		# b 雷霆：穿透伤害，专克防御意图。雷击以 a 开头，可以接在火焰后面；雷霆打击以 a 结尾，接回火焰。
		SpellData.new("zap", "电击术", "bd", {"damage": 3, "pierce": true}, "mascot_spark", 4),
		SpellData.new("thunder_strike", "雷霆打击", "bba", {"damage": 7, "pierce": true}, "mascot_spark", 7),
		SpellData.new("bolt", "雷击术", "abb", {"damage": 7, "pierce": true}, "mascot_spark", 6),
		SpellData.new("chain", "连锁闪电", "babb", {"damage": 11, "pierce": true}, "mascot_spark", 8),
		SpellData.new("storm", "雷暴术", "cbbb", {"damage": 12, "pierce": true}, "mascot_spark", 9),
		# c 护盾：以 c 开头的可以接在火焰箭、火球后面，护甲和棘甲把护盾接回雷霆。
		SpellData.new("armor", "护甲术", "ccb", {"shield": 8}, "mascot_shield", 4),
		SpellData.new("ward", "结界术", "acc", {"shield": 8}, "icon_shield", 5),
		SpellData.new("thorn", "棘甲术", "cb", {"shield": 4, "damage": 2}, "icon_shield", 5),
		SpellData.new("bulwark", "壁垒术", "ccdc", {"shield": 12}, "mascot_shield", 8),
		# d 治疗：从护盾或火焰过渡过来。
		SpellData.new("mend", "愈合术", "da", {"heal": 3}, "icon_heart_large", 4),
		SpellData.new("revive", "复苏术", "cdd", {"heal": 7}, "icon_heart_large", 6),
		SpellData.new("drain", "汲取术", "add", {"damage": 4, "heal": 3}, "icon_heart_large", 7),
		SpellData.new("lifeward", "生命结界", "dcc", {"shield": 5, "heal": 3}, "mascot_shield", 7),
		# e 金币：占用句子位置换取经济，局内越早买越赚。
		SpellData.new("coin", "招财术", "ea", {"gold": 1}, "icon_coin", 4),
		SpellData.new("midas", "点金术", "aee", {"damage": 3, "gold": 1}, "icon_coin", 6),
		SpellData.new("treasure", "聚宝术", "eece", {"gold": 4}, "icon_coin", 8),
		# 条件咒式：不要求原样连续，越容易达成数值越低。
		# 首尾呼应：两个 a 之间夹几个符文就算几倍，最多 5 倍（7 格句子）。
		SpellData.new("missile", "魔法飞弹", "aa", {"damage": 1}, "icon_fire", 5, BOOKEND),
		SpellData.new("aegis_arc", "回环结界", "cc", {"shield": 1}, "icon_shield", 5, BOOKEND),
		# 多样：和按主题堆符文的咒语相冲，4 种不同符文连在一起不容易。
		SpellData.new("prism", "元素爆发", "????", {"damage": 7}, "mascot_fireball", 7, VARIETY),
		# 计数：雷系咒语本身就有很多 b，凑 3 个很容易，所以数值低。
		SpellData.new("thundercloud", "雷云术", "bbb", {"damage": 3, "pierce": true}, "mascot_spark", 5, COUNT),
		# 缺席：不带火系就能触发，最容易，数值最低。
		SpellData.new("frost_wall", "寒霜壁", "a", {"shield": 3}, "icon_shield", 4, ABSENT),
	]


static func by_id(spell_id: String) -> SpellData:
	for spell in catalog():
		if spell.id == spell_id:
			return spell
	return null
