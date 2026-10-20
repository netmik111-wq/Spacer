extends SceneTree
const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
var server: GameServer
var cap
var bots: Array = []
func _initialize() -> void:
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1)
	server = GameServer.new()
	get_root().add_child(server)
	server.start(26492, "ship02", 4)
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.vents_on = OS.get_environment("VENTS") != ""
	server.keep_heard = true
	cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	for p in server.players:
		if p != null and p.bot and not p.corpse:
			bots.append(p)
	var walk: Array = []
	for c in server.map.walk.size():
		if server.map.walk[c] == 1 and server.map.on_ship(c) and server.map.door_of[c] < 0:
			walk.append(c)
	var n := 0
	for hole: int in server.map.hull:
		n += 1
		if n % 3 != 0:
			continue
		for c: int in server.air.holes.keys():
			server.air.set_hole(c, false)
		if OS.get_environment("CUMUL") == "":
			for c in server.air.air.size():
				if server.map.on_ship(c) and server.map.walk[c] == 1:
					server.air.air[c] = 1.0
		else:
			server.ship.store_air = 0.0
		server.air.settled = false
		server.ship.broken.clear()
		server.ship.store[Net.ITEM_PATCH] = 10
		server.ship.store[Net.ITEM_PART] = 10
		for q in bots:
			q.health = 100.0
			q.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
			q.tank = 1.0
			var c: int = walk[server.rng.randi_range(0, walk.size() - 1)]
			if OS.get_environment("CUMUL") == "":
				q.st.place(c % server.map.width, c / server.map.width)
			q.st.dir = 0
			q.bot_plan_tick = -1000
			server.stations.order_asked(cap, q.slot, Net.POST_REPAIR if server.rng.randf() < 0.7 else Net.POST_FREE)
		cap.said.clear()
		server.systems.breach(hole)
		var fixed_at := -1
		for t in 90 * Net.TICK_HZ:
			cap.health = 100.0
			server._tick()
			if fixed_at < 0 and not server.air.holes.has(hole):
				fixed_at = t / 20
			if OS.get_environment("DBG") != "" and t % 200 == 0 and hole % server.map.width == int(OS.get_environment("DBG")) and hole / server.map.width == 19:
				for q in bots:
					print("    t%d %s at %d,%d hp %.0f cond %d order %d task %d goal %d step %d doing %d using %s job %d tank %.2f sh %s air %.2f" % [t / 20, q.name, q.st.x, q.st.y, q.health, q.cond, q.order, q.bot_task, q.bot_goal, q.bot_step, q.doing, q.using, q.bot_job, q.tank, q.bot_shutters, server.air.air[q.st.y * server.map.width + q.st.x]])
		var forcing := {}
		for e in cap.said:
			if str(e[2]).contains("поднимает аварийный"):
				forcing[str(e[2])] = forcing.get(str(e[2]), 0) + 1
		var bad := ""
		for k in forcing:
			if forcing[k] > 1:
				bad += " %s x%d" % [k, forcing[k]]
		print("hole %d,%d fixed %d%s" % [hole % server.map.width, hole / server.map.width, fixed_at, bad])
		if bad != "" and OS.get_environment("STOP") != "":
			break
	quit(0)
