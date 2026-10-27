extends RefCounted
## (v64, the author's cluster answers C1..C19 and my V1..V11 picks) The road of
## clusters, the places inside a system, and the pirate hunters. Server only.
##
## The ship is in one cluster at a time (Sectors.build): `depth` clusters lie
## behind it, and it came in at `entry`. A long jump from an exit system (see
## Navigation) brings it into the next cluster, of the kind that exit showed;
## there is no way back into a cluster left behind (the author's C10). The
## flagship's cluster (Sectors.FLAG_DEPTH) keeps its exits shut until the
## flagship is beaten (my V1).
##
## Places (Sectors.places_of): most are hidden until the ship comes within its
## sensors' reach (SCAN, less inside a nebula); an ambush is seen from afar.
## Flying onto one takes it (debris, a container, bodies, a battlefield); an
## abandoned ship comes alongside as a derelict does while the ship is near it;
## coming within AMBUSH_REACH of an ambush brings its pirate ship out.
##
## Hunters (the author's C15, my V6..V8): pirate ships seen on the chart. The
## first comes HUNTER_FIRST seconds after the ship enters a cluster, then one
## more every HUNTER_EVERY, at most HUNTER_MOST at a time. Every HUNTER_STEP
## seconds each moves one lane toward our ship, never into a system with a
## supply station; inside a nebula they lose the trail and wander. Meeting one
## in a system is a fight with a pirate ship a cluster harder than the rest
## (HUNTER_LEVEL), with the hunter's temper. Beaten (or paid off, or fled) it is
## gone; jump away from it and it follows on.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Gear := preload("res://src/shared/gear.gd")
const Items := preload("res://src/shared/items.gd")
const Player := preload("res://src/server/player.gd")

const SCAN: Array[float] = [35.0, 50.0, 70.0]   # how far the sensors find a hidden place, by their tier
const SCAN_FOG := 15.0               # inside a nebula
const LANES_SEEN: Array[int] = [1, 2, 3]   # (the author's C7) how many lanes away the chart shows what a system holds, by tier
const HUNTER_FIRST := 375.0          # seconds in a cluster before the first hunter comes (v89, the author: 1.25 times fewer; was 300)
const HUNTER_EVERY := 300.0          # and then one more this often (v89: was 240)
const HUNTER_MOST := 3               # at most this many at a time...
const HUNTER_MOST_BIG := 4           # ... with a crew of BIG_CREW and more
const HUNTER_MOST_FLAG := 2          # ... in the flagship's cluster (it is the pressure there)
const BIG_CREW := 5
const HUNTER_STEP := 75.0            # each moves one lane this often
const HUNTER_SLOWER := 0.5           # (the author's pick, 2026-10-19) each time we escape one, its step is this much of HUNTER_STEP longer
const ESCAPE_SOONER := 60.0          # (v67, the author's O3) jumping out of a fight brings the next hunter this much sooner
const HUNTER_WARN := 20.0            # coming into our system, it is seen this long before it comes out
const HUNTER_COME := 6.0             # we jump into its system: it comes out this much later
const HUNTER_BREATHER := 45.0        # (v69, the author's note) after a fight, a hunter waiting in our system comes out no sooner than this
const SHELL_SECONDS := 8             # (v69) a hunter kept off by our people outside shells the hull this often...
const SHELL_HULL := 4                # ... this hard
const HUNTER_LEVEL := 3              # a hunter is this many steps of danger harder than the system it meets us in
const PACE: Array[float] = [1.0, 0.7, 1.4, 1.0, 1.0]   # per kind of cluster: how long they take to come (pirates sooner, traders later)
const MODE_PACE: Array[float] = [2.0, 1.0, 0.75]       # per mode (easy, normal, hard)
const MINE_SHARE := 0.2              # (my V4) a container that is a pirate mine
const MINE_HULL := 12
const SURVIVOR_SHARE := 0.25         # (my V4) bodies with a survivor among them
const CONTAINER_GEAR := 0.3          # a container that holds a crate of ship gear
const CONTAINER_THINGS: Array[int] = [Net.ITEM_PATCH, Net.ITEM_PART, Net.ITEM_MEDPATCH, Net.ITEM_MAG, Net.ITEM_FUEL, Net.ITEM_FOOD,
	Net.ITEM_SHELL, Net.ITEM_ROCKET, Net.ITEM_PROBE, Net.ITEM_BOARD]
