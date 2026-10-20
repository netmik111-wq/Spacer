extends RefCounted
## What light and sight can reach. Walls and the things on them stop both,
## and so do shut doors; windows and open doors let them through. Everything
## here works cell by cell on one deck, the way Space Station 13 lights its
## tiles. Shared, so that the server (for whoever has to see something: the
## crew, later enemies) and the client (for what it draws) agree.

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Doors := preload("res://src/shared/doors.gd")


static func blocks(map: ShipMap, doors: Doors, x: int, y: int) -> bool:
	## Does this cell stop light and sight?
	if x < 0 or y < 0 or x >= map.width or y >= map.height:
		return true
	var i := y * map.width + x
	if map.opaque[i] == 1:
		return true
	var d := map.door_of[i]
	return d >= 0 and doors.ready.size() > d and doors.is_shut(d)


static func clear_line(map: ShipMap, doors: Doors, from: Vector2i, to: Vector2i) -> bool:
	## Is the straight line between the middles of two cells free? The two
	## cells themselves do not count: a lit wall is the end of a clear line.
	var d := Vector2(to - from)
	var steps := int(ceilf(d.length() * 4.0))
	for k in range(1, steps):
		var at := Vector2(from) + d * (float(k) / steps)
		var c := Vector2i(roundi(at.x), roundi(at.y))
		if c == from or c == to:
			continue
		if blocks(map, doors, c.x, c.y):
			return false
	return true


static func clear_cached(map: ShipMap, doors: Doors, from: Vector2i, to: Vector2i, lines: Dictionary) -> bool:
	## clear_line, with what the line passes through remembered in `lines`: the
	## walls in its way never change while the ship keeps its shape, so only the
	## doors it crosses are looked at again. Whoever keeps `lines` empties it when
	## the ship changes shape (another ship comes, goes or docks).
	var key := (from.y * map.width + from.x) * map.cells.size() + to.y * map.width + to.x
	var crossed: Variant = lines.get(key)
	if crossed == null:
		crossed = _crossed(map, from, to)
		lines[key] = crossed
	for d: int in crossed:
		if d < 0 or (doors.ready.size() > d and doors.is_shut(d)):
			return false
	return true


static func _crossed(map: ShipMap, from: Vector2i, to: Vector2i) -> PackedInt32Array:
	## The doors the straight line between two cells passes through (as clear_line
	## walks it), or [-1] if a wall stops it.
	var out := PackedInt32Array()
	var d := Vector2(to - from)
	var steps := int(ceilf(d.length() * 4.0))
	for k in range(1, steps):
		var at := Vector2(from) + d * (float(k) / steps)
		var c := Vector2i(roundi(at.x), roundi(at.y))
		if c == from or c == to:
			continue
		if c.x < 0 or c.y < 0 or c.x >= map.width or c.y >= map.height or map.opaque[c.y * map.width + c.x] == 1:
			return PackedInt32Array([-1])
		var door := map.door_of[c.y * map.width + c.x]
		if door >= 0 and not out.has(door):
			out.append(door)
	return out


static func cone(map: ShipMap, doors: Doors, origin: Vector2, facing: int, width_deg: float, reach: int) -> Dictionary:
	## The cells a light (or a look) from `origin` (in cells; the middle of a
	## cell is a whole number) facing that way reaches: cell -> how strongly,
	## 1.0 near and less further off. The cone is `width_deg` wide and `reach`
	## cells long, and stays on the deck it starts on.
	var out := {}
	if facing < 1 or facing > Net.DIRS:
		return out
	var from := Vector2i(roundi(origin.x), roundi(origin.y))
	if from.x < 0 or from.y < 0 or from.x >= map.width or from.y >= map.height:
		return out
	var deck := map.deck_of(from.y)
	var top := deck * map.deck_stride
	var bottom := top + map.deck_height - 1
	var ahead := Net.way(facing)
	var half := deg_to_rad(width_deg * 0.5)
	for y in range(maxi(from.y - reach, top), mini(from.y + reach, bottom) + 1):
		for x in range(maxi(from.x - reach, 0), mini(from.x + reach, map.width - 1) + 1):
			var cell := y * map.width + x
			if map.cells[cell] < 0:
				continue
			var v := Vector2(x, y) - origin
			var dist := v.length()
			if dist > reach + 0.5:
				continue
			if dist > 0.75:
				# a cell counts when any of it is inside the cone, not only its middle
				if absf(ahead.angle_to(v)) > half + atan(0.5 / dist):
					continue
				if not clear_line(map, doors, from, Vector2i(x, y)):
					continue
			out[cell] = clampf(1.0 - dist / (reach + 1.0) * 0.65, 0.0, 1.0)
	return out


