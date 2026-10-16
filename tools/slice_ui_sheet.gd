extends SceneTree

## Cuts art/ui/ui_components_sheet.webp into the individual pieces under art/ui/pieces/.
## Run from the project root:
##   godot --headless --path . --script res://tools/slice_ui_sheet.gd
## The rectangles are in pixels of the 1672x941 sheet; re-measure them if the sheet is replaced.

const SHEET := "res://art/ui/ui_components_sheet.webp"
const OUT_DIR := "res://art/ui/pieces"

const PIECES := {
	"banner_enemy": Rect2i(15, 21, 271, 99),
	"banner_spell": Rect2i(16, 125, 275, 87),
	"banner_mind": Rect2i(13, 418, 275, 73),
	"banner_spell_list": Rect2i(11, 666, 266, 76),
	"banner_common": Rect2i(14, 832, 252, 92),
	"panel_parchment": Rect2i(293, 37, 332, 82),
	"panel_parchment_large": Rect2i(16, 213, 513, 200),
	"panel_parchment_plain": Rect2i(1253, 567, 264, 96),
	"panel_starry": Rect2i(13, 492, 576, 165),
	"panel_dark": Rect2i(11, 744, 266, 82),
	"pill_dark": Rect2i(1228, 47, 205, 63),
	"pill_parchment": Rect2i(1518, 42, 135, 66),
	"pill_label": Rect2i(1479, 734, 173, 66),
	"card_spell": Rect2i(283, 689, 315, 140),
	"card_spell_highlight": Rect2i(598, 689, 299, 140),
	"ribbon": Rect2i(551, 150, 430, 79),
	"ribbon_small": Rect2i(613, 847, 256, 75),
	"bar_hp_frame": Rect2i(694, 48, 310, 58),
	"bar_hp_fill": Rect2i(1010, 62, 200, 35),
	"bar_timer_frame": Rect2i(1311, 169, 343, 42),
	"bar_timer_fill": Rect2i(1331, 214, 299, 28),
	"bar_small_frame": Rect2i(1293, 468, 238, 36),
	"bar_small_fill_red": Rect2i(1538, 479, 96, 20),
	"bar_small_fill_yellow": Rect2i(1538, 503, 104, 21),
	"bar_small_fill_blue": Rect2i(1538, 527, 94, 20),
	"tile_orange": Rect2i(537, 244, 131, 85),
	"tile_blue": Rect2i(804, 244, 129, 85),
	"tile_shared": Rect2i(937, 243, 139, 86),
	"tile_empty": Rect2i(1080, 244, 131, 85),
	"slot_memory": Rect2i(1523, 558, 126, 110),
	"bracket_red": Rect2i(1219, 255, 216, 38),
	"bracket_blue": Rect2i(1449, 254, 206, 38),
	"button_cast": Rect2i(1012, 336, 209, 80),
	"button_cast_hover": Rect2i(1226, 313, 230, 119),
	"button_cast_pressed": Rect2i(1459, 333, 205, 83),
	"cloud_orange": Rect2i(603, 453, 158, 88),
	"cloud_pink": Rect2i(772, 451, 146, 90),
	"cloud_blue": Rect2i(930, 450, 143, 91),
	"cloud_orange_wide": Rect2i(601, 564, 166, 93),
	"cloud_pink_wide": Rect2i(773, 562, 194, 95),
	"cloud_blue_wide": Rect2i(974, 566, 209, 92),
	"cloud_fading": Rect2i(1094, 451, 199, 111),
	"mascot_fireball": Rect2i(900, 683, 190, 162),
	"mascot_shield": Rect2i(1100, 693, 187, 150),
	"mascot_spark": Rect2i(1305, 701, 170, 144),
	"icon_heart": Rect2i(638, 58, 48, 45),
	"icon_heart_large": Rect2i(1590, 864, 56, 51),
	"icon_sword": Rect2i(1437, 40, 71, 71),
	"icon_hourglass": Rect2i(1220, 153, 76, 97),
	"icon_fire": Rect2i(1446, 859, 58, 60),
	"icon_shield": Rect2i(1525, 858, 45, 59),
	"icon_glove": Rect2i(889, 847, 87, 78),
	"divider": Rect2i(982, 869, 192, 39),
	"rune_a": Rect2i(1193, 868, 49, 50),
	"rune_b": Rect2i(1256, 860, 47, 58),
	"rune_c": Rect2i(1320, 867, 43, 50),
	"rune_d": Rect2i(1377, 855, 50, 64),
}


func _init() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	sheet.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for piece_name: String in PIECES:
		var piece := sheet.get_region(PIECES[piece_name])
		piece.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, piece_name]))
	_save_starry_frame(sheet.get_region(PIECES["panel_starry"]))
	_save_coin_icon()
	# 每种符文一种颜色：图集只有橙、蓝两色，其余由色相平移得到。
	var tints := {"purple": 0.76, "green": 0.31, "gold": 0.12}
	_save_tinted(sheet.get_region(PIECES["tile_blue"]), "tile_purple", tints.purple)
	_save_tinted(sheet.get_region(PIECES["tile_blue"]), "tile_green", tints.green)
	_save_tinted(sheet.get_region(PIECES["tile_orange"]), "tile_gold", tints.gold)
	for suffix: String in ["", "_wide"]:
		_save_tinted(sheet.get_region(PIECES["cloud_blue" + suffix]), "cloud_purple" + suffix, tints.purple)
		_save_tinted(sheet.get_region(PIECES["cloud_blue" + suffix]), "cloud_green" + suffix, tints.green)
		_save_tinted(sheet.get_region(PIECES["cloud_orange" + suffix]), "cloud_gold" + suffix, tints.gold)
	print("Sliced %d pieces into %s" % [PIECES.size(), OUT_DIR])
	quit()


## 脑海区有自己的整幅背景图，这里只留下星空面板的金色边框：把内部偏蓝的夜空像素抠掉。
func _save_starry_frame(panel: Image) -> void:
	for y in panel.get_height():
		for x in panel.get_width():
			var c := panel.get_pixel(x, y)
			var edge := mini(mini(x, y), mini(panel.get_width() - 1 - x, panel.get_height() - 1 - y))
			if edge > 44 or (edge > 8 and c.b > c.r * 1.15 + 0.02):
				panel.set_pixel(x, y, Color(c, 0.0))
	panel.save_png(ProjectSettings.globalize_path("%s/frame_starry.png" % OUT_DIR))


## 图集里没有金币图标，先画一个占位：墨线描边的金色圆币。
func _save_coin_icon() -> void:
	var size := 64
	var coin := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var color := Color(0, 0, 0, 0)
			if d <= 30.0:
				color = Color("2a1a12")
			if d <= 26.5:
				color = Color("f2c14e")
			if d <= 20.0 and d >= 17.0:
				color = Color("c8901e")
			coin.set_pixel(x, y, color)
	coin.save_png(ProjectSettings.globalize_path("%s/icon_coin.png" % OUT_DIR))


## 把有颜色的像素换成目标色相，墨线和纸色（饱和度低）保持不变。
func _save_tinted(piece: Image, out_name: String, hue: float) -> void:
	for y in piece.get_height():
		for x in piece.get_width():
			var c := piece.get_pixel(x, y)
			if c.a > 0.0 and c.s > 0.18 and c.v > 0.3:
				piece.set_pixel(x, y, Color.from_hsv(hue, c.s, c.v, c.a))
	piece.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, out_name]))
