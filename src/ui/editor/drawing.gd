extends RefCounted
## (v81) What the ship editor draws: one grid of signs per deck (the signs of maps/*.txt, see
## tools/make_assets.py), the marks on rooms (locks, brig cells, a pirate ship's systems) and what
## kind of drawing it is. Every tool's change goes through here, so undo and redo see all of it:
## a stroke (everything between two `commit`s) is one step back.
##
## (v82.1, the author's note) Two layers per cell: the floor layer ("base": space, wall, floor, glass,
## catwalk, rock) and the object layer on top of it (doors, windows, consoles, machines, guns, spawn
## places, ladders). "cells" holds what the game sees, the object if there is one, else the floor;
## "base" holds the floor under it. Taking an object away shows its floor again, and painting a floor
## under an object keeps the object. The saved text has one sign per cell, as the game reads it; the
## floor under an object is worked out again on opening (a wall under a wall object, floor under the rest).

const MapBuilder := preload("res://src/shared/map_builder.gd")

const MAX_SIZE := 96                 # the largest canvas, either way
const UNDO_STEPS := 200
const BASE_SIGNS := " #.gcRO,"       # the floor layer's signs; every other sign is an object
const LAYER_BOTH := 0                # tools act on the object first, then the floor (as before)
const LAYER_FLOOR := 1               # tools touch only the floor layer
const LAYER_OBJECTS := 2             # tools touch only objects

var width := 40
var height := 12
var kind := "ship"                   # MapBuilder.KINDS
var decks: Array = []                # per deck {"name", "cells": what the game sees, "base": the floor layer (width * height signs each)}
var marks: Array = []                # {"type": "@" (a lock or a brig cell) or "%" (a system), "deck", "x", "y", "what"}
var mirror_x := false                # every stroke is drawn again mirrored left-right...
var mirror_y := false                # ... and up-down
var changes := 0                     # counts every change (the editor redraws and checks when it moves)
var layer := LAYER_BOTH              # which layer the tools change

var _undo: Array = []
var _redo: Array = []
var _before: Dictionary = {}         # the drawing as it was when the stroke under way began (empty: none)


func reset(w: int, h: int, n_decks: int) -> void:
	width = clampi(w, 4, MAX_SIZE)
	height = clampi(h, 3, MAX_SIZE)
	decks = []
	for i in n_decks:
		decks.append({"name": _deck_name(i), "cells": _blank(), "base": _blank()})
	marks = []
	_undo.clear()
	_redo.clear()
	_before = {}
	changes += 1


func _deck_name(i: int) -> String:
	return ["Верхняя палуба", "Нижняя палуба", "Третья палуба", "Четвёртая палуба"][i] if i < 4 else "Палуба %d" % (i + 1)


func _blank() -> PackedStringArray:
	var c := PackedStringArray()
	c.resize(width * height)
	c.fill(" ")
	return c


func inside(at: Vector2i) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x < width and at.y < height


func at(deck: int, c: Vector2i) -> String:
	if deck < 0 or deck >= decks.size() or not inside(c):
		return " "
	return (decks[deck]["cells"] as PackedStringArray)[c.y * width + c.x]


func base_at(deck: int, c: Vector2i) -> String:
	## The floor layer there (under any object).
	if deck < 0 or deck >= decks.size() or not inside(c):
		return " "
	return (decks[deck]["base"] as PackedStringArray)[c.y * width + c.x]


static func is_object(sign: String) -> bool:
	return BASE_SIGNS.find(sign) < 0


static func base_for(sign: String) -> String:
	## The floor an object stands on when none was drawn: a spawn place or a ladder on floor, the rest in a wall.
	return "." if sign == "s" or sign == "H" or sign == "/" else "#"


func base_text() -> String:
	## The drawing with its objects taken away (the editor's "hide objects").
	var keep := decks
	decks = []
	for deck: Dictionary in keep:
		decks.append({"name": deck["name"], "cells": deck["base"], "base": deck["base"]})
	var text := to_text()
	decks = keep
	return text


# ---------------------------------------------------------------- changes

func _touch() -> void:
	## The first change of a stroke keeps the drawing as it was, for undo.
	if _before.is_empty():
		_before = _snapshot()
	changes += 1


func _snapshot() -> Dictionary:
	var d := []
	for deck: Dictionary in decks:
		d.append({"name": deck["name"], "cells": (deck["cells"] as PackedStringArray).duplicate(),
			"base": (deck["base"] as PackedStringArray).duplicate()})
	return {"w": width, "h": height, "kind": kind, "decks": d, "marks": marks.duplicate(true)}


