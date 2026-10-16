extends RefCounted
## (v56, the author's video of FTL) The ship fight as it is seen in the world:
## shots of the ships' guns flying (a bright bolt with a trail, a rocket with
## its smoke, an ion orb, a plasma blob), bursting where they land (a flash that
## lights the dark, sparks, bits of hull, smoke), rippling on a shield's bubble,
## or flying past. Only drawn: what a shot does is the server's business (see
## Gunnery._draw_ours, _draw_theirs). WorldView feeds it and draws it on its
## seen-only layer, so it shows only where we look.

const Net := preload("res://src/shared/net.gd")

const COLOURS := {Net.SHOT_CANNON: Color(1.0, 0.45, 0.2), Net.SHOT_ION: Color(0.4, 0.7, 1.0),
	Net.SHOT_ROCKET: Color(1.0, 0.75, 0.35), Net.SHOT_PLASMA: Color(0.45, 1.0, 0.45), Net.SHOT_BEAM: Color(0.9, 0.55, 1.0),
	Net.SHOT_TRACTOR: Color(0.6, 1.0, 0.75), Net.SHOT_SIPHON: Color(0.35, 0.95, 1.0)}
const SHIELD := Color(0.45, 0.8, 1.0)
const TRAIL := 46.0                  # pixels of a bolt's trail
const BEAM_SECONDS := 0.9            # how long a second of a beam is drawn
const BOOM_SECONDS := 0.5            # a burst's flash
const RIPPLE_SECONDS := 0.6
const MAX_BITS := 500

var bolts: Array = []    # [kind, ends, from px, to px, deck, seconds since it was told (negative: not yet), flight seconds, burst]
var booms: Array = []    # [kind, ends, at px, deck, seconds, direction it came from (unit)]
var bits: Array = []     # [at px, speed px/s, seconds left, seconds in all, colour, size, deck, what (BIT_*)]
var _rng := RandomNumberGenerator.new()

enum { BIT_SPARK, BIT_SMOKE, BIT_DEBRIS, BIT_ARC }


func _init() -> void:
	_rng.randomize()


func busy() -> bool:
	return not (bolts.is_empty() and booms.is_empty() and bits.is_empty())


func add(kind: int, ends: int, from: Vector2, to: Vector2, deck: int, delay: float, flight: float) -> void:
	bolts.append([kind, ends, from, to, deck, -delay, flight, false])


func colour(kind: int) -> Color:
	return COLOURS.get(kind, COLOURS[Net.SHOT_CANNON])


static func beam_like(kind: int) -> bool:
	return kind == Net.SHOT_BEAM or kind == Net.SHOT_TRACTOR or kind == Net.SHOT_SIPHON


func update(delta: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Array = bolts[i]
		b[5] += delta
		var t: float = b[5]
		var flight: float = b[6]
		var kind: int = b[0]
		if t < 0.0:
			continue
		if kind == Net.SHOT_ROCKET and t < flight:
			_smoke_trail(b, t / maxf(flight, 0.01))
		if not b[7] and t >= flight:
			b[7] = true
			if int(b[1]) != Net.MISSED:
				_burst(kind, int(b[1]), b[3], int(b[4]), ((b[3] as Vector2) - (b[2] as Vector2)).normalized())
		var stays := BEAM_SECONDS if beam_like(kind) and flight <= 0.0 else 0.15
		if t > flight + stays:
			bolts.remove_at(i)
	for i in range(booms.size() - 1, -1, -1):
		booms[i][4] += delta
		if float(booms[i][4]) > RIPPLE_SECONDS:
			booms.remove_at(i)
	for i in range(bits.size() - 1, -1, -1):
		var p: Array = bits[i]
		p[2] -= delta
		if float(p[2]) <= 0.0:
			bits.remove_at(i)
			continue
		var what: int = p[7]
		p[0] += (p[1] as Vector2) * delta
		var drag := 2.5 if what == BIT_SMOKE else (4.0 if what == BIT_SPARK else 1.6)
		p[1] = (p[1] as Vector2) * maxf(1.0 - drag * delta, 0.0)
		if what == BIT_SMOKE:
			p[5] = float(p[5]) + 10.0 * delta


func _burst(kind: int, ends: int, at: Vector2, deck: int, dir: Vector2) -> void:
	## A shot gets where it was going: a burst, or a ripple on a shield.
	booms.append([kind, ends, at, deck, 0.0, dir])
	if ends == 0:
		for k in 6:
			var v := (-dir).rotated(_rng.randf_range(-1.2, 1.2)) * _rng.randf_range(60.0, 140.0)
			_bit(at, v, _rng.randf_range(0.15, 0.35), SHIELD.lightened(0.4), 1.5, deck, BIT_SPARK)
		return
	if beam_like(kind):
		for k in 4:
			_bit(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40.0, 120.0), _rng.randf_range(0.15, 0.3),
				colour(kind).lightened(0.3), 1.5, deck, BIT_SPARK)
		if kind == Net.SHOT_BEAM:
			_bit(at, Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-20, -8)), 0.9, Color(0.3, 0.28, 0.3, 0.35), 4.0, deck, BIT_SMOKE)
		return
	var c := colour(kind)
	if kind == Net.SHOT_ION:
		for k in 7:
			_bit(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, 40.0), _rng.randf_range(0.25, 0.5), c, 14.0, deck, BIT_ARC)
		return
	var heavy := kind == Net.SHOT_ROCKET
	for k in (22 if heavy else 14):
		# sparks thrown back out the way it came, and every way
		var v := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(80.0, 260.0)
		if _rng.randf() < 0.5:
			v = (-dir).rotated(_rng.randf_range(-0.9, 0.9)) * _rng.randf_range(120.0, 320.0)
		_bit(at, v, _rng.randf_range(0.2, 0.55), Color(1.0, _rng.randf_range(0.6, 0.95), 0.35), _rng.randf_range(1.0, 2.2), deck, BIT_SPARK)
	for k in (8 if heavy else 5):
		_bit(at, Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(30.0, 110.0), _rng.randf_range(0.6, 1.3),
			Color(0.25, 0.25, 0.28), _rng.randf_range(2.0, 3.5), deck, BIT_DEBRIS)
	for k in (6 if heavy else 4):
		_bit(at + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)), Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-24, -4)),
			_rng.randf_range(1.0, 1.9), Color(0.32, 0.3, 0.3, 0.45), _rng.randf_range(5.0, 8.0), deck, BIT_SMOKE)


