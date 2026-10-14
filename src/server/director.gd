extends RefCounted
## The event master ("ивентер"): decides what goes wrong on the ship, and when.
##
## It is the seed of what docs/VISION.md describes: a master that runs events
## by hand or by itself, looks at the ship and its crew, and keeps the players
## from being bored. For now it knows a handful of events and looks at very little, but
## the parts are in place: a catalogue of events by size, an automatic pace
## that depends on the sector, the crew and the trouble the ship is already
## in, and a way to fire any event by hand.
##
## To add an event: a line in EVENTS and a branch in `_run`.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

# sizes, as the vision counts them: tens of thousands of small events,
# thousands of medium ones, hundreds of big ones, dozens of catastrophes
const SMALL := 0
const MEDIUM := 1
const BIG := 2
const CATASTROPHE := 3
const SIZE_NAMES: Array[String] = ["мелкое", "среднее", "большое", "катастрофа"]

const MICROMETEORITE := 1
const METEOR_VOLLEY := 2
const CONSOLE_FAULT := 3
const ENGINE_FAULT := 4
const AIR_PLANT_FAULT := 5
const DOOR_JAM := 6
const SHUTTER_FAULT := 7
const POWER_GLITCH := 8
const BOARDING := 9
const PIRATE_SHIP := 10
const FUEL_DRIFT := 11

## id, name, size, sectors it can happen in, how often it is picked there
const EVENTS: Array[Dictionary] = [
	{"id": MICROMETEORITE, "name": "Микрометеорит", "size": SMALL,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 10},
	{"id": METEOR_VOLLEY, "name": "Метеорный залп", "size": MEDIUM,
		"where": [Sectors.METEORS], "weight": 4},
	{"id": CONSOLE_FAULT, "name": "Замыкание пульта", "size": MEDIUM,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 3},
	{"id": ENGINE_FAULT, "name": "Отказ двигателя", "size": BIG,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 2},
	{"id": AIR_PLANT_FAULT, "name": "Отказ воздушной установки", "size": MEDIUM,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 2},
	{"id": DOOR_JAM, "name": "Заклинившая дверь", "size": SMALL,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 4},
	{"id": SHUTTER_FAULT, "name": "Отказ аварийного шлюза", "size": SMALL,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 3},
	{"id": POWER_GLITCH, "name": "Сбой питания", "size": MEDIUM,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 2},
	# never picked by chance (weight 0): it comes by itself to a ship left with no fuel at all
	{"id": FUEL_DRIFT, "name": "Дрейфующее топливо", "size": SMALL,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT, Sectors.STATION], "weight": 0},
	{"id": BOARDING, "name": "Абордаж", "size": BIG,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER, Sectors.DERELICT], "weight": 2},
	{"id": PIRATE_SHIP, "name": "Пиратский корабль", "size": BIG,
		"where": [Sectors.EMPTY, Sectors.TRADER, Sectors.DERELICT], "weight": 2},
]

## seconds between events, by sector kind: [from, to]; none at a supply station
const PACE := {
	Sectors.EMPTY: [180.0, 360.0],
	Sectors.METEORS: [25.0, 45.0],
	Sectors.TRADER: [180.0, 360.0],
	Sectors.DERELICT: [180.0, 360.0],
}
const MERCY_SECONDS := 20.0          # how long an event is put off while the ship is already in trouble
const SETTLE_SECONDS := 15.0         # quiet after arriving in a sector
const STREAM_GRACE_SECONDS := 8.0    # quiet after flying into or out of a meteor stream
const RESCUE_SECONDS := 120.0        # a ship with no fuel aboard at all finds some after this long
const RESCUE_FUEL := 2               # cans in that find

var server: Node                     # the GameServer: the director reads it and calls its methods
var auto := true                     # false: only events fired by hand happen
var fired := 0                       # how many events have happened (for tests)

var _rng := RandomNumberGenerator.new()
var _next_tick := 0
var _queue: Array = []               # things still to happen: [tick, what]
var _dry_until := -1                 # the tick a ship with no fuel aboard finds some (-1 = it has fuel)


func setup(p_server: Node) -> void:
	server = p_server
	_rng.randomize()
	entered_sector()


func entered_sector() -> void:
	## The ship has just arrived somewhere: give the crew a breather, then start this sector's pace.
	_queue.clear()
	_schedule(SETTLE_SECONDS)


func surroundings_changed() -> void:
	## The ship has flown into or out of something inside the sector: the pace changes with it.
	_schedule(STREAM_GRACE_SECONDS)


func tick() -> void:
	var now: int = server.tick
	while not _queue.is_empty() and int(_queue[0][0]) <= now:
		var item: Array = _queue.pop_front()
		_do(str(item[1]))
	if server.over != Net.OVER_NONE:
		return                               # the campaign is over: nothing more happens
	if auto:
		_watch_fuel(now)
	if not auto or now < _next_tick:
		return
	var report := assess()
	if int(report["crew_up"]) == 0:
		_next_tick = now + int(MERCY_SECONDS * Net.TICK_HZ)   # nobody is on their feet: nothing new while they are down
		return
	if int(report["holes"]) >= maxi(1, int(report["crew_up"]) / 2 + 1):
		_next_tick = now + int(MERCY_SECONDS * Net.TICK_HZ)   # the crew already has more holes than it can reach
		return
	var event := _pick()
	if event.is_empty():
		_schedule(60.0)
		return
	fire(int(event["id"]))
	_schedule(0.0)


