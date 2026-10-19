extends SceneTree
## Checks endless space without a network or a window:
##   godot --headless --path . --script res://tools/spacetest.gd
## Space is made from a seed, not stored: the same place must always hold the
## same thing, every sector must have a way on, and a ship that keeps jumping
## must keep finding new sectors while the chart remembers the old ones.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0


func _initialize() -> void:
	var seed_value := 20261011
	# 1. the same place holds the same thing, whenever and from wherever it is looked at
	var a := Sectors.new()
	var b := Sectors.new()
	a.build(seed_value, Vector2i(5, -3), {})
	b.build(seed_value, Vector2i(7, -2), {})
	var same := true
	for i in a.count:
		var j := b.cell.find(a.cell[i])
		if j >= 0 and (a.kind[i] != b.kind[j] or a.names[i] != b.names[j] or a.spot[i] != b.spot[j] or a.entry[i] != b.entry[j]):
			same = false
	_expect(same, "a sector is the same from whichever side the chart comes upon it")
	var other := Sectors.new()
	other.build(seed_value + 1, Vector2i(5, -3), {})
	_expect(other.kind != a.kind or other.names != a.names, "another game has another space")

	# 2. over the network and back
	var copy := Sectors.new()
	copy.unpack(a.pack(), 0)
	_expect(copy.count == a.count and copy.here == a.here and copy.cell == a.cell and copy.kind == a.kind and copy.names == a.names
		and copy.links == a.links and copy.spot == a.spot and copy.reach == a.reach and copy.entry == a.entry,
		"the chart survives the trip to a client (%d bytes for %d sectors)" % [a.pack().size(), a.count])

	# 3. routes: everybody has a way on, nobody more than four, and space is in one piece
	var most := 0
	var least := 99
	var size := 30
	for y in range(-size, size + 1):
		for x in range(-size, size + 1):
			var n := 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if Sectors.joined(seed_value, Vector2i(x, y), Vector2i(x, y) + d):
					n += 1
			most = maxi(most, n)
			least = mini(least, n)
	_expect(least >= 1 and most <= Sectors.MAX_ROUTES, "every sector has a route, none more than %d (found %d to %d)" % [Sectors.MAX_ROUTES, least, most])
	var seen := {Vector2i.ZERO: true}
	var todo: Array[Vector2i] = [Vector2i.ZERO]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if absi(n.x) <= size and absi(n.y) <= size and not seen.has(n) and Sectors.joined(seed_value, c, n):
				seen[n] = true
				todo.append(n)
	var inner := 0
	var reached := 0
	for y in range(-10, 11):
		for x in range(-10, 11):
			inner += 1
			if seen.has(Vector2i(x, y)):
				reached += 1
	print("  from the start %d of the %d sectors within 10 can be reached without going further than %d" % [reached, inner, size])
	_expect(reached >= inner * 95 / 100, "space is in one piece around the start")

	# 4. what space holds: all five kinds (v61: and ion storms), and more meteor streams further out
	var near := [0, 0, 0, 0, 0, 0, 0]
	var far := [0, 0, 0, 0, 0, 0, 0]
	for y in range(-6, 7):
		for x in range(-6, 7):
			near[Sectors.kind_at(seed_value, Vector2i(x, y))] += 1
			far[Sectors.kind_at(seed_value, Vector2i(x + 300, y + 300))] += 1
	print("  around the start: %s; far away: %s (quiet, meteors, traders, stations, derelicts, -, ion storms)" % [near, far])
	near.remove_at(Sectors.FLAGSHIP)         # (the flagship is placed by the goal, never rolled)
	far.remove_at(Sectors.FLAGSHIP)
	_expect(near.min() > 0 and far.min() > 0, "every kind of sector is found near the start and far from it")
	_expect(far[Sectors.METEORS] > near[Sectors.METEORS], "meteor streams are commoner far from the start")
	_expect(Sectors.kind_at(seed_value, Vector2i.ZERO) == Sectors.EMPTY, "the voyage begins in quiet space")

	# 5. a ship that keeps jumping: the server builds the chart anew each time and remembers where it has been
	var server := GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26210, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	# a ship under way when the jump is set coasts straight on, whatever point it was making for
	var from: Vector2 = server.ship.pos
	server.ship.dest = from + Vector2(20, 0)
	server.ship.moving = true
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
	server.been = {Sectors.key(server.sectors.cell[server.ship.sector]): true}    # the walk below starts from here
	server.sectors.build(server.space_seed, server.sectors.cell[server.ship.sector], server.been)
	server.ship.credits = Net.START_CREDITS
	server.ship.store[Net.ITEM_FUEL] = 100                # the walk below is about the chart, not about fuel
	server.story.auto = false                             # (no comms calls: their outcomes may pay credits)
	for t in Net.DRIVE_REST_TICKS:
		server._tick()
	var start_cell: Vector2i = server.sectors.cell[server.ship.sector]
	var credits := server.ship.credits
	var fresh := 0
	var path: Array[Vector2i] = [start_cell]
	var ok := server.ship.sector == server.sectors.here and server.sectors.visited[server.ship.sector] == 1
	var walked := {}                      # cell -> times this walk came there (to get out of dead ends)
	for jump in 12:
		# go on to a sector not yet visited if there is one, else to the one the walk came to least
		var next := -1
		for n in server.sectors.neighbours(server.ship.sector):
			if next < 0 or (server.sectors.visited[n] == 0 and server.sectors.visited[next] == 1) \
					or (server.sectors.visited[n] == server.sectors.visited[next] \
					and int(walked.get(server.sectors.cell[n], 0)) < int(walked.get(server.sectors.cell[next], 0))):
				next = n
		var to: Vector2i = server.sectors.cell[next]
		if server.sectors.visited[next] == 0:
			fresh += 1
		server.navigation.start_jump(next, "Проверка")
		for t in Net.JUMP_TICKS + 2:
			server._tick()
		path.append(to)
		walked[to] = int(walked.get(to, 0)) + 1
		ok = ok and server.ship.sector == server.sectors.here and server.sectors.cell[server.ship.sector] == to \
			and server.sectors.visited[server.ship.sector] == 1 and server.ship.jump_to == Net.NO_SECTOR
	_expect(ok, "after every jump the chart is centred on the sector the ship jumped to")
	_expect(fresh >= 6 and server.ship.credits == credits + fresh * Net.EXPLORE_REWARD,
		"%d of 12 jumps found a new sector, and only those were paid for" % fresh)
	var remembered := true
	for i in server.sectors.count:
		if path.has(server.sectors.cell[i]) != (server.sectors.visited[i] == 1):
			remembered = false
	_expect(remembered and server.been.size() == fresh + 1, "the chart marks exactly the sectors the ship has been to (%d of them)" % server.been.size())
	var far_now: int = server.sectors.far_from_start(server.ship.sector)
	print("  the ship ended %d jumps from the start, at %s" % [far_now, server.sectors.cell[server.ship.sector]])
	server.stop()
	server.free()

	print("SPACETEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
