extends RefCounted
## (v97, the author's roadmap item 1: "procedural abandoned stations and derelicts") Derelicts made from
## pieces. Every campaign makes COUNT of its own when it starts (Campaign keeps them in the save): the
## drawing's text, as one would draw it in the ship editor, so MapBuilder builds it like any other and the
## server sends it to guests as it does one's own drawings (ShipMap.MADE_PREFIX names).
##
## The shape (my P2 pick, his answers pending): one deck, HEIGHT rows, because a derelict lies over our
## airlock in the empty rows above the top deck (ship02 has 10; GAP and the docking row take the rest).
## A row of rooms two tall over a corridor two tall, the outer door at the bottom; now and then a tall
## room at one end, doors between rooms, windows, machines (dead, as on any derelict), and a vault: the
## room at the far end from the way in, with one welded door (his 1.1: "minibosses, unique things").
## Marks in comment lines tell the server what lives there: "; dwellers = N", "; vault = X Y" (the
## vault door's cell, counted in the drawing).

const MapBuilder := preload("res://src/shared/map_builder.gd")
const HEIGHT := 7                    # rows, walls included: what fits over ship02's airlock (as derelict01)
const COUNT := 8                     # (my P1 pick) the campaign's own derelicts
const ROOM_MIN := 3                  # a room's floor, cells across
const ROOM_MAX := 7
const DOOR_MAX_X := 10               # the outer door's column at most: ship02's airlock is at x 10
const MACHINES := "1345PC67"        # what stands about, dead (single machines: no wide ones)
const WING_SHARE := 0.4              # a tall room at one end
const VAULT_SHARE := 0.5             # (my V1 pick) of the made ones, the share with a vault
const DWELL_SHARE := 0.5             # (my I1 pick) the share with robots living aboard
# (v99, the author: "better derelict station generators", "asteroid generation"; my D1 and A1 picks)
const SHIPS := 4                     # of COUNT, the derelict ships; the rest are stations
const ROCKS := 8                     # the campaign's own asteroids
const ROCK_SIZES := [0, 0, 1, 1, 1, 2, 2, 2]   # small (solid), medium and large (caves)
const ROCK_W := [Vector2i(10, 14), Vector2i(18, 26), Vector2i(28, 38)]
const ROCK_H := [Vector2i(6, 8), Vector2i(10, 14), Vector2i(15, 20)]   # 20 at most: ship02's 24 empty rows less the gap
const RIGHT_MAX := 31                # cells right of the way in at most: ship02 is 41 wide, its airlock at 10
const NEST_SHARE := 0.5              # (my M6 pick) the share of caved asteroids mantises live in
const STATION_W := Vector2i(26, 38)
const ROOM_KINDS := ["жилой отсек", "склад", "медотсек", "машинный зал", "рубка", "лаборатория", "арсенал"]
const ROOM_MACHINES := ["CP", "8", "YX", "6S7", "13K", "5M4", "8"]   # what stands in each kind (dead)
const STATION_KINDS := ["станция", "станция связи", "рудная станция", "верфь", "исследовательская станция", "перевалочная база"]
const KINDS := ["транспорт", "рудовоз", "танкер", "лайнер", "буксир", "грузовик", "разведчик", "ковчег", "сборщик", "курьер"]
const NAMES := ["Вега", "Тамбов", "Сирин", "Полярник", "Каракум", "Ладога", "Бирюза", "Енисей", "Прометей", "Медуза",
	"Северянка", "Таймыр", "Орион", "Гончая", "Альтаир", "Иртыш", "Кассиопея", "Мираж", "Скиф", "Заря"]


static func make_set(seed_value: int) -> Dictionary:
	## COUNT drawings by name ("made:1"...): the same seed gives the same set. (v99) The first SHIPS are
	## derelict ships, the rest of COUNT abandoned stations, then ROCKS asteroids ("made:9"...).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {}
	var used := {}
	for i in COUNT:
		out["made:%d" % (i + 1)] = derelict(rng, used) if i < SHIPS else station(rng, used)
	for i in ROCKS:
		out["made:%d" % (COUNT + i + 1)] = asteroid(rng, ROCK_SIZES[i])
	return out


