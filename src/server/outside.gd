extends RefCounted
## (v61, moved here from v60; my V15/V16 picks) Mending the hull from outside.
## Anybody in a suit, out in space and facing a whole cell of our hull, holds
## "use" with a hull patch in pockets and gives the hull HULL_PER_PATCH back (v67: or a piece of scrap, HULL_PER_SCRAP)
## (MEND_SECONDS, quicker with the repair skill), up to full: patches that close
## holes from inside can also mend the hull's strength from outside.
##
## A bot on «Работы» does it by itself when the hull is below BOT_GOES_BELOW and
## there is nothing to mend aboard and no fight: one bot at a time takes patches
## and a suit from the locker, fills its tank, goes into an airlock, pumps the
## chamber out, floats out to the hull and mends until the hull is whole or its
## patches run out, then comes back and pumps the chamber full again. A pirate
## showing up calls it back at once.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

const HULL_PER_PATCH := 15          # (v67, the author's H2: the hull comes back mostly from our own work; was 10)
const HULL_PER_SCRAP := 10          # (v67) a piece of scrap welded on, when there is no patch in pockets
const MEND_SECONDS := 10.0
const BOT_GOES_BELOW := 0.8          # the share of the hull below which a bot goes out to mend it
const BOT_PATCHES := 3               # the most patches it takes along
const BOT_TANK := 0.9                # it fills its tank to this first
const BOT_TANK_BACK := 0.3           # with less than this in its tank it comes back in
const REST_TICKS := 600              # after a trip that came to nothing, it waits 30 s before another
const EMPTY := 0.03                  # a chamber with less air than this is pumped out
const FULL := 0.85                   # and with more than this, full again

enum { PREP, TO_LOCK, PUMP_OUT, GO_OUT, MEND, GO_BACK, PUMP_IN }

var server: GameServer
var trips := {}                      # bot slot -> {phase, pump, goal, face, step, from}
var _rest_until := 0


func setup(p_server: GameServer) -> void:
	server = p_server
	trips.clear()
	_rest_until = 0


func tick() -> void:
	for slot: int in trips.keys():
		var p: Player = server.players[slot] if slot < server.players.size() else null
		if p == null or not p.bot or p.corpse or p.cond == Net.COND_DEAD:
			trips.erase(slot)


# ------------------------------------------------------------ anybody mending outside

func can_mend(p: Player, cell: int) -> bool:
	## Is the character out in space, facing a whole cell of our hull, with a
	## patch, and the hull short of full?
	var map = server.map
	return cell >= 0 and server.ship.hull < server.ship.hull_max and (p.count(Net.ITEM_PATCH) > 0 or p.count(Net.ITEM_SCRAP) > 0) and map.floats(p.st.x, p.st.y) \
		and not server.air.holes.has(cell) and not map.is_other(cell) and map.hull.has(cell)


func mend_ticks(p: Player) -> int:
	return roundi(MEND_SECONDS * Net.TICK_HZ * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)))


func mended(p: Player) -> void:
	## A patch if it has one, else a piece of scrap welded on (v67).
	var patch := p.count(Net.ITEM_PATCH) > 0
	p.remove(Net.ITEM_PATCH if patch else Net.ITEM_SCRAP)
	p.train(Net.SKILL_REPAIR)
	server.ship.hull = mini(server.ship.hull + (HULL_PER_PATCH if patch else HULL_PER_SCRAP), server.ship.hull_max)
	server.chat.say("%s латает обшивку снаружи: прочность %d из %d." % [p.name, server.ship.hull, server.ship.hull_max])


# ------------------------------------------------------------------ a bot going out

func out_now(p: Player) -> bool:
	return trips.has(p.slot)


func _threat() -> bool:
	var d = server.derelict
	return server.gunnery.fighting() or (d.here and d.kind == Net.OTHER_PIRATE) or server.over != Net.OVER_NONE


func _wants(p: Player) -> bool:
	## Should this bot set off to mend the hull from outside now?
	if p.order != Net.POST_REPAIR or p.bot_healing or server.tick < _rest_until or _threat() or not server.powered():
		return false
	if server.ship.hull >= roundi(server.ship.hull_max * BOT_GOES_BELOW) or not trips.is_empty():
		return false
	if _pump() < 0 or not server.stations._repair_jobs(p).is_empty() or server.stations._carried_gun(p) >= 0:
		return false
	var patches: int = p.count(Net.ITEM_PATCH) + int(server.ship.store.get(Net.ITEM_PATCH, 0))
	var suit: bool = p.has_suit() or server.stations._store_suit() >= 0
	return patches > 0 and suit


