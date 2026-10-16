extends Control
## 一场对决：敌人预告 → 限时构句 → 释放结算 → 敌人行动，循环到一方倒下。
## 画面按 art/concept/battle_layout_v2.jpg 的版式布局（1672x941），分为敌人区、咒语构筑、灵感碎片、法术列表四块。

## INTRO：开场教程还没点掉，计时和词云都不动。
enum Phase { INTRO, BUILD, RESOLVE, OVER }

const STAGE_BACKGROUND := "res://art/backgrounds/battle_stage.png"
const HAND_FRAMES := "res://art/characters/player/hand_wand/frame_%03d.png"
const ENEMY_ART := "res://art/characters/enemies/%s.png"
const MIND_BACKGROUND := "res://art/backgrounds/mind_area.webp"
## 第一场战斗开始前盖在整个画面上的教程图，点一下才正式开战。
const TUTORIAL_IMAGE := "res://art/tutorial/battle_basics.webp"

## 舞台背景（1983x793）按舞台比例裁出中下部：留住烛台和地上的法阵。
const STAGE_SOURCE := Rect2(0, 300, 1983, 432)
const STAGE_RECT := Rect2(0, 0, 1672, 364)
## 第一人称持杖的手：0～2 帧是待机（杖尖轻颤），3～7 帧是挥杖施法。
const HAND_RECT := Rect2(300, -30, 588, 509)
const HAND_IDLE_FRAMES := [0, 1, 2, 1]
const HAND_IDLE_FPS := 5.0
const HAND_CAST_FPS := 14.0
const PLAYER_ANCHOR := Vector2(420, 250)
const ENEMY_ANCHOR := Vector2(1058, 170)

const SPELL_RECT := Rect2(8, 372, 1254, 228)
const TILE_CENTER_X := 661.0
const TILE_TOP := 402.0
const TILE_AREA_WIDTH := 960.0
const BRACKET_TOP := 486.0
const BRACKET_AREA_HEIGHT := 58.0
const MIND_RECT := Rect2(14, 610, 1244, 322)
## 记忆栏：右键词云存入，之后点击放进句子。存着的词云跨回合保留，这场对决结束后回到牌库。
const MEMORY_SLOTS := 4
## 换一批选项要付出的构句时间。
const REROLL_TIME_COST := 3.0
## 互换句子里相邻两朵词云要付出的构句时间。
const SWAP_TIME_COST := 2.0
## 时间是唯一的货币：脑海里没满时，每隔这么久浮现一朵新词云（回合开始时第一朵立刻出现）。
const EMERGE_INTERVAL := 0.8
## 词云漂移速度范围（像素/秒）。慢速漂移只是营造“念头在飘”，不是考验反应。
const DRIFT_SPEED_MIN := 14.0
const DRIFT_SPEED_MAX := 32.0
## 脑海区里词云会撞上的固定障碍（脑海区内的坐标）：左下记忆栏、右下计数和按钮。
const MIND_OBSTACLES := [Rect2(10, 216, 438, 106), Rect2(792, 262, 452, 60)]

var _phase := Phase.INTRO
var _turn := 0
var _enemy: Dictionary
var _enemy_hp: int
var _intent: Dictionary
## 敌人力量：每次攻击额外加这么多。
var _strength := 0
## 玩家身上的灼烧层数：每回合结束受等量伤害，然后减 1。
var _burn := 0
## 敌人上回合的催促：本回合构句时间减少的秒数。
var _haste := 0.0
## 封印：本回合句子里预先占住的格子（-1 表示没有）。_seal_next 是这回合意图要封的格子。
var _seal_index := -1
var _seal_next := -1
var _seal_placed := false
var _status_layer: Control
var _hand: TextureRect
var _hand_frames: Array[Texture2D] = []
var _hand_casting := false
var _hand_clock := 0.0
var _sentence := ""
## 句子里每朵词云的来源与位置：{card, start}。
var _placed: Array[Dictionary] = []
## 放置类词条累积的护盾，本回合有效。
var _placed_shield := 0
var _draw_pile: Array[CloudCard] = []
var _discard_pile: Array[CloudCard] = []
## 当前浮在脑海区里的词云。
var _clouds: Array[FragmentCloud] = []
var _emerge_in := 0.0
var _matches: Array[Dictionary] = []
var _time_left := 0.0

var _stage: TextureRect
var _player_hp_bar: UiBar
var _player_hp_label: Label
var _enemy_hp_bar: UiBar
var _enemy_hp_label: Label
var _intent_icon: TextureRect
var _intent_label: RichTextLabel
var _timer_bar: UiBar
var _tile_layer: Control
var _bracket_layer: Control
var _stats_label: RichTextLabel
var _cast_button: TextureButton
var _cast_hover: TextureRect
var _cloud_layer: Control
var _reroll_button: Button
var _pile_label: Label
var _memory: Array = []
var _memory_layer: Control
var _cards: Array[SpellCard] = []
## 句子里每个符文牌的节点，以及每个匹配对应的 [括号, 标签]，释放动画用。
var _tile_nodes: Array[Control] = []
var _bracket_nodes: Array = []
var _popup_layer: Control


func _ready() -> void:
	_enemy = Game.current_enemy()
	_enemy_hp = _enemy.hp
	_memory.resize(MEMORY_SLOTS)
	_draw_pile.assign(Game.deck)
	_draw_pile.shuffle()
	_build_backdrop()
	_build_stage()
	_build_spell_area()
	_build_mind_area()
	_build_spell_list()
	_popup_layer = Control.new()
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popup_layer)
	if Game.tutorial_seen:
		_start_turn()
	else:
		_show_tutorial()


