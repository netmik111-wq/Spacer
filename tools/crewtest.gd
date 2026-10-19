extends SceneTree
## Checks the crew and the campaign on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/crewtest.gd
## The crew reserve: coming back after death takes somebody from it, an empty
## one sends nobody, a trader hires more. The hull wears with every hole and
## hit and is patched at a station; at nothing, or with the whole crew dead and
## nobody in reserve, the campaign is over and the ship goes nowhere.
## Jobs: a shut door of a restricted room opens only for those whose job gives
## access to it, its lock can be broken in a while, and without power it is an
## ordinary door. A job's own skill grows quickly, the others slowly, and a
## skilled hand mends quicker.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Doors := preload("res://src/shared/doors.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer
var last_said := ""


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26191, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	var p := server.crew.new_player("Капитан")
	p.take_job(Net.JOB_CAPTAIN)
	var q := server.crew.new_player("Матрос")
	q.take_job(Net.JOB_CREWMAN)

	print("spawn points")
	var spots_ok := true
	for spot: Vector2i in map.spawns:
		spots_ok = spots_ok and not _restricted_rooms().has(spot.y * map.width + spot.x)
	_expect(spots_ok, "nobody comes aboard inside a restricted room")
	# (2026-10-19) a boarder waiting at a spawn tile: those coming back wake elsewhere
	var watched: Vector2i = map.spawns[0]
	var guard = server.pirates.spawn(watched.x, watched.y + 1 if map.walkable(watched.x, watched.y + 1) else watched.y - 1, false)
	var room0: int = map.room_of[watched.y * map.width + watched.x]
	var safe_tile := false
	for s in map.spawns:
		safe_tile = safe_tile or server.crew._danger_at(s) <= 0.0
	var away := true
	for i in 30:
		var at := server.crew.spawn_point()
		away = away and (not safe_tile or server.crew._danger_at(at) <= 0.0)
	_expect(away, "nobody comes back at a spawn tile a boarder is waiting at (%s)" % ("there is a safe one" if safe_tile else "none is safe"))
	server.crew.remove(guard)

	print("the crew reserve")
	_expect(server.reserve == Net.START_RESERVE, "the ship sets out with %d in reserve" % Net.START_RESERVE)
	q.health = -150.0
	_run(2)
	_expect(q.cond == Net.COND_DEAD, "(the sailor is dead)")
	server.crew.respawn_from_reserve(q)
	_expect(q.cond == Net.COND_OK and server.reserve == Net.START_RESERVE - 1, "coming back takes one from the reserve")
	_expect(q.job == Net.JOB_CREWMAN and q.st.access == Net.access_of(Net.JOB_CREWMAN), "in the same job")
	var empty := true
	for item in q.slots:
		empty = empty and item == Net.ITEM_NONE
	_expect(empty and q.has_suit(), "dressed, but with nothing in the hands or pockets")
	server.reserve = 0
	q.health = -150.0
	_run(2)
	server.crew.respawn_from_reserve(q)
	_expect(q.cond == Net.COND_DEAD, "with nobody in reserve nobody comes back")
	_expect(server.over == Net.OVER_NONE, "while somebody is alive the campaign goes on")
	_face(p, map.locker.keys()[0])
	server.ship.credits = Net.PRICE_CREW * 2
	server.supplies.store_asked(p, Net.STORE_HIRE, 0)
	_expect(server.reserve == 0, "nobody can be hired with no trader alongside")
	var here := server.ship.sector
	server.sectors.kind[here] = Sectors.TRADER
	server.sectors.spot[here] = server.ship.pos
	server.sectors.reach[here] = Sectors.DOCK_RANGE
	_run(2)
	server.supplies.store_asked(p, Net.STORE_HIRE, 0)
	_expect(server.reserve == 1 and server.ship.credits == Net.PRICE_CREW, "a trader hires one for %d credits" % Net.PRICE_CREW)
	server.crew.respawn_from_reserve(q)
	_expect(q.cond == Net.COND_OK and server.reserve == 0, "and the dead one comes back")

	print("things on walls")
	var reach_ok := true
	var from_behind := 0
	for cell: int in map.intercom.keys() + map.chart.keys() + map.locker.keys():
		var front := map.fitting_front(cell)
		var fx := front % map.width
		var fy := front / map.width
		var up := Net.DIR_UP if front > cell else Net.DIR_DOWN
		reach_ok = reach_ok and map.use_ahead(fx, fy, up) == cell
		for side in [-1, 1]:
			if map.walkable(fx + side, fy) and not map.walkable(cell % map.width + side, cell / map.width):
				# (between two fittings either may answer)
				reach_ok = reach_ok and map.fitting_front(map.use_ahead(fx + side, fy, up)) >= 0
		var back := cell - (front - cell)
		if map.walkable(back % map.width, back / map.width):
			from_behind += 1
			reach_ok = reach_ok and map.use_ahead(back % map.width, back / map.width, Net.DIR_DOWN if up == Net.DIR_UP else Net.DIR_UP) < 0
	_expect(reach_ok and from_behind > 0, "a thing on a wall is used from its room, from in front or a cell aside, not through the wall")

	print("the hull")
	_expect(server.ship.hull == Net.HULL_MAX, "the hull starts whole")
	var cell: int = map.hull[0]
	server.systems.breach(cell)
	_expect(server.ship.hull == Net.HULL_MAX - Net.HULL_PER_HOLE, "a hole costs %d of it" % Net.HULL_PER_HOLE)
	server.air.set_hole(cell, false)
	server.air.refill()
	server.ship.credits = Net.PRICE_HULL
	server.supplies.store_asked(p, Net.STORE_BUY_HULL, 0)
	_expect(server.ship.hull == Net.HULL_MAX - Net.HULL_PER_HOLE + Net.HULL_LOT or server.ship.hull == Net.HULL_MAX, "a trader patches it for credits")
	server.sectors.kind[here] = Sectors.EMPTY
	_run(2)

	print("jobs and doors")
	var bridge := _door_needing(Net.ACCESS_BRIDGE)
	_expect(bridge >= 0, "the bridge has a restricted door")
	var outside := _outside(bridge)
	var through := _walk_through(q, bridge, outside, 60)
	_expect(not through, "a sailor does not get onto the bridge")
	through = _walk_through(p, bridge, outside, 60)
	_expect(through, "the captain does")
	p.st.place(outside.x, outside.y)
	_run(Doors.HOLD_TICKS + 20)
	_expect(server.doors.is_shut(bridge), "(the door has shut)")
	# breaking the lock
	_face_door(q, bridge, outside)
	q.using = true
	_run(Net.HACK_TICKS / 2)
	_expect(server.doors.is_shut(bridge), "the lock holds for a while")
	_run(Net.HACK_TICKS / 2 + 5)
	_expect(not server.doors.is_shut(bridge), "and then gives way")
	q.using = false
	q.st.place(outside.x, outside.y)
	q.st.dir = Net.DIR_NONE
	_run(Doors.HOLD_TICKS * 2 + 20)
	_expect(server.doors.is_shut(bridge), "(the door has shut)")
	server.director.fire(server.director.ENGINE_FAULT)
	server.power.set_charge(0.0)             # (v61) and the SMES empty: the ship dark
	_run(2)
	_expect(not server.powered(), "(no power)")
	_expect(_walk_through(q, bridge, outside, 80), "without power its lock does not work: it is pushed open by hand")
	server.ship.broken.clear()
	server.systems.power_changed()
	q.st.place(outside.x, outside.y)
	_run(Doors.HOLD_TICKS * 2 + 20)

	print("skills")
	var e := server.crew.new_player("Инженер")
	e.take_job(Net.JOB_ENGINEER)
	_expect(e.skills[Net.SKILL_REPAIR] == Net.JOB_START_SKILL and e.skills[Net.SKILL_MEDICINE] == 0, "an engineer starts knowing repairs, nothing of medicine")
	_expect(e.st.access & Net.ACCESS_ENGINE != 0 and e.st.access & Net.ACCESS_BRIDGE == 0, "with access to the engine room, not the bridge")
	var r0 := e.skills[Net.SKILL_REPAIR]
	var m0 := e.skills[Net.SKILL_MEDICINE]
	for i in 6:
		e.train(Net.SKILL_REPAIR)
		e.train(Net.SKILL_MEDICINE)
	_expect(e.skills[Net.SKILL_REPAIR] == r0 + 6 * Net.SKILL_GAIN, "their own skill grows with every job done")
	_expect(e.skills[Net.SKILL_MEDICINE] > m0 and e.skills[Net.SKILL_MEDICINE] < e.skills[Net.SKILL_REPAIR] - r0, "another one slowly")
	var slow := _mend_time(q)
	var quick := _mend_time(e)
	_expect(quick < slow, "a skilled hand mends quicker (%.1f s against %.1f s)" % [quick / float(Net.TICK_HZ), slow / float(Net.TICK_HZ)])

	print("speech")
	server.keep_heard = true
	server.air.refill()
	p.st.place(13, 14)                   # by the intercom of the upper corridor
	q.st.place(17, 14)
	e.st.place(23, map.deck_stride + 14) # by one on the lower deck
	for who in [p, q, e]:
		who.st.dir = Net.DIR_NONE
		who.said.clear()
	p.slots.fill(Net.ITEM_NONE)
	e.slots.fill(Net.ITEM_NONE)
	q.slots.fill(Net.ITEM_NONE)
	p.add(Net.ITEM_RADIO)
	e.add(Net.ITEM_RADIO)
	_say(p, "слышно?")
	_expect(_heard(q) == Net.CHAT_NEAR and _heard(e) < 0, "said aloud, it is heard close by, not on the other deck")
	_say(p, "; на связи")
	_expect(_heard(e) == Net.CHAT_RADIO and _heard(q) < 0, "by radio, whoever has one hears it, anywhere; who has none does not")
	_expect(last_said == "на связи", "(without the mark)")
	_say(q, "; а я?")
	_expect(_heard(p) < 0 and _heard(e) < 0, "without a radio one cannot speak by radio")
	_say(p, "! всем внимание")
	_expect(_heard(e) == Net.CHAT_INTERCOM and _heard(q) == Net.CHAT_INTERCOM, "into an intercom: heard by every panel")
	_say(q, "! а я далеко")
	_expect(_heard(e) < 0, "only right by a panel")
	server.ship.broken[map.engine.keys()[0]] = true
	server.power.set_charge(0.0)
	server.systems.power_changed()
	_say(p, "! без питания")
	_expect(_heard(e) < 0, "and only with power")
	server.ship.broken.clear()
	server.systems.power_changed()
	server.air.air[q.st.y * map.width + q.st.x] = 0.0
	_say(p, "а в вакууме?")
	_expect(_heard(q) < 0, "a vacuum carries no voice")
	q.st.place(14, 14)
	_say(p, "шлем к шлему")
	_expect(_heard(q) == Net.CHAT_NEAR, "except helmet to helmet")
	server.air.refill()
	q.health = -10.0
	_run(2)
	_say(q, "помогите")
	_expect(_heard(p) < 0, "one lying unconscious says nothing")
	q.health = -150.0
	_run(2)
	_say(q, "я умер")
	_expect(_heard(p) < 0, "the dead are not heard by the living")
	var r := server.crew.new_player("Ещё")
	r.health = -150.0
	_run(2)
	r.said.clear()
	_say(q, "есть кто?")
	_expect(_heard(r) == Net.CHAT_DEAD, "but by the dead")
	server.keep_heard = false

	print("the end of the campaign")
	server.reserve = 0
	for who in [p, q, e]:
		who.health = -150.0
	server.crew.new_player("Бот").bot = true
	_run(Net.TICK_HZ + 2)
	_expect(server.over == Net.OVER_CREW_LOST, "the whole crew dead and nobody in reserve: the campaign is over")
	server.crew.respawn_from_reserve(q)
	_expect(q.cond == Net.COND_DEAD, "nobody comes back after it")
	_face(p, map.chart.keys()[0])
	server.navigation.jump_asked(p, server.sectors.neighbours(server.ship.sector)[0])
	_expect(server.ship.jump_to == Net.NO_SECTOR, "and the ship jumps nowhere")
	_expect(GameServer.Crew.voyage_text(Net.TICK_HZ * 60 * 75) == "1 ч 15 мин", "the summary tells how long it held out")

	print("a hull worn through")
	server.over = Net.OVER_NONE
	server.ship.hull = Net.HULL_PER_HOLE
	var other: int = map.hull[map.hull.size() / 2]
	server.systems.breach(other)
	_expect(server.ship.hull == 0 and server.over == Net.OVER_WRECKED, "the hull worn to nothing ends the campaign")

	print("CREWTEST %s" % ("ok" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _restricted_rooms() -> Dictionary:
	## The floor cells of every restricted room: of the two sides of a restricted
	## door, the room is the smaller.
	var map := server.map
	var out := {}
	for d in map.doors.size():
		if map.door_access[d] != 0:
			var a := _room(map.door_sides[d * 2])
			var b := _room(map.door_sides[d * 2 + 1])
			out.merge(a if a.size() < b.size() else b)
	return out


func _room(cell: int) -> Dictionary:
	## The floor cells reachable from one without going through a door.
	var map := server.map
	var seen := {cell: true}
	var todo := [cell]
	while not todo.is_empty():
		var c: int = todo.pop_back()
		var x := c % map.width
		var y := c / map.width
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			var n := ny * map.width + nx
			if seen.has(n) or not map.walkable(nx, ny):
				continue
			if map.door_of[n] >= 0:
				continue
			seen[n] = true
			todo.append(n)
	return seen


func _door_needing(bit: int) -> int:
	for d in server.map.doors.size():
		if server.map.door_access[d] & bit != 0:
			return d
	return -1


func _outside(door: int) -> Vector2i:
	## The cell next to a restricted door on the side that needs no access.
	var map := server.map
	for side in 2:
		var c := map.door_sides[door * 2 + side]
		if c >= 0 and not _restricted_rooms().has(c):
			return Vector2i(c % map.width, c / map.width)
	return Vector2i(-1, -1)


func _towards(from: Vector2i, door: int) -> int:
	var at: Vector2i = server.map.doors[door]
	if at.x != from.x:
		return Net.DIR_RIGHT if at.x > from.x else Net.DIR_LEFT
	return Net.DIR_DOWN if at.y > from.y else Net.DIR_UP


func _walk_through(who: RefCounted, door: int, from: Vector2i, ticks: int) -> bool:
	## Walks somebody from a cell into a door for a while; true if they got past it.
	who.st.place(from.x, from.y)
	who.st.dir = _towards(from, door)
	var at: Vector2i = server.map.doors[door]
	var past := false
	for i in ticks:
		server._tick()
		if who.st.x != from.x and who.st.x != at.x or who.st.y != from.y and who.st.y != at.y:
			past = true
			break
	who.st.dir = Net.DIR_NONE
	return past


func _face_door(who: RefCounted, door: int, from: Vector2i) -> void:
	who.st.place(from.x, from.y)
	who.st.dir = Net.DIR_NONE
	who.st.facing = _towards(from, door)


func _mend_time(who: RefCounted) -> int:
	## How long somebody with a spare part takes to mend the broken engine.
	var engine: int = server.map.engine.keys()[0]
	server.ship.broken[engine] = true
	server.systems.power_changed()
	who.slots.fill(Net.ITEM_NONE)
	who.add(Net.ITEM_PART)
	who.add(Net.ITEM_PART)
	_face(who, engine)
	who.using = true
	var n := 0
	while server.ship.broken.has(engine) and n < 2000:
		server._tick()
		n += 1
	who.using = false
	return n


func _face(p: RefCounted, wall_cell: int) -> void:
	## Puts the character in front of a thing on a wall, looking at it.
	var map := server.map
	var x := wall_cell % map.width
	var y := wall_cell / map.width
	if map.walkable(x, y + 1):
		p.st.place(x, y + 1)
		p.st.facing = Net.DIR_UP
	elif map.walkable(x, y - 1):
		p.st.place(x, y - 1)
		p.st.facing = Net.DIR_DOWN
	elif map.walkable(x + 1, y):
		p.st.place(x + 1, y)
		p.st.facing = Net.DIR_LEFT
	else:
		p.st.place(x - 1, y)
		p.st.facing = Net.DIR_RIGHT
	p.st.dir = Net.DIR_NONE


func _say(who: RefCounted, text: String) -> void:
	who.chat_times.clear()               # (not the flood guard being tried here)
	server.chat.talk(who, text)


func _heard(who: RefCounted) -> int:
	## The channel of the last thing this one heard (and forgets it), or -1.
	if who.said.is_empty():
		return -1
	var ch: int = who.said[-1][0]
	last_said = who.said[-1][2]
	who.said.clear()
	return ch


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
