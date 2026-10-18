extends SceneTree
## Checks the rolled pirate ships (v53), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/shiptest.gd
## Every pirate hull loads, has a room for each system and fits off our
## airlock. Shipyard rolls a class that may come this far out, puts each system
## in a room of its own by lot, arms it from its class's pool. A ship that comes
## is unknown inside: our sensors show a room now and then, our hits show the
## room they land in, its guns firing show its gun room, a probe from the cargo
## shows it all. The guns aim at a room; an empty room only takes hull damage.
## Its temper decides when it runs. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Shipyard := preload("res://src/server/shipyard.gd")
const Net := preload("res://src/shared/net.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26310, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false              # (v56) shots land the moment they are fired here
	var map := server.map
	var g: Gunnery = server.gunnery
	g.ransom_chance = 0.0                # (its checks of tempers are about ships that run)
	var d: Derelict = server.derelict
	var yard: Shipyard = server.shipyard

	# the hulls
	_expect(map.others.size() == Net.OTHER_MAPS.size(), "every other ship's drawing loads (%d)" % map.others.size())
	for k in range(Net.OTHER_PIRATE, map.others.size()):
		var o = map.others[k]
		var needs := Net.ESYS_COUNT if Hulls.class_of_layout(k) == Net.ECLASS_CARRIER else Net.ESYS_COUNT - 1   # (v57: only the carrier has a teleporter)
		_expect(o.rooms.size() >= needs, "%s has a room for every system (%d rooms)" % [o.map_name, o.rooms.size()])
		_expect(d._spots.has(k), "%s fits off our airlock" % o.map_name)
		_expect(Hulls.class_of_layout(k) >= 0 and (Hulls.info(Hulls.class_of_layout(k))["layouts"] as Array).has(k),
			"%s belongs to a class" % o.map_name)
	var again := ShipMap.new()
	again.load_from("pirate04", false)
	_expect(again.rooms == map.others[4].rooms, "rooms are numbered alike every time the drawing is read (server and client agree)")

	# what comes near the start, and what may come
	var seen := {}
	for i in 200:
		var design: Dictionary = yard.make(2, true, d._pirate_spots())
		seen[int(design["klass"])] = true
		_check_design(design)
	_expect(not seen.has(Net.ECLASS_GUNSHIP) and not seen.has(Net.ECLASS_CRUISER) and seen.has(Net.ECLASS_CUTTER) and seen.has(Net.ECLASS_RAIDER),
		"near the start only cutters and raiders come (%s)" % str(seen.keys()))
	for k: int in Hulls.CLASSES.keys():
		if Hulls.is_boss(k):
			continue                         # (v57: the flagships are never rolled; see flagshiptest)
		yard.force_class = k
		var design: Dictionary = yard.make(2, true, d._pirate_spots())
		_expect(int(design["klass"]) == k and int(design["hull"]) == int(Hulls.info(k)["hull"]), "a %s can be rolled (hull %d)" % [Hulls.class_name_of(k), int(design["hull"])])
	yard.force_class = -1

	# one comes: its insides unknown
	var p := server.crew.new_player("Канонир")
	_to_console(p)
	server.ship.shield_on = false
	g.enemy_hit_chance = 0.0
	yard.force_class = Net.ECLASS_GUNSHIP
	_expect(d.pirates_come(2, true) and g.fighting(), "a gunship comes for a raid")
	_expect(d.ship.layout == d.layout and d.layout >= Net.OTHER_PIRATE, "its ship carries its drawing (%d)" % d.layout)
	_expect(g.enemy_hull == int(Hulls.info(Net.ECLASS_GUNSHIP)["hull"]) and g.hull_full() == g.enemy_hull, "its hull is its class's (%d)" % g.enemy_hull)
	_expect(g.revealed.count(1) == 0, "nothing of its insides is known yet")
	var pkt := g.packet()
	_expect(pkt.size() > 0 and _rooms_in_packet(pkt).count(Net.ROOM_UNKNOWN) == g.room_sys.size(), "clients see every room unknown")
	_expect(d.ship.entry().size() > 10 and d.ship.entry()[8] == d.layout, "S_SHIPS tells clients its drawing")

	# sensors
	g._scan_next = server.tick + 1
	_run(3)
	_expect(g.revealed.count(1) == 1, "our sensors make out one room after a while")
	server.ship.power_out_until = server.tick + 100000
	server.power.set_charge(0.0)             # (v61) a stall alone is carried by the SMES
	var before := g.revealed.count(1)
	g._scan_next = server.tick + 1
	_run(3)
	_expect(not server.powered() and g.revealed.count(1) == before, "without power the sensors see nothing")
	server.ship.power_out_until = 0
	_run(1)

	# its guns firing show its gun room
	var guns_room := g.room_of_system(Net.ESYS_WEAPONS)
	g.revealed[guns_room] = 0
	g._enemy_fires(Weapons.LASER)
	_expect(g.revealed[guns_room] == 1, "its guns firing give away its gun room")

	# aiming at a room
	g.enemy_shield = 0.0
	g.systems_full[Net.ESYS_SHIELDS] = 0
	var empty := g.room_sys.find(Net.ROOM_EMPTY)
	_expect(empty >= 0, "(a gunship has rooms with nothing in them)")
	g.revealed.fill(0)
	g.aim_asked(p, Net.AIM_ROOM + empty)
	_expect(g.aim == Net.AIM_ROOM + empty, "the guns aim at a room, known or not")
	var hull := g.enemy_hull
	var sys_before := g.systems.duplicate()
	g.charge.fill(1.0)
	server.ship.armed.fill(1)
	g._our_volley(0, Weapons.LASER)
	_expect(g.enemy_hull < hull or g.revealed[empty] == 0, "a shot at an empty room ...")
	if g.enemy_hull < hull:
		_expect(g.systems == sys_before and g.revealed[empty] == 1, "... only takes hull, and shows the room is empty")
	var helm_room := g.room_of_system(Net.ESYS_HELM)
	var r := g._land_on_enemy(Weapons.LASER, Net.ESYS_HELM)
	_expect(r != "" and g.systems[Net.ESYS_HELM] < g.systems_full[Net.ESYS_HELM] and g.revealed[helm_room] == 1,
		"a hit wears the system in its room and shows it")
	g.aim_asked(p, 200)
	_expect(g.aim == Net.AIM_ROOM + empty, "a room it does not have is not aimed at")

	# the probe
	var probes := int(server.ship.store.get(Net.ITEM_PROBE, 0))
	_expect(probes == 1, "the ship sets out with one probe")
	var stranger := server.crew.new_player("Мимо")
	g.probe_asked(stranger)
	_expect(int(server.ship.store[Net.ITEM_PROBE]) == 1, "a probe is launched only from the gun console")
	server.gunnery.setup_asked(p, Net.GUNSET_PROBE, 0, 0)
	_expect(g.revealed.count(0) == 0 and g.temper_known and int(server.ship.store[Net.ITEM_PROBE]) == 0,
		"a probe shows every room and its temper, and is used up")
	pkt = g.packet()
	_expect(_rooms_in_packet(pkt).count(Net.ROOM_UNKNOWN) == 0, "clients see it all")
	g.revealed.fill(0)
	g.probe_asked(p)
	_expect(g.revealed.count(1) == 0, "with no probes left nothing happens")

	# tempers
	g.flee = -1.0
	g.temper = Net.TEMPER_RECKLESS
	g.enemy_hull = 1
	_run(2)
	_expect(not g.fleeing() and g.fighting(), "a reckless one does not run, beaten as it is")
	g.temper = Net.TEMPER_CAUTIOUS
	g.enemy_hull = g.hull_full() / 2
	_run(2)
	_expect(g.fleeing(), "a cautious one runs at half its hull")
	g.flee = -1.0
	g.temper = Net.TEMPER_CALCULATING
	g.enemy_hull = g.hull_full() / 2
	_run(2)
	_expect(not g.fleeing(), "a calculating one fights on at half its hull")

	# wrecked: paid as its class
	var credits := server.ship.credits
	g.enemy_hull = 1
	g.enemy_shield = 0.0
	for i in 40:
		if not g.fighting():
			break
		g._land_on_enemy(Weapons.HEAVY, -1, empty)
		g._settle()
	_expect(d.wreck and server.ship.credits == credits + int(Hulls.info(Net.ECLASS_GUNSHIP)["reward"]), "wrecked, it pays its class's reward")
	_expect(d.ship.name.begins_with("Обломки"), "and lies alongside as wreckage (%s)" % d.ship.name)
	d._leave(true)
	yard.force_class = -1

	# a boarding ship of each class can come and dock
	for k: int in Hulls.CLASSES.keys():
		if Hulls.is_boss(k):
			continue
		yard.force_class = k
		_expect(d.pirates_come(2) and not d.raid and d.layout >= Net.OTHER_PIRATE, "a %s can come to board" % Hulls.class_name_of(k))
		d._leave(true)
	yard.force_class = -1

	print("SHIPTEST " + ("ok" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _check_design(design: Dictionary) -> void:
	var rooms: PackedByteArray = design["room_sys"]
	var ok: bool = rooms.size() == server.map.others[int(design["layout"])].rooms.size()
	for system in Net.ESYS_COUNT:
		var n: int = rooms.count(system)
		if (system == Net.ESYS_SHIELDS and not design["shield"]) or (system == Net.ESYS_TELEPORT and not design.get("teleport", false)):
			ok = ok and n == 0
		else:
			ok = ok and n == 1
	var info: Dictionary = Hulls.info(int(design["klass"]))
	var pool: Array = info["pool"]
	for w in design["weapons"]:
		ok = ok and pool.has(w)
	ok = ok and (design["weapons"] as PackedByteArray).size() >= int((info["guns"] as Array)[0])
	if not ok:
		_expect(false, "a rolled ship has every system in a room of its own and guns from its pool: %s" % str(design))


func _rooms_in_packet(pkt: PackedByteArray) -> PackedByteArray:
	## The rooms block of an S_GUNS packet (see Net.S_GUNS).
	var n: int = pkt[3]
	var at := 4 + n * 3 + 4 + 6
	var k: int = pkt[at - 1]
	at += k * 3 + 4          # flags, jump (u16), shield
	at += 2                  # class, temper
	return pkt.slice(at + 1, at + 1 + pkt[at])


func _to_console(p) -> void:
	var map := server.map
	var console: int = map.gun_console.keys()[0]
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
