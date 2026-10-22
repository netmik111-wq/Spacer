extends RefCounted
## The movement rule. The server runs it for every character each tick; the
## client runs the very same code to predict its own character, so the two
## agree as long as they see the same inputs on the same ticks.

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Doors := preload("res://src/shared/doors.gd")


class State:
	var x := 0                 # tile the character occupies
	var y := 0
	var cd := 0                # ticks until the next step may start
	var facing := 2            # Net.DIR_DOWN
	var dir := 0               # direction currently held (0 = none)
	var move_tick := -1000     # tick on which the last step started
	var fx := 0                # (v78) where the last step started from, in quarters of a tile (for drawing the slide)
	var fy := 0
	var ox := 0                # (v78) quarters of a tile off the centre of tile x,y: -2..1 (only a `fine` walker)
	var oy := 0
	var fine := false          # (v78, the author's M1 "D") steps a quarter of a tile at a time: players; bots,
	                           # pirates and robots keep whole tiles
	var prone := false         # (v78, C1 "B") lying down: crawls at half speed, shots fly over
	var down := false          # unconscious or dead: cannot walk
	var slow := false          # hauling somebody (or being hauled): a step takes Net.DRAG_TICKS
	var span := 4              # how many ticks the last step takes (for drawing the slide)
	var access := Net.ACCESS_ALL   # the rooms its job lets it into (Net.ACCESS_*): restricted doors open only for those
	var free_look := false     # (v77, the author's V1) it looks where the mouse is: walking does not turn it
	var hold := false          # (v81, the author's human wall) holds its position: nobody walks through its tile;
	                           # any step lets go

	func copy_from(o: State) -> void:
		x = o.x; y = o.y; cd = o.cd; facing = o.facing; dir = o.dir
		move_tick = o.move_tick; fx = o.fx; fy = o.fy; down = o.down
		slow = o.slow; span = o.span; access = o.access; free_look = o.free_look
		ox = o.ox; oy = o.oy; fine = o.fine; prone = o.prone; hold = o.hold

	func same_as(o: State) -> bool:
		return x == o.x and y == o.y and cd == o.cd and facing == o.facing \
			and dir == o.dir and move_tick == o.move_tick and down == o.down and slow == o.slow and free_look == o.free_look \
			and ox == o.ox and oy == o.oy and fine == o.fine and prone == o.prone and hold == o.hold

	func place(px: int, py: int) -> void:
		x = px; y = py; ox = 0; oy = 0; fx = px * 4; fy = py * 4; cd = 0; move_tick = -1000; prone = false; hold = false

	func qx() -> int:
		## (v78) Where it stands across, in quarters of a tile (x * 4 is the centre of tile x).
		return x * 4 + ox

	func qy() -> int:
		return y * 4 + oy


const TURN := 16                     # an input of TURN + a direction only turns the character that way
const LOOK_FREE := 32                # (v77) an input of LOOK_FREE: from now on it looks where the mouse is
const LOOK_WALK := 33                # and LOOK_WALK: it looks where it walks again
const LIE := 34                      # (v78) an input of LIE: it lies down
const RISE := 35                     # and RISE: it gets up
const HOLD := 36                     # (v81) an input of HOLD: it holds its position (the human wall)
const LET_GO := 37                   # and LET_GO: it stops holding


static func apply_input(st: State, value: int) -> void:
	## An input from the queue: hold a direction (0 = none), just turn (TURN + direction),
	## or (v77) look with the mouse or where one walks.
	if value == LOOK_FREE or value == LOOK_WALK:
		st.free_look = value == LOOK_FREE
	elif value == LIE or value == RISE:
		st.prone = value == LIE
	elif value == HOLD or value == LET_GO:
		st.hold = value == HOLD and not st.down
	elif value > TURN:
		if not st.down:
			st.facing = value - TURN
	else:
		st.dir = value


