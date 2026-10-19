extends SceneTree
## Checks ship gear, gun tiers part 2 (v59) on a real server stepped by hand:
##   godot --headless --path . --script res://tools/geartest.gd
## Every crate of gear is a thing with a name and a tiered price, kept in the
## locker. Only an engineer installs one, holding "use" at its machine: what it
## replaces comes out into the hand. Each system's tier does what its card says
## (the shield refills faster and the top one stops rockets, the reactor gives
## more power, the engine charges jumps quicker, the top sensors show the
## pirates' guns charging). Modules go in the bay's two slots: armour takes less
## off the hull and turns shells aside, the focusing array joins a laser volley,
## the phase drive changes the battle position at once and opens "behind them".
## Traders sell crates, wrecks and derelicts leave them, the flagship grows with
## our gear, and the gear is saved with the campaign.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Player := preload("res://src/server/player.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Items := preload("res://src/shared/items.gd")
const Gear := preload("res://src/shared/gear.gd")

var failed := 0
var server: GameServer
var eng: Player


func _initialize() -> void:
	_data()
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26370, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false
	eng = server.crew.new_player("Механик")
	eng.take_job(Net.JOB_ENGINEER)
	_systems()
	_modules()
	_fight_effects()
	_phase()
	_traders_and_loot()
	_save()
	server.stop()
	server.queue_free()
	print("GEARTEST %s" % ("OK" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _data() -> void:
	var ok := true
	var priced := true
	for g in Gear.all():
		var item := Gear.item_of(g)
		if item > 255 or Items.gear_of(item) != g or Items.name_of(item) == "" or Items.cargo(item) or Items.about(item) == "":
			ok = false
		if Items.price(item) <= 0 or (Gear.tier(g) < 1 and not Gear.extender(g)) or Gear.tier(g) > 3:   # (v62: the bay's extender has none)
			priced = false
	_expect(ok, "every crate of gear is a thing with a name, carried, not cargo (%d)" % Gear.all().size())
	_expect(priced, "each has a tier and a price")
	_expect(Gear.price(Gear.SHIELD_3) == Gear.price(Gear.SHIELD_2) * 2 and Gear.price(Gear.ARMOUR_2) * 2 == roundi(Gear.price(Gear.ARMOUR_1) * 5),
		"prices go x1 / x2.5 / x5 by tier")
	_expect(Items.kept_in_locker().has(Gear.item_of(Gear.REACTOR_2)), "the supply locker keeps them")
	var listed := false
	for c: Array in Items.CATEGORIES:
		listed = listed or (c[1] as Array).has(Gear.item_of(Gear.PHASE))
	_expect(listed, "the locker and the trader show them as ship modules")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var early := true
	for i in 50:
		early = early and Gear.tier(Gear.roll(1, rng)) == 1
	_expect(early, "near the start only tier 1 crates are found")


func _face(p: Player, cell: int) -> void:
	## Stands `p` in front of that wall cell, facing it.
	var map := server.map
	var front: int = map.fitting_front(cell)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == cell:
			return


func _install(p: Player, item: int, cell: int) -> void:
	## `p` holds that crate (or nothing) at that cell with "use" held long enough.
	_face(p, cell)
	p.hand = 0
	p.slots[0] = item
	p.using = true
	var modules := server.ship.modules.duplicate()
	var gear := server.ship.gear.duplicate()
	for t in roundi(Gear.INSTALL_SECONDS * Net.TICK_HZ) + 4:
		_run(1)
		if server.ship.modules != modules or server.ship.gear != gear:
			break                            # done: holding on would start on the next job
	p.using = false
	_run(1)


func _systems() -> void:
	var map := server.map
	var ship := server.ship
	var o = server.outfit
	_expect(ship.gear == PackedByteArray([1, 1, 1, 1, 1]) and o.reactor() == Weapons.REACTOR, "the ship sets out with built-in systems (reactor %d)" % o.reactor())
	var gen: int = map.shield.keys()[0]
	var engine: int = map.engine.keys()[0]
	var holo: int = map.holo.keys()[0]
	var crewman := server.crew.new_player("Матрос")
	crewman.take_job(Net.JOB_CREWMAN)
	_install(crewman, Gear.item_of(Gear.SHIELD_2), gen)
	_expect(o.tier(Gear.SYS_SHIELD) == 1 and crewman.slots[0] == Gear.item_of(Gear.SHIELD_2), "only an engineer installs gear")
	server.crew.remove(crewman)
	_install(eng, Gear.item_of(Gear.REACTOR_2), gen)
	_expect(o.reactor() == 8, "a reactor does not go in at the shield generator")
	_install(eng, Gear.item_of(Gear.SHIELD_2), gen)
	_expect(o.tier(Gear.SYS_SHIELD) == 2 and eng.slots[0] == Net.ITEM_NONE, "an engineer installs a shield generator; the built-in one leaves nothing")
	ship.shield = 0.0
	_run(Net.TICK_HZ * 4)
	var pace: float = server.stations.shield_pace()
	_expect(absf(ship.shield - 14.0 * pace) < 1.0, "it refills 3.5 a second (%.1f after 4 s, the engineer at it x%.2f)" % [ship.shield, pace])
	_expect(not o.hardened(), "and does not stop rockets")
	_install(eng, Gear.item_of(Gear.SHIELD_3), gen)
	_expect(o.tier(Gear.SYS_SHIELD) == 3 and eng.slots[0] == Gear.item_of(Gear.SHIELD_2) and o.hardened(),
		"the top one goes in, the one it replaces comes out into the hand, and it stops rockets")
	eng.slots[0] = Net.ITEM_NONE
	_install(eng, Gear.item_of(Gear.REACTOR_3), engine)
	_expect(o.reactor() == 12 and server.gunnery.packet()[4 + 3 * map.guns.size() + 1] == server.power.budget(), "a reactor at the engine: 12 power, and the gun console is told (with the SMES's boost, v61)")
	eng.slots[0] = Net.ITEM_NONE
	_install(eng, Gear.item_of(Gear.REACTOR_2), engine)
	_expect(o.reactor() == 10 and eng.slots[0] == Gear.item_of(Gear.REACTOR_3), "a weaker one may go back in: 10")
	eng.slots[0] = Net.ITEM_NONE
	_install(eng, Gear.item_of(Gear.ENGINE_3), engine)
	_expect(o.tier(Gear.SYS_ENGINE) == 3 and o.tier(Gear.SYS_REACTOR) == 2, "an engine goes in at the engine too, beside the reactor")
	server.navigation.start_jump(0, "Тест")
	_expect(ship.jump_tick - server.tick == Net.JUMP_TICKS / 2, "it charges a jump twice as quick (%d ticks)" % (ship.jump_tick - server.tick))
	ship.jump_to = Net.NO_SECTOR
	server.navigation.tell_nav()
	_install(eng, Gear.item_of(Gear.SENSORS_3), holo)
	_expect(o.tier(Gear.SYS_SENSORS) == 3 and o.sees_charge() and o.scan_seconds() < 3.0, "sensors go in at a holomap")
	eng.slots[0] = Gear.item_of(Gear.SENSORS_3)
	_face(eng, holo)
	_expect(o.can(eng, holo) != "" and o.can(eng, holo) != o.NOT_HERE, "the same one cannot go in twice (%s)" % o.can(eng, holo))
	eng.slots[0] = Net.ITEM_NONE


func _modules() -> void:
	var map := server.map
	var ship := server.ship
	var o = server.outfit
	_expect(map.bay.size() == 1, "the ship has a module bay")
	var bay: int = map.bay.keys()[0]
	_face(eng, bay)
	_expect(server.repairs.usable_ahead(eng), "(at the module bay)")
	_install(eng, Gear.item_of(Gear.ARMOUR_2), bay)
	_expect(Gear.armour_tier(ship.modules) == 2 and is_equal_approx(ship.armour, 0.2), "armour plating goes in the bay (ricochets %.0f%%)" % (ship.armour * 100))
	_install(eng, Gear.item_of(Gear.FOCUS), bay)
	_expect(o.focus() and ship.modules.count(Gear.NONE) == 0, "the focusing array takes the other slot")
	_install(eng, Gear.item_of(Gear.PHASE), bay)
	_expect(not o.phase() and eng.slots[0] == Gear.item_of(Gear.PHASE), "with both slots taken a third module does not go in")
	_install(eng, Gear.item_of(Gear.ARMOUR_3), bay)
	_expect(Gear.armour_tier(ship.modules) == 3 and eng.slots[0] == Gear.item_of(Gear.ARMOUR_2), "armour swaps for armour: the old plates come out")
	_install(eng, Net.ITEM_NONE, bay)
	_expect(not o.focus() and eng.slots[0] == Gear.item_of(Gear.FOCUS), "with empty hands the last module comes out")
	_install(eng, Gear.item_of(Gear.FOCUS), bay)
	_expect(o.focus(), "(and goes back in)")


func _fight_effects() -> void:
	var g: Gunnery = server.gunnery
	var ship := server.ship
	_fight(g)
	_expect(g.fighting(), "(a pirate ship to fight)")
	# armour: kinetic shells turn aside, other hits take less from the hull
	g.enemy_hit_chance = 1.0
	ship.shield_on = false
	ship.shield = 0.0
	var turned := 0
	for i in 120:                         # (many tries: at 30% the share in 40 strayed out of bounds now and then)
		var before := ship.hull
		g._enemy_fires(Weapons.RAILGUN)
		g._land_due()
		if ship.hull == before:
			turned += 1
		ship.hull = Net.HULL_MAX
		_mend()
	_expect(turned >= 18 and turned <= 60, "our armour turns some of their shells aside (%d of 120)" % turned)
	ship.modules = PackedByteArray([Gear.FOCUS, Gear.NONE])
	server.outfit.refresh()
	var bare := _hull_lost(g)
	ship.modules = PackedByteArray([Gear.FOCUS, Gear.ARMOUR_3])
	server.outfit.refresh()
	var armoured := _hull_lost(g)
	_expect(armoured < bare, "with armour their lasers take less off the hull (%d against %d)" % [armoured, bare])
	g.enemy_hit_chance = -1.0
	ship.shield_on = true
	# the focusing array: two lasers in one volley at one room
	ship.mounts = PackedByteArray([Weapons.LASER, Weapons.LASER, Weapons.ION])
	ship.armed.fill(1)
	g.charge.fill(1.0)
	g.aim = Net.AIM_ROOM
	_expect(is_equal_approx(g._focus(255), Gear.FOCUS_PIERCE), "two lasers aimed at one room join: the shield counts %d weaker" % int(Gear.FOCUS_PIERCE))
	_expect(g._focus(0) == 0.0, "but not one fired alone")
	g.aim = Net.AIM_ANY
	_expect(g._focus(255) == 0.0, "nor a volley fired anywhere")
	# the top sensors see their guns charging
	var pkt := g.packet()
	_expect(pkt[pkt.size() - 1] != 255 and g.enemy_weapons.size() > 0, "the top sensors show their guns charging")
	ship.gear[Gear.SYS_SENSORS] = 1
	pkt = g.packet()
	_expect(pkt[pkt.size() - 1] == 255, "the built-in ones do not")
	ship.gear[Gear.SYS_SENSORS] = 3


func _hull_lost(g: Gunnery) -> int:
	var lost := 0
	for i in 20:
		var before := server.ship.hull
		g._enemy_fires(Weapons.HEAVY)
		g._land_due()
		lost += before - server.ship.hull
		server.ship.hull = Net.HULL_MAX
		_mend()
	return lost


func _mend() -> void:
	server.ship.broken.clear()
	for c: int in server.air.holes.keys():
		server.air.set_hole(c, false)


func _phase() -> void:
	var map := server.map
	var ship := server.ship
	var st = server.stations
	var g: Gunnery = server.gunnery
	_fight(g)
	var pilot := server.crew.new_player("Пилот")
	var helm: int = map.helm.keys()[0]
	pilot.st.place(helm % map.width, helm / map.width + 1)
	pilot.st.facing = Net.DIR_UP
	if not server.systems.at_console(pilot, map.helm):
		_face(pilot, helm)
	_expect(server.systems.at_console(pilot, map.helm), "(the pilot at the ship's controls)")
	st.position_asked(pilot, Net.POS_BEHIND)
	_expect(st.position == Net.POS_CLOSE, "without the phase drive there is no going behind them")
	st.position_asked(pilot, Net.POS_FAR)
	_expect(st.goal == Net.POS_FAR and st.position == Net.POS_CLOSE, "and changing position is a manoeuvre")
	st.goal = Net.POS_NONE
	ship.modules = PackedByteArray([Gear.PHASE, Gear.ARMOUR_1])
	server.outfit.refresh()
	ship.phase_ready = 0
	st.position_asked(pilot, Net.POS_BEHIND)
	_expect(st.position == Net.POS_BEHIND and st.goal == Net.POS_NONE, "the phase drive takes the ship behind them at once")
	_expect(st.our_hit_bonus() > 0.2 and st.their_hit_bonus() < -0.15, "there we hit better and they hit worse")
	_expect(not server.outfit.phase_ready() and ship.phase_ready - server.tick == roundi(Gear.PHASE_SECONDS * Net.TICK_HZ), "then it recharges 60 s")
	st.position_asked(pilot, Net.POS_FLANK)
	_expect(st.goal == Net.POS_FLANK, "meanwhile positions change by a manoeuvre again")
	st.goal = Net.POS_NONE
	st.position = Net.POS_CLOSE
	st.position_asked(pilot, Net.POS_BEHIND)
	_expect(st.position == Net.POS_CLOSE, "and behind them is closed until it is charged")
	server.crew.remove(pilot)


func _traders_and_loot() -> void:
	var sectors := server.sectors
	var ship := server.ship
	var at := -1
	for i in sectors.count:
		if sectors.kind[i] == Sectors.TRADER:
			at = i
	if at >= 0:
		ship.sector = at
		ship.pos = sectors.spot[at]
		ship.in_reach = true
		for deal in [Sectors.DEAL_ARMS, Sectors.DEAL_JUNK, Sectors.DEAL_BLACK]:
			sectors.deal[at] = deal
			server.supplies._offers_for = -1
			var crates := 0
			for item in server.supplies.offers().keys():
				if item is int and Items.gear_of(item) != Gear.NONE:
					crates += 1
			_expect(crates >= 1 and crates <= 2, "a %s sells %d crate(s) of gear" % [Sectors.DEAL_NAMES[deal], crates])
		sectors.deal[at] = Sectors.DEAL_ARMS
		server.supplies._offers_for = -1
		_expect(not server.supplies.offers().has("harden"), "nobody sells the shield hardening now: it is the top shield generator")
	var g: Gunnery = server.gunnery
	_fight(g)
	g.wreck_gun_chance = 1.0
	g.wreck_gear_chance = 1.0
	var told: String = g._loot_gun(false)
	var crate := false
	for things: PackedByteArray in server.floor_things.values():
		for item in things:
			crate = crate or Items.gear_of(item) != Gear.NONE
	_expect(crate and told.contains("модул"), "a wreck may leave a crate of gear")
	g.wreck_gun_chance = Gunnery.WRECK_GUN
	g.wreck_gear_chance = Gunnery.WRECK_GEAR
	server.derelict._leave(true)
	_run(1)
	ship.gear = PackedByteArray([1, 1, 1, 1, 1])
	ship.modules = PackedByteArray([0, 0])
	var plain: int = server.shipyard.gear_upgrades()
	ship.gear = PackedByteArray([3, 3, 3, 3])
	ship.modules = PackedByteArray([Gear.ARMOUR_3, Gear.PHASE])
	_expect(plain == 0 and server.shipyard.gear_upgrades() == 5 and server.outfit.tier_points() == 11,
		"the flagship grows by half our gear's tier points (%d)" % server.outfit.tier_points())


func _save() -> void:
	var ship := server.ship
	ship.gear = PackedByteArray([2, 3, 1, 2, 1])
	ship.modules = PackedByteArray([Gear.FOCUS, Gear.ARMOUR_2])
	var data: Dictionary = JSON.parse_string(JSON.stringify(Campaign.snapshot(server)))
	ship.gear = PackedByteArray([1, 1, 1, 1, 1])
	ship.modules = PackedByteArray([0, 0])
	var problem := Campaign.restore(server, data)
	_expect(problem == "" and ship.gear == PackedByteArray([2, 3, 1, 2, 1]) and ship.modules == PackedByteArray([Gear.FOCUS, Gear.ARMOUR_2])
		and is_equal_approx(ship.armour, 0.2), "the gear is saved with the campaign %s" % problem)


func _fight(g: Gunnery) -> void:
	for tries in 30:
		if g.fighting() and not g._over:
			return
		server.derelict._leave(true)
		_run(1)
		server.derelict.pirates_come(2)


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	if what == "":
		return
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
