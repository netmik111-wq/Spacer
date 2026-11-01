extends SceneTree
## (v101) Checks the author's 1 Nov asks (his answers N1-N6 on the run-length page):
##   godot --headless --path . --script res://tools/turrettest.gd
## Ships in space look like ships (N5 C, N6 A): plating round the drawing, a pointed bow, engine bells and fins, and a
## shot through the plating lands on the ship itself. Turrets on the floor of the top and bottom decks (N3 A) turn all
## round and hit at 0.8 (N4 B). An engineer takes an empty mount down (10 s) and sets it up in another outer wall or on
## the floor (N2 A); others are refused, and so are inner walls, doorways and full ships; a spare mount comes from a
## trader. Clients learn where the mounts are (S_MOUNT_CELLS) and lay the same cells; a save keeps them. Longer runs
## (N1 A): the flagship waits in the sixth cluster, hunters grow by the cluster, bots weld the hull with scrap.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")
const Arena := preload("res://src/server/arena.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Mounts := preload("res://src/server/mounts.gd")
const Road := preload("res://src/server/road.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26410, "ship02", 2)
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
	server.arena.hold_pirates = true
	for q in server.players:
		if q != null and q.bot:
			q.order = Net.POST_FREE
	var map = server.map
	var a = server.arena

	# ---- N5 C / N6 A: a ship, not a hotdog
	var shape = ArenaShape.of_fleet(map, 0)
	var plates := 0
	for k: int in shape.kind:
		if k == ArenaShape.PLATE:
			plates += 1
	_expect(shape.w > shape.own_w + 4 and plates > 40, "our ship wears plating: %d cells, %d long against its own %d" % [plates, shape.w, shape.own_w])
	_expect(shape.bells.size() == 2 and shape.bells[0].x < -shape.own_w / 2.0, "two engine bells behind the stern (%s)" % str(shape.bells))
	var nose := -1
	var mid_row: int = shape.h / 2
	for x in range(shape.w - 1, -1, -1):
		if shape.kind[mid_row * shape.w + x] != ArenaShape.EMPTY:
			nose = x
			break
	var top_row := -1
	for x in range(shape.w - 1, -1, -1):
		if shape.kind[1 * shape.w + x] != ArenaShape.EMPTY:
			top_row = x
			break
	_expect(nose > top_row + 3, "the bow comes to a point (the middle row reaches %d, the second %d)" % [nose, top_row])
	var proxied := true
	for i: int in shape.proxy.keys():
		var under: PackedInt32Array = shape.cells_under(Vector2i(i % shape.w, i / shape.w))
		if under.is_empty():
			proxied = false
	_expect(not shape.proxy.is_empty() and proxied, "a shot through the plating lands on the ship itself")
	var pirate_map = map.others[0]
	var bare = ArenaShape.of_layout(pirate_map)
	var dressed = ArenaShape.of_layout(pirate_map, true)
	_expect(dressed.w > bare.w and dressed.h > bare.h and dressed.own_w == bare.w, "pirates get the same plating (%dx%d from %dx%d)" % [dressed.w, dressed.h, bare.w, bare.h])

	# ---- N3 A / N4 B: turrets on the floor
	var floor_guns: Array[int] = []
	for i in map.guns.size():
		if map.guns[i] >= 0 and map.on_floor.has(map.guns[i]):
			floor_guns.append(i)
	_expect(floor_guns.size() == 2, "ship02 has two turrets on the floor (%d)" % floor_guns.size())
	var roof := -1
	var belly := -1
	for i: int in floor_guns:
		if map.roof(map.guns[i]):
			roof = i
		else:
			belly = i
	_expect(roof >= 0 and belly >= 0, "one on the roof, one on the belly")
	var all_round := true
	for i: int in floor_guns:
		if ArenaShape.kind_in_fleet(map, map.guns[i]) != ArenaShape.MOUNT_ROOF:
			all_round = false
	_expect(all_round, "both turn all round (the roof kind, 360°)")
	_expect(server.ship.mounts[roof] == Weapons.NONE and server.ship.mounts[belly] == Weapons.NONE, "they start bare: guns are carried up to them")
	_expect(map.guns.size() == 6 + ShipMap.SPARE_MOUNTS and map.first_stowed() == 6, "and there is room for %d more mounts" % ShipMap.SPARE_MOUNTS)

	_expect(server.derelict.pirates_come(2, true), "(a raider comes)")
	_run(1)
	server.ship.mounts[roof] = Weapons.LASER
	var wall_gun := -1
	for i in map.guns.size():
		if map.guns[i] >= 0 and not map.on_floor.has(map.guns[i]) and server.ship.mounts[i] == Weapons.LASER:
			wall_gun = i
			break
	a._shoot_ours(0, roof, Weapons.LASER, 0, -1, 0.0, {})
	var soft: float = float((a.shots[-1] as Dictionary)["d"])
	a._shoot_ours(0, wall_gun, Weapons.LASER, 0, -1, 0.0, {})
	var hard: float = float((a.shots[-1] as Dictionary)["d"])
	_expect(absf(soft - hard * Arena.ROOF_SHARE) < 0.01 and hard > 0.0, "a turret's laser hits at 0.8 of the hull gun's (%.1f against %.1f)" % [soft, hard])
	server.ship.mounts[roof] = Weapons.NONE
	server.derelict.pirates_wrecked()
	a.shots.clear()
	server.derelict._leave(true)
	_run(40)

	# ---- N2 A: moving a mount
	var eng = server.crew.new_player("Механик")
	eng.job = Net.JOB_ENGINEER
	var hand = server.crew.new_player("Матрос")
	hand.job = Net.JOB_CREWMAN
	var moved: int = wall_gun
	var old_cell: int = map.guns[moved]
	server.ship.mounts[moved] = Weapons.NONE
	var spot: Array = server.stations._spots_for(old_cell)
	_expect(not spot.is_empty(), "(a place to stand at gun %d)" % (moved + 1))
	_stand(hand, int(spot[0][0]), int(spot[0][1]))
	_expect(server.mounts.can(hand, old_cell).begins_with("Пустое гнездо снимает"), "a crewman may not take an empty mount down")
	_stand(eng, int(spot[0][0]), int(spot[0][1]))
	_park(hand)
	_expect(server.mounts.can(eng, old_cell) == "", "an engineer may")
	_hold(eng, roundi(Mounts.MOVE_SECONDS * Net.TICK_HZ) + 10)
	_expect(map.guns[moved] < 0 and eng.in_hand() == Net.ITEM_MOUNT, "held 10 seconds, the mount comes down into his hands")
	_expect(map.cells[old_cell] != int(map.tile_ids["gun"]) and map.hull.has(old_cell), "and the wall there is a plain outer wall again")
	_expect(a.body(0).guns[moved]["cell"] == map.guns[moved], "the ship in space has lost that gun")

	# refused: an inner wall, a doorway
	var inner := -1
	for c in map.cells.size():
		if map.cells[c] >= 0 and map.walk[c] == 0 and not map.hull.has(c) and map.fitting_front(c) < 0 and map.door_of[c] < 0 \
				and not map.is_space(c % map.width, c / map.width - 1) and map.walkable(c % map.width, c / map.width + 1) \
				and map.walkable(c % map.width, c / map.width - 1):
			inner = c
			break
	_expect(inner >= 0 and map.can_mount(inner) != "", "not into an inner wall (%s)" % (map.can_mount(inner) if inner >= 0 else "?"))
	var door_cell: int = map.doors[0].y * map.width + map.doors[0].x
	_expect(map.can_mount(door_cell) != "", "nor into a doorway")

	# set up in another outer wall
	var wall := _free_wall(eng)
	_expect(wall.size() == 2, "(a clean outer wall to set it in)")
	_stand(eng, int(wall[1][0]), int(wall[1][1]))
	_expect(server.mounts.can(eng, int(wall[0])) == "", "the mount goes into another outer wall")
	_hold(eng, roundi(Mounts.MOVE_SECONDS * Net.TICK_HZ) + 10)
	var now: int = map.guns[moved]
	_expect(now == int(wall[0]) and map.cells[now] == int(map.tile_ids["gun"]) and not map.hull.has(now) and eng.in_hand() == Net.ITEM_NONE,
		"held 10 seconds, it stands there as gun %d" % (moved + 1))
	_expect(a.body(0).guns[moved]["cell"] == now and ArenaShape.of_fleet(map, 0).kind[ArenaShape.of_fleet(map, 0).index(_shape_cell(now))] == ArenaShape.GUN,
		"and the ship in space has it there")

	# down again and onto the floor of the top deck: a turret
	_stand(eng, int(wall[1][0]), int(wall[1][1]))
	_hold(eng, roundi(Mounts.MOVE_SECONDS * Net.TICK_HZ) + 10)
	var floor_spot := _free_floor(eng, true)
	_expect(floor_spot.size() == 2 and eng.in_hand() == Net.ITEM_MOUNT, "(taken down again, a clear floor on the top deck)")
	_stand(eng, int(floor_spot[1][0]), int(floor_spot[1][1]))
	_expect(server.mounts.can(eng, int(floor_spot[0])) == "", "a turret may stand on the roof's floor")
	_hold(eng, roundi(Mounts.MOVE_SECONDS * Net.TICK_HZ) + 10)
	now = map.guns[moved]
	if now != int(floor_spot[0]):
		print("    (why: «%s», at %d,%d facing %d, hand %d, cond %d, floor %s)" % [server.mounts.can(eng, int(floor_spot[0])), eng.st.x, eng.st.y,
			eng.st.facing, eng.in_hand(), eng.cond, str(server.floor_things.get(int(floor_spot[0]), []))])
	_expect(now == int(floor_spot[0]) and map.on_floor.has(now) and map.walk[now] == 0 and ArenaShape.kind_in_fleet(map, now) == ArenaShape.MOUNT_ROOF,
		"it is a turret there: in the way, turning all round")
	_expect(a.body(0).guns[moved]["kind"] == ArenaShape.MOUNT_ROOF, "and so in space")

	# clients lay the same cells
	var mirror = ShipMap.new()
	mirror.load_from("ship02")
	var pkt: PackedByteArray = server.mounts.cells_packet()
	for k in pkt[2]:
		var c := pkt.decode_s32(3 + k * 4)
		if mirror.guns[k] >= 0 and mirror.guns[k] != c:
			mirror.set_gun(k, -1)
	for k in pkt[2]:
		var c := pkt.decode_s32(3 + k * 4)
		if c >= 0 and mirror.guns[k] != c:
			mirror.set_gun(k, c)
	_expect(mirror.cells == map.cells and mirror.walk == map.walk and mirror.guns == map.guns, "a client told where the mounts are lays the same cells")

	# a save keeps them
	var data := Campaign.snapshot(server)
	var cells_saved: Array = data.get("gun_cells", [])
	_expect(cells_saved.size() == map.guns.size() and int(cells_saved[moved]) == now, "the save keeps where the mounts are")
	var b := GameServer.new()
	get_root().add_child(b)
	b.start(26412, "ship02", 0)
	var why := Campaign.restore(b, JSON.parse_string(JSON.stringify(data)))
	_expect(why == "" and b.map.guns == map.guns and b.map.cells == map.cells, "and a loaded game has them where they were (%s)" % why)
	b.stop()

	# spare mounts: two more, then no room
	for k in ShipMap.SPARE_MOUNTS:
		eng.slots[eng.hand] = Net.ITEM_MOUNT
		var spare := _free_floor(eng, false)
		_stand(eng, int(spare[1][0]), int(spare[1][1]))
		_hold(eng, roundi(Mounts.MOVE_SECONDS * Net.TICK_HZ) + 10)
	_expect(map.first_stowed() < 0 and Array(map.guns).filter(func(c: int) -> bool: return c >= 0).size() == map.guns.size(),
		"two bought mounts go up too (one on the belly's floor)")
	eng.slots[eng.hand] = Net.ITEM_MOUNT
	var last := _free_wall(eng, false)
	_stand(eng, int(last[1][0]), int(last[1][1]))
	_expect(server.mounts.can(eng, int(last[0])).begins_with("На корабле больше нет места"), "then the ship has no room for more")
	eng.slots[eng.hand] = Net.ITEM_NONE

	# ---- N1 A: longer runs
	_expect(Sectors.FLAG_DEPTH == 5, "the flagship waits in the sixth cluster")
	var levels: Array[int] = []
	for depth in 6:
		server.road.depth = depth
		levels.append(server.road.hunter_level())
	server.road.depth = 0
	_expect(levels[0] == 0 and levels[2] == 1 and levels[4] == 2 and levels[5] == Road.HUNTER_LEVEL, "hunters grow by the cluster (%s)" % str(levels))
	server.ship.store[Net.ITEM_PATCH] = 0
	server.ship.store[Net.ITEM_SCRAP] = 4
	_expect(server.outside._store_menders() == 4, "bots weld the hull with scrap when there are no patches")

	# ---- S3 A: the run's log
	_expect(server.run_log.lines.size() >= 1 and str(server.run_log.lines[0]).contains("Начало кампании"), "the run's log begins with the start")
	server.run_log._mark()
	server.ship.credits += 50
	server.voyage_ticks += 20 * 60 * 31
	server.run_log.cluster_done(1)
	_expect(str(server.run_log.lines[-1]).contains("Скопление 1 пройдено за 31 мин: пришло 50"), "a cluster passed is logged with its minutes and money (%s)" % str(server.run_log.lines[-1]))
	_expect(server.run_log.text().contains("Журнал прохождения"), "and it reads as a file")

	server.stop()
	print("turrettest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	quit(1 if failed > 0 else 0)


func _shape_cell(cell: int) -> Vector2i:
	var s = ArenaShape.of_fleet(server.map, 0)
	var l: Vector2 = s.local_of(cell)
	return Vector2i(roundi(l.x - 0.5 + s.w / 2.0), roundi(l.y - 0.5 + s.h / 2.0))


func _stand(p, cell: int, facing: int) -> void:
	p.st.x = cell % server.map.width
	p.st.y = cell / server.map.width
	p.st.ox = 0
	p.st.oy = 0
	p.st.facing = facing
	p.st.dir = Net.DIR_NONE
	p.st.cd = 0
	p.work = 0


func _park(p) -> void:
	var s: Vector2i = server.crew.spawn_point()
	p.st.x = s.x
	p.st.y = s.y


func _hold(p, ticks: int) -> void:
	## Holds "use" until what is in the hands changes (a mount comes down or goes up), at most twice that long (work
	## is slower for one hungry or hurt); the bots walking about are kept off the cell ahead (a turret needs it clear).
	p.using = true
	var ahead: int = server.map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	var had: int = p.in_hand()
	for i in ticks * 2:
		if p.in_hand() != had:
			break
		p.st.dir = Net.DIR_NONE
		for q in server.players:
			if q != null and q != p and q.st.y * server.map.width + q.st.x == ahead:
				_park(q)
		server._tick()
	p.using = false
	server._tick()


func _free_wall(p, asked := true) -> Array:
	## A clean outer wall cell of ship 0 a mount may go into, and where to stand facing it: [cell, [floor, facing]].
	var map = server.map
	for c: int in map.hull:
		if map.fleet_of(c) != 0 or map.can_mount(c) != "":
			continue
		for f in range(1, 5):
			var x: int = c % map.width - Net.DX[f]
			var y: int = c / map.width - Net.DY[f]
			if map.walkable(x, y) and map.door_at(x, y) < 0 and map.cell_ahead(x, y, f) == c:
				var was := [p.st.x, p.st.y, p.st.facing]
				_stand(p, y * map.width + x, f)
				var ok: bool = server.mounts.can(p, c) == "" or not asked
				p.st.x = was[0]
				p.st.y = was[1]
				p.st.facing = was[2]
				if ok:
					return [c, [y * map.width + x, f]]
	return []


func _free_floor(p, top: bool) -> Array:
	## A clear floor cell for a turret (on the roof, or on the belly), and where to stand facing it.
	var map = server.map
	for c in map.cells.size():
		if map.walk[c] != 1 or map.roof(c) != top or map.fleet_of(c) != 0 or map.can_mount(c) != "" or not map.on_ship(c):
			continue
		for f in range(1, 5):
			var x: int = c % map.width - Net.DX[f]
			var y: int = c / map.width - Net.DY[f]
			if map.walkable(x, y) and map.door_at(x, y) < 0:
				var was := [p.st.x, p.st.y, p.st.facing]
				_stand(p, y * map.width + x, f)
				var ok: bool = server.mounts.can(p, c) == ""
				p.st.x = was[0]
				p.st.y = was[1]
				p.st.facing = was[2]
				if ok:
					return [c, [y * map.width + x, f]]
	return []


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("  ok    " + what)
	else:
		failed += 1
		print("  FAIL  " + what)
