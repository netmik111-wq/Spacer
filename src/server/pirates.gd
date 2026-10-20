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
const FRIEND_CLEAR := 0.8            # cells: one of its own side this close to the line of fire stops it shooting
const FLEE_BELOW := 30.0             # health under which it falls back
const MAX_ABOARD := 4
# (v62, the author's K12) boarders who come over by docking or by teleport are not all in sealed suits:
const BARE_FROM := 3                 # from this many jumps out...
const BARE_SHARE := 0.35             # ... this share come without a suit: they breathe the air (venting kills them)
const HEAVY_FROM := 6                # from this many jumps out...
const HEAVY_SHARE := 0.15            # ... this share are heavy stormtroopers: no suit, armour that takes half of every wound
const HEAVY_TOUGHNESS := 0.5
const ROBOT_MAGS := 3                # (v62) an assault drone's built-in gun reloads this many times

# (v70, the author's B1: "boarders should come for something, not only to fight")
# about half of a boarding party come with a goal: to wreck a machine, rob the
# supply locker, plant a bomb or drag one of ours off. A pirate with a goal fights
# only who comes close (GOAL_FIGHT_REACH) or hurts it, else it goes about its work.
const GOAL_NONE := 0
const GOAL_WRECK := 1
const GOAL_ROB := 2
const GOAL_BOMB := 3
const GOAL_DRAG := 4
const GOAL_LEAVE := 5                # done (loot in its pockets): back out the way it came
const GOAL_SHARE := 0.5              # of a party, this share come with a goal
const GOAL_FIGHT_REACH := 4.0        # cells: closer than this, a pirate with a goal fights
const ANGRY_SECONDS := 8.0           # hurt, it fights back this long, goal or not
const WRECK_SECONDS := 8.0           # at a machine, it is broken after this long
const ROB_SECONDS := 5.0             # at the locker, this long to fill its pockets
const ROB_TAKES := 3                 # things it takes from the locker
const PLANT_SECONDS := 2.0           # to set a bomb
const BOMB_SECONDS := 30.0           # from setting to the blast
const BOMB_BEEP := 2.0               # seconds between its beeps
const DEFUSE_SECONDS := 5.0          # held E to disarm it (an engineer, half)
const BOMB_DAMAGE := 25              # to everyone in the room of the blast (within BOMB_REACH)
const BOMB_REACH := 3.0              # cells
const DRAG_LOOK := 14                # cells (along the grid): how far it looks for one of ours lying
const PARTY_GAP := 40                # ticks: boarders this close together are one party

var server: Node
var count := 0                       # pirates sent aboard so far (for their names)
var _rng := RandomNumberGenerator.new()
var bombs := {}                      # (v70) floor cell -> the tick it goes off
var goals_on := true                 # (tests: false = boarders come with no goals)
var _party_tick := -1000             # when the last boarder came aboard (for one party's goals)
var _party_bomb := false             # a bomb is already somebody's goal in this party
var _party_drag := false


func setup(p_server: Node) -> void:
	server = p_server
	count = 0
	bombs = {}
	_rng.randomize()


func aboard() -> int:
	## Pirates aboard and still on their feet or not yet dead.
	var n := 0
	for q in server.players:
		if q != null and q.pirate and not q.corpse and not q.prisoner:
			n += 1
	return n