static func derelict(rng: RandomNumberGenerator, used: Dictionary = {}) -> String:
	## One derelict's drawing.
	var w := rng.randi_range(16, 30)
	var g: Array = []
	for y in HEIGHT:
		var row := PackedStringArray()
		row.resize(w)
		row.fill(" ")
		g.append(row)
	var put := func(x: int, y: int, c: String) -> void:
		var row: PackedStringArray = g[y]
		row[x] = c
		g[y] = row
	var at := func(x: int, y: int) -> String:
		return (g[y] as PackedStringArray)[x]
	# the tall room at one end, the body (rooms over the corridor) beside it
	var wing := 0
	var wing_left := rng.randf() < 0.5
	if rng.randf() < WING_SHARE:
		wing = rng.randi_range(ROOM_MIN, 5) + 1
	var body_l := wing if wing_left else 0        # the body's outer wall columns
	var body_r := w - 1 - (0 if wing_left else wing)
	if wing > 0:
		var wl := 0 if wing_left else body_r
		var wr := body_l if wing_left else w - 1
		for y in HEIGHT:
			for x in range(wl, wr + 1):
				put.call(x, y, "#" if y == 0 or y == HEIGHT - 1 or x == wl or x == wr else ".")
	# the corridor: rows 4-5, its walls rows 3 and 6
	for y in range(3, HEIGHT):
		for x in range(body_l, body_r + 1):
			put.call(x, y, "#" if y == 3 or y == HEIGHT - 1 or x == body_l or x == body_r else ".")
	# the rooms row: rows 1-2, its top wall row 0, set in by a cell at an end now and then (not by the wing)
	var in_l := body_l + (1 if wing == 0 or not wing_left else 0) * (1 if rng.randf() < 0.5 else 0)
	var in_r := body_r - (1 if wing == 0 or wing_left else 0) * (1 if rng.randf() < 0.5 else 0)
	for y in range(0, 3):
		for x in range(in_l, in_r + 1):
			put.call(x, y, "#" if y == 0 or x == in_l or x == in_r else ".")
	# the rooms' walls
	var rooms: Array = []                     # [left floor x, right floor x]
	var x0 := in_l + 1
	while x0 <= in_r - 1:
		var left := in_r - 1 - x0 + 1
		var span := rng.randi_range(ROOM_MIN, ROOM_MAX)
		if left - span < ROOM_MIN + 1:
			span = left                       # the last room takes what is left
		rooms.append([x0, x0 + span - 1])
		x0 += span
		if x0 <= in_r - 1:
			for y in range(1, 3):
				put.call(x0, y, "#")
			x0 += 1
	# the outer door: in the corridor's bottom wall, at most DOOR_MAX_X across
	var door_x := rng.randi_range(body_l + 2, mini(DOOR_MAX_X, body_r - 2))
	put.call(door_x, HEIGHT - 1, "D")
	# the vault: the end room farthest from the way in, wide enough for its keeper
	var vault := -1
	if rooms.size() >= 3 and rng.randf() < VAULT_SHARE:
		var first: Array = rooms[0]
		var last: Array = rooms[-1]
		vault = 0 if absi(int(first[0]) - door_x) > absi(int(last[1]) - door_x) else rooms.size() - 1
	var vault_door := Vector2i(-1, -1)
	for k in rooms.size():
		var r: Array = rooms[k]
		var a := int(r[0])
		var b := int(r[1])
		# its door into the corridor
		var dx := rng.randi_range(a, b)
		put.call(dx, 3, "D")
		if k == vault:
			vault_door = Vector2i(dx, 3)
		# a door to the next room now and then (never the vault's)
		if k + 1 < rooms.size() and k != vault and k + 1 != vault and rng.randf() < 0.35:
			put.call(b + 1, rng.randi_range(1, 2), "A")
		# a window
		if rng.randf() < 0.6:
			put.call(rng.randi_range(a, b), 0, "W")
	for r: Array in rooms:
		# machines against the top wall, dead (never by a door: it would block it)
		for m in rng.randi_range(0, 2):
			var mx := rng.randi_range(int(r[0]), int(r[1]))
			if at.call(mx, 1) == "." and at.call(mx - 1, 1) != "A" and at.call(mx + 1, 1) != "A":
				put.call(mx, 1, MACHINES[rng.randi_range(0, MACHINES.length() - 1)])
	if wing > 0:
		# the tall room's door into the corridor, and a window in its top wall
		var wall_x := body_l if wing_left else body_r
		put.call(wall_x, rng.randi_range(4, 5), "A")
		var wl := 1 if wing_left else body_r + 1
		var wr := body_l - 1 if wing_left else w - 2
		put.call(rng.randi_range(wl, wr), 0, "W")
		if rng.randf() < 0.6:
			put.call(rng.randi_range(wl, wr), 1, MACHINES[rng.randi_range(0, MACHINES.length() - 1)])
	var name := ""
	for tries in 20:
		name = "%s «%s»" % [KINDS[rng.randi_range(0, KINDS.size() - 1)], NAMES[rng.randi_range(0, NAMES.size() - 1)]]
		if not used.has(name):
			break
	used[name] = true
	var dwellers := 0
	if rng.randf() < DWELL_SHARE:
		dwellers = rng.randi_range(1, 3)
	var lines := PackedStringArray(["; (v97) a derelict made from pieces (PlaceMaker)", "; kind = derelict",
		"; dwellers = %d" % dwellers])
	if vault_door.x >= 0:
		lines.append("; vault = %d %d" % [vault_door.x, vault_door.y])
		lines.append("& 1 %d %d herm" % [vault_door.x, vault_door.y])
	lines.append("= Брошенный " + name)
	for row: PackedStringArray in g:
		lines.append("".join(row).rstrip(" "))
	return "\n".join(lines)


