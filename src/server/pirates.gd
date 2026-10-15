extends RefCounted
## Pirates: enemies the server moves. They board through a hole they cut in
## the hull, hunt the crew, shoot from a distance (not without missing) or
## strike close up, follow what they heard, and fall back when badly hurt.
## They see by the same rules as the crew (Sight): ahead of them, not through
## walls, and in the dark only close by or where a light shines. They leave
## those lying on the floor alone.
##
## A pirate is an ordinary character (Player with `pirate` set): it walks by
## the same movement rule, opens doors the same way, is hurt and dies the same
## way, and leaves a body with what it carried.

const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")

const SEE_EVERY := 4                 # ticks between looks around
const PLAN_EVERY := 10               # ticks between working out the way
const SHOOT_FROM := 8                # cells: close enough to shoot
const AIM_SPREAD := 0.7              # cells: how far off the mark a shot may go
const FIRE_GAP := [14, 26]           # ticks between its shots
const FLEE_BELOW := 30.0             # health under which it falls back
const MAX_ABOARD := 4

var server: Node
var count := 0                       # pirates sent aboard so far (for their names)
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	count = 0
	_rng.randomize()


func aboard() -> int:
	## Pirates aboard and still on their feet or not yet dead.
	var n := 0
	for q in server.players:
		if q != null and q.pirate and not q.corpse:
			n += 1
	return n


func board(how_many: int) -> bool:
	## A boarding party cuts its way in through the hull and comes aboard.
	var map = server.map
	var ways: Array = []
	for cell: int in map.hull:
		if server.air.holes.has(cell):
			continue
		var x: int = cell % map.width
		var y: int = cell / map.width
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if map.walkable(x + d.x, y + d.y) and map.door_at(x + d.x, y + d.y) < 0:
				ways.append([cell, Vector2i(x + d.x, y + d.y)])
				break
	if ways.is_empty() or how_many <= 0:
		return false
	var way: Array = ways[_rng.randi_range(0, ways.size() - 1)]
	server.systems.breach(way[0])
	var inside: Vector2i = way[1]
	for i in mini(how_many, MAX_ABOARD):
		spawn(inside.x, inside.y, _rng.randf() < 0.6)
	server.chat.say("Тревога! Абордаж: пираты прорезали обшивку и идут на борт (%s, их %d)." % [
		map.deck_names[map.deck_of(inside.y)].to_lower(), mini(how_many, MAX_ABOARD)])
	return true


func spawn(x: int, y: int, gunner: bool):
	## One pirate in that cell: a gunner with a pistol and a spare magazine, or
	## a brawler with a baton. Either may carry a patch for wounds.
	count += 1
	var p = server.crew.alloc("Пират %d" % count)
	p.pirate = true
	p.colour = Net.SUIT_COLOURS + _rng.randi_range(0, Net.PIRATE_COLOURS - 1)
	p.st.place(x, y)
	if gunner:
		p.add(Net.ITEM_PISTOL + Net.PISTOL_ROUNDS, true)
		p.add(Net.ITEM_MAG)
	else:
		p.add(Net.ITEM_BATON, true)
	if _rng.randf() < 0.5:
		p.add(Net.ITEM_MEDPATCH)
	p.ai_fire_tick = server.tick + _rng.randi_range(10, 30)
	server.crew.announce_join(p, null)
	return p


func heard(p, x: int, y: int) -> void:
	## A pirate heard the crew: if it has nobody in sight, it goes to look.
	if p.ai_target < 0:
		p.ai_goal = Vector2i(x, y)


func attacked(p, by) -> void:
	## Whoever hurts a pirate becomes the one it is after.
	if by.pirate or by.corpse:
		return
	p.ai_target = by.slot
	p.ai_goal = Vector2i(by.st.x, by.st.y)


