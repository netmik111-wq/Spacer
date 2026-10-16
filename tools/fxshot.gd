extends SceneTree
## (v56) A picture of the ship fight's effects (FightFx) at a few moments, for
## looking at them without a fight: godot --path . --script res://tools/fxshot.gd -- OUT.png

const FightFx := preload("res://src/client/fight_fx.gd")
const Net := preload("res://src/shared/net.gd")

var _vp: SubViewport
var _pen: Node2D
var _fx: Array = []
var _frames := 0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1200, 400)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_vp)
	_pen = Node2D.new()
	_pen.draw.connect(_paint)
	_vp.add_child(_pen)
	# four panels: a laser bursting, a rocket bursting, a shot on a shield, an ion hit and a beam
	var cases := [[Net.SHOT_CANNON, Net.LANDED, 0.55], [Net.SHOT_CANNON, Net.LANDED, 0.85], [Net.SHOT_ROCKET, Net.LANDED, 1.45],
		[Net.SHOT_CANNON, 0, 0.75], [Net.SHOT_ION, Net.LANDED, 0.95], [Net.SHOT_BEAM, Net.LANDED, 0.3]]
	for i in cases.size():
		var f := FightFx.new()
		var c: Array = cases[i]
		var at := Vector2(100 + i * 200, 200)
		var flight := 0.0 if c[0] == Net.SHOT_BEAM else (1.3 if c[0] == Net.SHOT_ROCKET else 0.7)
		f.add(c[0], c[1], at + Vector2(-60, -170), at, 0, 0.0, flight)
		var t := 0.0
		while t < float(c[2]):
			f.update(1.0 / 60.0)
			t += 1.0 / 60.0
		_fx.append(f)


func _paint() -> void:
	_pen.draw_rect(Rect2(0, 0, 1200, 400), Color(0.05, 0.05, 0.08))
	for i in 6:
		_pen.draw_rect(Rect2(40 + i * 200, 200, 120, 80), Color(0.35, 0.37, 0.4))
		(_fx[i] as FightFx).draw(_pen, 0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://fx.png"
		_vp.get_texture().get_image().save_png(out)
		return true
	return false
