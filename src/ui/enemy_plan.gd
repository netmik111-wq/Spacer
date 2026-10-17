extends RefCounted
## The plan of the pirate ship we fight, as the gun console and the drone
## monitor show it (v54: drawn here for both). Room by room, each coloured by
## how worn the system in it is; rooms not scanned yet show a question mark;
## the room the guns aim at has sights on it; holes in its hull are crosses.
## On top (v54): its crew where we can see them (after a probe, or near our
## drone; red, a white ring while mending, dim while wounded) and our drone.
## (v56, the author's video of FTL) Its shield's bubble while it is up, and the
## shots of the fight: ours flying in from the left to burst in a room, ripple
## on the bubble or fly past ("ПРОМАХ"); its own leaving its weapons room.

const Net := preload("res://src/shared/net.gd")
const Gunnery := preload("res://src/server/gunnery.gd")    # only for its numbers

const UNKNOWN := Color(0.22, 0.26, 0.34)
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const GOOD := Color(0.4, 0.8, 0.5)
const WARN := Color(0.95, 0.72, 0.28)
const BAD := Color(0.92, 0.32, 0.28)
const AIM := Color(1.0, 0.92, 0.35)
const ION := Color(0.45, 0.7, 1.0)
const PIRATE := Color(0.95, 0.25, 0.2)
const DRONE := Color(0.35, 0.95, 1.0)
const SHIELD := Color(0.45, 0.8, 1.0)
const FightFx := preload("res://src/client/fight_fx.gd")
const BOOM_SECONDS := 0.6            # a burst on the plan
const MISS_SECONDS := 1.1            # "ПРОМАХ" floats up this long


static func fighting(client) -> bool:
	return client.enemy_full > 0 and client.enemy_sys.size() == Net.ESYS_COUNT


static func layout(client, size: Vector2) -> Array:
	## [the enemy's drawing (ShipMap), cell size, where its corner goes on the plan].
	var o = client.map.other if client.pirates_alongside() else null
	if o == null:
		return [null, 0.0, Vector2.ZERO]
	var px := floorf(minf(size.x / o.width, size.y / o.height))
	return [o, px, (size - Vector2(o.width, o.height) * px) / 2.0]


static func room_at_local(o, local: int) -> int:
	return o.room_of[local] if local >= 0 and local < o.room_of.size() else -1


static func room_at(client, size: Vector2, at: Vector2) -> int:
	## The room of the plan at that point, or -1.
	var lay := layout(client, size)
	var o = lay[0]
	if o == null or float(lay[1]) <= 0.0:
		return -1
	var v: Vector2 = (at - (lay[2] as Vector2)) / float(lay[1])
	if v.x < 0 or v.y < 0 or v.x >= o.width or v.y >= o.height:
		return -1
	return room_at_local(o, int(v.y) * o.width + int(v.x))


static func state(client, which: int) -> String:
	var left: int = client.enemy_sys[which]
	if client.enemy_sys_full[which] == 0:
		return "нет"
	if which == Net.ESYS_CREW:
		return "%d чел." % ((left + Gunnery.HITS_PER_BOARDER - 1) / Gunnery.HITS_PER_BOARDER)
	if left > 0 and which < client.enemy_sys_out.size() and client.enemy_sys_out[which] > 0:
		return "выкл. %d с" % client.enemy_sys_out[which]
	return "выбит" if left == 0 else "%d/%d" % [left, client.enemy_sys_full[which]]


