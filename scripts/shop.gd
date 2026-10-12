extends Control
## 对决之间的商店：买新法术、调整碎片来源、升级施法能力。
## 每次交易后整页重建，状态都在 Game 里。

const MIND_BACKGROUND := "res://art/backgrounds/mind_area_background.webp"
const FRAGMENT_CHOICES := ["a", "b", "c", "d", "aa", "ab", "ba", "bc", "cd", "dc", "da", "bd", "aab", "bcd"]
const FRAGMENT_ADD_COST := 3
const FRAGMENT_REMOVE_COST := 2
const REROLL_COST := 2

var _spell_offers: Array[SpellData] = []
var _fragment_offers: Array[String] = []


func _ready() -> void:
	_roll_spell_offers()
	_roll_fragment_offers()
	_rebuild()


func _roll_spell_offers() -> void:
	var candidates := SpellData.catalog().filter(func(spell: SpellData) -> bool: return not Game.has_spell(spell.id))
	candidates.shuffle()
	_spell_offers.assign(candidates.slice(0, 3))


func _roll_fragment_offers() -> void:
	var choices := FRAGMENT_CHOICES.duplicate()
	choices.shuffle()
	_fragment_offers.assign(choices.slice(0, 3))


func _rebuild() -> void:
	UiKit.clear_children(self)
	_build_backdrop()
	_build_header()
	_build_equipped()
	_build_shelf()
	_build_fragments_and_upgrades()

	var depart := UiKit.button("下一场对决", 32)
	depart.pressed.connect(Game.go_to_battle)
	add_child(UiKit.place(depart, Rect2(696, 842, 280, 80)))


func _spend(cost: int) -> bool:
	if Game.gold < cost:
		return false
	Game.gold -= cost
	return true


# ---------------------------------------------------------------- 页面

func _build_backdrop() -> void:
	var background := TextureRect.new()
	background.texture = load(MIND_BACKGROUND)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(background, Rect2(0, 0, 1672, 941)))


func _build_header() -> void:
	add_child(UiKit.place(UiKit.sprite("ribbon"), Rect2(586, 6, 500, 100)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("法师商店", 42)), Rect2(586, 6, 500, 88)))

	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(40, 26, 250, 64)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("金币  %d" % Game.gold, 30, UiKit.GOLD.darkened(0.25))), Rect2(40, 26, 250, 64)))

	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(1382, 26, 250, 64)))
	add_child(UiKit.place(UiKit.sprite("icon_heart"), Rect2(1404, 40, 36, 36)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("%d / %d" % [Game.hp, Game.max_hp], 30)), Rect2(1440, 26, 180, 64)))

	var enemy := Game.current_enemy()
	var next_label := UiKit.label("下一场：%s（生命 %d）" % [enemy.name, enemy.hp], 28, UiKit.CREAM)
	add_child(UiKit.place(UiKit.outlined(UiKit.centered(next_label)), Rect2(486, 104, 700, 40)))


func _column(rect: Rect2, title: String) -> void:
	add_child(UiKit.place(UiKit.nine("panel_parchment_large", 46), rect))
	add_child(UiKit.place(UiKit.centered(UiKit.label(title, 32)), Rect2(rect.position + Vector2(0, 18), Vector2(rect.size.x, 44))))
	add_child(UiKit.place(UiKit.sprite("divider"), Rect2(rect.position + Vector2(rect.size.x / 2.0 - 110, 58), Vector2(220, 26))))


func _build_equipped() -> void:
	_column(Rect2(24, 150, 530, 680), "已装备法术  %d / %d" % [Game.spells.size(), Game.spell_slots])
	var step := minf(128.0, 580.0 / Game.spell_slots)
	for i in Game.spells.size():
		var spell := Game.spells[i]
		var card := SpellCard.create(spell, Vector2(482, step - 6.0))
		card.position = Vector2(48, 238 + step * i)
		add_child(card)
		var forget := UiKit.button("遗忘", 20)
		forget.disabled = Game.spells.size() <= 1
		forget.pressed.connect(func() -> void:
			Game.spells.erase(spell)
			_rebuild())
		add_child(UiKit.place(forget, Rect2(card.position + Vector2(376, 16), Vector2(88, 40))))


