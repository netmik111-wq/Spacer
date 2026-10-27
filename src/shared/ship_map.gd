extends RefCounted
## A ship layout: which tile is drawn in every cell and where characters can
## walk. Loaded from maps/<name>.json, which tools/make_assets.py builds from
## the ASCII drawing next to it. The server and the client load the same file.
##
## A ship may have several decks. They all sit in the one grid, one below the
## other: deck 0 is the top deck and starts at row 0, deck 1 is under it and
## starts at row `deck_stride`, and so on. So a cell is x and y everywhere,
## and the row alone says which deck it is on. Between decks there is always
## at least one empty row, so nothing on one deck touches another in the grid.

const Net := preload("res://src/shared/net.gd")
const MapBuilder := preload("res://src/shared/map_builder.gd")

const USER_PREFIX := "ships:"        # (v81) a map named "ships:NAME" is ships/NAME.txt of one's own (see ships_dir)
static var ships_override := ""      # (tests) another «ships» folder
static var try_other := ""           # (v81) the ship editor's «Попробовать»: a drawing of one's own that comes alongside
                                     # (the game's server runs inside the game then, so both sides read this)
static var drawings := {}            # (v84) "ships:NAME" -> its drawing's text, read before the «ships» folder: what the
                                     # server read at start or from the save, what a guest was sent by the server (H1)
static var own_others: Array[String] = []   # (v84, the author's H5) drawings of one's own that come in the run
                                     # (pirate ships, derelicts, asteroids), after the game's own in `others`

const FLEET_JOIN := "|"              # (v85, the author's FS1) "ship02|ship01": our fleet, its ships' drawings one below another
const FLEET_GAP := 4                 # rows of open space between two ships of the fleet
# (v85) what each ship of the fleet has of its own: set in place by use_ship (the server's and the client's
# code ask `helm`, `guns`, `smes`... of the ship they work for; a gun or a tray is numbered within its ship)
const FLEET_FITS := ["oxygen", "helm", "chart", "engine", "air_plant", "locker", "intercom", "med_box", "tech_box", "holo", "shield", "bench",
	"bay", "autodoc", "scanner", "smes", "smes_small", "comms", "trays", "cryo", "stove", "backup_rooms", "guns",
	"gun_console", "drone_console", "lock_pump", "vents", "spawns"]

const DOOR_BAND := 0                 # a door in a horizontal wall ('D' in the drawing)
const DOOR_AIRLOCK := 1              # an airlock in a vertical wall ('A')

var map_name := ""
var kind := "ship"                   # (v81) what the drawing is: ship (ours), pirate, derelict or asteroid (MapBuilder.KINDS)
var width := 0
var height := 0                      # rows of the whole grid, all decks together
var deck_height := 0                 # rows of one deck
var deck_stride := 16                # rows from one deck to the next (a multiple of 16)
var deck_count := 1
var deck_names := PackedStringArray()
var cells := PackedInt32Array()      # tile id per cell, -1 = empty space
var walk := PackedByteArray()        # 1 = can be walked on (doors count: they open)
var opaque := PackedByteArray()      # 1 = light and sight do not pass (walls and the things on them;
                                     # windows let them through, and shut doors stop them: see Sight)
var spawns: Array[Vector2i] = []
var crc := 0                         # fingerprint of the layout, compared at login

var doors: Array[Vector2i] = []      # where each door is; a door is known by its number in this list
var door_kind := PackedByteArray()   # DOOR_BAND or DOOR_AIRLOCK, per door
var door_of := PackedInt32Array()    # door number per cell, -1 = no door there
var door_sides := PackedInt32Array() # per door, two cells: the floor on either side of it (-1 = none).
                                     # The first is above or to the left, the second below or to the right.
var hull := PackedInt32Array()       # cells of the outer shell that can be breached: wall or window
var panes := PackedInt32Array()      # (v91) our ships' window cells: each has a shutter (Systems.update_panes)
                                     # with a walkable cell on one side and space on another
var oxygen := {}                     # wall cells with an oxygen station (the red box): cell -> true
var helm := {}                       # wall cells with the ship's controls (the panel with orange lights)
var chart := {}                      # wall cells with the sector console (the green screen)
var engine := {}                     # wall cells with the engine: it drives the ship and its jumps
var air_plant := {}                  # wall cells with the air plant: cell -> the cell it blows into
var locker := {}                     # wall cells with the supply locker
var intercom := {}                   # wall cells with an intercom panel
var med_box := {}                    # (v91, the author's M7) wall cells with a first-aid box (see Supplies.box)
var tech_box := {}                   # (v91) wall cells with a spare parts box
var guns := PackedInt32Array()       # wall cells with the ship's guns, in the order they are numbered
var gun_console := {}                # wall cells with the gun console (the fourth console of the mockup)
var drone_console := {}              # (v54) wall cells with the drone monitor (the fifth console of the mockup)
var holo := {}                       # wall cells with a holomap monitor: the whole ship's air, holes and breakdowns
var shield := {}                     # wall cells with the shield generator (see Gunnery)
var bench := {}                      # (v58) wall cells with the workbench: guns taken apart, mended, upgraded
var bay := {}                        # (v59) wall cells with the module bay: ship modules go in its free slots
var autodoc := {}                    # (v60) wall cells with an autodoc: wall cell -> the bed (the floor cell in front)
var scanner := {}                    # (v60) wall cells with a body scanner
var smes := {}                       # (v61) wall cells with the ship's SMES: it stores power and carries the ship
var smes_small := {}                 # (v61) wall cells with the bridge's small backup SMES
var comms := {}                      # (v63) wall cells with the comms console: calls and text events, quests
var trays := PackedInt32Array()      # (v63) wall cells with a hydroponic tray, in the order they are numbered
var cryo := PackedInt32Array()       # (v63) wall cells with a cryosleep pod: the reserve sleeps in them
var stove := {}                      # (v71) wall cells with the galley's stove: meals cooked from rations (see Galley)
var dock := {}                       # (v86) wall cells with the shuttle's dock console, all ships of the fleet (see Shuttle)
var force_field := {}                    # (v86) hull cells with a hangar's force field: air-tight, see-through, never breached
var backup_rooms := {}               # (v61) the rooms (numbers in `rooms`) the backup SMES faces: it keeps them lit
var rooms: Array = []                # (v53) its floor split into rooms by walls and doors (a doorway is in none):
                                     # PackedInt32Array of cells each, top-left room first (see _find_rooms)
var room_of := PackedInt32Array()    # per cell: its number in `rooms`, -1 = in none
var zones: Array = []                # (a ship others fight) the rooms its systems stand in: per Net.ESYS_*,
                                     # the cells of its own drawing (see Gunnery); empty = none named
var lock_pump := {}                  # wall cells with an airlock pump: cell -> {"chamber": cells of the
                                     # chamber it serves, "inner": door, "outer": door (-1 = none)}
var door_partner := PackedInt32Array() # per door: the other door of its airlock chamber, or -1.
                                     # Only one of the two may be open at a time (see Doors.bump)
var door_vent := PackedByteArray()   # per door: 1 = it opens straight into space (an airlock's outer door)
var door_access := PackedByteArray() # per door: the access it asks for (Net.ACCESS_* bits), 0 = anybody
var door_look := PackedStringArray() # (v91, the author's D1) per door: the kind it is drawn as ("" = by its rooms)
var vents := PackedInt32Array()     # (v69) floor cells with a room's air vent, one per room (see _place_vents)
var access_in := PackedByteArray()   # (v69) per cell: the access of the restricted room it lies in (0 = none):
                                     # its doors open for anybody leaving it (see leaving)
