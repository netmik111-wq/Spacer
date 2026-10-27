extends RefCounted
## (v92, the author's plan item 0: "the fight stops being turn by turn: it goes in real
## time, the guns come out on the roof and the sides, a bot or a player works each gun;
## the pilot steers the ship himself, like Starsector") The fight's space. Server only.
##
## Inside, every ship is the grid it always was and never turns. Outside, while a pirate
## ship fights us, each ship is a body here: a place, a speed, a heading, and the shape of
## its own drawing from above (ArenaShape). Ours are bodies 0 and 1 (the ships of our
## fleet), the ship alongside is LEAD and its wingman WING. The pilot at the ship's controls
## steers with the keys (C_PILOT); with nobody steering, a bot at the helm flies to the
## battle position the console set, and with nobody at all the ship drifts to a stop. The
## pirates' pilot keeps the range its temper likes, turns its guns on us and runs when beaten.
##
## Guns are turrets where their mounts are (a 'T' in the hull), each with half a circle of
## fire out of its wall (the author's G1). A shot is a real thing in flight: Gunnery says when
## a gun fires and what a shot does when it meets something; here it flies, and meets the
## shield's bubble, the point defence or the hull at a real place. A hit on the hull is a hit
## on the cell of the drawing there (of one of the decks, by lot: the author's G2), so the
## breach, the system and the wounded are where the shot struck. Whoever stands at a mount
## (Mounts.gunner) and takes it (C_TURRET) aims it with the mouse and fires it himself; a bot
## at a mount fires its own gun at the console's target, with a lead and a spread; the gun
## console still fires every gun that bears.
##
## Leaving the fight: our ship out past RADIUS with no pirate near breaks the fight off (the
## author's P3 A); a pirate that runs past it is gone. A boarding ship's docking clock runs
## only while it is close (DOCK_NEAR): a pilot who keeps away keeps it off (the author's B1).
## Ships that meet push each other off and both take a little damage (the author's P4 A).
## Everything here is for the ship fight only: while no pirate fights, nothing exists.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")
const Player := preload("res://src/server/player.gd")

const LEAD := 2                      # the body of the ship alongside (0 and 1: the ships of our fleet)
const WING := 3                      # and of its wingman
const BODIES := 4
const RADIUS := 170.0                # cells from the fight's middle to its edge
const START_RANGE := 70.0            # a pirate comes out of the dark this far off
const WING_RANGE := 95.0
const LEAVE_SECONDS := 3.0           # our ship out past the edge this long, with no pirate near, is out of the fight
const LEAVE_GAP := 60.0              # how far the nearest pirate must be for that
const DOCK_NEAR := 24.0              # a boarding ship's docking clock runs only this close
const BUMP_REST := 2 * Net.TICK_HZ   # ticks between two blows of the same two ships meeting
const BUMP_SPEED := 2.0              # cells a second they must close at for a blow
const PILOT_HOLD := 2 * Net.TICK_HZ  # a pilot's keys count this long after he last sent them
const TURRET_HOLD := Net.TICK_HZ     # and a gunner's aim
const SEND_EVERY := 2                # ticks between two S_ARENA
const DRAG := 0.25                   # share of its speed a ship with no thrust loses a second (its dampers)
const DASH := 6.0                    # cells a second sideways the pilot's evade (Space) gives
const GUN_ARC := PI / 2.0            # a gun turns this far either side of straight out of its wall
const BOT_SPREAD := 0.12             # radians of aim error per unit of a gun's miss chance, for bots and pirates
const FAR_SPREAD := 60.0             # cells at which that error doubles
const GUARD_RANGE := 16.0            # cells off the hull the point defence meets a rocket
const HIT_NEAR := 3.0                # a pirate shot this near the thing it aimed at puts that thing out
const BEAM_RANGE := 90.0             # cells a beam, a tractor or a siphon reaches (bombs too)
const DT := 1.0 / Net.TICK_HZ
# speed (cells a second), thrust (cells a second, a second), turn (radians a second), per pirate class; -1: ours
const STATS := {-1: [6.0, 1.6, 0.35], Net.ECLASS_CUTTER: [9.0, 2.6, 0.6], Net.ECLASS_RAIDER: [7.5, 2.0, 0.45],
	Net.ECLASS_GUNSHIP: [6.0, 1.5, 0.32], Net.ECLASS_CRUISER: [5.0, 1.2, 0.26], Net.ECLASS_BATTLESHIP: [4.5, 1.0, 0.22],
	Net.ECLASS_CARRIER: [4.5, 1.0, 0.22], Net.ECLASS_DRONE: [8.0, 2.4, 0.55]}
# the range a raider likes, by temper (a boarder closes in)
const RANGE_OF := {Net.TEMPER_CALCULATING: 40.0, Net.TEMPER_CAUTIOUS: 55.0, Net.TEMPER_RECKLESS: 25.0, Net.TEMPER_HUNTER: 45.0,
	Net.TEMPER_SIEGE: 50.0, Net.TEMPER_STORM: 30.0, Net.TEMPER_MACHINE: 35.0}
# (C_PILOT) the pilot's keys
const KEY_AHEAD := 1
const KEY_BACK := 2
const KEY_LEFT := 4
const KEY_RIGHT := 8
const SLIDE_LEFT := 16
const SLIDE_RIGHT := 32


