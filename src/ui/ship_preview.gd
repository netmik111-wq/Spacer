extends Control
## (v84, the author's H2) A small picture of a ship's drawing for the main menu's ship list: walls, floors,
## doors and the machines, deck by deck side by side, each cell a few pixels.

const MapBuilder := preload("res://src/shared/map_builder.gd")

const WALL := Color(0.62, 0.67, 0.76)
const FLOOR := Color(0.34, 0.38, 0.45)
const SEE := Color(0.3, 0.42, 0.5)          # glass, catwalks, hatches
const DOOR := Color(0.35, 0.8, 0.75)
const MACHINE := Color(0.95, 0.72, 0.3)
const GAP := 6.0                            # pixels between decks

var _cells := PackedInt32Array()
var _width := 0
var _deck_height := 0
var _stride := 0
var _decks := 0
var _colour := {}                           # tile id -> colour
var _doors := {}                            # cell -> true


func _init() -> void:
	custom_minimum_size = Vector2(440, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tiles: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles.json"))
	if typeof(tiles) != TYPE_DICTIONARY:
		return
	var id := 0
	for t: Dictionary in tiles["tiles"]:
		var name := str(t["name"]).trim_prefix("pirate_")
		var kind := str(t["kind"])
		if kind == "door" or name.begins_with("door") or name.begins_with("airlock"):
			_colour[id] = DOOR
		elif kind == "wall" and not (name.begins_with("wall") or name.begins_with("window")):
			_colour[id] = MACHINE
		elif kind == "wall":
			_colour[id] = WALL
		elif kind == "floor" or kind == "ladder":
			_colour[id] = FLOOR
		else:
			_colour[id] = SEE
		id += 1


func show_drawing(name: String, text: String) -> void:
	## The drawing to show ("" text: nothing).
	_cells = PackedInt32Array()
	_doors = {}
	if text != "":
		var built := MapBuilder.build(name.trim_prefix("ships:"), text)
		var data: Dictionary = built["data"]
		if data.has("cells"):
			_width = int(data["width"])
			_deck_height = int(data.get("deck_height", data["height"]))
			_stride = int(data.get("deck_stride", data["height"]))
			_decks = (data.get("decks", ["?"]) as Array).size()
			_cells = PackedInt32Array(data["cells"])
			for d: Array in data.get("doors", []):
				_doors[int(d[1]) * _width + int(d[0])] = true
	queue_redraw()


func _draw() -> void:
	if _cells.is_empty() or _width <= 0 or _deck_height <= 0:
		return
	var room := size - Vector2(GAP * (_decks - 1), 0)
	var px := floorf(minf(room.x / float(_width * _decks), room.y / float(_deck_height)))
	px = clampf(px, 1.0, 6.0)
	var whole := Vector2(_width * _decks * px + GAP * (_decks - 1), _deck_height * px)
	var corner := ((size - whole) / 2.0).floor()
	for d in _decks:
		var left := corner + Vector2(d * (_width * px + GAP), 0)
		for y in _deck_height:
			var row := (d * _stride + y) * _width
			if row + _width > _cells.size():
				break
			for x in _width:
				var id := _cells[row + x]
				if id < 0:
					continue
				var c: Color = DOOR if _doors.has(row + x) else _colour.get(id, FLOOR)
				draw_rect(Rect2(left + Vector2(x, y) * px, Vector2(px, px)), c)