## 整屏教程图，点击任意处淡出后才开始第一回合。
func _show_tutorial() -> void:
	var page := TextureRect.new()
	page.texture = load(TUTORIAL_IMAGE)
	page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(UiKit.place(page, Rect2(0, 0, 1672, 941)))

	var hint := UiKit.outlined(UiKit.centered(UiKit.label("点击任意处开始战斗", 26, UiKit.CREAM)), 6)
	var pill := UiKit.ink_box(Color(UiKit.NIGHT, 0.75), 22)
	pill.border_color = UiKit.GOLD
	hint.add_theme_stylebox_override("normal", pill)
	page.add_child(UiKit.place(hint, Rect2(656, 884, 360, 46)))
	var blink := hint.create_tween().set_loops()
	blink.tween_property(hint, "modulate:a", 0.45, 0.8).set_trans(Tween.TRANS_SINE)
	blink.tween_property(hint, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	var dismiss := Button.new()
	dismiss.flat = true
	dismiss.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		dismiss.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	page.add_child(UiKit.place(dismiss, Rect2(0, 0, 1672, 941)))
	dismiss.pressed.connect(func() -> void:
		dismiss.disabled = true
		Game.tutorial_seen = true
		var fade := page.create_tween()
		fade.tween_property(page, "modulate:a", 0.0, 0.3)
		fade.tween_callback(page.queue_free)
		_start_turn())


func _process(delta: float) -> void:
	_animate_hand_idle(delta)
	if _phase != Phase.BUILD:
		return
	_time_left -= delta
	_refresh_timer()
	if _time_left <= 0.0:
		_cast()
		return
	_emerge_in -= delta
	if _emerge_in <= 0.0 and _clouds.size() < Game.max_clouds:
		_emerge_in = EMERGE_INTERVAL
		_emerge_cloud()
	_move_clouds(delta)


# ---------------------------------------------------------------- 词云漂移与碰撞

func _move_clouds(delta: float) -> void:
	var bounds := Rect2(Vector2(6, 6), MIND_RECT.size - Vector2(12, 12))
	for cloud in _clouds:
		if cloud.hovered:
			continue
		cloud.base_position += cloud.velocity * delta
		var body := _body(cloud)
		if body.position.x < bounds.position.x:
			cloud.base_position.x += bounds.position.x - body.position.x
			cloud.velocity.x = absf(cloud.velocity.x)
		elif body.end.x > bounds.end.x:
			cloud.base_position.x -= body.end.x - bounds.end.x
			cloud.velocity.x = -absf(cloud.velocity.x)
		if body.position.y < bounds.position.y:
			cloud.base_position.y += bounds.position.y - body.position.y
			cloud.velocity.y = absf(cloud.velocity.y)
		elif body.end.y > bounds.end.y:
			cloud.base_position.y -= body.end.y - bounds.end.y
			cloud.velocity.y = -absf(cloud.velocity.y)
		for obstacle: Rect2 in MIND_OBSTACLES:
			_bounce_off(cloud, obstacle)
	for i in _clouds.size():
		for j in range(i + 1, _clouds.size()):
			_collide(_clouds[i], _clouds[j])


## 碰撞用的形状：比控件略小，云朵边缘的留白不算。
func _body(cloud: FragmentCloud) -> Rect2:
	return Rect2(cloud.base_position, cloud.size).grow(-8.0)


## 两块矩形的重叠：返回沿 x 或 y 中较浅的那一轴的分离向量（从 a 指向 b）。
func _separation(a: Rect2, b: Rect2) -> Vector2:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	var direction := b.get_center() - a.get_center()
	if overlap_x < overlap_y:
		return Vector2(overlap_x * (1.0 if direction.x >= 0.0 else -1.0), 0)
	return Vector2(0, overlap_y * (1.0 if direction.y >= 0.0 else -1.0))


func _bounce_off(cloud: FragmentCloud, obstacle: Rect2) -> void:
	var body := _body(cloud)
	if not body.intersects(obstacle):
		return
	var push := -_separation(body, obstacle)
	cloud.base_position += push
	if push.x != 0.0:
		cloud.velocity.x = absf(cloud.velocity.x) * signf(push.x)
	else:
		cloud.velocity.y = absf(cloud.velocity.y) * signf(push.y)


## 两朵词云相撞：各退一半（被悬停的那朵不动，另一朵全退），沿碰撞轴交换速度。
func _collide(a: FragmentCloud, b: FragmentCloud) -> void:
	var body_a := _body(a)
	var body_b := _body(b)
	if not body_a.intersects(body_b):
		return
	var push := _separation(body_a, body_b)
	var share_a := 0.0 if a.hovered else (1.0 if b.hovered else 0.5)
	a.base_position -= push * share_a
	b.base_position += push * (1.0 - share_a)
	var axis := Vector2(signf(push.x), 0) if push.x != 0.0 else Vector2(0, signf(push.y))
	if (b.velocity - a.velocity).dot(axis) < 0.0:
		var va := a.velocity.dot(axis)
		var vb := b.velocity.dot(axis)
		a.velocity += axis * (vb - va)
		b.velocity += axis * (va - vb)


# ---------------------------------------------------------------- 回合流程

func _start_turn() -> void:
	_turn += 1
	var intents: Array = _enemy.intents
	_intent = intents[(_turn - 1) % intents.size()]
	_hand_casting = false
	_seal_next = randi_range(1, Game.max_length - 2) if _intent.has("seal") else -1
	# 上回合句子里的词云和没选的词云都进弃牌堆（封印格不是词云）。
	for placed in _placed:
		if not placed.get("sealed", false):
			_discard_pile.append(placed.card)
	_discard_clouds()
	_placed.clear()
	_placed_shield = 0
	_sentence = ""
	_seal_placed = false
	_time_left = Game.build_time - _haste
	if _haste > 0.0:
		_popup("催促：-%d 秒" % _haste, Vector2(620, 520), UiKit.RED, 34)
	_haste = 0.0
	_place_seal_if_due()
	_phase = Phase.BUILD
	UiKit.clear_children(_cloud_layer)
	_emerge_in = 0.0
	_refresh_piles()
	_cast_button.disabled = false
	_reroll_button.disabled = false
	_refresh_status()
	_refresh_sentence()
	_refresh_timer()


func _on_cloud_picked(cloud: FragmentCloud) -> void:
	if _phase != Phase.BUILD:
		return
	if not _can_append(cloud.card):
		cloud.reject()
		return
	_clouds.erase(cloud)
	cloud.consume()
	_append(cloud.card)


## 放得下，且不会压过封印格（词云要么在封印格之前结束，要么从它之后开始）。
func _can_append(card: CloudCard) -> bool:
	var start := _sentence.length()
	if start + card.runes.length() > Game.max_length:
		return false
	if _seal_index >= 0 and not _seal_placed and start < _seal_index and start + card.runes.length() > _seal_index:
		return false
	return true


func _append(card: CloudCard) -> void:
	_placed.append({"card": card, "start": _sentence.length()})
	_sentence += card.runes
	_apply_place_affix(card.affix())
	_place_seal_if_due()
	_refresh_sentence()
	_auto_cast_if_full()


## 句子正好写到封印格时，封印的 x 自动落下。
func _place_seal_if_due() -> void:
	if _seal_index < 0 or _seal_placed or _sentence.length() != _seal_index:
		return
	_seal_placed = true
	_placed.append({"card": CloudCard.new(CloudCard.JUNK_RUNE), "start": _sentence.length(), "sealed": true})
	_sentence += CloudCard.JUNK_RUNE


## 右键把词云存进记忆栏的空位。
func _on_cloud_stored(cloud: FragmentCloud) -> void:
	if _phase != Phase.BUILD:
		return
	var slot := _memory.find(null)
	if slot == -1:
		cloud.reject()
		return
	_memory[slot] = cloud.card
	_clouds.erase(cloud)
	cloud.consume()
	_refresh_memory()


func _use_memory(slot: int) -> void:
	var card: CloudCard = _memory[slot]
	if _phase != Phase.BUILD or card == null:
		return
	if not _can_append(card):
		return
	_memory[slot] = null
	_refresh_memory()
	_append(card)


## 句子写满就自动释放，稍等片刻让玩家看清最后一块。
func _auto_cast_if_full() -> void:
	if _sentence.length() < Game.max_length:
		return
	_cast_button.disabled = true
	await get_tree().create_timer(0.45).timeout
	_cast()


func _apply_place_affix(affix: AffixData) -> void:
	if affix == null or affix.trigger != AffixData.PLACE:
		return
	match affix.id:
		"sturdy":
			_placed_shield += 1
			_popup("坚固：护盾 +1", PLAYER_ANCHOR + Vector2(0, -40), UiKit.BLUE.lightened(0.5), 32)
		"insight":
			_time_left += 3.0
			_popup("灵光：+3 秒", Vector2(560, 360), UiKit.INK, 32)


func _cast() -> void:
	if _phase != Phase.BUILD:
		return
	_phase = Phase.RESOLVE
	_cast_button.disabled = true
	_cast_hover.visible = false
	_reroll_button.disabled = true
	for cloud in _clouds:
		cloud.frozen = true
		cloud.modulate.a = minf(cloud.modulate.a, 0.4)

	_play_hand_cast()
	await _play_cast_sequence()
	var result := _preview()
	if _matches.is_empty():
		_popup("咒语落空…", PLAYER_ANCHOR, UiKit.CREAM)
	if _intent.has("block"):
		_popup("防御 %d" % _intent.block, ENEMY_ANCHOR + Vector2(0, -40), UiKit.BLUE.lightened(0.5))
	if result.damage > 0:
		_enemy_hp = maxi(0, _enemy_hp - result.dealt)
		_popup("-%d" % result.dealt, ENEMY_ANCHOR, UiKit.RED.lightened(0.25), 64)
		_shake(_stage)
	if result.shield > 0:
		_popup("护盾 +%d" % result.shield, PLAYER_ANCHOR + Vector2(0, -40), UiKit.BLUE.lightened(0.5))
	if result.heal > 0:
		Game.heal(result.heal)
		_popup("生命 +%d" % result.heal, PLAYER_ANCHOR + Vector2(0, 30), UiKit.GREEN.lightened(0.4))
	if result.gold > 0:
		Game.gold += result.gold
		_popup("金币 +%d" % result.gold, PLAYER_ANCHOR + Vector2(0, 100), UiKit.GOLD.lightened(0.4))
	_refresh_status()
	await get_tree().create_timer(1.0).timeout

	if _enemy_hp <= 0:
		_finish(true)
		return

	if _intent.has("attack"):
		Game.hp = maxi(0, Game.hp - result.taken)
		if result.taken > 0:
			_popup("-%d" % result.taken, PLAYER_ANCHOR, UiKit.RED.lightened(0.25), 64)
			_shake(_stage)
		else:
			_popup("完全格挡！", PLAYER_ANCHOR, UiKit.BLUE.lightened(0.5))
	_apply_enemy_skills()
	_refresh_status()
	await get_tree().create_timer(1.0).timeout

	# 灼烧在回合结束时结算，护盾挡不住。
	if _burn > 0 and Game.hp > 0:
		Game.hp = maxi(0, Game.hp - _burn)
		_popup("灼烧 -%d" % _burn, PLAYER_ANCHOR + Vector2(0, 40), Color("ff8a3d"), 44)
		_burn -= 1
		_refresh_status()
		await get_tree().create_timer(0.7).timeout

	if Game.hp <= 0:
		_finish(false)
		return
	_start_turn()


## 待机：前三帧来回轻颤。
func _animate_hand_idle(delta: float) -> void:
	if _hand == null or _hand_casting:
		return
	_hand_clock += delta
	var index: int = HAND_IDLE_FRAMES[int(_hand_clock * HAND_IDLE_FPS) % HAND_IDLE_FRAMES.size()]
	_hand.texture = _hand_frames[index]


## 施法：播放挥杖的后五帧，停在最后一帧，直到下一回合开始。
func _play_hand_cast() -> void:
	_hand_casting = true
	for i in range(3, 8):
		_hand.texture = _hand_frames[i]
		await get_tree().create_timer(1.0 / HAND_CAST_FPS).timeout


## 敌人攻击之外的动作：干扰下一次构句，或给双方叠状态。
func _apply_enemy_skills() -> void:
	var at := ENEMY_ANCHOR + Vector2(0, 60)
	if _intent.has("haste"):
		_haste = _intent.haste
		_popup("催促！", at, UiKit.CREAM, 36)
	if _intent.has("junk"):
		for i in _intent.junk:
			_draw_pile.insert(randi_range(0, _draw_pile.size()), CloudCard.new(CloudCard.JUNK_RUNE))
		_popup("杂念 ×%d 混入抽牌堆" % _intent.junk, at, UiKit.CREAM, 32)
		_refresh_piles()
	if _intent.has("seal"):
		_seal_index = _seal_next
		_popup("封印第 %d 格" % (_seal_next + 1), at, UiKit.CREAM, 34)
	else:
		_seal_index = -1
	if _intent.has("burn"):
		_burn += _intent.burn
		_popup("灼烧 +%d" % _intent.burn, PLAYER_ANCHOR + Vector2(0, -60), Color("ff8a3d"), 36)
	if _intent.has("strength"):
		_strength += _intent.strength
		_popup("力量 +%d" % _intent.strength, at + Vector2(0, -40), UiKit.RED.lightened(0.3), 36)


## 释放动画：符文从左到右依次点亮；某个法术的最后一个符文亮起时，它的括号闪一下并报出效果。
## 没被任何法术用上的符文点亮后变暗。全部亮完再结算。
func _play_cast_sequence() -> void:
	const STEP := 0.17
	for i in _tile_nodes.size():
		var tile := _tile_nodes[i]
		tile.pivot_offset = tile.size / 2.0
		var lit := Color(1.3, 1.25, 1.05) if _matches_covering(i) > 0 else Color(0.62, 0.6, 0.6)
		var tween := tile.create_tween()
		tween.tween_property(tile, "scale", Vector2(1.16, 1.16), 0.08)
		tween.parallel().tween_property(tile, "modulate", Color(1.6, 1.5, 1.15), 0.08)
		tween.tween_property(tile, "scale", Vector2.ONE, 0.12)
		tween.parallel().tween_property(tile, "modulate", lit, 0.12)
		for k in _matches.size():
			var m: Dictionary = _matches[k]
			if m.start + m.length - 1 == i:
				_flash_spell(k, tile.get_global_rect().get_center())
		await get_tree().create_timer(STEP).timeout
	await get_tree().create_timer(0.3).timeout


func _flash_spell(index: int, at: Vector2) -> void:
	var spell: SpellData = _matches[index].spell
	var mult: int = _matches[index].mult
	for node: Control in _bracket_nodes[index]:
		var tween := node.create_tween()
		tween.tween_property(node, "modulate", Color(1.8, 1.6, 1.2), 0.08)
		tween.tween_property(node, "modulate", Color.WHITE, 0.3)
	for card in _cards:
		if card.spell == spell:
			card.pivot_offset = card.size / 2.0
			var pulse := card.create_tween()
			pulse.tween_property(card, "scale", Vector2(1.05, 1.05), 0.08)
			pulse.tween_property(card, "scale", Vector2.ONE, 0.15)
	_popup(spell.bracket_text(mult), at + Vector2(0, -60), (UiKit.RED if spell.is_attack() else UiKit.BLUE).lightened(0.35), 28)


## 当前句子释放后的结果预估：伤害、护盾、治疗、实际打出的伤害和预计受伤。遗物加成也算在内。
func _preview() -> Dictionary:
	var result := SpellMatcher.totals(_matches)
	if Game.has_relic("ember_ring"):
		result.damage += _matches.filter(func(m: Dictionary) -> bool: return (m.spell as SpellData).is_attack()).size()
	if Game.has_relic("crystal"):
		result.damage += 2 * _shared_rune_count()
	if Game.has_relic("echo") and _sentence.length() == Game.max_length and not _matches.is_empty():
		result.damage += 5
	if Game.has_relic("bracer"):
		result.shield += 3
	result.shield += _placed_shield
	_add_cover_affixes(result)
	var enemy_block: int = _intent.get("block", 0)
	result.dealt = maxi(0, result.damage - result.pierce - enemy_block) + result.pierce
	result.taken = 0
	if _intent.has("attack") and result.dealt < _enemy_hp:
		result.taken = maxi(0, _intent.attack + _strength - result.shield)
	return result


## 覆盖类词条：词云至少有一个符文被法术用上才生效。
func _add_cover_affixes(result: Dictionary) -> void:
	for placed in _placed:
		var affix: AffixData = (placed.card as CloudCard).affix()
		if affix == null or affix.trigger != AffixData.COVER:
			continue
		var most := 0
		for i in range(placed.start, placed.start + (placed.card as CloudCard).runes.length()):
			most = maxi(most, _matches_covering(i))
		if most == 0:
			continue
		match affix.id:
			"blazing":
				result.damage += 2
			"gilded":
				result.gold += 1
			"resonant":
				if most >= 2:
					result.damage += 3


func _matches_covering(index: int) -> int:
	return _matches.filter(func(m: Dictionary) -> bool: return SpellMatcher.covers(m, index)).size()


func _shared_rune_count() -> int:
	var count := 0
	for i in _sentence.length():
		if _matches_covering(i) >= 2:
			count += 1
	return count


func _finish(won: bool) -> void:
	_phase = Phase.OVER
	if not won:
		_show_result("败北…", "你倒在了地图第 %d 层。" % Game.floor_number(), "重新开始", func() -> void:
			Game.new_run()
			Game.go_to_map())
	elif Game.in_boss_fight():
		_show_result("通关！", "首领已被你的咒语击败。", "再来一局", func() -> void:
			Game.new_run()
			Game.go_to_map())
	else:
		var reward := Game.duel_reward()
		Game.gold += reward
		var detail := "获得 %d 金币。" % reward
		if Game.in_elite_fight():
			var relic := Game.random_relic()
			if relic != null:
				Game.gain_relic(relic)
				detail = "获得 %d 金币和遗物「%s」。" % [reward, relic.name]
		_show_result("胜利！", detail, "学习咒语", Game.go_to_learn)


# ---------------------------------------------------------------- 刷新显示

func _refresh_status() -> void:
	_player_hp_bar.ratio = float(Game.hp) / Game.max_hp
	_player_hp_label.text = "%d / %d" % [Game.hp, Game.max_hp]
	_enemy_hp_bar.ratio = float(_enemy_hp) / _enemy.hp
	_enemy_hp_label.text = "%d / %d" % [_enemy_hp, _enemy.hp]
	_intent_icon.texture = UiKit.tex(_intent_icon_piece())
	var parts := _intent_parts()
	_intent_label.add_theme_font_size_override("normal_font_size", 26 if parts.size() == 1 else 21)
	_intent_label.text = "下回合：" + " + ".join(parts)
	_intent_label.tooltip_text = "\n".join(_intent_descriptions())
	_refresh_statuses()


func _intent_icon_piece() -> String:
	if _intent.has("attack"):
		return "icon_sword"
	if _intent.has("block"):
		return "icon_shield"
	if _intent.has("haste"):
		return "icon_hourglass"
	if _intent.has("burn"):
		return "icon_fire"
	return "icon_heart"


## 意图的简写，例如“攻击 8 + 封印第 3 格”。
func _intent_parts() -> PackedStringArray:
	var parts: PackedStringArray = []
	if _intent.has("attack"):
		parts.append("攻击 [color=#ff6a55]%d[/color]" % (_intent.attack + _strength))
	if _intent.has("block"):
		parts.append("防御 [color=#7cc7f2]%d[/color]" % _intent.block)
	if _intent.has("haste"):
		parts.append("催促")
	if _intent.has("junk"):
		parts.append("杂念 ×%d" % _intent.junk)
	if _intent.has("seal"):
		parts.append("封印第 %d 格" % (_seal_next + 1))
	if _intent.has("burn"):
		parts.append("灼烧 %d" % _intent.burn)
	if _intent.has("strength"):
		parts.append("力量 +%d" % _intent.strength)
	return parts


func _intent_descriptions() -> PackedStringArray:
	var lines: PackedStringArray = []
	if _intent.has("attack"):
		lines.append("攻击：造成 %d 点伤害（含力量 %d），护盾可以抵挡" % [_intent.attack + _strength, _strength])
	if _intent.has("block"):
		lines.append("防御：本回合你的伤害先被 %d 点防御抵消（穿透伤害无视防御）" % _intent.block)
	if _intent.has("haste"):
		lines.append("催促：你的下一次构句时间 -%d 秒" % _intent.haste)
	if _intent.has("junk"):
		lines.append("杂念：往你的抽牌堆塞入 %d 张 x 词云，本场有效" % _intent.junk)
	if _intent.has("seal"):
		lines.append("封印：你的下一个句子第 %d 格预先填上 x" % (_seal_next + 1))
	if _intent.has("burn"):
		lines.append("灼烧：你获得 %d 层灼烧，每回合结束受等量伤害后减 1 层" % _intent.burn)
	if _intent.has("strength"):
		lines.append("力量：敌人之后每次攻击 +%d" % _intent.strength)
	return lines


## 双方血条下方的状态小标签。
func _refresh_statuses() -> void:
	UiKit.clear_children(_status_layer)
	var player: Array = []
	if _burn > 0:
		player.append(["icon_fire", "灼烧 %d" % _burn, "每回合结束受 %d 点伤害，然后减 1 层" % _burn])
	if _haste > 0.0:
		player.append(["icon_hourglass", "催促 -%d秒" % _haste, "下一次构句时间减少"])
	var enemy: Array = []
	if _strength > 0:
		enemy.append(["icon_sword", "力量 %d" % _strength, "每次攻击 +%d" % _strength])
	_place_status_chips(player, Vector2(40, 136))
	_place_status_chips(enemy, Vector2(1194, 156))


func _place_status_chips(chips: Array, origin: Vector2) -> void:
	var x := origin.x
	for chip: Array in chips:
		var label := UiKit.label(chip[1], 19, UiKit.CREAM)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.tooltip_text = chip[2]
		var style := UiKit.ink_box(Color(UiKit.NIGHT, 0.8), 10)
		style.border_color = UiKit.GOLD
		style.set_border_width_all(2)
		style.content_margin_left = 34
		label.add_theme_stylebox_override("normal", style)
		_status_layer.add_child(label)
		label.size = Vector2(label.get_combined_minimum_size().x, 34)
		label.position = Vector2(x, origin.y)
		_status_layer.add_child(UiKit.place(UiKit.sprite(chip[0]), Rect2(x + 6, origin.y + 5, 24, 24)))
		x += label.size.x + 8.0


func _refresh_timer() -> void:
	var shown := maxf(_time_left, 0.0)
	_timer_bar.ratio = shown / Game.build_time
	_timer_bar.set_fill("bar_hp_fill" if shown <= 5.0 else "bar_timer_fill")


func _refresh_sentence() -> void:
	_matches = SpellMatcher.find_matches(_sentence, Game.spells)
	_rebuild_tiles()
	_rebuild_brackets()

	var result := _preview()
	var stats := "伤害 [color=#ff8a70]%02d[/color]  护盾 [color=#8fd0f5]%02d[/color]" % [result.dealt, result.shield]
	if result.heal > 0:
		stats += "  治疗 [color=#9be39d]%02d[/color]" % result.heal
	if result.gold > 0:
		stats += "  金币 [color=#f2c14e]%02d[/color]" % result.gold
	stats += "  受伤 [color=#ff8a70]%02d[/color]" % result.taken
	_stats_label.text = "[center]%s[/center]" % stats

	for card in _cards:
		card.set_highlight(_matches.any(func(m: Dictionary) -> bool: return m.spell == card.spell))
	var room := Game.max_length - _sentence.length()
	for cloud in _clouds:
		cloud.set_available(cloud.text.length() <= room)
	_refresh_memory()


## 符文牌居中排成一行，牌与牌之间只留窄缝。
func _tile_rect(index: int) -> Rect2:
	var step := minf(137.0, TILE_AREA_WIDTH / Game.max_length)
	var left := TILE_CENTER_X - step * Game.max_length / 2.0
	return Rect2(Vector2(left + step * index + 2.0, TILE_TOP), Vector2(step - 4.0, 80.0))


func _rebuild_tiles() -> void:
	UiKit.clear_children(_tile_layer)
	_tile_nodes.clear()
	for i in Game.max_length:
		var rect := _tile_rect(i)
		if i >= _sentence.length():
			if i == _seal_index and not _seal_placed:
				_tile_layer.add_child(UiKit.place(UiKit.nine("slot_memory", 24), rect))
				var sealed := UiKit.centered(UiKit.label("封", 40, UiKit.CREAM))
				sealed.mouse_filter = Control.MOUSE_FILTER_STOP
				sealed.tooltip_text = "封印：句子写到这里时会自动填上 x，词云不能跨过这一格"
				_tile_layer.add_child(UiKit.place(sealed, rect))
			else:
				_tile_layer.add_child(UiKit.place(UiKit.nine("tile_empty", 24), rect))
			continue
		var rune := _sentence[i]
		var tile := UiKit.nine(_tile_piece(i, rune), 24)
		_tile_layer.add_child(UiKit.place(tile, rect))
		_tile_nodes.append(tile)
		var glyph := UiKit.centered(UiKit.label(rune, 58, UiKit.INK, UiKit.rune_font()))
		tile.add_child(UiKit.place(glyph, Rect2(Vector2(0, -6), rect.size)))
		var affix := _card_at(i).affix()
		if affix != null:
			var mark := UiKit.icon_sprite("affixes", affix.id, affix.icon)
			mark.mouse_filter = Control.MOUSE_FILTER_STOP
			mark.tooltip_text = "%s：%s" % [affix.name, affix.description]
			tile.add_child(UiKit.place(mark, Rect2(rect.size - Vector2(30, 32), Vector2(26, 26))))
	_build_swap_buttons()


## 相邻两朵词云的交界处放一个“换”按钮，花时间互换它们。
func _build_swap_buttons() -> void:
	for k in _placed.size() - 1:
		if _placed[k].get("sealed", false) or _placed[k + 1].get("sealed", false):
			continue
		var boundary := _tile_rect(_placed[k + 1].start).position.x - 2.0
		var swap := UiKit.button("换", 19)
		swap.tooltip_text = "互换两侧的词云（-%d 秒）" % SWAP_TIME_COST
		swap.disabled = _phase != Phase.BUILD
		swap.pressed.connect(_swap_clouds.bind(k))
		_tile_layer.add_child(UiKit.place(swap, Rect2(boundary - 21.0, 370, 42, 31)))


func _swap_clouds(k: int) -> void:
	if _phase != Phase.BUILD or k + 1 >= _placed.size():
		return
	if _placed[k].get("sealed", false) or _placed[k + 1].get("sealed", false):
		return
	var left: Dictionary = _placed[k]
	_placed[k] = _placed[k + 1]
	_placed[k + 1] = left
	_sentence = ""
	for placed in _placed:
		placed.start = _sentence.length()
		_sentence += (placed.card as CloudCard).runes
	_time_left -= SWAP_TIME_COST
	_popup("-%d 秒" % SWAP_TIME_COST, Vector2(_tile_rect(_placed[k].start).end.x, 420), UiKit.INK, 30)
	_refresh_sentence()


func _card_at(index: int) -> CloudCard:
	for placed in _placed:
		if index >= placed.start and index < placed.start + (placed.card as CloudCard).runes.length():
			return placed.card
	return null


func _tile_piece(_index: int, rune: String) -> String:
	return "tile_" + UiKit.rune_piece_color(rune)


func _rebuild_brackets() -> void:
	UiKit.clear_children(_bracket_layer)
	_bracket_nodes.clear()
	var rows := 1
	for m in _matches:
		rows = maxi(rows, m.row + 1)
	var row_height := clampf(BRACKET_AREA_HEIGHT / rows, 20.0, 34.0)
	for m in _matches:
		var spell: SpellData = m.spell
		var first := _tile_rect(m.start)
		var last := _tile_rect(m.start + m.length - 1)
		var color := UiKit.RED if spell.is_attack() else UiKit.BLUE
		var top: float = BRACKET_TOP + m.row * row_height
		var bracket := UiKit.nine("bracket_red" if spell.is_attack() else "bracket_blue", 14, 0)
		bracket.patch_margin_bottom = 10
		_bracket_layer.add_child(UiKit.place(bracket, Rect2(first.position.x + 4, top, last.end.x - first.position.x - 8, 22)))

		var chip := UiKit.label(spell.bracket_text(m.mult), 18 if rows <= 2 else 15, color)
		var chip_style := UiKit.ink_box(UiKit.PARCHMENT, 8)
		chip_style.set_border_width_all(0)
		chip.add_theme_stylebox_override("normal", chip_style)
		_bracket_layer.add_child(chip)
		chip.size = chip.get_combined_minimum_size()
		chip.position = Vector2((first.position.x + last.end.x - chip.size.x) / 2.0, top + 18 - chip.size.y / 2.0)
		_bracket_nodes.append([bracket, chip])


# ---------------------------------------------------------------- 脑海碎片

## 脑海里的词云全部消散，进弃牌堆。
func _discard_clouds() -> void:
	for cloud in _clouds:
		_discard_pile.append(cloud.card)
		cloud.dismiss()
	_clouds.clear()


## 从抽牌堆摸 count 张；抽牌堆空了就把弃牌堆洗回来。
func _draw_cards(count: int) -> Array[CloudCard]:
	var drawn: Array[CloudCard] = []
	for i in count:
		if _draw_pile.is_empty():
			if _discard_pile.is_empty():
				break
			_draw_pile.assign(_discard_pile)
			_discard_pile.clear()
			_draw_pile.shuffle()
		drawn.append(_draw_pile.pop_back())
	return drawn


## 从牌库摸一张，在脑海里找个空位浮现出来。没有空位就放回抽牌堆顶，稍后再试。
func _emerge_cloud() -> void:
	var cards := _draw_cards(1)
	if cards.is_empty():
		return
	var cloud := FragmentCloud.create(cards[0], Game.cloud_life * randf_range(0.9, 1.15))
	var spot := _free_spot(cloud.size)
	if spot.x < 0.0:
		_draw_pile.append(cards[0])
		cloud.free()
		return
	cloud.base_position = spot
	cloud.position = spot
	cloud.velocity = Vector2.from_angle(randf() * TAU) * randf_range(DRIFT_SPEED_MIN, DRIFT_SPEED_MAX)
	cloud.picked.connect(_on_cloud_picked)
	cloud.stored.connect(_on_cloud_stored)
	cloud.expired.connect(_on_cloud_expired)
	_cloud_layer.add_child(cloud)
	_clouds.append(cloud)
	cloud.set_available(cloud.text.length() <= Game.max_length - _sentence.length())
	cloud.appear(0.0)
	_refresh_piles()


func _on_cloud_expired(cloud: FragmentCloud) -> void:
	_clouds.erase(cloud)
	_discard_pile.append(cloud.card)
	_refresh_piles()


## 词云浮在脑海区上半部分，避开左下的记忆栏和右下的按钮。
func _free_spot(cloud_size: Vector2) -> Vector2:
	var area := Rect2(Vector2(24, 14), Vector2(MIND_RECT.size.x - 48.0, 190.0) - Vector2(cloud_size.x, 0))
	for attempt in 24:
		var spot := area.position + Vector2(randf() * area.size.x, randf() * area.size.y)
		var candidate := Rect2(spot, cloud_size).grow(10)
		if candidate.end.y > MIND_RECT.size.y - 100.0 and (candidate.position.x < 450.0 or candidate.end.x > 790.0):
			continue
		if _clouds.any(func(other: FragmentCloud) -> bool: return candidate.intersects(Rect2(other.base_position, other.size))):
			continue
		return spot
	return Vector2(-1, -1)


func _refresh_piles() -> void:
	_pile_label.text = "抽牌堆 %d · 弃牌堆 %d" % [_draw_pile.size(), _discard_pile.size()]
	var remaining := _draw_pile.map(func(card: CloudCard) -> String: return card.describe())
	remaining.sort()
	_pile_label.tooltip_text = "抽牌堆里还有：\n" + "\n".join(PackedStringArray(remaining)) if not remaining.is_empty() else "抽牌堆已空，下次摸牌时洗入弃牌堆"


func _reroll() -> void:
	if _phase != Phase.BUILD:
		return
	if not Game.has_relic("glove"):
		_time_left -= REROLL_TIME_COST
		_popup("-%d 秒" % REROLL_TIME_COST, Vector2(1120, 840), UiKit.CREAM, 34)
	_discard_clouds()
	_emerge_in = 0.0
	_refresh_piles()


# ---------------------------------------------------------------- 搭建界面

func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UiKit.NIGHT
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(backdrop, Rect2(0, 0, 1672, 941)))