static func info(text: String) -> Dictionary:
	## What the marks of a made drawing say: {"dwellers": n, "vault": the vault door's cell or (-1, -1)};
	## (v99) "mouth": an asteroid's way into its caves (-1, -1: none), "mantises", "finds" there, and a station's
	## "rooms": [[floor cell, kind]] (cells counted in the drawing).
	var out := {"dwellers": 0, "vault": Vector2i(-1, -1), "made": false, "mouth": Vector2i(-1, -1), "mantises": 0, "finds": 0, "rooms": []}
	for l in text.split("\n"):
		var s := l.strip_edges()
		if not s.begins_with(";"):
			continue
		s = s.substr(1).strip_edges()
		if s.begins_with("(v97)") or s.begins_with("(v99)"):
			out["made"] = true
		elif s.begins_with("mouth") or s.begins_with("room"):
			var bits := s.get_slice("=", 1).strip_edges().split(" ", false)
			if bits.size() >= 2 and s.begins_with("mouth"):
				out["mouth"] = Vector2i(int(bits[0]), int(bits[1]))
			elif bits.size() >= 3:
				(out["rooms"] as Array).append([Vector2i(int(bits[0]), int(bits[1])), int(bits[2])])
		elif s.begins_with("mantises"):
			out["mantises"] = int(s.get_slice("=", 1).strip_edges())
		elif s.begins_with("finds"):
			out["finds"] = int(s.get_slice("=", 1).strip_edges())
		elif s.begins_with("dwellers"):
			out["dwellers"] = int(s.get_slice("=", 1).strip_edges())
		elif s.begins_with("vault"):
			var bits := s.get_slice("=", 1).strip_edges().split(" ", false)
			if bits.size() == 2:
				out["vault"] = Vector2i(int(bits[0]), int(bits[1]))
	return out


# ---------------------------------------------------------------- (v99) stations and asteroids

static func _grid(w: int, h: int) -> Array:
	var g: Array = []
	for y in h:
		var row := PackedStringArray()
		row.resize(w)
		row.fill(" ")
		g.append(row)
	return g


