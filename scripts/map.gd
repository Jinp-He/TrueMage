extends Control
## 地图：从左边的起点出发，每次往右走一层，最右边是首领。
## 只有和当前位置相连的下一层节点可以点；走过的路线是深色实线，可走的是蓝色，其余是灰色。
## 素材见 art/ui/map/（由 tools/slice_map_sheet.gd 切出）。

const MAP_RECT := Rect2(24, 124, 1624, 680)
## 节点所在的纵向范围。
const NODE_TOP := 210.0
const NODE_BOTTOM := 730.0
const FIRST_LAYER_X := 330.0
const LAST_LAYER_X := 1340.0
const NODE_SIZE := 92.0
const START_CENTER := Vector2(150, 470)
const START_SIZE := Vector2(170, 168)
const BOSS_CENTER := Vector2(1520, 460)
const BOSS_SIZE := Vector2(200, 219)

const PATH_DONE := Color("3b3a40")
const PATH_OPEN := Color("1f8ad8")
const PATH_IDLE := Color(0.45, 0.42, 0.38, 0.55)

## 各类节点的图标切图；休息处和抄写室还没有专属图标，先用空白底座叠一颗心、一朵云。
const NODE_PIECES := {
	MapData.BATTLE: "node_battle",
	MapData.ELITE: "node_elite",
	MapData.SHOP: "node_shop",
	MapData.TREASURE: "node_treasure",
}
const TREASURE_GOLD := 15

var _routes: Routes
var _reachable: Array[MapData.MapNode] = []


## 画路线的图层：虚线加箭头。
class Routes:
	extends Control
	## 每项是 [起点, 终点, 颜色, 线宽]。
	var lines: Array = []

	func _draw() -> void:
		for line: Array in lines:
			var from: Vector2 = line[0]
			var to: Vector2 = line[1]
			var color: Color = line[2]
			var width: float = line[3]
			var direction := (to - from).normalized()
			draw_dashed_line(from, to - direction * 14.0, color, width, 16.0)
			var side := direction.orthogonal() * width * 1.8
			draw_colored_polygon(PackedVector2Array([to, to - direction * 18.0 + side, to - direction * 18.0 - side]), color)


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	UiKit.clear_children(self)
	_reachable = Game.map.reachable_from(Game.map_node)
	_build_backdrop()
	_build_header()
	_routes = Routes.new()
	_routes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(_routes, Rect2(0, 0, 1672, 941)))
	_build_routes()
	_build_start()
	for layer in MapData.LAYERS:
		for node: MapData.MapNode in Game.map.layers[layer]:
			_build_node(node)
	_build_boss()
	_build_marker()
	_build_legend()


# ---------------------------------------------------------------- 布局

func _node_center(node: MapData.MapNode) -> Vector2:
	if node.type == MapData.BOSS:
		return BOSS_CENTER
	var x := lerpf(FIRST_LAYER_X, LAST_LAYER_X, float(node.layer) / (MapData.LAYERS - 1))
	return Vector2(x, lerpf(NODE_TOP, NODE_BOTTOM, node.y))


func _current_layer() -> int:
	return -1 if Game.map_node == null else Game.map_node.layer


func _is_reachable(node: MapData.MapNode) -> bool:
	return node in _reachable


# ---------------------------------------------------------------- 画面

func _build_backdrop() -> void:
	var night := ColorRect.new()
	night.color = UiKit.NIGHT
	add_child(UiKit.place(night, Rect2(0, 0, 1672, 941)))
	add_child(UiKit.place(_map_nine("panel_large", 40), MAP_RECT))


## 地图切图的九宫格拉伸版：四角花纹保持原样。
func _map_nine(piece: String, margin: int) -> NinePatchRect:
	var node := NinePatchRect.new()
	node.texture = load(UiKit.MAP_PIECE_PATH % piece)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		node.set_patch_margin(side, margin)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func _build_header() -> void:
	add_child(UiKit.place(UiKit.map_sprite("banner_title"), Rect2(616, 4, 440, 126)))
	var title := "墓园 · 起点" if Game.map_node == null else "墓园 · 第 %d / %d 层" % [Game.floor_number(), MapData.LAYERS + 1]
	add_child(UiKit.place(UiKit.centered(UiKit.label(title, 34)),
		Rect2(616, 22, 440, 70)))

	add_child(UiKit.place(UiKit.map_sprite("pill_blank"), Rect2(36, 30, 240, 66)))
	add_child(UiKit.place(UiKit.map_sprite("icon_heart"), Rect2(52, 40, 50, 46)))
	add_child(UiKit.place(UiKit.label("%d / %d" % [Game.hp, Game.max_hp], 30), Rect2(112, 30, 160, 66)))

	add_child(UiKit.place(UiKit.map_sprite("pill_blank"), Rect2(292, 30, 200, 66)))
	add_child(UiKit.place(UiKit.map_sprite("icon_coin"), Rect2(306, 38, 50, 50)))
	add_child(UiKit.place(UiKit.label("%d" % Game.gold, 30, UiKit.GOLD.darkened(0.25)), Rect2(366, 30, 120, 66)))

	var hint := "选择第一站" if Game.map_node == null else "选择下一站"
	var hint_label := UiKit.outlined(UiKit.label(hint, 28, UiKit.CREAM), 6)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(UiKit.place(hint_label, Rect2(1236, 30, 400, 66)))