class Body:
	var id := 0
	var on := false
	var layout := -1                 # a pirate's drawing (ShipMap.others); -1 for ours
	var shape: RefCounted            # ArenaShape
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0                   # radians; 0 = the bow (the drawing's right) along +x
	var spin := 0.0
	var thrust := 0.0                # -1..1 asked this tick
	var slide := 0.0                 # -1..1 sideways
	var turn := 0.0                  # -1..1
	var stats: Array = [6.0, 1.6, 0.35]
	var guns: Array = []             # per gun: {"cell": its cell in the drawing, "at": Vector2 in the body's frame,
	                                 # "out": angle straight out of its wall, "aim": angle it points at (body's frame),
	                                 # "bears": the target is inside its arc}
	var glued := false               # docked: it rides alongside the ship it boards
	var leave := 0
	var thrusting := false

	func world(local: Vector2) -> Vector2:
		return pos + local.rotated(rot)

	func local(at: Vector2) -> Vector2:
		return (at - pos).rotated(-rot)


var server: GameServer
var enabled := true                  # (tests that want the fight as it was before v92 switch it off)
var hold_pirates := false            # (tests: pirates hold where they are put)
var bodies: Array = []
var shots: Array = []                # each: {"id", "side" 0 ours / 1 theirs, "from" body, "pos", "vel", "ends" tick, "w", "kind",
                                     # "meta" what Gunnery needs when it lands, "seen" bodies whose bubble it met, "guard"}
var pilots: Array = [{}, {}]         # per ship of our fleet: {"keys", "until", "by"}
var turrets: Array = [{}, {}]        # per ship of our fleet: gun -> {"aim": Vector2, "fire": bool, "until", "by"}
var _later: Array = []               # [tick, Callable]: shots of a burst still to leave their guns
var _next_id := 1
var _bumped := {}                    # "a:b" -> the tick those two last met
var _rng := RandomNumberGenerator.new()
var _was_on := false


func setup(p_server: GameServer) -> void:
	server = p_server
	bodies = []
	for i in BODIES:
		var b := Body.new()
		b.id = i
		bodies.append(b)
	shots = []
	_later = []
	pilots = [{}, {}]
	turrets = [{}, {}]
	_was_on = false
	_rng.randomize()


func on() -> bool:
	## Is the fight in space going on now?
	return _was_on


func body(i: int) -> Body:
	return bodies[i] if i >= 0 and i < bodies.size() and (bodies[i] as Body).on else null


func of_ours(ship: int) -> Body:
	return body(ship)


func of_enemy(foe: int) -> Body:
	return body(LEAD + foe)


# ---------------------------------------------------------------- when it starts and ends

func _lead_fights() -> bool:
	var g = server.gunnery
	var d = server.derelict
	return g.enemy_hull > 0 and not g._over and d.here and d.kind == Net.OTHER_PIRATE and not d.wreck


func _wing_fights() -> bool:
	return server.wing.here and int(server.wing.value(1, "enemy_hull")) > 0 and not bool(server.wing.value(1, "_over"))


func tick() -> void:
	var g = server.gunnery
	var want: bool = enabled and g.flies and server.over == Net.OVER_NONE and (_lead_fights() or _wing_fights())
	if not want:
		if _was_on:
			_stop()
		return
	if not _was_on:
		_start()
	_bodies_now()
	for b: Body in bodies:
		if b.on:
			_steer(b)
	for b: Body in bodies:
		if b.on:
			_move(b)
	_glue()
	_bump()
	_aim_turrets()
	_triggers()
	_run_later()
	_fly_shots()
	_docking()
	_edges()
	if server.tick % SEND_EVERY == 0:
		server.to_all(packet())


func _start() -> void:
	_was_on = true
	shots = []
	_later = []
	_bumped = {}
	for b: Body in bodies:
		b.on = false
	var map = server.map
	for i in map.fleet_size():
		var b: Body = bodies[i]
		b.on = true
		b.layout = -1
		b.shape = ArenaShape.of_fleet(map, i)
		b.pos = Vector2(0.0, 0.0 if i == 0 else (bodies[0] as Body).shape.h + 14.0)
		b.vel = Vector2.ZERO
		b.rot = 0.0
		b.spin = 0.0
		b.glued = false
		b.stats = STATS[-1]
		b.guns = []
		server.fleet.use(i)
		for cell: int in map.guns:
			b.guns.append(_gun(b, cell))
		server.fleet.use(0)


func _stop() -> void:
	_was_on = false
	for p: Dictionary in shots:
		_ended(p, Net.MISSED, p["pos"])
	shots = []
	_later = []
	for b: Body in bodies:
		b.on = false
	pilots = [{}, {}]
	turrets = [{}, {}]
	server.to_all(packet())


func _gun(b: Body, cell: int) -> Dictionary:
	var at: Vector2 = b.shape.local_of(cell)
	var out: float = b.shape.outward(cell).angle()
	return {"cell": cell, "at": at, "out": out, "aim": out, "bears": false}


func _bodies_now() -> void:
	## Pirates come into the fight and leave it.
	var lead := _lead_fights()
	_enemy_body(LEAD, lead, server.derelict.layout if lead else -1)
	var wing := _wing_fights()
	_enemy_body(WING, wing, server.wing.layout if wing else -1)


