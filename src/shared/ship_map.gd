extends RefCounted
## A ship layout: which tile is drawn in every cell and where characters can
## walk. Loaded from maps/<name>.json, which tools/make_assets.py builds from
## the ASCII drawing next to it. The server and the client load the same file.

var map_name := ""
var width := 0
var height := 0
var cells := PackedInt32Array()      # tile id per cell, -1 = empty space
var walk := PackedByteArray()        # 1 = can be walked on
var spawns: Array[Vector2i] = []
var crc := 0                         # fingerprint of the layout, compared at login

var tile_size := 32
var atlas_columns := 8
var tile_kinds := PackedStringArray()


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
	for t: Dictionary in tiles["tiles"]:
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
	crc = (h * 31 + width) & 0x7FFFFFFF
	spawns = []
	for s: Array in data["spawns"]:
		spawns.append(Vector2i(int(s[0]), int(s[1])))
	if spawns.is_empty():
		return "Карта «%s»: нет точек появления." % name
	return ""


func walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height and walk[y * width + x] == 1


func chunks_wide() -> int:
	return (width + 15) >> 4


func chunks_high() -> int:
	return (height + 15) >> 4
