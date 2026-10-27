extends RefCounted
## (v81) Turns a ship's drawing (the text form of maps/*.txt) into the layout the game reads, the
## same as tools/make_assets.py does for the game's own maps: every wall cell gets the piece that
## fits its neighbours. The ship editor and ships of one's own («ships» folder) use it in the game
## itself. tools/edittest.gd checks it gives exactly what the script gave for every map in maps/.
##
## (v81, the author: "more than 2 tiles") A room is two tiles tall or more: its middle rows take the
## floor_*_m pieces.
##
## Unlike the script it never stops at the first mistake: it lists every problem with its cell
## (in Russian, for the editor's panel) and still picks a piece for every cell, so a drawing with
## mistakes can be drawn as it is. The game loads a drawing only without problems.

const ACCESS_BITS := {"bridge": 1, "engine": 2, "medbay": 4, "armory": 8, "guns": 16}   # as Net.ACCESS_*
const SYSTEMS := ["weapons", "helm", "engine", "crew", "jump", "shields"]              # as Net.ESYS_*
const BAND_CHARS := "#DW<>123456789TIMZBUYXSQKPCGFV"
const FLOOR_CHARS := ".sgcH"
const ROCK_CHARS := "RO,"
const COVER_OF := {"g": "glass", "c": "grate"}
const SPECIAL := {"D": "door_open", "W": "window", "<": "window_l", ">": "window_r",
	"1": "console_1", "2": "console_2", "3": "console_3", "4": "console_4", "5": "console_5", "6": "engine",
	"7": "air_plant", "8": "locker", "9": "lock_pump", "T": "gun", "I": "intercom", "M": "holo", "Z": "shield",
	"B": "bench", "U": "bay", "Y": "autodoc", "X": "scanner", "S": "smes", "Q": "smes_small", "K": "comms",
	"P": "tray", "C": "cryo", "G": "stove", "F": "window_field", "V": "dock"}
const KINDS := ["ship", "pirate", "derelict", "asteroid"]
## (v91, the author: "it's not walls, it's on the ground") Machines stand on the floor. A machine sign is in the
## wall only in a row of machines between two pieces of wall with nothing solid above or below it (the old way);
## anywhere else it is a thing on the floor, the floor going on under it. Old drawings move their machines out
## of the wall onto the floor in front of them (to_floor), where there is room.
const MACHINE_SIGNS := "1345678MZBUYXSQKGCP"

static var _tiles := {}              # tile name -> id (from assets/tiles.json)
static var _kinds := PackedStringArray()


static func tile_ids() -> Dictionary:
	if _tiles.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles.json"))
		if typeof(data) == TYPE_DICTIONARY:
			for t: Dictionary in data["tiles"]:
				_tiles[str(t["name"])] = _kinds.size()
				_kinds.append(str(t["kind"]))
	return _tiles


static func tile_kind(id: int) -> String:
	tile_ids()
	return _kinds[id] if id >= 0 and id < _kinds.size() else ""


static func kind_of(name: String, text: String) -> String:
	## What the drawing is: its "; kind = ..." line, else its name (pirate*, derelict*, asteroid*, else ours).
	for l in text.split("\n"):
		var s := l.strip_edges()
		if s.begins_with(";") and s.substr(1).strip_edges().begins_with("kind"):
			var v := s.substr(1).strip_edges().trim_prefix("kind").strip_edges().trim_prefix("=").strip_edges()
			if KINDS.has(v):
				return v
	var base := name.get_file()
	for k: String in ["pirate", "derelict", "asteroid"]:
		if base.begins_with(k):
			return k
	return "ship"


static func read(text: String) -> Dictionary:
	## The drawing split up: {"decks": [[name, rows]], "marks": ["@ ..." and "% ..." lines]}.
	## Rows keep their spaces; a deck's empty rows at the bottom are dropped (as the script does).
	var decks := []
	var marks := PackedStringArray()
	for raw in text.replace("\r", "").split("\n"):
		var l: String = raw
		if l.begins_with(";"):
			continue
		if l.begins_with("@") or l.begins_with("%"):
			marks.append(l)
			continue
		if l.begins_with("="):
			var n := l.substr(1).strip_edges()
			decks.append([n if n != "" else "Палуба %d" % (decks.size() + 1), PackedStringArray()])
		elif not decks.is_empty():
			var rows: PackedStringArray = decks[-1][1]
			rows.append(l)
			decks[-1][1] = rows              # (a packed array is a copy: put it back)
		elif l.strip_edges() != "":
			decks.append(["Палуба", PackedStringArray([l])])
	for d: Array in decks:
		var rows: PackedStringArray = d[1]
		while not rows.is_empty() and rows[-1].strip_edges() == "":
			rows.remove_at(rows.size() - 1)
		d[1] = rows
	return {"decks": decks, "marks": marks}


