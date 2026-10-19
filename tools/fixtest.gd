extends SceneTree
## Checks build v69 (the author's bug notes and two ideas), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/fixtest.gd
## A click anywhere on one's own cell treats oneself, and Z does too; the autodoc
## heals the worst off on its bed, and one standing there can tend another; things
## floating where a ship docks are pushed out of its walls; no docking under way;
## a wreck stays on the chart where it died (clear of other places) and comes back
## alongside; a hunter lets go of a derelict alongside, shells us while somebody is
## outside, and the next one waits a breather; a station sells but never buys;
## leaving a locked room is free and a broken lock stays broken until mended; one
## press of an airlock door's button opens it; each room's vent tops it up (not
## with a hole); the server sends those behind us too (the client hides them).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26610, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	_healing()
	_autodoc()
	_buried()
	_docking()
	_hulks()
	_hunters()
	_station()
	_locked_rooms()
	_airlock()
	_vents()
	_sight()
	server.stop()
	server.free()
	print("fixtest: %d failed" % failed)
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
		if q != null and q.pirate:
			server.crew.remove(q)
	server.road._fight = {}
	server.road.hunters = []
	server.road.hulks = {}
	server.road.busy_tick = -1000000
	server.derelict.held_off_until = -1
	server.ship.moving = false
	_run(2)


func _floor_spot(p) -> void:
	## A plain floor cell of our ship (the spawn point), standing still.
	var at: Vector2i = server.crew.spawn_point()
	p.st.place(at.x, at.y)
	p.st.dir = Net.DIR_NONE


# --------------------------------------------------------------- healing

func _healing() -> void:
	print("  -- a first-aid kit and a patch on oneself")
	var a := server.crew.new_player("Медик")
	_floor_spot(a)
	a.slots.fill(Net.ITEM_NONE)
	a.hand = 0
	a.slots[0] = Net.ITEM_MEDKIT + Net.MEDKIT_USES
	a.wounds = 40.0
	a.health = 60.0
	server.combat.use_at(a, server.tick, Vector2(a.st.x + 0.45, a.st.y - 0.45))
	_expect(a.treating == a.slot, "a click in the corner of our own cell treats ourselves (it missed before v69)")
	a.treating = -1
	server.inventory.act(a)
	_expect(a.treating == a.slot, "and Z with the kit in hand does too")
	for t in 80:
		server._tick()
	_expect(a.wounds < 40.0 and a.slots[0] == Net.ITEM_MEDKIT + Net.MEDKIT_USES - 1, "standing still, one use closes wounds (%.0f left)" % a.wounds)
	a.treating = -1
	a.slots[0] = Net.ITEM_MEDPATCH
	var before := a.wounds
	server.inventory.act(a)
	_expect(a.wounds < before and a.slots[0] == Net.ITEM_NONE, "Z with a patch closes wounds at once")
	a.wounds = 0.0
	a.health = 50.0
	a.slots[0] = Net.ITEM_MEDPATCH
	server.inventory.act(a)
	_expect(a.slots[0] == Net.ITEM_MEDPATCH, "with no wounds the patch is kept (and the player is told why)")
	server.crew.remove(a)


func _autodoc() -> void:
	print("  -- the autodoc with two on its bed")
	var map := server.map
	var doc: int = map.autodoc.keys()[0]
	var bed: int = map.autodoc[doc]
	var well := server.crew.new_player("Здоровый")
	var hurt := server.crew.new_player("Раненый")
	for q in [well, hurt]:
		q.st.place(bed % map.width, bed / map.width)
		q.st.dir = Net.DIR_NONE
	well.health = 100.0
	well.wounds = 0.0
	hurt.health = 40.0
	hurt.wounds = 60.0
	_expect(server.medbay.in_bed(doc) == hurt, "the worst off on the bed is the one it heals")
	var was := hurt.wounds
	for t in 40:
		server._tick()
	_expect(hurt.wounds < was, "and its wounds close although a healthy one stands there too")
	_expect(server.medbay.tending(well, doc), "one standing on the bed can tend the other (hold E)")
	server.crew.remove(well)
	server.crew.remove(hurt)


# --------------------------------------------------------------- a ship alongside