const POCKET_THINGS: Array[int] = [Net.ITEM_MEDPATCH, Net.ITEM_MAG, Net.ITEM_FLASHLIGHT, Net.ITEM_RADIO, Net.ITEM_FOOD, Net.ITEM_PATCH]
const BATTLEFIELD_GUN := 0.3         # a battlefield leaves a damaged ship gun this often
const ANOMALY_SECONDS := 30          # (v67) at a holomap, ship holding still, to scan an anomaly
const ORE_SECONDS := 12.0            # (v67) an asteroid gives a piece of ore this often to one of ours outside
const ORE_MIN := 4
const ORE_MAX := 8
const GAS_MIN := 60 * Net.TICK_HZ    # (v67) a gas cloud gives fuel for this many ticks with somebody at the engine...
const GAS_MAX := 120 * Net.TICK_HZ
const GAS_PER_TICK := 2.5 / Net.TICK_HZ   # ... this much a tick (150..300 units in all)
const WORK_START: Array[String] = [
	"Корабль у аномалии. Пока он стоит, её можно изучить с голокарты (около 30 с).",
	"Корабль у астероида. Пока он стоит, из его рудных жил можно добывать руду: выйдите в скафандре.",
	"Корабль в газовом облаке. Пока он стоит и кто-то у двигателя, топливозаборник наполняет бак.",
]
const NOTES: Array[String] = [
	"В кармане записка: «Если кто найдёт — мы шли к выходу из скопления, охотники сели на хвост».",
	"Бортовой жетон и фотография. Имени не разобрать.",
	"На скафандре нацарапано: «Не верь контейнерам с маяком».",
	"Пустой баллон кислорода: они ждали помощи до конца.",
]

var server: GameServer
var depth := 0                       # clusters behind us
var entry := Vector2i.ZERO           # where the ship came into this cluster
var history := PackedByteArray()     # the kinds of the clusters left behind
var ticks_here := 0                  # ticks since the ship came into this cluster
var hunters: Array = []              # each {"at": system, "move": ticks, "coming": tick or -1}
var next_hunter := 0                 # ticks in the cluster at which the next hunter comes
var found := {}                      # Sectors.key * 8 + place -> true: places the sensors have found
var taken := {}                      # the same: places taken (an abandoned ship: one that has come alongside)
var auto := true                     # (tests) false: no hunters come by themselves
var _fight := {}                     # the hunter we fight: {"at", "id" (the pirate ship's id)}
var busy_tick := -1000000            # (v69) the last tick a pirate ship was alongside: the breather counts from it
var breather := HUNTER_BREATHER      # (tests set 0)
var _shelled := -1                   # the tick a hunter last shelled us from range (see _meet)
var work := {}                       # (v67) the same: what an anomaly, asteroid or gas cloud still has to give
var hulks := {}                      # (v69) Sectors.key of a system -> pirate ships wrecked there: each {"pos", "layout", "name",
                                     # "id", "things", "air", "outcome", "party", "boarded", "design"}; see Derelict.hulk_*
var _haul: Array = []                # (v67) what the place being taken gives, before it floats out
var _here_places: Array = []         # the places of the ship's system: [kind, where]
var _places_for := -1                # the system they are for
var _last_system := -1
var _dirty := true
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	depth = 0
	entry = Vector2i.ZERO
	history = PackedByteArray()
	hunters = []
	found = {}
	taken = {}
	work = {}
	hulks = {}
	_fight = {}
	_rng.randomize()
	_restart_clock()


func _restart_clock() -> void:
	ticks_here = 0
	next_hunter = roundi(HUNTER_FIRST * _pace() * Net.TICK_HZ)
	_places_for = -1
	_last_system = -1
	_dirty = true


func _pace() -> float:
	var k: int = server.sectors.ckind if server.sectors.count > 0 else Sectors.C_FRONTIER
	return PACE[k] * MODE_PACE[clampi(server.mode, 0, 2)]


func crew() -> int:
	## How many people play (bots and robots not counted), at least one.
	var n := 0
	for p: Player in server.players:
		if p != null and not p.bot and not p.pirate and not p.ally and not p.corpse:
			n += 1
	return maxi(n, 1)


func build(centre: Vector2i) -> void:
	## The cluster we are in, made again (on starting, loading, coming in) with the ship at `centre`.
	var s: Sectors = server.sectors
	s.build(server.space_seed, centre, server.been, depth, entry, crew(), not server.won)
	s.road = history
	_places_for = -1
	_dirty = true


func next_cluster(exit_k: int) -> void:
	## (Navigation) The long jump out by that exit has come through: into the next cluster.
	var s: Sectors = server.sectors
	var gone_kind := s.ckind
	var into: int = s.beyond[exit_k]
	entry = Sectors.next_entry(s.cell[s.exits[exit_k]])
	depth += 1
	history.append(gone_kind)
	hunters = []
	hulks = {}                               # (the wrecks stay behind with the cluster)
	_fight = {}
	server.been[Sectors.key(entry)] = true
	build(entry)
	server.ship.sector = s.here              # (before the story looks: its locker news reads the system's kind)
	_restart_clock()
	server.story.left_cluster()
	server.chat.say("Корабль вышел в скопление «%s» (%d-е на пути): %s.%s" % [Sectors.CLUSTER_NAMES[into], depth + 1,
		Sectors.CLUSTER_ABOUT[into], _flagship_word()])


