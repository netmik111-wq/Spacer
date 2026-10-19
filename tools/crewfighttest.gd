extends SceneTree
## Checks the fights for the whole crew (v68), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/crewfighttest.gd
## The engineer's power panel at the SMES powers the guns, the shield and the
## engines, switches the ship's own systems off for more power (the lights off
## darken the ship) and overcharges the reactor at a risk; the pilot's evade
## makes their next shots miss more, costs the SMES and rests; rounds loaded into
## a breech by hand speed a gun up and are fired first; a fight may have a goal
## (a cargo pod, a bounty, a courier); the alert levels send the bots and lock the
## blast doors; breakdowns come from hits near them, not from nothing; the fight's
## details are told on the bridge only. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Power := preload("res://src/server/power.gd")
const Stations := preload("res://src/server/stations.gd")
const Mounts := preload("res://src/server/mounts.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Director := preload("res://src/server/director.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26420, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.gunnery.ransom_chance = 0.0
	server.gunnery.enemy_hit_chance = 0.0
	server.systems.knock_chance = 0.0
	_breakers()
	_overcharge()
	_fight()
	_knock_on()
	_no_random_faults()
	_goals()
	server.stop()
	print("crewfighttest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _breakers() -> void:
	print("  -- the power panel: breakers")
	var pw: Power = server.power
	_run(5)
	var budget := pw.budget()
	_expect(pw.base_load() == Power.BASE_LOAD and pw.freed() == 0, "every breaker on: the ship draws its usual %d" % Power.BASE_LOAD)
	pw.set_breaker(Net.BREAKER_AIR, false)
	_expect(not pw.air_on() and pw.budget() == budget + 1, "the air plant off: one more for the guns (%d -> %d)" % [budget, pw.budget()])
	pw.set_breaker(Net.BREAKER_TRAYS, false)
	_expect(not pw.trays_on() and pw.freed() == 2, "the trays off too: two freed")
	var cell := server.crew.spawn_point()
	var c := cell.y * server.map.width + cell.x
	_expect(pw.light_at(c), "the lights are on aboard")
	pw.set_breaker(Net.BREAKER_LIGHTS, false)
	_expect(not pw.light_at(c) and server.ship.lights_off, "the lights off: dark aboard (but the ship has power: %s)" % server.powered())
	_expect(server.ship.power_packet()[5] == 0, "and the clients are told the lights are off")
	_expect(pw.freed() == Power.BASE_LOAD - Power.CORE_LOAD, "everything off but the core: %d freed" % pw.freed())
	var saved := pw.save_panel()
	for b in Power.BREAKERS:
		pw.set_breaker(b, true)
	_expect(pw.freed() == 0 and not server.ship.lights_off, "all back on")
	pw.load_panel(saved)
	_expect(pw.breaker.count(0) == 3 and server.ship.lights_off, "the panel comes back from a save")
	for b in Power.BREAKERS:
		pw.set_breaker(b, true)


func _overcharge() -> void:
	print("  -- the power panel: overcharging the reactor")
	var pw: Power = server.power
	var cap := server.crew.new_player("Инженер")
	pw.over_risk = 0.0
	var before := pw.reactor_now()
	pw.overcharge(cap, true)
	_expect(pw.overcharged() and pw.reactor_now() == before + Power.OVER_POWER, "overcharged: +%d (%d -> %d)" % [Power.OVER_POWER, before, pw.reactor_now()])
	_run(roundi(Power.OVER_SECONDS * Net.TICK_HZ) + 2)
	_expect(not pw.overcharged() and pw.reactor_now() == before, "it ends by itself after %d s" % int(Power.OVER_SECONDS))
	pw.overcharge(cap, true)
	_expect(not pw.overcharged(), "and cannot start again while the reactor cools")
	pw.over_rest_until = 0
	pw.over_risk = 1.0
	pw.overcharge(cap, true)
	_run(Net.TICK_HZ * 2)
	var engine: int = server.map.engine.keys()[0]
	_expect(not pw.overcharged() and (server.ship.broken.has(engine) or not pw.engine_running()), "pushed too far, it burns the engine")
	server.ship.broken.erase(engine)
	pw.over_risk = Power.OVER_RISK
	pw.over_rest_until = 0
	server.power.set_charge(1.0)
	_run(Net.TICK_HZ * 6)
	_expect(pw.engine_running(), "mended, the engine runs again")


func _fight() -> void:
	print("  -- a fight: alert, panel, evade, loaded mounts, bridge news")
	var st: Stations = server.stations
	var g: Gunnery = server.gunnery
	var pw: Power = server.power
	server.shipyard.force_class = Net.ECLASS_RAIDER
	_expect(server.derelict.pirates_come(3, true), "a raider comes")
	_run(2)
	_expect(st.alert == Net.ALERT_YELLOW, "the alert goes up to yellow by itself")
	var bots: Array = []
	for p in server.players:
		if p != null and p.bot:
			bots.append(p)
	_expect(bots.size() == 2 and bots.all(func(b) -> bool: return b.order == Net.POST_REPAIR), "the free bots go to mend")
	var cap := server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	_stand(cap, Net.POST_HELM)
	_run(2)
	_expect(server.chat.on_bridge(cap), "the captain at the controls is on the bridge")
	var away := server.crew.new_player("Механик")
	var spot := server.crew.spawn_point()
	away.st.place(server.map.engine.keys()[0] % server.map.width, spot.y)
	_stand(away, Net.POST_ENGINE)
	_expect(not server.chat.on_bridge(away), "one in the engine room is not")

	# red alert
	st.alert_asked(cap, Net.ALERT_RED)
	_expect(st.alert == Net.ALERT_RED, "the captain calls red alert")
	_expect(bots.all(func(b) -> bool: return b.order != Net.POST_FREE and b.order != Net.POST_REPAIR), "every bot goes to a post")
	var locked := 0
	for d in server.map.other_first_door:
		locked += server.doors.blast[d]
	_expect(locked == server.map.other_first_door, "every door is locked as a blast door (%d of %d)" % [locked, server.map.other_first_door])
	st.alert_asked(cap, Net.ALERT_GREEN)
	locked = 0
	for d in server.map.other_first_door:
		locked += server.doors.blast[d]
	_expect(st.alert == Net.ALERT_GREEN and locked == 0, "stood down: the doors open again")
	_expect(bots.all(func(b) -> bool: return b.order == Net.POST_FREE), "and the bots are free")

	# the engines on the panel add to the dodge
	var dodge := st.our_dodge()
	var used := g.power_used()
	pw.set_engines(cap, 1)
	if pw.engines == 1:
		_expect(is_equal_approx(st.our_dodge(), dodge + Power.ENGINE_DODGE) and g.power_used() == used + Power.ENGINE_POWER,
			"power to the engines: dodge %d%% -> %d%%, it takes %d" % [roundi(dodge * 100), roundi(st.our_dodge() * 100), Power.ENGINE_POWER])
	else:
		_expect(pw.budget() - used < Power.ENGINE_POWER, "no spare power for the engines, and it says so")
	pw.set_engines(cap, 0)
	# a gun switched off and on from the panel
	g.arm(cap, 0, false)
	_expect(server.ship.armed.size() > 0 and server.ship.armed[0] == 0, "the panel cuts gun 1")
	g.arm(cap, 0, true)
	_expect(server.ship.armed[0] == 1 or g.power_used() + Weapons.power(server.ship.mounts[0]) > pw.budget(), "and powers it again")

	# the evade
	var charge := pw.charge()
	st.evade_asked(cap)
	_expect(st.evading(), "the captain at the controls evades")
	_expect(absf(charge - pw.charge() - Stations.EVADE_COST) < 1.0, "it costs the SMES %d (%d -> %d)" % [int(Stations.EVADE_COST), roundi(charge), roundi(pw.charge())])
	_run(roundi((Stations.EVADE_SECONDS + Stations.EVADE_SKILL) * Net.TICK_HZ) + 2)
	_expect(not st.evading(), "the moment passes")
	st.evade_asked(cap)
	_expect(not st.evading(), "it cannot be pressed again before it rests")
	_run(roundi(Stations.EVADE_REST * Net.TICK_HZ))
	st.evade_asked(cap)
	_expect(st.evading(), "rested, it works again")
	# their shots during the evade hit less: count hits over many volleys
	g.enemy_hit_chance = -1.0
	var hits := [0, 0]
	for k in 2:
		for n in 200:
			st.evade_until = server.tick + 100 if k == 1 else 0
			hits[k] += _their_hits(g)
	g.enemy_hit_chance = 0.0
	st.evade_until = 0
	_expect(hits[1] < hits[0], "their shots hit less often during the evade (%d -> %d of 200 rolls)" % hits)

	# rounds loaded by hand
	var m: Mounts = server.mounts
	var i := -1
	for k in server.ship.mounts.size():
		if m.ammo_of(k) == 0:
			i = k
			break
	var kinetic := -1
	for k in server.ship.mounts.size():
		if m.ammo_of(k) != 0:
			kinetic = k
	if kinetic < 0:
		# put an autocannon up on the last mount for this
		kinetic = server.ship.mounts.size() - 1
		m.unload(kinetic)
		server.ship.mounts[kinetic] = Weapons.AUTOCANNON
		server.outfit.refresh()
	var ammo := m.ammo_of(kinetic)
	_expect(ammo != 0, "a mount with a kinetic gun (%s)" % Weapons.full_name(server.ship.mounts[kinetic], Weapons.FX_NONE))
	var bare := m.pace(kinetic)
	m.loaded[kinetic] = 2
	_expect(m.pace(kinetic) > bare, "loaded by hand it charges faster (x%.2f -> x%.2f)" % [bare, m.pace(kinetic)])
	var in_store := int(server.ship.store.get(ammo, 0))
	_expect(m.take_round(kinetic) and m.loaded[kinetic] == 1 and int(server.ship.store.get(ammo, 0)) == in_store, "it fires the loaded round first, not the locker's")
	m.unload(kinetic)
	_expect(m.loaded[kinetic] == 0 and int(server.ship.store.get(ammo, 0)) == in_store + 1, "taken down, what was loaded goes back into the locker")
	server.ship.store[ammo] = 0
	server.supplies.tell_store()
	_expect(not m.has_round(kinetic), "an empty locker and breech: no round")
	m.loaded[kinetic] = 1
	_expect(m.has_round(kinetic), "one loaded by hand fires though the locker is empty")
	server.ship.store[ammo] = in_store
	if i >= 0:
		_expect(m.has_round(i), "a laser needs no rounds")

	# a bot on the engine post keeps the power on
	g.switch_shield(null, false)
	st.order_asked(cap, bots[0].slot, Net.POST_ENGINE)
	_run(Net.TICK_HZ * 50)
	_expect(st.at_post(Net.POST_ENGINE) == bots[0], "a bot mans the engine room")
	_expect(server.ship.shield_on or g.shield_cell() < 0, "and switches the shield back on from the panel")
	st.order_asked(cap, Net.NOBODY, Net.POST_FREE)

	g.enemy_gone()
	server.derelict.pirates_wrecked()
	_run(Net.TICK_HZ * 2)
	_expect(st.alert == Net.ALERT_GREEN, "after the fight the alert is green")
	away.st.place(spot.x, spot.y)
	_stand(cap, -1)


func _their_hits(g: Gunnery) -> int:
	## One roll of their shot at the chance _enemy_fires uses now.
	var chance := clampf(0.7 + Gunnery.ENEMY_EDGE + server.stations.their_hit_bonus() - server.stations.our_dodge()
		- (Stations.EVADE_DODGE if server.stations.evading() else 0.0), 0.05, 0.95)
	return 1 if server.rng.randf() < chance else 0


func _knock_on() -> void:
	print("  -- breakdowns come from hits near them")
	var sys = server.systems
	sys.knock_chance = 0.0
	var some: int = server.map.hull[0]
	_expect(sys.knock_on(some, true) == "", "with no luck nothing breaks")
	sys.knock_chance = 1.0
	var broke := 0
	for cell: int in server.map.hull.slice(0, 40):
		if sys.knock_on(cell, false) != "":
			broke += 1
	_expect(broke > 0, "with every hit lucky, things near the hits break (%d of 40)" % broke)
	sys.knock_chance = 0.0
	# far from everything: a hull cell with nothing near it breaks nothing
	server.ship.broken.clear()
	for d in server.doors.jammed.size():
		server.doors.jammed[d] = 0
		server.doors.faulty[d] = 0
	_run(5)


func _no_random_faults() -> void:
	print("  -- no breakdowns out of nothing")
	var faults := [Director.CONSOLE_FAULT, Director.ENGINE_FAULT, Director.AIR_PLANT_FAULT, Director.DOOR_JAM,
		Director.SHUTTER_FAULT, Director.POWER_GLITCH]
	var bad := 0
	for e: Dictionary in Director.EVENTS:
		if faults.has(int(e["id"])) and int(e["weight"]) != 0:
			bad += 1
	_expect(bad == 0, "the director never picks a fault by chance")


func _goals() -> void:
	print("  -- fights with a goal")
	var g: Gunnery = server.gunnery
	var d = server.derelict
	# the plain pirate: no goal unless the director or the road sent it
	server.shipyard.force_class = Net.ECLASS_RAIDER
	_expect(d.pirates_come(3, true), "a raider comes")
	_expect(g.goal == Net.GOAL_NONE, "one not sent by the director has no goal")
	g.enemy_gone()
	d.pirates_wrecked()
	_run(Net.TICK_HZ * 2)

	# the cargo pod
	server.shipyard.force_class = Net.ECLASS_RAIDER
	g.goal_for_test = Net.GOAL_CARGO
	_expect(d.pirates_come(3, true), "a raider with a cargo pod comes")
	_expect(g.goal == Net.GOAL_CARGO and g.cargo_room >= 0, "its pod is in a room (%d)" % g.cargo_room)
	_expect(g.packet().size() > 0, "the gun console is told")
	var other := (g.cargo_room + 1) % g.room_sys.size()
	_expect(g._cargo_hit(other) == "" and not g.goal_lost, "a hit elsewhere leaves it whole")
	var credits: int = server.ship.credits
	var pay := g.goal_pay
	_expect(g._goal_paid() != "" and server.ship.credits == credits + pay, "whole when it is beaten: +%d" % pay)
	g.goal_lost = false
	_expect(g._cargo_hit(g.cargo_room) != "" and g.goal_lost, "a hit in its room smashes it")
	credits = server.ship.credits
	_expect(g._goal_paid() == "" and server.ship.credits == credits, "smashed, it pays nothing")
	g.enemy_gone()
	d.pirates_wrecked()
	_run(Net.TICK_HZ * 2)

	# the bounty
	server.shipyard.force_class = Net.ECLASS_RAIDER
	g.goal_for_test = Net.GOAL_BOUNTY
	_expect(d.pirates_come(3, true), "a wanted raider comes")
	_expect(g.goal == Net.GOAL_BOUNTY and g.goal_pay > 0, "a bounty of %d" % g.goal_pay)
	credits = server.ship.credits
	pay = g.goal_pay
	g.systems[Net.ESYS_WEAPONS] = 0
	g.systems[Net.ESYS_ENGINE] = 0
	_run(3)
	_expect(not g.fighting() and server.ship.credits == credits + pay, "its guns and engine out, it gives up: +%d" % pay)
	_run(Net.TICK_HZ * 2)

	# the courier
	server.shipyard.force_class = Net.ECLASS_RAIDER
	g.goal_for_test = Net.GOAL_RUNNER
	_expect(d.pirates_come(3, true), "a courier comes")
	_expect(g.goal == Net.GOAL_RUNNER and g._flee_seconds() == Gunnery.RUNNER_FLEE, "it runs at once: %d s to stop it" % int(Gunnery.RUNNER_FLEE))
	g.enemy_gone()
	d.pirates_wrecked()
	_run(Net.TICK_HZ * 2)
	_expect(g.goal == Net.GOAL_NONE, "gone, the goal is forgotten")

	# the director's raid may roll one
	g.goal_next = true
	server.shipyard.force_class = Net.ECLASS_RAIDER
	var seen := {}
	for n in 60:
		g.goal_next = true
		g._roll_goal()
		seen[g.goal] = true
	_expect(seen.size() >= 3, "the director's raids roll goals now and then (%d kinds of 60 rolls)" % seen.size())
	g.enemy_gone()
	d.pirates_wrecked()
	_run(Net.TICK_HZ * 2)


func _stand(p, post: int) -> void:
	## Puts a character at a post (or out of the way, -1).
	var map := server.map
	if post < 0:
		var spot := server.crew.spawn_point()
		p.st.place(spot.x, spot.y)
		return
	var s: Array = server.stations.spots[post][0]
	p.st.place(int(s[0]) % map.width, int(s[0]) / map.width)
	p.st.facing = int(s[1])


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