static func fleet_text(texts: Array, gap: int = 4) -> Dictionary:
	## (v85, the author's FS1) Our fleet as one drawing: each ship's decks laid below the one before, `gap` empty
	## rows apart. (v86) Each keeps its own empty rows on top, where ships come alongside it (v85 dropped a later
	## ship's, so nothing could come alongside it). Its marks move with it. {"text", "rows": the row of each deck where each ship starts}.
	var parts: Array = []
	var decks := 0
	for t: String in texts:
		var part := read(t)
		parts.append(part)
		decks = maxi(decks, (part["decks"] as Array).size())
	var lines: Array = []
	for d in decks:
		lines.append(PackedStringArray())
	var names := PackedStringArray()
	var marks := PackedStringArray()
	var rows := PackedInt32Array()
	var at := 0
	for k in parts.size():
		var ship_decks: Array = parts[k]["decks"]
		var tall := 0
		var top := 1 << 20
		for sd: Array in ship_decks:
			var r: PackedStringArray = sd[1]
			tall = maxi(tall, r.size())
			var empty := 0
			while empty < r.size() and r[empty].strip_edges() == "":
				empty += 1
			top = mini(top, empty)
		top = 0                          # (v86, the author's note) every ship keeps its own: pirates come alongside each
		if k > 0:
			at += gap
		rows.append(at)
		for d in decks:
			var r := PackedStringArray()
			if d < ship_decks.size():
				r = ship_decks[d][1]
				if names.size() <= d:
					names.append(str(ship_decks[d][0]))
			var mine: PackedStringArray = lines[d]
			while mine.size() < at:
				mine.append("")
			for y in range(top, tall):
				mine.append(r[y] if y < r.size() else "")
			lines[d] = mine
		for m: String in parts[k]["marks"]:
			var bits := m.substr(1).split(" ", false)
			if bits.size() == 4 and bits[2].is_valid_int():
				bits[2] = str(int(bits[2]) - top + at)
			marks.append(m.substr(0, 1) + " " + " ".join(bits))
		at += tall - top
	var out := PackedStringArray(["; kind = ship"])
	out.append_array(marks)
	for d in decks:
		out.append("= " + (names[d] if d < names.size() else "Палуба %d" % (d + 1)))
		out.append_array(lines[d])
	return {"text": "\n".join(out), "rows": rows}


