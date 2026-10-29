extends SceneTree
## Checks build v84 (the author's answers: hosting a game on one's own ship):
##   godot --headless --path . --script res://tools/hosttest.gd
## A game starts on a drawing from the «ships» folder; the server sends its drawings to a guest, who
## needs no file of his own (H1); a drawing with no helm or no engine cannot start (H3); the save keeps
## its own copy, so a changed file does not change a continued run (H4); one's own pirate ships,
## derelicts and asteroids come in the run when asked (H5); a blow that meets nobody is drawn within
## arm's reach, wherever the click was (S1).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Combat := preload("res://src/server/combat.gd")
const Main := preload("res://src/main.gd")

const PORT := 26920
const SHIPS := "user://hosttest_ships"
const EMPTY := "user://hosttest_empty"
const SAVE := "user://hosttest_save.json"

var failed := 0
var server: GameServer


func _initialize() -> void:
	_go()


func _go() -> void:
	_folders()
	_serious()
	_own_others_listed()
	server = GameServer.new()
	get_root().add_child(server)
	ShipMap.drawings = {}
	ShipMap.own_others = ShipMap.coming_in_run()
	ShipMap.places_on = false                 # (v97: no derelicts made from pieces: the checks count one's own drawings)
	ShipMap.made_others = []
	var problem := server.start(PORT, "ships:mine", 0)
	_expect(problem == "", "a game starts on a drawing of one's own (%s)" % problem)
	if problem != "":
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	_others_in_run()
	_packed()
	await _guest()
	_saved()
	_swing()
	server.stop()
	server.free()
	ShipMap.ships_override = ""
	ShipMap.drawings = {}
	ShipMap.own_others = []
	print("hosttest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _folders() -> void:
	## A «ships» folder of our own: our ship (the game's, under another name), one without a helm, and a
	## pirate ship, a derelict and an asteroid of our own (copies of the game's).
	for dir: String in [SHIPS, EMPTY]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	ShipMap.ships_override = ProjectSettings.globalize_path(SHIPS)
	var ours := FileAccess.get_file_as_string("res://maps/ship02.txt")
	_write("mine", ours)
	var lines := PackedStringArray()
	for l in ours.split("\n"):
		lines.append(l if l.begins_with("@") or l.begins_with("%") or l.begins_with(";") or l.begins_with("=") else l.replace("3", "."))   # (v91: the helm stands on the floor)
	_write("nohelm", "\n".join(lines))
	_write("pirate_mine", FileAccess.get_file_as_string("res://maps/pirate02.txt"))
	_write("derelict_mine", FileAccess.get_file_as_string("res://maps/derelict01.txt"))
	_write("asteroid_mine", FileAccess.get_file_as_string("res://maps/asteroid01.txt"))


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(SHIPS.path_join(name + ".txt"), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _serious() -> void:
	print("  -- a ship with no helm cannot start (the author's H3)")
	ShipMap.drawings = {}
	ShipMap.own_others = []
	var s := GameServer.new()
	get_root().add_child(s)
	var problem := s.start(PORT + 1, "ships:nohelm", 0)
	_expect(problem.contains("штурвал"), "it is refused, saying why: %s" % problem)
	if problem == "":
		s.stop()
	s.free()


func _own_others_listed() -> void:
	print("  -- one's own pirate ships, derelicts and asteroids that can be played (the author's H5)")
	var listed := ShipMap.coming_in_run()
	_expect(listed == ["ships:asteroid_mine", "ships:derelict_mine", "ships:pirate_mine"], "all three, and not our own ship: %s" % str(listed))


func _others_in_run() -> void:
	print("  -- they come in the run")
	var map := server.map
	var first := Net.OTHER_MAPS.size()
	_expect(map.others.size() == first + 3, "three more drawings of other ships (%d)" % map.others.size())
	_expect(server.derelict._derelict_spots().any(func(k: int) -> bool: return k >= first), "our derelict can lie off the airlock")
	_expect(server.derelict._rock_spots().any(func(k: int) -> bool: return k >= first), "and our asteroid")
	var fits: Array = server.derelict._pirate_spots()
	_expect(fits.any(func(k: int) -> bool: return k >= first), "and our pirate ship")
	var ours := 0
	for i in 200:
		var design: Dictionary = server.shipyard.make(2, false, fits)
		if int(design["layout"]) >= first:
			ours += 1
	_expect(ours > 0, "pirates come in our pirate ship's hull now and then (%d of 200)" % ours)
	# a derelict of ours comes in some places: the drawing goes by the place, the same every time
	var seen := {}
	for x in 6:
		var key := (32768 << 16) | (x + 32768)
		var drawn: Array = server.derelict._derelict_spots()
		seen[drawn[absi(key) % drawn.size()]] = true
	_expect(seen.size() == 2, "the game's derelict and ours both come, by place (%s)" % str(seen.keys()))


func _packed() -> void:
	print("  -- the server's welcome carries the drawings (the author's H1)")
	var w := ShipMap.pack_maps("ships:mine")
	var got := ShipMap.unpack_maps(w, 0)
	_expect(not got.is_empty(), "it reads back")
	if got.is_empty():
		return
	_expect(got["others"] == ShipMap.other_maps(), "the other ships' drawings in the server's order")
	var texts: Dictionary = got["drawings"]
	_expect(texts.has("ships:mine") and texts.has("ships:pirate_mine") and texts.size() == 4,
		"our ship and our three other drawings: %s" % str(texts.keys()))
	_expect(str(texts.get("ships:mine", "")) == FileAccess.get_file_as_string(SHIPS.path_join("mine.txt")), "the text as drawn")
	_expect(ShipMap.unpack_maps(w.slice(0, w.size() - 3), 0).is_empty(), "a cut packet is refused, not misread")


func _guest() -> void:
	print("  -- a guest with no «ships» folder of his own joins")
	ShipMap.ships_override = ProjectSettings.globalize_path(EMPTY)
	var c := GameClient.new()
	get_root().add_child(c)
	var why := [""]
	c.failed.connect(func(r: String) -> void: why[0] = r)
	c.connect_to("127.0.0.1", PORT, "Гость")
	var until := Time.get_ticks_msec() + 8000
	while c.phase != GameClient.PLAYING and why[0] == "" and Time.get_ticks_msec() < until:
		server._process(0.05)
		await process_frame
	_expect(c.phase == GameClient.PLAYING, "he plays (%s)" % why[0])
	_expect(c.map.crc == server.map.crc and c.map.map_name == "ships:mine", "on our ship, the same as the server's")
	_expect(c.map.others.size() == server.map.others.size(), "knowing every other ship the server may send (%d)" % c.map.others.size())
	c.close()
	get_root().remove_child(c)
	c.free()
	ShipMap.ships_override = ProjectSettings.globalize_path(SHIPS)


func _saved() -> void:
	print("  -- the save keeps its own copy of the drawing (the author's H4)")
	var data := Campaign.snapshot(server)
	_expect((data.get("drawings", {}) as Dictionary).has("ships:mine"), "the save has our ship's drawing")
	_expect((data.get("own_others", []) as Array).size() == 3, "and which drawings of ours come in the run")
	_expect(Campaign.write(server, SAVE), "it is written")
	var before := str(ShipMap.drawings["ships:mine"])
	_write("mine", "= сломано\n#\n")         # the drawing is changed (here: spoilt) after the evening
	var ship := Main._prepare_ships("continue", "ship02", false, SAVE)
	_expect(ship == "ships:mine", "a continued game is on the save's ship, whatever the menu says (%s)" % ship)
	_expect(str(ShipMap.drawings.get("ships:mine", "")) == before, "as the save kept it")
	_expect(ShipMap.own_others.size() == 3, "with the same other drawings")
	var s := GameServer.new()
	get_root().add_child(s)
	var problem := s.start(PORT + 2, ship, 0)
	if problem == "":
		problem = s.resume_campaign(SAVE)
	_expect(problem == "", "it starts and goes on (%s)" % problem)
	if problem == "":
		s.stop()
	s.free()
	ShipMap.ships_override = ProjectSettings.globalize_path(EMPTY)
	ship = Main._prepare_ships("new", "ship02", false, SAVE)
	_expect(ship == "ship02" and ShipMap.drawings.is_empty() and ShipMap.own_others.is_empty(), "a new campaign starts afresh")
	ShipMap.ships_override = ProjectSettings.globalize_path(SHIPS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _swing() -> void:
	print("  -- a blow at a far tile (the author's note)")
	var from := Vector2(10, 12)
	var end := Combat.swing_end(from, Vector2(17, 9))
	_expect(end.distance_to(from) <= Combat.REACH + 0.001, "is drawn within arm's reach (%.2f cells)" % end.distance_to(from))
	_expect((end - from).normalized().dot((Vector2(17, 9) - from).normalized()) > 0.99, "toward the click")
	_expect(Combat.swing_end(from, Vector2(10.5, 12)) == Vector2(10.5, 12), "a near click stays where it was")


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("    ok   " + what)
	else:
		failed += 1
		print("    FAIL " + what)
