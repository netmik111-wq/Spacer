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

	func copy_from(o: State) -> void:
		x = o.x; y = o.y; cd = o.cd; facing = o.facing; dir = o.dir
		move_tick = o.move_tick; fx = o.fx; fy = o.fy

	func same_as(o: State) -> bool:
		return x == o.x and y == o.y and cd == o.cd and facing == o.facing \
			and dir == o.dir and move_tick == o.move_tick

	func place(px: int, py: int) -> void:
		x = px; y = py; fx = px; fy = py; cd = 0; move_tick = -1000


## Advances one character by one tick. Returns true if a step started.
## Walking into a shut door pushes it open and waits in front of it.
static func step(st: State, map: ShipMap, doors: Doors, tick: int) -> bool:
	if st.cd > 0:
		st.cd -= 1
	if st.cd > 0 or st.dir == 0:
		return false
	st.facing = st.dir
	var nx: int = st.x + Net.DX[st.dir]
	var ny: int = st.y + Net.DY[st.dir]
	if not map.walkable(nx, ny):
		return false
	var door := map.door_at(nx, ny)
	if door >= 0:
		doors.bump(door, tick)
		if not doors.passable(door, tick):
			return false
	st.fx = st.x
	st.fy = st.y
	st.x = nx
	st.y = ny
	st.cd = Net.MOVE_TICKS
	st.move_tick = tick
	return true


## Where the character is drawn at (fractional) tick `t`, in tile units.
static func visual_pos(st: State, t: float) -> Vector2:
	var k := clampf((t - float(st.move_tick)) / float(Net.MOVE_TICKS), 0.0, 1.0)
	return Vector2(lerpf(float(st.fx), float(st.x), k), lerpf(float(st.fy), float(st.y), k))


static func is_sliding(st: State, t: float) -> bool:
	return t - float(st.move_tick) < float(Net.MOVE_TICKS)
