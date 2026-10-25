extends "res://scripts/battle.gd"
## Test-only fast adapter: production placement, preview, draw and enemy skills.
## resolve_fast omits animation/timers; check_balance compares it with real _cast.
class SilentEffects:
	extends Node2D
	func bolt(_from: Vector2, _to: Vector2, _tint: Color, _heavy: bool = false, _bend: bool = false) -> void:
		pass

var won := false
var variant := "baseline"
var supply: Array = []
var latency := 0.45
var miss_rate := 0.05
var expired := 0
var affinity_hits := 0
var affinity_damage := 0
var spell_damage := 0
var fireball_damage := 0
var ca_casts := 0
var decisions := 0
var trace: Array = []
var _best: Dictionary

func _ready() -> void:
	_effects = SilentEffects.new()
	add_child(_effects)
	_enemy = Game.enemy
	_enemy_hp = _enemy.hp
	_memory.resize(1)
	_draw_pile.assign(Game.deck)
	_draw_pile.shuffle()
	_cloud_layer = Control.new()
	add_child(_cloud_layer)
	_cast_button = TextureButton.new()
	add_child(_cast_button)
	_reroll_button = Button.new()
	add_child(_reroll_button)
	_start_turn()

func _popup(_text: String, _at: Vector2, _color: Color = Color.WHITE, _size: int = 42) -> void:
	pass
func _refresh_status() -> void:
	pass
func _refresh_timer() -> void:
	pass
func _refresh_piles() -> void:
	pass
func _refresh_memory() -> void:
	pass
func _animate_hand_idle() -> void:
	pass
func _auto_cast_if_full() -> void:
	pass
func _refresh_sentence() -> void:
	_matches = SpellMatcher.find_matches(_sentence, Game.spells)
	if variant == "no_overlap":
		var end := -1
		var filtered: Array[Dictionary] = []
		for m in _matches:
			if m.spell.id == "fireball":
				if m.start < end:
					continue
				end = m.start + m.length
			filtered.append(m)
		_matches = filtered
func _finish(victory: bool) -> void:
	won = victory
	_phase = Phase.OVER
func _discard_clouds() -> void:
	for entry: Dictionary in supply:
		_discard_pile.append(entry.card)
	supply.clear()

func state() -> Array:
	return [_sentence, _placed.duplicate(), _placed_shield, _enemy_hp, _affinity_block_used, _seal_placed, _phase, _matches.duplicate(), _time_left, won]
func restore(s: Array) -> void:
	_sentence = s[0]
	_placed.assign(s[1])
	_placed_shield = s[2]
	_enemy_hp = s[3]
	_affinity_block_used = s[4]
	_seal_placed = s[5]
	_phase = s[6]
	_matches.assign(s[7])
	_time_left = s[8]
	won = s[9]

func score() -> float:
	if _phase == Phase.OVER and won:
		return 1000.0
	var r := _preview()
	if r.self_damage >= Game.hp:
		return -1000.0
	var damage: float = r.dealt
	var attack: int = _intent.get("attack", 0) + (_strength if _intent.has("attack") else 0)
	var defense: float = mini(attack, r.shield)
	var gain: int = r.affinity - _fire_affinity
	var future := clampf((_enemy_hp - damage) / 12.0, 0.0, 3.0)
	return minf(damage, _enemy_hp) + (_enemy.hp - _enemy_hp) + defense * (1.1 if Game.hp < 12 else 0.8) + gain * future - r.self_damage * 1.2 + (1000.0 if damage >= _enemy_hp else 0.0)

func search(cards: Array, path: Array, depth: int) -> void:
	var value := score()
	if value > _best.score + 0.001:
		_best = {"score": value, "path": path.duplicate()}
	if depth >= 3 or _phase == Phase.OVER or _sentence.length() >= Game.max_length:
		return
	for i in cards.size():
		var item: Dictionary = cards[i]
		if not _can_append(item.card):
			continue
		var before := state()
		_append(item.card)
		var rest := cards.duplicate()
		rest.remove_at(i)
		path.append(item)
		search(rest, path, depth + 1)
		path.pop_back()
		restore(before)

