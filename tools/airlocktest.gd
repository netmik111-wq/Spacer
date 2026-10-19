extends SceneTree
## Checks that bots and pirates get through the airlock (v66, the author's note:
## "feels like bots cannot do it"), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/airlocktest.gd
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer
var cap
var bot
var pump := -1
var chamber := PackedInt32Array()
var inner := -1
var outer := -1


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26395, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	var map = server.map
	pump = map.lock_pump.keys()[0]
	chamber = map.lock_pump[pump]["chamber"]
	inner = map.lock_pump[pump]["inner"]
	outer = map.lock_pump[pump]["outer"]
	cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	for p in server.players:
		if p != null and p.bot and not p.corpse:
			if bot == null:
				bot = p
			else:
				server.stations.order_asked(cap, p.slot, Net.POST_FREE)
	_follow_into_chamber()
	_back_from_empty_chamber()
	_back_from_outside()
	_follow_outside()
	_follow_back_in()
	_pirate_comes_in()
	_follow_onto_docked()
	_jammed_outer()
	print("airlocktest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _reset() -> void:
	## Both doors shut, the chamber full, nobody pumping.
	server.ship.pumps.clear()
	for d in [inner, outer]:
		server.doors.ready[d] = server.doors.CLOSED
		server.doors.locked[d] = 0
		server.doors.jammed[d] = 0
		server.doors.forced[d] = 0
	for c in chamber:
		server.air.air[c] = 1.0
	server.air.settled = false


func _suit(p) -> void:
	p.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	p.tank = 1.0


func _place(p, cell: int) -> void:
	p.st.place(cell % server.map.width, cell / server.map.width)
	p.st.dir = Net.DIR_NONE


func _cell(p) -> int:
	return p.st.y * server.map.width + p.st.x


func _outside_spot() -> int:
	## Open space just past the outer door.
	var map = server.map
	var o: Vector2i = map.doors[outer]
	for d in range(1, 5):
		var x: int = o.x + Net.DX[d]
		var y: int = o.y + Net.DY[d]
		if map.floats(x, y):
			return y * map.width + x
	return -1


func _bridge_spot() -> int:
	return int(server.stations.spots[Net.POST_HELM][0][0])


func _follow_into_chamber() -> void:
	print("  -- a bot follows the captain into the airlock")
	_reset()
	_place(cap, chamber[0])
	_place(bot, _bridge_spot())
	server.stations.order_asked(cap, bot.slot, Net.POST_FOLLOW)
	var ok := _wait(40, func(): return absi(bot.st.x - cap.st.x) + absi(bot.st.y - cap.st.y) <= 1)
	_expect(ok, "it comes into the chamber beside him (at %d,%d, he at %d,%d)" % [bot.st.x, bot.st.y, cap.st.x, cap.st.y])


func _back_from_empty_chamber() -> void:
	print("  -- a bot in an emptied chamber gets back in")
	_reset()
	for c in chamber:
		server.air.air[c] = 0.0
	_suit(bot)
	_place(bot, chamber[0])
	_place(cap, _bridge_spot() + 3)
	server.stations.order_asked(cap, bot.slot, Net.POST_HELM)
	var ok := _wait(60, func(): return _inside(bot))
	_expect(ok, "it is back aboard (at %d,%d, doing %d)" % [bot.st.x, bot.st.y, bot.doing])
	_expect(_ship_air_ok(), "and the ship still has its air")


func _back_from_outside() -> void:
	print("  -- a bot out in space gets back in")
	_reset()
	for c in chamber:
		server.air.air[c] = 0.0
	_suit(bot)
	_place(bot, _outside_spot())
	server.stations.order_asked(cap, bot.slot, Net.POST_HELM)
	var ok := _wait(90, func(): return _inside(bot))
	_expect(ok, "it is back aboard (at %d,%d, doing %d)" % [bot.st.x, bot.st.y, bot.doing])
	_expect(_ship_air_ok(), "and the ship still has its air")


func _follow_outside() -> void:
	print("  -- a suited bot follows the captain out into space")
	_reset()
	_suit(bot)
	_suit(cap)
	_place(bot, _bridge_spot())
	_place(cap, _outside_spot())
	server.stations.order_asked(cap, bot.slot, Net.POST_FOLLOW)
	var store := server.ship.store_air
	var ok := _wait(90, func(): return server.map.floats(bot.st.x, bot.st.y) and absi(bot.st.x - cap.st.x) + absi(bot.st.y - cap.st.y) <= 2)
	_expect(ok, "it goes out after him (at %d,%d, he at %d,%d, doing %d)" % [bot.st.x, bot.st.y, cap.st.x, cap.st.y, bot.doing])
	_expect(server.ship.store_air > store, "pumping the chamber's air into the store first (%.2f -> %.2f)" % [store, server.ship.store_air])
	_expect(_ship_air_ok(), "and the ship still has its air")


func _follow_back_in() -> void:
	print("  -- and back in after him")
	_place(cap, _bridge_spot() + 2)
	var ok := _wait(90, func(): return _inside(bot) and absi(bot.st.x - cap.st.x) + absi(bot.st.y - cap.st.y) <= 1)
	_expect(ok, "it comes back in beside him (at %d,%d, doing %d)" % [bot.st.x, bot.st.y, bot.doing])
	_expect(_ship_air_ok(), "and the ship still has its air")
	server.stations.order_asked(cap, bot.slot, Net.POST_FREE)


func _pirate_comes_in() -> void:
	print("  -- a pirate in a suit comes in through the airlock")
	_reset()
	for c in chamber:
		server.air.air[c] = 0.0
	var spot := _outside_spot()
	var pir = server.pirates.spawn(spot % server.map.width, spot / server.map.width, true)
	_suit(pir)
	_place(cap, _bridge_spot())
	var ok := _wait(90, func(): return pir.corpse or pir.cond != Net.COND_OK or _inside(pir))
	_expect(ok, "it gets aboard (at %d,%d)" % [pir.st.x, pir.st.y])
	server.crew.remove(pir)


func _inside(p) -> bool:
	## Aboard past the airlock: not in its chamber nor in either of its doors.
	var c: int = _cell(p)
	var door: int = server.map.door_of[c]
	return server.map.on_ship(c) and not chamber.has(c) and door != inner and door != outer


func _follow_onto_docked() -> void:
	print("  -- a bot follows the captain onto a ship docked at the airlock")
	_reset()
	var map = server.map
	var d = server.derelict
	server.sectors.kind[server.ship.sector] = Sectors.DERELICT
	server.sectors.reach[server.ship.sector] = Sectors.DOCK_RANGE
	server.ship.pos = server.sectors.spot[server.ship.sector]
	server.ship.dest = server.ship.pos
	_wait(1, func(): return false)
	_expect(d.here and d.dock(true) == "" and d.docked, "a derelict docks at the airlock")
	for c in map.other_cells:
		if map.walk[c] == 1:
			server.air.air[c] = 0.85
	var beyond: int = map.lock_beyond(pump)
	var best := -1
	for c in map.other_cells:
		if map.walk[c] == 1 and map.door_of[c] < 0 and absi(c % map.width - beyond % map.width) <= 1 and c / map.width < beyond / map.width - 1:
			if best < 0 or c / map.width > best / map.width:
				best = c
	bot.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	_place(bot, _bridge_spot())
	_place(cap, best)
	server.stations.order_asked(cap, bot.slot, Net.POST_FOLLOW)
	var ok := _wait(90, func(): return map.is_other(_cell(bot)) and absi(bot.st.x - cap.st.x) + absi(bot.st.y - cap.st.y) <= 1)
	_expect(ok, "it comes aboard it beside him, without a suit (at %d,%d, he at %d,%d, doing %d)" % [bot.st.x, bot.st.y, cap.st.x, cap.st.y, bot.doing])
	server.stations.order_asked(cap, bot.slot, Net.POST_HELM)
	ok = _wait(90, func(): return _inside(bot))
	ok = ok and bot.cond == Net.COND_OK
	_expect(ok, "and back aboard ours when sent to its post (at %d,%d, doing %d)" % [bot.st.x, bot.st.y, bot.doing])
	for c in map.other_cells:
		server.air.air[c] = 0.0
	server.stations.order_asked(cap, bot.slot, Net.POST_FOLLOW)
	_wait(20, func(): return false)
	_expect(_inside(bot) and bot.cond == Net.COND_OK, "but without a suit it will not follow him into a vacuum (at %d,%d, doing %d)" % [bot.st.x, bot.st.y, bot.doing])
	server.stations.order_asked(cap, bot.slot, Net.POST_FREE)
	d.dock(false)


func _jammed_outer() -> void:
	print("  -- the outer door is stuck open")
	_reset()
	server.derelict._leave(true)
	for c in chamber:
		server.air.air[c] = 0.0
	server.doors.ready[outer] = server.tick
	server.doors.jammed[outer] = 1
	_suit(bot)
	_suit(cap)
	_place(bot, _bridge_spot())
	_place(cap, _outside_spot())
	server.stations.order_asked(cap, bot.slot, Net.POST_FOLLOW)
	_wait(40, func(): return false)
	_expect(server.doors.is_shut(inner) and _ship_air_ok(), "a bot will not override the inner door's lock and let the ship's air out")
	server.stations.order_asked(cap, bot.slot, Net.POST_FREE)


func _ship_air_ok() -> bool:
	var at: int = _bridge_spot()
	return server.air.air[at] > 0.7


func _wait(seconds: int, done: Callable) -> bool:
	for t in seconds * Net.TICK_HZ:
		cap.health = 100.0
		cap.wounds = 0.0
		cap.tank = 1.0
		server._tick()
		if done.call():
			return true
		if OS.get_environment("LOCKDEBUG") != "" and t % 20 == 0:
			print("    t%d bot %d,%d step %d lock %d using %s work %d | inner r%d l%d f%d | outer r%d l%d f%d | air %.2f pumps %s" % [t, bot.st.x, bot.st.y, bot.bot_step, bot.bot_lock, bot.using, bot.work,
				server.doors.ready[inner] - server.tick, server.doors.locked[inner], server.doors.forced[inner], server.doors.ready[outer] - server.tick, server.doors.locked[outer], server.doors.forced[outer], server.systems.lock_air(pump), server.ship.pumps])
	return false


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