func _buried() -> void:
	print("  -- things floating where a ship docks")
	_calm()
	var der = server.derelict
	der._arrive()
	var map := server.map
	# space cells the docked ship will cover: things floating there now
	var to: Vector2i = der._spots[der.layout][1]
	var o = map.other
	var put := 0
	for k in o.cells.size():
		var c: int = (to.y + k / o.width) * map.width + to.x + k % o.width
		if o.cells[k] >= 0 and o.walk[k] == 0 and map.floats(c % map.width, c / map.width) and put < 3:
			server.put_on_floor(c, Net.ITEM_MEDPATCH)
			put += 1
	_expect(put == 3, "three patches float where its wall will be")
	_expect(der.dock(true) == "" and der.docked, "it docks")
	var stuck := 0
	var patches := 0
	for c: int in server.floor_things.keys():
		if not (map.walkable(c % map.width, c / map.width) or map.floats(c % map.width, c / map.width)):
			stuck += 1
		patches += (server.floor_things[c] as PackedByteArray).count(Net.ITEM_MEDPATCH)
	_expect(stuck == 0 and patches >= 3, "nothing is left inside a wall: the patches drifted out (%d stuck, %d patches)" % [stuck, patches])
	der.dock(false)
	_calm()


func _docking() -> void:
	print("  -- no docking under way")
	_calm()
	var der = server.derelict
	der._arrive()
	server.ship.moving = true
	server.ship.dest = server.ship.pos + Vector2(30, 0)
	_expect(der.dock(true) != "" and not der.docked, "the ship must stop first")
	server.ship.moving = false
	_expect(der.dock(true) == "" and der.docked, "stopped, it docks")
	der.dock(false)
	_calm()


func _wreck_one() -> void:
	server.derelict.pirates_come(server.director._party(), true)
	_run(2)
	server.gunnery._wrecked()
	_run(2)


func _hulks() -> void:
	print("  -- a wreck stays on the chart (the author's note)")
	_calm()
	var r = server.road
	var der = server.derelict
	server.ship.pos = Vector2(100, 100)
	_wreck_one()
	_expect(der.here and der.wreck, "a raider wrecked stays alongside")
	var id: int = der.ship.id
	var cell: int = -1
	for c in server.map.other_cells:
		if server.map.walk[c] == 1 and not server.floor_things.has(c):
			cell = c
			break
	server.put_on_floor(cell, Net.ITEM_PART)
	var local: int = der._local(cell, server.map.other_at)
	server.ship.pos = der.wreck_at + Vector2(Sectors.WRECK_REACH - 2, 0)
	_run(2)
	_expect(der.here, "moving a little does not leave it")
	server.ship.pos = der.wreck_at + Vector2(40, 0)
	_run(2)
	_expect(not der.here and r.hulks_here().size() == 1, "flown away from, it stays in the system")
	var pkt: PackedByteArray = r.packet()
	_expect(pkt.find(Sectors.P_HULK) >= 0, "and is on the chart")
	server.ship.pos = r.hulks_here()[0]["pos"]
	_run(2)
	_expect(der.here and der.wreck and der.ship.id == id and r.hulks_here().is_empty(), "coming back, the same wreck comes alongside")
	var back := der._cell(server.map.other_at, local)
	_expect(server.floor_things.has(back) and (server.floor_things[back] as PackedByteArray).has(Net.ITEM_PART), "with what was left on it")
	# a wreck made next to another place lies a little further off
	r._here_places = [[Sectors.P_DEBRIS, Vector2(60, 60)]]
	var spot: Vector2 = r.hulk_spot(Vector2(62, 60))
	_expect(spot.distance_to(Vector2(60, 60)) >= Sectors.WORK_REACH + Sectors.WRECK_REACH + Sectors.HULK_APART - 0.6,
		"a wreck by another place is moved clear of it (%.0f off)" % spot.distance_to(Vector2(60, 60)))
	r._places_for = -1
	_calm()