var brig := PackedByteArray()        # (v75) per cell: 1 = a brig cell, where prisoners never slip the cuffs
var see_through := PackedByteArray() # per cell: 1 = its floor shows the deck below (glass, catwalk, hatch)
var air_down := PackedInt32Array()   # per cell: the cell below that shares its air (under a catwalk or
                                     # a hatch), or -1
var air_up := PackedInt32Array()     # the same, the other way
var climb := PackedInt32Array()      # per cell: where the ladder here leads (a cell on another deck), or -1
var stair_to := PackedInt32Array()   # (v91, the author's F3) per cell: where stepping onto it takes one (the same
                                     # spot of the deck above or below: see _find_stairs), or -1
var flights: Array = []              # (v91) each flight of stairs on one deck: {"cells": [top, bottom] on the way down,
                                     # "way": the way down (Vector2i), "down": true on the upper deck (his dark stairs)}

# Another ship alongside (a derelict). Its drawing lives in its own map file
# and is laid into this grid while it is near, at some place over our own
# ship; its doors take the numbers kept for them at the end of `doors`.
# `base_*` keep our own ship as it is without it.
const NO_OTHER := Vector2i(-9999, -9999)
var others: Array = []               # every kind of other ship that may come (ShipMaps), by number
var other: RefCounted = null         # the layout of the one here (or of the first kind while none is here)
var other_kind := -1                 # its number in `others`, -1 = none here
var other_at := NO_OTHER             # where its corner lies in our grid while it is here
var other_first_door := 0            # the number of its first door among ours
var other_cells := PackedInt32Array() # the cells it takes up while it is here
var base_cells := PackedInt32Array()
var base_walk := PackedByteArray()
var base_opaque := PackedByteArray()

var fleet_rows := PackedInt32Array([0])   # (v85) per ship of our fleet: the row of each deck its drawing starts on
var fleet_names := PackedStringArray()   # and its drawing's name
var fleet_on := -1                   # the ship whose own things are in place now (-1: all of them)
var _fits: Array = []                # per ship: field of FLEET_FITS -> its part; [-1] (the last) all of them
var held := {}                       # (v81, the author's human wall) cells somebody holds (Mover.State.hold): nobody
                                     # else walks into them. The server marks them every tick; a client marks those
                                     # of the others it sees, so its own walking is predicted alike
var tile_size := 32
var atlas_columns := 8
var tile_kinds := PackedStringArray()
var tile_ids := {}                   # tile name -> id
var tile_names := PackedStringArray() # (v91) tile id -> name
var fitting := PackedByteArray()     # per tile id: 1 = a thing fitted into a wall, used from the room it faces
var on_floor := {}                   # (v91, the author) cell -> the floor's tile under a machine standing on the floor:
                                     # nobody walks there, but one sees over it (unless it is `tall`)
var tall := {}                       # (v91, the author's G1: "vision is blocked if it's tall") such cells of the machines
                                     # in TALL: they stop sight and light as a wall does
var root := PackedInt32Array()       # (v91) per cell: the cell that stands for the machine it is a piece of (see MACHINE_WIDE)
var pieces := {}                     # (v91) such a cell -> every cell of its machine, for a machine of more than one
# (v91, the author's G1) the machines on the floor one cannot see over; the rest (consoles, the workbench, the
# stove, trays, the autodoc...) are low, and sight passes over them
const TALL := ["engine", "air_plant", "locker", "shield", "bay", "smes", "smes_small", "cryo"]
# (v90, the author's tile set) how many tiles wide a machine's picture is: a row of as many of one machine
# ("33" for the helm, "444" for the gun console) is one machine drawn wide, used from any of its cells.
# (v91) The star chart's big holo table is two by two ("11" over "11").
const MACHINE_WIDE := {"console_1": 2, "console_3": 2, "console_4": 3, "console_5": 1, "comms": 2, "holo": 2,
	"locker": 1, "intercom": 1, "smes": 2, "smes_small": 1}

# Things set into a wall face one room (see fitting_front) and are used from
# there: from the cell in front of them, or the cells either side of that one.
const FITTINGS := ["console_1", "console_2", "console_3", "console_4", "console_5",
	"engine", "air_plant", "locker", "intercom", "lock_pump", "holo", "shield", "bench", "bay", "autodoc", "scanner", "smes", "smes_small",
	"comms", "tray", "cryo", "stove", "dock", "med_box", "tech_box", "fire_box", "wall_light"]


func load_from(name: String, needs_spawns: bool = true) -> String:
	## Returns "" on success or a description of what went wrong.
	var tiles_text := FileAccess.get_file_as_string("res://assets/tiles.json")
	var data: Variant = null
	fleet_rows = PackedInt32Array([0])
	fleet_names = PackedStringArray([name])
	if name.contains(FLEET_JOIN):
		# (v85) our fleet: every ship's drawing laid one below another, built as one
		var texts := []
		for part in name.split(FLEET_JOIN):
			var t := drawing_text(part)
			if t.is_empty():
				return "Не найден корабль «%s»." % part.trim_prefix(USER_PREFIX)
			texts.append(t)
		var joined: Dictionary = MapBuilder.fleet_text(texts, FLEET_GAP)
		var built := MapBuilder.build("fleet", str(joined["text"]))
		var problems: Array = built["problems"]
		if not problems.is_empty():
			return "Флотилия: %s" % (problems[0] as Dictionary)["text"]
		fleet_rows = joined["rows"]
		fleet_names = name.split(FLEET_JOIN)
		kind = "ship"
		var problem := load_data(name, tiles_text, built["data"], needs_spawns)
		if problem == "":
			_split_fits()
		return problem
	if name.begins_with(USER_PREFIX):
		# (v81) a ship of one's own, drawn in the ship editor: built here from its drawing;
		# (v84) the copy the server sent or the save kept comes first, and a drawing read is kept
		var text := str(drawings.get(name, ""))
		if text.is_empty():
			text = FileAccess.get_file_as_string(ships_dir().path_join(name.substr(USER_PREFIX.length()) + ".txt"))
		if text.is_empty():
			return "Не найден корабль «%s» в папке ships." % name.substr(USER_PREFIX.length())
		drawings[name] = text
		var built := MapBuilder.build(name.substr(USER_PREFIX.length()), text)   # (its kind by the file's name, too)
		var problems: Array = built["problems"]
		if not problems.is_empty():
			var p: Dictionary = problems[0]
			return "Корабль «%s»: %s" % [name.substr(USER_PREFIX.length()), p["text"]]
		data = built["data"]
		kind = built["kind"]
	else:
		var map_text := FileAccess.get_file_as_string("res://maps/%s.json" % name)
		if map_text.is_empty():
			return "Не найдены файлы карты «%s»." % name
		data = JSON.parse_string(map_text)
		kind = MapBuilder.kind_of(name, "")
	return load_data(name, tiles_text, data, needs_spawns)


