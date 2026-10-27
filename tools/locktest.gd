extends SceneTree
## Checks the two-door airlock of the game's ship on a real server stepped by hand:
##   godot --headless --path . --script res://tools/locktest.gd
## Only one door of the chamber opens at a time; the outer door stays sealed
## while there is air inside and the inner one while there is none; the pump
## empties the chamber into the ship's store and fills it back.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Doors := preload("res://src/shared/doors.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26260, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	_expect(map.lock_pump.size() == 1, "the ship has one airlock with a pump")
	var pump: int = map.lock_pump.keys()[0]
	var lock: Dictionary = map.lock_pump[pump]
	var inner: int = lock["inner"]
	var outer: int = lock["outer"]
	_expect((lock["chamber"] as PackedInt32Array).size() == 9 and map.door_vent[outer] == 1 and map.door_vent[inner] == 0,
		"its chamber is 9 cells, the outer door opens into space")
	_run(4)
	_expect(server.doors.locked[outer] == 1 and server.doors.locked[inner] == 0, "with air inside the outer door is sealed, the inner one is not")

	var p := server.crew.new_player("Тест")
	p.slots.fill(Net.ITEM_NONE)
	var in_door: Vector2i = map.doors[inner]
	p.st.place(in_door.x, in_door.y + 1)
	p.st.dir = Net.DIR_UP
	_run(20)
	p.st.dir = Net.DIR_NONE
	_expect(p.st.y < in_door.y, "one walks into the chamber (now at %d,%d)" % [p.st.x, p.st.y])
	server.doors.locked[outer] = 0
	server.doors.bump(outer, server.tick)
	_expect(server.doors.is_shut(outer), "the outer door will not open while the inner one is open")
	_run(Doors.HOLD_TICKS + 20)
	_expect(server.doors.is_shut(inner), "the inner door shuts behind")
	_run(2)
	_expect(server.doors.locked[outer] == 1, "and the outer one is sealed again")

	var px := pump % map.width
	p.st.place(px, pump / map.width + 1)
	p.st.facing = Net.DIR_UP
	var store := server.ship.store_air
	server.ship.store_air = 10.0
	server.repairs.press(p)
	_expect(int(server.ship.pumps.get(pump, 0)) == GameServer.Systems.PUMP_OUT, "the pump starts taking the air out")
	_run(8 * Net.TICK_HZ)
	_expect(server.systems.lock_air(pump) < 0.01 and server.ship.pumps.is_empty(), "and stops when the chamber is empty (%.3f)" % server.systems.lock_air(pump))
	_expect(server.ship.store_air > 15.0, "the air went into the ship's store (%.1f)" % server.ship.store_air)
	_expect(server.doors.locked[outer] == 0 and server.doors.locked[inner] == 1, "now the outer door is free and the inner one sealed")
	var corridor := (in_door.y + 1) * map.width + in_door.x
	var door_cell: int = map.doors[outer].y * map.width + map.doors[outer].x
	server.doors.bump(outer, server.tick)
	_run(20)
	_expect(not server.doors.is_shut(outer) and server.air.air[door_cell] < 0.05, "the outer door opens and its doorway empties into space")
	server.repairs.press(p)
	_expect(server.ship.pumps.is_empty(), "the pump does not start with a door open")
	_run(Doors.HOLD_TICKS + 20)
	_expect(server.air.air[corridor] > 0.99, "the ship keeps its air (%.3f)" % server.air.air[corridor])
	server.repairs.press(p)
	_expect(int(server.ship.pumps.get(pump, 0)) == GameServer.Systems.PUMP_IN, "the pump fills the chamber back")
	_run(8 * Net.TICK_HZ)
	_run(4)
	_expect(server.systems.lock_air(pump) > 0.99 and server.doors.locked[inner] == 0 and server.doors.locked[outer] == 1,
		"full again: the inner door is free, the outer one sealed")
	server.ship.store_air = 0.0
	server.systems.lock_air(pump)
	for c in (lock["chamber"] as PackedInt32Array):
		server.air.air[c] = 0.0
	server.repairs.press(p)
	_expect(server.ship.pumps.is_empty(), "with no air in store there is nothing to fill it with")
	server.ship.store_air = store

	# the outer door stuck open must not lock the crew out of the airlock
	server.doors.jammed[outer] = 1
	server.doors.ready[outer] = server.tick
	_run(4)
	var crew := server.crew.new_player("Ремонтник")
	crew.st.place(in_door.x, in_door.y + 1)
	crew.st.facing = Net.DIR_UP
	crew.st.dir = Net.DIR_UP
	_run(10)
	crew.st.dir = Net.DIR_NONE
	_expect(server.doors.is_shut(inner) and crew.st.y == in_door.y + 1, "with the outer door stuck open the inner one stays shut")
	crew.using = true
	_run(Net.FORCE_TICKS + 2)
	crew.using = false
	_expect(server.doors.forced[inner] == 1, "but its lock can be overridden by hand")
	crew.st.dir = Net.DIR_UP
	_run(30)
	crew.st.dir = Net.DIR_NONE
	_expect(crew.st.y < in_door.y, "and then one gets into the chamber to mend the outer door (at %d,%d)" % [crew.st.x, crew.st.y])

	server.stop()
	server.free()
	print("LOCKTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
