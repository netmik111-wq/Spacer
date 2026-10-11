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

## id, name, size, sectors it can happen in, how often it is picked there
const EVENTS: Array[Dictionary] = [
	{"id": MICROMETEORITE, "name": "Микрометеорит", "size": SMALL,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER], "weight": 10},
	{"id": METEOR_VOLLEY, "name": "Метеорный залп", "size": MEDIUM,
		"where": [Sectors.METEORS], "weight": 4},
	{"id": CONSOLE_FAULT, "name": "Замыкание пульта", "size": MEDIUM,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER], "weight": 3},
	{"id": ENGINE_FAULT, "name": "Отказ двигателя", "size": BIG,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER], "weight": 2},
	{"id": AIR_PLANT_FAULT, "name": "Отказ воздушной установки", "size": MEDIUM,
		"where": [Sectors.EMPTY, Sectors.METEORS, Sectors.TRADER], "weight": 2},
]

## seconds between events, by sector kind: [from, to]; none at a supply station
const PACE := {
	Sectors.EMPTY: [180.0, 360.0],
	Sectors.METEORS: [25.0, 45.0],
	Sectors.TRADER: [180.0, 360.0],
}
const MERCY_SECONDS := 20.0          # how long an event is put off while the ship is already in trouble
const SETTLE_SECONDS := 15.0         # quiet after arriving in a sector
const STREAM_GRACE_SECONDS := 8.0    # quiet after flying into or out of a meteor stream

var server: Node                     # the GameServer: the director reads it and calls its methods
var auto := true                     # false: only events fired by hand happen
var fired := 0                       # how many events have happened (for tests)

var _rng := RandomNumberGenerator.new()
var _next_tick := 0
var _queue: Array = []               # things still to happen: [tick, what]


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
	return {"crew": crew, "crew_up": crew_up, "holes": server.air.holes.size(), "sector": server.danger_kind(),
		"broken": server.broken.size(), "engine_down": server.engine_down()}


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
			server.break_console()
		ENGINE_FAULT:
			server.break_engine()
		AIR_PLANT_FAULT:
			server.break_air_plant()
		METEOR_VOLLEY:
			# three hits a second and a half apart
			for i in 3:
				_queue.append([server.tick + i * 30, "hole"])
			_queue.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))


func _do(what: String) -> void:
	if what == "hole":
		server.breach_random()


func _can_happen(e: Dictionary, here: int) -> bool:
	## Fits this place, and would change something: a thing already broken does not break again.
	if not (e["where"] as Array).has(here):
		return false
	match int(e["id"]):
		CONSOLE_FAULT:
			return server.can_break("console")
		ENGINE_FAULT:
			return server.can_break("engine")
		AIR_PLANT_FAULT:
			return server.can_break("air_plant")
	return true


func _pick() -> Dictionary:
	var here: int = server.danger_kind()
	var total := 0
	for e: Dictionary in EVENTS:
		if _can_happen(e, here):
			total += int(e["weight"])
	if total == 0:
		return {}
	var roll := _rng.randi_range(1, total)
	for e: Dictionary in EVENTS:
		if _can_happen(e, here):
			roll -= int(e["weight"])
			if roll <= 0:
				return e
	return {}


func _schedule(at_least: float) -> void:
	## Sets when the next automatic event may come: this sector's pace, sooner
	## with a bigger crew, never sooner than `at_least` seconds.
	var here: int = server.danger_kind()
	var wait := 600.0
	if PACE.has(here):
		var span: Array = PACE[here]
		wait = _rng.randf_range(float(span[0]), float(span[1]))
		var crew := int(assess()["crew"])
		wait /= clampf(0.75 + 0.25 * crew, 1.0, 2.5)     # 1 player: as written; 7 and more: 2.5 times as often
	_next_tick = server.tick + int(maxf(wait, at_least) * Net.TICK_HZ)
