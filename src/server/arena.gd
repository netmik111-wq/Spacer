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
## (v93, the author's plan 0.2) Armour on every cell of a ship's outer wall from above; ours stays worn after the
## fight (Ship.worn) until mended from outside (Outside), at a station or at the trader's yard. A shot that meets it
## past RICOCHET_COS may glance off (Weapons.BOUNCE) and fly on harmless.
## (v94, the author: "rework the whole damage, shield, hull and armour system like in Starsector, so fights feel
## alive; without guns that shoot 360° and hardpoint guns it feels like something else") Guns are of three mount
## kinds (ArenaShape.MOUNT_*): fixed in the bow, side turrets of 180° and roof turrets of 360°, and turrets turn at
## their own pace. Shots carry Starsector's damage (Weapons.SPACE): a raised shield stops them and the ship heats
## (Body.heat, Starsector's flux; the shield's part, `hard`, goes away only while the shield is down); full, the
## shield overloads for OVERLOAD_SECONDS; a ship may vent (VENT_RATE) with its shield and guns off. Guns heat their
## own ship too and do not fire past its top. Armour is weakened by the hit (damage x damage/(damage + armour), never
## below MIN_SHARE) and worn round where it struck; what reaches the hull counts in hull points, and every
## INSIDE_UNIT of it is one hit inside (Gunnery's old point of damage: a breach, a system worn, the wounded).
## The pilot raises the shield with the right mouse button and turns its arc with the mouse (C_SHIELD); with nobody
## holding it, the shield goes up when a shot comes and down to cool (the bots, and the pirates).
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
const BOT_SPREAD := 0.12             # radians of aim error per unit of a gun's miss chance, for bots and pirates
const FAR_SPREAD := 60.0             # cells at which that error doubles
const GUARD_RANGE := 16.0            # cells off the hull the point defence meets a rocket
const HIT_NEAR := 3.0                # a pirate shot this near the thing it aimed at puts that thing out
const BEAM_RANGE := 90.0             # cells a beam, a tractor or a siphon reaches (bombs too)
const DT := 1.0 / Net.TICK_HZ
const ARMOUR_OURS := 150.0           # (v94, my A1 pick) points of armour on each cell of our outer wall, before the plating
const ARMOUR_TIER := 50.0            # and what each tier of the plating adds
const PANE_SHARE := 0.34             # a window holds this share of its ship's plating
# a pirate's, by its class
const ARMOUR_OF := {Net.ECLASS_CUTTER: 50.0, Net.ECLASS_RAIDER: 100.0, Net.ECLASS_GUNSHIP: 150.0, Net.ECLASS_CRUISER: 200.0,
	Net.ECLASS_BATTLESHIP: 300.0, Net.ECLASS_CARRIER: 250.0, Net.ECLASS_DRONE: 80.0}
const ARMOUR_FLOOR := 0.05           # (Starsector's) armour never counts below this share of its whole
const MIN_SHARE := 0.15              # nor lets less than this share of a hit through
const INSIDE_UNIT := 100.0           # hull points that make one hit inside
const OUR_HP := 20.0                 # our hull's points per point of its strength (Ship.hull), as shown
const RICOCHET_COS := 0.5            # a shot meeting the wall more than 60° off straight on may glance off
const SLANT_MOST := 2.0              # the most a slant thickens the armour a shot must pass
const SLANT_SLACK := 0.1             # a shot nearly head-on (within some 18°) counts as head-on
const ARMOUR_EVERY := 2 * Net.TICK_HZ   # ticks between two whole lists of worn armour to the clients
const BOUNCE_SLOW := 0.7             # a shot that glanced off keeps this share of its speed
const BOUNCE_LIFE := 1.2             # and flies this long (seconds) before it is spent
# (v94) heat: [what it holds, what goes away a second, how much a point of a hit on the shield heats it]; -1 ours
const FLUX_OF := {-1: [3000.0, 150.0, 1.0], Net.ECLASS_CUTTER: [800.0, 50.0, 1.2], Net.ECLASS_RAIDER: [1500.0, 70.0, 1.0],
	Net.ECLASS_GUNSHIP: [2000.0, 90.0, 1.0], Net.ECLASS_CRUISER: [3000.0, 120.0, 0.9], Net.ECLASS_BATTLESHIP: [5000.0, 180.0, 0.7],
	Net.ECLASS_CARRIER: [4000.0, 150.0, 0.8], Net.ECLASS_DRONE: [1200.0, 60.0, 1.0]}
const HARDENED_EFF := 0.8            # the hardened shield heats this much less
const ARC_EFF := 0.7                 # and an arc (v93's "stronger arc")
const OVERLOAD_SECONDS := 5.0
const OVERLOAD_COOL := 2.0           # overloaded, it cools this many times its plain pace, the shield's heat too
const VENT_RATE := 5.0               # venting, this many times
const BOT_VENT := 0.75               # with nobody holding the shield, it vents at this share of heat when no shot comes
const THREAT_SECONDS := 1.2          # a shot this near in time raises a shield nobody holds
const AUTO_HOLD := 12                # and it stays up this many ticks after
const SHIELD_HOLD := Net.TICK_HZ     # the pilot's shield and its aim count this long after he last sent them
const ARC_HALF := PI * 0.4           # (v93) a shield squeezed into an arc covers 72° either side of its middle
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
	var plates := 0.0                # (v93) points of armour on a wall cell of its outer hull
	var worn := {}                   # (v93) the shape's cell -> points worn off there (ours: the Ship's own, kept)
	var heat := 0.0                  # (v94) Starsector's flux: all of it ...
	var hard := 0.0                  # ... and the shield's part of it, which goes only while the shield is down
	var cap := 3000.0
	var cool := 150.0                # heat that goes away a second
	var eff := 1.0                   # heat a point of a hit on the shield makes
	var over_until := 0              # the tick its overload ends
	var venting := false
	var raised := false              # its shield is up now
	var auto_until := 0              # (nobody holds the shield) it stays up until this tick
	var debt := 0.0                  # hull points taken that have not made a hit inside yet
	var shield_dir := 0.0            # the middle of an arc, in the body's frame (ours: the pilot's mouse)

	func overloaded(now: int) -> bool:
		return now < over_until

	func world(local: Vector2) -> Vector2:
		return pos + local.rotated(rot)

	func local(at: Vector2) -> Vector2:
		return (at - pos).rotated(-rot)


