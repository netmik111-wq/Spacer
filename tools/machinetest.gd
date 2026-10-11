extends SceneTree
## Checks the ship's machines on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/machinetest.gd
## The engine: without it the ship neither moves nor jumps, and mending it
## brings both back. The air plant: it fills its own compartment and nothing
## else while the doors are shut, and stops when it is out of order.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Director := preload("res://src/server/director.gd")
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

	# --- the engine
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

	# mending it: stand in front of it and hold "use"
	_face(p, engine)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(not server.engine_down(), "holding use in front of the engine mends it")
	_face(p, map.chart.keys()[0])
	server._jump_asked(p, target)
	_expect(server.jump_to == target, "with the engine mended the jump starts")
	_expect(server.break_engine() and server.jump_to == Net.NO_SECTOR, "an engine failure breaks off a jump being charged")
	server.broken.clear()
	_expect(server.break_console() and not server.break_engine(), "the engine does not break while a bridge console is out")
	server.broken.clear()

	# --- the air plant
	var air := server.air
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
	var out_cell: int = map.air_plant[plant]
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
	var before := air.total()
	_run(10 * Net.TICK_HZ)
	_expect(absf(air.total() - before) < 0.001, "a plant that is out of order makes no air")
	_face(p, plant)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(server.broken.is_empty(), "holding use in front of the plant mends it")
	_run(5 * Net.TICK_HZ)
	_expect(air.total() > before + 0.3, "and it makes air again")
	# it never pushes a room above normal pressure
	air.refill()
	_run(20 * Net.TICK_HZ)
	var top := 0.0
	for i in air._cells:
		top = maxf(top, air.air[i])
	_expect(top <= 1.0001 and absf(air.total() - air._cells.size()) < 0.01, "a full ship stays at normal pressure (highest cell %.3f)" % top)

	server.stop()
	server.free()
	print("MACHINETEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


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
