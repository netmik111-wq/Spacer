extends SceneTree
## Checks v80's fixes from the author's full run (his eleven notebook notes): no hole ever opens
## on a machine set into the wall; bullets fly through open space; a bot holds "use" at a mount
## without taking its gun down unless the console ordered it, and the hold that mended a mount
## does not go on to take its gun down; a wreck alongside stays behind once our ship gets under
## way and comes back when it stops by its mark; a ship flying in the system stops when one of
## ours goes outside, and says who; a shot flies over somebody out cold unless aimed at them.
## On a real server stepped by hand:
##   godot --headless --path . --script res://tools/fullruntest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26480, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.stations.volunteers = false
	server.pirates.goals_on = false
	server.defence.on = false
	_no_hole_on_machines()
	_shots_in_space()
	_mounts_left_alone()
	_wreck_stays()
	_stops_for_outside()
	_out_cold_spared()
	server.stop()
	server.free()
	print("fullruntest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failed += 1


func _run(ticks: int) -> void:
	for t in ticks:
		server.ship.hull = server.ship.hull_max
		server._tick()


func _player(who: String, at: Vector2i):
	var p = server.crew.new_player(who)
	p.slots.fill(Net.ITEM_NONE)
	p.st.place(at.x, at.y)
	p.st.facing = Net.DIR_RIGHT
	return p


func _open_row(length: int) -> Vector2i:
	## A floor cell aboard with open floor (no doorway, no wall) for `length` cells on its row.
	var map = server.map
	for y in map.height:
		for x in map.width:
			var ok := map.on_ship(y * map.width + x)
			for dx in range(0, length):
				ok = ok and map.walkable(x + dx, y) and map.door_at(x + dx, y) < 0
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _space_row(length: int) -> Vector2i:
	## A cell of open space with `length` cells of open space to its right, on a deck's own rows.
	var map = server.map
	for y in map.height:
		for x in map.width:
			var ok := true
			for dx in range(0, length):
				ok = ok and map.floats(x + dx, y)
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _no_hole_on_machines() -> void:
	print("  -- a hole never opens on a machine in the wall (his picture: a hole on the supply locker)")
	var map = server.map
	var on_machine := 0
	for cell: int in map.hull:
		if map.fitting_front(cell) >= 0 or map.guns.has(cell):
			on_machine += 1
	_expect(on_machine == 0 and map.hull.size() > 20, "no breachable cell holds a fitting or a gun (%d of %d)" % [on_machine, map.hull.size()])
	var lockers := 0
	for cell: int in map.locker.keys():
		var x: int = cell % map.width
		var y: int = cell / map.width
		if map.is_space(x - 1, y) or map.is_space(x + 1, y) or map.is_space(x, y - 1) or map.is_space(x, y + 1):
			lockers += 1
	print("     (lockers in the outer wall: %d)" % lockers)


func _shots_in_space() -> void:
	print("  -- bullets fly through open space (his note: «in space you cannot shoot enemies»)")
	var at := _space_row(6)
	_expect(at.x >= 0, "there is open space beside the ship")
	var shooter = _player("Стрелок", at)
	shooter.dress()
	shooter.supply = true
	shooter.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	shooter.hand = 0
	var foe = server.pirates.spawn(at.x + 4, at.y, true)
	foe.ready_tick = 1 << 30
	foe.ai_fire_tick = 1 << 30
	foe.health = 100.0
	foe.wounds = 0.0
	server.combat.use_at(shooter, server.tick, Vector2(at.x + 4, at.y))
	_expect(foe.health < 100.0, "a pirate four cells off in space is hit (%.0f)" % foe.health)
	server.crew.remove(foe)
	server.crew.remove(shooter)


func _mounts_left_alone() -> void:
	print("  -- bots take a mounted gun down only when the console orders it (his note)")
	var map = server.map
	var ship = server.ship
	var i := -1
	for k in map.guns.size():
		if ship.mounts[k] != Weapons.NONE:
			i = k
			break
	_expect(i >= 0, "a mount with a gun on it")
	if i < 0:
		return
	var cell: int = map.guns[i]
	var front := -1
	for o: int in [map.width, -map.width, 1, -1]:
		if front < 0 and map.walk[cell + o] == 1 and map.on_ship(cell + o):
			front = cell + o
	var bot = _player("Бот Т", Vector2i(front % map.width, front / map.width))
	bot.bot = true
	bot.order = Net.POST_MOUNTS
	_expect(server.mounts.can(bot, cell) == server.mounts.NOT_HERE, "with no order, empty hands at a mounted gun do nothing")
	server.mounts.wanted[i] = server.mounts.WANT_DOWN
	_expect(server.mounts.can(bot, cell) == "", "with the order to take it down, they may")
	server.mounts.wanted[i] = server.mounts.WANT_NONE
	server.crew.remove(bot)
	# a player who mends the mount and keeps holding E
	var p = _player("Механик", Vector2i(front % map.width, front / map.width))
	var gun_was: int = ship.mounts[i]
	for d in Net.DIRS:
		if map.use_ahead(p.st.x, p.st.y, d, server.air.holes) == cell:
			p.st.facing = d
	_expect(map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes) == cell, "the mechanic faces the mount")
	ship.broken[cell] = true
	p.using = true
	var ticks := 0
	while ship.broken.has(cell) and ticks < 60 * Net.TICK_HZ:
		server.repairs.update(p)
		server.tick += 1
		ticks += 1
	_expect(not ship.broken.has(cell), "held E mends the mount")
	for t in roundi(server.mounts.UNMOUNT_SECONDS * Net.TICK_HZ * 2):
		server.repairs.update(p)
		server.tick += 1
	_expect(ship.mounts[i] == gun_was, "holding on does not take its gun down")
	p.using = false
	server.repairs.update(p)
	p.using = true
	for t in roundi(server.mounts.UNMOUNT_SECONDS * Net.TICK_HZ) + 2:
		server.repairs.update(p)
		server.tick += 1
	_expect(ship.mounts[i] == Weapons.NONE, "a fresh hold does (as before)")
	ship.mounts[i] = gun_was
	server.crew.remove(p)