var server: GameServer
var enabled := true                  # (tests that want the fight as it was before v92 switch it off)
var hold_pirates := false            # (tests: pirates hold where they are put)
var pirate_shields := true          # (v94 tests: false keeps the pirates' shields down)
var pane_share := PANE_SHARE         # (v93; tests that want windows as strong as walls raise it)
var shields: Array = [{}, {}]        # (v94) per ship of our fleet: the pilot's {"up", "dir", "until", "by"} (C_SHIELD)
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
var _worn_now := {}                  # (v93) body -> {shape cell: true} worn since the last ARENA_ARMOUR
var _our_shapes := {}                # (v93) ship of our fleet -> its ArenaShape, out of a fight too (mending from outside)


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
	shields = [{}, {}]
	_was_on = false
	_worn_now = {}
	_our_shapes = {}
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
	for b: Body in bodies:
		if b.on:
			_heat_tick(b)
	_aim_turrets()
	_triggers()
	_run_later()
	_fly_shots()
	_docking()
	_edges()
	if server.tick % SEND_EVERY == 0:
		server.to_all(packet())
	_tell_armour(server.tick % ARMOUR_EVERY == 0)


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
		_our_shapes[i] = b.shape
		server.fleet.use(i)
		for cell: int in map.guns:
			b.guns.append(_gun(b, cell))
		b.plates = ARMOUR_OURS + ARMOUR_TIER * server.outfit.armour_tier()
		b.worn = server.ship.worn
		_flux_of(b, FLUX_OF[-1])
		b.cool *= server.outfit.shield_regen() / Weapons.SHIELD_REGEN
		if server.outfit.hardened():
			b.eff *= HARDENED_EFF
		server.fleet.use(0)
	_worn_now = {}
	_tell_armour(true)


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
	shields = [{}, {}]
	server.to_all(packet())


func _gun(b: Body, cell: int) -> Dictionary:
	var at: Vector2 = b.shape.local_of(cell)
	var out: float = b.shape.mount_out(cell)
	var kind: int = b.shape.mount_kind(cell)
	return {"cell": cell, "at": at, "out": out, "aim": out, "bears": false, "kind": kind, "arc": ArenaShape.MOUNT_ARC[kind]}


func _gun_weapon(b: Body, k: int) -> int:
	## (v94.1) The weapon on that body's gun k: ours from its ship's mounts, a pirate's from its list (weapon j fires
	## from gun j % guns, so gun k is weapon k's).
	if b.id < LEAD:
		var ships: Array = server.fleet.ships
		var mounts: PackedByteArray = ships[b.id].mounts if b.id < ships.size() else server.ship.mounts
		return mounts[k] if k < mounts.size() else Weapons.NONE
	var list: PackedByteArray = _their_weapons(b)
	for j in list.size():
		if _their_gun(b, j, list[j]) == k:
			return list[j]
	return Weapons.LASER


func _their_weapons(b: Body) -> PackedByteArray:
	var list = server.wing.value(b.id - LEAD, "enemy_weapons")
	return list if list != null else PackedByteArray()


func _their_gun(b: Body, weapon: int, w: int) -> int:
	## (v94.1, his M2 note) The gun mount a pirate's weapon fires from: its own (weapon % guns) if the gun fits it, else
	## the next one that does (a pirate's drawing may have no mount for it: then its own).
	var n := b.guns.size()
	if n == 0:
		return 0
	for j in n:
		var k := (weapon + j) % n
		if Weapons.fits(w, int(b.guns[k]["kind"])):
			return k
	return weapon % n


func _turn(b: Body, k: int) -> float:
	## (v94.1, his M2 note) Radians a second gun k turns: a fixed gun not at all, a turret at its gun's own pace.
	if int(b.guns[k]["kind"]) == ArenaShape.MOUNT_HARD:
		return 0.0
	var w := _gun_weapon(b, k)
	return Weapons.turn_speed(w if w != Weapons.NONE else Weapons.LASER)


