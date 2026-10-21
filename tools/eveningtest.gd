extends SceneTree
## Checks build v77 (the author's evening of play with KaineQwQ, and his answers on the
## view and on bots walking), on a real server, with real clients for the rejoin:
##   godot --headless --path . --script res://tools/eveningtest.gd
## A trader never sells what it looks for (no buy low, sell high); a wreck sent away for a
## jump does not come straight back (no chat spam); the same name from the same address
## takes its own character back at once (no "Name 2"), and one saved out in space comes
## back aboard; the SOS ship whose crew died comes alongside, with its dead, and stays
## while we do; looking with the mouse, walking does not turn one; bots and pirates find
## ways on a slant, never across a corner or a doorway.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Mover := preload("res://src/shared/mover.gd")
const Paths := preload("res://src/server/paths.gd")
const Campaign := preload("res://src/server/campaign.gd")

const PORT := 26880

var failed := 0
var server: GameServer
var said: Array = []                 # every line the server logged


func _initialize() -> void:
	_go()


func _go() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(PORT, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	server.stations.volunteers = false
	server.log_line.connect(func(t: String) -> void: said.append(t))
	_trader()
	_wreck_and_jump()
	_saved_in_space()
	_sos()
	_free_look()
	_slants()
	_pirates_slant()
	_bot_walks_slant()
	await _rejoin()
	await _mouse_spin()
	server.stop()
	server.free()
	print("eveningtest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for t in ticks:
		server.ship.hull = server.ship.hull_max
		server._tick()


func _calm() -> void:
	if server.derelict.here:
		server.derelict._leave(true)
	server.gunnery.enemy_gone()
	for q in server.players:
		if q != null and (q.pirate or q.corpse):
			server.crew.remove(q)
	server.road._fight = {}
	server.road.hunters = []
	server.road.hulks = {}
	server.derelict.held_off_until = -1
	server.ship.moving = false
	server.ship.jump_to = Net.NO_SECTOR
	_run(2)


func _said(from: int, part: String) -> int:
	## How many lines said to everyone since `from` (an index into the log) hold `part`.
	var n := 0
	for i in range(from, said.size()):
		if str(said[i]).contains(part):
			n += 1
	return n


# --------------------------------------------------------------- the trader

func _trader() -> void:
	print("  -- a trader never sells what it looks for (the author's T1)")
	var s: Sectors = server.sectors
	var sys: int = server.ship.sector
	var was: int = s.kind[sys]
	s.kind[sys] = Sectors.TRADER
	server.ship.in_reach = true
	server.supplies._offers_for = -1
	var w: PackedByteArray = server.supplies.wanted()
	var offers: Dictionary = server.supplies.offers()
	var loop := false
	for item in w:
		if offers.has(item) and int(offers[item]) < server.supplies.sell_price(item):
			loop = true
	_expect(w.size() == 2 and not offers.has(w[0]) and not offers.has(w[1]), "what it looks for is not on its shelf (%s)" % str(w))
	_expect(not loop, "so nothing is bought cheaper than it sells")
	var plain := 0
	for item: int in offers.keys():
		if item is int and server.supplies.sell_price(item) > int(offers[item]):
			plain += 1
	_expect(plain == 0, "nothing it sells is bought back dearer")
	s.kind[sys] = was
	server.supplies._offers_for = -1


# --------------------------------------------------------------- the wreck and the jump

func _wreck_and_jump() -> void:
	print("  -- a wreck left for a jump stays away (the author's note: chat spam)")
	_calm()
	server.ship.pos = Vector2(100, 100)
	server.derelict.pirates_come(server.director._party(), true)
	_run(2)
	server.gunnery._wrecked()
	_run(2)
	for q in server.players:
		if q != null and q.pirate and not q.corpse:
			server.crew.remove(q)            # (nobody left aboard to hold it)
	_expect(server.derelict.here and server.derelict.wreck, "a raider wrecked stays alongside")
	var from: int = said.size()
	server.ship.jump_to = server.ship.sector
	server.ship.jump_tick = server.tick + 100000
	_run(40)
	_expect(not server.derelict.here, "with the jump charging it is left behind")
	_expect(_said(from, "Рядом") == 0 and _said(from, "остался позади") <= 1,
		"once, not again and again (%d lines «Рядом», %d «позади»)" % [_said(from, "Рядом"), _said(from, "остался позади")])
	server.ship.jump_to = Net.NO_SECTOR
	_run(2)
	_expect(server.derelict.here and server.derelict.wreck, "the jump called off, it is alongside again")
	var line := ""
	for i in range(from, said.size()):
		if str(said[i]).begins_with("[корабль] Рядом"):
			line = str(said[i])
	_expect(line.contains(server.derelict.ship.name.substr(1)), "its name is said whole: %s" % line)
	_calm()


# --------------------------------------------------------------- saved in space

func _saved_in_space() -> void:
	print("  -- a character saved out where a ship was comes back aboard")
	_calm()
	var p = server.crew.new_player("Космонавт")
	var map = server.map
	var space := -1
	for c in map.cells.size():
		if map.floats(c % map.width, c / map.width):
			space = c
			break
	p.st.place(space % map.width, space / map.width)
	var c: Dictionary = Campaign.character(p)
	server.crew.remove(p)
	var q = server.crew.new_player("Космонавт")
	server.crew.restore_character(q, c)
	_expect(map.on_ship(q.st.y * map.width + q.st.x), "back aboard, not afloat (%d,%d)" % [q.st.x, q.st.y])
	server.crew.remove(q)


# --------------------------------------------------------------- the SOS ship

func _sos() -> void:
	print("  -- the SOS ship whose crew died comes alongside (the author's S1)")
	_calm()
	var bodies_before := 0
	for q in server.players:
		if q != null and q.corpse:
			bodies_before += 1
	server.story._apply({"sos_ship": 1})
	_run(2)
	var d = server.derelict
	var bodies := 0
	var things := 0
	for q in server.players:
		if q != null and q.corpse and server.map.is_other(q.st.y * server.map.width + q.st.x):
			bodies += 1
			for k in Net.SLOTS:
				if q.slots[k] != Net.ITEM_NONE:
					things += 1
	_expect(d.here and d.sos and d.kind == Net.OTHER_DERELICT, "a dark ship lies alongside")
	_expect(bodies == d.SOS_BODIES and things >= bodies, "with %d dead aboard, something in their pockets (%d things)" % [bodies, things])
	_run(60)
	_expect(d.here, "it stays while our ship stays")
	server.ship.pos += Vector2(Sectors.WRECK_REACH + 5, 0)
	_run(2)
	var left := 0
	for q in server.players:
		if q != null and q.corpse:
			left += 1
	_expect(not d.here and not d.sos and left == bodies_before, "flown away from, it is left behind with its dead")
	server.ship.pos -= Vector2(Sectors.WRECK_REACH + 5, 0)
	_run(2)
	_expect(not d.here, "and does not come back by itself")
	_calm()


# --------------------------------------------------------------- free look

func _free_look() -> void:
	print("  -- looking with the mouse, walking does not turn one (the author's V1)")
	var map = server.map
	var p = server.crew.new_player("Глаза")
	var st: Mover.State = p.st
	var at: Vector2i = server.crew.spawn_point()
	st.place(at.x, at.y)
	Mover.apply_input(st, Mover.LOOK_FREE)
	Mover.apply_input(st, Mover.TURN + Net.DIR_UP)
	var d := Net.DIR_NONE
	for k in range(1, 5):
		if map.walkable(at.x + Net.DX[k], at.y + Net.DY[k]) and k != Net.DIR_UP:
			d = k
			break
	Mover.apply_input(st, d)
	var moved := false
	for t in 10:
		moved = Mover.step(st, map, server.doors, server.tick + t) or moved
	_expect(moved and st.facing == Net.DIR_UP, "it walks %d and still looks up (facing %d)" % [d, st.facing])
	Mover.apply_input(st, Mover.LOOK_WALK)
	Mover.step(st, map, server.doors, server.tick + 20)
	_expect(st.facing == d, "looking where one walks again, it turns that way")
	server.crew.remove(p)


# --------------------------------------------------------------- slants

func _open_square() -> int:
	## The top left cell of a patch of our ship's open floor 3 across and 2 down (no doors; rooms are 2 high).
	var map = server.map
	var w: int = map.width
	for c in map.cells.size():
		var x: int = c % w
		var y: int = c / w
		var ok := true
		for dy in range(0, 2):
			for dx in range(0, 3):
				var j := (y + dy) * w + x + dx
				if not map.walkable(x + dx, y + dy) or not map.on_ship(j) or map.door_of[j] >= 0 or map.deck_of(y + dy) != map.deck_of(y):
					ok = false
		if ok:
			return c
	return -1


func _slants() -> void:
	print("  -- ways on a slant (the author's B1)")
	var map = server.map
	var w: int = map.width
	var c := _open_square()
	_expect(c >= 0, "an open patch of floor to try in")
	if c < 0:
		return
	var anywhere := func(nx: int, ny: int) -> bool: return map.walkable(nx, ny) and map.on_ship(ny * w + nx)
	var r: Array = Paths.first_step(map, c, {c + w + 1: 0}, anywhere)
	_expect(int(r[0]) == Net.dir_of(1, 1), "one down and one right: a step down-right (%d)" % int(r[0]))
	r = Paths.first_step(map, c, {c + 2: 0}, anywhere)
	_expect(int(r[0]) == Net.DIR_RIGHT, "two right: straight right, no zigzag (%d)" % int(r[0]))
	# never across a corner: with the cell beside the way shut, the slant is not taken
	var shut := c + 1
	var no_corner := func(nx: int, ny: int) -> bool: return ny * w + nx != shut and map.walkable(nx, ny) and map.on_ship(ny * w + nx)
	r = Paths.first_step(map, c, {c + w + 1: 0}, no_corner)
	_expect(int(r[0]) == Net.DIR_DOWN, "a corner in the way: down first, then right (%d)" % int(r[0]))
	# never on a slant into or out of a doorway
	var bad := 0
	for d in map.doors.size():
		var at: Vector2i = map.doors[d]
		var door := at.y * w + at.x
		for k in range(5, Net.DIRS + 1):
			var from := (at.y - Net.DY[k]) * w + at.x - Net.DX[k]
			if map.walkable(from % w, from / w):
				var r2: Array = Paths.first_step(map, from, {door: 0}, anywhere)
				if int(r2[0]) > 4:
					bad += 1
	_expect(bad == 0, "no doorway is entered on a slant (%d)" % bad)


func _pirates_slant() -> void:
	print("  -- a pirate takes the slant too")
	var map = server.map
	var w: int = map.width
	var c := _open_square()
	if c < 0:
		return
	var pir = server.pirates.spawn(c % w, c / w, false)
	pir.st.place(c % w + 1, c / w + 1)
	var step: int = server.pirates._first_step(pir, Vector2i(c % w, c / w))
	_expect(step == Net.dir_of(-1, -1), "one up and one left: up-left (%d)" % step)
	server.crew.remove(pir)


func _bot_walks_slant() -> void:
	print("  -- a bot walks there on a slant")
	_calm()
	var map = server.map
	var w: int = map.width
	var c := _open_square()
	if c < 0:
		return
	server.crew.add_bot()
	var bot = null
	for q in server.players:
		if q != null and q.bot and not q.corpse:
			bot = q
	bot.st.place(c % w, c / w)
	bot.order = Net.POST_FREE
	var goal := c + w + 2
	var slanted := 0
	for t in 120:
		var r: Array = server.stations._route(bot.st.y * w + bot.st.x, {goal: 0})
		if int(r[1]) < 0:
			break
		bot.st.dir = int(r[0])
		bot.bot_until = server.tick + 1000
		var was: Vector2i = Vector2i(bot.st.x, bot.st.y)
		server.movement.move(bot)
		server.tick += 1
		if Vector2i(bot.st.x, bot.st.y) != was and bot.st.x != was.x and bot.st.y != was.y:
			slanted += 1
		if bot.st.y * w + bot.st.x == goal:
			break
	_expect(bot.st.y * w + bot.st.x == goal and slanted == 1, "one slant step and one straight to a cell one down and two across (%d)" % slanted)
	server.crew.remove(bot)


# --------------------------------------------------------------- the rejoin

func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until_playing(c: GameClient) -> void:
	var until := Time.get_ticks_msec() + 8000
	while c.phase != GameClient.PLAYING and Time.get_ticks_msec() < until:
		await process_frame


func _rejoin() -> void:
	print("  -- back after a lag drop: the same character (the author's R1)")
	_calm()
	var a := GameClient.new()
	get_root().add_child(a)
	a.connect_to("127.0.0.1", PORT, "Кайн")
	await _until_playing(a)
	_expect(a.phase == GameClient.PLAYING, "the first link joins")
	if a.phase != GameClient.PLAYING:
		return
	var id := a.my_id
	var p = server.players[id]
	p.slots[2] = Net.ITEM_PART
	# the link dies without a word: the server would not notice for 12 s
	get_root().remove_child(a)
	a.free()
	await _frames(5)
	var b := GameClient.new()
	get_root().add_child(b)
	b.connect_to("127.0.0.1", PORT, "Кайн")
	await _until_playing(b)
	var names := []
	for q in server.players:
		if q != null and not q.bot and not q.pirate and not q.corpse:
			names.append(q.name)
	_expect(b.phase == GameClient.PLAYING and b.my_id == id, "the second link joins as the same character (id %d, was %d)" % [b.my_id, id])
	_expect(names == ["Кайн"], "nobody named «Кайн 2»: %s" % str(names))
	var q = server.players[b.my_id]
	_expect(q != null and q.slots[2] == Net.ITEM_PART, "with what was in its pockets")
	b.close()
	get_root().remove_child(b)
	b.free()
	await _frames(5)


func _mouse_spin() -> void:
	print("  -- the mouse swept round many times a tick: one still walks and turns (v77.1, the author's bug)")
	_calm()
	var c := GameClient.new()
	get_root().add_child(c)
	c.connect_to("127.0.0.1", PORT, "Мышь")
	await _until_playing(c)
	_expect(c.phase == GameClient.PLAYING, "the link joins")
	if c.phase != GameClient.PLAYING:
		return
	c.want_free_look = true
	var p = server.players[c.my_id]
	var ways := {}
	var cells := {}
	var worst := 0
	var until := Time.get_ticks_msec() + 4000
	var k := 0                    # frames
	while Time.get_ticks_msec() < until:
		# a fast game draws many frames a tick, the mouse spinning round twice a second
		k += 1
		var me := Vector2(c.pred.x, c.pred.y)
		c.aim_at(me + Vector2.from_angle(Time.get_ticks_msec() * 0.012) * 4.0, 1.0 / 144.0)
		c.want_dir = Net.DIR_LEFT if (Time.get_ticks_msec() / 700) % 2 == 0 else Net.DIR_RIGHT
		ways[p.st.facing] = true
		cells[Vector2i(p.st.x, p.st.y)] = true
		worst = maxi(worst, c._last_apply - c.pred_tick)
		await process_frame
	c.want_dir = 0
	_expect(worst < 6, "the queued inputs stay close to now (at most %d ticks ahead, %d frames)" % [worst, k])
	_expect(ways.size() >= 4, "the server turned it many ways (%d)" % ways.size())
	_expect(cells.size() >= 3, "and it walked (%d cells)" % cells.size())
	c.close()
	get_root().remove_child(c)
	c.free()
	await _frames(5)


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		failed += 1
		print("FAIL ", what)
