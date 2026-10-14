extends SceneTree
## Checks a derelict alongside, on a real server stepped by hand:
##   godot --headless --path . --script res://tools/derelicttest.gd
## It comes when the ship is near and lies a few cells of space off the
## airlock; the crew pushes off through space to it (slowly, with no air);
## it is dark, unpowered and holds things; it docks against the airlock with
## whoever is aboard it; the ship will not leave anybody outside; and what is
## left on it is there again on the next visit.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Doors := preload("res://src/shared/doors.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26270, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	var d: Derelict = server.derelict
	_expect(d.possible(), "the ship has room for a derelict over its airlock")

	# it comes when the ship is near one
	server.sectors.kind[server.ship.sector] = Sectors.DERELICT
	server.sectors.reach[server.ship.sector] = Sectors.DOCK_RANGE
	server.ship.pos = server.sectors.spot[server.ship.sector]
	server.ship.dest = server.ship.pos
	_run(1)
	_expect(d.here and map.other_at != ShipMap.NO_OTHER, "a derelict comes alongside (at %s)" % map.other_at)
	var loot := 0
	for c in map.other_cells:
		if server.floor_things.has(c):
			loot += Net.FLOOR_STACK - (server.floor_things[c] as PackedByteArray).count(Net.ITEM_NONE)
	_expect(loot >= 5, "with things lying about on it (%d)" % loot)
	var theirs := -1
	for k in range(map.other_first_door, map.doors.size()):
		if map.door_vent[k] == 1:
			theirs = k
	_expect(theirs >= 0 and server.doors.dead[theirs] == 1, "its doors have no power")

	# out of the airlock and across
	var pump: int = map.lock_pump.keys()[0]
	var outer: int = map.lock_pump[pump]["outer"]
	var ours: Vector2i = map.doors[outer]
	var p := server.crew.new_player("Тест")
	p.slots.fill(Net.ITEM_NONE)
	p.supply = true
	p.tank = 1.0
	for c in (map.lock_pump[pump]["chamber"] as PackedInt32Array):
		server.air.air[c] = 0.0
	_run(4)
	p.st.place(ours.x, ours.y + 1)
	p.st.dir = Net.DIR_UP
	var started := server.tick
	var there: Vector2i = map.doors[theirs]
	var reached := -1
	for t in 400:
		_run(1)
		if p.st.y <= there.y and reached < 0:
			reached = server.tick
	p.st.dir = Net.DIR_NONE
	_expect(map.is_other(p.st.y * map.width + p.st.x), "one walks out into space and over to it (now at %d,%d)" % [p.st.x, p.st.y])
	var cells := ours.y + 1 - there.y
	_expect(reached - started >= cells * Net.MOVE_TICKS + Derelict.GAP * (Net.DRAG_TICKS - Net.MOVE_TICKS),
		"pushing off through space is slow going (%d ticks for %d cells)" % [reached - started, cells])
	_expect(server.air.air[(ours.y - 1) * map.width + ours.x] == 0.0, "there is no air out there")
	_expect(d.holds_ship() != "", "the ship will not go while somebody is outside")

	# docking takes whoever is aboard along
	var before := Vector2i(p.st.x, p.st.y)
	var why := d.dock(true)
	_expect(why == "" and d.docked and Vector2i(p.st.x, p.st.y) == before + Vector2i(0, Derelict.GAP),
		"it docks against the airlock, with the one aboard it (%s)" % why)
	_expect(map.doors[theirs] == ours - Vector2i(0, 1) and map.door_vent[outer] == 0, "outer door against outer door")

	# back aboard, undocked, and away
	p.st.place(ours.x, ours.y + 2)
	_expect(d.dock(false) == "" and not d.docked, "it is drawn off again")
	var left := loot
	_expect(d.holds_ship() == "", "with everybody aboard the ship may go")
	server.ship.pos = server.sectors.spot[server.ship.sector] + Vector2(40, 0)
	server.ship.dest = server.ship.pos
	_run(1)
	_expect(not d.here and map.other_at == ShipMap.NO_OTHER and map.cells[there.y * map.width + there.x] < 0, "and leaves it behind")
	server.ship.pos = server.sectors.spot[server.ship.sector]
	server.ship.dest = server.ship.pos
	_run(1)
	var again := 0
	for c in map.other_cells:
		if server.floor_things.has(c):
			again += Net.FLOOR_STACK - (server.floor_things[c] as PackedByteArray).count(Net.ITEM_NONE)
	_expect(again == left, "coming back, what was left on it is still there (%d)" % again)

	# a pirate ship: shows up, docks by force, breaks the airlock open, sends its crew
	server.ship.pos = server.sectors.spot[server.ship.sector] + Vector2(40, 0)
	server.ship.dest = server.ship.pos
	_run(1)
	_expect(not d.here and d.pirates_can_come(), "with nothing alongside, pirates can come")
	var before_pirates := server.pirates.aboard()
	_expect(d.pirates_come(2) and d.here and d.kind == Net.OTHER_PIRATE and not d.docked, "a pirate ship shows up off the airlock")
	_expect(d.dock(true) != "", "nobody docks with pirates of their own accord")
	_run(Derelict.PIRATE_WARNING_TICKS + 2)
	var inner: int = map.lock_pump[pump]["inner"]
	_expect(d.docked and server.doors.jammed[outer] == 1 and server.doors.jammed[inner] == 1,
		"after the warning it docks by force and breaks both airlock doors open")
	_expect(server.pirates.aboard() == before_pirates + 2, "and its pirates come out (%d)" % (server.pirates.aboard() - before_pirates))
	_expect(server.doors.dead[theirs] == 0, "its doors have power")
	p.st.place(ours.x + 6, ours.y + 5)                 # one of the crew in the corridor below the airlock
	p.health = 100.0
	var came := 0
	for t in 30 * Net.TICK_HZ:
		_run(1)
		p.health = maxf(p.health, 50.0)
		came = 0
		for q in server.players:
			if q != null and q.pirate and not q.corpse and map.on_ship(q.st.y * map.width + q.st.x):
				came += 1
		if came > 0:
			break
	_expect(came > 0, "pirates come through the broken airlock into the ship")
	_expect(d.dock(false) == "" and not d.docked, "it can be cast off from the controls")
	_run(2)
	_expect(not d.here and map.other_at == ShipMap.NO_OTHER, "and then it goes")

	server.stop()
	server.free()
	print("DERELICTTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	printerr("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