func _enemy_body(i: int, fights: bool, layout: int) -> void:
	var b: Body = bodies[i]
	if not fights or layout < 0 or layout >= server.map.others.size():
		b.on = false
		return
	if b.on and b.layout == layout:
		return
	b.on = true
	b.layout = layout
	b.shape = ArenaShape.of_layout(server.map.others[layout])
	b.glued = false
	b.spin = 0.0
	var klass: int = int(server.wing.value(i - LEAD, "klass"))
	b.stats = STATS.get(klass, STATS[Net.ECLASS_RAIDER])
	var whom := _enemy_target(i)
	var from: Vector2 = whom.pos if whom != null else Vector2.ZERO
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	if i == WING and body(LEAD) != null:
		side = -signf((body(LEAD).pos - from).y) if absf((body(LEAD).pos - from).y) > 1.0 else side
	b.pos = from + Vector2(_rng.randf_range(-25.0, 25.0), side * (WING_RANGE if i == WING else START_RANGE))
	b.vel = Vector2.ZERO
	b.rot = (from - b.pos).angle() + PI / 2.0 * side   # broadside on, more or less
	b.guns = []
	var their: PackedInt32Array = server.map.others[layout].guns
	for cell: int in their:
		b.guns.append(_gun(b, cell))


func _enemy_target(i: int) -> Body:
	## The ship of ours that pirate fights.
	var t := int(server.wing.value(i - LEAD, "target"))
	var b := body(t)
	return b if b != null else body(0)


# ---------------------------------------------------------------- steering

func pilot_asked(p: Player, keys: int) -> void:
	## (C_PILOT) The pilot at the ship's controls holds these keys (KEY_* bits).
	var i: int = server.fleet.on
	if not _was_on or not server.systems.at_console(p, server.map.helm) or i >= pilots.size():
		return
	pilots[i] = {"keys": keys, "until": server.tick + PILOT_HOLD, "by": p}


func dash(ship: int, way: float) -> bool:
	## (the pilot's evade, Space) A push sideways: away from the nearest shot coming (way 0), or as the keys say.
	var b := body(ship)
	if b == null:
		return false
	if way == 0.0:
		way = 1.0
		var best := INF
		for p: Dictionary in shots:
			if int(p["side"]) != 1:
				continue
			var d: float = (p["pos"] as Vector2).distance_to(b.pos)
			if d < best:
				best = d
				way = -1.0 if b.local(p["pos"]).y > 0.0 else 1.0
	b.vel += Vector2(0.0, way * DASH).rotated(b.rot)
	return true


func _steer(b: Body) -> void:
	b.thrust = 0.0
	b.slide = 0.0
	b.turn = 0.0
	if b.glued or (hold_pirates and b.id >= LEAD):
		return
	if b.id < LEAD:
		_steer_ours(b)
	else:
		_steer_theirs(b)


func _steer_ours(b: Body) -> void:
	var pilot: Dictionary = pilots[b.id] if b.id < pilots.size() else {}
	if not pilot.is_empty() and server.tick < int(pilot["until"]):
		server.fleet.use(b.id)
		var still: bool = server.systems.at_console(pilot["by"], server.map.helm)
		server.fleet.use(0)
		if still:
			var k: int = pilot["keys"]
			b.thrust = (1.0 if k & KEY_AHEAD else 0.0) - (1.0 if k & KEY_BACK else 0.0)
			b.turn = (1.0 if k & KEY_RIGHT else 0.0) - (1.0 if k & KEY_LEFT else 0.0)
			b.slide = (1.0 if k & SLIDE_RIGHT else 0.0) - (1.0 if k & SLIDE_LEFT else 0.0)
			return
	pilots[b.id] = {}
	server.fleet.use(b.id)
	var at_helm: bool = server.stations.manned(Net.POST_HELM)
	var pos: int = server.stations.position
	var foe: int = server.gunnery.foe
	server.fleet.use(0)
	var enemy := of_enemy(foe)
	if enemy == null:
		enemy = of_enemy(0) if of_enemy(0) != null else of_enemy(1)
	if not at_helm or enemy == null or server.fleet.is_lost(b.id):
		return                               # nobody flies it: it drifts to a stop
	# a bot (or a player standing idle) at the helm flies to the battle position the console set
	var range := 30.0
	var off := (b.pos - enemy.pos).normalized() if b.pos != enemy.pos else Vector2.UP
	match pos:
		Net.POS_FAR:
			range = 60.0
		Net.POS_FLANK:
			off = Vector2(0.0, 1.0).rotated(enemy.rot)
			if off.dot(b.pos - enemy.pos) < 0.0:
				off = -off
			range = 32.0
		Net.POS_BEHIND:
			off = Vector2(-1.0, 0.0).rotated(enemy.rot)
			range = 28.0
	_fly_to(b, enemy.pos + off * range, _facing(b, enemy.pos), 1.0)


func _steer_theirs(b: Body) -> void:
	var foe := b.id - LEAD
	var g = server.gunnery
	server.wing.use(foe)
	var engine_out: bool = g.down(Net.ESYS_ENGINE)
	var blind: bool = g.down(Net.ESYS_HELM) or not g._manned(Net.ESYS_HELM)
	var running: bool = g.fleeing()
	var held: bool = g.held()
	var temper: int = g.temper
	var raid: bool = g.raid or foe == 1
	server.wing.use(0)
	var whom := _enemy_target(b.id)
	if whom == null or held:
		return
	if engine_out:
		return                               # it drifts
	var range: float = RANGE_OF.get(temper, 40.0)
	if not raid:
		# a boarding ship closes in as its docking clock runs down
		var left := float(server.derelict._pirates_dock_at - server.tick) / Net.TICK_HZ
		range = clampf(left * 1.2, 8.0, 50.0) if server.derelict._pirates_dock_at >= 0 else 10.0
	var off := (b.pos - whom.pos).normalized() if b.pos != whom.pos else Vector2.DOWN
	var face := _facing(b, whom.pos)
	if running:
		off = (b.pos - whom.pos).normalized()
		range = RADIUS * 2.0
		face = off.angle()
	elif not raid and range <= 12.0:
		face = (whom.pos - b.pos).angle()
	# it circles slowly round us so as not to sit still in our sights
	off = off.rotated(0.12 * (1.0 if b.id == LEAD else -1.0))
	_fly_to(b, whom.pos + off * range, face, 1.0, blind)


