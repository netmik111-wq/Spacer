extends SceneTree
## (v81) Checks the ship editor's ground: the game's own builder (MapBuilder) makes exactly the layout
## tools/make_assets.py made for every map in maps/; a mistake is listed with its cell and the drawing
## is still drawn; a ship of one's own in the «ships» folder loads and a server runs on it; the
## editor's drawing keeps through saving and opening, undo and redo, mirror, fill, copy and paste;
## «Попробовать» lays a drawing of one's own at our airlock; an asteroid comes alongside by an asteroid
## place; (the author's human wall) one holding the position is walked round, shot past, and lets go
## at a step.
##   godot --headless --path . --script res://tools/edittest.gd
## Fails with exit code 1.

const MapBuilder := preload("res://src/shared/map_builder.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const GameServer := preload("res://src/server/game_server.gd")
const Drawing := preload("res://src/ui/editor/drawing.gd")
const Checks := preload("res://src/ui/editor/checks.gd")
const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const WorldView := preload("res://src/client/world_view.gd")

var failed := 0
var dir := ""


func _initialize() -> void:
	dir = OS.get_cache_dir().path_join("spacer_edittest_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	ShipMap.ships_override = dir
	_same_as_script()
	_tile_set()
	_mistakes_listed()
	_drawing_tools()
	_layers()
	_own_ship_runs()
	_checks()
	_in_game()
	_clean()
	print("edittest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _clean() -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _expect(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failed += 1


func _same_as_script() -> void:
	for f in DirAccess.get_files_at("res://maps"):
		if not f.ends_with(".txt"):
			continue
		var name := f.get_basename()
		var built := MapBuilder.build(name, FileAccess.get_file_as_string("res://maps/" + f))
		var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/%s.json" % name))
		var got: Dictionary = JSON.parse_string(JSON.stringify(built["data"]))
		var same := true
		for k: String in want.keys():
			if JSON.stringify(want[k]) != JSON.stringify(got.get(k)):
				same = false
				print("     %s differs in %s" % [name, k])
		_expect(same and (built["problems"] as Array).is_empty(), "%s: the game's builder makes what the script made" % name)


func _tile_set() -> void:
	## (v90) Every piece the client lays in place of a map's own tile (WorldView._laid, _door_look) is in
	## the sheet, ours and the pirates', and the sheet's picture holds every tile its list names.
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles.json"))
	var names := {}
	for t: Dictionary in meta["tiles"]:
		names[str(t["name"])] = true
	var missing: Array = []
	var want: Array = ["window_m", "lamp_green", "lamp_yellow", "lamp_orange", "lamp_red", "danger_line", "vent"]
	for kind in ["base", "tech", "cargo", "herm"]:
		for o: int in 2:
			var head := "door_%s_%s_" % [kind, "hv"[o]]
			for lamp in ["green", "yellow", "red", "off"]:      # (v91) "off": a locked door's lamp blinking
				want.append(head + lamp)
			for i in range(1, int(WorldView.DOOR_STAGES[o]) + 1):
				want.append(head + "open%d" % i)
	for m: String in ShipMap.MACHINE_WIDE.keys():
		want.append(m + "_up")
		var k: int = ShipMap.MACHINE_WIDE[m]
		if k > 1:
			for i in k:
				want.append("%s_w%d_%d" % [m, k, i])
				want.append("%s_up_w%d_%d" % [m, k, i])
	for n: String in want:
		for tint in ["", "pirate_"]:
			if not names.has(tint + n):
				missing.append(tint + n)
	_expect(missing.is_empty(), "every look tile is in the sheet %s" % str(missing.slice(0, 5)))
	# (v91) every machine standing on the floor of the game's maps has its picture, turned and in pieces
	var lost: Array = []
	var standing := 0
	for f: String in DirAccess.get_files_at("res://maps"):
		if not f.ends_with(".txt"):
			continue
		var m := ShipMap.new()
		m.load_from(f.get_basename(), false)
		for c: int in m.on_floor.keys():
			standing += 1
			var tint := "pirate_" if m.tile_names[m.cells[c]].begins_with("pirate_") else ""
			if not m.tile_ids.has(tint + m.standing_look(c)):
				lost.append("%s %s" % [f, tint + m.standing_look(c)])
	_expect(standing > 20 and lost.is_empty(), "every machine on the floor has its picture (%d machines) %s" % [standing, str(lost.slice(0, 4))])
	var sheet: Texture2D = load("res://assets/tiles.png")
	var cols := int(meta["columns"])
	_expect(int(sheet.get_height()) >= ceili(float(names.size()) / cols) * int(meta["tile_size"]),
		"the sheet holds all %d tiles" % names.size())


func _mistakes_listed() -> void:
	var text := "= Палуба\n#####\n#...#\n##D##\n#...#\n#...#\n#...#\n#####\n"
	var built := MapBuilder.build("ships:test", text)
	var problems: Array = built["problems"]
	var low := problems.filter(func(p: Dictionary) -> bool: return str(p["text"]).contains("одну клетку"))
	_expect(not low.is_empty() and int(low[0]["y"]) == 1, "a room one tile tall is a problem with its cell (%d problems)" % problems.size())
	var ids := MapBuilder.tile_ids()
	var cells0: Array = built["data"]["cells"]
	_expect(int(cells0[4 * 5 + 2]) == int(ids["floor_m_m"]), "a room three tall has a middle row of floor")
	var cells: Array = built["data"]["cells"]
	_expect(cells.count(-1) < cells.size() and not cells.has(null), "the mistaken drawing is still drawn")
	var spawns := problems.filter(func(p: Dictionary) -> bool: return int(p["deck"]) == -1)
	_expect(not spawns.is_empty(), "our ship without a place to appear is a problem")


func _drawing_tools() -> void:
	var d := Drawing.new()
	d.reset(12, 8, 1)
	d.paint(0, Vector2i(2, 2), "#")
	d.commit()
	_expect(d.at(0, Vector2i(2, 2)) == "#", "a brush stroke sets the cell")
	d.mirror_x = true
	d.paint(0, Vector2i(1, 1), "#")
	d.commit()
	_expect(d.at(0, Vector2i(10, 1)) == "#", "mirror left-right paints the other side")
	d.mirror_x = false
	d.undo()
	_expect(d.at(0, Vector2i(10, 1)) == " " and d.at(0, Vector2i(1, 1)) == " ", "undo takes the whole stroke back")
	d.redo()
	_expect(d.at(0, Vector2i(10, 1)) == "#", "redo puts it back")
	d.room(0, Rect2i(3, 3, 6, 4))
	d.commit()
	_expect(d.at(0, Vector2i(3, 3)) == "#" and d.at(0, Vector2i(4, 4)) == "." and d.at(0, Vector2i(8, 6)) == "#",
		"the room tool puts walls round and floor inside")
	d.fill(0, Vector2i(5, 4), "s")
	d.commit()
	_expect(d.at(0, Vector2i(4, 4)) == "s" and d.at(0, Vector2i(7, 5)) == "s" and d.at(0, Vector2i(3, 4)) == "#",
		"fill changes the room's floor and stops at walls")
	var clip := d.copy(0, Rect2i(3, 3, 6, 4))
	d.paste(0, Vector2i(0, 0), clip)
	d.commit()
	_expect(d.at(0, Vector2i(0, 0)) == "#" and d.at(0, Vector2i(1, 1)) == "s", "paste lays the copy down")
	d.add_deck()
	_expect(d.decks.size() == 2 and d.at(1, Vector2i(4, 4)) == " ", "a new deck is empty")
	d.marks.append({"type": "@", "deck": 0, "x": 4, "y": 4, "what": "bridge"})
	d.kind = "ship"
	var text := d.to_text()
	var e := Drawing.new()
	e.from_text(text)
	_expect(e.to_text() == text and e.kind == "ship" and e.marks.size() == 1 and e.decks.size() == 2,
		"saved and opened again it is the same")
	d.resize(20, 10)
	_expect(d.width == 20 and d.at(0, Vector2i(4, 4)) == "s", "growing the canvas keeps the drawing")


func _layers() -> void:
	## (v82.1, the author's note) floor under, objects on top
	var d := Drawing.new()
	d.reset(10, 6, 1)
	d.room(0, Rect2i(1, 1, 8, 4))
	d.paint(0, Vector2i(3, 1), "3")
	d.paint(0, Vector2i(4, 2), "s")
	d.commit()
	_expect(d.at(0, Vector2i(3, 1)) == "3" and d.base_at(0, Vector2i(3, 1)) == "#", "a console lies on the wall under it")
	d.paint(0, Vector2i(4, 2), "g")
	d.commit()
	_expect(d.at(0, Vector2i(4, 2)) == "s" and d.base_at(0, Vector2i(4, 2)) == "g", "painting floor under a spawn place keeps it")
	d.paint(0, Vector2i(3, 1), " ")
	d.commit()
	_expect(d.at(0, Vector2i(3, 1)) == "#", "erasing an object shows the wall under it")
	d.fill(0, Vector2i(2, 2), "c")
	d.commit()
	_expect(d.at(0, Vector2i(4, 2)) == "s" and d.base_at(0, Vector2i(4, 2)) == "g" and d.at(0, Vector2i(5, 2)) == "c",
		"a floor fill runs round objects and keeps them")
	d.layer = Drawing.LAYER_FLOOR
	d.paint(0, Vector2i(6, 3), "D")
	d.paint(0, Vector2i(4, 2), " ")
	d.commit()
	_expect(d.at(0, Vector2i(6, 3)) == "c" and d.at(0, Vector2i(4, 2)) == "s" and d.base_at(0, Vector2i(4, 2)) == " ",
		"on the floor layer objects are neither drawn nor erased")
	d.layer = Drawing.LAYER_OBJECTS
	d.paint(0, Vector2i(5, 2), "#")
	d.clear(0, Rect2i(0, 0, 10, 6))
	d.commit()
	_expect(d.at(0, Vector2i(5, 2)) == "c" and d.at(0, Vector2i(4, 2)) == " " and d.at(0, Vector2i(1, 1)) == "#",
		"on the object layer floors stay and only objects are cleared")
	d.layer = Drawing.LAYER_BOTH
	var e := Drawing.new()
	e.from_text("= Палуба\n#####\n#.D.#\n#s..#\n#####\n")
	_expect(e.base_at(0, Vector2i(2, 1)) == "#" and e.base_at(0, Vector2i(1, 2)) == "." and e.at(0, Vector2i(1, 2)) == "s",
		"opening a ship finds the floor under its objects")
	e.from_text(d.base_text())
	_expect(e.at(0, Vector2i(4, 2)) == " " and e.at(0, Vector2i(5, 2)) == "c", "hiding objects draws the floor alone")


func _own_ship_runs() -> void:
	# the game's own ship, saved as a ship of one's own, is a ship a server runs on
	var text := FileAccess.get_file_as_string("res://maps/ship02.txt")
	var f := FileAccess.open(dir.path_join("Мой корабль.txt"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var map := ShipMap.new()
	var problem := map.load_from(ShipMap.USER_PREFIX + "Мой корабль")
	var theirs := ShipMap.new()
	theirs.load_from("ship02")
	_expect(problem == "" and map.crc == theirs.crc, "a ship of one's own loads as the game's ship (%s)" % problem)
	var server := GameServer.new()
	get_root().add_child(server)
	problem = server.start(26490, ShipMap.USER_PREFIX + "Мой корабль", 2)
	_expect(problem == "", "a server starts on it (%s)" % problem)
	if problem == "":
		for t in 200:
			server._tick()
		_expect(server.players.filter(func(p) -> bool: return p != null).size() >= 2, "its bots walk aboard")
		server.stop()
	server.free()
	var bad := ShipMap.new()
	_expect(bad.load_from(ShipMap.USER_PREFIX + "нет такого") != "", "a missing ship is said plainly")


func _checks() -> void:
	# the problems panel's checks of what the game needs
	var d := Drawing.new()
	d.from_text(FileAccess.get_file_as_string("res://maps/ship02.txt"))
	d.kind = "ship"
	var found := Checks.run(d)
	_expect(found.filter(func(p: Dictionary) -> bool: return p["error"]).is_empty(), "the game's ship has no errors (%s)" % [found])
	var bare := Drawing.new()
	bare.from_text("= Палуба\n#####\n#s..#\n#...#\n#####\n")
	bare.kind = "ship"
	found = Checks.run(bare)
	var texts := ", ".join(found.map(func(p: Dictionary) -> String: return p["text"]))
	_expect(texts.contains("штурвал") or texts.contains("управлени"), "a ship without controls is told so (%s)" % texts)
	var rock := Drawing.new()
	rock.from_text(FileAccess.get_file_as_string("res://maps/asteroid01.txt"))
	found = Checks.run(rock)
	_expect(rock.kind == "asteroid" and found.filter(func(p: Dictionary) -> bool: return p["error"]).is_empty(),
		"an asteroid needs no ship's things (%s)" % [found])


# ---------------------------------------------------------------- in a game: trial, asteroid, the human wall

var server: GameServer


func _run(ticks: int) -> void:
	for t in ticks:
		server._tick()


func _in_game() -> void:
	# a pirate ship of one's own, tried: it lies at our airlock
	var text := FileAccess.get_file_as_string("res://maps/pirate03.txt").replace("; kind", ";  was")
	text = "; kind = pirate\n" + text
	var f := FileAccess.open(dir.path_join("Мой пират.txt"), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	ShipMap.try_other = ShipMap.USER_PREFIX + "Мой пират"
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26491, "ship02", 0)
	ShipMap.try_other = ""
	_expect(problem == "", "a server starts with a drawing of one's own to try (%s)" % problem)
	if problem != "":
		server.free()
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.stations.volunteers = false
	server.pirates.goals_on = false
	server.defence.on = false
	var k := server.map.others.size() - 1
	_expect(server.map.others[k].kind == "pirate", "it is read as a pirate ship")
	_expect(server.derelict.try_alongside(k) and server.derelict.docked, "«Попробовать» docks it at our airlock")
	_run(40)
	_expect(server.derelict.here and not server.gunnery.fighting(), "it stays, and nobody fights")
	server.derelict._leave(true)
	_asteroid()
	_human_wall()
	server.stop()
	server.free()


func _asteroid() -> void:
	var map: ShipMap = server.map
	_expect(map.others_of("asteroid").size() == 2 and not map.others_of("pirate").has(map.others_of("asteroid")[0]),
		"the asteroids are known, and not taken for pirate ships")
	_expect(server.derelict._rock_spots().size() == 2, "both asteroids fit over our airlock")
	server.road._here_places = [[Sectors.P_ASTEROID, server.ship.pos]]
	server.road._places_for = server.ship.sector
	server.ship.moving = false
	_run(3)
	_expect(server.derelict.here and server.derelict.kind == Net.OTHER_ROCK and server.derelict.ship.kind == Net.SHIP_ROCK,
		"by an asteroid place the rock comes alongside")
	_expect(server.derelict.dock(true) != "" and not server.derelict.docked, "an asteroid cannot be docked")
	var p = server.crew.new_player("Шахтёр")
	var vein := -1
	for c: int in map.other_cells:
		if map.cells[c] == int(map.tile_ids["rock_ore"]):
			vein = c
	_expect(vein >= 0 and server.salvage.can_cut(p, vein) == server.salvage.NOT_HERE, "no scrap is cut off rock")
	server.road.work[server.road._key(0)] = 1
	_expect(server.road.ore_left() == 1, "the place keeps how much ore is left")
	server.road.mined()
	_expect(server.road.ore_left() == 0 and server.road.taken.has(server.road._key(0)), "dug out, the asteroid is spent")
	_run(3)
	_expect(not server.derelict.here, "a spent asteroid is left behind")
	server.road._here_places = []
	server.crew.remove(p)


func _human_wall() -> void:
	var map: ShipMap = server.map
	var at := Vector2i(-1, -1)
	for y in map.height:
		for x in map.width:
			var ok := map.on_ship(y * map.width + x)
			for dx in range(0, 6):
				ok = ok and map.walkable(x + dx, y) and map.door_at(x + dx, y) < 0
			if ok and at.x < 0:
				at = Vector2i(x, y)
	var wall = server.crew.new_player("Стена")
	wall.st.place(at.x + 2, at.y)
	wall.quarters = true
	var walker = server.crew.new_player("Идущий")
	walker.st.place(at.x, at.y)
	walker.quarters = true
	wall.inputs.append([server.tick + 1, Mover.HOLD, 1])
	_run(2)
	_expect(wall.st.hold, "X: the position is held")
	walker.inputs.append([server.tick + 1, Net.DIR_RIGHT, 2])
	_run(60)
	var reached: int = walker.st.qx()
	_expect(reached <= (at.x + 1) * 4, "nobody walks through a held tile (stopped at %.2f)" % (reached / 4.0))
	walker.inputs.append([server.tick + 1, Net.DIR_NONE, 3])
	_run(2)
	# friends fire past the one holding the line
	var pirate = server.pirates.spawn(at.x + 4, at.y, false)
	pirate.ready_tick = 1 << 30
	pirate.ai_fire_tick = 1 << 30
	walker.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	walker.hand = 0
	walker.st.place(at.x, at.y)
	wall.health = 100.0
	server.combat.use_at(walker, server.tick, Vector2(at.x + 4, at.y))
	_expect(wall.health == 100.0, "a friend's shot flies past the one holding the line")
	# a step lets go
	wall.inputs.append([server.tick + 1, Net.DIR_LEFT, 2])
	_run(3)
	_expect(not wall.st.hold, "a step lets go of the position")
	for q in [wall, walker, pirate]:
		server.crew.remove(q)