func _pump() -> int:
	## An airlock pump of our own ship whose chamber has a way out into space.
	for c: int in server.map.lock_pump.keys():
		var lock: Dictionary = server.map.lock_pump[c]
		if int(lock["outer"]) >= 0 and server.map.on_ship(server.map.fitting_front(c)) and not server.ship.broken.has(c):
			return c
	return -1


func drive(p: Player) -> bool:
	## One tick of a bot's trip outside. False: it is not on one (Stations runs it as ever).
	if not trips.has(p.slot):
		if not _wants(p):
			return false
		trips[p.slot] = {"phase": PREP, "pump": _pump(), "goal": -1, "face": 0, "step": 0, "from": -1, "plan": -1000}
		server.chat.say("%s идёт латать обшивку снаружи." % p.name)
	var t: Dictionary = trips[p.slot]
	var pump: int = t["pump"]
	var chamber: PackedInt32Array = server.map.lock_pump[pump]["chamber"]
	var phase: int = t["phase"]
	var outside: bool = server.map.floats(p.st.x, p.st.y)
	var quit := _threat() or p.order != Net.POST_REPAIR or p.bot_healing or not server.powered()
	if quit or (phase == MEND or phase == GO_OUT) and p.has_suit() and p.tank < BOT_TANK_BACK:
		if phase <= TO_LOCK:
			return _done(p, false)
		if phase < GO_BACK:
			_phase(t, GO_BACK)
	p.using = false
	match int(t["phase"]):
		PREP:
			return _prep(p, t)
		TO_LOCK:
			if _at(p, t, _spots(pump)):
				if server.systems.lock_shut(pump):
					_phase(t, PUMP_OUT)
				p.doing = Net.DOING_GOING
		PUMP_OUT:
			if not _at(p, t, _spots(pump)):
				return true
			if _most_air(chamber) <= EMPTY:
				server.ship.pumps.erase(pump)
				_phase(t, GO_OUT)
			elif not server.ship.pumps.has(pump) and server.systems.lock_shut(pump):
				server.systems.toggle_pump(p, pump)
			p.doing = Net.DOING_WORK
		GO_OUT:
			if _at(p, t, _hull_spots(), true):
				_phase(t, MEND)
			p.doing = Net.DOING_GOING
		MEND:
			var cell: int = server.map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
			if not outside or not can_mend(p, cell):
				_phase(t, GO_BACK)
				return true
			p.using = true
			p.doing = Net.DOING_WORK
		GO_BACK:
			if _at(p, t, _spots(pump), true):
				if server.systems.lock_shut(pump):
					_phase(t, PUMP_IN)
			p.doing = Net.DOING_GOING
		PUMP_IN:
			if not _at(p, t, _spots(pump)):
				return true
			if _least_air(chamber) >= FULL or server.ship.store_air <= 0.0:
				server.ship.pumps.erase(pump)
				return _done(p, server.ship.hull >= roundi(server.ship.hull_max * BOT_GOES_BELOW))
			if not server.ship.pumps.has(pump) and server.systems.lock_shut(pump):
				server.systems.toggle_pump(p, pump)
			p.doing = Net.DOING_WORK
	return true


func _prep(p: Player, t: Dictionary) -> bool:
	## Patches and a suit from the locker, then a full tank from an oxygen station.
	var store: Dictionary = server.ship.store
	var want_patch: bool = p.count(Net.ITEM_PATCH) < BOT_PATCHES and int(store.get(Net.ITEM_PATCH, 0)) > 0 and p.count(Net.ITEM_NONE) > 0 \
		and (p.count(Net.ITEM_PATCH) == 0 or not t.get("took", false))
	var want_suit: bool = not p.has_suit()
	if want_suit and server.stations._store_suit() < 0 or p.count(Net.ITEM_PATCH) == 0 and int(store.get(Net.ITEM_PATCH, 0)) == 0:
		return _done(p, false)
	if want_patch or want_suit:
		var spots := {}
		for c: int in server.map.locker.keys():
			spots.merge(_spots(c))
		if _at(p, t, spots):
			var sup = server.supplies
			while p.count(Net.ITEM_PATCH) < BOT_PATCHES and int(store.get(Net.ITEM_PATCH, 0)) > 0 and p.count(Net.ITEM_NONE) > 0:
				sup.store_asked(p, Net.STORE_TAKE, Net.ITEM_PATCH)
			t["took"] = true
			if not p.has_suit() and server.stations._store_suit() >= 0 and p.count(Net.ITEM_NONE) > 0:
				var s: int = server.stations._store_suit()
				sup.store_asked(p, Net.STORE_TAKE, s)
				var k := p.slots.find(s)
				if k >= 0:
					p.hand = k
					server.inventory.act(p)      # it puts the suit on
			t["from"] = -1
		p.doing = Net.DOING_CARRY
		return true
	if p.tank < BOT_TANK:
		var spots := {}
		for c: int in server.map.oxygen.keys():
			if not server.ship.broken.has(c) and server.map.on_ship(server.map.fitting_front(c)):
				spots.merge(_spots(c))
		if spots.is_empty():
			return _done(p, false)
		if _at(p, t, spots):
			p.using = true
		p.doing = Net.DOING_CARRY
		return true
	_phase(t, TO_LOCK)
	return true


