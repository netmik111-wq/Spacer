extends RefCounted
## The pirate ship's own crew at their posts while it fights us (v54, the
## author: "the probe also shows their crew moving through their rooms").
## Server only.
##
## Each of its crew stands on a cell of its drawing (the enemy ship's ShipMap,
## its own coordinates, so moving the ship alongside changes nothing) and walks
## room to room. Twice a second they look again at who goes where: one flies
## first to mend what our hits knocked out, then one flies the ship from its
## cockpit, the next mend what is worn (what it needs most first, as Gunnery
## says), then man its guns and its shield generator; whoever is left rests in
## its quarters. A wounded one lies low in
## the quarters for a while. What they do counts (Gunnery asks): its guns charge
## slower with nobody at them, it cannot dodge or charge its jump with nobody in
## its cockpit, and a worn system is mended only while somebody stands in its
## room, faster with two.
##
## Our hits find them: a shot that gets through into a room may kill or wound
## whoever is in it (Gunnery.crew_killed keeps its count of the crew in step).
## We see them only for a while after a probe, or near our drone (Drone.sees).

const Net := preload("res://src/shared/net.gd")

const STEP_TICKS := 6                # one step of theirs: a little slower than ours
const PLAN_TICKS := 10               # how often they look again at who goes where
const PROBE_SECONDS := 20.0          # a probe shows them this long (the author's word: "about 20 s")
const HURT_SECONDS := 12.0           # a wounded one lies low this long
const KILL_CHANCE := 0.3             # a hit that gets through into a room: each one in it dies this often...
const WOUND_CHANCE := 0.4            # ... or else is wounded this often
const MENDERS := 2                   # at most this many mend one system together

var server: GameServer
var o = null                         # the enemy's drawing (a ShipMap); null while no enemy is here
var at := PackedInt32Array()         # per one of them: the cell of the drawing it stands on
var dest := PackedInt32Array()       # the cell it walks to
var job := PackedInt32Array()        # the system (Net.ESYS_*) whose room it is at or going to; ESYS_CREW = resting
var mends := PackedByteArray()       # 1 = it goes to mend that system (else it mans it)
var hurt_until := PackedInt32Array() # the tick it is fit again
var probe_until := 0                 # the tick a probe stops showing them
var _next_step := PackedInt32Array()
var _passable := PackedByteArray()   # per cell of the drawing: 1 = they (and the drone) can stand there
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	_rng.randomize()
	clear()


func clear() -> void:
	o = null
	at = PackedInt32Array()
	dest = PackedInt32Array()
	job = PackedInt32Array()
	mends = PackedByteArray()
	hurt_until = PackedInt32Array()
	_next_step = PackedInt32Array()
	probe_until = 0


func board(count: int, layout: int) -> void:
	## A pirate ship comes: its crew stand at their posts.
	clear()
	if layout < 0 or layout >= server.map.others.size():
		return
	o = server.map.others[layout]
	_passable = PackedByteArray()
	_passable.resize(o.cells.size())
	for c in o.cells.size():
		_passable[c] = 1 if o.cells[c] >= 0 and (o.walk[c] == 1 or o.door_of[c] >= 0) else 0
	var posts := [Net.ESYS_HELM, Net.ESYS_WEAPONS, Net.ESYS_SHIELDS]
	for i in count:
		var system: int = posts[i] if i < posts.size() else Net.ESYS_CREW
		var room: int = server.gunnery.room_of_system(system)
		if room < 0:
			system = Net.ESYS_CREW
			room = server.gunnery.room_of_system(system)
		var cell := _free_cell(room)
		if cell < 0:
			cell = _any_floor()
		at.append(cell)
		dest.append(cell)
		job.append(system)
		mends.append(0)
		hurt_until.append(0)
		_next_step.append(0)


func count() -> int:
	return at.size()


func room_of(i: int) -> int:
	return o.room_of[at[i]] if o != null else -1


func hurt(i: int) -> bool:
	return server.tick < hurt_until[i]


func in_room(room: int) -> int:
	## How many fit ones stand in that room now.
	var n := 0
	for i in at.size():
		if room >= 0 and room_of(i) == room and not hurt(i):
			n += 1
	return n


func manned(system: int) -> bool:
	## Is anybody fit at that system's post (in its room)? Always, if we cannot tell.
	if o == null:
		return true
	return in_room(server.gunnery.room_of_system(system)) > 0


func menders(system: int) -> int:
	## How many are mending that system now (fit, sent to mend it, and in its room).
	var room: int = server.gunnery.room_of_system(system)
	var n := 0
	for i in at.size():
		if job[i] == system and mends[i] == 1 and room_of(i) == room and not hurt(i):
			n += 1
	return mini(n, MENDERS)


func shown() -> bool:
	## Does a probe show them all now?
	return server.tick < probe_until


func tick() -> void:
	var g = server.gunnery
	if o != null and not g.fighting():
		clear()
	if o != null:
		if server.tick % PLAN_TICKS == 0:
			_plan()
		for i in at.size():
			if at[i] != dest[i] and server.tick >= _next_step[i]:
				_next_step[i] = server.tick + STEP_TICKS
				at[i] = _step_towards(at[i], dest[i])
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func hit_room(room: int) -> Array:
	## A shot of ours got through into that room: [killed, wounded] of those in it.
	var killed := 0
	var wounded := 0
	var i := 0
	while i < at.size():
		if room >= 0 and room_of(i) == room:
			var roll := _rng.randf()
			if roll < KILL_CHANCE:
				_remove(i)
				killed += 1
				continue
			if roll < KILL_CHANCE + WOUND_CHANCE:
				hurt_until[i] = server.tick + roundi(HURT_SECONDS * Net.TICK_HZ)
				wounded += 1
		i += 1
	return [killed, wounded]