func _facing(b: Body, at: Vector2) -> float:
	## The heading at which most of its guns bear on that point (the nearest such to where it points now).
	var to := at - b.pos
	if b.guns.is_empty():
		return to.angle()
	var best := b.rot
	var best_n := -1
	var best_turn := INF
	for k in 16:
		var h := TAU * k / 16.0
		var n := 0
		for gun: Dictionary in b.guns:
			if absf(wrapf(to.angle() - (h + float(gun["out"])), -PI, PI)) <= GUN_ARC * 0.85:
				n += 1
		var t := absf(wrapf(h - b.rot, -PI, PI))
		if n > best_n or (n == best_n and t < best_turn):
			best_n = n
			best = h
			best_turn = t
	return best


func _fly_to(b: Body, goal: Vector2, face: float, pace: float, blind: bool = false) -> void:
	var speed: float = float(b.stats[0]) * pace
	var want := ((goal - b.pos) * 0.3).limit_length(speed)
	var need := (want - b.vel).rotated(-b.rot)
	b.thrust = clampf(need.x * 1.5, -1.0, 1.0) if absf(need.x) > 0.2 else 0.0
	b.slide = clampf(need.y * 1.5, -1.0, 1.0) if absf(need.y) > 0.2 else 0.0
	if blind:
		return                               # nobody at its helm: it holds its heading
	var turn_rate: float = b.stats[2]
	var da := wrapf(face - b.rot, -PI, PI)
	var spin_want := clampf(da * 1.2, -turn_rate, turn_rate)
	b.turn = clampf((spin_want - b.spin) / maxf(turn_rate * 0.3, 0.01) + spin_want / turn_rate, -1.0, 1.0)


func _move(b: Body) -> void:
	if b.glued:
		return
	var can := true
	if b.id < LEAD:
		server.fleet.use(b.id)
		can = not server.engine_down() and server.powered() and not server.fleet.is_lost(b.id)
		server.fleet.use(0)
	var speed: float = b.stats[0]
	var accel: float = b.stats[1]
	var turn_rate: float = b.stats[2]
	var push := Vector2.ZERO
	if can:
		push = Vector2(b.thrust * (1.0 if b.thrust > 0.0 else 0.6), b.slide * 0.5).rotated(b.rot) * accel
	b.thrusting = push.length() > 0.01
	b.vel += push * DT
	if not b.thrusting:
		b.vel *= 1.0 - DRAG * DT
	var v := b.vel.length()
	if v > speed:
		b.vel = b.vel * (maxf(speed, v - accel * 2.0 * DT) / v)    # past its top speed (a dash): it eases back
	b.spin = move_toward(b.spin, (b.turn * turn_rate) if can else 0.0, turn_rate * 1.5 * DT)
	b.pos += b.vel * DT
	b.rot = wrapf(b.rot + b.spin * DT, -PI, PI)


func _glue() -> void:
	## A pirate docked to a ship of ours rides alongside it, where its drawing lies in the grid.
	var lead: Body = bodies[LEAD]
	lead.glued = false
	if not lead.on or not server.derelict.docked:
		return
	var ours := body(server.derelict.near)
	var map = server.map
	if ours == null or map.other_at == map.NO_OTHER:
		return
	var them: RefCounted = lead.shape
	var mine: RefCounted = ours.shape
	var centre := Vector2(map.other_at.x + them.x0 + them.w / 2.0, map.local_y(map.other_at.y) + them.r0 + them.h / 2.0)
	var mid := Vector2(mine.x0 + mine.w / 2.0, mine.r0 + mine.h / 2.0)
	lead.glued = true
	lead.pos = ours.world(centre - mid)
	lead.rot = ours.rot
	lead.vel = ours.vel
	lead.spin = 0.0


func _bump() -> void:
	## Ships that meet push each other off; closing fast, both take a little damage.
	for i in BODIES:
		var a: Body = bodies[i]
		if not a.on:
			continue
		for j in range(i + 1, BODIES):
			var b: Body = bodies[j]
			if not b.on or (a.glued and b.id == server.derelict.near) or (b.glued and a.id == server.derelict.near):
				continue
			if a.pos.distance_to(b.pos) > a.shape.radius + b.shape.radius:
				continue
			var inside := 0
			for k in range(0, a.shape.outline.size(), 2):
				if b.shape.solid(b.local(a.world(a.shape.outline[k]))):
					inside += 1
			for k in range(0, b.shape.outline.size(), 2):
				if a.shape.solid(a.local(b.world(b.shape.outline[k]))):
					inside += 1
			if inside == 0:
				continue
			var n := (a.pos - b.pos).normalized() if a.pos != b.pos else Vector2.UP
			var closing := (b.vel - a.vel).dot(n)
			if not a.glued:
				a.pos += n * 0.25
			if not b.glued:
				b.pos -= n * 0.25
			if closing > 0.0:
				if not a.glued:
					a.vel += n * closing * 0.6
				if not b.glued:
					b.vel -= n * closing * 0.6
			var key := "%d:%d" % [i, j]
			if closing > BUMP_SPEED and server.tick - int(_bumped.get(key, -BUMP_REST)) >= BUMP_REST:
				_bumped[key] = server.tick
				_blow(a)
				_blow(b)
				server.chat.say("Корабли столкнулись!")