func _flagship_word() -> String:
	if server.won:
		return ""
	var left := Sectors.FLAG_DEPTH - depth
	if left == 0:
		return " Здесь логово флагмана пиратов: выходы из скопления откроются, только когда он будет разбит."
	if left > 0:
		return " До скопления флагмана: %d." % left
	return ""


func can_leave() -> String:
	## Why the long jump out of the cluster cannot be set from here ("" = it can).
	var s: Sectors = server.sectors
	if s.exit_of(server.ship.sector) < 0:
		return "Отсюда нет выхода из скопления: долгий прыжок делается из выходного сектора (стрелки на карте)."
	if s.locked and not server.won:
		return "Глушилка флагмана пиратов держит выходы из скопления: пока он не разбит, отсюда не уйти."
	if not server.ship.can_jump(true):
		return "Для долгого прыжка нужно %d единиц топлива в баке." % server.outfit.jump_fuel(true)
	return ""


# --------------------------------------------------------------- the tick

func tick() -> void:
	if server.over != Net.OVER_NONE or server.sectors.count == 0:
		return
	ticks_here += 1
	var sys: int = server.ship.sector
	if sys != _last_system:
		_last_system = sys
		_arrived(sys)
	if _places_for != sys:
		_places_for = sys
		_here_places = server.sectors.places(server.space_seed, sys)
		_dirty = true
	_places_tick()
	_watch_fight()
	if server.tick % Net.TICK_HZ == 0:
		_hunters_second()
	if _dirty or server.tick % (2 * Net.TICK_HZ) == 0:
		_dirty = false
		var pkt := packet()
		if pkt != _told:
			_told = pkt
			server.to_all(pkt)


func _arrived(sys: int) -> void:
	## The ship came into a system: a hunter waiting there comes out soon.
	for h: Dictionary in hunters:
		h["coming"] = -1
		if int(h["at"]) == sys:
			h["coming"] = server.tick + roundi(HUNTER_COME * Net.TICK_HZ)
			server.chat.alarm("Здесь ждёт пиратский охотник! Он выйдет на нас через %d с." % int(HUNTER_COME))
	_dirty = true


func _key(i: int) -> int:
	return Sectors.key(server.sectors.cell[server.ship.sector]) * 8 + i


func in_fog() -> bool:
	return server.sectors.count > 0 and server.sectors.fog[server.ship.sector] == 1


func scan_range() -> float:
	if in_fog():
		return SCAN_FOG
	return SCAN[clampi(server.outfit.tier(Gear.SYS_SENSORS), 1, 3) - 1]


func _places_tick() -> void:
	var at: Vector2 = server.ship.pos
	var scan := scan_range()
	for i in _here_places.size():
		var pl: Array = _here_places[i]
		var k := _key(i)
		var kind: int = pl[0]
		var d: float = at.distance_to(pl[1])
		if not found.has(k) and (kind == Sectors.P_AMBUSH or d <= scan):
			found[k] = true
			_dirty = true
			if kind != Sectors.P_AMBUSH:
				server.chat.say("Сенсоры нашли в секторе: %s (метка на пульте управления)." % Sectors.PLACE_NAMES[kind])
			else:
				server.chat.say("Сенсоры видят сигнатуру корабля, затаившегося в секторе: похоже на засаду пиратов. Её можно облететь.")
		if taken.has(k) or kind == Sectors.P_WRECK:
			continue
		if kind == Sectors.P_AMBUSH:
			if d <= Sectors.AMBUSH_REACH and server.pirates.aboard() == 0 and server.derelict.pirates_can_come():
				taken[k] = true
				_dirty = true
				server.chat.say("Засада! Пиратский корабль выходит из тени.")
				server.gunnery.goal_next = true          # (v68) it may come with a goal
				server.derelict.pirates_come(server.director._party(), true)
		elif kind >= Sectors.P_ANOMALY:
			_work_tick(i, kind, d)
		elif d <= Sectors.PLACE_REACH:
			taken[k] = true
			_dirty = true
			_take(kind)


