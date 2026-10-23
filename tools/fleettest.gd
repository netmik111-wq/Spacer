extends SceneTree
## (v85, the author's FS1-FS8) Checks our fleet on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/fleettest.gd
## Two ships of ours lie one below the other in one grid. Each has its own hull, fuel, lockers, power and
## bots; they fly and jump together, share one purse, pirates pick one of them (mostly the weaker), and
## the run is lost only when both are. A save keeps the second ship's own state.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0


func _initialize() -> void:
	# one ship: no fleet at all
	var one := GameServer.new()
	get_root().add_child(one)
	if one.start(26300, "ship02", 1) != "":
		quit(1)
		return
	_expect(one.fleet.size() == 1 and not one.fleet.many() and one.map.fleet_size() <= 1, "one ship: no fleet")
	one.stop()
	one.free()

	var server := GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26301, "ship02|ship02", 1)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	var fleet = server.fleet
	_expect(fleet.size() == 2 and server.map.fleet_rows.size() == 2 and server.map.fleet_rows[1] > server.map.fleet_rows[0],
		"two ships of ours, the second below the first (rows %s)" % str(server.map.fleet_rows))
	var a = fleet.ships[0]
	var b = fleet.ships[1]
	_expect(a.id != b.id and b.kind == Net.SHIP_CREW and b.purse == a, "each has its own network id; the purse is the first's")

	# bots on each (the author's FS8)
	var bots := [0, 0]
	for p in server.players:
		if p != null and p.bot and not p.pirate and not p.ally:
			var at: int = server.map.fleet_of(p.st.y * server.map.width + p.st.x)
			if at >= 0 and at == p.fleet_ship:
				bots[at] += 1
	# (the first keeps the host's place; the second, with no host, has a bot in it too)
	_expect(bots[0] == server.crew_size - 1 and bots[1] == server.crew_size, "every ship has its own crew of bots, aboard it: %s" % str(bots))

	# own fittings per ship
	fleet.use(1)
	var helm1: Array = server.map.helm.keys()
	var guns1: PackedInt32Array = server.map.guns
	fleet.use(0)
	var helm0: Array = server.map.helm.keys()
	_expect(not helm1.is_empty() and not helm0.is_empty() and server.map.fleet_of(int(helm1[0])) == 1 and server.map.fleet_of(int(helm0[0])) == 0,
		"each ship has its own helm")
	_expect(guns1.size() == server.map.guns.size() and guns1.size() > 0 and server.map.fleet_of(guns1[0]) == 1, "and its own guns, numbered from 1 again")

	# a player who asks for the second ship comes aboard it
	var p = server.crew.new_player("Второй", 1)
	_expect(p.fleet_ship == 1 and server.map.fleet_of(p.st.y * server.map.width + p.st.x) == 1, "a newcomer asked for the second ship stands in it")
	fleet.use_for(p)
	_expect(fleet.on == 1 and server.ship == b, "what they do is done for that ship")
	fleet.use(0)

	# separate state
	a.tank = 500.0
	b.tank = 300.0
	a.store[Net.ITEM_PATCH] = 7
	b.store[Net.ITEM_PATCH] = 2
	fleet.use(1)
	server.power.set_charge(0.0)
	fleet.use(0)
	_expect(a.tank == 500.0 and b.tank == 300.0 and int(a.store[Net.ITEM_PATCH]) == 7, "fuel and lockers are each ship's own")
	_run(Net.TICK_HZ)
	fleet.use(1)
	var b_charge: float = server.power.charge()
	fleet.use(0)
	_expect(server.power.charge() > 0.5 and b_charge < server.power.charge(), "and so is the SMES (%.2f and %.2f)" % [server.power.charge(), b_charge])
	a.credits = 100
	fleet.use(1)
	server.ship.credits += 50
	fleet.use(0)
	_expect(a.credits == 150, "one purse: money earned on the second ship is the fleet's")

	# flying together (FS4)
	var from: Vector2 = a.pos
	a.dest = (from + Vector2(400, 0)).clamp(Vector2.ZERO, Vector2(Sectors.SPAN, Sectors.SPAN))
	a.moving = true
	_run(Net.TICK_HZ * 2)
	_expect(b.pos.is_equal_approx(a.pos) and not a.pos.is_equal_approx(from), "the second ship flies with the first")
	_expect(b.tank < 300.0 and a.tank < 500.0, "each burns its own fuel (%.1f, %.1f)" % [a.tank, b.tank])
	a.moving = false
	a.dest = a.pos
	_run(2)
	b.tank = 1.0
	_expect(fleet.can_jump(false) != "", "a jump waits while either ship's tank is short")
	b.tank = 600.0
	_expect(fleet.can_jump(false) == "", "and goes once both have fuel")

	# pirates pick a ship, mostly the weaker (FS5)
	b.hull = b.hull_max / 2
	var weaker := 0
	for i in 300:
		if fleet.target() == 1:
			weaker += 1
	_expect(weaker > 300 * 0.62 and weaker < 300 * 0.95, "pirates mostly pick the weaker ship (%d of 300)" % weaker)

	# a save keeps the second ship's own state
	b.store[Net.ITEM_PATCH] = 5
	b.tank = 444.0
	var data: Dictionary = JSON.parse_string(JSON.stringify(Campaign.snapshot(server)))
	var again := GameServer.new()
	get_root().add_child(again)
	if again.start(26302, "ship02|ship02", 1) != "":
		quit(1)
		return
	_expect(Campaign.restore(again, data) == "", "the saved fleet loads")
	var b2 = again.fleet.ships[1]
	_expect(absf(b2.tank - 444.0) < 0.01 and int(b2.store[Net.ITEM_PATCH]) == 5 and b2.hull == b.hull, "with the second ship's fuel, lockers and hull")
	_expect(absf(again.fleet.ships[0].tank - a.tank) < 0.01 and int(again.fleet.ships[0].store[Net.ITEM_PATCH]) == 7, "and the first's as they were (%.1f / %.1f, %d)" % [again.fleet.ships[0].tank, a.tank, int(again.fleet.ships[0].store[Net.ITEM_PATCH])])
	again.stop()
	again.free()

	# lost only when both are (FS6)
	fleet.use(1)
	server.crew.hull_hit(server.ship.hull)
	_expect(fleet.is_lost(1) and server.over == Net.OVER_NONE and not server.powered(), "the second ship's hull gives way: it goes dark, the run goes on")
	fleet.use(0)
	_expect(server.powered() and fleet.standing() == 1, "the first still has power")
	fleet.use(1)
	server.ship.hull = 10
	fleet.use(0)
	_run(1)
	_expect(not fleet.is_lost(1), "mended above nothing, the second ship is ours again")
	fleet.use(1)
	server.crew.hull_hit(server.ship.hull)
	fleet.use(0)
	server.crew.hull_hit(server.ship.hull)
	_expect(server.over == Net.OVER_WRECKED, "with both lost, the run is over")

	server.stop()
	server.free()
	print("FLEETTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for i in ticks:
		for s in get_root().get_children():
			if s is GameServer:
				s._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