func _blow(b: Body) -> void:
	if b.id < LEAD:
		server.fleet.use(b.id)
		server.crew.hull_hit(1)
		server.combat.jolt(Net.JOLT_HEAVY, Net.SHOT_SHELL, _grid_spot(b, Vector2.ZERO))
		server.fleet.use(0)
	else:
		server.wing.use(b.id - LEAD)
		server.gunnery.enemy_hull = maxi(server.gunnery.enemy_hull - 1, 0)
		server.gunnery.settle()
		server.wing.use(0)


func _docking() -> void:
	## (the author's B1) A boarding ship's clock to dock runs only while it is close to the ship it boards.
	var lead := body(LEAD)
	var d = server.derelict
	if lead == null or lead.glued or d._pirates_dock_at < 0 or d.docked or server.gunnery.raid:
		return
	var whom := _enemy_target(LEAD)
	if whom != null and lead.pos.distance_to(whom.pos) > DOCK_NEAR + whom.shape.radius:
		d._pirates_dock_at += 1


func _edges() -> void:
	## Out past the edge: our ship leaves the fight (no pirate near), a pirate that runs is gone.
	var lead_ours := body(0)
	if lead_ours != null:
		if lead_ours.pos.length() > RADIUS:
			var nearest := INF
			for i in [LEAD, WING]:
				var e := body(i)
				if e != null:
					nearest = minf(nearest, e.pos.distance_to(lead_ours.pos))
			if nearest > LEAVE_GAP:
				lead_ours.leave += 1
				if lead_ours.leave >= roundi(LEAVE_SECONDS * Net.TICK_HZ):
					_broke_away()
					return
			else:
				lead_ours.leave = 0
		else:
			lead_ours.leave = 0
	for i in [LEAD, WING]:
		var e := body(i)
		if e == null or e.glued or e.pos.length() <= RADIUS * 1.15:
			continue
		var g = server.gunnery
		server.wing.use(i - LEAD)
		if g.fleeing() and g.enemy_hull > 0 and not g._over:
			g._escaped()
		server.wing.use(0)


func _broke_away() -> void:
	## (the author's P3 A) Our ship has left the fight's area: the pirates are left behind.
	var g = server.gunnery
	server.chat.say("Корабль вышел из района боя: пираты отстали.")
	server.road.escaped()
	server.wing.jumped()
	if _lead_fights():
		g.enemy_hull = 0
		g.beam_left.fill(0)
		g.goal_lost = true
		server.derelict.pirates_escaped()
	_stop()


# ---------------------------------------------------------------- guns

func turret_asked(p: Player, gun: int, aim: Vector2, fire: bool) -> void:
	## (C_TURRET) The gunner at a mount aims its gun at a point of the fight's space, and holds the trigger or not.
	var i: int = server.fleet.on
	if not _was_on or i >= turrets.size() or gun < 0 or gun >= server.map.guns.size() or server.mounts.gunner(gun) != p:
		return
	(turrets[i] as Dictionary)[gun] = {"aim": aim, "fire": fire, "until": server.tick + TURRET_HOLD, "by": p}


func manned_by_hand(ship: int, gun: int) -> bool:
	## Does a player aim that gun himself now (then the console and the bots leave it to him)?
	if ship >= turrets.size():
		return false
	var t: Dictionary = (turrets[ship] as Dictionary).get(gun, {})
	return not t.is_empty() and server.tick < int(t["until"])


func _aim_turrets() -> void:
	## Every gun turns to what it means to hit (or as far as its arc lets it).
	for b: Body in bodies:
		if not b.on:
			continue
		for k in b.guns.size():
			var gun: Dictionary = b.guns[k]
			var at := _wanted_point(b, k)
			if not at.is_finite():
				gun["bears"] = false
				continue
			var muzzle := b.world(gun["at"])
			var rel := wrapf((at - muzzle).angle() - b.rot - float(gun["out"]), -PI, PI)
			gun["bears"] = absf(rel) <= GUN_ARC
			gun["aim"] = float(gun["out"]) + clampf(rel, -GUN_ARC, GUN_ARC)


func _wanted_point(b: Body, k: int) -> Vector2:
	## Where gun k of that body means to put its shot now (INF: nothing to aim at).
	if b.id < LEAD:
		var t: Dictionary = (turrets[b.id] as Dictionary).get(k, {}) if b.id < turrets.size() else {}
		if not t.is_empty() and server.tick < int(t["until"]):
			return t["aim"]
		server.fleet.use(b.id)
		var foe: int = server.gunnery.foe
		server.wing.use(foe)
		var room: int = server.gunnery._aimed_room()
		server.wing.use(0)
		server.fleet.use(0)
		var e := of_enemy(foe)
		if e == null:
			e = of_enemy(1 - foe)
			room = -1
		if e == null:
			return Vector2.INF
		return _lead_point(b, b.world(b.guns[k]["at"]), e, _room_point(e, foe, room), Weapons.NONE)
	var whom := _enemy_target(b.id)
	return whom.pos if whom != null else Vector2.INF


