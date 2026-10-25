extends Node
const Bot = preload("res://tools/balance_bot.gd")
var records: Array = []
var runs: Array = []
var errors: Array = []
var count := 10
var run_count := 10

func adapt(variant: String) -> void:
	if variant == "no_affinity":
		for spell in Game.spells:
			spell.fire_affinity = 0
			spell.damage_per_affinity = 0
			spell.shield_per_affinity = 0

func fight(enemy: Dictionary, variant: String, profile: String, battle_seed: int) -> Dictionary:
	seed(battle_seed)
	Game.enemy = enemy.duplicate(true)
	var bot = Bot.new()
	bot.variant = variant
	if profile == "slow":
		bot.latency = 0.9
		bot.miss_rate = 0.12
	add_child(bot)
	bot.set_process(false)
	var result: Dictionary = bot.play()
	result.enemy = enemy.id
	result.variant = variant
	result.profile = profile
	result.seed = battle_seed
	bot.free()
	return result

func reward() -> int:
	var best := -INF
	var chosen := 0
	for i in Game.pending_rewards.size():
		var o: Dictionary = Game.pending_rewards[i]
		var value := 0.0
		match o.kind:
			"stat":
				value = float(o.amount) * {"fireball": 2.5, "fire_arrow": 1.0, "kindle": 2.0, "shield": 1.4}.get(o.spell, 1.0)
			"capacity": value = 5.0
			"heal": value = 12.0 if Game.hp < 18 else 3.0
			"mind": value = 2.0
			"gold": value = 2.5
			"short_sentence": value = 4.0
		if value > best:
			best = value
			chosen = i
	return chosen

func service(type: String) -> void:
	match type:
		MapData.REST:
			Game.heal(roundi(Game.max_hp * 0.4))
		MapData.TREASURE:
			var relic := Game.random_relic()
			if relic != null: Game.gain_relic(relic)
			else: Game.gold += 15
		MapData.SHOP:
			# Use the actual random three-relic shelf, no rerolls or free purchases.
			var candidates := RelicData.catalog().filter(func(r: RelicData) -> bool: return r.available())
			candidates.shuffle()
			var shelf := candidates.slice(0, 3)
			var priority := ["ember_ring", "bracer", "crystal", "echo", "heart", "scroll", "hourglass", "feather", "glove", "bookmark"]
			shelf.sort_custom(func(a: RelicData, b: RelicData) -> bool: return priority.find(a.id) < priority.find(b.id))
			for relic: RelicData in shelf:
				if Game.gold >= relic.cost:
					Game.gold -= relic.cost
					Game.gain_relic(relic)
		MapData.SCRIPTORIUM:
			for card in Game.deck:
				var at := card.runes.find("d")
				if at == -1: at = card.runes.find("b")
				if at >= 0:
					card.runes = card.runes.substr(0, at) + "a" + card.runes.substr(at + 1)
					break

func full_run(run_seed: int, variant: String) -> Dictionary:
	seed(run_seed)
	Game.new_run()
	adapt(variant)
	var route: Array = []
	var reached := false
	var cleared := false
	var first_failure := ""
	var priority := [MapData.REST, MapData.TREASURE, MapData.SHOP, MapData.SCRIPTORIUM, MapData.BATTLE, MapData.ELITE, MapData.BOSS]
	for step in 9:
		var reachable := Game.map.reachable_from(Game.map_node)
		if reachable.is_empty():
			errors.append("no reachable node before boss: %d" % run_seed)
			break
		reachable.sort_custom(func(a: MapData.MapNode, b: MapData.MapNode) -> bool: return priority.find(a.type) < priority.find(b.type))
		var node: MapData.MapNode = reachable[0]
		Game.map_node = node
		node.visited = true
		var entry := {"layer": node.layer, "type": node.type, "hp_before": Game.hp}
		if node.type in [MapData.BATTLE, MapData.ELITE, MapData.BOSS]:
			var enemy: Dictionary
			if node.type == MapData.BOSS:
				reached = true
				enemy = Game.BOSS_ENEMY
			elif node.type == MapData.ELITE:
				enemy = Game._elite(Game.LATE_ENEMIES.pick_random())
			else:
				enemy = (Game.EARLY_ENEMIES if node.layer < Game.EARLY_LAYERS else Game.LATE_ENEMIES).pick_random()
			var result := fight(enemy, variant, "normal", run_seed * 100 + step)
			entry.result = result
			entry.hp_after = Game.hp
			route.append(entry)
			if not result.won:
				first_failure = enemy.id
				break
			if node.type == MapData.BOSS:
				cleared = true
				break
			if not Game.complete_battle(): errors.append("settlement failed")
			var selected := reward()
			entry.reward = Game.pending_rewards[selected].duplicate(true)
			if not Game.claim_reward(selected): errors.append("claim failed")
		else:
			service(node.type)
			entry.hp_after = Game.hp
			route.append(entry)
	return {"seed": run_seed, "variant": variant, "reached_boss": reached, "cleared": cleared, "failure": first_failure, "hp": Game.hp, "length": Game.max_length, "spells": Game.spells.map(func(s: SpellData) -> Dictionary: return {"id": s.id, "damage": s.damage, "shield": s.shield, "affinity": s.fire_affinity}), "relics": Game.relics.duplicate(), "route": route}