func _sees(p, q) -> bool:
	## Can the pirate see this crew member (the crew's own rules of sight)?
	var map = server.map
	var to: Vector2i = Vector2i(q.st.x, q.st.y)
	var from: Vector2 = Vector2(p.st.x, p.st.y)
	if map.deck_of(to.y) != map.deck_of(p.st.y) or from.distance_to(Vector2(to)) > Sight.SIGHT_REACH:
		return false
	if from.distance_to(Vector2(to)) <= 1.5:
		return true                          # right next to it: felt, if not seen
	if server.powered():
		return Sight.sees(map, server.doors, from, p.st.facing, to, Sight.eye_arcs(false), Sight.SIGHT_REACH, server.replication.lines)
	if Sight.sees(map, server.doors, from, p.st.facing, to, Sight.eye_arcs(true), Sight.DARK_REACH, server.replication.lines):
		return true
	# in the dark a lit flashlight gives its holder away from afar, whichever way the pirate looks
	var lit: bool = not Items.light(q.in_hand()).is_empty()
	return lit and Sight.clear_cached(map, server.doors, Vector2i(p.st.x, p.st.y), to, server.replication.lines)


func think(p) -> void:
	## One tick of a pirate's mind. It only chooses where to go and when to
	## use what it holds; walking is the same as for anybody else.
	if p.cond != Net.COND_OK or p.health <= 0.0:
		return                               # (a wound that just felled it is taken account of this tick)
	var now: int = server.tick
	# who to go after: keep the one it has while it can see them, else the nearest it can see
	if (now + p.slot) % SEE_EVERY == 0 or p.ai_target < 0:
		var target = server.players[p.ai_target] if p.ai_target >= 0 and p.ai_target < server.players.size() else null
		if target == null or target.corpse or target.cond != Net.COND_OK or not _sees(p, target):
			p.ai_target = -1
			var best := 1e9
			for q in server.players:
				if q == null or q.pirate or q.corpse or q.cond != Net.COND_OK or not _sees(p, q):
					continue
				var d: float = Vector2(q.st.x, q.st.y).distance_to(Vector2(p.st.x, p.st.y))
				if d < best:
					best = d
					p.ai_target = q.slot
		if p.ai_target >= 0:
			var t = server.players[p.ai_target]
			p.ai_goal = Vector2i(t.st.x, t.st.y)
	var target = server.players[p.ai_target] if p.ai_target >= 0 and p.ai_target < server.players.size() else null
	if target != null and (target.corpse or target.cond != Net.COND_OK):
		target = null
		p.ai_target = -1
	var here: Vector2 = Vector2(p.st.x, p.st.y)
	var item: int = p.in_hand()
	# badly hurt: patch itself up if it can, else fall back from whoever it fights
	if p.health < FLEE_BELOW:
		var patch: int = p.slots.find(Net.ITEM_MEDPATCH)
		if patch >= 0 and now >= p.ready_tick:
			p.hand = patch
			server.combat.use_at(p, now, here)
			return
		if target != null:
			_step_away(p, Vector2(target.st.x, target.st.y))
			return
	if target != null:
		var there: Vector2 = Vector2(target.st.x, target.st.y)
		var dist: float = here.distance_to(there)
		var rounds: int = Items.rounds(item)
		if rounds == 0 and p.slots.has(Net.ITEM_MAG):
			_stop(p)
			server.combat.use_at(p, now, there)                  # reload
			return
		if rounds > 0 and dist <= SHOOT_FROM:
			_stop(p)
			_face(p, there)
			if now >= p.ai_fire_tick and now >= p.ready_tick:
				p.ai_fire_tick = now + _rng.randi_range(FIRE_GAP[0], FIRE_GAP[1])
				var aim: Vector2 = there + Vector2(_rng.randf_range(-AIM_SPREAD, AIM_SPREAD), _rng.randf_range(-AIM_SPREAD, AIM_SPREAD))
				server.combat.use_at(p, now, aim)
			return
		if rounds <= 0 and absi(target.st.x - p.st.x) + absi(target.st.y - p.st.y) == 1:
			_stop(p)
			_face(p, there)
			if p.slots.has(Net.ITEM_BATON):
				p.hand = p.slots.find(Net.ITEM_BATON)
			if now >= p.ready_tick and Items.INFO.has(p.in_hand()) and Items.INFO[p.in_hand()].has("blow"):
				server.combat.use_at(p, now, there)
			return
	# otherwise walk: to the one it hunts, to where it heard something, or about the ship
	if p.ai_goal == Vector2i(p.st.x, p.st.y) or p.ai_goal.x < 0:
		p.ai_goal = _somewhere(p)
	if now - p.ai_plan_tick >= PLAN_EVERY or p.st.dir == Net.DIR_NONE:
		p.ai_plan_tick = now
		p.ai_step = _first_step(p, p.ai_goal)
		if p.ai_step == 0:
			p.ai_goal = Vector2i(-1, -1)                  # nowhere to go from here: choose again
	if p.st.cd > 0:
		return
	if p.ai_step == -1:
		_stop(p)
		server.movement.climb(p)
		p.ai_plan_tick = 0
	else:
		p.st.dir = p.ai_step


