extends RefCounted
## The plan of the pirate ship we fight, as the gun console and the drone
## monitor show it (v54: drawn here for both). Room by room, each coloured by
## how worn the system in it is; rooms not scanned yet show a question mark;
## the room the guns aim at has sights on it; holes in its hull are crosses.
## On top (v54): its crew where we can see them (after a probe, or near our
## drone; red, a white ring while mending, dim while wounded) and our drone.

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
	if client.ecrew_probe > 0:
		canvas.draw_string(font, Vector2(6, 14), "Зонд показывает экипаж: ещё %d с" % client.ecrew_probe, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PIRATE.lightened(0.3))