func keep(alive: int, room: int = -1) -> void:
	## Its crew is down to `alive` (hits on its quarters): those in that room go first.
	while at.size() > maxi(alive, 0):
		var gone := at.size() - 1
		for i in at.size():
			if room >= 0 and room_of(i) == room:
				gone = i
				break
		_remove(gone)


func _remove(i: int) -> void:
	at.remove_at(i)
	dest.remove_at(i)
	job.remove_at(i)
	mends.remove_at(i)
	hurt_until.remove_at(i)
	_next_step.remove_at(i)


func _plan() -> void:
	## Who goes where: the cockpit first, then what needs mending most, then the
	## guns and the shield; the rest (and the wounded) to the quarters.
	var g = server.gunnery
	var needs: Array = []                     # [system, mend]
	for k: int in g.mend_order():
		if g.systems[k] == 0 and g.systems_full[k] > 0:
			needs.append([k, 1])
	needs.append([Net.ESYS_HELM, 0])
	for k: int in g.mend_order():
		if g.systems[k] == 0 and g.systems_full[k] > 0:
			needs.append([k, 1])              # a second pair of hands on what is knocked out
		elif g.systems[k] < g.systems_full[k]:
			needs.append([k, 1])
	needs.append([Net.ESYS_WEAPONS, 0])
	needs.append([Net.ESYS_SHIELDS, 0])
	var free: Array = []
	for i in at.size():
		if not hurt(i):
			free.append(i)
		else:
			_send(i, Net.ESYS_CREW, 0)
	for need: Array in needs:
		var room: int = g.room_of_system(need[0])
		if room < 0 or free.is_empty() or (need[0] == Net.ESYS_SHIELDS and g.systems_full[Net.ESYS_SHIELDS] == 0):
			continue
		# whoever is already on it keeps it; else the nearest
		var best := -1
		for i: int in free:
			if job[i] == need[0] and mends[i] == need[1]:
				best = i
				break
		if best < 0:
			var best_d := INF
			for i: int in free:
				var d := Vector2(at[i] % o.width, at[i] / o.width).distance_squared_to(_room_middle(room))
				if d < best_d:
					best_d = d
					best = i
		free.erase(best)
		_send(best, need[0], need[1])
	for i: int in free:
		_send(i, Net.ESYS_CREW, 0)


func _send(i: int, system: int, mend: int) -> void:
	if job[i] == system and mends[i] == mend and o.room_of[dest[i]] == server.gunnery.room_of_system(system):
		return
	job[i] = system
	mends[i] = mend
	var room: int = server.gunnery.room_of_system(system)
	if room < 0:
		return
	if o.room_of[at[i]] == room:
		dest[i] = at[i]
		return
	var cell := _free_cell(room)
	if cell >= 0:
		dest[i] = cell


func _room_middle(room: int) -> Vector2:
	var cells: PackedInt32Array = o.rooms[room]
	var c: int = cells[cells.size() / 2]
	return Vector2(c % o.width, c / o.width)


func _free_cell(room: int) -> int:
	## A cell of that room nobody stands on or heads for (any cell of it if all are taken).
	if room < 0 or room >= o.rooms.size():
		return -1
	var cells: PackedInt32Array = o.rooms[room]
	var choice := PackedInt32Array()
	for c in cells:
		if not at.has(c) and not dest.has(c):
			choice.append(c)
	if choice.is_empty():
		choice = cells
	return choice[_rng.randi_range(0, choice.size() - 1)] if not choice.is_empty() else -1


func _any_floor() -> int:
	for c in _passable.size():
		if _passable[c] == 1 and o.room_of[c] >= 0:
			return c
	return 0


func passable(cell: int) -> bool:
	return o != null and cell >= 0 and cell < _passable.size() and _passable[cell] == 1


func _step_towards(from: int, to: int) -> int:
	## The next cell on a shortest way from one cell of the drawing to another (a breadth-first search back from the goal).
	var w: int = o.width
	var seen := {to: true}
	var edge := PackedInt32Array([to])
	while not edge.is_empty():
		var next := PackedInt32Array()
		for c in edge:
			for s: int in [1, -1, w, -w]:
				var j := c + s
				if (s == 1 and j % w == 0) or (s == -1 and c % w == 0) or not passable(j) or seen.has(j):
					continue
				if j == from:
					return c
				seen[j] = true
				next.append(j)
		edge = next
	return from


func visible(cell: int) -> bool:
	return shown() or server.drone.sees(cell)


func packet() -> PackedByteArray:
	var id: int = server.derelict.ship.id if server.derelict.ship != null else 0
	var left := clampi(int(ceil(float(probe_until - server.tick) / Net.TICK_HZ)), 0, 255) if o != null else 0
	var out := PackedByteArray([Net.S_ECREW, id & 0xFF, id >> 8, left, 0])
	var n := 0
	for i in at.size():
		if not visible(at[i]):
			continue
		n += 1
		out.append(at[i] & 0xFF)
		out.append(at[i] >> 8)
		out.append((Net.ECREW_MENDING if mends[i] == 1 and room_of(i) == server.gunnery.room_of_system(job[i]) else 0)
			| (Net.ECREW_HURT if hurt(i) else 0))
	out[4] = n
	return out