func _build_routes() -> void:
	var lines := []
	var start_open := Game.map_node == null
	for node: MapData.MapNode in Game.map.layers[0]:
		lines.append(_line(START_CENTER, START_SIZE.x / 2.0, node, node.visited, start_open))
	for layer in MapData.LAYERS:
		for node: MapData.MapNode in Game.map.layers[layer]:
			for row in node.next:
				var target := Game.map.node_at(layer + 1, row)
				lines.append(_line(_node_center(node), NODE_SIZE / 2.0, target,
					node.visited and target.visited, node == Game.map_node))
	# 灰线先画，走过的和可走的盖在上面。
	lines.sort_custom(func(a: Array, b: Array) -> bool: return a[2] == PATH_IDLE and b[2] != PATH_IDLE)
	_routes.lines = lines
	_routes.queue_redraw()


func _line(from: Vector2, from_radius: float, target: MapData.MapNode, done: bool, open: bool) -> Array:
	var to := _node_center(target)
	var to_radius := BOSS_SIZE.x / 2.0 if target.type == MapData.BOSS else NODE_SIZE / 2.0
	var direction := (to - from).normalized()
	var color := PATH_DONE if done else (PATH_OPEN if open else PATH_IDLE)
	return [from + direction * (from_radius + 6.0), to - direction * (to_radius + 4.0), color, 5.0 if done or open else 4.0]


func _build_start() -> void:
	var rect := Rect2(START_CENTER - START_SIZE / 2.0, START_SIZE)
	add_child(UiKit.place(UiKit.map_sprite("portrait_start"), rect))
	_ribbon_text(Game.character.name, rect)


func _build_boss() -> void:
	var boss := Game.map.boss()
	var rect := Rect2(BOSS_CENTER - BOSS_SIZE / 2.0, BOSS_SIZE)
	var holder := _pivot_holder(rect)
	holder.add_child(UiKit.place(UiKit.map_sprite("portrait_boss"), Rect2(Vector2.ZERO, rect.size)))
	_ribbon_text(Game.BOSS_ENEMY.name, rect)
	if _is_reachable(boss):
		_pulse(holder)
		_click_area(rect, boss, "首领：%s（生命 %d）" % [Game.BOSS_ENEMY.name, Game.BOSS_ENEMY.hp])


## 头像底部的飘带上写名字。
func _ribbon_text(text: String, rect: Rect2) -> void:
	var label := UiKit.centered(UiKit.label(text, 22))
	add_child(UiKit.place(label, Rect2(rect.position.x, rect.end.y - rect.size.y * 0.2, rect.size.x, rect.size.y * 0.16)))


func _build_node(node: MapData.MapNode) -> void:
	var center := _node_center(node)
	var rect := Rect2(center - Vector2.ONE * NODE_SIZE / 2.0, Vector2.ONE * NODE_SIZE)
	var reachable := _is_reachable(node)
	var holder := _pivot_holder(rect)

	# 外圈：当前位置橙色，可前往蓝色。底座切图比图标节点略大一圈，外框正好露在图标外面。
	var ring := ""
	if node == Game.map_node:
		ring = "node_current"
	elif reachable:
		ring = "node_reachable"
	if ring != "":
		var grow := NODE_SIZE * 0.14
		holder.add_child(UiKit.place(UiKit.map_sprite(ring), Rect2(-Vector2.ONE * grow, rect.size + Vector2.ONE * grow * 2.0)))

	holder.add_child(UiKit.place(_node_icon(node.type), Rect2(Vector2.ZERO, rect.size)))
	if node.visited:
		holder.add_child(UiKit.place(UiKit.map_sprite("icon_check"), Rect2(rect.size * 0.6, rect.size * 0.42)))
	elif node.layer <= _current_layer():
		# 已经错过的节点变暗。
		holder.modulate = Color(0.55, 0.52, 0.5, 0.8)

	if reachable:
		_pulse(holder)
		_click_area(rect, node, MapData.NAMES[node.type])
	else:
		holder.tooltip_text = MapData.NAMES[node.type]
		holder.mouse_filter = Control.MOUSE_FILTER_STOP


