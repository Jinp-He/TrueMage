extends SceneTree

## Cuts art/ui/map_components_sheet.webp into the individual map pieces under art/ui/map/.
## Run from the project root:
##   godot --headless --path . --script res://tools/slice_map_sheet.gd
## 矩形是 1672x941 图集上的大致范围，按行、从左到右排列；切图时会自动收紧到不透明像素的边界。
## 每行最左侧带文字的分类标签（面板与标题、顶部状态……）不切。

const SHEET := "res://art/ui/map_components_sheet.webp"
const OUT_DIR := "res://art/ui/map"
## 收紧边界后四周保留的透明边距。
const PADDING := 2
const ALPHA_CUTOFF := 0.25

const PIECES := {
	# 面板与标题
	"panel_large": Rect2i(264, 10, 628, 222),
	"banner_title": Rect2i(900, 30, 386, 108),
	"plate_small": Rect2i(904, 144, 216, 84),
	"plate_wide": Rect2i(1134, 141, 527, 94),
	# 顶部状态
	"icon_heart": Rect2i(278, 258, 82, 82),
	"bar_frame": Rect2i(375, 255, 410, 88),
	"bar_fill_red": Rect2i(792, 272, 273, 58),
	"icon_coin": Rect2i(1082, 258, 77, 82),
	"pill_blank": Rect2i(1168, 260, 266, 78),
	"button_settings": Rect2i(1448, 246, 102, 101),
	"icon_settings": Rect2i(1566, 256, 86, 85),
	# 地图节点：底座（空白、已锁定、当前位置、可前往）和各类节点
	"node_blank": Rect2i(270, 372, 120, 124),
	"node_locked": Rect2i(388, 372, 118, 124),
	"node_current": Rect2i(502, 366, 128, 136),
	"node_reachable": Rect2i(630, 366, 128, 136),
	"node_battle": Rect2i(763, 375, 113, 120),
	"node_elite": Rect2i(876, 375, 110, 120),
	"node_shop": Rect2i(986, 375, 113, 120),
	"node_learn": Rect2i(1099, 375, 113, 120),
	"node_event": Rect2i(1212, 375, 113, 120),
	"node_treasure": Rect2i(1324, 375, 116, 120),
	"marker_player": Rect2i(1455, 378, 112, 106),
	"icon_check": Rect2i(1584, 400, 70, 72),
	# 路线与交互：直线（已走、未走、可选）、弯线、单独的箭头、指针、提示框、按钮（普通、悬停、按下）、继续箭头
	"path_dark": Rect2i(284, 528, 268, 48),
	"path_gray": Rect2i(284, 585, 268, 48),
	"path_blue": Rect2i(284, 642, 268, 52),
	"path_curve_up": Rect2i(610, 515, 250, 100),
	"path_curve_down": Rect2i(610, 625, 250, 80),
	"arrow_dark": Rect2i(898, 522, 64, 50),
	"arrow_gray": Rect2i(898, 580, 64, 50),
	"arrow_blue": Rect2i(898, 636, 64, 54),
	"cursor_hand": Rect2i(1012, 515, 104, 104),
	"tooltip": Rect2i(1160, 505, 366, 114),
	"button_purple": Rect2i(1002, 620, 190, 78),
	"button_purple_hover": Rect2i(1192, 620, 190, 78),
	"button_purple_pressed": Rect2i(1382, 620, 190, 78),
	"icon_play": Rect2i(1584, 608, 70, 92),
	# 起点与首领
	"portrait_start": Rect2i(350, 706, 222, 220),
	"portrait_boss": Rect2i(796, 676, 238, 254),
	"frame_round": Rect2i(1158, 732, 186, 186),
	"ribbon_label": Rect2i(1360, 805, 256, 95),
}

## 和别的切图挤在一起的部分：切之前先把这些区域抹成透明。
const ERASE := {
	# 首领头像的帽尖伸进了上一行：抹掉左上的弯线箭头、正上方的蓝色箭头和右上的紫色按钮底边。
	"portrait_boss": [Rect2i(796, 676, 60, 24), Rect2i(900, 676, 58, 10), Rect2i(1000, 676, 34, 24)],
}


func _init() -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	sheet.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for piece_name: String in PIECES:
		var source := sheet
		if ERASE.has(piece_name):
			source = sheet.duplicate()
			for area: Rect2i in ERASE[piece_name]:
				source.fill_rect(area, Color(0, 0, 0, 0))
		var rect := _trim(source, PIECES[piece_name])
		source.get_region(rect).save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, piece_name]))
		print("%s: %s" % [piece_name, rect])
	print("Sliced %d pieces into %s" % [PIECES.size(), OUT_DIR])
	quit()


## 把大致范围收紧到其中不透明像素的边界，再留出 PADDING。
## 图集背景里有一层几乎透明的杂色，所以只把 alpha 超过 ALPHA_CUTOFF 的像素算作内容。
func _trim(sheet: Image, rough: Rect2i) -> Rect2i:
	rough = rough.intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
	var lo := rough.end
	var hi := rough.position - Vector2i.ONE
	for y in range(rough.position.y, rough.end.y):
		for x in range(rough.position.x, rough.end.x):
			if sheet.get_pixel(x, y).a > ALPHA_CUTOFF:
				lo = lo.min(Vector2i(x, y))
				hi = hi.max(Vector2i(x, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE).grow(PADDING).intersection(rough)