func at_wreck() -> bool:
	## (Derelict) Is the ship close to an abandoned ship among this system's places? (It comes alongside then.)
	for i in _here_places.size():
		var pl: Array = _here_places[i]
		if int(pl[0]) == Sectors.P_WRECK and server.ship.pos.distance_to(pl[1]) <= Sectors.WRECK_REACH:
			if not taken.has(_key(i)):
				taken[_key(i)] = true
				_dirty = true
			return true
	return false


func _take(kind: int) -> void:
	## (v67, the author's R2) What the ship picks up at a place floats out by one of our
	## airlocks for the crew to fetch in suits (Salvage.float_out); a tractor beam pulls it in.
	var lv: int = server.sectors.far_from_start(server.ship.sector)
	var got := PackedStringArray()
	_haul = []
	match kind:
		Sectors.P_DEBRIS:
			got.append(_debris())
		Sectors.P_CONTAINER:
			if _rng.randf() < MINE_SHARE:
				server.chat.say("Контейнер оказался пиратской миной! Взрыв у самого борта.")
				server.systems.breach_random()
				server.crew.hull_hit(MINE_HULL)
				return
			if _rng.randf() < CONTAINER_GEAR:
				_haul.append(server.outfit.loot(lv, _rng))
				got.append("ящик корабельного снаряжения")
			for i in _rng.randi_range(2, 3):
				got.append(_thing(CONTAINER_THINGS))
		Sectors.P_BODIES:
			got.append(_bodies())
		Sectors.P_BATTLEFIELD:
			got.append(_debris())
			got.append(_debris())
			got.append(_bodies())
			_haul.append(Net.ITEM_GUN_PARTS + _rng.randi_range(0, Weapons.KINDS - 1))
			got.append("детали орудия")
			if _rng.randf() < BATTLEFIELD_GUN:
				# (the author's B2: guns come as a rare event) a battlefield is one
				var t: int = Weapons.tiers_for(lv, 1, _rng)[0]
				var choice: Array = Weapons.OURS.filter(func(w: int) -> bool: return Weapons.tier(w) == t and not Weapons.unique(w) and w != Weapons.GUARD)
				if not choice.is_empty():
					_haul.append(Weapons.item_of(choice[_rng.randi_range(0, choice.size() - 1)], 0, true))
					got.append("повреждённое корабельное орудие")
	var what := ", ".join(got).strip_edges()
	if _haul.is_empty():
		server.chat.say("Ничего ценного.")
		return
	var out: int = server.salvage.float_out(_haul)
	if out == _haul.size():
		server.chat.say("Найдено: %s. Всё плавает за бортом у шлюза: выйдите в скафандре и заберите (или включите захватный луч). После прыжка оно останется здесь." % what)
	else:
		server.chat.say("Найдено: %s. Часть плавает за бортом у шлюза, остальное подобрано в шкаф снабжения." % what)
	server.supplies.tell_store()


func _debris() -> String:
	## (v67, the author's M1: no money lying about) scrap and maybe a spare part
	var scrap := _rng.randi_range(2, 4)
	for i in scrap:
		_haul.append(Net.ITEM_SCRAP)
	var part := _rng.randf() < 0.5
	if part:
		_haul.append(Net.ITEM_PART)
	return "лом ×%d%s" % [scrap, " и запчасть" if part else ""]


func _bodies() -> String:
	var out := _thing(POCKET_THINGS)
	if _rng.randf() < SURVIVOR_SHARE and server.reserve < Net.RESERVE_MAX:
		server.reserve += 1
		server.crew.tell_campaign()
		server.chat.say("Среди тел один ещё дышит! Выживший пришёл в себя и просится в экипаж: резерв +1.")
	else:
		server.chat.say(NOTES[_rng.randi_range(0, NOTES.size() - 1)])
	return out


func _thing(pool: Array[int]) -> String:
	var item: int = pool[_rng.randi_range(0, pool.size() - 1)]
	_haul.append(item)
	return Items.name_of(item)


func _store(item: int, n: int) -> void:
	server.ship.store[item] = maxi(int(server.ship.store.get(item, 0)) + n, 0)


# --------------------------------------------------------------- work at a place (v67, the author's R1)

