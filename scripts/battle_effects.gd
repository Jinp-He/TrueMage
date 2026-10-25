extends Node2D
## Procedural effects use fixed geometry, never the gameplay random generator.
var _aura: Mark

class Mark:
	extends Node2D
	var kind := "burst"
	var tint := Color("ff943d")
	var progress := 0.0
	var radius := 26.0
	var clock := 0.0
	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()
	func _draw() -> void:
		if kind == "aura":
			for i in 3:
				var at := Vector2.from_angle(clock * 1.5 + i * TAU / 3.0) * 36
				draw_circle(at, 7, Color(tint,0.3))
				draw_circle(at, 3, tint)
		elif kind == "bolt":
			draw_line(Vector2(-radius * 2.8, 0), Vector2.ZERO, Color(tint, 0.35), radius * 1.3, true)
			draw_circle(Vector2.ZERO, radius, Color("38233b"))
			draw_circle(Vector2.ZERO, radius * 0.8, tint)
			draw_circle(Vector2(radius * 0.2, 0), radius * 0.4, Color("fff3b0"))
		elif kind == "shield":
			var points := PackedVector2Array([Vector2(-60,-52),Vector2(0,-70),Vector2(60,-52),Vector2(48,22),Vector2(0,62),Vector2(-48,22),Vector2(-60,-52)])
			draw_colored_polygon(points, Color(tint, 0.18))
			draw_polyline(points, Color("283447"), 10, true)
			draw_polyline(points, tint, 5, true)
			draw_line(Vector2(0,-48),Vector2(0,36),Color(tint,0.5),3,true)
		else:
			var r := radius * (0.4 + progress * 1.7)
			draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(tint, 1.0-progress), 5, true)
			for i in 8:
				var direction := Vector2.from_angle(i * TAU / 8.0)
				draw_line(direction*r, direction*(r+14*(1-progress)), Color(tint,1-progress),4,true)

class Silhouette:
	extends Node2D
	var tint := Color("675080")
	func _draw() -> void:
		draw_set_transform(Vector2(0,132),0,Vector2(1,0.22))
		draw_circle(Vector2.ZERO,95,Color(0,0,0,0.35))
		draw_set_transform(Vector2.ZERO)
		var robe := PackedVector2Array([Vector2(-45,-70),Vector2(45,-70),Vector2(60,12),Vector2(94,120),Vector2(0,138),Vector2(-94,120),Vector2(-60,12),Vector2(-45,-70)])
		draw_colored_polygon(robe,tint)
		draw_polyline(robe,Color("211c2b"),8,true)
		draw_circle(Vector2(0,-60),55,Color("211c2b"))
		draw_arc(Vector2(0,-60),57,PI,TAU,24,tint.lightened(0.25),10,true)
		for x in [-19,19]:
			draw_circle(Vector2(x,-60),7,Color("f8d97c"))
		draw_line(Vector2(76,-95),Vector2(76,110),Color("211c2b"),12,true)
		draw_line(Vector2(76,-95),Vector2(76,110),Color("b1946c"),5,true)
		draw_circle(Vector2(76,-105),16,tint.lightened(0.4))

func mark(kind: String, at: Vector2, tint: Color, radius: float = 26.0) -> Mark:
	var node := Mark.new()
	node.kind = kind
	node.position = at
	node.tint = tint
	node.radius = radius
	add_child(node)
	return node

func burst(at: Vector2, tint: Color, radius: float = 30.0) -> void:
	var node := mark("burst", at, tint, radius)
	var tween := create_tween()
	tween.tween_property(node,"progress",1.0,0.32)
	tween.tween_callback(node.queue_free)

func bolt(from: Vector2, to: Vector2, tint: Color, heavy: bool = false, bend: bool = false) -> void:
	var node := mark("bolt", from, tint, 23 if heavy else 10)
	node.rotation = (to-from).angle()
	var tween := create_tween()
	if bend:
		tween.tween_property(node,"position",from.lerp(to,0.5)+Vector2(0,-55),0.14)
	tween.tween_property(node,"position",to,0.32 if heavy else 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	node.queue_free()
	burst(to,tint,48 if heavy else 22)

func shield(at: Vector2, tint: Color = Color("8ddfff")) -> void:
	var node := mark("shield",at,tint)
	node.scale = Vector2.ONE * 0.35
	var tween := create_tween()
	tween.tween_property(node,"scale",Vector2.ONE,0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.18)
	tween.tween_property(node,"modulate:a",0.0,0.25)
	tween.tween_callback(node.queue_free)

func hit(target: Control) -> void:
	var home := target.position
	var tween := create_tween()
	tween.tween_property(target,"modulate",Color(1.8,1.25,1.05),0.05)
	tween.parallel().tween_property(target,"position",home+Vector2(9,0),0.05)
	tween.tween_property(target,"modulate",Color.WHITE,0.16)
	tween.parallel().tween_property(target,"position",home,0.16)
	await tween.finished

func enemy_attack(target: Control, destination: Vector2, blocked: bool, shielded: bool = false) -> void:
	var home := target.position
	var tween := create_tween()
	tween.tween_property(target,"position",home+Vector2(16,-8),0.16)
	tween.tween_property(target,"position",home+Vector2(-30,0),0.12)
	await tween.finished
	await bolt(home+Vector2(0,20),destination,Color("c6a0ee"))
	if shielded or blocked:
		shield(destination)
	if not blocked:
		burst(destination,Color("ff7669"),40)
	tween = create_tween()
	tween.tween_property(target,"position",home,0.16)
	await tween.finished

func defeat(target: Control) -> void:
	burst(target.position,Color("e7be76"),72)
	var tween := create_tween().set_parallel()
	tween.tween_property(target,"modulate:a",0.0,0.45)
	tween.tween_property(target,"position:y",target.position.y+50,0.45)
	tween.tween_property(target,"scale",Vector2(0.8,0.7),0.45)
	await tween.finished


func set_affinity(value: int, at: Vector2) -> void:
	if value <= 0:
		if is_instance_valid(_aura):
			_aura.queue_free()
			_aura = null
		return
	if not is_instance_valid(_aura):
		_aura = mark("aura",at,Color("ffbd55"))
	_aura.modulate.a = minf(1.0,0.5+0.1*value)
