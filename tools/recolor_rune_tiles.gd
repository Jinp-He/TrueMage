extends SceneTree
## 美术只画了橙、蓝、绿三色符文牌（rune_tile_*），紫、金、灰三色从橙色牌换色相生成。
## 用法：godot --headless --path . --script res://tools/recolor_rune_tiles.gd

const SOURCE := "res://art/ui/pieces/rune_tile_orange.png"
const OUT := "res://art/ui/pieces/rune_tile_%s.png"
## 目标色相（0～1）和饱和度倍率。
const TARGETS := {"purple": [0.78, 0.75], "gold": [0.12, 1.15], "gray": [0.0, 0.0]}


func _initialize() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	for color_name: String in TARGETS:
		var image := source.duplicate() as Image
		var hue: float = TARGETS[color_name][0]
		var saturation: float = TARGETS[color_name][1]
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a == 0.0:
					continue
				image.set_pixel(x, y, Color.from_hsv(hue, clampf(c.s * saturation, 0.0, 1.0), c.v, c.a))
		image.save_png(ProjectSettings.globalize_path(OUT % color_name))
	print("Recolored rune tiles: ", TARGETS.keys())
	quit()
