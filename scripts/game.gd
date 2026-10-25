extends Node
## 自动加载单例：保存一整局（地图、对决、商店）的状态，并负责切换场景。

const MAP_SCENE := "res://scenes/map.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SPELL_SHOP_SCENE := "res://scenes/spell_shop.tscn"
const REST_SCENE := "res://scenes/rest.tscn"
const SCRIPTORIUM_SCENE := "res://scenes/scriptorium.tscn"
const LEARN_SCENE := "res://scenes/learn.tscn"
const REWARD_SCENE := "res://scenes/reward.tscn"
const CLOUD_LIFE_CAP := 12.0
const SAVE_FIELDS := ["max_hp", "hp", "gold", "enemy", "spell_slots", "max_length", "build_time", "max_clouds", "cloud_life", "combo_damage", "short_sentence_damage", "pending_rewards", "settled_battles", "reward_detail", "resume_scene"]
var save_path := "user://run.save"
var short_sentence_damage := 0
var combo_damage := 0
var pending_rewards: Array = []
var settled_battles: Array = []
var reward_detail := ""
var resume_scene := MAP_SCENE
var save_error := ""

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
	# Tests use an isolated save and never read or overwrite the player save.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-path="):
			save_path = arg.trim_prefix("--save-path=")
	if not load_run():
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
	max_length = 5
	build_time = 20.0
	max_clouds = 4
	cloud_life = 6.0
	relics = []
	short_sentence_damage = 0
	combo_damage = 0
	pending_rewards = []
	settled_battles = []
	reward_detail = ""
	resume_scene = MAP_SCENE
	save_run()


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
	if not pending_rewards.is_empty():
		go_to_reward()
		return
	resume_scene = MAP_SCENE
	if save_run():
		get_tree().change_scene_to_file(MAP_SCENE)


## 走到地图上的一个节点：战斗类节点先定好敌人再进战斗，商店、休息处、抄写室切到各自页面。
## 宝箱不切场景，由地图页面当场开箱。
func enter_node(node: MapData.MapNode) -> void:
	if not pending_rewards.is_empty() or node not in map.reachable_from(map_node):
		return
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


## 兼容旧调用方：战后统一进入成长奖励。
func go_to_learn() -> void:
	go_to_reward()


func go_to_battle() -> void:
	resume_scene = BATTLE_SCENE
	if save_run():
		get_tree().change_scene_to_file(BATTLE_SCENE)


func go_to_reward() -> void:
	get_tree().change_scene_to_file(REWARD_SCENE)


func combo_bonus(matches: Array[Dictionary]) -> int:
	var ids := {}
	for m in matches:
		ids[m.spell.id] = true
	return combo_damage if ids.size() >= 2 else 0


# Search actual deck fragments, not arbitrary unlocked letters. Bounded search
# conservatively omits rewards whose applicability could not be demonstrated.
func reward_examples() -> Dictionary:
	var examples := {}
	var queue: Array[String] = [""]
	var seen := {"": true}
	var fragments := {}
	for card in deck:
		if not card.is_junk():
			fragments[card.runes] = true
	var cursor := 0
	while cursor < queue.size() and cursor < 20000:
		var sentence := queue[cursor]
		cursor += 1
		var matches := SpellMatcher.find_matches(sentence, spells)
		var ids := {}
		for m in matches:
			ids[m.spell.id] = true
			if not examples.has(m.spell.id):
				examples[m.spell.id] = sentence
		if ids.size() >= 2 and not examples.has("combo"):
			examples.combo = sentence
		if examples.size() >= spells.size() + 1:
			break
		for fragment: String in fragments:
			var next := sentence + fragment
			if next.length() <= max_length and not seen.has(next) and queue.size() < 20000:
				seen[next] = true
				queue.append(next)
	return examples


