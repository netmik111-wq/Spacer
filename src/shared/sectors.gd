extends RefCounted
## Space, as the ship's chart shows it. Space has no end: it is a grid of
## sectors without edges, and what is in a sector follows from where it is
## (and from the seed of this game), so nothing is stored about sectors the
## ship has not been near. Each sector has one main thing in it.
##
## This object holds the part of space around the ship, the "window": the
## sectors up to REACH_X to the sides and REACH_Y up and down of the one the
## ship is in. The server builds it anew every time the ship arrives
## somewhere and sends it to clients, who only read it. Inside a window a
## sector is known by its number there; `cell` says where in space it is.
##
## Routes join a sector to some of its four neighbours on the grid. Every
## sector has a route north or east, so there is always a way further out,
## and never a pocket of space with no way out of it.
##
## (v57, the author: "a linear point in the game where we go") Every game has
## one goal: the pirates' flagship waits in the sector `goal` names, a fixed
## number of jumps out (east and north). Along its row and its column every
## route is open, so a ship heading out east and north comes upon the lane.

const EMPTY := 0                     # nothing in particular
const METEORS := 1                   # a meteor stream: the hull takes hits
const TRADER := 2                    # a trader: sells supplies
const STATION := 3                   # a supply station: the ship's air is topped up
const DERELICT := 4                  # a derelict: an abandoned ship to search
const FLAGSHIP := 5                  # (v57) the goal: the pirates' flagship waits here
const ION_STORM := 6                 # (v61, the author's K16) an ion storm: inside it the reactor gives half, and surges put things out
const KIND_NAMES: Array[String] = ["спокойный космос", "метеорный поток", "торговец", "станция снабжения", "брошенный корабль", "флагман пиратов",
	"ионный шторм"]
const ION_SHARE := 0.3               # (v61) of the quiet sectors, those that hold an ion storm (about one sector in ten)
const GOAL_JUMPS := 12               # (v57) how far out the flagship waits, in jumps from the start

# (v58, the author: traders have their speciality) What a trader deals in:
#   an arms dealer: 3..5 ship guns and their ammunition; buys guns at half price, the rest cheap;
#   a junk dealer: no guns, no ammunition, its things a little cheaper; buys everything, cheap;
#   a black market: 1..2 rare guns (a tier above what the place would have) and ammunition.
# The traders nearest the start are always arms dealers, so that no game goes long without guns for sale.
const DEAL_ARMS := 0
const DEAL_JUNK := 1
const DEAL_BLACK := 2
const DEAL_NAMES: Array[String] = ["оружейник", "барахольщик", "чёрный рынок"]
const DEAL_ABOUT: Array[String] = ["продаёт корабельное оружие, модули и боеприпасы, оружие и модули покупает за половину цены",
	"оружия не держит, обычные вещи и модуль у него дешевле; покупает всё, но дёшево",
	"одно-два редких орудия, редкий модуль и боеприпасы, дорого; покупает за треть цены"]
const DEAL_ARMS_NEAR := 2            # every trader up to this many jumps from the start is an arms dealer
# what each buys a thing of ours back at: [plain things, ship guns, ammunition and gun parts]
const DEAL_SELL: Array = [[0.2, 0.5, 0.5], [0.2, 0.2, 0.2], [0.3, 0.3, 0.3]]
const JUNK_PRICES := 0.8             # a junk dealer's prices for plain things, against the usual

const NAMES: Array[String] = [
	"Тихая заводь", "Кеплер", "Пояс Хадли", "Рубеж", "Стеклянное море", "Маяк Орта",
	"Глухой угол", "Вега-Прайм", "Перекат", "Северный створ", "Ржавый брод", "Тёмная вода",
	"Полынья", "Карман Лема", "Отмель", "Дальний причал", "Сухой док", "Белый шум",
	"Старый фарватер", "Узкий проход", "Соляной шлейф", "Колодец", "Зимовье", "Медный берег",
	"Ледяная гряда", "Порог", "Тихий омут", "Чёрный плёс", "Высокая вода", "Одинокий бакен",
]

