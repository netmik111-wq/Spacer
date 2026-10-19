extends SceneTree
## Checks the ship's power (v61), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/powertest.gd
## The SMES carries the ship when the engine stops and the ship goes dark only
## when it is empty too; the bridge's backup keeps the bridge going then; a hit
## takes its whole charge; it charges from what the reactor has spare and adds
## its boost in a fight; its terminal works; coils make it bigger; the ion storm
## halves the reactor, its surges put things out on both ships and slow the
## pirates; meteors strike the pirates too; the hull is mended from outside, and
## a bot on "work" goes out through the airlock to do it; it all survives a save.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Power := preload("res://src/server/power.gd")
const Hazards := preload("res://src/server/hazards.gd")
const Outside := preload("res://src/server/outside.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer
var kept: Array = []


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26380, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false
	_carrying()
	_backup()
	_hit_and_charge()
	_terminal()
	_coils()
	_storm()
	_meteors()
	_outside()
	_bot_outside()
	_saved()
	print("powertest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _main() -> Dictionary:
	return server.power.main_units()[0]


func _engine() -> int:
	return server.map.engine.keys()[0]


func _carrying() -> void:
	print("  -- the SMES carries the ship")
	var pw: Power = server.power
	_expect(server.map.smes.size() == 1 and server.map.smes_small.size() == 1, "ship02 has an SMES and the bridge's backup")
	_expect(pw.charge() >= pw.full() - 0.01, "it starts full (%d)" % roundi(pw.charge()))
	_run(5)
	_expect(server.powered() and pw.budget() == server.outfit.reactor() + Power.BOOST, "with the engine going: power, and the reactor plus the boost for the guns (%d)" % pw.budget())
	server.ship.broken[_engine()] = true
	_run(Net.TICK_HZ * 10)
	_expect(server.powered() and pw.carrying(), "the engine is out: the ship still has power from the SMES")
	var used := pw.full() - pw.charge()
	_expect(absf(used - Power.BASE_LOAD * 10.0) < 2.0, "out of a fight it draws the ship's own %d a second (%.1f in 10 s)" % [Power.BASE_LOAD, used])
	pw.set_charge(0.0)
	_run(2)
	_expect(not server.powered(), "empty, with the engine out: no power")
	_expect(server.ship.broken.size() == 1, "and nothing breaks from it")
	server.ship.broken.erase(_engine())
	_run(2)
	_expect(server.powered(), "the engine mended: power again")


func _backup() -> void:
	print("  -- the bridge's backup")
	var pw: Power = server.power
	server.ship.broken[_engine()] = true
	pw.set_charge(0.0)
	for u: Dictionary in pw.units:
		if u["small"]:
			u["charge"] = pw.capacity(u)
	_run(2)
	var helm: int = server.map.helm.keys()[0]
	var engine_room: int = server.map.fitting_front(_engine())
	_expect(not server.powered() and pw.backup_on(), "the ship is dark, the backup holds the bridge")
	_expect(pw.at(helm) and server.map.on_backup(helm), "the helm works on the backup")
	_expect(not pw.at(engine_room), "the engine room stays dark")
	var p = server.crew.new_player("Пилот")
	kept = [p]
	var s: Array = server.stations._spots_for(helm)[0]
	p.st.place(int(s[0]) % server.map.width, int(s[0]) / server.map.width)
	p.st.facing = int(s[1])
	_expect(server.systems.at_console(p, server.map.helm), "somebody at the helm can use it")
	server.crew.remove(p)
	kept = []
	server.ship.broken.erase(_engine())
	pw.set_charge(1.0)
	_run(2)


func _hit_and_charge() -> void:
	print("  -- a hit, and charging")
	var pw: Power = server.power
	var u := _main()
	server.ship.broken[int(u["cell"])] = true
	_run(1)
	_expect(float(u["charge"]) == 0.0, "an SMES that is hit loses its whole charge")
	server.ship.broken.erase(int(u["cell"]))
	_run(Net.TICK_HZ * 10)
	_expect(absf(float(u["charge"]) - Power.INPUT_MAX * 10.0) < 2.0, "it charges %d a second from the reactor's spare power (%.1f in 10 s)" % [Power.INPUT_MAX, float(u["charge"])])
	pw.set_charge(1.0)


func _terminal() -> void:
	print("  -- the terminal")
	var pw: Power = server.power
	var u := _main()
	var p = server.crew.new_player("Инженер")
	kept = [p]
	pw.asked(p, 0, Power.ACT_CHARGE, 0)
	_expect(u["charging"], "not facing it: nothing changes")
	var s: Array = server.stations._spots_for(int(u["cell"]))[0]
	p.st.place(int(s[0]) % server.map.width, int(s[0]) / server.map.width)
	p.st.facing = int(s[1])
	_expect(server.repairs.usable_ahead(p), "facing it: it can be used")
	pw.asked(p, 0, Power.ACT_CHARGE, 0)
	pw.asked(p, 0, Power.ACT_LEVEL, 99)
	_expect(not u["charging"] and int(u["level"]) == Power.OUTPUT_MAX, "charging off, output up to its most (%d)" % int(u["level"]))
	pw.asked(p, 0, Power.ACT_OUTPUT, 0)
	server.ship.broken[_engine()] = true
	_run(2)
	_expect(not server.powered(), "output off and the engine out: dark, full as it is")
	pw.asked(p, 0, Power.ACT_OUTPUT, 1)
	pw.asked(p, 0, Power.ACT_CHARGE, 1)
	pw.asked(p, 0, Power.ACT_LEVEL, Power.OUTPUT_START)
	_run(2)
	_expect(server.powered(), "output on: power again")
	server.ship.broken.erase(_engine())
	server.crew.remove(p)
	kept = []
	var pkt := pw.packet()
	_expect(pkt[0] == Net.S_SMES and pkt[3] == pw.units.size() and pkt.size() == 4 + 15 * pw.units.size() + 9 + 4, "the terminals' packet (%d bytes)" % pkt.size())


func _coils() -> void:
	print("  -- coils")
	var pw: Power = server.power
	var u := _main()
	server.ship.gear[Gear.SYS_COILS] = 3
	server.outfit.refresh()
	_expect(pw.capacity(u) == Power.CAPACITY * 2.0 and pw.input_max(u) == Power.INPUT_MAX + 4, "superconducting coils: twice the charge, +4 a second")
	server.ship.gear[Gear.SYS_COILS] = 1
	server.outfit.refresh()
	_expect(float(u["charge"]) <= pw.capacity(u), "back to the built-in ones, it holds what fits")
	var p = server.crew.new_player("Механик")
	kept = [p]
	p.take_job(Net.JOB_ENGINEER)
	var s: Array = server.stations._spots_for(int(u["cell"]))[0]
	p.st.place(int(s[0]) % server.map.width, int(s[0]) / server.map.width)
	p.st.facing = int(s[1])
	p.slots[0] = Net.ITEM_GEAR + Gear.COILS_2
	p.hand = 0
	_expect(server.outfit.can(p, int(u["cell"])) == "", "an engineer can put coils into the SMES")
	server.crew.remove(p)
	kept = []


func _storm() -> void:
	print("  -- the ion storm")
	var pw: Power = server.power
	var hz: Hazards = server.hazards
	server.admin.place_ship(Sectors.ION_STORM)
	_run(2)
	_expect(hz.in_storm(), "the ship is inside an ion storm")
	_expect(pw.reactor_now() == server.outfit.reactor() / 2, "the reactor gives half (%d)" % pw.reactor_now())
	var said := hz.surge()
	_expect(said.begins_with("Ионный разряд:") and not server.ship.jammed.is_empty(), "a surge puts one of our things out (%s)" % said)
	for c: int in server.ship.jammed.keys():
		_expect(not server.map.engine.has(c) and not server.map.helm.has(c) and not server.map.chart.has(c), "never the engine nor a console")
	_expect(server.derelict.pirates_come(3, true) and server.gunnery.fighting(), "a pirate comes to fight inside the storm")
	_expect(is_equal_approx(hz.enemy_pace(), 1.0 / Hazards.STORM_PACE) and hz.enemy_regen() == Hazards.STORM_REGEN, "its guns charge slower and its shield refills at half pace")
	var g = server.gunnery
	said = hz.surge()
	var out := false
	for sys in g.systems_out.size():
		out = out or g.systems_out[sys] > server.tick
	_expect(out and said.contains("пиратов"), "the surge puts out one of its systems too")
	server.ship.jammed.clear()


func _meteors() -> void:
	print("  -- meteors strike the pirates too")
	var g = server.gunnery
	var hull: int = g.enemy_hull
	server.director._do("hole")
	_expect(g.enemy_hull == hull - 1 or not g.fighting(), "a meteor takes a point off its hull (%d -> %d)" % [hull, g.enemy_hull])
	g.enemy_gone()
	server.derelict._leave(true)
	server.systems.seal_all()
	server.admin.place_ship(Sectors.STATION)
	_run(2)
	_expect(not server.hazards.in_storm(), "out of the storm")


func _outside() -> void:
	print("  -- mending the hull from outside")
	var p = server.crew.new_player("Сварщик")
	kept = [p]
	var spots: Dictionary = server.outside._hull_spots()
	_expect(not spots.is_empty(), "there are places out in space beside the hull")
	var at: int = spots.keys()[0]
	p.st.place(at % server.map.width, at / server.map.width)
	p.st.facing = spots[at]
	p.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	p.slots[0] = Net.ITEM_PATCH
	p.slots[1] = Net.ITEM_PATCH
	server.ship.hull = 100
	p.using = true
	_run(Outside.MEND_SECONDS * Net.TICK_HZ + 5)
	p.using = false
	_expect(server.ship.hull == 100 + Outside.HULL_PER_PATCH, "a patch gives the hull %d (%d)" % [Outside.HULL_PER_PATCH, server.ship.hull])
	_expect(p.count(Net.ITEM_PATCH) == 1, "and is used up")
	server.crew.remove(p)
	kept = []


func _bot_outside() -> void:
	print("  -- a bot goes out to mend the hull")
	var cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	kept = [cap]
	var bots: Array = []
	for b in server.players:
		if b != null and b.bot and not b.corpse:
			bots.append(b)
	for b in bots:
		server.stations.order_asked(cap, b.slot, Net.POST_REPAIR)
	server.ship.store[Net.ITEM_PATCH] = 6
	server.ship.store[Net.ITEM_SUIT + Net.SUIT_TANK_STEPS] = maxi(int(server.ship.store.get(Net.ITEM_SUIT + Net.SUIT_TANK_STEPS, 0)), 2)
	server.ship.hull = 120
	server.outside._rest_until = 0
	var went := false
	var ticks := 0
	while ticks < 400 and (not went or not server.outside.trips.is_empty()):
		_run(Net.TICK_HZ)
		ticks += 1
		for b in bots:
			went = went or server.map.floats(b.st.x, b.st.y)
	_expect(went, "a bot floats out through the airlock")
	_expect(server.ship.hull > 120, "it mends the hull (%d)" % server.ship.hull)
	var inside := true
	for b in bots:
		inside = inside and not server.map.floats(b.st.x, b.st.y) and b.cond == Net.COND_OK
	_expect(server.outside.trips.is_empty() and inside, "and comes back in, whole (%d s)" % ticks)
	server.crew.remove(cap)
	kept = []


func _saved() -> void:
	print("  -- saving")
	server.power.set_charge(0.3)
	var data := Campaign.snapshot(server)
	server.power.set_charge(1.0)
	var why := Campaign.restore(server, JSON.parse_string(JSON.stringify(data)))
	_expect(why == "" and absf(server.power.charge() - server.power.full() * 0.3) < 1.0, "the SMES's charge survives a save (%d)" % roundi(server.power.charge()))


func _run(ticks: int) -> void:
	for t in ticks:
		for k in kept:
			k.health = 100.0
			k.wounds = 0.0
			k.tank = 1.0
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
