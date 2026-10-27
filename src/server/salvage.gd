extends RefCounted
## (v67, the author's B2 and R2) Salvage by hand, and things floating outside.
##
## Scrap («лом») is cut off the walls of a dark ship alongside (a derelict or a
## wreck) by holding "use" at one of its walls, from inside it or from space in a
## suit: CUT_SECONDS a piece (quicker with the repair skill). Each ship gives so
## much and no more: a derelict DERELICT_BUDGET pieces (remembered for its system),
## a wreck WRECK_BUDGET, one taken by boarding CAPTURE_BUDGET.
##
## What the ship picks up at a place in a system (debris, a container, bodies, a
## battlefield) no longer lands in the locker by itself: it floats out in space a
## few cells from one of our airlocks, and somebody in a suit goes out for it. An
## armed tractor beam pulls one floating thing a TRACTOR_SECONDS into an airlock's
## chamber instead. A jump leaves whatever still floats behind.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Items := preload("res://src/shared/items.gd")
const Player := preload("res://src/server/player.gd")

const NOT_HERE := "-"
const CUT_SECONDS := 8.0
const DERELICT_BUDGET := 8
const WRECK_BUDGET := 8
const CAPTURE_BUDGET := 14
const FLOAT_NEAR := 2                # things float this many cells or more from the airlock's outer door...
const FLOAT_FAR := 6                 # ... and no farther than this
const TRACTOR_SECONDS := 5.0

var server: GameServer
var left := {}                       # the ship alongside ("d" + its system's key, or "w" + its id) -> pieces still to cut
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	left.clear()
	_rng.randomize()


func _key() -> String:
	var d = server.derelict
	if d.ship == null:
		return ""
	return ("w%d" % d.ship.id) if d.wreck else ("d%d" % d._came_in)


func pieces_left() -> int:
	var k := _key()
	if k == "":
		return 0
	if not left.has(k):
		left[k] = WRECK_BUDGET if server.derelict.wreck else DERELICT_BUDGET
	return int(left[k])


func captured() -> void:
	## (Gunnery) The wreck alongside was taken by boarding: more to cut off it.
	var k := _key()
	if k != "":
		left[k] = CAPTURE_BUDGET


func can_cut(p: Player, cell: int) -> String:
	## "" = it can cut scrap off this cell now; NOT_HERE = this is no wall of a
	## dark ship alongside; anything else is why not.
	var map = server.map
	if cell < 0 or not map.is_other(cell) or map.walk[cell] == 1 or map.door_of[cell] >= 0 or not server.derelict.dark() \
			or server.derelict.kind == Net.OTHER_ROCK:
		return NOT_HERE
	if p.cond != Net.COND_OK or p.corpse:
		return NOT_HERE
	if pieces_left() <= 0:
		return "С этого корабля больше нечего срезать."
	return ""


func cut_ticks(p: Player) -> int:
	return roundi(CUT_SECONDS * Net.TICK_HZ * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)))


func cut(p: Player, _cell: int) -> void:
	var k := _key()
	left[k] = pieces_left() - 1
	p.train(Net.SKILL_REPAIR)
	if not p.add(Net.ITEM_SCRAP, true):
		server.put_on_floor(p.st.y * server.map.width + p.st.x, Net.ITEM_SCRAP)
	server.chat.tell(p, "Срезан кусок лома. Осталось на этом корабле: %d." % int(left[k]))


# ------------------------------------------------------------- (v81) ore out of an asteroid

const MINE_SECONDS := 10.0           # to dig a piece of ore out of a vein by hand (quicker with the repair skill)


func can_mine(p: Player, cell: int) -> String:
	## "" = it can dig ore out of this cell now; NOT_HERE = no ore vein of the asteroid alongside.
	var map = server.map
	if cell < 0 or not map.is_other(cell) or not server.derelict.here or server.derelict.kind != Net.OTHER_ROCK \
			or map.cells[cell] != int(map.tile_ids.get("rock_ore", -2)):
		return NOT_HERE
	if p.cond != Net.COND_OK or p.corpse:
		return NOT_HERE
	if server.derelict.trial:
		return ""
	if server.road.ore_left() <= 0:
		return "Астероид выработан: руды не осталось."
	return ""


func mine_ticks(p: Player) -> int:
	return roundi(MINE_SECONDS * Net.TICK_HZ * (1.0 - 0.3 * p.skill(Net.SKILL_REPAIR)))


