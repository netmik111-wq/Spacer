extends SceneTree
## Checks v75's polish (the author's poll "Spacer v75 Polish" and his notebook notes) on a
## real server stepped by hand: a gunner mends its broken mount, a bot leaves a room with
## no air, a bot forcing the same shutter again and again counts as stuck, bots do not
## crowd one doorway, only breaches are said in everybody's chat, the quiet first minutes,
## the run's summary:
##   godot --headless --path . --script res://tools/polishtest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer
var cap
var bots: Array = []
var said: Array = []


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26431, "ship02", 3)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	server.systems.vents_on = false
	server.keep_heard = true
	server.log_line.connect(func(t: String): said.append(t))
	cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	for p in server.players:
		if p != null and p.bot and not p.corpse:
			bots.append(p)
	_gunner_mends()
	_leaves_no_air()
	_same_shutter()
	_doorway()
	_only_breaches_aloud()
	_quiet_start()
	_summary()
	print("polishtest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _suit(p) -> void:
	p.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	p.tank = 1.0


func _place(p, cell: int) -> void:
	p.st.place(cell % server.map.width, cell / server.map.width)
	p.st.dir = Net.DIR_NONE
	p.bot_plan_tick = -1000


func _cell(p) -> int:
	return p.st.y * server.map.width + p.st.x


func _settle() -> void:
	## All holes shut, air everywhere, nothing broken, every bot whole, at the helm.
	for c: int in server.air.holes.keys():
		server.air.set_hole(c, false)
	for c in server.air.air.size():
		if server.map.on_ship(c) and server.map.walk[c] == 1:
			server.air.air[c] = 1.0
	server.air.settled = false
	server.ship.broken.clear()
	server.ship.store[Net.ITEM_PATCH] = 10
	server.ship.store[Net.ITEM_PART] = 10
	var helm := int(server.stations.spots[Net.POST_HELM][0][0])
	for q in bots:
		q.health = 100.0
		q.tank = 1.0
		_place(q, helm)
		server.stations.order_asked(cap, q.slot, Net.POST_HELM)
	_wait(3, func(): return false)


func _gunner_mends() -> void:
	print("  -- (the author's note) a gunner at a broken mount mends it")
	_settle()
	server.stations.volunteers = false         # nobody else comes to mend it
	var i := -1
	for k in server.ship.mounts.size():
		if server.ship.mounts[k] != Weapons.NONE:
			i = k
			break
	_expect(i >= 0, "the ship has a gun on a mount")
	if i < 0:
		return
	var bot = bots[0]
	server.stations.order_asked(cap, bot.slot, Net.POST_MOUNTS)
	_wait(3, func(): return false)
	var mount: int = server.map.guns[i]
	server.ship.broken[mount] = true
	var mended := _wait(120, func(): return not server.ship.broken.has(mount))
	_expect(mended, "the mount is mended (task %d goal %d doing %d)" % [bot.bot_task, bot.bot_goal, bot.doing])
	server.stations.volunteers = true


func _leaves_no_air() -> void:
	print("  -- (the author's note) a bot on work in a room with no air goes where there is air")
	_settle()
	var cells: Array = server.map.brig_cells()
	_expect(not cells.is_empty(), "the ship has a brig")
	if cells.is_empty():
		return
	var room: Array = cells[0]
	for c: int in room:
		server.air.air[c] = 0.0
	var bot = bots[1]
	_suit(bot)
	server.stations.order_asked(cap, bot.slot, Net.POST_REPAIR)
	_place(bot, int(room[0]))
	var out := _wait(60, func(): return server.air.air[_cell(bot)] >= 0.5 and server.map.door_of[_cell(bot)] < 0 and not room.has(_cell(bot)))
	_expect(out, "it walked out to air (task %d goal %d, at %d,%d)" % [bot.bot_task, bot.bot_goal, bot.st.x, bot.st.y])


func _same_shutter() -> void:
	print("  -- (the author's note: «поднимает аварийный шлюз ×5») the same shutter forced again and again is being stuck")
	_settle()
	var bot = bots[2]
	var st = server.stations
	server.chat.bot_lines.clear()
	var door := 0
	_expect(st.shutter_forced(bot, door), "the first time it is said aloud")
	_expect(not st.shutter_forced(bot, door), "the second time it is not")
	st.shutter_forced(bot, door)
	_expect(_logged(bot, "застрял"), "the third time the bot says it is stuck and looks for another way")
	_expect(st.shutter_forced(bot, door + 1), "another shutter is said aloud again")


func _doorway() -> void:
	print("  -- (the author's B3) a bot waits while another works at a door")
	_settle()
	var a = bots[0]
	var b = bots[1]
	var door := -1
	var at := -1
	for d in server.map.other_first_door:
		for k in 2:
			var c: int = server.map.door_sides[d * 2 + k]
			if c >= 0 and server.map.walk[c] == 1:
				door = d
				at = c
				break
		if door >= 0:
			break
	_place(a, at)
	for dir in range(1, 5):
		if server.map.door_at(a.st.x + Net.DX[dir], a.st.y + Net.DY[dir]) == door:
			a.st.facing = dir
	a.using = true
	_expect(server.stations._door_busy(b, door), "the door is busy for the other bot")
	_expect(not server.stations._door_busy(a, door), "but not for the one at work there")
	a.using = false
	_expect(not server.stations._door_busy(b, door), "and free once it lets go")


func _only_breaches_aloud() -> void:
	print("  -- (the author's B4) only a breach is said in everybody's chat")
	_settle()
	var bot = bots[0]
	var st = server.stations
	said.clear()
	var console: int = server.map.helm.keys()[0]
	server.ship.broken[console] = true
	st._took(bot, console)
	_expect(not _said("[корабль]", "беру"), "a broken console goes to the bots' log only")
	_expect(_said("[боты]", "беру"), "(it is in the log)")
	st._took(bot, -1)
	var hole: int = server.map.hull[0]
	server.air.set_hole(hole, true)
	said.clear()
	st._took(bot, hole)
	_expect(_said("[корабль]", "беру"), "a breach is said aloud")
	st._took(bot, -1)
	server.ship.broken.clear()
	server.air.set_hole(hole, false)


func _quiet_start() -> void:
	print("  -- (the author's E4) the first 5 minutes are quiet on easy and normal")
	var d = server.director
	var keep: int = server.voyage_ticks
	server.voyage_ticks = 0
	_expect(d.quiet(), "at the start: quiet")
	server.voyage_ticks = 301 * Net.TICK_HZ
	_expect(not d.quiet(), "after five minutes: not")
	server.voyage_ticks = 0
	server.mode = Net.MODE_HARD
	_expect(not d.quiet(), "the hard mode is never quiet")
	server.mode = Net.MODE_NORMAL
	server.voyage_ticks = keep


func _summary() -> void:
	print("  -- (the author's E1) the run's summary")
	_settle()
	var earned: int = server.ship.earned
	server.ship.credits += 25
	_expect(server.ship.earned == earned + 25, "credits gained are counted as earned")
	var spent_before: int = server.ship.earned
	server.ship.credits -= 10
	_expect(server.ship.earned == spent_before, "credits spent are not")
	server.ships_beaten = 3
	var bot = bots[2]
	server.combat.hurt(bot, 500, null)
	_wait(2, func(): return false)
	var died := false
	for e: Array in server.deaths:
		if str(e[0]) == bot.name and str(e[1]) == "погиб от ран":
			died = true
	_expect(died, "a death is recorded with how it came (%s)" % str(server.deaths))
	var pk: PackedByteArray = server.crew.summary_packet()
	_expect(pk[0] == Net.S_SUMMARY and pk.decode_u16(1) == 3 and pk.decode_u32(5) == server.ship.earned and pk[9] == server.deaths.size(),
		"the summary packet carries ships beaten, credits earned and the dead")


func _said(prefix: String, words: String) -> bool:
	for t: String in said:
		if t.begins_with(prefix) and t.contains(words):
			return true
	return false


func _logged(p, words: String) -> bool:
	for e: Array in server.chat.bot_lines:
		if (p == null or int(e[0]) == p.slot) and str(e[1]).contains(words):
			return true
	return false


func _wait(seconds: int, done: Callable) -> bool:
	for t in seconds * Net.TICK_HZ:
		cap.health = 100.0
		server._tick()
		if done.call():
			return true
	return false


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
