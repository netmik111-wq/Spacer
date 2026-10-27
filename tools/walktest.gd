extends SceneTree
## Checks v74's walking on a slant (the author's N2, N3): 8 ways, a slant step 1.4 times
## a straight one, no cutting corners or crossing doorways on a slant, sliding along a
## wall, hauling goes straight, facing and using things on a slant, sight on a slant,
## and the look byte that carries 8 facings. On a real server stepped by hand:
##   godot --headless --path . --script res://tools/walktest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Sight := preload("res://src/shared/sight.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26431, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	_rules()
	_step_time()
	_corners()
	_on_server()
	_use_and_sight()
	_look_byte()
	print("walktest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _open_cell() -> Vector2i:
	## A floor cell x,y with open floor (no doorway, no wall) from x - 1 to x + 2 across, on its
	## row and the one below (the ship's rooms are two cells high).
	var map = server.map
	for y in map.height:
		for x in map.width:
			if not map.on_ship(y * map.width + x):
				continue
			var ok := true
			for dy in range(0, 2):
				for dx in range(-1, 3):
					ok = ok and map.walkable(x + dx, y + dy) and map.door_at(x + dx, y + dy) < 0
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _rules() -> void:
	print("  -- the directions")
	_expect(Net.DIRS == 8 and Net.DX.size() == 9 and Net.DY.size() == 9, "8 ways")
	var all := {}
	for d in range(1, Net.DIRS + 1):
		all[Vector2i(Net.DX[d], Net.DY[d])] = d
		_expect(Net.dir_of(Net.DX[d], Net.DY[d]) == d, "dir_of gives %d back" % d)
		_expect(absf(Net.way(d).length() - 1.0) < 0.001, "way %d is of length 1" % d)
	_expect(all.size() == 8, "each way different")
	_expect(not Net.diagonal(Net.DIR_LEFT) and Net.diagonal(Net.DIR_DOWN_RIGHT), "which are slants")


func _step_time() -> void:
	print("  -- a slant step takes 1.4 times a straight one (on average, ticks being whole)")
	var sum := 0
	var sum_drag := 0
	for t in 1000:
		var s := Mover.slant_span(Net.MOVE_TICKS, t)
		if s != 5 and s != 6:
			_expect(false, "4 ticks straight -> 5 or 6 on a slant (tick %d: %d)" % [t, s])
		sum += s
		sum_drag += Mover.slant_span(Net.DRAG_TICKS, t)
	_expect(absf(sum / 1000.0 - Net.MOVE_TICKS * 1.4) < 0.001, "on average 5.6 ticks (%.3f)" % (sum / 1000.0))
	_expect(absf(sum_drag / 1000.0 - Net.DRAG_TICKS * 1.4) < 0.001, "slow going: on average 11.2 (%.3f)" % (sum_drag / 1000.0))
	var map = server.map
	var at := _open_cell()
	_expect(at.x >= 0, "an open spot of floor (%s)" % at)
	var st := Mover.State.new()
	st.place(at.x, at.y)
	st.dir = Net.DIR_DOWN_RIGHT
	var stepped := Mover.step(st, map, server.doors, 100)
	_expect(stepped and st.x == at.x + 1 and st.y == at.y + 1, "a step down and right lands on the slant")
	_expect(st.facing == Net.DIR_DOWN_RIGHT, "it faces the way it walks")
	_expect(st.span == Mover.slant_span(Net.MOVE_TICKS, 100) and st.cd == st.span, "the step lasts its slant time")
	var pos := Mover.visual_pos(st, 100 + st.span * 0.5)
	_expect(pos.distance_to(Vector2(at.x + 0.5, at.y + 0.5)) < 0.01, "drawn half way along the slant mid-step")
	var st2 := Mover.State.new()
	st2.place(at.x + 1, at.y + 1)
	st2.dir = Net.DIR_UP_LEFT
	Mover.step(st2, map, server.doors, 200)
	_expect(st2.x == at.x and st2.y == at.y, "up and left too")
	var first := st2.span
	st2.dir = Net.DIR_DOWN_RIGHT
	var ticks := 1
	while st2.x == at.x and ticks < 30:
		Mover.step(st2, map, server.doors, 200 + ticks)
		ticks += 1
	_expect(st2.x == at.x + 1 and st2.y == at.y + 1 and ticks - 1 == first, "and back again once that step is done (%d ticks)" % first)
	var hauler := Mover.State.new()
	hauler.place(at.x, at.y)
	hauler.slow = true
	hauler.dir = Net.DIR_DOWN_RIGHT
	Mover.step(hauler, map, server.doors, 300)
	_expect(hauler.y == at.y and hauler.x == at.x + 1, "somebody hauling goes straight (across first), so the body follows")


func _corners() -> void:
	print("  -- no cutting corners, no doorways on a slant, sliding along a wall")
	var map = server.map
	var cut := 0
	var doorway := 0
	var slid := 0
	var tried := 0
	for y in map.height:
		for x in map.width:
			if not map.walkable(x, y) or not map.on_ship(y * map.width + x):
				continue
			for d in range(Net.DIR_UP_LEFT, Net.DIRS + 1):
				var dx: int = Net.DX[d]
				var dy: int = Net.DY[d]
				if map.stair_to[y * map.width + x] >= 0 or map.stair_to[(y + dy) * map.width + x + dx] >= 0:
					continue                 # (v91) a step onto the stairs' far end comes out on the other deck
				var st := Mover.State.new()
				st.place(x, y)
				st.dir = d
				st.access = Net.ACCESS_ALL
				tried += 1
				if not Mover.step(st, map, server.doors, 7):
					continue
				var moved := Vector2i(st.x - x, st.y - y)
				if moved == Vector2i(dx, dy):
					if not map.passable(x + dx, y) or not map.passable(x, y + dy):
						cut += 1
					if map.door_at(x, y) >= 0 or map.door_at(st.x, st.y) >= 0 or map.door_at(x + dx, y) >= 0 or map.door_at(x, y + dy) >= 0:
						doorway += 1
				elif moved == Vector2i(dx, 0) or moved == Vector2i(0, dy):
					slid += 1
				else:
					cut += 1
	_expect(tried > 100, "every floor cell tried each slant (%d)" % tried)
	_expect(cut == 0, "no slant step cuts a corner past a wall (%d did)" % cut)
	_expect(doorway == 0, "no slant step goes into, out of or past a doorway (%d did)" % doorway)
	_expect(slid > 0, "held against a wall, a slant slides along it (%d times)" % slid)


func _on_server() -> void:
	print("  -- a player walks on a slant on the server, and the client's copy of the rule agrees")
	var p = server.crew.new_player("Ходок")
	var at := _open_cell()
	p.st.place(at.x + 1, at.y)
	p.st.dir = Net.DIR_DOWN_LEFT
	for i in 3:
		server._tick()
	_expect(p.st.x == at.x and p.st.y == at.y + 1, "one step down and left")
	_expect(p.st.facing == Net.DIR_DOWN_LEFT, "facing that way")
	var shadow := Mover.State.new()
	shadow.place(at.x, at.y)
	var real := Mover.State.new()
	real.copy_from(p.st)
	_expect(real.same_as(p.st), "the state copies whole")
	p.st.dir = Net.DIR_NONE
	# the input range the server takes: 8 ways and 8 turns
	_expect(Mover.TURN > Net.DIRS, "a turn is never mistaken for a step")
	Mover.apply_input(shadow, Mover.TURN + Net.DIR_UP_RIGHT)
	_expect(shadow.facing == Net.DIR_UP_RIGHT and shadow.dir == 0, "a turn to a slant only turns")
	Mover.apply_input(shadow, Net.DIR_DOWN_RIGHT)
	_expect(shadow.dir == Net.DIR_DOWN_RIGHT, "a slant is a step")


func _use_and_sight() -> void:
	print("  -- facing on a slant: using things and seeing")
	var map = server.map
	# a console fitted in a wall, and a cell beside its front from where it is on a slant
	var found := false
	for c: int in map.helm.keys() + map.gun_console.keys() + map.holo.keys():
		var front: int = map.fitting_front(c)
		if front < 0:
			continue
		var fx: int = front % map.width
		var fy: int = front / map.width
		var wx: int = c % map.width
		var wy: int = c / map.width
		# from the front cell, face on a slant towards the wall side: the console beside is reached
		var sx := wx - fx
		var sy := wy - fy
		for side in [-1, 1]:
			var d := Net.dir_of(sx if sx != 0 else side, sy if sy != 0 else side)
			if Net.diagonal(d):
				var got: int = map.use_ahead(fx, fy, d)
				_expect(got == c, "facing on a slant at a wall, the console right beside is used (%s got %d)" % [map.device_name(c), got])
				found = true
				break
		if found:
			break
	_expect(found, "a console to try")
	var at := _open_cell()
	var cell: int = (at.y + 1) * map.width + at.x + 1
	_expect(map.use_ahead(at.x, at.y, Net.DIR_DOWN_RIGHT) == cell, "on open floor, the cell on the slant (a thing lying there)")
	var arcs := Sight.eye_arcs(false)
	var from := Vector2(at.x, at.y)
	_expect(Sight.sees(map, server.doors, from, Net.DIR_DOWN_RIGHT, Vector2i(at.x + 1, at.y + 1), arcs, Sight.SIGHT_REACH), "sight on a slant sees ahead")
	_expect(not Sight.sees(map, server.doors, from, Net.DIR_DOWN_RIGHT, Vector2i(at.x - 1, at.y), arcs, Sight.SIGHT_REACH), "but not behind")
	var cone := Sight.cone(map, server.doors, from, Net.DIR_DOWN_RIGHT, 60.0, 4)
	_expect(cone.has(cell) and not cone.has(at.y * map.width + at.x - 1), "a flashlight on a slant lights ahead, not behind")


func _look_byte() -> void:
	print("  -- the look byte carries 8 facings next to the other marks")
	var bad := 0
	for f in range(1, Net.DIRS + 1):
		for light in [false, true]:
			for slow in [false, true]:
				var look := Net.pack_look(f, Net.COND_DEAD, slow, light)
				if not (look < 256 and Net.look_facing(look) == f and Net.look_light(look) == light and Net.look_slow(look) == slow \
						and Net.look_cond(look) == Net.COND_DEAD):
					_expect(false, "facing %d light %s slow %s comes back" % [f, light, slow])
					bad += 1
	_expect(bad == 0, "all facings, lights and slow steps come back")


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
