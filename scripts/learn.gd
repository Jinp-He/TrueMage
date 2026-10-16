extends IntermissionPage
## 学习咒语：每打赢一场（首领除外）都会来到这里，免费二选一：
##   学会一个新咒语（法术位满了就替换左边选中的咒语），或者给一个已有咒语追加一个符文。
## 也可以什么都不选，直接返回地图。

const OFFER_COUNT := 3

var _offers: Array[SpellData] = []
var _selected: SpellData
var _chosen := false


func _ready() -> void:
	var candidates := SpellData.catalog().filter(func(spell: SpellData) -> bool: return not Game.has_spell(spell.id))
	candidates.shuffle()
	_offers.assign(candidates.slice(0, OFFER_COUNT))
	_selected = Game.spells[0]
	super()


func _page_title() -> String:
	return "学习咒语"


func _subtitle() -> String:
	return "已经学到东西了，可以返回地图。" if _chosen else "学会一个新咒语，或强化一个已有的咒语，二选一；都不要也可以直接返回。"


func _build_page() -> void:
	var hint := "点击咒语：强化它，或者被新咒语替换" if _full() else "点击咒语选择要强化的那个"
	_build_owned_spells(Rect2(24, 150, 530, 680), _selected, _select, hint)
	_build_upgrade()
	_build_offers()


func _full() -> bool:
	return Game.spells.size() >= Game.spell_slots


func _select(spell: SpellData) -> void:
	_selected = spell
	_rebuild()


func _mark_chosen() -> void:
	_chosen = true


func _build_upgrade() -> void:
	var column := Rect2(570, 150, 532, 680)
	_column(column, "强化咒语")
	var card := SpellCard.create(_selected, Vector2(484, 140))
	card.position = column.position + Vector2(24, 92)
	add_child(card)
	_build_rune_adder(_selected, column, 400, 0, _mark_chosen, not _chosen)


func _build_offers() -> void:
	_column(Rect2(1118, 150, 530, 680), "学习新咒语")
	for i in _offers.size():
		var spell := _offers[i]
		var card := SpellCard.create(spell, Vector2(482, 150))
		card.position = Vector2(1142, 238 + 162 * i)
		add_child(card)
		var learn := UiKit.button("替换「%s」" % _selected.name if _full() else "学习", 20)
		learn.tooltip_text = "忘掉「%s」，学会「%s」" % [_selected.name, spell.name] if _full() else ""
		learn.disabled = _chosen
		learn.pressed.connect(func() -> void:
			if _full():
				Game.spells[Game.spells.find(_selected)] = spell
			else:
				Game.spells.append(spell)
			_offers.erase(spell)
			_selected = spell
			_chosen = true
			_rebuild())
		add_child(UiKit.place(learn, Rect2(card.position + Vector2(300, 20), Vector2(164, 42))))
	if _full():
		add_child(UiKit.place(UiKit.centered(UiKit.label("法术位已满：学习会替换左边选中的咒语。", 20)), Rect2(1128, 730, 510, 30)))