static func build(name: String, text: String) -> Dictionary:
	## {"data": the layout as maps/*.json holds it, "problems": [{"deck", "x", "y", "text"}], "kind"}.
	## deck -1 is a problem of the whole ship.
	var ids := tile_ids()
	var kind := kind_of(name, text)
	if kind == "pirate":
		var tinted := {}
		for k: String in ids.keys():
			tinted[k] = ids.get("pirate_" + k, ids[k])
		ids = tinted
	var problems := []
	var parts := read(to_floor(text))
	var decks: Array = parts["decks"]
	if decks.is_empty():
		problems.append(_problem(-1, 0, 0, "Нет ни одной палубы."))
		decks = [["Палуба", PackedStringArray([" "])]]
	# (v81) a deck not drawn yet at the bottom (the editor's new ship) is simply left out
	while decks.size() > 1 and (decks[-1][1] as PackedStringArray).is_empty():
		decks.pop_back()
	var w := 1
	var h := 1
	for d: Array in decks:
		var rows: PackedStringArray = d[1]
		if rows.is_empty():
			problems.append(_problem(decks.find(d), 0, 0, "Палуба «%s» пустая." % d[0]))
		h = maxi(h, rows.size())
		for r in rows:
			w = maxi(w, r.length())
	var stride := ((h + 1 + 15) / 16) * 16
	var total := stride * (decks.size() - 1) + h
	var cells := PackedInt32Array()
	cells.resize(w * total)
	cells.fill(-1)
	var spawns := []
	var doors := []
	var things := []
	var grids := []
	for d in decks.size():
		grids.append(_grid(decks[d][1], w, h))
	for d in decks.size():
		var above: Array = grids[d - 1] if d > 0 else []
		var below: Array = grids[d + 1] if d + 1 < decks.size() else []
		var out := _deck(grids[d], above, below, w, h, ids, d, problems)
		var deck_cells: PackedInt32Array = out[0]
		for i in deck_cells.size():
			cells[d * stride * w + i] = deck_cells[i]
		for s: Array in out[1]:
			spawns.append([s[0], s[1] + d * stride])
		for o: Array in out[2]:
			doors.append([o[0], o[1] + d * stride, o[2]])
		for t: Array in out[3]:
			things.append([t[0], t[1] + d * stride, t[2]])
	if spawns.is_empty() and kind == "ship":
		problems.append(_problem(-1, 0, 0, "Нет мест появления экипажа (пол «s»)."))
	var door_access := []
	door_access.resize(doors.size())
	door_access.fill(0)
	var access_rooms := []
	var brig_rooms := []
	var zones := []
	for l: String in parts["marks"]:
		var bits := l.substr(1).split(" ", false)
		var system := l.begins_with("%")
		var what := bits[3] if bits.size() == 4 else ""
		var ok := bits.size() == 4 and bits[0].is_valid_int() and bits[1].is_valid_int() and bits[2].is_valid_int() \
			and (SYSTEMS.has(what) if system else (ACCESS_BITS.has(what) or what == "brig"))
		var d := int(bits[0]) - 1 if ok else -1
		if not ok or d < 0 or d >= decks.size():
			problems.append(_problem(-1, 0, 0, "Неверная строка «%s»." % l))
			continue
		var x0 := int(bits[1])
		var y0 := int(bits[2])
		var g: Array = grids[d]
		if FLOOR_CHARS.find(_at(g, x0, y0, w, h)) < 0:
			problems.append(_problem(d, x0, y0, "Метка «%s» стоит не на полу." % _mark_name(what)))
			continue
		if not system and what == "brig":
			brig_rooms.append([x0, y0 + d * stride])
			continue
		if not system:
			access_rooms.append([x0, y0 + d * stride, ACCESS_BITS[what]])
		# the room: floor reached without passing a wall or a door
		var seen := {Vector2i(x0, y0): true}
		var todo := [Vector2i(x0, y0)]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := c + step
				var ch := _at(g, n.x, n.y, w, h)
				if FLOOR_CHARS.find(ch) >= 0 and ch != "" and not seen.has(n):
					seen[n] = true
					todo.append(n)
				elif not system and (ch == "D" or ch == "A"):
					for k in doors.size():
						if int(doors[k][0]) == n.x and int(doors[k][1]) == n.y + d * stride:
							door_access[k] = int(door_access[k]) | int(ACCESS_BITS[what])
		if system:
			var zone := []
			for c: Vector2i in seen.keys():
				zone.append((c.y + d * stride) * w + c.x)
			zone.sort()
			zones.append([SYSTEMS.find(what), zone])
	var names := []
	for d: Array in decks:
		names.append(d[0])
	var data := {"name": name, "width": w, "height": total, "deck_height": h, "deck_stride": stride,
		"decks": names, "cells": Array(cells), "spawns": spawns, "doors": doors,
		"door_access": door_access, "access_rooms": access_rooms, "brig_rooms": brig_rooms, "zones": zones,
		"things": things}
	return {"data": data, "problems": problems, "kind": kind}


static func _mark_name(what: String) -> String:
	return {"bridge": "мостик", "engine": "машинное", "medbay": "медотсек", "armory": "оружейная", "guns": "орудия",
		"brig": "камера", "weapons": "оружие", "helm": "управление", "crew": "каюты", "jump": "прыжковый двигатель",
		"shields": "щиты"}.get(what, what)


static func _problem(deck: int, x: int, y: int, text: String) -> Dictionary:
	return {"deck": deck, "x": x, "y": y, "text": text}


static func _grid(rows: PackedStringArray, w: int, h: int) -> Array:
	var g := []
	for y in h:
		g.append(rows[y].rpad(w) if y < rows.size() else " ".repeat(w))
	return g


static func _at(g: Array, x: int, y: int, w: int, h: int) -> String:
	if g.is_empty() or x < 0 or y < 0 or x >= w or y >= h or y >= g.size():
		return " "
	var row: String = g[y]
	return row[x] if x < row.length() else " "


