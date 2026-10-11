extends RefCounted
## The piece of space the ship travels in: a handful of sectors joined by jump
## routes. Each sector has one main thing in it. The server makes the map and
## sends it to clients, who only read it.
##
## This is the simplest thing that works. The author's vision (docs/VISION.md)
## is an endless space; when that comes, sectors will be made as the ship
## reaches them instead of all at once.

const EMPTY := 0                     # nothing in particular
const METEORS := 1                   # a meteor stream: the hull takes hits
const TRADER := 2                    # a trader (nothing to trade yet)
const STATION := 3                   # a supply station: the ship's air is topped up
const KIND_NAMES: Array[String] = ["спокойный космос", "метеорный поток", "торговец", "станция снабжения"]

const NAMES: Array[String] = [
	"Тихая заводь", "Кеплер-7", "Пояс Хадли", "Рубеж", "Стеклянное море", "Маяк Орта",
	"Глухой угол", "Вега-Прайм", "Перекат", "Северный створ", "Ржавый брод", "Тёмная вода",
	"Полынья", "Карман Лема", "Отмель", "Дальний причал", "Сухой док", "Белый шум",
]

const MAX_ROUTES := 4                # a sector gets no second way round beyond this many routes

# Inside a sector the ship moves on a square of SPAN by SPAN units.
const SPAN := 200.0
const SHIP_SPEED := 1.5              # units per second under way
const DOCK_RANGE := 10               # how close the ship must come to a trader or a station

var count := 0
var kind := PackedByteArray()
var pos := PackedVector2Array()      # where each sector sits on the chart, 0..100 across, 0..60 down
var names := PackedStringArray()
var links: Array = []                # pairs [a, b] with a < b

# the inside of each sector
var spot := PackedVector2Array()     # where its main thing is: the middle of the meteor stream, the station, the trader
var reach := PackedByteArray()       # how far that thing reaches: the stream's radius, or DOCK_RANGE; 0 = nothing there
var entry := PackedVector2Array()    # where a ship arriving by jump appears


func generate(seed_value: int, how_many: int = 12) -> void:
	## A new chart. Sector 0 is where the ship starts: quiet space.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	count = mini(how_many, NAMES.size())
	kind.resize(count)
	pos.resize(count)
	names.resize(count)
	var pool := NAMES.duplicate()
	for i in count:
		# a place not too close to the sectors already there
		var best := Vector2.ZERO
		var best_gap := -1.0
		for attempt in 12:
			var p := Vector2(rng.randf_range(6.0, 94.0), rng.randf_range(6.0, 54.0))
			var gap := 1000.0
			for j in i:
				gap = minf(gap, p.distance_to(pos[j]))
			if gap > best_gap:
				best_gap = gap
				best = p
		pos[i] = best
		var pick := rng.randi_range(0, pool.size() - 1)
		names[i] = pool[pick]
		pool.remove_at(pick)
		var roll := rng.randf()
		kind[i] = EMPTY if roll < 0.3 else (METEORS if roll < 0.65 else (TRADER if roll < 0.8 else STATION))
	kind[0] = EMPTY
	# routes: every sector is tied to the nearest one made before it, so the
	# chart is in one piece, then to its nearest neighbour for a second way round
	links.clear()
	for i in range(1, count):
		var near := 0
		for j in i:
			if pos[i].distance_to(pos[j]) < pos[i].distance_to(pos[near]):
				near = j
		_link(near, i)
	for i in count:
		var near := -1
		for j in count:
			if j != i and not linked(i, j) and neighbours(j).size() < MAX_ROUTES \
					and (near < 0 or pos[i].distance_to(pos[j]) < pos[i].distance_to(pos[near])):
				near = j
		if near >= 0 and neighbours(i).size() < MAX_ROUTES and pos[i].distance_to(pos[near]) < 34.0:
			_link(i, near)
	# make sure there is a trader, a supply station and a meteor stream somewhere
	if not kind.has(TRADER):
		kind[count - 2] = TRADER
	if not kind.has(STATION):
		kind[count - 1] = STATION
	if not kind.has(METEORS):
		kind[1] = METEORS
	# the inside of every sector
	spot.resize(count)
	reach.resize(count)
	entry.resize(count)
	for i in count:
		spot[i] = Vector2(rng.randf_range(70.0, 130.0), rng.randf_range(70.0, 130.0))
		var away := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		match kind[i]:
			METEORS:
				# a jump lands the ship inside the stream, some way from its edge
				reach[i] = rng.randi_range(45, 60)
				entry[i] = spot[i] + away * reach[i] * rng.randf_range(0.35, 0.6)
			TRADER, STATION:
				reach[i] = DOCK_RANGE
				entry[i] = spot[i] + away * rng.randf_range(45.0, 65.0)
			_:
				reach[i] = 0
				entry[i] = spot[i]
		entry[i] = entry[i].clamp(Vector2(4, 4), Vector2(SPAN - 4, SPAN - 4)).round()
		spot[i] = spot[i].round()


func _link(a: int, b: int) -> void:
	if a != b and not linked(a, b):
		links.append([mini(a, b), maxi(a, b)])


func linked(a: int, b: int) -> bool:
	for l: Array in links:
		if int(l[0]) == mini(a, b) and int(l[1]) == maxi(a, b):
			return true
	return false


func neighbours(of: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for l: Array in links:
		if int(l[0]) == of:
			out.append(int(l[1]))
		elif int(l[1]) == of:
			out.append(int(l[0]))
	return out


func within_reach(id: int, at: Vector2) -> bool:
	## Is a ship at this place inside the sector's meteor stream, or close enough to dock?
	return reach[id] > 0 and at.distance_to(spot[id]) <= reach[id]


func describe(id: int) -> String:
	return "«%s», %s" % [names[id], KIND_NAMES[kind[id]]]


func pack() -> PackedByteArray:
	## For the network: u8 count; per sector u8 kind, u8 x, u8 y, u8 spot x, u8 spot y, u8 reach,
	## u8 entry x, u8 entry y, u8 name length, name; u8 links; pairs u8, u8.
	var out := PackedByteArray([count])
	for i in count:
		var name_bytes := names[i].to_utf8_buffer()
		out.append_array(PackedByteArray([kind[i], roundi(pos[i].x), roundi(pos[i].y),
			roundi(spot[i].x), roundi(spot[i].y), reach[i], roundi(entry[i].x), roundi(entry[i].y), name_bytes.size()]))
		out.append_array(name_bytes)
	out.append(links.size())
	for l: Array in links:
		out.append(int(l[0]))
		out.append(int(l[1]))
	return out


func unpack(data: PackedByteArray, at: int) -> void:
	count = data[at]
	at += 1
	kind.resize(count)
	pos.resize(count)
	names.resize(count)
	spot.resize(count)
	reach.resize(count)
	entry.resize(count)
	for i in count:
		kind[i] = data[at]
		pos[i] = Vector2(data[at + 1], data[at + 2])
		spot[i] = Vector2(data[at + 3], data[at + 4])
		reach[i] = data[at + 5]
		entry[i] = Vector2(data[at + 6], data[at + 7])
		var n := data[at + 8]
		names[i] = data.slice(at + 9, at + 9 + n).get_string_from_utf8()
		at += 9 + n
	links.clear()
	var link_count := data[at]
	at += 1
	for i in link_count:
		links.append([data[at], data[at + 1]])
		at += 2
