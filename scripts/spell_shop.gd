extends IntermissionPage
## 咒语商店：购买新咒语、遗忘咒语，以及花金币强化已有咒语的咒式。

const ADD_RUNE_COST := 4
const REMOVE_RUNE_COST := 3
const REROLL_COST := 2

var _offers: Array[SpellData] = []
var _selected: SpellData


func _ready() -> void:
	_roll_offers()
	if not Game.spells.is_empty():
		_selected = Game.spells[0]
	super()


func _page_title() -> String:
	return "咒语商店"


func _build_page() -> void:
	_build_owned()
	_build_upgrade()
	_build_shelf()


func _roll_offers() -> void:
	var candidates := SpellData.catalog().filter(func(spell: SpellData) -> bool: return not Game.has_spell(spell.id))
	candidates.shuffle()
	_offers.assign(candidates.slice(0, 3))


# ---------------------------------------------------------------- 我的咒语

func _build_owned() -> void:
	_column(Rect2(24, 150, 530, 680), "我的咒语  %d / %d" % [Game.spells.size(), Game.spell_slots])
	add_child(UiKit.place(UiKit.centered(UiKit.label("点击咒语进行强化", 20)), Rect2(24, 222, 530, 26)))
	var step := minf(128.0, 560.0 / Game.spell_slots)
	for i in Game.spells.size():
		var spell := Game.spells[i]
		var card := SpellCard.create(spell, Vector2(482, step - 6.0))
		card.position = Vector2(48, 256 + step * i)
		card.set_highlight(spell == _selected)
		add_child(card)
		_hit_area(Rect2(card.position, card.size), func() -> void:
			_selected = spell
			_rebuild())
		var forget := UiKit.button("遗忘", 20)
		forget.disabled = Game.spells.size() <= 1
		forget.pressed.connect(func() -> void:
			Game.spells.erase(spell)
			if _selected == spell:
				_selected = Game.spells[0]
			_rebuild())
		add_child(UiKit.place(forget, Rect2(card.position + Vector2(376, 16), Vector2(88, 40))))


# ---------------------------------------------------------------- 强化

func _build_upgrade() -> void:
	var column := Rect2(570, 150, 532, 680)
	_column(column, "咒语强化")
	if _selected == null:
		return
	var card := SpellCard.create(_selected, Vector2(484, 140))
	card.position = Vector2(594, 232)
	add_child(card)

	# 移除：每个符文下面一个按钮。
	add_child(UiKit.place(UiKit.label("移除符文（%d 金币）：更好拼出，效果降低" % REMOVE_RUNE_COST, 21), Rect2(600, 384, 480, 30)))
	var count := _selected.pattern.length()
	var step := minf(60.0, 470.0 / count)
	var x0 := column.get_center().x - step * count / 2.0
	var can_remove := count > SpellData.MIN_PATTERN_LENGTH and Game.gold >= REMOVE_RUNE_COST
	for i in count:
		var rune := _selected.pattern[i]
		var tile_rect := Rect2(x0 + step * i + 3, 420, step - 6, 52)
		add_child(UiKit.place(UiKit.nine("tile_orange" if SpellData.is_warm(rune) else "tile_blue", 18), tile_rect))
		add_child(UiKit.place(UiKit.centered(UiKit.label(rune, 36, UiKit.rune_color(rune).darkened(0.25), UiKit.rune_font())), tile_rect))
		var preview := _selected.copy()
		preview.remove_rune(i)
		var remove := UiKit.button("－", 20)
		remove.disabled = not can_remove
		remove.tooltip_text = "%s → %s  %s" % [_selected.pattern, preview.pattern, preview.change_text(_selected)]
		remove.pressed.connect(func() -> void:
			if _spend(REMOVE_RUNE_COST):
				_selected.remove_rune(i)
				_rebuild())
		add_child(UiKit.place(remove, Rect2(tile_rect.position + Vector2(0, 58), Vector2(tile_rect.size.x, 34))))
	if count <= SpellData.MIN_PATTERN_LENGTH:
		add_child(UiKit.place(UiKit.centered(UiKit.label("咒式至少保留 %d 个符文" % SpellData.MIN_PATTERN_LENGTH, 19)), Rect2(570, 514, 532, 26)))

	# 追加：接在咒式末尾。选哪个符文效果都一样，所以效果只写一次。
	var added := _selected.copy()
	added.add_rune("a")
	add_child(UiKit.place(UiKit.label("追加符文（%d 金币）：%s" % [ADD_RUNE_COST, added.change_text(_selected)], 21), Rect2(600, 546, 480, 30)))
	var can_add := count < Game.max_length and Game.gold >= ADD_RUNE_COST
	for i in SpellData.RUNES.size():
		var rune: String = SpellData.RUNES[i]
		var add := UiKit.button("+ " + rune, 28)
		add.add_theme_font_override("font", UiKit.rune_font())
		add.add_theme_color_override("font_color", UiKit.rune_color(rune).darkened(0.2))
		add.add_theme_color_override("font_hover_color", UiKit.rune_color(rune).darkened(0.2))
		add.disabled = not can_add
		add.pressed.connect(func() -> void:
			if _spend(ADD_RUNE_COST):
				_selected.add_rune(rune)
				_rebuild())
		add_child(UiKit.place(add, Rect2(604 + 94 * i, 588, 84, 56)))
	if count >= Game.max_length:
		add_child(UiKit.place(UiKit.centered(UiKit.label("咒式已和句子长度上限一样长", 19)), Rect2(570, 652, 532, 26)))

	add_child(UiKit.place(UiKit.centered(UiKit.label("追加哪个符文效果都一样，区别在于更容易和谁连上。", 20)), Rect2(570, 726, 532, 30)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("咒式越长越难拼，但触发一次的收益更高。", 20)), Rect2(570, 758, 532, 30)))


# ---------------------------------------------------------------- 货架

func _build_shelf() -> void:
	_column(Rect2(1118, 150, 530, 680), "咒语货架")
	var full := Game.spells.size() >= Game.spell_slots
	for i in _offers.size():
		var spell := _offers[i]
		var card := SpellCard.create(spell, Vector2(482, 150))
		card.position = Vector2(1142, 238 + 162 * i)
		add_child(card)
		var buy := UiKit.button("购买  %d" % spell.cost, 20)
		buy.disabled = full or Game.gold < spell.cost
		buy.pressed.connect(func() -> void:
			if _spend(spell.cost):
				Game.spells.append(spell)
				_offers.erase(spell)
				_selected = spell
				_rebuild())
		add_child(UiKit.place(buy, Rect2(card.position + Vector2(346, 20), Vector2(118, 42))))

	var hint := "法术位已满：先遗忘一个咒语。" if full else "挑选能与已有咒式相连的咒语。"
	add_child(UiKit.place(UiKit.centered(UiKit.label(hint, 22)), Rect2(1128, 726, 510, 36)))
	var reroll := UiKit.button("刷新货架  %d" % REROLL_COST, 20)
	reroll.disabled = Game.gold < REROLL_COST
	reroll.pressed.connect(func() -> void:
		if _spend(REROLL_COST):
			_roll_offers()
			_rebuild())
	add_child(UiKit.place(reroll, Rect2(1303, 766, 160, 44)))