static func draw(canvas: Control, client, size: Vector2, time: float, hover_room: int, aimed: int, drone_room: int = -1) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.05))
	var lay := layout(client, size)
	var o = lay[0]
	if o == null or not fighting(client) or client.enemy_rooms.size() != o.rooms.size():
		canvas.draw_string(font, Vector2(0, size.y / 2.0 + 6), "Нет цели", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, DIM)
		return
	var px: float = lay[1]
	var at: Vector2 = lay[2]
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	for y in o.height:
		for x in o.width:
			var local: int = y * o.width + x
			if o.cells[local] < 0:
				continue
			var r := Rect2(at + Vector2(x, y) * px, Vector2(px, px))
			if o.walk[local] == 0:
				canvas.draw_rect(r, Color(0.25, 0.3, 0.3))
				continue
			var room := room_at_local(o, local)
			var c := Color(0.12, 0.16, 0.16)
			if room >= 0:
				var z: int = client.enemy_rooms[room]
				if z == Net.ROOM_UNKNOWN:
					c = UNKNOWN
				elif z < Net.ESYS_COUNT:
					var share := float(client.enemy_sys[z]) / maxf(client.enemy_sys_full[z], 1.0)
					c = (GOOD if share >= 1.0 else (WARN if share > 0.0 else BAD)).darkened(0.55)
					if client.enemy_sys_full[z] == 0:
						c = Color(0.16, 0.18, 0.2)              # (no shield generator in it)
					elif z < client.enemy_sys_out.size() and client.enemy_sys_out[z] > 0:
						c = ION.darkened(0.5)                     # put out by ion or EMP for now
				if room == hover_room:
					c = c.lightened(0.25)
				if room == drone_room:
					c = c.lerp(DRONE, 0.12)
			canvas.draw_rect(r.grow(-1.0), c)
	# the rooms' names (or what we do not know yet) and the sights on the room aimed at
	for k in o.rooms.size():
		var cells: PackedInt32Array = o.rooms[k]
		if cells.is_empty():
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for local in cells:
			var v := Vector2(local % o.width, local / o.width)
			lo = lo.min(v)
			hi = hi.max(v + Vector2.ONE)
		var box := Rect2(at + lo * px, (hi - lo) * px)
		var z: int = client.enemy_rooms[k]
		var name := "?" if z == Net.ROOM_UNKNOWN else ("пусто" if z >= Net.ESYS_COUNT else Net.ESYS_NAMES[z])
		var fsize := 13
		while fsize > 9 and font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > box.size.x - 2.0:
			fsize -= 1
		if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > box.size.x - 2.0:
			name = "Прыжок" if z == Net.ESYS_JUMP else name.left(3)   # (a small room: a short name)
			if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > box.size.x - 2.0:
				name = name.left(1)
		canvas.draw_string(font, box.position + Vector2(0, box.size.y / 2.0 - 2), name, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fsize,
			DIM if z == Net.ROOM_EMPTY else INK)
		if z < Net.ESYS_COUNT:
			canvas.draw_string(font, box.position + Vector2(0, box.size.y / 2.0 + 14), state(client, z), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 11, INK)
		if k == aimed:
			var aim := Color(AIM, 0.5 + 0.5 * pulse)
			canvas.draw_rect(box.grow(2.0), aim, false, 2.0)
			var mid := box.get_center()
			var rad := minf(box.size.x, box.size.y) * 0.35
			canvas.draw_arc(mid, rad, 0.0, TAU, 32, aim, 1.5)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				canvas.draw_line(mid + d * rad * 0.6, mid + d * rad * 1.3, aim, 1.5)
	# holes in its hull, where we have seen them
	for y in o.height:
		for x in o.width:
			var cell: int = (client.map.other_at.y + y) * client.map.width + client.map.other_at.x + x
			if client.holes.has(cell):
				var mid := at + (Vector2(x, y) + Vector2(0.5, 0.5)) * px
				canvas.draw_line(mid - Vector2(4, 4), mid + Vector2(4, 4), BAD, 2.0)
				canvas.draw_line(mid - Vector2(4, -4), mid + Vector2(4, -4), BAD, 2.0)
	# its crew, where we see them
	for i in client.ecrew.size():
		var c: int = client.ecrew[i]
		var mid := at + (Vector2(c % o.width, c / o.width) + Vector2(0.5, 0.5)) * px
		var f: int = client.ecrew_flags[i]
		var colour := PIRATE.darkened(0.45) if f & Net.ECREW_HURT else PIRATE
		canvas.draw_circle(mid, maxf(px * 0.28, 3.0), Color(0, 0, 0, 0.7))
		canvas.draw_circle(mid, maxf(px * 0.22, 2.5), colour)
		if f & Net.ECREW_MENDING:
			canvas.draw_arc(mid, maxf(px * 0.36, 4.0), time * 4.0, time * 4.0 + PI * 1.3, 12, Color(1, 1, 1, 0.85), 1.5)
	# our drone
	if client.drone_state == Net.DRONE_INSIDE:
		var d: int = client.drone_at
		var mid := at + (Vector2(d % o.width, d / o.width) + Vector2(0.5, 0.5)) * px
		var s := maxf(px * 0.3, 4.0)
		canvas.draw_rect(Rect2(mid - Vector2(s, s) * 0.6, Vector2(s, s) * 1.2), Color(0, 0, 0, 0.7))
		canvas.draw_rect(Rect2(mid - Vector2(s, s) * 0.45, Vector2(s, s) * 0.9), DRONE)
		canvas.draw_arc(mid, s * 1.6, 0.0, TAU, 20, Color(DRONE, 0.35 + 0.35 * pulse), 1.5)
	_draw_fight(canvas, client, o, px, at, size, font)
	if client.ecrew_probe > 0:
		canvas.draw_string(font, Vector2(6, 14), "Зонд показывает экипаж: ещё %d с" % client.ecrew_probe, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PIRATE.lightened(0.3))