func _work_tick(i: int, kind: int, d: float) -> void:
	## An anomaly, an asteroid or a gas cloud pays only while the ship holds still near it
	## and somebody works: at a holomap, outside in a suit, or at the engine.
	if d > Sectors.WORK_REACH or server.ship.moving or server.ship.jump_to != Net.NO_SECTOR:
		return
	var k := _key(i)
	if not work.has(k):
		var amount := 0
		match kind:
			Sectors.P_ANOMALY: amount = ANOMALY_SECONDS * Net.TICK_HZ
			Sectors.P_ASTEROID: amount = _rng.randi_range(ORE_MIN, ORE_MAX)
			Sectors.P_GAS: amount = _rng.randi_range(GAS_MIN, GAS_MAX)
		work[k] = amount
		server.chat.say(WORK_START[kind - Sectors.P_ANOMALY])
	var left: int = work[k]
	match kind:
		Sectors.P_ANOMALY:
			if _someone_at(server.map.holo) == null:
				return
			left -= 1
			if left <= 0:
				var n := _rng.randi_range(1, 2)
				_store(Net.ITEM_DATA, n)
				server.supplies.tell_store()
				server.chat.say("Аномалия изучена: данные сканирования ×%d в шкафу снабжения. Торговцы их покупают." % n)
		Sectors.P_ASTEROID:
			if server.derelict.here and server.derelict.kind == Net.OTHER_ROCK:
				return                       # (v81) the rock is alongside: ore is dug out of its veins (Salvage.mine)
			if server.tick % roundi(ORE_SECONDS * Net.TICK_HZ) != 0:
				return
			var miner := _outside_one()
			if miner == null:
				return
			left -= 1
			if not server.put_on_floor(miner.st.y * server.map.width + miner.st.x, Net.ITEM_ORE):
				return
			server.chat.tell(miner, "От астероида откололся кусок руды: он у вас под ногами. Осталось примерно %d." % left)
			if left <= 0:
				server.chat.say("Астероид выработан.")
		Sectors.P_GAS:
			var at_engine := _someone_at(server.map.engine)
			if at_engine == null or server.ship.tank >= Net.FUEL_MAX or server.engine_down():
				return
			left -= 1
			server.ship.tank = minf(server.ship.tank + GAS_PER_TICK, Net.FUEL_MAX)
			if server.tick % (5 * Net.TICK_HZ) == 0:
				server.supplies.tell_store()
			if left <= 0:
				server.supplies.tell_store()
				server.chat.say("Газовое облако выбрано: топлива в баке %d." % floori(server.ship.tank))
	work[k] = left
	if left <= 0:
		taken[k] = true
		_dirty = true


func _asteroid_here() -> int:
	## (v81) The asteroid place (its number among this system's places) the ship holds still by, with
	## ore left, or -1.
	if server.ship.moving or server.ship.jump_to != Net.NO_SECTOR:
		return -1
	for i in _here_places.size():
		var pl: Array = _here_places[i]
		if int(pl[0]) == Sectors.P_ASTEROID and not taken.has(_key(i)) and server.ship.pos.distance_to(pl[1]) <= Sectors.WORK_REACH:
			return i
	return -1


func at_asteroid() -> bool:
	## (v81, Derelict) Should the asteroid lie alongside now?
	return _asteroid_here() >= 0


func asteroid_key() -> int:
	## Which asteroid it is (picks its drawing), the same every time.
	var i := _asteroid_here()
	return absi(_key(i)) if i >= 0 else 0


func ore_left() -> int:
	var i := _asteroid_here()
	if i < 0:
		return 0
	var k := _key(i)
	if not work.has(k):
		work[k] = _rng.randi_range(ORE_MIN, ORE_MAX)
	return int(work[k])


func mined() -> int:
	## (v81, Salvage.mine) A piece of ore was dug out of the asteroid alongside: how much is left.
	var i := _asteroid_here()
	if i < 0:
		return 0
	var left := ore_left() - 1
	var k := _key(i)
	work[k] = left
	if left <= 0:
		taken[k] = true
		_dirty = true
		server.chat.say("Астероид выработан.")
	return left


func _someone_at(cells: Dictionary) -> Player:
	for p: Player in server.players:
		if p != null and not p.pirate and not p.corpse and server.systems.at_console(p, cells):
			return p
	return null


func _outside_one() -> Player:
	for p: Player in server.players:
		if p != null and not p.pirate and not p.corpse and p.cond == Net.COND_OK and server.map.floats(p.st.x, p.st.y):
			return p
	return null


# --------------------------------------------------------------- hunters

func _most() -> int:
	if server.sectors.depth == Sectors.FLAG_DEPTH and not server.won:
		return HUNTER_MOST_FLAG
	return HUNTER_MOST_BIG if crew() >= BIG_CREW else HUNTER_MOST


