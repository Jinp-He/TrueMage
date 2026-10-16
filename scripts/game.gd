extends Node
## 自动加载单例：保存一整局（连续对决 + 商店）的状态，并负责切换场景。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const SPELL_SHOP_SCENE := "res://scenes/spell_shop.tscn"
const REST_SCENE := "res://scenes/rest.tscn"

const MAX_LENGTH_CAP := 9
const SPELL_SLOT_CAP := 5
const CLOUDS_CAP := 6
const DECK_MIN := 8

## 敌人按顺序出场；立绘放在 art/characters/enemies/<id>.png。intents 依次循环，每个意图可以组合多个动作（设计见“TrueMage 敌人设计”文档）：
##   attack N  攻击 N（加上力量）          block N   本回合防御 N
##   haste N   玩家下次构句时间 −N 秒      junk N    往抽牌堆塞 N 张杂念词云
##   seal      封印玩家下个句子的某一格    burn N    给玩家叠 N 层灼烧
##   strength N  自身力量 +N
const ENEMIES := [
	{"id": "skeleton_apprentice", "name": "骷髅学徒", "hp": 22, "intents": [
		{"attack": 5}, {"attack": 3, "haste": 5}, {"attack": 6}, {"block": 4}]},
	{"id": "graveyard_wizard", "name": "墓园巫师", "hp": 34, "intents": [
		{"attack": 6, "junk": 2}, {"attack": 8}, {"block": 6}, {"attack": 7, "junk": 2}]},
	{"id": "bound_monk", "name": "咒缚僧侣", "hp": 46, "intents": [
		{"attack": 8, "seal": true}, {"attack": 10}, {"block": 8, "seal": true}, {"attack": 12}]},
	{"id": "darkmoon_priest", "name": "暗月祭司", "hp": 60, "intents": [
		{"attack": 6, "burn": 3}, {"block": 6, "strength": 2}, {"attack": 10}, {"attack": 8, "burn": 2}]},
	{"id": "bone_archmage", "name": "骸骨大法师", "hp": 80, "intents": [
		{"attack": 12, "haste": 4}, {"attack": 8, "junk": 2}, {"block": 10, "seal": true},
		{"attack": 14, "burn": 3}, {"strength": 3}]},
]

var character: CharacterData
var max_hp: int
var hp: int
var gold: int
var duel_index: int
var spells: Array[SpellData]
var spell_slots: int
var max_length: int
var build_time: float
## 脑海区同时最多容纳的词云数。
var max_clouds: int
## 每朵词云在脑海里停留的秒数。
var cloud_life: float
var relics: Array[String]
## 牌库：每场对决开始时洗成抽牌堆，脑海区每批从中发出词云。
var deck: Array[CloudCard]


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font = UiKit.text_font()
	theme.default_font_size = 24
	get_tree().root.theme = theme
	new_run()


func new_run(character_id: String = "evoker") -> void:
	character = CharacterData.by_id(character_id)
	max_hp = character.max_hp
	hp = max_hp
	gold = 0
	duel_index = 0
	spells.assign(character.spell_ids.map(func(spell_id: String) -> SpellData: return SpellData.by_id(spell_id)))
	deck = character.build_deck()
	spell_slots = 4
	max_length = 7
	build_time = 20.0
	max_clouds = 4
	cloud_life = 6.0
	relics = []


func current_enemy() -> Dictionary:
	return ENEMIES[duel_index]


func is_last_duel() -> bool:
	return duel_index == ENEMIES.size() - 1


func duel_reward() -> int:
	return 6 + duel_index * 2


func has_spell(spell_id: String) -> bool:
	return spells.any(func(spell: SpellData) -> bool: return spell.id == spell_id)


func has_relic(relic_id: String) -> bool:
	return relic_id in relics


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func go_to_battle() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


## 对决之间咒语商店和休息处轮流出现：第 1 场后是咒语商店，第 2 场后是休息处，以此类推。
func next_stop_is_spell_shop() -> bool:
	return duel_index % 2 == 1


func go_to_intermission() -> void:
	get_tree().change_scene_to_file(SPELL_SHOP_SCENE if next_stop_is_spell_shop() else REST_SCENE)