static func drawing_text(name: String) -> String:
	## (v85) The text of a drawing: one of one's own (the copy kept, else the «ships» folder) or the game's.
	if name.begins_with(USER_PREFIX):
		var text := str(drawings.get(name, ""))
		if text.is_empty():
			text = FileAccess.get_file_as_string(ships_dir().path_join(name.substr(USER_PREFIX.length()) + ".txt"))
			if not text.is_empty():
				drawings[name] = text
		return text
	return FileAccess.get_file_as_string("res://maps/%s.txt" % name)


func fleet_size() -> int:
	return fleet_rows.size()


func fleet_of(cell: int) -> int:
	## (v85) Which ship of our fleet a cell is in (0 = the first); -1 for the ship alongside.
	if fleet_rows.size() < 2:
		return 0
	if is_other(cell):
		return -1
	return fleet_near(cell)


func fleet_near(cell: int) -> int:
	## (v86) The ship of our fleet whose rows that cell lies in (the ship alongside included: the one it lies off).
	if fleet_rows.size() < 2:
		return 0
	var row := local_y(cell / width)
	for i in range(fleet_rows.size() - 1, 0, -1):
		if row >= fleet_rows[i] - FLEET_GAP / 2:
			return i
	return 0


func shuttle_docks() -> Array:
	## (v86, the author's N1) Per ship of our fleet, its shuttle dock: {"console": the dock console's cell,
	## "front": the floor in front of it, "park": where the shuttle waits outside the hangar's force field
	## (its middle, in tiles of the grid), "out": -1 when space is above the field, 1 below}; an empty
	## Dictionary for a ship with none. The same answer on the server and on every client.
	var out: Array = []
	for i in fleet_size():
		out.append({})
	var consoles: Array = dock.keys()
	consoles.sort()
	for c: int in consoles:
		var i := fleet_of(c)
		if i < 0 or not (out[i] as Dictionary).is_empty():
			continue
		var x := c % width
		var y := c / width
		# the force field's cells in the same wall, nearest the console first
		var near := -1
		for k in range(1, 9):
			for fx: int in [x + k, x - k]:
				if near < 0 and force_field.has(y * width + fx):
					near = fx
		var front := fitting_front(c)
		if near < 0 or front < 0:
			continue
		var lo := near
		var hi := near
		while force_field.has(y * width + lo - 1):
			lo -= 1
		while force_field.has(y * width + hi + 1):
			hi += 1
		var side := -1 if is_space(near, y - 1) else 1
		out[i] = {"console": c, "front": front, "park": Vector2((lo + hi + 1) / 2.0, y + 0.5 + side * 2.0), "out": side}
	return out


func all_of(field: String) -> Variant:
	## (v85) Every ship's of those fittings (FLEET_FITS), whichever ship's are in place.
	return get(field) if _fits.is_empty() else (_fits[-1] as Dictionary)[field]


func use_ship(i: int) -> void:
	## (v85) Puts that ship's own things in place (FLEET_FITS); -1 puts every ship's.
	if _fits.is_empty() or i == fleet_on:
		return
	fleet_on = i
	var fits: Dictionary = _fits[i] if i >= 0 else _fits[-1]
	for f: String in FLEET_FITS:
		set(f, fits[f])


func _split_fits() -> void:
	_fits = []
	for i in fleet_rows.size() + 1:
		var fits := {}
		for f: String in FLEET_FITS:
			var all: Variant = get(f)
			if i == fleet_rows.size():
				fits[f] = all
				continue
			var mine: Variant
			if all is Dictionary:
				mine = {}
				for k: Variant in (all as Dictionary).keys():
					var c := int(k) if f != "backup_rooms" else int((rooms[int(k)] as PackedInt32Array)[0])
					if fleet_of(c) == i:
						mine[k] = all[k]
			elif all is PackedInt32Array:
				mine = PackedInt32Array()
				for c: int in all:
					if fleet_of(c) == i:
						mine.append(c)
			else:
				mine = all.filter(func(v: Vector2i) -> bool: return fleet_of(v.y * width + v.x) == i)
			fits[f] = mine
		_fits.append(fits)
	fleet_on = -1
	use_ship(0)


static func ships_dir() -> String:
	## (v81) The «ships» folder next to the game (run from the project: the project's own), where the
	## ship editor keeps its drawings.
	if ships_override != "":
		return ships_override
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("ships")
	return ProjectSettings.globalize_path("res://").path_join("ships")


