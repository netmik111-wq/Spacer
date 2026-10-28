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
## v49: weapons on mounts swapped with the cargo, the reactor's power, shields
## (ours and theirs), the new weapons (heavy, rapid, beam, blaster, rockets,
## EMP, ion) and the trader's offers, selling and the shield hardening.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Mounts := preload("res://src/server/mounts.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sectors := preload("res://src/shared/sectors.gd")

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
	server.arena.enabled = false            # (v92) the fight as it was before it flew in space (arenatest has that)
	server.gunnery.flies = false              # (v56) shots land the moment they are fired here
	server.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	var map := server.map
	var g: Gunnery = server.gunnery
	server.shipyard.classic = true          # (the checks below were written for the old pirate ship: see shiptest for the rolled ones)
	g.shield_chance = 0.0                    # (the old checks below are about a pirate ship with no shield)
	g.ransom_chance = 0.0                    # (the old checks below are about a ship that runs when beaten)
	g.loadout_for_test = PackedByteArray([Weapons.LASER])
	var d: Derelict = server.derelict
	_expect(map.guns.size() == 4 and map.gun_console.size() == 1, "the ship has four guns (v94: one fixed in the bow) and a gun console")
	server.ship.mounts[3] = Weapons.NONE        # (the power checks below count the first three's lasers)
	server.ship.armed[3] = 0
	server.ship.armed[2] = 1                    # (v94: gun 3 is the fixed bow gun, off at the start)

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
	_expect(map.shield.size() == 1 and server.ship.shield > 99.0 and g.our_shield_up(), "the ship has a shield generator, and the shield is up")
	_expect(g.power_used() == 3 + Weapons.SHIELD_POWER, "three lasers and the shield draw %d of %d power" % [g.power_used(), Weapons.REACTOR])

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
	var at := 4 + 3 * map.guns.size() + 4 + 4
	var end := pkt.size() - (map.guns.size() + 4 + g.enemy_weapons.size() * 2 + 5 + 11)     # (v86: the two enemies; v68: the goal; v58: the mounts' effects, the point defence, theirs; v59: their charges)
	_expect(pkt[at] == Net.ESYS_HELM and pkt[at + 1] == Net.ESYS_COUNT and pkt[end - 4] == 1 and pkt[end - 3] == Weapons.LASER and pkt[end - 2] == 0,
		"clients are told where the guns aim, how the enemy's systems are and what guns it has")
	var credits := server.ship.credits
	for i in 20:
		g.charge.fill(1.0)
		g.fire(p, 255)
		if d.wreck:
			break
	# (v72, the author's note) a boarding ship wrecked before it docks stays alongside as a wreck
	_expect(d.here and d.wreck and g.enemy_hull == 0, "enough hits wreck it before it docks: it stays alongside, a wreck")
	_expect(server.ship.credits == credits + Gunnery.WRECK_REWARD, "and the ship is paid for it")
	_expect(server.pirates.aboard() == 0, "none of its crew is aboard ours")
	d.pirates_wrecked()                      # (cleared away for the next one)

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
	_run(int(Gunnery.ENEMY_REPAIR_SECONDS + 10.0) * Net.TICK_HZ)
	_expect(not g.down(Net.ESYS_WEAPONS) or not g.down(Net.ESYS_ENGINE), "its crew walks over and mends a system after a while")
	credits = server.ship.credits
	g.enemy_hull = Gunnery.ENEMY_HULL
	g.aim_asked(p, Net.ESYS_CREW)
	_shoot_until(p, func() -> bool: return not d.here)
	_expect(not d.here and g.enemy_hull == 0 and server.ship.credits == credits, "hits on its quarters kill the boarding party, and it breaks off (unpaid)")
	_expect(server.pirates.aboard() == 0, "nobody comes aboard")

	# it shoots back (our shield off: see the shield's own checks below)
	server.ship.shield_on = false
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
	for cell: int in server.pirates.bombs.keys():
		server.pirates._lift_bomb(cell)         # a bomb they left would break a gun the next checks fire (1 run in 30)

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
	_run(40 * Net.TICK_HZ)
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
	server.ship.pos = d.wreck_at + Vector2(Sectors.WRECK_REACH + 5, 0)    # (v69) out of its reach: a little way is not enough
	_run(2)
	_expect(not d.here and server.pirates.aboard() == 0, "when the ship moves on the wreck stays behind, with its dead")
	server.road.hulks = {}                   # (v69) it stays on the chart there: not wanted back in this test
	server.ship.moving = false

	_v49(p)

	server.stop()
	server.free()
	print("GUNTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _shoot_until(p, done: Callable) -> void:
	## Fires one gun at a time until the enemy is in the state wanted (or 60 shots:
	## a wreck takes 12 to 25 with misses and shields, now and then 30).
	for i in 60:
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


func _v49(p) -> void:
	var g: Gunnery = server.gunnery
	var d: Derelict = server.derelict
	var ship = server.ship
	var map := server.map
	print("  -- v49: weapons, power, shields, trade")
	_heal(p)
	ship.broken.clear()
	ship.shield_on = true
	ship.hull = Net.HULL_MAX
	_expect(Net.HULL_MAX == 200 and Gunnery.ENEMY_HULL == 12, "our hull is 200, a pirate ship's 12")

	# the cargo and the mounts (v61: with the SMES's output off, so the reactor alone gives the power)
	for u: Dictionary in server.power.units:
		u["output"] = false
	ship.store[Weapons.item_of(Weapons.HEAVY)] = 1
	ship.store[Weapons.item_of(Weapons.SIEGE)] = 1
	g._mount(p, 1, Weapons.item_of(Weapons.HEAVY))      # (v60: carried up by hand, see worktest; the old swap stays for tests)
	_expect(ship.mounts[1] == Weapons.HEAVY and ship.armed[1] == 0 and int(ship.store[Weapons.item_of(Weapons.LASER)]) == 1
		and int(ship.store[Weapons.item_of(Weapons.HEAVY)]) == 0, "a heavy laser from the cargo goes on gun 2; the laser it replaces goes into the cargo, unpowered")
	g.arm(p, 1, true)
	_expect(ship.armed[1] == 1 and g.power_used() == 2 + 3 + Weapons.SHIELD_POWER, "powered, it draws 3 (7 of 8 now)")
	g._mount(p, 2, Weapons.item_of(Weapons.SIEGE))
	g.arm(p, 2, true)
	_expect(ship.armed[2] == 0, "the siege laser (4) does not fit in what the reactor has left")
	g.switch_shield(p, false)
	g.arm(p, 0, false)
	g.arm(p, 2, true)
	_expect(ship.armed[2] == 1 and g.power_used() == 7 and ship.shield == 0.0, "with the shield and a laser switched off it does")
	g._mount(p, 2, Net.ITEM_NONE)
	_expect(ship.mounts[2] == Weapons.NONE and int(ship.store[Weapons.item_of(Weapons.SIEGE)]) == 1, "a gun is taken down into the cargo")
	g.setup_asked(p, Net.GUNSET_MOUNT, 2, Weapons.item_of(Weapons.SIEGE))
	_expect(ship.mounts[2] == Weapons.NONE and server.mounts.wanted[2] == Weapons.item_of(Weapons.SIEGE),
		"(v60) the console orders a gun onto a mount; it does not put it up by itself")
	g.setup_asked(p, Net.GUNSET_MOUNT, 2, Weapons.item_of(Weapons.SIEGE))
	_expect(server.mounts.wanted[2] == Mounts.WANT_NONE, "the same order again takes it back")
	var stranger := server.crew.new_player("Мимо2")
	g.setup_asked(stranger, Net.GUNSET_MOUNT, 2, Weapons.item_of(Weapons.SIEGE))
	_expect(server.mounts.wanted[2] == Mounts.WANT_NONE, "only from the gun console")
	server.crew.remove(stranger)
	var before: Dictionary = ship.store.duplicate()
	server.supplies.store_asked(_at_locker(p), Net.STORE_TAKE, Weapons.item_of(Weapons.SIEGE))
	_expect(int(ship.store[Weapons.item_of(Weapons.SIEGE)]) == int(before[Weapons.item_of(Weapons.SIEGE)]) - 1 and p.count(Weapons.item_of(Weapons.SIEGE)) == 1,
		"(v60) a ship's gun is taken from the locker into the hands, to be carried to its mount")
	p.slots[p.slots.find(Weapons.item_of(Weapons.SIEGE))] = Net.ITEM_NONE
	ship.store[Weapons.item_of(Weapons.SIEGE)] = int(before[Weapons.item_of(Weapons.SIEGE)])
	_to_console(p)

	# our shield
	ship.mounts[2] = Weapons.SIEGE
	ship.armed[2] = 1
	ship.armed[0] = 1
	g.switch_shield(p, true)
	_expect(not ship.shield_on, "the shield needs 2 power: with the reactor full (%d of 8) it does not come on" % g.power_used())
	for u: Dictionary in server.power.units:
		u["output"] = true
	g.switch_shield(p, true)
	_expect(ship.shield_on, "(v61) with the SMES's boost (+%d) it does" % server.power.boost())
	g.switch_shield(p, false)
	for u: Dictionary in server.power.units:
		u["output"] = false
	g.arm(p, 2, false)
	ship.mounts[2] = Weapons.LASER
	g.switch_shield(p, true)
	_expect(ship.shield_on, "the shield is switched on")
	_run(10 * Net.TICK_HZ)
	_expect(absf(ship.shield - 10.0 * Weapons.SHIELD_REGEN) < 1.0, "and builds up %.1f a second (%.1f after 10 s)" % [Weapons.SHIELD_REGEN, ship.shield])
	ship.shield = 100.0
	g.enemy_hit_chance = 1.0
	_expect(d.pirates_come(1, true), "a raider with one laser")
	var holes := server.air.holes.size()
	var hull: int = ship.hull
	for k in 2:
		g._enemy_fires(Weapons.LASER)
	_expect(server.air.holes.size() == holes and ship.hull == hull and ship.broken.is_empty() and absf(ship.shield - 50.0) < 1.0,
		"our shield stops its lasers while it holds: each takes 25 (%.0f left)" % ship.shield)
	ship.shield = 0.0
	ship.jammed[g.shield_cell()] = server.tick + 1000
	g._enemy_fires(Weapons.LASER)
	_expect(ship.hull < hull or not ship.broken.is_empty(), "with the shield down a laser gets through")
	# (v56) shots fly before they land
	ship.broken.clear()
	g.enemy_charge.fill(0.0)
	g.flies = true
	hull = ship.hull
	g._enemy_fires(Weapons.LASER)
	_expect(ship.hull == hull and ship.broken.is_empty() and g.in_flight() == 1, "(v56) its shot is on its way: nothing is hit yet")
	_run(Weapons.flight_ticks(Weapons.LASER))
	_expect((ship.hull < hull or not ship.broken.is_empty()) and g.in_flight() == 0,
		"and it lands %d ticks later" % Weapons.flight_ticks(Weapons.LASER))
	var their_hull := g.enemy_hull
	ship.broken.clear()                       # its shot may have broken our gun
	ship.jammed.erase(server.map.guns[0])
	g.charge.fill(1.0)
	g.fire(p, 0)
	_expect(g.enemy_hull == their_hull and g.in_flight() == 1, "(v56) ours flies too: the pirate ship is untouched while it does")
	_run(Weapons.flight_ticks(Weapons.LASER))
	_expect(g.in_flight() == 0, "and lands (or misses) when its flight is over (their hull %d of %d)" % [g.enemy_hull, their_hull])
	g.flies = false
	ship.jammed.clear()
	ship.broken.clear()
	ship.shield = 49.0
	var through := 0
	for k in 200:
		ship.shield = 25.0
		if g._meets_shield(Weapons.LASER, false) and _rng_through(g, 25.0):
			through += 1
	_expect(through > 70 and through < 130, "at 25 about half the shots get through (%d of 200)" % through)
	ship.shield = 100.0
	hull = ship.hull
	g._enemy_fires(Weapons.ROCKET)
	_expect(ship.hull <= hull - 2 * Net.HULL_PER_HOLE + 0 or ship.broken.size() > 0, "a rocket goes through a full shield")
	ship.broken.clear()
	ship.hardened = true
	ship.shield = 100.0
	hull = ship.hull
	g._enemy_fires(Weapons.ROCKET)
	_expect(ship.hull == hull and ship.broken.is_empty() and ship.shield < 100.0, "a hardened shield stops rockets too")
	ship.hardened = false
	ship.shield = 0.0
	ship.shield_on = false
	hull = ship.hull
	g._enemy_fires(Weapons.ION)
	_expect(ship.hull == hull and ship.jammed.size() == 1, "an ion hit on us does no damage but puts a gun or the shield out")
	_run(3 * Net.TICK_HZ + 1)
	_expect(ship.jammed.is_empty(), "for 3 s")
	ship.shield_on = true
	ship.broken.clear()

	# their shield and our new guns
	g.enemy_hit_chance = 0.0
	for k in Net.ESYS_COUNT:
		g.systems_full[k] = maxi(g.systems_full[k], 3)
		g.systems[k] = g.systems_full[k]
	g.enemy_shield = 100.0
	g.aim = Net.ESYS_WEAPONS
	var eh: int = g.enemy_hull
	g._land_on_enemy(Weapons.LASER, Net.ESYS_WEAPONS)
	_expect(g.enemy_hull == eh and absf(g.enemy_shield - 75.0) < 0.5, "their shield stops our laser and loses 25")
	g._land_on_enemy(Weapons.ION, Net.ESYS_WEAPONS)
	_expect(g.enemy_hull == eh and absf(g.enemy_shield - 40.0) < 0.5, "an ion shot takes 35 off it and nothing off the hull")
	g._land_on_enemy(Weapons.ROCKET, Net.ESYS_WEAPONS)
	_expect(g.enemy_hull == eh - 2, "a rocket goes through it: 2 damage")
	g.enemy_shield = 0.0
	g._land_on_enemy(Weapons.ION, Net.ESYS_HELM)
	_expect(g.down(Net.ESYS_HELM) and g.systems[Net.ESYS_HELM] == 3 and g.enemy_hull == eh - 2, "with no shield an ion hit puts its bridge out, without damage")
	_run(3 * Net.TICK_HZ + 1)
	_expect(not g.down(Net.ESYS_HELM), "for 3 s")
	g._land_on_enemy(Weapons.EMP, Net.ESYS_ENGINE)
	_run(5 * Net.TICK_HZ)
	_expect(g.down(Net.ESYS_ENGINE), "an EMP rocket puts a system out")
	_run(Net.TICK_HZ + 1)
	_expect(not g.down(Net.ESYS_ENGINE), "for 6 s")
	g.enemy_shield = 100.0
	g._mend_next = server.tick + 100000
	eh = g.enemy_hull
	var got := 0
	g._rng.seed = 49                     # a fixed roll: 20 coin tosses fell 17 to 3 once on CI
	for k in 20:
		g.enemy_shield = 100.0
		var was: int = g.enemy_hull
		g._land_on_enemy(Weapons.BLASTER, Net.ESYS_HELM)
		if g.enemy_hull < was:
			got += 1
		g.enemy_hull = eh
	_expect(got >= 4 and got <= 16, "half the blaster's pellets go through a full shield (%d of 20)" % got)
	g.systems[Net.ESYS_SHIELDS] = 1
	g._land_on_enemy(Weapons.HEAVY, Net.ESYS_SHIELDS)
	g.enemy_shield = 0.0
	g._land_on_enemy(Weapons.HEAVY, Net.ESYS_SHIELDS)
	_expect(g.down(Net.ESYS_SHIELDS) and g.enemy_shield == 0.0, "a heavy laser through the shield knocks out its generator, and its shield falls")
	_run(Net.TICK_HZ * 2)
	_expect(g.enemy_shield == 0.0, "and does not come back")

	# the rapid laser: six shots
	ship.mounts[0] = Weapons.RAPID
	ship.armed[0] = 1
	ship.armed[1] = 0
	g.charge[0] = 1.0
	g.enemy_hull = 12
	g.aim = Net.ESYS_HELM
	g.fire(p, 0)
	_expect(g.enemy_hull <= 12 and g.charge[0] == 0.0, "the rapid laser fires a burst (%d damage of 6 shots)" % (12 - g.enemy_hull))
	# the cutting beam
	ship.mounts[0] = Weapons.BEAM
	g.charge[0] = 1.0
	g.enemy_hull = 12
	g.enemy_shield = 0.0
	g.aim = Net.ESYS_CREW
	g.systems[Net.ESYS_CREW] = 20
	g.systems_full[Net.ESYS_CREW] = 20
	d._pirates_party = 10
	g.fire(p, 0)
	_expect(g.enemy_hull == 11 and g.beam_left[0] == Weapons.BEAM_PULSES - 1, "the beam burns at once and never misses")
	g.aim = Net.ESYS_HELM
	_run(Weapons.BEAM_PULSES * Net.TICK_HZ)
	_expect(g.enemy_hull == 12 - Weapons.BEAM_PULSES and g.beam_left[0] == 0 and g.systems[Net.ESYS_CREW] == 19 and g.systems[Net.ESYS_HELM] < 3,
		"it burns %d s, a point a second, and follows the aim to another room" % Weapons.BEAM_PULSES)
	g.systems[Net.ESYS_SHIELDS] = 3
	g.enemy_shield = 100.0
	g.charge[0] = 1.0
	var eh2: int = g.enemy_hull
	g.fire(p, 0)
	_run(Weapons.BEAM_PULSES * Net.TICK_HZ)
	_expect(g.enemy_hull == eh2 and g.enemy_shield > 50.0, "a shield that holds keeps the beam out, and loses little")
	# rockets need rockets
	ship.mounts[0] = Weapons.ROCKET
	ship.store[Net.ITEM_ROCKET] = 0
	g.charge[0] = 1.0
	g.fire(p, 0)
	_expect(g.charge[0] == 1.0, "a rocket launcher does not fire with no rockets in the cargo")
	ship.store[Net.ITEM_ROCKET] = 2
	g.fire(p, 0)
	_expect(g.charge[0] == 0.0 and ship.store[Net.ITEM_ROCKET] == 1, "and spends one when it does")
	# the tractor beam (v50)
	ship.mounts[0] = Weapons.TRACTOR
	g.enemy_hull = 12
	g.systems[Net.ESYS_HELM] = 3
	g.systems_out[Net.ESYS_HELM] = 0
	g.systems[Net.ESYS_SHIELDS] = 3
	g.enemy_shield = 100.0
	g.charge[0] = 1.0
	g.fire(p, 0)
	_expect(not g.held() and g.enemy_shield == 100.0 - Weapons.BEAM_SHIELD and g.enemy_hull == 12, "a shield that holds keeps the tractor beam out")
	g.enemy_shield = 0.0
	g.systems[Net.ESYS_SHIELDS] = 0
	g.charge[0] = 1.0
	var dock_before: int = d._pirates_dock_at
	g.fire(p, 0)
	_expect(g.held() and g.enemy_hull == 12, "with the shield down it holds the ship, and does no damage")
	_expect(is_equal_approx(g._hit_chance(Weapons.LASER), 0.95) and is_equal_approx(g._hit_chance(Weapons.RAPID), 0.6),
		"while it holds, our shots hit %d%% more often, up to 95%%" % roundi(Weapons.TRACTOR_BONUS * 100))
	g.flee = 0.0
	_run(Net.TICK_HZ * 2)
	_expect(g.flee == 0.0 and (dock_before < 0 or d._pirates_dock_at >= dock_before + Net.TICK_HZ * 2),
		"a held ship charges no jump and comes no closer")
	g.flee = -1.0
	_run(roundi(Weapons.TRACTOR_HOLD * Net.TICK_HZ))
	_expect(not g.held(), "it lets go after %d s" % int(Weapons.TRACTOR_HOLD))
	var pk := g.packet()
	_expect(Weapons.of_item(Weapons.item_of(Weapons.TRACTOR)) == Weapons.TRACTOR and Weapons.item_of(Weapons.TRACTOR) != Net.ITEM_ROCKET
		and Weapons.of_item(Net.ITEM_ROCKET) == Weapons.NONE and Items.cargo(Weapons.item_of(Weapons.SIPHON)) and pk.size() > 0,
		"the new beams are cargo things of their own, apart from the rockets")
	# the siphon beam (v50)
	ship.mounts[0] = Weapons.SIPHON
	g.systems[Net.ESYS_SHIELDS] = 3
	g.enemy_shield = 100.0
	ship.shield_on = true
	ship.shield = 20.0
	g.charge[0] = 1.0
	var our0: float = ship.shield
	g.fire(p, 0)
	_run(Weapons.SIPHON_PULSES * Net.TICK_HZ)
	var took := Weapons.SIPHON_DRAIN * Weapons.SIPHON_PULSES
	_expect(g.beam_left[0] == 0 and g.enemy_hull == 12 and g.enemy_shield <= 100.0 - took + 15.0 and ship.shield >= our0 + took - 1.0,
		"the siphon drains %d of their shield into ours (theirs %d, ours %d)" % [roundi(took), roundi(g.enemy_shield), roundi(ship.shield)])
	ship.mounts[0] = Weapons.LASER
	g.enemy_hit_chance = -1.0
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	d.pirates_escaped()
	_run(2)

	# the trader
	server.ship.sector = _trader_sector()
	_expect(server.ship.sector >= 0, "(a trader nearby for the trade checks)")
	if server.ship.sector < 0:
		return
	server.ship.pos = server.sectors.spot[server.ship.sector]
	server.ship.in_reach = true
	var offers: Dictionary = server.supplies.offers()
	var guns := 0
	for item in offers.keys():
		if item is int and Weapons.of_item(item) != Weapons.NONE:
			guns += 1
	var kind := server.supplies.deal()
	var guns_ok := (guns >= 3 and guns <= 5) if kind == Sectors.DEAL_ARMS else ((guns >= 1 and guns <= 2) if kind == Sectors.DEAL_BLACK else guns == 0)
	_expect(guns_ok and (offers.has(Net.ITEM_ROCKET) == (kind != Sectors.DEAL_JUNK) or server.supplies.wanted().has(Net.ITEM_ROCKET)) \
			and (offers.has(Net.ITEM_PATCH) or server.supplies.wanted().has(Net.ITEM_PATCH)),   # (v77: not what it looks for)
		"a trader (%s) sells %d kinds of ship gun, rockets unless it deals in junk, and the usual things" % [Sectors.DEAL_NAMES[kind], guns])
	_expect(server.supplies.offers() == offers, "always the same at the same place")
	ship.credits = 1000
	var lp = _at_locker(p)
	var some_gun: int = -1
	var not_sold: int = -1
	for item in offers.keys():
		if item is int and Weapons.of_item(item) != Weapons.NONE:
			some_gun = item
	for w in Weapons.OURS:
		if not offers.has(Weapons.item_of(w)):
			not_sold = Weapons.item_of(w)
	if some_gun < 0:
		some_gun = Net.ITEM_PATCH                 # (a junk dealer: buy and sell a patch instead)
	var n0 := int(ship.store.get(some_gun, 0))
	server.supplies.store_asked(lp, Net.STORE_BUY, some_gun)
	_expect(int(ship.store[some_gun]) == n0 + 1 and ship.credits == 1000 - int(offers[some_gun]), "a ship's gun is bought into the cargo")
	_expect(Weapons.of_item(some_gun) == Weapons.NONE or not server.supplies.offers().has(some_gun), "the trader had one of it: it is gone once bought")
	var n1 := int(ship.store.get(not_sold, 0))
	server.supplies.store_asked(lp, Net.STORE_BUY, not_sold)
	_expect(int(ship.store.get(not_sold, 0)) == n1, "what this trader does not have cannot be bought")
	var c0: int = ship.credits
	server.supplies.store_asked(lp, Net.STORE_SELL, some_gun)
	var paid := server.supplies.sell_price(some_gun)
	_expect(int(ship.store[some_gun]) == n0 and ship.credits == c0 + paid, "and sold back for its share of the price (%d)" % paid)
	server.supplies.store_asked(lp, Net.STORE_BUY_BACK, some_gun)
	_expect(int(ship.store[some_gun]) == n0 + 1 and ship.credits == c0, "and bought back for what the trader paid")
	ship.hardened = false
	server.supplies.store_asked(lp, Net.STORE_HARDEN, 0)
	_expect(ship.hardened == offers.has("harden"), "the shield hardening only where it is offered (%s)" % ("offered" if offers.has("harden") else "not offered"))
	var tp: PackedByteArray = server.supplies.trade_packet()
	var now: Dictionary = server.supplies.offers()
	_expect(tp[0] == Net.S_TRADE and tp[1] == now.size() - (1 if now.has("harden") else 0), "clients are told what the trader offers")


func _rng_through(g: Gunnery, level: float) -> bool:
	return g._rng.randf() < Weapons.through_chance(level)


func _trader_sector() -> int:
	## The sector the ship is in, made a trader's.
	server.sectors.kind[server.ship.sector] = Sectors.TRADER
	return server.ship.sector


func _heal(p) -> void:
	p.supply = true
	p.tank = 1.0e9
	p.health = 100.0
	p.wounds = 0.0
	p.cond = Net.COND_OK
	p.st.down = false


func _at_locker(p):
	var map := server.map
	var locker: int = map.locker.keys()[0]
	var front: int = map.fitting_front(locker)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == locker:
			break
	return p


func _to_console(p) -> void:
	var map := server.map
	var console: int = map.gun_console.keys()[0]
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN
