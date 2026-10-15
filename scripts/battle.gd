extends Control
## 一场对决：敌人预告 → 限时构句 → 释放结算 → 敌人行动，循环到一方倒下。
## 画面按 1672x941 的效果图坐标布局，分为敌人区、咒语区、脑海区、法术列表四块。

enum Phase { BUILD, RESOLVE, OVER }

const MOCKUP := "res://art/concept/battle_screen_mockup.webp"
const MIND_BACKGROUND := "res://art/backgrounds/mind_area_background.webp"

## 舞台暂时取自效果图顶部（角色是画在背景里的），等独立的舞台图和角色图到位后替换。
const STAGE_REGION := Rect2(0, 0, 1672, 283)
const PLAYER_ANCHOR := Vector2(420, 190)
const ENEMY_ANCHOR := Vector2(880, 120)

const TILE_ORIGIN := Vector2(84, 386)
const TILE_AREA_WIDTH := 880.0
const BRACKET_TOP := 478.0
const BRACKET_AREA_HEIGHT := 100.0
const MIND_RECT := Rect2(16, 640, 1218, 292)
## 换一批选项要付出的构句时间。
const REROLL_TIME_COST := 3.0

var _phase := Phase.BUILD
var _turn := 0
var _enemy: Dictionary
var _enemy_hp: int
var _intent: Array
var _sentence := ""
var _matches: Array[Dictionary] = []
var _time_left := 0.0

var _stage: TextureRect
var _player_hp_bar: UiBar
var _player_hp_label: Label
var _enemy_hp_bar: UiBar
var _enemy_hp_label: Label
var _round_label: Label
var _intent_icon: TextureRect
var _intent_label: RichTextLabel
var _timer_label: Label
var _timer_bar: UiBar
var _length_label: Label
var _tile_layer: Control
var _bracket_layer: Control
var _stats_label: RichTextLabel
var _cast_button: TextureButton
var _cast_hover: TextureRect
var _cloud_layer: Control
var _reroll_button: Button
var _cards: Array[SpellCard] = []
var _popup_layer: Control


func _ready() -> void:
	_enemy = Game.current_enemy()
	_enemy_hp = _enemy.hp
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
	_sentence += cloud.text
	cloud.consume()
	_offer_wave()
	_refresh_sentence()


func _cast() -> void:
	if _phase != Phase.BUILD:
		return
	_phase = Phase.RESOLVE
	_cast_button.disabled = true
	_cast_hover.visible = false
	_reroll_button.disabled = true
	for cloud: FragmentCloud in _cloud_layer.get_children():
		cloud.frozen = true
		cloud.modulate.a = minf(cloud.modulate.a, 0.4)

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
	var enemy_block: int = _intent[1] if _intent[0] == "block" else 0
	result.dealt = maxi(0, result.damage - enemy_block)
	result.taken = 0
	if _intent[0] == "attack" and result.dealt < _enemy_hp:
		result.taken = maxi(0, _intent[1] - result.shield)
	return result


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
	_round_label.text = "回合 %d" % _turn
	if _intent[0] == "attack":
		_intent_icon.texture = UiKit.tex("icon_sword")
		_intent_label.text = "下回合：攻击 [color=#ff6a55]%d[/color]" % _intent[1]
	else:
		_intent_icon.texture = UiKit.tex("icon_shield")
		_intent_label.text = "下回合：防御 [color=#7cc7f2]%d[/color]" % _intent[1]


func _refresh_timer() -> void:
	var shown := maxf(_time_left, 0.0)
	_timer_label.text = "%04.1f" % shown
	_timer_label.add_theme_color_override("font_color", UiKit.RED if shown <= 3.0 else UiKit.INK)
	_timer_bar.ratio = shown / Game.build_time


func _refresh_sentence() -> void:
	_matches = SpellMatcher.find_matches(_sentence, Game.spells)
	_length_label.text = "长度： %d / %d" % [_sentence.length(), Game.max_length]
	_rebuild_tiles()
	_rebuild_brackets()

	var result := _preview()
	var stats := "伤害 [color=#%s]%d[/color]      护盾 [color=#%s]%d[/color]" % [
		UiKit.RED.to_html(false), result.dealt, UiKit.BLUE.to_html(false), result.shield]
	if result.heal > 0:
		stats += "      治疗 [color=#%s]%d[/color]" % [UiKit.GREEN.to_html(false), result.heal]
	stats += "      预计受伤 [color=#%s]%d[/color]" % [UiKit.RED.to_html(false), result.taken]
	_stats_label.text = "[center]%s[/center]" % stats

	for card in _cards:
		card.set_highlight(_matches.any(func(m: Dictionary) -> bool: return m.spell == card.spell))
	var room := Game.max_length - _sentence.length()
	for cloud: FragmentCloud in _cloud_layer.get_children():
		cloud.set_available(cloud.text.length() <= room)


