extends IntermissionPage
## Candidates live in Game, so reopening this page cannot reroll them.

var _selected := -1
var _busy := false
var _message := ""

func _ready() -> void:
	if Game.pending_rewards.is_empty() and Game.resume_scene == Game.BATTLE_SCENE:
		Game.complete_battle()
	super()

func _page_title() -> String:
	return "战后成长"

func _subtitle() -> String:
	return ""

func _rebuild() -> void:
	UiKit.clear_children(self)
	_build_backdrop()
	_build_header(_page_title())
	_build_page()

func _build_page() -> void:
	for i in Game.pending_rewards.size():
		var display := _presentation(Game.pending_rewards[i])
		var x := 40.0 + i * 544.0
		var rect := Rect2(x, 190, 504, 500)
		_column(rect, display.title)
		if Game.pending_rewards[i].kind == "capacity":
			for slot in 3:
				var piece := "rune_tile_gold" if slot == 2 else "rune_tile_empty"
				add_child(UiKit.place(UiKit.sprite(piece), Rect2(x + 182 + slot * 50, 316, 40, 56)))
		else:
			var icon := UiKit.icon_sprite("spells", Game.pending_rewards[i].spell, display.icon) if Game.pending_rewards[i].kind == "stat" else UiKit.sprite(display.icon)
			add_child(UiKit.place(icon, Rect2(x + 208, 300, 88, 88)))
		var value := UiKit.centered(UiKit.label(display.value, 42))
		add_child(UiKit.place(value, Rect2(x + 24, 426, 456, 70)))
		var detail := UiKit.centered(UiKit.label(display.detail, 24))
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(UiKit.place(detail, Rect2(x + 30, 508, 444, 100)))
		var choose := _hit_area(rect, _select.bind(i))
		choose.name = "RewardChoice%d" % i
		choose.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		choose.focus_mode = Control.FOCUS_ALL
		choose.tooltip_text = display.title
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var frame := StyleBoxFlat.new()
			frame.bg_color = Color(1, 0.85, 0.4, 0.08) if i == _selected else Color.TRANSPARENT
			frame.border_color = UiKit.GOLD if i == _selected or state != "normal" else Color.TRANSPARENT
			frame.set_border_width_all(4)
			frame.set_corner_radius_all(24)
			choose.add_theme_stylebox_override(state, frame)
	var confirm := UiKit.button("领取", 30)
	confirm.disabled = _selected < 0 or _busy
	confirm.pressed.connect(_confirm)
	add_child(UiKit.place(confirm, Rect2(696, 750, 280, 80)))
	if Game.pending_rewards.is_empty():
		confirm.disabled = false
		confirm.text = "继续" if Game.save_error.is_empty() else "重试"
	var message := _message if not _message.is_empty() else Game.reward_detail
	add_child(UiKit.place(UiKit.centered(UiKit.label(message, 24, UiKit.CREAM)), Rect2(100, 850, 1472, 60)))

func _select(index: int) -> void:
	_selected = index
	_rebuild()

# Derive presentation from reward data so saved candidates use the current UI too.
func _presentation(offer: Dictionary) -> Dictionary:
	match offer.kind:
		"stat":
			for spell in Game.spells:
				if spell.id != offer.spell:
					continue
				var label: String = {"damage": "伤害", "shield": "护盾", "heal": "治疗", "gold": "金币", "fire_affinity": "火焰亲和", "shield_per_affinity": "亲和护盾倍率"}.get(offer.effect, offer.effect)
				var before: int = spell.get(offer.effect)
				var detail := label
				if offer.effect == "fire_affinity":
					detail = "火焰亲和 · 持续本场战斗"
				return {"title": spell.name + " · " + spell.pattern_text(), "value": "%d → %d" % [before, before + int(offer.get("amount", 3))], "detail": detail, "icon": spell.icon}
		"capacity":
			return {"title": "句子扩展", "value": "%d → %d 格" % [Game.max_length, mini(Game.MAX_LENGTH_CAP, Game.max_length + 1)], "detail": "句子容量", "icon": "icon_timer"}
		"short_sentence":
			return {"title": "短句专注", "value": "额外伤害 +3", "detail": "不超过 4 格且触发法术
每句一次", "icon": "icon_fire"}
		"heal":
			return {"title": "恢复生命", "value": "+%d" % mini(8, Game.max_hp - Game.hp), "detail": "%d → %d / %d" % [Game.hp, mini(Game.max_hp, Game.hp + 8), Game.max_hp], "icon": "icon_heart_large"}
		"mind":
			return {"title": "念头延续", "value": "%.0f → %.0f 秒" % [Game.cloud_life, minf(Game.CLOUD_LIFE_CAP, Game.cloud_life + 2)], "detail": "词云停留", "icon": "cloud_blue"}
		"gold":
			return {"title": "金币", "value": "+10", "detail": "", "icon": "icon_coin"}
		"combo":
			return {"title": "组合强化", "value": "额外伤害 +4", "detail": "同句施放两种不同法术
每句一次", "icon": "icon_fire"}
	return {"title": offer.title, "value": "", "detail": offer.text, "icon": "icon_fire"}

func _confirm() -> void:
	if _busy:
		return
	_busy = true
	if Game.pending_rewards.is_empty():
		if Game.resume_scene == Game.BATTLE_SCENE:
			Game.complete_battle()
		else:
			Game.go_to_map()
	elif Game.claim_reward(_selected):
		Game.go_to_map()
	_busy = false
	_message = Game.save_error
	_rebuild()
