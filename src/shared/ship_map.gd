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

const DOOR_BAND := 0                 # a door in a horizontal wall ('D' in the drawing)
const DOOR_AIRLOCK := 1              # an airlock in a vertical wall ('A')

var map_name := ""
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
                                     # with a walkable cell on one side and space on another
var oxygen := {}                     # wall cells with an oxygen station (the red box): cell -> true
var helm := {}                       # wall cells with the ship's controls (the panel with orange lights)
var chart := {}                      # wall cells with the sector console (the green screen)
var engine := {}                     # wall cells with the engine: it drives the ship and its jumps
var air_plant := {}                  # wall cells with the air plant: cell -> the cell it blows into
var locker := {}                     # wall cells with the supply locker
var intercom := {}                   # wall cells with an intercom panel
var guns := PackedInt32Array()       # wall cells with the ship's guns, in the order they are numbered
var gun_console := {}                # wall cells with the gun console (the fourth console of the mockup)
var holo := {}                       # wall cells with a holomap monitor: the whole ship's air, holes and breakdowns
var shield := {}                     # wall cells with the shield generator (see Gunnery)
var zones: Array = []                # (a ship others fight) the rooms its systems stand in: per Net.ESYS_*,
                                     # the cells of its own drawing (see Gunnery); empty = none named
var lock_pump := {}                  # wall cells with an airlock pump: cell -> {"chamber": cells of the
                                     # chamber it serves, "inner": door, "outer": door (-1 = none)}
var door_partner := PackedInt32Array() # per door: the other door of its airlock chamber, or -1.
                                     # Only one of the two may be open at a time (see Doors.bump)
var door_vent := PackedByteArray()   # per door: 1 = it opens straight into space (an airlock's outer door)
var door_access := PackedByteArray() # per door: the access it asks for (Net.ACCESS_* bits), 0 = anybody
var see_through := PackedByteArray() # per cell: 1 = its floor shows the deck below (glass, catwalk, hatch)
var air_down := PackedInt32Array()   # per cell: the cell below that shares its air (under a catwalk or
                                     # a hatch), or -1
var air_up := PackedInt32Array()     # the same, the other way
var climb := PackedInt32Array()      # per cell: where the ladder here leads (a cell on another deck), or -1

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

var tile_size := 32
var atlas_columns := 8
var tile_kinds := PackedStringArray()
var tile_ids := {}                   # tile name -> id
var fitting := PackedByteArray()     # per tile id: 1 = a thing fitted into a wall, used from the room it faces

# Things set into a wall face one room (see fitting_front) and are used from
# there: from the cell in front of them, or the cells either side of that one.
const FITTINGS := ["console_1", "console_2", "console_3", "console_4", "console_5",
	"engine", "air_plant", "locker", "intercom", "lock_pump", "holo", "shield"]


