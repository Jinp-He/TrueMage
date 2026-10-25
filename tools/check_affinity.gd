extends Node
var failures := 0
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func totals(sentence: String, affinity: int = 0, roll: bool = false) -> Dictionary:
	return SpellMatcher.totals(SpellMatcher.find_matches(sentence, SpellData.catalog()), affinity, roll)

func battle_scene():
	Game.new_run()
	Game.tutorial_seen = true
	Game.map_node = Game.map.node_at(0, 0)
	Game.map_node.type = MapData.BATTLE
	Game.enemy = Game.EARLY_ENEMIES[0].duplicate(true)
	var battle = load(Game.BATTLE_SCENE).instantiate()
	add_child(battle)
	battle.set_process(false)
	battle._intent = {"attack": 0}
	return battle

func sentence(battle, text: String) -> void:
	battle._sentence = text
	battle._placed.clear()
	for i in text.length():
		battle._placed.append({"card": CloudCard.new(text[i]), "start": i})
	battle._refresh_sentence()

func _ready() -> void:
	Game.new_run()
	check(Game.max_length == 5 and Game.spells.size() == 4, "five slots and four current starter spells")
	check(SpellData.catalog().size() == 7 and SpellData.by_id("thunder_strike") == null and SpellData.by_id("ember") == null, "retired catalog removed")
	check(Game.deck.any(func(c: CloudCard) -> bool: return "d" in c.runes), "d available for ad")
	check(totals("ca").affinity == 2 and totals("ca").damage == 0, "ca grants two affinity")
	check(totals("ac", 4).damage == 7, "ac deals three plus affinity")
	check(totals("aaaaa").damage == 20, "five a runes trigger four overlapping fireballs")
	check(totals("ccc").shield == 10, "overlapping cc shields each grant five")
	check(totals("ab").damage == 6 and totals("ab").self_damage == 1, "ab costs one HP for six damage")
	check(totals("ba", 4).shield == 4 and totals("ba", 0).shield == 0, "ba grants affinity shield without consuming stacks")
	check(totals("cac").damage == 5 and totals("cac").affinity == 2, "ca benefits later ac in same sentence")
	check(totals("aca").damage == 3 and totals("aca").affinity == 2, "later ca never retroactively boosts earlier ac")
	var preview := totals("ad")
	check(preview.damage == 4.5 and preview.damage_min == 3 and preview.damage_max == 6, "ad preview shows range and expected damage")
	seed(381)
	var expected_rng := randf()
	seed(381)
	for i in 20:
		totals("ad")
	check(randf() == expected_rng, "preview never advances RNG")
	seed(17)
	var high := 0
	var independent := false
	var legal := true
	for i in 10000:
		var hit: int = totals("ad", 0, true).damage
		legal = legal and hit in [3, 6]
		high += int(hit == 6)
		independent = independent or totals("adad", 0, true).damage == 9
	check(legal and high > 4800 and high < 5200 and independent, "ten thousand ad rolls follow 3/6 distribution with independent triggers")
	var battle = battle_scene()
	sentence(battle, "ca")
	await battle._cast()
	check(battle._fire_affinity == 2 and battle._turn == 2, "real ca cast grants persistent affinity")
	var enemy_hp: int = battle._enemy_hp
	battle._append(CloudCard.new("a"))
	check(battle._enemy_hp == enemy_hp - 2, "affinity damages once per newly placed a")
	battle._start_turn()
	check(battle._fire_affinity == 2, "affinity survives another turn")
	battle._intent = {"block": 3}
	enemy_hp = battle._enemy_hp
	battle._append(CloudCard.new("aa"))
	check(battle._enemy_hp == enemy_hp - 1 and battle._affinity_block_used == 3, "multi rune affinity consumes enemy block correctly")
	battle._start_turn()
	battle._intent = {"attack": 0}
	battle._memory[0] = CloudCard.new("a")
	enemy_hp = battle._enemy_hp
	battle._use_memory(0)
	check(battle._enemy_hp == enemy_hp - 2, "using memory triggers persistent affinity")
	battle._start_turn()
	Game.spells = SpellData.catalog()
	sentence(battle, "ba")
	check(battle._preview().shield == 2, "real battle preview uses current affinity for ba")
	await battle._cast()
	check(battle._fire_affinity == 2, "ba does not consume affinity")
	battle.queue_free()
	await get_tree().process_frame
	battle = battle_scene()
	check(battle._fire_affinity == 0, "new battle starts with zero affinity")
	Game.spells = SpellData.catalog()
	Game.hp = 10
	Game.relics.append("bracer")
	sentence(battle, "ab")
	var hp_before := Game.hp
	enemy_hp = battle._enemy_hp
	await battle._cast()
	check(Game.hp == hp_before - 1 and battle._enemy_hp == enemy_hp - 6, "real ab bypasses shield and deals six")
	battle.queue_free()
	await get_tree().process_frame
	battle = battle_scene()
	Game.spells = SpellData.catalog()
	Game.hp = 1
	battle._enemy_hp = 1
	sentence(battle, "ab")
	await battle._cast()
	check(Game.hp == 0 and battle._enemy_hp == 1 and Game.pending_rewards.is_empty() and battle._phase == battle.Phase.OVER, "ab self lethal loses before granting victory")
	battle.queue_free()
	await get_tree().process_frame
	battle = battle_scene()
	Game.spells = SpellData.catalog()
	sentence(battle, "ad")
	for i in 10:
		check(battle._preview().dealt_min == 3 and battle._preview().dealt_max == 6, "stable random preview")
	enemy_hp = battle._enemy_hp
	await battle._cast()
	check(enemy_hp - battle._enemy_hp in [3, 6], "real ad cast resolves to three or six")
	battle.queue_free()
	await get_tree().process_frame
	Game.new_run()
	Game.spells = SpellData.catalog()
	Game.spells[0].fire_affinity = 3
	Game.spells[6].damage = 6
	Game.save_run()
	check(Game.load_run() and Game.spells[0].fire_affinity == 3 and Game.spells[6].random_bonus == 3 and Game.spells[6].damage == 6, "all new effect fields and upgrades survive disk reload")
	var old := Game.snapshot()
	old.erase("spell_ruleset")
	old.spells = [{"id": "thunder_strike", "name": "old", "pattern": "bba", "damage": 7}]
	old.hp = 19
	old.gold = 23
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_var(old)
	file.close()
	check(Game.load_run() and FileAccess.file_exists(Game.save_path + ".legacy") and Game.hp == 19 and Game.gold == 23 and Game.spells[0].id == "kindle", "legacy save backed up and migrated without retired spells")
	check(Game.load_run() and Game.spells[0].id == "kindle", "migration persists once")
	var shop = load(Game.SPELL_SHOP_SCENE).instantiate()
	add_child(shop)
	check(shop._offers.all(func(s: SpellData) -> bool: return s.id in ["bloodflame", "warmth", "wildfire"]), "shop offers only new unowned spells")
	shop.queue_free()
	await get_tree().process_frame
	Game.end_run()
	print("SPELL TEST FAILURES: ", failures)
	get_tree().quit(failures)
