extends RefCounted
## The air inside the ship. Server only: clients get the result.
##
## Every walkable cell holds an amount of air, 1.0 being normal pressure.
## Each step, air moves between neighbouring cells towards the lower pressure.
## A shut door lets nothing through. A hole in the hull drains the cells next
## to it into space. Between decks air passes where the floor is a catwalk or
## an open hatch, and nowhere else: glass is sealed.
##
## The loop visits every walkable cell. That is fine for a small ship; for big
## maps see research/README.md (only the cells where something happens need
## visiting, and the loop could move to a compiled module).

const ShipMap := preload("res://src/shared/ship_map.gd")
const Doors := preload("res://src/shared/doors.gd")
const Net := preload("res://src/shared/net.gd")

const FLOW := 0.2                    # share of a pressure difference that crosses between two cells per step (below 0.25, or it oscillates)
const FLOW_DECK := 0.1               # the same between a cell and the one above or below it. Smaller, so that
                                     # a cell with five or six neighbours still cannot give away more than it has.
const LEAK := 0.12                   # share of a cell's air lost per step through each hole next to it
const PLANT_PER_STEP := 0.012        # air an air plant adds to the cell in front of it per step: one cell's
                                     # worth in about 8 s, a room of ten cells in a minute and a half
const REST := 0.00002                # below this much change per step the air is considered settled

var map: ShipMap
var air := PackedFloat32Array()      # per cell; cells nobody can stand in stay 0
var level := PackedByteArray()       # the same, rounded for the network: 0..Net.AIR_FULL
var holes := {}                      # breached hull cell -> true
var settled := false                 # nothing is moving: steps are skipped until something changes

var _next := PackedFloat32Array()
var _cells := PackedInt32Array()     # the walkable cells
var _near := PackedInt32Array()      # 6 neighbours of each cell: 4 on its deck, the one above, the one below (-1 = none)
var _leaks := PackedByteArray()      # holes next to each cell


func setup(p_map: ShipMap) -> void:
	map = p_map
	var n := map.width * map.height
	air.resize(n)
	_next.resize(n)
	level.resize(n)
	_near.resize(n * 6)
	_near.fill(-1)
	_leaks.resize(n)
	_cells.clear()
	holes.clear()
	for y in map.height:
		for x in map.width:
			var i := y * map.width + x
			if map.walk[i] == 0:
				continue
			_cells.append(i)
			air[i] = 1.0
			level[i] = Net.AIR_FULL
			if map.walkable(x - 1, y): _near[i * 6] = i - 1
			if map.walkable(x + 1, y): _near[i * 6 + 1] = i + 1
			if map.walkable(x, y - 1): _near[i * 6 + 2] = i - map.width
			if map.walkable(x, y + 1): _near[i * 6 + 3] = i + map.width
			_near[i * 6 + 4] = map.air_up[i]
			_near[i * 6 + 5] = map.air_down[i]
	settled = true


func set_hole(cell: int, on: bool) -> bool:
	## Opens or closes a hole in a hull cell. Returns true if that changed anything.
	if holes.has(cell) == on:
		return false
	if on:
		holes[cell] = true
	else:
		holes.erase(cell)
	var x := cell % map.width
	var y := cell / map.width
	for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if map.walkable(x + o.x, y + o.y):
			var i := (y + o.y) * map.width + x + o.x
			_leaks[i] = _leaks[i] + 1 if on else _leaks[i] - 1
	settled = false
	return true


func refill() -> void:
	## Normal pressure everywhere (a supply station tops the ship up). Holes go on leaking.
	for i in _cells:
		air[i] = 1.0
		level[i] = Net.AIR_FULL
	settled = false


func feed(cell: int, amount: float) -> float:
	## An air plant blows this much into a cell, up to normal pressure.
	## Returns how much went in.
	var room := minf(1.0 - air[cell], amount)
	if room <= 0.0:
		return 0.0
	air[cell] += room
	settled = false
	return room


func wake() -> void:
	## Something changed (a door moved): look again.
	settled = false


func total() -> float:
	var t := 0.0
	for i in _cells:
		t += air[i]
	return t


func step(doors: Doors, tick: int) -> void:
	if settled:
		return
	var door_of := map.door_of
	var biggest := 0.0
	for i in _cells:
		var a := air[i]
		var d := door_of[i]
		if d >= 0 and not doors.passable(d, tick):
			_next[i] = a                 # a shut door keeps what is in its own cell
			continue
		var gain := 0.0
		var base := i * 6
		for k in 6:
			var j := _near[base + k]
			if j < 0:
				continue
			var dj := door_of[j]
			if dj >= 0 and not doors.passable(dj, tick):
				continue
			gain += (air[j] - a) * (FLOW if k < 4 else FLOW_DECK)
		var v := a + gain
		if _leaks[i] > 0:
			v -= LEAK * _leaks[i] * a
		if v < 0.0:
			v = 0.0
		_next[i] = v
		var change := absf(v - a)
		if change > biggest:
			biggest = change
	var swap := air
	air = _next
	_next = swap
	for i in _cells:
		level[i] = clampi(roundi(air[i] * Net.AIR_FULL), 0, Net.AIR_FULL)
	if biggest < REST:
		settled = true