static func glow(map: ShipMap, doors: Doors, origin: Vector2, facing: int, radius: float, ahead: float) -> Dictionary:
	## A soft round pool of light, the way a flashlight lights in Space Station 13
	## (v46, the author's screenshot): brightest around a spot `ahead` cells in
	## front of `origin` (in cells; it may lie between cells), fading to nothing
	## `radius` cells from that spot. Only cells with a clear line from the
	## holder's own cell get any, so walls and shut doors cast shadows; the
	## first wall is lit on its face. Stays on the deck it starts on.
	## cell -> how strongly, 0..1.
	var out := {}
	var from := Vector2i(roundi(origin.x), roundi(origin.y))
	if from.x < 0 or from.y < 0 or from.x >= map.width or from.y >= map.height:
		return out
	var deck := map.deck_of(from.y)
	var top := deck * map.deck_stride
	var bottom := top + map.deck_height - 1
	var mid := origin
	if facing >= 1 and facing <= Net.DIRS and ahead > 0.0:
		# the spot moves ahead until a wall: facing a wall, the light pools at its face
		var way := Net.way(facing)
		var gone := 0.0
		while gone < ahead:
			var step := minf(0.5, ahead - gone)
			var next := mid + way * step
			if blocks(map, doors, roundi(next.x), roundi(next.y)):
				break
			mid = next
			gone += step
	var r := ceili(radius)
	var c := Vector2i(roundi(mid.x), roundi(mid.y))
	var walls: Array[Vector2i] = []
	for y in range(maxi(c.y - r, top), mini(c.y + r, bottom) + 1):
		for x in range(maxi(c.x - r, 0), mini(c.x + r, map.width - 1) + 1):
			var cell := y * map.width + x
			if map.cells[cell] < 0:
				continue
			var d := Vector2(x, y).distance_to(mid)
			if d >= radius:
				continue
			var here := Vector2i(x, y)
			if here != from and blocks(map, doors, x, y):
				walls.append(here)
				continue
			if here != from and not clear_line(map, doors, from, here):
				continue
			out[cell] = _fade(d, radius)
	# A wall is lit on a face turned towards the light, next to a lit floor cell.
	# (A straight line to a wall seen nearly edge on grazes the walls beside it,
	# so the line alone would leave most of a long wall dark.)
	for w: Vector2i in walls:
		for k in range(1, 5):
			var n := w + Vector2i(Net.DX[k], Net.DY[k])
			if not out.has(n.y * map.width + n.x) or blocks(map, doors, n.x, n.y):
				continue
			var faces := false
			if Net.DX[k] > 0:
				faces = origin.x >= n.x - 0.5
			elif Net.DX[k] < 0:
				faces = origin.x <= n.x + 0.5
			elif Net.DY[k] > 0:
				faces = origin.y >= n.y - 0.5
			else:
				faces = origin.y <= n.y + 0.5
			if faces:
				out[w.y * map.width + w.x] = _fade(Vector2(w).distance_to(mid), radius)
				break
	return out


static func _fade(d: float, radius: float) -> float:
	## How strongly a pool of light lights a cell `d` cells from its middle:
	## bright in the middle, then a soft fade that is long gone by the edge.
	return pow(clampf(1.2 * (1.0 - d / radius), 0.0, 1.0), 1.3)


# How a character sees: a cone ahead of it, made of two eyes whose fields
# overlap in the middle (the author's numbers). In the light the whole field
# is FIELD degrees wide; in the dark it narrows to DARK_FIELD and only lit
# places, or the few cells right around the character, can be made out.
# Each eye is kept apart so that one day an eye can be lost and its part of
# the cone with it.
const FIELD := 160.0
const DARK_FIELD := 60.0
const EYES_OVERLAP := 10.0
const SIGHT_REACH := 9                 # cells: how far the eyes reach (v46, the author: 9 cells, as in SS13)
const DARK_REACH := 2                  # cells seen around oneself in pitch dark


static func eye_arcs(dark: bool, eyes: int = 3) -> Array:
	## The arcs the eyes see, [from, to] in degrees from straight ahead (one
	## side negative). `eyes`: bit 0 the first eye, bit 1 the second.
	var total := DARK_FIELD if dark else FIELD
	var eye := (total + EYES_OVERLAP) * 0.5      # 85 degrees in the light, 35 in the dark
	var out: Array = []
	if eyes & 1:
		out.append([-total * 0.5, -total * 0.5 + eye])
	if eyes & 2:
		out.append([total * 0.5 - eye, total * 0.5])
	return out


static func in_arcs(ahead: Vector2, v: Vector2, arcs: Array) -> bool:
	## Is the direction `v` inside one of the arcs around `ahead` (allowing for
	## a cell's size at that distance)?
	var dist := v.length()
	if dist < 0.75:
		return true
	var a := rad_to_deg(ahead.angle_to(v))
	var give := rad_to_deg(atan(0.5 / dist))
	for arc: Array in arcs:
		if a >= float(arc[0]) - give and a <= float(arc[1]) + give:
			return true
	return false


static func sees(map: ShipMap, doors: Doors, from: Vector2, facing: int, to: Vector2i, arcs: Array, reach: int, lines: Variant = null) -> bool:
	## Can somebody at `from` (in cells), facing that way, see the cell `to`
	## (same deck, inside the arcs, within reach, nothing in the way)?
	## `lines`: a Dictionary to remember lines in (see clear_cached), or null.
	if facing < 1 or facing > Net.DIRS:
		return false
	return sees_way(map, doors, from, Net.way(facing), to, arcs, reach, lines)


static func sees_way(map: ShipMap, doors: Doors, from: Vector2, ahead: Vector2, to: Vector2i, arcs: Array, reach: int, lines: Variant = null) -> bool:
	## (v77) The same, looking along `ahead` (a way of length 1: the mouse's, between the 8).
	var at := Vector2i(roundi(from.x), roundi(from.y))
	if map.deck_of(at.y) != map.deck_of(to.y):
		return false
	var v := Vector2(to) - from
	if v.length() > reach + 0.5:
		return false
	if not in_arcs(ahead, v, arcs):
		return false
	if v.length() < 0.75:
		return true
	return clear_line(map, doors, at, to) if lines == null else clear_cached(map, doors, at, to, lines)