func _room_point(e: Body, foe: int, room: int) -> Vector2:
	## The middle of that room of a pirate's drawing, in its body's frame (its middle with no room).
	var lay = server.map.others[e.layout]
	if room < 0 or room >= lay.rooms.size():
		return Vector2.ZERO
	var cells: Array = Array(lay.rooms[room])
	if cells.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for c: int in cells:
		sum += e.shape.local_of(c)
	return sum / cells.size()


func _lead_point(from: Body, muzzle: Vector2, to: Body, local: Vector2, w: int) -> Vector2:
	## Where to aim so that a shot meets that point of a moving ship (twice round is near enough).
	var speed := shot_speed(w) if w != Weapons.NONE else 45.0
	var at := to.world(local)
	var rel := to.vel - from.vel
	for k in 2:
		var t := muzzle.distance_to(at) / speed
		at = to.world(local) + rel * t
	return at


func bears(ship: int, gun: int) -> bool:
	## Does that gun of ours have something to shoot at inside its arc now?
	var b := body(ship)
	return b != null and gun < b.guns.size() and bool(b.guns[gun]["bears"])


func enemy_bears(foe: int, weapon: int) -> bool:
	## Does that gun of a pirate bear on the ship of ours it fights (always, with no mounts drawn)?
	var b := of_enemy(foe)
	if b == null:
		return false
	if b.guns.is_empty():
		return true
	return bool(b.guns[weapon % b.guns.size()]["bears"])


func _triggers() -> void:
	## Guns fired by hand (a player at the mount holding the trigger) and by bots at their mounts.
	var g = server.gunnery
	for i in server.map.fleet_size():
		var b := body(i)
		if b == null:
			continue
		server.fleet.use(i)
		for k in b.guns.size():
			if k >= server.map.guns.size():
				break
			var t: Dictionary = (turrets[i] as Dictionary).get(k, {}) if i < turrets.size() else {}
			var hand := not t.is_empty() and server.tick < int(t["until"])
			if hand:
				if bool(t["fire"]):
					g.fire_mount(t["by"], k)
				continue
			var who = server.mounts.gunner(k)
			if who != null and who.bot and g.fighting() and g.ransom == 0 and bool(b.guns[k]["bears"]):
				g.fire_mount(who, k)
		server.fleet.use(0)


func shot_speed(w: int) -> float:
	## Cells a second a shot of that gun flies.
	if w == Weapons.RAILGUN:
		return 110.0
	match Weapons.klass(w):
		Weapons.CLASS_BLASTER:
			return 32.0
		Weapons.CLASS_ROCKET:
			return 22.0
		Weapons.CLASS_ION:
			return 36.0
		Weapons.CLASS_KINETIC:
			return 55.0
		Weapons.CLASS_NEURAL:
			return 40.0
	return 45.0


func shot_range(w: int) -> float:
	return 110.0 if Weapons.klass(w) == Weapons.CLASS_ROCKET else 85.0


func _spread(w: int) -> float:
	## A gun's own scatter in radians, whoever aims it.
	if Weapons.klass(w) == Weapons.CLASS_BLASTER:
		return 0.08
	if int(Weapons.info(w)["shots"]) >= 4:
		return 0.05
	return 0.012


func reaches(ship: int, gun: int, foe: int) -> bool:
	## (beams, tractors, siphons, bombs) Is that pirate inside the gun's arc and in reach now?
	var b := body(ship)
	var e := of_enemy(foe)
	if b == null or e == null or gun >= b.guns.size():
		return false
	return bool(b.guns[gun]["bears"]) and b.world(b.guns[gun]["at"]).distance_to(e.pos) <= BEAM_RANGE + e.shape.radius


func fire_ours(ship: int, gun: int, w: int, foe: int, room: int, miss: float, delay: int, meta: Dictionary) -> void:
	## Gunnery fires one shot of gun `gun` of that ship of ours (`delay` ticks on, for a burst), at the
	## gunner's mark or, with no hand on it, at that room of the pirate (-1: its middle). `miss`: the
	## chance a plain roll would have missed, which sets how far off a bot's aim is.
	_after(delay, _shoot_ours.bind(ship, gun, w, foe, room, miss, meta))


func _shoot_ours(ship: int, gun: int, w: int, foe: int, room: int, miss: float, meta: Dictionary) -> void:
	var b := body(ship)
	var e := of_enemy(foe)
	if b == null or gun >= b.guns.size():
		server.gunnery.arena_miss({"side": 0, "meta": meta, "w": w}, Vector2(-1, -1))
		return
	var muzzle := b.world(b.guns[gun]["at"])
	var at := Vector2.INF
	var by_hand := manned_by_hand(ship, gun)
	if by_hand:
		at = (turrets[ship] as Dictionary)[gun]["aim"]
	elif e != null:
		at = _lead_point(b, muzzle, e, _room_point(e, foe, room), w)
	var dir: float = b.rot + float(b.guns[gun]["aim"]) if not at.is_finite() else (at - muzzle).angle()
	var rel := wrapf(dir - b.rot - float(b.guns[gun]["out"]), -PI, PI)
	dir = b.rot + float(b.guns[gun]["out"]) + clampf(rel, -GUN_ARC, GUN_ARC)
	var off := _spread(w)
	if not by_hand and at.is_finite():
		off += miss * BOT_SPREAD * (1.0 + muzzle.distance_to(at) / FAR_SPREAD)
	dir += _rng.randfn(0.0, off)
	b.guns[gun]["aim"] = wrapf(dir - b.rot, -PI, PI)
	_launch(0, ship, muzzle, dir, w, meta)