func _hunters_second() -> void:
	var s: Sectors = server.sectors
	var ours: int = server.ship.sector
	if auto and server.director.auto and ticks_here >= next_hunter and not server.director.quiet():
		next_hunter = ticks_here + roundi(HUNTER_EVERY * _pace() * Net.TICK_HZ)
		if hunters.size() + (1 if not _fight.is_empty() else 0) < _most():
			spawn_hunter()
	var d := s.distances(ours)
	# (v73, the author's note: "another hunter waits" every second) a wreck left
	# alongside is no fight: only a live pirate ship keeps the breather from starting
	if server.gunnery.fighting() or (server.derelict.here and server.derelict.kind == Net.OTHER_PIRATE and not server.derelict.wreck):
		busy_tick = server.tick
	for h: Dictionary in hunters:
		var at: int = h["at"]
		if at == ours:
			_meet(h)
			continue
		h["move"] = int(h["move"]) + Net.TICK_HZ
		if int(h["move"]) < roundi(HUNTER_STEP * (1.0 + HUNTER_SLOWER * int(h.get("escaped", 0))) * Net.TICK_HZ):
			continue
		h["move"] = 0
		var ways: Array = []
		for n in s.neighbours(at):
			if s.kind[n] != Sectors.STATION:
				ways.append(n)
		if ways.is_empty():
			continue
		var pick: int = ways[_rng.randi_range(0, ways.size() - 1)]
		if not in_fog():
			for n: int in ways:
				if d[n] >= 0 and d[n] < d[pick]:
					pick = n
			if d[pick] >= d[at]:
				continue                     # (no way closer that is not a station: it waits)
		h["at"] = pick
		_dirty = true
		if pick == ours:
			h["coming"] = server.tick + roundi(HUNTER_WARN * Net.TICK_HZ)
			server.chat.alarm("Пиратский охотник вошёл в наш сектор! Он выйдет на нас через %d с. Успеем прыгнуть, или будем драться." % int(HUNTER_WARN))


func spawn_hunter() -> bool:
	## A hunter comes into the cluster, as far from us as it can (never into a station's system).
	var s: Sectors = server.sectors
	var d := s.distances(server.ship.sector)
	var best := -1
	for i in s.count:
		if i == server.ship.sector or s.kind[i] == Sectors.STATION or s.kind[i] == Sectors.FLAGSHIP:
			continue
		if best < 0 or d[i] > d[best]:
			best = i
	if best < 0:
		return false
	hunters.append({"at": best, "move": 0, "coming": -1})
	_dirty = true
	server.chat.say("Сенсоры дальнего обзора: в скопление вошёл пиратский охотник (%s). Он идёт по нашему следу." % s.names[best] if not in_fog() else
		"Сквозь туманность пробился сигнал: в скопление вошёл пиратский охотник. Здесь он нас не видит.")
	return true


func _meet(h: Dictionary) -> void:
	if int(h["coming"]) < 0:
		h["coming"] = server.tick + roundi(HUNTER_COME * Net.TICK_HZ)
	if not _fight.is_empty():
		return
	var after := busy_tick + roundi(breather * Net.TICK_HZ)
	if server.tick < after and int(h["coming"]) < after:
		# (v69, the author's note: "it retreats and at once attacks again with full hull")
		# another hunter that waited in our system gives the crew a breather first
		h["coming"] = after
		_dirty = true
		if not h.get("told", false):
			h["told"] = true                 # (v73) said once for each hunter
			server.chat.say("Ещё один охотник поджидает в этом секторе: он выйдет на нас через %d с." % ceili((after - server.tick) / float(Net.TICK_HZ)))
		return
	if server.tick < int(h["coming"]):
		return
	var der = server.derelict
	if server.pirates.aboard() > 0 or server.gunnery.fighting():
		h["coming"] = server.tick + Net.TICK_HZ
		return
	if not der.pirates_can_come():
		# (v69, the author's note: docked, the hunter never came) a derelict alongside is
		# let go; while anybody of ours is outside, it shells the hull from range instead
		if not der.cast_off():
			h["coming"] = server.tick + Net.TICK_HZ
			if der.someone_outside() and server.tick - _shelled >= SHELL_SECONDS * Net.TICK_HZ:
				_shelled = server.tick
				server.crew.hull_hit(SHELL_HULL)
				server.chat.say("Охотник бьёт по нам издалека! Пока кто-то снаружи, мы не можем принять бой: всем на борт.")
		return
	var design: Dictionary = server.shipyard.make(server.director._party(), true, der._pirate_spots(), HUNTER_LEVEL, Net.TEMPER_HUNTER)
	if design.is_empty():
		return
	design["name"] = "Охотник «%s»" % str(design["name"]).get_slice("«", 1).trim_suffix("»")
	if der.pirates_come(server.director._party(), true, design):
		hunters.erase(h)
		_fight = {"at": server.ship.sector, "id": der.ship.id, "escaped": int(h.get("escaped", 0))}
		_dirty = true


