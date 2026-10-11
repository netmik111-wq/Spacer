extends SceneTree
## Checks the ship's machines on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/machinetest.gd
## The engine powers the ship: without it nothing moves, jumps, makes air or
## fills a tank, and doors open by hand; nothing breaks, and mending the engine
## brings it all back. The air plant fills its own compartment and nothing else
## while the doors are shut. Emergency shutters drop on a pressure difference,
## can be forced by hand, and need power.
## Doors can jam open, shutters can fail, and the power can drop out for a
## few seconds: the director's smaller troubles.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Director := preload("res://src/server/director.gd")
const Doors := preload("res://src/shared/doors.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26190, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	_expect(map.engine.size() == 1 and map.air_plant.size() == 1, "the ship has an engine and an air plant")
	var engine: int = map.engine.keys()[0]
	var plant: int = map.air_plant.keys()[0]
	var p := server._new_player("Проверка")

	print("the engine")
	_face(p, map.helm.keys()[0])
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(server.ship_moving, "with the engine running the helm sets a course")
	_expect(server.director.fire(Director.ENGINE_FAULT) and server.engine_down(), "the director can stop the engine")
	_expect(not server.ship_moving, "the ship stops when the engine does")
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(not server.ship_moving, "the helm does nothing without the engine")
	_face(p, map.chart.keys()[0])
	var target: int = server.sectors.neighbours(server.sector)[0]
	server._jump_asked(p, target)
	_expect(server.jump_to == Net.NO_SECTOR, "no jump without the engine")
	_expect(not server.break_console(), "a bridge console does not break while the engine is out")

	print("no power: every system stands still, none is broken")
	_expect(server.broken.size() == 1, "only the engine itself is out of order")
	var air := server.air
	var out_cell: int = map.air_plant[plant]
	air.air[out_cell] = 0.5
	air.wake()
	var before := air.total()
	_run(5 * Net.TICK_HZ)
	_expect(absf(air.total() - before) < 0.001, "the air plant makes no air")
	_face(p, map.oxygen.keys()[0])
	p.tank = 0.2
	p.using = true
	_run(2 * Net.TICK_HZ)
	_expect(p.tank <= 0.2, "an oxygen station does not fill a tank")
	p.using = false
	var slow := _ticks_through_a_door(p)
	_expect(slow >= Doors.MANUAL_OPEN_TICKS and slow < Doors.MANUAL_OPEN_TICKS + 12, "a door is pushed open by hand: %.1f s to get through" % (slow / float(Net.TICK_HZ)))

	print("mending the engine brings everything back")
	_face(p, engine)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(not server.engine_down() and server.broken.is_empty(), "holding use in front of the engine mends it")
	before = air.total()
	_run(5 * Net.TICK_HZ)
	_expect(air.total() > before + 0.05, "the air plant makes air again")
	_face(p, map.oxygen.keys()[0])
	p.using = true
	_run(2 * Net.TICK_HZ)
	_expect(p.tank > 0.5, "an oxygen station fills a tank again")
	p.using = false
	var quick := _ticks_through_a_door(p)
	_expect(quick < Doors.OPEN_TICKS + 12, "doors open by themselves again: %.1f s to get through" % (quick / float(Net.TICK_HZ)))
	_face(p, map.chart.keys()[0])
	server._jump_asked(p, target)
	_expect(server.jump_to == target, "the jump starts")
	_expect(server.break_engine() and server.jump_to == Net.NO_SECTOR, "an engine failure breaks off a jump being charged")
	_mend_all()
	_expect(server.break_console() and not server.break_engine(), "the engine does not break while a bridge console is out")
	_mend_all()

	print("the air plant")
	p.tank = 1.0
	p.supply = true                      # the tester breathes from its tank: the ship is about to be emptied
	for i in air._cells:
		air.air[i] = 0.0
	air.wake()
	var seconds := 60
	_run(seconds * Net.TICK_HZ)
	var made := air.total()
	var expected := Net.TICK_HZ / float(Net.AIR_EVERY) * seconds * air.PLANT_PER_STEP
	print("  the air plant made %.1f cells' worth of air in %d s (%.1f expected)" % [made, seconds, expected])
	_expect(absf(made - expected) < 0.2, "an air plant makes air at its set rate")
	_expect(air.air[out_cell] > 0.05, "the air comes out in front of the plant (%.0f%% there)" % (air.air[out_cell] * 100.0))
	var above := -1
	for i in map.air_down.size():
		if map.air_down[i] >= 0 and map.deck_of_cell(map.air_down[i]) == map.deck_of_cell(out_cell):
			above = i
			break
	if above >= 0:
		_expect(air.air[above] > 0.01, "and rises through the catwalk to the deck above (%.0f%% there)" % (air.air[above] * 100.0))
	var far := (map.deck_stride + 1) * map.width + 5       # the room in the far corner of the lower deck
	_expect(air.air[far] == 0.0, "shut doors keep it out of the other compartments")
	_expect(server.director.fire(Director.AIR_PLANT_FAULT), "the director can stop the air plant")
	before = air.total()
	_run(10 * Net.TICK_HZ)
	_expect(absf(air.total() - before) < 0.001, "a plant that is out of order makes no air")
	_face(p, plant)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(server.broken.is_empty(), "holding use in front of the plant mends it")
	air.refill()
	_run(20 * Net.TICK_HZ)
	var top := 0.0
	for i in air._cells:
		top = maxf(top, air.air[i])
	_expect(top <= 1.0001 and absf(air.total() - air._cells.size()) < 0.01, "a full ship stays at normal pressure (highest cell %.3f)" % top)
	p.supply = false

	print("emergency shutters")
	_expect(_sealed().is_empty(), "with the same pressure everywhere no shutter is down")
	# a hole in the room in the top left corner of the top deck: its two doors are 7,3 and 10,1
	var hole := -1
	for cell in map.hull:
		if cell / map.width == 0 and cell % map.width >= 5 and cell % map.width <= 9:
			hole = cell
			break
	var door_down := map.door_at(7, 3)
	var door_side := map.door_at(10, 1)
	server.breach(hole)
	var dropped := -1
	for t in 20 * Net.TICK_HZ:
		server._tick()
		if dropped < 0 and server.doors.locked[door_down] == 1:
			dropped = t
	var sealed := _sealed()
	_expect(dropped >= 0 and sealed.has(door_down) and sealed.has(door_side) and sealed.size() == 2,
		"a breach drops the shutters of that room's doors and no others (after %.1f s)" % (dropped / float(Net.TICK_HZ)))
	p.st.place(7, 4)
	p.st.dir = Net.DIR_UP
	_run(3 * Net.TICK_HZ)
	_expect(p.st.x == 7 and p.st.y == 4 and server.doors.is_shut(door_down), "walking into a door with its shutter down does not open it")
	p.st.dir = Net.DIR_NONE
	p.st.facing = Net.DIR_UP
	p.using = true
	_run(Net.FORCE_TICKS + 2)
	p.using = false
	_expect(server.doors.locked[door_down] == 0, "holding use for %d s forces the shutter up" % (Net.FORCE_TICKS / Net.TICK_HZ))
	p.st.dir = Net.DIR_UP
	_run(Net.TICK_HZ)
	_expect(p.st.y < 4, "and the door then opens as usual")
	p.st.place(9, 4)                     # step aside; the hole is still there
	p.st.dir = Net.DIR_NONE
	_run(Net.FORCED_OPEN_TICKS + 2 * Net.TICK_HZ)
	_expect(server.doors.is_sealed(door_down), "left alone, a forced shutter drops again and the door shuts")
	server.seal_all()
	air.refill()
	_run(2 * Net.TICK_HZ)
	_expect(_sealed().is_empty(), "when the pressure evens out the shutters lift by themselves")

	# without power nothing drops
	server.break_engine()
	server.breach(hole)
	_run(15 * Net.TICK_HZ)
	_expect(_sealed().is_empty(), "without power no shutter drops")
	_mend_all()
	_run(Net.TICK_HZ)
	_expect(_sealed().has(door_down), "with the power back they drop where they should")
	server.break_engine()
	server.seal_all()
	air.refill()
	_run(5 * Net.TICK_HZ)
	_expect(_sealed().has(door_down), "and one that is down stays down while there is no power")

	_mend_all()
	_run(Net.TICK_HZ)

	print("a door jammed open")
	_expect(server.director.fire(Director.DOOR_JAM), "the director can jam a door")
	var stuck := -1
	for d in server.doors.jammed.size():
		if server.doors.jammed[d] == 1:
			stuck = d
	_run(Doors.HOLD_TICKS + 3 * Net.TICK_HZ)
	_expect(stuck >= 0 and not server.doors.is_shut(stuck), "it stands open and does not shut by itself")
	p.st.place(map.doors[stuck].x, map.doors[stuck].y)       # stand next to it, on whichever side has floor
	var beside := map.door_sides[stuck * 2] if map.door_sides[stuck * 2] >= 0 else map.door_sides[stuck * 2 + 1]
	p.st.place(beside % map.width, beside / map.width)
	p.st.facing = _towards(beside, map.doors[stuck])
	p.using = true
	_run(Net.REPAIR_TICKS + 2)
	p.using = false
	_run(Net.TICK_HZ)
	_expect(server.doors.jammed[stuck] == 0 and server.doors.is_shut(stuck), "mended, it shuts again")

	print("a faulty shutter")
	# one that has dropped for no reason: it stays down although the pressure is even
	server.doors.faulty[door_down] = 1
	server.doors.locked[door_down] = 1
	_run(5 * Net.TICK_HZ)
	_expect(server.doors.is_sealed(door_down), "a faulty shutter that has dropped stays down in even pressure")
	p.st.place(7, 4)
	p.st.facing = Net.DIR_UP
	p.using = true
	_run(Net.REPAIR_TICKS + 2)
	p.using = false
	_run(Net.TICK_HZ)
	_expect(server.doors.faulty[door_down] == 0 and server.doors.locked[door_down] == 0, "mended, it lifts by itself")
	# one that will not drop: a breach on the other side leaves the door unguarded
	server.doors.faulty[door_down] = 1
	server.breach(hole)
	_run(10 * Net.TICK_HZ)
	_expect(server.doors.locked[door_down] == 0 and server.doors.locked[door_side] == 1, "a faulty shutter does not drop at a breach; its neighbour does")
	p.tank = 1.0
	p.supply = true
	p.using = true
	_run(Net.REPAIR_TICKS + 2)
	p.using = false
	_run(Net.TICK_HZ)
	_expect(server.doors.locked[door_down] == 1, "mended, it drops as it should")
	_expect(server.director.fire(Director.SHUTTER_FAULT) and server._count(server.doors.faulty) == 1, "the director can make a shutter fail")
	server.seal_all()
	air.refill()
	for d in server.doors.faulty.size():
		server.doors.faulty[d] = 0
	_run(2 * Net.TICK_HZ)
	p.supply = false

	print("a passing power failure")
	_face(p, map.helm.keys()[0])
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(server.director.fire(Director.POWER_GLITCH) and not server.powered(), "the director can cut the power for a moment")
	_expect(server.broken.is_empty() and not server.engine_down(), "nothing is broken by it")
	_expect(not server.ship_moving and server.doors.manual, "the ship stops and doors go manual, as with the engine out")
	_run(16 * Net.TICK_HZ)
	_expect(server.powered() and not server.doors.manual, "the power comes back by itself within 15 s")
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(server.ship_moving, "and the helm works again")

	server.stop()
	server.free()
	print("MACHINETEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _towards(from_cell: int, to: Vector2i) -> int:
	## The way to face from a cell to look at the cell next to it.
	var w := server.map.width
	var fx := from_cell % w
	var fy := from_cell / w
	if to.x != fx:
		return Net.DIR_RIGHT if to.x > fx else Net.DIR_LEFT
	return Net.DIR_DOWN if to.y > fy else Net.DIR_UP


func _mend_all() -> void:
	server.broken.clear()
	server._power_changed()


func _sealed() -> Array:
	## The doors whose shutter is down.
	var out: Array = []
	for d in server.doors.locked.size():
		if server.doors.locked[d] == 1:
			out.append(d)
	return out


func _ticks_through_a_door(p: RefCounted) -> int:
	## Walks the character from the corridor up through the door at 7,3 and says how long it took.
	p.st.place(7, 4)
	p.st.dir = Net.DIR_UP
	var n := 0
	while p.st.y > 2 and n < 200:
		server._tick()
		n += 1
	p.st.dir = Net.DIR_NONE
	_run(Doors.HOLD_TICKS + 20)          # let the door shut behind
	return n


func _face(p: RefCounted, wall_cell: int) -> void:
	## Puts the character in front of a thing on a wall, looking at it.
	var map := server.map
	var x := wall_cell % map.width
	var y := wall_cell / map.width
	if map.walkable(x, y + 1):
		p.st.place(x, y + 1)
		p.st.facing = Net.DIR_UP
	else:
		p.st.place(x, y - 1)
		p.st.facing = Net.DIR_DOWN
	p.st.dir = Net.DIR_NONE


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
