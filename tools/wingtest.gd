extends SceneTree
## (v86) Checks the author's fleet notes and the pirates' wingman on a real server stepped by hand:
##   godot --headless --path . --script res://tools/wingtest.gd
## Fleet notes: pirates may come alongside the second ship too; bots mend and take posts only aboard their
## own ship; the crew window is told each bot's ship; a pirate ship docked to one ship of ours is still a
## target for the other's guns; on hard both enemies pick the weaker ship.
## The wingman (the author's E1): a second pirate ship joins a fight a while in; the gun console picks which
## one our guns shoot; hits on one leave the other whole; it shoots our ships from afar, never docks; wrecked
## it pays; with the ship alongside beaten it runs; a jump leaves it behind.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26310, "ship02|ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.director.quiet_start = false
	server.gunnery.flies = false
	server.gunnery.ransom_chance = 0.0
	server.systems.knock_chance = 0.0
	server.stations.volunteers = false
	server.pirates.goals_on = false
	var fleet = server.fleet
	var d = server.derelict
	var g = server.gunnery
	var w = server.wing
	w.chance_for_test = 0.0               # (none until the checks below ask)

	# pirates may come alongside the second ship as well (v85 left it no room)
	_expect(not d._spots_of[1].is_empty(), "there is room off the second ship's airlock (%d drawings fit)" % d._spots_of[1].size())
	d.near = 1
	d._spots = d._spots_of[1]
	d._aimed_at = server.tick
	_expect(d.pirates_come(2) and g.target == 1, "a pirate ship comes alongside the second ship")
	var mid: int = (server.map.other_at.y + server.map.other.height / 2) * server.map.width + server.map.other_at.x
	_expect(server.map.fleet_near(mid) == 1, "and lies in its rows")
	_clear()

	# bots mend and take posts only aboard their own ship
	var hole := -1
	for c: int in server.map.hull:
		if server.map.fleet_of(c) == 1:
			hole = c
			break
	fleet.use(0)
	var bot0 = _bot_of(0)
	var bot1 = _bot_of(1)
	_expect(bot0 != null and bot1 != null, "each ship has bots")
	server.ship.store[Net.ITEM_PATCH] = 5
	_expect(hole >= 0 and server.air.set_hole(hole, true), "(a hole in the second ship's hull)")
	fleet.use(0)
	var jobs0: Array = server.stations._repair_jobs(bot0)
	fleet.use(1)
	server.ship.store[Net.ITEM_PATCH] = 5
	var jobs1: Array = server.stations._repair_jobs(bot1)
	fleet.use(0)
	_expect(not jobs0.has(hole) and jobs1.has(hole), "the first ship's bots leave the second's hole to its own (%s / %s)" % [str(jobs0.has(hole)), str(jobs1.has(hole))])
	server.air.set_hole(hole, false)
	var captain = server.crew.new_player("Капитан", 0)
	captain.job = Net.JOB_CAPTAIN
	server.stations.order_asked(captain, Net.NOBODY, Net.POST_ALL)
	var helm := [0, 0]
	for q in server.players:
		if q != null and q.bot and not q.corpse and q.order == Net.POST_HELM:
			helm[q.fleet_ship] += 1
	_expect(helm[0] == 1 and helm[1] == 1, "«Все по местам»: each ship's helm gets a bot of its own crew (%s)" % str(helm))
	var pkt: PackedByteArray = server.stations.packet()
	var n: int = pkt[10]
	var ships := {}
	for i in n:
		ships[pkt[11 + i * 5 + 4]] = true
	_expect(n > 0 and ships.has(0) and ships.has(1), "the crew window is told each bot's ship")

	# a pirate ship docked to one ship of ours is still a target for the other
	d.near = 0
	d._spots = d._spots_of[0]
	d._aimed_at = server.tick
	_expect(d.pirates_come(2), "(another pirate ship comes, to the first ship)")
	d._pirates_dock_at = server.tick
	_run(2)
	_expect(d.docked and g.target == 0, "it docks to the first ship by force")
	fleet.use(0)
	_expect(not g.engaged(), "the first ship's guns cannot reach it any more")
	fleet.use(1)
	_expect(g.engaged() and g.fighting(), "but the second ship's can")
	var gunner = _at_guns(1)
	var hull: int = g.enemy_hull
	for i in 10:                             # (until a shot gets through)
		fleet.use(1)
		g.enemy_shield = 0.0
		g.charge.fill(1.0)
		g.fire(gunner, 255)
		_run(1)
		fleet.use(1)
		if g.enemy_hull < hull:
			break
	fleet.use(1)
	_expect(g.enemy_hull < hull or g.enemy_hull == 0, "and its shots land (%d -> %d)" % [hull, g.enemy_hull])
	fleet.use(0)
	_clear()

	# on hard both pick the weaker ship
	server.mode = Net.MODE_HARD
	fleet.ships[1].hull = fleet.ships[1].hull_max / 2
	var weaker := 0
	for i in 200:
		if fleet.target() == 1:
			weaker += 1
	_expect(weaker == 200, "on hard pirates always go for the weaker ship (%d of 200)" % weaker)
	server.mode = Net.MODE_NORMAL
	fleet.ships[1].hull = fleet.ships[1].hull_max

	# the wingman
	d.near = 0
	d._spots = d._spots_of[0]
	d._aimed_at = server.tick
	w.chance_for_test = 1.0
	_expect(d.pirates_come(2), "a pirate ship comes alongside")
	d._pirates_dock_at = server.tick + 100000
	_run(2)
	_expect(w.join_at > server.tick and not w.here, "a wingman is due a while into the fight (in %d s)" % ((w.join_at - server.tick) / Net.TICK_HZ))
	w.join_at = server.tick
	_run(1)
	_expect(w.here and w.engaged(1) and g.fighting(), "it comes out of the dark and fights")
	_expect(w.value(1, "raid") and int(w.value(1, "enemy_hull")) > 0 and not d.docked, "at a distance, with a hull of its own")
	var lead_hull: int = g.enemy_hull
	var wing_hull: int = int(w.value(1, "enemy_hull"))
	gunner = _at_guns(0)
	pkt = g.packet()
	_expect(pkt[pkt.size() - 11] == 0 and pkt[pkt.size() - 5] == 1 and pkt[pkt.size() - 10] == 1, "the gun console is told of both, aiming at the first")
	g.setup_asked(gunner, Net.GUNSET_FOE, 1, 0)
	_expect(g.foe == 1 and g.aim == Net.AIM_ANY, "the gun console turns our guns on the wingman")
	for i in 10:
		w.use(1)
		g.enemy_shield = 0.0
		w.use(0)
		g.charge.fill(1.0)
		g.fire(gunner, 255)
		if int(w.value(1, "enemy_hull")) < wing_hull:
			break
	_expect(g.enemy_hull == lead_hull and int(w.value(1, "enemy_hull")) < wing_hull,
		"our shots hit the wingman, not the ship alongside (%d -> %d)" % [wing_hull, int(w.value(1, "enemy_hull"))])
	_expect(w.on == 0, "and the ship alongside is in place again after")
	pkt = g.packet()
	_expect(pkt[pkt.size() - 11] == 1, "the console is told it aims at the wingman")
	# wrecked, it pays
	var credits: int = server.ship.credits
	for i in 30:
		w.use(1)
		g.enemy_shield = 0.0
		w.use(0)
		g.charge.fill(1.0)
		g.fire(gunner, 255)
		_run(1)
		if not w.here:
			break
	_expect(not w.here and server.ship.credits > credits, "wrecked, the wingman is paid for (%d; here %s, hull %s, alongside %s)" % [
		server.ship.credits - credits, str(w.here), str(w.value(1, "enemy_hull")), str(g.alive())])
	_expect(g.foe == 0 and d.here and g.engaged(), "our guns turn back to the ship alongside, which fights on")
	_clear()

	# with the ship alongside beaten it runs
	d.near = 0
	d._spots = d._spots_of[0]
	d._aimed_at = server.tick
	_expect(d.pirates_come(2), "(another pirate ship comes)")
	d._pirates_dock_at = server.tick + 100000
	_run(1)
	w.join_at = server.tick
	_run(1)
	_expect(w.here, "(and its wingman)")
	g.foe = 0
	for i in 40:
		g.enemy_shield = 0.0
		g.charge.fill(1.0)
		g.fire(gunner, 255)
		_run(1)
		if not g.alive():
			break
	_run(2)
	_expect(not g.alive() and w.here and float(w.value(1, "flee")) >= 0.0, "the ship alongside beaten, the wingman charges its jump")
	_run(roundi(w.LAST_RUN * Net.TICK_HZ) + 40)
	_expect(not w.here, "and gets away if not stopped")
	_clear()

	# a jump leaves it behind
	d.near = 0
	d._spots = d._spots_of[0]
	d._aimed_at = server.tick
	d.pirates_come(2)
	_run(1)
	w.join_at = server.tick
	_run(1)
	_expect(w.here, "(a wingman again)")
	w.jumped()
	_expect(not w.here and not w.engaged(1), "a jump leaves it behind")

	# it shoots at us (last: its hits may break what the checks above need)
	_clear()
	d.near = 0
	d._spots = d._spots_of[0]
	d._aimed_at = server.tick
	d.pirates_come(2)
	d._pirates_dock_at = server.tick + 100000
	_run(1)
	w.join_at = server.tick
	_run(1)
	_expect(w.here, "(a wingman again)")
	var ours := _ours()
	var holes: int = server.air.holes.size()
	for i in 40:
		w.use(1)
		g.enemy_hit_chance = 1.0
		g.enemy_charge.fill(1.0)
		w.use(0)
		_run(1)
		if _ours() < ours or server.air.holes.size() > holes:
			break
	_expect(_ours() < ours or server.air.holes.size() > holes, "it fires at our ships from afar (%d -> %d)" % [ours, _ours()])

	# (v87, the author's note: the second ship never fired) each ship's guns charge on their own
	_clear()
	for i in 2:                                      # (whole again after the wingman's hits above)
		fleet.use(i)
		server.ship.broken.clear()
		server.ship.jammed.clear()
		server.ship.hull = server.ship.hull_max
		server.power.set_charge(1.0)
	fleet.use(0)
	fleet.use(0)
	g.charge.fill(1.0)
	fleet.use(1)
	g.charge.fill(1.0)
	fleet.use(0)
	g.charge.fill(0.0)
	fleet.use(1)
	_expect(g.charge.size() > 0 and g.charge[0] >= 1.0, "(v87) emptying the first ship's guns leaves the second's charged")
	fleet.use(0)
	# both ships' bots at the gun consoles fire in a fight
	d.near = 0
	d._spots = d._spots_of[0]
	d._aimed_at = server.tick
	_expect(d.pirates_come(2), "(a pirate ship comes)")
	d._pirates_dock_at = server.tick + 100000
	var shots := [0, 0]
	var before := [PackedFloat32Array(), PackedFloat32Array()]
	for t in 600:
		for i in 2:
			fleet.use(i)
			g.enemy_hull = maxi(g.enemy_hull, 3)          # (kept alive: the count is what matters)
			g.enemy_charge.fill(0.0)                      # (and harmless: its hits may break a console or a gun)
			before[i] = g.charge.duplicate()
		fleet.use(0)
		_run(1)
		for i in 2:
			fleet.use(i)
			for k in g.charge.size():
				if g.charge[k] < before[i][k] - 0.5:
					shots[i] += 1
		fleet.use(0)
	var posted := [0, 0]
	for q in server.players:
		if q != null and q.bot and not q.corpse and q.order == Net.POST_GUNS:
			fleet.use(q.fleet_ship)
			posted[q.fleet_ship] += 1 if server.systems.at_console(q, server.map.gun_console) else 0
	fleet.use(0)
	_expect(shots[0] > 0 and shots[1] > 0, "(v87) both ships' gunner bots fire (%s; at the consoles %s)" % [str(shots), str(posted)])
	# (v87, the author's note: after beating a pirate ship called by the admin, no other could be called)
	g._wrecked()
	_run(2)
	_expect(d.here and d.wreck, "(the beaten ship stays alongside as a wreck)")
	server.admin.fight(1, 0, false)
	_expect(d.here and not d.wreck and g.alive(), "(v87) the admin's call lets the wreck drift off and a new pirate ship comes")
	_expect(server.road.hulks.size() > 0, "and the wreck is kept on the chart")

	server.stop()
	server.free()
	print("WINGTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _clear() -> void:
	## Takes away whatever is alongside, and the wingman.
	server.wing.jumped()
	if server.derelict.here:
		server.derelict.pirates_wrecked()
		server.derelict._leave()
	server.gunnery.foe = 0
	server.fleet.use(1)
	server.gunnery.foe = 0
	server.fleet.use(0)
	_run(2)


func _ours() -> int:
	## Our ships' hulls and shields, all told.
	var n := 0
	for s in server.fleet.ships:
		n += s.hull + int(s.shield)
	return n


func _bot_of(ship: int):
	for q in server.players:
		if q != null and q.bot and not q.corpse and not q.pirate and q.fleet_ship == ship:
			return q
	return null


func _at_guns(ship: int):
	## A player at that ship's gun console (that ship in place after).
	server.fleet.use(ship)
	var map = server.map
	var console: int = map.gun_console.keys()[0]
	var p = server.crew.new_player("Канонир %d" % ship, ship)
	server.fleet.use(ship)
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN
	if not server.systems.at_console(p, map.gun_console):
		p.st.place(console % map.width, console / map.width + 1)
		p.st.facing = Net.DIR_UP
	_expect(server.systems.at_console(p, map.gun_console), "(standing at ship %d's gun console)" % (ship + 1))
	return p


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
