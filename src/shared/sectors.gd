extends RefCounted
## Space, as the ship's chart shows it. (v64, the author's cluster answers
## C1..C19) Space is a road of clusters: each cluster is 10 to 14 star systems
## ("sectors" in the code and on older screens) joined by lanes, with the ship
## coming in on its left side and two exits on its right. A long jump from an
## exit system (EXIT_FUEL cans) leaves the cluster for good and comes into the
## next one; each exit leads to a cluster of its own kind, shown before one
## goes. The pirates' flagship waits in the fourth cluster (FLAG_DEPTH); its
## exits open only once it is beaten. After it, the road goes on, harder.
##
## A cluster lies on a grid of COLS by ROWS cells of space: cluster `depth`
## takes the columns from 6 * depth on, so no two clusters of one game share a
## cell, and a system is still known by its cell (Sectors.key) everywhere.
## What a cluster holds follows from the game's seed, its depth and the cell
## the ship comes in at (its `entry`), so nothing is stored about it but those.
##
## This object holds the cluster the ship is in. The server builds it when the
## ship comes into the cluster (and when a save is loaded) and sends it to the
## clients, who only read it. Inside it a system is known by its number; `cell`
## says where in space it is.
##
## Inside a system the ship flies on a square of SPAN by SPAN units: its main
## thing (a trader, a station, a wreck, a meteor stream, an ion storm) has its
## `spot`, and (v64, the author's C6 and his notebook) places of its own lie
## about it, most of them hidden until the ship's sensors come near: debris,
## a dropped container, bodies, an abandoned ship, a battlefield, a pirate
## ambush (places_of).

const EMPTY := 0                     # nothing in particular
const METEORS := 1                   # a meteor stream: the hull takes hits
const TRADER := 2                    # a trader: sells supplies
const STATION := 3                   # a supply station: the ship's air is topped up
const DERELICT := 4                  # a derelict: an abandoned ship to search
const FLAGSHIP := 5                  # (v57) the goal: the pirates' flagship waits here
const ION_STORM := 6                 # (v61, the author's K16) an ion storm: inside it the reactor gives half, and surges put things out
const KIND_NAMES: Array[String] = ["спокойный космос", "метеорный поток", "торговец", "станция снабжения", "брошенный корабль", "флагман пиратов",
	"ионный шторм"]

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
const DEAL_ARMS_NEAR := 2            # every trader up to this many cells from the start is an arms dealer
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

# (v64) the kinds of cluster (the author's C12): what most of its systems hold
const C_FRONTIER := 0                # a mix of everything; the first cluster is always one
const C_PIRATE := 1                  # pirate territory: more pirates and ambushes, hunters come sooner
const C_TRADE := 2                   # trade worlds: traders and stations, hunters come later
const C_STORM := 3                   # a storm belt: a band of ion storms across it
const C_DEAD := 4                    # a dead zone: wrecks and secrets, no supply station, little fuel
const CLUSTER_NAMES: Array[String] = ["Приграничье", "Пиратские угодья", "Торговые миры", "Штормовой пояс", "Мёртвая зона"]
const CLUSTER_ABOUT: Array[String] = ["всего понемногу", "много пиратов и засад, охотники приходят раньше",
	"торговцы и станции, охотники приходят позже", "полоса ионных штормов", "обломки и тайники, станций снабжения нет, топлива мало"]
# per kind of cluster: the weight of each kind of system [quiet, meteors, trader, station, derelict, -, ion storm]
const SYSTEM_WEIGHTS: Array = [
	[30, 15, 20, 12, 15, 0, 6],
	[35, 15, 12, 6, 22, 0, 8],
	[20, 10, 34, 24, 10, 0, 2],
	[25, 12, 16, 10, 12, 0, 8],
	[30, 18, 8, 0, 40, 0, 4],
]
const STORM_BAND := [3, 5]           # a storm belt's band of ion storms: this many systems
const FOG_CHANCE: Array[float] = [0.3, 0.5, 0.2, 0.2, 0.5]   # (the author's C14) per kind of cluster: a nebula over some systems
const FOG_PATCH := [2, 4]            # the nebula covers this many systems