func _build_stage() -> void:
	var stage_texture := AtlasTexture.new()
	stage_texture.atlas = load(STAGE_BACKGROUND)
	stage_texture.region = STAGE_SOURCE
	_stage = TextureRect.new()
	_stage.texture = stage_texture
	_stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage.stretch_mode = TextureRect.STRETCH_SCALE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(_stage, STAGE_RECT))

	# 有立绘就站在法阵上，没有就放一块名牌占位。
	var enemy_art: String = ENEMY_ART % _enemy.id
	if ResourceLoader.exists(enemy_art):
		var enemy_sprite := TextureRect.new()
		enemy_sprite.texture = load(enemy_art)
		enemy_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		enemy_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(UiKit.place(enemy_sprite, Rect2(ENEMY_ANCHOR.x - 210, 10, 420, 340)))
	var nameplate := UiKit.centered(UiKit.label(_enemy.name, 34, UiKit.CREAM))
	UiKit.outlined(nameplate, 8)
	var plate_style := UiKit.ink_box(Color(UiKit.NIGHT, 0.7), 16)
	plate_style.border_color = UiKit.GOLD
	plate_style.set_border_width_all(3)
	nameplate.add_theme_stylebox_override("normal", plate_style)
	nameplate.visible = not ResourceLoader.exists(enemy_art)
	_stage.add_child(UiKit.place(nameplate, Rect2(ENEMY_ANCHOR - Vector2(130, 30), Vector2(260, 64))))

	for i in 8:
		_hand_frames.append(load(HAND_FRAMES % i))
	_hand = TextureRect.new()
	_hand.texture = _hand_frames[0]
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(UiKit.place(_hand, HAND_RECT))

	_stage.add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(30, 20, 452, 60)))
	_stage.add_child(UiKit.place(UiKit.sprite("icon_heart_large"), Rect2(48, 27, 50, 46)))
	_player_hp_bar = UiBar.create("bar_hp_frame", "bar_hp_fill", Vector2(274, 46), Vector2(20, 11))
	_player_hp_bar.position = Vector2(104, 27)
	_stage.add_child(_player_hp_bar)
	_player_hp_label = UiKit.label("", 24)
	_stage.add_child(UiKit.place(_player_hp_label, Rect2(388, 26, 90, 48)))
	_player_hp_label.tooltip_text = Game.character.name
	_player_hp_label.mouse_filter = Control.MOUSE_FILTER_STOP

	_stage.add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(1194, 28, 452, 60)))
	_stage.add_child(UiKit.place(UiKit.sprite("icon_heart_large"), Rect2(1212, 35, 50, 46)))
	_enemy_hp_bar = UiBar.create("bar_hp_frame", "bar_hp_fill", Vector2(274, 46), Vector2(20, 11))
	_enemy_hp_bar.position = Vector2(1268, 35)
	_stage.add_child(_enemy_hp_bar)
	_enemy_hp_label = UiKit.label("", 24)
	_stage.add_child(UiKit.place(_enemy_hp_label, Rect2(1552, 34, 90, 48)))
	_enemy_hp_label.tooltip_text = _enemy.name
	_enemy_hp_label.mouse_filter = Control.MOUSE_FILTER_STOP

	_stage.add_child(UiKit.place(UiKit.nine("pill_dark", 30), Rect2(1264, 90, 312, 60)))
	_intent_icon = UiKit.sprite("icon_sword")
	_stage.add_child(UiKit.place(_intent_icon, Rect2(1284, 99, 42, 42)))
	_intent_label = UiKit.rich(26, UiKit.CREAM)
	_intent_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(UiKit.place(_intent_label, Rect2(1334, 104, 236, 40)))
	_status_layer = Control.new()
	_status_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_status_layer)

	_stage.add_child(UiKit.place(UiKit.nine("pill_dark", 30), Rect2(640, 302, 314, 62)))
	_stats_label = UiKit.rich(24, UiKit.CREAM)
	_stage.add_child(UiKit.place(_stats_label, Rect2(648, 318, 298, 36)))

	# 已拥有的遗物排在玩家血条下方，悬停看说明。
	for i in Game.relics.size():
		var relic := RelicData.by_id(Game.relics[i])
		var badge := UiKit.icon_sprite("relics", relic.id, relic.icon)
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		badge.tooltip_text = "%s：%s" % [relic.name, relic.description]
		_stage.add_child(UiKit.place(badge, Rect2(40 + 46 * i, 88, 40, 40)))