func _flux_of(b: Body, f: Array) -> void:
	b.cap = f[0]
	b.cool = f[1]
	b.eff = f[2]
	b.heat = 0.0
	b.hard = 0.0
	b.over_until = 0
	b.venting = false
	b.raised = false
	b.auto_until = 0
	b.debt = 0.0
	b.shield_dir = 0.0


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
	var heavy = server.wing.value(i - LEAD, "enemy_armour")    # (v58) a hull rolled with armour: a quarter more
	b.plates = float(ARMOUR_OF.get(klass, 100.0)) * (1.25 if heavy != null and float(heavy) > 0.0 else 1.0)
	b.worn = {}
	_flux_of(b, FLUX_OF.get(klass, FLUX_OF[Net.ECLASS_RAIDER]))


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
	if raid and (b.heat > b.cap * 0.7 or b.overloaded(server.tick) or b.venting):
		range *= 1.6                         # (v94) hot or overloaded, it stands off to cool, as Starsector's do
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
	## (v94) Each gun counts by its own arc; a fixed gun counts more (it is the strongest), so its ship points it.
	var to := at - b.pos
	if b.guns.is_empty():
		return to.angle()
	var tries := PackedFloat32Array([b.rot])
	for gun: Dictionary in b.guns:
		tries.append(wrapf(to.angle() - float(gun["out"]), -PI, PI))   # the heading that points this gun straight at it
	for k in 8:
		tries.append(TAU * k / 8.0)
	var best := b.rot
	var best_n := -1.0
	var best_turn := INF
	for h: float in tries:
		var n := 0.0
		for gun: Dictionary in b.guns:
			if absf(wrapf(to.angle() - (h + float(gun["out"])), -PI, PI)) <= maxf(float(gun["arc"]) * 0.85, PI / 60.0):
				n += 1.5 if int(gun["kind"]) == ArenaShape.MOUNT_HARD else 1.0
		var t := absf(wrapf(h - b.rot, -PI, PI))
		if n > best_n + 0.01 or (absf(n - best_n) <= 0.01 and t < best_turn):
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
	if gun == Net.ALL_GUNS:
		_all_asked(p, aim, fire)
		return
	if not _was_on or i >= turrets.size() or gun < 0 or gun >= server.map.guns.size() or server.mounts.gunner(gun) != p:
		return
	(turrets[i] as Dictionary)[gun] = {"aim": aim, "fire": fire, "until": server.tick + TURRET_HOLD, "by": p}


func _all_asked(p: Player, aim: Vector2, fire: bool) -> void:
	## (v93, the author's P1 note: "one player steers and shoots; one who joins takes every gun not taken")
	## At the ship's controls or the gun console: every gun nobody aims by hand at its mount takes this mark;
	## the gun console's gunner comes before the pilot. Let go (fire false), they go back to their bots at once.
	var i: int = server.fleet.on
	var map = server.map
	var console: bool = server.systems.at_console(p, map.gun_console)
	if not _was_on or i >= turrets.size() or not (console or server.systems.at_console(p, map.helm)):
		return
	var mine: Dictionary = turrets[i]
	if fire and not mine.values().any(func(t: Dictionary) -> bool: return t.get("by") == p):
		server.usage.note(p, "aim_all")      # (once a burst: the mark comes again ten times a second)
	for k in map.guns.size():
		var t: Dictionary = mine.get(k, {})
		var taken: bool = not t.is_empty() and server.tick < int(t["until"]) and t["by"] != p
		if taken and (not t.get("all", false) or bool(t.get("console", false)) and not console):
			continue                         # a gunner at its mount, or the gun console over the pilot
		if not fire:
			if not t.is_empty() and t["by"] == p:
				mine.erase(k)
			continue
		mine[k] = {"aim": aim, "fire": true, "until": server.tick + TURRET_HOLD, "by": p, "all": true, "console": console}


func manned_by_hand(ship: int, gun: int) -> bool:
	## Does a player aim that gun himself now (then the console and the bots leave it to him)?
	if ship >= turrets.size():
		return false
	var t: Dictionary = (turrets[ship] as Dictionary).get(gun, {})
	return not t.is_empty() and server.tick < int(t["until"])


func _aim_turrets() -> void:
	## Every gun turns to what it means to hit (or as far as its arc lets it), (v94) at its own pace: a fixed gun
	## points straight out and bears only while its ship points it; a turret follows its mark.
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
			var arc: float = gun["arc"]
			var rel := wrapf((at - muzzle).angle() - b.rot - float(gun["out"]), -PI, PI)
			var want := clampf(rel, -arc, arc)
			var now := wrapf(float(gun["aim"]) - float(gun["out"]), -PI, PI)
			var step: float = _turn(b, k) * DT
			if step <= 0.0:
				now = want                       # fixed: it moves only its few degrees
			elif arc >= PI:
				now = now + clampf(wrapf(want - now, -PI, PI), -step, step)
			else:
				now = clampf(now + clampf(want - now, -step, step), -arc, arc)   # a turret turns the short way inside its arc
			gun["aim"] = wrapf(float(gun["out"]) + now, -PI, PI)
			var tol := _tolerance(b, gun, muzzle.distance_to(at))
			gun["bears"] = absf(rel) <= arc + (tol if step <= 0.0 else 0.0) and absf(wrapf(rel - now, -PI, PI)) <= tol


func _tolerance(b: Body, gun: Dictionary, far: float) -> float:
	## (v94) How far off its mark a gun may point and still fire: about the target's half width at that range.
	var e := 6.0
	for o: Body in bodies:
		if o.on and (o.id < LEAD) != (b.id < LEAD):
			e = maxf(e, o.shape.radius * 0.6)
	return clampf(atan2(e, maxf(far, 1.0)), PI / 90.0, 0.35) + (PI / 36.0 if int(gun["kind"]) == ArenaShape.MOUNT_HARD else 0.0)


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
	var list := _their_weapons(b)
	return bool(b.guns[_their_gun(b, weapon, list[weapon] if weapon < list.size() else Weapons.LASER)]["bears"])


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
	var g: Dictionary = b.guns[gun]
	var dir := _barrel(b, g, at, muzzle)
	var off := _spread(w)
	if not by_hand and at.is_finite():
		off += miss * BOT_SPREAD * (1.0 + muzzle.distance_to(at) / FAR_SPREAD)
	dir += _rng.randfn(0.0, off)
	_launch(0, ship, muzzle, dir, w, meta)