const COLS := 5                      # a cluster's grid of cells
const ROWS := 4
const SYSTEMS := [10, 14]            # (the author's C2) systems in a cluster
const MOST_SYSTEMS := 16             # (the author's C17) with a big crew there are a few more, up to this
const EXTRA_LANE := 0.4              # of two neighbouring systems not joined already, this share get a lane
const DIAGONAL_LANE := 0.15          # and now and then a lane across a corner
const FLAG_DEPTH := 3                # (the author's C3) the flagship waits in the fourth cluster
const LEVEL_STEP := 4                # (the author's C13) each cluster is this many steps of danger harder
const EXIT_FUEL := 2                 # (the author's C11) a long jump out of the cluster burns this many cans
const EXIT_JUMP := 254               # the jump target that means "the long jump out by this exit"
const NO_GOAL := Vector2i(-32768, -32768)   # `goal` when the flagship is not in this cluster

# (v64) places inside a system (places_of)
const P_DEBRIS := 0                  # debris: spare parts and scrap
const P_CONTAINER := 1               # a dropped container: things, a crate of gear, or a mine
const P_BODIES := 2                  # bodies: what they carried, now and then a survivor
const P_WRECK := 3                   # an abandoned ship: comes alongside to be searched, as a derelict
const P_BATTLEFIELD := 4             # (the author's notebook) a battlefield: debris and bodies, more of everything
const P_AMBUSH := 5                  # (the author's notebook) a pirate ship lying in wait: seen from afar, avoidable
const PLACE_NAMES: Array[String] = ["обломки", "контейнер", "тела", "брошенный корабль", "поле боя", "засада пиратов"]
const PLACE_WEIGHTS: Array[int] = [30, 25, 20, 10, 8, 7]
const PLACE_REACH := 6               # how close the ship must come to take a place
const WRECK_REACH := DOCK_RANGE      # an abandoned ship: as close as to a derelict
const AMBUSH_REACH := 25             # coming this close to an ambush, the pirates come out

# Inside a sector the ship moves on a square of SPAN by SPAN units.
const SPAN := 200.0
const SHIP_SPEED := 1.5              # units per second under way
const DOCK_RANGE := 10               # how close the ship must come to a trader or a station

var count := 0
var here := 0                        # the number of the ship's own system in this cluster
var cell: Array[Vector2i] = []       # where in space each system is
var kind := PackedByteArray()
var pos := PackedVector2Array()      # where each system sits on the chart, 0..100 across, 0..60 down
var names := PackedStringArray()
var visited := PackedByteArray()     # 1 = the ship has been there
var links: Array = []                # pairs [a, b] with a < b

# the inside of each system
var spot := PackedVector2Array()     # where its main thing is: the middle of the meteor stream, the station, the trader
var reach := PackedByteArray()       # how far that thing reaches: the stream's radius, or DOCK_RANGE; 0 = nothing there
var entry := PackedVector2Array()    # where a ship arriving by jump appears
var goal := NO_GOAL                  # (v57) the flagship's system, if it is in this cluster
var deal := PackedByteArray()        # (v58) per system: what its trader deals in (DEAL_*; for a trader only)

# (v64) the cluster
var depth := 0                       # how many clusters lie behind it (0: the first)
var ckind := C_FRONTIER              # its kind (C_*)
var start := 0                       # the system the ship came in at
var exits := PackedByteArray()       # the systems one may leave the cluster from
var beyond := PackedByteArray()      # per exit: the kind of the cluster it leads to
var locked := false                  # (the flagship's cluster) its exits stay shut until the flagship is beaten
var level := PackedByteArray()       # per system: how dangerous it is (what far_from_start gives)
var fog := PackedByteArray()         # per system: 1 = inside a nebula (the author's C14)
var road := PackedByteArray()        # the kinds of the clusters left behind, oldest first (the server sets it)


static func key(at: Vector2i) -> int:
	## A system's place in space as one number (for remembering where the ship has been).
	return ((at.y + 32768) << 16) | (at.x + 32768)


