extends SceneTree
const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
var server: GameServer
func _initialize() -> void:
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1)
	server = GameServer.new()
	get_root().add_child(server)
	server.start(26491, "ship02", 4)
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.keep_heard = true
	var cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	var bots: Array = []
	for p in server.players:
		if p != null and p.bot and not p.corpse:
			bots.append(p)
			p.put_on(Net.ITEM_SUIT + 10)
			p.tank = 1.0
	# no air anywhere, nothing in store
	var mode := OS.get_environment("MODE")
	if mode == "" or mode == "all":
		server.ship.store_air = 0.0
		for i in server.air.air.size():
			server.air.air[i] = 0.0
	elif mode == "half":
		for i in server.air.air.size():
			if i % server.map.width < 20:
				server.air.air[i] = 0.0
	if OS.get_environment("BREAK") != "":
		var k := 0
		for c: int in server.ship.devices_all() if false else []:
			pass
		for c in server.map.oxygen.keys():
			if c % server.map.width < 20:
				server.ship.broken[c] = true
		for c in server.map.helm.keys():
			server.ship.broken[c] = true
	if OS.get_environment("REPAIR") != "":
		for q in bots:
			server.stations.order_asked(cap, q.slot, Net.POST_REPAIR)
	if OS.get_environment("ORDERS") != "":
		server.stations._all_to_posts(cap)
	server.air.settled = false
	var hole: int = server.map.hull[int(OS.get_environment("HOLE")) if OS.get_environment("HOLE") != "" else 5]
	server.air.set_hole(hole, true)
	print("hole at %d,%d" % [hole % server.map.width, hole / server.map.width])
	var forced := {}
	var lastpos := {}
	var still := {}
	for t in 120 * Net.TICK_HZ:
		cap.health = 100.0
		server._tick()
		for q in bots:
			var c: int = q.st.y * server.map.width + q.st.x
			if lastpos.get(q.slot, -1) == c:
				still[q.slot] = still.get(q.slot, 0) + 1
			else:
				still[q.slot] = 0
			lastpos[q.slot] = c
		if t % 100 == 0:
			for q in bots:
				print("t%d %s at %d,%d order %d task %d goal %d step %d doing %d using %s job %d tank %.2f still %d sh %s" % [t / 20, q.name, q.st.x, q.st.y, q.order, q.bot_task, q.bot_goal, q.bot_step, q.doing, q.using, q.bot_job, q.tank, still[q.slot], q.bot_shutters])
	var forcing := {}
	for e in cap.said:
		if str(e[2]).contains("поднимает аварийный"):
			forcing[str(e[2])] = forcing.get(str(e[2]), 0) + 1
	print("FORCED ", forcing)
	for e in server.chat.bot_lines:
		print("LOG ", e)
	quit(0)