static func _bubble(o, px: float, at: Vector2) -> Array:
	## Its shield's bubble on the plan: [centre, radii].
	var r := Vector2(o.width, o.height) * px * 0.5
	return [at + r, r + Vector2(px * 0.9, px * 0.9)]


static func _ellipse(canvas: Control, centre: Vector2, radii: Vector2, colour: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 49:
		points.append(centre + Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * radii)
	canvas.draw_polyline(points, colour, width, true)


static func _room_point(o, px: float, at: Vector2, room: int, seed: int) -> Vector2:
	## A cell of that room on the plan, picked by the shot's own number (or the middle of the ship).
	if room < 0 or room >= o.rooms.size() or (o.rooms[room] as PackedInt32Array).is_empty():
		return at + Vector2(o.width, o.height) * px * 0.5
	var cells: PackedInt32Array = o.rooms[room]
	var local: int = cells[absi(seed) % cells.size()]
	return at + (Vector2(local % o.width, local / o.width) + Vector2(0.5, 0.5)) * px


static func _draw_fight(canvas: Control, client, o, px: float, at: Vector2, size: Vector2, font: Font) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var b := _bubble(o, px, at)
	var centre: Vector2 = b[0]
	var radii: Vector2 = b[1]
	# the bubble flares where a shot of ours meets it
	var flare := 0.0
	for v: Array in client.volleys:
		if int(v[0]) == Net.VOLLEY_OURS and int(v[2]) == 0:
			var since := now - float(v[4]) - float(v[5])
			if since >= 0.0 and since < BOOM_SECONDS:
				flare = maxf(flare, 1.0 - since / BOOM_SECONDS)
	if client.enemy_shield > 0 or flare > 0.0:
		var strength := clampf(client.enemy_shield / 100.0, 0.0, 1.0)
		_ellipse(canvas, centre, radii, Color(SHIELD, 0.12 + 0.25 * strength + 0.6 * flare), 1.5 + 2.5 * flare)
	for v: Array in client.volleys:
		var whose: int = v[0]
		var kind: int = v[1]
		var ends: int = v[2]
		var room: int = v[3]
		var t := now - float(v[4])
		var flight: float = v[5]
		var seed: int = v[6]
		if t < 0.0:
			continue
		var colour: Color = FightFx.COLOURS.get(kind, FightFx.COLOURS[Net.SHOT_CANNON])
		if whose == Net.VOLLEY_THEIRS:
			# its shot leaves its weapons room for the left edge (where we are)
			if t > flight * 0.6:
				continue
			var from := _room_point(o, px, at, room, seed)
			var to := Vector2(-10.0, from.y + float(seed % 40 - 20))
			var k := t / (flight * 0.6)
			if k < 0.25:
				canvas.draw_circle(from, px * 0.5 * (1.0 - k * 4.0) + 2.0, Color(colour.lightened(0.4), 0.9 * (1.0 - k * 4.0)))
			_bolt(canvas, kind, from, to, k, colour)
			continue
		var target := _room_point(o, px, at, room, seed)
		var from := Vector2(-10.0, clampf(target.y + float(seed % 80 - 40), 4.0, size.y - 4.0))
		var to := target
		if ends == 0:
			to = _bubble_entry(from, target, centre, radii)
		elif ends == Net.MISSED:
			to = target + (target - from).normalized() * size.x
		elif ends == Net.SHOT_DOWN:
			to = from.lerp(target, 0.75)          # (v58) their point defence caught it on the way
		if FightFx.beam_like(kind):
			# a second of a beam: a line burning in
			if t <= flight:
				var w := 2.0 + sin(t * 40.0)
				canvas.draw_line(from, to, Color(colour, 0.3), w + 5.0)
				canvas.draw_line(from, to, Color(colour.lightened(0.5), 0.9), w)
				canvas.draw_circle(to, 4.0 + 2.0 * sin(t * 30.0), colour.lightened(0.6))
			continue
		var reach := flight if ends != Net.MISSED else flight * 1.6
		if t < reach:
			_bolt(canvas, kind, from, to, t / reach if ends == Net.MISSED else t / flight, colour)
		var since := t - flight
		if since < 0.0:
			continue
		if ends == Net.LANDED and since < BOOM_SECONDS:
			var k := since / BOOM_SECONDS
			if room >= 0 and room < o.rooms.size():
				for local: int in o.rooms[room]:
					canvas.draw_rect(Rect2(at + Vector2(local % o.width, local / o.width) * px, Vector2(px, px)), Color(1.0, 0.3, 0.15, 0.35 * (1.0 - k)))
			var big := px * (1.4 if FightFx.heavy(kind) else 1.0)
			canvas.draw_circle(target, big * (0.4 + 0.8 * k), Color(colour, 0.5 * (1.0 - k)))
			canvas.draw_circle(target, big * 0.45 * (1.0 - k), Color(1.0, 0.92, 0.7, 1.0 - k))
			canvas.draw_arc(target, big * (0.3 + 1.4 * k), 0.0, TAU, 24, Color(1.0, 0.8, 0.5, 0.7 * (1.0 - k)), 2.0)
		elif ends == 0 and since < BOOM_SECONDS:
			var k := since / BOOM_SECONDS
			canvas.draw_circle(to, px * 0.6 * (1.0 - k) + 1.0, Color(SHIELD.lightened(0.5), 1.0 - k))
		elif (ends == Net.MISSED or ends == Net.RICOCHET or ends == Net.SHOT_DOWN) and since < MISS_SECONDS:
			var k := since / MISS_SECONDS
			var word: String = {Net.MISSED: "ПРОМАХ", Net.RICOCHET: "РИКОШЕТ", Net.SHOT_DOWN: "СБИТА"}[ends]
			if ends == Net.SHOT_DOWN and k < 0.4:
				canvas.draw_circle(to, px * (0.4 + k), Color(1.0, 0.8, 0.5, 0.7 * (1.0 - k / 0.4)))
			var spot := (to if ends == Net.SHOT_DOWN else target) + Vector2(-40.0, -10.0 - 22.0 * k)
			canvas.draw_string(font, spot + Vector2(1, 1), word, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 14, Color(0, 0, 0, 0.8 * (1.0 - k)))
			canvas.draw_string(font, spot, word, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 14, Color(1.0, 1.0, 1.0, 1.0 - k * k))


static func _bolt(canvas: Control, kind: int, from: Vector2, to: Vector2, k: float, colour: Color) -> void:
	var head := from.lerp(to, clampf(k, 0.0, 1.0))
	var dir := (to - from).normalized()
	var tail := head - dir * minf(26.0, from.distance_to(head))
	match kind:
		Net.SHOT_ROCKET, Net.SHOT_HEAVY_ROCKET:
			canvas.draw_line(tail, head, Color(0.8, 0.8, 0.8, 0.35), 4.0)
			canvas.draw_line(head - dir * 6.0, head, Color(0.85, 0.85, 0.9), 3.0)
			canvas.draw_circle(head - dir * 7.0, 2.5, Color(1.0, 0.7, 0.3))
		Net.SHOT_ION, Net.SHOT_STORM, Net.SHOT_NOVA:
			canvas.draw_circle(head, 5.0, Color(colour, 0.35))
			canvas.draw_circle(head, 3.0, colour.lightened(0.5))
		Net.SHOT_SHELL, Net.SHOT_FLAK:
			canvas.draw_line(head - dir * 8.0, head, colour, 2.0)
		_:
			canvas.draw_line(tail, head, Color(colour, 0.3), 5.0)
			canvas.draw_line(tail.lerp(head, 0.4), head, colour.lightened(0.3), 2.0)
			canvas.draw_circle(head, 2.0, Color(1.0, 0.95, 0.85))


static func _bubble_entry(from: Vector2, to: Vector2, centre: Vector2, radii: Vector2) -> Vector2:
	var p := from
	var step := (to - from).normalized() * 2.0
	for i in roundi(from.distance_to(to) / 2.0):
		if ((p - centre) / radii).length_squared() <= 1.0:
			return p
		p += step
	return to
