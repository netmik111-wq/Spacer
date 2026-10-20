extends SceneTree
## Checks v72's bots at work (the author's note: bots did not raise the emergency
## shutter to a hole and mended only after he had; "repairs always first"; bots
## tell when they take a job; a log of what bots do) and the boarders' ship that
## stays as a wreck, on a real server stepped by hand:
##   godot --headless --path . --script res://tools/bottest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer
var cap
var bots: Array = []


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26421, "ship02", 3)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	server.systems.vents_on = false        # a breached room stays empty
	server.keep_heard = true
	cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	for p in server.players:
		if p != null and p.bot and not p.corpse:
			bots.append(p)
	_shutter()
	_one_bot_per_job()
	_free_bot_mends()
	_hand_over()
	_shut_in()
	_boarders_wreck()
	print("bottest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _room_of_hole(hole: int) -> int:
	var map = server.map
	for o in [1, -1, map.width, -map.width]:
		var c: int = hole + o
		if c >= 0 and c < map.room_of.size() and map.room_of[c] >= 0 and map.walk[c] == 1:
			return map.room_of[c]
	return -1


func _room_doors(room: int) -> Array:
	var map = server.map
	var out: Array = []
	for d in map.other_first_door:
		if server.systems.lock_door(d):
			continue
		for k in 2:
			var c: int = map.door_sides[d * 2 + k]
			if c >= 0 and map.room_of[c] == room:
				out.append(d)
				break
	return out


func _hull_cells(avoid: Dictionary) -> Array:
	## Hull cells of rooms with doors (none an airlock's), one per room, away from the rooms in `avoid`.
	var out: Array = []
	var seen := {}
	for cell: int in server.map.hull:
		var room := _room_of_hole(cell)
		if room < 0 or seen.has(room) or avoid.has(room):
			continue
		var doors := _room_doors(room)
		if doors.is_empty():
			continue
		var ok := true
		for c: int in server.map.rooms[room]:
			if server.map.door_of[c] >= 0 and server.systems.lock_door(server.map.door_of[c]):
				ok = false
		if not ok:
			continue
		seen[room] = true
		out.append(cell)
	return out


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
	## All holes shut, air everywhere, every bot whole, at the bridge, standing down.
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


func _shutter() -> void:
	print("  -- a suited bot raises the shutter down between it and a hole (the author's note)")
	_settle()
	var helm := int(server.stations.spots[Net.POST_HELM][0][0])
	var holes := _hull_cells({server.map.room_of[helm]: true})
	if holes.is_empty():
		_expect(false, "a room with doors to breach")
		return
	var hole: int = holes[0]
	var room := _room_of_hole(hole)
	server.systems.breach(hole)
	var sealed := _wait(30, func():
		for d: int in _room_doors(room):
			if not server.doors.is_sealed(d):
				return false
		return true)
	_expect(sealed, "the breached room's shutters are down (doors %s)" % [_room_doors(room)])
	var bot = bots[0]
	_suit(bot)
	server.stations.order_asked(cap, bot.slot, Net.POST_REPAIR)
	var shut := _wait(90, func(): return not server.air.holes.has(hole))
	_expect(shut, "the bot gets to the hole and patches it (bot at %d, doing %d, task %d)" % [_cell(bot), bot.doing, bot.bot_task])
	_expect(_logged(bot, "поднимает аварийный шлюз"), "it raised a shutter on its way")
	_wait(2, func(): return false)
	_expect(_logged(bot, "беру пробоину"), "it said it took the hole")
	_expect(_logged(bot, "готово: пробоину"), "and logged it done")


func _one_bot_per_job() -> void:
	print("  -- two bots, two holes: each takes its own (my B3 pick)")
	_settle()
	var helm := int(server.stations.spots[Net.POST_HELM][0][0])
	var holes := _hull_cells({server.map.room_of[helm]: true})
	if holes.size() < 2:
		_expect(false, "two rooms with doors to breach")
		return
	server.systems.breach(holes[0])
	server.systems.breach(holes[1])
	var a = bots[0]
	var b = bots[1]
	_suit(a)
	_suit(b)
	server.chat.bot_lines.clear()
	server.stations.order_asked(cap, a.slot, Net.POST_REPAIR)
	server.stations.order_asked(cap, b.slot, Net.POST_REPAIR)
	var same := false
	var done := _wait(150, func():
		if a.bot_job >= 0 and b.bot_job >= 0:
			if a.bot_job == b.bot_job:
				same = true
		return not server.air.holes.has(holes[0]) and not server.air.holes.has(holes[1]))
	_expect(done, "both holes are patched")
	_expect(not same and _logged(a, "беру пробоину") and _logged(b, "беру пробоину"), "each took a hole, never the same one")


func _free_bot_mends() -> void:
	print("  -- a free bot comes to mend, then goes back to wandering (my B2 pick)")
	_settle()
	for q in bots:
		server.stations.order_asked(cap, q.slot, Net.POST_HELM)
	var bot = bots[2]
	server.stations.order_asked(cap, bot.slot, Net.POST_FREE)
	var console: int = server.map.gun_console.keys()[0]
	server.ship.broken[console] = true
	var mended := _wait(120, func(): return not server.ship.broken.has(console))
	_expect(mended, "the gun console is mended by the free bot (doing %d, task %d)" % [bot.doing, bot.bot_task])
	_wait(2, func(): return false)
	_expect(bot.order == Net.POST_FREE and bot.bot_job < 0, "and it is free again, with no job")
	_wait(2, func(): return false)
	_expect(bot.bot_goal < 0, "it has nowhere to go: it wanders")


func _hand_over() -> void:
	print("  -- a bot with no suit hands a hole in a vacuum to a suited one (the author's comment on L1)")
	_settle()
	for k: int in server.ship.store.keys():
		if k >= Net.ITEM_SUIT and k <= Net.ITEM_SUIT + Net.SUIT_TANK_STEPS:
			server.ship.store[k] = 0
	var helm := int(server.stations.spots[Net.POST_HELM][0][0])
	var holes := _hull_cells({server.map.room_of[helm]: true})
	var hole: int = holes[0]
	var a = bots[0]
	var b = bots[1]
	a.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	_suit(b)
	server.systems.breach(hole)
	_wait(10, func(): return false)
	server.chat.bot_lines.clear()
	server.stations.order_asked(cap, a.slot, Net.POST_REPAIR)
	server.stations.order_asked(cap, b.slot, Net.POST_REPAIR)
	var shut := _wait(90, func(): return not server.air.holes.has(hole))
	_expect(_logged(a, "Передаю работу: %s" % b.name), "the bot with no suit names the suited one")
	_expect(shut and _logged(b, "беру пробоину"), "and the suited one takes the hole and patches it")


func _shut_in() -> void:
	print("  -- a suited bot shut in a room with no air gets out to its work (CI's salvagetest, 1 run in 20)")
	_settle()
	var helm := int(server.stations.spots[Net.POST_HELM][0][0])
	var hole: int = _hull_cells({server.map.room_of[helm]: true})[0]
	var room := _room_of_hole(hole)
	server.systems.breach(hole)
	_wait(30, func():
		for c: int in server.map.rooms[room]:
			if server.map.walk[c] == 1 and server.air.air[c] > 0.1:
				return false
		return true)
	server.air.set_hole(hole, false)          # mended, but its shutters stay down and the room empty
	var inside := -1
	for c: int in server.map.rooms[room]:
		if server.map.walk[c] == 1 and server.map.door_of[c] < 0 and server.air.air[c] < 0.5:
			inside = c
	var bot = bots[0]
	var sealed := true
	for d: int in _room_doors(room):
		sealed = sealed and server.doors.is_sealed(d)
	_expect(inside >= 0 and sealed, "(a room with no air, its shutters down: inside %d, sealed %s, hole %d room %d)" % [inside, sealed, hole, room])
	_suit(bot)
	_place(bot, inside)
	server.chat.bot_lines.clear()
	server.ship.tank = 100.0
	server.ship.store[Net.ITEM_FUEL] = 2
	server.stations.order_asked(cap, bot.slot, Net.POST_REPAIR)
	var poured := _wait(90, func(): return server.ship.tank >= 200.0)
	_expect(poured, "it raises a shutter and pours fuel (tank %d, task %d, goal %d)" % [floori(server.ship.tank), bot.bot_task, bot.bot_goal])
	_expect(_logged(bot, "наружу из отсека без воздуха"), "and says why it raised the shutter")


func _boarders_wreck() -> void:
	print("  -- a boarders' ship wrecked before it docks stays alongside as a wreck (the author's note)")
	var d = server.derelict
	_expect(d.pirates_come(3, false), "a boarding ship comes")
	var fuel_before := int(server.ship.store.get(Net.ITEM_FUEL, 0))
	server.gunnery._wrecked()
	_expect(d.here and d.wreck, "it stays alongside, a wreck")
	_expect(int(server.ship.store.get(Net.ITEM_FUEL, 0)) == fuel_before, "no fuel can jumps into our hold")
	var can := false
	for c: int in server.map.other_cells:
		if server.floor_things.has(c) and (server.floor_things[c] as PackedByteArray).has(Net.ITEM_FUEL):
			can = true
	_expect(can, "the fuel can lies aboard the wreck")
	_wait(2, func(): return false)
	_expect(d.here and d.wreck, "and it is still there a moment later")


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
		if OS.get_environment("BOTDEBUG") != "" and t % 20 == 0:
			for q in bots:
				print("    t%d %s at %d,%d order %d task %d goal %d step %d doing %d using %s job %d tank %.2f" % [t, q.name, q.st.x, q.st.y, q.order, q.bot_task, q.bot_goal, q.bot_step, q.doing, q.using, q.bot_job, q.tank])
	return false


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