func _restore(s: Dictionary) -> void:
	width = s["w"]
	height = s["h"]
	kind = s["kind"]
	decks = []
	for deck: Dictionary in s["decks"]:
		decks.append({"name": deck["name"], "cells": (deck["cells"] as PackedStringArray).duplicate(),
			"base": (deck["base"] as PackedStringArray).duplicate()})
	marks = (s["marks"] as Array).duplicate(true)
	changes += 1


func commit() -> void:
	## The stroke is over: one step for undo.
	if _before.is_empty():
		return
	_undo.append(_before)
	if _undo.size() > UNDO_STEPS:
		_undo.pop_front()
	_redo.clear()
	_before = {}


func undo() -> bool:
	commit()
	if _undo.is_empty():
		return false
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	return true


func redo() -> bool:
	commit()
	if _redo.is_empty():
		return false
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	return true


func can_undo() -> bool:
	return not _undo.is_empty() or not _before.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func _put_sign(deck: int, c: Vector2i, sign: String) -> void:
	## One sign into its layer (a space erases: the object first, unless the layer says otherwise).
	if not inside(c) or deck < 0 or deck >= decks.size():
		return
	var i := c.y * width + c.x
	var top: String = (decks[deck]["cells"] as PackedStringArray)[i]
	var under: String = (decks[deck]["base"] as PackedStringArray)[i]
	var has_object := is_object(top)
	if sign == " ":
		if has_object and layer != LAYER_FLOOR:
			_layers(deck, i, under, under)
		elif layer != LAYER_OBJECTS:
			_layers(deck, i, top if has_object else " ", " ")
	elif is_object(sign):
		if layer != LAYER_FLOOR:
			_layers(deck, i, sign, under if under != " " else base_for(sign))
	elif layer != LAYER_OBJECTS:
		_layers(deck, i, top if has_object else sign, sign)


func _layers(deck: int, i: int, top: String, under: String) -> void:
	var cells: PackedStringArray = decks[deck]["cells"]
	var base: PackedStringArray = decks[deck]["base"]
	if cells[i] == top and base[i] == under:
		return
	_touch()
	cells[i] = top
	base[i] = under


static func _flip_x(sign: String) -> String:
	return {"<": ">", ">": "<"}.get(sign, sign)


func paint(deck: int, c: Vector2i, sign: String) -> void:
	## One cell, and its mirror images while mirroring is on.
	_put_sign(deck, c, sign)
	var mx := Vector2i(width - 1 - c.x, c.y)
	var my := Vector2i(c.x, height - 1 - c.y)
	if mirror_x:
		_put_sign(deck, mx, _flip_x(sign))
	if mirror_y:
		_put_sign(deck, my, sign)
	if mirror_x and mirror_y:
		_put_sign(deck, Vector2i(mx.x, my.y), _flip_x(sign))


func line(deck: int, a: Vector2i, b: Vector2i, sign: String) -> void:
	for c in line_cells(a, b):
		paint(deck, c, sign)


static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	## The cells of a straight line (Bresenham), both ends included.
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var s := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var err := d.x - d.y
	var c := a
	while true:
		out.append(c)
		if c == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			c.x += s.x
		if e2 < d.x:
			err += d.x
			c.y += s.y
	return out


func rect(deck: int, r: Rect2i, sign: String, filled: bool) -> void:
	r = r.abs()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if filled or x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1:
				paint(deck, Vector2i(x, y), sign)


func room(deck: int, r: Rect2i) -> void:
	## Walls round, floor inside; walls already there stay walls (rooms side by side share them).
	r = r.abs()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			var c := Vector2i(x, y)
			if edge:
				if MapBuilder.BAND_CHARS.find(at(deck, c)) < 0 and at(deck, c) != "A":
					paint(deck, c, "#")
			else:
				paint(deck, c, ".")


func fill(deck: int, start: Vector2i, sign: String) -> void:
	## Every cell joined to that one (sideways or up and down) holding the same sign. A floor sign
	## fills by the floor layer, so the objects standing on it stay and do not stop it.
	var by_base := not is_object(sign) and layer != LAYER_OBJECTS
	var look := base_at if by_base else at
	var was: String = look.call(deck, start)
	if not inside(start) or was == sign:
		return
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		paint(deck, c, sign)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if inside(n) and not seen.has(n) and look.call(deck, n) == was:
				seen[n] = true
				todo.append(n)


func copy(deck: int, r: Rect2i) -> Dictionary:
	r = r.abs().intersection(Rect2i(0, 0, width, height))
	var cells := PackedStringArray()
	var base := PackedStringArray()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var top := at(deck, Vector2i(x, y))
			var under := base_at(deck, Vector2i(x, y))
			# what the layer choice leaves out is not copied
			cells.append(under if layer == LAYER_FLOOR else (top if is_object(top) or layer != LAYER_OBJECTS else " "))
			base.append(" " if layer == LAYER_OBJECTS else under)
	return {"w": r.size.x, "h": r.size.y, "cells": cells, "base": base}


