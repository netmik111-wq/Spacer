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
	var fx := 0                # tile the last step started from (for drawing the slide)
	var fy := 0
	var down := false          # unconscious or dead: cannot walk
	var slow := false          # hauling somebody (or being hauled): a step takes Net.DRAG_TICKS
	var span := 4              # how many ticks the last step takes (for drawing the slide)
	var access := Net.ACCESS_ALL   # the rooms its job lets it into (Net.ACCESS_*): restricted doors open only for those

	func copy_from(o: State) -> void:
		x = o.x; y = o.y; cd = o.cd; facing = o.facing; dir = o.dir
		move_tick = o.move_tick; fx = o.fx; fy = o.fy; down = o.down
		slow = o.slow; span = o.span; access = o.access

	func same_as(o: State) -> bool:
		return x == o.x and y == o.y and cd == o.cd and facing == o.facing \
			and dir == o.dir and move_tick == o.move_tick and down == o.down and slow == o.slow

	func place(px: int, py: int) -> void:
		x = px; y = py; fx = px; fy = py; cd = 0; move_tick = -1000


const TURN := 8                      # an input of TURN + a direction only turns the character that way


static func apply_input(st: State, value: int) -> void:
	## An input from the queue: hold a direction (0 = none), or just turn (TURN + direction).
	if value > TURN:
		if not st.down:
			st.facing = value - TURN
	else:
		st.dir = value


## Advances one character by one tick. Returns true if a step started.
## Walking into a shut door pushes it open and waits in front of it.
static func step(st: State, map: ShipMap, doors: Doors, tick: int) -> bool:
	if st.cd > 0:
		st.cd -= 1
	# the character turns the way it is told at once, even in mid-step or against a wall
	if not st.down and st.dir != 0:
		st.facing = st.dir
	if st.down or st.cd > 0 or st.dir == 0:
		return false
	var nx: int = st.x + Net.DX[st.dir]
	var ny: int = st.y + Net.DY[st.dir]
	if not map.passable(nx, ny):
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
	st.fx = st.x
	st.fy = st.y
	st.x = nx
	st.y = ny
	# hauling somebody, or pushing off through open space, is slow going
	st.span = Net.DRAG_TICKS if st.slow or map.floats(nx, ny) or map.floats(st.fx, st.fy) else Net.MOVE_TICKS
	st.cd = st.span
	st.move_tick = tick
	return true


## Where the character is drawn at (fractional) tick `t`, in tile units.
static func visual_pos(st: State, t: float) -> Vector2:
	var k := clampf((t - float(st.move_tick)) / float(st.span), 0.0, 1.0)
	return Vector2(lerpf(float(st.fx), float(st.x), k), lerpf(float(st.fy), float(st.y), k))


static func is_sliding(st: State, t: float) -> bool:
	return t - float(st.move_tick) < float(st.span)