func _watch_fuel(now: int) -> void:
	## A ship with not a single can of fuel left could be stuck for good: no
	## jump, and no trader or nothing to pay one with. Space is cruel, but not
	## a dead end: after a while a drifting container of fuel turns up.
	if server.supplies.fuel_aboard() > 0:
		_dry_until = -1
	elif _dry_until < 0:
		_dry_until = now + int(RESCUE_SECONDS * Net.TICK_HZ)
	elif now >= _dry_until:
		_dry_until = -1
		fire(FUEL_DRIFT)


func assess() -> Dictionary:
	## What the director knows about the ship right now. This is where the
	## "scan" of the vision will grow: skills, gear, how the crew has been doing.
	var crew := 0
	var crew_up := 0
	for p in server.players:
		if p != null and not p.corpse and not p.bot:
			crew += 1
			if p.cond == Net.COND_OK:
				crew_up += 1
	return {"crew": crew, "crew_up": crew_up, "holes": server.air.holes.size(), "sector": server.navigation.danger_kind(),
		"broken": server.ship.broken.size(), "engine_down": server.engine_down(), "patches": server.supplies.patches_aboard(),
		"weapons": server.supplies.weapons_aboard(), "pirates": server.pirates.aboard(), "fuel": server.supplies.fuel_aboard()}


func fire(event_id: int) -> bool:
	## Makes an event happen now, whatever the pace says. Used by the automatic
	## side and by the host's menu alike.
	for e: Dictionary in EVENTS:
		if int(e["id"]) == event_id:
			fired += 1
			server.log_line.emit("[ивентер] %s (%s)" % [e["name"], SIZE_NAMES[int(e["size"])]])
			_run(event_id)
			return true
	return false


func _run(event_id: int) -> void:
	match event_id:
		MICROMETEORITE:
			_do("hole")
		CONSOLE_FAULT:
			server.systems.break_console()
		ENGINE_FAULT:
			server.systems.break_engine()
		AIR_PLANT_FAULT:
			server.systems.break_air_plant()
		DOOR_JAM:
			server.systems.jam_door()
		SHUTTER_FAULT:
			server.systems.fault_shutter()
		POWER_GLITCH:
			server.systems.power_glitch()
		BOARDING:
			server.pirates.board(_party())
		PIRATE_SHIP:
			server.derelict.pirates_come(_party())
		FUEL_DRIFT:
			server.supplies.find_fuel(RESCUE_FUEL)
		METEOR_VOLLEY:
			# three hits a second and a half apart
			for i in 3:
				_queue.append([server.tick + i * 30, "hole"])
			_queue.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))


func _do(what: String) -> void:
	if what == "hole":
		server.systems.breach_random()


func _can_happen(e: Dictionary, here: int) -> bool:
	## Fits this place, and would change something: a thing already broken does not break again.
	if not (e["where"] as Array).has(here):
		return false
	match int(e["id"]):
		CONSOLE_FAULT:
			return server.systems.can_break("console")
		ENGINE_FAULT:
			return server.systems.can_break("engine")
		AIR_PLANT_FAULT:
			return server.systems.can_break("air_plant")
		DOOR_JAM:
			return server.systems.can_break("door")
		SHUTTER_FAULT:
			return server.systems.can_break("shutter")
		POWER_GLITCH:
			return server.systems.can_break("power")
		BOARDING:
			return server.pirates.aboard() == 0
		PIRATE_SHIP:
			return server.pirates.aboard() == 0 and server.derelict.pirates_can_come()
	return true


func _party() -> int:
	## How many pirates come: more crew, more pirates; an unarmed crew meets fewer of them.
	var crew := maxi(int(assess()["crew"]), 1)
	var party := clampi(1 + crew / 2, 1, 4)
	if server.supplies.weapons_aboard() == 0:
		party = maxi(party - 1, 1)
	return party


func _weight(e: Dictionary, here: int) -> int:
	## How often this event is picked here and now; 0 = not at all.
	if not _can_happen(e, here):
		return 0
	var w := int(e["weight"])
	# a crew with no weapons at all is boarded half as often
	if (int(e["id"]) == BOARDING or int(e["id"]) == PIRATE_SHIP) and server.supplies.weapons_aboard() == 0:
		w = maxi(w / 2, 1)
	# a crew with nothing left to close a hole with gets holes three times as rarely
	if (int(e["id"]) == MICROMETEORITE or int(e["id"]) == METEOR_VOLLEY) and server.supplies.patches_aboard() == 0:
		w = maxi(w / 3, 1)
	return w


func _pick() -> Dictionary:
	var here: int = server.navigation.danger_kind()
	var total := 0
	for e: Dictionary in EVENTS:
		total += _weight(e, here)
	if total == 0:
		return {}
	var roll := _rng.randi_range(1, total)
	for e: Dictionary in EVENTS:
		if _weight(e, here) > 0:
			roll -= _weight(e, here)
			if roll <= 0:
				return e
	return {}


func _schedule(at_least: float) -> void:
	## Sets when the next automatic event may come: this sector's pace, sooner
	## with a bigger crew, never sooner than `at_least` seconds.
	var here: int = server.navigation.danger_kind()
	var wait := 600.0
	if PACE.has(here):
		var span: Array = PACE[here]
		wait = _rng.randf_range(float(span[0]), float(span[1]))
		var crew := int(assess()["crew"])
		wait /= clampf(0.75 + 0.25 * crew, 1.0, 2.5)     # 1 player: as written; 7 and more: 2.5 times as often
	_next_tick = server.tick + int(maxf(wait, at_least) * Net.TICK_HZ)