func clear(deck: int, r: Rect2i) -> void:
	## Wipes a box: both layers, or only the one chosen.
	r = r.abs()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if inside(c):
				var i := c.y * width + c.x
				var top := at(deck, c)
				var under := base_at(deck, c)
				match layer:
					LAYER_FLOOR: _layers(deck, i, top if is_object(top) else " ", " ")
					LAYER_OBJECTS: _layers(deck, i, under, under)
					_: _layers(deck, i, " ", " ")


func paste(deck: int, corner: Vector2i, clip: Dictionary) -> void:
	## Lays a copy down with its top-left corner there. Its empty cells leave what is under them.
	var cells: PackedStringArray = clip.get("cells", PackedStringArray())
	var base: PackedStringArray = clip.get("base", cells)
	for y in int(clip.get("h", 0)):
		for x in int(clip.get("w", 0)):
			var k := y * int(clip["w"]) + x
			if base[k] != " ":
				_put_sign(deck, corner + Vector2i(x, y), base[k])
			if is_object(cells[k]):
				_put_sign(deck, corner + Vector2i(x, y), cells[k])


static func flip_clip(clip: Dictionary, across: bool) -> Dictionary:
	## A copy turned over left-right (across) or up-down.
	var w := int(clip["w"])
	var h := int(clip["h"])
	var out := {"w": w, "h": h}
	for key in ["cells", "base"]:
		var src: PackedStringArray = clip.get(key, clip["cells"])
		var turned := PackedStringArray()
		for y in h:
			for x in w:
				var s := src[y * w + (w - 1 - x)] if across else src[(h - 1 - y) * w + x]
				turned.append(_flip_x(s) if across else s)
		out[key] = turned
	return out


# ---------------------------------------------------------------- size and decks

func resize(w: int, h: int, shift := Vector2i.ZERO) -> void:
	## A new canvas size; the drawing (and its marks) moves by `shift` on it.
	w = clampi(w, 4, MAX_SIZE)
	h = clampi(h, 3, MAX_SIZE)
	if w == width and h == height and shift == Vector2i.ZERO:
		return
	_touch()
	for deck: Dictionary in decks:
		for key in ["cells", "base"]:
			var old: PackedStringArray = deck[key]
			var cells := PackedStringArray()
			cells.resize(w * h)
			cells.fill(" ")
			for y in height:
				for x in width:
					var n := Vector2i(x, y) + shift
					if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
						cells[n.y * w + n.x] = old[y * width + x]
			deck[key] = cells
	width = w
	height = h
	var kept := []
	for m: Dictionary in marks:
		var n := Vector2i(int(m["x"]), int(m["y"])) + shift
		if inside(n):
			m["x"] = n.x
			m["y"] = n.y
			kept.append(m)
	marks = kept


func add_deck() -> void:
	_touch()
	decks.append({"name": _deck_name(decks.size()), "cells": _blank(), "base": _blank()})


func remove_deck(i: int) -> void:
	if decks.size() <= 1 or i < 0 or i >= decks.size():
		return
	_touch()
	decks.remove_at(i)
	var kept := []
	for m: Dictionary in marks:
		if int(m["deck"]) == i:
			continue
		if int(m["deck"]) > i:
			m["deck"] = int(m["deck"]) - 1
		kept.append(m)
	marks = kept


func move_deck(i: int, by: int) -> void:
	var j := i + by
	if i < 0 or j < 0 or i >= decks.size() or j >= decks.size():
		return
	_touch()
	var d = decks[i]
	decks[i] = decks[j]
	decks[j] = d
	for m: Dictionary in marks:
		if int(m["deck"]) == i:
			m["deck"] = j
		elif int(m["deck"]) == j:
			m["deck"] = i


func rename_deck(i: int, name: String) -> void:
	if i >= 0 and i < decks.size() and name.strip_edges() != "" and decks[i]["name"] != name.strip_edges():
		_touch()
		decks[i]["name"] = name.strip_edges()


func set_kind(k: String) -> void:
	if k != kind and MapBuilder.KINDS.has(k):
		_touch()
		kind = k


func mark_at(deck: int, c: Vector2i, type: String) -> int:
	## The number of the mark of that type ("@" or "%") on that very cell, or -1.
	for i in marks.size():
		var m: Dictionary = marks[i]
		if str(m["type"]) == type and int(m["deck"]) == deck and int(m["x"]) == c.x and int(m["y"]) == c.y:
			return i
	return -1


