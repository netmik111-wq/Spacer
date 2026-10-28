extends RefCounted
## (v92, the author's plan item 0: the real-time fight) A ship's shape as the fight's space
## sees it: its drawing from above, every deck laid over the others, in cells. The server and
## every client build it from the same drawing, so they agree on where a ship is solid.
##
## Inside, a ship is the grid it always was and never turns; outside, in Arena, it is a body
## that flies and turns. A point of a body (in its own frame: x along the bow, centred on the
## drawing) falls in one of these cells, and the cell tells which cells of the grid lie there,
## one per deck: a hit there lands on one of them (the author's G2 A: a deck by lot).
## Shared: built by Arena on the server and by GameClient for SpaceView.

const ShipMap := preload("res://src/shared/ship_map.gd")

const EMPTY := 0
const FLOOR := 1                     # inside: floors, doorways, machines on the floor
const PANE := 2                      # a window
const WALL := 3                      # the hull and the walls inside
const GUN := 4                       # a gun mount ('T')

var map: RefCounted                  # the ShipMap it was built from (the grid, or a drawing of others)
var x0 := 0                          # the drawing's column of the shape's left edge
var r0 := 0                          # and the row inside a deck of its top edge
var w := 0
var h := 0
var kind := PackedByteArray()        # per cell (w * h), the most solid of the decks' there (EMPTY..GUN)
var outline := PackedVector2Array()  # the middle of every solid cell that touches empty space, in the body's frame
var edge := PackedByteArray()        # (v93) per cell: 1 = a solid cell that touches empty space (the outer wall: armour)
var radius := 0.0                    # from the middle to the farthest corner
var _skip_other := false             # (the grid) the ship alongside's cells are not ours


static func of_fleet(p_map: RefCounted, ship: int) -> RefCounted:
	## Ship `ship` of our fleet, from the grid (the ship alongside left out).
	var s = load("res://src/shared/arena_shape.gd").new()
	var top: int = p_map.fleet_rows[ship] if ship < p_map.fleet_rows.size() else 0
	var bottom: int = p_map.fleet_rows[ship + 1] - ShipMap.FLEET_GAP / 2 if ship + 1 < p_map.fleet_rows.size() else p_map.deck_height
	s._skip_other = true
	s._build(p_map, 0, top, p_map.width, bottom - top)
	return s


static func of_layout(p_map: RefCounted) -> RefCounted:
	## A drawing of another ship (ShipMap.others), whole.
	var s = load("res://src/shared/arena_shape.gd").new()
	s._build(p_map, 0, 0, p_map.width, p_map.deck_height)
	return s


func _build(p_map: RefCounted, cx: int, cy: int, cw: int, ch: int) -> void:
	map = p_map
	var lo := Vector2i(cw, ch)
	var hi := Vector2i(-1, -1)
	var grid := PackedByteArray()
	grid.resize(cw * ch)
	for d in map.deck_count:
		for r in ch:
			for x in cw:
				var c := _cell_of(d, cx + x, cy + r)
				if c < 0:
					continue
				var k := _kind(c)
				if k > grid[r * cw + x]:
					grid[r * cw + x] = k
				lo = Vector2i(mini(lo.x, x), mini(lo.y, r))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, r))
	if hi.x < 0:
		x0 = cx
		r0 = cy
		w = 1
		h = 1
		kind = PackedByteArray([0])
		return
	x0 = cx + lo.x
	r0 = cy + lo.y
	w = hi.x - lo.x + 1
	h = hi.y - lo.y + 1
	kind.resize(w * h)
	for y in h:
		for x in w:
			kind[y * w + x] = grid[(lo.y + y) * cw + lo.x + x]
	radius = Vector2(w, h).length() / 2.0
	edge.resize(w * h)
	for y in h:
		for x in w:
			if kind[y * w + x] == EMPTY:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if at(x + d.x, y + d.y) == EMPTY:
					outline.append(middle(x, y))
					break
			# (v93) the outer wall that holds armour: open space beside it, a corner's too (a shot may come in slanting there)
			for d: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if at(x + d.x, y + d.y) == EMPTY:
					edge[y * w + x] = 1
					break