## 标题横幅：空白卷轴上写字，便于跟随术语表改名。
func _banner(text: String, rect: Rect2) -> void:
	add_child(UiKit.place(UiKit.sprite("ribbon_small"), rect))
	add_child(UiKit.place(UiKit.centered(UiKit.label(text, 26)), Rect2(rect.position + Vector2(0, -4), rect.size)))


func _build_spell_area() -> void:
	add_child(UiKit.place(UiKit.nine("panel_parchment_large", 46), SPELL_RECT))
	_banner("咒语构筑", Rect2(14, 352, 186, 56))

	_tile_layer = Control.new()
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tile_layer)
	_bracket_layer = Control.new()
	_bracket_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bracket_layer)

	add_child(UiKit.place(UiKit.sprite("icon_hourglass"), Rect2(282, 544, 50, 62)))
	_timer_bar = UiBar.create("bar_timer_frame", "bar_timer_fill", Vector2(570, 32), Vector2(12, 7))
	_timer_bar.position = Vector2(338, 561)
	add_child(_timer_bar)

	# 悬停态的贴图带一圈火花，比按钮本体大，所以单独叠一张。
	var button_rect := Rect2(972, 538, 196, 78)
	_cast_hover = UiKit.sprite("button_cast_hover")
	_cast_hover.stretch_mode = TextureRect.STRETCH_SCALE
	_cast_hover.visible = false
	add_child(UiKit.place(_cast_hover, Rect2(button_rect.position - Vector2(12, 15), Vector2(216, 112))))
	_cast_button = TextureButton.new()
	_cast_button.texture_normal = UiKit.tex("button_cast")
	_cast_button.texture_pressed = UiKit.tex("button_cast_pressed")
	_cast_button.texture_disabled = UiKit.tex("button_cast_pressed")
	_cast_button.ignore_texture_size = true
	_cast_button.stretch_mode = TextureButton.STRETCH_SCALE
	_cast_button.focus_mode = Control.FOCUS_NONE
	_cast_button.tooltip_text = "提前释放；句子写满时会自动释放"
	_cast_button.pressed.connect(_cast)
	_cast_button.mouse_entered.connect(func() -> void: _cast_hover.visible = not _cast_button.disabled)
	_cast_button.mouse_exited.connect(func() -> void: _cast_hover.visible = false)
	add_child(UiKit.place(_cast_button, button_rect))
	var cast_label := UiKit.centered(UiKit.label("释放", 40, UiKit.CREAM))
	add_child(UiKit.place(UiKit.outlined(cast_label, 6), Rect2(button_rect.position + Vector2(0, -3), button_rect.size)))