func load_data(name: String, tiles_text: String, data: Variant, needs_spawns: bool = true) -> String:
	## Sets the layout up from a map's data (as maps/*.json holds it). "" or what went wrong.
	if tiles_text.is_empty():
		return "Не найдены файлы карты «%s»." % name
	var tiles: Variant = JSON.parse_string(tiles_text)
	if typeof(tiles) != TYPE_DICTIONARY or typeof(data) != TYPE_DICTIONARY:
		return "Файлы карты «%s» повреждены." % name
	tile_size = int(tiles["tile_size"])
	atlas_columns = int(tiles["columns"])
	tile_kinds = PackedStringArray()
	tile_ids = {}
	tile_names = PackedStringArray()
	for t: Dictionary in tiles["tiles"]:
		tile_ids[str(t["name"])] = tile_kinds.size()
		tile_kinds.append(str(t["kind"]))
		tile_names.append(str(t["name"]))
	map_name = name
	width = int(data["width"])
	height = int(data["height"])
	deck_height = int(data.get("deck_height", height))
	deck_stride = int(data.get("deck_stride", ((height + 16) >> 4) << 4))
	deck_names = PackedStringArray()
	for n: Variant in data.get("decks", ["Палуба"]):
		deck_names.append(str(n))
	deck_count = deck_names.size()
	if deck_stride % 16 != 0 or deck_stride <= deck_height or height != deck_stride * (deck_count - 1) + deck_height:
		return "Карта «%s»: палубы уложены неверно." % name
	cells = PackedInt32Array()
	walk = PackedByteArray()
	opaque = PackedByteArray()
	cells.resize(width * height)
	walk.resize(width * height)
	opaque.resize(width * height)
	var windows := []
	fitting = PackedByteArray()
	fitting.resize(tile_kinds.size())
	for t: Dictionary in tiles["tiles"]:
		if FITTINGS.has(str(t["name"]).trim_prefix("pirate_")) and tile_ids.has(str(t["name"])):
			fitting[int(tile_ids[str(t["name"])])] = 1
		if str(t["name"]).trim_prefix("pirate_").begins_with("window"):
			windows.append(tile_ids[str(t["name"])])
	var src: Array = data["cells"]
	if src.size() != width * height:
		return "Карта «%s»: размер не совпадает с содержимым." % name
	var h := 17
	for i in src.size():
		var id := int(src[i])
		cells[i] = id
		var ok := id >= 0 and id < tile_kinds.size() and tile_kinds[id] != "wall"
		walk[i] = 1 if ok else 0
		opaque[i] = 1 if id >= 0 and not ok and not windows.has(id) else 0
		h = (h * 31 + id + 2) & 0x7FFFFFFF
	on_floor = {}
	tall = {}
	for t: Array in data.get("things", []):
		var at := int(t[1]) * width + int(t[0])
		on_floor[at] = int(t[2])
		opaque[at] = 0
		if cells[at] >= 0 and TALL.has(tile_names[cells[at]].trim_prefix("pirate_")):
			tall[at] = true
			opaque[at] = 1
		h = (h * 31 + at + 3) & 0x7FFFFFFF
	spawns = []
	for s: Array in data["spawns"]:
		spawns.append(Vector2i(int(s[0]), int(s[1])))
	if spawns.is_empty() and needs_spawns:
		return "Карта «%s»: нет точек появления." % name

	doors = []
	door_kind = PackedByteArray()
	door_of = PackedInt32Array()
	door_of.resize(width * height)
	door_of.fill(-1)
	for d: Array in data.get("doors", []):
		var at := Vector2i(int(d[0]), int(d[1]))
		if not walkable(at.x, at.y):
			return "Карта «%s»: дверь стоит на непроходимой клетке." % name
		door_of[at.y * width + at.x] = doors.size()
		doors.append(at)
		door_kind.append(DOOR_AIRLOCK if str(d[2]) == "A" else DOOR_BAND)
		h = (h * 31 + at.x * 131 + at.y + 5) & 0x7FFFFFFF
	door_access = PackedByteArray()
	var access: Array = data.get("door_access", [])
	for d in doors.size():
		door_access.append(int(access[d]) if d < access.size() else 0)
		h = (h * 31 + door_access[d]) & 0x7FFFFFFF
	crc = ((h * 31 + width) * 31 + deck_stride * 7 + deck_count) & 0x7FFFFFFF
	door_look = PackedStringArray()
	door_look.resize(doors.size())
	for l: Array in data.get("door_looks", []):
		var d := door_of[int(l[1]) * width + int(l[0])]
		if d >= 0:
			door_look[d] = str(l[2])
	door_sides = PackedInt32Array()
	for d in doors.size():
		var at: Vector2i = doors[d]
		var step := Vector2i(0, 1) if door_kind[d] == DOOR_BAND else Vector2i(1, 0)
		for side: Vector2i in [at - step, at + step]:
			door_sides.append(side.y * width + side.x if walkable(side.x, side.y) else -1)

	oxygen = {}
	helm = {}
	chart = {}
	engine = {}
	air_plant = {}
	locker = {}
	intercom = {}
	med_box = {}
	tech_box = {}
	holo = {}
	shield = {}
	bench = {}
	bay = {}
	autodoc = {}
	scanner = {}
	smes = {}
	smes_small = {}
	comms = {}
	trays = PackedInt32Array()
	cryo = PackedInt32Array()
	stove = {}
	dock = {}
	force_field = {}
	backup_rooms = {}
	guns = PackedInt32Array()
	gun_console = {}
	drone_console = {}
	zones = []
	for z: Array in data.get("zones", []):
		var at: int = int(z[0])
		while zones.size() <= at:
			zones.append(PackedInt32Array())
		zones[at] = PackedInt32Array(z[1])
	_find_rooms()
	access_in = PackedByteArray()
	access_in.resize(width * height)
	for r: Array in data.get("access_rooms", []):
		var at := int(r[1]) * width + int(r[0])
		if at >= 0 and at < room_of.size() and room_of[at] >= 0:
			for c: int in rooms[room_of[at]]:
				access_in[c] |= int(r[2])
	brig = PackedByteArray()
	brig.resize(width * height)
	for r: Array in data.get("brig_rooms", []):
		var at := int(r[1]) * width + int(r[0])
		if at >= 0 and at < room_of.size() and room_of[at] >= 0:
			for c: int in rooms[room_of[at]]:
				brig[c] = 1
	_group_machines()
	for i in cells.size():
		if cells[i] >= 0 and cells[i] < fitting.size() and fitting[cells[i]] == 1 and root[i] != i:
			continue                         # (v91) a piece of a wide machine: its first cell stands for it
		if cells[i] >= 0 and cells[i] == tile_ids.get("gun", -2):
			guns.append(i)
		if cells[i] >= 0 and cells[i] == tile_ids.get("console_4", -2):
			gun_console[i] = true
		if cells[i] >= 0 and cells[i] == tile_ids.get("console_5", -2):
			drone_console[i] = true
		if cells[i] < 0:
			continue
		if cells[i] == tile_ids.get("locker", -1):
			locker[i] = true
		if cells[i] == tile_ids.get("intercom", -1):
			intercom[i] = true
		if cells[i] == tile_ids.get("med_box", -1):
			med_box[i] = true
		if cells[i] == tile_ids.get("tech_box", -1):
			tech_box[i] = true
		if cells[i] == tile_ids.get("holo", -1):
			holo[i] = true
		if cells[i] == tile_ids.get("shield", -1):
			shield[i] = true
		if cells[i] == tile_ids.get("bench", -1):
			bench[i] = true
		if cells[i] == tile_ids.get("bay", -1):
			bay[i] = true
		if cells[i] == tile_ids.get("scanner", -1):
			scanner[i] = true
		if cells[i] == tile_ids.get("smes", -1):
			smes[i] = true
		if cells[i] == tile_ids.get("comms", -1):
			comms[i] = true
		if cells[i] == tile_ids.get("tray", -1):
			trays.append(i)
		if cells[i] == tile_ids.get("cryo", -1):
			cryo.append(i)
		if cells[i] == tile_ids.get("stove", -1):
			stove[i] = true
		if cells[i] == tile_ids.get("dock", -1):
			dock[i] = true
		if cells[i] == tile_ids.get("window_field", -1):
			force_field[i] = true
		if cells[i] == tile_ids.get("smes_small", -1):
			smes_small[i] = true
			var front := fitting_front(i)
			if front >= 0 and room_of[front] >= 0:
				backup_rooms[room_of[front]] = true
		if cells[i] == tile_ids.get("autodoc", -1):
			autodoc[i] = fitting_front(i)
		if cells[i] == tile_ids.get("engine", -1):
			engine[i] = true
		elif cells[i] == tile_ids.get("air_plant", -1):
			# it blows into the room it faces
			var front := fitting_front(i)
			if front >= 0:
				air_plant[i] = front
		if cells[i] == tile_ids.get("console_2", -1):
			oxygen[i] = true
		elif cells[i] == tile_ids.get("console_3", -1):
			helm[i] = true
		elif cells[i] == tile_ids.get("console_1", -1):
			chart[i] = true

	var problem := _find_airlocks()
	if problem != "":
		return problem
	base_cells = cells.duplicate()
	base_walk = walk.duplicate()
	base_opaque = opaque.duplicate()

	# what joins the decks: see-through floors, shared air, ladders
	var n_cells := width * height
	see_through = PackedByteArray()
	see_through.resize(n_cells)
	air_down = PackedInt32Array()
	air_down.resize(n_cells)
	air_down.fill(-1)
	air_up = air_down.duplicate()
	climb = air_down.duplicate()
	for i in n_cells:
		if cells[i] < 0:
			continue
		var kind := tile_kinds[cells[i]]
		if kind != "glass" and kind != "grate" and kind != "hatch":
			continue
		see_through[i] = 1
		var under := i + deck_stride * width
		if kind == "glass" or under >= n_cells or walk[under] == 0:
			continue
		if door_of[under] >= 0:
			return "Карта «%s»: под мостками или люком стоит дверь." % name
		air_down[i] = under
		air_up[under] = i
		if kind == "hatch":
			climb[i] = under
			if climb[under] < 0:
				climb[under] = i             # (a shaft through three decks would need a choice of direction)

	var stairs_problem := _find_stairs(name)
	if stairs_problem != "":
		return stairs_problem

	hull = PackedInt32Array()
	for y in height:
		for x in width:
			if cells[y * width + x] < 0 or walk[y * width + x] == 1:
				continue
			# (v80, the author's note) never a hole on a machine set into the wall: its "use"
			# would win over the patch and the hole could not be mended
			if fitting_front(y * width + x) >= 0 or guns.has(y * width + x) or force_field.has(y * width + x):
				continue                     # ((v86) nor in a force field: no wall there to hole)
			var inside := walkable(x - 1, y) or walkable(x + 1, y) or walkable(x, y - 1) or walkable(x, y + 1)
			var outside := is_space(x - 1, y) or is_space(x + 1, y) or is_space(x, y - 1) or is_space(x, y + 1)
			if inside and outside:
				hull.append(y * width + x)
	panes = PackedInt32Array()
	for i in cells.size():
		if cells[i] >= 0 and windows.has(cells[i]) and not tile_names[cells[i]].ends_with("window_field"):
			panes.append(i)
	_place_vents()
	return ""


