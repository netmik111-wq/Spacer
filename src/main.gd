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
##   campaign=continue   a server goes on with the saved campaign, if there is one (the default);
##                       campaign=new starts a new one (the old save is overwritten at the first autosave),
##                       campaign=off neither reads nor writes a save
##   mode=normal         (v63) a new campaign's mode: easy, normal or hard (a continued one keeps its own);
##                       (v71) "+complex" or "+plain" after it turns complex repairs on or off (the hard mode has them on)
##   map=ship02          (v84) a new campaign's ship: ship02, or ships:NAME for a drawing of one's own in the
##                       «ships» folder (a continued campaign keeps the ship of its save); --own_others: one's own
##                       pirate ships, derelicts and asteroids come in the run too
##   --editor           (v81) open the ship editor straight away; editor_open=PATH opens that drawing in it
##                       (res://maps/ship02.txt, or a file of one's own); with try_after=SECONDS its «Попробовать»
## Other keys: F11 toggles full screen.
## Used by the game itself when it starts a server for a hosted game:
##   --autoquit (stop once the server has stayed empty), token=TEXT (lets that game stop it).
## Test helpers: --demo (walk around without a keyboard), demo_until=SECONDS,
## path=DIR:SECONDS,... (scripted walk), trace=FILE (positions every frame),
## say=TEXT (send a chat line), --debug (show the F3 overlay),
## quit_after=SECONDS, shot=FILE.png with shot_after=SECONDS, stats=FILE.json,
## bench=FILE.json (dedicated server: every tick's length, written on quit_after; see tools/bench.sh),
## breach_after=SECONDS / seal_after=SECONDS (the host's test tools; on a
## dedicated server breach_after tears a random hole), suit_after=SECONDS (turn
## the oxygen supply on), use_after=SECONDS (hold the "use" key from then on),
## --respawn (come back by itself after dying), goto=X,Y,FACING (walk to a cell
## along its row, then turn; with goto_after=SECONDS; several cells go in turn,
## split by ";"; Y counts through all decks, so the second deck starts at 16),
## climb_at=N (press "use" once on reaching the N-th goto cell, counted from 1:
## that takes a ladder), jump_after=SECONDS (ask
## for a jump to the first sector in reach), event_after=SECONDS with event=ID
## (the host fires a director event), console_after=SECONDS (open the console
## the character faces), panel=inventory|crew|help|admin|options|pause|trade with panel_after=SECONDS (open that
## window), --no-events (dedicated server: the director stays quiet),
## helm_after=SECONDS with helm=X,Y (set a course inside the sector; helm=out
## steers straight out of a meteor stream, helm=spot to the station or trader).
## With --inproc only: warp_after=SECONDS with warp_kind=KIND (jump to a sector
## of that kind, whatever the routes), break_helm_after=SECONDS, --log (print
## the server's messages), door_trouble_after=SECONDS with door_trouble=jam|down|up
## (the door the character faces jams open, or its shutter fails down or up),
## dock_after=SECONDS (the ship is put right at the sector's station or trader).
## volley_after=SECONDS (v56: from then on, every second, every gun of ours fires
## at the pirate ship alongside and it fires a laser back that always hits; with
## --noshield our shield is off first, so its shots land on the hull).
## drag_after=SECONDS (take hold of whoever lies next to the character),
## search_after=SECONDS (go through their pockets), loot_after=SECONDS (take
## the first thing found there), faint_after=SECONDS with --inproc (the other
## characters aboard fall unconscious, one of them right in front of ours, for
## trying the three above). hand=N with hand_after=SECONDS (take slot N, counted
## from 0, into the hand), take=ITEM with take_after=SECONDS (take that thing from
## the supply locker the character faces), act_after=SECONDS (use the thing in
## the hand: switch a flashlight), drop_after=SECONDS (put it down),
## pick_after=SECONDS (press "use" once: picks up what lies in front or underfoot).
## (v78) lie_after=SECONDS (lie down, as the C key does). (v82) rise_after=SECONDS (get up again).
## (v77) aim=DX,DY (the mouse is taken to be that many cells from our character: the eyes turn to it).
## --demo, goto, path, click and hover look where they walk (the view does not follow the mouse).
## hover=DX,DY (the mouse is taken to be that many cells from our character: the outline of anything usable there).
## click=X,Y with click_after=SECONDS (a left click on that cell, as the mouse would).
## drone_after=SECONDS (send the scouting drone from the drone monitor the character faces),
## with steer=DIR,SECONDS;DIR,SECONDS... (then steer it: DIR 1 up, 2 down, 3 left, 4 right, 0 stop),
## probe_after=SECONDS (launch a probe from the gun console the character faces).
## Dedicated server: board_after=SECONDS (pirates come aboard then),
## derelict_after=SECONDS (a derelict comes alongside then and docks at once;
## also with --inproc, and --nodock leaves it alongside),
## pirateship_after=SECONDS (a pirate ship comes then, and docks by force 15 s later).
## With --inproc only: give=ITEM with give_after=SECONDS (the thing appears in
## the character's hand, or its first free slot), place=X,Y with place_after=SECONDS
## (the character is put in that cell), dockship_after=SECONDS (dock with the derelict alongside),
## restock_after=SECONDS (v65: the admin's «refill the supply locker»),
## (v82) hurt=N with hurt_after=SECONDS (our character takes a wound of N; with --in_doc it is put on an autodoc's bed), weld_after=SECONDS (every door welded).
## (v62, --inproc only) enemy_after=SECONDS with enemy_class=K (a pirate ship of that class, Net.ECLASS_*,
## comes to fight at a distance), assault_after=SECONDS (an assault drone lands aboard at once),
## robot_after=SECONDS (one of our security robots is set down beside the character).

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const GameScreen := preload("res://src/ui/game_screen.gd")
const MainMenu := preload("res://src/ui/main_menu.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Sounds := preload("res://src/client/sounds.gd")
const CrewArt := preload("res://src/client/crew_art.gd")
const Music := preload("res://src/client/music.gd")
const Options := preload("res://src/client/options.gd")
const Player := preload("res://src/server/player.gd")
const ShipEditor := preload("res://src/ui/ship_editor.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")

var _placed := false
var _derelicted := false
var _pirateshipped := false
var _enemied := false                # (v62) the screenshot options above
var _assaulted := false
var _roboted := false
var _dockship := false
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
var _host_campaign := "continue"    # a hosted game goes on with the saved campaign, or starts a new one
var _host_mode := "normal"           # (v63) and the mode a new one is played in (Net.MODE_KEYS)
var _host_map := "ship02"            # (v81) the ship a hosted game is played on
var _host_own := false               # (v84, the author's H5) one's own other drawings come in the run
var _editor: ShipEditor = null       # (v81) the ship editor, kept while the game runs so its undo survives a try
var _trial := ""                     # (v81) the kind of drawing «Попробовать» is playing ("" = a real game)
var _tried := false
var _empty_since := 0.0              # dedicated server with --autoquit: when it last had a player
var _had_players := false

const FPS_ACTIVE := 60                # until the player's own limit is read (see Options.max_fps)
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
var _breached := false
var _sealed := false
var _suited := false
var _jumped := false
var _evented := false
var _consoled := false
var _paneled := false
var _helmed := false
var _warped := false
var _helm_broken := false
var _climbed := false
var _door_troubled := false
var _docked := false
var _dragged := false
var _searched := false
var _looted := false
var _fainted := false
var _handed := false
var _taken := false
var _acted := false
var _lain := false                      # (v78) lie_after done
var _risen := false                     # (v82) rise_after done
var _droned := false
var _probed := false
var _steers: Array = []              # [direction, seconds] still to send to the drone
var _steer_at := 0.0
var _dropped := false
var _picked := false
var _given := false
var _restocked := false
var _hurt := false                      # (v82) hurt_after done
var _welded := false                    # (v82) weld_after done
var _boarded := false
var _goto_at := 0
var _next_volley := 0.0
var _clicked := false
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
		_server.director.auto = not _flags.has("no-events")
		_server.shutdown_requested.connect(func() -> void: _quit_server.call_deferred())
		_server.measure = _opt.has("bench")
		_set_mode(_server, str(_opt.get("mode", "normal")))
		var how := str(_opt.get("campaign", "continue"))
		var problem := _server.start(port, _prepare_ships(how, str(_opt.get("map", "ship02")), _flags.has("own_others")), bots)
		if problem == "":
			problem = _open_campaign(_server, str(_opt.get("campaign", "continue")))
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
	_define_inputs()                     # (sets the frame limit the player chose)
	Sounds.prepare()
	CrewArt.sheet()                      # (v85) the people's sheet, made before joining (as the sounds)
	add_child(Music.new())               # (v75) the music, for the whole run
	_client = GameClient.new()
	add_child(_client)
	_client.joined.connect(_on_joined)
	_client.failed.connect(_on_failed)
	_client.lost.connect(_on_lost)
	_show_menu("")
	if _flags.has("editor"):
		_open_editor()
		if _opt.has("editor_open"):
			_editor.open_path(str(_opt["editor_open"]))
	var player := str(_opt.get("name", ""))
	if _flags.has("host"):
		_host_game(player if player != "" else "Игрок", port, bots)
	elif _opt.has("join"):
		_join_game(player if player != "" else "Игрок", str(_opt["join"]), port)


func _define_inputs() -> void:
	## The keys, the sound and the picture, as the player set them (see Options).
	Options.load_all()
	Options.apply_video()


func _show_menu(message: String, is_error: bool = false) -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
	if _trial != "":
		# (v81) back from «Попробовать» to the editor, as it was
		_trial = ""
		ShipMap.try_other = ""
		_host_map = "ship02"
		if _menu != null:
			_menu.visible = false
			_menu.set_busy(false)
		_editor.back_from_try()
		if message != "":
			_editor._note(message)
		if Music.current != null:
			Music.current.play(Sounds.MUSIC_MENU)
		return
	if _menu == null:
		_menu = MainMenu.new()
		add_child(_menu)
		_menu.host_requested.connect(_host_game)
		_menu.join_requested.connect(_join_game)
		_menu.quit_requested.connect(func() -> void: get_tree().quit())
		_menu.editor_requested.connect(_open_editor)
	_menu.visible = true
	_menu.set_busy(false)
	_menu.refresh_ships()                # (v84) the editor may have saved a new ship
	if Music.current != null:
		Music.current.play(Sounds.MUSIC_MENU)
	_menu.show_status(message, is_error)


func _open_editor() -> void:
	## (v81) The ship editor, from the main menu.
	if _editor == null:
		_editor = ShipEditor.new()
		add_child(_editor)
		_editor.closed.connect(func() -> void:
			_editor.visible = false
			_show_menu(""))
		_editor.try_requested.connect(_try_ship)
	_menu.visible = false
	_editor.visible = true


func _try_ship(ship: String, kind: String) -> void:
	## (v81, the author's E10) «Попробовать»: a game alone, at once, on the drawing: our own ship is
	## played on; any other kind lies at the airlock of the game's ship. The server runs inside the game
	## (ShipMap.try_other is read by both sides), with no save and no events.
	_trial = kind
	ShipMap.drawings = {}                # (v84) the drawing as it is now, not as an earlier try read it
	ShipMap.own_others = []
	ShipMap.try_other = "" if kind == "ship" else ShipMap.USER_PREFIX + ship
	_host_map = ShipMap.USER_PREFIX + ship if kind == "ship" else "ship02"
	_editor.visible = false
	_stop_server()
	_hosting = true
	_host_name = _menu.player_name()
	_host_bots = 0
	_host_campaign = "off"
	_host_mode = "normal"
	_server_token = "%08x%08x" % [randi(), randi()]
	_tried = false
	_menu.visible = true
	_host_inside(_pending_port if _pending_port > 0 else Net.DEFAULT_PORT)


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


static func _prepare_ships(how: String, wanted: String, own: bool, path: String = Campaign.PATH) -> String:
	## (v84) The ship a hosted game is played on, with the drawings of one's own it uses ready in ShipMap: a
	## continued campaign's from its save (the author's H4: the save keeps its own copies, so the drawing may
	## change since), a new one's from the «ships» folder as they are now.
	ShipMap.drawings = {}
	ShipMap.own_others = []
	if how == "continue":
		var data := Campaign.read(path)
		if not data.is_empty():
			var kept: Dictionary = data.get("drawings", {})
			for n: String in kept:
				ShipMap.drawings[n] = str(kept[n])
			for n: Variant in data.get("own_others", []):
				ShipMap.own_others.append(str(n))
			return str(data.get("map", "ship02"))
	if own:
		ShipMap.own_others = ShipMap.coming_in_run()
	return wanted


func _open_campaign(server: GameServer, how: String) -> String:
	## Where the server keeps its campaign, and whether it goes on with the saved one.
	if how == "off":
		return ""
	server.save_path = Campaign.PATH
	if how == "new":
		Campaign.forget()
		return ""
	return server.resume_campaign()


func _start_server_process(port: int, bots: int) -> bool:
	## Runs the server as a second copy of the game without a window. A server
	## inside the game would freeze for everybody whenever this window is
	## dragged, resized or otherwise held up; a separate process does not care.
	var args := PackedStringArray(["--headless"])
	if OS.has_feature("editor"):         # started from the editor: the program is Godot itself
		args.append_array(PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]))
	args.append_array(PackedStringArray(["--", "--server", "--autoquit",
		"port=%d" % port, "bots=%d" % bots, "token=%s" % _server_token, "campaign=%s" % _host_campaign,
		"mode=%s" % _host_mode, "map=%s" % _host_map]))
	if _host_own:
		args.append("--own_others")
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	_server_started = Time.get_ticks_msec() / 1000.0
	return _server_pid > 0