func load_from(name: String, needs_spawns: bool = true) -> String:
	## Returns "" on success or a description of what went wrong.
	var tiles_text := FileAccess.get_file_as_string("res://assets/tiles.json")
	var map_text := FileAccess.get_file_as_string("res://maps/%s.json" % name)
	if tiles_text.is_empty() or map_text.is_empty():
		return "Не найдены файлы карты «%s»." % name
	var tiles: Variant = JSON.parse_string(tiles_text)
	var data: Variant = JSON.parse_string(map_text)
	if typeof(tiles) != TYPE_DICTIONARY or typeof(data) != TYPE_DICTIONARY:
		return "Файлы карты «%s» повреждены." % name
	tile_size = int(tiles["tile_size"])
	atlas_columns = int(tiles["columns"])
	tile_kinds = PackedStringArray()
	tile_ids = {}
	for t: Dictionary in tiles["tiles"]:
		tile_ids[str(t["name"])] = tile_kinds.size()
		tile_kinds.append(str(t["kind"]))
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
	holo = {}
	shield = {}
	guns = PackedInt32Array()
	gun_console = {}
	zones = []
	for z: Array in data.get("zones", []):
		var at: int = int(z[0])
		while zones.size() <= at:
			zones.append(PackedInt32Array())
		zones[at] = PackedInt32Array(z[1])
	for i in cells.size():
		if cells[i] >= 0 and cells[i] == tile_ids.get("gun", -2):
			guns.append(i)
		if cells[i] >= 0 and cells[i] == tile_ids.get("console_4", -2):
			gun_console[i] = true
		if cells[i] < 0:
			continue
		if cells[i] == tile_ids.get("locker", -1):
			locker[i] = true
		if cells[i] == tile_ids.get("intercom", -1):
			intercom[i] = true
		if cells[i] == tile_ids.get("holo", -1):
			holo[i] = true
		if cells[i] == tile_ids.get("shield", -1):
			shield[i] = true
		if cells[i] == tile_ids.get("engine", -1):
			engine[i] = true
		elif cells[i] == tile_ids.get("air_plant", -1):
			# it blows into the room it faces: the cell below it, or failing that the one above
			var x := i % width
			var y := i / width
			if walkable(x, y + 1):
				air_plant[i] = i + width
			elif walkable(x, y - 1):
				air_plant[i] = i - width
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

	hull = PackedInt32Array()
	for y in height:
		for x in width:
			if cells[y * width + x] < 0 or walk[y * width + x] == 1:
				continue
			var inside := walkable(x - 1, y) or walkable(x + 1, y) or walkable(x, y - 1) or walkable(x, y + 1)
			var outside := is_space(x - 1, y) or is_space(x + 1, y) or is_space(x, y - 1) or is_space(x, y + 1)
			if inside and outside:
				hull.append(y * width + x)
	return ""


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
		for d in o.doors.size():
			var p: Vector2i = o.doors[d] + at
			doors[other_first_door + d] = p
			door_of[p.y * width + p.x] = other_first_door + d
	_sides()


func door_tint(d: int) -> String:
	## The prefix of the tiles this door is drawn in ("pirate_" on a pirate ship).
	if d >= other_first_door and other_kind >= 0 and str(other.map_name).begins_with("pirate"):
		return "pirate_"
	return ""


func is_other(cell: int) -> bool:
	## Is this cell part of the other ship (while it is here)?
	return other_at != NO_OTHER and cell >= 0 and cell < cells.size() and base_cells[cell] < 0 and cells[cell] >= 0


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
	var tx: int = x + [0, 0, 0, -1, 1][facing]
	var ty: int = y + [0, -1, 1, 0, 0][facing]
	if tx < 0 or ty < 0 or tx >= width or ty >= height:
		return -1
	return ty * width + tx


func fitting_front(cell: int) -> int:
	## The floor cell a thing fitted into this wall cell faces: the one below it,
	## failing that above, then to the right or left. -1 = no fitting here.
	if cell < 0 or cell >= cells.size() or cells[cell] < 0 or cells[cell] >= fitting.size() or fitting[cells[cell]] == 0:
		return -1
	var x := cell % width
	var y := cell / width
	for v: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if walkable(x + v.x, y + v.y):
			return (y + v.y) * width + x + v.x
	return -1


func use_ahead(x: int, y: int, facing: int, keep: Dictionary = {}) -> int:
	## The cell the "use" key works on for a character at x,y facing that way:
	## the cell ahead, except that a thing fitted into a wall is only reached
	## from the room it faces (never through the wall), from the cell in front
	## of it or either cell beside that one (facing the wall). Cells in `keep`
	## (holes in the hull) are always the cell ahead. -1 = nothing.
	var ahead := cell_ahead(x, y, facing)
	if ahead < 0 or keep.has(ahead):
		return ahead
	var here := y * width + x
	var front := fitting_front(ahead)
	if front >= 0:
		return ahead if front == here else -1
	if walk[ahead] == 1 or cells[ahead] < 0:
		return ahead
	# a bare wall: a fitting beside this spot of it, facing the cell beside us
	var along := 1 if Net.DX[facing] == 0 else width
	for side: int in [-along, along]:
		var c := ahead + side
		if c >= 0 and c < cells.size() and absi(c % width - ahead % width) <= 1 and fitting_front(c) == here + side:
			return c
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
	if holo.has(cell):
		return "голокарта"
	if shield.has(cell):
		return "генератор щита"
	return ""


func deck_of(y: int) -> int:
	## Which deck a row of the grid belongs to (0 = the top deck).
	return y / deck_stride


func deck_of_cell(cell: int) -> int:
	return (cell / width) / deck_stride


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