func _tile_rect(index: int) -> Rect2:
	var step := minf(126.0, TILE_AREA_WIDTH / Game.max_length)
	var tile_size := Vector2(step - 14.0, 85.0)
	return Rect2(TILE_ORIGIN + Vector2(step * index, 0), tile_size)


func _rebuild_tiles() -> void:
	UiKit.clear_children(_tile_layer)
	for i in Game.max_length:
		var rect := _tile_rect(i)
		var number := UiKit.centered(UiKit.label(str(i + 1), 18))
		_tile_layer.add_child(UiKit.place(number, Rect2(rect.position + Vector2(0, -26), Vector2(rect.size.x, 24))))
		if i >= _sentence.length():
			_tile_layer.add_child(UiKit.place(UiKit.nine("tile_empty", 24), rect))
			continue
		var rune := _sentence[i]
		_tile_layer.add_child(UiKit.place(UiKit.nine(_tile_piece(i, rune), 24), rect))
		var glyph := UiKit.centered(UiKit.label(rune, 62, UiKit.INK, UiKit.rune_font()))
		_tile_layer.add_child(UiKit.place(glyph, Rect2(rect.position + Vector2(0, -6), rect.size)))


## 同时被攻击法术和防御法术覆盖的符文用双色牌，让共享一眼可见。
func _tile_piece(index: int, rune: String) -> String:
	var in_attack := false
	var in_support := false
	for m in _matches:
		if index >= m.start and index < m.start + m.length:
			if (m.spell as SpellData).is_attack():
				in_attack = true
			else:
				in_support = true
	if in_attack and in_support:
		return "tile_shared"
	return "tile_orange" if rune in ["a", "b"] else "tile_blue"


func _rebuild_brackets() -> void:
	UiKit.clear_children(_bracket_layer)
	var rows := 1
	for m in _matches:
		rows = maxi(rows, m.row + 1)
	var row_height := clampf(BRACKET_AREA_HEIGHT / rows, 24.0, 46.0)
	for m in _matches:
		var spell: SpellData = m.spell
		var first := _tile_rect(m.start)
		var last := _tile_rect(m.start + m.length - 1)
		var color := UiKit.RED if spell.is_attack() else UiKit.BLUE
		var top: float = BRACKET_TOP + m.row * row_height
		var bracket := UiKit.nine("bracket_red" if spell.is_attack() else "bracket_blue", 14, 0)
		bracket.patch_margin_bottom = 10
		_bracket_layer.add_child(UiKit.place(bracket, Rect2(first.position.x + 4, top, last.end.x - first.position.x - 8, 22)))

		var chip := UiKit.label(spell.bracket_text(), 20 if rows <= 3 else 17, color)
		var chip_style := UiKit.ink_box(UiKit.PARCHMENT, 8)
		chip_style.set_border_width_all(0)
		chip.add_theme_stylebox_override("normal", chip_style)
		_bracket_layer.add_child(chip)
		chip.size = chip.get_combined_minimum_size()
		chip.position = Vector2((first.position.x + last.end.x - chip.size.x) / 2.0, top + 18 - chip.size.y / 2.0)


# ---------------------------------------------------------------- 脑海碎片