func _host_game(player: String, port: int, bots: int, campaign: String = "", mode: String = "",
		ship: String = "", own: bool = false) -> void:
	_stop_server()
	_host_campaign = campaign if campaign != "" else str(_opt.get("campaign", "continue"))
	_host_mode = mode if mode != "" else str(_opt.get("mode", "normal"))
	_host_map = ship if ship != "" else str(_opt.get("map", "ship02"))   # (v84, the author's H2)
	_host_own = own or _flags.has("own_others")
	_hosting = true
	_host_name = player
	_host_bots = bots
	_server_token = "%08x%08x" % [randi(), randi()]   # lets this game, and nobody else, command the server
	if not _flags.has("inproc") and _start_server_process(port, bots):
		_host_tries = 3
		if _connect(player, "127.0.0.1", port):
			_menu.show_status("Запуск сервера…")
		return
	_host_inside(port)


static func _set_mode(server: GameServer, text: String) -> void:
	## (v63) The mode a new campaign is played in; (v71) and whether it has complex repairs:
	## "hard", "normal+complex", "hard+plain" (a continued campaign keeps its own).
	var parts := text.split("+")
	server.mode = maxi(Net.MODE_KEYS.find(parts[0]), 0)
	server.complex_repairs = server.mode == Net.MODE_HARD
	if parts.has("complex"):
		server.complex_repairs = true
	elif parts.has("plain"):
		server.complex_repairs = false