func _smoke_trail(b: Array, k: float) -> void:
	if _rng.randf() < 0.55:
		var at: Vector2 = (b[2] as Vector2).lerp(b[3], k)
		_bit(at, Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)), _rng.randf_range(0.5, 0.9),
			Color(0.75, 0.75, 0.75, 0.35), 3.0, int(b[4]), BIT_SMOKE)


func _bit(at: Vector2, v: Vector2, life: float, c: Color, size: float, deck: int, what: int) -> void:
	if bits.size() >= MAX_BITS:
		bits.pop_front()
	bits.append([at, v, life, life, c, size, deck, what])


# ---------------------------------------------------------------- drawing

func draw(pen: CanvasItem, deck: int) -> void:
	for p: Array in bits:
		if int(p[6]) != deck:
			continue
		var left := float(p[2]) / float(p[3])
		var c: Color = p[4]
		var at: Vector2 = p[0]
		match int(p[7]):
			BIT_SPARK:
				var v: Vector2 = p[1]
				pen.draw_line(at, at - v * 0.03, Color(c, left), float(p[5]))
			BIT_SMOKE:
				pen.draw_circle(at, float(p[5]), Color(c, c.a * left))
			BIT_DEBRIS:
				var s := float(p[5])
				pen.draw_rect(Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), Color(c, minf(left * 2.0, 1.0)))
			BIT_ARC:
				_jagged(pen, at, float(p[5]), Color(c, left))
	for b: Array in bolts:
		if int(b[4]) == deck and float(b[5]) >= 0.0:
			_draw_bolt(pen, b)
	for m: Array in booms:
		if int(m[3]) == deck:
			_draw_boom(pen, m)