func _stair(c: int) -> bool:
	return c >= 0 and c < cells.size() and cells[c] >= 0 and tile_names[cells[c]].trim_prefix("pirate_") == "stairs"


func _find_stairs(name: String) -> String:
	## (v91, the author's F3: "dark stairs go down, white go up") A flight of stairs is two cells of '/' in a row on
	## one deck and the same two on the deck below. Going down, one walks onto the upper flight from its open end
	## and, stepping onto its other end (over the stairwell), comes out on the lower deck at the cell under it,
	## walking on into the room there; going up the other way round. The upper flight ends at a wall, the lower
	## one at the room's floor, so `stair_to` holds the two cells where one changes decks.
	stair_to = PackedInt32Array()
	stair_to.resize(width * height)
	stair_to.fill(-1)
	flights = []
	var done := {}
	var down := deck_stride * width
	for i in cells.size():
		if not _stair(i) or done.has(i):
			continue
		var x := i % width
		var y := i / width
		var along := Vector2i(1, 0) if x + 1 < width and _stair(i + 1) else Vector2i(0, 1)
		var step := along.y * width + along.x
		var j := i + step
		if not _stair(j) or deck_of(j / width) != deck_of(y) or _stair(j + step):
			return "Карта «%s»: лестница в %d,%d должна быть длиной в две клетки." % [name, x, y]
		done[i] = true
		done[j] = true
		if _stair(i - down) and _stair(j - down):
			continue                         # the lower flight of a pair, met with the upper one
		if not (_stair(i + down) and _stair(j + down)):
			return "Карта «%s»: лестнице в %d,%d нужна такая же на палубе ниже." % [name, x, y]
		done[i + down] = true
		done[j + down] = true
		# below, the flight comes out into the room at one end and has a wall behind the other
		var top := -1
		var bottom := -1
		var way := along
		var lj := j + down
		var li := i + down
		if walkable(lj % width + along.x, lj / width + along.y) and not _stair(lj + step):
			top = li
			bottom = lj
		elif walkable(li % width - along.x, li / width - along.y) and not _stair(li - step):
			top = lj
			bottom = li
			way = -along
		if top < 0 or walkable(top % width - way.x, top / width - way.y):
			return "Карта «%s»: лестница в %d,%d должна выходить в отсек на палубе ниже одним концом, а другим упираться в стену." % [name, x, y]
		var over := bottom - down
		if walkable(over % width + way.x, over / width + way.y):
			return "Карта «%s»: лестница в %d,%d наверху должна упираться в стену." % [name, x, y]
		stair_to[over] = bottom
		stair_to[top] = top - down
		if air_down[over] < 0:
			air_down[over] = bottom
			air_up[bottom] = over
		flights.append({"cells": PackedInt32Array([top - down, over]), "way": way, "down": true})
		flights.append({"cells": PackedInt32Array([top, bottom]), "way": way, "down": false})
	return ""


func _place_vents() -> void:
	## (v69, the author's idea) A vent in every room but an airlock's chamber: on the
	## floor cell nearest the room's middle that is no ladder, hatch or catwalk.
	vents = PackedInt32Array()
	var chambers := {}
	for pump: int in lock_pump.keys():
		for c: int in lock_pump[pump]["chamber"]:
			chambers[c] = true
	for room: PackedInt32Array in rooms:
		if room.size() < 2 or chambers.has(room[0]):
			continue
		var mid := Vector2.ZERO
		for c in room:
			mid += Vector2(c % width, c / width)
		mid /= room.size()
		var best := -1
		var best_d := INF
		for c in room:
			if climb[c] >= 0 or see_through[c] == 1 or _stair(c):
				continue
			var d := Vector2(c % width, c / width).distance_squared_to(mid)
			if d < best_d - 0.001:
				best_d = d
				best = c
		if best >= 0:
			vents.append(best)


func _find_airlocks() -> String:
	## An airlock is a chamber with a pump on its wall and two doors: an outer
	## one that opens into space and an inner one into the ship.
	lock_pump = {}
	door_partner = PackedInt32Array()
	door_partner.resize(doors.size())
	door_partner.fill(-1)
	door_vent = PackedByteArray()
	door_vent.resize(doors.size())
	for d in doors.size():
		var at: Vector2i = doors[d]
		var step := Vector2i(0, 1) if door_kind[d] == DOOR_BAND else Vector2i(1, 0)
		var a := at - step
		var b := at + step
		if (door_sides[d * 2] < 0 and is_space(a.x, a.y)) or (door_sides[d * 2 + 1] < 0 and is_space(b.x, b.y)):
			door_vent[d] = 1
	var pump_id: int = tile_ids.get("lock_pump", -1)
	for i in cells.size():
		if pump_id < 0 or cells[i] != pump_id:
			continue
		var x := i % width
		var y := i / width
		var start := -1
		for o: int in [width, -width]:
			var j := i + o
			if j >= 0 and j < cells.size() and walk[j] == 1 and door_of[j] < 0:
				start = j
				break
		if start < 0:
			return "Карта «%s»: насос шлюза в %d,%d не смотрит в камеру." % [map_name, x, y]
		# the chamber: floor reached from the pump without passing a door
		var seen := {start: true}
		var todo := [start]
		while not todo.is_empty():
			var c: int = todo.pop_back()
			for o: int in [1, -1, width, -width]:
				var j := c + o
				if j < 0 or j >= cells.size() or seen.has(j) or walk[j] == 0 or door_of[j] >= 0:
					continue
				if absi(j % width - c % width) > 1:
					continue
				seen[j] = true
				todo.append(j)
		var inner := -1
		var outer := -1
		for d in doors.size():
			if seen.has(door_sides[d * 2]) or seen.has(door_sides[d * 2 + 1]):
				if door_vent[d] == 1:
					outer = d
				else:
					inner = d
		if inner < 0 or outer < 0:
			return "Карта «%s»: у шлюза с насосом в %d,%d нет двух дверей (внутренней и наружной)." % [map_name, x, y]
		door_partner[inner] = outer
		door_partner[outer] = inner
		lock_pump[i] = {"chamber": PackedInt32Array(seen.keys()), "inner": inner, "outer": outer}
	return ""


