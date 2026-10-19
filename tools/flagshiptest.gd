extends SceneTree
## Checks the goal of the game, the pirates' flagship (v57), on a real server
## stepped by hand:
##   godot --headless --path . --script res://tools/flagshiptest.gd
## The goal sector lies GOAL_JUMPS out, every game can reach it, and clients
## learn where it is. Arriving there, the flagship comes out and fights to the
## end (no running, no ransom), and no jump while it fights. The battleship
## aims at our shield generator, then the engine (a broken console spares it
## nothing here), then our guns; it grows a gun for each ship weapon we carry
## past three. The carrier's neural shots stun everybody in the room they hit,
## and its teleporter puts boarders onto our bridge while it works and is
## manned; the whole crew down with its boarders aboard loses the ship.
## Wrecking a flagship wins the game, and the voyage goes on.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Flagship := preload("res://src/server/flagship.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Hulls := preload("res://src/shared/hulls.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26350, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false
	var map := server.map
	var g: Gunnery = server.gunnery
	var d: Derelict = server.derelict
	var f: Flagship = server.flagship

	# the goal, on the chart (v64: in the fourth cluster)
	server.road.depth = Sectors.FLAG_DEPTH
	server.road.entry = Vector2i(6 * Sectors.FLAG_DEPTH, 0)
	server.road.build(server.road.entry)
	server.ship.sector = server.sectors.here
	var goal: Vector2i = server.sectors.goal
	_expect(goal != Sectors.NO_GOAL and server.sectors.kind[server.sectors.index_of(goal)] == Sectors.FLAGSHIP,
		"the flagship waits in the fourth cluster (%s)" % str(goal))
	_expect(server.sectors.locked and server.road.can_leave() != "", "while it lives, no exit lets us out of its cluster")
	var packed := server.sectors.pack()
	var again := Sectors.new()
	again.unpack(packed, 0)
	_expect(again.goal == goal and again.jumps_to_goal(again.here) == server.sectors.jumps_to_goal(server.sectors.here)
		and again.jumps_to_goal(again.here) > 0, "clients learn where it is and how far")
	_expect(f.kind() == 1 or f.kind() == 2, "the game has one of the two kinds (%d)" % f.kind())

	# arriving there: the battleship comes out
	f.forced = 1
	_arrive_at(goal)
	_expect(not d.here, "it does not come at once")
	_run(roundi(Flagship.COME_SECONDS * Net.TICK_HZ) + 2)
	_expect(d.here and g.fighting() and g.boss == 1 and g.klass == Net.ECLASS_BATTLESHIP, "a few seconds after arriving the battleship comes out")
	_expect(g.enemy_weapons.size() == 4 and g.systems_full[Net.ESYS_TELEPORT] == 0, "with our three lasers it carries four guns and no teleporter")
	var p0 := server.crew.new_player("Штурман")
	var chart_cell: int = map.chart.keys()[0]
	for s2: Array in server.stations._spots_for(chart_cell):
		_place(p0, int(s2[0]))
		p0.st.facing = int(s2[1])
		break
	server.ship.drive_ready = 0
	server.navigation.jump_asked(p0, server.sectors.neighbours(server.sectors.here)[0])
	_expect(server.ship.jump_to == Net.NO_SECTOR, "no jump while it fights")
	server.crew.remove(p0)
	_expect(d.layout == 8 and g.room_sys.count(Net.ESYS_TELEPORT) == 0, "on its own hull")
	g.enemy_hull = 2
	g.ransom_chance = 1.0
	_run(40)
	_expect(not g.fleeing() and g.ransom == 0, "beaten, it neither runs nor offers a ransom")

	# the battleship's aim
	g._rng.seed = 5
	var gen := g.shield_cell()
	server.ship.shield_on = true
	var at_gen := 0
	for i in 200:
		if g._enemy_target() == gen:
			at_gen += 1
	_expect(at_gen > 130, "it goes for our shield generator first (%d of 200)" % at_gen)
	server.ship.broken[gen] = true
	var at_engine := 0
	for i in 200:
		if map.engine.has(g._enemy_target()):
			at_engine += 1
	_expect(at_engine > 130, "with the generator down, for the engine (%d of 200)" % at_engine)
	var console: int = map.chart.keys()[0]
	server.ship.broken[console] = true
	var guns := 0
	var engine := 0
	for i in 200:
		var t := g._enemy_target()
		if map.guns.has(t):
			guns += 1
		if map.engine.has(t):
			engine += 1
	_expect(engine > 130, "a bridge console broken, it still goes for the engine: no way out here (%d)" % engine)
	server.ship.broken[map.engine.keys()[0]] = true
	guns = 0
	for i in 200:
		if map.guns.has(g._enemy_target()):
			guns += 1
	var smes := 0
	for i in 200:
		if map.smes.has(g._enemy_target()):
			smes += 1
	_expect(smes > 130 or map.smes.is_empty(), "the engine down, it goes for the SMES that carries the ship (v61) (%d)" % smes)
	for c: int in map.smes.keys():
		server.ship.broken[c] = true
	guns = 0
	for i in 200:
		if map.guns.has(g._enemy_target()):
			guns += 1
	_expect(guns > 130, "the engine and the SMES down, it goes for our guns (%d)" % guns)
	server.ship.broken.erase(map.engine.keys()[0])
	server.ship.broken.erase(console)
	server.ship.broken.erase(gen)
	# its hit on the engine darkens the ship
	g.enemy_hit_chance = 1.0
	server.ship.shield_on = false
	server.power.set_charge(0.0)             # (v61) with the SMES empty
	var hit_engine := false
	for i in 30:
		g._enemy_fires(Weapons.LASER)
		if server.engine_down():
			hit_engine = true
			break
	_expect(hit_engine and not server.powered(), "a shot at the engine breaks it, and the ship goes dark")
	server.ship.broken.clear()
	server.systems.power_changed()

	# wrecking it wins the game
	g.enemy_hull = 1
	var credits := server.ship.credits
	g._land_through(Weapons.HEAVY, -1, 0)
	g._settle()
	_expect(server.won and server.over == Net.OVER_NONE, "wrecked, it wins the game, and the voyage goes on")
	_expect(server.crew.campaign_packet()[14] == 1, "everybody is told it is won")
	_expect(server.ship.credits > credits and d.wreck, "it pays, and its wreck stays to be searched")
	d._leave(true)
	_arrive_at(goal + Vector2i(-1, 0))
	_arrive_at(goal)
	_run(roundi(Flagship.COME_SECONDS * Net.TICK_HZ) + 2)
	_expect(not d.here, "beaten, it does not come again")
	server.won = false
	# (v67, the author's O1) it no longer grows with our guns: only with time
	server.ship.mounts[0] = Weapons.SIEGE
	server.ship.mounts[1] = Weapons.PHOENIX
	server.ship.store[Weapons.item_of(Weapons.SIEGE)] = 2
	var bigger: Dictionary = server.shipyard.flagship(1, d._pirate_spots())
	_expect((bigger["weapons"] as PackedByteArray).size() == 4, "with two top guns mounted it carries no more guns than before")
	server.ship.store.erase(Weapons.item_of(Weapons.SIEGE))
	server.ship.mounts[0] = Weapons.LASER
	server.ship.mounts[1] = Weapons.LASER

	# the carrier
	f.forced = 2
	_expect(server.director.fire(server.director.FLAGSHIP_CARRIER) and g.boss == 2, "the host can call the carrier in for a test")
	_expect(g.systems_full[Net.ESYS_TELEPORT] > 0 and g.room_of_system(Net.ESYS_TELEPORT) >= 0 and d.layout == 9,
		"it has a teleporter in a room of its own, on its own hull")
	_expect(g.enemy_weapons.count(Weapons.NEURAL) == 2, "and two neural emitters")
	# a neural shot stuns everybody in the room it hits, and nobody else
	var a := server.crew.new_player("Первый")
	var b := server.crew.new_player("Второй")
	var c := server.crew.new_player("Третий")
	var bridge := f.bridge_cells()
	_expect(bridge.size() > 4, "our bridge is a room (%d cells)" % bridge.size())
	_place(a, bridge[0])
	_place(b, bridge[bridge.size() - 1])
	var away := server.crew.spawn_point()
	c.st.place(away.x, away.y)
	var said := g._stun_room(bridge[0], 40.0)
	_expect(a.health == 60.0 and b.health == 60.0 and c.health == 100.0 and a.wounds == 0.0, "a neural shot stuns both on the bridge, not the one elsewhere (%s)" % said)
	g._stun_room(bridge[0], 40.0)
	g._stun_room(bridge[0], 40.0)
	_expect(a.health == Gunnery.STUN_FLOOR, "three knock one down, but no lower than %d" % int(Gunnery.STUN_FLOOR))
	a.health = 100.0
	b.health = 100.0
	# the teleporter
	_place(a, away.y * map.width + away.x)
	_place(b, away.y * map.width + away.x)
	_expect(server.pirates.aboard() == 0, "no pirates aboard yet")
	_run(roundi(Flagship.TELEPORT_FIRST * Net.TICK_HZ) + 2)
	var on_bridge := 0
	for p in server.players:
		if p != null and p.pirate and bridge.has(p.st.y * map.width + p.st.x) and p.hold >= 0:
			on_bridge += 1
	var teleport_manned := server.enemy_crew.manned(Net.ESYS_TELEPORT)
	_expect(teleport_manned and on_bridge == Flagship.TELEPORT_PARTY, "its teleporter puts %d boarders onto our bridge (%d)" % [Flagship.TELEPORT_PARTY, on_bridge])
	_expect(f.troops == Flagship.TROOPS - Flagship.TELEPORT_PARTY, "they come out of its troops (%d left)" % f.troops)
	_expect(f.capture == 0, "while any of ours is on their feet, the ship is not taken")
	# with the teleporter knocked out, nobody more comes
	for p in server.players:
		if p != null and p.pirate:
			server.crew.remove(p)
	g.systems[Net.ESYS_TELEPORT] = 0
	g._mend_next = server.tick + 100000
	f._teleport_at = server.tick
	_run(Net.TICK_HZ)
	_expect(server.pirates.aboard() == 0, "its teleporter knocked out, it sends nobody")
	g.systems[Net.ESYS_TELEPORT] = g.systems_full[Net.ESYS_TELEPORT]
	# (its crew walk their ship: wait, a while at most, for one of them to be back at the teleporter)
	var waited := 0
	while waited < 10 * Net.TICK_HZ and server.pirates.aboard() == 0:
		f._teleport_at = server.tick
		_run(1)
		waited += 1
	_expect(server.pirates.aboard() == Flagship.TELEPORT_PARTY, "mended, it sends them again (%.1f s)" % (waited / float(Net.TICK_HZ)))
	# the whole crew down with its boarders aboard: the ship is taken
	for q in [a, b, c]:
		q.health = -5.0
	_run(2 * Net.TICK_HZ)
	_expect(f.capture > 0 and server.over == Net.OVER_NONE, "the whole crew down: the capture has begun")
	for t in 2 * Net.TICK_HZ:
		a.health = 100.0                         # (up, and kept up: the boarders hunt and may fell him again)
		server._tick()
	_expect(f.capture == 0, "one gets up: it is stopped")
	for t in (Flagship.CAPTURE_SECONDS + 2) * Net.TICK_HZ:
		for q in [a, b, c]:
			q.health = minf(q.health, -5.0)          # (nobody comes round meanwhile)
		server._tick()
	_expect(server.over == Net.OVER_CAPTURED, "nobody up for %d s: the ship is taken" % Flagship.CAPTURE_SECONDS)

	print("flagshiptest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _arrive_at(cell: Vector2i) -> void:
	## The ship is in that sector of space now, as if it had jumped there.
	server.been[Sectors.key(cell)] = true
	server.road.build(cell)
	server.ship.sector = server.sectors.here
	server.ship.pos = server.sectors.entry[server.ship.sector]
	_run(1)


func _place(p, cell: int) -> void:
	p.st.place(cell % server.map.width, cell / server.map.width)


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	if what == "":
		return
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
