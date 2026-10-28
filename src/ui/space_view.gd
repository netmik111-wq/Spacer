extends Control
## (v92, the author's plan item 0) The fight in real time, seen from outside: the ships as they fly
## and turn (their drawings from above), their guns turning, shields, shots and beams. Shown at the
## ship's controls in a fight (the pilot steers: W/S, A/D, Q/E, Space), at a gun mount taken by hand
## (the mouse aims, the button fires) and, small, to anyone by V. Everything comes from
## GameClient.arena (ArenaSeen), drawn a little in the past as the others are.

const Net := preload("res://src/shared/net.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")
const FightFx := preload("res://src/client/fight_fx.gd")
const GameClient := preload("res://src/client/game_client.gd")
const ArenaSeen := preload("res://src/client/arena_seen.gd")

const WATCH := 0
const PILOT := 1
const TURRET := 2
const ALL := 3                       # (v93) at the gun console: the mouse aims every gun nobody aims by hand

const RADIUS := 170.0                # as Arena.RADIUS: the fight's edge
const GUN_ARC := PI / 2.0            # as Arena.GUN_ARC
const ARC_HALF := PI * 0.4           # as Arena.ARC_HALF
const OURS := {ArenaShape.FLOOR: Color(0.2, 0.24, 0.27), ArenaShape.WALL: Color(0.5, 0.6, 0.62),
	ArenaShape.PANE: Color(0.45, 0.75, 0.95), ArenaShape.GUN: Color(0.95, 0.82, 0.4)}
const THEIRS := {ArenaShape.FLOOR: Color(0.25, 0.19, 0.19), ArenaShape.WALL: Color(0.66, 0.42, 0.38),
	ArenaShape.PANE: Color(0.85, 0.6, 0.5), ArenaShape.GUN: Color(1.0, 0.55, 0.3)}
const HOW_COLOUR := {Net.LANDED: Color(1.0, 0.6, 0.25), Net.MISSED: Color(0.7, 0.7, 0.7), Net.RICOCHET: Color(0.9, 0.9, 1.0),
	Net.SHOT_DOWN: Color(1.0, 0.95, 0.6), 0: FightFx.SHIELD, Net.HELD: Color(0.75, 0.8, 0.85)}
# (v93, my A4 pick) a word by a shot's end on a hull: went through, the armour held, glanced off
const HOW_WORD := {Net.LANDED: "пробил", Net.HELD: "броня", Net.RICOCHET: "рикошет"}
const WORN_COLOUR := Color(1.0, 0.85, 0.3)        # armour half gone
const BARE_COLOUR := Color(0.95, 0.25, 0.2)       # no armour left

var client: GameClient
var mode := WATCH
var gun := -1                        # (TURRET) the number of our gun at the mount we stand at
var zoom := 3.5                      # pixels a cell
var firing := false                  # (TURRET) the mouse button held
var _mouse := Vector2.ZERO
var _stars := PackedVector3Array()


func setup(p_client: GameClient) -> void:
	client = p_client
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	for i in 160:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.15, 0.6)))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func t_now() -> float:
	return client.render_tick()


func mine() -> int:
	## The body of the ship of ours we are aboard.
	return client.my_fleet


func centre() -> Vector2:
	var s: Dictionary = client.arena.state(mine(), t_now())
	return s["pos"] if not s.is_empty() else Vector2.ZERO


func to_screen(at: Vector2) -> Vector2:
	return (at - centre()) * zoom + size / 2.0


func to_space(at: Vector2) -> Vector2:
	return (at - size / 2.0) / zoom + centre()


func aim_point() -> Vector2:
	## (TURRET) The point of the fight's space under the mouse.
	return to_space(_mouse)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		_mouse = b.position
		if b.button_index == MOUSE_BUTTON_LEFT:
			firing = b.pressed and mode != WATCH     # (v93, the author's P1 note) the pilot fires the free guns too
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom * 1.2, 14.0)
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom / 1.2, 1.5)
		accept_event()