const REACH_X := 3                   # how far the chart reaches from the ship's sector, in sectors
const REACH_Y := 2
const MAX_ROUTES := 4                # a sector has at most this many routes (its four neighbours)
const EXTRA_ROUTE := 0.3             # how often a sector has a route besides the one it must have, each way
const NEAR_METEORS := 0.2            # the share of sectors with a meteor stream at the start of the voyage,
const FAR_METEORS := 0.015           # how much it grows with every sector away from there,
const MOST_METEORS := 0.45           # and where it stops growing

# Inside a sector the ship moves on a square of SPAN by SPAN units.
const SPAN := 200.0
const SHIP_SPEED := 1.5              # units per second under way
const DOCK_RANGE := 10               # how close the ship must come to a trader or a station

var count := 0
var here := 0                        # the number of the ship's own sector in this window
var cell: Array[Vector2i] = []       # where in space each sector is
var kind := PackedByteArray()
var pos := PackedVector2Array()      # where each sector sits on the chart, 0..100 across, 0..60 down
var names := PackedStringArray()
var visited := PackedByteArray()     # 1 = the ship has been there
var links: Array = []                # pairs [a, b] with a < b

# the inside of each sector
var spot := PackedVector2Array()     # where its main thing is: the middle of the meteor stream, the station, the trader
var reach := PackedByteArray()       # how far that thing reaches: the stream's radius, or DOCK_RANGE; 0 = nothing there
var entry := PackedVector2Array()    # where a ship arriving by jump appears
var goal := Vector2i.ZERO            # (v57) where in space the flagship waits (it may lie outside the window)
var deal := PackedByteArray()        # (v58) per sector: what its trader deals in (DEAL_*; for a trader only)


static func key(at: Vector2i) -> int:
	## A sector's place in space as one number (for remembering where the ship has been).
	return ((at.y + 32768) << 16) | (at.x + 32768)