func board(how_many: int) -> bool:
	## A boarding party cuts its way in through the hull and comes aboard.
	## (v62) Those who cut in always wear sealed suits: the hole lets the air out.
	var map = server.map
	if how_many <= 0:
		return false
	var inside := cut_in()
	if inside.x < 0:
		return false
	for i in mini(how_many, MAX_ABOARD):
		give_goal(spawn(inside.x, inside.y, _rng.randf() < 0.6))
	server.chat.alarm("Тревога! Абордаж: пираты прорезали обшивку и идут на борт (%s, их %d)." % [
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
	p.way_in = y * server.map.width + x
	server.crew.announce_join(p, null)
	return p


func spawn_boarder(x: int, y: int, gunner: bool, far: int = -1):
	## (v62) A boarder who comes over by docking or by teleport: by how far out we are,
	## now and then one without a sealed suit, or a heavy stormtrooper (the author's K12).
	var p = spawn(x, y, gunner)
	if far < 0:
		far = server.sectors.far_from_start(server.ship.sector) if server.sectors.count > 0 else 0
	var roll := _rng.randf()
	if far >= HEAVY_FROM and roll < HEAVY_SHARE:
		p.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
		p.toughness = HEAVY_TOUGHNESS
		p.colour = Net.ARMOUR_COLOUR
		p.name = "Штурмовик %d" % count
		server.crew.announce_join(p, null)
	elif far >= BARE_FROM and roll < HEAVY_SHARE + BARE_SHARE:
		p.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	give_goal(p)
	return p


func spawn_robot(x: int, y: int, what: String = "Штурмовой дрон"):
	## (v62) An enemy robot in that cell: a drone ship's assault drone or guard.
	## A machine: it needs no air, wears nothing and fights with a built-in gun.
	count += 1
	var p = server.crew.alloc("%s %d" % [what, count])
	p.pirate = true
	p.robot = true
	p.colour = Net.ROBOT_COLOUR
	p.worn.fill(Net.ITEM_NONE)
	p.st.place(x, y)
	p.add(Net.ITEM_PISTOL + Net.PISTOL_ROUNDS, true)
	for i in ROBOT_MAGS:
		p.add(Net.ITEM_MAG)
	p.ai_fire_tick = server.tick + _rng.randi_range(10, 30)
	server.crew.announce_join(p, null)
	return p


func cut_in() -> Vector2i:
	## (v62) A hole cut through our hull where a boarder can step in: the cell
	## inside it (-1, -1 if there is no whole hull to cut).
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
	if ways.is_empty():
		return Vector2i(-1, -1)
	var way: Array = ways[_rng.randi_range(0, ways.size() - 1)]
	server.systems.breach(way[0])
	return way[1]


func foe(p, q) -> bool:
	## (v62) Is `q` one that `p` fights? Pirates (and their robots) fight our
	## people and our security robots; our robots fight pirates.
	if q == null or q == p or q.corpse or q.prisoner or q.taken:
		return false                         # (v70) nobody fights a prisoner
	return q.pirate if p.ally else not q.pirate


func heard(p, x: int, y: int) -> void:
	## A pirate heard the crew: if it has nobody in sight, it goes to look.
	if p.ai_target < 0:
		p.ai_goal = Vector2i(x, y)


func attacked(p, by) -> void:
	## Whoever hurts a pirate becomes the one it is after (v62: and a pirate who
	## hurts our security robot, the one it is after).
	if by.corpse or by.pirate == p.pirate:
		return
	p.angry_until = server.tick + roundi(ANGRY_SECONDS * Net.TICK_HZ)   # (v70) goal or not, it fights back
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


func _friend_in_way(p, there: Vector2) -> bool:
	## Would a shot at `there` pass through one of its own side first? Then it
	## holds fire and moves (a bullet hits whoever it meets first: our robot kept
	## shooting the crewman who stood between it and a pirate).
	var from := Vector2(p.st.x, p.st.y)
	var way: Vector2 = there - from
	var dist := way.length()
	if dist < 0.1:
		return false
	way /= dist
	for q in server.players:
		if q == null or q == p or q.corpse or q.cond == Net.COND_DEAD or foe(p, q):
			continue
		if server.map.deck_of(q.st.y) != server.map.deck_of(p.st.y):
			continue
		var pos := Vector2(q.st.x, q.st.y)
		var along: float = (pos - from).dot(way)
		if along > 0.2 and along < dist and (pos - (from + way * along)).length() <= FRIEND_CLEAR:
			return true
	return false


func think(p) -> void:
	## One tick of a pirate's mind. It only chooses where to go and when to
	## use what it holds; walking is the same as for anybody else.
	if p.cond != Net.COND_OK or p.health <= 0.0:
		return                               # (a wound that just felled it is taken account of this tick)
	p.using = false                          # (v66) set again below while it forces an airlock door
	var now: int = server.tick
	var busy: bool = has_goal(p) and now >= p.angry_until
	var reach: float = GOAL_FIGHT_REACH if busy else 1e9
	if p.dragging >= 0:
		reach = -1.0                         # (v70) hauling one of ours off: it does not stop to fight
	# who to go after: keep the one it has while it can see them, else the nearest it can see
	if (now + p.slot) % SEE_EVERY == 0 or p.ai_target < 0:
		var target = server.players[p.ai_target] if p.ai_target >= 0 and p.ai_target < server.players.size() else null
		if target == null or target.corpse or target.cond != Net.COND_OK or not _sees(p, target) \
				or Vector2(target.st.x, target.st.y).distance_to(Vector2(p.st.x, p.st.y)) > reach:
			p.ai_target = -1
			var best := 1e9
			for q in server.players:
				if not foe(p, q) or q.cond != Net.COND_OK or not _sees(p, q):
					continue
				var d: float = Vector2(q.st.x, q.st.y).distance_to(Vector2(p.st.x, p.st.y))
				if d > reach:
					continue
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
	# badly hurt: patch itself up if it can, else fall back from whoever it fights (a machine does not)
	if p.health < FLEE_BELOW and not p.robot:
		var patch: int = p.slots.find(Net.ITEM_MEDPATCH)
		if patch >= 0 and p.wounds > 0.0 and now >= p.ready_tick:
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
		if rounds > 0 and dist <= SHOOT_FROM and not _friend_in_way(p, there):
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
	# (v70) a pirate with a goal goes about it
	if target == null and has_goal(p) and _pursue(p):
		return
	# otherwise walk: to the one it hunts, to where it heard something, or about the ship
	if p.ai_goal == Vector2i(p.st.x, p.st.y) or p.ai_goal.x < 0:
		p.ai_goal = _post(p) if p.home >= 0 or p.hold >= 0 else _somewhere(p)
		if p.ai_goal == Vector2i(p.st.x, p.st.y):
			_stop(p)
			return                           # (v55) back at its post on its own ship: it stays
	# (v73) worked out again before each new step too: a way kept for PLAN_EVERY ticks
	# took a quick step past the goal, and near it the pirate could pace back and
	# forth for good (a pirate in the airlock chamber never got aboard, 1 run in 200)
	var cell_now: int = p.st.y * server.map.width + p.st.x
	if now - p.ai_plan_tick >= PLAN_EVERY or p.st.dir == Net.DIR_NONE \
			or (p.st.cd <= 1 and cell_now != p.ai_plan_cell):
		p.ai_plan_tick = now
		p.ai_plan_cell = cell_now
		p.ai_step = _first_step(p, p.ai_goal)
		if p.ai_step == 0:
			p.ai_goal = Vector2i(-1, -1)                  # nowhere to go from here: choose again
	# (v70) cd 1 is a step's last tick: the next step starts right after this think. (Waiting
	# for cd 0, a walking pirate turned only against a wall, so it kept going straight.)
	if p.st.cd > 1:
		return
	if p.ai_step > 0:
		# (v66) an airlock door in the way that will not open: it is forced by hand;
		# (v70) so is any shutter down in a boarder's way (the hole it cut drops the
		# room's shutters: before, it stayed shut in there for good)
		var door: int = server.map.door_at(p.st.x + Net.DX[p.ai_step], p.st.y + Net.DY[p.ai_step])
		var bars: bool = server.systems.lock_bars(door) or (not p.ally and door >= 0 and server.doors.is_sealed(door))
		if bars and server.systems.get_past(p, door, false):
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


func _passable(x: int, y: int, suited: bool = false, forces: bool = false) -> bool:
	## (v66) Airlock doors are forced when need be; in a suit open space will do too.
	## (v70) `forces`: a boarder forces any shutter in its way (our robots do not).
	var map = server.map
	if not map.walkable(x, y):
		return suited and map.floats(x, y)
	var d: int = map.door_at(x, y)
	return d < 0 or forces or not server.doors.is_sealed(d) or server.systems.lock_door(d)


func _post(p) -> Vector2i:
	## (v55) Its post on its own ship, in our grid (where it stands if that ship has gone);
	## (v57) or the cell of our bridge it was put aboard to hold.
	if p.hold >= 0:
		return Vector2i(p.hold % server.map.width, p.hold / server.map.width)
	var d = server.derelict
	if not d.here or server.map.other == null:
		p.home = -1
		return Vector2i(p.st.x, p.st.y)
	var c: int = d._cell(server.map.other_at, p.home)
	return Vector2i(c % server.map.width, c / server.map.width)


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
	var suited: bool = p.has_suit()
	var forces: bool = not p.ally
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
			if _passable(x + Net.DX[d], y + Net.DY[d], suited, forces):
				nexts.append([(y + Net.DY[d]) * map.width + x + Net.DX[d], d])
		if map.climb[cell] >= 0 and not map.floats(x, y):
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


# ------------------------------------------------------------ (v70) boarders' goals

func give_goal(p) -> void:
	## By lot, a boarder on our ship comes for something: about half of a party, at
	## most one bomb and one kidnapping in each.
	if p == null or p.robot or not goals_on:
		return
	if server.tick - _party_tick > PARTY_GAP:
		_party_bomb = false
		_party_drag = false
	_party_tick = server.tick
	p.goal = GOAL_NONE
	p.goal_cell = -1
	p.goal_work = 0
	if _rng.randf() >= GOAL_SHARE:
		return
	var can: Array = []
	if not _wreck_targets().is_empty():
		can.append(GOAL_WRECK)
	if not server.map.locker.is_empty():
		can.append(GOAL_ROB)
	if not _party_bomb:
		can.append(GOAL_BOMB)
	if not _party_drag:
		can.append(GOAL_DRAG)
	if can.is_empty():
		return
	p.goal = can[_rng.randi_range(0, can.size() - 1)]
	_party_bomb = _party_bomb or p.goal == GOAL_BOMB
	_party_drag = _party_drag or p.goal == GOAL_DRAG


func has_goal(p) -> bool:
	## Goals are for boarders on our own ship (not the pirate ship's crew at home,
	## nor the flagship's), and not for our robots.
	return p.goal != GOAL_NONE and p.pirate and not p.robot and p.home < 0 and p.hold < 0 and p.way_in >= 0


func _wreck_targets() -> Array:
	## Machines a boarder may wreck: the engine (while the escape rule lets it),
	## the air plant, the shield generator and our guns, never the bridge consoles.
	var map = server.map
	var out: Array = []
	if server.systems.can_break("engine"):
		out.append_array(map.engine.keys())
	out.append_array(map.air_plant.keys())
	out.append_array(map.shield.keys())
	for i in map.guns.size():
		if server.ship.mounts[i] != 0:
			out.append(map.guns[i])
	return out.filter(func(c: int) -> bool: return not server.ship.broken.has(c) and not server.stations._spots_for(c).is_empty())


func _nearest(p, cells: Array) -> int:
	var best := -1
	var best_d := 1 << 30
	var w: int = server.map.width
	for c: int in cells:
		var d: int = absi(c % w - p.st.x) + absi(c / w - p.st.y) + (1000 if server.map.deck_of(c / w) != server.map.deck_of(p.st.y) else 0)
		if d < best_d:
			best_d = d
			best = c
	return best


func _spot(p, target: int) -> Array:
	## Where to stand to work on that machine: [cell, facing], the one nearest it; [] if none.
	var spots: Array = server.stations._spots_for(target)
	if spots.is_empty():
		return []
	var w: int = server.map.width
	var here: int = p.st.y * w + p.st.x
	for s: Array in spots:
		if int(s[0]) == here:
			return s
	return spots[0]


func _pursue(p) -> bool:
	## One tick of a pirate going about its goal. True when it is at work (it
	## needs no walking this tick); false when it sets `ai_goal` for the walk (or
	## has given its goal up).
	var map = server.map
	var w: int = map.width
	var here: int = p.st.y * w + p.st.x
	match p.goal:
		GOAL_WRECK, GOAL_BOMB, GOAL_ROB:
			if p.goal_cell < 0 or (p.goal != GOAL_ROB and server.ship.broken.has(p.goal_cell)):
				var pick: Array = map.locker.keys() if p.goal == GOAL_ROB else _wreck_targets()
				p.goal_cell = _nearest(p, pick)
				p.goal_work = 0
				if p.goal_cell < 0:
					p.goal = GOAL_NONE
					return false
			var spot := _spot(p, p.goal_cell)
			if spot.is_empty():
				p.goal = GOAL_NONE
				return false
			if int(spot[0]) != here:
				p.goal_work = 0
				p.ai_goal = Vector2i(int(spot[0]) % w, int(spot[0]) / w)
				return false
			_stop(p)
			p.st.facing = int(spot[1])
			p.goal_work += 1
			if p.goal_work % Net.TICK_HZ == 0:
				server.chat.sound(Net.SOUND_BLOW, p.st.x, p.st.y, p.slot)
			var need: float = WRECK_SECONDS if p.goal == GOAL_WRECK else (ROB_SECONDS if p.goal == GOAL_ROB else PLANT_SECONDS)
			if p.goal_work >= roundi(need * Net.TICK_HZ):
				match p.goal:
					GOAL_WRECK:
						wreck(p.goal_cell)
						p.goal = GOAL_NONE
					GOAL_ROB:
						_rob(p)
						p.goal = GOAL_LEAVE
					GOAL_BOMB:
						plant(here)
						p.goal = GOAL_NONE
				p.goal_work = 0
			return true
		GOAL_DRAG:
			if p.dragging >= 0:
				if here == p.way_in:
					_take_away(p)
					return true
				p.ai_goal = Vector2i(p.way_in % w, p.way_in / w)
				return false
			var victim = _victim(p)
			if victim == null:
				return false                 # nobody down yet: it roams and fights as any other
			if absi(victim.st.x - p.st.x) + absi(victim.st.y - p.st.y) <= 1 and p.st.cd == 0:
				_stop(p)
				p.dragging = victim.slot
				victim.dragged_by = p.slot
				p.st.slow = true
				victim.st.slow = true
				server.chat.say("%s хватает %s и тащит к пробоине!" % [p.name, victim.name])
				return true
			p.ai_goal = Vector2i(victim.st.x, victim.st.y)
			return false
		GOAL_LEAVE:
			if here == p.way_in:
				var took := PackedStringArray()
				for item in p.slots:
					if item != Net.ITEM_NONE and not Items.is_weapon(item) and item != Net.ITEM_MAG and item != Net.ITEM_MEDPATCH:
						took.append(Items.name_of(item).to_lower())
				server.chat.say("%s уходит с добычей%s." % [p.name, (": " + ", ".join(took)) if not took.is_empty() else ""])
				server.crew.remove(p)
				return true
			p.ai_goal = Vector2i(p.way_in % w, p.way_in / w)
			return false
	return false


func _victim(p):
	## One of ours lying (out cold or dead, not a body left behind) that nobody hauls, nearest first.
	var best = null
	var best_d := DRAG_LOOK + 1
	for q in server.players:
		if q == null or q.pirate or q.ally or q.corpse or q.taken or q.cond == Net.COND_OK or q.dragged_by >= 0:
			continue
		if server.map.deck_of(q.st.y) != server.map.deck_of(p.st.y) or not server.map.on_ship(q.st.y * server.map.width + q.st.x):
			continue
		var d: int = absi(q.st.x - p.st.x) + absi(q.st.y - p.st.y)
		if d < best_d:
			best_d = d
			best = q
	return best


func _take_away(p) -> void:
	## Out through the hole it came in by, with one of ours: he is lost to us (a
	## player comes back from the reserve as after a death; no body is left).
	var victim = server.players[p.dragging] if p.dragging < server.players.size() else null
	server.looting.let_go(p)
	if victim != null:
		victim.taken = true
		victim.health = Net.HEALTH_DEAD - 1.0
		victim.cond = Net.COND_DEAD
		victim.died_tick = server.tick
		victim.st.down = true
		victim.st.dir = Net.DIR_NONE
		victim.supply = false
		victim.self_dirty = true
		for q in server.players:
			if q != null and q.searching == victim.slot:
				server.looting.stop_search(q)
		server.chat.say("Пираты утащили %s к себе на корабль! Его уже не вернуть." % victim.name)
	server.crew.remove(p)


func _rob(p) -> void:
	## Its pockets filled from the supply locker (the store), what fits.
	var store: Dictionary = server.ship.store
	var took := PackedStringArray()
	for i in ROB_TAKES:
		var kinds: Array = store.keys().filter(func(k: int) -> bool: return int(store[k]) > 0)
		if kinds.is_empty() or p.slots.find(Net.ITEM_NONE) < 0:
			break
		var item: int = kinds[_rng.randi_range(0, kinds.size() - 1)]
		store[item] = int(store[item]) - 1
		p.add(item)
		took.append(Items.name_of(item).to_lower())
	if took.is_empty():
		server.chat.say("%s роется в шкафу снабжения, но брать там нечего." % p.name)
		return
	server.supplies.tell_store()
	server.chat.say("Пираты грабят шкаф снабжения! %s уносит: %s. Перехватите его, пока не ушёл." % [p.name, ", ".join(took)])


func wreck(cell: int) -> void:
	## A machine put out of order by hand.
	var map = server.map
	if cell < 0 or server.ship.broken.has(cell):
		return
	if map.engine.has(cell) and not server.systems.can_break("engine"):
		return
	server.ship.broken[cell] = true
	server.to_all(server.ship.devices_packet())
	if map.engine.has(cell):
		server.systems.power_changed()
	server.chat.say("Пираты ломают: %s не работает!" % map.device_name(cell))


func plant(cell: int) -> void:
	if not server.put_on_floor(cell, Net.ITEM_BOMB):
		return
	bombs[cell] = server.tick + roundi(BOMB_SECONDS * Net.TICK_HZ)
	var map = server.map
	server.chat.alarm("Пираты заложили бомбу (%s)! До взрыва %d с: держите E над ней, чтобы обезвредить." % [
		map.deck_names[map.deck_of(cell / map.width)].to_lower(), roundi(BOMB_SECONDS)])


func bomb_by(p) -> int:
	## The bomb in the cell in front of this character or underfoot (-1: none).
	if bombs.is_empty():
		return -1
	var here: int = p.st.y * server.map.width + p.st.x
	var ahead: int = server.map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	for c: int in [ahead, here]:
		if bombs.has(c):
			return c
	return -1


func defuse_ticks(p) -> int:
	return roundi(DEFUSE_SECONDS * Net.TICK_HZ * (0.5 if p.job == Net.JOB_ENGINEER else 1.0))


func defuse(p, cell: int) -> void:
	_lift_bomb(cell)
	server.chat.say("%s обезвреживает бомбу." % p.name)


func _lift_bomb(cell: int) -> void:
	bombs.erase(cell)
	var things: PackedByteArray = server.floor_things.get(cell, PackedByteArray())
	var at := things.find(Net.ITEM_BOMB)
	if at >= 0:
		things[at] = Net.ITEM_NONE
		if things.count(Net.ITEM_NONE) == Net.FLOOR_STACK:
			server.floor_things.erase(cell)
		else:
			server.floor_things[cell] = things
		server.replication.floor_record(cell)


func tick() -> void:
	## (v70) The pirates' bombs beep and go off.
	if bombs.is_empty():
		return
	var w: int = server.map.width
	for cell: int in bombs.keys():
		var at: int = bombs[cell]
		if server.tick >= at:
			_burst(cell)
		elif (at - server.tick) % roundi(BOMB_BEEP * Net.TICK_HZ) == 0:
			server.chat.sound(Net.SOUND_BEEP, cell % w, cell / w)


func _burst(cell: int) -> void:
	var map = server.map
	var w: int = map.width
	var at := Vector2(cell % w, cell / w)
	_lift_bomb(cell)
	server.combat.jolt(Net.JOLT_HEAVY, 0, at)
	server.combat.flash(cell)
	# the nearest hull within reach is torn open, the nearest machine broken
	var hull := -1
	var hull_d := BOMB_REACH + 0.5
	for c: int in map.hull:
		if map.deck_of(c / w) == map.deck_of(cell / w) and not server.air.holes.has(c):
			var d := Vector2(c % w, c / w).distance_to(at)
			if d < hull_d:
				hull_d = d
				hull = c
	if hull >= 0:
		server.systems.breach(hull)
	var machines: Array = _wreck_targets().filter(func(c: int) -> bool: return Vector2(c % w, c / w).distance_to(at) <= BOMB_REACH + 0.5)
	if not machines.is_empty():
		wreck(_nearest_to(cell, machines))
	for q in server.players:
		if q == null or q.corpse or q.cond == Net.COND_DEAD or map.deck_of(q.st.y) != map.deck_of(cell / w):
			continue
		if Vector2(q.st.x, q.st.y).distance_to(at) <= BOMB_REACH:
			server.combat.hurt(q, BOMB_DAMAGE, null, server.combat.CAUSE_BLAST)
	server.chat.say("Взрыв бомбы! %s." % _cap(map.deck_names[map.deck_of(cell / w)]))


func _nearest_to(cell: int, cells: Array) -> int:
	var w: int = server.map.width
	var best: int = cells[0]
	for c: int in cells:
		if Vector2(c % w, c / w).distance_to(Vector2(cell % w, cell / w)) < Vector2(best % w, best / w).distance_to(Vector2(cell % w, cell / w)):
			best = c
	return best


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)
