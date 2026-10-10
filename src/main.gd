extends Node
## Entry point. Decides what this run is (dedicated server, or the game with
## its menu) and switches between the menu and the game screen.
##
## Options go after "--" on the command line:
##   --server            run only the server, no window (use with --headless)
##   port=24500          port to listen on / connect to
##   bots=2              wandering bots on a server
##   --host              create a game straight away (skips the menu)
##   join=ADDRESS        join a game straight away
##   name=NAME           player name for --host / join
## Other keys: F11 toggles full screen.
## Test helpers: --demo (walk around without a keyboard), demo_until=SECONDS,
## path=DIR:SECONDS,... (scripted walk), trace=FILE (positions every frame),
## say=TEXT (send a chat line), --debug (show the F3 overlay),
## quit_after=SECONDS, shot=FILE.png with shot_after=SECONDS, stats=FILE.json.

const Net := preload("res://src/shared/net.gd")
const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const GameScreen := preload("res://src/ui/game_screen.gd")
const MainMenu := preload("res://src/ui/main_menu.gd")

var _server: GameServer = null
var _client: GameClient = null
var _menu: MainMenu = null
var _screen: GameScreen = null
var _pending_port := Net.DEFAULT_PORT
var _hosting := false

var _opt := {}
var _flags := {}
var _t_start := 0.0
var _shot_done := false
var _path_t0 := -1.0
var _said := false
var _debug_shown := false
var _pause_shown := false
var _rehosted := false
var _trace: FileAccess = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			_flags[a.substr(2)] = true
		elif a.contains("="):
			var i := a.find("=")
			_opt[a.substr(0, i)] = a.substr(i + 1)
	_t_start = Time.get_ticks_msec() / 1000.0
	var port := int(_opt.get("port", Net.DEFAULT_PORT))
	var bots := int(_opt.get("bots", 0))

	if _flags.has("server"):
		Engine.max_fps = 60
		_server = GameServer.new()
		add_child(_server)
		_server.log_line.connect(func(text: String) -> void: print(text))
		var problem := _server.start(port, "ship01", bots)
		if problem != "":
			printerr(problem)
			get_tree().quit(1)
		else:
			print("Остановить сервер: закройте это окно или нажмите Ctrl+C.")
		return

	if DisplayServer.get_name() == "headless":
		Engine.max_fps = 60          # no display to wait for: do not spin the CPU
	_define_inputs()
	_client = GameClient.new()
	add_child(_client)
	_client.joined.connect(_on_joined)
	_client.failed.connect(_on_failed)
	_client.lost.connect(_on_lost)
	_show_menu("")
	var player := str(_opt.get("name", ""))
	if _flags.has("host"):
		_host_game(player if player != "" else "Игрок", port, bots)
	elif _opt.has("join"):
		_join_game(player if player != "" else "Игрок", str(_opt["join"]), port)


func _define_inputs() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"chat": [KEY_ENTER, KEY_KP_ENTER], "pause": [KEY_ESCAPE],
		"debug": [KEY_F3], "toggle_predict": [KEY_F4], "fullscreen": [KEY_F11],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key   # physical keys: WASD works on any keyboard layout
			InputMap.action_add_event(action, ev)


func _show_menu(message: String, is_error: bool = false) -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
	if _menu == null:
		_menu = MainMenu.new()
		add_child(_menu)
		_menu.host_requested.connect(_host_game)
		_menu.join_requested.connect(_join_game)
		_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_menu.visible = true
	_menu.set_busy(false)
	_menu.show_status(message, is_error)


func _stop_server() -> void:
	if _server != null:
		_server.stop()
		_server.queue_free()
		_server = null


func _host_game(player: String, port: int, bots: int) -> void:
	_stop_server()
	_server = GameServer.new()
	add_child(_server)
	var problem := _server.start(port, "ship01", bots)
	if problem != "":
		_stop_server()
		_show_menu(problem, true)
		return
	_hosting = true
	_connect(player, "127.0.0.1", port)


func _join_game(player: String, address: String, port: int) -> void:
	_stop_server()
	_hosting = false
	_connect(player, address, port)


