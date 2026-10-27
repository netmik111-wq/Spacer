extends SceneTree
## Checks build v91 (the author's tile set answers), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/windowtest.gd
## Machines stand on the floor: nobody walks through one, sight passes over it, and it is used
## from its front only. Every window of ours has a shutter: a hole torn in a window lets the air
## out for a moment, then its shutter shuts over it and the room keeps its air until the hole is
## mended; at red alert every shutter is down; a shutter down stops sight as a wall does; without
## power none moves. Clients are told: 2 a hole behind a shutter, 3 a shutter down.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Sight := preload("res://src/shared/sight.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26640, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	server.stations.volunteers = false       # nobody mends the window by himself
	_machines()
	_broken_window()
	_red_alert()
	_no_power()
	_boxes()
	server.stop()
	server.free()
	print("windowtest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for t in ticks:
		server.ship.hull = server.ship.hull_max
		server._tick()


func _machines() -> void:
	print("  -- machines on the floor")
	var map := server.map
	var helm: int = map.helm.keys()[0]
	_expect(map.on_floor.has(helm) and map.walk[helm] == 0 and map.opaque[helm] == 0,
		"the helm stands on the floor: nobody walks through it, sight passes over it")
	var front := map.fitting_front(helm)
	_expect(front >= 0 and map.walk[front] == 1, "it has a floor cell in front of it")
	var f := Vector2i(front % map.width, front / map.width)
	var h := Vector2i(helm % map.width, helm / map.width)
	var facing := Net.dir_of(h.x - f.x, h.y - f.y)
	_expect(map.use_ahead(f.x, f.y, facing, {}) == map.machine_of(helm), "it is used from its front")
	var behind := helm - (front - helm)
	if behind >= 0 and behind < map.walk.size() and map.walk[behind] == 1:
		_expect(map.use_ahead(behind % map.width, behind / map.width, Net.dir_of(f.x - h.x, f.y - h.y), {}) != map.machine_of(helm),
			"not from behind")
	# every wide machine is one: each piece of it is used as its first
	var wide := 0
	for root: int in map.pieces.keys():
		for c: int in map.pieces[root]:
			if map.machine_of(c) != root:
				wide = -1000
		wide += 1
	_expect(wide > 3, "the wide machines' pieces all lead to their first (%d machines)" % wide)


func _pane_room(cell: int) -> int:
	## The floor cell inside next to a window.
	var map := server.map
	for o: int in [-map.width, map.width, -1, 1]:
		var c := cell + o
		if c >= 0 and c < map.walk.size() and map.walk[c] == 1:
			return c
	return -1


func _outer_pane() -> int:
	var map := server.map
	for c: int in map.panes:
		var x := c % map.width
		var y := c / map.width
		if map.hull.has(c) and _pane_room(c) >= 0 and (map.is_space(x, y - 1) or map.is_space(x, y + 1)):
			return c
	return -1


func _broken_window() -> void:
	print("  -- a broken window")
	var map := server.map
	_expect(map.panes.size() >= 6, "the ship has windows (%d)" % map.panes.size())
	var pane := _outer_pane()
	_expect(pane >= 0, "one of them looks onto space")
	if pane < 0:
		return
	var inside := _pane_room(pane)
	_run(4)
	var full := server.air.air[inside]
	server.systems.breach(pane)
	_expect(server.systems.pane_state(pane) == 1, "a hole in it is told as a hole while its shutter is still up")
	_run(Net.TICK_HZ / 2)
	_expect(server.air.air[inside] < full - 0.02, "for a moment the air goes out (%.2f -> %.2f)" % [full, server.air.air[inside]])
	_expect(not server.systems.panes_down.has(pane), "half a second on, its shutter is not down yet")
	_run(Net.TICK_HZ)
	_expect(server.systems.panes_down.has(pane) and server.air.sealed.has(pane), "a second on, its shutter shut over the hole")
	_expect(server.systems.pane_state(pane) == 2 and server.air.holes.has(pane), "the hole is still there, behind the shutter (told as 2)")
	_expect(map.opaque[pane] == 1, "the shutter stops sight")
	var low := server.air.air[inside]
	_run(Net.TICK_HZ * 5)
	_expect(server.air.air[inside] >= low - 0.001, "the room keeps its air (%.2f -> %.2f)" % [low, server.air.air[inside]])
	server.air.set_hole(pane, false)              # mended
	_run(4)
	_expect(not server.systems.panes_down.has(pane) and map.opaque[pane] == 0 and server.systems.pane_state(pane) == 0,
		"mended, the shutter goes up and the window lets sight through")


func _red_alert() -> void:
	print("  -- red alert")
	var map := server.map
	server.stations.set_alert(Net.ALERT_RED)
	_run(4)
	var down := 0
	for c: int in map.panes:
		if server.fleet.mine(c) and server.systems.panes_down.has(c) and map.opaque[c] == 1:
			down += 1
	_expect(down == map.panes.size(), "at red alert every shutter is down (%d of %d)" % [down, map.panes.size()])
	var pane := _outer_pane()
	var inside := _pane_room(pane)
	var x := pane % map.width
	var y := pane / map.width
	var out := Vector2i(x, y - 1) if map.is_space(x, y - 1) else Vector2i(x, y + 1)
	var beyond := out + (out - Vector2i(x, y)) * 2
	var from := Vector2i(inside % map.width, inside / map.width)
	_expect(not Sight.clear_cached(map, server.doors, from, beyond, server.replication.lines), "nobody sees out through a shutter")
	var full := server.air.air[inside]
	server.systems.breach(pane)
	_expect(server.air.sealed.has(pane) and server.systems.pane_state(pane) == 2, "a hit on a window behind its shutter lets no air out")
	_run(Net.TICK_HZ)
	_expect(server.air.air[inside] >= full - 0.001, "not even for a moment (%.2f -> %.2f)" % [full, server.air.air[inside]])
	server.air.set_hole(pane, false)
	server.stations.set_alert(Net.ALERT_GREEN)
	_run(4)
	_expect(server.systems.panes_down.is_empty(), "the alert over, every shutter goes up")
	_expect(Sight.clear_cached(map, server.doors, from, beyond, server.replication.lines), "and one sees out again")


func _no_power() -> void:
	print("  -- no power")
	server.ship.broken[server.map.engine.keys()[0]] = true
	server.power.set_charge(0.0)
	_run(Net.TICK_HZ)
	_expect(not server.powered(), "the ship is dark")
	var pane := _outer_pane()
	server.systems.breach(pane)
	_run(Net.TICK_HZ * 3)
	_expect(not server.systems.panes_down.has(pane), "without power a broken window's shutter does not shut")
	server.ship.broken.erase(server.map.engine.keys()[0])
	server.power.set_charge(1.0)
	_run(Net.TICK_HZ * 2)
	_expect(server.systems.panes_down.has(pane), "with power back it does")
	server.air.set_hole(pane, false)


func _boxes() -> void:
	print("  -- boxes on the walls")
	var map := server.map
	_expect(map.med_box.size() == 1 and map.tech_box.size() == 1, "the ship has a first-aid box and a spare parts box")
	var box: int = map.med_box.keys()[0]
	var front := map.fitting_front(box)
	_expect(front >= 0 and map.walk[front] == 1, "the first-aid box faces a floor cell")
	var p = server.crew.new_player("Тест")
	p.st.place(front % map.width, front / map.width)
	p.st.facing = Net.dir_of(box % map.width - front % map.width, box / map.width - front / map.width)
	for i in Net.SLOTS:
		p.slots[i] = Net.ITEM_NONE
	var kit := Net.ITEM_MEDKIT + Net.MEDKIT_USES
	server.ship.store[kit] = 2
	server.repairs.press(p)
	_expect(p.count(kit) == 1 and int(server.ship.store[kit]) == 1, "E at it takes a first-aid kit out of the locker's stock")
	p.hand = p.slots.find(kit)
	server.repairs.press(p)
	_expect(p.count(kit) == 0 and int(server.ship.store[kit]) == 2, "with the kit in hand, E puts it back")
	server.ship.store[kit] = 0
	server.repairs.press(p)
	_expect(p.count(kit) == 0, "with none in the locker the box is empty")
	var tech: int = map.tech_box.keys()[0]
	var by := map.fitting_front(tech)
	p.st.place(by % map.width, by / map.width)
	p.st.facing = Net.dir_of(tech % map.width - by % map.width, tech / map.width - by / map.width)
	server.ship.store[Net.ITEM_PART] = 1
	server.ship.store[Net.ITEM_BOARD] = 1
	server.repairs.press(p)
	p.hand = p.slots.find(Net.ITEM_NONE)        # (with the part in hand E would put it back)
	server.repairs.press(p)
	_expect(p.count(Net.ITEM_PART) == 1 and p.count(Net.ITEM_BOARD) == 1, "the spare parts box gives a part, then a circuit board")
	_expect(not map.hull.has(box) and not map.hull.has(tech), "no hole is ever torn in a box")
	server.crew.remove(p)


func _expect(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failed += 1