func _ready() -> void:
	run.call_deferred()

func validate_adapter() -> void:
	Engine.time_scale = 100.0
	for case in [{"sentence": "caacc", "enemy": Game.EARLY_ENEMIES[0]}, {"sentence": "aaaaa", "enemy": Game.EARLY_ENEMIES[1]}, {"sentence": "ab", "enemy": Game.LATE_ENEMIES[0]}, {"sentence": "ad", "enemy": Game.LATE_ENEMIES[1]}, {"sentence": "ba", "enemy": Game.BOSS_ENEMY}]:
		var text: String = case.sentence
		Game.new_run()
		Game.spells = SpellData.catalog()
		Game.enemy = case.enemy.duplicate(true)
		Game.map_node = Game.map.node_at(0, 0)
		Game.tutorial_seen = true
		var before := Game.snapshot()
		var bot = Bot.new()
		add_child(bot)
		bot.set_process(false)
		bot._fire_affinity = 2
		bot._sentence = text
		bot._placed.clear()
		for i in text.length(): bot._placed.append({"card": CloudCard.new(text[i]), "start": i})
		bot._refresh_sentence()
		seed(123)
		bot.resolve_fast()
		var expected := [Game.hp, bot._enemy_hp, bot._fire_affinity, bot._turn, bot._burn, bot._haste]
		bot.free()
		Game.restore_snapshot(before)
		var real = load(Game.BATTLE_SCENE).instantiate()
		add_child(real)
		real.set_process(false)
		real._fire_affinity = 2
		real._sentence = text
		real._placed.clear()
		for i in text.length(): real._placed.append({"card": CloudCard.new(text[i]), "start": i})
		real._refresh_sentence()
		seed(123)
		await real._cast()
		var actual := [Game.hp, real._enemy_hp, real._fire_affinity, real._turn, real._burn, real._haste]
		if actual != expected: errors.append({"adapter": text, "expected": expected, "actual": actual})
		real.queue_free()
		await get_tree().process_frame
	Engine.time_scale = 1.0
	print("ADAPTER VALIDATION ERRORS: ", errors.size())

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): count = int(arg.trim_prefix("--samples="))
		if arg.begins_with("--runs="): run_count = int(arg.trim_prefix("--runs="))
	await validate_adapter()
	if not errors.is_empty():
		print(errors)
		get_tree().quit(1)
		return
	var variants := ["baseline", "no_affinity", "no_overlap"]
	for variant: String in variants:
		for profile: String in ["normal", "slow"]:
			for enemy: Dictionary in Game.EARLY_ENEMIES + Game.LATE_ENEMIES:
				for n in count:
					Game.new_run()
					adapt(variant)
					var result := fight(enemy, variant, profile, 2000 + n)
					records.append(result)
				print("DUELS ", variant, " ", profile, " ", enemy.id, " n=", count)
				await get_tree().process_frame
		for n in run_count:
			runs.append(full_run(9000 + n, variant))
			if n % 10 == 0:
				print("RUNS ", variant, " ", n + 1, "/", run_count)
				await get_tree().process_frame
	var file := FileAccess.open("res://.godot/reward-validation/balance-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"duels": records, "runs": runs, "errors": errors, "samples": count, "run_count": run_count}, "\t"))
	file.close()
	Game.end_run()
	print("BALANCE COMPLETE: ", records.size(), " duels, ", runs.size(), " runs, errors=", errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)
