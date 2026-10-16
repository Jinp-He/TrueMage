extends Control
## 一场对决：敌人预告 → 限时构句 → 释放结算 → 敌人行动，循环到一方倒下。
## 画面按 art/concept/battle_layout_v2.jpg 的版式布局（1672x941），分为敌人区、咒语构筑、灵感碎片、法术列表四块。

enum Phase { BUILD, RESOLVE, OVER }

const LAYOUT_ART := "res://art/concept/battle_layout_v2.jpg"
const MIND_BACKGROUND := "res://art/backgrounds/mind_area_background.webp"

## 舞台暂时取自版式图顶部（角色和场景都画在图里），等独立的舞台图和角色图到位后替换。
const STAGE_SOURCE := Rect2(8, 37, 1630, 355)
const STAGE_RECT := Rect2(0, 0, 1672, 364)
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

var _phase := Phase.BUILD
var _turn := 0
var _enemy: Dictionary
var _enemy_hp: int
var _intent: Array
var _sentence := ""
## 句子里每朵词云的来源与位置：{card, start}。
var _placed: Array[Dictionary] = []
## 放置类词条累积的护盾，本回合有效。
var _placed_shield := 0
var _draw_pile: Array[CloudCard] = []
var _discard_pile: Array[CloudCard] = []
## 当前这一批还在脑海区里的词云。
var _wave: Array[FragmentCloud] = []
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
	_start_turn()


func _process(delta: float) -> void:
	if _phase != Phase.BUILD:
		return
	_time_left -= delta
	_refresh_timer()
	if _time_left <= 0.0:
		_cast()


# ---------------------------------------------------------------- 回合流程

func _start_turn() -> void:
	_turn += 1
	var intents: Array = _enemy.intents
	_intent = intents[(_turn - 1) % intents.size()]
	# 上回合句子里的词云和没选的词云都进弃牌堆。
	for placed in _placed:
		_discard_pile.append(placed.card)
	_discard_wave()
	_placed.clear()
	_placed_shield = 0
	_sentence = ""
	_time_left = Game.build_time
	_phase = Phase.BUILD
	UiKit.clear_children(_cloud_layer)
	_offer_wave()
	_cast_button.disabled = false
	_reroll_button.disabled = false
	_refresh_status()
	_refresh_sentence()
	_refresh_timer()


func _on_cloud_picked(cloud: FragmentCloud) -> void:
	if _phase != Phase.BUILD:
		return
	if _sentence.length() + cloud.text.length() > Game.max_length:
		cloud.reject()
		return
	_placed.append({"card": cloud.card, "start": _sentence.length()})
	_sentence += cloud.text
	_wave.erase(cloud)
	cloud.consume()
	_apply_place_affix(cloud.card.affix())
	_offer_wave()
	_refresh_sentence()
	_auto_cast_if_full()


## 右键把词云存进记忆栏的空位；这也算这一批的选择，随后浮现下一批。
func _on_cloud_stored(cloud: FragmentCloud) -> void:
	if _phase != Phase.BUILD:
		return
	var slot := _memory.find(null)
	if slot == -1:
		cloud.reject()
		return
	_memory[slot] = cloud.card
	_wave.erase(cloud)
	cloud.consume()
	_offer_wave()
	_refresh_memory()


func _use_memory(slot: int) -> void:
	var card: CloudCard = _memory[slot]
	if _phase != Phase.BUILD or card == null:
		return
	if _sentence.length() + card.runes.length() > Game.max_length:
		return
	_memory[slot] = null
	_placed.append({"card": card, "start": _sentence.length()})
	_sentence += card.runes
	_apply_place_affix(card.affix())
	_refresh_memory()
	_refresh_sentence()
	_auto_cast_if_full()


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
	for cloud in _wave:
		cloud.frozen = true
		cloud.modulate.a = minf(cloud.modulate.a, 0.4)

	await _play_cast_sequence()
	var result := _preview()
	if _matches.is_empty():
		_popup("咒语落空…", PLAYER_ANCHOR, UiKit.CREAM)
	if _intent[0] == "block":
		_popup("防御 %d" % _intent[1], ENEMY_ANCHOR + Vector2(0, -40), UiKit.BLUE.lightened(0.5))
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

	if _intent[0] == "attack":
		Game.hp = maxi(0, Game.hp - result.taken)
		if result.taken > 0:
			_popup("-%d" % result.taken, PLAYER_ANCHOR, UiKit.RED.lightened(0.25), 64)
			_shake(_stage)
		else:
			_popup("完全格挡！", PLAYER_ANCHOR, UiKit.BLUE.lightened(0.5))
		_refresh_status()
	await get_tree().create_timer(1.0).timeout

	if Game.hp <= 0:
		_finish(false)
		return
	_start_turn()


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
	_popup(spell.bracket_text(), at + Vector2(0, -60), (UiKit.RED if spell.is_attack() else UiKit.BLUE).lightened(0.35), 28)


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
	var enemy_block: int = _intent[1] if _intent[0] == "block" else 0
	result.dealt = maxi(0, result.damage - result.pierce - enemy_block) + result.pierce
	result.taken = 0
	if _intent[0] == "attack" and result.dealt < _enemy_hp:
		result.taken = maxi(0, _intent[1] - result.shield)
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
	return _matches.filter(func(m: Dictionary) -> bool: return index >= m.start and index < m.start + m.length).size()


func _shared_rune_count() -> int:
	var count := 0
	for i in _sentence.length():
		var covering := _matches.filter(func(m: Dictionary) -> bool: return i >= m.start and i < m.start + m.length)
		if covering.size() >= 2:
			count += 1
	return count