## 让上一批剩下的选项消散，再浮现新的一批 3～5 个选项（尽量不重复）。
func _offer_wave() -> void:
	for old: FragmentCloud in _cloud_layer.get_children():
		old.dismiss()
	var count := randi_range(Game.min_options, Game.OPTIONS_MAX)
	# 按碎片来源里的份数加权抽取，同一批里不重复。
	var remaining: Array = Game.fragment_pool.duplicate()
	var options: Array = []
	while options.size() < count and not remaining.is_empty():
		var fragment: String = remaining.pick_random()
		options.append(fragment)
		while fragment in remaining:
			remaining.erase(fragment)
	while options.size() < count:
		options.append(Game.fragment_pool.pick_random())

	var clouds: Array[FragmentCloud] = []
	var total_width := 0.0
	for option: String in options:
		var cloud := FragmentCloud.create(option)
		clouds.append(cloud)
		total_width += cloud.size.x
	var gap := clampf((MIND_RECT.size.x - 120.0 - total_width) / maxf(count - 1, 1), 8.0, 48.0)
	var x := (MIND_RECT.size.x - total_width - gap * (count - 1)) / 2.0
	var room := Game.max_length - _sentence.length()
	for i in clouds.size():
		var cloud := clouds[i]
		var y := (MIND_RECT.size.y - cloud.size.y) / 2.0 + (-22.0 if i % 2 == 0 else 22.0)
		cloud.base_position = Vector2(x, y)
		cloud.position = cloud.base_position
		cloud.picked.connect(_on_cloud_picked)
		_cloud_layer.add_child(cloud)
		cloud.set_available(cloud.text.length() <= room)
		cloud.appear(0.12 + 0.06 * i)
		x += cloud.size.x + gap


func _reroll() -> void:
	if _phase != Phase.BUILD:
		return
	if not Game.has_relic("glove"):
		_time_left -= REROLL_TIME_COST
		_popup("-%d 秒" % REROLL_TIME_COST, Vector2(1100, 840), UiKit.CREAM, 34)
	_offer_wave()


# ---------------------------------------------------------------- 搭建界面

func _build_backdrop() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UiKit.NIGHT
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(backdrop, Rect2(0, 0, 1672, 941)))


func _build_stage() -> void:
	var stage_texture := AtlasTexture.new()
	stage_texture.atlas = load(MOCKUP)
	stage_texture.region = STAGE_REGION
	_stage = TextureRect.new()
	_stage.texture = stage_texture
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(_stage, STAGE_REGION))

	# 这几块面板正好盖住效果图里画死的血条、回合和意图。
	_stage.add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(46, 10, 366, 62)))
	_stage.add_child(UiKit.place(UiKit.label("生命", 28), Rect2(70, 16, 70, 50)))
	_stage.add_child(UiKit.place(UiKit.sprite("icon_heart"), Rect2(134, 24, 34, 34)))
	_player_hp_bar = UiBar.create("bar_small_frame", "bar_small_fill_red", Vector2(132, 24), Vector2(8, 6))
	_player_hp_bar.position = Vector2(172, 29)
	_stage.add_child(_player_hp_bar)
	_player_hp_label = UiKit.centered(UiKit.label("", 25))
	_stage.add_child(UiKit.place(_player_hp_label, Rect2(304, 16, 100, 50)))

	_stage.add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(1500, 8, 152, 68)))
	_round_label = UiKit.centered(UiKit.label("", 32))
	_stage.add_child(UiKit.place(_round_label, Rect2(1500, 8, 152, 68)))

	var name_label := UiKit.outlined(UiKit.centered(UiKit.label(_enemy.name, 28, UiKit.CREAM)))
	_stage.add_child(UiKit.place(name_label, Rect2(1136, 8, 334, 36)))
	_stage.add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(1136, 44, 334, 60)))
	_stage.add_child(UiKit.place(UiKit.sprite("icon_heart"), Rect2(1156, 56, 36, 36)))
	_enemy_hp_bar = UiBar.create("bar_small_frame", "bar_small_fill_red", Vector2(166, 24), Vector2(8, 6))
	_enemy_hp_bar.position = Vector2(1198, 62)
	_stage.add_child(_enemy_hp_bar)
	_enemy_hp_label = UiKit.centered(UiKit.label("", 25))
	_stage.add_child(UiKit.place(_enemy_hp_label, Rect2(1366, 49, 98, 50)))

	_stage.add_child(UiKit.place(UiKit.nine("pill_dark", 30), Rect2(1144, 104, 318, 62)))
	_intent_icon = UiKit.sprite("icon_sword")
	_stage.add_child(UiKit.place(_intent_icon, Rect2(1170, 114, 42, 42)))
	_intent_label = UiKit.rich(27, UiKit.CREAM)
	_stage.add_child(UiKit.place(_intent_label, Rect2(1222, 117, 230, 40)))

	# 已拥有的遗物排在玩家血条下方，悬停看说明。
	for i in Game.relics.size():
		var relic := RelicData.by_id(Game.relics[i])
		var badge := UiKit.sprite(relic.icon)
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		badge.tooltip_text = "%s：%s" % [relic.name, relic.description]
		_stage.add_child(UiKit.place(badge, Rect2(60 + 46 * i, 78, 40, 40)))