func _host_inside(port: int) -> void:
	## The server inside the game itself: the fallback when a separate process
	## cannot be started. It also reports a busy port in plain words.
	_stop_server(0)
	if _trial == "":
		_show_menu("")
	_server = GameServer.new()
	add_child(_server)
	_server.shutdown_token = _server_token
	_set_mode(_server, _host_mode)
	if _flags.has("log"):
		_server.log_line.connect(func(text: String) -> void: print(text))
	var ship := _host_map if _trial != "" else _prepare_ships(_host_campaign, _host_map, _host_own)
	var problem := _server.start(port, ship, _host_bots)
	if problem == "" and _trial != "":
		_server.director.auto = false    # (v81) a try is a calm walk round: no events, hunters or calls
		_server.road.auto = false
		_server.story.auto = false
	if problem == "":
		problem = _open_campaign(_server, _host_campaign)
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
	var job := int(_opt["job"]) if _opt.has("job") else (_menu.job() if _menu != null else Net.JOB_CREWMAN)
	_client.wanted_ship = int(_opt.get("fleet_pick", _menu.wanted_ship() if _menu != null else 0))   # (v85)
	var problem := _client.connect_to(address, port, player, job)
	if problem != "":
		_stop_server(0)
		_show_menu(problem, true)
		return false
	_menu.set_busy(true)
	_menu.show_status("Подключение к %s:%d…" % [address, port])
	return true


