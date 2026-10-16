extends IntermissionPage
## 休息处：二选一，在篝火旁休息回血，或者静心强化一个咒语（免费追加一个符文）。

const REST_HEAL_RATIO := 0.4

var _selected: SpellData
## 这一站已经做过选择。
var _chosen := false


func _ready() -> void:
	_selected = Game.spells[0]
	super()


func _page_title() -> String:
	return "休息处"


func _subtitle() -> String:
	return "已经歇过脚了，可以返回地图。" if _chosen else "在篝火旁休息，或静心强化一个咒语，二选一。"


func _build_page() -> void:
	_build_campfire()
	_build_owned_spells(Rect2(570, 150, 532, 680), _selected, _select, "或者：选一个咒语静心强化")
	_build_meditation()


func _select(spell: SpellData) -> void:
	_selected = spell
	_rebuild()


func _rest_amount() -> int:
	return mini(roundi(Game.max_hp * REST_HEAL_RATIO), Game.max_hp - Game.hp)


func _build_campfire() -> void:
	_column(Rect2(24, 150, 530, 680), "篝火")
	add_child(UiKit.place(UiKit.sprite("icon_heart_large"), Rect2(209, 260, 160, 130)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("在篝火旁睡一觉，恢复 %d%% 生命上限。" % roundi(REST_HEAL_RATIO * 100), 23)), Rect2(34, 414, 510, 36)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("当前生命  %d / %d" % [Game.hp, Game.max_hp], 23)), Rect2(34, 452, 510, 36)))
	var rest := UiKit.button("休息  （+%d 生命）" % _rest_amount(), 28)
	rest.disabled = _chosen or _rest_amount() <= 0
	rest.pressed.connect(func() -> void:
		Game.heal(_rest_amount())
		_mark_chosen()
		_rebuild())
	add_child(UiKit.place(rest, Rect2(139, 510, 300, 72)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("休息和强化只能二选一", 21)), Rect2(34, 620, 510, 30)))


func _build_meditation() -> void:
	var column := Rect2(1118, 150, 530, 680)
	_column(column, "静心强化")
	var card := SpellCard.create(_selected, Vector2(482, 140))
	card.position = column.position + Vector2(24, 92)
	add_child(card)
	_build_rune_adder(_selected, column, 400, 0, _mark_chosen, not _chosen)


func _mark_chosen() -> void:
	_chosen = true