static func _raw_solid(g: Array, x: int, y: int, w: int, h: int) -> bool:
	var c := _at(g, x, y, w, h)
	return BAND_CHARS.find(c) >= 0 or c == "A"


static func _solid(g: Array, x: int, y: int, w: int, h: int, things: Dictionary = {}) -> bool:
	return _raw_solid(g, x, y, w, h) and not things.has(Vector2i(x, y))


static func _floor_at(g: Array, x: int, y: int, w: int, h: int, things: Dictionary) -> bool:
	return _floor(_at(g, x, y, w, h)) or things.has(Vector2i(x, y))


static func _wall_end(c: String) -> bool:
	return (BAND_CHARS.find(c) >= 0 or c == "A") and MACHINE_SIGNS.find(c) < 0


static func things_of(g: Array, w: int, h: int) -> Dictionary:
	## (v91) The cells of a deck's drawing where a machine stands on the floor.
	var things := {}
	for y in h:
		var x := 0
		while x < w:
			if MACHINE_SIGNS.find(_at(g, x, y, w, h)) < 0:
				x += 1
				continue
			var x1 := x
			while MACHINE_SIGNS.find(_at(g, x1 + 1, y, w, h)) >= 0:
				x1 += 1
			var in_wall := _wall_end(_at(g, x - 1, y, w, h)) and _wall_end(_at(g, x1 + 1, y, w, h))
			for i in range(x, x1 + 1):
				if _raw_solid(g, i, y - 1, w, h) or _raw_solid(g, i, y + 1, w, h):
					in_wall = false
			if not in_wall:
				for i in range(x, x1 + 1):
					things[Vector2i(i, y)] = true
			x = x1 + 1
	return things


static func to_floor(text: String) -> String:
	## (v91, the author's G3) A drawing with its machines moved out of the walls onto the floor in front of
	## them: each row of machines in a wall goes one cell into the room below it (or, failing that, above),
	## where that is plain floor ("."), no mark points, no doorway is blocked and no part of the deck is cut
	## off. Rows that have no such room stay in the wall. Lines other than the decks' are kept as they are.
	var lines := text.replace("\r", "").split("\n")
	var avoid := {}                      # deck -> {Vector2i: true}: the cells marks point at
	for l: String in lines:
		if l.begins_with("@") or l.begins_with("%"):
			var bits := l.substr(1).split(" ", false)
			if bits.size() == 4 and bits[0].is_valid_int() and bits[1].is_valid_int() and bits[2].is_valid_int():
				var d := int(bits[0]) - 1
				if not avoid.has(d):
					avoid[d] = {}
				avoid[d][Vector2i(int(bits[1]), int(bits[2]))] = true
	var deck := -1
	var start := -1                      # the line index of the deck's first row
	var spans := []                      # [deck, first line, line after the last]
	for i in lines.size():
		var l: String = lines[i]
		if l.begins_with("="):
			if deck >= 0:
				spans.append([deck, start, i])
			deck += 1
			start = i + 1
		elif deck < 0 and not l.begins_with(";") and not l.begins_with("@") and not l.begins_with("%") and l.strip_edges() != "":
			deck = 0
			start = i
	if deck >= 0:
		spans.append([deck, start, lines.size()])
	for span: Array in spans:
		var rows := PackedStringArray()
		var w := 1
		for i in range(span[1], span[2]):
			if lines[i].begins_with(";") or lines[i].begins_with("@") or lines[i].begins_with("%"):
				continue
			rows.append(lines[i])
			w = maxi(w, lines[i].length())
		var h := rows.size()
		var g := _grid(rows, w, h)
		var moved := _move_out(g, w, h, avoid.get(span[0], {}))
		if not moved:
			continue
		var k := 0
		for i in range(span[1], span[2]):
			if lines[i].begins_with(";") or lines[i].begins_with("@") or lines[i].begins_with("%"):
				continue
			lines[i] = (g[k] as String).rstrip(" ")
			k += 1
	return "\n".join(lines)


