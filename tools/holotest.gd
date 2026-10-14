extends SceneTree
## Checks the holomap monitors of the game's ship on a real server stepped by hand:
##   godot --headless --path . --script res://tools/holotest.gd
## There is one on the bridge and one in the engine room. Only somebody standing
## at one, with power, is sent the holomap; it holds the air of every cell of the
## ship's floor, every hole in the hull and every door's state, and stops when
## they step away or the power goes.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26300, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	var monitors: Array = map.holo.keys()
	_expect(monitors.size() == 2 and map.deck_of_cell(monitors[0]) != map.deck_of_cell(monitors[1]),
		"the ship has two holomaps, on different decks")
	var bridge := 0
	for c: int in monitors:
		if map.deck_of_cell(c) == 0:
			bridge = c
	var p := server.crew.new_player("Смотритель")
	var front := map.fitting_front(bridge)
	p.st.place(front % map.width, front / map.width)
	p.st.facing = Net.DIR_UP if front > bridge else Net.DIR_DOWN
	var stranger := server.crew.new_player("Мимо")
	server.holomap.asked(stranger, true)
	_expect(server.holomap.watching.is_empty(), "nobody away from a monitor is sent the holomap")
	server.holomap.asked(p, true)
	_expect(server.holomap.watching.has(p.slot), "somebody standing at it is")

	var floor_cells := 0
	for c in map.base_walk.size():
		if map.on_ship(c):
			floor_cells += 1
	var pkt := server.holomap.packet()
	var n := pkt.decode_u16(3)
	_expect(pkt[0] == Net.S_HOLO and pkt.decode_u16(1) == server.ship.id and n == floor_cells,
		"it holds the air of every cell of the ship's floor (%d)" % n)
	var normal := true
	for i in n:
		normal = normal and pkt[5 + i] == Net.AIR_FULL
	_expect(normal, "all at normal pressure to begin with")
	_expect(pkt.decode_u16(5 + n) == 0, "and no holes")
	var at := 5 + n + 2
	_expect(pkt[at] == map.other_first_door and pkt.size() == at + 1 + map.other_first_door, "and the state of each of the ship's doors")

	var hole: int = map.hull[0]
	server.systems.breach(hole)
	for t in Net.TICK_HZ * 3:
		server._tick()
	pkt = server.holomap.packet()
	var holes := []
	for i in pkt.decode_u16(5 + n):
		holes.append(pkt.decode_u16(5 + n + 2 + i * 2))
	_expect(holes.has(hole), "a hole in the hull shows on it")
	var thin := false
	for i in n:
		thin = thin or pkt[5 + i] < Net.AIR_FULL * 3 / 4
	_expect(thin, "and the air going out of the room it is in")
	var shutters := false
	for d in pkt[5 + n + 2 + holes.size() * 2]:
		shutters = shutters or (pkt[5 + n + 3 + holes.size() * 2 + d] >> 1) & 1 == 1
	_expect(shutters, "and the emergency shutters that came down")

	server.ship.broken[map.engine.keys()[0]] = true
	for t in server.holomap.SEND_EVERY + 1:
		server._tick()
	_expect(not server.holomap.watching.has(p.slot), "without power it goes dark")
	server.ship.broken.clear()
	server.holomap.asked(p, true)
	p.st.place(front % map.width + 3, front / map.width)
	for t in server.holomap.SEND_EVERY + 1:
		server._tick()
	_expect(not server.holomap.watching.has(p.slot), "stepping away from it ends it")

	server.stop()
	server.free()
	print("HOLOTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
