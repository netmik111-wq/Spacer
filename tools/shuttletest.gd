extends SceneTree
## (v86) Checks the fleet's shuttle and the hangars' force fields on a real server stepped by hand:
##   godot --headless --path . --script res://tools/shuttletest.gd
## Each ship of the fleet has a hangar (a force field and the dock console beside it); one ship alone has
## no shuttle. At a console with the shuttle there a person gets in (4 at most, bots never); aboard nobody
## walks, is seen or is hit; flown to the other ship everyone steps out in its hangar, on cells of their
## own; an empty shuttle is called over; one may get out before it flies. The force field holds the air,
## lets sight through and is never holed.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	# one ship alone: a hangar, but nowhere to fly
	var one := ShipMap.new()
	_expect(one.load_from("ship02") == "", "(the ship loads)")
	var alone: Array = one.shuttle_docks()
	_expect(alone.size() == 1 and not (alone[0] as Dictionary).is_empty(), "a lone ship has its hangar")

	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26330, "ship02|ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.stations.volunteers = false
	var map = server.map
	var sh = server.shuttle
	_expect(sh.works() and sh.docks.size() == 2 and sh.at == 0 and not sh.flying(), "two ships, two hangars: the shuttle waits at the first")
	for i in 2:
		var d: Dictionary = sh.docks[i]
		_expect(map.fleet_of(int(d["console"])) == i and map.fleet_of(int(d["front"])) == i, "the second ship's hangar is its own" if i == 1 else "the first ship's hangar is its own")

	# the force field
	var fields: Array = map.force_field.keys()
	_expect(fields.size() == 8, "each hangar has a force field of four cells (%d)" % fields.size())
	var tight := true
	for c: int in fields:
		if map.walk[c] == 1 or map.opaque[c] == 1 or map.hull.has(c):
			tight = false
	_expect(tight, "the field is not walked through, lets sight through and is never holed")
	var front0: int = int((sh.docks[0] as Dictionary)["front"])
	_run(Net.TICK_HZ * 20)
	_expect(server.air.air[front0] > 0.9, "the hangar keeps its air behind the field (%.2f)" % server.air.air[front0])

	# getting in
	var a = _at_dock(0, "Аня")
	var pkt: PackedByteArray = sh.packet()
	_expect(pkt[0] == Net.S_SHUTTLE and pkt[1] == 0 and pkt[2] == 255 and pkt[4] == 0, "the clients are told it waits, empty")
	sh.asked(a, Net.SHUTTLE_BOARD, 0)
	_expect(a.in_shuttle and sh.riders.has(a), "a person at the console gets in")
	pkt = sh.packet()
	_expect(pkt[4] == 1 and pkt.decode_u16(5) == a.slot, "and the clients are told who is aboard")
	var was := Vector2i(a.st.x, a.st.y)
	a.inputs.append([server.tick + 1, Net.DIR_DOWN, a.last_seq + 1])
	_run(20)
	_expect(Vector2i(a.st.x, a.st.y) == was and a.inputs.is_empty(), "aboard nobody walks")
	var pirate = server.crew.new_player("Пират", 0)
	pirate.pirate = true
	_expect(not server.pirates.foe(pirate, a), "nor is anybody's foe")
	pirate.corpse = true
	var bot = null
	for q in server.players:
		if q != null and q.bot and not q.corpse and q.fleet_ship == 0:
			bot = q
			break
	var front: int = front0
	bot.st.place(front % map.width, front / map.width)
	bot.st.facing = _towards(0)
	sh.asked(bot, Net.SHUTTLE_BOARD, 0)
	_expect(not bot.in_shuttle, "bots never get in (they work aboard their own ship)")
	var b = _at_dock(0, "Боря")
	var c = _at_dock(0, "Вера")
	var d = _at_dock(0, "Гоша")
	var e = _at_dock(0, "Дина")
	for q in [b, c, d, e]:
		sh.asked(q, Net.SHUTTLE_BOARD, 0)
	_expect(sh.riders.size() == Net.SHUTTLE_SEATS and not e.in_shuttle, "four seats: the fifth stays behind")
	# getting out before it flies
	sh.asked(d, Net.SHUTTLE_LEAVE, 0)
	_expect(not d.in_shuttle and sh.riders.size() == 3 and map.fleet_of(d.st.y * map.width + d.st.x) == 0, "one gets out again, in the same hangar")
	sh.asked(e, Net.SHUTTLE_BOARD, 0)
	_expect(e.in_shuttle, "and makes room for another")
	sh.asked(d, Net.SHUTTLE_FLY, 1)
	_expect(not sh.flying(), "only one aboard flies it")

	# the flight
	sh.asked(a, Net.SHUTTLE_FLY, 1)
	_expect(sh.flying() and sh.to == 1, "a passenger flies it to the second ship")
	_expect(map.fleet_of(a.st.y * map.width + a.st.x) == 1, "their view goes to the far hangar at once")
	sh.asked(a, Net.SHUTTLE_LEAVE, 0)
	_expect(a.in_shuttle, "in flight there is no getting out")
	_run(roundi(Net.SHUTTLE_SECONDS * Net.TICK_HZ) - 5)
	_expect(sh.flying() and a.in_shuttle, "the flight takes %d s" % roundi(Net.SHUTTLE_SECONDS))
	_run(10)
	_expect(not sh.flying() and sh.at == 1 and sh.riders.is_empty(), "it lands at the second ship")
	var spots := {}
	var room: int = map.room_of[int((sh.docks[1] as Dictionary)["front"])]
	var ok := true
	for q in [a, b, c, e]:
		var cell: int = q.st.y * map.width + q.st.x
		if q.in_shuttle or map.walk[cell] != 1 or map.room_of[cell] != room or spots.has(cell):
			ok = false
		spots[cell] = true
	_expect(ok, "everyone steps out into its hangar, each on a cell of their own")
	server.fleet.use_for(a)
	_expect(server.fleet.on == 1, "and is aboard the second ship")
	server.fleet.use(0)

	# calling it back, empty
	d = _at_dock(0, "Ева")
	sh.asked(d, Net.SHUTTLE_CALL, 0)
	_expect(sh.flying() and sh.to == 0 and sh.riders.is_empty(), "called from the first ship's console, it comes over empty")
	_run(roundi(Net.SHUTTLE_SECONDS * Net.TICK_HZ) + 2)
	_expect(sh.at == 0 and not sh.flying(), "and waits there")
	sh.asked(d, Net.SHUTTLE_CALL, 0)
	_expect(not sh.flying(), "(called where it stands, it stays)")

	server.stop()
	server.free()
	print("SHUTTLETEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _towards(i: int) -> int:
	## The way one faces the dock console from the floor in front of it.
	var dock: Dictionary = server.shuttle.docks[i]
	return Net.DIR_UP if int(dock["console"]) < int(dock["front"]) else Net.DIR_DOWN


func _at_dock(i: int, who: String):
	## A new player of ours standing at that ship's dock console.
	var p = server.crew.new_player(who, i)
	var front: int = int((server.shuttle.docks[i] as Dictionary)["front"])
	p.st.place(front % server.map.width, front / server.map.width)
	p.st.facing = _towards(i)
	_expect(server.shuttle.dock_at(p) == i, "(%s at the dock console)" % who)
	return p


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
