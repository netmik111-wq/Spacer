extends SceneTree
## Checks the clusters of space without a network or a window:
##   godot --headless --path . --script res://tools/spacetest.gd
## (v64) Space is a road of clusters made from a seed, not stored: the same
## cluster must always hold the same thing, every system must be reachable,
## every cluster must have its two exits, a trader and (but the dead zone) a
## station, and the flagship must wait in the fourth. A ship that keeps jumping
## must find new systems, and the long jump out must take it into the next
## cluster. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0


func _initialize() -> void:
	var seed_value := 20261011
	# 1. the same cluster holds the same thing, whenever it is made
	var a := Sectors.new()
	var b := Sectors.new()
	a.build(seed_value, Vector2i.ZERO, {})
	b.build(seed_value, Vector2i(1, 0), {Sectors.key(Vector2i.ZERO): true})
	_expect(a.cell == b.cell and a.kind == b.kind and a.names == b.names and a.links == b.links and a.spot == b.spot
		and a.entry == b.entry and a.exits == b.exits and a.beyond == b.beyond, "a cluster is the same whenever it is made")
	_expect(a.cell[a.start] == Vector2i.ZERO and a.here == a.start and b.visited[b.start] == 1, "the voyage begins at the first cluster's start")
	var other := Sectors.new()
	other.build(seed_value + 1, Vector2i.ZERO, {})
	_expect(other.kind != a.kind or other.names != a.names or other.links != a.links, "another game has another space")

	# 2. over the network and back
	a.road = PackedByteArray([1, 3])
	var copy := Sectors.new()
	copy.unpack(a.pack(), 0)
	_expect(copy.count == a.count and copy.here == a.here and copy.cell == a.cell and copy.kind == a.kind and copy.names == a.names
		and copy.links == a.links and copy.spot == a.spot and copy.reach == a.reach and copy.entry == a.entry and copy.deal == a.deal
		and copy.depth == a.depth and copy.ckind == a.ckind and copy.start == a.start and copy.exits == a.exits and copy.beyond == a.beyond
		and copy.level == a.level and copy.fog == a.fog and copy.road == a.road and copy.goal == a.goal and copy.locked == a.locked,
		"the cluster survives the trip to a client (%d bytes for %d systems)" % [a.pack().size(), a.count])

	# 3. the shape of every cluster: many seeds, every depth
	var bad_size := 0
	var cut_off := 0
	var bad_exits := 0
	var no_trader := 0
	var no_station := 0
	var station_in_dead := 0
	var bad_flagship := 0
	var bad_level := 0
	var same_beyond := 0
	var most_lanes := 0
	var kinds := [0, 0, 0, 0, 0, 0, 0]
	var ckinds := [0, 0, 0, 0, 0]
	var fogged := 0
	var thin_storm := 0
	var trader_far := 0
	var made := 0
	var small_total := 0
	var big_total := 0
	for sv in range(1000, 1200):
		for depth in 6:
			var at := Vector2i.ZERO if depth == 0 else Vector2i(6 * depth, (sv * 7 + depth * 3) % 9 - 4)
			var s := Sectors.new()
			s.build(sv, at, {}, depth, at, 1, true)
			made += 1
			small_total += s.count
			var big := Sectors.new()
			big.build(sv, at, {}, depth, at, 8, true)
			big_total += big.count
			if s.count < Sectors.SYSTEMS[0] or s.count > Sectors.MOST_SYSTEMS or big.count > Sectors.MOST_SYSTEMS:
				bad_size += 1
			var d := s.distances(s.start)
			if d.has(-1):
				cut_off += 1
			if s.exits.size() != 2 or s.exits[0] == s.exits[1] or s.cell[s.exits[0]].x != at.x + Sectors.COLS - 1 or s.cell[s.exits[1]].x != at.x + Sectors.COLS - 1 \
					or s.cell[s.start] != at:
				bad_exits += 1
			if s.beyond.size() == 2 and s.beyond[0] == s.beyond[1]:
				same_beyond += 1
			if not s.kind.has(Sectors.TRADER) or not s.kind.has(Sectors.DERELICT):
				no_trader += 1
			if s.ckind != Sectors.C_DEAD and not s.kind.has(Sectors.STATION):
				no_station += 1
			if s.ckind == Sectors.C_DEAD and s.kind.has(Sectors.STATION):
				station_in_dead += 1
			var flags := s.kind.count(Sectors.FLAGSHIP)
			if (depth == Sectors.FLAG_DEPTH) != (flags == 1) or flags > 1 or (depth == Sectors.FLAG_DEPTH and (not s.locked or s.exits.has(s.index_of(s.goal)))):
				bad_flagship += 1
			if s.level[s.start] != depth * Sectors.LEVEL_STEP:
				bad_level += 1
			if depth == 0:
				var near := 99
				for i in s.count:
					if s.kind[i] == Sectors.TRADER:
						near = mini(near, d[i])
				if near > 2:
					trader_far += 1
			for i in s.count:
				most_lanes = maxi(most_lanes, s.neighbours(i).size())
				kinds[s.kind[i]] += 1
			ckinds[s.ckind] += 1
			if s.fog.has(1):
				fogged += 1
			if s.ckind == Sectors.C_STORM and s.kind.count(Sectors.ION_STORM) < 3:
				thin_storm += 1
	print("  %d clusters: systems of each kind %s; clusters of each kind %s; %d with a nebula" % [made, kinds, ckinds, fogged])
	_expect(bad_size == 0, "every cluster has %d to %d systems (a big crew up to %d)" % [Sectors.SYSTEMS[0], Sectors.SYSTEMS[1], Sectors.MOST_SYSTEMS])
	_expect(big_total > small_total, "a big crew finds bigger clusters (%.1f against %.1f systems)" % [float(big_total) / made, float(small_total) / made])
	_expect(cut_off == 0, "every system of every cluster can be reached along lanes")
	_expect(bad_exits == 0, "every cluster is entered on its left and has two exits on its far side")
	_expect(same_beyond == 0, "two exits never lead to clusters of one kind")
	_expect(no_trader == 0 and no_station == 0 and station_in_dead == 0, "every cluster has a trader and a derelict, and all but the dead zone a station")
	_expect(trader_far == 0, "in the first cluster a trader is at most two jumps from the start")
	_expect(bad_flagship == 0, "the flagship waits in the fourth cluster only, not at an exit, and shuts its exits")
	_expect(bad_level == 0, "each cluster is %d steps of danger harder than the one before" % Sectors.LEVEL_STEP)
	_expect(most_lanes <= 8, "no system has more than 8 lanes (found %d)" % most_lanes)
	var all_kinds := kinds.duplicate()
	all_kinds.remove_at(Sectors.FLAGSHIP)
	_expect(all_kinds.min() > 0 and ckinds.min() > 0 and fogged > 0, "every kind of system and of cluster is met, and nebulae")
	_expect(thin_storm == 0, "a storm belt has a band of at least three ion storms")
	var places := 0
	var with_places := 0
	for i in a.count:
		var p := a.places(seed_value, i)
		places += p.size()
		with_places += 1 if p.size() > 0 else 0
		for pl: Array in p:
			if (pl[1] as Vector2).distance_to(a.entry[i]) <= Sectors.PLACE_REACH + 4:
				places = -999
	_expect(a.places(seed_value, a.start).is_empty(), "the first cluster's start has no places of its own")
	_expect(places > 0, "places lie inside systems (%d in %d systems), never where a ship comes out of a jump" % [places, with_places])

	# 4. a ship that keeps jumping, and the long jump out
	var server := GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26210, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.story.auto = false                             # (no comms calls: their outcomes may pay credits)
	server.story.m1_next = 1 << 30        # (the chapter's mission and SOS sectors call even so; those are kept off below)
	# a ship under way when the jump is set coasts straight on, whatever point it was making for
	var from: Vector2 = server.ship.pos
	server.ship.dest = from + Vector2(20, 0)
	server.ship.moving = true
	server.story.sos_done[Sectors.key(server.sectors.cell[server.sectors.neighbours(server.ship.sector)[0]])] = true
	server.navigation.start_jump(server.sectors.neighbours(server.ship.sector)[0], "Проверка")
	_expect(server.ship.moving and server.ship.dest == Vector2(Sectors.SPAN, from.y), "set for a jump, a moving ship coasts on to the edge of the sector instead of its old course")
	for t in Net.JUMP_TICKS - 2:
		server._tick()
	var went: float = server.ship.pos.x - from.x
	_expect(absf(went - Sectors.SHIP_SPEED * (Net.JUMP_TICKS - 2) / Net.TICK_HZ) < 0.2 and server.ship.pos.y == from.y,
		"and keeps its speed and heading until the jump (%.1f units in %.0f s)" % [went, (Net.JUMP_TICKS - 2) / float(Net.TICK_HZ)])
	for t in 4:
		server._tick()
	_expect(not server.ship.moving and server.ship.pos == server.sectors.entry[server.ship.sector], "it comes out of the jump standing still at its place of arrival")
	server.ship.credits = Net.START_CREDITS
	server.ship.tank = Net.FUEL_MAX                       # the walk below is about the chart, not about fuel
	var s: Sectors = server.sectors
	var credits := server.ship.credits
	var fresh := 0
	var ok := true
	var visited_before := s.visited.count(1)
	# walk to an exit, by the shortest way, through systems not visited where one can
	var exit: int = s.exits[0]
	var guard := 0
	while server.ship.sector != exit and guard < 30:
		guard += 1
		var d := s.distances(exit)
		var next := -1
		for n in s.neighbours(server.ship.sector):
			if d[n] < d[server.ship.sector] and (next < 0 or s.visited[n] == 0):
				next = n
		if s.visited[next] == 0:
			fresh += 1
		server.ship.drive_ready = 0
		server.story.sos_done[Sectors.key(s.cell[next])] = true
		server.navigation.start_jump(next, "Проверка")
		for t in Net.JUMP_TICKS + 2:
			server._tick()
		ok = ok and server.ship.sector == next and s.here == next and s.visited[next] == 1 and server.ship.jump_to == Net.NO_SECTOR
	_expect(ok and server.ship.sector == exit, "the ship walks along lanes to an exit (%d jumps)" % guard)
	_expect(fresh > 0 and server.ship.credits == credits + fresh * Net.EXPLORE_REWARD and s.visited.count(1) == visited_before + fresh,
		"%d new systems found and paid for, and marked on the chart" % fresh)
	var into: int = s.beyond[0]
	var was_kind: int = s.ckind
	var old_cells := s.cell.duplicate()
	server.ship.tank = Net.FUEL_MAX
	var fuel: float = server.ship.tank
	server.ship.drive_ready = 0
	server.navigation.start_jump(Sectors.EXIT_JUMP, "Проверка")
	_expect(server.ship.jump_to == Sectors.EXIT_JUMP and server.ship.jump_tick - server.tick > Net.JUMP_TICKS, "the long jump charges longer than a plain one")
	for t in Net.JUMP_TICKS * 2:
		server._tick()
	_expect(is_equal_approx(server.ship.tank, fuel - Sectors.EXIT_FUEL * server.ship.jump_cost), "the long jump burns %d units (%d lane jumps' worth)" % [
		Sectors.EXIT_FUEL * server.ship.jump_cost, Sectors.EXIT_FUEL])
	_expect(s.depth == 1 and s.ckind == into and s.road == PackedByteArray([was_kind]) and server.ship.sector == s.start,
		"and the ship comes into the next cluster at its start, of the kind the exit showed (%s)" % Sectors.CLUSTER_NAMES[into])
	var shared := false
	for c: Vector2i in s.cell:
		shared = shared or old_cells.has(c)
	_expect(not shared, "the new cluster shares no system with the old one: there is no way back")
	_expect(s.far_from_start(s.start) == Sectors.LEVEL_STEP, "and it is a step of danger harder")
	server.stop()
	server.free()

	print("SPACETEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
