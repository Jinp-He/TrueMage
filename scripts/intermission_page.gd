class_name IntermissionPage
extends Control
## 地图上的非战斗页面（咒语商店、休息处、抄写室、战后的学习咒语）共用的外观：脑海星空背景、标题横幅、金币与生命、羊皮纸分栏。
## 每次交易后子类调用 _rebuild() 整页重建，状态都在 Game 里。

const MIND_BACKGROUND := "res://art/backgrounds/mind_area.webp"


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	UiKit.clear_children(self)
	_build_backdrop()
	_build_header(_page_title())
	_build_page()
	var depart := UiKit.button("返回地图", 32)
	depart.pressed.connect(Game.go_to_map)
	add_child(UiKit.place(depart, Rect2(696, 842, 280, 80)))


## 子类实现：页面标题与正文。
func _page_title() -> String:
	return ""


## 标题下方的一行说明，默认显示所在层数。
func _subtitle() -> String:
	return "地图第 %d 层" % Game.floor_number()


func _build_page() -> void:
	pass


func _spend(cost: int) -> bool:
	if Game.gold < cost:
		return false
	Game.gold -= cost
	return true


func _build_backdrop() -> void:
	var background := TextureRect.new()
	background.texture = load(MIND_BACKGROUND)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(background, Rect2(0, 0, 1672, 941)))


func _build_header(title: String) -> void:
	add_child(UiKit.place(UiKit.sprite("ribbon"), Rect2(586, 6, 500, 100)))
	add_child(UiKit.place(UiKit.centered(UiKit.label(title, 42)), Rect2(586, 6, 500, 88)))

	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(40, 26, 250, 64)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("金币  %d" % Game.gold, 30, UiKit.GOLD.darkened(0.25))), Rect2(40, 26, 250, 64)))

	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(1382, 26, 250, 64)))
	add_child(UiKit.place(UiKit.sprite("icon_heart"), Rect2(1404, 40, 36, 36)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("%d / %d" % [Game.hp, Game.max_hp], 30)), Rect2(1440, 26, 180, 64)))

	var subtitle := UiKit.label(_subtitle(), 26, UiKit.CREAM)
	add_child(UiKit.place(UiKit.outlined(UiKit.centered(subtitle), 6), Rect2(286, 104, 1100, 40)))


func _column(rect: Rect2, title: String) -> void:
	add_child(UiKit.place(UiKit.nine("panel_parchment_large", 46), rect))
	add_child(UiKit.place(UiKit.centered(UiKit.label(title, 32)), Rect2(rect.position + Vector2(0, 18), Vector2(rect.size.x, 44))))
	add_child(UiKit.place(UiKit.sprite("divider"), Rect2(rect.position + Vector2(rect.size.x / 2.0 - 110, 58), Vector2(220, 26))))


## 一个透明的整块按钮，叠在卡片上让整张卡可点。
func _hit_area(rect: Rect2, on_press: Callable) -> Button:
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.pressed.connect(on_press)
	add_child(UiKit.place(hit, rect))
	return hit


## 左栏“我的咒语”：点一张卡选中它。返回卡片，子类可以在卡上再加按钮。
func _build_owned_spells(rect: Rect2, selected: SpellData, on_select: Callable, hint: String = "点击咒语进行强化") -> Array[SpellCard]:
	_column(rect, "我的咒语  %d / %d" % [Game.spells.size(), Game.spell_slots])
	add_child(UiKit.place(UiKit.centered(UiKit.label(hint, 20)), Rect2(rect.position + Vector2(0, 72), Vector2(rect.size.x, 26))))
	var cards: Array[SpellCard] = []
	var step := minf(128.0, 560.0 / Game.spell_slots)
	for i in Game.spells.size():
		var spell := Game.spells[i]
		var card := SpellCard.create(spell, Vector2(rect.size.x - 48, step - 6.0))
		card.position = rect.position + Vector2(24, 106 + step * i)
		card.set_highlight(spell == selected)
		add_child(card)
		_hit_area(Rect2(card.position, card.size), on_select.bind(spell))
		cards.append(card)
	return cards


## 在咒式末尾追加一个符文来强化咒语。cost 为 0 表示免费；enabled 为 false 时按钮全部禁用（例如这一页已经做过选择）。
## 从 top 往下占三行：说明、符文按钮、不能追加时的提示。
func _build_rune_adder(spell: SpellData, column: Rect2, top: float, cost: int, on_added: Callable, enabled: bool = true) -> void:
	# 选哪个符文效果都一样，所以效果只写一次。
	var added := spell.copy()
	added.add_rune(SpellData.RUNES.filter(func(rune: String) -> bool: return rune not in spell.pattern).front() if spell.rule == SpellData.ABSENT else "a")
	var price := "免费" if cost == 0 else "%d 金币" % cost
	add_child(UiKit.place(UiKit.label("追加符文（%s）：%s" % [price, added.change_text(spell)], 21), Rect2(column.position.x + 30, top, column.size.x - 52, 30)))
	var can_add := enabled and spell.can_add_rune(Game.max_length) and Game.gold >= cost
	var add_rune := func(rune: String) -> void:
		if _spend(cost):
			spell.add_rune(rune)
			on_added.call()
			_rebuild()
	# 多样型、首尾型追加什么符文都一样，只给一个强化按钮。
	if not spell.rune_choice_matters():
		var boost := UiKit.button("强化", 28)
		boost.disabled = not can_add
		boost.pressed.connect(add_rune.bind("a"))
		add_child(UiKit.place(boost, Rect2(column.get_center().x - 90, top + 42, 180, 56)))
	for i in (SpellData.RUNES.size() if spell.rune_choice_matters() else 0):
		var rune: String = SpellData.RUNES[i]
		var add := UiKit.button("+ " + rune, 28)
		add.add_theme_font_override("font", UiKit.rune_font())
		add.add_theme_color_override("font_color", UiKit.rune_color(rune).darkened(0.2))
		add.add_theme_color_override("font_hover_color", UiKit.rune_color(rune).darkened(0.2))
		add.disabled = not can_add or (spell.rule == SpellData.ABSENT and rune in spell.pattern)
		add.pressed.connect(add_rune.bind(rune))
		add_child(UiKit.place(add, Rect2(column.position.x + 34 + 94 * i, top + 42, 84, 56)))
	if not spell.can_add_rune(Game.max_length):
		add_child(UiKit.place(UiKit.centered(UiKit.label("咒式已经不能再追加", 19)), Rect2(column.position.x, top + 106, column.size.x, 26)))


## 一朵静态的词云：云朵、符文，带词条时下方挂徽记。
func _cloud_tile(card: CloudCard, rect: Rect2, font_size: int) -> void:
	var cloud := UiKit.sprite(FragmentCloud.piece_for(card.runes))
	cloud.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(UiKit.place(cloud, rect))
	add_child(UiKit.place(UiKit.centered(UiKit.label(card.runes, font_size, UiKit.INK, UiKit.rune_font())), Rect2(rect.position + Vector2(0, -3), rect.size)))
	var affix := card.affix()
	if affix != null:
		add_child(FragmentCloud.affix_badge(affix, Vector2(rect.get_center().x, rect.end.y - 2), 15))
