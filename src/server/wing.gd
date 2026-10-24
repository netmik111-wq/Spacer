extends RefCounted
## (v86, the author's E1: "enemies can have more ships too, and other enemy ships can join the battle")
## A second pirate ship that joins a fight already going: the first step to enemy fleets. It comes out of
## the dark a while into a fight with an ordinary pirate ship and fights at a distance; it never comes
## alongside, docks or boards, so it is not in the grid: it is only guns, a shield, a hull and its rooms
## as the gun console's sights see them. Our gun console picks which of the two our guns shoot at
## (Gunnery.foe, per ship of our fleet). When the ship alongside is beaten or gone, it turns and runs.
##
## Gunnery was written for one enemy, and still is: its enemy fields are "the enemy we deal with now".
## Like Fleet does for our ships, this part keeps the wingman's own share of those fields (ENEMY) and puts
## it in place for a while (use(1)), then puts the first back (use(0)); the first is in place otherwise.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Hulls := preload("res://src/shared/hulls.gd")

# Gunnery's fields each enemy has its own of
const ENEMY: Array[String] = ["held_until", "enemy_hull", "systems", "systems_full", "systems_out", "enemy_shield",
	"enemy_weapons", "enemy_fx", "enemy_charge", "enemy_guard", "_enemy_guard_ready", "enemy_armour", "raid", "enemy_full",
	"klass", "temper", "temper_known", "room_sys", "revealed", "reward", "_regen", "_slower", "_dodge", "_scan_next", "flee",
	"_mend_next", "_mend_part", "ransom", "ransom_until", "_offered", "_over", "goal", "goal_lost", "goal_pay", "cargo_room",
	"boss", "crewless", "teleport", "target", "phase2", "_flying"]
const CHANCE := [0.25, 0.1, 0.4]     # per mode (Net.MODE_NORMAL, EASY, HARD): the share of fights that get a wingman
const JOIN_SECONDS := Vector2(25.0, 50.0)   # it comes this long into the fight
const LAST_RUN := 12.0               # seconds it takes to charge its jump once the ship alongside is beaten

var server: GameServer
var on := 0                          # the enemy whose fields are in place now (0: the ship alongside; 1: the wingman)
var here := false                    # a wingman is in the fight
var layout := -1                     # its drawing (ShipMap.others), for the console's plan of it
var name := ""
var chance_for_test := -1.0          # (tests: the share of fights that get one, instead of CHANCE)
var join_at := -1                    # the tick the wingman of this fight comes (-1: none comes)
var _fight_seen := false             # the fight alongside has been rolled for a wingman
var _kept: Array = [{}, {}]          # per enemy: field -> its own value while the other is in place
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	on = 0
	here = false
	layout = -1
	join_at = -1
	_fight_seen = false
	_kept = [{}, {}]
	_rng.randomize()


func use(i: int) -> void:
	## Puts that enemy's fields in place in Gunnery (0: the ship alongside, 1: the wingman).
	if i == on or i < 0 or i > 1:
		return
	var g = server.gunnery
	var keep: Dictionary = _kept[on]
	var put: Dictionary = _kept[i]
	for f: String in ENEMY:
		var v: Variant = g.get(f)
		keep[f] = v
		if put.has(f):
			g.set(f, put[f])
		elif v is Array or v is Dictionary or v is PackedByteArray or v is PackedInt32Array or v is PackedFloat32Array:
			g.set(f, v.duplicate())          # (its first time in place: not the other's own)
	on = i


func value(i: int, field: String) -> Variant:
	## That enemy's own value of one of the ENEMY fields, whichever is in place.
	if i == on:
		return server.gunnery.get(field)
	return (_kept[i] as Dictionary).get(field, null)


func engaged(i: int) -> bool:
	## Is that enemy in the fight now, for the ship of our fleet in place? (The ship alongside not while it
	## is docked to this very ship; Gunnery.engaged for the one in place.)
	if i == 1:
		return here and int(value(1, "enemy_hull")) > 0 and not bool(value(1, "_over"))
	var d = server.derelict
	return int(value(0, "enemy_hull")) > 0 and d.here and d.kind == Net.OTHER_PIRATE and not d.wreck \
		and (not d.docked or server.fleet.on != int(value(0, "target")))