func _node_icon(type: String) -> Control:
	if NODE_PIECES.has(type):
		return UiKit.map_sprite(NODE_PIECES[type])
	var base := UiKit.map_sprite("node_blank")
	if type == MapData.SCRIPTORIUM:
		base.add_child(UiKit.place(UiKit.sprite("cloud_blue"), Rect2(NODE_SIZE * Vector2(0.17, 0.26), NODE_SIZE * Vector2(0.66, 0.46))))
		base.add_child(UiKit.place(UiKit.centered(UiKit.label("ab", 26, UiKit.INK, UiKit.rune_font())), Rect2(NODE_SIZE * Vector2(0.17, 0.24), NODE_SIZE * Vector2(0.66, 0.46))))
	else:
		base.add_child(UiKit.place(UiKit.map_sprite("icon_heart"), Rect2(Vector2.ONE * NODE_SIZE * 0.24, Vector2.ONE * NODE_SIZE * 0.52)))
	return base


## 以中心为轴缩放的容器，给节点做脉动和悬停放大。
func _pivot_holder(rect: Rect2) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(holder, rect))
	holder.pivot_offset = rect.size / 2.0
	return holder


func _pulse(node: Control) -> void:
	var tween := node.create_tween().set_loops()
	tween.tween_property(node, "scale", Vector2.ONE * 1.08, 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


func _click_area(rect: Rect2, node: MapData.MapNode, tooltip: String) -> void:
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.tooltip_text = tooltip
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.pressed.connect(_travel.bind(node))
	add_child(UiKit.place(hit, rect))


## 玩家标记：法师帽浮在当前位置上方，还没出发时在起点头像上。
func _build_marker() -> void:
	var anchor := START_CENTER - Vector2(0, START_SIZE.y / 2.0 + 10.0)
	if Game.map_node != null:
		anchor = _node_center(Game.map_node) - Vector2(0, NODE_SIZE / 2.0 + 10.0)
	var marker := UiKit.map_sprite("marker_player")
	add_child(UiKit.place(marker, Rect2(anchor - Vector2(36, 62), Vector2(72, 66))))
	var tween := marker.create_tween().set_loops()
	tween.tween_property(marker, "position:y", marker.position.y - 8.0, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(marker, "position:y", marker.position.y, 0.7).set_trans(Tween.TRANS_SINE)


func _build_legend() -> void:
	var rect := Rect2(216, 820, 1240, 100)
	add_child(UiKit.place(_map_nine("plate_wide", 30), rect))
	var types := [MapData.BATTLE, MapData.ELITE, MapData.SHOP, MapData.REST, MapData.SCRIPTORIUM, MapData.TREASURE]
	var slot := (rect.size.x - 60.0) / types.size()
	for i in types.size():
		var left := rect.position + Vector2(30.0 + slot * i + 14.0, 22.0)
		var icon := _node_icon(types[i])
		icon.scale = Vector2.ONE * 56.0 / NODE_SIZE
		add_child(UiKit.place(icon, Rect2(left, Vector2.ONE * NODE_SIZE)))
		add_child(UiKit.place(UiKit.label(MapData.NAMES[types[i]], 24), Rect2(left + Vector2(64, 0), Vector2(130, 56))))


# ---------------------------------------------------------------- 前进

func _travel(node: MapData.MapNode) -> void:
	if not _is_reachable(node):
		return
	Game.enter_node(node)
	if node.type == MapData.TREASURE:
		_open_treasure()


## 宝箱就地打开：得到一件随机遗物，遗物都拿齐了就换成金币。
func _open_treasure() -> void:
	var relic := Game.random_relic()
	var detail := ""
	if relic != null:
		Game.gain_relic(relic)
		detail = "获得遗物「%s」\n%s" % [relic.name, relic.description]
	else:
		Game.gold += TREASURE_GOLD
		detail = "箱子里只剩金币：获得 %d 金币" % TREASURE_GOLD
	_rebuild()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	add_child(UiKit.place(dim, Rect2(0, 0, 1672, 941)))
	dim.add_child(UiKit.place(_map_nine("panel_large", 40), Rect2(486, 300, 700, 340)))
	dim.add_child(UiKit.place(UiKit.map_sprite("banner_title"), Rect2(616, 236, 440, 126)))
	dim.add_child(UiKit.place(UiKit.centered(UiKit.label("宝箱", 42)), Rect2(616, 254, 440, 70)))
	if relic != null:
		dim.add_child(UiKit.place(UiKit.icon_sprite("relics", relic.id, relic.icon), Rect2(796, 372, 80, 80)))
	var text := UiKit.centered(UiKit.label(detail, 28))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dim.add_child(UiKit.place(text, Rect2(526, 456, 620, 84)))
	var confirm := UiKit.button("收下", 32)
	confirm.pressed.connect(dim.queue_free)
	dim.add_child(UiKit.place(confirm, Rect2(736, 548, 200, 72)))
