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
##   --inproc           when hosting, run the server inside the game instead of a process of its own
## Other keys: F11 toggles full screen.
## Used by the game itself when it starts a server for a hosted game:
##   --autoquit (stop once the server has stayed empty), token=TEXT (lets that game stop it).
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
var _server_pid := -1                # the server started for a hosted game, when it runs as its own process
var _server_token := ""
var _server_started := 0.0
var _host_name := ""
var _host_tries := 0
var _host_bots := 0
var _empty_since := 0.0              # dedicated server with --autoquit: when it last had a player
var _had_players := false

const FPS_ACTIVE := 60
const FPS_BACKGROUND := 30
const EMPTY_QUIT_SEC := 15.0         # a hosted game's server stops this long after the last player left
const NOBODY_CAME_SEC := 40.0

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
		_server.shutdown_token = str(_opt.get("token", ""))
		_server.shutdown_requested.connect(func() -> void: _quit_server.call_deferred())
		var problem := _server.start(port, "ship01", bots)
		if problem != "":
			printerr(problem)
			get_tree().quit(1)
		else:
			print("Остановить сервер: закройте это окно или нажмите Ctrl+C.")
		_empty_since = _t_start
		return

	# The picture changes 20 times a second at most, so drawing faster than
	# 60 frames only heats the graphics card on a fast monitor.
	Engine.max_fps = FPS_ACTIVE
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


func _quit_server() -> void:
	# dedicated server: stop for good
	if _server != null:
		_server.stop()
	get_tree().quit()


func _stop_server(wait_ms: int = 1500) -> void:
	if _server != null:
		_server.stop()
		_server.queue_free()
		_server = null
	if _server_pid > 0:
		# It was asked to stop (see _leave); give it a moment to tell the other
		# players, then make sure it is gone and the port is free again.
		var deadline := Time.get_ticks_msec() + wait_ms
		while OS.is_process_running(_server_pid) and Time.get_ticks_msec() < deadline:
			OS.delay_msec(20)
		if OS.is_process_running(_server_pid):
			OS.kill(_server_pid)
		_server_pid = -1


func _start_server_process(port: int, bots: int) -> bool:
	## Runs the server as a second copy of the game without a window. A server
	## inside the game would freeze for everybody whenever this window is
	## dragged, resized or otherwise held up; a separate process does not care.
	_server_token = "%08x%08x" % [randi(), randi()]
	var args := PackedStringArray(["--headless"])
	if OS.has_feature("editor"):         # started from the editor: the program is Godot itself
		args.append_array(PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]))
	args.append_array(PackedStringArray(["--", "--server", "--autoquit",
		"port=%d" % port, "bots=%d" % bots, "token=%s" % _server_token]))
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	_server_started = Time.get_ticks_msec() / 1000.0
	return _server_pid > 0


func _host_game(player: String, port: int, bots: int) -> void:
	_stop_server()
	_hosting = true
	_host_name = player
	_host_bots = bots
	if not _flags.has("inproc") and _start_server_process(port, bots):
		_host_tries = 3
		if _connect(player, "127.0.0.1", port):
			_menu.show_status("Запуск сервера…")
		return
	_host_inside(port)


func _host_inside(port: int) -> void:
	## The server inside the game itself: the fallback when a separate process
	## cannot be started. It also reports a busy port in plain words.
	_stop_server(0)
	_show_menu("")
	_server = GameServer.new()
	add_child(_server)
	var problem := _server.start(port, "ship01", _host_bots)
	if problem != "":
		_stop_server()
		_show_menu(problem, true)
		return
	_connect(_host_name, "127.0.0.1", port)


func _join_game(player: String, address: String, port: int) -> void:
	_stop_server()
	_hosting = false
	_connect(player, address, port)


func _connect(player: String, address: String, port: int) -> bool:
	_pending_port = port
	var problem := _client.connect_to(address, port, player)
	if problem != "":
		_stop_server(0)
		_show_menu(problem, true)
		return false
	_menu.set_busy(true)
	_menu.show_status("Подключение к %s:%d…" % [address, port])
	return true


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
	if _server_pid > 0:
		if OS.is_process_running(_server_pid) and _host_tries > 0:
			_host_tries -= 1             # our own server is still starting up: try again
			_connect.call_deferred(_host_name, "127.0.0.1", _pending_port)
		else:
			_host_inside.call_deferred(_pending_port)   # it never came up: host the old way
		return
	_stop_server(0)
	_show_menu(reason, true)


func _on_lost(reason: String) -> void:
	_stop_server(0)
	_show_menu(reason, true)


func _leave() -> void:
	_client.stop_server_and_close(_server_token if _server_pid > 0 else "")
	_stop_server()
	_show_menu("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _client != null:
			_client.stop_server_and_close(_server_token if _server_pid > 0 else "")
		_stop_server(600)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _client != null:
			Engine.max_fps = FPS_BACKGROUND
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _client != null:
			Engine.max_fps = FPS_ACTIVE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 - _t_start
	if _flags.has("server") and _flags.has("autoquit") and _server != null:
		# Started by a player's game. If that game dies without saying goodbye,
		# do not stay behind forever: stop once nobody is left.
		if _server.player_count() > 0:
			_had_players = true
			_empty_since = t + _t_start
		elif t + _t_start - _empty_since > (EMPTY_QUIT_SEC if _had_players else NOBODY_CAME_SEC):
			_quit_server()
			return
	if _server_pid > 0 and _client != null and _client.phase != GameClient.IDLE and not OS.is_process_running(_server_pid):
		# our server process is gone: say so at once instead of waiting for a timeout
		_client.close()
		_server_pid = -1
		if Time.get_ticks_msec() / 1000.0 - _server_started < 5.0:
			# It quit straight after starting: a busy port, or it cannot run this
			# way on this computer. Host inside the game instead.
			_host_inside(_pending_port)
		else:
			_show_menu("Сервер остановился.", true)
	# test helpers; unused in normal play
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
			_client.stop_server_and_close(_server_token if _server_pid > 0 else "")
		_stop_server()
		get_tree().quit()
