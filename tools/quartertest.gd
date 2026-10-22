extends SceneTree
## Checks v78's quarter steps (the author's M1 "D": "not free walking, a quarter of a
## tile"), lying down (C1 "B") and friendly fire as in RimWorld (his M2): a player
## stops on any quarter, its tile is the one under its centre, its body never lies over
## a wall or a doorway on a slant, it slides into line with a doorway, a door does not
## shut on a body half in it, a hauled body follows by whole tiles, the network bytes,
## lying low (crawling, shots fly over unless aimed at), and a friend right by the
## shooter is never hit. On a real server stepped by hand:
##   godot --headless --path . --script res://tools/quartertest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Items := preload("res://src/shared/items.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26478, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.stations.volunteers = false
	_bytes()
	_on_server()
	_body_never_in_walls()
	_doorways()
	_door_held()
	_haul()
	_lying()
	_friendly_fire()
	print("quartertest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _open_row(length: int) -> Vector2i:
	## A floor cell x,y with open floor (no doorway, no wall) from x - 1 to x + length on its
	## row and the one below (the ship's rooms are two cells high).
	var map = server.map
	for y in map.height:
		for x in map.width:
			if not map.on_ship(y * map.width + x):
				continue
			var ok := true
			for dy in range(0, 2):
				for dx in range(-1, length + 1):
					ok = ok and map.walkable(x + dx, y + dy) and map.door_at(x + dx, y + dy) < 0
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _player(who: String, at: Vector2i):
	var p = server.crew.new_player(who)
	p.quarters = true
	p.slots.fill(Net.ITEM_NONE)
	p.supply = true
	p.tank = 1.0
	p.st.place(at.x, at.y)
	p.st.facing = Net.DIR_RIGHT
	return p


func _bytes() -> void:
	print("  -- the byte after the look: quarters off and lying down")
	var all := true
	for ox in range(-2, 2):
		for oy in range(-2, 2):
			for prone in [false, true]:
				var b := Net.pack_off(ox, oy, prone)
				all = all and b < 256 and Net.off_x(b) == ox and Net.off_y(b) == oy and Net.off_prone(b) == prone
	_expect(all, "every offset and lying down come back as packed")
	_expect(Net.ENT_BYTES == 8 and Net.SELF_BYTES == 20, "records carry it")
	var a := Mover.State.new()
	a.place(10, 10)
	a.ox = 1
	a.oy = -2
	a.fine = true
	a.prone = true
	var b2 := Mover.State.new()
	b2.copy_from(a)
	_expect(b2.same_as(a) and b2.ox == 1 and b2.oy == -2 and b2.fine and b2.prone, "the state copies whole")
	b2.ox = 0
	_expect(not b2.same_as(a), "and a quarter off is a difference")


func _on_server() -> void:
	print("  -- a player stops on a quarter of a tile; bots keep whole tiles")
	var at := _open_row(5)
	_expect(at.x >= 0, "a stretch of open floor (%s)" % at)
	var p = _player("Четвертинка", at)
	p.st.dir = Net.DIR_RIGHT
	server._tick()
	_expect(p.st.fine, "a player steps by quarters")
	_expect(p.st.x == at.x and p.st.ox == 1, "one tick: a quarter of a tile on, still on its tile (%d %+d)" % [p.st.x, p.st.ox])
	server._tick()
	_expect(p.st.x == at.x + 1 and p.st.ox == -2, "two: half way, the tile under its centre is the next (%d %+d)" % [p.st.x, p.st.ox])
	p.st.dir = Net.DIR_NONE
	for i in 6:
		server._tick()
	_expect(p.st.x == at.x + 1 and p.st.ox == -2, "let go: it stays half way between")
	var pos := Mover.visual_pos(p.st, server.tick)
	_expect(pos.distance_to(Vector2(at.x + 0.5, at.y)) < 0.001, "and is drawn there (%s)" % pos)
	p.st.place(at.x, at.y)
	p.st.dir = Net.DIR_RIGHT
	for i in 4 * Net.MOVE_TICKS:
		server._tick()
	_expect(p.st.x == at.x + 4 and p.st.ox == 0, "four tiles in %d ticks: as fast as whole steps (%d %+d)" % [4 * Net.MOVE_TICKS, p.st.x, p.st.ox])
	p.st.place(at.x, at.y)
	p.st.dir = Net.DIR_DOWN_RIGHT
	var ticks := 0
	while p.st.qx() < at.x * 4 + 4 and ticks < 40:
		server._tick()
		ticks += 1
	_expect(p.st.y == at.y + 1 and ticks >= 5 and ticks <= 7, "a tile on a slant takes about 1.4 times as long (%d ticks)" % ticks)
	p.st.dir = Net.DIR_NONE
	var b = server.crew.new_player("Бот")
	b.bot = true
	b.quarters = true
	b.st.place(at.x, at.y + 1)
	b.st.ox = 1
	server._tick()
	_expect(not b.st.fine, "a bot (one that took a player's place too) keeps whole tiles")
	b.st.dir = Net.DIR_RIGHT
	Mover.step(b.st, server.map, server.doors, server.tick + 1)
	_expect(b.st.ox == 0 and b.st.oy == 0, "and is back on a tile's centre")
	b.cond = Net.COND_DEAD                   # out of the way of the checks below
	b.corpse = true
	b.st.down = true
	p.st.place(at.x - 1, at.y)


func _body_never_in_walls() -> void:
	print("  -- 300 walkers roam the ship by quarters: no body over a wall, a corner or a doorway on a slant")
	var map = server.map
	var floor_cells: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			if map.on_ship(y * map.width + x) and map.walkable(x, y) and map.door_at(x, y) < 0:
				floor_cells.append(Vector2i(x, y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var table := Doors.new()
	table.copy_from(server.doors)
	var walkers: Array = []
	for i in 300:
		var st := Mover.State.new()
		var c: Vector2i = floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
		st.place(c.x, c.y)
		st.fine = true
		st.access = Net.ACCESS_ALL
		walkers.append(st)
	var bad_wall := 0
	var bad_slant := 0
	var off_centre := 0
	var moved := 0
	var crossed := 0
	for t in range(1, 600):
		for st: Mover.State in walkers:
			if rng.randf() < 0.08:
				st.dir = rng.randi_range(0, Net.DIRS)
			if rng.randf() < 0.01:
				st.prone = not st.prone
			var was := Vector2i(st.x, st.y)
			if Mover.step(st, map, table, t):
				moved += 1
				if was != Vector2i(st.x, st.y):
					crossed += 1
			var tiles := Mover.body_tiles(st)
			for c: Vector2i in tiles:
				if not map.passable(c.x, c.y):
					bad_wall += 1
			if tiles.size() == 4:
				for c: Vector2i in tiles:
					if map.door_at(c.x, c.y) >= 0:
						bad_slant += 1
			if st.ox != 0 or st.oy != 0:
				off_centre += 1
			if absi(st.ox) > 2 or st.ox == 2 or absi(st.oy) > 2 or st.oy == 2:
				bad_wall += 1000
	_expect(moved > 10000 and crossed > 1000, "they walked (%d quarters, %d tiles)" % [moved, crossed])
	_expect(off_centre > 1000, "and often stood off a tile's centre (%d times)" % off_centre)
	_expect(bad_wall == 0, "no body ever lay over a wall (%d times)" % bad_wall)
	_expect(bad_slant == 0, "nor over a doorway on a slant (%d times)" % bad_slant)


func _doorways() -> void:
	print("  -- a quarter off a doorway, walking into it slides into line and goes through")
	var map = server.map
	var tried := 0
	var through := 0
	for d in map.doors.size():
		var c: Vector2i = map.doors[d]
		for way: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var side := Vector2i(way.y, way.x)
			var before := c - way * 2
			var after := c + way * 2
			if not (map.walkable(before.x, before.y) and map.walkable((c - way).x, (c - way).y) and map.walkable(after.x, after.y)
					and map.walkable((c + way).x, (c + way).y)):
				continue
			if map.door_at(before.x, before.y) >= 0 or map.door_at((c - way).x, (c - way).y) >= 0:
				continue
			# a whole-tile walker gets through here: so must a quarter one that starts off line
			var whole := Mover.State.new()
			whole.place(before.x, before.y)
			whole.access = Net.ACCESS_ALL
			whole.dir = Net.dir_of(way.x, way.y)
			var table := Doors.new()
			table.copy_from(server.doors)
			for t in range(1, 80):
				Mover.step(whole, map, table, t)
			if Vector2i(whole.x, whole.y) != after:
				continue
			for s: int in [-1, 1]:
				var beside := before + side * s
				var beside2 := c - way + side * s
				if not map.walkable(beside.x, beside.y) or not map.walkable(beside2.x, beside2.y) or map.door_at(beside.x, beside.y) >= 0 \
						or map.door_at(beside2.x, beside2.y) >= 0:
					continue
				var st := Mover.State.new()
				st.place(before.x, before.y)
				st.fine = true
				st.access = Net.ACCESS_ALL
				if way.x != 0:
					st.oy = s
				else:
					st.ox = s
				st.dir = Net.dir_of(way.x, way.y)
				var table2 := Doors.new()
				table2.copy_from(server.doors)
				var in_line := true
				for t in range(1, 120):
					Mover.step(st, map, table2, t)
					if map.door_at(st.x, st.y) == d and (st.ox if way.y != 0 else st.oy) != 0:
						in_line = false
				tried += 1
				if Vector2i(st.x, st.y) == after and in_line:
					through += 1
	_expect(tried > 4, "doorways tried from a quarter off (%d)" % tried)
	_expect(through == tried, "every one slid into line and went through (%d of %d)" % [through, tried])


func _plain_door() -> int:
	var map = server.map
	for d in map.doors.size():
		var c: Vector2i = map.doors[d]
		if server.doors.partner[d] < 0 and map.walkable(c.x - 1, c.y) and map.walkable(c.x + 1, c.y) \
				and map.walkable(c.x - 3, c.y) and map.door_at(c.x - 1, c.y) < 0 and map.on_ship(c.y * map.width + c.x):
			return d
	return -1


func _door_held() -> void:
	print("  -- a door does not shut on a body half in its doorway")
	var d := _plain_door()
	_expect(d >= 0, "a plain door with floor on both sides")
	if d < 0:
		return
	var c: Vector2i = server.map.doors[d]
	var p = _player("Порог", Vector2i(c.x - 1, c.y))
	p.st.access = Net.ACCESS_ALL
	p.st.dir = Net.DIR_RIGHT
	var ticks := 0
	while p.st.ox < 1 and ticks < 60:
		server._tick()
		ticks += 1
	p.st.dir = Net.DIR_NONE
	_expect(p.st.x == c.x - 1 and p.st.ox == 1, "it stands a quarter into the doorway (%d %+d)" % [p.st.x, p.st.ox])
	for i in Doors.HOLD_TICKS + 40:
		server._tick()
	_expect(server.doors.ready[d] != Doors.CLOSED, "the door is still open after %d ticks" % (Doors.HOLD_TICKS + 40))
	p.st.place(c.x - 3, c.y)
	for i in Doors.HOLD_TICKS + 40:
		server._tick()
	_expect(server.doors.ready[d] == Doors.CLOSED, "and shuts once it has stepped back")
	p.st.place(c.x - 2, c.y + 0)


func _haul() -> void:
	print("  -- a body hauled by a quarter-stepper follows by whole tiles")
	var at := _open_row(6)
	var p = _player("Тащит", Vector2i(at.x + 1, at.y))
	var body = _player("Груз", Vector2i(at.x, at.y))
	body.cond = Net.COND_DEAD
	body.health = 0.0
	body.st.down = true
	p.dragging = body.slot
	body.dragged_by = p.slot
	p.st.slow = true
	body.st.slow = true
	p.st.dir = Net.DIR_RIGHT
	server._tick()
	server._tick()
	_expect(p.st.x == at.x + 1 and p.st.ox == 1 and body.st.x == at.x, "a quarter on (slowly): the body stays (%d %+d, body %d)" % [p.st.x, p.st.ox, body.st.x])
	server._tick()
	server._tick()
	_expect(p.st.x == at.x + 2 and body.st.x == at.x + 1 and body.st.ox == 0, "half way into the next tile: the body takes the tile left (%d, body %d)" % [p.st.x, body.st.x])
	for i in 8:
		server._tick()
	_expect(p.dragging == body.slot and body.st.x == p.st.x - 1, "still hauling, one tile behind (%d, body %d)" % [p.st.x, body.st.x])
	p.st.dir = Net.DIR_NONE
	server.looting.let_go(p)
	body.st.place(at.x + 5, at.y + 1)
	p.st.place(at.x, at.y + 1)


func _lying() -> void:
	print("  -- lying down: crawling at half speed, shots fly over unless aimed at")
	var st := Mover.State.new()
	var at := _open_row(6)
	st.place(at.x, at.y)
	st.fine = true
	Mover.apply_input(st, Mover.LIE)
	_expect(st.prone, "LIE lays it down")
	st.dir = Net.DIR_RIGHT
	var table := Doors.new()
	table.copy_from(server.doors)
	var ticks := 0
	while st.qx() < at.x * 4 + 8 and ticks < 60:
		Mover.step(st, server.map, table, 100 + ticks)
		ticks += 1
	_expect(ticks >= 2 * 2 * Net.MOVE_TICKS - 1 and ticks <= 2 * 2 * Net.MOVE_TICKS, "two tiles take twice as long (%d ticks)" % ticks)
	# (v82, his crawl video) getting up takes a second: still lying, no step, C again stays down
	Mover.apply_input(st, Mover.RISE)
	_expect(st.prone and st.rise == Mover.RISE_TICKS, "RISE starts getting up")
	var stood_at := st.qx()
	for k in 5:
		Mover.step(st, server.map, table, 200 + k)
	_expect(st.prone and st.qx() == stood_at, "getting up it does not walk")
	Mover.apply_input(st, Mover.LIE)
	_expect(st.prone and st.rise == 0, "LIE while getting up stays down")
	Mover.apply_input(st, Mover.RISE)
	st.dir = 0
	for k in Mover.RISE_TICKS:
		Mover.step(st, server.map, table, 300 + k)
	_expect(not st.prone and st.rise == 0, "RISE gets it up after a second")
	st.place(at.x, at.y)
	st.prone = true
	st.place(at.x, at.y)
	_expect(not st.prone, "a new place (a ladder, coming back) stands it up")
	# on the server
	var shooter = _player("Стрелок", at)
	shooter.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	shooter.hand = 0
	var low = server.pirates.spawn(at.x + 2, at.y, false)
	var high = server.pirates.spawn(at.x + 4, at.y, false)
	for q in [low, high]:
		q.health = 100.0
		q.wounds = 0.0
	low.st.prone = true
	server.combat.use_at(shooter, server.tick, Vector2(at.x + 4, at.y))
	_expect(low.health == 100.0 and high.health < 100.0, "a shot past one lying low hits the one behind (%.0f, %.0f)" % [low.health, high.health])
	shooter.ready_tick = 0
	server.combat.use_at(shooter, server.tick, Vector2(at.x + 2, at.y))
	_expect(low.health < 100.0, "aimed at the one lying low, it hits (%.0f)" % low.health)
	for q in [low, high]:
		q.st.place(at.x + 5, at.y + 1)
		q.health = 0.0
		q.cond = Net.COND_DEAD
		q.corpse = true
	shooter.st.place(at.x - 1, at.y + 1)


func _friendly_fire() -> void:
	print("  -- friendly fire as in RimWorld: a friend right by the shooter is never hit")
	var at := _open_row(6)
	var a = _player("Стрелок 2", at)
	a.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	a.hand = 0
	var friend = _player("Рядом", Vector2i(at.x + 1, at.y))
	var foe = server.pirates.spawn(at.x + 4, at.y, false)
	foe.health = 100.0
	foe.wounds = 0.0
	server.combat.use_at(a, server.tick, Vector2(at.x + 4, at.y))
	_expect(friend.health == 100.0 and foe.health < 100.0, "from behind a friend at its side: the friend is spared, the foe hit (%.0f, %.0f)" % [friend.health, foe.health])
	friend.st.place(at.x + 1, at.y + 1)
	friend.st.oy = -1
	a.ready_tick = 0
	foe.health = 100.0
	server.combat.use_at(a, server.tick, Vector2(at.x + 4, at.y))
	_expect(friend.health == 100.0 and foe.health < 100.0, "a friend a slant away and a quarter in the line: spared too")
	friend.st.place(at.x + 2, at.y)
	a.ready_tick = 0
	foe.health = 100.0
	server.combat.use_at(a, server.tick, Vector2(at.x + 4, at.y))
	_expect(friend.health < 100.0 and foe.health == 100.0, "a friend two tiles on in the line is hit (%.0f)" % friend.health)
	friend.health = 100.0
	friend.wounds = 0.0
	# the other way round: a pirate shooting at one of ours right beside it does hit
	foe.st.place(at.x, at.y + 1)
	foe.slots[foe.hand] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	foe.ready_tick = 0
	a.st.place(at.x + 1, at.y + 1)
	a.health = 100.0
	a.wounds = 0.0
	server.combat.use_at(foe, server.tick, Vector2(at.x + 1, at.y + 1))
	_expect(a.health < 100.0, "a foe right by the shooter is not spared (%.0f)" % a.health)
	# a shot from a player a quarter off its tile starts where it is drawn
	friend.st.place(at.x + 5, at.y)
	a.st.place(at.x, at.y)
	a.st.oy = 1
	foe.st.place(at.x + 4, at.y)
	foe.health = 100.0
	a.ready_tick = 0
	server.combat.use_at(a, server.tick, Vector2(at.x + 4, at.y + 0.25))
	_expect(foe.health < 100.0, "a shot along the drawn line still finds its mark (%.0f)" % foe.health)


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
