extends SceneTree
## (v96) Checks the places seen in space, meteors as things flying in space, our own boarding pod and the bots'
## better fighting, on a real server stepped by hand:
##   godot --headless --path . --script res://tools/podtest.gd
## The road packet carries a drawing per place; a station docks only once the ship stops by it. A meteor flies at
## our hull and breaches it where it strikes; an evade early enough steers round it; a bot at the controls may;
## the shield stops it; two shots of ours break it. Our pod: E at the bay seats one, it starts after the wait, flies
## to the pirate ship alongside, sticks in its hull and lets its riders out inside; E at it takes them home; the
## empty pod comes home by itself after the fight; their point defence may throw it back (riders bruised, mending);
## a bot told «К оружию» is called to the second seat. The bots: fighters know what any of ours sees (D1), a badly
## hurt one falls back and patches itself (D2), the locker's shotgun first (D3), friends shoot one target (D4).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Arena := preload("res://src/server/arena.gd")
const Pods := preload("res://src/server/pods.gd")
const Defence := preload("res://src/server/defence.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26341, "ship02", 2)
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
	server.systems.vents_on = false
	server.pods.bots_ride = false
	for q in server.players:                  # (the bots stand still: the checks place people themselves)
		if q != null and q.bot:
			q.order = Net.POST_FREE
	server.ship.pos = Vector2(100, 100)
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	_run(2)
	_places()
	_meteors()
	_pod()
	_bots()
	print("podtest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	quit(0 if failed == 0 else 1)


func _places() -> void:
	print("  -- places in space")
	var road = server.road
	var pkt: PackedByteArray = road.packet()
	var at: int = 5 + int(pkt[4]) * 2         # past the hunters
	at += int(pkt[at]) + 1                    # past the known systems
	var n: int = pkt[at]
	_expect(pkt.size() == at + 1 + n * 5 + 1, "S_ROAD carries five bytes a place and the system's own drawing (%d places, %d bytes)" % [n, pkt.size()])
	var looks_ok := true
	for i in road._here_places.size():
		var look: int = road.look_of(i)
		looks_ok = looks_ok and (look == 255 or look < server.map.others.size())
	_expect(looks_ok, "every place's drawing is one of the drawings that come alongside, or none")


func _meteors() -> void:
	print("  -- meteors in space")
	var a = server.arena
	var ship = server.ship
	var st = server.stations
	ship.guard_armed = false
	ship.shield_on = false
	var holes0: int = server.air.holes.size()
	_expect(st.meteor_seen() and a.rocks_flying() == 1, "a meteor seen is a rock flying in space")
	_run(roundi((Arena.ROCK_WARN + 1.0) * Net.TICK_HZ))
	_expect(a.rocks_flying() == 0 and server.air.holes.size() > holes0 and st.meteor_at == 0,
		"it strikes our hull and breaches it (holes %d -> %d)" % [holes0, server.air.holes.size()])
	_mend()

	# an evade early enough steers round it
	var b = a.body(0)
	_expect(st.meteor_seen(), "(another meteor)")
	_run(Net.TICK_HZ)
	a.dash(0, 0.0)
	_run(roundi((Arena.ROCK_WARN + 3.0) * Net.TICK_HZ))
	_expect(a.rocks_flying() == 0 and server.air.holes.is_empty() and st.meteor_at == 0, "an evade seconds before steers round it")
	b.vel = Vector2.ZERO

	# a bot at the controls throws the ship aside (the lot pinned)
	var bot = _bot_at_helm()
	st.meteor_roll = 0.0
	_expect(st.meteor_seen(), "(a meteor, a bot at the controls)")
	_run(roundi((Arena.ROCK_WARN + 3.0) * Net.TICK_HZ))
	_expect(server.air.holes.is_empty(), "a bot at the controls steers round it when its lot comes")
	st.meteor_roll = 0.99
	b.vel = Vector2.ZERO
	_expect(st.meteor_seen(), "(again, the lot against it)")
	_run(roundi((Arena.ROCK_WARN + 3.0) * Net.TICK_HZ))
	_expect(not server.air.holes.is_empty(), "and it strikes when the lot fails")
	_mend()
	st.meteor_roll = -1.0
	_away(bot)
	b.vel = Vector2.ZERO
	_run(Net.TICK_HZ * 3)

	# the shield stops it
	ship.shield_on = true
	server.power.set_charge(1.0e9)
	b.vel = Vector2.ZERO
	_expect(st.meteor_seen(), "(a meteor, the shield on)")
	_run(roundi((Arena.ROCK_WARN + 3.0) * Net.TICK_HZ))
	_expect(server.air.holes.is_empty() and a.rocks_flying() == 0, "a raised shield stops it (holes %d)" % server.air.holes.size())
	_mend()
	_run(Net.TICK_HZ * 5)
	_expect(not b.raised, "and comes down once it is gone")
	ship.shield_on = false

	# two shots of ours break it
	_expect(st.meteor_seen(), "(a meteor to shoot)")
	var rock: Dictionary = {}
	for p: Dictionary in a.shots:
		if p.get("pod", "") == "rock":
			rock = p
	for k in 2:
		var shot := {"id": 9990 + k, "side": 0, "from": 0, "pos": (rock["pos"] as Vector2) - (rock["vel"] as Vector2).normalized() * 3.0,
			"vel": (rock["vel"] as Vector2).normalized() * 40.0, "ends": server.tick + 20, "w": Weapons.LASER, "kind": Net.SHOT_CANNON,
			"meta": {}, "seen": {}, "guard": false, "d": 30.0, "type": 0, "practice": true}
		a.shots.append(shot)
	_run(3)
	_expect(a.rocks_flying() == 0 and st.meteor_at == 0, "two shots of ours break it (rock hp %d)" % int(rock.get("hp", -1)))
	_run(roundi(Arena.ROCK_WARN * Net.TICK_HZ))
	_expect(server.air.holes.is_empty(), "and nothing strikes")


func _pod() -> void:
	print("  -- our boarding pod")
	var a = server.arena
	var map = server.map
	var pods = server.pods
	var d = server.derelict
	var g = server.gunnery
	_expect(map.pod.size() == 1 and pods.bays.size() == 1, "ship02 has a pod bay")
	var bay: int = map.pod.keys()[0]
	var p = _at_bay(bay, "Абордажник")
	pods.press(p, bay)
	_expect(not p.in_shuttle and pods.state(bay) == Net.POD_READY, "with no fight it does not take anybody")

	_expect(d.pirates_come(2, false), "(a boarding ship comes)")
	_run(1)
	a.hold_pirates = true
	a.pirate_shields = false
	var b = a.body(0)
	var e = a.body(Arena.LEAD)
	e.pos = b.pos + Vector2(0, 70)
	e.vel = Vector2.ZERO
	g.enemy_guard = false
	g.enemy_charge.fill(0.0)
	_expect(pods.press(p, bay) and p.in_shuttle and p.in_pod == bay and pods.state(bay) == Net.POD_WAITING, "E at the bay seats one, the pod waits")
	_run(roundi(Pods.WAIT * Net.TICK_HZ) + 1)
	_expect(pods.state(bay) == Net.POD_OUT and a.our_pods_flying() == 1, "after the wait it starts")
	var landed := false
	for t in Net.TICK_HZ * 12:
		g.enemy_charge.fill(0.0)
		_run(1)
		if pods.state(bay) != Net.POD_OUT:
			break
	landed = pods.state(bay) == Net.POD_STUCK
	_expect(landed, "it sticks in the pirate ship's hull (state %d)" % pods.state(bay))
	_expect(not p.in_shuttle and map.is_other(p.st.y * map.width + p.st.x) and map.walkable(p.st.x, p.st.y),
		"its rider steps out inside the pirate ship")
	if landed:
		var stuck: int = pods.bays[bay]["stuck"]
		_expect(pods.press(p, stuck) and p.in_pod == bay, "E at the stuck pod takes one home")
		_run(roundi((Pods.HOME_WAIT + Pods.HOME_SECONDS) * Net.TICK_HZ) + 2)
		_expect(pods.state(bay) == Net.POD_READY and not p.in_shuttle and map.on_ship(p.st.y * map.width + p.st.x),
			"it flies home and lets the rider out by its bay")

	# an empty pod comes home by itself once the fight is over
	_expect(pods.press(p, bay), "(seated again)")
	for t in Net.TICK_HZ * 20:
		g.enemy_charge.fill(0.0)
		_run(1)
		if pods.state(bay) == Net.POD_STUCK:
			break
	_away(p)
	_kill_pirates()
	_expect(pods.state(bay) == Net.POD_STUCK and (pods.bays[bay]["riders"] as Array).is_empty(), "(it stuck, its rider is back aboard ours)")
	g.enemy_hull = 0
	d.pirates_wrecked()
	_run(roundi(Pods.HOME_SECONDS * Net.TICK_HZ) + 4)
	_expect(pods.state(bay) == Net.POD_READY, "after the fight the empty pod comes home by itself (state %d)" % pods.state(bay))
	_run(2)

	# their point defence may throw it back: riders bruised, the pod mended
	_expect(d.pirates_come(2, false), "(another boarding ship)")
	_run(1)
	e = a.body(Arena.LEAD)
	e.pos = b.pos + Vector2(0, 70)
	e.vel = Vector2.ZERO
	var down := false
	for i in 25:
		g.enemy_guard = true
		g._enemy_guard_ready = 0
		p.health = 100.0
		p.wounds = 0.0
		pods.bays[bay]["state"] = Net.POD_READY
		_away(p)
		pods.press(p, bay)
		for t in Net.TICK_HZ * 20:
			g.enemy_charge.fill(0.0)
			_run(1)
			if pods.state(bay) != Net.POD_WAITING and pods.state(bay) != Net.POD_OUT:
				break
		if pods.state(bay) == Net.POD_MENDING:
			down = true
			break
		_away(p)
		_kill_pirates()
		if pods.state(bay) == Net.POD_STUCK:
			pods.bays[bay] = Pods._fresh()
	_expect(down, "their point defence shoots a pod down now and then")
	if down:
		_expect(p.health < 100.0 and not p.in_shuttle and map.on_ship(p.st.y * map.width + p.st.x), "its rider is thrown back home, bruised (%.0f)" % p.health)
		pods.press(p, bay)
		_expect(not p.in_shuttle, "the pod is mended before it flies again")
		_run(roundi(Pods.MEND * Net.TICK_HZ) + 1)
		_expect(pods.state(bay) == Net.POD_READY, "and is ready %d s later" % int(Pods.MEND))

	# a bot told «К оружию» is called to the second seat
	g.enemy_guard = false
	pods.bots_ride = true
	var bot = server.crew.new_player("Бот-абордажник", 0)
	bot.bot = true
	bot.job = Net.JOB_CREWMAN
	bot.defends = true
	bot.order = Net.POST_FREE
	bot.slots.fill(Net.ITEM_NONE)
	bot.slots[0] = Net.ITEM_PISTOL
	bot.slots[1] = Net.ITEM_MAG
	var front: int = map.pod[bay]
	bot.st.place(front % map.width, front / map.width)
	_away(p)
	p.st.place(front % map.width, front / map.width)
	for f in range(1, 5):
		if map.use_ahead(p.st.x, p.st.y, f) == bay:
			p.st.facing = f
	for q in server.players:
		if q != null and q.bot and q != bot:
			q.defends = false
	if map.walkable(front % map.width - 3, front / map.width):
		bot.st.place(front % map.width - 3, front / map.width)
	pods.press(p, bay)
	_expect(bot.pod_call == bay, "a bot told «К оружию» is called to the free seat")
	var both := false
	for t in roundi(Pods.BOT_WAIT * Net.TICK_HZ):
		g.enemy_charge.fill(0.0)
		_run(1)
		if bot.in_pod == bay:
			both = true
			break
	_expect(both and pods.state(bay) != Net.POD_READY, "it comes and sits in")
	for t in Net.TICK_HZ * 20:
		g.enemy_charge.fill(0.0)
		_run(1)
		if pods.state(bay) == Net.POD_STUCK:
			break
	_expect(pods.state(bay) == Net.POD_STUCK and map.is_other(bot.st.y * map.width + bot.st.x), "it boards the pirate ship with us")
	_away(p)
	_kill_pirates()
	var back := false
	for t in Net.TICK_HZ * 40:
		_kill_pirates()
		_run(1)
		if bot.in_pod == bay or pods.state(bay) == Net.POD_HOME or pods.state(bay) == Net.POD_READY:
			back = true
			break
	_expect(back, "with no pirates left there it goes back to the pod (state %d)" % pods.state(bay))
	pods.bots_ride = false
	g.enemy_hull = 0
	d.pirates_wrecked()
	_run(roundi((Pods.HOME_WAIT + Pods.HOME_SECONDS) * Net.TICK_HZ) + 4)
	_away(bot)
	bot.defends = false
	_gone(bot)
	_gone(p)
	a.hold_pirates = false
	_run(2)


func _bots() -> void:
	print("  -- bots against boarders")
	var def = server.defence
	def.on = true
	var at := _open_row(8)
	var far := _open_row(8, 40)
	var q = _pirate(at)
	var g = _bot("Охранник", far, Net.JOB_GUARD)
	g.slots[0] = Net.ITEM_PISTOL
	g.slots[1] = Net.ITEM_MAG
	g.st.facing = Net.DIR_RIGHT
	var eye = server.crew.new_player("Глаз", 0)
	eye.st.place(at.x + 3, at.y)
	eye.st.facing = Net.DIR_LEFT
	def.radio = false
	_ticks(Net.TICK_HZ, q, at)
	var alone: bool = def.busy(g)
	def.radio = true
	_ticks(Net.TICK_HZ, q, at)
	_expect(not alone and def.busy(g), "a fighter far off knows of a pirate one of ours sees (alone it did not)")

	# D2: badly hurt it falls back and patches itself
	g.st.place(far.x, far.y)
	g.health = 30.0
	g.wounds = 70.0
	g.slots[2] = Net.ITEM_MEDPATCH
	var patched := false
	for t in Net.TICK_HZ * 10:
		_ticks(1, q, at)
		if not g.slots.has(Net.ITEM_MEDPATCH):
			patched = true
			break
	_expect(g.falling_back, "a badly hurt fighter falls back")
	_expect(patched, "and puts its medical patch on")
	g.health = 100.0
	g.wounds = 0.0
	_ticks(Net.TICK_HZ / 2, q, at)
	_expect(not g.falling_back, "healed, it goes back in")

	# D3: the shotgun first
	server.ship.store[Net.ITEM_PISTOL] = 2
	server.ship.store[Net.ITEM_SHOTGUN] = 1
	_expect(def._locker_gun() == Net.ITEM_SHOTGUN, "the locker's shotgun is taken first")

	# D4: friends near shoot one target
	var q2 = _pirate(at + Vector2i(1, 0))
	var f = _bot("Напарник", at + Vector2i(5, 0), Net.JOB_GUARD)
	f.doing = Net.DOING_FIGHT
	f.ai_target = q2.slot
	g.st.place(at.x + 6, at.y)
	g.st.facing = Net.DIR_LEFT
	g.ai_target = q.slot
	def._focus(g)
	_expect(g.ai_target == q2.slot, "a fighter by a friend shoots the friend's target")
	_gone(q)
	_gone(q2)
	_gone(f)
	_gone(g)
	_gone(eye)
	def.on = false


# ---------------------------------------------------------------- helpers

func _mend() -> void:
	for c: int in server.air.holes.keys():
		server.air.set_hole(c, false)


func _kill_pirates() -> void:
	for q in server.players:
		if q != null and q.pirate and not q.corpse:
			q.health = Net.HEALTH_DEAD
			q.corpse = true
			q.cond = Net.COND_DEAD


func _bot_at_helm():
	var map = server.map
	var bot = server.crew.new_player("Бот-пилот", 0)
	bot.bot = true
	bot.order = Net.POST_HELM
	var console: int = map.helm.keys()[0]
	var front: int = map.fitting_front(console)
	bot.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		bot.st.facing = f
		if map.use_ahead(bot.st.x, bot.st.y, f) == map.machine_of(console):
			break
	_run(Net.TICK_HZ)
	_expect(server.stations._at.get(Net.POST_HELM, null) == bot, "(a bot stands at the controls)")
	return bot


func _at_bay(bay: int, who: String):
	var map = server.map
	var p = server.crew.new_player(who, 0)
	var front: int = map.pod[bay]
	p.st.place(front % map.width, front / map.width)
	for f in range(1, 5):
		if map.use_ahead(p.st.x, p.st.y, f) == bay:
			p.st.facing = f
	return p


func _open_row(length: int, skip: int = 0) -> Vector2i:
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


func _bot(who: String, at: Vector2i, job: int):
	var b = server.crew.new_player(who, 0)
	b.bot = true
	b.job = job
	b.st.access = Net.ACCESS_ALL | Net.ACCESS_OURS
	b.slots.fill(Net.ITEM_NONE)
	b.st.place(at.x, at.y)
	b.st.facing = Net.DIR_LEFT
	b.order = Net.POST_FREE
	return b


func _pirate(at: Vector2i):
	var q = server.pirates.spawn(at.x, at.y, true)
	q.ready_tick = 1 << 30
	q.ai_fire_tick = 1 << 30
	return q


func _gone(who) -> void:
	who.cond = Net.COND_DEAD
	who.corpse = true
	who.st.down = true
	who.in_shuttle = false
	who.in_pod = -1
	who.st.place(0, 0)


func _away(p) -> void:
	var spawn: Vector2i = server.crew.spawn_point()
	p.in_shuttle = false
	p.in_pod = -1
	p.st.place(spawn.x, spawn.y)


func _ticks(n: int, held = null, at := Vector2i(-1, -1)) -> void:
	for i in n:
		server._tick()
		if held != null:
			held.st.place(at.x, at.y)
			held.st.dir = Net.DIR_NONE


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