func _on_joined() -> void:
	_menu.visible = false
	if Music.current != null:
		Music.current.play("")           # in the game the world decides (WorldView._music)
	_screen = GameScreen.new()
	add_child(_screen)
	_screen.demo_walk = _flags.has("demo")
	_screen.scripted_look = _flags.has("demo") or _opt.has("goto") or _opt.has("path") or _opt.has("click") or _opt.has("hover")
	if _opt.has("aim"):
		var aim := str(_opt["aim"]).split(",")
		_screen.aim_cells = Vector2(float(aim[0]), float(aim[1]) if aim.size() > 1 else 0.0)
	if _opt.has("predict"):
		_client.predict = str(_opt["predict"]) != "0"
	if _hosting:
		_client.admin_token = _server_token
	if _trial != "" and _trial != "ship" and _server != null and not _tried:
		_tried = true
		if not _server.derelict.try_alongside(_server.map.others.size() - 1):
			_server.chat.say("Нарисованное не помещается у шлюза корабля игры: сделайте его меньше (не выше 9 рядов).")
		else:
			_server.chat.say("Пробный %s у шлюза. Выход в меню вернёт в редактор." % ("астероид" if _trial == "asteroid" else "корабль"))
	_screen.setup(_client, _hosting, _pending_port)
	_screen.exit_requested.connect(_leave)
	if _opt.has("hover"):
		var xy := str(_opt["hover"]).split(",")
		_screen._world.hover_test = Vector2(float(xy[0]), float(xy[1]))


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
		if _client != null and (Options.max_fps == 0 or Options.max_fps > FPS_BACKGROUND):
			Engine.max_fps = FPS_BACKGROUND
		# (v79, his Task Manager picture: the game's window "not responding" while all worked) With
		# vertical sync a covered or minimised OpenGL window can wait on the driver for seconds without
		# reading its messages, and Windows marks it hung. In the background the frame limit paces it.
		if _client != null and Options.vsync:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _client != null:
			Engine.max_fps = Options.max_fps
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Options.vsync else DisplayServer.VSYNC_DISABLED)


