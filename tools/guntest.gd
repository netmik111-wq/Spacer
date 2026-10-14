extends SceneTree
## Checks the ship's guns against a pirate ship, on a real server stepped by hand:
##   godot --headless --path . --script res://tools/guntest.gd
## Guns charge with power and fire only from the gun console at a pirate ship
## that has not docked yet. Enough hits wreck it before it docks, and pay for
## it; meanwhile its shots hole the hull or put things out of order. The guns
## aim at its systems: with its guns out it does not shoot, with its engine out
## it cannot dock, its crew mends them, and with its boarders dead it breaks
## off. Left alone, it docks by force.
## A raider (v44) fights at a distance and never docks; beaten badly it charges
## its jump drive and runs in 20 s, slower with the drive worn, never with the
## drive or its engine out. Wrecked, it stays alongside, dark, and can be docked
## with; the first of the crew aboard finds its crew dead, fighting, or joining.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26290, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	var g: Gunnery = server.gunnery
	var d: Derelict = server.derelict
	_expect(map.guns.size() == 3 and map.gun_console.size() == 1, "the ship has three guns and a gun console")

	var p := server.crew.new_player("Канонир")
	var console: int = map.gun_console.keys()[0]
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN
	_expect(server.systems.at_console(p, map.gun_console), "(standing at the gun console)")

	g.charge.fill(0.0)
	_run(Net.TICK_HZ * 4)
	_expect(g.charge[0] > 0.4 and g.charge[0] < 0.6, "a gun charges by itself (%.2f after 4 s)" % g.charge[0])
	_run(Net.TICK_HZ * 5)
	_expect(g.charge[0] >= 1.0, "and is ready in %d s" % int(Gunnery.CHARGE_SECONDS))

	g.fire(p, 255)
	_expect(g.charge[0] >= 1.0, "with nobody to shoot at it does not fire")
	_expect(d.pirates_come(2) and g.fighting(), "a pirate ship comes and the fight is on")
	var stranger := server.crew.new_player("Мимо")
	g.fire(stranger, 255)
	_expect(g.charge[0] >= 1.0, "only from the gun console")
	g.aim_asked(stranger, Net.ESYS_ENGINE)
	_expect(g.aim == Net.AIM_ANY, "only the gun console aims the guns")
	g.aim_asked(p, Net.ESYS_HELM)
	_expect(g.aim == Net.ESYS_HELM, "the gun console aims them at the enemy's bridge")
	var pkt := g.packet()
	_expect(pkt[pkt.size() - 4 - Net.ESYS_COUNT * 2] == Net.ESYS_COUNT and pkt[pkt.size() - 5 - Net.ESYS_COUNT * 2] == Net.ESYS_HELM,
		"clients are told where the guns aim and how the enemy's systems are")
	var credits := server.ship.credits
	for i in 20:
		g.charge.fill(1.0)
		g.fire(p, 255)
		if not d.here:
			break
	_expect(not d.here and g.enemy_hull == 0, "enough hits wreck it before it docks")
	_expect(server.ship.credits == credits + Gunnery.WRECK_REWARD, "and the ship is paid for it")
	_expect(server.pirates.aboard() == 0, "its crew goes down with it")

	# its systems
	g.enemy_hit_chance = 1.0
	_expect(d.pirates_come(2), "another one comes")
	g.aim_asked(p, Net.ESYS_WEAPONS)
	_shoot_until(p, func() -> bool: return g.down(Net.ESYS_WEAPONS))
	_expect(g.down(Net.ESYS_WEAPONS) and d.here, "hits on its gun room put its guns out of action")
	g._mend_next = server.tick + 100000
	var holes := server.air.holes.size()
	server.ship.broken.clear()
	for t in 30 * Net.TICK_HZ:
		server._tick()
	_expect(server.air.holes.size() == holes and server.ship.broken.is_empty(), "with its guns out it does not shoot")
	g.aim_asked(p, Net.ESYS_ENGINE)
	_shoot_until(p, func() -> bool: return g.down(Net.ESYS_ENGINE))
	var dock_at: int = d._pirates_dock_at
	for t in 5 * Net.TICK_HZ:
		server._tick()
	_expect(g.down(Net.ESYS_ENGINE) and d._pirates_dock_at == dock_at + 5 * Net.TICK_HZ, "with its engine out it cannot close in: the time to dock stands still")
	g._mend_next = server.tick + 1
	_run(2)
	_expect(not g.down(Net.ESYS_WEAPONS) or not g.down(Net.ESYS_ENGINE), "its crew mends a system after a while")
	credits = server.ship.credits
	g.enemy_hull = Gunnery.ENEMY_HULL
	g.aim_asked(p, Net.ESYS_CREW)
	_shoot_until(p, func() -> bool: return not d.here)
	_expect(not d.here and g.enemy_hull == 0 and server.ship.credits == credits, "hits on its quarters kill the boarding party, and it breaks off (unpaid)")
	_expect(server.pirates.aboard() == 0, "nobody comes aboard")

	# it shoots back
	holes = server.air.holes.size()
	_expect(d.pirates_come(1), "and another")
	var hurt := false
	for t in 35 * Net.TICK_HZ:
		server._tick()
		if server.air.holes.size() > holes + 0 or not server.ship.broken.is_empty():
			hurt = true
			break
	_expect(hurt, "its shots hole the hull or put something out of order")
	g.charge.fill(0.0)
	server.ship.broken.clear()
	for t in (Derelict.PIRATE_WARNING_TICKS + 20):
		server._tick()
	_expect(d.docked and not g.fighting(), "left alone, it docks by force and the guns fall silent")
	d.dock(false)
	_run(2)
	_expect(not d.here, "(drawn off, it goes)")
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)

	# a raid: a fight at a distance
	# (the gunner breathes from a tank and is patched up: the hull around the console may be holed by now)
	p.supply = true
	p.tank = 1.0e9
	p.health = 100.0
	p.wounds = 0.0
	p.cond = Net.COND_OK
	p.st.down = false
	server.ship.broken.clear()
	g.enemy_hit_chance = 0.0
	_expect(d.pirates_come(2, true) and g.raid and d._pirates_dock_at < 0, "a raider comes, and does not mean to dock")
	_run(Derelict.PIRATE_WARNING_TICKS + 40)
	_expect(d.here and not d.docked and g.fighting(), "left alone, it keeps fighting at a distance")
	g.enemy_hull = Gunnery.FLEE_HULL
	_run(1)
	_expect(g.fleeing() and g.jump_seconds_left() <= int(Gunnery.FLEE_SECONDS), "beaten badly, it charges its jump drive to run")
	credits = server.ship.credits
	_run(int(Gunnery.FLEE_SECONDS - 2.0) * Net.TICK_HZ)
	_expect(d.here, "it is still here a little before its jump")
	_run(3 * Net.TICK_HZ)
	_expect(not d.here and server.ship.credits == credits, "and then it jumps away, unpaid")

	_expect(d.pirates_come(2, true), "another raider")
	g._mend_next = server.tick + 1000000
	g.systems[Net.ESYS_ENGINE] = 0
	g.enemy_hull = Gunnery.FLEE_HULL
	_run(40 * Net.TICK_HZ)
	_expect(d.here and g.fleeing() and g.jump_seconds_left() == 65535, "with its engine out it cannot jump away")
	g.systems[Net.ESYS_ENGINE] = Gunnery.SYSTEM_STRENGTH
	g.systems[Net.ESYS_JUMP] = 0
	_run(40 * Net.TICK_HZ)
	_expect(d.here and g.jump_seconds_left() == 65535, "nor with its jump drive out")
	g.systems[Net.ESYS_JUMP] = 1
	g.flee = 0.0
	_run(25 * Net.TICK_HZ)
	_expect(d.here and g.jump_seconds_left() > 10, "with the drive worn the jump takes longer (%d s left after 25 s)" % g.jump_seconds_left())
	_run(20 * Net.TICK_HZ)
	_expect(not d.here, "but in the end it goes")

	# wrecked: a hulk to board
	_expect(d.pirates_come(3, true), "and another")
	credits = server.ship.credits
	var bodies_before := server.corpses.size()
	g.aim = Net.AIM_ANY
	_shoot_until(p, func() -> bool: return not g.fighting())
	_expect(d.here and d.wreck and server.ship.credits == credits + Gunnery.WRECK_REWARD, "wrecked, it stays alongside, and the ship is paid for it")
	_expect(d.dark() and d.ship.kind == Net.SHIP_WRECK, "dark and dead, and clients are told it is a wreck")
	var dead_aboard := server.corpses.size() - bodies_before
	_expect(dead_aboard == d._crew_total - d._pirates_party, "its dead lie aboard (%d of %d)" % [dead_aboard, d._crew_total])
	var why := d.dock(true)
	_expect(why == "" and d.docked, "it can be docked with")
	d._outcome = "fight"
	d._pirates_party = 2
	var boarder := server.crew.new_player("Абордажник")
	var floor: int = d._floor_cells()[0]
	boarder.st.place(floor % map.width, floor / map.width)
	_run(1)
	_expect(server.pirates.aboard() == 2, "survivors who fight come out when the crew boards")
	for q in server.players:
		if q != null and q.pirate and not q.corpse:
			server.crew.remove(q)
	d._boarded = false
	d._outcome = "join"
	d._pirates_party = 2
	var reserve: int = server.reserve
	_run(1)
	_expect(server.reserve == mini(reserve + 2, Net.RESERVE_MAX), "survivors who give up join the reserve")
	server.crew.remove(boarder)
	d.dock(false)
	server.ship.dest = server.ship.pos + Vector2(50, 0)
	server.ship.moving = true
	_run(2)
	_expect(not d.here and server.pirates.aboard() == 0, "when the ship moves on the wreck stays behind, with its dead")
	server.ship.moving = false


	server.stop()
	server.free()
	print("GUNTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _shoot_until(p, done: Callable) -> void:
	## Fires one gun at a time until the enemy is in the state wanted (or 30 shots).
	for i in 30:
		if done.call():
			return
		server.gunnery.charge.fill(1.0)
		server.gunnery.fire(p, 0)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