func mine(p: Player, _cell: int) -> void:
	var left := 99 if server.derelict.trial else server.road.mined()
	p.train(Net.SKILL_REPAIR)
	if not p.add(Net.ITEM_ORE, true):
		server.put_on_floor(p.st.y * server.map.width + p.st.x, Net.ITEM_ORE)
	server.chat.tell(p, "Добыт кусок руды. В астероиде осталось примерно %d." % maxi(left, 0))


# ------------------------------------------------------------- things floating outside

func _vents() -> Array:
	## Our airlocks that open into space: [pump cell, the space cell past its outer door].
	var map = server.map
	var out := []
	for pump: int in map.lock_pump.keys():
		var lock: Dictionary = map.lock_pump[pump]
		var d: int = lock["outer"]
		if d < 0 or map.door_vent[d] == 0 or d >= map.other_first_door:
			continue
		var at: Vector2i = map.doors[d]
		for v: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if map.floats(at.x + v.x, at.y + v.y):
				out.append([pump, (at.y + v.y) * map.width + at.x + v.x])
				break
	return out


func _spots_near(start: int) -> Array:
	## Open space cells FLOAT_NEAR..FLOAT_FAR steps from that one, by a walk through space.
	var map = server.map
	var dist := {start: 0}
	var queue := [start]
	var out := []
	while not queue.is_empty():
		var c: int = queue.pop_front()
		var n: int = dist[c]
		if n >= FLOAT_NEAR:
			out.append(c)
		if n >= FLOAT_FAR:
			continue
		for o: int in [1, -1, map.width, -map.width]:
			var j := c + o
			if dist.has(j) or j < 0 or j >= map.cells.size() or not map.floats(j % map.width, j / map.width):
				continue
			dist[j] = n + 1
			queue.append(j)
	return out


func float_out(items: Array) -> int:
	## Lets those things float in space near one of our airlocks. How many found room (the rest go to the locker).
	var vents := _vents()
	var placed := 0
	var spots: Array = [] if vents.is_empty() else _spots_near(vents[_rng.randi_range(0, vents.size() - 1)][1])
	for item: int in items:
		var done := false
		for tries in 12:
			if spots.is_empty():
				break
			if server.put_on_floor(spots[_rng.randi_range(0, spots.size() - 1)], item):
				done = true
				break
		if done:
			placed += 1
		else:
			server.ship.store[item] = int(server.ship.store.get(item, 0)) + 1
	return placed


func floating() -> Array:
	## The cells out in space with something in them.
	var map = server.map
	var out := []
	for c: int in server.floor_things.keys():
		if map.floats(c % map.width, c / map.width):
			out.append(c)
	return out


func _tractor_on() -> bool:
	var s = server.ship
	for i in s.mounts.size():
		if Weapons.klass(s.mounts[i]) == Weapons.CLASS_TRACTOR and i < s.armed.size() and s.armed[i] == 1 \
				and not s.broken.has(server.map.guns[i]):
			return true
	return false


func tick() -> void:
	if server.tick % roundi(TRACTOR_SECONDS * Net.TICK_HZ) != 0 or not server.powered() or not _tractor_on():
		return
	var out := floating()
	if out.is_empty():
		return
	var vents := _vents()
	if vents.is_empty():
		return
	var lock: Dictionary = server.map.lock_pump[vents[0][0]]
	var chamber: PackedInt32Array = lock["chamber"]
	var from: int = out[0]
	var things: PackedByteArray = server.floor_things[from]
	var top := Net.FLOOR_STACK - 1
	while top >= 0 and things[top] == Net.ITEM_NONE:
		top -= 1
	if top < 0 or chamber.is_empty():
		return
	if not server.put_on_floor(chamber[_rng.randi_range(0, chamber.size() - 1)], things[top]):
		return
	server.chat.say("Захватный луч подтянул в шлюз: %s." % Items.name_of(things[top]).to_lower())
	things[top] = Net.ITEM_NONE
	if things.count(Net.ITEM_NONE) == Net.FLOOR_STACK:
		server.floor_things.erase(from)
	else:
		server.floor_things[from] = things
	server.replication.floor_record(from)


func jumped() -> void:
	## A jump leaves behind whatever still floats outside.
	var out := floating()
	for c: int in out:
		server.floor_things.erase(c)
		server.replication.floor_record(c)
	# (v89, his note: bodies floating by the ship were still there after a jump) the bodies out there too
	var map = server.map
	var bodies := 0
	for p in server.players:
		if p != null and (p.corpse or p.pirate and p.cond == Net.COND_DEAD) and map.floats(p.st.x, p.st.y):
			server.crew.remove(p)
			bodies += 1
	if not out.is_empty() or bodies > 0:
		server.chat.say("То, что плавало за бортом, осталось позади.")