func _hunters() -> void:
	print("  -- hunters and a ship alongside")
	_calm()
	var r = server.road
	var der = server.derelict
	var s = server.sectors
	var kind_was: int = s.kind[server.ship.sector]
	s.kind[server.ship.sector] = Sectors.EMPTY
	der._arrive()
	der.dock(true)
	r.spawn_hunter()
	r.hunters[0]["at"] = server.ship.sector
	r.hunters[0]["coming"] = server.tick
	_run(Net.TICK_HZ * 3)
	_expect(server.gunnery.fighting(), "docked to a derelict, the hunter comes anyway: the derelict is let go")
	server.gunnery._wrecked()
	_run(2)
	der._leave(true)
	r.hulks = {}
	_run(Net.TICK_HZ * 2)
	r.spawn_hunter()
	r.hunters[0]["at"] = server.ship.sector
	r.hunters[0]["coming"] = server.tick
	_run(Net.TICK_HZ * 3)
	_expect(not server.gunnery.fighting() and int(r.hunters[0]["coming"]) >= r.busy_tick + roundi(r.breather * Net.TICK_HZ),
		"right after a fight the next hunter waits a breather")
	_calm()
	var out := server.crew.new_player("Снаружи")
	var space := -1
	for c in server.map.cells.size():
		if server.map.floats(c % server.map.width, c / server.map.width):
			space = c
			break
	out.st.place(space % server.map.width, space / server.map.width)
	out.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	out.tank = 1.0
	r.spawn_hunter()
	r.hunters[0]["at"] = server.ship.sector
	r.hunters[0]["coming"] = server.tick
	var hull := server.ship.hull
	for t in Net.TICK_HZ * 3:
		server._tick()
	_expect(not server.gunnery.fighting() and server.ship.hull < hull, "with one of ours outside it shells the hull instead")
	server.crew.remove(out)
	s.kind[server.ship.sector] = kind_was
	_calm()


func _station() -> void:
	print("  -- a supply station")
	var s = server.sectors
	var kind_was: int = s.kind[server.ship.sector]
	s.kind[server.ship.sector] = Sectors.STATION
	server.ship.in_reach = true
	var p := server.crew.new_player("Продавец")
	var map := server.map
	var locker: int = map.locker.keys()[0]
	var x := locker % map.width
	var y := locker / map.width
	p.st.place(x, y + 1 if map.walkable(x, y + 1) else y - 1)
	p.st.facing = Net.DIR_UP if map.walkable(x, y + 1) else Net.DIR_DOWN
	server.supplies._offers_for = -1
	var offers: Dictionary = server.supplies.offers()
	_expect(offers.has(Net.ITEM_ROBOT) and not offers.has(Net.ITEM_PATCH), "it sells robots, not a trader's goods")
	server.ship.store[Net.ITEM_PATCH] = 3
	var credits := server.ship.credits
	server.supplies.store_asked(p, Net.STORE_SELL, Net.ITEM_PATCH)
	_expect(server.ship.credits == credits and int(server.ship.store[Net.ITEM_PATCH]) == 3, "and buys nothing")
	server.ship.credits = 500
	server.supplies.store_asked(p, Net.STORE_BUY, Net.ITEM_ROBOT)
	_expect(server.ship.credits < 500, "what it sells can be bought")
	s.kind[server.ship.sector] = kind_was
	server.ship.in_reach = false
	server.crew.remove(p)


# --------------------------------------------------------------- doors

func _locked_rooms() -> void:
	print("  -- locked rooms")
	var map := server.map
	var door := -1
	var inside := -1
	var outside := -1
	for d in map.doors.size():
		if map.door_access[d] == 0 or map.door_partner[d] >= 0:
			continue
		var a: int = map.door_sides[d * 2]
		var b: int = map.door_sides[d * 2 + 1]
		if a < 0 or b < 0:
			continue
		if (map.access_in[a] & map.door_access[d]) != 0 and (map.access_in[b] & map.door_access[d]) == 0:
			door = d; inside = a; outside = b
		elif (map.access_in[b] & map.door_access[d]) != 0 and (map.access_in[a] & map.door_access[d]) == 0:
			door = d; inside = b; outside = a
		if door >= 0:
			break
	_expect(door >= 0, "a locked room's door is found")
	var p := server.crew.new_player("Без доступа")
	p.st.access = 0
	var at: Vector2i = map.doors[door]
	for pair in [[inside, true], [outside, false]]:
		var c: int = pair[0]
		server.doors.ready[door] = Doors.CLOSED
		p.st.place(c % map.width, c / map.width)
		p.st.cd = 0
		var dir := 0
		for f in range(1, 5):
			if c % map.width + Net.DX[f] == at.x and c / map.width + Net.DY[f] == at.y:
				dir = f
		p.st.dir = dir
		var moved := false
		for t in 20:
			moved = Mover.step(p.st, map, server.doors, server.tick + t) or moved
		_expect(moved == pair[1], "from inside one walks out freely" if pair[1] else "from outside it stays shut")
	# breaking the lock
	server.doors.ready[door] = Doors.CLOSED
	p.st.place(outside % map.width, outside / map.width)
	p.st.dir = Net.DIR_NONE
	for f in range(1, 5):
		if outside % map.width + Net.DX[f] == at.x and outside / map.width + Net.DY[f] == at.y:
			p.st.facing = f
	p.using = true
	for t in Net.HACK_TICKS + 5:
		server._tick()
	p.using = false
	_expect(server.doors.picked[door] == 1, "a lock broken open stays broken")
	_run(Net.TICK_HZ * 4)
	_expect(not server.doors.barred(door, map.door_access[door], 0), "and the door lets anybody through")
	p.slots[1] = Net.ITEM_PART
	p.using = true
	for t in Net.REPAIR_TICKS + 5:
		server._tick()
	p.using = false
	_expect(server.doors.picked[door] == 0, "until it is mended")
	server.crew.remove(p)