func _watch_fight() -> void:
	if _fight.is_empty():
		return
	var der = server.derelict
	if der.ship != null and der.ship.id == int(_fight["id"]):
		return
	if server.ship.sector != int(_fight["at"]):
		hunters.append({"at": int(_fight["at"]), "move": 0, "coming": -1, "escaped": int(_fight.get("escaped", 0)) + 1})
		server.chat.say("Охотник остался позади, но он пойдёт по нашему следу.")
	_fight = {}
	_dirty = true


func escaped() -> void:
	## (v67, the author's O3) We jumped out of a fight: the next hunter comes sooner.
	next_hunter = maxi(ticks_here, next_hunter - roundi(ESCAPE_SOONER * Net.TICK_HZ))
	_dirty = true


func pirates_beaten() -> void:
	## (Story) The pirate ship alongside is wrecked, taken, broken off or paid us off: a hunter among them is gone.
	if not _fight.is_empty():
		_fight["at"] = server.ship.sector


func seconds_to_hunter() -> int:
	if not auto or not server.director.auto or hunters.size() >= _most():
		return 65535
	return maxi(next_hunter - ticks_here, 0) / Net.TICK_HZ


func admin_next(exit_k: int) -> void:
	## (admin) Into the next cluster by that exit at once, as if the long jump had come through.
	if server.ship.jump_to != Net.NO_SECTOR or server.derelict.here or server.sectors.exits.size() <= exit_k:
		return
	next_cluster(exit_k)
	server.navigation.landed()


func reveal_here() -> void:
	## (admin) The sensors find every place in this system.
	for i in _here_places.size():
		found[_key(i)] = true
	_dirty = true


# --------------------------------------------------------------- the chart

func known() -> PackedByteArray:
	## (the author's C7) What the chart shows the kind of: where we have been, what lies
	## within the sensors' lanes, traders and stations (they call out), the flagship.
	## Inside a nebula nothing but where we have been; a system inside one shows only once visited.
	var s: Sectors = server.sectors
	var out := PackedByteArray()
	out.resize(s.count)
	var d := s.distances(server.ship.sector)
	var lanes: int = LANES_SEEN[clampi(server.outfit.tier(Gear.SYS_SENSORS), 1, 3) - 1]
	var blind := in_fog()
	for i in s.count:
		var k := s.visited[i] == 1 or i == server.ship.sector
		if not blind and s.fog[i] == 0:
			k = k or (d[i] >= 0 and d[i] <= lanes) or s.kind[i] == Sectors.TRADER or s.kind[i] == Sectors.STATION or s.kind[i] == Sectors.FLAGSHIP
		out[i] = 1 if k else 0
	return out


func packet() -> PackedByteArray:
	## Net.S_ROAD.
	var out := PackedByteArray([Net.S_ROAD, 1 if in_fog() else 0, 0, 0])
	out.encode_u16(2, seconds_to_hunter())
	var seen: Array = [] if in_fog() else hunters
	out.append(seen.size())
	for h: Dictionary in seen:
		out.append(int(h["at"]))
		out.append(1 if int(h["coming"]) >= 0 else 0)
	var k := known()
	out.append(k.size())
	out.append_array(k)
	var shown: Array = []
	for i in _here_places.size():
		if found.has(_key(i)):
			shown.append(i)
	var wrecks: Array = hulks_here()
	out.append(shown.size() + wrecks.size())
	for i: int in shown:
		var pl: Array = _here_places[i]
		out.append(int(pl[0]))
		out.append(roundi((pl[1] as Vector2).x))
		out.append(roundi((pl[1] as Vector2).y))
		out.append(1 if taken.has(_key(i)) else 0)
	for h: Dictionary in wrecks:
		out.append(Sectors.P_HULK)
		out.append(roundi((h["pos"] as Vector2).x))
		out.append(roundi((h["pos"] as Vector2).y))
		out.append(0)
	return out


# --------------------------------------------------------------- (v69) our wrecks

func hulks_here() -> Array:
	## The pirate ships wrecked in our system (not the one alongside now).
	if server.sectors.count == 0:
		return []
	return hulks.get(Sectors.key(server.sectors.cell[server.ship.sector]), [])


func add_hulk(at_key: int, h: Dictionary) -> void:
	var list: Array = hulks.get(at_key, [])
	list.append(h)
	hulks[at_key] = list
	_dirty = true


func take_hulk(h: Dictionary) -> void:
	for k: int in hulks.keys():
		(hulks[k] as Array).erase(h)
	_dirty = true


func at_hulk() -> Dictionary:
	## A wreck of ours the ship is within reach of (it comes alongside then), or {}.
	for h: Dictionary in hulks_here():
		if server.ship.pos.distance_to(h["pos"]) <= Sectors.WRECK_REACH:
			return h
	return {}