func _connect(player: String, address: String, port: int) -> void:
	_pending_port = port
	var problem := _client.connect_to(address, port, player)
	if problem != "":
		_stop_server()
		_show_menu(problem, true)
		return
	_menu.set_busy(true)
	_menu.show_status("Подключение к %s:%d…" % [address, port])


func _on_joined() -> void:
	_menu.visible = false
	_screen = GameScreen.new()
	add_child(_screen)
	_screen.demo_walk = _flags.has("demo")
	if _opt.has("predict"):
		_client.predict = str(_opt["predict"]) != "0"
	_screen.setup(_client, _hosting, _pending_port)
	_screen.exit_requested.connect(_leave)


func _on_failed(reason: String) -> void:
	_stop_server()
	_show_menu(reason, true)


func _on_lost(reason: String) -> void:
	_stop_server()
	_show_menu(reason, true)


func _leave() -> void:
	_client.close()
	_stop_server()
	_show_menu("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _client != null:
			_client.close()
		_stop_server()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(_delta: float) -> void:
	# test helpers; unused in normal play
	var t := Time.get_ticks_msec() / 1000.0 - _t_start
	if _opt.has("path") and _screen != null:
		# "4:1.5,0:0.5,3:1.5" = hold right 1.5 s, stand 0.5 s, hold left 1.5 s (after joining)
		if _path_t0 < 0.0:
			_path_t0 = t
		var at := t - _path_t0
		var dir := 0
		for leg: String in str(_opt["path"]).split(","):
			var parts := leg.split(":")
			if at < float(parts[1]):
				dir = int(parts[0])
				break
			at -= float(parts[1])
		_screen.forced_dir = dir
	if _opt.has("say") and _screen != null and not _said and t >= float(_opt.get("say_after", 3.0)):
		_said = true
		_client.send_chat(str(_opt["say"]))
	if _opt.has("rehost_after") and not _rehosted and _screen != null and t >= float(_opt["rehost_after"]):
		_rehosted = true                 # leave to the menu and create a game again, like a player would
		_leave()
		_host_game("Снова", int(_opt.get("port", Net.DEFAULT_PORT)), 1)
	if _flags.has("pause") and _screen != null and not _pause_shown and t >= 2.0:
		_pause_shown = true
		_screen.show_pause(true)
	if _flags.has("debug") and _screen != null and not _debug_shown:
		_debug_shown = true
		_screen.show_debug(true)
	if _opt.has("trace") and _client != null and _client.phase == GameClient.PLAYING:
		if _trace == null:
			_trace = FileAccess.open(str(_opt["trace"]), FileAccess.WRITE)
		var line := "%d w%d" % [Time.get_ticks_usec(), _client.want_dir]
		for id: int in _client.ents.keys():
			var smp := _client.sample(id)
			if not smp.is_empty():
				var pos: Vector2 = smp[0]
				line += " %d:%.4f:%.4f" % [id, pos.x, pos.y]
		_trace.store_line(line)
	if _opt.has("shot") and not _shot_done and t >= float(_opt.get("shot_after", 3.0)):
		_shot_done = true
		get_viewport().get_texture().get_image().save_png(str(_opt["shot"]))
	if _opt.has("demo_until") and _screen != null and t >= float(_opt["demo_until"]):
		_screen.demo_walk = false
	if _opt.has("quit_after") and t >= float(_opt["quit_after"]):
		if _opt.has("stats") and _client != null:
			var f := FileAccess.open(str(_opt["stats"]), FileAccess.WRITE)
			var mine: GameClient.Ent = _client.ents.get(_client.my_id)
			if f != null:
				f.store_string(JSON.stringify({
					"phase": _client.phase, "my_id": _client.my_id, "players": _client.roster.size(),
					"entities": _client.ents.size(), "rtt_ms": _client.rtt_ms,
					"mispredicts": _client.mispredicts, "checks_ok": _client.checks_ok,
					"checks_bad": _client.checks_bad, "packets_in": _client.packets_in,
					"bytes_in": _client.bytes_in, "pred_x": _client.pred.x, "pred_y": _client.pred.y,
					"steps_predicted": _client.steps_predicted,
					"auth_x": mine.x if mine != null else -1, "auth_y": mine.y if mine != null else -1,
				}))
		if _client != null:
			_client.close()
		_stop_server()
		get_tree().quit()