func _airlock() -> void:
	print("  -- one press of an airlock door's button (the author's idea)")
	var map := server.map
	var pump: int = map.lock_pump.keys()[0]
	var inner: int = map.lock_pump[pump]["inner"]
	var outer: int = map.lock_pump[pump]["outer"]
	var chamber: PackedInt32Array = map.lock_pump[pump]["chamber"]
	server.ship.pumps.clear()
	for d in [inner, outer]:
		server.doors.ready[d] = Doors.CLOSED
		server.doors.locked[d] = 0
	for c in chamber:
		server.air.air[c] = 1.0
	server.ship.store_air = 30.0
	var p := server.crew.new_player("Шлюз")
	p.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	p.tank = 1.0
	var o: Vector2i = map.doors[outer]
	for f in range(1, 5):
		var x: int = o.x + Net.DX[f]
		var y: int = o.y + Net.DY[f]
		if map.floats(x, y):
			p.st.place(x, y)
			p.st.facing = [0, 2, 1, 4, 3][f]
	p.st.dir = Net.DIR_NONE
	_run(Net.TICK_HZ)
	_expect(server.doors.locked[outer] == 1, "from space the outer door is held: the chamber is full")
	var store := server.ship.store_air
	server.repairs.press(p)
	var opened := false
	for t in Net.TICK_HZ * 20:
		p.health = 100.0
		p.tank = 1.0
		server._tick()
		if server.doors.ready[outer] != Doors.CLOSED:
			opened = true
			break
	_expect(opened, "one press: the chamber is emptied and the outer door opens by itself")
	_expect(server.ship.store_air > store, "the chamber's air went into the ship's store (%.1f -> %.1f)" % [store, server.ship.store_air])
	server.crew.remove(p)
	_run(Net.TICK_HZ * 4)


func _vents() -> void:
	print("  -- a vent in every room (the author's idea)")
	var map := server.map
	_expect(map.vents.size() >= 6, "the ship has a vent per room (%d)" % map.vents.size())
	var room: PackedInt32Array = PackedInt32Array()
	for v in map.vents:
		var r: PackedInt32Array = map.rooms[map.room_of[v]]
		var plant := false
		for cell: int in map.air_plant.keys():
			plant = plant or r.has(map.air_plant[cell])
		if not plant:
			room = r
			break
	server.ship.store_air = 30.0
	for c in room:
		server.air.air[c] = 0.3
	var store := server.ship.store_air
	server.systems._vents()
	_expect(server.ship.store_air < store, "a room short of air gets it from the store")
	var hole := -1
	for c in room:
		for o: int in [1, -1, map.width, -map.width]:
			if map.hull.has(c + o):
				hole = c + o
	if hole >= 0:
		server.air.set_hole(hole, true)
		store = server.ship.store_air
		server.systems._vents()
		_expect(server.ship.store_air == store, "a room with a hole gets none (the vent shuts)")
		server.air.set_hole(hole, false)
	for c in room:
		server.air.air[c] = 1.0


func _sight() -> void:
	print("  -- those behind us are sent too (the author's video)")
	var a := server.crew.new_player("Смотрит")
	var b := server.crew.new_player("Сзади")
	_floor_spot(a)
	var x := a.st.x
	var y := a.st.y
	var behind := -1
	for k in range(1, 4):
		if server.map.walkable(x - k, y):
			behind = k
	b.st.place(x - behind, y)
	a.st.facing = Net.DIR_RIGHT
	server.replication.sight_changed()
	_expect(behind >= 2 and server.replication.sees(a, b), "one behind us is sent (the client hides it by its own facing)")
	server.replication.set_round(false)
	server.replication.sight_changed()
	_expect(not server.replication.sees(a, b), "with the old rule it was not")
	server.replication.set_round(true)
	server.crew.remove(a)
	server.crew.remove(b)


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		failed += 1
		print("FAIL ", what)
