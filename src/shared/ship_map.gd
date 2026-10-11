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
var spawns: Array[Vector2i] = []
var crc := 0                         # fingerprint of the layout, compared at login

var doors: Array[Vector2i] = []      # where each door is; a door is known by its number in this list
var door_kind := PackedByteArray()   # DOOR_BAND or DOOR_AIRLOCK, per door
var door_of := PackedInt32Array()    # door number per cell, -1 = no door there
var hull := PackedInt32Array()       # cells of the outer shell that can be breached: wall or window
                                     # with a walkable cell on one side and space on another
var oxygen := {}                     # wall cells with an oxygen station (the red box): cell -> true
var helm := {}                       # wall cells with the ship's controls (the panel with orange lights)
var chart := {}                      # wall cells with the sector console (the green screen)
var engine := {}                     # wall cells with the engine: it drives the ship and its jumps
var air_plant := {}                  # wall cells with the air plant: cell -> the cell it blows into
var see_through := PackedByteArray() # per cell: 1 = its floor shows the deck below (glass, catwalk, hatch)
var air_down := PackedInt32Array()   # per cell: the cell below that shares its air (under a catwalk or
                                     # a hatch), or -1
var air_up := PackedInt32Array()     # the same, the other way
var climb := PackedInt32Array()      # per cell: where the ladder here leads (a cell on another deck), or -1

var tile_size := 32
var atlas_columns := 8
var tile_kinds := PackedStringArray()
var tile_ids := {}                   # tile name -> id


func load_from(name: String) -> String:
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
	cells.resize(width * height)
	walk.resize(width * height)
	var src: Array = data["cells"]
	if src.size() != width * height:
		return "Карта «%s»: размер не совпадает с содержимым." % name
	var h := 17
	for i in src.size():
		var id := int(src[i])
		cells[i] = id
		var ok := id >= 0 and id < tile_kinds.size() and tile_kinds[id] != "wall"
		walk[i] = 1 if ok else 0
		h = (h * 31 + id + 2) & 0x7FFFFFFF
	spawns = []
	for s: Array in data["spawns"]:
		spawns.append(Vector2i(int(s[0]), int(s[1])))
	if spawns.is_empty():
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
	crc = ((h * 31 + width) * 31 + deck_stride * 7 + deck_count) & 0x7FFFFFFF

	oxygen = {}
	helm = {}
	chart = {}
	engine = {}
	air_plant = {}
	for i in cells.size():
		if cells[i] < 0:
			continue
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