func _find_rooms() -> void:
	## Splits the floor into rooms: cells reached from one another without
	## passing a wall or a door. Numbered in the order their first cell comes,
	## row by row, so the server and every client number them alike.
	rooms = []
	room_of = PackedInt32Array()
	room_of.resize(width * height)
	room_of.fill(-1)
	for start in cells.size():
		if walk[start] == 0 or door_of[start] >= 0 or room_of[start] >= 0:
			continue
		var n := rooms.size()
		var room := PackedInt32Array([start])
		room_of[start] = n
		var i := 0
		while i < room.size():
			var c: int = room[i]
			i += 1
			for step: int in [1, -1, width, -width]:
				var j := c + step
				if j < 0 or j >= cells.size() or (step == 1 and j % width == 0) or (step == -1 and c % width == 0):
					continue
				if walk[j] == 0 or door_of[j] >= 0 or room_of[j] >= 0:
					continue
				room_of[j] = n
				room.append(j)
		room.sort()
		rooms.append(room)


static func other_maps() -> Array[String]:
	## The drawings of other ships that may come alongside, in the order `others` numbers them.
	var out: Array[String] = Net.OTHER_MAPS.duplicate()
	out.append_array(own_others)
	if try_other != "":
		out.append(try_other)
	return out


static func own_drawings() -> Array[Dictionary]:
	## (v84) The drawings in the «ships» folder, by name: {"name" ("ships:NAME"), "file" (NAME), "kind", "text"}.
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(ships_dir())
	if dir == null:
		return out
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		if f.get_extension() != "txt":
			continue
		var text := FileAccess.get_file_as_string(ships_dir().path_join(f))
		if text.is_empty():
			continue
		out.append({"name": USER_PREFIX + f.get_basename(), "file": f.get_basename(),
			"kind": MapBuilder.kind_of(f.get_basename(), text), "text": text})
	return out


static func coming_in_run() -> Array[String]:
	## (v84, the author's H5) Own drawings of pirate ships, derelicts and asteroids the game can use: they load,
	## and a pirate ship has a room for each of its systems. One that does not fit off our airlock is never met.
	var out: Array[String] = []
	for d: Dictionary in own_drawings():
		if not ["pirate", "derelict", "asteroid"].has(str(d["kind"])):
			continue
		var built := MapBuilder.build(str(d["file"]), str(d["text"]))
		if not (built["problems"] as Array).is_empty():
			continue
		var o: RefCounted = load("res://src/shared/ship_map.gd").new()
		if o.load_data(str(d["name"]), FileAccess.get_file_as_string("res://assets/tiles.json"), built["data"], false) != "":
			continue
		if str(d["kind"]) == "pirate" and o.rooms.size() < Net.ESYS_COUNT - 2:
			continue
		out.append(str(d["name"]))
	return out


static func drawings_in_use(main: String) -> Dictionary:
	## (v84) The texts of the drawings of one's own a game on `main` uses: sent to every guest, kept in the save.
	var out := {}
	var names: Array[String] = []
	for n in main.split(FLEET_JOIN):         # (v85) every ship of the fleet
		names.append(n)
	names.append_array(other_maps())
	for n: String in names:
		if n.begins_with(USER_PREFIX) and drawings.has(n):
			out[n] = drawings[n]
	return out


static func pack_maps(main: String) -> PackedByteArray:
	## (v84, the author's H1) The end of S_WELCOME: the other ships' drawings by name in the order `others`
	## numbers them (u8 count, then u8 length and name each), then the drawings of one's own those use
	## (u8 count, then u8 name length, name, u32 text size, u32 packed size, the text deflated each).
	var w := PackedByteArray()
	var names := other_maps()
	w.append(names.size())
	for n: String in names:
		var b := n.to_utf8_buffer()
		w.append(b.size())
		w.append_array(b)
	var used := drawings_in_use(main)
	w.append(used.size())
	for n: String in used:
		var b := n.to_utf8_buffer()
		var text := str(used[n]).to_utf8_buffer()
		var packed := text.compress(FileAccess.COMPRESSION_DEFLATE)
		w.append(b.size())
		w.append_array(b)
		var at := w.size()
		w.resize(at + 8)
		w.encode_u32(at, text.size())
		w.encode_u32(at + 4, packed.size())
		w.append_array(packed)
	return w


