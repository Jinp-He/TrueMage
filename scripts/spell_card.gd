class_name SpellCard
extends Control
## 法术卡：吉祥物图标、名称、咒式和效果。战斗的法术列表和商店共用。

var spell: SpellData

var _frame: NinePatchRect


static func create(p_spell: SpellData, card_size: Vector2, tag: String = "") -> SpellCard:
	var card := SpellCard.new()
	card.spell = p_spell
	card.size = card_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card._build(tag)
	return card


func set_highlight(on: bool) -> void:
	_frame.texture = UiKit.tex("card_spell_highlight" if on else "card_spell")


func _build(tag: String) -> void:
	var k := clampf(size.y / 160.0, 0.62, 1.0)
	_frame = UiKit.nine("card_spell", 36)
	_frame.size = size
	add_child(_frame)

	var icon_side := minf(size.y - 28.0, 124.0)
	var icon := UiKit.icon_sprite("spells", spell.id, spell.icon)
	add_child(UiKit.place(icon, Rect2(20, (size.y - icon_side) / 2.0, icon_side, icon_side)))

	var text_x := 20.0 + icon_side + 14.0
	var text_w := size.x - text_x - 16.0
	var line := size.y * 0.25
	var top := size.y * 0.13

	# 右上角留给标签，名字太长时缩小字号。
	var name_width := text_w - (100.0 * k + 30.0 if tag != "" else 0.0)
	var name_size := int(32 * k)
	while name_size > 14 and UiKit.text_font().get_string_size(spell.name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > name_width:
		name_size -= 1
	var name_label := UiKit.label(spell.name, name_size)
	add_child(UiKit.place(name_label, Rect2(text_x, top, text_w, line)))

	var pattern := UiKit.rich(int(26 * k))
	pattern.add_theme_font_override("bold_font", UiKit.rune_font())
	pattern.add_theme_font_size_override("bold_font_size", int(32 * k))
	pattern.text = "咒语： %s" % spell.pattern_bbcode()
	add_child(UiKit.place(pattern, Rect2(text_x, top + line, text_w, line * 1.2)))

	# 强化后效果描述可能变长，缩小字号直到放得下。
	var effect_size := int(23 * k)
	while effect_size > 12 and UiKit.text_font().get_string_size(spell.effect_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, effect_size).x > text_w - 40.0:
		effect_size -= 1
	var effect := UiKit.label(spell.effect_text(), effect_size)
	add_child(UiKit.place(effect, Rect2(text_x, top + line * 2.1, text_w, line)))

	if tag != "":
		var chip := UiKit.centered(UiKit.label(tag, int(18 * k)))
		chip.add_theme_stylebox_override("normal", UiKit.ink_box(Color("fbeecb"), 10))
		add_child(UiKit.place(chip, Rect2(size.x - 100.0 * k - 18.0, top, 100.0 * k, 34.0 * k)))