func _build_mind_area() -> void:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(clip, MIND_RECT))
	var background := TextureRect.new()
	background.texture = load(MIND_BACKGROUND)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(UiKit.place(background, Rect2(Vector2.ZERO, MIND_RECT.size)))

	_cloud_layer = Control.new()
	_cloud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(UiKit.place(_cloud_layer, Rect2(Vector2.ZERO, MIND_RECT.size)))

	add_child(UiKit.place(UiKit.nine("frame_starry", 34), Rect2(MIND_RECT.position - Vector2(6, 6), MIND_RECT.size + Vector2(12, 12))))
	_banner("灵感碎片", Rect2(14, 590, 186, 56))

	# 记忆栏
	var memory_rect := Rect2(24, 828, 428, 96)
	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), memory_rect))
	var memory_title := UiKit.centered(UiKit.label("记忆", 26))
	memory_title.mouse_filter = Control.MOUSE_FILTER_STOP
	memory_title.tooltip_text = "右键词云存入记忆；点击记忆中的词云放进句子。\n存着的词云跨回合保留。"
	add_child(UiKit.place(memory_title, Rect2(34, 846, 66, 60)))
	_memory_layer = Control.new()
	_memory_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_memory_layer)

	_reroll_button = UiKit.button("换一批（免费）" if Game.has_relic("glove") else "换一批（-%d 秒）" % REROLL_TIME_COST, 20)
	_reroll_button.pressed.connect(_reroll)
	add_child(UiKit.place(_reroll_button, Rect2(1054, 876, 186, 44)))

	_pile_label = UiKit.label("", 19, UiKit.CREAM)
	_pile_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var pile_style := UiKit.ink_box(Color(UiKit.NIGHT, 0.75), 10)
	pile_style.border_color = UiKit.GOLD
	pile_style.set_border_width_all(2)
	_pile_label.add_theme_stylebox_override("normal", pile_style)
	add_child(UiKit.place(_pile_label, Rect2(810, 878, 232, 40)))