func make_rewards() -> Array:
	var examples := reward_examples()
	var stats: Array = []
	for spell in spells:
		if not examples.is_empty() and not examples.has(spell.id):
			continue
		for key: String in ["damage", "shield", "heal", "gold", "fire_affinity", "shield_per_affinity"]:
			if spell.get(key) > 0:
				var label: String = {"damage": "伤害", "shield": "护盾", "heal": "治疗", "gold": "金币", "fire_affinity": "火焰亲和", "shield_per_affinity": "亲和护盾倍率"}[key]
				var amount := 1 if key in ["gold", "fire_affinity", "shield_per_affinity"] else 3
				stats.append({"kind": "stat", "spell": spell.id, "effect": key,
					"amount": amount, "title": "法术强化 · " + spell.name,
					"text": "%s：%s %d → %d\n咒式不变：%s\n可用例句：%s" % [spell.name, label, spell.get(key), spell.get(key) + amount, spell.pattern_text(), examples.get(spell.id, "需调整符文供应或句子容量")]})
	stats.shuffle()
	var offers: Array = []
	if not stats.is_empty():
		offers.append(stats.pop_back())
	if max_length < MAX_LENGTH_CAP:
		offers.append({"kind": "capacity", "title": "构句成长 · 句子扩展", "text": "句子容量 %d → %d 格\n已有法术的咒式不变\n构句总时间不变" % [max_length, max_length + 1]})
	else:
		offers.append({"kind": "short_sentence", "title": "构句成长 · 短句专注", "text": "句长不超过 4 格且触发法术时\n额外伤害 %d → %d，每句一次" % [short_sentence_damage, short_sentence_damage + 3]})
	if hp < max_hp:
		offers.append({"kind": "heal", "title": "休整 · 恢复生命", "text": "立即恢复 %d 点生命\n生命 %d → %d / %d" % [mini(8, max_hp - hp), hp, mini(max_hp, hp + 8), max_hp]})
	elif cloud_life < CLOUD_LIFE_CAP:
		offers.append({"kind": "mind", "title": "脑海操控", "text": "词云存续 %.0f → %.0f 秒\n施法总时间不变（%.0f 秒）\n存续上限 %.0f 秒" % [cloud_life, minf(CLOUD_LIFE_CAP, cloud_life + 2), build_time, CLOUD_LIFE_CAP]})
	else:
		offers.append({"kind": "gold", "title": "补给 · 金币", "text": "立即获得 10 金币"})
	return offers


# Loot and offers form a single saved checkpoint, keyed by the map encounter.
func complete_battle() -> bool:
	if map_node == null or map_node.type not in [MapData.BATTLE, MapData.ELITE] or hp <= 0:
		return false
	var key := "%d:%d" % [map_node.layer, map_node.row]
	if key in settled_battles:
		return false
	var before := snapshot()
	gold += duel_reward()
	reward_detail = "获得 %d 金币。" % duel_reward()
	if in_elite_fight():
		var relic := random_relic()
		if relic != null:
			gain_relic(relic)
			reward_detail += "获得遗物「%s」。" % relic.name
	pending_rewards = make_rewards()
	settled_battles.append(key)
	resume_scene = REWARD_SCENE
	if not save_run():
		restore_snapshot(before)
		return false
	return true


# UI and bots must both use this interface. A failed save rolls back the grant.
func claim_reward(index: int) -> bool:
	if index < 0 or index >= pending_rewards.size():
		return false
	var before := snapshot()
	var offer: Dictionary = pending_rewards[index]
	match offer.kind:
		"stat":
			var target: SpellData = null
			for spell in spells:
				if spell.id == offer.spell:
					target = spell
			if target == null:
				return false
			target.set(offer.effect, target.get(offer.effect) + int(offer.get("amount", 3)))
		"capacity":
			max_length = mini(MAX_LENGTH_CAP, max_length + 1)
		"short_sentence":
			short_sentence_damage += 3
		"heal":
			heal(8)
		"gold":
			gold += 10
		"combo":
			combo_damage += 4
		"mind":
			cloud_life = minf(CLOUD_LIFE_CAP, cloud_life + 2)
		_:
			return false
	pending_rewards = []
	resume_scene = MAP_SCENE
	if not save_run():
		restore_snapshot(before)
		return false
	return true