static func _move_out(g: Array, w: int, h: int, avoid: Dictionary) -> bool:
	var moved := false
	var parts := _parts(g, w, h)
	for y in h:
		var x := 0
		while x < w:
			if MACHINE_SIGNS.find(_at(g, x, y, w, h)) < 0:
				x += 1
				continue
			var x1 := x
			while MACHINE_SIGNS.find(_at(g, x1 + 1, y, w, h)) >= 0:
				x1 += 1
			var run_end := x1 + 1
			if things_of(g, w, h).has(Vector2i(x, y)):
				x = run_end
				continue
			for dy: int in [1, -1]:
				var ty := y + dy
				var ok := ty >= 0 and ty < h
				for i in range(x, x1 + 1):
					if not ok:
						break
					var beyond := _at(g, i, ty + dy, w, h)
					ok = _at(g, i, ty, w, h) == "." and not avoid.has(Vector2i(i, ty)) and beyond != "D"
				if ok and (_at(g, x - 1, ty, w, h) == "A" or _at(g, x1 + 1, ty, w, h) == "A"):
					ok = false
				if not ok:
					continue
				var before := g.duplicate()
				var row: String = g[y]
				var to: String = g[ty]
				for i in range(x, x1 + 1):
					to = to.substr(0, i) + row[i] + to.substr(i + 1)
					row = row.substr(0, i) + "#" + row.substr(i + 1)
				g[y] = row
				g[ty] = to
				if _parts(g, w, h) > parts:
					for r in h:
						g[r] = before[r]
					continue
				moved = true
				break
			x = run_end
	return moved


static func _parts(g: Array, w: int, h: int) -> int:
	## How many pieces a deck's walkable cells (floor and doorways) fall into.
	var seen := {}
	var count := 0
	for y in h:
		for x in w:
			var c := _at(g, x, y, w, h)
			if seen.has(Vector2i(x, y)) or not (_floor(c) or c == "D" or c == "A"):
				continue
			count += 1
			var todo := [Vector2i(x, y)]
			seen[Vector2i(x, y)] = true
			while not todo.is_empty():
				var p: Vector2i = todo.pop_back()
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := p + step
					var nc := _at(g, n.x, n.y, w, h)
					if not seen.has(n) and (_floor(nc) or nc == "D" or nc == "A"):
						seen[n] = true
						todo.append(n)
	return count


static func _floor(c: String) -> bool:
	return FLOOR_CHARS.find(c) >= 0