func _barrel(b: Body, g: Dictionary, at: Vector2, muzzle: Vector2) -> float:
	## (v94) Which way a gun fires now: where its barrel points, nudged onto its mark within its tolerance.
	var dir: float = b.rot + float(g["aim"])
	if at.is_finite():
		var tol := _tolerance(b, g, muzzle.distance_to(at))
		dir += clampf(wrapf((at - muzzle).angle() - dir, -PI, PI), -tol, tol)
	return dir


func fire_theirs(foe: int, weapon: int, w: int, target_cell: int, miss: float, delay: int, meta: Dictionary) -> void:
	## Gunnery fires one shot of a pirate's gun at that cell of the ship of ours it fights (-1: its middle).
	_after(delay, _shoot_theirs.bind(foe, weapon, w, target_cell, miss, meta))


func _shoot_theirs(foe: int, weapon: int, w: int, target_cell: int, miss: float, meta: Dictionary) -> void:
	var b := of_enemy(foe)
	var whom := body(int(meta.get("ship", 0)))
	if b == null or whom == null:
		server.gunnery.arena_miss({"side": 1, "meta": meta, "w": w, "foe": foe}, Vector2(-1, -1))
		return
	var gun: Dictionary = b.guns[_their_gun(b, weapon, w)] if not b.guns.is_empty() else {}
	var muzzle := b.world(gun["at"]) if not gun.is_empty() else b.pos
	var local: Vector2 = whom.shape.local_of(target_cell) if target_cell >= 0 else Vector2.ZERO
	var at := _lead_point(b, muzzle, whom, local, w)
	var dir := (at - muzzle).angle() if gun.is_empty() or miss <= 0.0 else _barrel(b, gun, at, muzzle)
	if miss >= 1.0:                          # (tests: its shots always miss, clear of the whole ship)
		dir = (whom.pos - muzzle).angle() + (1.0 if _rng.randf() < 0.5 else -1.0) * (atan2(whom.shape.radius + 4.0, muzzle.distance_to(whom.pos)) + 0.1)
	elif miss > 0.0:
		dir += _rng.randfn(0.0, _spread(w) + miss * BOT_SPREAD * (1.0 + muzzle.distance_to(at) / FAR_SPREAD))
	_launch(1, LEAD + foe, muzzle, dir, w, meta)


func _launch(side: int, from: int, muzzle: Vector2, dir: float, w: int, meta: Dictionary) -> void:
	var b: Body = bodies[from]
	var speed := shot_speed(w)
	var p := {"id": _next_id, "side": side, "from": from, "pos": muzzle, "vel": Vector2.RIGHT.rotated(dir) * speed + b.vel,
		"ends": server.tick + roundi(shot_range(w) / speed * Net.TICK_HZ), "w": w, "kind": server.gunnery._shot_kind(w),
		"meta": meta, "seen": {}, "guard": Weapons.guard_chance(w) > 0.0, "d": Weapons.space_damage(w),
		"type": Weapons.damage_type(w)}
	if side == 1:
		p["foe"] = from - LEAD
	_next_id = (_next_id % 65535) + 1
	shots.append(p)
	_tell_fly(p)


func _tell_fly(p: Dictionary) -> void:
	var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_SHOT_FLY, 0, 0, int(p["kind"]), int(p["side"]), 0, 0, 0, 0])
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


# ---------------------------------------------------------------- (v94) heat and the shield

func shield_asked(p: Player, up: bool, dir: float, vent: bool) -> void:
	## (C_SHIELD) The pilot at the ship's controls holds the shield up or down and turns its arc to that heading
	## (radians in the fight's space); `vent`: dump the heat now.
	var i: int = server.fleet.on
	if not _was_on or i >= shields.size() or not server.systems.at_console(p, server.map.helm):
		return
	shields[i] = {"up": up, "dir": dir, "until": server.tick + SHIELD_HOLD, "by": p}
	var b := body(i)
	if vent and b != null:
		vent_now(b)


func vent_now(b: Body) -> bool:
	## Venting: the shield drops, the guns stop, and the heat goes VENT_RATE times as fast until none is left.
	if b == null or b.venting or b.overloaded(server.tick) or b.heat <= 0.0:
		return false
	b.venting = true
	b.raised = false
	if b.id < LEAD:
		server.fleet.use(b.id)
		server.chat.say_bridge("Сброс нагрева: щит опущен, орудия молчат, пока корабль остывает.")
		server.fleet.use(0)
	return true


func _gen_ok(b: Body) -> bool:
	## Can that ship's shield stand at all now (a generator, whole, powered and switched on)?
	var g = server.gunnery
	if b.id < LEAD:
		server.fleet.use(b.id)
		var gen: int = g.shield_cell()
		var ok: bool = gen >= 0 and server.ship.shield_on and server.powered() and not server.ship.broken.has(gen) and not g.jammed(gen) \
			and not server.fleet.is_lost(b.id)
		server.fleet.use(0)
		return ok
	if not pirate_shields:
		return false
	server.wing.use(b.id - LEAD)
	var ok2: bool = g.systems.size() > Net.ESYS_SHIELDS and g.systems_full[Net.ESYS_SHIELDS] > 0 and g.systems[Net.ESYS_SHIELDS] > 0 \
		and not g.down(Net.ESYS_SHIELDS)
	server.wing.use(0)
	return ok2