func _refresh_memory() -> void:
	if _memory_layer == null:
		return
	UiKit.clear_children(_memory_layer)
	var room := Game.max_length - _sentence.length()
	for i in MEMORY_SLOTS:
		var rect := Rect2(108 + 84 * i, 838, 78, 76)
		var card: CloudCard = _memory[i]
		if card == null:
			_memory_layer.add_child(UiKit.place(UiKit.nine("slot_memory", 24), rect))
			continue
		var tile := UiKit.nine("tile_" + UiKit.rune_piece_color(card.runes[0]), 18)
		tile.modulate = Color.WHITE if card.runes.length() <= room else Color(0.55, 0.55, 0.6)
		_memory_layer.add_child(UiKit.place(tile, rect))
		var font_size := 34 if card.runes.length() <= 2 else 26
		_memory_layer.add_child(UiKit.place(UiKit.centered(UiKit.label(card.runes, font_size, UiKit.INK, UiKit.rune_font())), rect))
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.tooltip_text = card.describe()
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		hit.pressed.connect(_use_memory.bind(i))
		_memory_layer.add_child(UiKit.place(hit, rect))


func _build_spell_list() -> void:
	add_child(UiKit.place(UiKit.nine("panel_dark", 26), Rect2(1266, 372, 400, 562)))
	_banner("法术列表", Rect2(1276, 352, 186, 56))
	var count := Game.spells.size()
	var step := minf(152.0, 512.0 / count)
	for i in count:
		var card := SpellCard.create(Game.spells[i], Vector2(372, step - 6.0))
		card.position = Vector2(1280, 416 + step * i)
		add_child(card)
		_cards.append(card)


