extends SceneTree
## Checks the ship's guns against a pirate ship, on a real server stepped by hand:
##   godot --headless --path . --script res://tools/guntest.gd
## Guns charge with power and fire only from the gun console at a pirate ship
## that has not docked yet. Enough hits wreck it before it docks, and pay for
## it; meanwhile its shots hole the hull or put things out of order. Left
## alone, it docks by force.
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

	var p := server._new_player("Канонир")
	var console: int = map.gun_console.keys()[0]
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN
	_expect(server._at_console(p, map.gun_console), "(standing at the gun console)")

	g.charge.fill(0.0)
	_run(Net.TICK_HZ * 4)
	_expect(g.charge[0] > 0.4 and g.charge[0] < 0.6, "a gun charges by itself (%.2f after 4 s)" % g.charge[0])
	_run(Net.TICK_HZ * 5)
	_expect(g.charge[0] >= 1.0, "and is ready in %d s" % int(Gunnery.CHARGE_SECONDS))

	g.fire(p, 255)
	_expect(g.charge[0] >= 1.0, "with nobody to shoot at it does not fire")
	_expect(d.pirates_come(2) and g.fighting(), "a pirate ship comes and the fight is on")
	var stranger := server._new_player("Мимо")
	g.fire(stranger, 255)
	_expect(g.charge[0] >= 1.0, "only from the gun console")
	var credits := server.credits
	for i in 20:
		g.charge.fill(1.0)
		g.fire(p, 255)
		if not d.here:
			break
	_expect(not d.here and g.enemy_hull == 0, "enough hits wreck it before it docks")
	_expect(server.credits == credits + Gunnery.WRECK_REWARD, "and the ship is paid for it")
	_expect(server.pirates.aboard() == 0, "its crew goes down with it")

	# it shoots back
	var holes := server.air.holes.size()
	g.enemy_hit_chance = 1.0
	_expect(d.pirates_come(1), "another one comes")
	var hurt := false
	for t in 35 * Net.TICK_HZ:
		server._tick()
		if server.air.holes.size() > holes + 0 or not server.broken.is_empty():
			hurt = true
			break
	_expect(hurt, "its shots hole the hull or put something out of order")
	g.charge.fill(0.0)
	server.broken.clear()
	for t in (Derelict.PIRATE_WARNING_TICKS + 20):
		server._tick()
	_expect(d.docked and not g.fighting(), "left alone, it docks by force and the guns fall silent")

	server.stop()
	server.free()
	print("GUNTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