static func _put_at(g: Array, x: int, y: int, c: String) -> void:
	var row: PackedStringArray = g[y]
	row[x] = c
	g[y] = row


static func _sign_at(g: Array, x: int, y: int) -> String:
	if y < 0 or y >= g.size() or x < 0 or x >= (g[0] as PackedStringArray).size():
		return " "
	return (g[y] as PackedStringArray)[x]


static func _box(g: Array, x0: int, y0: int, x1: int, y1: int) -> void:
	## Walls round a floor from x0, y0 to x1, y1 (the walls' own cells), what is inside floor.
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_put_at(g, x, y, "#" if y == y0 or y == y1 or x == x0 or x == x1 else ".")


static func _split(rng: RandomNumberGenerator, from_x: int, to_x: int) -> Array:
	## Rooms side by side between two outer wall columns: [left floor x, right floor x] each, a wall between.
	var rooms: Array = []
	var x0 := from_x + 1
	while x0 <= to_x - 1:
		var left := to_x - x0
		var span := rng.randi_range(ROOM_MIN, ROOM_MAX)
		if left - span < ROOM_MIN + 1:
			span = left
		rooms.append([x0, x0 + span - 1])
		x0 += span + 1
	return rooms


static func _machine_ok(g: Array, x: int, y: int) -> bool:
	## A machine may stand there: on plain floor, no machine or door beside it (two machines side by side
	## would be read as one wide machine), and not in the way of a door above or below.
	if _sign_at(g, x, y) != ".":
		return false
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var c := _sign_at(g, x + d.x, y + d.y)
		if c == "A" or c == "D" or MapBuilder.MACHINE_SIGNS.find(c) >= 0:
			return false
	return true