## Advances one character by one tick. Returns true if a step started.
## Walking into a shut door pushes it open and waits in front of it.
## (v74, the author's N2) A diagonal step never cuts a corner: both cells beside it must be
## open floor (or space), and no doorway is crossed on a slant. Held against a corner, the
## character slides along the side that is open.
static func step(st: State, map: ShipMap, doors: Doors, tick: int) -> bool:
	if st.cd > 0:
		st.cd -= 1
	# the character turns the way it is told at once, even in mid-step or against a wall
	if not st.down and st.dir != 0 and not st.free_look:
		st.facing = st.dir
	if st.hold and (st.down or st.dir != 0):
		st.hold = false                  # (v81) a step lets go of the position held
	if st.down or st.cd > 0 or st.dir == 0:
		return false
	if st.fine:
		return _fine_step(st, map, doors, tick)
	if st.ox != 0 or st.oy != 0:
		st.ox = 0                        # a bot has taken over a player: back on the centre of its tile
		st.oy = 0
	var dir := st.dir
	if Net.diagonal(dir) and (st.slow or not slant_open(map, st.x, st.y, Net.DX[dir], Net.DY[dir])):
		# along the wall: the side way that is open (across first, then up or down); somebody
		# hauling (or hauled) goes straight, so the body follows into the cell just left
		var across := Net.dir_of(Net.DX[dir], 0)
		var upright := Net.dir_of(0, Net.DY[dir])
		if map.passable(st.x + Net.DX[dir], st.y):
			dir = across
		elif map.passable(st.x, st.y + Net.DY[dir]):
			dir = upright
		else:
			return false
	var nx: int = st.x + Net.DX[dir]
	var ny: int = st.y + Net.DY[dir]
	if not map.passable(nx, ny) or map.held.has(ny * map.width + nx):
		return false
	var door := map.door_at(nx, ny)
	if door >= 0:
		if doors.barred(door, map.door_access[door], st.access) and not map.leaving(st.x, st.y, door):
			return false                 # a restricted room, and its job gives no access there (v69: leaving it is free)
		if doors.blocks(door, st.access):
			return false                 # (v60) a blast door locked against boarders
		doors.bump(door, tick)
		if not doors.passable(door, tick):
			return false
	var was_x := st.x
	var was_y := st.y
	st.fx = was_x * 4
	st.fy = was_y * 4
	st.x = nx
	st.y = ny
	# hauling somebody, or pushing off through open space, is slow going
	st.span = Net.DRAG_TICKS if st.slow or st.prone or map.floats(nx, ny) or map.floats(was_x, was_y) else Net.MOVE_TICKS
	if Net.diagonal(dir):
		st.span = slant_span(st.span, tick)
	st.cd = st.span
	st.move_tick = tick
	return true


static func slant_open(map: ShipMap, x: int, y: int, dx: int, dy: int) -> bool:
	## (v74) May a character step from x,y by dx,dy on a slant: the cell there and both cells
	## beside the way open floor or space, none of them (nor x,y) a doorway.
	for c: Vector2i in [Vector2i(x + dx, y + dy), Vector2i(x + dx, y), Vector2i(x, y + dy)]:
		if not map.passable(c.x, c.y) or map.door_at(c.x, c.y) >= 0:
			return false
	return map.door_at(x, y) < 0 and map.deck_of(y) == map.deck_of(y + dy)


static func slant_span(straight: int, tick: int) -> int:
	## (v74, the author's N3: 1.4 times a straight step) Ticks are whole, so a slant step
	## takes the next whole number up or down by the tick it starts on: on average exactly
	## 1.4 times (4 ticks -> 5 or 6, 5.6 on average; 8 -> 11 or 12, 11.2).
	return (straight * 14 + posmod(tick, 10)) / 10


## Where the character is drawn at (fractional) tick `t`, in tile units.
static func visual_pos(st: State, t: float) -> Vector2:
	var k := clampf((t - float(st.move_tick)) / float(st.span), 0.0, 1.0)
	return Vector2(lerpf(float(st.fx), float(st.qx()), k), lerpf(float(st.fy), float(st.qy()), k)) * 0.25


# ------------------------------------------------- (v78) quarter steps

## A `fine` walker stands on any quarter of a tile. Its tile (x, y) is the one under its
## centre, and that tile alone counts for air, doors, sight and using things; its body
## (a tile wide) may lie over the next tile too, which must then be open to it. A step is
## a quarter of a tile, so it takes a quarter of a whole step's time: the same speed.
## Walking into a doorway or a corridor a quarter off, it slides into line by itself.
static func _fine_step(st: State, map: ShipMap, doors: Doors, tick: int) -> bool:
	var dx: int = Net.DX[st.dir]
	var dy: int = Net.DY[st.dir]
	var moved := false
	if dx != 0 and dy != 0:
		# on a slant; somebody hauling (or hauled) goes straight, across first
		moved = (not st.slow and _shift(st, map, doors, tick, dx, dy)) or _shift(st, map, doors, tick, dx, 0) \
			or _shift(st, map, doors, tick, 0, dy) or _line_up(st, map, tick, dx, 0) or _line_up(st, map, tick, 0, dy)
		if moved and not st.slow and st.qx() != st.fx and st.qy() != st.fy:
			st.span = slant_span(st.span, tick)
			st.cd = st.span
	else:
		moved = _shift(st, map, doors, tick, dx, dy) or _line_up(st, map, tick, dx, dy)
	return moved


