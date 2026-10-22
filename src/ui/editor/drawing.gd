extends RefCounted
## (v81) What the ship editor draws: one grid of signs per deck (the signs of maps/*.txt, see
## tools/make_assets.py), the marks on rooms (locks, brig cells, a pirate ship's systems) and what
## kind of drawing it is. Every tool's change goes through here, so undo and redo see all of it:
## a stroke (everything between two `commit`s) is one step back.

const MapBuilder := preload("res://src/shared/map_builder.gd")

const MAX_SIZE := 96                 # the largest canvas, either way
const UNDO_STEPS := 200

var width := 40
var height := 12
var kind := "ship"                   # MapBuilder.KINDS
var decks: Array = []                # per deck {"name": String, "cells": PackedStringArray (width * height signs)}
var marks: Array = []                # {"type": "@" (a lock or a brig cell) or "%" (a system), "deck", "x", "y", "what"}
var mirror_x := false                # every stroke is drawn again mirrored left-right...
var mirror_y := false                # ... and up-down
var changes := 0                     # counts every change (the editor redraws and checks when it moves)

var _undo: Array = []
var _redo: Array = []
var _before: Dictionary = {}         # the drawing as it was when the stroke under way began (empty: none)


func reset(w: int, h: int, n_decks: int) -> void:
	width = clampi(w, 4, MAX_SIZE)
	height = clampi(h, 3, MAX_SIZE)
	decks = []
	for i in n_decks:
		decks.append({"name": _deck_name(i), "cells": _blank()})
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


# ---------------------------------------------------------------- changes

func _touch() -> void:
	## The first change of a stroke keeps the drawing as it was, for undo.
	if _before.is_empty():
		_before = _snapshot()
	changes += 1


func _snapshot() -> Dictionary:
	var d := []
	for deck: Dictionary in decks:
		d.append({"name": deck["name"], "cells": (deck["cells"] as PackedStringArray).duplicate()})
	return {"w": width, "h": height, "kind": kind, "decks": d, "marks": marks.duplicate(true)}


func _restore(s: Dictionary) -> void:
	width = s["w"]
	height = s["h"]
	kind = s["kind"]
	decks = []
	for deck: Dictionary in s["decks"]:
		decks.append({"name": deck["name"], "cells": (deck["cells"] as PackedStringArray).duplicate()})
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
	if not inside(c) or deck < 0 or deck >= decks.size():
		return
	var cells: PackedStringArray = decks[deck]["cells"]
	if cells[c.y * width + c.x] == sign:
		return
	_touch()
	cells[c.y * width + c.x] = sign


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
	## Every cell joined to that one (sideways or up and down) holding the same sign.
	var was := at(deck, start)
	if not inside(start) or was == sign:
		return
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		paint(deck, c, sign)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if inside(n) and not seen.has(n) and at(deck, n) == was:
				seen[n] = true
				todo.append(n)


func copy(deck: int, r: Rect2i) -> Dictionary:
	r = r.abs().intersection(Rect2i(0, 0, width, height))
	var cells := PackedStringArray()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			cells.append(at(deck, Vector2i(x, y)))
	return {"w": r.size.x, "h": r.size.y, "cells": cells}


func clear(deck: int, r: Rect2i) -> void:
	r = r.abs()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put_sign(deck, Vector2i(x, y), " ")


func paste(deck: int, corner: Vector2i, clip: Dictionary) -> void:
	## Lays a copy down with its top-left corner there. Its empty cells leave what is under them.
	var cells: PackedStringArray = clip.get("cells", PackedStringArray())
	for y in int(clip.get("h", 0)):
		for x in int(clip.get("w", 0)):
			var s := cells[y * int(clip["w"]) + x]
			if s != " ":
				_put_sign(deck, corner + Vector2i(x, y), s)


static func flip_clip(clip: Dictionary, across: bool) -> Dictionary:
	## A copy turned over left-right (across) or up-down.
	var w := int(clip["w"])
	var h := int(clip["h"])
	var src: PackedStringArray = clip["cells"]
	var out := PackedStringArray()
	for y in h:
		for x in w:
			var s := src[y * w + (w - 1 - x)] if across else src[(h - 1 - y) * w + x]
			out.append(_flip_x(s) if across else s)
	return {"w": w, "h": h, "cells": out}


# ---------------------------------------------------------------- size and decks

func resize(w: int, h: int, shift := Vector2i.ZERO) -> void:
	## A new canvas size; the drawing (and its marks) moves by `shift` on it.
	w = clampi(w, 4, MAX_SIZE)
	h = clampi(h, 3, MAX_SIZE)
	if w == width and h == height and shift == Vector2i.ZERO:
		return
	_touch()
	for deck: Dictionary in decks:
		var old: PackedStringArray = deck["cells"]
		var cells := PackedStringArray()
		cells.resize(w * h)
		cells.fill(" ")
		for y in height:
			for x in width:
				var n := Vector2i(x, y) + shift
				if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
					cells[n.y * w + n.x] = old[y * width + x]
		deck["cells"] = cells
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
	decks.append({"name": _deck_name(decks.size()), "cells": _blank()})


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
	var parts := MapBuilder.read(text)
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
		var rows: PackedStringArray = deck[1]
		for y in mini(rows.size(), height):
			for x in mini(rows[y].length(), width):
				cells[y * width + x] = rows[y][x]
		decks.append({"name": deck[0], "cells": cells})
	if decks.is_empty():
		decks.append({"name": _deck_name(0), "cells": _blank()})
	marks = []
	for l: String in parts["marks"]:
		var bits := l.substr(1).split(" ", false)
		if bits.size() == 4 and bits[0].is_valid_int() and bits[1].is_valid_int() and bits[2].is_valid_int():
			marks.append({"type": l[0], "deck": int(bits[0]) - 1, "x": int(bits[1]), "y": int(bits[2]), "what": bits[3]})
	_undo.clear()
	_redo.clear()
	_before = {}
	changes += 1
