extends Node

var failures := 0

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func encounter(elite: bool = false) -> void:
	Game.map_node = Game.map.node_at(0, 0)
	Game.map_node.type = MapData.ELITE if elite else MapData.BATTLE
	Game.map_node.visited = true
	Game.enemy = Game.EARLY_ENEMIES[0].duplicate(true)
	Game.resume_scene = Game.BATTLE_SCENE
	Game.tutorial_seen = true

func _ready() -> void:
	if "--prepare-resume" in OS.get_cmdline_user_args():
		Game.new_run()
		encounter()
		Game.complete_battle()
		get_tree().quit()
		return
	if "--verify-resume" in OS.get_cmdline_user_args():
		check(Game.pending_rewards.size() == 3 and Game.resume_scene == Game.REWARD_SCENE, "fresh process restores pending reward checkpoint")
		check(not Game.complete_battle(), "fresh process rejects repeated victory loot")
		Game.end_run()
		get_tree().quit(failures)
		return
	Game.new_run()
	encounter(true)
	var patterns := Game.spells.map(func(s: SpellData) -> String: return s.pattern)
	check(Game.complete_battle(), "elite victory checkpoint saved")
	var gold := Game.gold
	var relics := Game.relics.duplicate()
	var offers := Game.pending_rewards.duplicate(true)
	check(offers.size() == 3, "three growth choices")
	check(not Game.complete_battle() and Game.gold == gold and Game.relics == relics, "loot cannot be granted twice")
	check(Game.load_run() and Game.pending_rewards == offers, "pending offers survive disk reload unchanged")
	check(not Game.claim_reward(-1) and not Game.claim_reward(3), "invalid claims rejected")
	var target: SpellData
	for spell in Game.spells:
		if spell.id == offers[0].spell:
			target = spell
	var old: int = target.get(offers[0].effect)
	check(Game.claim_reward(0), "claim stat upgrade")
	check(target.get(offers[0].effect) == old + int(offers[0].amount), "stat increased by offered amount")
	check(not Game.claim_reward(0), "double click rejected")
	check(Game.load_run() and Game.pending_rewards.is_empty(), "claimed state survives disk reload")
	check(not Game.complete_battle() and Game.gold == gold, "reload cannot reclaim encounter")
	for spell in Game.spells:
		if spell.id == offers[0].spell:
			check(spell.get(offers[0].effect) == old + int(offers[0].amount), "stat upgrade survives disk reload")
	check(Game.spells.map(func(s: SpellData) -> String: return s.pattern) == patterns, "ordinary reward never adds spell characters")
	Game.new_run()
	encounter()
	Game.complete_battle()
	check(Game.max_length == 5, "initial sentence length is five")
	check(offers[0].kind == "stat" and offers[1].kind == "capacity" and offers[2].kind == "mind", "reward slots have fixed roles")
	check(Game.claim_reward(1) and Game.max_length == 6, "sentence capacity upgrade granted")
	check(Game.load_run() and Game.max_length == 6, "capacity upgrade survives disk reload")
	Game.combo_damage = 4 # Compatibility for already claimed legacy rewards.
	var battle = load(Game.BATTLE_SCENE).instantiate()
	add_child(battle)
	battle.set_process(false)
	battle._sentence = "accbbac"
	battle._matches = SpellMatcher.find_matches(battle._sentence, Game.spells)
	var base := SpellMatcher.totals(battle._matches)
	check(battle._preview().damage == base.damage + 4, "actual battle preview adds combo once despite repeated matches")
	var single := SpellMatcher.find_matches("aaaaa", Game.spells)
	check(Game.combo_bonus(single) == 0, "two copies of one spell do not trigger combo")
	battle.queue_free()
	await get_tree().process_frame
	Game.new_run()
	encounter()
	Game.complete_battle()
	var build_time := Game.build_time
	check(Game.claim_reward(2) and Game.cloud_life == 8 and Game.build_time == build_time, "mind upgrade changes lifetime only")
	check(Game.load_run() and Game.cloud_life == 8, "mind upgrade survives reload")
	battle = load(Game.BATTLE_SCENE).instantiate()
	add_child(battle)
	battle.set_process(false)
	battle._emerge_cloud()
	check(battle._clouds.size() > 0 and battle._clouds[0].max_life == 8, "next battle spawns longer lived clouds")
	battle.queue_free()
	await get_tree().process_frame
	Game.cloud_life = Game.CLOUD_LIFE_CAP
	var capped := Game.make_rewards()
	check(capped.size() == 3 and not capped.any(func(o: Dictionary) -> bool: return o.kind == "mind"), "capped mind reward replaced by useful miscellaneous reward")
	Game.spells.resize(1)
	var solo := Game.make_rewards()
	check(not solo.any(func(o: Dictionary) -> bool: return o.kind == "combo"), "impossible combo excluded")
	Game.new_run()
	encounter()
	Game.complete_battle()
	var before := Game.snapshot()
	var path := Game.save_path
	Game.save_path = "res://.godot/reward-validation/missing/subdir/save"
	check(not Game.claim_reward(0) and Game.snapshot() == before, "save failure rolls back reward and preserves candidates")
	Game.save_path = path
	Game.new_run()
	check(Game.combo_damage == 0 and Game.cloud_life == 6 and Game.pending_rewards.is_empty(), "new run clears growth")
	# Exercise the real victory overlay, reward buttons, map transition and next encounter.
	encounter()
	battle = load(Game.BATTLE_SCENE).instantiate()
	add_child(battle)
	battle.set_process(false)
	battle._finish(true)
	var won_gold := Game.gold
	battle._finish(true)
	check(Game.gold == won_gold and Game.pending_rewards.size() == 3, "battle victory callback idempotent")
	battle.queue_free()
	await get_tree().process_frame
	var page = load(Game.REWARD_SCENE).instantiate()
	add_child(page)
	for child in page.get_children():
		if child is Button and child.name == "RewardChoice0":
			child.pressed.emit()
			break
	await get_tree().process_frame
	check(page._selected == 0, "reward button selects first option")
	# Do not replace this test runner; verify the shared interface then instantiate map.
	check(Game.claim_reward(page._selected), "UI selected reward uses common claim interface")
	page.queue_free()
	await get_tree().process_frame
	var map_page = load(Game.MAP_SCENE).instantiate()
	add_child(map_page)
	check(not map_page._reachable.is_empty(), "reward resumes reachable map routes")
	map_page.queue_free()
	Game.map_node = Game.map.node_at(2, 0)
	Game.map_node.type = MapData.BATTLE
	Game.enemy = Game.EARLY_ENEMIES[0].duplicate(true)
	battle = load(Game.BATTLE_SCENE).instantiate()
	add_child(battle)
	check(battle._enemy_hp > 0 and Game.pending_rewards.is_empty(), "next encounter starts without old reward")
	battle.queue_free()
	await get_tree().process_frame
	Game.end_run()
	print("REWARD TEST FAILURES: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