static func _shift(st: State, map: ShipMap, doors: Doors, tick: int, dx: int, dy: int) -> bool:
	## One quarter that way, if the body fits where it goes: every tile it newly lies over
	## open to it (a door pushed open first), and on a slant no wall corner nor doorway under it.
	var nqx := st.qx() + dx
	var nqy := st.qy() + dy
	var nx := (nqx + 2) >> 2
	var ny := (nqy + 2) >> 2
	var nox := nqx - nx * 4
	var noy := nqy - ny * 4
	var ax := _beside(nx, nox)
	var ay := _beside(ny, noy)
	if ax != nx and ay != ny:
		# lying over four tiles: all of them open floor (or space) on one deck, no doorway among them
		for c: Vector2i in [Vector2i(nx, ny), Vector2i(ax, ny), Vector2i(nx, ay), Vector2i(ax, ay)]:
			if not map.passable(c.x, c.y) or map.door_at(c.x, c.y) >= 0:
				return false
		if map.deck_of(ny) != map.deck_of(ay):
			return false
	var bx := _beside(st.x, st.ox)
	var by := _beside(st.y, st.oy)
	for c: Vector2i in [Vector2i(nx, ny), Vector2i(ax, ny), Vector2i(nx, ay), Vector2i(ax, ay)]:
		if (c.x == st.x or c.x == bx) and (c.y == st.y or c.y == by):
			continue                     # it lies there already
		if not map.passable(c.x, c.y) or map.held.has(c.y * map.width + c.x):
			return false                 # (v81) a held tile is a wall of people
		var door := map.door_at(c.x, c.y)
		if door >= 0:
			if doors.barred(door, map.door_access[door], st.access) and not map.leaving(st.x, st.y, door):
				return false
			if doors.blocks(door, st.access):
				return false
			doors.bump(door, tick)
			if not doors.passable(door, tick):
				return false
	var was_x := st.x
	var was_y := st.y
	st.fx = st.qx()
	st.fy = st.qy()
	st.x = nx
	st.y = ny
	st.ox = nox
	st.oy = noy
	var whole := Net.DRAG_TICKS if st.slow or st.prone or map.floats(nx, ny) or map.floats(was_x, was_y) else Net.MOVE_TICKS
	st.span = maxi(whole / 4, 1)
	st.cd = st.span
	st.move_tick = tick
	return true


static func _line_up(st: State, map: ShipMap, tick: int, dx: int, dy: int) -> bool:
	## Blocked going straight while a quarter off across the way: slide towards the row
	## (or column) the way ahead is open from. Moving into line always fits.
	var off := st.oy if dx != 0 else st.ox
	if off == 0:
		return false
	var s := signi(off)
	# a straight quarter is refused only from the centre of a tile, going into the next one
	var ahead_x := st.x + dx
	var ahead_y := st.y + dy
	if dx != 0:
		if map.passable(ahead_x, st.y):
			return _shift_free(st, map, tick, 0, -s)
		if map.passable(ahead_x, st.y + s):
			return _shift_free(st, map, tick, 0, s)
	else:
		if map.passable(st.x, ahead_y):
			return _shift_free(st, map, tick, -s, 0)
		if map.passable(st.x + s, ahead_y):
			return _shift_free(st, map, tick, s, 0)
	return false


static func _shift_free(st: State, map: ShipMap, tick: int, dx: int, dy: int) -> bool:
	## A quarter across the way: the body only moves within the tiles it already lies
	## over, so no door is asked (and none is pushed).
	return _shift(st, map, null, tick, dx, dy)


static func _beside(t: int, off: int) -> int:
	## The other tile a body `off` quarters from the centre of tile `t` lies over (t itself when centred).
	return t if off == 0 else t + signi(off)


static func body_tiles(st: State) -> Array[Vector2i]:
	## (v78) Every tile the body lies over: one, two or four.
	var bx := _beside(st.x, st.ox)
	var by := _beside(st.y, st.oy)
	var out: Array[Vector2i] = [Vector2i(st.x, st.y)]
	if bx != st.x:
		out.append(Vector2i(bx, st.y))
	if by != st.y:
		out.append(Vector2i(st.x, by))
		if bx != st.x:
			out.append(Vector2i(bx, by))
	return out


static func is_sliding(st: State, t: float) -> bool:
	return t - float(st.move_tick) < float(st.span)
