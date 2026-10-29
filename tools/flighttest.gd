extends SceneTree
## (v95) Checks flying round the system in space (the author's note: "people see the ship as in a fight and fly
## to things with WASD round the map"), firing with no enemy near, and the pirates' boarding pods, on a real
## server stepped by hand:
##   godot --headless --path . --script res://tools/flighttest.gd
## Our ship is a body in space out of a fight too, where Ship.pos says; the pilot's keys fly it and the place goes
## back to Ship.pos; fuel burns only while the engines push; the system's edge is a wall; the autopilot flies a
## course and any key takes over; it holds still while somebody is outside; a jump puts it at its arrival; a gun
## fired by hand with no enemy sends a burst off that meets nothing; a fight starts where the ship is and breaking
## off is getting far from every pirate; an ambush comes out of its own place; a boarding pod passes the shield,
## breaches the hull where it strikes and puts boarders in; point defence and our shots break pods; the packet
## carries the fight's state.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Arena := preload("res://src/server/arena.gd")

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
	var map = server.map
	var ship = server.ship
	for q in server.players:                  # (the bots stand still: the checks place people themselves)
		if q != null and q.bot:
			q.order = Net.POST_FREE
	ship.pos = Vector2(100, 100)
	ship.dest = ship.pos
	ship.moving = false
	_run(2)

	# our ship is a body in space out of a fight, where Ship.pos says
	_expect(a.flying() and not a.on() and a.body(0) != null, "out of a fight our ship is a body in space")
	_expect(a.body(0).pos.distance_to(ship.pos * Arena.SCALE) < 0.01, "where Ship.pos says (%s)" % str(a.body(0).pos))
	var pkt: PackedByteArray = a.packet()
	_expect(pkt[5] & Net.ARENA_FIGHT == 0 and pkt[6] == 1, "S_ARENA says no fight and carries our ship alone")

	# the pilot's keys fly it, and the place goes back to Ship.pos; fuel burns while the engines push
	var pilot = _at(map.helm.keys()[0], "Пилот")
	var b = a.body(0)
	var from: Vector2 = ship.pos
	var tank0: float = ship.tank
	for i in 4 * Net.TICK_HZ:
		a.pilot_asked(pilot, Arena.KEY_AHEAD)
		_run(1)
	var went: float = ship.pos.distance_to(from)
	_expect(b.vel.length() > 3.0 and went > 1.0 and ship.moving, "W flies the ship out of a fight (%.1f units, %.1f cells/s)" % [went, b.vel.length()])
	_expect(tank0 - ship.tank > 0.0 and absf((tank0 - ship.tank) - went * Net.FLIGHT_FUEL) < 0.05,
		"and burns fuel by the distance (%.2f for %.1f units)" % [tank0 - ship.tank, went])
	_away(pilot)
	var coast_from: Vector2 = ship.pos
	var tank1: float = ship.tank
	_run(Arena.PILOT_HOLD + 10 * Net.TICK_HZ)
	_expect(ship.pos.distance_to(coast_from) > 0.5 and is_equal_approx(tank1, ship.tank), "let go, it coasts on for free (%.1f units)" % ship.pos.distance_to(coast_from))
	_run(30 * Net.TICK_HZ)
	_expect(b.vel == Vector2.ZERO and not ship.moving, "and its dampers stop it")

	# the system's edge is a wall
	ship.pos = Vector2(Sectors.SPAN - 1.0, 100)
	_run(1)
	b.rot = 0.0
	b.vel = Vector2(6, 0)
	_run(Net.TICK_HZ * 2)
	_expect(ship.pos.x <= Sectors.SPAN and b.pos.x <= Sectors.SPAN * Arena.SCALE, "the system's edge stops it (x %.1f)" % ship.pos.x)

	# the autopilot flies a course, and any key takes over
	ship.pos = Vector2(60, 60)
	_run(1)
	a.course_asked(true, Vector2(80, 60))
	_expect(a.course and ship.moving, "a click on the small map sets the autopilot's course")
	_run(40 * Net.TICK_HZ)
	_expect(not a.course and ship.pos.distance_to(Vector2(80, 60)) < 1.0 and b.vel == Vector2.ZERO,
		"it flies there by itself and stops (%.1f units off)" % ship.pos.distance_to(Vector2(80, 60)))
	a.course_asked(true, Vector2(120, 60))
	_run(Net.TICK_HZ)
	pilot = _at(map.helm.keys()[0], "Пилот 2")
	a.pilot_asked(pilot, Arena.KEY_LEFT)
	_run(1)
	_expect(not a.course, "a key of the pilot takes it off the autopilot")
	a.pilot_asked(pilot, 0)
	_away(pilot)
	_run(30 * Net.TICK_HZ)

	# it holds still while somebody is outside
	var out = server.crew.new_player("Снаружи", 0)
	var space_cell := _space_cell()
	out.st.place(space_cell.x, space_cell.y)
	_expect(server.derelict.someone_outside(), "(somebody is outside)")
	var still_at: Vector2 = ship.pos
	a.course_asked(true, ship.pos + Vector2(30, 0))
	_run(5 * Net.TICK_HZ)
	_expect(ship.pos.distance_to(still_at) < 0.05, "with somebody outside it does not move (%.2f units)" % ship.pos.distance_to(still_at))
	_away(out)
	_run(Net.TICK_HZ)

	# a jump puts the fleet at its arrival, standing still
	var next: int = server.sectors.neighbours(ship.sector)[0]
	server.story.sos_done[Sectors.key(server.sectors.cell[next])] = true
	ship.tank = Net.FUEL_MAX
	server.navigation.start_jump(next, "Проверка")
	_run(Net.JUMP_TICKS + 4)
	_expect(ship.sector == next and b.pos.distance_to(server.sectors.entry[next] * Arena.SCALE) < 0.01 and b.vel == Vector2.ZERO,
		"out of a jump it stands at its place of arrival")

	# a gun fired by hand with no enemy: its burst flies off and meets nothing
	var k := 0
	while k < map.guns.size() and (ship.mounts[k] == Weapons.NONE or ship.armed[k] == 0):
		k += 1
	var hand = _at_mount(k)
	if hand != null:
		server.gunnery.charge.fill(1.0)
		var mark: Vector2 = b.world(b.guns[k]["at"]) + Vector2.RIGHT.rotated(b.rot + float(b.guns[k]["out"])) * 40.0
		var fired := false
		var tank_before: int = int(ship.store.get(Weapons.ammo(ship.mounts[k]), 0))
		for i in Net.TICK_HZ * 2:
			a.turret_asked(hand, k, mark, true)
			_run(1)
			for p: Dictionary in a.shots:
				if p.has("practice"):
					fired = true
			if fired:
				break
		_expect(fired, "with no enemy near, a gun taken by hand fires (%s)" % Weapons.name_of(ship.mounts[k]))
		a.turret_asked(hand, k, mark, false)
		_run(Net.TICK_HZ * 4)
		_expect(a.shots.is_empty() and server.air.holes.is_empty(), "its shots fly off and are gone")
		_expect(Weapons.ammo(ship.mounts[k]) == 0 or int(ship.store.get(Weapons.ammo(ship.mounts[k]), 0)) <= tank_before,
			"a round is spent as in a fight, a laser costs nothing")
		_away(hand)

	# a fight starts where the ship is; breaking off is getting far from every pirate
	var d = server.derelict
	ship.pos = Vector2(100, 100)
	_run(1)
	_expect(d.pirates_come(2, true), "(a raider comes)")
	_run(1)
	_expect(a.on() and b.pos.distance_to(Vector2(400, 400)) < 1.0, "a fight starts where the ship is (%s)" % str(b.pos))
	var e = a.body(Arena.LEAD)
	_expect(e != null and e.pos.distance_to(b.pos) < 100.0, "the pirate comes out of the dark near it (%.0f cells)" % e.pos.distance_to(b.pos))
	pkt = a.packet()
	_expect(pkt[5] & Net.ARENA_FIGHT != 0 and pkt[6] == 2, "S_ARENA says a fight goes on")
	a.hold_pirates = true
	e.pos = b.pos + Vector2(Arena.RADIUS * 0.8, 0)
	_run(roundi(Arena.LEAVE_SECONDS * Net.TICK_HZ) + 5)
	_expect(a.on(), "a pirate within %d cells keeps the fight on" % roundi(Arena.RADIUS))
	e.pos = b.pos + Vector2(Arena.RADIUS + 30.0, 0)
	e.vel = Vector2.ZERO
	_run(roundi(Arena.LEAVE_SECONDS * Net.TICK_HZ) + 5)
	_expect(not a.on() and not d.here and a.flying() and a.body(0) != null, "past %d cells from every pirate the fight is broken off, our ship flies on" % roundi(Arena.RADIUS))
	a.hold_pirates = false

	# an ambush comes out of its own place
	a.come_from = Vector2(500, 300)
	_expect(d.pirates_come(2, true), "(an ambush comes)")
	_run(1)
	e = a.body(Arena.LEAD)
	_expect(e != null and e.pos.distance_to(Vector2(500, 300)) < 2.0, "an ambush's pirate comes out of where it lay")
	server.gunnery.enemy_hull = 0
	d.pirates_wrecked()
	_run(2)

	# a boarding pod passes the shield, breaches the hull where it strikes and puts boarders in
	_expect(d.pirates_come(2, false), "(a boarding ship comes)")
	_run(1)
	var g = server.gunnery
	if g.boarders_left() < Arena.POD_PARTY + Arena.POD_KEEP:   # (a crew that can spare a pod's party and keep POD_KEEP at home)
		g.systems[Net.ESYS_CREW] = (Arena.POD_PARTY + Arena.POD_KEEP) * g.HITS_PER_BOARDER
		d._pirates_party = g.boarders_left()
	g.pods = true
	a.hold_pirates = true
	e = a.body(Arena.LEAD)
	e.pos = b.pos + Vector2(0, -90)
	e.vel = Vector2.ZERO
	ship.guard_armed = false
	ship.shield_on = true
	var holes0: int = server.air.holes.size()
	var aboard0: int = server.pirates.aboard()
	var crew0: int = server.gunnery.boarders_left()
	_expect(a.launch_pod(0, false), "a boarding ship sends a pod")
	_run(Net.TICK_HZ * 10)
	_expect(a.pods_flying() == 0 and server.air.holes.size() > holes0, "it strikes our hull and breaches it (holes %d -> %d)" % [holes0, server.air.holes.size()])
	_expect(server.pirates.aboard() == aboard0 + Arena.POD_PARTY and server.gunnery.boarders_left() == crew0 - Arena.POD_PARTY,
		"and its people come in (%d aboard, %d left on their ship)" % [server.pirates.aboard(), server.gunnery.boarders_left()])

	# point defence breaks a pod; so do our shots
	for p in server.players:
		if p != null and p.pirate:
			p.health = Net.HEALTH_DEAD
			p.corpse = true
	ship.guard = Weapons.GUARD
	ship.guard_armed = true
	var down := 0
	var tries := 0
	for i in 12:
		server.gunnery.guard_charge = 1.0
		var holes_before: int = server.air.holes.size()
		if not a.launch_pod(0, false):
			continue
		tries += 1
		for t in Net.TICK_HZ * 9:                 # (the pirate's own guns held, so every new hole is the pod's)
			server.gunnery.enemy_charge.fill(0.0)
			_run(1)
		down += 1 if server.air.holes.size() == holes_before else 0
		for c: int in server.air.holes.keys():
			server.air.set_hole(c, false)
		for p in server.players:
			if p != null and p.pirate and not p.corpse:
				p.health = Net.HEALTH_DEAD
				p.corpse = true
	_expect(tries > 0 and down > 0 and down < tries, "point defence shoots some pods down (%d of %d; armed %s, powered %s, charge %.1f)" % [
		down, tries, ship.guard_armed, server.powered(), server.gunnery.guard_charge])
	ship.guard = Weapons.NONE
	var pod: Dictionary = {}
	a.launch_pod(0, false)
	for p: Dictionary in a.shots:
		if p.has("pod"):
			pod = p
	var shot := {"id": 9999, "side": 0, "from": 0, "pos": (pod["pos"] as Vector2) + Vector2(0, 3), "vel": Vector2(0, -40),
		"ends": server.tick + 20, "w": Weapons.LASER, "kind": Net.SHOT_CANNON, "meta": {"log": {"gun": 0, "w": Weapons.LASER, "fx": 0, "left": 1,
		"misses": 0, "stopped": 0, "down": 0, "ricochet": 0, "hits": PackedStringArray(), "said": PackedStringArray(), "focus": false, "ship": 0},
		"pierce": 0.0, "ship": 0, "foe": 0}, "seen": {}, "guard": false, "d": 30.0, "type": 0}
	a.shots.append(shot)
	a.shots.append(shot.duplicate(true))
	(a.shots[-1] as Dictionary)["id"] = 9998
	_run(2)
	_expect(int(pod.get("hp", 1)) <= 0 and not a.shots.has(pod), "two shots of ours break a pod")

	print("flighttest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	quit(0 if failed == 0 else 1)


func _space_cell() -> Vector2i:
	## A cell of open space just off our hull, where one in a suit stands outside.
	var map = server.map
	for c: int in map.hull:
		var x: int = c % map.width
		var y: int = c / map.width
		for dv: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n := Vector2i(x, y) + dv
			if map.is_space(n.x, n.y) and not map.is_other(n.y * map.width + n.x):
				return n
	return Vector2i(-1, -1)


func _at(console: int, who: String):
	var map = server.map
	var p = server.crew.new_player(who, 0)
	var front: int = map.fitting_front(console)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == map.machine_of(console):
			break
	_expect(server.systems.at_console(p, map.helm), "(%s stands at the controls)" % who)
	return p


func _at_mount(k: int):
	var map = server.map
	if k < 0 or k >= map.guns.size():
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
