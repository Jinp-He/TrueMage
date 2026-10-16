class_name IntermissionPage
extends Control
## 对决之间的页面（咒语商店、休息处）共用的外观：脑海星空背景、标题横幅、金币与生命、羊皮纸分栏。
## 每次交易后子类调用 _rebuild() 整页重建，状态都在 Game 里。

const MIND_BACKGROUND := "res://art/backgrounds/mind_area.webp"


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	UiKit.clear_children(self)
	_build_backdrop()
	_build_header(_page_title())
	_build_page()
	var depart := UiKit.button("下一场对决", 32)
	depart.pressed.connect(Game.go_to_battle)
	add_child(UiKit.place(depart, Rect2(696, 842, 280, 80)))


## 子类实现：页面标题与正文。
func _page_title() -> String:
	return ""


func _build_page() -> void:
	pass


func _spend(cost: int) -> bool:
	if Game.gold < cost:
		return false
	Game.gold -= cost
	return true


func _build_backdrop() -> void:
	var background := TextureRect.new()
	background.texture = load(MIND_BACKGROUND)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.place(background, Rect2(0, 0, 1672, 941)))


func _build_header(title: String) -> void:
	add_child(UiKit.place(UiKit.sprite("ribbon"), Rect2(586, 6, 500, 100)))
	add_child(UiKit.place(UiKit.centered(UiKit.label(title, 42)), Rect2(586, 6, 500, 88)))

	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(40, 26, 250, 64)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("金币  %d" % Game.gold, 30, UiKit.GOLD.darkened(0.25))), Rect2(40, 26, 250, 64)))

	add_child(UiKit.place(UiKit.nine("pill_parchment", 30), Rect2(1382, 26, 250, 64)))
	add_child(UiKit.place(UiKit.sprite("icon_heart"), Rect2(1404, 40, 36, 36)))
	add_child(UiKit.place(UiKit.centered(UiKit.label("%d / %d" % [Game.hp, Game.max_hp], 30)), Rect2(1440, 26, 180, 64)))

	var enemy := Game.current_enemy()
	var next_label := UiKit.label("下一场：%s（生命 %d）" % [enemy.name, enemy.hp], 28, UiKit.CREAM)
	add_child(UiKit.place(UiKit.outlined(UiKit.centered(next_label)), Rect2(486, 104, 700, 40)))


func _column(rect: Rect2, title: String) -> void:
	add_child(UiKit.place(UiKit.nine("panel_parchment_large", 46), rect))
	add_child(UiKit.place(UiKit.centered(UiKit.label(title, 32)), Rect2(rect.position + Vector2(0, 18), Vector2(rect.size.x, 44))))
	add_child(UiKit.place(UiKit.sprite("divider"), Rect2(rect.position + Vector2(rect.size.x / 2.0 - 110, 58), Vector2(220, 26))))


## 一个透明的整块按钮，叠在卡片上让整张卡可点。
func _hit_area(rect: Rect2, on_press: Callable) -> Button:
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.pressed.connect(on_press)
	add_child(UiKit.place(hit, rect))
	return hit
