extends SceneTree
## Checks the road of clusters (v64), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/roadtest.gd
## Places inside a system (hidden until the sensors find them; debris, a
## container, bodies, a battlefield taken by flying onto them; an abandoned
## ship alongside; an ambush seen from afar that comes out when we come close),
## the pirate hunters (coming into the cluster far from us, walking the lanes
## toward us, never into a station's system, unseen from inside a nebula, a
## fight when they find us, following on when we jump away), the long jump's
## rules, the chart's packet, side quests lost with a cluster left behind, and
## that it all survives a save (and an old save starts a fresh first cluster).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Road := preload("res://src/server/road.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = _new_server(26500)
	if server == null:
		quit(1)
		return
	_places()
	_hunters()
	_long_jump()
	_packet()
	_left_behind()
	_saved()
	server.stop()
	server.free()
	print("roadtest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _new_server(port: int) -> GameServer:
	var s := GameServer.new()
	get_root().add_child(s)
	var problem := s.start(port, "ship02", 1)
	if problem != "":
		print(problem)
		return null
	s.director.auto = false
	s.story.auto = false
	s.road.auto = false
	s.road.breather = 0.0          # (v69) the next hunter waits after a fight: fixtest checks that
	s.gunnery.flies = false
	s.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	return s


func _run(ticks: int) -> void:
	for t in ticks:
		server.ship.hull = server.ship.hull_max
		server._tick()


func _calm() -> void:
	if server.derelict.here:
		server.derelict._leave(true)
	server.gunnery.enemy_gone()
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	server.road._fight = {}
	server.road.hunters = []
	server.road.hulks = {}                   # (v69) wrecks left on the chart: not wanted in these checks
	_run(2)


func _arrive_at(cell: Vector2i) -> void:
	## The ship is in that system of the cluster now, as if it had jumped there.
	server.been[Sectors.key(cell)] = true
	server.road.build(cell)
	server.ship.sector = server.sectors.here
	server.sectors.visited[server.ship.sector] = 1
	_put(server.sectors.entry[server.ship.sector])
	server.story.entered_sector()
	_run(1)


func _enter_cluster(depth: int) -> void:
	server.road.depth = depth
	server.road.entry = Vector2i(6 * depth, 0)
	server.road.hunters = []
	_arrive_at(server.road.entry)


func _put(at: Vector2) -> void:
	server.ship.pos = at
	server.ship.dest = at
	server.ship.moving = false


func _find_place(kind: int) -> Array:
	## [depth, cell, place index] of a system holding a place of that kind (not in the flagship's cluster).
	for depth in 16:
		if depth == Sectors.FLAG_DEPTH:
			continue
		var s := Sectors.new()
		var at := Vector2i(6 * depth, 0)
		s.build(server.space_seed, at, {}, depth, at)
		for i in s.count:
			if kind == Sectors.P_AMBUSH and s.kind[i] == Sectors.DERELICT:
				continue                         # (a wreck alongside keeps pirates off until it goes)
			var p := s.places(server.space_seed, i)
			for k in p.size():
				if int(p[k][0]) == kind:
					return [depth, s.cell[i], k]
	return []


func _place_at(k: int) -> Vector2:
	return server.road._here_places[k][1]


func _off(from: Vector2, d: float) -> Vector2:
	## A point `d` from `from`, toward the middle of the system.
	var mid := Vector2(Sectors.SPAN, Sectors.SPAN) / 2.0
	var dir := (mid - from).normalized() if from.distance_to(mid) > 1.0 else Vector2.RIGHT
	return from + dir * d


func _locker() -> int:
	## What the ship has: in the locker, and (v67) floating outside by the airlock, to be fetched.
	var n := 0
	for item in server.ship.store:
		n += int(server.ship.store[item])
	for c: int in server.salvage.floating():
		n += Net.FLOOR_STACK - (server.floor_things[c] as PackedByteArray).count(Net.ITEM_NONE)
	return n


func _scrap_out() -> int:
	var n := 0
	for c: int in server.salvage.floating():
		n += (server.floor_things[c] as PackedByteArray).count(Net.ITEM_SCRAP)
	return n


# --------------------------------------------------------------- places

func _places() -> void:
	print("  -- places inside a system")
	var r: Road = server.road
	for kind: int in [Sectors.P_DEBRIS, Sectors.P_CONTAINER, Sectors.P_BODIES, Sectors.P_BATTLEFIELD]:
		var f := _find_place(kind)
		_expect(not f.is_empty(), "")
		if f.is_empty():
			print("  FAIL  no %s anywhere" % Sectors.PLACE_NAMES[kind])
			continue
		_calm()
		_enter_cluster(f[0])
		_arrive_at(f[1])
		var k: int = f[2]
		var where := _place_at(k)
		var key := r._key(k)
		r.found.erase(key)
		r.taken.erase(key)
		_put(_off(where, r.scan_range() + 6.0))
		_run(1)
		var hidden := not r.found.has(key)
		_put(_off(where, r.scan_range() - 3.0))
		_run(1)
		_expect(hidden and r.found.has(key) and not r.taken.has(key),
			"%s: hidden until the sensors come within %.0f, then marked" % [Sectors.PLACE_NAMES[kind], r.scan_range()])
		var scrap := _scrap_out()
		var things := _locker()
		var hull := server.ship.hull
		var reserve := server.reserve
		_put(where)
		server.ship.hull = server.ship.hull_max
		r.tick()                                 # (by hand: _run would mend the hull a mine broke)
		_expect(r.taken.has(key), "flown onto, it is taken")
		match kind:
			Sectors.P_DEBRIS:
				_expect(_scrap_out() >= scrap + 2, "(v67) debris: scrap floating outside by the airlock")
			Sectors.P_CONTAINER:
				_expect(_locker() > things or server.ship.hull < server.ship.hull_max, "a container: things in the locker, or a mine went off")
			Sectors.P_BODIES:
				_expect(_locker() > things and server.reserve >= reserve, "bodies: something from their pockets (reserve %d -> %d)" % [reserve, server.reserve])
			Sectors.P_BATTLEFIELD:
				_expect(_locker() >= things + 3, "a battlefield: parts, pockets and gun parts")
		var again := _locker()
		_put(_off(where, 10.0))
		_run(2)
		_put(where)
		_run(2)
		_expect(_locker() == again, "taken once only")
		_run(1)
		server.ship.hull = hull
	# a mine
	var f := _find_place(Sectors.P_CONTAINER)
	if not f.is_empty():
		_calm()
		_enter_cluster(f[0])
		_arrive_at(f[1])
		var mined := false
		for tries in 40:
			r.taken.erase(r._key(f[2]))
			server.ship.hull = server.ship.hull_max
			_put(_place_at(f[2]))
			r.tick()
			if server.ship.hull < server.ship.hull_max:
				mined = true
				break
			_put(_off(_place_at(f[2]), 20.0))
			r.tick()
		_expect(mined, "now and then a container is a pirate mine")
	# the abandoned ship
	f = _find_place(Sectors.P_WRECK)
	_expect(not f.is_empty(), "an abandoned ship is somewhere")
	if not f.is_empty():
		_calm()
		_enter_cluster(f[0])
		_arrive_at(f[1])
		_expect(not server.derelict.here, "far from the abandoned ship, nothing is alongside")
		_put(_place_at(f[2]))
		_run(Net.TICK_HZ * 2)
		_expect(server.derelict.here, "close to it, it comes alongside")
		_calm()
	# the ambush
	f = _find_place(Sectors.P_AMBUSH)
	_expect(not f.is_empty(), "an ambush is somewhere")
	if not f.is_empty():
		_calm()
		_enter_cluster(f[0])
		_arrive_at(f[1])
		var key := r._key(f[2])
		_expect(r.found.has(key) and not server.gunnery.fighting(), "an ambush is seen from afar (%.0f away), and waits" % server.ship.pos.distance_to(_place_at(f[2])))
		_put(_off(_place_at(f[2]), Sectors.AMBUSH_REACH - 2.0))
		_run(Net.TICK_HZ * 3)
		_expect(server.derelict.here and server.gunnery.fighting(), "flown close, its pirate ship comes out (here %s, fighting %s, taken %s, kind %d, outside %s, can %s)"
			% [server.derelict.here, server.gunnery.fighting(), r.taken.has(key), server.sectors.kind[server.ship.sector],
			server.derelict.someone_outside(), server.derelict.pirates_can_come()])
		_calm()
	_enter_cluster(0)


# --------------------------------------------------------------- hunters

func _hunters() -> void:
	print("  -- hunters")
	var r: Road = server.road
	var s: Sectors = server.sectors
	_calm()
	_enter_cluster(0)
	var kinds_were := s.kind.duplicate()
	var fog_were := s.fog.duplicate()
	s.fog.fill(0)                                # (inside a nebula it would wander)
	for i in s.count:                            # (a station on the only way would hold it back)
		if s.kind[i] == Sectors.STATION:
			s.kind[i] = Sectors.EMPTY
	_expect(r.spawn_hunter(), "a hunter comes into the cluster")
	var h: Dictionary = r.hunters[0]
	var d := s.distances(server.ship.sector)
	var far := 0
	for i in s.count:
		if s.kind[i] != Sectors.STATION:
			far = maxi(far, d[i])
	_expect(d[int(h["at"])] == far and s.kind[int(h["at"])] != Sectors.STATION, "as far from us as it can, not at a station (%d jumps)" % far)
	var steps := 0
	var closer := true
	while int(h["at"]) != server.ship.sector and steps < 20:
		var was: int = d[int(h["at"])]
		h["move"] = roundi(Road.HUNTER_STEP * Net.TICK_HZ) - Net.TICK_HZ
		_run(Net.TICK_HZ + 1)
		steps += 1
		closer = closer and d[int(h["at"])] <= was
	_expect(closer and int(h["at"]) == server.ship.sector, "it walks the lanes to us (%d steps)" % steps)
	_expect(int(h["coming"]) > server.tick, "it is seen coming into our system")
	_run(roundi(Road.HUNTER_WARN * Net.TICK_HZ) + Net.TICK_HZ * 2)
	_expect(server.gunnery.fighting() and server.derelict.ship.name.begins_with("Охотник"),
		"then it comes out: a fight (%s)" % (server.derelict.ship.name if server.derelict.ship != null else "-"))
	_expect(r.hunters.is_empty() and not r._fight.is_empty(), "it is the hunter we fight")
	# we jump away from it: it follows on
	var fought_at: int = server.ship.sector
	server.derelict._leave(true)
	server.gunnery.enemy_gone()
	_arrive_at(s.cell[s.neighbours(fought_at)[0]])
	_run(2)
	_expect(r.hunters.size() == 1 and int(r.hunters[0]["at"]) == fought_at, "jumped away from, it stays on our trail")
	# (2026-10-19, the author's pick) each escape makes it slower to catch up
	var slow: Dictionary = r.hunters[0]
	s.kind[server.ship.sector] = s.kind[fought_at]   # (a hunter never comes into a station's system: pin where we are)
	_expect(int(slow.get("escaped", 0)) == 1, "it remembers it was escaped once")
	var plain_step := roundi(Road.HUNTER_STEP * Net.TICK_HZ)
	slow["move"] = plain_step - Net.TICK_HZ
	_run(Net.TICK_HZ + 1)
	var held := int(slow["at"]) == fought_at
	slow["move"] = roundi(Road.HUNTER_STEP * (1.0 + Road.HUNTER_SLOWER) * Net.TICK_HZ) - Net.TICK_HZ
	_run(Net.TICK_HZ + 1)
	_expect(held and int(slow["at"]) != fought_at, "escaped once, it takes %d s a lane, not %d" % [
		roundi(Road.HUNTER_STEP * (1.0 + Road.HUNTER_SLOWER)), roundi(Road.HUNTER_STEP)])
	slow["coming"] = -1
	s.kind = kinds_were
	s.fog = fog_were
	_calm()
	# beaten, it is gone
	r.spawn_hunter()
	r.hunters[0]["at"] = server.ship.sector
	r.hunters[0]["coming"] = server.tick
	_run(Net.TICK_HZ * 2)
	_expect(server.gunnery.fighting(), "")
	server.gunnery._wrecked()
	_run(Net.TICK_HZ)
	server.derelict._leave(true)
	_run(2)
	_expect(r.hunters.is_empty() and r._fight.is_empty(), "wrecked, the hunter is gone")
	_calm()
	# a station is safe
	var st := s.kind.find(Sectors.STATION)
	_arrive_at(s.cell[st])
	r.spawn_hunter()
	r.hunters[0]["at"] = s.neighbours(st)[0]
	for i in 6:
		r.hunters[0]["move"] = roundi(Road.HUNTER_STEP * Net.TICK_HZ) - Net.TICK_HZ
		_run(Net.TICK_HZ + 1)
	_expect(int(r.hunters[0]["at"]) != st, "it never comes into a station's system")
	# a nebula hides them both ways
	var fog_was: int = s.fog[server.ship.sector]
	s.fog[server.ship.sector] = 0
	var seen := r.packet()
	s.fog[server.ship.sector] = 1
	var blind := r.packet()
	s.fog[server.ship.sector] = fog_was
	_expect(seen[4] == 1 and blind[4] == 0 and blind[1] == 1, "from inside a nebula the chart shows no hunters")
	_calm()
	# they come by themselves, and fewer at a time than the most
	r.auto = true
	server.director.auto = true
	r.ticks_here = r.next_hunter - 1
	_run(Net.TICK_HZ + 1)
	var came := r.hunters.size()
	for i in 10:
		r.ticks_here = r.next_hunter
		_run(Net.TICK_HZ)
	_expect(came == 1 and r.hunters.size() <= r._most(), "the cluster's clock brings them, %d at most (%d now)" % [r._most(), r.hunters.size()])
	r.auto = false
	server.director.auto = false
	_calm()


# --------------------------------------------------------------- the long jump

func _long_jump() -> void:
	print("  -- the long jump")
	var r: Road = server.road
	var s: Sectors = server.sectors
	_enter_cluster(0)
	_expect(r.can_leave() != "", "not from the start: only from an exit")
	_arrive_at(s.cell[s.exits[1]])
	server.ship.tank = server.ship.jump_cost * Sectors.EXIT_FUEL - 1
	_expect(r.can_leave().contains("топлива"), "from an exit, but it needs %d units" % (server.ship.jump_cost * Sectors.EXIT_FUEL))
	server.ship.tank = Net.FUEL_MAX
	_expect(r.can_leave() == "", "with them, it can be set")
	_enter_cluster(Sectors.FLAG_DEPTH)
	_arrive_at(s.cell[s.exits[0]])
	_expect(r.can_leave().contains("Глушилка"), "in the flagship's cluster, its jammer holds the exits")
	server.won = true
	_expect(r.can_leave() == "", "beaten, they open")
	server.won = false
	server.flagship.awake = false
	_enter_cluster(0)


# --------------------------------------------------------------- the chart

func _packet() -> void:
	print("  -- the chart's packet")
	var r: Road = server.road
	var s: Sectors = server.sectors
	_calm()
	r.spawn_hunter()
	var f := _find_place(Sectors.P_DEBRIS)
	_enter_cluster(f[0])
	r.spawn_hunter()
	_arrive_at(f[1])
	r.reveal_here()
	s.fog[server.ship.sector] = 0                # (from inside a nebula the chart shows less: checked above)
	var client := GameClient.new()
	client._read_road(r.packet())
	var road: Dictionary = client.road
	_expect(road.get("hunters", []).size() == r.hunters.size() and (road["known"] as PackedByteArray).size() == s.count,
		"the client reads the hunters and what the chart shows")
	_expect(road["places"].size() == r._here_places.size() and (road["places"][f[2]][1] as Vector2) == _place_at(f[2]),
		"and the places found here, where they lie")
	var k: PackedByteArray = road["known"]
	var ok := k[server.ship.sector] == 1
	for i in s.count:
		if s.kind[i] == Sectors.TRADER and s.fog[i] == 0:
			ok = ok and k[i] == 1
	_expect(ok, "the chart knows where we are, and where the traders call from")
	client.free()
	_calm()
	_enter_cluster(0)


# --------------------------------------------------------------- leaving a cluster

func _left_behind() -> void:
	print("  -- a cluster left behind")
	var st = server.story
	_calm()
	_enter_cluster(0)
	st.quests.clear()
	st.quests.append({"kind": Net.QUEST_CARGO, "at": server.sectors.cell[server.sectors.kind.find(Sectors.STATION)], "placed": false, "part": 0,
		"name": "", "title": "Груз", "text": "", "reward": 30})
	server.ship.store[Net.ITEM_CARGO] = 1
	var into: int = server.sectors.beyond[0]
	server.road.admin_next(0)
	_run(2)
	_expect(server.sectors.depth == 1 and server.sectors.ckind == into and server.ship.sector == server.sectors.start, "into the next cluster, at its start")
	_expect(st.quests.is_empty() and int(server.ship.store.get(Net.ITEM_CARGO, 0)) == 0, "a side quest of the cluster left behind is lost")
	_expect(server.road.history.size() == 1, "the road behind us is remembered")


# --------------------------------------------------------------- saving

func _saved() -> void:
	print("  -- saving")
	var r: Road = server.road
	_calm()
	r.spawn_hunter()
	var f := _find_place(Sectors.P_DEBRIS)
	_enter_cluster(f[0])
	r.history = PackedByteArray(range(f[0]).map(func(_i: int) -> int: return Sectors.C_PIRATE))
	_arrive_at(f[1])
	r.spawn_hunter()
	r.reveal_here()
	_run(1)
	var data := Campaign.snapshot(server)
	var json: Dictionary = JSON.parse_string(JSON.stringify(data))
	var other := _new_server(26501)
	var problem := Campaign.restore(other, json)
	_expect(problem == "", "it restores (%s)" % problem)
	_expect(other.sectors.depth == server.sectors.depth and other.sectors.cell == server.sectors.cell and other.sectors.kind == server.sectors.kind
		and other.ship.sector == server.ship.sector, "the cluster and where we are in it")
	r.hunters[0]["escaped"] = 2
	data = Campaign.snapshot(server)
	json = JSON.parse_string(JSON.stringify(data))
	other.stop()
	other.free()
	other = _new_server(26503)
	problem = Campaign.restore(other, json)
	_expect(int(other.road.hunters[0].get("escaped", 0)) == 2, "a hunter keeps how often it was escaped")
	_expect(other.road.hunters.size() == r.hunters.size() and other.road.found.size() == r.found.size() and other.road.history == r.history,
		"the hunters, the places found, the road behind")
	other.stop()
	other.free()
	# an old save (before the clusters) starts at a fresh first cluster
	json.erase("road")
	var old := _new_server(26502)
	problem = Campaign.restore(old, json)
	_expect(problem == "" and old.sectors.depth == 0 and old.ship.sector == old.sectors.start
		and old.sectors.cell[old.sectors.start] == Vector2i.ZERO, "an old save goes on at the start of a fresh first cluster")
	old.stop()
	old.free()


func _expect(ok: bool, what: String) -> void:
	if what == "":
		if not ok:
			failed += 1
			print("  FAIL  (a step above)")
		return
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
