extends IntermissionPage
## 休息处：免费休息回血一次，以及向遗物商人购买遗物。

const REST_HEAL_RATIO := 0.4
const REROLL_COST := 2

var _offers: Array[RelicData] = []
var _rested := false


func _ready() -> void:
	_roll_offers()
	super()


func _page_title() -> String:
	return "休息处"


func _build_page() -> void:
	_build_campfire()
	_build_relic_shelf()


func _roll_offers() -> void:
	var candidates := RelicData.catalog().filter(func(relic: RelicData) -> bool: return relic.available())
	candidates.shuffle()
	_offers.assign(candidates.slice(0, 3))


func _rest_amount() -> int:
	return mini(roundi(Game.max_hp * REST_HEAL_RATIO), Game.max_hp - Game.hp)


func _build_campfire() -> void:
	_column(Rect2(24, 150, 530, 680), "篝火")
	add_child(UiKit.place(UiKit.sprite("icon_heart_large"), Rect2(209, 240, 160, 130)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("在篝火旁睡一觉，恢复 %d%% 生命上限。" % roundi(REST_HEAL_RATIO * 100), 23)), Rect2(34, 384, 510, 36)))

	var rest := UiKit.button("已休息" if _rested else "休息  （+%d 生命）" % _rest_amount(), 26)
	rest.disabled = _rested or _rest_amount() <= 0
	rest.pressed.connect(func() -> void:
		Game.heal(_rest_amount())
		_rested = true
		_rebuild())
	add_child(UiKit.place(rest, Rect2(149, 430, 280, 60)))

	add_child(UiKit.place(UiKit.sprite("divider"), Rect2(179, 518, 220, 26)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("已拥有的遗物", 26)), Rect2(24, 548, 530, 36)))
	if Game.relics.is_empty():
		add_child(UiKit.place(UiKit.centered(UiKit.label("还没有遗物", 21)), Rect2(24, 596, 530, 30)))
	for i in Game.relics.size():
		var relic := RelicData.by_id(Game.relics[i])
		var row := Vector2(56 + 240 * (i % 2), 596 + 44 * (i / 2))
		var icon := UiKit.icon_sprite("relics", relic.id, relic.icon)
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.tooltip_text = relic.description
		add_child(UiKit.place(icon, Rect2(row, Vector2(38, 38))))
		add_child(UiKit.place(UiKit.label(relic.name, 21), Rect2(row + Vector2(46, 0), Vector2(190, 38))))


func _build_relic_shelf() -> void:
	_column(Rect2(570, 150, 1078, 680), "遗物商人")
	if _offers.is_empty():
		add_child(UiKit.place(UiKit.centered(UiKit.label("商人的货都卖完了。", 24)), Rect2(570, 300, 1078, 40)))
	for i in _offers.size():
		var relic := _offers[i]
		var top := Vector2(600, 236 + 160 * i)
		add_child(UiKit.place(UiKit.nine("card_spell", 36), Rect2(top, Vector2(1018, 148))))
		add_child(UiKit.place(UiKit.icon_sprite("relics", relic.id, relic.icon), Rect2(top + Vector2(28, 24), Vector2(100, 100))))
		add_child(UiKit.place(UiKit.label(relic.name, 32), Rect2(top + Vector2(150, 22), Vector2(600, 46))))
		add_child(UiKit.place(UiKit.label(relic.description, 25), Rect2(top + Vector2(150, 76), Vector2(680, 40))))
		var buy := UiKit.button("购买  %d" % relic.cost, 22)
		buy.disabled = Game.gold < relic.cost
		buy.pressed.connect(func() -> void:
			if _spend(relic.cost):
				Game.relics.append(relic.id)
				relic.on_acquire()
				_offers.erase(relic)
				_rebuild())
		add_child(UiKit.place(buy, Rect2(top + Vector2(860, 50), Vector2(130, 48))))

	var reroll := UiKit.button("刷新货架  %d" % REROLL_COST, 20)
	reroll.disabled = Game.gold < REROLL_COST
	reroll.pressed.connect(func() -> void:
		if _spend(REROLL_COST):
			_roll_offers()
			_rebuild())
	add_child(UiKit.place(reroll, Rect2(1029, 744, 160, 44)))
