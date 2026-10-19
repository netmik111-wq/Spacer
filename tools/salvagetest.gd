extends SceneTree
## Checks work and money on the road (v67, the author's "every part" answers), on a
## real server stepped by hand:
##   godot --headless --path . --script res://tools/salvagetest.gd
## Fuel in units (the tank, jumps by the engine's tier, flying burns it, cans poured
## at the engine, a trader's fuel, bots pouring), scrap cut off a derelict, what a
## place gives floating outside (and the tractor beam), the work places (a gas cloud,
## an anomaly, an asteroid), traders that want things, the refinery, welding the
## hull with scrap, the parting volley, the dry rescue, no flagship growth from gear
## and the tank in a save.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Gear := preload("res://src/shared/gear.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Campaign := preload("res://src/server/campaign.gd")

var failed := 0
var server: GameServer
var p


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26410, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	p = server.crew.new_player("Тест")
	p.take_job(Net.JOB_ENGINEER)
	p.slots.fill(Net.ITEM_NONE)
	_fuel()
	_pour()
	_trader()
	_cut()
	_floating()
	_work_places()
	_refinery()
	_weld()
	_parting()
	_dry()
	_bots_pour()
	_save()
	print("salvagetest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


# ------------------------------------------------------------------ helpers

func _face(who, wall: int) -> bool:
	## Stands `who` in front of that wall cell, facing it. False if there is no floor before it.
	var map = server.map
	var front: int = map.fitting_front(wall)
	if front < 0:
		for o: int in [map.width, -map.width, 1, -1]:
			var c := wall + o
			if c >= 0 and c < map.cells.size() and map.walkable(c % map.width, c / map.width) and map.door_of[c] < 0:
				front = c
				break
	if front < 0:
		return false
	who.st.place(front % map.width, front / map.width)
	who.st.dir = Net.DIR_NONE
	var d := wall - front
	who.st.facing = 4 if d == 1 else (3 if d == -1 else (2 if d > 0 else 1))
	return map.use_ahead(who.st.x, who.st.y, who.st.facing, server.air.holes) == wall


func _hold(who, ticks: int) -> void:
	who.using = true
	_run(ticks)
	who.using = false
	_run(1)


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1


# ------------------------------------------------------------------ fuel in units

func _fuel() -> void:
	var ship = server.ship
	_expect(is_equal_approx(ship.tank, Net.FUEL_START) and ship.jump_cost == 40, "the ship starts with %d units in the tank; a jump burns 40" % Net.FUEL_START)
	ship.gear[Gear.SYS_ENGINE] = 3
	server.outfit.refresh()
	_expect(ship.jump_cost == 30 and server.outfit.jump_fuel(true) == 30 * Sectors.EXIT_FUEL, "a tier 3 engine burns 30 a jump, the long jump %d" % (30 * Sectors.EXIT_FUEL))
	ship.gear[Gear.SYS_ENGINE] = 2
	server.outfit.refresh()
	_expect(ship.jump_cost == 35, "a tier 2 engine burns 35")
	ship.gear[Gear.SYS_ENGINE] = 1
	server.outfit.refresh()
	# flying inside a system burns by distance
	ship.pos = Vector2(50, 50)
	ship.dest = Vector2(150, 50)
	ship.moving = true
	var was: float = ship.tank
	_run(Net.TICK_HZ * 10)
	var went: float = ship.pos.x - 50.0
	_expect(went > 5.0 and absf((was - ship.tank) - went * Net.FLIGHT_FUEL) < 0.05,
		"flying %.1f units of distance burns %.2f fuel" % [went, was - ship.tank])
	ship.tank = 0.5
	ship.dest = Vector2(190, 50)
	ship.moving = true
	_run(Net.TICK_HZ * 10)
	_expect(not ship.moving or ship.dest == ship.pos, "with the tank run dry the ship drifts to a stop")
	_expect(not ship.can_jump(), "and cannot jump")
	ship.moving = false
	ship.tank = Net.FUEL_START


func _pour() -> void:
	var map = server.map
	var engine: int = map.engine.keys()[0]
	_expect(_face(p, engine), "one stands at the engine")
	server.ship.tank = 500.0
	p.slots[p.hand] = Net.ITEM_FUEL
	_hold(p, Net.POUR_TICKS + 2)
	_expect(is_equal_approx(server.ship.tank, 500.0 + Net.CAN_FUEL) and p.slots[p.hand] == Net.ITEM_NONE,
		"a can poured at the engine: +%d in the tank (now %d)" % [Net.CAN_FUEL, floori(server.ship.tank)])
	server.ship.tank = Net.FUEL_MAX - 50
	p.slots[p.hand] = Net.ITEM_FUEL
	_hold(p, Net.POUR_TICKS + 2)
	_expect(p.slots[p.hand] == Net.ITEM_FUEL and is_equal_approx(server.ship.tank, Net.FUEL_MAX - 50), "a nearly full tank takes no can")
	p.slots[p.hand] = Net.ITEM_NONE
	server.ship.tank = Net.FUEL_START


# ------------------------------------------------------------------ a trader

func _trader() -> void:
	var s: Sectors = server.sectors
	var sys: int = server.ship.sector
	var kind_was: int = s.kind[sys]
	s.kind[sys] = Sectors.TRADER
	server.ship.in_reach = true
	server.supplies._offers_for = -1
	var w: PackedByteArray = server.supplies.wanted()
	_expect(w.size() == 2 and w[0] != w[1] and Sectors.WANTS.has(w[0]) and Sectors.WANTS.has(w[1]),
		"the trader looks for two things: %s, %s" % [Items.name_of(w[0]) if w.size() > 0 else "?", Items.name_of(w[1]) if w.size() > 1 else "?"])
	_expect(s.describe(sys).contains("ищет"), "and the chart says so: %s" % s.describe(sys))
	var unnamed := Sectors.WANTS.filter(func(i: int) -> bool: return Items.name_of(i) == "" or Items.price(i) <= 0)
	_expect(unnamed.is_empty(), "everything a trader may look for has a name and a price %s" % str(unnamed))
	_expect(server.supplies.sell_price(w[0]) == maxi(int(Items.price(w[0]) * Sectors.WANT_PAYS), 1),
		"it pays half as much again for them (%d cr for %s)" % [server.supplies.sell_price(w[0]), Items.name_of(w[0])])
	if not w.has(Net.ITEM_SCRAP):
		_expect(server.supplies.sell_price(Net.ITEM_SCRAP) == Items.price(Net.ITEM_SCRAP), "scrap sells at its full price")
	var offers: Dictionary = server.supplies.offers()
	_expect(not offers.has(Net.ITEM_SCRAP) and not offers.has(Net.ITEM_ORE) and not offers.has(Net.ITEM_DATA), "nobody sells scrap, ore or scan data")
	var pkt: PackedByteArray = server.supplies.trade_packet()
	_expect(pkt.slice(pkt.size() - 3) == PackedByteArray([2, w[0], w[1]]), "the trade packet ends with what it looks for")
	# fuel straight into the tank, at the locker
	_expect(_face(p, server.map.locker.keys()[0]), "one stands at the locker")
	server.ship.credits = 100
	server.ship.tank = 500.0
	server.supplies.store_asked(p, Net.STORE_BUY_FUEL, 0)
	_expect(is_equal_approx(server.ship.tank, 500.0 + Net.FUEL_LOT) and server.ship.credits == 100 - Net.PRICE_FUEL,
		"%d units into the tank for %d cr" % [Net.FUEL_LOT, Net.PRICE_FUEL])
	s.kind[sys] = kind_was
	server.ship.in_reach = false
	server.supplies._offers_for = -1
	server.ship.tank = Net.FUEL_START


# ------------------------------------------------------------------ scrap

func _cut() -> void:
	var map = server.map
	var d = server.derelict
	var s: Sectors = server.sectors
	s.kind[server.ship.sector] = Sectors.DERELICT
	s.reach[server.ship.sector] = Sectors.DOCK_RANGE
	server.ship.pos = s.spot[server.ship.sector]
	server.ship.dest = server.ship.pos
	_run(1)
	_expect(d.here and d.dark(), "a derelict lies alongside")
	var wall := -1
	for c: int in map.other_cells:
		if map.walk[c] == 0 and map.door_of[c] < 0 and map.cells[c] >= 0 and not server.air.holes.has(c):   # (a hole is mended first)
			for o: int in [1, -1, map.width, -map.width]:
				if map.is_other(c + o) and map.walkable((c + o) % map.width, (c + o) / map.width) and map.door_of[c + o] < 0:
					wall = c
			if wall >= 0:
				break
	_expect(wall >= 0 and _face(p, wall), "one stands at a wall of it")
	server.air.air[p.st.y * map.width + p.st.x] = 1.0
	_expect(server.salvage.can_cut(p, wall) == "" and server.repairs.usable_ahead(p), "its wall can be cut")
	var left: int = server.salvage.pieces_left()
	_hold(p, server.salvage.cut_ticks(p) + 2)
	_expect(p.count(Net.ITEM_SCRAP) == 1 and server.salvage.pieces_left() == left - 1, "holding E cuts a piece of scrap (%d left)" % server.salvage.pieces_left())
	server.salvage.left[server.salvage._key()] = 0
	_expect(server.salvage.can_cut(p, wall) not in ["", server.salvage.NOT_HERE], "and when it is stripped, it says so")
	p.slots.fill(Net.ITEM_NONE)
	var home: Vector2i = server.crew.spawn_point()
	p.st.place(home.x, home.y)              # (back aboard: the ship does not leave anybody on it)
	server.ship.pos = Vector2(5, 5)
	server.ship.dest = server.ship.pos
	s.kind[server.ship.sector] = Sectors.EMPTY
	_run(2)
	_expect(not d.here, "the derelict is left behind")
	_expect(server.salvage.can_cut(p, wall) == server.salvage.NOT_HERE, "and nothing is cut off thin air")


# ------------------------------------------------------------------ things floating outside

func _floating() -> void:
	var map = server.map
	var placed: int = server.salvage.float_out([Net.ITEM_SCRAP, Net.ITEM_SCRAP, Net.ITEM_PART])
	var out: Array = server.salvage.floating()
	var n := 0
	for c: int in out:
		n += Net.FLOOR_STACK - (server.floor_things[c] as PackedByteArray).count(Net.ITEM_NONE)
	_expect(placed == 3 and n == 3, "what a place gives floats out in space by the airlock (%d things)" % n)
	# the tractor beam pulls them in, one at a time
	var g := -1
	for i in server.ship.mounts.size():
		if Weapons.klass(server.ship.mounts[i]) == Weapons.CLASS_TRACTOR:
			g = i
	if g < 0:
		g = 0
		server.ship.mounts[0] = Weapons.TRACTOR
	server.ship.armed[g] = 1
	_run(roundi(server.salvage.TRACTOR_SECONDS * Net.TICK_HZ) + 1)
	var after := 0
	for c: int in server.salvage.floating():
		after += Net.FLOOR_STACK - (server.floor_things[c] as PackedByteArray).count(Net.ITEM_NONE)
	_expect(after == n - 1, "an armed tractor beam pulls one into the airlock")
	server.ship.armed[g] = 0
	server.salvage.jumped()
	_expect(server.salvage.floating().is_empty(), "a jump leaves the rest behind")
	# a place: debris gives scrap and no credits
	var credits: int = server.ship.credits
	server.road._take(Sectors.P_DEBRIS)
	var scrap := 0
	for c: int in server.salvage.floating():
		scrap += (server.floor_things[c] as PackedByteArray).count(Net.ITEM_SCRAP)
	_expect(scrap >= 2 and server.ship.credits == credits, "debris gives scrap (%d), floating, and no money" % scrap)
	server.salvage.jumped()


# ------------------------------------------------------------------ the work places

func _place(kind: int) -> void:
	server.road._here_places = [[kind, server.ship.pos]]
	server.road._places_for = server.ship.sector
	server.road.found[server.road._key(0)] = true
	server.road.taken.erase(server.road._key(0))
	server.road.work.erase(server.road._key(0))
	server.ship.moving = false


func _work_places() -> void:
	var map = server.map
	# a gas cloud: somebody at the engine, the ship still
	_place(Sectors.P_GAS)
	server.ship.tank = 300.0
	_expect(_face(p, map.engine.keys()[0]), "one stands at the engine in a gas cloud")
	_run(Net.TICK_HZ * 4)
	_expect(server.ship.tank > 300.0 + 2.0 * 3.5, "the scoop fills the tank (%d)" % floori(server.ship.tank))
	server.road.work[server.road._key(0)] = 1
	_run(2)
	_expect(server.road.taken.has(server.road._key(0)), "until the cloud is used up")
	# an anomaly: scanned from a holomap
	_place(Sectors.P_ANOMALY)
	var data: int = server.ship.store.get(Net.ITEM_DATA, 0)
	_expect(_face(p, map.holo.keys()[0]), "one stands at a holomap by an anomaly")
	_run(server.road.ANOMALY_SECONDS * Net.TICK_HZ + 4)
	_expect(int(server.ship.store.get(Net.ITEM_DATA, 0)) > data, "it is scanned: scan data in the locker")
	# an asteroid: ore breaks off for somebody outside
	_place(Sectors.P_ASTEROID)
	var spot: int = -1
	for c: int in server.salvage._spots_near(server.salvage._vents()[0][1]):
		spot = c
		break
	p.st.place(spot % map.width, spot / map.width)
	p.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	p.supply = true
	p.tank = 1.0
	_run(roundi(server.road.ORE_SECONDS * Net.TICK_HZ) + 2)
	var ore := 0
	for things: PackedByteArray in server.floor_things.values():
		ore += things.count(Net.ITEM_ORE)
	_expect(ore >= 1, "one of ours outside by an asteroid gets ore (%d)" % ore)
	server.salvage.jumped()
	server.road._here_places = []
	p.supply = false
	p.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	server.ship.tank = Net.FUEL_START


# ------------------------------------------------------------------ the refinery and the hull

func _refinery() -> void:
	var map = server.map
	_expect(_face(p, map.bench.keys()[0]), "an engineer at the workbench")
	server.ship.store[Net.ITEM_SCRAP] = 4
	var cans: int = server.ship.store.get(Net.ITEM_FUEL, 0)
	server.workshop.asked(p, Net.BENCH_FUEL_SCRAP, 0)
	for t in server.workshop.REFINE_TICKS + 2:
		server._tick()
	_expect(int(server.ship.store.get(Net.ITEM_SCRAP, 0)) == 0 and int(server.ship.store.get(Net.ITEM_FUEL, 0)) == cans + 1,
		"4 scrap are refined into a can of fuel")
	_expect(Items.price(Net.ITEM_SCRAP) * 4 > Net.PRICE_FUEL and Items.price(Net.ITEM_ORE) * 3 > Net.PRICE_FUEL,
		"refining costs more than a trader's fuel (the author's R3)")


func _weld() -> void:
	var map = server.map
	var hull_cell := -1
	var spot := -1
	for c: int in map.hull:
		if map.is_other(c):
			continue
		for o: int in [map.width, -map.width, 1, -1]:
			if map.floats((c + o) % map.width, (c + o) / map.width):
				spot = c + o
				hull_cell = c
				break
		if spot >= 0:
			break
	p.st.place(spot % map.width, spot / map.width)
	var d := hull_cell - spot
	p.st.facing = 4 if d == 1 else (3 if d == -1 else (2 if d > 0 else 1))
	server.ship.hull = 50
	p.slots.fill(Net.ITEM_NONE)
	p.slots[p.hand] = Net.ITEM_SCRAP
	p.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	p.supply = true
	p.tank = 1.0
	_expect(server.outside.can_mend(p, hull_cell), "outside with scrap and no patch, the hull can be welded")
	_hold(p, server.outside.mend_ticks(p) + 2)
	_expect(server.ship.hull == 50 + server.outside.HULL_PER_SCRAP and p.count(Net.ITEM_SCRAP) == 0, "a piece of scrap gives +%d" % server.outside.HULL_PER_SCRAP)
	p.slots[p.hand] = Net.ITEM_PATCH
	_hold(p, server.outside.mend_ticks(p) + 2)
	_expect(server.ship.hull == 50 + server.outside.HULL_PER_SCRAP + 15, "a patch gives +15 (was 10)")
	p.slots.fill(Net.ITEM_NONE)
	p.supply = false
	p.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	server.ship.hull = server.ship.hull_max
	var home: Vector2i = server.crew.spawn_point()
	p.st.place(home.x, home.y)


# ------------------------------------------------------------------ fights and help

func _parting() -> void:
	var d = server.derelict
	var g = server.gunnery
	_expect(d.pirates_come(2, true) and g.fighting(), "a raider comes to fight")
	g.enemy_charge.fill(1.0)
	var hull: int = server.ship.hull
	var shield: float = server.ship.shield
	server.road.ticks_here = 0
	server.road.next_hunter = 3000
	server.ship.shield = 0.0
	g.enemy_hit_chance = 1.0
	g.parting_volley()
	_expect(g.enemy_charge.count(0.0) == g.enemy_charge.size(), "jumping away, every charged pirate gun fires once")
	_expect(server.road.next_hunter == 3000 - roundi(server.road.ESCAPE_SOONER * Net.TICK_HZ), "and the next hunter comes %d s sooner" % int(server.road.ESCAPE_SOONER))
	g.enemy_hit_chance = -1.0
	server.ship.shield = shield
	d._leave(true)
	server.ship.hull = maxi(hull, server.ship.hull)
	server.air.holes.clear()
	_run(2)


func _dry() -> void:
	var dir = server.director
	server.ship.tank = 10.0
	server.ship.store[Net.ITEM_FUEL] = 0
	dir._dry_until = -1
	dir._watch_fuel(server.tick)
	_expect(dir._dry_until == server.tick + int(dir.RESCUE_SECONDS * Net.TICK_HZ) and dir.RESCUE_SECONDS >= 240.0,
		"a ship that cannot jump and has no cans waits %d s for help" % int(dir.RESCUE_SECONDS))
	server.ship.tank = Net.FUEL_START
	dir._watch_fuel(server.tick)
	_expect(dir._dry_until == -1, "fuel in the tank for a jump: no wait")
	_expect(server.shipyard.upgrades() == 0 and server.shipyard.gear_upgrades() == 0, "the flagship does not grow with our guns or gear (the author's O1)")


func _bots_pour() -> void:
	var bot = server.crew.new_player("Бот")
	bot.bot = true
	bot.st.access = Net.ACCESS_ALL | Net.ACCESS_OURS
	bot.slots.fill(Net.ITEM_NONE)
	bot.order = Net.POST_REPAIR
	server.ship.tank = 100.0
	server.ship.store[Net.ITEM_FUEL] = 2
	server.ship.broken.clear()
	p.st.place(1, 1)                         # (out of the way)
	var t := 0
	while t < Net.TICK_HZ * 90 and server.ship.tank < 250.0:
		_run(Net.TICK_HZ)
		t += Net.TICK_HZ
	_expect(server.ship.tank >= 300.0 - 0.1 or (server.ship.tank >= 200.0 and int(server.ship.store.get(Net.ITEM_FUEL, 0)) < 2),
		"a bot on work pours cans from the locker into a low tank (%d after %d s)" % [floori(server.ship.tank), t / Net.TICK_HZ])
	server.crew.remove(bot)
	server.ship.tank = Net.FUEL_START


func _save() -> void:
	server.ship.tank = 437.0
	var data: Dictionary = JSON.parse_string(JSON.stringify(Campaign.snapshot(server)))
	server.ship.tank = 1.0
	Campaign.restore(server, data)
	_expect(floori(server.ship.tank) == 437, "the tank is kept in a save (%d)" % floori(server.ship.tank))
	data.erase("tank")
	Campaign.restore(server, data)
	_expect(floori(server.ship.tank) == Net.FUEL_START, "an older save gets a fresh tank")