func _unhandled_input(event: InputEvent) -> void:
	if Options.pressed(event, "fullscreen"):
		Options.fullscreen = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		Options.apply_video()
		Options.save_all()


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
	if _opt.has("try_after") and _editor != null and _editor.visible and not _tried and _trial == "" and t >= float(_opt["try_after"]):
		_editor._on_try()
	if _opt.has("derelict_after") and not _derelicted and _server != null and t >= float(_opt["derelict_after"]):
		_derelicted = true
		_server.sectors.kind[_server.ship.sector] = Sectors.DERELICT
		_server.sectors.reach[_server.ship.sector] = Sectors.DOCK_RANGE
		_server.ship.pos = _server.sectors.spot[_server.ship.sector]
		_server.ship.dest = _server.ship.pos
		_server.ship.moving = false
		_server.to_all(_server.ship.helm_packet(_server.tick))
	if _opt.has("derelict_after") and _derelicted and not _dockship and not _flags.has("nodock") and _server != null and _server.derelict.here:
		_dockship = true
		_server.derelict.dock(true)
	if _opt.has("pirateship_after") and not _pirateshipped and _flags.has("server") and _server != null and t >= float(_opt["pirateship_after"]):
		_pirateshipped = true
		_server.director.fire(_server.director.PIRATE_SHIP)
	if _opt.has("enemy_after") and not _enemied and _server != null and _screen != null and t >= float(_opt["enemy_after"]):
		_enemied = true
		_server.shipyard.force_class = int(_opt.get("enemy_class", Net.ECLASS_DRONE))
		_server.derelict.pirates_come(3, true)
		_server.shipyard.force_class = -1
	if _opt.has("assault_after") and not _assaulted and _server != null and _screen != null and t >= float(_opt["assault_after"]):
		_assaulted = true
		_server.assault._drone_lands()
	if _opt.has("robot_after") and not _roboted and _server != null and _screen != null and t >= float(_opt["robot_after"]):
		_roboted = true
		var me = _server.players[_client.my_id]
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = Vector2i(me.st.x, me.st.y) + d
			if _server.map.walkable(c.x, c.y) and _server.map.door_at(c.x, c.y) < 0:
				_server.robots.spawn(c.x, c.y)
				break
	if _opt.has("board_after") and not _boarded and _flags.has("server") and _server != null and t >= float(_opt["board_after"]):
		_boarded = true
		_server.director.fire(_server.director.BOARDING)
	if _opt.has("breach_after") and not _breached and t >= float(_opt["breach_after"]):
		if _flags.has("server") and _server != null:
			_breached = true
			_server.systems.breach_random()
		elif _screen != null:
			_breached = true
			_client.send_admin(Net.ADMIN_BREACH)
	if _flags.has("respawn") and _client != null and _client.my_cond == Net.COND_DEAD and Engine.get_process_frames() % 30 == 0:
		_client.send_respawn()               # test clients come back by themselves
	if _opt.has("goto") and _screen != null and t >= float(_opt.get("goto_after", 0.0)):
		# "7,4,0;7,1,0;13,1,1": cells to walk to in turn (first along the column, then
		# along the row), each with the way to face on arrival (0 = any)
		var stops := str(_opt["goto"]).split(";")
		var me := _client.pred
		var dir := 0
		while _goto_at < stops.size():
			var want := stops[_goto_at].split(",")
			if me.y != int(want[1]):
				dir = Net.DIR_UP if me.y > int(want[1]) else Net.DIR_DOWN
			elif me.x != int(want[0]):
				dir = Net.DIR_LEFT if me.x > int(want[0]) else Net.DIR_RIGHT
			elif int(want[2]) != 0 and me.facing != int(want[2]):
				dir = int(want[2])
			if dir != 0:
				break
			_goto_at += 1
		_screen.forced_dir = dir
		if _opt.has("climb_at") and not _climbed and _goto_at >= int(_opt["climb_at"]) and _client.use_target() >= 6:
			_climbed = true
			_client.send_use(true)
			_client.send_use(false)
	if _opt.has("jump_after") and not _jumped and _screen != null and t >= float(_opt["jump_after"]):
		_jumped = true
		var reach := _client.sectors.neighbours(_client.sector)
		if not reach.is_empty():
			_client.send_jump(reach[0])
	if _opt.has("event_after") and not _evented and _screen != null and t >= float(_opt["event_after"]):
		_evented = true
		_client.send_admin(Net.ADMIN_EVENT, int(_opt.get("event", 1)))
	if _opt.has("panel_after") and not _paneled and _screen != null and t >= float(_opt["panel_after"]):
		_paneled = true
		_screen.open_panel(str(_opt.get("panel", "inventory")))
	if _opt.has("console_after") and not _consoled and _screen != null and t >= float(_opt["console_after"]):
		_consoled = true
		_screen.open_console_here()
	if _opt.has("helm_after") and not _helmed and _screen != null and t >= float(_opt["helm_after"]):
		_helmed = true
		var where := str(_opt.get("helm", "100,100"))
		var sectors := _client.sectors
		var spot: Vector2 = sectors.spot[_client.sector]
		if where == "out":
			_client.send_helm(true, spot + (_client.ship_pos() - spot).normalized() * (sectors.reach[_client.sector] + 12.0))
		elif where == "spot":
			_client.send_helm(true, spot)
		else:
			_client.send_helm(true, Vector2(float(where.split(",")[0]), float(where.split(",")[1])))
	if _opt.has("warp_after") and not _warped and _server != null and _screen != null and t >= float(_opt["warp_after"]):
		_warped = true
		for i in _server.sectors.count:
			if _server.sectors.kind[i] == int(_opt.get("warp_kind", 1)):
				_server.navigation.start_jump(i, "Тест")
				break
	if _opt.has("volley_after") and _server != null and _screen != null and t >= float(_opt["volley_after"]) \
			and t >= _next_volley and _server.gunnery.fighting():
		_next_volley = t + 1.0
		var g = _server.gunnery
		if _flags.has("noshield"):
			_server.ship.shield_on = false
		g.enemy_hit_chance = 1.0
		for i in g.charge.size():
			if _server.ship.mounts[i] != 0:
				g._our_volley(i, _server.ship.mounts[i])
		g._enemy_fires(1)
	if _opt.has("break_helm_after") and not _helm_broken and _server != null and _screen != null and t >= float(_opt["break_helm_after"]):
		_helm_broken = true
		_server.ship.broken[_server.map.helm.keys()[0]] = true
		_server.to_all(_server.ship.devices_packet())
	if _opt.has("faint_after") and not _fainted and _server != null and _screen != null and t >= float(_opt["faint_after"]):
		_fainted = true
		var me = _server.players[_client.my_id]
		var ahead: int = _server.map.cell_ahead(me.st.x, me.st.y, me.st.facing)
		var placed := false
		for q in _server.players:
			if q != null and q.slot != _client.my_id and not q.corpse:
				q.health = -30.0             # unconscious, and a good while from coming round
				q.cond = Net.COND_CRIT
				q.st.down = true
				q.st.dir = Net.DIR_NONE
				q.add(Net.ITEM_PATCH)
				if not placed and ahead >= 0 and _server.map.walk[ahead] == 1:
					placed = true            # the first of them is laid right in front of us
					q.st.place(ahead % _server.map.width, ahead / _server.map.width)
	if _opt.has("drag_after") and not _dragged and _screen != null and t >= float(_opt["drag_after"]):
		_dragged = true
		if _client.lying_near() >= 0:
			_client.send_drag(_client.lying_near())
	if _opt.has("search_after") and not _searched and _screen != null and t >= float(_opt["search_after"]):
		_searched = true
		if _client.lying_near() >= 0:
			_client.send_search(_client.lying_near())
	if _opt.has("loot_after") and not _looted and _screen != null and t >= float(_opt["loot_after"]):
		_looted = true
		for i in _client.search_slots.size():
			if _client.search_slots[i] != Net.ITEM_NONE:
				_client.send_loot(true, i)
				break
	if _opt.has("hand_after") and not _handed and _screen != null and t >= float(_opt["hand_after"]):
		_handed = true
		_client.send_hand(int(_opt.get("hand", 0)))
	if _opt.has("take_after") and not _taken and _screen != null and t >= float(_opt["take_after"]):
		_taken = true
		_client.send_store(Net.STORE_TAKE, int(_opt.get("take", Net.ITEM_FLASHLIGHT)))
	if _opt.has("act_after") and not _acted and _screen != null and t >= float(_opt["act_after"]):
		_acted = true
		_client.send_act()
	if _opt.has("lie_after") and not _lain and _screen != null and t >= float(_opt["lie_after"]):
		_lain = true
		_client.toggle_prone()
	if _opt.has("rise_after") and not _risen and _screen != null and t >= float(_opt["rise_after"]):
		_risen = true
		_client.toggle_prone()
	if _opt.has("drone_after") and not _droned and _screen != null and t >= float(_opt["drone_after"]):
		_droned = true
		_client.send_drone(Net.DRONE_LAUNCH)
		for part in str(_opt.get("steer", "")).split(";", false):
			var bits := part.split(",")
			_steers.append([int(bits[0]), float(bits[1]) if bits.size() > 1 else 1.0])
		_steer_at = t + 5.0
	if not _steers.is_empty() and t >= _steer_at:
		var step: Array = _steers.pop_front()
		_client.send_drone(Net.DRONE_STEER, step[0])
		_steer_at = t + float(step[1])
	if _opt.has("probe_after") and not _probed and _screen != null and t >= float(_opt["probe_after"]):
		_probed = true
		_client.send_gunset(Net.GUNSET_PROBE, 0, 0)
	if _opt.has("drop_after") and not _dropped and _screen != null and t >= float(_opt["drop_after"]):
		_dropped = true
		_client.send_drop()
	if _opt.has("give_after") and not _given and _server != null and _screen != null and t >= float(_opt["give_after"]):
		_given = true
		_server.players[_client.my_id].add(int(_opt.get("give", Net.ITEM_FLASHLIGHT)), true)
	if _opt.has("restock_after") and not _restocked and _server != null and _screen != null and t >= float(_opt["restock_after"]):
		_restocked = true
		var pkt := PackedByteArray([Net.C_ADMIN, Net.ADMIN_RESTOCK, 0, 0, 0])
		_server.admin.asked(_server.players[_client.my_id], pkt)
	if _opt.has("hurt_after") and not _hurt and _server != null and _screen != null and t >= float(_opt["hurt_after"]):
		_hurt = true
		var hurt_one: Player = _server.players[_client.my_id]
		_server.combat.hurt(hurt_one, int(_opt.get("hurt", 50)), null)
		if _flags.has("in_doc") and not _server.map.autodoc.is_empty():
			# and is put on the first autodoc's bed (to see its healing drawn)
			var bed := int(_server.map.autodoc.values()[0])
			hurt_one.st.x = bed % _server.map.width
			hurt_one.st.y = bed / _server.map.width
			hurt_one.self_dirty = true
	if _opt.has("weld_after") and not _welded and _server != null and _screen != null and t >= float(_opt["weld_after"]):
		_welded = true
		for d in _server.doors.welded.size():
			_server.doors.welded[d] = 1
			_server.replication.door_record(d)
	if _opt.has("click_after") and not _clicked and _screen != null and t >= float(_opt["click_after"]):
		_clicked = true
		var at := str(_opt.get("click", "0,0")).split(",")
		_screen.click_at(Vector2(float(at[0]), float(at[1])))
	if _opt.has("pick_after") and not _picked and _screen != null and t >= float(_opt["pick_after"]):
		_picked = true
		_client.send_use(true)
		_client.send_use(false)
	if _opt.has("dock_after") and not _docked and _server != null and _screen != null and t >= float(_opt["dock_after"]):
		_docked = true
		_server.ship.pos = _server.sectors.spot[_server.ship.sector]
		_server.ship.dest = _server.ship.pos
		_server.ship.moving = false
		_server.to_all(_server.ship.helm_packet(_server.tick))
	if _opt.has("place_after") and not _placed and _server != null and _screen != null and t >= float(_opt["place_after"]):
		_placed = true
		var xy := str(_opt.get("place", "0,0")).split(",")
		var me = _server.players[_client.my_id]
		me.st.place(int(xy[0]), int(xy[1]))
		me.self_dirty = true
	if _opt.has("dockship_after") and not _dockship and _server != null and _screen != null and t >= float(_opt["dockship_after"]):
		_dockship = true
		_server.derelict.dock(true)
	if _opt.has("door_trouble_after") and not _door_troubled and _server != null and _screen != null and t >= float(_opt["door_trouble_after"]):
		_door_troubled = true
		var ahead := _client.use_cell()
		var door := _server.map.door_of[ahead] if ahead >= 0 else -1
		if door >= 0:
			match str(_opt.get("door_trouble", "jam")):
				"jam":
					_server.doors.jammed[door] = 1
					_server.doors.ready[door] = _server.tick
				"down":
					_server.doors.faulty[door] = 1
					_server.doors.locked[door] = 1
				"up":
					_server.doors.faulty[door] = 1
	if _opt.has("suit_after") and not _suited and _screen != null and t >= float(_opt["suit_after"]):
		_suited = true
		_client.send_suit(true)
	if _opt.has("use_after") and _screen != null:
		_screen.forced_use = t >= float(_opt["use_after"])
	if _opt.has("seal_after") and not _sealed and _screen != null and t >= float(_opt["seal_after"]):
		_sealed = true
		_client.send_admin(Net.ADMIN_SEAL)
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
		if _opt.has("bench") and _server != null:
			var bf := FileAccess.open(str(_opt["bench"]), FileAccess.WRITE)
			if bf != null:
				bf.store_string(JSON.stringify(_server.bench_report()))
				bf.close()
		if _opt.has("stats") and _client != null:
			var f := FileAccess.open(str(_opt["stats"]), FileAccess.WRITE)
			var mine: GameClient.Ent = _client.ents.get(_client.my_id)
			if f != null:
				f.store_string(JSON.stringify({
					"phase": _client.phase, "my_id": _client.my_id, "players": _client.roster.size(),
					"entities": _client.ents.size(), "rtt_ms": _client.rtt_ms,
					"mispredicts": _client.mispredicts, "checks_ok": _client.checks_ok,
					"checks_bad": _client.checks_bad, "packets_in": _client.packets_in,
					"bytes_in": _client.bytes_in, "pred_x": _client.pred.x + _client.pred.ox * 0.25, "pred_y": _client.pred.y + _client.pred.oy * 0.25,
					"steps_predicted": _client.steps_predicted,
					"ship_checks_bad": _client.ship_checks_bad, "holes": _client.holes.size(),
					"air_here": _client.air_at(_client.pred.x, _client.pred.y),
					"health": _client.health, "cond": _client.my_cond,
					"tank": _client.tank, "supply": _client.supply, "crew": _client.crew_count(),
					"deck": _client.my_deck(), "patches": _client.patches, "parts": _client.parts,
					"dragging": _client.dragging(), "searching": _client.search_id,
					"floor": _client.floor_things.size(), "pirates": _client.roster.values().filter(func(r: Dictionary) -> bool: return int(r["kind"]) == Net.KIND_PIRATE).size(), "in_hand": _client.in_hand(), "lit": _client.lit_cells().size(),
					"sector": _client.sector, "visited": _client.sectors.visited.count(1), "sectors": _client.sectors.count,
						"far": _client.sectors.far_from_start(_client.sector) if _client.sectors.count > 0 else -1,
					"ship_x": _client.ship_pos().x, "ship_y": _client.ship_pos().y, "broken": _client.broken.size(),
					"sector_kind": _client.sectors.kind[_client.sector] if _client.sectors.count > 0 else -1,
					"bodies": _client.roster.size() - _client.crew_count(),
					"auth_x": mine.x + mine.ox * 0.25 if mine != null else -1, "auth_y": mine.y + mine.oy * 0.25 if mine != null else -1,
					"login_ms": _client.login_ms, "in_world_ms": _client.in_world_ms,
				}))
		if _client != null:
			_client.stop_server_and_close(_server_token if _server_pid > 0 else "")
		_stop_server()
		get_tree().quit()