func _phase(t: Dictionary, phase: int) -> void:
	t["phase"] = phase
	t["from"] = -1


func _done(p: Player, worked: bool) -> bool:
	trips.erase(p.slot)
	p.using = false
	p.bot_plan_tick = -1000
	if not worked:
		_rest_until = server.tick + REST_TICKS
	return false


func _spots(fitting: int) -> Dictionary:
	var out := {}
	for s: Array in server.stations._spots_for(fitting):
		out[int(s[0])] = int(s[1])
	return out


func _hull_spots() -> Dictionary:
	## Cells out in space beside a whole cell of our hull: cell -> the way to face it.
	var map = server.map
	var w: int = map.width
	var out := {}
	for c: int in map.hull:
		if server.air.holes.has(c) or map.is_other(c):
			continue
		for d in range(1, 5):
			var x: int = c % w - Net.DX[d]
			var y: int = c / w - Net.DY[d]
			if map.floats(x, y):
				out[y * w + x] = d
	return out


func _at(p: Player, t: Dictionary, goals: Dictionary, space: bool = false) -> bool:
	## Walks the bot toward the nearest of the goals (cell -> facing, 0 = any). True once it stands there facing it.
	var map = server.map
	var here: int = p.st.y * map.width + p.st.x
	if goals.has(here):
		p.st.dir = Net.DIR_NONE
		var f: int = goals[here]
		if f > 0 and p.st.facing != f:
			p.st.facing = f
			p.self_dirty = true
		return true
	if here != int(t["from"]) or server.tick - int(t["plan"]) >= 10:
		var r := _route(here, goals, space)
		t["step"] = r[0]
		t["from"] = here
		t["plan"] = server.tick
	var step: int = t["step"]
	if step == -1:
		p.st.dir = Net.DIR_NONE
		if p.st.cd == 0:
			server.movement.climb(p)
			t["from"] = -1
	else:
		p.st.dir = step
		if step == 0:
			p.doing = Net.DOING_NO_WAY
	return false


func _route(start: int, goals: Dictionary, space: bool) -> Array:
	## Like Stations._route, but through the airlock and (with `space`) out into open space too.
	var map = server.map
	var w: int = map.width
	var first := {start: 0}
	var queue := PackedInt32Array([start])
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		var x := cell % w
		var y := cell / w
		var nexts: Array = []
		for d in range(1, 5):
			var nx: int = x + Net.DX[d]
			var ny: int = y + Net.DY[d]
			var j := ny * w + nx
			var ok: bool = map.walkable(nx, ny) and map.on_ship(j) or space and map.floats(nx, ny)
			if not ok:
				continue
			var door: int = map.door_of[j]
			if door >= 0 and server.doors.is_sealed(door):
				continue
			nexts.append([j, d])
		if map.climb[cell] >= 0 and not map.floats(x, y):
			nexts.append([map.climb[cell], -1])
		for n: Array in nexts:
			var to: int = n[0]
			if first.has(to):
				continue
			first[to] = n[1] if cell == start else first[cell]
			if goals.has(to):
				return [first[to], to]
			queue.append(to)
	return [0, -1]


func _most_air(cells: PackedInt32Array) -> float:
	var most := 0.0
	for c in cells:
		most = maxf(most, server.air.air[c])
	return most


func _least_air(cells: PackedInt32Array) -> float:
	var least := 1.0
	for c in cells:
		least = minf(least, server.air.air[c])
	return least