func set_mark(deck: int, c: Vector2i, type: String, what: String) -> void:
	## Puts a mark on a room's floor cell; the room's mark of that type is replaced, "" takes it away.
	## `room` is every floor cell of the room (the editor finds it), to find a mark already there.
	_touch()
	var i := mark_at(deck, c, type)
	if i >= 0:
		marks.remove_at(i)
	if what != "":
		marks.append({"type": type, "deck": deck, "x": c.x, "y": c.y, "what": what})


func remove_marks_in(deck: int, cells: Array, type: String) -> void:
	var kept := []
	for m: Dictionary in marks:
		if str(m["type"]) == type and int(m["deck"]) == deck and cells.has(Vector2i(int(m["x"]), int(m["y"]))):
			_touch()
			continue
		kept.append(m)
	marks = kept


func room_cells(deck: int, c: Vector2i) -> Array:
	## The floor cells of the room that cell lies in (reached without passing a wall or a door).
	if MapBuilder.FLOOR_CHARS.find(at(deck, c)) < 0:
		return []
	var seen := {c: true}
	var todo: Array = [c]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if not seen.has(n) and MapBuilder.FLOOR_CHARS.find(at(deck, n)) >= 0 and inside(n):
				seen[n] = true
				todo.append(n)
	return seen.keys()


# ---------------------------------------------------------------- text form

func to_text() -> String:
	## The drawing as a ships/*.txt file: the same form as the game's maps/*.txt.
	var lines := PackedStringArray()
	lines.append("; Нарисовано в редакторе кораблей Spacer. Знаки описаны в tools/make_assets.py.")
	lines.append("; kind = %s" % kind)
	lines.append("; size = %d %d" % [width, height])
	for m: Dictionary in marks:
		lines.append("%s %d %d %d %s" % [m["type"], int(m["deck"]) + 1, int(m["x"]), int(m["y"]), m["what"]])
	for deck: Dictionary in decks:
		lines.append("= " + str(deck["name"]))
		var cells: PackedStringArray = deck["cells"]
		var rows := PackedStringArray()
		for y in height:
			rows.append("".join(cells.slice(y * width, (y + 1) * width)).rstrip(" "))
		while not rows.is_empty() and rows[-1] == "":
			rows.remove_at(rows.size() - 1)
		if rows.is_empty():
			rows.append(" ")         # an empty deck still keeps its place
		lines.append_array(rows)
	return "\n".join(lines) + "\n"


func from_text(text: String, name: String = "") -> void:
	## Opens a drawing (a ships/*.txt of one's own, or one of the game's maps/*.txt).
	## (v91, the author's G3) Machines drawn into a wall before are opened standing on the floor in front of it.
	var parts := MapBuilder.read(MapBuilder.to_floor(text))
	kind = MapBuilder.kind_of(name, text)
	var w := 4
	var h := 3
	for deck: Array in parts["decks"]:
		h = maxi(h, (deck[1] as PackedStringArray).size())
		for r: String in deck[1]:
			w = maxi(w, r.length())
	for l in text.split("\n"):
		var s := l.strip_edges()
		if s.begins_with(";") and s.substr(1).strip_edges().begins_with("size"):
			var bits := s.substr(1).strip_edges().trim_prefix("size").replace("=", " ").split(" ", false)
			if bits.size() == 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
				w = maxi(w, int(bits[0]))
				h = maxi(h, int(bits[1]))
	width = clampi(w, 4, MAX_SIZE)
	height = clampi(h, 3, MAX_SIZE)
	decks = []
	for deck: Array in parts["decks"]:
		var cells := _blank()
		var base := _blank()
		var rows: PackedStringArray = deck[1]
		var standing := MapBuilder.things_of(MapBuilder._grid(rows, width, height), width, height)
		for y in mini(rows.size(), height):
			for x in mini(rows[y].length(), width):
				cells[y * width + x] = rows[y][x]
				base[y * width + x] = ("." if standing.has(Vector2i(x, y)) else base_for(rows[y][x])) if is_object(rows[y][x]) else rows[y][x]
		decks.append({"name": deck[0], "cells": cells, "base": base})
	if decks.is_empty():
		decks.append({"name": _deck_name(0), "cells": _blank(), "base": _blank()})
	marks = []
	for l: String in parts["marks"]:
		var bits := l.substr(1).split(" ", false)
		if bits.size() == 4 and bits[0].is_valid_int() and bits[1].is_valid_int() and bits[2].is_valid_int():
			marks.append({"type": l[0], "deck": int(bits[0]) - 1, "x": int(bits[1]), "y": int(bits[2]), "what": bits[3]})
	_undo.clear()
	_redo.clear()
	_before = {}
	changes += 1