func _wreck_stays() -> void:
	print("  -- a wreck alongside stays behind once our ship gets under way (his video)")
	var der = server.derelict
	server.ship.pos = Vector2(100, 100)
	server.derelict.pirates_come(server.director._party(), true)
	_run(2)
	server.gunnery._wrecked()
	_run(2)
	_expect(der.here and der.wreck, "a raider wrecked stays alongside")
	server.ship.moving = true
	server.ship.dest = server.ship.pos + Vector2(4, 0)
	_run(2)
	_expect(not der.here and server.road.hulks_here().size() == 1, "under way, it is left at its mark")
	var ticks := 0
	while server.ship.moving and ticks < 60 * Net.TICK_HZ:
		_run(1)
		ticks += 1
	_run(2)
	_expect(der.here and der.wreck, "stopped near its mark, it comes alongside again")
	der._leave(true)
	server.road.hulks = {}
	server.gunnery.enemy_gone()
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	_run(2)


func _stops_for_outside() -> void:
	print("  -- a ship flying in the system stops when one of ours goes outside, and says who")
	server.ship.tank = 600.0
	server.ship.moving = true
	server.ship.dest = server.ship.pos + Vector2(60, 0)
	_run(2)
	var at := _space_row(1)
	var out = _player("Снаружи", at)
	out.dress()
	out.supply = true
	_run(12)
	_expect(not server.ship.moving, "the ship stopped")
	out.health = -5.0
	out.cond = Net.COND_CRIT
	var why: String = server.derelict.holds_ship()
	_expect(why.contains("Снаружи") and why.contains("без сознания"), "the helm names who is out, and how: «%s»" % why)
	out.cond = Net.COND_DEAD
	out.health = Net.HEALTH_DEAD
	_expect(server.derelict.holds_ship() == "", "the dead never hold the ship")
	server.crew.remove(out)


func _out_cold_spared() -> void:
	print("  -- a shot flies over somebody out cold, unless aimed at them (his question)")
	var at := _open_row(6)
	var shooter = _player("Стрелок 2", at)
	shooter.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	shooter.hand = 0
	var down = server.pirates.spawn(at.x + 2, at.y, false)
	var up = server.pirates.spawn(at.x + 4, at.y, false)
	for q in [down, up]:
		q.ready_tick = 1 << 30
		q.ai_fire_tick = 1 << 30
		q.health = 100.0
		q.wounds = 0.0
	down.cond = Net.COND_CRIT
	server.combat.use_at(shooter, server.tick, Vector2(at.x + 4, at.y))
	_expect(down.health == 100.0 and up.health < 100.0, "the shot passes the one out cold and hits the one behind (%.0f, %.0f)" % [down.health, up.health])
	shooter.ready_tick = 0
	server.combat.use_at(shooter, server.tick, Vector2(at.x + 2, at.y))
	_expect(down.health < 100.0, "aimed at the one out cold, it hits (%.0f)" % down.health)
