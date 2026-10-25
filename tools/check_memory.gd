extends Node

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func _ready() -> void:
	Game.enemy = Game.EARLY_ENEMIES[0].duplicate(true)
	Game.tutorial_seen = true
	var battle = load("res://scenes/battle.tscn").instantiate()
	add_child(battle)
	battle.set_process(false)
	check(battle._memory.size() == 1, "single memory slot")
	var first := FragmentCloud.create(CloudCard.new("ac"), 6.0)
	var second := FragmentCloud.create(CloudCard.new("b"), 6.0)
	for cloud in [first, second]:
		battle._cloud_layer.add_child(cloud)
		battle._clouds.append(cloud)
		cloud.stored.connect(battle._on_cloud_stored)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	first._gui_input(right_click)
	check(battle._memory[0] == first.card and not battle._clouds.has(first), "right click stores fragment")
	second._gui_input(right_click)
	check(battle._memory[0] == first.card and battle._clouds.has(second), "full memory rejects replacement")
	battle._sentence = "aaaaaa"
	battle._use_memory(0)
	check(battle._memory[0] == first.card, "fragment retained when sentence has insufficient room")
	battle._start_turn()
	check(battle._memory[0] == first.card, "memory survives next turn")
	for child in battle._memory_layer.get_children():
		if child is Button and not child.is_queued_for_deletion():
			child.pressed.emit()
			break
	check(battle._memory[0] == null and battle._sentence == "ac", "memory button uses fragment and clears slot")
	var third := FragmentCloud.create(CloudCard.new("c"), 6.0)
	battle._cloud_layer.add_child(third)
	battle._clouds.append(third)
	third.stored.connect(battle._on_cloud_stored)
	third._gui_input(right_click)
	check(battle._memory[0] == third.card, "can store again after use")
	battle._phase = battle.Phase.RESOLVE
	battle._use_memory(0)
	check(battle._memory[0] == third.card, "cannot use memory outside build phase")
	print("MEMORY TEST FAILURES: ", failures)
	get_tree().quit(0 if failures == 0 else 1)