func _build_shelf() -> void:
	_column(Rect2(570, 150, 532, 680), "法术货架")
	var full := Game.spells.size() >= Game.spell_slots
	for i in _spell_offers.size():
		var spell := _spell_offers[i]
		var card := SpellCard.create(spell, Vector2(484, 150))
		card.position = Vector2(594, 238 + 162 * i)
		add_child(card)
		var buy := UiKit.button("购买  %d" % spell.cost, 20)
		buy.disabled = full or Game.gold < spell.cost
		buy.pressed.connect(func() -> void:
			if _spend(spell.cost):
				Game.spells.append(spell)
				_spell_offers.erase(spell)
				_rebuild())
		add_child(UiKit.place(buy, Rect2(card.position + Vector2(346, 20), Vector2(118, 42))))

	var hint := "法术位已满：先遗忘一个法术，或升级法术位。" if full else "挑选能与已有咒式相连的法术。"
	add_child(UiKit.place(UiKit.centered(UiKit.label(hint, 22)), Rect2(580, 726, 512, 36)))
	var reroll := UiKit.button("刷新货架  %d" % REROLL_COST, 20)
	reroll.disabled = Game.gold < REROLL_COST
	reroll.pressed.connect(func() -> void:
		if _spend(REROLL_COST):
			_roll_spell_offers()
			_rebuild())
	add_child(UiKit.place(reroll, Rect2(756, 766, 160, 44)))


func _build_fragments_and_upgrades() -> void:
	_column(Rect2(1118, 150, 530, 680), "碎片来源")
	add_child(UiKit.place(UiKit.centered(UiKit.label("脑海中会浮现这些碎片。点击移除（%d 金币）" % FRAGMENT_REMOVE_COST, 20)), Rect2(1128, 236, 510, 30)))

	var can_remove := Game.fragment_pool.size() > Game.FRAGMENT_POOL_MIN and Game.gold >= FRAGMENT_REMOVE_COST
	for i in Game.fragment_pool.size():
		var chip := _rune_button(Game.fragment_pool[i])
		chip.disabled = not can_remove
		chip.pressed.connect(func() -> void:
			if _spend(FRAGMENT_REMOVE_COST):
				Game.fragment_pool.remove_at(i)
				_rebuild())
		add_child(UiKit.place(chip, Rect2(1144 + 69 * (i % 7), 272 + 48 * (i / 7), 64, 44)))

	var can_add := Game.fragment_pool.size() < Game.FRAGMENT_POOL_MAX and Game.gold >= FRAGMENT_ADD_COST
	add_child(UiKit.place(UiKit.label("加入（%d 金币）：" % FRAGMENT_ADD_COST, 22), Rect2(1146, 420, 180, 44)))
	for i in _fragment_offers.size():
		var fragment := _fragment_offers[i]
		var add := _rune_button("+ " + fragment)
		add.disabled = not can_add
		add.pressed.connect(func() -> void:
			if _spend(FRAGMENT_ADD_COST):
				Game.fragment_pool.append(fragment)
				_fragment_offers.erase(fragment)
				_rebuild())
		add_child(UiKit.place(add, Rect2(1322 + 104 * i, 420, 98, 44)))

	add_child(UiKit.place(UiKit.centered(UiKit.label("施法能力", 30)), Rect2(1118, 474, 530, 40)))
	add_child(UiKit.place(UiKit.sprite("divider"), Rect2(1273, 510, 220, 22)))
	# 每项：标题、不可用时的说明、价格、是否可用、效果。
	var upgrades := [
		["咒文延展：句长 %d → %d" % [Game.max_length, Game.max_length + 1], "咒文延展：已达上限", 8,
			Game.max_length < Game.MAX_LENGTH_CAP, func() -> void: Game.max_length += 1],
		["沉思：构句时间 %d 秒 → %d 秒" % [Game.build_time, Game.build_time + 2], "沉思：已达上限", 6,
			Game.build_time < Game.BUILD_TIME_CAP, func() -> void: Game.build_time += 2.0],
		["凝神：碎片多停留 1 秒", "凝神：已达上限", 5,
			Game.fragment_life < Game.FRAGMENT_LIFE_CAP, func() -> void: Game.fragment_life += 1.0],
		["扩充法术位：%d → %d" % [Game.spell_slots, Game.spell_slots + 1], "扩充法术位：已达上限", 10,
			Game.spell_slots < Game.SPELL_SLOT_CAP, func() -> void: Game.spell_slots += 1],
		["强身：生命上限 +6", "", 6, true, func() -> void:
			Game.max_hp += 6
			Game.heal(6)],
		["疗伤：恢复 10 点生命", "疗伤：生命已满", 4, Game.hp < Game.max_hp, func() -> void: Game.heal(10)],
	]
	for i in upgrades.size():
		var available: bool = upgrades[i][3]
		var title: String = upgrades[i][0] if available else upgrades[i][1]
		var cost: int = upgrades[i][2]
		var apply: Callable = upgrades[i][4]
		var y := 536.0 + 47.0 * i
		add_child(UiKit.place(UiKit.label(title, 23), Rect2(1146, y, 380, 44)))
		var buy := UiKit.button(str(cost), 22)
		buy.disabled = not available or Game.gold < cost
		buy.pressed.connect(func() -> void:
			if _spend(cost):
				apply.call()
				_rebuild())
		add_child(UiKit.place(buy, Rect2(1536, y + 2, 86, 40)))


func _rune_button(text: String) -> Button:
	var node := UiKit.button(text, 26)
	node.add_theme_font_override("font", UiKit.rune_font())
	return node