static func _deck(g: Array, above: Array, below: Array, w: int, h: int, ids: Dictionary, deck: int, problems: Array) -> Array:
	## One deck: [cells, spawns, doors]. `above` and `below` are the decks next to it (or empty).
	var cells := PackedInt32Array()
	cells.resize(w * h)
	cells.fill(-1)
	var spawns := []
	var doors := []
	var under := []
	var things := things_of(g, w, h)
	for y in h:
		for x in w:
			var c := _at(g, x, y, w, h)
			if c == " ":
				continue
			var n := _solid(g, x, y - 1, w, h, things)
			var s := _solid(g, x, y + 1, w, h, things)
			var e := _solid(g, x + 1, y, w, h, things)
			var wst := _solid(g, x - 1, y, w, h, things)
			var piece := ""
			var thing := things.has(Vector2i(x, y))
			if _floor(c) or thing:
				if c == "s":
					spawns.append([x, y])
				var left := _floor_at(g, x - 1, y, w, h, things)
				var right := _floor_at(g, x + 1, y, w, h, things)
				var top := not _floor_at(g, x, y - 1, w, h, things)
				var bottom := not _floor_at(g, x, y + 1, w, h, things)
				if top and bottom:
					problems.append(_problem(deck, x, y, "Комната в одну клетку высотой: нужно две или больше."))
				var row := "t" if top else ("b" if bottom else "m")   # (the author: rooms taller than two)
				if not left and not right:
					piece = "floor_n"
				else:
					piece = "floor_%s_%s" % ["l" if not left else ("r" if not right else "m"), row]
				var cover: String = COVER_OF.get(c, "")
				if c == "c" and not _floor(_at(below, x, y, w, h)):
					problems.append(_problem(deck, x, y, "Под мостками нет пола на палубе ниже (воздуху некуда идти)."))
				if c == "H":
					var down := _at(below, x, y, w, h) == "H"
					var up := _at(above, x, y, w, h) == "H"
					if not down and not up:
						problems.append(_problem(deck, x, y, "Лестнице нужна «H» в той же клетке палубы выше или ниже."))
					cover = "hatch" if down else "ladder"
				if cover != "":
					piece = cover + piece.substr(5)
				if thing:
					var reach := false
					for v: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
						reach = reach or _floor(_at(g, x + v.x, y + v.y, w, h))
					if not reach:
						problems.append(_problem(deck, x, y, "Машине нужен пол рядом: оттуда ею пользуются."))
					if _at(g, x, y - 1, w, h) == "D" or _at(g, x, y + 1, w, h) == "D" or _at(g, x - 1, y, w, h) == "A" or _at(g, x + 1, y, w, h) == "A":
						problems.append(_problem(deck, x, y, "Машина загораживает дверь."))
					under.append([x, y, int(ids.get(piece, -1))])
					piece = SPECIAL[c]
			elif ROCK_CHARS.find(c) >= 0:
				piece = {"R": "rock_%d" % ((x * 7 + y * 13) % 3 + 1), "O": "rock_ore", ",": "rock_ground"}[c]
			elif c == "A":
				if not (n and s) or e or wst:
					problems.append(_problem(deck, x, y, "Шлюз должен стоять в вертикальной стене."))
				if _at(g, x, y - 1, w, h) == "A" or _at(g, x, y + 1, w, h) == "A":
					problems.append(_problem(deck, x, y, "Шлюз касается другого шлюза."))
				piece = "airlock"
				doors.append([x, y, "A"])
			elif BAND_CHARS.find(c) >= 0:
				var horizontal := e or wst
				if not horizontal:
					if c == "W" and n and s:
						piece = "window_v"       # (v91, the author's W3) a window in a side wall
					elif c != "#":
						problems.append(_problem(deck, x, y, "«%s» должна стоять в горизонтальной стене." % _what(c)))
						piece = SPECIAL.get(c, "wall_v")
					elif not n or not s:
						problems.append(_problem(deck, x, y, "Одинокий кусок стены."))
						piece = "wall_v"
					else:
						var below_is_band := _solid(g, x - 1, y + 1, w, h, things) or _solid(g, x + 1, y + 1, w, h, things)
						if not below_is_band:
							piece = "wall_v"
						elif _at(g, x, y - 1, w, h) == "A":
							piece = "wall_v_end_a"
						elif not _solid(g, x - 1, y + 1, w, h, things):
							piece = "wall_v_end_l"
						elif not _solid(g, x + 1, y + 1, w, h, things):
							piece = "wall_v_end_r"
						else:
							piece = "wall_v_end"
				elif SPECIAL.has(c):
					if not (e and wst) or n or s:
						problems.append(_problem(deck, x, y, "«%s» нужна стена слева и справа и ничего сверху и снизу." % _what(c)))
					var up := _at(g, x, y - 1, w, h)
					var down := _at(g, x, y + 1, w, h)
					if c == "D" and not (_floor(up) and _floor(down) or _floor(up) and down == " " or up == " " and _floor(down)):
						problems.append(_problem(deck, x, y, "Двери нужен пол сверху и снизу (или космос с одной стороны)."))
					if c == "<" and _at(g, x + 1, y, w, h) != ">" or c == ">" and _at(g, x - 1, y, w, h) != "<":
						problems.append(_problem(deck, x, y, "Широкому окну нужны обе половины."))
					piece = SPECIAL[c]
					if c == "D":
						doors.append([x, y, "D"])
				elif e and wst:
					piece = "wall_cross" if (n and s) else ("wall_tdown" if s else ("wall_tup" if n else "wall_h"))
				elif e and not wst:
					if n and s:
						piece = "wall_jr"        # (v91) a vertical wall going on past a band that leaves it to the right
					elif n == s:
						problems.append(_problem(deck, x, y, "Конец стены без угла."))
						piece = "wall_h"
					else:
						piece = "wall_tl" if s else "wall_bl"
				else:
					if n and s:
						piece = "wall_jl"
					elif n == s:
						problems.append(_problem(deck, x, y, "Конец стены без угла."))
						piece = "wall_h"
					else:
						piece = "wall_tr" if s else "wall_br"
			else:
				problems.append(_problem(deck, x, y, "Неизвестный знак «%s»." % c))
				continue
			cells[y * w + x] = int(ids.get(piece, -1))
	return [cells, spawns, doors, under]


static func _what(c: String) -> String:
	## A piece's name for a problem's text.
	return {"D": "Дверь", "W": "Окно", "<": "Окно", ">": "Окно", "T": "Орудие"}.get(c, "Машина")