func _threat(b: Body) -> bool:
	## Is a shot of the other side coming at it within THREAT_SECONDS?
	for p: Dictionary in shots:
		if (int(p["side"]) == 0) == (b.id < LEAD) or int(p.get("off", -1)) == b.id:
			continue
		var rel: Vector2 = (p["pos"] as Vector2) - b.pos
		var v: Vector2 = (p["vel"] as Vector2) - b.vel
		var closing := -rel.dot(v) / maxf(rel.length(), 0.01)
		if closing > 0.0 and rel.length() - b.shape.radius - 2.0 <= closing * THREAT_SECONDS:
			return true
	return false


func _heat_tick(b: Body) -> void:
	## The shield goes up and down, the heat goes away, an overload or a vent runs out.
	var now := server.tick
	var ok := _gen_ok(b)
	var held: Dictionary = shields[b.id] if b.id < shields.size() else {}
	var by_hand := not held.is_empty() and now < int(held["until"])
	if b.id < shields.size() and not by_hand:
		shields[b.id] = {}
	if b.overloaded(now):
		b.raised = false
		_cool(b, b.cool * OVERLOAD_COOL * DT, true)
	elif b.venting:
		b.raised = false
		_cool(b, b.cool * VENT_RATE * DT, true)
		if b.heat <= 0.0:
			b.venting = false
	else:
		var threat := _threat(b)
		if threat:
			b.auto_until = now + AUTO_HOLD
		if by_hand:
			b.raised = ok and bool(held["up"])
			if arc_of(b) >= 0:
				b.shield_dir = wrapf(float(held["dir"]) - b.rot, -PI, PI)
		else:
			b.raised = ok and now < b.auto_until
			if arc_of(b) >= 0:
				b.shield_dir = wrapf(arc_of(b) * PI / 2.0, -PI, PI)   # (v93) where the generator turned it
			if not threat and b.heat >= b.cap * BOT_VENT and now >= b.auto_until:
				vent_now(b)                  # (bots, the pirates) nothing coming: dump the heat
		_cool(b, b.cool * DT, not b.raised)
	if not ok:
		b.raised = false
	# what the old screens read as the shield's strength: how much it can still take
	var left := 0.0 if not ok or b.overloaded(now) or b.venting else maxf(100.0 * (1.0 - b.heat / b.cap), 1.0)
	if b.id < LEAD:
		server.fleet.ships[b.id].shield = left if b.id < server.fleet.size() else 0.0
	else:
		server.wing.use(b.id - LEAD)
		server.gunnery.enemy_shield = left
		server.wing.use(0)


func _cool(b: Body, n: float, hard_too: bool) -> void:
	var soft := b.heat - b.hard
	var off := minf(soft, n)
	b.heat -= off
	if hard_too and n > off:
		var more := minf(b.hard, n - off)
		b.hard -= more
		b.heat -= more
	b.heat = maxf(b.heat, 0.0)
	b.hard = clampf(b.hard, 0.0, b.heat)


func _on_shield(b: Body, n: float, hard: bool) -> void:
	## A hit (or a second of a beam) on its raised shield: it heats; full, it overloads.
	var take := n * b.eff * (ARC_EFF if arc_of(b) >= 0 else 1.0)
	b.heat += take
	if hard:
		b.hard += take
	if b.heat >= b.cap:
		b.heat = b.cap
		b.hard = minf(b.hard, b.heat)
		b.over_until = server.tick + roundi(OVERLOAD_SECONDS * Net.TICK_HZ)
		b.raised = false
		b.venting = false
		if b.id < LEAD:
			server.fleet.use(b.id)
			server.chat.alarm("Щит перегружен! %d с без щита и без орудий." % roundi(OVERLOAD_SECONDS))
			server.fleet.use(0)
		else:
			server.chat.say_bridge("Щит пиратов перегружен: %d с они беззащитны и не стреляют." % roundi(OVERLOAD_SECONDS))


func heat_ok(ship: int, w: int) -> bool:
	## (v94) May that gun of ours fire now: the ship not overloaded or venting, and its heat room enough?
	return _can_heat(body(ship), w)


func enemy_heat_ok(foe: int, w: int) -> bool:
	return _can_heat(of_enemy(foe), w)


func _can_heat(b: Body, w: int) -> bool:
	if b == null:
		return true
	if b.overloaded(server.tick) or b.venting:
		return false
	return b.heat + Weapons.burst_heat(w) <= b.cap


func heated(ship: int, w: int) -> void:
	_heat_by(body(ship), Weapons.burst_heat(w))


func enemy_heated(foe: int, w: int) -> void:
	_heat_by(of_enemy(foe), Weapons.burst_heat(w))


func _heat_by(b: Body, n: float) -> void:
	if b != null:
		b.heat = minf(b.heat + n, b.cap)


func is_overloaded(ship: int) -> bool:
	var b := body(ship)
	return b != null and (b.overloaded(server.tick) or b.venting)


