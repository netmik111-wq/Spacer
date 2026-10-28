extends SceneTree
## (v93) Checks armour in the fight in space (Arena: the author's plan 0.2) on a real server stepped by hand:
##   godot --headless --path . --script res://tools/armourtest.gd
## Armour lies on the outer wall only and faces out; (v94) it weakens a hit by Starsector's damage / (damage + armour),
## never below 15%, wears by the hit, a worn place lets more through, kinetic is weak and explosive strong against it,
## a slant thickens it; shots met at a slant glance
## off (kinetic more than lasers) and fly on harmless; the pirate's shots held by our armour leave the inside
## whole and the armour worn; ours stays worn after the fight and is mended from outside with a patch; the
## client reads ARENA_ARMOUR. Also (his P1 note) the helm's mouse fires every gun no gunner holds, and (his D3 C)
## the shield turns from a bubble to an arc on one side and round again. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Arena := preload("res://src/server/arena.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")
const ArenaSeen := preload("res://src/client/arena_seen.gd")
const Outside := preload("res://src/server/outside.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26330, "ship02", 2)
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
	for q in server.players:
		if q != null and q.bot:
			q.order = Net.POST_FREE

	# armour lies on the outer wall only, facing out
	var shape = ArenaShape.of_fleet(map, 0)
	var outer := 0
	var inner_armour := 0
	var top := -1
	for y in shape.h:
		for x in shape.w:
			var i: int = shape.index(Vector2i(x, y))
			if shape.armoured(i):
				outer += 1
				if top < 0 and y == 0 and shape.kind[i] == ArenaShape.WALL:
					top = i
			if shape.edge[i] == 0 and shape.armoured(i):
				inner_armour += 1
	_expect(outer > 20 and inner_armour == 0, "armour lies on the outer wall only (%d cells)" % outer)
	var n: Vector2 = shape.normal(Vector2i(top % shape.w, top / shape.w))
	_expect(top >= 0 and n.y < -0.7, "the top wall faces up (%.2f, %.2f)" % [n.x, n.y])

	# a pirate comes; shots at its top wall, by hand
	_expect(d.pirates_come(2, true), "(a raider comes)")
	_run(1)
	var e = a.body(Arena.LEAD)
	_expect(e != null and e.plates >= 50.0, "the raider's wall holds armour (%d)" % (e.plates if e != null else -1))
	e.rot = 0.0
	var spot := -1
	for x in e.shape.w:
		var i: int = e.shape.index(Vector2i(x, 0))
		if e.shape.armoured(i) and e.shape.kind[i] == ArenaShape.WALL and e.shape.normal(Vector2i(x, 0)).y < -0.9:
			spot = i
			break
	_expect(spot >= 0, "(a flat spot on its top wall)")
	var c := Vector2i(spot % e.shape.w, spot / e.shape.w)
	var l: Vector2 = e.shape.middle(c.x, c.y)
	var down: Vector2 = -e.shape.normal(c)       # straight into the wall
	# (v94, Starsector's armour) the armour round the place weakens a hit by damage / (damage + armour), never below 15%
	e.plates = 100.0
	e.worn = {}
	e.debt = 0.0
	var hit := _shot(Weapons.LASER)
	_expect(a._strike(hit, e, l, down) == Net.HELD, "a laser (30) against 100 points of armour is held")
	var laser_did := float(hit["meta"].get("struck", 0.0))
	_expect(laser_did > 6.5 and laser_did < 10.0, "and does about 30 x 30 / 130 to the hull, a little more by a window (%.1f)" % laser_did)
	_expect(absf(float(e.worn.get(spot, 0.0)) - 15.0) < 0.5, "the armour there wears by half the hit, its neighbours the rest (%.1f)" % float(e.worn.get(spot, 0.0)))
	for k in 6:
		a._strike(_shot(Weapons.LASER), e, l, down)
	hit = _shot(Weapons.LASER)
	a._strike(hit, e, l, down)
	_expect(float(hit["meta"].get("struck", 0.0)) > laser_did + 1.0, "on the worn place a laser does more (%.1f)" % float(hit["meta"].get("struck", 0.0)))
	e.worn = {}
	e.debt = 0.0
	hit = _shot(Weapons.RAILGUN)
	_expect(a._strike(hit, e, l, down) == Net.LANDED and int(hit["meta"].get("units", 0)) >= 2, "a railgun (400) gets two hits inside (%d)" % int(hit["meta"].get("units", 0)))
	e.worn = {}
	e.debt = 0.0
	e.plates = 10000.0
	hit = _shot(Weapons.LASER)
	a._strike(hit, e, l, down)
	_expect(absf(float(hit["meta"].get("struck", 0.0)) - 30.0 * Arena.MIN_SHARE) < 0.1, "the thickest armour still lets 15%% through (%.1f)" % float(hit["meta"].get("struck", 0.0)))
	# kinetic is half against armour, explosive double
	e.plates = 100.0
	var kind_hit := {}
	for w: int in [Weapons.AUTOCANNON, Weapons.ROCKET]:
		e.worn = {}
		e.debt = 0.0
		hit = _shot(w)
		a._strike(hit, e, l, down)
		kind_hit[w] = float(hit["meta"].get("struck", 0.0)) / Weapons.space_damage(w)
	_expect(kind_hit[Weapons.ROCKET] > kind_hit[Weapons.AUTOCANNON] * 2.0, "a rocket gets through armour far better than a shell (%.2f vs %.2f of its damage)" % [kind_hit[Weapons.ROCKET], kind_hit[Weapons.AUTOCANNON]])
	# a slant thickens it: a heavy laser head-on and 50 degrees off
	e.worn = {}
	e.debt = 0.0
	hit = _shot(Weapons.HEAVY)
	a._strike(hit, e, l, down)
	var head_on := float(hit["meta"].get("struck", 0.0))
	e.worn = {}
	e.debt = 0.0
	var slant := down.rotated(deg_to_rad(50.0))
	hit = _shot(Weapons.HEAVY)
	a._strike(hit, e, l, slant)
	_expect(float(hit["meta"].get("struck", 0.0)) < head_on * 0.8, "met 50° off, the armour holds more (%.1f vs %.1f head-on)" % [float(hit["meta"].get("struck", 0.0)), head_on])
	e.debt = 0.0
	# glancing off, met 75 degrees off
	var glance := down.rotated(deg_to_rad(75.0))
	var kin := 0
	var las := 0
	for k in 400:
		e.worn = {}
		if a._strike(_shot(Weapons.AUTOCANNON), e, l, glance) == Net.RICOCHET:
			kin += 1
		e.worn = {}
		if a._strike(_shot(Weapons.LASER), e, l, glance) == Net.RICOCHET:
			las += 1
	_expect(kin > 240 and kin < 320, "kinetic shells met 75° off glance off about 70%% of the time (%d of 400)" % kin)
	_expect(las > 80 and las < 160 and las < kin, "lasers less often (%d of 400)" % las)
	e.worn = {}
	var rico := 0
	for k in 100:
		if a._strike(_shot(Weapons.AUTOCANNON), e, l, down) == Net.RICOCHET:
			rico += 1
	_expect(rico == 0, "nothing glances off met head-on")

	# a glancing shot flies on, harmless
	a.shots.clear()
	var p := _shot(Weapons.AUTOCANNON)
	p["pos"] = e.world(l)
	p["vel"] = glance * 55.0
	a._glance(p, e, l, e.world(l))
	_expect(a.shots.size() == 1 and a.shots[0].get("off", -1) == e.id, "a shell that glanced off flies on (never back into that ship)")
	_expect((a.shots[0]["vel"] as Vector2).dot(e.shape.normal(c).rotated(e.rot)) > 0.0, "away from the wall it met")
	_run(Arena.BOUNCE_LIFE * Net.TICK_HZ + 2)
	var still := 0
	for q: Dictionary in a.shots:
		if int(q.get("off", -1)) == e.id:
			still += 1
	_expect(still == 0, "and is gone after a while")

	# a shell that glanced off flies on through the ship it met (it is never struck twice by one shell)
	a.shots.clear()
	var back := _shot(Weapons.AUTOCANNON)
	back["pos"] = e.world(l) - down.rotated(e.rot) * 3.0
	back["vel"] = down.rotated(e.rot) * 20.0
	back["off"] = e.id
	back["ends"] = server.tick + 40
	back["guard"] = false
	back["seen"] = {}
	a.shots.append(back)
	var hits0: int = g.enemy_hull
	_run(4)
	var ours_left := 0
	for q: Dictionary in a.shots:
		if int(q.get("off", -1)) == e.id:
			ours_left += 1                     # (v94: the pirate's own shots fly too, faster than before)
	_expect(ours_left == 1 and g.enemy_hull == hits0, "a glanced shell passes through the ship it glanced off")
	a.shots.clear()

	# (the author's P1 note) one at the helm aims every free gun with the mouse; a gunner's own gun stays his
	var pilot = _at(map.helm.keys()[0], "Пилот")
	var other = server.crew.new_player("Канонир", 0)
	var t: Dictionary = a.turrets[0]
	t.clear()
	t[0] = {"aim": Vector2.ZERO, "fire": false, "until": server.tick + 100, "by": other}
	a.turret_asked(pilot, Net.ALL_GUNS, Vector2(0, -50), true)
	var all_his: bool = map.guns.size() > 1
	for k in range(1, map.guns.size()):
		if (t.get(k, {}) as Dictionary).get("by") != pilot:
			all_his = false
	_expect(all_his and t[0]["by"] == other, "the pilot fires every gun but the one a gunner holds")
	a.turret_asked(pilot, Net.ALL_GUNS, Vector2.ZERO, false)
	_expect(t.size() == 1, "let go, they go back to their bots")
	var stranger = server.crew.new_player("Прохожий", 0)
	a.turret_asked(stranger, Net.ALL_GUNS, Vector2(0, -50), true)
	_expect(t.size() == 1, "one away from the controls fires nothing")
	t.clear()

	# (the author's D3 C) the shield: a bubble, or a stronger arc on one side, turned by hand at the generator
	var ours = a.body(0)
	server.ship.shield_arc = -1
	var r: Vector2 = ours.shape.bubble()
	_expect(a._covers(ours, Vector2(-r.x, 0)) and a._covers(ours, Vector2(r.x, 0)), "a bubble covers all round")
	g.turn_shield(pilot)
	_run(1)
	_expect(server.ship.shield_arc == 0 and a._covers(ours, Vector2(r.x, 0)) and not a._covers(ours, Vector2(-r.x, 0)),
		"E at the generator: an arc on the bow, the stern open")
	g.turn_shield(pilot)
	_run(1)
	_expect(server.ship.shield_arc == 1 and a._covers(ours, Vector2(0, r.y)) and not a._covers(ours, Vector2(0, -r.y)), "then starboard")
	for k in 3:
		g.turn_shield(pilot)
	_expect(server.ship.shield_arc == -1, "and round to the bubble again")
	server.crew.remove(pilot)
	server.crew.remove(other)
	server.crew.remove(stranger)

	# the pirate's shots, held by our armour: the inside stays whole, the armour wears
	var b = a.body(0)
	_expect(b.plates == Arena.ARMOUR_OURS + Arena.ARMOUR_TIER * server.outfit.armour_tier(), "our wall holds %d points" % b.plates)
	b.plates = 5000.0
	a.pane_share = 1.0                         # (a window holds a third: it would let more in)
	for k in g.enemy_weapons.size():
		g.enemy_weapons[k] = Weapons.LASER
	server.ship.shield_on = false
	server.ship.shield = 0.0
	g.enemy_hit_chance = 1.0
	var holes0: int = server.air.holes.size()
	var hull0: int = server.ship.hull
	for i in 2:                                # (v94: 15% always gets through, so not too many shots)
		_hold(Vector2(0, 0), 0.0, Vector2(0, -50), PI / 2.0)
		for k in g.enemy_charge.size():
			g.enemy_charge[k] = 1.0
		_run(60)
	_expect(not server.ship.worn.is_empty(), "the pirate's shots wear our armour (%d places)" % server.ship.worn.size())
	_expect(server.air.holes.size() == holes0 and server.ship.hull == hull0, "and thick armour keeps the inside whole (holes %d -> %d, hull %d -> %d)" % [holes0, server.air.holes.size(), hull0, server.ship.hull])

	# ours stays worn after the fight
	b.plates = Arena.ARMOUR_OURS
	a.pane_share = Arena.PANE_SHARE
	g.enemy_hit_chance = 0.0
	a.shots.clear()
	a._later.clear()
	g.enemy_hull = 0
	_run(5)
	d._leave(true)
	_run(5)
	_expect(not a.on(), "(the fight is over)")
	var worn_left: int = server.ship.worn.size()
	_expect(worn_left > 0, "our armour stays worn after the fight (%d places)" % worn_left)

	# and is mended from outside with a patch, the hull being whole
	server.ship.hull = server.ship.hull_max
	var spots: Dictionary = server.outside._hull_spots()
	_expect(not spots.is_empty(), "the worn places can be reached from outside (%d spots)" % spots.size())
	var w = server.crew.new_player("Сварщик")
	var at: int = spots.keys()[0]
	w.st.place(at % map.width, at / map.width)
	w.st.facing = spots[at]
	w.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	w.slots[0] = Net.ITEM_PATCH
	var cell: int = map.use_ahead(w.st.x, w.st.y, w.st.facing, server.air.holes)
	_expect(server.outside.can_mend(w, cell), "with the hull whole, a worn place can still be mended")
	w.using = true
	_run(Outside.MEND_SECONDS * Net.TICK_HZ + 5)
	w.using = false
	_expect(server.ship.worn.size() < worn_left, "a patch makes the armour there whole (%d -> %d places)" % [worn_left, server.ship.worn.size()])
	_expect(w.count(Net.ITEM_PATCH) == 0, "and is used up")
	server.crew.remove(w)

	# the client reads ARENA_ARMOUR
	var seen := ArenaSeen.new()
	var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_ARMOUR, 2, 2, 0, 0, 1, 3, 0, 0, 3, 3])
	msg.encode_u16(4, 17)
	msg.encode_u16(8, 18)
	seen.shot(msg, 0)
	var got: Dictionary = seen.armour.get(2, {})
	_expect(got.size() == 1 and got.get(17, Vector2i.ZERO) == Vector2i(1, 3), "the client keeps worn places, and forgets whole ones (%s)" % str(got))
	seen.shot(PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_ARMOUR, 2, 255]), 0)
	_expect(not seen.armour.has(2), "all made whole at once")

	print("armourtest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	server.stop()
	quit(1 if failed > 0 else 0)


func _at(console: int, who: String):
	var map = server.map
	var p = server.crew.new_player(who, 0)
	var front: int = map.fitting_front(console)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == map.machine_of(console):
			break
	_expect(server.systems.at_console(p, map.helm), "(%s stands at the helm)" % who)
	return p


func _shot(w: int) -> Dictionary:
	return {"w": w, "side": 0, "meta": {}, "vel": Vector2(0, 1), "pos": Vector2.ZERO, "kind": 0, "from": 0}


func _hold(ours: Vector2, our_rot: float, theirs: Vector2, their_rot: float) -> void:
	var a = server.arena
	var b = a.body(0)
	var e = a.body(Arena.LEAD)
	b.pos = ours
	b.rot = our_rot
	b.vel = Vector2.ZERO
	b.spin = 0.0
	if e != null:
		e.pos = theirs
		e.rot = their_rot
		e.vel = Vector2.ZERO
		e.spin = 0.0


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