func _draw() -> void:
	var t := t_now()
	var now := Time.get_ticks_msec()
	client.arena.forget(now, t)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.05))
	var c := centre()
	for s: Vector3 in _stars:
		var p := Vector2(posmod(s.x * size.x - c.x * zoom * s.z, size.x), posmod(s.y * size.y - c.y * zoom * s.z, size.y))
		draw_rect(Rect2(p, Vector2(1.5, 1.5)), Color(0.8, 0.85, 1.0, s.z))
	draw_arc(to_screen(Vector2.ZERO), RADIUS * zoom, 0.0, TAU, 96, Color(0.5, 0.3, 0.3, 0.5), 1.5)
	for id: int in client.arena.bodies.keys():
		_draw_ship(id, t)
	for b: Dictionary in client.arena.beams:
		var col: Color = FightFx.COLOURS.get(int(b["kind"]), Color.WHITE)
		draw_line(to_screen(b["from"]), to_screen(b["to"]), Color(col, 0.35), 5.0)
		draw_line(to_screen(b["from"]), to_screen(b["to"]), col.lightened(0.4), 1.5)
	for s: Dictionary in client.arena.shots.values():
		var at: Vector2 = client.arena.shot_at(s, t)
		var col: Color = FightFx.COLOURS.get(int(s["kind"]), Color.WHITE)
		var dir := (s["vel"] as Vector2).normalized()
		draw_line(to_screen(at - dir * 1.6), to_screen(at), col, 2.0 if FightFx.rocket_like(int(s["kind"])) else 1.5)
		draw_circle(to_screen(at), 1.8, col.lightened(0.5))
	for b: Dictionary in client.arena.bursts:
		var k := float(now - int(b["born"])) / ArenaSeen.BURST_MS
		var col: Color = HOW_COLOUR.get(int(b["how"]), Color.WHITE)
		draw_arc(to_screen(b["at"]), (1.0 + 3.0 * k) * zoom * 0.6, 0.0, TAU, 20, Color(col, 1.0 - k), 2.0)
		if HOW_WORD.has(int(b["how"])) and zoom >= 2.5:
			draw_string(ThemeDB.fallback_font, to_screen(b["at"]) + Vector2(6, -6 - 10.0 * k), HOW_WORD[int(b["how"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 1.0 - k))
	_draw_marks(t)
	if mode != WATCH:
		_draw_sight(t)
	_draw_words(t)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.5, 0.6, 0.8), false, 1.0)


