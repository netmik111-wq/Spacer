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


static func cone(map: ShipMap, doors: Doors, origin: Vector2, facing: int, width_deg: float, reach: int) -> Dictionary:
	## The cells a light (or a look) from `origin` (in cells; the middle of a
	## cell is a whole number) facing that way reaches: cell -> how strongly,
	## 1.0 near and less further off. The cone is `width_deg` wide and `reach`
	## cells long, and stays on the deck it starts on.
	var out := {}
	if facing < 1 or facing > 4:
		return out
	var from := Vector2i(roundi(origin.x), roundi(origin.y))
	if from.x < 0 or from.y < 0 or from.x >= map.width or from.y >= map.height:
		return out
	var deck := map.deck_of(from.y)
	var top := deck * map.deck_stride
	var bottom := top + map.deck_height - 1
	var ahead := Vector2(Net.DX[facing], Net.DY[facing])
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


# How a character sees: a cone ahead of it, made of two eyes whose fields
# overlap in the middle (the author's numbers). In the light the whole field
# is FIELD degrees wide; in the dark it narrows to DARK_FIELD and only lit
# places, or the few cells right around the character, can be made out.
# Each eye is kept apart so that one day an eye can be lost and its part of
# the cone with it.
const FIELD := 160.0
const DARK_FIELD := 60.0
const EYES_OVERLAP := 10.0
const SIGHT_REACH := 20                # cells: a lit ship is seen as far as the screen goes
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


static func sees(map: ShipMap, doors: Doors, from: Vector2, facing: int, to: Vector2i, arcs: Array, reach: int) -> bool:
	## Can somebody at `from` (in cells), facing that way, see the cell `to`
	## (same deck, inside the arcs, within reach, nothing in the way)?
	if facing < 1 or facing > 4:
		return false
	var at := Vector2i(roundi(from.x), roundi(from.y))
	if map.deck_of(at.y) != map.deck_of(to.y):
		return false
	var v := Vector2(to) - from
	if v.length() > reach + 0.5:
		return false
	if not in_arcs(Vector2(Net.DX[facing], Net.DY[facing]), v, arcs):
		return false
	return v.length() < 0.75 or clear_line(map, doors, at, to)