static func unpack_maps(pkt: PackedByteArray, pos: int) -> Dictionary:
	## The other side of pack_maps: {"others": [names], "drawings": {name: text}}, or {} if it is cut short.
	var names: Array[String] = []
	var got := {}
	if pos >= pkt.size():
		return {}
	var count := pkt[pos]
	pos += 1
	for i in count:
		if pos >= pkt.size() or pos + 1 + pkt[pos] > pkt.size():
			return {}
		names.append(pkt.slice(pos + 1, pos + 1 + pkt[pos]).get_string_from_utf8())
		pos += 1 + pkt[pos]
	if pos >= pkt.size():
		return {}
	count = pkt[pos]
	pos += 1
	for i in count:
		if pos >= pkt.size() or pos + 1 + pkt[pos] + 8 > pkt.size():
			return {}
		var n := pkt.slice(pos + 1, pos + 1 + pkt[pos]).get_string_from_utf8()
		pos += 1 + pkt[pos]
		var size := pkt.decode_u32(pos)
		var packed := pkt.decode_u32(pos + 4)
		pos += 8
		if pos + packed > pkt.size():
			return {}
		got[n] = pkt.slice(pos, pos + packed).decompress(size, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()
		pos += packed
	return {"others": names, "drawings": got}


func serious() -> String:
	## (v84, the author's H3) What makes this drawing unplayable as our own ship, or "" (a ship with nowhere to
	## appear never loads at all). The rest of the ship editor's problems only warn.
	if helm.is_empty():
		return "нет штурвала (пульт управления, «3»): кораблём нельзя править."
	if engine.is_empty():
		return "нет двигателя («6»): кораблю нечем лететь."
	return ""


func others_of(of_kind: String) -> Array[int]:
	## (v81) The numbers in `others` of the drawings of that kind (pirate, derelict, asteroid).
	var out: Array[int] = []
	for k in others.size():
		if str(others[k].kind) == of_kind and others[k].map_name != try_other:
			out.append(k)
	return out


func add_other(name: String) -> int:
	## Makes room for another kind of ship that may come alongside: its layout,
	## and numbers for its doors. Returns its number in `others`, or -1 if its
	## map would not load. It is not here until `place_other`.
	var o: RefCounted = load("res://src/shared/ship_map.gd").new()
	if o.load_from(name, false) != "":
		return -1
	if others.is_empty():
		other = o
		other_first_door = doors.size()
	others.append(o)
	while doors.size() - other_first_door < o.doors.size():
		doors.append(NO_OTHER)
		door_kind.append(DOOR_BAND)
		door_sides.append(-1)
		door_sides.append(-1)
		door_partner.append(-1)
		door_vent.append(0)
		door_access.append(0)              # another ship's doors ask for no access
		door_look.append("")
	return others.size() - 1


func other_fits_kind(kind: int, at: Vector2i) -> bool:
	var keep = other
	other = others[kind]
	var ok := other_fits(at)
	other = keep
	return ok


func other_fits(at: Vector2i) -> bool:
	## Can the other ship lie with its corner there: on one deck, over nothing but space?
	if other == null:
		return false
	var o = other
	if at.x < 0 or at.y < 0 or at.x + o.width > width or local_y(at.y) + o.height > deck_height:
		return false
	for y in o.height:
		for x in o.width:
			if o.cells[y * o.width + x] >= 0 and base_cells[(at.y + y) * width + at.x + x] >= 0:
				return false
	return true


func place_other(at: Vector2i, kind: int = 0) -> void:
	## Lays another ship of that kind into the grid with its corner there (NO_OTHER takes it away).
	for c in other_cells:
		cells[c] = base_cells[c]
		walk[c] = base_walk[c]
		opaque[c] = base_opaque[c]
		door_of[c] = -1
		on_floor.erase(c)
		tall.erase(c)
		root[c] = c
		pieces.erase(c)
	other_cells = PackedInt32Array()
	other_at = at
	for d in range(other_first_door, doors.size()):
		doors[d] = NO_OTHER
	other_kind = kind if at != NO_OTHER else -1
	if not others.is_empty():
		other = others[maxi(kind, 0)]
	var o = other
	for d in o.doors.size():
		door_kind[other_first_door + d] = o.door_kind[d]
		door_look[other_first_door + d] = o.door_look[d]
	if at != NO_OTHER:
		for y in o.height:
			for x in o.width:
				var from: int = y * o.width + x
				if o.cells[from] < 0:
					continue
				var c: int = (at.y + y) * width + at.x + x
				other_cells.append(c)
				cells[c] = o.cells[from]
				walk[c] = o.walk[from]
				opaque[c] = o.opaque[from]
				if o.on_floor.has(from):
					on_floor[c] = o.on_floor[from]
				if o.tall.has(from):
					tall[c] = true
				var r: int = o.root[from]
				root[c] = (at.y + r / o.width) * width + at.x + r % o.width
				if o.pieces.has(from):
					var mine := PackedInt32Array()
					for q: int in o.pieces[from]:
						mine.append((at.y + q / o.width) * width + at.x + q % o.width)
					pieces[c] = mine
		for d in o.doors.size():
			var p: Vector2i = o.doors[d] + at
			doors[other_first_door + d] = p
			door_of[p.y * width + p.x] = other_first_door + d
	_sides()


func door_tint(d: int) -> String:
	## The prefix of the tiles this door is drawn in ("pirate_" on a pirate ship).
	if d >= other_first_door and other_kind >= 0 and str(other.kind) == "pirate":
		return "pirate_"
	return ""


func is_other(cell: int) -> bool:
	## Is this cell part of the other ship (while it is here)?
	return other_at != NO_OTHER and cell >= 0 and cell < cells.size() and base_cells[cell] < 0 and cells[cell] >= 0


func leaving(x: int, y: int, door: int) -> bool:
	## (v69, the author's note: no time to break the lock coming back from space) Is one
	## standing at x, y on the inside of that restricted door? Leaving a locked room is free.
	var c := y * width + x
	return c >= 0 and c < access_in.size() and (access_in[c] & door_access[door]) != 0


func is_brig(cell: int) -> bool:
	return cell >= 0 and cell < brig.size() and brig[cell] == 1


func brig_cells() -> Array:
	## (v75) The rooms (cells each) of the brig, top-left first.
	var out: Array = []
	var seen := {}
	for c in brig.size():
		if brig[c] == 1 and room_of[c] >= 0 and not seen.has(room_of[c]):
			seen[room_of[c]] = true
			out.append(rooms[room_of[c]])
	return out


func room_at(x: int, y: int) -> int:
	## The room a cell lies in (-1: none, or off the map).
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return room_of[y * width + x]


func on_ship(cell: int) -> bool:
	## Is this cell inside our own ship?
	return cell >= 0 and cell < base_walk.size() and base_walk[cell] == 1


func door_here(d: int) -> bool:
	## Is this door anywhere (the other ship's doors are not while it is away)?
	return doors[d] != NO_OTHER


func _sides() -> void:
	## Which floor lies on either side of every door, and which doors open into space.
	for d in doors.size():
		var at: Vector2i = doors[d]
		var step := Vector2i(0, 1) if door_kind[d] == DOOR_BAND else Vector2i(1, 0)
		var a := at - step
		var b := at + step
		var here := at != NO_OTHER
		door_sides[d * 2] = a.y * width + a.x if here and walkable(a.x, a.y) else -1
		door_sides[d * 2 + 1] = b.y * width + b.x if here and walkable(b.x, b.y) else -1
		door_vent[d] = 1 if here and ((door_sides[d * 2] < 0 and is_space(a.x, a.y)) or (door_sides[d * 2 + 1] < 0 and is_space(b.x, b.y))) else 0


func lock_beyond(pump: int) -> int:
	## The floor just past the outer door of that pump's airlock: the ship docked
	## there (v54), or -1 when the door opens into space.
	var lock: Dictionary = lock_pump[pump]
	var d: int = lock["outer"]
	if d < 0:
		return -1
	var chamber: PackedInt32Array = lock["chamber"]
	for k in 2:
		var c := door_sides[d * 2 + k]
		if c >= 0 and not chamber.has(c):
			return c
	return -1


func lock_inside(pump: int) -> int:
	## (v73) The floor just past the inner door of that pump's airlock (the ship's
	## own side), or -1.
	var lock: Dictionary = lock_pump[pump]
	var d: int = lock["inner"]
	if d < 0:
		return -1
	var chamber: PackedInt32Array = lock["chamber"]
	for k in 2:
		var c := door_sides[d * 2 + k]
		if c >= 0 and not chamber.has(c):
			return c
	return -1


func floats(x: int, y: int) -> bool:
	## Open space a suited character can drift through: inside the grid, on a
	## deck's own rows, where there is no ship.
	return x >= 0 and y >= 0 and x < width and y < height and local_y(y) < deck_height and cells[y * width + x] < 0


func passable(x: int, y: int) -> bool:
	## Can a character be in this cell: on a floor, in a doorway, or out in space?
	return walkable(x, y) or floats(x, y)


func walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height and walk[y * width + x] == 1


func is_space(x: int, y: int) -> bool:
	return x < 0 or y < 0 or x >= width or y >= height or cells[y * width + x] < 0


func door_at(x: int, y: int) -> int:
	## The number of the door in this cell, or -1.
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return door_of[y * width + x]


func cell_ahead(x: int, y: int, facing: int) -> int:
	## The cell a character standing at x,y and facing that way looks at, or -1 outside the map.
	var tx: int = x + Net.DX[facing]
	var ty: int = y + Net.DY[facing]
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return -1
	return ty * width + tx


func fitting_front(cell: int) -> int:
	## The floor cell a thing fitted into this wall cell faces: the one below it,
	## failing that above, then to the right or left. -1 = no fitting here.
	## (v91) A machine standing on the floor faces away from the wall it stands against.
	if cell < 0 or cell >= cells.size() or cells[cell] < 0 or cells[cell] >= fitting.size() or fitting[cells[cell]] == 0:
		return -1
	var x := cell % width
	var y := cell / width
	if on_floor.has(cell):
		for v: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if _wall(x + v.x, y + v.y) and walkable(x - v.x, y - v.y):
				return (y - v.y) * width + x - v.x
	for v: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if walkable(x + v.x, y + v.y):
			return (y + v.y) * width + x + v.x
	return -1


func behind(cell: int) -> int:
	## (v91) The wall cell a machine standing on the floor has its back to; -1 = none.
	var front := fitting_front(cell)
	if not on_floor.has(cell) or front < 0:
		return -1
	return cell - (front - cell)


func _wall(x: int, y: int) -> bool:
	## (v91) A wall here (a window, a fitting in it, an airlock's frame), not a machine on the floor nor open space?
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	var c := y * width + x
	return cells[c] >= 0 and walk[c] == 0 and not on_floor.has(c)


func _group_machines() -> void:
	## (v91) Which cells are pieces of one machine (MACHINE_WIDE): a row of as many of one as its picture is wide,
	## along the wall it stands at (down a side wall for one facing sideways); the holo table two by two. Its first
	## cell (top, then left) stands for it everywhere: in the lists of machines, for "use", breakdowns and mending.
	root = PackedInt32Array()
	root.resize(width * height)
	for i in root.size():
		root[i] = i
	pieces = {}
	for i in cells.size():
		var id := cells[i]
		if id < 0 or id >= fitting.size() or fitting[id] == 0 or root[i] != i or pieces.has(i):
			continue
		var x := i % width
		var y := i / width
		var name := tile_names[id].trim_prefix("pirate_")
		var k: int = MACHINE_WIDE.get(name, 1)
		if k < 2:
			continue
		var group := PackedInt32Array()
		if name == "console_1" and on_floor.has(i) and x + 1 < width and y + 1 < height \
				and cells[i + 1] == id and cells[i + width] == id and cells[i + width + 1] == id:
			group = PackedInt32Array([i, i + 1, i + width, i + width + 1])
		else:
			var front := fitting_front(i)
			var step := width if front == i - 1 or front == i + 1 else 1
			# the run of this machine this cell starts (cells before it are already grouped or on their own)
			var run := 0
			var c := i
			while c < cells.size() and cells[c] == id and (step == width or c / width == y) and root[c] == c:
				run += 1
				c += step
			var before := 0
			c = i - step
			while c >= 0 and cells[c] == id and (step == width or c / width == y):
				before += 1
				c -= step
			if before > 0 or run % k != 0:
				continue                     # not a whole number of machines: each cell is one on its own
			for j in run:
				group.append(i + j * step)
			for g in range(0, run, k):
				var one := group.slice(g, g + k)
				for p in one:
					root[p] = one[0]
				pieces[one[0]] = one
			continue
		for p in group:
			root[p] = group[0]
		pieces[group[0]] = group


func standing_look(cell: int) -> String:
	## (v91) The picture a machine standing on the floor here is drawn in (tools/make_assets.py FLOOR_LOOKS),
	## without the pirates' "pirate_": turned the way it faces, a piece of a wide one. "" = no machine on the floor.
	if not on_floor.has(cell) or cells[cell] < 0:
		return ""
	var name := tile_names[cells[cell]].trim_prefix("pirate_")
	var front := fitting_front(cell)
	var side := "_up" if front == cell - width else ("_r" if front == cell - 1 else ("_l" if front == cell + 1 else ""))
	var all: PackedInt32Array = pieces.get(root[cell], PackedInt32Array())
	if all.is_empty():
		return name + "_fl" + side
	if name == "console_1" and all.size() == 4:
		return "console_1_fl_t_%d" % all.find(cell)
	return "%s_fl%s_w%d_%d" % [name, side, all.size(), all.find(cell)]


func machine_of(cell: int) -> int:
	## (v91) The cell that stands for the machine this cell is a piece of (itself for anything else).
	return root[cell] if cell >= 0 and cell < root.size() else cell


func use_ahead(x: int, y: int, facing: int, keep: Dictionary = {}) -> int:
	## The cell the "use" key works on for a character at x,y facing that way:
	## the cell ahead, except that a thing fitted into a wall is only reached
	## from the room it faces (never through the wall), from the cell in front
	## of it or either cell beside that one (facing the wall). Cells in `keep`
	## (holes in the hull) are always the cell ahead. -1 = nothing.
	## (v91) A machine standing on the floor is reached from any cell round it; a piece of
	## a wide one gives the cell that stands for the whole machine (machine_of).
	var ahead := cell_ahead(x, y, facing)
	if ahead < 0 or keep.has(ahead):
		return ahead
	var here := y * width + x
	if on_floor.has(ahead):
		return root[ahead]
	if Net.diagonal(facing):
		# (v74) facing on a slant: a thing on the floor there or somebody there; failing that,
		# a fitting right beside us on either side of the slant; never a doorway or a wall
		for c: int in [y * width + x + Net.DX[facing], (y + Net.DY[facing]) * width + x]:
			if fitting_front(c) == here or on_floor.has(c):
				return root[c]
		return ahead if walk[ahead] == 1 and door_of[ahead] < 0 else -1
	var front := fitting_front(ahead)
	if front >= 0:
		return root[ahead] if front == here else -1
	if walk[ahead] == 1 or cells[ahead] < 0:
		return ahead
	# a bare wall: a fitting beside this spot of it, facing the cell beside us
	var along := 1 if Net.DX[facing] == 0 else width
	for side: int in [-along, along]:
		var c := ahead + side
		if c >= 0 and c < cells.size() and absi(c % width - ahead % width) <= 1 and fitting_front(c) == here + side:
			return root[c]
	return ahead


func device_name(cell: int) -> String:
	## What the thing on this wall cell is called, for messages ("" = nothing that can break).
	if chart.has(cell):
		return "карта сектора"
	if helm.has(cell):
		return "управление кораблём"
	if engine.has(cell):
		return "двигатель"
	if air_plant.has(cell):
		return "воздушная установка"
	if lock_pump.has(cell):
		return "насос шлюза"
	if guns.has(cell):
		return "орудие %d" % (guns.find(cell) + 1)
	if gun_console.has(cell):
		return "пульт орудий"
	if drone_console.has(cell):
		return "монитор дрона"
	if holo.has(cell):
		return "голокарта"
	if shield.has(cell):
		return "генератор щита"
	if bay.has(cell):
		return "модульная стойка"
	if autodoc.has(cell):
		return "автодок"
	if scanner.has(cell):
		return "медицинский сканер"
	if smes.has(cell):
		return "СМЭС"
	if smes_small.has(cell):
		return "резервный СМЭС мостика"
	if comms.has(cell):
		return "пульт связи"
	if dock.has(cell):
		return "пульт челнока"
	return ""


func on_backup(cell: int) -> bool:
	## (v61) Does the bridge's backup SMES feed this cell: a floor cell of the
	## room it faces, or a thing on a wall that is used from there?
	if backup_rooms.is_empty() or cell < 0 or cell >= cells.size():
		return false
	var at := cell if walk[cell] == 1 else fitting_front(cell)
	return at >= 0 and backup_rooms.has(room_of[at])


func deck_of(y: int) -> int:
	## Which deck a row of the grid belongs to (0 = the top deck).
	return y / deck_stride


func deck_of_cell(cell: int) -> int:
	return (cell / width) / deck_stride


func set_pane(cell: int, down: bool) -> void:
	## (v91, the author's W1) A window's shutter down stops light and sight as a wall does; up, the
	## window lets them through again. The server and the client both call it (Systems.update_panes,
	## GameClient's hull records), so they see alike.
	opaque[cell] = 1 if down else 0


func local_y(y: int) -> int:
	## The row inside its own deck.
	return y % deck_stride


func chunks_wide() -> int:
	return (width + 15) >> 4


func chunks_high() -> int:
	## Chunk rows of one deck.
	return (deck_height + 15) >> 4


func chunk_rows() -> int:
	## Chunk rows of the whole grid.
	return (height + 15) >> 4
