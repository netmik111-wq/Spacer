extends SceneTree
## Checks v79's bots against armed boarders (the author's B1 "B"): a bot that sees an armed
## pirate close drops its work and runs far from it, lies low there, and goes back to work
## once the pirate is gone; a bot hurt by a pirate it never saw knows of it too; a guard bot
## fetches a pistol from the supply locker and shoots the pirate; a guard bot with no gun to
## be had runs like the others; with Defence.on off the bots take no notice (as before v79).
## Also the camera lean setting is kept. On a real server stepped by hand:
##   godot --headless --path . --script res://tools/defencetest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Defence := preload("res://src/server/defence.gd")
const Options := preload("res://src/client/options.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26479, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.stations.volunteers = false
	server.pirates.goals_on = false
	_runs()
	_hurt_unseen()
	_guard()
	_guard_without_gun()
	_to_arms()
	_switched_off()
	_lean_kept()
	print("defencetest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _open_row(length: int, skip: int = 0) -> Vector2i:
	## A floor cell with open floor (no doorway, no wall) for `length` cells on its row.
	var map = server.map
	var found := 0
	for y in map.height:
		for x in map.width:
			if not map.on_ship(y * map.width + x):
				continue
			var ok := true
			for dx in range(0, length):
				ok = ok and map.walkable(x + dx, y) and map.door_at(x + dx, y) < 0
			if ok:
				if found == skip:
					return Vector2i(x, y)
				found += 1
	return Vector2i(-1, -1)


func _bot(who: String, at: Vector2i, job: int = Net.JOB_CREWMAN):
	var b = server.crew.new_player(who)
	b.bot = true
	b.job = job
	b.st.access = Net.ACCESS_ALL | Net.ACCESS_OURS
	b.slots.fill(Net.ITEM_NONE)
	b.st.place(at.x, at.y)
	b.st.facing = Net.DIR_LEFT
	b.order = Net.POST_REPAIR
	return b


func _pirate(at: Vector2i):
	## An armed pirate held in place that never fires (the checks are about our bots).
	var q = server.pirates.spawn(at.x, at.y, true)
	q.ready_tick = 1 << 30
	q.ai_fire_tick = 1 << 30
	return q


func _gone(who) -> void:
	who.cond = Net.COND_DEAD
	who.corpse = true
	who.st.down = true
	who.st.place(0, 0)


func _ticks(n: int, held = null, at := Vector2i(-1, -1)) -> void:
	for i in n:
		server._tick()
		if held != null:
			held.st.place(at.x, at.y)
			held.st.dir = Net.DIR_NONE


func _runs() -> void:
	print("  -- a bot sees an armed pirate: it runs, lies low, and goes back to work after")
	var at := _open_row(6)
	_expect(at.x >= 0, "a stretch of open floor (%s)" % at)
	var q = _pirate(at)
	var b = _bot("Бегун", at + Vector2i(3, 0))
	_ticks(2 * Net.TICK_HZ, q, at)
	_expect(server.defence.busy(b), "it took notice of the pirate")
	_expect(b.doing == Net.DOING_HIDE, "it says it hides (%d)" % b.doing)
	var far := 0.0
	var lay := false
	for s in 30:
		_ticks(Net.TICK_HZ, q, at)
		far = Vector2(b.st.x, b.st.y).distance_to(Vector2(at)) if server.map.deck_of(b.st.y) == server.map.deck_of(at.y) else 99.0
		lay = lay or b.st.prone
		if lay:
			break
	_expect(far >= Defence.SAFE_FROM or lay, "it got away from the pirate (%.1f cells)" % far)
	_expect(lay, "and lies low there")
	_gone(q)
	_ticks(roundi((Defence.CALM_SECONDS + 1.0) * Net.TICK_HZ))
	_expect(not server.defence.busy(b), "the pirate gone, it calms down")
	_expect(not b.st.prone, "gets up")
	_expect(b.doing != Net.DOING_HIDE, "and goes back to its order (%d)" % b.doing)
	_gone(b)


func _hurt_unseen() -> void:
	print("  -- a bot hurt by a pirate it never saw knows of it")
	var at := _open_row(6)
	var q = _pirate(at)
	var b = _bot("Раненый", at + Vector2i(5, 0))
	b.st.facing = Net.DIR_RIGHT                  # its back to the pirate
	server.defence.on = false
	_ticks(2, q, at)
	server.defence.on = true
	server.combat.hurt(b, 5, q)
	_expect(server.defence.busy(b), "the wound tells it where the pirate is")
	_gone(q)
	_gone(b)
	_ticks(roundi((Defence.CALM_SECONDS + 1.0) * Net.TICK_HZ))


func _guard() -> void:
	print("  -- a guard bot fetches a gun from the locker and shoots the pirate")
	server.ship.store[Net.ITEM_PISTOL] = 1
	server.ship.store[Net.ITEM_MAG] = 3
	server.ship.store[Net.ITEM_SHOTGUN] = 0      # (v96 takes a shotgun first: this check is about the pistol)
	var at := _open_row(6)
	var q = _pirate(at)
	q.health = 100.0
	var g = _bot("Охранник-бот", at + Vector2i(3, 0), Net.JOB_GUARD)
	var armed := false
	var fought := false
	for s in 90:
		_ticks(Net.TICK_HZ, q, at)
		armed = armed or server.defence.gun_slot(g) >= 0
		fought = fought or g.doing == Net.DOING_FIGHT
		if q.health < 100.0 or q.cond != Net.COND_OK:
			break
	_expect(armed, "it has a pistol from the locker")
	_expect(int(server.ship.store.get(Net.ITEM_PISTOL, 0)) == 0, "the locker gave it")
	# (it may have loaded both by now if it missed a lot: what counts is that it took them)
	_expect(int(server.ship.store.get(Net.ITEM_MAG, 0)) <= 3 - Defence.AMMO_TAKEN, "with magazines (%d left in the locker)" % int(server.ship.store.get(Net.ITEM_MAG, 0)))
	_expect(fought, "it says it fights")
	_expect(q.health < 100.0 or q.cond != Net.COND_OK, "and hit the pirate (health %.0f)" % q.health)
	_expect(not g.st.prone, "it does not lie low while it fights")
	_gone(q)
	_ticks(roundi((Defence.CALM_SECONDS + 1.0) * Net.TICK_HZ))
	_expect(not server.defence.busy(g), "the pirate gone, it goes back to work")
	_expect(server.defence.gun_slot(g) >= 0, "keeping its gun")
	_gone(g)


func _guard_without_gun() -> void:
	print("  -- a guard bot with no gun to be had runs like the others")
	server.ship.store[Net.ITEM_PISTOL] = 0
	server.ship.store[Net.ITEM_SHOTGUN] = 0
	var at := _open_row(6)
	var q = _pirate(at)
	var g = _bot("Безоружный", at + Vector2i(3, 0), Net.JOB_GUARD)
	_ticks(2 * Net.TICK_HZ, q, at)
	_expect(g.doing == Net.DOING_HIDE, "it hides (%d)" % g.doing)
	_gone(q)
	_gone(g)
	_ticks(roundi((Defence.CALM_SECONDS + 1.0) * Net.TICK_HZ))


func _to_arms() -> void:
	print("  -- (v89, the author's note) a crewman bot told «к оружию» fights as a guard does")
	server.ship.store[Net.ITEM_PISTOL] = 1
	server.ship.store[Net.ITEM_MAG] = 2
	var at := _open_row(6)
	var q = _pirate(at)
	var g = _bot("Бот с приказом", at + Vector2i(3, 0))
	var captain = server.crew.new_player("Капитан")
	captain.job = Net.JOB_CAPTAIN
	captain.st.place(at.x + 5, at.y)
	server.stations.order_asked(captain, g.slot, Net.POST_ARMS)
	_expect(g.defends, "the order is taken")
	var armed := false
	var hid := false
	for s in 60:
		_ticks(Net.TICK_HZ / 2, q, at)
		armed = armed or server.defence.gun_slot(g) >= 0
		hid = hid or g.doing == Net.DOING_HIDE
		if armed:
			break
	_expect(armed and not hid, "it takes a gun from the locker instead of hiding")
	var told: PackedByteArray = server.stations.packet()
	_expect(told.size() > 12, "the crew list goes out")
	server.stations.order_asked(captain, g.slot, Net.POST_NO_ARMS)
	_expect(not g.defends, "and «не воевать» takes it back")
	_gone(q)
	_gone(g)
	server.crew.remove(captain)
	_ticks(roundi((Defence.CALM_SECONDS + 1.0) * Net.TICK_HZ))


func _switched_off() -> void:
	print("  -- switched off, bots take no notice (as before v79)")
	server.defence.on = false
	var at := _open_row(6)
	var q = _pirate(at)
	var b = _bot("Спокойный", at + Vector2i(3, 0))
	_ticks(2 * Net.TICK_HZ, q, at)
	_expect(not server.defence.busy(b) and b.doing != Net.DOING_HIDE, "it goes on as before")
	server.defence.on = true
	_gone(q)
	_gone(b)


func _lean_kept() -> void:
	print("  -- the camera's lean toward the mouse is a setting that is kept")
	var was: int = Options.lean
	_expect(was >= 0 and was <= 3, "it starts in range (%d)" % was)
	Options.lean = 3
	Options.save_all()
	Options.lean = 0
	Options.load_all()
	_expect(Options.lean == 3, "saved and read back")
	Options.lean = was
	Options.save_all()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
