class_name FragmentCloud
extends Control
## 脑海区里的一个碎片选项。一批选项同时浮现，选中其中一块后其余的消散，再浮现下一批。

signal picked(cloud: FragmentCloud)

var text: String
var base_position: Vector2
var frozen := false

var _cloud: TextureRect
var _bob_phase: float
var _age := 0.0
var _available := true
var _gone := false


static func create(p_text: String) -> FragmentCloud:
	var cloud := FragmentCloud.new()
	cloud.text = p_text
	cloud.size = Vector2(150, 92) if p_text.length() == 1 else Vector2(128 + 38 * p_text.length(), 96)
	cloud.pivot_offset = cloud.size / 2.0
	cloud._bob_phase = randf() * TAU
	cloud._build()
	return cloud


func set_available(on: bool) -> void:
	_available = on
	_cloud.modulate = Color.WHITE if on else Color(0.55, 0.55, 0.62)


## 浮现动画；delay 用来让同一批选项依次冒出来。
func appear(delay: float) -> void:
	modulate.a = 0.0
	scale = Vector2(0.7, 0.7)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.25).set_delay(delay)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	_cloud = UiKit.sprite(_cloud_piece())
	_cloud.stretch_mode = TextureRect.STRETCH_SCALE
	_cloud.size = size
	add_child(_cloud)

	var label := UiKit.centered(UiKit.label(text, 50, UiKit.INK, UiKit.rune_font()))
	add_child(UiKit.place(label, Rect2(0, -4, size.x, size.y)))


func _cloud_piece() -> String:
	var fire := false
	var frost := false
	for rune in text:
		if SpellData.is_warm(rune):
			fire = true
		else:
			frost = true
	var color := "pink" if fire and frost else ("orange" if fire else "blue")
	return "cloud_%s%s" % [color, "" if text.length() == 1 else "_wide"]


func _process(delta: float) -> void:
	if _gone:
		return
	_age += delta
	position = base_position + Vector2(0, sin(_age * 1.7 + _bob_phase) * 5.0)


func _gui_input(event: InputEvent) -> void:
	if _gone or frozen:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		picked.emit(self)


func _notification(what: int) -> void:
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
