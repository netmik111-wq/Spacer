extends SceneTree
## Checks gun tiers, part 1 (v58) on a real server stepped by hand:
##   godot --headless --path . --script res://tools/tiertest.gd
## Every gun of ours has a hidden tier and a kind, and the next gun of its line;
## a gun's state (its effect, damaged) lives in the thing it is, and comes back
## out of it. Pirate guns get better the farther out; the flagship's are the
## best. Kinetic shells: the shield only wears, a heavy slug goes through, armour
## turns them aside, a railgun passes the shield. Point defence shoots rockets
## down, theirs and ours. Beaten ships leave a gun now and then, the flagship its
## own. Traders deal in different things and buy back what they bought. An
## engineer at the workbench takes guns apart, mends and upgrades them; nobody
## else may. The new state is saved with the campaign.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Items := preload("res://src/shared/items.gd")
const Hulls := preload("res://src/shared/hulls.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	_data()
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26360, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false
	_pirates()
	_kinetic_and_guard()
	_loot()
	_traders()
	_bench()
	_save()
	server.stop()
	server.queue_free()
	print("TIERTEST %s" % ("OK" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _data() -> void:
	var lines_ok := true
	var tiers_ok := true
	for w in Weapons.OURS:
		if Weapons.tier(w) < 1 or Weapons.tier(w) > 3 or Weapons.kind(w) < 0:
			tiers_ok = false
		var next := Weapons.next_of(w)
		if next != Weapons.NONE and (Weapons.tier(next) != Weapons.tier(w) + 1 or Weapons.kind(next) != Weapons.kind(w)):
			lines_ok = false
	_expect(tiers_ok, "every gun of ours has a tier (1..3) and a kind of parts")
	_expect(lines_ok, "each upgrades into a gun of its kind one tier up")
	_expect(Weapons.next_of(Weapons.LASER) == Weapons.HEAVY and Weapons.next_of(Weapons.HEAVY) == Weapons.SIEGE
		and Weapons.next_of(Weapons.AUTOCANNON) == Weapons.RAILGUN and Weapons.next_of(Weapons.RAILGUN) == Weapons.HAMMER,
		"laser -> heavy -> siege, autocannon -> railgun -> hammer")
	var round_trip := true
	var names_ok := true
	for item in Weapons.gun_items():
		var w := Weapons.of_item(item)
		var again := Weapons.item_of(w, Weapons.fx_of(item), Weapons.damaged(item))
		if again != item or item > 255:
			round_trip = false
		if not Items.INFO.has(item) or Items.name_of(item) == "":
			names_ok = false
	_expect(round_trip, "a gun's state comes back out of the thing it is (%d things)" % Weapons.gun_items().size())
	_expect(names_ok, "every one of them is a thing with a name")
	var fx_item := Weapons.item_of(Weapons.SIEGE, Weapons.FX_STUN)
	_expect(Weapons.fx_of(fx_item) == Weapons.FX_STUN and Items.name_of(fx_item).contains(Weapons.fx_name(Weapons.FX_STUN)),
		"a tier 3 gun's effect is in its name (%s)" % Items.name_of(fx_item))
	var broken := Weapons.item_of(Weapons.HEAVY, Weapons.FX_NONE, true)
	_expect(Weapons.damaged(broken) and Items.price(broken) < Items.price(Weapons.item_of(Weapons.HEAVY)), "a damaged gun is worth less")
	_expect(Weapons.unique(Weapons.NOVA) and Items.price(Weapons.item_of(Weapons.NOVA)) == 0 and Weapons.parts_from(Weapons.item_of(Weapons.NOVA)) == 0,
		"the flagship's own gun is unique: not for sale, not to take apart")
	_expect(Weapons.power(Weapons.SIEGE) > Weapons.power(Weapons.HEAVY) and Weapons.power(Weapons.HEAVY) > Weapons.power(Weapons.LASER)
		and Weapons.power(Weapons.HAMMER) > Weapons.power(Weapons.RAILGUN) and Weapons.power(Weapons.RAILGUN) > Weapons.power(Weapons.AUTOCANNON),
		"a better gun draws more power")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var near_ok := true
	var mid_twos := 0
	var far_threes := 0
	for i in 400:
		for t in Weapons.tiers_for(2, 3, rng):
			near_ok = near_ok and t == 1
		var mid := Weapons.tiers_for(5, 3, rng)
		near_ok = near_ok and mid.count(2) <= 1 and mid.count(3) == 0
		mid_twos += mid.count(2)
		far_threes += Weapons.tiers_for(9, 4, rng).count(3)
	_expect(near_ok, "up to 3 jumps out pirates have only tier 1 guns; 4..7 out at most one tier 2")
	_expect(mid_twos > 100 and mid_twos < 300, "4..7 out about half the ships have a tier 2 gun (%d of 400)" % mid_twos)
	_expect(far_threes > 0 and far_threes < 200, "8 out tier 3 guns are rare (%d in 400 ships)" % far_threes)


func _pirates() -> void:
	var near := server.shipyard.make(2, false, [Net.OTHER_PIRATE, Net.OTHER_PIRATE + 1, Net.OTHER_PIRATE + 2])
	var plain := true
	for w in near["weapons"]:
		plain = plain and Weapons.tier(w) == 1
	_expect(plain and not near["guard"], "a pirate ship by the start has tier 1 guns and no point defence (%s)" % str(Array(near["weapons"])))
	var boss := server.shipyard.flagship(1, [Hulls.CLASSES[Net.ECLASS_BATTLESHIP]["layouts"][0]])
	var best := not boss.is_empty()
	for w in boss.get("weapons", []):
		best = best and Weapons.tier(w) == 3
	_expect(best and boss["guard"], "the flagship's guns are all tier 3, and it has point defence")


func _kinetic_and_guard() -> void:
	var g: Gunnery = server.gunnery
	var d: Derelict = server.derelict
	var ship := server.ship
	_expect(d.pirates_come(2) and g.fighting(), "a pirate ship comes and the fight is on")
	_expect(Weapons.shield_damage(Weapons.AUTOCANNON) == Weapons.KINETIC_WEAR and Weapons.passes_shield(Weapons.RAILGUN)
		and Weapons.pierce(Weapons.RAILGUN) >= 1, "shells wear the shield; a railgun passes it and goes on into a second room")
	ship.store[Net.ITEM_SHELL] = 500
	_armour = 0.0
	_guard = false
	# an autocannon's light shells against a full shield: the shield wears, the hull holds
	var hull_lost := 0
	var worn := 0.0
	for i in 30:
		_fight(g)
		g.enemy_hull = 100
		g.enemy_shield = 100.0
		g._our_volley(0, Weapons.AUTOCANNON)
		hull_lost += 100 - g.enemy_hull
		worn += 100.0 - g.enemy_shield
		_settle(g)
	_expect(hull_lost == 0 and worn > 0.0, "autocannon shells only wear a full shield (worn %d in all)" % roundi(worn))
	hull_lost = 0
	for i in 30:
		_fight(g)
		g.enemy_hull = 100
		g.enemy_shield = 100.0
		g._our_volley(0, Weapons.HAMMER)
		hull_lost += 100 - g.enemy_hull
		_settle(g)
	_expect(hull_lost > 0, "the hammer's slug goes through the shield, less a point (%d)" % hull_lost)
	hull_lost = 0
	for i in 30:
		_fight(g)
		g.enemy_hull = 100
		g.enemy_shield = 100.0
		g._our_volley(0, Weapons.RAILGUN)
		hull_lost += 100 - g.enemy_hull
		_settle(g)
	_expect(hull_lost > 30, "the railgun passes the shield whole (%d)" % hull_lost)
	_armour = 1.0
	hull_lost = 0
	for i in 20:
		_fight(g)
		g.enemy_hull = 100
		g.enemy_shield = 0.0
		g._our_volley(0, Weapons.RAILGUN)
		hull_lost += 100 - g.enemy_hull
		_settle(g)
	_expect(hull_lost == 0, "armour turns kinetic shots aside: ricochet")
	_armour = 0.0
	# their point defence against our rockets
	ship.store[Net.ITEM_ROCKET] = 500
	_guard = true
	hull_lost = 0
	var landed := 0
	for i in 40:
		_fight(g)
		g.enemy_hull = 100
		g.enemy_shield = 0.0
		g._enemy_guard_ready = 0
		g._our_volley(0, Weapons.ROCKET)
		if g.enemy_hull < 100:
			landed += 1
		_settle(g)
	_expect(landed > 0 and landed < 36, "their point defence shoots down most of our rockets (%d of 40 got through)" % landed)
	_guard = false
	_fight(g)
	# ours: mounted from the cargo at its own mount, powered, it shoots theirs down
	var p := server.crew.new_player("Канонир")
	var map := server.map
	var console: int = map.gun_console.keys()[0]
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN
	ship.store[Weapons.item_of(Weapons.GUARD)] = 1
	g.setup_asked(p, Net.GUNSET_MOUNT, 0, Weapons.item_of(Weapons.GUARD))
	_expect(ship.mounts[0] != Weapons.GUARD, "point defence does not go on a gun's mount")
	g.setup_asked(p, Net.GUNSET_MOUNT, Net.GUARD_MOUNT, Weapons.item_of(Weapons.GUARD))
	_expect(ship.guard == Weapons.GUARD and int(ship.store[Weapons.item_of(Weapons.GUARD)]) == 0, "it goes on its own mount")
	g.setup_asked(p, Net.GUNSET_SHIELD, 0, 0)
	g.setup_asked(p, Net.GUNSET_ARM, Net.GUARD_MOUNT, 1)
	_expect(ship.guard_armed, "and is powered")
	g.enemy_hit_chance = 1.0
	var hits := 0
	for i in 40:
		g.guard_charge = 1.0
		var before := ship.hull
		g._enemy_fires(Weapons.ROCKET)
		_settle(g)
		if ship.hull < before:
			hits += 1
		ship.hull = Net.HULL_MAX
	_expect(hits > 0 and hits < 36, "our point defence shoots down most of their rockets (%d of 40 hit us)" % hits)
	g.enemy_hit_chance = -1.0
	server.crew.remove(p)


func _loot() -> void:
	var g: Gunnery = server.gunnery
	_fight(g)
	var before := _guns_on_floor()
	var told := g._loot_gun(true)
	_expect(told != "" and _guns_on_floor() == before + 1, "a ship taken by boarding always leaves one of its guns")
	g._drop_nova()
	var nova := false
	for things: PackedByteArray in server.floor_things.values():
		for item in things:
			nova = nova or Weapons.of_item(item) == Weapons.NOVA
	_expect(nova, "the flagship's wreck holds the «Сверхновая»")
	server.derelict._leave(true)
	_settle(g)


func _fight(g: Gunnery) -> void:
	## A pirate ship alongside, fighting, with a shield generator that works (a
	## shot may have killed its crew, which ends the fight).
	for tries in 30:
		if g.fighting() and not g._over and not g.down(Net.ESYS_SHIELDS):
			break
		server.derelict._leave(true)
		_run(1)
		server.derelict.pirates_come(2)      # (one without a shield generator is sent away for another)
	g.enemy_armour = _armour
	g.enemy_guard = _guard


var _armour := 0.0
var _guard := false


func _guns_on_floor() -> int:
	var n := 0
	for things: PackedByteArray in server.floor_things.values():
		for item in things:
			if Weapons.of_item(item) != Weapons.NONE:
				n += 1
	return n


func _traders() -> void:
	var sectors := server.sectors
	var near_arms := true
	var kinds := {}
	for s in 200:
		var cell := Vector2i(s % 20 - 10, s / 20 - 5)
		var deal := Sectors.deal_at(server.space_seed + s, cell)
		kinds[deal] = true
		if Sectors.jumps_between(Vector2i.ZERO, cell) <= Sectors.DEAL_ARMS_NEAR and deal != Sectors.DEAL_ARMS:
			near_arms = false
	_expect(near_arms, "every trader near the start is an arms dealer")
	_expect(kinds.size() == 3, "farther out there are all three kinds")
	# the black market: rarer guns, dearer
	var ship := server.ship
	var at := -1
	for i in sectors.count:
		if sectors.kind[i] == Sectors.TRADER:
			at = i
	_expect(at >= 0, "(a trader in the cluster for the trade checks: every cluster has one since v64)")
	if at < 0:
		return
	ship.sector = at
	ship.pos = sectors.spot[at]
	ship.in_reach = true
	sectors.deal[at] = Sectors.DEAL_JUNK
	server.supplies._offers_for = -1
	var junk: Dictionary = server.supplies.offers()
	var guns := 0
	for item in junk.keys():
		if item is int and Weapons.of_item(item) != Weapons.NONE:
			guns += 1
	_expect(guns == 0 and not junk.has(Net.ITEM_ROCKET) and int(junk[Net.ITEM_PATCH]) < Items.price(Net.ITEM_PATCH),
		"a junk dealer has no guns and no ammunition, and its things are cheaper")
	_expect(server.supplies.sell_price(Net.ITEM_PATCH) == Weapons.sell_price(Items.price(Net.ITEM_PATCH), 0.2), "it buys at a fifth")
	sectors.deal[at] = Sectors.DEAL_BLACK
	server.supplies._offers_for = -1
	var black: Dictionary = server.supplies.offers()
	guns = 0
	var dear := true
	for item in black.keys():
		if item is int and Weapons.of_item(item) != Weapons.NONE:
			guns += 1
			dear = dear and int(black[item]) > Items.price(item)
	_expect(guns >= 1 and guns <= 2 and dear, "the black market has one or two guns, dear (%d)" % guns)
	sectors.deal[at] = Sectors.DEAL_ARMS
	server.supplies._offers_for = -1


func _bench() -> void:
	var map := server.map
	var ship := server.ship
	_expect(map.bench.size() == 1, "the ship has a workbench")
	# the fights above may have left holes: the air would run out and the engineer pass out mid-work
	server.admin.repair_all()
	server.air.refill()
	var bench: int = map.bench.keys()[0]
	var p := server.crew.new_player("Механик")
	var front: int = map.fitting_front(bench)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == bench:
			break
	_expect(map.use_ahead(p.st.x, p.st.y, p.st.facing) == bench and server.repairs.usable_ahead(p), "(at the workbench)")
	var laser := Weapons.item_of(Weapons.LASER)
	var parts := Items.gun_parts(Weapons.KIND_LASER)
	ship.store[laser] = 3
	ship.store[parts] = 0
	p.take_job(Net.JOB_CREWMAN)
	server.workshop.asked(p, Net.BENCH_APART, laser)
	_expect(p.bench.is_empty(), "only an engineer may work at it")
	p.take_job(Net.JOB_ENGINEER)
	server.workshop.asked(p, Net.BENCH_APART, laser)
	_expect(not p.bench.is_empty(), "an engineer may")
	_run(server.workshop.APART_TICKS + 2)
	_expect(int(ship.store[laser]) == 2 and int(ship.store[parts]) == 1 and p.bench.is_empty(), "a laser taken apart gives one part of its kind")
	server.workshop.asked(p, Net.BENCH_APART, laser)
	_run(server.workshop.APART_TICKS + 2)
	server.workshop.asked(p, Net.BENCH_UPGRADE, laser)
	_run(server.workshop.UPGRADE_TICKS + 2)
	_expect(int(ship.store[laser]) == 0 and int(ship.store.get(Weapons.item_of(Weapons.HEAVY), 0)) == 1 and int(ship.store[parts]) == 0,
		"two laser parts make a laser a heavy laser")
	var heavy := Weapons.item_of(Weapons.HEAVY)
	server.workshop.asked(p, Net.BENCH_UPGRADE, heavy)
	_expect(p.bench.is_empty(), "without four parts the heavy laser cannot be upgraded")
	ship.store[parts] = 4
	server.workshop.asked(p, Net.BENCH_UPGRADE, heavy)
	_run(server.workshop.UPGRADE_TICKS / 2)
	p.st.place(front % map.width + 2, front / map.width)
	_run(2)
	_expect(p.bench.is_empty() and int(ship.store[heavy]) == 1, "stepping away puts the work down")
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == bench:
			break
	server.workshop.asked(p, Net.BENCH_UPGRADE, heavy)
	_run(server.workshop.UPGRADE_TICKS + 2)
	var siege := -1
	for item: int in ship.store.keys():
		if Weapons.of_item(item) == Weapons.SIEGE and int(ship.store[item]) > 0:
			siege = item
	_expect(siege >= 0 and Weapons.fx_of(siege) != Weapons.FX_NONE and int(ship.store[parts]) == 0,
		"four more make it a siege laser, with an effect rolled (%s)" % (Items.name_of(siege) if siege >= 0 else "none"))
	var broken := Weapons.item_of(Weapons.ION, Weapons.FX_NONE, true)
	ship.store[broken] = 1
	ship.store[Net.ITEM_PART] = 1
	server.workshop.asked(p, Net.BENCH_MEND, broken)
	_run(server.workshop.MEND_TICKS + 2)
	_expect(int(ship.store[broken]) == 0 and int(ship.store.get(Weapons.item_of(Weapons.ION), 0)) == 1 and int(ship.store[Net.ITEM_PART]) == 0,
		"a damaged gun is mended with a spare part")
	server.crew.remove(p)


func _save() -> void:
	var ship := server.ship
	ship.mount_fx[1] = Weapons.FX_TWICE
	ship.guard = Weapons.GUARD
	ship.guard_armed = true
	server.supplies.bought[123] = [Weapons.item_of(Weapons.LASER)]
	server.supplies.sold[123] = [[Net.ITEM_PATCH, 4]]
	var data: Dictionary = JSON.parse_string(JSON.stringify(Campaign.snapshot(server)))
	ship.mount_fx[1] = 0
	ship.guard = 0
	ship.guard_armed = false
	server.supplies.bought.clear()
	server.supplies.sold.clear()
	var problem := Campaign.restore(server, data)
	_expect(problem == "" and ship.mount_fx[1] == Weapons.FX_TWICE and ship.guard == Weapons.GUARD and ship.guard_armed,
		"the mounts' effects and the point defence are saved %s" % problem)
	_expect(server.supplies.bought.get(123, []) == [Weapons.item_of(Weapons.LASER)] and server.supplies.sold.get(123, []) == [[Net.ITEM_PATCH, 4]],
		"and what each trader sold us and bought from us")


func _settle(g: Gunnery) -> void:
	g._land_due()
	_run(1)


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	if what == "":
		return
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