func fire_theirs(foe: int, weapon: int, w: int, target_cell: int, miss: float, delay: int, meta: Dictionary) -> void:
	## Gunnery fires one shot of a pirate's gun at that cell of the ship of ours it fights (-1: its middle).
	_after(delay, _shoot_theirs.bind(foe, weapon, w, target_cell, miss, meta))


func _shoot_theirs(foe: int, weapon: int, w: int, target_cell: int, miss: float, meta: Dictionary) -> void:
	var b := of_enemy(foe)
	var whom := body(int(meta.get("ship", 0)))
	if b == null or whom == null:
		server.gunnery.arena_miss({"side": 1, "meta": meta, "w": w, "foe": foe}, Vector2(-1, -1))
		return
	var gun: Dictionary = b.guns[weapon % b.guns.size()] if not b.guns.is_empty() else {}
	var muzzle := b.world(gun["at"]) if not gun.is_empty() else b.pos
	var local: Vector2 = whom.shape.local_of(target_cell) if target_cell >= 0 else Vector2.ZERO
	var at := _lead_point(b, muzzle, whom, local, w)
	var dir := (at - muzzle).angle()
	if miss >= 1.0:                          # (tests: its shots always miss, clear of the whole ship)
		dir = (whom.pos - muzzle).angle() + (1.0 if _rng.randf() < 0.5 else -1.0) * (atan2(whom.shape.radius + 4.0, muzzle.distance_to(whom.pos)) + 0.1)
	elif miss > 0.0:
		dir += _rng.randfn(0.0, _spread(w) + miss * BOT_SPREAD * (1.0 + muzzle.distance_to(at) / FAR_SPREAD))
	if not gun.is_empty():
		gun["aim"] = wrapf(dir - b.rot, -PI, PI)
	_launch(1, LEAD + foe, muzzle, dir, w, meta)


func _launch(side: int, from: int, muzzle: Vector2, dir: float, w: int, meta: Dictionary) -> void:
	var b: Body = bodies[from]
	var speed := shot_speed(w)
	var p := {"id": _next_id, "side": side, "from": from, "pos": muzzle, "vel": Vector2.RIGHT.rotated(dir) * speed + b.vel,
		"ends": server.tick + roundi(shot_range(w) / speed * Net.TICK_HZ), "w": w, "kind": server.gunnery._shot_kind(w),
		"meta": meta, "seen": {}, "guard": Weapons.guard_chance(w) > 0.0}
	if side == 1:
		p["foe"] = from - LEAD
	_next_id = (_next_id % 65535) + 1
	shots.append(p)
	var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_SHOT_FLY, 0, 0, int(p["kind"]), side, 0, 0, 0, 0])
	msg.encode_u16(2, int(p["id"]))
	msg.encode_u32(6, server.tick)
	_put_point(msg, p["pos"])
	_put_point(msg, (p["vel"] as Vector2) / 4.0)
	var life := msg.size()
	msg.resize(life + 2)
	msg.encode_u16(life, int(p["ends"]) - server.tick)
	server.to_all(msg)


func draw_beam(ship: int, gun: int, foe: int, room: int, kind: int, stopped: bool) -> void:
	## A second of a beam of ours, drawn in the fight's space: from the gun to the room (or to the bubble).
	var b := body(ship)
	var e := of_enemy(foe)
	if b == null or e == null or gun >= b.guns.size():
		return
	var from := b.world(b.guns[gun]["at"])
	var to := e.world(_room_point(e, foe, room))
	if stopped:
		to = _bubble_meet(from, to, e)
	b.guns[gun]["aim"] = wrapf((to - from).angle() - b.rot, -PI, PI)
	var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_SHOT_BEAM, 0, 0, kind, 0])
	_put_point(msg, from)
	_put_point(msg, to)
	msg.append(Weapons.BEAM_PULSE_TICKS)
	server.to_all(msg)


func _bubble_meet(from: Vector2, to: Vector2, e: Body) -> Vector2:
	var r: Vector2 = e.shape.bubble()
	var p := from
	var step := (to - from).normalized() * 0.5
	for k in roundi(from.distance_to(to) / 0.5):
		var l := e.local(p)
		if Vector2(l.x / r.x, l.y / r.y).length_squared() <= 1.0:
			return p
		p += step
	return to


func _after(ticks: int, work: Callable) -> void:
	if ticks <= 0:
		work.call()
	else:
		_later.append([server.tick + ticks, work])


func _run_later() -> void:
	if _later.is_empty():
		return
	var due: Array = []
	var still: Array = []
	for f: Array in _later:
		(due if server.tick >= int(f[0]) else still).append(f)
	_later = still
	for f: Array in due:
		(f[1] as Callable).call()


# ---------------------------------------------------------------- shots in flight

func _shielded(b: Body) -> bool:
	var g = server.gunnery
	if b.id < LEAD:
		server.fleet.use(b.id)
		var up: bool = g.our_shield_up() and server.ship.shield > 0.0
		server.fleet.use(0)
		return up
	server.wing.use(b.id - LEAD)
	var up2: bool = g._enemy_shield_up()
	server.wing.use(0)
	return up2