func _draw_bolt(pen: CanvasItem, b: Array) -> void:
	var kind: int = b[0]
	var from: Vector2 = b[2]
	var to: Vector2 = b[3]
	var t: float = b[5]
	var flight: float = b[6]
	var c := colour(kind)
	if flight <= 0.0:
		# a second of a beam: a line that burns, flickering, then fades
		var left := clampf(1.0 - t / BEAM_SECONDS, 0.0, 1.0)
		var w := 2.0 + 1.5 * sin(t * 40.0)
		pen.draw_line(from, to, Color(c, 0.25 * left), w + 6.0)
		pen.draw_line(from, to, Color(c.lightened(0.5), 0.9 * left), w)
		pen.draw_circle(to, 5.0 + 2.0 * sin(t * 33.0), Color(c.lightened(0.6), 0.8 * left))
		return
	var k := clampf(t / flight, 0.0, 1.0)
	var head := from.lerp(to, k)
	var dir := (to - from).normalized()
	var fade := 1.0 if t <= flight else clampf(1.0 - (t - flight) / 0.15, 0.0, 1.0)
	var tail := head - dir * minf(TRAIL, from.distance_to(head))
	match kind:
		Net.SHOT_ROCKET:
			pen.draw_line(head - dir * 9.0, head, Color(0.8, 0.8, 0.82, fade), 4.0)
			pen.draw_circle(head - dir * 10.0, 3.5 + _rng.randf() * 1.5, Color(1.0, 0.7, 0.3, 0.9 * fade))
		Net.SHOT_ION:
			pen.draw_circle(head, 7.0, Color(c, 0.3 * fade))
			pen.draw_circle(head, 4.0, Color(c.lightened(0.6), 0.95 * fade))
			pen.draw_line(tail.lerp(head, 0.5), head, Color(c, 0.4 * fade), 3.0)
			_jagged(pen, head, 8.0, Color(c.lightened(0.4), 0.7 * fade))
		Net.SHOT_PLASMA:
			pen.draw_line(tail.lerp(head, 0.6), head, Color(c, 0.4 * fade), 5.0)
			pen.draw_circle(head, 4.5, Color(c.lightened(0.4), 0.95 * fade))
		_:
			pen.draw_line(tail, head, Color(c, 0.25 * fade), 7.0)
			pen.draw_line(tail.lerp(head, 0.3), head, Color(c.lightened(0.3), 0.9 * fade), 3.0)
			pen.draw_circle(head, 3.0, Color(1.0, 0.95, 0.85, fade))


func _draw_boom(pen: CanvasItem, m: Array) -> void:
	var kind: int = m[0]
	var ends: int = m[1]
	var at: Vector2 = m[2]
	var t: float = m[4]
	var dir: Vector2 = m[5]
	if ends == 0:
		# a ripple on the shield's bubble: arcs bowed against the way it came, spreading out
		var k := clampf(t / RIPPLE_SECONDS, 0.0, 1.0)
		var centre := at + dir * 42.0
		var facing := (-dir).angle()
		for r in 3:
			var radius := 42.0 + (k * 26.0) + r * 7.0
			var alpha := (1.0 - k) * (0.85 - r * 0.25)
			if alpha > 0.0:
				pen.draw_arc(centre, radius, facing - 0.9 + k * 0.2, facing + 0.9 - k * 0.2, 20, Color(SHIELD, alpha), 3.0 - r)
		pen.draw_circle(at, 7.0 * (1.0 - k), Color(SHIELD.lightened(0.5), 0.9 * (1.0 - k)))
		return
	if beam_like(kind):
		return
	if t > BOOM_SECONDS:
		return
	var k := t / BOOM_SECONDS
	var c := colour(kind)
	var size := 34.0 if kind == Net.SHOT_ROCKET else 24.0
	if kind == Net.SHOT_ION:
		pen.draw_circle(at, size * (0.4 + k), Color(c, 0.35 * (1.0 - k)))
		pen.draw_arc(at, size * (0.3 + 1.2 * k), 0.0, TAU, 28, Color(c.lightened(0.4), 0.9 * (1.0 - k)), 2.0)
		return
	pen.draw_circle(at, size * (0.5 + 0.8 * k), Color(c, 0.45 * (1.0 - k)))
	pen.draw_circle(at, size * 0.55 * (1.0 - k), Color(1.0, 0.92, 0.7, 0.95 * (1.0 - k)))
	pen.draw_arc(at, size * (0.4 + 1.6 * k), 0.0, TAU, 28, Color(1.0, 0.8, 0.5, 0.6 * (1.0 - k)), 2.0)


func _jagged(pen: CanvasItem, at: Vector2, size: float, c: Color) -> void:
	## A little crackle of electricity.
	var p := at
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	for i in 3:
		var q := p + dir.rotated(_rng.randf_range(-1.0, 1.0)) * size * 0.5
		pen.draw_line(p, q, c, 1.5)
		p = q


func draw_light(mask: CanvasItem, deck: int) -> void:
	## Bursts and bolts light the dark around them (blue in the light mask, as muzzle flashes do).
	for m: Array in booms:
		if int(m[3]) != deck or int(m[1]) == 0 or float(m[4]) > BOOM_SECONDS * 1.4:
			continue
		var k := float(m[4]) / (BOOM_SECONDS * 1.4)
		mask.draw_circle(m[2], (110.0 if int(m[0]) == Net.SHOT_ROCKET else 80.0) * (1.0 - 0.4 * k), Color(0, 0, 1, 1.0 - k))
	for b: Array in bolts:
		if int(b[4]) != deck or float(b[5]) < 0.0 or float(b[5]) > float(b[6]):
			continue
		var k := clampf(float(b[5]) / maxf(float(b[6]), 0.01), 0.0, 1.0)
		mask.draw_circle((b[2] as Vector2).lerp(b[3], k), 30.0, Color(0, 0, 1, 0.6))