func _finish(won: bool) -> void:
	_phase = Phase.OVER
	if not won:
		_show_result("败北…", "你倒在了第 %d 场对决。" % (Game.duel_index + 1), "重新开始", func() -> void:
			Game.new_run()
			Game.go_to_battle())
	elif Game.is_last_duel():
		_show_result("通关！", "所有对手都已被你的咒语击败。", "再来一局", func() -> void:
			Game.new_run()
			Game.go_to_battle())
	else:
		var reward := Game.duel_reward()
		Game.gold += reward
		Game.duel_index += 1
		var stop := "前往咒语商店" if Game.next_stop_is_spell_shop() else "前往休息处"
		_show_result("胜利！", "获得 %d 金币。" % reward, stop, Game.go_to_intermission)


# ---------------------------------------------------------------- 刷新显示

func _refresh_status() -> void:
	_player_hp_bar.ratio = float(Game.hp) / Game.max_hp
	_player_hp_label.text = "%d / %d" % [Game.hp, Game.max_hp]
	_enemy_hp_bar.ratio = float(_enemy_hp) / _enemy.hp
	_enemy_hp_label.text = "%d / %d" % [_enemy_hp, _enemy.hp]
	if _intent[0] == "attack":
		_intent_icon.texture = UiKit.tex("icon_sword")
		_intent_label.text = "下回合：攻击 [color=#ff6a55]%d[/color]" % _intent[1]
	else:
		_intent_icon.texture = UiKit.tex("icon_shield")
		_intent_label.text = "下回合：防御 [color=#7cc7f2]%d[/color]" % _intent[1]


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
	for cloud in _wave:
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
			var mark := UiKit.sprite(affix.icon)
			mark.mouse_filter = Control.MOUSE_FILTER_STOP
			mark.tooltip_text = "%s：%s" % [affix.name, affix.description]
			tile.add_child(UiKit.place(mark, Rect2(rect.size - Vector2(30, 32), Vector2(26, 26))))


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

		var chip := UiKit.label(spell.bracket_text(), 18 if rows <= 2 else 15, color)
		var chip_style := UiKit.ink_box(UiKit.PARCHMENT, 8)
		chip_style.set_border_width_all(0)
		chip.add_theme_stylebox_override("normal", chip_style)
		_bracket_layer.add_child(chip)
		chip.size = chip.get_combined_minimum_size()
		chip.position = Vector2((first.position.x + last.end.x - chip.size.x) / 2.0, top + 18 - chip.size.y / 2.0)
		_bracket_nodes.append([bracket, chip])


# ---------------------------------------------------------------- 脑海碎片

## 没被选中的词云进弃牌堆并消散。
func _discard_wave() -> void:
	for cloud in _wave:
		_discard_pile.append(cloud.card)
		cloud.dismiss()
	_wave.clear()


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


## 上一批剩下的词云消散，再从牌库发出新的一批 3～5 朵。
func _offer_wave() -> void:
	_discard_wave()
	var cards := _draw_cards(randi_range(Game.min_options, Game.OPTIONS_MAX))
	var total_width := 0.0
	for card in cards:
		var cloud := FragmentCloud.create(card)
		_wave.append(cloud)
		total_width += cloud.size.x
	var count := _wave.size()
	var gap := clampf((MIND_RECT.size.x - 120.0 - total_width) / maxf(count - 1, 1), 8.0, 48.0)
	var x := (MIND_RECT.size.x - total_width - gap * (count - 1)) / 2.0
	var room := Game.max_length - _sentence.length()
	for i in count:
		var cloud := _wave[i]
		# 下方左侧是记忆栏，词云浮在偏上的一条带里。
		var y := 112.0 - cloud.size.y / 2.0 + (-20.0 if i % 2 == 0 else 20.0)
		cloud.base_position = Vector2(x, y)
		cloud.position = cloud.base_position
		cloud.picked.connect(_on_cloud_picked)
		cloud.stored.connect(_on_cloud_stored)
		_cloud_layer.add_child(cloud)
		cloud.set_available(cloud.text.length() <= room)
		cloud.appear(0.12 + 0.06 * i)
		x += cloud.size.x + gap
	_refresh_piles()


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
	_offer_wave()


# ---------------------------------------------------------------- 搭建界面

func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UiKit.NIGHT
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(backdrop, Rect2(0, 0, 1672, 941)))


func _build_stage() -> void:
	var stage_texture := AtlasTexture.new()
	stage_texture.atlas = load(LAYOUT_ART)
	stage_texture.region = STAGE_SOURCE
	_stage = TextureRect.new()
	_stage.texture = stage_texture
	_stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage.stretch_mode = TextureRect.STRETCH_SCALE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(_stage, STAGE_RECT))

	# 这几块面板正好盖住版式图里画死的血条、意图和预估。
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
	_stage.add_child(UiKit.place(_intent_label, Rect2(1334, 104, 236, 40)))

	_stage.add_child(UiKit.place(UiKit.nine("pill_dark", 30), Rect2(640, 302, 314, 62)))
	_stats_label = UiKit.rich(24, UiKit.CREAM)
	_stage.add_child(UiKit.place(_stats_label, Rect2(648, 318, 298, 36)))

	# 已拥有的遗物排在玩家血条下方，悬停看说明。
	for i in Game.relics.size():
		var relic := RelicData.by_id(Game.relics[i])
		var badge := UiKit.sprite(relic.icon)
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