static func _mix(seed_value: int, x: int, y: int, salt: int) -> int:
	## A number that depends on the place, the game's seed and what it is for, and looks random.
	var h := (seed_value ^ (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = ((h ^ (h >> 16)) * 668265261) & 0x7FFFFFFF
	return h ^ (h >> 15)


static func _unit(seed_value: int, x: int, y: int, salt: int) -> float:
	return float(_mix(seed_value, x, y, salt) % 100003) / 100003.0


static func jumps_between(a: Vector2i, b: Vector2i) -> int:
	## How far apart two cells of space are, counted on the grid (not along lanes: see hops).
	return absi(a.x - b.x) + absi(a.y - b.y)


static func deal_at(seed_value: int, at: Vector2i) -> int:
	## (v58) What the trader in that sector deals in (DEAL_*).
	if absi(at.x) + absi(at.y) <= DEAL_ARMS_NEAR:
		return DEAL_ARMS
	var roll := _unit(seed_value, at.x, at.y, 12)
	return DEAL_ARMS if roll < 0.4 else (DEAL_JUNK if roll < 0.75 else DEAL_BLACK)


static func name_at(seed_value: int, at: Vector2i) -> String:
	var base := NAMES[_mix(seed_value, at.x, at.y, 5) % NAMES.size()]
	return "%s-%d" % [base, 2 + _mix(seed_value, at.x, at.y, 6) % 98]


static func cluster_kind(seed_value: int, p_depth: int, at: Vector2i) -> int:
	## The kind of the cluster whose ship comes in at `at` (the first is always the frontier).
	if p_depth <= 0:
		return C_FRONTIER
	return _mix(seed_value, at.x, at.y, 200 + p_depth) % CLUSTER_NAMES.size()


static func next_entry(exit_cell: Vector2i) -> Vector2i:
	## Where a ship leaving by that exit comes into the next cluster: two columns on, the same row.
	return exit_cell + Vector2i(2, 0)


static func beyond_kinds(seed_value: int, p_depth: int, exit_cells: Array) -> PackedByteArray:
	## The kinds of the clusters the exits lead to; two exits never lead to clusters of one kind.
	var out := PackedByteArray()
	for c: Vector2i in exit_cells:
		var k := cluster_kind(seed_value, p_depth + 1, next_entry(c))
		if out.has(k):
			k = (k + 1 + _mix(seed_value, c.x, c.y, 77) % (CLUSTER_NAMES.size() - 1)) % CLUSTER_NAMES.size()
			if out.has(k):
				k = (k + 1) % CLUSTER_NAMES.size()
		out.append(k)
	return out


static func size_for(seed_value: int, p_depth: int, at: Vector2i, crew: int) -> int:
	## How many systems the cluster has: 10 to 14, one more for every two of the crew past two.
	var n := SYSTEMS[0] + _mix(seed_value, at.x, at.y, 300 + p_depth) % (SYSTEMS[1] - SYSTEMS[0] + 1)
	return mini(n + maxi(crew - 2, 0) / 2, MOST_SYSTEMS)


func build(seed_value: int, centre: Vector2i, been: Dictionary, p_depth: int = 0, at: Vector2i = Vector2i.ZERO,
		crew: int = 1, flagship: bool = true) -> void:
	## The cluster `p_depth` the ship came into at `at`, with the ship at `centre` (the
	## start if that is not in it). `been` holds the keys of the systems the ship has
	## visited; `crew` how many play (the author's C17); `flagship` false once it is beaten.
	depth = p_depth
	ckind = cluster_kind(seed_value, depth, at)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(seed_value, at.x, at.y, 100 + depth)
	var row0: int = rng.randi_range(0, ROWS - 1) if depth > 0 else rng.randi_range(1, 2)
	var origin := at - Vector2i(0, row0)
	# the cells: two ways across, from the entry to two exits on the far side, then more around them
	var parent := {}                     # local cell -> the one it grew from (the lanes that must be)
	var first := Vector2i(0, row0)
	parent[first] = first
	var top := rng.randi_range(0, 1)
	var bottom := rng.randi_range(2, 3)
	for to: Vector2i in [Vector2i(COLS - 1, top), Vector2i(COLS - 1, bottom)]:
		var c := first
		while c != to:
			var n := c
			if c.x == COLS - 1 or (c.y != to.y and rng.randf() < 0.4):
				n = c + Vector2i(0, signi(to.y - c.y))
			else:
				n = c + Vector2i(1, 0)
			if not parent.has(n):
				parent[n] = c
			c = n
	var want := size_for(seed_value, depth, at, crew)
	var tries := 0
	while parent.size() < want and tries < 400:
		tries += 1
		var keys: Array = parent.keys()
		var from: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
		var d: Vector2i = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi_range(0, 3)]
		var n := from + d
		if n.x < 0 or n.x >= COLS or n.y < 0 or n.y >= ROWS or parent.has(n):
			continue
		parent[n] = from
	# number them by column, then by row
	var locals: Array = parent.keys()
	locals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	count = locals.size()
	var index := {}
	for i in count:
		index[locals[i]] = i
	cell.clear()
	kind.resize(count)
	pos.resize(count)
	names.resize(count)
	visited.resize(count)
	spot.resize(count)
	reach.resize(count)
	entry.resize(count)
	deal.resize(count)
	level.resize(count)
	fog.resize(count)
	fog.fill(0)
	links.clear()
	for i in count:
		var l: Vector2i = locals[i]
		var c := origin + l
		cell.append(c)
		names[i] = name_at(seed_value, c)
		visited[i] = 1 if been.has(key(c)) else 0
		deal[i] = deal_at(seed_value, c)
		level[i] = mini(depth * LEVEL_STEP + l.x / 2, 255)
		pos[i] = Vector2(
			10.0 + l.x * 80.0 / (COLS - 1) + (_unit(seed_value, c.x, c.y, 8) - 0.5) * 9.0,
			8.0 + l.y * 44.0 / (ROWS - 1) + (_unit(seed_value, c.x, c.y, 9) - 0.5) * 7.0)
	start = index[first]
	# lanes: the ones it grew along, and some more between neighbours
	var lane := func(a: int, b: int) -> void:
		var pair := [mini(a, b), maxi(a, b)]
		if a != b and not links.has(pair):
			links.append(pair)
	for l: Vector2i in locals:
		lane.call(index[l], index[parent[l]])
	for l: Vector2i in locals:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if index.has(l + d) and rng.randf() < EXTRA_LANE:
				lane.call(index[l], index[l + d])
		# across a corner, if the other diagonal of that square is not there
		if index.has(l + Vector2i(1, 1)) and rng.randf() < DIAGONAL_LANE:
			var other := [index.get(l + Vector2i(1, 0), -1), index.get(l + Vector2i(0, 1), -1)]
			if not (int(other[0]) >= 0 and int(other[1]) >= 0 and links.has([mini(other[0], other[1]), maxi(other[0], other[1])])):
				lane.call(index[l], index[l + Vector2i(1, 1)])
	links.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	# the exits: the systems of the last column at its top and bottom
	exits = PackedByteArray([index[Vector2i(COLS - 1, top)], index[Vector2i(COLS - 1, bottom)]])
	var exit_cells: Array = [cell[exits[0]], cell[exits[1]]]
	beyond = beyond_kinds(seed_value, depth, exit_cells)
	# what each system holds
	var weights: Array = SYSTEM_WEIGHTS[ckind]
	for i in count:
		kind[i] = EMPTY if i == start else _roll(weights, rng)
	if ckind == C_STORM:
		for i in _patch(rng, rng.randi_range(STORM_BAND[0], STORM_BAND[1])):
			kind[i] = ION_STORM
	if ckind == C_DEAD:
		for i in count:
			if kind[i] == STATION:
				kind[i] = DERELICT
	# the flagship (the author's C3): far across its cluster, not at an exit
	goal = NO_GOAL
	locked = false
	if depth == FLAG_DEPTH:
		var best := -1
		for i in count:
			if exits.has(i) or i == start:
				continue
			if best < 0 or _lair_score(i, locals) > _lair_score(best, locals):
				best = i
		if best >= 0:
			kind[best] = FLAGSHIP
			goal = cell[best]
			locked = flagship
	# every cluster has a trader, and all but the dead zone a station; near the start of the first, close by
	if not kind.has(TRADER):
		_convert(TRADER, rng)
	if not kind.has(STATION) and ckind != C_DEAD:
		_convert(STATION, rng)
	if depth == 0 and _nearest(TRADER) > 2:
		var near := -1
		for i in count:
			if i != start and kind[i] != TRADER and kind[i] != STATION and hops(start, i) <= 2 and hops(start, i) > 0 and (near < 0 or hops(start, i) < hops(start, near)):
				near = i
		if near >= 0 and kind[near] != FLAGSHIP:
			kind[near] = TRADER
			deal[near] = DEAL_ARMS
	if not kind.has(DERELICT):
		_convert(DERELICT, rng)              # (and a wreck to search: quests ask for one)
	# a nebula over a few systems (never the start or the flagship's)
	if rng.randf() < FOG_CHANCE[ckind]:
		for i in _patch(rng, rng.randi_range(FOG_PATCH[0], FOG_PATCH[1])):
			if kind[i] != FLAGSHIP:
				fog[i] = 1
	# the inside of each system
	for i in count:
		var c: Vector2i = cell[i]
		rng.seed = _mix(seed_value, c.x, c.y, 7)
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
	here = maxi(cell.find(centre), 0) if cell.has(centre) else start


func _lair_score(i: int, locals: Array) -> int:
	## Where the flagship would rather wait: far from the start, far across, not in a storm belt's band.
	return hops(start, i) * 10 + (locals[i] as Vector2i).x - (100 if kind[i] == ION_STORM else 0)


static func _roll(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for w: int in weights:
		total += w
	var roll := rng.randi_range(1, total)
	for k in weights.size():
		roll -= int(weights[k])
		if roll <= 0:
			return k
	return EMPTY


func _patch(rng: RandomNumberGenerator, size: int) -> Array:
	## A few systems next to one another along lanes (through the start, but never it).
	var from := rng.randi_range(0, count - 1)
	if from == start:
		from = (from + 1 + rng.randi_range(0, count - 2)) % count
	var out := [from]
	var near := [from]                   # what the patch has reached, the start included
	while out.size() < size:
		var edge: Array = []
		for c: int in near:
			for n in neighbours(c):
				if not near.has(n) and not edge.has(n):
					edge.append(n)
		if edge.is_empty():
			break
		var pick: int = edge[rng.randi_range(0, edge.size() - 1)]
		near.append(pick)
		if pick != start:
			out.append(pick)
	return out


func _convert(to: int, rng: RandomNumberGenerator) -> void:
	## One quiet system (failing that meteors, a derelict, a storm, one of several traders or stations) becomes one of that kind.
	var pool: Array = []
	for pass_kinds: Array in [[EMPTY], [METEORS, DERELICT if to != DERELICT else METEORS], [ION_STORM]]:
		for i in count:
			if i != start and pass_kinds.has(kind[i]):
				pool.append(i)
		if not pool.is_empty():
			break
	if pool.is_empty():                      # (a trade world all traders and stations: one of many)
		for i in count:
			if i != start and kind[i] != to and (kind[i] == TRADER or kind[i] == STATION) and kind.count(kind[i]) > 1:
				pool.append(i)
	if not pool.is_empty():
		kind[pool[rng.randi_range(0, pool.size() - 1)]] = to


func _nearest(of_kind: int) -> int:
	var best := 999
	for i in count:
		if kind[i] == of_kind:
			best = mini(best, hops(start, i))
	return best


static func places_of(seed_value: int, at: Vector2i, of_kind: int, of_ckind: int, arrive: Vector2, main: Vector2, is_start: bool) -> Array:
	## (v64) The places inside a system besides its main thing: [P_*, where] each.
	## None at the first cluster's start, at the flagship's or at a station.
	if is_start or of_kind == FLAGSHIP or of_kind == STATION:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(seed_value, at.x, at.y, 400)
	var roll := rng.randf()
	var n := 0 if roll < 0.3 else (1 if roll < 0.7 else (2 if roll < 0.92 else 3))
	if of_ckind == C_DEAD:
		n += 1
	var weights := PLACE_WEIGHTS.duplicate()
	if of_kind == DERELICT:
		weights[P_WRECK] = 0                 # (one abandoned ship alongside at a time)
	if of_ckind == C_DEAD:
		weights[P_WRECK] *= 2
		weights[P_BATTLEFIELD] *= 2
	if of_ckind == C_PIRATE:
		weights[P_AMBUSH] *= 3
	if of_ckind == C_TRADE:
		weights[P_AMBUSH] = 2
	var out: Array = []
	for k in n:
		var p := _roll(weights, rng)
		if p == P_WRECK or p == P_AMBUSH:
			weights[p] = 0                   # one of each at most
		var where := Vector2.ZERO
		for tries in 20:
			where = Vector2(rng.randf_range(15.0, SPAN - 15.0), rng.randf_range(15.0, SPAN - 15.0))
			var ok := where.distance_to(main) > 30.0 and where.distance_to(arrive) > (AMBUSH_REACH + 25.0 if p == P_AMBUSH else 25.0)
			for o: Array in out:
				ok = ok and where.distance_to(o[1]) > 20.0
			if ok:
				break
		out.append([p, where.round()])
	return out


func places(seed_value: int, id: int) -> Array:
	## (v64) The places inside that system of this cluster.
	return places_of(seed_value, cell[id], kind[id], ckind, entry[id], spot[id], depth == 0 and id == start)


func index_of(at: Vector2i) -> int:
	## That cell's system in this cluster, or -1.
	return cell.find(at)


func linked(a: int, b: int) -> bool:
	return links.has([mini(a, b), maxi(a, b)])


func neighbours(of: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for l: Array in links:
		if int(l[0]) == of:
			out.append(int(l[1]))
		elif int(l[1]) == of:
			out.append(int(l[0]))
	return out


func hops(a: int, b: int) -> int:
	## (v64) Jumps along lanes from one system to another (-1 if either is not here).
	if a < 0 or b < 0 or a >= count or b >= count:
		return -1
	return distances(a)[b]


func distances(from: int) -> PackedInt32Array:
	## Jumps along lanes from `from` to every system of the cluster.
	var d := PackedInt32Array()
	d.resize(count)
	d.fill(-1)
	if from < 0 or from >= count:
		return d
	d[from] = 0
	var todo: Array[int] = [from]
	while not todo.is_empty():
		var c: int = todo.pop_front()
		for n in neighbours(c):
			if d[n] < 0:
				d[n] = d[c] + 1
				todo.append(n)
	return d


func hops_between(a: Vector2i, b: Vector2i) -> int:
	## Jumps along lanes between two cells of space in this cluster (-1 if one is not in it).
	return hops(index_of(a), index_of(b))


func exit_of(id: int) -> int:
	## Which exit that system is (0, 1), or -1.
	var k := exits.find(id)
	return k


func within_reach(id: int, at: Vector2) -> bool:
	## Is a ship at this place inside the sector's meteor stream or ion storm, or close enough to dock?
	return reach[id] > 0 and at.distance_to(spot[id]) <= reach[id]


func far_from_start(id: int) -> int:
	## How dangerous the system is: (v64) LEVEL_STEP for every cluster behind, and a
	## little more across the cluster (where jumps from the start used to count).
	return level[id] if id >= 0 and id < level.size() else 0


func jumps_to_goal(id: int) -> int:
	## (v57) Jumps from that system to the flagship's (v64: along lanes; -1 if it is not in this cluster).
	if goal == NO_GOAL:
		return -1
	return hops(id, index_of(goal))


func describe(id: int) -> String:
	if id == EXIT_JUMP:
		var k := exit_of(here)
		return "соседнее скопление «%s»" % CLUSTER_NAMES[beyond[k]] if k >= 0 else "соседнее скопление"
	if kind[id] == TRADER and deal.size() > id:
		return "«%s», %s: %s" % [names[id], KIND_NAMES[kind[id]], DEAL_NAMES[deal[id]]]     # (v58)
	return "«%s», %s" % [names[id], KIND_NAMES[kind[id]]]


func pack() -> PackedByteArray:
	## For the network: u8 count, u8 here; per sector s16 cell x, s16 cell y, u8 kind, u8 visited,
	## u8 x, u8 y on the chart, u8 spot x, u8 spot y, u8 reach, u8 entry x, u8 entry y,
	## u8 name length, name; u8 links; pairs u8, u8; (v57) s16 goal x, s16 goal y; (v58) per sector u8 deal;
	## (v64) u8 depth, u8 kind of cluster, u8 start, u8 locked, u8 exits, per exit u8 system, u8 kind beyond;
	## per sector u8 level, u8 fog; u8 clusters behind, their kinds.
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
	out.append_array(PackedByteArray([mini(depth, 255), ckind, start, 1 if locked else 0, exits.size()]))
	for k in exits.size():
		out.append(exits[k])
		out.append(beyond[k])
	out.append_array(level)
	out.append_array(fog)
	out.append(mini(road.size(), 255))
	out.append_array(road.slice(maxi(road.size() - 255, 0)))
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
	deal = data.slice(at, at + count)
	at += count
	depth = data[at]
	ckind = data[at + 1]
	start = data[at + 2]
	locked = data[at + 3] != 0
	var n_exits := data[at + 4]
	at += 5
	exits = PackedByteArray()
	beyond = PackedByteArray()
	for k in n_exits:
		exits.append(data[at])
		beyond.append(data[at + 1])
		at += 2
	level = data.slice(at, at + count)
	at += count
	fog = data.slice(at, at + count)
	at += count
	var behind := data[at]
	road = data.slice(at + 1, at + 1 + behind)
