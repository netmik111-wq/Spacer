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

const HEIGHT := 7                    # rows, walls included: what fits over ship02's airlock (as derelict01)
const COUNT := 8                     # (my P1 pick) the campaign's own derelicts
const ROOM_MIN := 3                  # a room's floor, cells across
const ROOM_MAX := 7
const DOOR_MAX_X := 10               # the outer door's column at most: ship02's airlock is at x 10
const MACHINES := "1345PC67"        # what stands about, dead (single machines: no wide ones)
const WING_SHARE := 0.4              # a tall room at one end
const VAULT_SHARE := 0.5             # (my V1 pick) of the made ones, the share with a vault
const DWELL_SHARE := 0.5             # (my I1 pick) the share with robots living aboard
const KINDS := ["транспорт", "рудовоз", "танкер", "лайнер", "буксир", "грузовик", "разведчик", "ковчег", "сборщик", "курьер"]
const NAMES := ["Вега", "Тамбов", "Сирин", "Полярник", "Каракум", "Ладога", "Бирюза", "Енисей", "Прометей", "Медуза",
	"Северянка", "Таймыр", "Орион", "Гончая", "Альтаир", "Иртыш", "Кассиопея", "Мираж", "Скиф", "Заря"]


static func make_set(seed_value: int) -> Dictionary:
	## COUNT drawings by name ("made:1"...): the same seed gives the same set.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := {}
	var used := {}
	for i in COUNT:
		out["made:%d" % (i + 1)] = derelict(rng, used)
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
	## What the marks of a made drawing say: {"dwellers": n, "vault": the vault door's cell or (-1, -1)}.
	var out := {"dwellers": 0, "vault": Vector2i(-1, -1), "made": false}
	for l in text.split("\n"):
		var s := l.strip_edges()
		if not s.begins_with(";"):
			continue
		s = s.substr(1).strip_edges()
		if s.begins_with("(v97)"):
			out["made"] = true
		elif s.begins_with("dwellers"):
			out["dwellers"] = int(s.get_slice("=", 1).strip_edges())
		elif s.begins_with("vault"):
			var bits := s.get_slice("=", 1).strip_edges().split(" ", false)
			if bits.size() == 2:
				out["vault"] = Vector2i(int(bits[0]), int(bits[1]))
	return out
