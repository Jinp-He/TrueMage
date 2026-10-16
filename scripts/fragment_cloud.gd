class_name FragmentCloud
extends Control
## 脑海区里的一朵词云（牌库里的一张牌）。词云一朵接一朵浮现，各自停留一段时间后消散；选走一朵不影响其他的。

signal picked(cloud: FragmentCloud)
## 右键：存入记忆栏。
signal stored(cloud: FragmentCloud)
## 停留时间到了，自己消散。
signal expired(cloud: FragmentCloud)

const BAR_HEIGHT := 22.0
const FADING_AT := 0.25

var card: CloudCard
var text: String
var base_position: Vector2
var frozen := false
var life: float
var max_life: float
## 在脑海里漂移的速度（像素/秒），由战斗场景负责移动和碰撞。
var velocity: Vector2
## 鼠标悬停时停下，方便点击。
var hovered := false

var _cloud: TextureRect
var _bar: UiBar
var _bob_phase: float
var _age := 0.0
var _available := true
var _gone := false


static func create(p_card: CloudCard, p_life: float) -> FragmentCloud:
	var cloud := FragmentCloud.new()
	cloud.card = p_card
	cloud.text = p_card.runes
	cloud.life = p_life
	cloud.max_life = p_life
	var body := Vector2(150, 92) if cloud.text.length() == 1 else Vector2(128 + 38 * cloud.text.length(), 96)
	cloud.size = body + Vector2(0, BAR_HEIGHT)
	cloud.pivot_offset = cloud.size / 2.0
	cloud._bob_phase = randf() * TAU
	cloud._build()
	return cloud


func set_available(on: bool) -> void:
	_available = on
	_cloud.modulate = Color.WHITE if on else Color(0.55, 0.55, 0.62)


## 浮现动画；delay 让同一批词云一朵接一朵冒出来。冒出来之前点不到。
func appear(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2(0.7, 0.7)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void:
		if not _gone:
			mouse_filter = Control.MOUSE_FILTER_STOP)


## 被选中：放大后飞散。
func consume() -> void:
	_leave(Vector2(1.25, 1.25), 0.18)


## 没被选中：化作烟雾消散。
func dismiss() -> void:
	if _gone:
		return
	_cloud.texture = UiKit.tex("cloud_fading")
	_cloud.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leave(Vector2(0.9, 0.9), 0.3)


## 句子放不下这块碎片时左右晃一下。
func reject() -> void:
	var tween := create_tween()
	for offset: float in [-8.0, 8.0, -5.0, 0.0]:
		tween.tween_property(_cloud, "position:x", offset, 0.05)


func _build() -> void:
	var body := Vector2(size.x, size.y - BAR_HEIGHT)
	_cloud = UiKit.sprite(_cloud_piece())
	_cloud.stretch_mode = TextureRect.STRETCH_SCALE
	_cloud.size = body
	add_child(_cloud)

	var label := UiKit.centered(UiKit.label(text, 50, UiKit.INK, UiKit.rune_font()))
	add_child(UiKit.place(label, Rect2(Vector2(0, -4), body)))

	var bar_size := Vector2(minf(size.x - 40.0, 124.0), 18)
	_bar = UiBar.create("bar_small_frame", "bar_small_fill_blue", bar_size, Vector2(7, 4))
	_bar.position = Vector2((size.x - bar_size.x) / 2.0, size.y - BAR_HEIGHT + 3.0)
	add_child(_bar)

	var affix := card.affix()
	if affix != null:
		tooltip_text = "%s：%s" % [affix.name, affix.description]
		add_child(affix_badge(affix, Vector2(size.x / 2.0, body.y - 6.0)))


## 词条徽记：小图标 + 词条名，中心放在 center。战斗和商店共用。
static func affix_badge(affix: AffixData, center: Vector2, font_size: int = 18) -> Control:
	var badge := HBoxContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_constant_override("separation", 2)
	var icon := UiKit.icon_sprite("affixes", affix.id, affix.icon)
	icon.custom_minimum_size = Vector2(font_size + 6, font_size + 6)
	badge.add_child(icon)
	var name_label := UiKit.label(affix.name, font_size)
	badge.add_child(name_label)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiKit.ink_box(Color("fbeecb"), 10)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(badge)
	# 进入场景树后主题字体才确定，那时再按实际大小居中。
	panel.ready.connect(func() -> void:
		panel.size = panel.get_combined_minimum_size()
		panel.position = center - panel.size / 2.0)
	return panel


func _cloud_piece() -> String:
	return piece_for(text)


## 单一符文的词云用该符文的颜色，混合符文用粉色；单符文用小云，多符文用宽云。
static func piece_for(text: String) -> String:
	var colors := {}
	for rune in text:
		colors[UiKit.rune_piece_color(rune)] = true
	var color: String = colors.keys()[0] if colors.size() == 1 else "pink"
	return "cloud_%s%s" % [color, "" if text.length() == 1 else "_wide"]


func _process(delta: float) -> void:
	if _gone:
		return
	_age += delta
	position = base_position + Vector2(0, sin(_age * 1.7 + _bob_phase) * 5.0)
	if frozen:
		return
	life -= delta
	var left := life / max_life
	_bar.ratio = left
	_bar.set_fill("bar_small_fill_blue" if left > 0.6 else ("bar_small_fill_yellow" if left > 0.3 else "bar_small_fill_red"))
	if left < FADING_AT:
		_cloud.self_modulate.a = 0.45 + 0.55 * (left / FADING_AT)
	if life <= 0.0:
		expired.emit(self)
		dismiss()


func _gui_input(event: InputEvent) -> void:
	if _gone or frozen:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit(self)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			stored.emit(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		hovered = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		hovered = false
	if _gone or frozen or not _available:
		return
	if what == NOTIFICATION_MOUSE_ENTER:
		scale = Vector2(1.07, 1.07)
	elif what == NOTIFICATION_MOUSE_EXIT:
		scale = Vector2.ONE


func _leave(to_scale: Vector2, duration: float) -> void:
	_gone = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_property(self, "scale", to_scale, duration)
	tween.chain().tween_callback(queue_free)
