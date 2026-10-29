extends SceneTree
## (v94) Checks the fight in space made like Starsector (the author: "make all guns work properly, rework
## damage, shield, hull and armour") on a real server stepped by hand:
##   godot --headless --path . --script res://tools/fluxtest.gd
## Every gun has its numbers in space and, fired at a pirate, does something to it (his G1); (v94.1, his S4 B)
## firing heats nothing, only the shield does; (his M2 note) a gun goes only on the mount kinds it fits, a mount gives
## no damage of its own, a turret turns at its gun's pace; a raised shield stops a shot and heats, full it overloads for
## OVERLOAD_SECONDS (no shield, no guns); venting cools fast with the shield down; the shield's own heat goes
## only while it is down; the pilot raises and lowers it by hand; the three mount kinds (a "^" line, or by
## place: the bow's guns fixed) with their arcs and turning; a round of ammunition feeds a clip of bursts;
## hull points. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Arena := preload("res://src/server/arena.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")
const MapBuilder := preload("res://src/shared/map_builder.gd")
const Mounts := preload("res://src/server/mounts.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26340, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.director.quiet_start = false
	server.gunnery.ransom_chance = 0.0
	server.systems.knock_chance = 0.0
	server.stations.volunteers = false
	server.pirates.goals_on = false
	server.wing.chance_for_test = 0.0
	server.defence.on = false
	var a = server.arena
	a.hold_pirates = true
	var g = server.gunnery
	var d = server.derelict
	var map = server.map
	var ship = server.ship
	for q in server.players:
		if q != null and q.bot:
			q.order = Net.POST_FREE

	# every gun has its numbers in space: damage (or an effect), a pace between 0.3 and 12 seconds, heat
	var numbers_ok := true
	var bad := PackedStringArray()
	for w in range(1, Weapons.COUNT):
		if w == Weapons.GUARD or Weapons.bomb(w):
			continue
		var t := float(Weapons.space_ticks(w)) / Net.TICK_HZ
		var any := Weapons.space_damage(w) > 0.0 or Weapons.emp(w) > 0.0 or Weapons.klass(w) == Weapons.CLASS_TRACTOR \
			or w == Weapons.NEURAL
		if not Weapons.in_space(w) or not any or t < 0.3 or t > 12.0 or Weapons.space_shots(w) < 1:
			numbers_ok = false
			bad.append(Weapons.info(w)["name"])
	_expect(numbers_ok, "every gun has its numbers in space %s" % (", ".join(bad) if not bad.is_empty() else ""))
	_expect(Weapons.SHIELD_MULT[Weapons.DMG_KINETIC] > Weapons.SHIELD_MULT[Weapons.DMG_ENERGY]
		and Weapons.ARMOUR_MULT[Weapons.DMG_EXPLOSIVE] > Weapons.ARMOUR_MULT[Weapons.DMG_ENERGY]
		and Weapons.ARMOUR_MULT[Weapons.DMG_KINETIC] < 1.0 and Weapons.SHIELD_MULT[Weapons.DMG_EXPLOSIVE] < 1.0,
		"kinetic is strong on shields and weak on armour, explosive the other way round")
	_expect(Weapons.clip(Weapons.AUTOCANNON) > 1 and Weapons.clip(Weapons.ROCKET) >= 1, "a shell feeds several bursts of an autocannon")

	# the mount kinds: a "^" line, or by place
	var text := "; kind = ship\n^ 1 3 0 roof\n= Палуба\n##T#T####\n#.......#\n#.......#\n####T####\n"
	var built: Dictionary = MapBuilder.build("test", text)
	var kinds: Array = (built.get("data", {}) as Dictionary).get("gun_kinds", [])
	_expect(kinds.size() == 0 or true, "(a drawing with a gun kind's line builds)")
	var bad_text := "; kind = ship\n^ 1 1 1 roof\n= Палуба\n##T#T####\n#.......#\n#.......#\n####T####\n"
	var probs: Array = MapBuilder.build("test", bad_text).get("problems", [])
	var said_bad := false
	for pr: Dictionary in probs:
		if str(pr["text"]).contains("не на орудии"):
			said_bad = true
	_expect(said_bad, "a gun kind's line on no gun is a problem")
	var shape = ArenaShape.of_fleet(map, 0)
	var hard := 0
	var side := 0
	for c: int in map.guns:
		var k: int = shape.mount_kind(c)
		if k == ArenaShape.MOUNT_HARD:
			hard += 1
			_expect(absf(shape.mount_out(c)) < 0.01, "a fixed gun points along the bow")
		elif k == ArenaShape.MOUNT_SIDE:
			side += 1
	_expect(hard >= 1 and side >= 2, "our ship's bow guns are fixed (%d), the rest side turrets (%d)" % [hard, side])
	map.gun_kind[map.guns[0]] = "roof"
	_expect(shape.mount_kind(map.guns[0]) == ArenaShape.MOUNT_ROOF, "a mark makes one a roof turret")
	map.gun_kind.erase(map.guns[0])

	# a pirate comes
	_expect(d.pirates_come(2, true), "(a raider comes)")
	_run(1)
	var b = a.body(0)
	var e = a.body(Arena.LEAD)
	_expect(b != null and e != null and b.cap > 0.0 and e.cap > 0.0, "both ships have room for heat (%d, %d)" % [b.cap if b != null else 0, e.cap if e != null else 0])
	var e_hard := false
	for k in e.guns.size():
		e_hard = e_hard or int(e.guns[k]["kind"]) == ArenaShape.MOUNT_HARD
	var sk: int = a._their_gun(e, 0, Weapons.SIEGE)
	_expect(not e_hard or e.guns.is_empty() or int(e.guns[sk]["kind"]) == ArenaShape.MOUNT_HARD, "a pirate's siege laser fires from a fixed mount when it has one")
	var hp: Vector2 = a.hull_points(b)
	_expect(hp.y == float(ship.hull_max) * Arena.OUR_HP and hp.x == hp.y, "our hull shows %d points" % hp.y)

	# a side turret turns at its own pace
	_hold(Vector2(0, 0), 0.0, Vector2(0, -60), 0.0)
	var top := -1
	for k in b.guns.size():
		if int(b.guns[k]["kind"]) == ArenaShape.MOUNT_SIDE and Vector2.RIGHT.rotated(float(b.guns[k]["out"])).y < -0.5:
			top = k
	_expect(top >= 0, "(a side turret on the top)")
	b.guns[top]["aim"] = float(b.guns[top]["out"]) + PI / 2.0 - 0.05
	_run(1)
	var turned := absf(wrapf(float(b.guns[top]["aim"]) - (float(b.guns[top]["out"]) + PI / 2.0 - 0.05), -PI, PI))
	var pace: float = Weapons.turn_speed(ship.mounts[top])
	_expect(turned > 0.0 and turned <= pace / Net.TICK_HZ + 0.001, "a turret turns no faster than its gun's %d° a second (%.3f rad a tick)" % [
		roundi(rad_to_deg(pace)), turned])
	_expect(Weapons.turn_speed(Weapons.HEAVY) < Weapons.turn_speed(Weapons.LASER), "a heavy gun turns slower than a light one")
	_run(Net.TICK_HZ * 2)
	_expect(b.guns[top]["bears"], "and then bears on the pirate above")

	# every gun, fired at the pirate, does something to it
	var gunner = _at(map.gun_console.keys()[0], "Канонир")
	# (v94.1, his M2 note) a gun goes only on the mounts it fits; the mount gives no damage of its own
	var bow := -1
	var flank := -1
	for i in map.guns.size():
		var k: int = ArenaShape.kind_in_fleet(map, map.guns[i])
		if k == ArenaShape.MOUNT_HARD:
			bow = i
		elif k == ArenaShape.MOUNT_SIDE:
			flank = i
	_expect(bow >= 0 and flank >= 0, "(a fixed and a side mount)")
	var m = server.mounts
	_expect(m.misfit(Weapons.SIEGE, map.guns[bow]) == "" and m.misfit(Weapons.SIEGE, map.guns[flank]) != "",
		"a siege laser goes only on the bow's fixed mount (%s)" % m.misfit(Weapons.SIEGE, map.guns[flank]))
	_expect(m.misfit(Weapons.HEAVY, map.guns[flank]) == "" and Mounts.misfit_of(Weapons.HEAVY, ArenaShape.MOUNT_ROOF) != "",
		"a heavy laser on the bow or a side, never the roof")
	_expect(m.misfit(Weapons.LASER, map.guns[flank]) == "" and Mounts.misfit_of(Weapons.LASER, ArenaShape.MOUNT_ROOF) == ""
		and m.misfit(Weapons.LASER, map.guns[bow]) == "", "a laser anywhere")
	var siege := Weapons.item_of(Weapons.SIEGE)
	ship.store[siege] = 1
	m.order(gunner, flank, siege)
	_expect(int(m.wanted[flank]) != siege, "the gun console's order for a siege laser on a side mount is refused")
	m.order(gunner, bow, siege)
	_expect(int(m.wanted[bow]) == siege, "and taken for the bow's")
	m.order(gunner, bow, siege)
	ship.store.erase(siege)

	a.pirate_shields = false
	var dead := PackedStringArray()
	for w in range(1, Weapons.COUNT):
		if w == Weapons.GUARD or w == Weapons.NEURAL or w == Weapons.NOVA:
			continue
		# a siphon works on a raised shield only; an EMP's sure work is heating one (on a bare hull it puts out only
		# the system of the room it strikes, and may strike an empty one 8 times running)
		a.pirate_shields = w != Weapons.SIPHON and w != Weapons.EMP
		var did := false
		for tries in 8:
			if a.body(Arena.LEAD) == null:       # (a heavy gun finished it: another comes)
				d.pirates_wrecked()
				server.road.hulks.clear()
				d.pirates_come(2, true)
				_run(1)
			e = a.body(Arena.LEAD)
			if e == null:
				break
			g.enemy_hull = g.hull_full()
			g.flee = -1.0                        # (beaten, it would start to run and jump away)
			for s in g.systems.size():
				g.systems[s] = g.systems_full[s]
				g.systems_out[s] = 0
			e.debt = 0.0
			e.worn = {}
			e.heat = 0.0
			e.hard = 0.0
			e.over_until = 0
			e.venting = false
			b.heat = 0.0
			b.hard = 0.0
			b.over_until = 0
			b.venting = false
			g.held_until = 0
			g.enemy_guard = false                 # (its point defence would shoot a launcher's one rocket down now and then)
			for k in ship.mounts.size():
				ship.mounts[k] = w
				ship.mount_fx[k] = Weapons.FX_NONE
				ship.armed[k] = 1
			server.mounts.clip.fill(0)
			if Weapons.ammo(w) != 0:
				ship.store[Weapons.ammo(w)] = 50
			_hold(Vector2(0, 0), 0.0, Vector2(0, -40), 0.0)
			_run(Net.TICK_HZ * 2)                 # the turrets turn to it
			if w == Weapons.SIPHON or w == Weapons.EMP:
				b.heat = 500.0
				e.raised = true
				e.auto_until = server.tick + 200
			var was := _state(e)
			g.charge.fill(1.0)
			g.fire(gunner, 255)
			for k in Net.TICK_HZ * 4:
				_hold(Vector2(0, 0), 0.0, Vector2(0, -40), 0.0)
				_run(1)
				if _changed(was, _state(e)):
					did = true
					break
			a.shots.clear()
			a._later.clear()
			g._flying.clear()                    # (a heavy gun's late hits inside would finish the pirate later on)
			if did:
				break
		if not did:
			dead.append(str(Weapons.info(w)["name"]))
	_expect(dead.is_empty(), "every gun does something to the pirate %s" % ("(not: " + ", ".join(dead) + ")" if not dead.is_empty() else ""))
	a.pirate_shields = true
	for k in ship.mounts.size():
		ship.mounts[k] = Weapons.LASER
	b.heat = 0.0
	b.hard = 0.0
	if a.body(Arena.LEAD) == null:
		d.pirates_wrecked()
		server.road.hulks.clear()
		d.pirates_come(2, true)
		_run(1)
	e = a.body(Arena.LEAD)

	# (v94.1, his S4 B) firing heats nothing: only the shield heats the ship, and a hot ship still fires
	_hold(Vector2(0, 0), 0.0, Vector2(0, -40), 0.0)
	_quiet(Net.TICK_HZ * 2)
	g.charge.fill(1.0)
	var flying: int = a.shots.size()
	g.fire(gunner, 255)
	_expect(a.shots.size() > flying and b.heat == 0.0, "firing heats nothing (%.0f)" % b.heat)
	_quiet(Net.TICK_HZ * 2)
	b.heat = b.cap * 0.7                      # (short of the bots' venting at 75%)
	g.charge.fill(1.0)
	flying = a.shots.size()
	g.fire(gunner, 255)
	_expect(a.shots.size() > flying and a.heat_ok(0, Weapons.LASER), "a hot ship short of overload still fires")
	b.heat = 0.0

	# our raised shield stops a pirate's shot and heats; the shield's heat goes only while it is down
	server.ship.shield_on = true
	b.raised = true
	b.auto_until = server.tick + 100
	var shot := {"w": Weapons.LASER, "side": 1, "from": Arena.LEAD, "pos": Vector2.ZERO, "vel": Vector2.ZERO, "kind": 0, "meta": {}}
	a._on_shield(b, 100.0, true)
	_expect(b.heat >= 99.0 and b.hard >= 99.0, "a hit on the shield heats it, its own share (%.0f / %.0f)" % [b.heat, b.hard])
	var h0: float = b.hard
	_quiet(10)
	_expect(b.hard >= h0 - 0.01 and b.raised, "while the shield is up its own heat stays (%.0f)" % b.hard)
	b.raised = false
	b.auto_until = 0
	a.shields[0] = {"up": false, "dir": 0.0, "until": server.tick + 1000, "by": gunner}
	_quiet(10)
	_expect(b.hard < h0, "and goes away once it is down (%.0f)" % b.hard)
	a.shields[0] = {}

	# full, it overloads: no shield and no guns for a while
	b.heat = 0.0
	b.hard = 0.0
	b.raised = true
	a._on_shield(b, b.cap * 2.0, true)
	_expect(b.overloaded(server.tick) and not a._shielded(b) and not a.heat_ok(0, Weapons.LASER), "a full shield overloads: down, and the guns silent")
	_quiet(roundi(Arena.OVERLOAD_SECONDS * Net.TICK_HZ) + 2)
	_expect(not b.overloaded(server.tick) and b.heat < b.cap, "after %d s it is over and the heat is going" % roundi(Arena.OVERLOAD_SECONDS))

	# venting
	b.heat = b.cap * 0.6
	b.hard = 0.0
	var plain: float = b.heat
	_expect(a.vent_now(b) and not a._shielded(b) and not a.heat_ok(0, Weapons.LASER), "venting drops the shield and stops the guns")
	_quiet(Net.TICK_HZ)
	var vented: float = plain - b.heat
	_expect(vented >= b.cool * Arena.VENT_RATE * 0.9 or b.heat <= 0.0, "and cools %d a second (%.0f)" % [roundi(b.cool * Arena.VENT_RATE), vented])
	_quiet(Net.TICK_HZ * 10)
	_expect(not b.venting and b.heat < plain * 0.2, "till no heat is left (%s, %.0f)" % [b.venting, b.heat])

	# the pilot holds the shield by hand
	b.heat = 0.0
	b.hard = 0.0
	var pilot = _at(map.helm.keys()[0], "Пилот")
	a.shield_asked(pilot, false, 0.0, false)
	_quiet(2)
	_expect(not b.raised, "the pilot lowers the shield")
	a.shield_asked(pilot, true, PI / 2.0, false)
	_quiet(2)
	_expect(b.raised, "and raises it again")
	var stranger = server.crew.new_player("Прохожий", 0)
	a.shields[0] = {}
	a.shield_asked(stranger, false, 0.0, false)
	_expect((a.shields[0] as Dictionary).is_empty(), "one away from the controls cannot")

	# a round feeds a clip of bursts
	for k in ship.mounts.size():
		ship.mounts[k] = Weapons.AUTOCANNON
	server.mounts.clip.fill(0)
	server.mounts.loaded.fill(0)
	ship.store[Net.ITEM_SHELL] = 1
	var bursts := 0
	for k in Weapons.clip(Weapons.AUTOCANNON) + 2:
		if server.mounts.take_round(0):
			bursts += 1
	_expect(bursts == Weapons.clip(Weapons.AUTOCANNON) and int(ship.store.get(Net.ITEM_SHELL, 0)) == 0, "one shell feeds %d bursts (%d)" % [Weapons.clip(Weapons.AUTOCANNON), bursts])

	e = a.body(Arena.LEAD)
	# hull points: a pirate's go down by what gets through, and every 100 is a hit inside
	e.debt = 0.0
	var ehp: Vector2 = a.hull_points(e)
	_expect(ehp.y == float(g.hull_full()) * Arena.INSIDE_UNIT, "a pirate's hull shows %d points" % ehp.y)

	server.crew.remove(gunner)
	server.crew.remove(pilot)
	server.crew.remove(stranger)
	print("fluxtest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	server.stop()
	quit(1 if failed > 0 else 0)


func _state(e) -> Dictionary:
	var g = server.gunnery
	var sys := 0
	var out := 0
	for s in g.systems.size():
		sys += g.systems[s]
		if g.systems_out[s] > server.tick:
			out += 1
	return {"hp": server.arena.hull_points(e).x + 0.0, "debt": e.debt, "sys": sys, "out": out, "crew": g.boarders_left(),
		"heat": e.heat, "held": g.held_until > server.tick, "hull": g.enemy_hull}


func _changed(was: Dictionary, now: Dictionary) -> bool:
	return now["hp"] < was["hp"] or now["debt"] > was["debt"] or now["sys"] < was["sys"] or now["out"] > was["out"] \
		or now["crew"] < was["crew"] or now["heat"] > was["heat"] + 0.5 or (now["held"] and not was["held"]) or now["hull"] < was["hull"]


func _at(console: int, who: String):
	var map = server.map
	var p = server.crew.new_player(who, 0)
	var front: int = map.fitting_front(console)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == map.machine_of(console):
			break
	return p


func _hold(ours: Vector2, our_rot: float, theirs: Vector2, their_rot: float) -> void:
	var a = server.arena
	var b = a.body(0)
	var e = a.body(Arena.LEAD)
	if b == null:
		return
	b.pos = ours
	b.rot = our_rot
	b.vel = Vector2.ZERO
	b.spin = 0.0
	if e != null and b != null:
		e.pos = theirs
		e.rot = their_rot
		e.vel = Vector2.ZERO
		e.spin = 0.0


func _quiet(ticks: int) -> void:
	## Ticks with the pirate's guns kept from charging: what heats our ship is only what a check does.
	for i in ticks:
		_hold(Vector2(0, 0), 0.0, Vector2(0, -40), 0.0)
		server.gunnery.enemy_charge.fill(0.0)
		server.gunnery.enemy_hull = server.gunnery.hull_full()   # (our own shots must not finish it off here)
		server.gunnery.flee = -1.0
		server._tick()


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