func beam_burn(ship: int, gun: int, foe: int, room: int, w: int) -> Dictionary:
	## (v94) A second of one of our beams at that room of a pirate: a raised shield on the way takes it as heat
	## (Starsector's soft flux); else it burns the hull where it meets it, through the armour as a shot would.
	## {"stopped", "units", "jam", "cell": the pirate drawing's cell it burned (-1)}.
	var b := body(ship)
	var e := of_enemy(foe)
	var out := {"stopped": false, "units": 0, "cell": -1}
	if b == null or e == null or gun >= b.guns.size():
		return out
	var from := b.world(b.guns[gun]["at"])
	var to := e.world(_room_point(e, foe, room))
	var d := Weapons.space_damage(w)
	var meet := _bubble_meet(from, to, e)
	if _shielded(e) and meet != to and _covers(e, e.local(meet)):
		_on_shield(e, d * Weapons.SHIELD_MULT[Weapons.damage_type(w)], false)
		out["stopped"] = true
		to = meet
	else:
		var p := from
		var step := (to - from).normalized() * 0.4
		for k in roundi(from.distance_to(to) / 0.4) + 1:
			if e.shape.solid(e.local(p)):
				break
			p += step
		var shot := {"w": w, "d": d, "type": Weapons.damage_type(w), "meta": {}}
		_strike(shot, e, e.local(p), to - from)
		out["units"] = int((shot["meta"] as Dictionary).get("units", 0))
		var under := _grid_cells(e, e.local(p))
		out["cell"] = under[_rng.randi_range(0, under.size() - 1)] if not under.is_empty() else -1
		to = p
	b.guns[gun]["aim"] = wrapf((to - from).angle() - b.rot, -PI, PI)
	var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_SHOT_BEAM, 0, 0, server.gunnery._shot_kind(w), 0])
	_put_point(msg, from)
	_put_point(msg, to)
	msg.append(Weapons.BEAM_PULSE_TICKS)
	server.to_all(msg)
	return out


func siphon(ship: int, foe: int, n: float) -> float:
	## (v94) A second of our siphon: the heat it takes off our shield it puts on theirs, while theirs is up.
	var b := body(ship)
	var e := of_enemy(foe)
	if b == null or e == null or not _shielded(e):
		return 0.0
	_on_shield(e, n, true)
	var was := b.heat
	_cool(b, n, true)
	return was - b.heat


# ---------------------------------------------------------------- shots in flight

func _shielded(b: Body) -> bool:
	## (v94) Is its shield raised now (and not overloaded or venting)?
	return b.raised and not b.overloaded(server.tick) and not b.venting


func arc_of(b: Body) -> int:
	## (v93, the author's D3 C) Ours: -1 the shield is a bubble, 0..3 an arc on the bow, starboard, stern, port.
	if b == null or b.id >= LEAD or b.id >= server.fleet.size():
		return -1
	return server.fleet.ships[b.id].shield_arc


func _covers(b: Body, l: Vector2) -> bool:
	## Does the shield of b stand at that point of its bubble (all round, or within its arc)?
	var arc := arc_of(b)
	if arc < 0:
		return true
	var r: Vector2 = b.shape.bubble()
	var way := Vector2(l.x / r.x, l.y / r.y).angle()
	return absf(wrapf(way - b.shield_dir, -PI, PI)) <= ARC_HALF


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
			if not b.on or (int(p["side"]) == 0) == (b.id < LEAD) or int(p.get("off", -1)) == b.id:
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
				if shield and not (p["seen"] as Dictionary).has(b.id) and Vector2(l.x / r.x, l.y / r.y).length_squared() <= 1.0 \
						and _covers(b, l):
					(p["seen"] as Dictionary)[b.id] = true
					var w: int = p["w"]
					var slips := Weapons.klass(w) == Weapons.CLASS_BLASTER and _rng.randf() < Weapons.BLASTER_SLIP_SPACE
					if not Weapons.passes_shield(w) and not slips:
						# (v94) a raised shield stops every shot and its ship heats
						_on_shield(b, (float(p.get("d", 0.0)) * Weapons.SHIELD_MULT[int(p.get("type", 0))] + Weapons.emp(w)), true)
						g.arena_bubble(p, b.id, at)
						_ended(p, 0, at)
						done = true
						break
				if b.shape.solid(l):
					var met := Net.LANDED
					if Weapons.meets_armour(int(p["w"])):
						met = _strike(p, b, l, to - from)
					if met != Net.LANDED:
						p["armour"] = met           # Gunnery: it did nothing inside
					var how: int = g.arena_hit(p, b.id, l, _grid_cells(b, l), at)
					_ended(p, met if met != Net.LANDED else how, at)
					if met == Net.RICOCHET:
						_glance(p, b, l, at)
					done = true
					break
		if done:
			continue
		p["pos"] = to
		if server.tick >= int(p["ends"]):
			if not p.has("off"):
				g.arena_miss(p, to)          # (a shot that glanced off and found nothing more says nothing)
			_ended(p, Net.MISSED, to)
			continue
		still.append(p)
	shots = still


# ---------------------------------------------------------------- armour (v93)

func armour_most(b: Body, i: int) -> float:
	## The points of armour that cell of the body's shape holds when whole (0: none, inside or not the outer wall).
	if b == null or not b.shape.armoured(i):
		return 0.0
	return b.plates * pane_share if b.shape.kind[i] == ArenaShape.PANE else b.plates


func armour_left(b: Body, i: int) -> float:
	return maxf(armour_most(b, i) - float(b.worn.get(i, 0.0)), 0.0)


