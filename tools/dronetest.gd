extends SceneTree
## Checks the pirate ship's crew at their posts, the scouting drone and the
## ransom (v54), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/dronetest.gd
## Its crew stand at their posts, walk to what our hits knocked out and mend it
## only there; hits into a room wound those in it, never kill (the author);
## a probe shows them for a while. The drone flies over from the drone monitor,
## goes where it is steered, shows the rooms it enters and the crew near it,
## runs out of battery, is lost when the enemy goes, and its blast wears the
## system in its room through the shield. A beaten ship may offer a ransom:
## it holds its fire, taking it pays and sends it off, a shot of ours ends it.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const EnemyCrew := preload("res://src/server/enemy_crew.gd")
const Drone := preload("res://src/server/drone.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26330, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false              # (v56) shots land the moment they are fired here
	var map := server.map
	var g: Gunnery = server.gunnery
	var d: Derelict = server.derelict
	var crew: EnemyCrew = server.enemy_crew
	var drone: Drone = server.drone
	g.enemy_hit_chance = 0.0
	g.ransom_chance = 0.0
	server.ship.shield_on = false
	_expect(map.drone_console.size() == 1, "the bridge has a drone monitor")

	# its crew at their posts
	server.shipyard.force_class = Net.ECLASS_RAIDER
	_expect(d.pirates_come(2, true), "a raider comes")
	var n: int = d._pirates_party
	_expect(crew.count() == n and n >= 2, "its crew (%d) are aboard at their posts" % n)
	_expect(crew.manned(Net.ESYS_HELM), "somebody flies it")
	for i in crew.count():
		_expect(crew.passable(crew.at[i]), "each stands on its floor")
	_expect(_ecrew(crew.packet()) == 0, "we see none of them yet")

	# they go to mend what our hits knocked out, and mend it there only
	var guns_room := g.room_of_system(Net.ESYS_WEAPONS)
	g.systems[Net.ESYS_WEAPONS] = 0
	_run(Net.TICK_HZ * 8)
	_expect(crew.in_room(guns_room) > 0 and crew.menders(Net.ESYS_WEAPONS) > 0, "somebody walks to its knocked out guns and mends them")
	_run(roundi(Gunnery.ENEMY_REPAIR_SECONDS * Net.TICK_HZ) + 2)
	_expect(g.systems[Net.ESYS_WEAPONS] >= 1, "and gets them working again")
	g.systems[Net.ESYS_ENGINE] = 0
	var hold := []
	for i in crew.count():
		hold.append(crew.at[i])
	var quarters := g.room_of_system(Net.ESYS_CREW)
	for i in crew.count():
		crew.at[i] = (map.others[d.layout].rooms[quarters] as PackedInt32Array)[0]
		crew.dest[i] = crew.at[i]
	var engine_before: int = g.systems[Net.ESYS_ENGINE]
	g._mend_tick()
	_expect(crew.menders(Net.ESYS_ENGINE) == 0 and g.systems[Net.ESYS_ENGINE] == engine_before, "nobody in its room: nothing mends it")
	_expect(not crew.manned(Net.ESYS_WEAPONS) and not crew.manned(Net.ESYS_HELM), "with all of them in the quarters its guns and cockpit stand empty")
	var hit := g._hit_chance(Weapons.LASER)
	_expect(is_equal_approx(hit, float(Weapons.info(Weapons.LASER)["hit"])), "with nobody in its cockpit it cannot dodge")

	# hits into a room find those in it: they are wounded, never killed (the author)
	var before := crew.count()
	var wounded := false
	for k in 40:
		var said := g.crew_hit(quarters)
		if said.contains("Ранен"):
			wounded = true
			break
	_expect(wounded and crew.count() == before, "a hit into their room wounds them and kills nobody (%d of %d)" % [crew.count(), before])
	_expect(g.boarders_left() == crew.count() and d._pirates_party == crew.count(), "its crew count stands (%d)" % crew.count())

	# a probe shows them for a while
	server.ship.store[Net.ITEM_PROBE] = 1
	var p := server.crew.new_player("Канонир")
	var gc: int = map.gun_console.keys()[0]
	_place(p, gc, Net.DIR_DOWN)
	g.probe_asked(p)
	_run(1)
	_expect(crew.shown() and _ecrew(crew.packet()) == crew.count(), "a probe shows every one of them")
	_run(roundi(EnemyCrew.PROBE_SECONDS * Net.TICK_HZ) + 2)
	_expect(not crew.shown() and _ecrew(crew.packet()) == 0, "for %d s" % int(EnemyCrew.PROBE_SECONDS))

	# the drone
	var dc: int = map.drone_console.keys()[0]
	var q := server.crew.new_player("Оператор")
	drone.spotted = 0.0                          # (nobody shoots it down until the check of that below)
	server.ship.store[Net.ITEM_DRONE] = 1
	drone.asked(p, Net.DRONE_LAUNCH, 0)
	_expect(drone.state == Net.DRONE_NONE, "the drone is not launched from the gun console")
	_place(q, dc, Net.DIR_UP)
	_expect(server.systems.at_console(q, map.drone_console), "(standing at the drone monitor)")
	drone.asked(q, Net.DRONE_LAUNCH, 0)
	_expect(drone.state == Net.DRONE_FLYING and int(server.ship.store[Net.ITEM_DRONE]) == 0, "from the drone monitor it flies, taken from the cargo")
	g.revealed.fill(0)
	_run(roundi(Drone.FLY_SECONDS * Net.TICK_HZ) + 1)
	_expect(drone.inside() and drone.room() >= 0, "it gets inside, into a room")
	_expect(g.revealed[drone.room()] == 1, "the room it is in is known now")
	var start := drone.at
	var moved := false
	for dir in [Net.DIR_LEFT, Net.DIR_RIGHT, Net.DIR_UP, Net.DIR_DOWN]:
		drone.asked(q, Net.DRONE_STEER, dir)
		_run(Drone.STEP_TICKS * 2 + 1)
		if drone.at != start:
			moved = true
			break
	_expect(moved and drone.inside(), "it goes where it is steered")
	drone.asked(q, Net.DRONE_STEER, Net.DIR_NONE)
	# walk it through every room it can reach: each becomes known
	var o = map.others[d.layout]
	var rooms_seen := {}
	for k in 400:
		if not drone.inside():
			break
		rooms_seen[drone.room()] = true
		var goal := -1
		for r in o.rooms.size():
			if g.revealed[r] == 0:
				goal = (o.rooms[r] as PackedInt32Array)[0]
				break
		if goal < 0:
			break
		var next := crew._step_towards(drone.at, goal)
		var dir := _dir_to(o, drone.at, next)
		drone.asked(q, Net.DRONE_STEER, dir)
		_run(Drone.STEP_TICKS)
	drone.asked(q, Net.DRONE_STEER, Net.DIR_NONE)
	_expect(g.revealed.count(0) == 0 or not drone.inside(), "steered through the ship, it shows every room (%d of %d known)" % [g.revealed.count(1), g.revealed.size()])
	if drone.inside():
		# it sees those in its room (hits earlier on may have left nobody: then one more is aboard)
		if crew.count() == 0:
			g.systems[Net.ESYS_CREW] = Gunnery.HITS_PER_BOARDER
			d._pirates_party = 1
			crew.board(1, d.layout)
		crew.at[0] = drone.at
		crew.dest[0] = drone.at
		_expect(_ecrew(crew.packet()) >= 1, "it sees a pirate in its room")
		# its blast wears the system in its room through the shield
		var room_sys := g.room_of_system(Net.ESYS_HELM)
		drone.at = (o.rooms[room_sys] as PackedInt32Array)[0]
		g.enemy_shield = Weapons.SHIELD_FULL
		var helm: int = g.systems[Net.ESYS_HELM]
		var hull := g.enemy_hull
		drone.asked(q, Net.DRONE_BLOW, 0)
		_expect(drone.state == Net.DRONE_NONE and g.systems[Net.ESYS_HELM] == maxi(helm - Drone.BLAST, 0) and g.enemy_hull == hull - 1,
			"blown up in a room, it wears the system there by %d through a full shield" % Drone.BLAST)
	# a second drone: pirates in its room shoot it down; a third: its battery runs out
	server.ship.store[Net.ITEM_DRONE] = 2
	drone.asked(q, Net.DRONE_LAUNCH, 0)
	_run(roundi(Drone.FLY_SECONDS * Net.TICK_HZ) + 1)
	_expect(drone.inside(), "another drone gets in")
	drone.spotted = 1.0
	crew.hurt_until[0] = 0
	for t in Net.TICK_HZ + 1:
		crew.at[0] = drone.at
		crew.dest[0] = drone.at
		server._tick()
	_expect(drone.state == Net.DRONE_NONE, "pirates in its room spot it and shoot it down")
	drone.spotted = 0.0
	drone.asked(q, Net.DRONE_LAUNCH, 0)
	_run(roundi((Drone.FLY_SECONDS + Drone.BATTERY_SECONDS - 1.0) * Net.TICK_HZ))
	_expect(drone.inside(), "a third one flies a minute")
	_run(Net.TICK_HZ + 2)
	_expect(drone.state == Net.DRONE_NONE, "and its battery runs out after %d s" % int(Drone.BATTERY_SECONDS))
	# a third: lost when the enemy goes
	server.ship.store[Net.ITEM_DRONE] = 1
	drone.asked(q, Net.DRONE_LAUNCH, 0)
	_run(roundi(Drone.FLY_SECONDS * Net.TICK_HZ) + 1)
	g._escaped()
	_run(2)
	_expect(drone.state == Net.DRONE_NONE and crew.count() == 0, "when the enemy goes, the drone is lost and its crew with it")
	drone.asked(q, Net.DRONE_LAUNCH, 0)
	_expect(drone.state == Net.DRONE_NONE, "with no enemy alongside no drone is sent")

	# the ransom
	g.ransom_chance = 1.0
	server.shipyard.force_class = Net.ECLASS_RAIDER
	_expect(d.pirates_come(2, true), "another raider")
	g.temper = Net.TEMPER_CALCULATING
	g.enemy_hit_chance = 1.0
	g.enemy_hull = 2
	_run(1)
	_expect(g.ransom > 0 and not g.fleeing(), "beaten, it offers a ransom (%d) instead of running" % g.ransom)
	var holes := server.air.holes.size()
	server.ship.broken.clear()
	_run(Net.TICK_HZ * 12)
	_expect(server.air.holes.size() == holes and server.ship.broken.is_empty(), "it holds its fire while the offer stands")
	var credits := server.ship.credits
	var fuel := int(server.ship.store.get(Net.ITEM_FUEL, 0))
	g.ransom_taken(p)
	_expect(not d.here and server.ship.credits > credits and int(server.ship.store[Net.ITEM_FUEL]) == fuel + 1, "taken: we are paid and it goes")
	_expect(d.pirates_come(2, true), "and another")
	g.temper = Net.TEMPER_CAUTIOUS
	g.enemy_hull = 2
	_run(1)
	_expect(g.ransom > 0, "it offers a ransom")
	g.charge.fill(1.0)
	server.ship.armed.fill(1)
	g.enemy_hit_chance = 0.0
	g._rng.seed = 7
	g.fire(p, 255)
	_expect(not g.fighting() or (g.ransom == 0 and g.fleeing()), "a shot of ours ends the offer: it runs")
	if d.here:
		d._leave(true)
	_expect(d.pirates_come(2, true), "and one more")
	g.temper = Net.TEMPER_RECKLESS
	g.enemy_hull = 1
	_run(1)
	_expect(g.ransom == 0 and not g.fleeing(), "a reckless one neither runs nor offers anything")
	g.temper = Net.TEMPER_HUNTER
	_run(1)
	_expect(g.ransom > 0, "(a hunter offers)")
	_run(roundi(Gunnery.RANSOM_SECONDS * Net.TICK_HZ) + 2)
	_expect(g.ransom == 0 and (g.fleeing() or not g.fighting()), "nobody answers in %d s: it runs" % int(Gunnery.RANSOM_SECONDS))

	# (v54, the author's word) a raider boards only when we can neither fight nor run
	if d.here:
		d._leave(true)
	_expect(d.pirates_come(2, true), "a raider, to see when it boards")
	g.ransom_chance = 0.0
	g.temper = Net.TEMPER_RECKLESS
	server.ship.store[Net.ITEM_FUEL] = 3
	_run(2)
	_expect(d._pirates_dock_at < 0, "while a gun of ours can fire it keeps its distance")
	for i in server.ship.mounts.size():
		server.ship.broken[map.guns[i]] = true
	_run(2)
	_expect(d._pirates_dock_at < 0, "with our guns silent but a jump to be had, it still keeps off")
	for c: int in map.chart.keys():
		server.ship.broken[c] = true
	_run(2)
	_expect(d._pirates_dock_at >= 0 and not d.docked, "guns silent and no jump: it closes in to board")
	server.ship.broken.erase(map.guns[0])
	_run(2)
	_expect(d._pirates_dock_at < 0, "a gun mended in time: it pulls back")
	server.ship.broken[map.guns[0]] = true
	_run(Derelict.RAID_BOARD_TICKS + 10)
	var boarders := 0
	for who in server.players:
		if who != null and who.pirate and not who.corpse:
			boarders += 1
	_expect(d.docked and boarders > 0, "otherwise it docks by force and its crew comes aboard (%d)" % boarders)
	# (2026-10-19) undocking from it sends it away; it used to stay, fight on and board again every 30 s
	for who in server.players:
		if who != null and who.pirate and not who.corpse:
			server.crew.remove(who)
	_expect(d.dock(false) == "", "(we undock from it)")
	_run(Derelict.RAID_BOARD_TICKS + 10)
	var again := 0
	for who in server.players:
		if who != null and who.pirate and not who.corpse:
			again += 1
	_expect(not d.here and not g.fighting() and again == 0, "undocked, it goes and does not board again (%d aboard)" % again)

	print("DRONETEST %s" % ("OK" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _ecrew(pkt: PackedByteArray) -> int:
	return pkt[4]


func _dir_to(o, from: int, to: int) -> int:
	var dx: int = to % o.width - from % o.width
	var dy: int = to / o.width - from / o.width
	if dx < 0:
		return Net.DIR_LEFT
	if dx > 0:
		return Net.DIR_RIGHT
	if dy < 0:
		return Net.DIR_UP
	if dy > 0:
		return Net.DIR_DOWN
	return Net.DIR_NONE


func _place(p, console: int, facing: int) -> void:
	var map := server.map
	p.st.place(console % map.width, console / map.width + (1 if facing == Net.DIR_UP else -1))
	p.st.facing = facing


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
