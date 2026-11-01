extends SceneTree
## (v92) Checks the fight in real time (Arena) on a real server stepped by hand:
##   godot --headless --path . --script res://tools/arenatest.gd
## A ship's shape from its drawing; a pirate comes out in the fight's space; the pilot's keys move and turn
## the ship; with nobody steering it drifts to a stop; guns bear only inside their arc; our shots fly and
## wear the pirate; its shots fly and hole our hull at the place they strike, or miss, or meet the shield;
## a boarding ship's docking clock waits while it is far; ships that meet push apart; a gun taken by hand
## fires where its gunner aims; our ship out past the edge leaves the fight; the packet reads back.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Arena := preload("res://src/server/arena.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26320, "ship02", 2)
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
	for q in server.players:                  # (the bots stand still: the checks place people themselves)
		if q != null and q.bot:
			q.order = Net.POST_FREE

	# the shape of our ship from its drawing
	var shape = load("res://src/shared/arena_shape.gd").of_fleet(map, 0)
	_expect(shape.w > 20 and shape.h > 8 and shape.outline.size() > 20, "our ship's shape: %dx%d, %d cells round its edge" % [shape.w, shape.h, shape.outline.size()])
	var out_ok: bool = map.guns.size() > 0
	for c: int in map.guns:
		if c >= 0 and not map.on_floor.has(c) and shape.local_of(c).dot(shape.outward(c)) <= 0.0:
			out_ok = false             # ((v101) spare places and the turrets on the floor point nowhere in particular)
	_expect(out_ok, "every gun (%d) points out of the hull" % map.guns.size())

	# a raider comes: the fight's space starts
	_expect(d.pirates_come(2, true), "(a raider comes)")
	_run(1)
	_expect(a.on() and a.body(0) != null and a.body(Arena.LEAD) != null, "the fight goes on in space: our ship and the pirate are bodies")
	var dist: float = a.body(0).pos.distance_to(a.body(Arena.LEAD).pos)
	_expect(dist > 50.0 and dist < 100.0, "it comes out of the dark %.0f cells off" % dist)
	_expect(a.body(0).guns.size() == map.guns.size(), "our guns are its turrets")

	# the pilot steers
	var pilot = _at(map.helm.keys()[0], "Пилот")
	var b = a.body(0)
	var x0: float = b.pos.x
	for i in 40:
		a.pilot_asked(pilot, Arena.KEY_AHEAD)
		_run(1)
	_expect(b.pos.x - x0 > 1.0 and b.vel.x > 1.0, "W pushes the ship ahead (%.1f cells, %.1f a second)" % [b.pos.x - x0, b.vel.x])
	var rot0: float = b.rot
	for i in 40:
		a.pilot_asked(pilot, Arena.KEY_RIGHT)
		_run(1)
	_expect(b.rot - rot0 > 0.2, "D turns it (%.2f rad in 2 s)" % (b.rot - rot0))
	_away(pilot)
	_run(Arena.PILOT_HOLD + 1)
	var v1: float = b.vel.length()
	_run(200)
	_expect(b.vel.length() < v1 * 0.5, "with nobody steering it drifts to a stop (%.1f -> %.1f)" % [v1, b.vel.length()])

	# guns bear only inside their arc
	_hold(Vector2(0, 0), 0.0, Vector2(0, -70), 0.0)
	_run(Net.TICK_HZ * 2)                   # (v94) turrets turn at their own pace
	var up := 0
	var down_bear := 0
	for k in b.guns.size():
		var outv := Vector2.RIGHT.rotated(float(b.guns[k]["out"]))
		if outv.y < -0.5 and b.guns[k]["bears"]:
			up += 1
		if outv.y > 0.5 and b.guns[k]["bears"]:
			down_bear += 1
	_expect(up > 0 and down_bear == 0, "with the pirate above, the guns on the top bear (%d) and those below do not (%d)" % [up, down_bear])

	# our shots fly and wear the pirate
	var gunner = _at(map.gun_console.keys()[0], "Канонир")
	a.pirate_shields = false
	var hull: float = a.hull_points(a.body(Arena.LEAD)).x
	var shots_seen := 0
	for i in 12:
		_hold(Vector2(0, 0), 0.0, Vector2(0, -50), 0.0)
		g.charge.fill(1.0)
		g.fire(gunner, 255)
		shots_seen = maxi(shots_seen, a.shots.size() + a._later.size())
		_run(40)
		if a.hull_points(a.body(Arena.LEAD)).x < hull:
			break
	_expect(shots_seen > 0, "a volley sends shots flying (%d)" % shots_seen)
	_expect(a.hull_points(a.body(Arena.LEAD)).x < hull, "and they strike the pirate (hull %d -> %d)" % [hull, a.hull_points(a.body(Arena.LEAD)).x])
	a.pirate_shields = true

	# its shots fly and strike our hull where they land
	g.enemy_hull = g.hull_full()
	server.ship.shield_on = false
	server.ship.shield = 0.0
	g.enemy_hit_chance = 1.0
	var holes0: int = server.air.holes.size()
	var hull0: int = server.ship.hull
	for i in 10:
		_hold(Vector2(0, 0), 0.0, Vector2(0, -50), PI / 2.0)
		for k in g.enemy_charge.size():
			g.enemy_charge[k] = 1.0
		_run(60)
		if server.air.holes.size() > holes0 or server.ship.hull < hull0 or not server.ship.broken.is_empty():
			break
	_expect(server.air.holes.size() > holes0 or server.ship.hull < hull0 or not server.ship.broken.is_empty(),
		"its aimed shots strike us (holes %d -> %d, hull %d -> %d, out of order %d)" % [holes0, server.air.holes.size(), hull0, server.ship.hull, server.ship.broken.size()])
	var hole_ok := true
	for c: int in server.air.holes.keys():
		if not map.is_other(c) and not map.hull.has(c):
			hole_ok = false
			print("    hole off the hull at %d,%d tile %s" % [c % map.width, c / map.width, map.tile_names[map.cells[c]]])
	_expect(hole_ok, "and every hole of ours is in our hull")
	_mend_all()
	g.enemy_hit_chance = 0.0
	holes0 = server.air.holes.size()
	hull0 = server.ship.hull
	for i in 5:
		_hold(Vector2(0, 0), 0.0, Vector2(0, -50), PI / 2.0)
		for k in g.enemy_charge.size():
			g.enemy_charge[k] = 1.0
		_run(60)
	_expect(server.air.holes.size() == holes0 and server.ship.hull == hull0, "shots aimed off fly past (holes %d, hull %d)" % [server.air.holes.size(), server.ship.hull])

	# the shield's bubble stops what it can
	g.enemy_hit_chance = 1.0
	server.ship.shield_on = true
	server.ship.shield = Weapons.SHIELD_FULL
	var stopped_any := false
	for i in 10:
		_hold(Vector2(0, 0), 0.0, Vector2(0, -50), PI / 2.0)
		server.ship.shield = Weapons.SHIELD_FULL
		var before: float = server.ship.shield
		for k in g.enemy_charge.size():
			g.enemy_charge[k] = 1.0
		_run(60)
		if server.ship.shield < before:
			stopped_any = true
			break
	_expect(stopped_any, "our shield takes its shots on the bubble")
	_mend_all()
	g.enemy_hit_chance = -1.0

	# a gun taken by hand fires where its gunner aims
	var k_top := -1
	for k in b.guns.size():
		if Vector2.RIGHT.rotated(float(b.guns[k]["out"])).y < -0.5:
			k_top = k
	var hand = _at_mount(k_top)
	_expect(hand != null and server.mounts.gunner(k_top) == hand, "a player stands at a gun on the top (%d)" % k_top)
	if hand != null:
		_hold(Vector2(0, 0), 0.0, Vector2(0, -50), 0.0)
		var mark := Vector2(-30.0, -60.0)
		g.charge.fill(1.0)
		var flying: int = a.shots.size()
		var fired: Dictionary = {}
		for i in Net.TICK_HZ * 2:         # (v94) the turret turns to the mark first
			a.turret_asked(hand, k_top, mark, true)
			_run(1)
			for p: Dictionary in a.shots:
				if int(p["side"]) == 0:
					fired = p
			if not fired.is_empty():
				break
		_expect(not fired.is_empty() and a.manned_by_hand(0, k_top), "the trigger fires it (%d in flight)" % (a.shots.size() - flying))
		if not fired.is_empty():
			var muzzle: Vector2 = b.world(b.guns[k_top]["at"])
			var off := absf(wrapf(((fired["vel"] as Vector2) - b.vel).angle() - (mark - muzzle).angle(), -PI, PI))
			_expect(off < 0.1, "towards the gunner's mark (%.3f rad off)" % off)
		_away(hand)

	# ships that meet push apart
	_hold(Vector2(0, 0), 0.0, Vector2(4, 0), 0.0)
	var hull_before: int = server.ship.hull
	a.body(Arena.LEAD).vel = Vector2(-6, 0)
	_run(2)
	var gap: float = a.body(0).pos.distance_to(a.body(Arena.LEAD).pos)
	_run(20)
	_expect(a.body(0).pos.distance_to(a.body(Arena.LEAD).pos) > gap, "ships that meet push apart (%.1f -> %.1f)" % [gap, a.body(0).pos.distance_to(a.body(Arena.LEAD).pos)])
	_expect(server.ship.hull < hull_before, "and the blow hurts (hull %d -> %d)" % [hull_before, server.ship.hull])

	# the packet reads back
	var pkt: PackedByteArray = a.packet()
	var n: int = pkt[6]
	var at := 7                               # (v95: a byte of the fight's state after the tick)
	for i in n:
		var guns: int = pkt[at + 4 + 8 + 6 + 12]
		at += 4 + 8 + 6 + 12 + 1 + guns * 4
	_expect(n == 2 and at == pkt.size(), "S_ARENA holds %d ships and ends where it should (%d / %d)" % [n, at, pkt.size()])

	# our ship out past the edge with the pirate far behind: out of the fight
	_hold(Vector2(Arena.RADIUS + 20.0, 0), 0.0, Vector2(-Arena.RADIUS, 0), 0.0)
	a.body(Arena.LEAD).vel = Vector2.ZERO
	a.body(0).vel = Vector2(3, 0)
	_run(roundi(Arena.LEAVE_SECONDS * Net.TICK_HZ) + 5)
	_expect(not a.on() and not d.here, "past the edge with the pirate far behind, the fight is broken off")

	# a boarding ship's docking clock waits while it is far
	_expect(d.pirates_come(2, false), "(a boarding ship comes)")
	_run(1)
	_hold(Vector2(0, 0), 0.0, Vector2(0, -120), 0.0)
	var dock_at: int = d._pirates_dock_at
	_run(20)
	_expect(d._pirates_dock_at >= dock_at + 19, "far off, its docking clock waits (%d -> %d)" % [dock_at, d._pirates_dock_at])

	print("arenatest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	quit(0 if failed == 0 else 1)


func _hold(ours: Vector2, our_rot: float, theirs: Vector2, their_rot: float) -> void:
	## Puts both ships there, still.
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


func _mend_all() -> void:
	server.arena.shots.clear()                # (nothing left in flight from the last check)
	server.arena._later.clear()
	for c: int in server.air.holes.keys():
		server.air.set_hole(c, false)
	server.ship.broken.clear()
	server.ship.jammed.clear()
	server.ship.hull = server.ship.hull_max


func _at(console: int, who: String):
	var map = server.map
	var p = server.crew.new_player(who, 0)
	var front: int = map.fitting_front(console)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == map.machine_of(console):
			break
	_expect(server.systems.at_console(p, map.helm) or server.systems.at_console(p, map.gun_console), "(%s stands at the console)" % who)
	return p


func _at_mount(k: int):
	var map = server.map
	if k < 0:
		return null
	var cell: int = map.guns[k]
	var p = server.crew.new_player("Стрелок", 0)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		var x: int = cell % map.width - Net.DX[f]
		var y: int = cell / map.width - Net.DY[f]
		if map.walkable(x, y):
			p.st.place(x, y)
			p.st.facing = f
			break
	server.mounts._scan()
	return p


func _away(p) -> void:
	## Takes a player off where he stood (far into the hold) so that he steers or aims nothing.
	var spawn: Vector2i = server.crew.spawn_point()
	p.st.place(spawn.x, spawn.y)
	server.mounts._scan()


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