func tick(dt: float) -> void:
	_time_left -= dt
	_emerge_in -= dt
	for i in range(supply.size() - 1, -1, -1):
		supply[i].life -= dt
		if supply[i].life <= 0:
			_discard_pile.append(supply[i].card)
			supply.remove_at(i)
			expired += 1
	if _emerge_in <= 0 and supply.size() < Game.max_clouds:
		var cards := _draw_cards(1)
		if not cards.is_empty():
			supply.append({"card": cards[0], "life": Game.cloud_life, "memory": false})
		_emerge_in = EMERGE_INTERVAL

func resolve_fast() -> void:
	var r := _preview(true)
	trace.append({"turn": _turn, "sentence": _sentence, "affinity": _fire_affinity, "damage": r.dealt, "shield": r.shield, "hp": Game.hp, "enemy_hp": _enemy_hp})
	Game.hp = maxi(0, Game.hp - r.self_damage)
	if Game.hp <= 0:
		_finish(false)
		return
	for m in _matches:
		if m.spell.id == "kindle":
			ca_casts += 1
		if m.spell.id == "fireball":
			fireball_damage += m.spell.damage
	_fire_affinity = r.affinity
	_enemy_hp = maxi(0, _enemy_hp - int(r.dealt))
	spell_damage += int(r.dealt)
	Game.heal(r.heal)
	Game.gold += r.gold
	if _enemy_hp <= 0:
		_finish(true)
		return
	Game.hp = maxi(0, Game.hp - r.taken)
	_apply_enemy_skills()
	if _burn > 0 and Game.hp > 0:
		Game.hp = maxi(0, Game.hp - _burn)
		_burn -= 1
	if Game.hp <= 0:
		_finish(false)
	else:
		_start_turn()

func play() -> Dictionary:
	var action_in := latency
	var steps := 0
	while _phase != Phase.OVER and _turn <= 20 and steps < 6000:
		steps += 1
		tick(0.1)
		action_in -= 0.1
		if _time_left <= 0 or _sentence.length() >= Game.max_length:
			resolve_fast()
			action_in = latency
			continue
		if action_in > 0:
			continue
		action_in = latency
		if randf() < miss_rate:
			continue
		# Allow a small visible batch to form; the bot never reads the draw pile.
		if supply.size() < 3 and _time_left > 5 and _sentence.is_empty():
			continue
		var cards := supply.duplicate()
		if _memory[0] != null:
			cards.append({"card": _memory[0], "memory": true})
		_best = {"score": score(), "path": []}
		search(cards, [], 0)
		if not _best.path.is_empty():
			var item: Dictionary = _best.path[0]
			var before_hp := _enemy_hp
			if item.memory:
				_use_memory(0)
			else:
				supply.erase(item)
				_append(item.card)
			affinity_damage += before_hp - _enemy_hp
			affinity_hits += (item.card as CloudCard).runes.count("a") if _fire_affinity > 0 else 0
			decisions += 1
		elif _memory[0] == null:
			for entry: Dictionary in supply:
				if entry.card.runes == "a" and not _can_append(entry.card):
					_memory[0] = entry.card
					supply.erase(entry)
					break
		# Cast early only to kill; otherwise retain the option to complete a sentence.
		if _phase != Phase.OVER and _preview().dealt_min >= _enemy_hp:
			resolve_fast()
	if _phase != Phase.OVER:
		_finish(false)
	return {"won": won, "turns": _turn, "hp": Game.hp, "affinity": _fire_affinity, "affinity_damage": affinity_damage, "affinity_hits": affinity_hits, "spell_damage": spell_damage, "fireball_damage": fireball_damage, "ca_casts": ca_casts, "expired": expired, "decisions": decisions, "trace": trace}