func _strike(p: Dictionary, b: Body, l: Vector2, way: Vector2) -> int:
	## (v94) A shot meets the hull of body b at l, flying that way. Starsector's armour: what the armour round the
	## place holds weakens it (more, the more slanting it meets the wall); the armour there wears by the hit's whole
	## strength against armour; what gets through goes to the hull points, and every INSIDE_UNIT of them is a hit
	## inside (p["meta"]["units"]). Returns Net.LANDED (a hit inside, or an ion shot putting a system out), Net.HELD
	## (only the plating and the hull points took it) or Net.RICOCHET (it glanced off).
	var w: int = p["w"]
	var d: float = p.get("d", Weapons.space_damage(w))
	var type: int = p.get("type", Weapons.damage_type(w))
	var c: Vector2i = b.shape.cell_at(l)
	var i: int = b.shape.index(c)
	var most := armour_most(b, i)
	var dir := (way.rotated(-b.rot)).normalized()
	var straight := clampf(-dir.dot(b.shape.normal(c)), 0.0, 1.0)     # cos of the angle off straight on
	var meta: Dictionary = p["meta"]
	var s := d * Weapons.ARMOUR_MULT[type]
	if most > 0.0 and straight < RICOCHET_COS and armour_left(b, i) > 0.0 and _rng.randf() < Weapons.bounce_chance(w):
		_wear(b, c, s * 0.25)
		return Net.RICOCHET
	var share := 1.0
	if most > 0.0:
		var near := 0.0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var k: int = b.shape.index(c + Vector2i(dx, dy))
				if (dx != 0 or dy != 0) and armour_most(b, k) > 0.0:
					near += armour_left(b, k)
					n += 1
		var held := 0.5 * armour_left(b, i) + 0.5 * (near / n if n > 0 else armour_left(b, i))
		held = maxf(held, most * ARMOUR_FLOOR)
		if straight < 1.0 - SLANT_SLACK:
			held *= minf(1.0 / maxf(straight, 0.01), SLANT_MOST)
		share = maxf(s / (s + held), MIN_SHARE) if s > 0.0 else 0.0
		_wear(b, c, s)
	var hull := d * share
	b.debt += hull
	var units := floori(b.debt / INSIDE_UNIT)
	b.debt -= units * INSIDE_UNIT
	meta["units"] = units
	meta["struck"] = hull
	if type == Weapons.DMG_ION and _rng.randf() < Weapons.jam_chance(w) * (0.5 + 0.5 * share):
		meta["jam"] = true
		return Net.LANDED
	return Net.LANDED if units > 0 else Net.HELD


func _wear(b: Body, c: Vector2i, n: float) -> void:
	## (v94) Wears n points of armour round that cell: half there, half shared by the armoured cells beside it.
	var round_it: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var k: int = b.shape.index(c + Vector2i(dx, dy))
			if (dx != 0 or dy != 0) and armour_most(b, k) > 0.0:
				round_it.append(k)
	var i: int = b.shape.index(c)
	_wear_cell(b, i, n * (0.5 if not round_it.is_empty() else 1.0))
	for k: int in round_it:
		_wear_cell(b, k, n * 0.5 / round_it.size())


func _wear_cell(b: Body, i: int, n: float) -> void:
	var most := armour_most(b, i)
	if most <= 0.0 or n <= 0.0:
		return
	b.worn[i] = minf(float(b.worn.get(i, 0.0)) + n, most)
	if not _worn_now.has(b.id):
		_worn_now[b.id] = {}
	(_worn_now[b.id] as Dictionary)[i] = true


func hull_points(b: Body) -> Vector2:
	## (v94) Its hull points now and when whole (ours: Ship.hull shown OUR_HP times; a pirate's: INSIDE_UNIT a point).
	if b == null:
		return Vector2.ZERO
	if b.id < LEAD:
		var sh = server.fleet.ships[b.id] if b.id < server.fleet.size() else server.ship
		return Vector2(maxf(sh.hull * OUR_HP - b.debt * OUR_HP * Net.HULL_PER_HOLE / INSIDE_UNIT, 0.0), sh.hull_max * OUR_HP)
	var g = server.wing
	var left := float(int(g.value(b.id - LEAD, "enemy_hull")))
	var full := float(int(g.value(b.id - LEAD, "enemy_full")))
	return Vector2(maxf(left * INSIDE_UNIT - b.debt, 0.0), full * INSIDE_UNIT)


func _glance(p: Dictionary, b: Body, l: Vector2, at: Vector2) -> void:
	## A shot that glanced off flies on from where it met the wall, mirrored by it, slower; it may still strike
	## another ship of that side (the author's A3 A), never the one it glanced off.
	var n: Vector2 = b.shape.normal(b.shape.cell_at(l)).rotated(b.rot)
	var vel: Vector2 = (p["vel"] as Vector2) - b.vel
	if vel.dot(n) < 0.0:
		vel -= 2.0 * vel.dot(n) * n
	vel = vel * BOUNCE_SLOW + b.vel
	var meta: Dictionary = (p["meta"] as Dictionary).duplicate()
	var was: Dictionary = meta.get("log", {})
	meta["log"] = {"w": p["w"], "fx": was.get("fx", 0), "left": 1, "misses": 0, "stopped": 0, "down": 0, "ricochet": 0,
		"hits": PackedStringArray(), "said": PackedStringArray(), "gun": was.get("gun", 0), "focus": false, "ship": was.get("ship", 0)}
	meta["target"] = -1                  # it hits wherever it meets
	meta["cell"] = -1
	var q := {"id": _next_id, "side": p["side"], "from": p["from"], "pos": at + n * 0.6, "vel": vel,
		"ends": server.tick + roundi(BOUNCE_LIFE * Net.TICK_HZ), "w": p["w"], "kind": p["kind"], "meta": meta, "seen": {},
		"guard": Weapons.guard_chance(int(p["w"])) > 0.0, "off": b.id, "d": float(p.get("d", 0.0)) * BOUNCE_SLOW,
		"type": p.get("type", Weapons.DMG_ENERGY)}
	if p.has("foe"):
		q["foe"] = p["foe"]
	_next_id = (_next_id % 65535) + 1
	shots.append(q)
	_tell_fly(q)


