extends SceneTree
## How long the server takes to work out who each player sees, without a
## network: N wandering bots, each judged as if a client were watching.
##   godot --headless --path . --script res://tools/sightbench.gd -- 32 400

const GameServer := preload("res://src/server/game_server.gd")
const Player := preload("res://src/server/player.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 32
	var ticks := int(args[1]) if args.size() > 1 else 400
	var server := GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26290, "ship02", n)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var usec := 0
	var calls := 0
	for t in ticks:
		server._tick()
		var t0 := Time.get_ticks_usec()
		for p: Player in server.players:
			if p != null and not p.corpse:
				p.view_cx = p.st.x >> 4
				p.view_cy = server.map.local_y(p.st.y) >> 4
				server.replication._characters(p, false)
				calls += 1
		usec += Time.get_ticks_usec() - t0
	print("bots %d, ticks %d: who-sees-whom %.2f ms a tick (%.1f us a player)" % [n, ticks, usec / 1000.0 / ticks, float(usec) / maxi(calls, 1)])
	server.stop()
	quit(0)