func snapshot() -> Dictionary:
	var data := {"version": 1, "spell_ruleset": 2, "character": character.id, "relics": relics.duplicate(), "spells": [], "deck": [], "layers": [], "node": []}
	for key in SAVE_FIELDS:
		data[key] = get(key)
	for spell in spells:
		data.spells.append({"id": spell.id, "name": spell.name, "pattern": spell.pattern, "rule": spell.rule, "fire_affinity": spell.fire_affinity, "damage_per_affinity": spell.damage_per_affinity, "shield_per_affinity": spell.shield_per_affinity, "self_damage": spell.self_damage, "random_bonus": spell.random_bonus, "damage": spell.damage, "shield": spell.shield, "heal": spell.heal, "gold": spell.gold, "pierce": spell.pierce, "icon": spell.icon, "cost": spell.cost})
	for card in deck:
		data.deck.append([card.runes, card.affix_id])
	for layer: Array in map.layers:
		var entries := []
		for node: MapData.MapNode in layer:
			entries.append({"layer": node.layer, "row": node.row, "type": node.type, "y": node.y, "next": node.next.duplicate(), "visited": node.visited})
		data.layers.append(entries)
	if map_node != null:
		data.node = [map_node.layer, map_node.row]
	return data.duplicate(true)


func restore_snapshot(data: Dictionary) -> void:
	data = data.duplicate(true)
	data["short_sentence_damage"] = data.get("short_sentence_damage", 0)
	character = CharacterData.by_id(data.character)
	for key in SAVE_FIELDS:
		set(key, data[key])
	relics.assign(data.relics)
	spells.clear()
	if data.get("spell_ruleset", 0) == 2:
		for entry: Dictionary in data.spells:
			if SpellData.by_id(entry.id) != null:
				spells.append(SpellData.new(entry.id, entry.name, entry.pattern, entry, entry.icon, entry.cost, entry.rule))
	else:
		spells.assign(character.spell_ids.map(func(id: String) -> SpellData: return SpellData.by_id(id)))
	deck.clear()
	for entry: Array in data.deck:
		deck.append(CloudCard.new(entry[0], entry[1]))
	map = MapData.new()
	for layer: Array in data.layers:
		var nodes := []
		for entry: Dictionary in layer:
			var node := MapData.MapNode.new(entry.layer, entry.row)
			node.type = entry.type
			node.y = entry.y
			node.next.assign(entry.next)
			node.visited = entry.visited
			nodes.append(node)
		map.layers.append(nodes)
	map_node = null if data.node.is_empty() else map.node_at(data.node[0], data.node[1])
	if data.get("spell_ruleset", 0) != 2:
		# Retired spell effects never survive through a saved inventory or offer.
		if not deck.any(func(card: CloudCard) -> bool: return "d" in card.runes):
			deck.append(CloudCard.new("d"))
			deck.append(CloudCard.new("d"))
		if not pending_rewards.is_empty():
			pending_rewards = make_rewards()



func save_run() -> bool:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		save_error = "无法保存进度，请检查存档目录权限后重试。"
		return false
	file.store_var(snapshot())
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(save_path + ".tmp", save_path) != OK:
		save_error = "保存失败，请重试；奖励尚未确认。"
		return false
	save_error = ""
	return true


func load_run() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var data = file.get_var(false)
	if not data is Dictionary or data.get("version") != 1:
		return false
	data["short_sentence_damage"] = data.get("short_sentence_damage", 0)
	for key in SAVE_FIELDS + ["character", "relics", "spells", "deck", "layers", "node"]:
		if not data.has(key):
			return false
	if data.get("spell_ruleset", 0) != 2:
		var backup := save_path + ".legacy"
		if not FileAccess.file_exists(backup):
			if DirAccess.copy_absolute(save_path, backup) != OK:
				save_error = "旧存档备份失败，尚未转换。"
				return false
	restore_snapshot(data)
	if data.get("spell_ruleset", 0) != 2:
		save_run()
	return true


func end_run() -> void:
	pending_rewards = []
	resume_scene = MAP_SCENE
	DirAccess.remove_absolute(save_path)