func _cell_of(deck: int, x: int, row: int) -> int:
	## The cell of the drawing at that column and row of a deck, or -1 where there is no ship of this shape.
	if x < 0 or x >= map.width or row < 0 or row >= map.deck_height:
		return -1
	var c: int = (deck * map.deck_stride + row) * map.width + x
	if c >= map.cells.size() or map.cells[c] < 0:
		return -1
	if _skip_other and map.is_other(c):
		return -1
	return c


func _kind(c: int) -> int:
	if (map.all_of("guns") as PackedInt32Array).has(c):
		return GUN
	if map.walk[c] == 1 or map.on_floor.has(c):
		return FLOOR
	var t: int = map.cells[c]
	var name: String = map.tile_names[t] if t >= 0 and t < map.tile_names.size() else ""
	if name.contains("window") or name.contains("glass") or name.contains("pane"):
		return PANE
	return WALL


func at(x: int, y: int) -> int:
	## What lies at that cell of the shape (EMPTY outside it).
	if x < 0 or y < 0 or x >= w or y >= h:
		return EMPTY
	return kind[y * w + x]


func middle(x: int, y: int) -> Vector2:
	## That cell's middle in the body's frame.
	return Vector2(x + 0.5 - w / 2.0, y + 0.5 - h / 2.0)


func cell_at(local: Vector2) -> Vector2i:
	## The shape's cell a point of the body's frame falls in (may lie outside it).
	return Vector2i(floori(local.x + w / 2.0), floori(local.y + h / 2.0))


func solid(local: Vector2) -> bool:
	var c := cell_at(local)
	return at(c.x, c.y) != EMPTY


func local_of(cell: int) -> Vector2:
	## A cell of the drawing (the grid, or the other ship's own drawing), in the body's frame.
	var x: int = cell % map.width
	var row: int = map.local_y(cell / map.width)
	return Vector2(x - x0 + 0.5 - w / 2.0, row - r0 + 0.5 - h / 2.0)


func cells_under(c: Vector2i) -> PackedInt32Array:
	## The drawing's cells at that cell of the shape, one per deck that has one there.
	var out := PackedInt32Array()
	if at(c.x, c.y) == EMPTY:
		return out
	for d in map.deck_count:
		var cell := _cell_of(d, x0 + c.x, r0 + c.y)
		if cell >= 0:
			out.append(cell)
	return out


func bubble() -> Vector2:
	## The half-axes of the shield's bubble around it (Gunnery.BUBBLE cells off the hull).
	return Vector2(w, h) / 2.0 + Vector2(1.6, 1.6)


func outward(cell: int) -> Vector2:
	## Which way is open space from that cell of the drawing (a gun's), in the body's frame:
	## the side with the fewest solid cells within 3, so a gun in a hull wall points out of it.
	var p := local_of(cell)
	var best := Vector2(0, -1)
	var best_n := 99
	for d: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var n := 0
		for k in range(1, 4):
			if solid(p + d * k):
				n += 1
		if n < best_n:
			best_n = n
			best = d
	return best


func index(c: Vector2i) -> int:
	## (v93) That cell's number in `kind` and `edge`, or -1 outside the shape.
	return c.y * w + c.x if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h else -1


func armoured(i: int) -> bool:
	## (v93) Does that cell carry armour: a cell of the outer hull (a wall, a gun mount, a window, a door in it)?
	return i >= 0 and i < edge.size() and edge[i] == 1 and kind[i] != EMPTY


func normal(c: Vector2i) -> Vector2:
	## (v93) Which way the hull faces at that cell, in the body's frame: the open cells within two of it,
	## summed. A side of the drawing is a staircase of cells; this smooths it, so a shot's angle to the
	## hull (and a ricochet) does not depend on which step it met.
	var sum := Vector2.ZERO
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if (dx != 0 or dy != 0) and at(c.x + dx, c.y + dy) == EMPTY:
				sum += Vector2(dx, dy).normalized()
	if sum.length_squared() < 0.0001:
		sum = middle(c.x, c.y)
	return sum.normalized() if sum.length_squared() > 0.0 else Vector2.RIGHT