func _draw_ship(id: int, t: float) -> void:
	var s: Dictionary = client.arena.state(id, t)
	var shape: RefCounted = client.arena.shape_of(id)
	if s.is_empty() or shape == null:
		return
	var ours := id < 2
	var colours: Dictionary = OURS if ours else THEIRS
	var pos: Vector2 = s["pos"]
	var rot: float = s["rot"]
	if int(s["flags"]) & Net.ARENA_THRUST:
		var back := Vector2(-shape.w / 2.0 - 1.5, 0.0)
		draw_circle(to_screen(pos + back.rotated(rot)), 0.9 * zoom, Color(0.5, 0.75, 1.0, 0.45))
	draw_set_transform(to_screen(pos), rot, Vector2(zoom, zoom))
	var worn: Dictionary = client.arena.armour.get(id, {})
	for y in shape.h:
		for x in shape.w:
			var k: int = shape.kind[y * shape.w + x]
			if k != ArenaShape.EMPTY:
				var col: Color = colours[k]
				if worn.has(y * shape.w + x):
					# (v93) the outer wall coloured by its armour: yellow as it wears, red with none left
					var a: Vector2i = worn[y * shape.w + x]
					var left := float(a.x) / maxf(float(a.y), 1.0)
					col = BARE_COLOUR if a.x <= 0 else WORN_COLOUR.lerp(col, left)
				draw_rect(Rect2(shape.middle(x, y) - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var aims: PackedFloat32Array = s["aims"]
	var gunf: PackedByteArray = s["gunf"]
	for k in aims.size():
		var at: Vector2 = pos + client.arena.gun_spot(id, k).rotated(rot)
		var lit := k < gunf.size() and gunf[k] & 1
		var col := Color(1.0, 0.9, 0.5) if lit else Color(0.7, 0.7, 0.7)
		if ours and id == mine() and k == gun and mode == TURRET:
			col = Color(0.5, 1.0, 0.6)
		draw_line(to_screen(at), to_screen(at + Vector2.from_angle(rot + aims[k]) * 2.2), col, maxf(zoom * 0.35, 1.5))
	var shield: int = s["shield"]
	if shield > 0:
		var r: Vector2 = shape.bubble()
		var pts := PackedVector2Array()
		var arc := (int(s["flags"]) >> Net.ARENA_ARC_SHIFT) & 7      # (v93) 0 a bubble, 1..4 an arc to one side
		var from := 0.0 if arc == 0 else (arc - 1) * PI / 2.0 - ARC_HALF
		var span := TAU if arc == 0 else ARC_HALF * 2.0
		for k in 41:
			var a := from + span * k / 40.0
			pts.append(to_screen(pos + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot)))
		var full := clampf(shield / 100.0, 0.0, 1.0)          # (Weapons.SHIELD_FULL)
		draw_polyline(pts, Color(FightFx.SHIELD, 0.3 + 0.5 * full), (1.5 + 1.5 * full) * (1.0 if arc == 0 else 1.8))


func _draw_marks(t: float) -> void:
	## Ships off the screen: a mark at its edge, pointing to them.
	var rect := Rect2(Vector2(14, 14), size - Vector2(28, 28))
	for id: int in client.arena.bodies.keys():
		var s: Dictionary = client.arena.state(id, t)
		if s.is_empty():
			continue
		var p := to_screen(s["pos"])
		if rect.has_point(p):
			continue
		var dir := (p - size / 2.0).normalized()
		var edge := size / 2.0 + dir * minf(absf((size.x / 2.0 - 16.0) / maxf(absf(dir.x), 0.001)), absf((size.y / 2.0 - 16.0) / maxf(absf(dir.y), 0.001)))
		var col := Color(0.5, 0.9, 0.6) if id < 2 else Color(1.0, 0.45, 0.35)
		draw_colored_polygon(PackedVector2Array([edge + dir * 10.0, edge + dir.orthogonal() * 6.0, edge - dir.orthogonal() * 6.0]), col)
		var far: float = ((s["pos"] as Vector2) - centre()).length()
		draw_string(ThemeDB.fallback_font, edge - dir * 22.0 - Vector2(10, -4), "%d" % roundi(far), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_sight(t: float) -> void:
	## (TURRET) The arc our gun turns through, and the mark under the mouse.
	var s: Dictionary = client.arena.state(mine(), t)
	if s.is_empty():
		return
	if gun < 0:
		# (v93) the pilot or the gun console: the mark alone (every free gun turns to it as far as its arc lets it)
		var c := Color(1.0, 0.9, 0.4) if firing else Color(0.6, 1.0, 0.7, 0.8)
		draw_arc(_mouse, 7.0, 0.0, TAU, 20, c, 1.5)
		draw_line(_mouse - Vector2(12, 0), _mouse - Vector2(4, 0), c, 1.5)
		draw_line(_mouse + Vector2(4, 0), _mouse + Vector2(12, 0), c, 1.5)
		draw_line(_mouse - Vector2(0, 12), _mouse - Vector2(0, 4), c, 1.5)
		draw_line(_mouse + Vector2(0, 4), _mouse + Vector2(0, 12), c, 1.5)
		return
	var rot: float = s["rot"]
	var at: Vector2 = to_screen((s["pos"] as Vector2) + client.arena.gun_spot(mine(), gun).rotated(rot))
	var out: float = rot + client.arena.gun_out(mine(), gun)
	draw_arc(at, 120.0, out - GUN_ARC, out + GUN_ARC, 32, Color(0.5, 1.0, 0.6, 0.25), 1.0)
	draw_line(at, at + Vector2.from_angle(out - GUN_ARC) * 40.0, Color(0.5, 1.0, 0.6, 0.35), 1.0)
	draw_line(at, at + Vector2.from_angle(out + GUN_ARC) * 40.0, Color(0.5, 1.0, 0.6, 0.35), 1.0)
	var rel := wrapf((_mouse - at).angle() - out, -PI, PI)
	var col := Color(1.0, 0.4, 0.3) if absf(rel) > GUN_ARC else (Color(1.0, 0.9, 0.4) if firing else Color(0.6, 1.0, 0.7))
	draw_arc(_mouse, 9.0, 0.0, TAU, 20, col, 1.5)
	draw_line(_mouse - Vector2(14, 0), _mouse - Vector2(5, 0), col, 1.5)
	draw_line(_mouse + Vector2(5, 0), _mouse + Vector2(14, 0), col, 1.5)
	draw_line(_mouse - Vector2(0, 14), _mouse - Vector2(0, 5), col, 1.5)
	draw_line(_mouse + Vector2(0, 5), _mouse + Vector2(0, 14), col, 1.5)


func _draw_words(t: float) -> void:
	var font := ThemeDB.fallback_font
	var s: Dictionary = client.arena.state(mine(), t)
	var lines: Array[String] = []
	if not s.is_empty():
		var speed: float = (s["vel"] as Vector2).length()
		lines.append("Скорость: %.1f" % speed)
	if mode == PILOT:
		lines.append("W/S — ход, A/D — поворот, Q/E — вбок, Пробел — уклонение, Esc — отойти")
		lines.append("Мышь — прицел, левая кнопка — огонь орудиями без своего стрелка")
	elif mode == ALL:
		lines.append("Мышь — прицел, левая кнопка — огонь орудиями без своего стрелка, Tab — пульт орудий")
	elif mode == TURRET:
		lines.append("Мышь — прицел, левая кнопка — огонь, колесо — масштаб, E или Esc — отойти")
	var y := 18.0
	for line in lines:
		draw_string(font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 0.8))
		y += 17.0

