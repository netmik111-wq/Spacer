extends SceneTree
## Checks the ship's guns against a pirate ship, on a real server stepped by hand:
##   godot --headless --path . --script res://tools/guntest.gd
## Guns charge with power and fire only from the gun console at a pirate ship
## that has not docked yet. Enough hits wreck it before it docks, and pay for
## it; meanwhile its shots hole the hull or put things out of order. The guns
## aim at its systems: with its guns out it does not shoot, with its engine out
## it cannot dock, its crew mends them, and with its boarders dead it breaks
## off. Left alone, it docks by force.
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
	_expect(pkt[pkt.size() - 1 - Net.ESYS_COUNT * 2] == Net.ESYS_COUNT and pkt[pkt.size() - 2 - Net.ESYS_COUNT * 2] == Net.ESYS_HELM,
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