static func _mix(seed_value: int, x: int, y: int, salt: int) -> int:
	## A number that depends on the place, the game's seed and what it is for, and looks random.
	var h := (seed_value ^ (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = ((h ^ (h >> 16)) * 668265261) & 0x7FFFFFFF
	return h ^ (h >> 15)


static func _unit(seed_value: int, x: int, y: int, salt: int) -> float:
	return float(_mix(seed_value, x, y, salt) % 100003) / 100003.0


static func _east(seed_value: int, at: Vector2i) -> bool:
	## Is there a route from this sector to the one east of it?
	return (_mix(seed_value, at.x, at.y, 1) & 1) == 0 or _unit(seed_value, at.x, at.y, 2) < EXTRA_ROUTE


static func _north(seed_value: int, at: Vector2i) -> bool:
	return (_mix(seed_value, at.x, at.y, 1) & 1) == 1 or _unit(seed_value, at.x, at.y, 3) < EXTRA_ROUTE


static func goal_of(seed_value: int) -> Vector2i:
	## (v57) The flagship's sector: GOAL_JUMPS out, mostly east, some of it north.
	var north := 3 + _mix(seed_value, 0, 0, 11) % 3
	return Vector2i(GOAL_JUMPS - north, -north)


static func jumps_between(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func joined(seed_value: int, a: Vector2i, b: Vector2i) -> bool:
	## Is there a route between two sectors of space? (v57) Along the goal's row
	## and its column every route is there: a lane straight to the flagship that
	## any way out east and north must cross (unless it has already gone past it).
	var d := b - a
	var g := goal_of(seed_value)
	if jumps_between(a, b) == 1 and ((a.x == g.x and b.x == g.x) or (a.y == g.y and b.y == g.y)):
		return true
	if d == Vector2i(1, 0):
		return _east(seed_value, a)
	if d == Vector2i(-1, 0):
		return _east(seed_value, b)
	if d == Vector2i(0, -1):
		return _north(seed_value, a)
	if d == Vector2i(0, 1):
		return _north(seed_value, b)
	return false


static func kind_at(seed_value: int, at: Vector2i) -> int:
	## What a sector holds. The start is quiet; further out meteor streams get commoner.
	if at == Vector2i.ZERO:
		return EMPTY
	if at == goal_of(seed_value):
		return FLAGSHIP
	var far := absi(at.x) + absi(at.y)
	var meteors := clampf(NEAR_METEORS + FAR_METEORS * far, NEAR_METEORS, MOST_METEORS)
	var roll := _unit(seed_value, at.x, at.y, 4)
	if roll < meteors:
		return METEORS
	roll = (roll - meteors) / (1.0 - meteors)        # what is left is shared out as before
	if roll < 0.32:
		# (v61) part of the quiet ones hold an ion storm; the rest of space stays where it was in older saves
		return ION_STORM if roll < 0.32 * ION_SHARE else EMPTY
	if roll < 0.47:
		return DERELICT
	return TRADER if roll < 0.72 else STATION


static func deal_at(seed_value: int, at: Vector2i) -> int:
	## (v58) What the trader in that sector deals in (DEAL_*).
	if absi(at.x) + absi(at.y) <= DEAL_ARMS_NEAR:
		return DEAL_ARMS
	var roll := _unit(seed_value, at.x, at.y, 12)
	return DEAL_ARMS if roll < 0.4 else (DEAL_JUNK if roll < 0.75 else DEAL_BLACK)


static func name_at(seed_value: int, at: Vector2i) -> String:
	var base := NAMES[_mix(seed_value, at.x, at.y, 5) % NAMES.size()]
	return "%s-%d" % [base, 2 + _mix(seed_value, at.x, at.y, 6) % 98]


func build(seed_value: int, centre: Vector2i, been: Dictionary) -> void:
	## The window of space around `centre`. `been` holds the keys of the sectors the ship has visited.
	count = (2 * REACH_X + 1) * (2 * REACH_Y + 1)
	cell.clear()
	kind.resize(count)
	pos.resize(count)
	names.resize(count)
	visited.resize(count)
	spot.resize(count)
	reach.resize(count)
	entry.resize(count)
	deal.resize(count)
	links.clear()
	goal = goal_of(seed_value)
	var rng := RandomNumberGenerator.new()
	var i := 0
	for dy in range(-REACH_Y, REACH_Y + 1):
		for dx in range(-REACH_X, REACH_X + 1):
			var at := centre + Vector2i(dx, dy)
			cell.append(at)
			if dx == 0 and dy == 0:
				here = i
			kind[i] = kind_at(seed_value, at)
			deal[i] = deal_at(seed_value, at)
			names[i] = name_at(seed_value, at)
			visited[i] = 1 if been.has(key(at)) else 0
			# on the chart: a grid, each sector nudged a little off its place so it does not look like one
			pos[i] = Vector2(
				8.0 + (dx + REACH_X) * 84.0 / (2 * REACH_X) + (_unit(seed_value, at.x, at.y, 8) - 0.5) * 7.0,
				8.0 + (dy + REACH_Y) * 42.0 / (2 * REACH_Y) + (_unit(seed_value, at.x, at.y, 9) - 0.5) * 5.0)
			# the inside of the sector
			rng.seed = _mix(seed_value, at.x, at.y, 7)
			spot[i] = Vector2(rng.randf_range(70.0, 130.0), rng.randf_range(70.0, 130.0))
			var away := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
			match kind[i]:
				METEORS:
					# a jump lands the ship inside the stream, some way from its edge
					reach[i] = rng.randi_range(45, 60)
					entry[i] = spot[i] + away * reach[i] * rng.randf_range(0.35, 0.6)
				ION_STORM:
					# (v61) a storm is wider than a stream; a jump lands inside it too
					reach[i] = rng.randi_range(55, 75)
					entry[i] = spot[i] + away * reach[i] * rng.randf_range(0.35, 0.6)
				TRADER, STATION, DERELICT:
					reach[i] = DOCK_RANGE
					entry[i] = spot[i] + away * rng.randf_range(45.0, 65.0)
				_:
					reach[i] = 0
					entry[i] = spot[i]
			entry[i] = entry[i].clamp(Vector2(4, 4), Vector2(SPAN - 4, SPAN - 4)).round()
			spot[i] = spot[i].round()
			i += 1
	var wide := 2 * REACH_X + 1
	for a in count:
		if a % wide < wide - 1 and joined(seed_value, cell[a], cell[a + 1]):
			links.append([a, a + 1])
		if a + wide < count and joined(seed_value, cell[a], cell[a + wide]):
			links.append([a, a + wide])


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
	## Is a ship at this place inside the sector's meteor stream or ion storm, or close enough to dock?
	return reach[id] > 0 and at.distance_to(spot[id]) <= reach[id]


func far_from_start(id: int) -> int:
	## How many jumps from where the voyage began, at the least.
	return absi(cell[id].x) + absi(cell[id].y)


func jumps_to_goal(id: int) -> int:
	## (v57) How many jumps from that sector to the flagship's, at the least.
	return jumps_between(cell[id], goal)


func describe(id: int) -> String:
	if kind[id] == TRADER and deal.size() > id:
		return "«%s», %s: %s" % [names[id], KIND_NAMES[kind[id]], DEAL_NAMES[deal[id]]]     # (v58)
	return "«%s», %s" % [names[id], KIND_NAMES[kind[id]]]


func pack() -> PackedByteArray:
	## For the network: u8 count, u8 here; per sector s16 cell x, s16 cell y, u8 kind, u8 visited,
	## u8 x, u8 y on the chart, u8 spot x, u8 spot y, u8 reach, u8 entry x, u8 entry y,
	## u8 name length, name; u8 links; pairs u8, u8; (v57) s16 goal x, s16 goal y; (v58) per sector u8 deal.
	var out := PackedByteArray([count, here])
	for i in count:
		var name_bytes := names[i].to_utf8_buffer()
		var o := out.size()
		out.resize(o + 14)
		out.encode_s16(o, cell[i].x)
		out.encode_s16(o + 2, cell[i].y)
		out.encode_u8(o + 4, kind[i])
		out.encode_u8(o + 5, visited[i])
		out.encode_u8(o + 6, roundi(pos[i].x))
		out.encode_u8(o + 7, roundi(pos[i].y))
		out.encode_u8(o + 8, roundi(spot[i].x))
		out.encode_u8(o + 9, roundi(spot[i].y))
		out.encode_u8(o + 10, reach[i])
		out.encode_u8(o + 11, roundi(entry[i].x))
		out.encode_u8(o + 12, roundi(entry[i].y))
		out.encode_u8(o + 13, name_bytes.size())
		out.append_array(name_bytes)
	out.append(links.size())
	for l: Array in links:
		out.append(int(l[0]))
		out.append(int(l[1]))
	var o := out.size()
	out.resize(o + 4)
	out.encode_s16(o, goal.x)
	out.encode_s16(o + 2, goal.y)
	out.append_array(deal)
	return out


func unpack(data: PackedByteArray, at: int) -> void:
	count = data[at]
	here = data[at + 1]
	at += 2
	cell.clear()
	kind.resize(count)
	pos.resize(count)
	names.resize(count)
	visited.resize(count)
	spot.resize(count)
	reach.resize(count)
	entry.resize(count)
	for i in count:
		cell.append(Vector2i(data.decode_s16(at), data.decode_s16(at + 2)))
		kind[i] = data[at + 4]
		visited[i] = data[at + 5]
		pos[i] = Vector2(data[at + 6], data[at + 7])
		spot[i] = Vector2(data[at + 8], data[at + 9])
		reach[i] = data[at + 10]
		entry[i] = Vector2(data[at + 11], data[at + 12])
		var n := data[at + 13]
		names[i] = data.slice(at + 14, at + 14 + n).get_string_from_utf8()
		at += 14 + n
	links.clear()
	var link_count := data[at]
	at += 1
	for i in link_count:
		links.append([data[at], data[at + 1]])
		at += 2
	goal = Vector2i(data.decode_s16(at), data.decode_s16(at + 2))
	at += 4
	deal = data.slice(at, at + count) if data.size() >= at + count else PackedByteArray()
	deal.resize(count)
