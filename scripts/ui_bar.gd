class_name UiBar
extends Control
## 进度条：一个九宫格外框加一条按比例伸缩的填充。

var ratio: float = 1.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		_update_fill()

var _fill: NinePatchRect
var _inset: Vector2


static func create(frame_piece: String, fill_piece: String, bar_size: Vector2, inset: Vector2) -> UiBar:
	var bar := UiBar.new()
	bar.size = bar_size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar._inset = inset
	var frame := UiKit.nine(frame_piece, int(bar_size.y * 0.6), 0)
	frame.size = bar_size
	bar.add_child(frame)
	bar._fill = UiKit.nine(fill_piece, 8, 0)
	bar._fill.position = inset
	bar.add_child(bar._fill)
	bar._update_fill()
	return bar


func set_fill(fill_piece: String) -> void:
	_fill.texture = UiKit.tex(fill_piece)


func _update_fill() -> void:
	if _fill == null:
		return
	var area := size - _inset * 2.0
	_fill.visible = ratio > 0.0
	_fill.size = Vector2(maxf(area.y, area.x * ratio), area.y)
