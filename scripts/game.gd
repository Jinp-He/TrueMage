extends Node
## 自动加载单例：保存一整局（连续对决 + 商店）的状态，并负责切换场景。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"

const MAX_LENGTH_CAP := 9
const SPELL_SLOT_CAP := 5
const BUILD_TIME_CAP := 16.0
const FRAGMENT_LIFE_CAP := 7.5
const FRAGMENT_POOL_MIN := 4
const FRAGMENT_POOL_MAX := 21

## 敌人按顺序出场；intents 循环使用。type 为 "attack" 或 "block"。
const ENEMIES := [
	{"name": "骷髅学徒", "hp": 22, "intents": [["attack", 5], ["attack", 6], ["block", 4], ["attack", 8]]},
	{"name": "墓园巫师", "hp": 34, "intents": [["attack", 8], ["block", 6], ["attack", 10], ["attack", 7]]},
	{"name": "咒缚僧侣", "hp": 46, "intents": [["attack", 10], ["attack", 12], ["block", 8], ["attack", 14]]},
	{"name": "暗月祭司", "hp": 60, "intents": [["block", 8], ["attack", 14], ["attack", 11], ["attack", 18]]},
	{"name": "骸骨大法师", "hp": 80, "intents": [["attack", 14], ["attack", 16], ["block", 12], ["attack", 22]]},
]

var max_hp: int
var hp: int
var gold: int
var duel_index: int
var spells: Array[SpellData]
var spell_slots: int
var max_length: int
var build_time: float
var fragment_life: float
var fragment_pool: Array[String]


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font = UiKit.text_font()
	theme.default_font_size = 24
	get_tree().root.theme = theme
	new_run()


func new_run() -> void:
	max_hp = 30
	hp = max_hp
	gold = 0
	duel_index = 0
	spells = [SpellData.by_id("fireball"), SpellData.by_id("armor"), SpellData.by_id("spark")]
	spell_slots = 4
	max_length = 7
	build_time = 10.0
	fragment_life = 4.5
	fragment_pool = ["a", "a", "b", "c", "d", "aa", "ab", "bc", "cd"]


func current_enemy() -> Dictionary:
	return ENEMIES[duel_index]


func is_last_duel() -> bool:
	return duel_index == ENEMIES.size() - 1


func duel_reward() -> int:
	return 6 + duel_index * 2


func has_spell(spell_id: String) -> bool:
	return spells.any(func(spell: SpellData) -> bool: return spell.id == spell_id)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func go_to_battle() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


func go_to_shop() -> void:
	get_tree().change_scene_to_file(SHOP_SCENE)