func hulk_spot(at: Vector2) -> Vector2:
	## (v69, the author: "if you are too close to another event or trader, make it appear a
	## little further") Where a ship wrecked at `at` stays on the chart: there, or the nearest
	## spot clear of the system's other places, its trader or station, and other wrecks.
	var s: Sectors = server.sectors
	var keep: Array = []                     # [where, how far off to stay]
	var sys: int = server.ship.sector
	if s.count > 0 and s.reach[sys] > 0:
		keep.append([s.spot[sys], float(s.reach[sys]) + Sectors.WRECK_REACH + Sectors.HULK_APART])
	for pl: Array in _here_places:
		keep.append([pl[1], Sectors.WORK_REACH + Sectors.WRECK_REACH + Sectors.HULK_APART])
	for h: Dictionary in hulks_here():
		keep.append([h["pos"], 2.0 * Sectors.WRECK_REACH + Sectors.HULK_APART])
	var clear := func(p: Vector2) -> bool:
		for k: Array in keep:
			if p.distance_to(k[0]) < float(k[1]):
				return false
		return true
	var edge := Vector2(10.0, 10.0)
	var far := Vector2(Sectors.SPAN - 10.0, Sectors.SPAN - 10.0)
	if clear.call(at.clamp(edge, far)):
		return at.clamp(edge, far).round()
	for r in range(4, 120, 4):
		for k in 24:
			var p := (at + Vector2.from_angle(TAU * k / 24.0) * r).clamp(edge, far)
			if clear.call(p):
				return p.round()
	return at.clamp(edge, far).round()


# --------------------------------------------------------------- saving

func save() -> Dictionary:
	var hs: Array = []
	var esc: Array = []
	for h: Dictionary in hunters:
		hs.append(int(h["at"]))
		esc.append(int(h.get("escaped", 0)))
	if not _fight.is_empty():
		hs.append(int(_fight["at"]))
		esc.append(int(_fight.get("escaped", 0)))
	return {"depth": depth, "entry": [entry.x, entry.y], "history": Array(history), "ticks": ticks_here, "next": next_hunter,
		"hunters": hs, "escaped": esc, "found": found.keys(), "taken": taken.keys(), "work": work, "hulks": _hulks_saved()}


func _hulks_saved() -> Dictionary:
	var out := {}
	for k: int in hulks.keys():
		var list: Array = []
		for h: Dictionary in hulks[k]:
			var things: Array = []
			for e: Array in h["things"]:
				things.append([int(e[0]), Array(e[1] as PackedByteArray)])
			list.append({"x": (h["pos"] as Vector2).x, "y": (h["pos"] as Vector2).y, "layout": h["layout"], "name": h["name"],
				"things": things, "outcome": h["outcome"], "party": h["party"], "boarded": h["boarded"], "classic": (h["design"] as Dictionary).has("classic"),
				"bodies": h.get("bodies", [])})
		out[str(k)] = list
	return out


func load_from(d: Dictionary) -> void:
	depth = int(d.get("depth", 0))
	entry = Vector2i(int(d["entry"][0]), int(d["entry"][1])) if d.has("entry") else Vector2i.ZERO
	history = PackedByteArray(d.get("history", []))
	ticks_here = int(d.get("ticks", 0))
	next_hunter = int(d.get("next", roundi(HUNTER_FIRST * Net.TICK_HZ)))
	hunters = []
	var esc: Array = d.get("escaped", [])
	for i in d.get("hunters", []).size():
		hunters.append({"at": int(d["hunters"][i]), "move": 0, "coming": -1, "escaped": int(esc[i]) if i < esc.size() else 0})
	found = {}
	for k in d.get("found", []):
		found[int(k)] = true
	taken = {}
	for k in d.get("taken", []):
		taken[int(k)] = true
	work = {}
	var w: Dictionary = d.get("work", {})
	for k in w:
		work[int(k)] = int(w[k])
	hulks = {}
	var hd: Dictionary = d.get("hulks", {})
	for k in hd:
		for e: Dictionary in hd[k]:
			var things: Array = []
			for t: Array in e.get("things", []):
				things.append([int(t[0]), PackedByteArray(t[1])])
			add_hulk(int(k), {"pos": Vector2(float(e["x"]), float(e["y"])), "layout": int(e["layout"]), "name": str(e["name"]),
				"id": server.new_ship_id(), "things": things, "air": {}, "outcome": str(e.get("outcome", "dead")),
				"party": int(e.get("party", 0)), "boarded": bool(e.get("boarded", true)), "bodies": e.get("bodies", []),
				"design": {"layout": int(e["layout"]), "classic": true} if e.get("classic", false) else {"layout": int(e["layout"])}})
	_fight = {}
	_places_for = -1
	_last_system = -1
	_dirty = true
