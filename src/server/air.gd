extends RefCounted
## The air inside the ship. Server only: clients get the result.
##
## Every walkable cell holds an amount of air, 1.0 being normal pressure.
## Each step, air moves between neighbouring cells towards the lower pressure.
## A shut door lets nothing through. A hole in the hull drains the cells next
## to it into space.
##
## The loop visits every walkable cell. That is fine for a small ship; for big
## maps see research/README.md (only the cells where something happens need
## visiting, and the loop could move to a compiled module).

const ShipMap := preload("res://src/shared/ship_map.gd")
const Doors := preload("res://src/shared/doors.gd")
const Net := preload("res://src/shared/net.gd")

const FLOW := 0.2                    # share of a pressure difference that crosses between two cells per step (below 0.25, or it oscillates)
const LEAK := 0.12                   # share of a cell's air lost per step through each hole next to it
const REST := 0.00002                # below this much change per step the air is considered settled

var map: ShipMap
var air := PackedFloat32Array()      # per cell; cells nobody can stand in stay 0
var level := PackedByteArray()       # the same, rounded for the network: 0..Net.AIR_FULL
var holes := {}                      # breached hull cell -> true
var settled := false                 # nothing is moving: steps are skipped until something changes

var _next := PackedFloat32Array()
var _cells := PackedInt32Array()     # the walkable cells
var _near := PackedInt32Array()      # 4 neighbours of each cell (-1 = none)
var _leaks := PackedByteArray()      # holes next to each cell


func setup(p_map: ShipMap) -> void:
	map = p_map
	var n := map.width * map.height
	air.resize(n)
	_next.resize(n)
	level.resize(n)
	_near.resize(n * 4)
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
			if map.walkable(x - 1, y): _near[i * 4] = i - 1
			if map.walkable(x + 1, y): _near[i * 4 + 1] = i + 1
			if map.walkable(x, y - 1): _near[i * 4 + 2] = i - map.width
			if map.walkable(x, y + 1): _near[i * 4 + 3] = i + map.width
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
		var base := i * 4
		for k in 4:
			var j := _near[base + k]
			if j < 0:
				continue
			var dj := door_of[j]
			if dj >= 0 and not doors.passable(dj, tick):
				continue
			gain += air[j] - a
		var v := a + FLOW * gain
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
