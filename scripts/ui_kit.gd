class_name UiKit
extends RefCounted
## 用 art/ui/pieces 里的切图拼界面的小工具。

const PIECE_PATH := "res://art/ui/pieces/%s.png"

const INK := Color("2a1a12")
const CREAM := Color("f6e7c1")
const PARCHMENT := Color("f1ddb0")
const RED := Color("c8321e")
const BLUE := Color("1f6fa8")
const GREEN := Color("3c8a3f")
const GOLD := Color("b8860b")
const PURPLE := Color("7b3fb5")
const NIGHT := Color("16121f")

static var _text_font: Font
static var _rune_font: Font


static func tex(piece: String) -> Texture2D:
	return load(PIECE_PATH % piece)


## 中文界面字体：优先用系统里的楷体，贴近手绘墨线的感觉。
static func text_font() -> Font:
	if _text_font == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Kaiti SC", "STKaiti", "KaiTi", "Noto Serif CJK SC", "Songti SC", "serif"])
		system.font_weight = 700
		var font := FontVariation.new()
		font.base_font = system
		font.variation_embolden = 0.5
		_text_font = font
	return _text_font


static func rune_font() -> Font:
	if _rune_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Cooper Black", "Georgia", "Times New Roman", "serif"])
		font.font_weight = 700
		_rune_font = font
	return _rune_font


static func place(node: Control, rect: Rect2) -> Control:
	node.position = rect.position
	node.size = rect.size
	return node


static func label(text: String, font_size: int, color: Color = INK, font: Font = null) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	if font != null:
		node.add_theme_font_override("font", font)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


## 叠在舞台画面上的浅色字，带墨色描边。
static func outlined(node: Label, outline: int = 8) -> Label:
	node.add_theme_color_override("font_outline_color", INK)
	node.add_theme_constant_override("outline_size", outline)
	return node


static func centered(node: Label) -> Label:
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func rich(font_size: int, color: Color = INK) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.scroll_active = false
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("normal_font_size", font_size)
	node.add_theme_color_override("default_color", color)
	return node


static func sprite(piece: String) -> TextureRect:
	var node := TextureRect.new()
	node.texture = tex(piece)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func nine(piece: String, margin_x: int, margin_y: int = -1) -> NinePatchRect:
	if margin_y < 0:
		margin_y = margin_x
	var node := NinePatchRect.new()
	node.texture = tex(piece)
	node.patch_margin_left = margin_x
	node.patch_margin_right = margin_x
	node.patch_margin_top = margin_y
	node.patch_margin_bottom = margin_y
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 大按钮用图集里的标签牌；小按钮字挤不进牌子的花边，改用同色系的墨线圆角框。
static func button(text: String, font_size: int = 22) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", font_size)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, INK)
	node.add_theme_color_override("font_disabled_color", Color(INK, 0.4))
	var large := font_size >= 30
	node.add_theme_stylebox_override("normal", _button_style(large, Color.WHITE))
	node.add_theme_stylebox_override("hover", _button_style(large, Color(1.0, 0.93, 0.66)))
	node.add_theme_stylebox_override("pressed", _button_style(large, Color(0.82, 0.74, 0.56)))
	node.add_theme_stylebox_override("disabled", _button_style(large, Color(0.78, 0.76, 0.72, 0.55)))
	return node


static func _button_style(large: bool, tint: Color) -> StyleBox:
	if large:
		var textured := StyleBoxTexture.new()
		textured.texture = tex("pill_label")
		textured.set_texture_margin_all(26)
		textured.modulate_color = tint
		return textured
	return ink_box(Color("fbeecb") * tint, 12)


static func ink_box(fill: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(INK, fill.a)
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style


## 符文对应的切图配色名：符文牌 tile_<名>，云朵 cloud_<名>。
static func rune_piece_color(rune: String) -> String:
	return {"a": "orange", "b": "purple", "c": "blue", "d": "green", "e": "gold"}.get(rune, "orange")


static func rune_color(rune: String) -> Color:
	match rune:
		"a":
			return RED
		"b":
			return PURPLE
		"c":
			return BLUE
		"d":
			return GREEN
		"e":
			return GOLD
	return INK


## 把咒式转成按符文上色的 BBCode。
static func rune_bbcode(pattern: String) -> String:
	var out := ""
	for rune in pattern:
		out += "[color=#%s]%s[/color]" % [rune_color(rune).to_html(false), rune]
	return out


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
