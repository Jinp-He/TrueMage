extends Node
## 自动加载单例：保存一整局（地图、对决、商店）的状态，并负责切换场景。

const MAP_SCENE := "res://scenes/map.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SPELL_SHOP_SCENE := "res://scenes/spell_shop.tscn"
const REST_SCENE := "res://scenes/rest.tscn"
const SCRIPTORIUM_SCENE := "res://scenes/scriptorium.tscn"
const LEARN_SCENE := "res://scenes/learn.tscn"

const MAX_LENGTH_CAP := 9
const SPELL_SLOT_CAP := 5
const CLOUDS_CAP := 6
const DECK_MIN := 8

## 敌人按地图深度分组；立绘放在 art/characters/enemies/<id>.png。intents 依次循环，每个意图可以组合多个动作（设计见“TrueMage 敌人设计”文档）：
##   attack N  攻击 N（加上力量）          block N   本回合防御 N
##   haste N   玩家下次构句时间 −N 秒      junk N    往抽牌堆塞 N 张杂念词云
##   seal      封印玩家下个句子的某一格    burn N    给玩家叠 N 层灼烧
##   strength N  自身力量 +N
## 前期敌人出现在地图前 EARLY_LAYERS 层的普通战斗，之后换成后期敌人。
const EARLY_ENEMIES := [
	{"id": "skeleton_apprentice", "name": "骷髅学徒", "hp": 22, "intents": [
		{"attack": 5}, {"attack": 3, "haste": 5}, {"attack": 6}, {"block": 4}]},
	{"id": "graveyard_wizard", "name": "墓园巫师", "hp": 34, "intents": [
		{"attack": 6, "junk": 2}, {"attack": 8}, {"block": 6}, {"attack": 7, "junk": 2}]},
]
const LATE_ENEMIES := [
	{"id": "bound_monk", "name": "咒缚僧侣", "hp": 46, "intents": [
		{"attack": 8, "seal": true}, {"attack": 10}, {"block": 8, "seal": true}, {"attack": 12}]},
	{"id": "darkmoon_priest", "name": "暗月祭司", "hp": 60, "intents": [
		{"attack": 6, "burn": 3}, {"block": 6, "strength": 2}, {"attack": 10}, {"attack": 8, "burn": 2}]},
]
const BOSS_ENEMY := {"id": "bone_archmage", "name": "骸骨大法师", "hp": 80, "intents": [
	{"attack": 12, "haste": 4}, {"attack": 8, "junk": 2}, {"block": 10, "seal": true},
	{"attack": 14, "burn": 3}, {"strength": 3}]}
const EARLY_LAYERS := 3
## 精英暂时由后期敌人加强而来：生命 ×1.25，每次攻击 +2。打赢额外得一件遗物。
const ELITE_HP_SCALE := 1.25
const ELITE_ATTACK_BONUS := 2

## 第一场战斗前的教程看过没有。不随新开一局重置：同一次启动只看一次。
var tutorial_seen := false
var character: CharacterData
var max_hp: int
var hp: int
var gold: int
var map: MapData
## 地图上当前所在的节点；还没出发时为 null。
var map_node: MapData.MapNode
## 正在进行或即将开始的这场对决的敌人。
var enemy: Dictionary
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
	map = MapData.generate()
	map_node = null
	enemy = {}
	spells.assign(character.spell_ids.map(func(spell_id: String) -> SpellData: return SpellData.by_id(spell_id)))
	deck = character.build_deck()
	spell_slots = 4
	max_length = 7
	build_time = 20.0
	max_clouds = 4
	cloud_life = 6.0
	relics = []


func current_enemy() -> Dictionary:
	return enemy


func in_boss_fight() -> bool:
	return map_node != null and map_node.type == MapData.BOSS


func in_elite_fight() -> bool:
	return map_node != null and map_node.type == MapData.ELITE


## 当前在第几层（从 1 数起），首领层算最后一层。
func floor_number() -> int:
	return 0 if map_node == null else map_node.layer + 1


func duel_reward() -> int:
	var reward := 6 + map_node.layer
	return reward * 2 if in_elite_fight() else reward


## 一件还没拥有、此刻可以获得的随机遗物，没有就返回 null。
func random_relic() -> RelicData:
	var candidates := RelicData.catalog().filter(func(relic: RelicData) -> bool: return relic.available())
	return null if candidates.is_empty() else candidates.pick_random()


func gain_relic(relic: RelicData) -> void:
	relics.append(relic.id)
	relic.on_acquire()


func has_spell(spell_id: String) -> bool:
	return spells.any(func(spell: SpellData) -> bool: return spell.id == spell_id)


func has_relic(relic_id: String) -> bool:
	return relic_id in relics


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func go_to_map() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


## 走到地图上的一个节点：战斗类节点先定好敌人再进战斗，商店、休息处、抄写室切到各自页面。
## 宝箱不切场景，由地图页面当场开箱。
func enter_node(node: MapData.MapNode) -> void:
	map_node = node
	node.visited = true
	match node.type:
		MapData.BATTLE:
			enemy = (EARLY_ENEMIES if node.layer < EARLY_LAYERS else LATE_ENEMIES).pick_random()
			go_to_battle()
		MapData.ELITE:
			enemy = _elite(LATE_ENEMIES.pick_random())
			go_to_battle()
		MapData.BOSS:
			enemy = BOSS_ENEMY
			go_to_battle()
		MapData.SHOP:
			get_tree().change_scene_to_file(SPELL_SHOP_SCENE)
		MapData.REST:
			get_tree().change_scene_to_file(REST_SCENE)
		MapData.SCRIPTORIUM:
			get_tree().change_scene_to_file(SCRIPTORIUM_SCENE)


func _elite(base: Dictionary) -> Dictionary:
	var elite := base.duplicate(true)
	elite.name = "精英·" + base.name
	elite.hp = roundi(base.hp * ELITE_HP_SCALE)
	for intent: Dictionary in elite.intents:
		if intent.has("attack"):
			intent.attack += ELITE_ATTACK_BONUS
	return elite


## 每打赢一场普通或精英战斗，先到学习咒语页面，再回地图。
func go_to_learn() -> void:
	get_tree().change_scene_to_file(LEARN_SCENE)


func go_to_battle() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)