# ---------------------------------------------------------------- 反馈

func _popup(text: String, at: Vector2, color: Color, font_size: int = 44) -> void:
	var label := UiKit.outlined(UiKit.centered(UiKit.label(text, font_size, color)), 10)
	_popup_layer.add_child(UiKit.place(label, Rect2(at - Vector2(200, 40), Vector2(400, 80))))
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 70.0, 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)


func _shake(node: Control) -> void:
	var tween := node.create_tween()
	for offset: float in [10.0, -8.0, 5.0, 0.0]:
		tween.tween_property(node, "position:x", offset, 0.05)


func _show_result(title: String, detail: String, action: String, on_confirm: Callable) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(UiKit.place(dim, Rect2(0, 0, 1672, 941)))
	dim.add_child(UiKit.place(UiKit.nine("panel_parchment_large", 46), Rect2(486, 290, 700, 360)))
	dim.add_child(UiKit.place(UiKit.sprite("ribbon"), Rect2(586, 240, 500, 110)))
	dim.add_child(UiKit.place(UiKit.centered(UiKit.label(title, 46)), Rect2(586, 240, 500, 96)))
	dim.add_child(UiKit.place(UiKit.centered(UiKit.label(detail, 30)), Rect2(506, 390, 660, 80)))
	var confirm := UiKit.button(action, 32)
	confirm.pressed.connect(on_confirm)
	dim.add_child(UiKit.place(confirm, Rect2(716, 520, 240, 76)))
