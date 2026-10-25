extends Node
var failures := 0
var flashes: Array = []
var battle

func check(ok: bool, label: String):
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1

func prepare(spells: Array[SpellData], sentence: String):
	Game.new_run()
	Game.tutorial_seen = true
	Game.spells.assign(spells)
	Game.map_node = Game.map.node_at(0,0)
	Game.map_node.type = MapData.BATTLE
	Game.enemy = Game.EARLY_ENEMIES[1].duplicate(true)
	battle = load(Game.BATTLE_SCENE).instantiate()
	add_child(battle)
	battle.set_process(false)
	battle._intent = {"attack": 0}
	for i in sentence.length():
		battle._placed.append({"card": CloudCard.new(sentence[i]), "start": i})
	battle._sentence = sentence
	battle._refresh_sentence()
	flashes.clear()
	battle.spell_animation_started.connect(func(id: String, cover: Array):
		flashes.append([id,cover.duplicate()])
		if "--capture" in OS.get_cmdline_user_args():
			get_tree().create_timer(0.1).timeout.connect(capture.bind("%s_%d_glow" % [id,flashes.size()]))
			get_tree().create_timer(0.5).timeout.connect(capture.bind("%s_%d_fx" % [id,flashes.size()])))

func cleanup():
	await get_tree().create_timer(0.65).timeout
	battle.queue_free()
	await get_tree().process_frame

func _ready():
	prepare([SpellData.new("ab_test","甲","ab",{"damage":3},"icon_fire",0), SpellData.new("bc_test","乙","bc",{"damage":5},"icon_fire",0)], "abc")
	var before: int = battle._enemy_hp
	await battle._cast()
	check(flashes == [["ab_test",[0,1]],["bc_test",[1,2]]], "abc flashes ab then bc, shared b participates twice")
	check(battle._enemy_hp == before-8, "per spell animation settles damage exactly once")
	check(battle._enemy_visual.get_child_count() > 0, "missing enemy art has visible procedural figure")
	await cleanup()
	prepare([SpellData.new("ab_test","甲","ab",{"damage":3},"icon_fire",0), SpellData.new("bc_test","乙","bc",{"damage":5},"icon_fire",0)], "abc")
	Game.combo_damage = 4
	Game.relics.append("ember_ring")
	battle._placed[0].card = CloudCard.new("a", "blazing")
	battle._intent = {"block": 5}
	before = battle._enemy_hp
	var bonus_expected: int = battle._preview().dealt
	await battle._cast()
	check(battle._enemy_hp == before-bonus_expected, "combo relic and affix bonuses settle once after spells")
	await cleanup()
	prepare([SpellData.by_id("shield")], "cc")
	battle._intent = {"attack": 7}
	var hp := Game.hp
	await battle._cast()
	check(Game.hp == hp-2, "shield animation preserves enemy attack damage")
	await cleanup()
	prepare([SpellData.by_id("fireball")], "aaaa")
	battle._intent = {"block": 6}
	before = battle._enemy_hp
	await battle._cast()
	check(flashes.size() == 3 and flashes[1][1] == [1,2], "overlapping occurrences of same spell each get a release")
	check(battle._enemy_hp == before-9, "enemy block is consumed once across three hits")
	await cleanup()
	prepare([SpellData.by_id("kindle"),SpellData.by_id("fire_arrow"),SpellData.by_id("fireball"),SpellData.by_id("shield")], "caacc")
	before = battle._enemy_hp
	var expected: int = battle._preview().dealt
	await battle._cast()
	check(battle._enemy_hp == before-expected and battle._fire_affinity == 2, "affinity and mixed spells preserve preview result")
	check(flashes.size() == 4, "four matched spells each animate separately")
	await cleanup()
	prepare([SpellData.by_id("wildfire")], "adad")
	before = battle._enemy_hp
	seed(731)
	var rolled: int = battle._preview(true).dealt
	seed(731)
	await battle._cast()
	check(before-battle._enemy_hp == rolled, "random spell damage uses one sampled outcome per occurrence")
	await cleanup()
	prepare([SpellData.by_id("fireball")], "aaaa")
	battle._enemy_hp = 1
	await battle._cast()
	await get_tree().create_timer(0.6).timeout
	check(battle._phase == battle.Phase.OVER and battle._enemy_visual.modulate.a == 0, "victory fades enemy before showing reward")
	check(Game.pending_rewards.size() == 3, "animated victory still creates one reward checkpoint")
	await cleanup()
	Game.end_run()
	print("ANIMATION TEST FAILURES: ", failures)
	get_tree().quit(failures)


func capture(label: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/playtest/anim_"+label+".png")
