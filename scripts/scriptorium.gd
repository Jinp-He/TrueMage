extends IntermissionPage
## 抄写室：整理词云牌库。每次来可以免费做一件事：
##   删除一朵词云、改写其中一个符文、把一朵拆成两朵，或者把两朵合成一朵。
## 合并时词条保留前一朵的（前一朵没有就用后一朵的），拆分时词条留在前半朵。

const MERGE_MAX := 4

var _selected: CloudCard
var _merge_target: CloudCard
var _rewrite_index := 0
var _chosen := false


func _ready() -> void:
	_selected = Game.deck[0]
	super()


func _page_title() -> String:
	return "抄写室"


func _subtitle() -> String:
	return "已经抄写完了，可以返回地图。" if _chosen else "删除、改写、拆分、合并，每次只能做一件。"


func _build_page() -> void:
	_build_deck_grid()
	_build_edit()
	_build_merge()


func _finish() -> void:
	_chosen = true
	_merge_target = null
	_rewrite_index = 0
	_rebuild()


func _build_deck_grid() -> void:
	_column(Rect2(24, 150, 530, 680), "我的牌库  %d 张" % Game.deck.size())
	add_child(UiKit.place(UiKit.centered(UiKit.label("点击词云选中它", 20)), Rect2(24, 222, 530, 26)))
	for i in Game.deck.size():
		var card := Game.deck[i]
		var rect := Rect2(52 + 120 * (i % 4), 258 + 78 * (i / 4), 112, 64)
		if card == _selected:
			add_child(UiKit.place(UiKit.nine("card_spell_highlight", 30), rect.grow(6)))
		_cloud_tile(card, rect, 30)
		var hit := _hit_area(rect, func() -> void:
			_selected = card
			_merge_target = null
			_rewrite_index = 0
			_rebuild())
		hit.tooltip_text = card.describe()


func _build_edit() -> void:
	var column := Rect2(570, 150, 532, 680)
	_column(column, "删除 · 改写 · 拆分")
	var center_x := column.get_center().x
	_cloud_tile(_selected, Rect2(center_x - 100, 226, 200, 108), 48)

	var remove := UiKit.button("删除这朵词云", 22)
	remove.disabled = _chosen or Game.deck.size() <= Game.DECK_MIN
	remove.tooltip_text = "牌库至少保留 %d 张" % Game.DECK_MIN
	remove.pressed.connect(func() -> void:
		Game.deck.erase(_selected)
		_selected = Game.deck[0]
		_finish())
	add_child(UiKit.place(remove, Rect2(center_x - 110, 346, 220, 46)))

	# 改写：先点符文选位置，再点新符文。
	add_child(UiKit.place(UiKit.label("改写：点下面的符文选位置，再选新符文", 21), Rect2(600, 410, 480, 30)))
	var count := _selected.runes.length()
	for i in count:
		var rune := _selected.runes[i]
		var tile_rect := Rect2(center_x - 34.0 * count + 68 * i + 4, 446, 60, 52)
		if i == _rewrite_index and count > 1:
			add_child(UiKit.place(UiKit.nine("card_spell_highlight", 20), tile_rect.grow(5)))
		add_child(UiKit.place(UiKit.nine("tile_%s" % UiKit.rune_piece_color(rune), 18), tile_rect))
		add_child(UiKit.place(UiKit.centered(UiKit.label(rune, 34, UiKit.INK, UiKit.rune_font())), tile_rect))
		_hit_area(tile_rect, func() -> void:
			_rewrite_index = i
			_rebuild())
	for i in SpellData.RUNES.size():
		var rune: String = SpellData.RUNES[i]
		var to := UiKit.button("→ " + rune, 24)
		to.add_theme_font_override("font", UiKit.rune_font())
		to.disabled = _chosen or _selected.runes[_rewrite_index] == rune
		to.pressed.connect(func() -> void:
			var runes := _selected.runes
			_selected.runes = runes.substr(0, _rewrite_index) + rune + runes.substr(_rewrite_index + 1)
			_finish())
		add_child(UiKit.place(to, Rect2(604 + 94 * i, 510, 84, 48)))

	# 拆分：在两个符文之间切一刀。
	add_child(UiKit.place(UiKit.label("拆分：从中间切开，变成两朵", 21), Rect2(600, 580, 480, 30)))
	if count < 2:
		add_child(UiKit.place(UiKit.centered(UiKit.label("只有一个符文，不能再拆", 20)), Rect2(570, 620, 532, 30)))
	for cut in range(1, count):
		var left := _selected.runes.substr(0, cut)
		var right := _selected.runes.substr(cut)
		var split := UiKit.button("%s | %s" % [left, right], 24)
		split.add_theme_font_override("font", UiKit.rune_font())
		split.disabled = _chosen
		split.pressed.connect(func() -> void:
			var index := Game.deck.find(_selected)
			_selected.runes = left
			Game.deck.insert(index + 1, CloudCard.new(right))
			_finish())
		add_child(UiKit.place(split, Rect2(center_x - 75.0 * (count - 1) + 150 * (cut - 1) + 6, 620, 138, 48)))


func _build_merge() -> void:
	var column := Rect2(1118, 150, 530, 680)
	_column(column, "合并")
	add_child(UiKit.place(UiKit.centered(UiKit.label("选一朵接在「%s」后面（最多 %d 个符文）" % [_selected.runes, MERGE_MAX], 20)), Rect2(1118, 222, 530, 26)))
	var slot := 0
	for card in Game.deck:
		if card == _selected:
			continue
		var rect := Rect2(1146 + 120 * (slot % 4), 258 + 66 * (slot / 4), 108, 56)
		slot += 1
		var fits := _selected.runes.length() + card.runes.length() <= MERGE_MAX
		if card == _merge_target:
			add_child(UiKit.place(UiKit.nine("card_spell_highlight", 30), rect.grow(5)))
		_cloud_tile(card, rect, 26)
		if not fits:
			var shade := ColorRect.new()
			shade.color = Color(UiKit.PARCHMENT, 0.6)
			shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(UiKit.place(shade, rect))
			continue
		var hit := _hit_area(rect, func() -> void:
			_merge_target = card
			_rebuild())
		hit.tooltip_text = "%s + %s → %s" % [_selected.runes, card.runes, _selected.runes + card.runes]

	if _merge_target != null:
		var merged := _selected.runes + _merge_target.runes
		var merge := UiKit.button("合并为  %s" % merged, 24)
		merge.disabled = _chosen or Game.deck.size() <= Game.DECK_MIN
		merge.tooltip_text = "牌库至少保留 %d 张" % Game.DECK_MIN
		merge.pressed.connect(func() -> void:
			_selected.runes = merged
			if _selected.affix_id == "":
				_selected.affix_id = _merge_target.affix_id
			Game.deck.erase(_merge_target)
			_finish())
		add_child(UiKit.place(merge, Rect2(1263, 720, 240, 52)))