func _stop(p) -> void:
	p.st.dir = Net.DIR_NONE


func _face(p, there: Vector2) -> void:
	## Turns towards a place (only when not in mid-step).
	if p.st.cd > 0:
		return
	var v: Vector2 = there - Vector2(p.st.x, p.st.y)
	if absf(v.x) >= absf(v.y):
		p.st.facing = Net.DIR_RIGHT if v.x > 0 else Net.DIR_LEFT
	else:
		p.st.facing = Net.DIR_DOWN if v.y > 0 else Net.DIR_UP


func _step_away(p, from: Vector2) -> void:
	var map = server.map
	var best := 0
	var far: float = Vector2(p.st.x, p.st.y).distance_to(from)
	for d in range(1, 5):
		var nx: int = p.st.x + Net.DX[d]
		var ny: int = p.st.y + Net.DY[d]
		if _passable(nx, ny) and Vector2(nx, ny).distance_to(from) > far:
			far = Vector2(nx, ny).distance_to(from)
			best = d
	p.st.dir = best


func _passable(x: int, y: int) -> bool:
	var map = server.map
	if not map.walkable(x, y):
		return false
	var d: int = map.door_at(x, y)
	return d < 0 or not server.doors.is_sealed(d)


func _somewhere(p) -> Vector2i:
	## A walkable cell anywhere aboard to wander to.
	var map = server.map
	for attempt in 30:
		var x: int = _rng.randi_range(0, map.width - 1)
		var y: int = _rng.randi_range(0, map.height - 1)
		if map.walkable(x, y) and map.door_at(x, y) < 0:
			return Vector2i(x, y)
	return Vector2i(p.st.x, p.st.y)


func _first_step(p, goal: Vector2i) -> int:
	## The first step of the shortest way to `goal`: a direction (1..4), -1 to
	## take the ladder it stands on, 0 if there is no way. Walks the ship's
	## grid, ladders included, around shutters that are down.
	var map = server.map
	var start: int = p.st.y * map.width + p.st.x
	var end: int = goal.y * map.width + goal.x
	if goal.x < 0 or start == end:
		return 0
	var first: Dictionary = {start: 0}
	var queue: PackedInt32Array = PackedInt32Array([start])
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		var x: int = cell % map.width
		var y: int = cell / map.width
		var nexts: Array = []
		for d in range(1, 5):
			if _passable(x + Net.DX[d], y + Net.DY[d]):
				nexts.append([(y + Net.DY[d]) * map.width + x + Net.DX[d], d])
		if map.climb[cell] >= 0:
			nexts.append([map.climb[cell], -1])
		for n: Array in nexts:
			var to: int = n[0]
			if first.has(to):
				continue
			first[to] = n[1] if cell == start else first[cell]
			if to == end:
				return first[to]
			queue.append(to)
	return 0
