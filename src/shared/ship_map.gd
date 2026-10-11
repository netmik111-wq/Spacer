extends RefCounted
## A ship layout: which tile is drawn in every cell and where characters can
## walk. Loaded from maps/<name>.json, which tools/make_assets.py builds from
## the ASCII drawing next to it. The server and the client load the same file.

const DOOR_BAND := 0                 # a door in a horizontal wall ('D' in the drawing)
const DOOR_AIRLOCK := 1              # an airlock in a vertical wall ('A')

var map_name := ""
var width := 0
var height := 0
var cells := PackedInt32Array()      # tile id per cell, -1 = empty space
var walk := PackedByteArray()        # 1 = can be walked on (doors count: they open)
var spawns: Array[Vector2i] = []
var crc := 0                         # fingerprint of the layout, compared at login

var doors: Array[Vector2i] = []      # where each door is; a door is known by its number in this list
var door_kind := PackedByteArray()   # DOOR_BAND or DOOR_AIRLOCK, per door
var door_of := PackedInt32Array()    # door number per cell, -1 = no door there
var hull := PackedInt32Array()       # cells of the outer shell that can be breached: wall or window
                                     # with a walkable cell on one side and space on another

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
	crc = (h * 31 + width) & 0x7FFFFFFF

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


func chunks_wide() -> int:
	return (width + 15) >> 4


func chunks_high() -> int:
	return (height + 15) >> 4
