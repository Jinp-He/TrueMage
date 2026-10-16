extends IntermissionPage
## 咒语商店，分两页：
##   法术页：购买、遗忘法术，增减符文改写咒式。
##   词云页：购买、移除牌库里的词云，给词云加词条。

const ADD_RUNE_COST := 4
const REMOVE_RUNE_COST := 3
const REROLL_COST := 2
const AFFIX_COST := 5
const REMOVE_CLOUD_COST := 3
const CLOUD_AFFIX_CHANCE := 0.35

var _tab := "spells"
var _offers: Array[SpellData] = []
var _selected: SpellData
var _cloud_offers: Array[CloudCard] = []
var _affix_offers: Array[AffixData] = []
var _selected_cloud: CloudCard


func _ready() -> void:
	_roll_offers()
	_roll_cloud_offers()
	_affix_offers.assign(AffixData.catalog())
	_affix_offers.shuffle()
	_affix_offers.resize(3)
	if not Game.spells.is_empty():
		_selected = Game.spells[0]
	if not Game.deck.is_empty():
		_selected_cloud = Game.deck[0]
	super()


func _page_title() -> String:
	return "咒语商店"


func _build_page() -> void:
	_build_tabs()
	if _tab == "spells":
		_build_owned()
		_build_upgrade()
		_build_shelf()
	else:
		_build_deck()
		_build_cloud_upgrade()
		_build_cloud_shelf()


func _build_tabs() -> void:
	for i in 2:
		var key: String = ["spells", "clouds"][i]
		var tab := UiKit.button(["法术", "词云"][i], 24)
		tab.toggle_mode = true
		tab.button_pressed = _tab == key
		tab.pressed.connect(func() -> void:
			_tab = key
			_rebuild())
		add_child(UiKit.place(tab, Rect2(40 + 128 * i, 98, 118, 46)))


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


# ---------------------------------------------------------------- 词云页

## 货架上的词云：多数截取自已装备法术的咒式，好让新词云能用上；部分带词条。
func _roll_cloud_offers() -> void:
	_cloud_offers.clear()
	for i in 3:
		var runes := ""
		if randf() < 0.7 and not Game.spells.is_empty():
			var pattern: String = Game.spells.pick_random().pattern
			var length := randi_range(1, mini(3, pattern.length()))
			runes = pattern.substr(randi_range(0, pattern.length() - length), length)
		else:
			for j in randi_range(1, 2):
				runes += SpellData.RUNES.pick_random()
		var affix_id := ""
		if randf() < CLOUD_AFFIX_CHANCE:
			affix_id = AffixData.catalog().pick_random().id
		_cloud_offers.append(CloudCard.new(runes, affix_id))


func _cloud_price(card: CloudCard) -> int:
	return 2 + card.runes.length() + (3 if card.affix_id != "" else 0)


## 一朵静态的词云：云朵、符文，带词条时下方挂徽记。
func _cloud_tile(card: CloudCard, rect: Rect2, font_size: int) -> void:
	var cloud := UiKit.sprite(FragmentCloud.piece_for(card.runes))
	cloud.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UiKit.place(cloud, rect))
	add_child(UiKit.place(UiKit.centered(UiKit.label(card.runes, font_size, UiKit.INK, UiKit.rune_font())), Rect2(rect.position + Vector2(0, -3), rect.size)))
	var affix := card.affix()
	if affix != null:
		add_child(FragmentCloud.affix_badge(affix, Vector2(rect.get_center().x, rect.end.y - 2), 15))


func _build_deck() -> void:
	_column(Rect2(24, 150, 530, 680), "我的牌库  %d 张" % Game.deck.size())
	add_child(UiKit.place(UiKit.centered(UiKit.label("点击词云进行强化或移除", 20)), Rect2(24, 222, 530, 26)))
	for i in Game.deck.size():
		var card := Game.deck[i]
		var rect := Rect2(52 + 120 * (i % 4), 258 + 78 * (i / 4), 112, 64)
		if card == _selected_cloud:
			var glow := UiKit.nine("card_spell_highlight", 30)
			add_child(UiKit.place(glow, rect.grow(6)))
		_cloud_tile(card, rect, 30)
		var hit := _hit_area(rect, func() -> void:
			_selected_cloud = card
			_rebuild())
		hit.tooltip_text = card.describe()


func _build_cloud_upgrade() -> void:
	var column := Rect2(570, 150, 532, 680)
	_column(column, "词云强化")
	if _selected_cloud == null:
		return
	_cloud_tile(_selected_cloud, Rect2(column.get_center().x - 110, 236, 220, 120), 56)
	var affix := _selected_cloud.affix()
	var current := "当前词条：无" if affix == null else "当前词条：%s——%s" % [affix.name, affix.description]
	add_child(UiKit.place(UiKit.centered(UiKit.label(current, 21)), Rect2(570, 372, 532, 30)))

	add_child(UiKit.place(UiKit.label("加上词条（%d 金币，会替换原有词条）：" % AFFIX_COST, 21), Rect2(600, 414, 480, 30)))
	for i in _affix_offers.size():
		var offer := _affix_offers[i]
		var button := UiKit.button("%s：%s" % [offer.name, offer.description], 20)
		button.disabled = Game.gold < AFFIX_COST or _selected_cloud.affix_id == offer.id
		button.pressed.connect(func() -> void:
			if _spend(AFFIX_COST):
				_selected_cloud.affix_id = offer.id
				_rebuild())
		add_child(UiKit.place(button, Rect2(600, 452 + 56 * i, 472, 48)))
	add_child(UiKit.place(UiKit.label("“被法术用上时”：这朵词云的符文要进入某个法术", 18), Rect2(600, 620, 480, 26)))

	var remove := UiKit.button("移除这朵词云  %d" % REMOVE_CLOUD_COST, 22)
	remove.disabled = Game.deck.size() <= Game.DECK_MIN or Game.gold < REMOVE_CLOUD_COST
	remove.pressed.connect(func() -> void:
		if _spend(REMOVE_CLOUD_COST):
			Game.deck.erase(_selected_cloud)
			_selected_cloud = Game.deck[0]
			_rebuild())
	add_child(UiKit.place(remove, Rect2(716, 668, 240, 50)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("牌库至少保留 %d 张" % Game.DECK_MIN, 19)), Rect2(570, 726, 532, 28)))


func _build_cloud_shelf() -> void:
	_column(Rect2(1118, 150, 530, 680), "词云货架")
	for i in _cloud_offers.size():
		var card := _cloud_offers[i]
		var top := 240.0 + 150.0 * i
		_cloud_tile(card, Rect2(1160, top, 200, 108), 44)
		var price := _cloud_price(card)
		var buy := UiKit.button("购买  %d" % price, 20)
		buy.disabled = Game.gold < price
		buy.pressed.connect(func() -> void:
			if _spend(price):
				Game.deck.append(card)
				_cloud_offers.erase(card)
				_selected_cloud = card
				_rebuild())
		add_child(UiKit.place(buy, Rect2(1430, top + 30, 140, 46)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("买来的词云加入牌库，下一场对决起会浮现。", 20)), Rect2(1128, 700, 510, 30)))
	var reroll := UiKit.button("刷新货架  %d" % REROLL_COST, 20)
	reroll.disabled = Game.gold < REROLL_COST
	reroll.pressed.connect(func() -> void:
		if _spend(REROLL_COST):
			_roll_cloud_offers()
			_rebuild())
	add_child(UiKit.place(reroll, Rect2(1303, 744, 160, 44)))