func _tell_armour(all: bool) -> void:
	## ARENA_ARMOUR: the cells worn since the last time, or (all) every worn cell of every body.
	for b: Body in bodies:
		if not b.on:
			continue
		var cells: Array = b.worn.keys() if all else (_worn_now.get(b.id, {}) as Dictionary).keys()
		if cells.is_empty() and not all:
			continue
		var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_ARMOUR, b.id, 0])
		var n := 0
		for i: int in cells:
			if n >= 255:
				break
			var o := msg.size()
			msg.resize(o + 4)
			msg.encode_u16(o, i)
			msg[o + 2] = clampi(roundi(armour_left(b, i) / maxf(armour_most(b, i), 1.0) * 200.0), 0, 200)
			msg[o + 3] = 200 if armour_most(b, i) > 0.0 else 0     # (v94) shares of 200 (the points run to hundreds)
			n += 1
		msg[3] = n
		if n > 0:
			server.to_all(msg)
	_worn_now = {}


func our_shape(ship: int) -> RefCounted:
	## The ArenaShape of a ship of our fleet, kept (for mending its armour from outside, out of a fight too).
	if not _our_shapes.has(ship):
		_our_shapes[ship] = ArenaShape.of_fleet(server.map, ship)
	return _our_shapes[ship]


func worn_near(ship: int, cell: int) -> PackedInt32Array:
	## (Outside) The worn cells of our ship's shape at that cell of the grid and beside it (within one).
	var out := PackedInt32Array()
	var worn: Dictionary = server.fleet.ships[ship].worn
	if worn.is_empty():
		return out
	var s: RefCounted = our_shape(ship)
	var c: Vector2i = s.cell_at(s.local_of(cell))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var i: int = s.index(c + Vector2i(dx, dy))
			if i >= 0 and float(worn.get(i, 0.0)) > 0.0:
				out.append(i)
	return out


func armour_mended() -> void:
	## Our armour was made whole outside the fight's own code (a station, the trader, the admin): tell the clients.
	if _was_on:
		_tell_armour_whole()


func armour_mended_at(ship: int, cells: PackedInt32Array) -> void:
	## (Outside) Those cells of a ship of ours were mended: told with the next ARENA_ARMOUR.
	if not _was_on or body(ship) == null:
		return
	if not _worn_now.has(ship):
		_worn_now[ship] = {}
	for i in cells:
		(_worn_now[ship] as Dictionary)[i] = true


func _tell_armour_whole() -> void:
	for ship in mini(server.fleet.size(), LEAD):
		var b := body(ship)
		if b == null:
			continue
		var msg := PackedByteArray([Net.S_ARENA_SHOT, Net.ARENA_ARMOUR, b.id, 255])
		server.to_all(msg)                   # 255 cells: all whole again


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
	## u8 shield (0..100, 0: not raised), u8 spare, (v94) u16 hull points, u16 when whole, u16 heat, u16 its top,
	## u8 the shield's share of it (of 200), u8 ARENA_RAISED|OVERLOAD|VENT, s16 the arc's middle*1000 (body's frame),
	## u8 guns, per gun s16 aim*1000 (the body's frame), u8 GUNF bits, u8 charge (of 200).
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
		var charges := PackedFloat32Array()
		if b.id < LEAD:
			server.fleet.use(b.id)
			shield = server.ship.shield if _shielded(b) else 0.0
			charges = g.charge
			server.fleet.use(0)
		else:
			server.wing.use(b.id - LEAD)
			shield = g.enemy_shield if _shielded(b) else 0.0
			charges = g.enemy_charge
			server.wing.use(0)
		if b.thrusting:
			flags |= Net.ARENA_THRUST
		if b.glued:
			flags |= Net.ARENA_GLUED
		flags |= (arc_of(b) + 1) << Net.ARENA_ARC_SHIFT       # (v93) the shield's arc (0: a bubble)
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
		msg[o + 5] = 0
		# (v94) hull points, heat, the shield's state and the way its arc faces
		var hp := hull_points(b)
		o = msg.size()
		msg.resize(o + 12)
		msg.encode_u16(o, clampi(roundi(hp.x), 0, 65535))
		msg.encode_u16(o + 2, clampi(roundi(hp.y), 0, 65535))
		msg.encode_u16(o + 4, clampi(roundi(b.heat), 0, 65535))
		msg.encode_u16(o + 6, clampi(roundi(b.cap), 0, 65535))
		msg[o + 8] = clampi(roundi(b.hard / maxf(b.cap, 1.0) * 200.0), 0, 200)
		msg[o + 9] = (Net.ARENA_RAISED if _shielded(b) else 0) | (Net.ARENA_OVERLOAD if b.overloaded(server.tick) else 0) \
			| (Net.ARENA_VENT if b.venting else 0)
		msg.encode_s16(o + 10, clampi(roundi(b.shield_dir * 1000.0), -32768, 32767))
		o = msg.size()
		msg.resize(o + 1)
		msg[o] = b.guns.size()
		for k in b.guns.size():
			var gun: Dictionary = b.guns[k]
			o = msg.size()
			msg.resize(o + 4)
			msg.encode_s16(o, clampi(roundi(float(gun["aim"]) * 1000.0), -32768, 32767))
			var gf := 1 if bool(gun["bears"]) else 0
			if b.id < LEAD and manned_by_hand(b.id, k):
				gf |= 2
			msg[o + 2] = gf
			var ch := charges[k % charges.size()] if not charges.is_empty() else 0.0
			msg[o + 3] = clampi(roundi(ch * 200.0), 0, 200)
	msg[5] = n
	return msg