func _build_spell_area() -> void:
	add_child(UiKit.place(UiKit.nine("panel_parchment_large", 46), Rect2(8, 286, 1234, 346)))
	add_child(UiKit.place(UiKit.sprite("banner_spell"), Rect2(22, 282, 244, 78)))

	add_child(UiKit.place(UiKit.sprite("icon_hourglass"), Rect2(342, 298, 46, 58)))
	add_child(UiKit.place(UiKit.label("构句倒计时", 30), Rect2(402, 302, 160, 50)))
	_timer_label = UiKit.label("", 54, UiKit.INK, UiKit.rune_font())
	add_child(UiKit.place(_timer_label, Rect2(572, 296, 130, 60)))
	add_child(UiKit.place(UiKit.label("秒", 28), Rect2(698, 304, 40, 50)))
	_timer_bar = UiBar.create("bar_timer_frame", "bar_timer_fill", Vector2(290, 36), Vector2(14, 8))
	_timer_bar.position = Vector2(736, 310)
	add_child(_timer_bar)
	_length_label = UiKit.label("", 28)
	add_child(UiKit.place(_length_label, Rect2(1048, 302, 190, 50)))

	_tile_layer = Control.new()
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tile_layer)
	_bracket_layer = Control.new()
	_bracket_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bracket_layer)

	_stats_label = UiKit.rich(29)
	add_child(UiKit.place(_stats_label, Rect2(216, 582, 800, 40)))

	# 释放按钮放在符文牌右侧，牌下方整行留给括号。
	# 悬停态的贴图带一圈火花，比按钮本体大，所以单独叠一张。
	var button_rect := Rect2(978, 380, 236, 92)
	_cast_hover = UiKit.sprite("button_cast_hover")
	_cast_hover.stretch_mode = TextureRect.STRETCH_SCALE
	_cast_hover.visible = false
	add_child(UiKit.place(_cast_hover, Rect2(button_rect.position - Vector2(15, 18), Vector2(260, 134))))
	_cast_button = TextureButton.new()
	_cast_button.texture_normal = UiKit.tex("button_cast")
	_cast_button.texture_pressed = UiKit.tex("button_cast_pressed")
	_cast_button.texture_disabled = UiKit.tex("button_cast_pressed")
	_cast_button.ignore_texture_size = true
	_cast_button.stretch_mode = TextureButton.STRETCH_SCALE
	_cast_button.focus_mode = Control.FOCUS_NONE
	_cast_button.pressed.connect(_cast)
	_cast_button.mouse_entered.connect(func() -> void: _cast_hover.visible = not _cast_button.disabled)
	_cast_button.mouse_exited.connect(func() -> void: _cast_hover.visible = false)
	add_child(UiKit.place(_cast_button, button_rect))
	var cast_label := UiKit.centered(UiKit.label("释放", 46, UiKit.CREAM))
	add_child(UiKit.place(UiKit.outlined(cast_label, 6), Rect2(button_rect.position + Vector2(0, -3), button_rect.size)))
	add_child(UiKit.place(UiKit.sprite("icon_glove"), Rect2(1150, 440, 84, 76)))


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

	var frame := UiKit.nine("frame_starry", 34)
	add_child(UiKit.place(frame, Rect2(8, 634, 1234, 304)))
	add_child(UiKit.place(UiKit.sprite("banner_mind"), Rect2(22, 630, 244, 66)))

	_reroll_button = UiKit.button("换一批（免费）" if Game.has_relic("glove") else "换一批（-%d 秒）" % REROLL_TIME_COST, 20)
	_reroll_button.pressed.connect(_reroll)
	add_child(UiKit.place(_reroll_button, Rect2(1036, 876, 186, 44)))


func _build_spell_list() -> void:
	add_child(UiKit.place(UiKit.nine("panel_dark", 26), Rect2(1250, 286, 414, 652)))
	add_child(UiKit.place(UiKit.sprite("banner_spell_list"), Rect2(1322, 290, 270, 78)))
	var count := Game.spells.size()
	var step := minf(170.0, 556.0 / count)
	for i in count:
		var card := SpellCard.create(Game.spells[i], Vector2(394, step - 6.0), "已配置")
		card.position = Vector2(1260, 374 + step * i)
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