func fighting() -> bool:
	## Does a fight go on for the ship of our fleet in place: either enemy?
	return engaged(0) or engaged(1)


func tick() -> void:
	## Rolls a wingman for each fight alongside, brings it in after a while, and runs its side of the fight.
	var g = server.gunnery
	var lead: bool = g.alive() and g.boss == 0 and server.over == Net.OVER_NONE
	if lead and not _fight_seen:
		_fight_seen = true
		# (only while the director sends things, as with hunters: tests that set it off get no wingman unasked)
		var share: float = chance_for_test if chance_for_test >= 0.0 else (float(CHANCE[clampi(server.mode, 0, CHANCE.size() - 1)]) if server.director.auto else 0.0)
		join_at = -1
		if not here and _rng.randf() < share:
			join_at = server.tick + roundi(_rng.randf_range(JOIN_SECONDS.x, JOIN_SECONDS.y) * Net.TICK_HZ)
	elif not g.alive() and _fight_seen and not here:
		_fight_seen = false
		join_at = -1
	if not here and join_at >= 0 and server.tick >= join_at:
		join_at = -1
		if lead and not server.derelict.docked:
			comes()
	if not here:
		return
	if not g.alive() and int(value(1, "flee")) < 0 and not bool(value(1, "_over")):
		use(1)
		g.flee = maxf(0.0, (g._flee_seconds() - LAST_RUN) * Net.TICK_HZ)   # it is near its jump: a few seconds to stop it
		server.chat.say("%s остаётся без ведущего и заряжает прыжок, чтобы уйти." % name)
		use(0)
	use(1)
	g.tick_enemy()
	var gone: bool = g.enemy_hull <= 0 or g._over
	use(0)
	if gone:
		leaves()


func comes(design: Dictionary = {}) -> bool:
	## The wingman comes out of the dark and opens fire. `design`: a ship already made (tests); else Shipyard rolls one.
	var g = server.gunnery
	if here:
		return false
	var lead_target: int = g.target
	if design.is_empty():
		var any: Array = []
		for k in server.map.others.size():
			any.append(k)                    # (it never comes alongside: any drawing will do)
		design = server.shipyard.make(1, true, any)
	if design.is_empty() or design.has("boss") or design.get("drone", false):
		return false
	_kept[1] = {}
	use(1)
	g.enemy_arrives(design, true, true)
	g.target = lead_target if server.mode == Net.MODE_HARD else server.fleet.target()   # (the author's N3: hard focuses one)
	g._offered = true                        # it has no word with us: no ransom
	use(0)
	here = true
	layout = int(design["layout"])
	name = str(design["name"]) if not design.has("classic") else "Второй пиратский корабль"
	var whom: String = ("по кораблю %s" % server.fleet.name_of(int(_kept[1]["target"]))) if server.fleet.many() else "по нам"
	server.chat.alarm("Тревога! Из темноты выходит ещё один пират, %s, и бьёт %s издалека. На абордаж он не пойдёт. Цель для орудий выбирают на пульте орудий." % [
		name.substr(0, 1).to_lower() + name.substr(1), whom])
	return true


func leaves() -> void:
	## The wingman is wrecked or gone (Gunnery told what became of it): our guns aimed at it turn to the first.
	here = false
	layout = -1
	_kept[1] = {}
	server.fleet.each(func() -> void: server.gunnery.foe = 0)


func jumped() -> void:
	## We jumped away (or the fight alongside ended for good): it is left behind.
	if here:
		leaves()
	join_at = -1
	_fight_seen = false


func summary(i: int) -> PackedByteArray:
	## For the gun console (Net.S_GUNS): 1 in the fight for this ship / 0, hull, full, class, drawing.
	if i == 1 and not here:
		return PackedByteArray([0, 0, 0, 0, 255])
	var lay: int = layout if i == 1 else (server.derelict.layout if server.derelict.here else 255)
	return PackedByteArray([1 if engaged(i) else 0, clampi(int(value(i, "enemy_hull")), 0, 255), clampi(int(value(i, "enemy_full")), 0, 255),
		int(value(i, "klass")), clampi(lay, 0, 255)])
