extends Node

var failures := 0
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failures += 1

func _ready() -> void:
	run.call_deferred()

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func run() -> void:
	# Keep the runner alive while normal game scenes change.
	get_tree().current_scene = null
	Game.new_run()
	Game.tutorial_seen = true
	Game.enter_node(Game.map.node_at(0, 0))
	await frames()
	var battle = get_tree().current_scene
	check(battle.scene_file_path == Game.BATTLE_SCENE, "map entry opens battle")
	battle.set_process(false)
	# Use a normal enemy and repeat actual cast resolution until victory.
	for turn in 5:
		if battle._phase == battle.Phase.OVER:
			break
		battle._placed.clear()
		for i in 5:
			battle._placed.append({"card": CloudCard.new("caacc"[i]), "start": i})
		battle._sentence = "caacc"
		battle._matches = SpellMatcher.find_matches(battle._sentence, Game.spells)
		battle._refresh_sentence()
		if turn == 0 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://.godot/reward-validation/battle-spells.png")
		var expected: int = maxi(0, battle._enemy_hp - battle._preview().dealt)
		await battle._cast()
		check(battle._enemy_hp == expected, "actual cast applies preview damage including affinity")
	check(battle._enemy_hp == 0 and Game.pending_rewards.size() == 3, "actual spell casts win and create growth choices")
	Game.go_to_reward()
	await frames()
	var page = get_tree().current_scene
	check(page.scene_file_path == Game.REWARD_SCENE, "victory opens growth scene")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/reward-validation/reward.png")
	# Dispatch actual mouse input at the choose and confirm button coordinates.
	for point in [Vector2(292, 620), Vector2(836, 790)]:
		var press := InputEventMouseButton.new()
		press.position = point
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		get_viewport().push_input(press, true)
		var release := press.duplicate()
		release.pressed = false
		get_viewport().push_input(release, true)
		await frames()
	check(Game.pending_rewards.is_empty() and get_tree().current_scene.scene_file_path == Game.MAP_SCENE, "mouse selection and confirmation save and return to map")
	check(Game.load_run() and Game.resume_scene == Game.MAP_SCENE, "disk checkpoint resumes map after claim")
	# Traverse a service and enter the next real battle through map entry API.
	var service: MapData.MapNode = Game.map.reachable_from(Game.map_node)[0]
	Game.enter_node(service)
	await frames()
	Game.go_to_map()
	await frames()
	Game.enter_node(Game.map.reachable_from(Game.map_node)[0])
	await frames()
	check(get_tree().current_scene.scene_file_path == Game.BATTLE_SCENE, "map service and next battle transition succeeds")
	Game.end_run()
	print("FLOW TEST FAILURES: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