static func station(rng: RandomNumberGenerator, used: Dictionary = {}) -> String:
	## (v99, my D1 pick) An abandoned station: a spine corridor two tall from end to end, a row of rooms over
	## it and a row under it, each room of a kind (quarters, storage, medbay, engine room, control room,
	## laboratory, armoury) with what such a room holds; the way in through a small dock room in the lower row,
	## its outer door at the bottom. Now and then a tall hall at one end. The vault, as on a derelict ship, is
	## the upper room farthest from the way in.
	var w := rng.randi_range(STATION_W.x, STATION_W.y)
	var top_h := rng.randi_range(3, 4)       # floor rows of the upper rooms
	var bot_h := rng.randi_range(3, 4)
	var spine := top_h + 1                   # the spine's top wall row
	var low := spine + 3                     # the spine's bottom wall row, the lower rooms' top wall
	var h := low + bot_h + 2
	var g := _grid(w, h)
	var hall := 0
	var hall_left := rng.randf() < 0.5
	if rng.randf() < WING_SHARE:
		hall = rng.randi_range(4, 6) + 1
	var l := hall if hall_left else 0
	var r := w - 1 - (0 if hall_left else hall)
	if hall > 0:
		var hl := 0 if hall_left else r
		var hr := l if hall_left else w - 1
		_box(g, hl, 0, hr, h - 1)
	_box(g, l, 0, r, spine)
	_box(g, l, spine, r, low)
	_box(g, l, low, r, h - 1)
	if hall > 0:
		# the hall's walls shared with the body; its door into the spine
		var wall_x := l if hall_left else r
		for y in h:
			_put_at(g, wall_x, y, "#")
		_put_at(g, wall_x, spine + rng.randi_range(1, 2), "A")
	# the dock room in the lower row: three across, its outer door at most DOOR_MAX_X across and the
	# rest of the station no more than RIGHT_MAX right of it
	var door_x := rng.randi_range(maxi(l + 2, w - RIGHT_MAX), mini(DOOR_MAX_X, r - 2))
	var lower := _split_at(rng, l, r, door_x)
	var upper := _split(rng, l, r)
	for k in upper.size():
		var a := int(upper[k][0])
		var b := int(upper[k][1])
		if k + 1 < upper.size():
			for y in range(1, spine):
				_put_at(g, b + 1, y, "#")
	for k in lower.size():
		var b := int(lower[k][1])
		if k + 1 < lower.size():
			for y in range(low + 1, h - 1):
				_put_at(g, b + 1, y, "#")
	_put_at(g, door_x, h - 1, "D")
	# kinds: the dock room none, the rest by lot (an armoury seldom)
	var rooms: Array = []                    # [left x, right x, first floor row, last floor row, kind (-1 the dock)]
	for k in upper.size():
		rooms.append([int(upper[k][0]), int(upper[k][1]), 1, spine - 1, _room_kind(rng)])
	for k in lower.size():
		var dock: bool = int(lower[k][0]) <= door_x and door_x <= int(lower[k][1])
		rooms.append([int(lower[k][0]), int(lower[k][1]), low + 1, h - 2, -1 if dock else _room_kind(rng)])
	# the vault: the upper room farthest from the way in, at least three across
	var vault := -1
	if upper.size() >= 3 and rng.randf() < VAULT_SHARE:
		var far := -1.0
		for k in upper.size():
			var mid := (float(upper[k][0]) + float(upper[k][1])) * 0.5
			if absf(mid - door_x) > far and int(upper[k][1]) - int(upper[k][0]) >= 2:
				far = absf(mid - door_x)
				vault = k
	var vault_door := Vector2i(-1, -1)
	for k in rooms.size():
		var room: Array = rooms[k]
		var a := int(room[0])
		var b := int(room[1])
		var upper_room := int(room[2]) == 1
		var dx := rng.randi_range(a, b)
		_put_at(g, dx, spine if upper_room else low, "D")
		if upper_room and k == vault:
			vault_door = Vector2i(dx, spine)
		# a door to the next room in the same row now and then (never the vault's)
		var next := k + 1
		if next < rooms.size() and int(rooms[next][2]) == int(room[2]) and k != vault and next != vault and rng.randf() < 0.3:
			_put_at(g, b + 1, rng.randi_range(int(room[2]), int(room[3])), "A")
		if upper_room and rng.randf() < 0.5:
			_put_at(g, rng.randi_range(a, b), 0, "W")
	if hall > 0:
		var hl := 1 if hall_left else r + 1
		var hr := l - 1 if hall_left else w - 2
		_put_at(g, rng.randi_range(hl, hr), 0, "W")
		rooms.append([hl, hr, 1, h - 2, _room_kind(rng)])
	var marks := PackedStringArray()
	for room: Array in rooms:
		var kind := int(room[4])
		if kind < 0:
			continue
		# machines against the far wall (the top one up, the bottom one down), dead
		var row := int(room[2]) if int(room[2]) == 1 else int(room[3])
		var signs: String = ROOM_MACHINES[kind]
		for m in rng.randi_range(1, 2):
			var mx := rng.randi_range(int(room[0]), int(room[1]))
			if _machine_ok(g, mx, row):
				_put_at(g, mx, row, signs[rng.randi_range(0, signs.length() - 1)])
		var cell := Vector2i(int(room[0]), (int(room[2]) + int(room[3])) / 2)
		marks.append("; room = %d %d %d" % [cell.x, cell.y, kind])
	var name := ""
	for tries in 20:
		name = "%s «%s»" % [STATION_KINDS[rng.randi_range(0, STATION_KINDS.size() - 1)], NAMES[rng.randi_range(0, NAMES.size() - 1)]]
		if not used.has(name):
			break
	used[name] = true
	var dwellers := rng.randi_range(1, 3) if rng.randf() < DWELL_SHARE else 0
	var lines := PackedStringArray(["; (v99) an abandoned station made from pieces (PlaceMaker)", "; kind = derelict",
		"; dwellers = %d" % dwellers])
	lines.append_array(marks)
	if vault_door.x >= 0:
		lines.append("; vault = %d %d" % [vault_door.x, vault_door.y])
		lines.append("& 1 %d %d herm" % [vault_door.x, vault_door.y])
	lines.append("= Заброшенная " + name)
	for row: PackedStringArray in g:
		lines.append("".join(row).rstrip(" "))
	return "\n".join(lines)