func _fly_shots() -> void:
	var g = server.gunnery
	var still: Array = []
	for p: Dictionary in shots:
		var from: Vector2 = p["pos"]
		var to: Vector2 = from + (p["vel"] as Vector2) * DT
		var done := false
		for b: Body in bodies:
			if done:
				break
			if not b.on or (int(p["side"]) == 0) == (b.id < LEAD):
				continue
			if b.pos.distance_to(from) > b.shape.radius + 6.0 + from.distance_to(to) + (GUARD_RANGE if p["guard"] else 0.0):
				continue
			var steps := maxi(ceili(from.distance_to(to) / 0.4), 1)
			var shield := _shielded(b)
			var r: Vector2 = b.shape.bubble()
			for s in steps + 1:
				var at := from.lerp(to, float(s) / steps)
				var l := b.local(at)
				if p["guard"] and Vector2(l.x / (r.x + GUARD_RANGE), l.y / (r.y + GUARD_RANGE)).length_squared() <= 1.0:
					p["guard"] = false
					if g.arena_guard(p, b.id, at):
						_ended(p, Net.SHOT_DOWN, at)
						done = true
						break
				if shield and not (p["seen"] as Dictionary).has(b.id) and Vector2(l.x / r.x, l.y / r.y).length_squared() <= 1.0:
					(p["seen"] as Dictionary)[b.id] = true
					if g.arena_bubble(p, b.id, at):
						_ended(p, 0, at)
						done = true
						break
				if b.shape.solid(l):
					var how: int = g.arena_hit(p, b.id, l, _grid_cells(b, l), at)
					_ended(p, how, at)
					done = true
					break
		if done:
			continue
		p["pos"] = to
		if server.tick >= int(p["ends"]):
			g.arena_miss(p, to)
			_ended(p, Net.MISSED, to)
			continue
		still.append(p)
	shots = still


func _grid_cells(b: Body, l: Vector2) -> PackedInt32Array:
	## The cells of the drawing under that point of a body (one per deck there): for ours, cells of
	## the grid; for a pirate, cells of its own drawing (Gunnery maps them on).
	return b.shape.cells_under(b.shape.cell_at(l))


func _grid_spot(b: Body, l: Vector2) -> Vector2:
	## Where that point of a ship of ours lies in the grid (of its top deck), for the sounds and flashes inside.
	var c: Vector2i = b.shape.cell_at(l)
	return Vector2(b.shape.x0 + c.x + 0.5, b.shape.r0 + c.y + 0.5)


func _ended(p: Dictionary, how: int, at: Vector2) -> void:
	var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_SHOT_END, 0, 0, how & 0xFF])
	msg.encode_u16(2, int(p["id"]))
	_put_point(msg, at)
	server.to_all(msg)


func in_flight() -> int:
	return shots.size() + _later.size()


# ---------------------------------------------------------------- what clients are told

static func _put_point(msg: PackedByteArray, v: Vector2) -> void:
	var o := msg.size()
	msg.resize(o + 4)
	msg.encode_s16(o, clampi(roundi(v.x * 8.0), -32768, 32767))
	msg.encode_s16(o + 2, clampi(roundi(v.y * 8.0), -32768, 32767))


func packet() -> PackedByteArray:
	## S_ARENA: u32 tick, u8 count, then per body on: u8 id, u8 flags (ARENA_*), s16 drawing (-1: ours),
	## s16 x*8, s16 y*8, s16 vx*8, s16 vy*8, u16 heading (0..65535 for a full turn), s16 spin*1000,
	## u8 shield (0..100), u8 guns, per gun s16 aim*1000 (the body's frame), u8 GUNF bits.
	var msg := PackedByteArray([Net.S_ARENA, 0, 0, 0, 0, 0])
	msg.encode_u32(1, server.tick)
	var n := 0
	var g = server.gunnery
	for b: Body in bodies:
		if not b.on:
			continue
		n += 1
		var shield := 0.0
		var flags := 0
		if b.id < LEAD:
			server.fleet.use(b.id)
			shield = server.ship.shield if g.our_shield_up() else 0.0
			server.fleet.use(0)
		else:
			server.wing.use(b.id - LEAD)
			shield = g.enemy_shield if g._enemy_shield_up() else 0.0
			server.wing.use(0)
		if b.thrusting:
			flags |= Net.ARENA_THRUST
		if b.glued:
			flags |= Net.ARENA_GLUED
		if b.id < LEAD and not (pilots[b.id] as Dictionary).is_empty():
			flags |= Net.ARENA_PILOTED
		var o := msg.size()
		msg.resize(o + 4)
		msg[o] = b.id
		msg[o + 1] = flags
		msg.encode_s16(o + 2, b.layout)
		_put_point(msg, b.pos)
		_put_point(msg, b.vel)
		o = msg.size()
		msg.resize(o + 6)
		msg.encode_u16(o, roundi(wrapf(b.rot, 0.0, TAU) / TAU * 65535.0) & 0xFFFF)
		msg.encode_s16(o + 2, clampi(roundi(b.spin * 1000.0), -32768, 32767))
		msg[o + 4] = clampi(roundi(shield), 0, 255)
		msg[o + 5] = b.guns.size()
		for k in b.guns.size():
			var gun: Dictionary = b.guns[k]
			o = msg.size()
			msg.resize(o + 3)
			msg.encode_s16(o, clampi(roundi(float(gun["aim"]) * 1000.0), -32768, 32767))
			var gf := 1 if bool(gun["bears"]) else 0
			if b.id < LEAD and manned_by_hand(b.id, k):
				gf |= 2
			msg[o + 2] = gf
	msg[5] = n
	return msg