static func _split_at(rng: RandomNumberGenerator, from_x: int, to_x: int, door_x: int) -> Array:
	## The lower row's rooms: a dock room three across round the outer door's column, the rest split on each side.
	var dock_l := clampi(door_x - 1, from_x + 1, to_x - 3)
	var dock_r := dock_l + 2
	var out: Array = []
	if dock_l - 1 - from_x >= ROOM_MIN + 1:
		out.append_array(_split(rng, from_x, dock_l - 1))
	else:
		dock_l = from_x + 1
	var right: Array = []
	if to_x - (dock_r + 1) >= ROOM_MIN + 1:
		right = _split(rng, dock_r + 1, to_x)
	else:
		dock_r = to_x - 1
	out.append([dock_l, dock_r])
	out.append_array(right)
	return out


static func _room_kind(rng: RandomNumberGenerator) -> int:
	if rng.randf() < 0.08:
		return ROOM_KINDS.size() - 1         # the armoury, seldom
	return rng.randi_range(0, ROOM_KINDS.size() - 2)


static func asteroid(rng: RandomNumberGenerator, size: int) -> String:
	## (v99, the author's "asteroid generation", my A1 pick) An asteroid: rock in a bumpy round shape. A small
	## one is solid, its ore veins on the outside; a medium or large one has caves of bare ground, winding
	## up from a mouth in its bottom edge (where the ship lands, or the crew floats over to), ore veins in
	## their walls, more of them deep in. Mantises nest in half the caved ones; finds lie deep in.
	var w := rng.randi_range(ROCK_W[size].x, ROCK_W[size].y)
	var h := rng.randi_range(ROCK_H[size].x, ROCK_H[size].y)
	var g := _grid(w, h)
	var cx := (w - 1) * 0.5
	var cy := (h - 1) * 0.5
	var a := rng.randf() * TAU
	var b := rng.randf() * TAU
	var bump := rng.randf_range(0.08, 0.16)
	var inside := {}
	for y in h:
		for x in w:
			var dx := (x - cx) / (w * 0.5)
			var dy := (y - cy) / (h * 0.5)
			var ang := atan2(dy, dx)
			var edge := 1.0 - bump + bump * sin(3.0 * ang + a) * 0.7 + bump * sin(5.0 * ang + b) * 0.3
			if sqrt(dx * dx + dy * dy) < edge:
				inside[Vector2i(x, y)] = true
	var mouth := Vector2i(-1, -1)
	var passage := h                         # the passage's top row
	if size > 0:
		# the mouth's column, its rock walls on each side down to the bottom row
		# as near the middle as ship02's airlock lets it be (at the edge the passage would never get past the rim)
		var lo := maxi(2, w - RIGHT_MAX)
		var hi := mini(DOOR_MAX_X, w - 3)
		var mx := clampi(w / 2 + rng.randi_range(-2, 2), lo, hi)
		var y_top := h - 1
		while y_top > 0 and not inside.has(Vector2i(mx, y_top)):
			y_top -= 1
		for y in range(y_top, h):
			for x in range(mx - 1, mx + 2):
				inside[Vector2i(x, y)] = true
		mouth = Vector2i(mx, h - 1)
		# the passage goes up from the mouth until the rock round it is whole (past the asteroid's rim)
		passage = h - 3
		while passage > 1:
			var whole := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					whole = whole and inside.has(Vector2i(mx + dx, passage - 1 + dy))
			if whole:
				break
			for x in range(mx - 1, mx + 2):
				inside[Vector2i(x, passage - 1)] = true
			passage -= 1
	for c: Vector2i in inside:
		_put_at(g, c.x, c.y, "R")
	var ground := {}
	if size > 0:
		var carve := func(c: Vector2i) -> void:
			# bare ground only where the rock round it stays whole (a rim of rock to the outside)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not inside.has(c + Vector2i(dx, dy)):
						return
			ground[c] = true
		for y in range(mouth.y, passage - 1, -1):
			ground[Vector2i(mouth.x, y)] = true    # the mouth's passage, the way in
		# passages wind from the caves already dug toward spots deep in the rock, a chamber at each
		var spots: Array = []
		for c: Vector2i in inside:
			if c.y < passage:
				spots.append(c)
		var targets := 2 + size * 2 + rng.randi_range(0, 1) if not spots.is_empty() else 0
		for t in targets:
			var goal: Vector2i = spots[rng.randi_range(0, spots.size() - 1)]
			for tries in 6:
				var far: Vector2i = spots[rng.randi_range(0, spots.size() - 1)]
				if Vector2(far).distance_to(Vector2(mouth)) > Vector2(goal).distance_to(Vector2(mouth)):
					goal = far
			var dug: Array = ground.keys()
			var c: Vector2i = dug[rng.randi_range(0, dug.size() - 1)]
			if c.y > passage:
				c = Vector2i(mouth.x, passage)
			var wide := rng.randf() < 0.4
			for step in (w + h) * 2:
				if c == goal:
					break
				var d := Vector2i(signi(goal.x - c.x), signi(goal.y - c.y))
				if d.x != 0 and d.y != 0:
					d = Vector2i(d.x, 0) if rng.randf() < 0.5 else Vector2i(0, d.y)
				if rng.randf() < 0.3:
					d = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi_range(0, 3)]
				var n := c + d
				if not inside.has(n) or n.y > passage:
					continue
				carve.call(n)
				if not ground.has(n):
					continue                 # (only on through what it could dig: the caves stay joined)
				c = n
				if wide:
					carve.call(c + (Vector2i(0, 1) if d.x != 0 else Vector2i(1, 0)))
			var r := 1 + (1 if size == 2 and rng.randf() < 0.5 else 0)
			for dy in range(-1, 2):
				for dx in range(-r - 1, r + 2):
					carve.call(goal + Vector2i(dx, dy))
		# only what joins the way in: a passage cut off by the rim's rule is rock again
		var joined := {Vector2i(mouth.x, mouth.y): true}
		var todo := [Vector2i(mouth.x, mouth.y)]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if ground.has(c + d) and not joined.has(c + d):
					joined[c + d] = true
					todo.append(c + d)
		ground = joined
		for c: Vector2i in ground:
			_put_at(g, c.x, c.y, ",")
	# ore veins: in the caves' walls (more of them deep in), and on the outside
	var deepest := 1.0
	for c: Vector2i in ground:
		deepest = maxf(deepest, Vector2(c).distance_to(Vector2(mouth)))
	for c: Vector2i in inside:
		if ground.has(c):
			continue
		var by_cave := -1.0
		var by_space := false
		for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			if ground.has(c + d):
				by_cave = maxf(by_cave, Vector2(c + d).distance_to(Vector2(mouth)) / deepest)
			elif not inside.has(c + d):
				by_space = true
		if (by_cave >= 0.0 and rng.randf() < 0.08 + 0.22 * by_cave) or (by_space and rng.randf() < (0.22 if size == 0 else 0.04)):
			if absi(c.x - mouth.x) > 1 or c.y < passage:
				_put_at(g, c.x, c.y, "O")
	var first := 0
	while first < h - 1 and "".join(g[first]).strip_edges() == "":
		first += 1                           # no empty rows on top (the mouth is in the bottom one)
	var lines := PackedStringArray(["; (v99) an asteroid made by PlaceMaker", "; kind = asteroid"])
	if size > 0:
		lines.append("; mouth = %d %d" % [mouth.x, mouth.y - first])
		lines.append("; mantises = %d" % (rng.randi_range(0, 2) if rng.randf() < NEST_SHARE else -1))
		lines.append("; finds = %d" % rng.randi_range(0, size))
	lines.append("= " + ["Малый астероид", "Астероид", "Большой астероид"][size])
	for row: PackedStringArray in g.slice(first):
		lines.append("".join(row).rstrip(" "))
	return "\n".join(lines)
