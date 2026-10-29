extends RefCounted
## The ship's guns and shield, and the guns and shield of a pirate ship that
## comes for us. Server only.
##
## Our guns sit in the hull ('T' in the map) and are fired from the gun
## console on the bridge. Each gun mount holds one weapon (Weapons.*), or none;
## a weapon taken down goes into the cargo (the supply locker) as a thing, and
## another from the cargo goes up in its place (v49, the author's request).
## An armed weapon draws power from the reactor (server.outfit.reactor(), shared with
## the shield) and charges by itself while the ship has power and the mount is
## whole; a charged gun fires at the enemy when told to. A pirate ship off the
## airlock shoots back until it docks: its hits tear the hull or put a gun, the
## shield generator or a bridge console out of order. Its own hull takes
## ENEMY_HULL points of damage; then it is wrecked, and the ship is paid for it.
##
## Shields (v49, the author's rule): our ship's generator ('Z' in the map) and
## the enemy's (a room of its drawing) each keep a shield of 0..100 that refills
## by itself. See Weapons for what the shield stops and how.
##
## The guns aim at one of the enemy's systems (Net.ESYS_*), each in a room of
## its drawing (ShipMap.zones), or anywhere. A hit takes its damage from its hull
## and from the system in the room it lands in; a system worn to nothing stops
## working (its guns fall silent, its bridge cannot aim or dodge, its engine
## cannot close in, its shield falls) until its crew mends it, a point every
## ENEMY_REPAIR_SECONDS. Ion and EMP put a system out for a few seconds instead.
## Every HITS_PER_BOARDER points on its quarters kill one of its crew; a ship
## that came to board us breaks off with nobody left to send over.
##
## It comes for one of two things (v44, the author's request): to board us
## (it closes in and docks by force, see Derelict), or for a raid, a fight at
## a distance to the end. Either way it fights with some sense: it goes for our
## guns while they can hurt it, holes the hull where the crew is, mends first
## what it needs most, and when it is beaten badly it charges its jump drive
## and runs (FLEE_SECONDS, longer with the drive worn; never with the drive or
## its engine knocked out). A raider our guns wreck stays alongside as a dead
## hulk the crew can board (Derelict.becomes_wreck).
##
## Our tractor beam (v50) holds it for a while: it cannot dodge, run or close
## in (held()); our siphon beam drains its shield into ours.
##
## Every pirate ship is rolled by Shipyard (v53): its class sets its hull, the
## strength of its systems, its shield and how quick and hard to hit it is; its
## temper (Hulls.TEMPERS) how it fights: when it runs, what it shoots at. Its
## systems stand in rooms picked by lot, so at first we do not know which room
## holds what (the author's note: the enemy's insides are unknown until
## scanned). The guns aim at a room (Net.AIM_ROOM + room) or at a system once
## we know where it is. A room shows what it holds when our sensors get to it
## (one every SCAN_SECONDS while the ship has power), when our shot lands in it,
## and its gun room when its guns fire; a probe from the cargo shows it all,
## and its temper with it.
##
## Its crew stand at their posts and walk to what needs mending (v54, see
## EnemyCrew): its guns charge slower with nobody at them, it cannot dodge and
## charges its jump slower with nobody in its cockpit, and a worn system is
## mended only while somebody is in its room. Our hits that get through may
## kill or wound whoever is in the room hit. A beaten ship that is not reckless
## may offer a ransom instead of running (RANSOM_CHANCE): it holds its fire
## while the offer stands; the gun console takes it, a shot of ours ends it.
##
## (v62, the author's road plan: enemies) A drone ship (Hulls "drone") has no
## crew (`crewless`): nobody flies it, mans its guns or mends it, so it works as
## if every post were manned, its repair drones mend what is worn while its
## control core (Net.ESYS_DRONES) works, it never runs and never bargains. Its
## "crew" are guard robots that wake when we board; it is taken by wrecking its
## core by hand. Some pirates carry a teleporter (`teleport`, see Assault).
## Bombs (Weapons.CLASS_BOMB) are teleported into the room they are aimed at:
## no shield, point defence or dodging stops them, and they hurt what is in the
## room, not the hull. «Шрапнель» spreads over the room aimed at and those
## beside it. The flagship goes into its second phase at a third of its hull
## (`phase2`, the author's K21): it mends everything once and fights harder.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const Items := preload("res://src/shared/items.gd")
const Gear := preload("res://src/shared/gear.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")

const CHARGE_SECONDS := 8.0          # (the plain laser's; each weapon has its own, see Weapons)
const ENEMY_HULL := 12               # damage a raider takes before it is wrecked (v49: was 6; v53: per class, see Hulls)
const ENEMY_SLOWER := 1.3            # its guns charge this much slower than ours
const ENEMY_SHIELD_CHANCE := 0.7     # share of pirate ships with a shield generator
const WRECK_REWARD := 40             # credits for a wrecked pirate ship
const SYSTEM_STRENGTH := 3           # damage that puts one of a raider's systems out (v53: per class)
const HITS_PER_BOARDER := 2          # damage on its quarters that kills one of its boarding party
const ENEMY_REPAIR_SECONDS := 15.0   # its crew mends one point of a worn system this often
const ENEMY_BREACH_SHARE := 0.6      # of its hits not at our guns, those that hole the hull (the rest put a console or the shield out)
const DOWN_TEXT: Array[String] = ["Пираты не могут стрелять.", "Пираты не могут уклоняться и стреляют мимо.",
	"Пираты не могут ни подойти, ни уйти прыжком.", "", "Пираты не могут уйти прыжком.", "Щит пиратов погас.",
	"Телепорт пиратов молчит: новых абордажников не будет, пока его не починят.",
	"Ядро дронов молчит: штурмовых дронов и ремонта не будет, пока его не починят."]
const FLEE_HULL := 4                 # hull left at which a calculating raider gives up and runs (v53: per temper)
const FLEE_SECONDS := 20.0           # to charge its jump with the drive whole (the author's number); worn, longer
const AIM_GUNS := 0.55               # share of its shots that go for our guns while one of them works
const BLIND_ENEMY_HIT := 0.5         # its shots hit this much less often while its bridge is out
const SCAN_SECONDS := 7.0            # (v53) our sensors make out one more of its rooms this often
const UNMANNED_PACE := 0.6           # (v54) its guns charge this much slower with nobody at them
const UNMANNED_JUMP := 0.5           # and its jump with nobody in its cockpit
const RANSOM_CHANCE := 0.5           # (v54) a beaten ship that would run offers a ransom instead this often
const RANSOM_SHARE := 0.6            # of the reward for wrecking it
const RANSOM_SECONDS := 20.0         # the offer stands this long; then it runs
const RANSOM_PRISONER := 0.3         # and one of its crew is handed over with it this often (into our reserve)
const ENEMY_EDGE := 0.05             # (v55, the author: "a little stronger" now that our pilot dodges) added to its hit chance
const CAPTURE_SHARE := 1.5           # (v55) a ship taken by boarding is salvaged: this much of its reward...
const CAPTURE_PARTS := 2             # ... and spare parts and fuel stripped from it
# (v68, the author's F4) fights with other goals, besides wrecking it
const GOAL_CARGO := 0.2              # of raids: it tows a cargo pod
const GOAL_BOUNTY := 0.15            # it is wanted (alive)
const GOAL_RUNNER := 0.15            # a courier that runs from the start
const CARGO_SHARE := 1.0             # the whole pod is worth this much of its reward
const BOUNTY_SHARE := 2.0            # the bounty, of its reward (and nothing else: it goes off under guard)
const RUNNER_SHARE := 1.0            # the courier's contraband, besides its reward, when it is stopped
const RUNNER_FLEE := 40.0            # seconds the courier needs to charge its jump with the drive whole
const RUNNER_PACE := 0.5             # its guns charge this much slower (it is no warship)
const SABOTAGE_TEXT := "Наши на борту пиратов ломают: %s (%d из %d)."

var enemy_hit_chance := -1.0         # (tests set it to 0 or 1: their shots always miss or always hit)
var shield_chance := ENEMY_SHIELD_CHANCE   # (tests set it)
var ransom_chance := RANSOM_CHANCE   # (tests set it)
var loadout_for_test := PackedByteArray()  # (tests: the enemy's guns, instead of a roll)
var server: Node
var charge := PackedFloat32Array()   # per mount, 0..1
var beam_left := PackedInt32Array()  # per mount: pulses still to come of a cutting beam that burns now
var _beam_next := PackedInt32Array() # per mount: the tick of its next pulse
var _beam_room := PackedInt32Array() # per mount: the room it burns while the guns aim anywhere
var _beam_log: Array = []            # per mount: what its pulses did, told when it goes out
var held_until := 0                  # the tick our tractor beam lets it go
var enemy_hull := 0                  # damage the enemy can still take; 0 = no enemy
var systems := PackedByteArray()     # per Net.ESYS_*: the strength the enemy's system has left
var systems_full := PackedByteArray() # and when whole
var systems_out := PackedInt32Array() # per Net.ESYS_*: the tick it comes back from ion or EMP
var enemy_shield := 0.0              # 0..Weapons.SHIELD_FULL
var enemy_weapons := PackedByteArray()
var enemy_fx := PackedByteArray()    # (v58) per enemy weapon: the effect its tier 3 gun carries
var enemy_charge := PackedFloat32Array()
var enemy_guard := false             # (v58) it has point defence: it may shoot down our rockets and our drone
var _enemy_guard_ready := 0          # the tick its point defence is charged again
var enemy_armour := 0.0              # (v58) the share of our kinetic shells its armour turns aside
var guard_charge := 0.0              # (v58) our point defence's charge, 0..1
var aim := Net.AIM_ANY               # where our guns aim (Net.ESYS_* or Net.AIM_ANY)
var raid := false                    # it came to fight at a distance, not to board
var enemy_full := 0                  # (v53) its hull when whole
var klass := Net.ECLASS_RAIDER       # its class (Hulls)
var temper := Net.TEMPER_CALCULATING # how it fights (Hulls.TEMPERS)
var temper_known := false            # a probe has shown it
var room_sys := PackedByteArray()    # per room of its drawing: the system in it (Net.ESYS_*) or Net.ROOM_EMPTY
var revealed := PackedByteArray()    # per room: 1 = we know what is in it
var reward := WRECK_REWARD
var _regen := 1.0
var _slower := ENEMY_SLOWER
var _dodge := 0.0
var _scan_next := 0                  # the tick our sensors make out another room
var flee := -1.0                     # ticks' worth of its jump charged while it runs (-1 = it is not running)
var _mend_next := 0                  # its crew mends nothing before this tick (tests hold mending off with it)
var _mend_part := PackedFloat32Array() # per Net.ESYS_*: how far the point being mended has got (0..1)
var ransom := 0                      # (v54) credits it offers to be let go (0 = no offer)
var ransom_until := 0                # the tick the offer runs out
var _offered := false                # it has made its offer this fight
var _over := false                   # this enemy is settled (wrecked or broken off): _settle does nothing more
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()
var flies := true                    # (v56) shots take their flight before they land (tests set false: at once)
var _flying: Array = []              # (v56) shots on their way: [the tick they land, what they do then]
var _fx := RandomNumberGenerator.new()   # (v56) for what is only drawn (so the game's own lots stay as they were)
var _aim_bonus := 0.0                # (v60) added to our hit chance while the console's volley is rolled (the gunnery skill)
var _units := -1                     # (v94) while a hit in space lands: its damage inside in old points (-1: the gun's own)
const GUNNER_HIT := 0.05             # (v60) the most the gunnery skill of the one at the console adds to our hit chance
var goal := Net.GOAL_NONE            # (v68) what this fight is for besides wrecking it (Net.GOAL_*)
var goal_lost := false               # the cargo is smashed, the bounty lost or the courier gone
var goal_pay := 0                    # credits the goal brings when it is met
var cargo_room := -1                 # the room of its drawing the cargo pod is in
var goal_for_test := -1              # (tests: the goal of the next raid, instead of a roll)
var goal_next := false               # the next raid may roll a goal (only those the eventer or the road send)
var boss := 0                        # (v57) the flagship at the goal point: 1 battleship, 2 carrier (0 = an ordinary pirate)
const STUN_FLOOR := -10.0           # (v57) a neural shot takes health no lower than this: down for a while, not dead
const BOSS_AIM := 0.8                # (v57) the battleship's shots go for what it means to hit this often (else the hull near the crew)
var crewless := false                # (v62) a drone ship: no crew at its posts, a machine fights
var teleport := false                # (v62) it carries a teleporter (an ordinary pirate's: see Assault)
var target := 0                      # (v85, the author's FS5) the ship of our fleet it fights and boards (Fleet.target)
var foe := 0                         # (v86, the author's E1) the enemy our guns aim at: 0 the ship alongside, 1 its wingman (Wing)
var phase2 := false                  # (v62) the flagship's second phase, from a third of its hull (the author's K21)
const PHASE2_SHARE := 1.0 / 3.0      # of its hull left when it comes
const PHASE2_PACE := 1.3             # the battleship's guns charge this much faster in it
const DRONE_REPAIR := 0.75           # (v62) a drone ship's repair drones mend at this share of one crewman's pace
const BOMB_WOUND := 25.0             # (v62) what a bomb (or a fragment of «Шрапнель») does to each of ours it wounds
const THERMITE_BURN := 60.0          # and «Термит» to the one it burns


func setup(p_server: Node) -> void:
	server = p_server
	var n: int = server.map.guns.size()
	var ship = server.ship
	if ship.mounts.size() != n:
		ship.mounts.resize(n)
		ship.mounts.fill(Weapons.LASER)
		ship.armed.resize(n)
		ship.armed.fill(1)
		# (v94) a fixed gun starts switched off where the ship has turrets too (ours got one in v94: the power at
		# the start stays as it was); the power panel turns it on
		var shape = ArenaShape.of_fleet(server.map, server.fleet.on)
		var turrets := 0
		for c: int in server.map.guns:
			if shape.mount_kind(c) != ArenaShape.MOUNT_HARD:
				turrets += 1
		for i in n:
			if turrets > 0 and shape.mount_kind(server.map.guns[i]) == ArenaShape.MOUNT_HARD:
				ship.armed[i] = 0
	ship.mount_fx.resize(n)
	charge.resize(n)
	charge.fill(1.0)
	beam_left.resize(n)
	beam_left.fill(0)
	_beam_next.resize(n)
	_beam_room.resize(n)
	_beam_log.resize(n)
	ship.shield = Weapons.SHIELD_FULL if shield_cell() >= 0 and ship.shield_on else 0.0
	enemy_gone()
	aim = Net.AIM_ANY
	_told = PackedByteArray()
	_rng.randomize()
	_fx.randomize()


func enemy_arrives(design: Dictionary, p_raid: bool = false, wingman: bool = false) -> void:
	## A pirate ship rolled by Shipyard comes: its numbers, its guns, its rooms (none known yet).
	## (v86) `wingman`: the second one (Wing): it has no crew we see, no goal, nobody to board.
	_over = false
	target = server.derelict.near
	var boarders: int = design["crew"]
	klass = design["klass"]
	temper = design["temper"]
	temper_known = false
	enemy_full = design["hull"]
	enemy_hull = enemy_full
	reward = design["reward"]
	_regen = design["regen"]
	_slower = design["slower"]
	_dodge = design["dodge"]
	boss = int(design.get("boss", 0))
	crewless = bool(design.get("drone", false))
	teleport = bool(design.get("teleport", false))
	phase2 = false
	raid = p_raid
	flee = -1.0
	_mend_next = server.tick
	_scan_next = server.tick + roundi(server.outfit.scan_seconds() * Net.TICK_HZ)
	var shielded: bool = design["shield"]
	var strength: int = design["strength"]
	systems_full = PackedByteArray([strength, strength, strength, maxi(boarders, 1) * HITS_PER_BOARDER,
		strength, strength if shielded else 0, strength if teleport else 0, strength if crewless else 0])
	systems = systems_full.duplicate()
	systems_out = PackedInt32Array()
	systems_out.resize(Net.ESYS_COUNT)
	enemy_shield = Weapons.SHIELD_FULL if shielded else 0.0
	enemy_weapons = loadout_for_test.duplicate() if not loadout_for_test.is_empty() else (design["weapons"] as PackedByteArray).duplicate()
	enemy_fx = (design["fx"] as PackedByteArray).duplicate() if design.has("fx") and loadout_for_test.is_empty() else PackedByteArray()
	enemy_fx.resize(enemy_weapons.size())
	enemy_guard = bool(design.get("guard", false))
	_enemy_guard_ready = server.tick
	enemy_armour = float(design.get("armour", 0.0))
	enemy_charge = PackedFloat32Array()
	for w in enemy_weapons:
		enemy_charge.append(_rng.randf_range(0.0, 0.4))       # it comes with its guns part charged
	room_sys = (design["room_sys"] as PackedByteArray).duplicate()
	revealed = PackedByteArray()
	revealed.resize(room_sys.size())
	revealed.fill(1 if design.has("classic") else 0)        # (the old pirate ship was known through and through)
	_mend_part = PackedFloat32Array()
	_mend_part.resize(Net.ESYS_COUNT)
	ransom = 0
	_offered = false
	if wingman:
		held_until = 0
		goal = Net.GOAL_NONE
		goal_lost = false
		cargo_room = -1
		_flying = []
		return
	aim = Net.AIM_ANY
	_roll_goal()
	server.enemy_crew.board(boarders, int(design["layout"]))
	if server.assault != null:
		server.assault.enemy_arrives()
	if server.prisons != null:
		server.prisons.enemy_arrives()       # (v70) a man of theirs in our cuffs: they call about him


# ---------------------------------------------------------------- (v68) fights with goals

func _roll_goal() -> void:
	goal = Net.GOAL_NONE
	goal_lost = false
	goal_pay = 0
	cargo_room = -1
	var may := goal_next
	goal_next = false
	if not raid or boss > 0 or crewless:
		goal_for_test = -1
		return
	var g := goal_for_test
	goal_for_test = -1
	if g < 0 and not may:
		return
	if g < 0:
		var r := _rng.randf()
		g = Net.GOAL_CARGO if r < GOAL_CARGO else (Net.GOAL_BOUNTY if r < GOAL_CARGO + GOAL_BOUNTY
			else (Net.GOAL_RUNNER if r < GOAL_CARGO + GOAL_BOUNTY + GOAL_RUNNER else Net.GOAL_NONE))
	match g:
		Net.GOAL_CARGO:
			var empty: Array = range(room_sys.size()).filter(func(r: int) -> bool: return room_sys[r] == Net.ROOM_EMPTY)
			if empty.is_empty():
				# a small ship with no spare room: the pod sits beside one of its systems, never its guns or shield
				empty = range(room_sys.size()).filter(func(r: int) -> bool:
					return room_sys[r] != Net.ESYS_WEAPONS and room_sys[r] != Net.ESYS_SHIELDS)
			if empty.is_empty():
				return
			cargo_room = empty[_rng.randi_range(0, empty.size() - 1)]
			revealed[cargo_room] = 1
			goal = g
			goal_pay = roundi(reward * CARGO_SHARE)
			server.chat.say("Пират тянет грузовой контейнер (его отсек отмечен на плане пульта орудий): целым он стоит %d кредитов. Попадание в этот отсек разобьёт груз." % goal_pay)
		Net.GOAL_BOUNTY:
			goal = g
			goal_pay = roundi(reward * BOUNTY_SHARE)
			server.chat.say("Этот пират в розыске: %d кредитов, если взять его живым. Выбейте ему орудия и двигатель разом, и он сдастся. Разбитый, он награды не принесёт." % goal_pay)
		Net.GOAL_RUNNER:
			goal = g
			goal_pay = roundi(reward * RUNNER_SHARE)
			flee = 0.0
			server.chat.say("Курьер контрабандистов! Он уже заряжает прыжок: через %d с уйдёт. Выбейте ему двигатель или гипердвигатель, и его груз (%d кредитов) наш." % [int(RUNNER_FLEE), goal_pay])


func _flee_seconds() -> float:
	return RUNNER_FLEE if goal == Net.GOAL_RUNNER else FLEE_SECONDS


func _cargo_hit(room: int) -> String:
	## A blow in the room of its cargo pod smashes it.
	if goal != Net.GOAL_CARGO or goal_lost or room != cargo_room or room < 0:
		return ""
	goal_lost = true
	return "Грузовой контейнер разбит!"


func _surrenders() -> void:
	## (v68) The wanted pirate with its guns and engine out gives itself up: the bounty, and it goes off under guard.
	goal_lost = true
	server.story.pirates_beaten()
	server.ship.credits += goal_pay
	server.chat.say("Пират в розыске сдаётся: орудия и двигатель выбиты. Награда за голову: +%d кредитов. Его уводит конвой." % goal_pay)
	ransom = 0
	enemy_hull = 0
	beam_left.fill(0)
	server.supplies.tell_store()
	server.derelict.pirates_escaped()


func _goal_paid() -> String:
	## It was wrecked or taken: what its goal brings now (said after the reward).
	if goal_lost:
		return ""
	match goal:
		Net.GOAL_CARGO:
			goal_lost = true
			server.ship.credits += goal_pay
			return " Грузовой контейнер цел: +%d кредитов." % goal_pay
		Net.GOAL_RUNNER:
			goal_lost = true
			server.ship.credits += goal_pay
			return " Груз контрабандиста наш: +%d кредитов." % goal_pay
		Net.GOAL_BOUNTY:
			goal_lost = true
			return " Награда за голову пропала: его хотели живым."
	return ""


func room_of_system(which: int) -> int:
	## The room of its drawing that system stands in, or -1.
	return room_sys.find(which) if which >= 0 and which < Net.ESYS_COUNT else -1


func system_in(room: int) -> int:
	## The system in that room, or -1 (an empty room, or no such room).
	if room < 0 or room >= room_sys.size() or room_sys[room] == Net.ROOM_EMPTY:
		return -1
	return room_sys[room]


func reveal(room: int, why: String = "") -> bool:
	## We learn what that room holds. True if it was news. `why` is said if it holds a system.
	if room < 0 or room >= revealed.size() or revealed[room] == 1:
		return false
	revealed[room] = 1
	var system := system_in(room)
	if why != "" and system >= 0:
		server.chat.say_bridge("%s: %s." % [why, Net.ESYS_NAMES[system].to_lower()])
	return true


func reveal_all() -> void:
	revealed.fill(1)
	temper_known = true


func probe_asked(p) -> void:
	## Somebody at the gun console launches a scanning probe from the cargo.
	if not server.systems.at_console(p, server.map.gun_console):
		return
	if not engaged():
		server.chat.tell(p, "Зонд запускать не к кому: целей нет.")
		return
	var ship = server.ship
	if int(ship.store.get(Net.ITEM_PROBE, 0)) <= 0:
		server.chat.tell(p, "В трюме нет зондов. Их продают торговцы.")
		return
	if revealed.count(0) == 0 and temper_known and server.enemy_crew.shown():
		server.chat.tell(p, "Зонд ещё работает: корабль пиратов и так виден целиком.")
		return
	ship.store[Net.ITEM_PROBE] -= 1
	server.supplies.tell_store()
	reveal_all()
	server.enemy_crew.probe_until = server.tick + roundi(server.enemy_crew.PROBE_SECONDS * Net.TICK_HZ)
	var found := PackedStringArray()
	for system in Net.ESYS_COUNT:
		if room_of_system(system) >= 0 and systems_full[system] > 0:
			found.append(Net.ESYS_NAMES[system].to_lower())
	var t: Dictionary = Hulls.temper(temper)
	server.chat.say("%s запускает зонд. Корабль пиратов просканирован: видны все отсеки (%s), экипаж %d (%d с видно, кто где). Повадки: %s, %s." % [
		p.name, ", ".join(found), _pirate_crew(), int(server.enemy_crew.PROBE_SECONDS), t["name"], t["about"]])


func _pirate_crew() -> int:
	return server.derelict._pirates_party if server.derelict != null else 0


func _scan_tick() -> void:
	## Our sensors make out one more of its rooms now and then, while the ship has power.
	if server.tick < _scan_next:
		return
	_scan_next = server.tick + roundi(server.outfit.scan_seconds() * Net.TICK_HZ)
	if not server.powered():
		return
	var hidden := PackedInt32Array()
	for r in revealed.size():
		if revealed[r] == 0:
			hidden.append(r)
	if hidden.is_empty():
		return
	reveal(hidden[_rng.randi_range(0, hidden.size() - 1)], "Сканеры нашли у пиратов")


func hull_full() -> int:
	return enemy_full if enemy_full > 0 else ENEMY_HULL


func enemy_gone() -> void:
	enemy_hull = 0
	goal = Net.GOAL_NONE
	goal_lost = false
	cargo_room = -1
	boss = 0
	crewless = false
	teleport = false
	phase2 = false
	enemy_full = 0
	room_sys = PackedByteArray()
	revealed = PackedByteArray()
	temper_known = false
	flee = -1.0
	held_until = 0
	systems = PackedByteArray()
	systems_full = PackedByteArray()
	systems_out = PackedInt32Array()
	enemy_shield = 0.0
	enemy_weapons = PackedByteArray()
	enemy_fx = PackedByteArray()
	enemy_guard = false
	enemy_armour = 0.0
	enemy_charge = PackedFloat32Array()
	beam_left.fill(0)
	ransom = 0
	_flying.clear()                      # (whatever was still on its way misses: one of the ships is gone)
	if server.enemy_crew != null:
		server.enemy_crew.clear()


func down(which: int) -> bool:
	## Is that system of the enemy out of action (worn to nothing, or put out by ion or EMP for now)?
	if which >= systems.size():
		return false
	return systems[which] == 0 or server.tick < systems_out[which]


func boarders_left() -> int:
	## How many of its boarding party are still alive (two points of damage on its quarters kill one).
	return 0 if systems.size() <= Net.ESYS_CREW else (systems[Net.ESYS_CREW] + HITS_PER_BOARDER - 1) / HITS_PER_BOARDER


func aim_asked(p, which: int) -> void:
	## Somebody at the gun console points the guns at one of the enemy's systems, or anywhere.
	if not server.systems.at_console(p, server.map.gun_console):
		return
	var rooms: int = (server.wing.value(foe if server.wing.here else 0, "room_sys") as PackedByteArray).size()
	if which != Net.AIM_ANY and (which < 0 or which >= Net.ESYS_COUNT) and (which < Net.AIM_ROOM or which >= Net.AIM_ROOM + rooms):
		return
	aim = which


func _aimed_room() -> int:
	## The room our guns aim at now, or -1: anywhere (or at a system it does not have).
	if aim == Net.AIM_ANY:
		return -1
	if aim >= Net.AIM_ROOM:
		return aim - Net.AIM_ROOM
	return room_of_system(aim)


func _any_room() -> int:
	## A room of its drawing, by lot: where a shot not aimed lands.
	return _rng.randi_range(0, room_sys.size() - 1) if room_sys.size() > 0 else -1


func fighting() -> bool:
	## Does a fight go on for the ship of our fleet in place (v86: with the ship alongside or its wingman)?
	return server.wing.fighting() if server.wing != null else engaged()


func engaged() -> bool:
	## A pirate ship lies off the airlock and has not docked yet: guns can reach it, and it shoots.
	## (v86, the author's note) Docked to one ship of our fleet, it is still a target for the other's guns.
	## (v86) With the wingman in place (Wing.on): it is still in the fight.
	if _wing():
		return server.wing.here and enemy_hull > 0 and not _over
	var d = server.derelict
	return enemy_hull > 0 and d.here and d.kind == Net.OTHER_PIRATE and not d.wreck and (not d.docked or server.fleet.on != target)


func alive() -> bool:
	## (v86) Is the pirate ship alongside still to be fought, whichever ship of our fleet is in place
	## (engaged() is false for the one it docked to)? Our shots on their way land while it is.
	var d = server.derelict
	return enemy_hull > 0 and d.here and d.kind == Net.OTHER_PIRATE and not d.wreck


func _finds(from_ship: int) -> bool:
	## (v86) Does a shot of ours fired from that ship of our fleet still find the pirate ship as it lands
	## (not wrecked or gone, and not docked to that very ship)?
	return alive() and not _over and (_wing() or not server.derelict.docked or from_ship != target)


func _wing() -> bool:
	## (v86) Is the wingman's state in place now (Wing.use)?
	return server.wing != null and server.wing.on == 1


func _manned(system: int) -> bool:
	## Does one of its crew man that system? (v86) The wingman's crew is not seen: always.
	return _wing() or server.enemy_crew.manned(system)


func fleeing() -> bool:
	return flee >= 0.0


func _jump_rate() -> float:
	## How fast its jump charges now: 1 with the drive whole, slower worn, 0 with it or the engine out.
	if down(Net.ESYS_ENGINE) or down(Net.ESYS_JUMP) or systems.size() <= Net.ESYS_JUMP:
		return 0.0
	return float(systems[Net.ESYS_JUMP]) / maxf(systems_full[Net.ESYS_JUMP], 1.0) \
		* (1.0 if _manned(Net.ESYS_HELM) else UNMANNED_JUMP) * server.outfit.jump_jam()


func jump_seconds_left() -> int:
	## Seconds until it jumps away at the pace it charges now (65535 = it cannot charge now).
	var rate := _jump_rate()
	if rate <= 0.0:
		return 65535
	return int(ceil((_flee_seconds() * Net.TICK_HZ - flee) / rate / Net.TICK_HZ))


# ---------------------------------------------------------------- our guns and shield

const ARC_WORDS := ["дуга вперёд, по носу", "дуга на правый борт", "дуга назад, по корме", "дуга на левый борт"]
const ARC_STRONG := 1.5               # (v93) an arc counts as this much more shield against what gets through
const ARC_TAKES := 0.5                # and takes this share of the shield a stopped shot wears off


func turn_shield(p) -> void:
	## (v93, the author's D3 C: "switch the shield's direction by hand at the generator, to survive") E at our shield
	## generator: the bubble round the whole ship, then an arc on the bow, starboard, the stern, port, and round again.
	var ship = server.ship
	ship.shield_arc = ship.shield_arc + 1 if ship.shield_arc < 3 else -1
	server.chat.tell(p, "Щит: %s." % ("пузырь вокруг всего корабля" if ship.shield_arc < 0 else
		ARC_WORDS[ship.shield_arc] + " — крепче, но закрывает только эту сторону"))
	server.usage.note(p, "shield_arc")


func shield_cell() -> int:
	## Our shield generator's wall cell, or -1 if the ship has none.
	return server.map.shield.keys()[0] if not server.map.shield.is_empty() else -1


func our_guns_silent() -> bool:
	## (v54) Can none of our guns fire: no power, or every mounted gun broken or put out
	## by ion? (A gun merely switched off still counts: it can be switched on.)
	if not server.powered():
		return true
	var ship = server.ship
	for i in ship.mounts.size():
		if ship.mounts[i] != Weapons.NONE and not ship.broken.has(server.map.guns[i]) and not jammed(server.map.guns[i]):
			return false
	return true


func jammed(cell: int) -> bool:
	return server.tick < int(server.ship.jammed.get(cell, -1))


func power_used() -> int:
	## Power the armed guns and the shield draw from the reactor.
	var ship = server.ship
	var n := 0
	for i in ship.mounts.size():
		if ship.armed[i] == 1:
			n += Weapons.power(ship.mounts[i])
	if ship.guard != Weapons.NONE and ship.guard_armed:
		n += Weapons.power(ship.guard)
	if ship.shield_on and shield_cell() >= 0:
		n += Weapons.SHIELD_POWER
	if server.power != null:
		n += server.power.engines_draw()    # (v68) power for the engines (dodge)
	return n


func our_shield_up() -> bool:
	## Does our shield stand now (it has some left, and its generator works)?
	var gen := shield_cell()
	return gen >= 0 and server.ship.shield > 0.0 and server.ship.shield_on and server.powered() \
		and not server.ship.broken.has(gen) and not jammed(gen)


func setup_asked(p, action: int, a: int, b: int) -> void:
	## Somebody at the gun console powers a gun or cuts it, switches the shield, or changes a gun.
	if not server.systems.at_console(p, server.map.gun_console):
		return
	var ship = server.ship
	match action:
		Net.GUNSET_PROBE:
			probe_asked(p)
		Net.GUNSET_RANSOM:
			ransom_taken(p)
		Net.GUNSET_FOE:
			var to := 1 if a == 1 and server.wing.here else 0
			if to != foe:
				foe = to
				aim = Net.AIM_ANY            # (its rooms are not the other's)
		Net.GUNSET_ARM, Net.GUNSET_SHIELD:
			# (v68, the author's F2) power moved to the power panel in the engine room
			server.chat.tell(p, "Питание орудий и щита включают на щите питания у СМЭС в машинном отделении.")
		Net.GUNSET_MOUNT:
			if a == Net.GUARD_MOUNT:
				_mount(p, a, b)
			else:
				server.mounts.order(p, a, b)  # (v60) guns are carried up by hand: the console orders it


func arm(p, a: int, on: bool) -> void:
	## (v68) A gun powered or cut, from the power panel (Power.ACT_GUN).
	var ship = server.ship
	if a == Net.GUARD_MOUNT:
		arm_guard(p, on)
		return
	if a < 0 or a >= ship.mounts.size() or ship.mounts[a] == Weapons.NONE:
		return
	if not on:
		ship.armed[a] = 0
		charge[a] = 0.0              # a gun without power loses its charge
		ship.cut.erase(a)            # (v89) switched off by hand: it stays off
	elif ship.armed[a] == 0:
		if power_used() + Weapons.power(ship.mounts[a]) > server.power.budget():
			if p != null:
				server.chat.tell(p, "Не хватает энергии реактора: %s берёт %d, свободно %d. Отключите другое орудие, щит или двигатели." % [
					Weapons.name_of(ship.mounts[a]), Weapons.power(ship.mounts[a]), server.power.budget() - power_used()])
			return
		ship.armed[a] = 1


func switch_shield(p, on: bool) -> void:
	## (v68) The shield switched on or off, from the power panel.
	var ship = server.ship
	if shield_cell() < 0:
		return
	if not on:
		ship.shield_on = false
		ship.shield = 0.0
		ship.cut.erase(-2)           # (v89) Outfit.CUT_SHIELD: switched off by hand, it stays off
	elif not ship.shield_on:
		if power_used() + Weapons.SHIELD_POWER > server.power.budget():
			if p != null:
				server.chat.tell(p, "Не хватает энергии реактора на щит: нужно %d, свободно %d." % [Weapons.SHIELD_POWER, server.power.budget() - power_used()])
			return
		ship.shield_on = true


func _mount(p, a: int, item: int) -> void:
	## (v58) A gun from the cargo (the thing `item`, with its effect if it has one) goes
	## on mount `a`, or the one there comes down (ITEM_NONE). The point defence has a
	## mount of its own (Net.GUARD_MOUNT), and nothing else goes there.
	var ship = server.ship
	var w := Weapons.of_item(item) if item != Net.ITEM_NONE else Weapons.NONE
	if item != Net.ITEM_NONE and (w == Weapons.NONE or Weapons.damaged(item) or int(ship.store.get(item, 0)) <= 0):
		return
	if a == Net.GUARD_MOUNT:
		if w != Weapons.NONE and w != Weapons.GUARD:
			return
		if w == ship.guard:
			return
		if ship.guard != Weapons.NONE:
			_into_cargo(Weapons.item_of(ship.guard))
		if w != Weapons.NONE:
			ship.store[item] -= 1
		ship.guard = w
		ship.guard_armed = false
		guard_charge = 0.0
		server.supplies.tell_store()
		server.chat.say("%s %s «Заслон»%s" % [p.name, "ставит в гнездо точечной обороны" if w != Weapons.NONE else "снимает в трюм",
			". Включите ему питание." if w != Weapons.NONE else "."])
		return
	if a >= ship.mounts.size() or w == Weapons.GUARD:
		return
	var old: int = ship.mounts[a]
	var old_fx: int = ship.mount_fx[a]
	if item != Net.ITEM_NONE and w == old and Weapons.fx_of(item) == old_fx:
		return
	if item == Net.ITEM_NONE and old == Weapons.NONE:
		return
	server.mounts.unload(a)                  # (v68) its hand-loaded rounds back into the locker
	if old != Weapons.NONE:
		_into_cargo(Weapons.item_of(old, old_fx))
	if w != Weapons.NONE:
		ship.store[item] -= 1
	ship.mounts[a] = w
	ship.mount_fx[a] = Weapons.fx_of(item) if w != Weapons.NONE else Weapons.FX_NONE
	ship.armed[a] = 0
	charge[a] = 0.0
	beam_left[a] = 0
	server.supplies.tell_store()
	if w == Weapons.NONE:
		server.chat.say("%s снимает с орудия %d: %s (в трюм)." % [p.name, a + 1, Weapons.lower_name(old, old_fx)])
	else:
		server.chat.say("%s ставит на орудие %d: %s.%s Включите ему питание." % [p.name, a + 1, Weapons.lower_name(w, ship.mount_fx[a]),
			"" if old == Weapons.NONE else " Снятое (%s) убрано в трюм." % Weapons.lower_name(old, old_fx)])


func _into_cargo(item: int) -> void:
	server.ship.store[item] = int(server.ship.store.get(item, 0)) + 1


func arm_guard(p, on: bool) -> void:
	var ship = server.ship
	if ship.guard == Weapons.NONE or on == ship.guard_armed:
		return
	if on and power_used() + Weapons.power(ship.guard) > server.power.budget():
		if p != null:
			server.chat.tell(p, "Не хватает энергии реактора: «Заслон» берёт %d, свободно %d." % [Weapons.power(ship.guard), server.power.budget() - power_used()])
		return
	ship.guard_armed = on
	if not on:
		guard_charge = 0.0
		ship.cut.erase(-1)           # (v89) Outfit.CUT_GUARD


func guard_ready() -> bool:
	## (v58) Is our point defence charged, powered and switched on?
	var ship = server.ship
	return ship.guard != Weapons.NONE and ship.guard_armed and server.powered() and guard_charge >= 1.0


func tick() -> void:
	## Our own guns, point defence and shield (v85: of the ship of our fleet in place; Fleet.each runs it for each).
	var map = server.map
	var ship = server.ship
	for cell: int in ship.jammed.keys():
		if server.tick >= int(ship.jammed[cell]):
			ship.jammed.erase(cell)
	var space: bool = server.arena.on()
	for i in charge.size():
		var w: int = ship.mounts[i]
		if w == Weapons.NONE or ship.armed[i] == 0:
			charge[i] = 0.0
		elif server.powered() and not ship.broken.has(map.guns[i]) and not jammed(map.guns[i]):
			# (v60) quicker with a gunner; (v94) in space each gun's own pace, Starsector's
			charge[i] = minf(charge[i] + server.mounts.pace(i) / (Weapons.space_ticks(w) if space else Weapons.charge_ticks(w)), 1.0)
	if ship.guard == Weapons.NONE or not ship.guard_armed:
		guard_charge = 0.0
	elif server.powered():
		guard_charge = minf(guard_charge + 1.0 / (Weapons.space_ticks(ship.guard) if space else Weapons.charge_ticks(ship.guard)), 1.0)
	# our shield: it falls without power, its generator or when switched off; it holds while ionised
	# ((v94) in space its strength is what its heat leaves, set by Arena)
	var gen := shield_cell()
	if space:
		pass
	elif gen < 0 or not ship.shield_on or not server.powered() or ship.broken.has(gen):
		ship.shield = 0.0
	elif not jammed(gen):
		ship.shield = minf(ship.shield + server.outfit.shield_regen() * server.stations.shield_pace() / Net.TICK_HZ, Weapons.SHIELD_FULL)
	for i in beam_left.size():
		if beam_left[i] > 0 and server.tick >= _beam_next[i]:
			server.wing.use(foe if server.wing.here else 0)   # (v86) a beam burns the enemy the console picked
			_beam_pulse(i)
			server.wing.use(0)
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func tick_enemy() -> void:
	## The pirate ship we fight: it fires, runs, mends, offers ransom. (v85) Its shots land on the ship of our
	## fleet it picked (target), so that ship's state is in place meanwhile.
	if server.fleet.is_lost(target):
		target = server.fleet.target()       # (v85) that ship of ours is lost: they turn on another
	server.fleet.use(target)
	_land_due()
	if engaged():
		var runs: float = Hulls.temper(temper)["flee"]
		if not fleeing() and ransom == 0 and runs > 0.0 and (enemy_hull <= roundi(hull_full() * runs) or (down(Net.ESYS_WEAPONS) and enemy_hull * 2 <= hull_full())):
			if not _offered and _rng.randf() < ransom_chance:
				_offers_ransom()
			else:
				_starts_to_flee()
		if ransom > 0 and server.tick >= ransom_until:
			_ransom_ends("Пираты не дождались ответа на выкуп.")
		if goal == Net.GOAL_BOUNTY and not goal_lost and down(Net.ESYS_WEAPONS) and down(Net.ESYS_ENGINE) \
				and not server.stations.ours_aboard:
			_surrenders()
			return
		_scan_tick()
		if _wing():
			pass                                           # (v86) the wingman never comes to dock
		elif (down(Net.ESYS_ENGINE) or fleeing() or held()) and server.derelict._pirates_dock_at >= 0:
			server.derelict._pirates_dock_at += 1          # it drifts, runs or is held: the time to fight it off stands still
		elif server.stations.slows_docking() and server.derelict._pirates_dock_at >= 0 and server.tick % 2 == 0:
			server.derelict._pirates_dock_at += 1          # (v55) we keep our distance: it closes in at half the pace
		if fleeing() and not held() and (_wing() or not server.stations.ours_aboard):
			flee += _jump_rate()
			if flee >= _flee_seconds() * Net.TICK_HZ:
				_escaped()
		if boss > 0 and not phase2 and enemy_hull > 0 and enemy_hull <= roundi(hull_full() * PHASE2_SHARE):
			_phase_two()
		_enemy_shield_tick()
		if engaged() and not down(Net.ESYS_WEAPONS) and ransom == 0:
			var pace: float = 1.0 / _weapons_slowness() / _slower * float(Hulls.temper(temper)["pace"]) \
				* (1.0 if _manned(Net.ESYS_WEAPONS) else UNMANNED_PACE) * server.hazards.enemy_pace() \
				* (PHASE2_PACE if phase2 and boss == 1 else 1.0) * (RUNNER_PACE if goal == Net.GOAL_RUNNER else 1.0)
			var space: bool = server.arena.on()
			for k in enemy_weapons.size():
				var ew: int = enemy_weapons[k]
				enemy_charge[k] = minf(enemy_charge[k] + pace / (Weapons.space_ticks(ew) if space else Weapons.charge_ticks(ew)), 1.0)
				if enemy_charge[k] >= 1.0 and engaged() and (not space or Weapons.bomb(ew)
						or server.arena.enemy_bears(server.wing.on, k) and server.arena.enemy_heat_ok(server.wing.on, ew)):
					# (v92) its gun must bear on us; (v94) and its ship not be overloaded or too hot
					enemy_charge[k] = 0.0
					if space and not Weapons.bomb(ew):
						server.arena.enemy_heated(server.wing.on, ew)
					_enemy_fires(ew, enemy_fx[k] if k < enemy_fx.size() else Weapons.FX_NONE, 0, k)
		if engaged() and server.tick >= _mend_next:
			_mend_tick()
	server.fleet.use(0)


func _enemy_shield_tick() -> void:
	## Its shield refills as fast as its generator is whole; knocked out, it falls. ((v94) in space: Arena's heat)
	if flies and server.arena.on():
		return
	if systems.size() <= Net.ESYS_SHIELDS or systems_full[Net.ESYS_SHIELDS] == 0 or systems[Net.ESYS_SHIELDS] == 0:
		enemy_shield = 0.0
	elif server.tick >= systems_out[Net.ESYS_SHIELDS]:
		enemy_shield = minf(enemy_shield + Weapons.SHIELD_REGEN * _regen * server.hazards.enemy_regen() / Net.TICK_HZ * systems[Net.ESYS_SHIELDS] / systems_full[Net.ESYS_SHIELDS],
			Weapons.SHIELD_FULL)


func held() -> bool:
	## Does our tractor beam hold it now?
	return engaged() and server.tick < held_until


func _enemy_shield_up() -> bool:
	return enemy_shield > 0.0 and systems.size() > Net.ESYS_SHIELDS and not down(Net.ESYS_SHIELDS)


func packet() -> PackedByteArray:
	## (v86) The enemy part is of the one our guns aim at (foe); both enemies' summaries go at the end.
	var w = server.wing
	w.use(foe if w.here else 0)
	var out := _packet()
	w.use(0)
	out.append(foe if w.here else 0)
	out.append_array(w.summary(0))
	out.append_array(w.summary(1))
	return out


func _packet() -> PackedByteArray:
	var map = server.map
	var ship = server.ship
	var out := PackedByteArray([Net.S_GUNS, ship.id & 0xFF, ship.id >> 8, charge.size()])
	for i in charge.size():
		out.append(ship.mounts[i])
		if ship.broken.has(map.guns[i]):
			out.append(Net.GUN_BROKEN)
		elif jammed(map.guns[i]):
			out.append(Net.GUN_JAMMED)
		else:
			out.append(roundi(charge[i] * 20.0) * 5)
		var ammo := Weapons.ammo(ship.mounts[i])
		out.append((Net.GUNF_ARMED if ship.armed[i] == 1 else 0) | (Net.GUNF_BEAM if beam_left[i] > 0 else 0)
			| (Net.GUNF_NO_AMMO if ammo != 0 and not server.mounts.has_round(i) else 0))
	out.append(power_used())
	out.append(server.power.budget())                  # (v61) the reactor's power now, with the SMES's boost
	var gen := shield_cell()
	out.append(roundi(ship.shield))
	out.append(0 if gen < 0 else (Net.SHF_HAS | (Net.SHF_ON if ship.shield_on else 0) | (Net.SHF_BROKEN if ship.broken.has(gen) else 0)
		| (Net.SHF_JAMMED if jammed(gen) else 0) | (Net.SHF_HARDENED if server.outfit.hardened() else 0)))
	out.append(enemy_hull if engaged() else 0)
	out.append(hull_full() if engaged() else 0)
	var left := 0
	if engaged() and not _wing() and server.derelict._pirates_dock_at >= 0:
		left = maxi(int(ceil(float(server.derelict._pirates_dock_at - server.tick) / Net.TICK_HZ)), 0)
	out.append(left & 0xFF)
	out.append(left >> 8)
	out.append(aim)
	if engaged():
		out.append(systems.size())
		for i in systems.size():
			out.append(systems[i])
			out.append(systems_full[i])
			out.append(clampi(int(ceil(float(systems_out[i] - server.tick) / Net.TICK_HZ)), 0, 255))
	else:
		out.append(0)
	out.append(((Net.ENEMY_RAID if raid else 0) | (Net.ENEMY_FLEEING if fleeing() else 0) | (Net.ENEMY_HELD if held() else 0)
		| (Net.ENEMY_RANSOM if ransom > 0 else 0) | (Net.ENEMY_PHASE2 if phase2 else 0) | (Net.ENEMY_CREWLESS if crewless else 0))
		if engaged() else 0)
	var jump := jump_seconds_left() if engaged() and fleeing() else 0
	out.append(jump & 0xFF)
	out.append(jump >> 8)
	out.append(roundi(enemy_shield) if engaged() else 0)
	out.append(klass)
	out.append(temper if temper_known else Net.TEMPER_UNKNOWN)
	if engaged():
		out.append(room_sys.size())
		for r in room_sys.size():
			out.append(room_sys[r] if revealed[r] == 1 else Net.ROOM_UNKNOWN)
	else:
		out.append(0)
	out.append(mini(int(ship.store.get(Net.ITEM_PROBE, 0)), 255))
	if engaged():
		out.append(enemy_weapons.size())
		out.append_array(enemy_weapons)
	else:
		out.append(0)
	out.append(mini(ransom, 255) if engaged() else 0)
	out.append(clampi(int(ceil(float(ransom_until - server.tick) / Net.TICK_HZ)), 0, 255) if engaged() and ransom > 0 else 0)
	out.append_array(ship.mount_fx)
	out.append(ship.guard)
	out.append(roundi(guard_charge * 20.0) * 5)
	out.append(Net.GUNF_ARMED if ship.guard_armed else 0)
	out.append(1 if engaged() and enemy_guard else 0)
	if engaged():
		out.append_array(enemy_fx)
		# (v59) the top sensors show its guns charging, per gun 0..100 (255 = not seen)
		for k in enemy_charge.size():
			out.append(roundi(enemy_charge[k] * 20.0) * 5 if server.outfit.sees_charge() else 255)
	# (v68) u8 its goal (GOAL_*), u8 GOALF_*, u8 the cargo pod's room (255 = none), u16 what the goal pays
	var f := engaged()
	out.append(goal if f else Net.GOAL_NONE)
	out.append(Net.GOALF_LOST if goal_lost else 0)
	out.append(cargo_room if f and cargo_room >= 0 else 255)
	var o := out.size()
	out.resize(o + 2)
	out.encode_u16(o, goal_pay if f else 0)
	return out


func _weapons_slowness() -> float:
	## Its guns fire slower as they are worn down.
	if systems.size() <= Net.ESYS_WEAPONS or systems[Net.ESYS_WEAPONS] == 0:
		return 1.0
	return float(systems_full[Net.ESYS_WEAPONS]) / float(systems[Net.ESYS_WEAPONS])


func _starts_to_flee() -> void:
	flee = 0.0
	if _wing():
		server.chat.say("%s сильно повреждён и заряжает прыжок, чтобы уйти." % server.wing.name)
		return
	var why := "" if _jump_rate() > 0.0 else " Но %s выбит: пока его не починят, прыжка не будет." % \
		("двигатель" if down(Net.ESYS_ENGINE) else "гипердвигатель")
	server.chat.say("Пиратский корабль сильно повреждён и заряжает гипердвигатель, чтобы уйти: через %d с его не догнать. Выбейте двигатель или гипердвигатель, и он не уйдёт.%s" % [
		int(FLEE_SECONDS), why])


func _escaped() -> void:
	## It got its jump charged: it is gone, and nobody is paid for it.
	enemy_hull = 0
	if _wing():
		server.chat.say("%s ушёл в прыжок." % server.wing.name)   # (v86) Wing.tick sees it gone
		return
	beam_left.fill(0)
	server.derelict.pirates_escaped()
	server.chat.say("Курьер ушёл в прыжок вместе с грузом. Упустили." if goal == Net.GOAL_RUNNER else "Пиратский корабль ушёл в прыжок. Упустили.")
	goal_lost = true


func fire(p, which: int) -> void:
	## Somebody at the gun console fires one gun, or every gun that is ready (which = 255),
	## (v86) at the enemy the console picked (foe).
	server.wing.use(foe if server.wing.here else 0)
	_fire(p, which)
	server.wing.use(0)


func fire_mount(p, i: int) -> void:
	## (v92) Gun i fired from its own mount: by the player who took its controls, or by a bot gunner there.
	server.wing.use(foe if server.wing.here else 0)
	_fire(p, i, true)
	server.wing.use(0)


func _fire(p, which: int, at_mount: bool = false) -> void:
	var map = server.map
	var ship = server.ship
	if not at_mount and not server.systems.at_console(p, map.gun_console):
		return
	if not engaged():
		if not at_mount:
			server.chat.say("Стрелять не по кому: целей нет.")
		return
	var arena = server.arena
	var space: bool = arena.on()
	var wide := 0                        # (v92) guns that would fire but do not bear on the target
	var hot := 0                         # (v94) guns that would fire but their ship is too hot
	var fired := 0
	var focus := _focus(which)
	_aim_bonus = GUNNER_HIT * p.skill(Net.SKILL_GUNS) * server.stations.share(p)   # (v60) the one at the console aims better with skill (v70: a bot, half)
	for i in charge.size():
		if not ((which == 255 or which == i) and charge[i] >= 1.0 and ship.armed[i] == 1 and not ship.broken.has(map.guns[i]) \
				and not jammed(map.guns[i]) and beam_left[i] == 0):
			continue
		var w: int = ship.mounts[i]
		var fx: int = ship.mount_fx[i]
		var ammo := Weapons.ammo(w)
		if space and not at_mount and arena.manned_by_hand(server.fleet.on, i):
			continue                         # (v92) a player aims that one himself
		if space and not (arena.reaches(server.fleet.on, i, server.wing.on) if _instant(w) else arena.bears(server.fleet.on, i)):
			wide += 1                        # (v92) the target is outside its arc (or out of a beam's reach)
			continue
		if space and not arena.heat_ok(server.fleet.on, w):
			hot += 1                         # (v94) overloaded, venting, or too hot for one more burst
			continue
		if not server.mounts.take_round(i):        # (v68) a round loaded by hand first, then the locker
			server.chat.tell(p, "Орудие %d: нет %s в трюме (%s)." % [i + 1, "снарядов" if ammo == Net.ITEM_SHELL else "ракет",
				Weapons.lower_name(w, fx)])
			continue
		charge[i] = 0.0
		fired += 1
		server.mounts.fired(i)
		if space and not _instant(w):
			arena.heated(server.fleet.on, w)       # (v94) a beam heats a second at a time (_beam_pulse)
		if Weapons.klass(w) == Weapons.CLASS_BEAM or Weapons.klass(w) == Weapons.CLASS_SIPHON:
			beam_left[i] = Weapons.pulses(w)
			_beam_next[i] = server.tick
			_beam_room[i] = _any_room()
			_beam_log[i] = [0, 0, PackedStringArray()]        # pulses that burned, pulses the shield stopped, what came of it
			_beam_pulse(i)
		elif Weapons.klass(w) == Weapons.CLASS_TRACTOR:
			_tractor(i, w)
		elif Weapons.bomb(w):
			_our_bomb(i, w, fx)
		else:
			_our_volley(i, w, fx, 0, focus if Weapons.klass(w) == Weapons.CLASS_LASER else 0.0)
			if fx == Weapons.FX_TWICE and _rng.randf() < Weapons.FX_TWICE_CHANCE:
				# (v58) the effect «сдвоенный»: a second volley right behind the first, free of ammunition
				_our_volley(i, w, fx, int(Weapons.info(w)["shots"]) * Weapons.BURST_GAP_TICKS + 6)
		if not engaged() or _settle():
			break
	_aim_bonus = 0.0
	if wide > 0 and fired == 0 and not at_mount and not p.bot:
		server.chat.tell(p, "Цель вне сектора обстрела: орудия стреляют только в свою сторону. Пилоту нужно развернуть корабль бортом.")
	elif hot > 0 and fired == 0 and not at_mount and not p.bot:
		server.chat.tell(p, "Щит перегружен или идёт сброс нагрева: орудия молчат, пока это не кончится.")
	if fired > 0:
		p.train(Net.SKILL_GUNS)
		if ransom > 0 and engaged():
			_ransom_ends("Мы открыли огонь: пираты отзывают выкуп.")
		_settle()


func _ready_to_fire(i: int) -> bool:
	var ship = server.ship
	return charge[i] >= 1.0 and ship.armed[i] == 1 and not ship.broken.has(server.map.guns[i]) and not jammed(server.map.guns[i]) \
		and beam_left[i] == 0


func _focus(which: int) -> float:
	## (v59, the author's mirror note) With the focusing array, lasers fired in one
	## volley at one room join into one beam: the shield counts Gear.FOCUS_PIERCE
	## weaker for each laser past the first. 0 = no joining.
	if which != 255 or not server.outfit.focus() or _aimed_room() < 0:
		return 0.0
	var n := 0
	for i in charge.size():
		if _ready_to_fire(i) and Weapons.klass(server.ship.mounts[i]) == Weapons.CLASS_LASER:
			n += 1
	return Gear.FOCUS_PIERCE * (n - 1) if n >= 2 else 0.0


func settle() -> bool:
	return _settle()


func _settle() -> bool:
	## After our hits: is it wrecked, or is its boarding party dead? True if the fight is over.
	if _over:
		return true                          # (settled already: it is paid for once)
	if enemy_hull <= 0 and systems.size() > 0:
		_wrecked()
		return true
	if crewless:
		# (v62) a drone ship: its guards dead or not, it is taken only by wrecking its core by hand
		if systems.size() > Net.ESYS_DRONES and systems[Net.ESYS_DRONES] == 0 and server.stations.ours_aboard:
			_wrecked()
			return true
		return false
	if systems.size() > 0 and enemy_hull > 0 and systems[Net.ESYS_CREW] == 0:
		if raid or server.stations.ours_aboard:
			_wrecked()                       # nobody left alive aboard: it drifts, a dead hulk
		else:
			_broken_off()
		return true
	return false


func _broken_off() -> void:
	## Its boarding party is dead: with nobody to send over it gives up and goes.
	if _wing():
		_wrecked()
		return
	server.story.pirates_beaten()           # (v63) a bounty's or the courier's
	_over = true
	enemy_hull = 0
	beam_left.fill(0)
	server.derelict.pirates_wrecked()
	server.chat.say("Абордажная команда пиратов перебита! Пиратский корабль прекращает атаку и уходит.")


func _hit_chance(w: int) -> float:
	## Ours: better while its bridge is out (it cannot dodge) and while our tractor beam holds it.
	var dodge := _dodge if _manned(Net.ESYS_HELM) else minf(_dodge, 0.0)
	if flies and server.arena.on():
		dodge = 0.0                          # (v93, the author's P5 A) in space it dodges by flying, not by a roll
	var hit := clampf(float(Weapons.info(w)["hit"]) - dodge + server.stations.our_hit_bonus() + _aim_bonus, 0.05, Weapons.BEST_HIT)
	var bonus := (Weapons.BLIND_BONUS if down(Net.ESYS_HELM) else 0.0) + (Weapons.TRACTOR_BONUS if held() else 0.0)
	if bonus > 0.0:
		hit = maxf(hit, minf(hit + bonus, Weapons.BEST_HIT))
	return hit


func _tractor(i: int, w: int) -> void:
	## The tractor beam: it never misses; unless the shield stops it, it holds the ship.
	var map = server.map
	var cell: int = map.guns[i]
	var space_stop: bool = server.arena.on() and server.arena._shielded(server.arena.of_enemy(server.wing.on)) \
		if server.arena.of_enemy(server.wing.on) != null else false
	if space_stop or not server.arena.on() and _meets_shield(w, false) and _enemy_shield_up() and _rng.randf() >= Weapons.through_chance(enemy_shield):
		_draw_beam(cell, Net.SHOT_TRACTOR, 0, -1, w)
		enemy_shield = maxf(enemy_shield - Weapons.shield_damage(w), 0.0)
		server.chat.say_bridge("Орудие %d (захватный луч): щит пиратов не пустил луч.%s" % [i + 1, _enemy_state()])
		return
	_draw_beam(cell, Net.SHOT_TRACTOR, Net.LANDED, -1, w)
	if server.arena.on():
		server.arena.draw_beam(server.fleet.on, i, server.wing.on, -1, Net.SHOT_TRACTOR, false)
	var hold := float(Weapons.info(w)["hold"]) if Weapons.info(w).has("hold") else Weapons.TRACTOR_HOLD
	held_until = maxi(held_until, server.tick + roundi(hold * Net.TICK_HZ))
	server.chat.say_bridge("Орудие %d (захватный луч): пиратский корабль схвачен на %d с: не уклоняется, не уходит прыжком и не подходит к шлюзу.%s" % [
		i + 1, int(hold), _enemy_state()])


const HOW_PLAIN := 0                 # (v58) what became of one of our shots on its way (see _our_volley)
const HOW_DOWN := 1                  # shot down by its point defence
const HOW_RICOCHET := 2              # turned aside by its armour
const HOW_HELD := 5                  # (v93) its armour held it (Arena)
const HOW_SOFT := 3                  # a kinetic shell that went through its shield, one damage the less


static func _instant(w: int) -> bool:
	## (v92) Does that gun reach at once (a beam, a tractor, a siphon, a bomb) rather than fire a shot that flies?
	var k := Weapons.klass(w)
	return k == Weapons.CLASS_BEAM or k == Weapons.CLASS_SIPHON or k == Weapons.CLASS_TRACTOR or Weapons.bomb(w)


func _our_volley(i: int, w: int, fx: int = Weapons.FX_NONE, start: int = 0, focus: float = 0.0) -> void:
	## One gun's shot (or burst) at the enemy. (v56) Each shot is rolled now (hit
	## or miss, the room, whether the shield will stop it) and drawn on its way;
	## it lands Weapons.flight_ticks later, and the volley is told in one line
	## when its last shot has landed. (v58) Its point defence may shoot a rocket
	## down, its armour may turn a kinetic shell aside, and its shield only takes
	## a point off a shell's damage.
	var map = server.map
	var cell: int = map.guns[i]
	var x: int = cell % map.width
	var y: int = cell / map.width
	server.combat.jolt(Net.JOLT_FIRE, w, Vector2(x, y))
	var shots: int = Weapons.space_shots(w) if flies and server.arena.on() else int(Weapons.info(w)["shots"])
	var log := {"gun": i, "w": w, "fx": fx, "left": shots, "misses": 0, "stopped": 0, "down": 0, "ricochet": 0,
		"hits": PackedStringArray(), "said": PackedStringArray(), "focus": focus > 0.0, "ship": server.fleet.on}
	var shield := enemy_shield              # as the shield will be when each shot meets it
	var pierce := (Weapons.FX_PIERCE_BY if fx == Weapons.FX_PIERCE else 0.0) + focus
	if flies and server.arena.on():
		# (v92) each shot flies in the fight's space and finds what it finds (see arena_hit)
		var miss := 1.0 - _hit_chance(w)
		for s in shots:
			server.arena.fire_ours(server.fleet.on, i, w, server.wing.on, _aimed_room(), miss, start + s * Weapons.BURST_GAP_TICKS,
				{"log": log, "pierce": pierce, "ship": server.fleet.on, "foe": server.wing.on})
		return
	for s in shots:
		var delay := start + s * Weapons.BURST_GAP_TICKS
		var hit := _rng.randf() < _hit_chance(w)
		var room := -1
		var stop := false
		var how := HOW_PLAIN
		if Weapons.guard_chance(w) > 0.0 and enemy_guard and not down(Net.ESYS_WEAPONS) and server.tick + delay >= _enemy_guard_ready:
			_enemy_guard_ready = server.tick + delay + Weapons.charge_ticks(Weapons.GUARD)
			if _rng.randf() < Weapons.guard_chance(w):
				how = HOW_DOWN
				hit = false
		if hit:
			room = _aimed_room()
			if room < 0:
				room = _any_room()
			if Weapons.area(w) and _rng.randf() < AREA_SPREAD:
				room = _beside(room)             # (v62) «Шрапнель»: a fragment finds the room next door
			if Weapons.klass(w) == Weapons.CLASS_KINETIC and _rng.randf() < enemy_armour:
				how = HOW_RICOCHET
			elif Weapons.klass(w) == Weapons.CLASS_KINETIC and not Weapons.passes_shield(w) and _enemy_shield_up() and shield > 0.0:
				how = HOW_SOFT
				shield = maxf(shield - Weapons.KINETIC_WEAR, 0.0)
				stop = int(Weapons.info(w)["damage"]) <= Weapons.KINETIC_SHIELD
			elif _meets_shield(w, false) and _enemy_shield_up() and shield > 0.0 and _rng.randf() >= Weapons.through_chance(shield - pierce):
				stop = true
				shield = maxf(shield - Weapons.shield_damage(w), 0.0)
		var ends := (0 if stop else Net.LANDED) if hit else Net.MISSED
		if how == HOW_DOWN:
			ends = Net.SHOT_DOWN
		elif how == HOW_RICOCHET:
			ends = Net.RICOCHET
		var spot := _draw_ours(cell, w, ends, room, delay)
		_after(delay + Weapons.flight_ticks(w), _our_shot_lands.bind(log, hit, room, stop, spot, how))


func _our_shot_lands(log: Dictionary, hit: bool, room: int, stop: bool, spot: Vector2, how: int = HOW_PLAIN) -> void:
	## One shot of ours arrives (see _our_volley).
	log["left"] -= 1
	var w: int = log["w"]
	if not _finds(int(log.get("ship", 0))):
		return                               # it is wrecked, gone or docked by now: the shot finds nothing
	if how == HOW_DOWN:
		log["down"] += 1
		server.combat.jolt(Net.JOLT_THEIR_SHIELD, Net.SHOT_FLAK, spot)
	elif not hit:
		log["misses"] += 1
	elif how == HOW_RICOCHET:
		log["ricochet"] += 1
		server.combat.jolt(Net.JOLT_THEIR_SHIELD, _shot_kind(w), spot)
	elif how == HOW_HELD:
		log["held"] = int(log.get("held", 0)) + 1
		server.combat.jolt(Net.JOLT_THEIR_SHIELD, _shot_kind(w), spot)
	elif stop:
		if not server.arena.on():
			enemy_shield = maxf(enemy_shield - Weapons.shield_damage(w), 0.0)
		log["stopped"] += 1
		server.combat.jolt(Net.JOLT_THEIR_SHIELD, _shot_kind(w), spot)
	else:
		server.combat.jolt(Net.JOLT_THEIR_HIT, _shot_kind(w), spot)
		var r := _land_through(w, system_in(room), room, int(log["fx"]), how == HOW_SOFT)
		(log["hits"] as PackedStringArray).append(_room_word(room))
		if r != "+":
			(log["said"] as PackedStringArray).append(r)
	var over := enemy_hull <= 0 or (not crewless and systems.size() > Net.ESYS_CREW and systems[Net.ESYS_CREW] == 0)
	if int(log["left"]) <= 0 or over:
		log["left"] = 0
		_tell_volley(log)
	if over or int(log["left"]) <= 0:
		_settle()


func _tell_volley(log: Dictionary) -> void:
	var hits: PackedStringArray = log["hits"]
	var said: PackedStringArray = log["said"]
	var parts := PackedStringArray()
	if not hits.is_empty():
		parts.append(("попадание: " if hits.size() == 1 else "попадания (%d): " % hits.size()) + ", ".join(_unique(hits)))
	if int(log["stopped"]) > 0:
		parts.append("щит остановил" + ("" if int(log["stopped"]) == 1 else " %d" % int(log["stopped"])))
	if int(log["misses"]) > 0:
		parts.append("промах" + ("" if int(log["misses"]) == 1 else " ×%d" % int(log["misses"])))
	if int(log.get("ricochet", 0)) > 0:
		parts.append("рикошет от брони" + ("" if int(log["ricochet"]) == 1 else " ×%d" % int(log["ricochet"])))
	if int(log.get("held", 0)) > 0:
		parts.append("броня не пробита" + ("" if int(log["held"]) == 1 else " ×%d" % int(log["held"])))
	if int(log.get("down", 0)) > 0:
		var what := "ракет" if Weapons.klass(int(log["w"])) == Weapons.CLASS_ROCKET else "снаряд"
		parts.append(("%s сбила их точечная оборона" % ("ракету" if what == "ракет" else "снаряд")) if int(log["down"]) == 1
			else "%s сбила их точечная оборона (%d)" % ["ракеты" if what == "ракет" else "снаряды", int(log["down"])])
	if parts.is_empty() or said.is_empty() and hits.is_empty() and server.arena.on():
		return                               # (v94) in space guns fire every second: only what got inside is told
	server.chat.say_bridge("Орудие %d (%s%s): %s.%s%s" % [int(log["gun"]) + 1, Weapons.lower_name(int(log["w"]), int(log.get("fx", 0))),
		", сведённый луч" if log.get("focus", false) else "", "; ".join(parts),
		"" if said.is_empty() else " " + " ".join(_unique(said)), _enemy_state()])


# ---------------------------------------------------------------- (v56) drawing shots on their way

const OUT_CELLS := 16.0              # how far into space a shot is drawn leaving its gun, or coming in
const BUBBLE := 1.6                  # cells between a ship's hull and its shield's bubble


func _draw_ours(cell: int, w: int, ends: int, room: int, delay: int) -> Vector2:
	## A shot of ours on its way: out of our gun into space (half its flight), then
	## in at the pirate ship from the side, to the room (or into its shield's bubble,
	## or past it). Told to those near either end, and to the gun console's plan.
	## Where it ends, in cells (-1, -1: the enemy is not drawn).
	var map = server.map
	var kind := _shot_kind(w)
	var flight := Weapons.flight_ticks(w)
	var half := flight / 2
	var at := Vector2(cell % map.width, cell / map.width)
	var out := Vector2(_outward(cell))
	server.combat.tell_shot(kind, Net.MISSED, at, at + out * OUT_CELLS, int(at.y), delay, half)
	server.combat.tell_volley(Net.VOLLEY_OURS, kind, ends, room, delay, flight)
	var spot := _room_spot(room if room >= 0 else _fx_room())
	if spot.x < 0.0:
		return spot
	var box := _enemy_box()
	var side := Vector2(-1.0 if spot.x < box.get_center().x else 1.0, _fx.randf_range(-0.35, 0.35)).normalized()
	var from := spot + side * OUT_CELLS
	var to := spot
	if ends == 0:
		to = _bubble_entry(from, spot, box)
	elif ends == Net.MISSED:
		to = spot - side * OUT_CELLS + side.orthogonal() * _fx.randf_range(-2.5, 2.5)
	elif ends == Net.SHOT_DOWN:
		to = from.lerp(spot, 0.45)           # (v58) its point defence meets it on the way in
	server.combat.tell_shot(kind, ends, from, to, int(spot.y), delay + half, flight - half)
	return to


func _draw_theirs(w: int, cell: int, ends: int, delay: int) -> Vector2:
	## One of its shots on its way: a flash out of its weapons room, then in at
	## our hull from space at that cell (or into our bubble, or past us). Where it ends.
	var map = server.map
	var kind := _shot_kind(w)
	var flight := Weapons.flight_ticks(w)
	var half := flight / 2
	var gun_room := room_of_system(Net.ESYS_WEAPONS)
	server.combat.tell_volley(Net.VOLLEY_THEIRS, kind, ends, gun_room, delay, flight)
	var muzzle := _room_spot(gun_room)
	if muzzle.x >= 0.0:
		var box := _enemy_box()
		var side := Vector2(-1.0 if muzzle.x < box.get_center().x else 1.0, 0.0)
		server.combat.tell_shot(kind, Net.MISSED, muzzle, muzzle + side * OUT_CELLS, int(muzzle.y), delay, half)
	if cell < 0:
		return Vector2(-1, -1)
	var at := Vector2(cell % map.width, cell / map.width)
	var out := Vector2(_outward(cell))
	var along := out.orthogonal() * (1.0 if _fx.randf() < 0.5 else -1.0)
	var from := at + out * OUT_CELLS + along * _fx.randf_range(-3.0, 3.0)
	var to := at
	if ends == 0:
		to = at + (from - at).normalized() * BUBBLE
	elif ends == Net.MISSED:
		# it grazes past, just off the hull
		from = at + out * (OUT_CELLS * 0.7) + along * 10.0
		to = at + out * 1.2 - along * 12.0
	elif ends == Net.SHOT_DOWN:
		to = from.lerp(at, 0.55)             # (v58) our point defence meets it on the way in
	server.combat.tell_shot(kind, ends, from, to, int(at.y), delay + half, flight - half)
	return to


func _draw_beam(cell: int, kind: int, ends: int, room: int, w: int) -> void:
	## A second of a beam: a line out of our gun, and one across into the pirate
	## ship (its room, or its shield's bubble; a siphon or tractor is drawn to its middle).
	var map = server.map
	var at := Vector2(cell % map.width, cell / map.width)
	server.combat.tell_shot(kind, Net.MISSED, at, at + Vector2(_outward(cell)) * OUT_CELLS, int(at.y))
	server.combat.jolt(Net.JOLT_FIRE, w, at)
	server.combat.tell_volley(Net.VOLLEY_OURS, kind, ends, room, 0, Weapons.BEAM_PULSE_TICKS)
	var box := _enemy_box()
	var spot := _room_spot(room) if room >= 0 else (box.get_center() if box.size.x > 0.0 else Vector2(-1, -1))
	if spot.x < 0.0:
		return
	var side := Vector2(-1.0 if spot.x < box.get_center().x else 1.0, -0.2).normalized()
	var from := spot + side * OUT_CELLS
	var to := _bubble_entry(from, spot, box) if ends == 0 else spot
	server.combat.tell_shot(kind, ends, from, to, int(spot.y))
	if kind == Net.SHOT_BEAM or kind == Net.SHOT_REAPER:
		server.combat.jolt(Net.JOLT_THEIR_SHIELD if ends == 0 else Net.JOLT_THEIR_HIT, kind, to)


func _room_spot(room: int) -> Vector2:
	## A cell of that room of the pirate ship, by lot, in the grid's cells (-1, -1: none).
	var o = server.map.other
	if _wing() or o == null or room < 0 or room >= o.rooms.size() or server.map.other_at == server.map.NO_OTHER:
		return Vector2(-1, -1)                # ((v86) the wingman is not in the grid: it is not drawn)
	var cells: Array = Array(o.rooms[room])
	if cells.is_empty():
		return Vector2(-1, -1)
	var c: int = server.derelict._cell(server.map.other_at, int(cells[_fx.randi_range(0, cells.size() - 1)]))
	return Vector2(c % server.map.width, c / server.map.width)


func _fx_room() -> int:
	return _fx.randi_range(0, room_sys.size() - 1) if room_sys.size() > 0 else -1


func _enemy_box() -> Rect2:
	## The pirate ship's drawing in the grid's cells.
	var o = server.map.other
	var at: Vector2i = server.map.other_at
	return Rect2(Vector2(at), Vector2(o.width, o.height)) if o != null and not _wing() else Rect2()


func _bubble_entry(from: Vector2, to: Vector2, box: Rect2) -> Vector2:
	## Where a line from `from` to `to` first meets the pirate ship's shield
	## bubble: an ellipse a little wider than its drawing.
	var c := box.get_center()
	var r := box.size / 2.0 + Vector2(BUBBLE, BUBBLE)
	var p := from
	var step := (to - from).normalized() * 0.25
	for i in roundi(from.distance_to(to) / 0.25):
		var d := (p - c) / r
		if d.length_squared() <= 1.0:
			return p
		p += step
	return to


func _after(ticks: int, landing: Callable) -> void:
	## (v56) What a shot does when it gets there, that many ticks from now.
	if not flies or ticks <= 0:
		landing.call()
	else:
		_flying.append([server.tick + ticks, landing])


func _land_due() -> void:
	## (v56) The shots that get there this tick, in the order they were fired.
	if _flying.is_empty():
		return
	var due: Array = []
	var still: Array = []
	for f: Array in _flying:
		(due if server.tick >= int(f[0]) else still).append(f)
	if due.is_empty():
		return
	_flying = still
	for f: Array in due:
		(f[1] as Callable).call()


func in_flight() -> int:
	## (v56) Shots on their way now (tests).
	return _flying.size()


func _beam_pulse(i: int) -> void:
	## A cutting beam burns a second more: never a miss, the shield permitting.
	var map = server.map
	if not engaged():
		beam_left[i] = 0
		return
	var w: int = server.ship.mounts[i]
	if Weapons.klass(w) == Weapons.CLASS_SIPHON:
		_siphon_pulse(i)
		return
	var cell: int = map.guns[i]
	var room := _aimed_room()
	if room < 0:
		room = _beam_room[i]
	var space: bool = server.arena.on()
	var r := ""
	if space and not server.arena.reaches(server.fleet.on, i, server.wing.on):
		r = "-"                              # (v92) the target has left its arc or its reach: this second burns nothing
	elif space:
		# (v94) a second of the beam in space: a raised shield takes it as heat, else it burns the hull through its armour
		server.arena.heated(server.fleet.on, w)
		var burn: Dictionary = server.arena.beam_burn(server.fleet.on, i, server.wing.on, room, w)
		if bool(burn["stopped"]):
			r = ""
		elif int(burn["units"]) > 0:
			var lay = server.map.others[server.arena.of_enemy(server.wing.on).layout]
			var at_room := _room_by(lay, int(burn["cell"]))
			if at_room >= 0:
				room = at_room
			_units = int(burn["units"])
			r = _land_through(w, system_in(room), room, server.ship.mount_fx[i])
			_units = -1
		else:
			r = "+"
	else:
		r = _land_on_enemy(w, system_in(room), room, server.ship.mount_fx[i])
		if space:
			server.arena.draw_beam(server.fleet.on, i, server.wing.on, room, _shot_kind(w), r == "")
	if r == "-":
		r = ""
	_draw_beam(cell, _shot_kind(w), 0 if r == "" else Net.LANDED, room, w)
	var log: Array = _beam_log[i]
	if r == "":
		log[1] += 1
	else:
		log[0] += 1
		if r != "+":
			(log[2] as PackedStringArray).append(r)
	beam_left[i] -= 1
	_beam_next[i] = server.tick + Weapons.BEAM_PULSE_TICKS
	if beam_left[i] == 0 or enemy_hull <= 0:
		beam_left[i] = 0
		var parts := PackedStringArray()
		if log[0] > 0:
			parts.append("прожёг %d раз (%s)" % [log[0], _room_word(room)])
		if log[1] > 0:
			parts.append("щит не пустил %d раз" % log[1])
		server.chat.say_bridge("Орудие %d (%s): %s.%s%s" % [i + 1, Weapons.lower_name(w, server.ship.mount_fx[i]), ", ".join(parts),
			"" if (log[2] as PackedStringArray).is_empty() else " " + " ".join(_unique(log[2])), _enemy_state()])
	if engaged():
		_settle()


func _siphon_pulse(i: int) -> void:
	## A siphon beam drinks a second more of the enemy's shield and pours it into ours.
	var map = server.map
	var ship = server.ship
	var cell: int = map.guns[i]
	_draw_beam(cell, Net.SHOT_SIPHON, 0 if enemy_shield > 0.0 else Net.LANDED, -1, ship.mounts[i])
	if server.arena.on():
		server.arena.draw_beam(server.fleet.on, i, server.wing.on, -1, Net.SHOT_SIPHON, false)
	var log: Array = _beam_log[i]
	if server.arena.on():
		# (v94) in space it moves heat: what it puts on their raised shield it takes off ours
		var n := Weapons.space_damage(Weapons.SIPHON)
		var cooled: float = server.arena.siphon(server.fleet.on, server.wing.on, n) if server.arena.reaches(server.fleet.on, i, server.wing.on) else -1.0
		if cooled >= 0.0:
			log[0] += n
			log[1] += cooled
	else:
		var take := minf(enemy_shield, Weapons.SIPHON_DRAIN)
		enemy_shield -= take
		log[0] += take
		var gen := shield_cell()
		if take > 0.0 and gen >= 0 and ship.shield_on and server.powered() and not ship.broken.has(gen) and not jammed(gen):
			var room: float = Weapons.SHIELD_FULL - ship.shield
			ship.shield = minf(ship.shield + take, Weapons.SHIELD_FULL)
			log[1] += minf(take, room)
	beam_left[i] -= 1
	_beam_next[i] = server.tick + Weapons.BEAM_PULSE_TICKS
	if beam_left[i] == 0:
		var what := ""
		if log[0] <= 0.0:
			what = "у пиратов нет щита, тянуть нечего." if not server.arena.on() else "щит пиратов опущен или вне досягаемости, тянуть нечего."
		elif server.arena.on():
			what = "нагрел щит пиратов на %d, наш корабль остыл на %d." % [roundi(log[0]), roundi(log[1])]
		else:
			what = "вытянул из щита пиратов %d, нашему щиту %s." % [roundi(log[0]),
				("+%d" % roundi(log[1])) if log[1] > 0.0 else "ничего (генератор не работает или щит полон)"]
		server.chat.say_bridge("Орудие %d (сифон): %s%s" % [i + 1, what, _enemy_state()])


func _enemy_state() -> String:
	if enemy_hull <= 0:
		return ""
	var s := " Корпус пиратов: %d из %d." % [enemy_hull, hull_full()]
	if systems.size() > Net.ESYS_SHIELDS and systems_full[Net.ESYS_SHIELDS] > 0:
		s += " Их щит: %d." % roundi(enemy_shield)
	return s


static func _unique(words: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for w in words:
		if not out.has(w):
			out.append(w)
	return out


func _shot_kind(w: int) -> int:
	match w:
		Weapons.PHOENIX:
			return Net.SHOT_PHOENIX
		Weapons.STORM:
			return Net.SHOT_STORM
		Weapons.DEVASTATOR:
			return Net.SHOT_HEAVY_ROCKET
		Weapons.REAPER:
			return Net.SHOT_REAPER
		Weapons.RAILGUN:
			return Net.SHOT_RAIL
		Weapons.HAMMER:
			return Net.SHOT_HAMMER
		Weapons.NOVA:
			return Net.SHOT_NOVA
		Weapons.GUARD:
			return Net.SHOT_FLAK
	match Weapons.klass(w):
		Weapons.CLASS_ION:
			return Net.SHOT_ION
		Weapons.CLASS_ROCKET:
			return Net.SHOT_ROCKET
		Weapons.CLASS_BLASTER:
			return Net.SHOT_PLASMA
		Weapons.CLASS_BEAM:
			return Net.SHOT_BEAM
		Weapons.CLASS_NEURAL:
			return Net.SHOT_NEURAL
		Weapons.CLASS_KINETIC:
			return Net.SHOT_SHRAPNEL if w == Weapons.SHRAPNEL else Net.SHOT_SHELL
		Weapons.CLASS_BOMB:
			return Net.SHOT_BOMB
	return Net.SHOT_CANNON


func _meets_shield(w: int, hardened: bool) -> bool:
	## Does this shot have to get through the shield at all? (v58) Kinetic shells
	## never meet it that way (it softens them instead), and the railgun and the
	## flagship's gun pass it.
	if Weapons.passes_shield(w) or Weapons.klass(w) == Weapons.CLASS_KINETIC:
		return false
	match Weapons.klass(w):
		Weapons.CLASS_ROCKET:
			return hardened
		Weapons.CLASS_BLASTER:
			return _rng.randf() >= Weapons.BLASTER_SLIP
	return true


func _room_word(room: int) -> String:
	## What a hit in that room is told as: the system there, or an empty room.
	var system := system_in(room)
	return Net.ESYS_NAMES[system].to_lower() if system >= 0 else "пустой отсек"


func _land_on_enemy(w: int, system: int, room: int = -1, fx: int = Weapons.FX_NONE) -> String:
	## A shot of ours that found the enemy, in that room (with that system in
	## it, or -1: an empty room). "" = its shield stopped it; otherwise it got
	## through: "+" when there is nothing to tell, else what came of it. A shot
	## that gets through shows us what the room holds.
	if room < 0:
		room = room_of_system(system)
	var pierce := Weapons.FX_PIERCE_BY if fx == Weapons.FX_PIERCE else 0.0
	if _meets_shield(w, false) and _enemy_shield_up() and _rng.randf() >= Weapons.through_chance(enemy_shield - pierce):
		enemy_shield = maxf(enemy_shield - Weapons.shield_damage(w), 0.0)
		return ""
	return _land_through(w, system, room, fx)


func _land_through(w: int, system: int, room: int, fx: int = Weapons.FX_NONE, soft: bool = false) -> String:
	## A shot of ours past the shield, in that room: what came of it ("+" = nothing to tell).
	## (v58) `soft`: a kinetic shell that went through the shield, KINETIC_SHIELD damage the less.
	## The railgun and the flagship's gun go on through into another room; a tier 3
	## gun's effect (fx) adds what it does.
	if room < 0:
		room = room_of_system(system)
	reveal(room)
	var info := Weapons.info(w)
	var said := ""
	if info.has("disable"):
		# ion and EMP: the system there stops for a while; no damage
		if system >= 0 and system < systems_out.size():
			systems_out[system] = maxi(systems_out[system], server.tick + roundi(float(info["disable"]) * Net.TICK_HZ))
			if system == Net.ESYS_SHIELDS and systems_full[system] > 0:
				said = "Щит пиратов выключен на %d с." % int(info["disable"])
			else:
				said = "%s пиратов выключено на %d с." % [Net.ESYS_NAMES[system], int(info["disable"])]
		var extra := _fx_on_enemy(fx, system, room)
		said = _join(said, extra)
		return "+" if said == "" else said
	var damage: int = info["damage"] if _units < 0 else _units
	if soft:
		damage = maxi(damage - Weapons.KINETIC_SHIELD, 0)
		enemy_shield = maxf(enemy_shield - Weapons.KINETIC_WEAR, 0.0)
	enemy_hull -= damage
	if Weapons.hole_chance(w) >= 1.0 or _rng.randf() < Weapons.hole_chance(w) or fx == Weapons.FX_HOLE:
		_hole_near(room)
	said = _wear_room(system, room, damage, Weapons.crew_wound(w) if Weapons.crew_wound(w) > 0.0 else -1.0)
	for k in Weapons.pierce(w):
		# (v58) it goes on through: the system of another room takes the blow too (not the hull again)
		var others: Array = range(room_sys.size()).filter(func(r: int) -> bool: return r != room)
		if others.is_empty():
			break
		var past: int = others[_rng.randi_range(0, others.size() - 1)]
		reveal(past)
		var through := _wear_room(system_in(past), past, damage)
		said = _join(said, "Навылет: %s%s" % [_room_word(past), "." if through == "" else ". " + through])
	said = _join(said, _fx_on_enemy(fx, system, room))
	return "+" if said == "" else said


static func _join(a: String, b: String) -> String:
	return b if a == "" else (a if b == "" else a + " " + b)


func _fx_on_enemy(fx: int, system: int, room: int) -> String:
	## (v58) What a tier 3 gun's effect adds to a hit of ours on the pirate ship.
	match fx:
		Weapons.FX_HOLE:
			_hole_near(room)
		Weapons.FX_STUN:
			var hurt := crew_hit(room)
			return ("Оглушающий удар: " + hurt) if hurt != "" else ""
		Weapons.FX_KNOCK:
			if system >= 0 and system < systems_out.size() and systems_full[system] > 0:
				systems_out[system] = maxi(systems_out[system], server.tick + roundi(Weapons.FX_KNOCK_SECONDS * Net.TICK_HZ))
				return "Сбой: %s пиратов на %d с." % [Net.ESYS_NAMES[system].to_lower(), int(Weapons.FX_KNOCK_SECONDS)]
	return ""


func _wear_room(system: int, room: int, damage: int, wound: float = -1.0) -> String:
	## A blow of `damage` in that room: whoever is in it may be hurt (each one
	## `wound` of the time; -1: the plain chance, 0: nobody), and the system there worn.
	var hurt := crew_hit(room, wound) if system != Net.ESYS_CREW and damage > 0 and wound != 0.0 else ""
	if damage > 0:
		hurt = _join(_cargo_hit(room), hurt)     # (v68) the cargo pod's room
	if system < 0 or system >= systems.size() or systems[system] == 0 or damage <= 0:
		return hurt
	var was: int = systems[system]
	systems[system] = maxi(was - damage, 0)
	if system == Net.ESYS_CREW and _wing():
		return "Пираты в кубрике ранены."     # (v86) the wingman's crew is not seen
	if system == Net.ESYS_CREW:
		var left := boarders_left()
		if left < server.derelict._pirates_party:
			server.derelict._pirates_party = left
			server.enemy_crew.keep(left, room)
			return ("Убит пират из экипажа, осталось %d." if raid else "Убит абордажник, осталось %d.") % left
		return "Пираты в кубрике ранены." if raid else "Абордажники ранены."
	var said := hurt
	if systems[system] == 0:
		if system == Net.ESYS_SHIELDS:
			enemy_shield = 0.0
		var what := "Выведено из строя: %s. %s" % [Net.ESYS_NAMES[system].to_lower(), DOWN_TEXT[system]]
		if fleeing() and (system == Net.ESYS_ENGINE or system == Net.ESYS_JUMP):
			what += " Прыжок сорван, пока не починят."
		said = what if said == "" else what + " " + said
	elif system == Net.ESYS_JUMP and fleeing():
		said = "Гипердвигатель повреждён: прыжок заряжается медленнее, ещё %d с." % jump_seconds_left() + ("" if said == "" else " " + said)
	return said


func _hole_near(room: int) -> void:
	## A hole in the enemy's hull, next to the room that was hit where it can be (where it shows otherwise).
	if _wing():
		return                               # (v86) the wingman is not in the grid
	var hull: PackedInt32Array = server.derelict._hull_cells()
	if hull.is_empty():
		return
	var near := PackedInt32Array()
	var o = server.map.other
	if o != null and room >= 0 and room < o.rooms.size():
		var w: int = server.map.width
		for c: int in hull:
			for local: int in o.rooms[room]:
				var z: int = server.derelict._cell(server.map.other_at, local)
				if absi(z % w - c % w) <= 1 and absi(z / w - c / w) <= 1:
					near.append(c)
					break
	var from := near if not near.is_empty() else hull
	var c: int = from[_rng.randi_range(0, from.size() - 1)]
	if server.air.set_hole(c, true):
		server.replication.hull_record(c, 1)


func mend_order() -> Array:
	## What its crew mends first (its quarters are not mended): while it runs, its
	## jump drive and engine; else its guns. A system knocked out comes before one only worn.
	var order: Array = [Net.ESYS_JUMP, Net.ESYS_ENGINE, Net.ESYS_WEAPONS, Net.ESYS_SHIELDS, Net.ESYS_HELM, Net.ESYS_TELEPORT, Net.ESYS_DRONES] if fleeing() \
		else [Net.ESYS_DRONES, Net.ESYS_WEAPONS, Net.ESYS_TELEPORT, Net.ESYS_SHIELDS, Net.ESYS_HELM, Net.ESYS_ENGINE, Net.ESYS_JUMP]
	var out: Array = []
	for k: int in order:
		if k < systems.size() and systems[k] == 0 and systems_full[k] > 0:
			out.append(k)
	for k: int in order:
		if not out.has(k):
			out.append(k)
	return out


func _mend_tick() -> void:
	## The pirates mend a worn system a point every ENEMY_REPAIR_SECONDS while one
	## of them is in its room (twice as fast with two).
	for k: int in mend_order():
		if k >= systems.size() or systems[k] >= systems_full[k]:
			_mend_part[k] = 0.0
			continue
		var n: float = float(server.enemy_crew.menders(k)) if server.enemy_crew.o != null and not _wing() else 1.0
		if crewless:
			n = DRONE_REPAIR if not down(Net.ESYS_DRONES) else 0.0   # (v62) its repair drones, while its core works
		if n <= 0.0:
			continue
		_mend_part[k] += n / (ENEMY_REPAIR_SECONDS * Net.TICK_HZ)
		if _mend_part[k] >= 0.9999:
			_mend_part[k] = 0.0
			systems[k] += 1
			if systems[k] == 1:
				server.chat.say_bridge(("Ремонтные дроны починили: %s снова работают." if crewless else "Пираты починили: %s снова работают.") % Net.ESYS_NAMES[k].to_lower())


func crew_hit(room: int, wound: float = -1.0, kill_one: bool = false) -> String:
	## A blow that got through into that room finds whoever is in it. What came of it ("" = nobody there was hurt).
	## (v62) `wound`: the chance each one is wounded (-1: the plain one); `kill_one`: one of them dies («Термит»).
	if room < 0 or server.enemy_crew.o == null or _wing():
		return ""                            # ((v86) the wingman's crew is not seen)
	var r: Array = server.enemy_crew.hit_room(room, wound, kill_one)
	var killed: int = r[0]
	var wounded: int = r[1]
	if killed > 0 and systems.size() > Net.ESYS_CREW:
		systems[Net.ESYS_CREW] = maxi(systems[Net.ESYS_CREW] - killed * HITS_PER_BOARDER, 0)
		server.derelict._pirates_party = boarders_left()
		server.enemy_crew.keep(boarders_left())
	var parts := PackedStringArray()
	var who := "робот-охранник" if crewless else "пират"
	if killed > 0:
		parts.append(("Убит %s в отсеке, осталось %d." % [who, boarders_left()]) if killed == 1 else
			("Убиты пираты в отсеке (%d), осталось %d." % [killed, boarders_left()]))
	if wounded > 0:
		parts.append(("Ранен %s." % who) if wounded == 1 else "Ранены пираты (%d)." % wounded)
	return " ".join(parts)


# ---------------------------------------------------------------- (v62) bombs, fragments, the second phase

const AREA_SPREAD := 0.5             # a fragment of «Шрапнель» lands in a room beside the one aimed at this often


func _beside(room: int) -> int:
	## A room of its drawing next to that one (through one wall or door), by lot; that room if none.
	var o = server.map.other
	if o == null or room < 0 or room >= o.rooms.size():
		return room
	var mine: PackedInt32Array = o.rooms[room]
	var near: Array = []
	for r in o.rooms.size():
		if r == room or r >= room_sys.size():
			continue
		var found := false
		for a: int in o.rooms[r]:
			for b: int in mine:
				if absi(a % o.width - b % o.width) + absi(a / o.width - b / o.width) <= 2:
					found = true
					break
			if found:
				break
		if found:
			near.append(r)
	return near[_rng.randi_range(0, near.size() - 1)] if not near.is_empty() else room


func _our_bomb(i: int, w: int, fx: int) -> void:
	## (v62) One of our bomb launchers: the bomb is teleported straight into the
	## room aimed at. No shield, point defence or dodge stops it; now and then the
	## teleport loses it (its "hit").
	var map = server.map
	var cell: int = map.guns[i]
	server.combat.jolt(Net.JOLT_FIRE, w, Vector2(cell % map.width, cell / map.width))
	var room := _aimed_room()
	if room < 0:
		room = _any_room()
	var hit := _rng.randf() < clampf(float(Weapons.info(w)["hit"]) + _aim_bonus, 0.05, Weapons.BEST_HIT)
	var spot := _draw_ours(cell, w, Net.LANDED if hit else Net.MISSED, room, 0)
	_after(Weapons.flight_ticks(w), _our_bomb_lands.bind(i, w, fx, room, hit, spot, server.fleet.on))


func _our_bomb_lands(i: int, w: int, fx: int, room: int, hit: bool, spot: Vector2, from_ship: int = 0) -> void:
	if not _finds(from_ship):
		return
	var gun := "Орудие %d (%s)" % [i + 1, Weapons.lower_name(w, fx)]
	if not hit or room < 0:
		server.chat.say_bridge("%s: телепорт сбился, бомба потеряна.%s" % [gun, _enemy_state()])
		return
	server.combat.jolt(Net.JOLT_THEIR_HIT, Net.SHOT_BOMB, spot)
	reveal(room)
	var info := Weapons.info(w)
	var system := system_in(room)
	var said := ""
	if info.has("disable") and system >= 0 and systems_full[system] > 0:
		systems_out[system] = maxi(systems_out[system], server.tick + roundi(float(info["disable"]) * Net.TICK_HZ))
		said = "%s пиратов выключено на %d с." % [Net.ESYS_NAMES[system], int(info["disable"])]
	var hull := int(info.get("hull", 0))
	if hull > 0:
		enemy_hull -= hull
		_hole_near(room)
		said = _join(said, "Обшивка прожжена.")
	var damage: int = info["damage"]
	if damage > 0 and system >= 0:
		said = _join(said, _wear_room(system, room, damage, 0.0))
	if system != Net.ESYS_CREW or damage == 0:
		var wound := Weapons.crew_wound(w) if Weapons.crew_wound(w) > 0.0 else (1.0 if info.has("stun") else 0.0)
		if wound > 0.0:
			said = _join(said, crew_hit(room, wound, bool(info.get("kill", false))))
	said = _join(said, _fx_on_enemy(fx, system, room))
	server.chat.say_bridge("%s: взрыв в отсеке (%s).%s%s" % [gun, _room_word(room), "" if said == "" else " " + said, _enemy_state()])
	_settle()


func _enemy_bomb(w: int, fx: int) -> void:
	## (v62) One of its bomb launchers: the bomb comes through our shield and point
	## defence into a room of ours, where it means to hit (a device, or the crew).
	var map = server.map
	reveal(room_of_system(Net.ESYS_WEAPONS), "Вспышки выстрелов выдали отсек пиратов")
	var chance: float = float(Weapons.info(w)["hit"]) if enemy_hit_chance < 0.0 else enemy_hit_chance
	if down(Net.ESYS_HELM):
		chance *= BLIND_ENEMY_HIT
	var target := _enemy_target()
	var cell := target if target >= 0 else _crew_cell()
	if cell < 0:
		var cells: PackedInt32Array = server.assault.landing_cells()
		cell = cells[_rng.randi_range(0, cells.size() - 1)] if not cells.is_empty() else -1
	var hit := cell >= 0 and _rng.randf() < chance
	var spot := _draw_theirs(w, cell, Net.LANDED if hit else Net.MISSED, 0)
	_after(Weapons.flight_ticks(w), _their_bomb_lands.bind(w, fx, target, cell, hit, spot))


func _their_bomb_lands(w: int, fx: int, target: int, cell: int, hit: bool, spot: Vector2) -> void:
	var map = server.map
	var ship = server.ship
	var gun := Weapons.lower_name(w, fx)
	if not hit:
		server.chat.say_bridge("Пираты стреляют (%s): телепорт сбился, бомба не дошла." % gun)
		return
	server.combat.jolt(Net.JOLT_HEAVY, Net.SHOT_BOMB, spot)
	var info := Weapons.info(w)
	var said := PackedStringArray()
	if info.has("disable"):
		if target >= 0:
			ship.jammed[target] = maxi(int(ship.jammed.get(target, 0)), server.tick + roundi(float(info["disable"]) * Net.TICK_HZ))
			said.append("%s выключено на %d с." % [_cap(map.device_name(target)), int(info["disable"])])
	elif target >= 0 and int(info["damage"]) > 0:
		ship.broken[target] = true
		server.to_all(ship.devices_packet())
		if map.engine.has(target):
			server.systems.power_changed()
			said.append("Двигатель выбит: корабль обесточен! Почините его на нижней палубе.")
		else:
			said.append("Не работает: %s." % map.device_name(target))
	var hull := int(info.get("hull", 0))
	if hull > 0:
		var by := _hull_nearest(cell)
		if by >= 0 and not (server.outfit.no_hole() > 0.0 and _rng.randf() < server.outfit.no_hole()):
			server.systems.breach(by)
		server.crew.hull_hit(_armoured(Net.HULL_PER_HOLE * hull))
		said.append("Обшивка прожжена изнутри.")
	var wound := Weapons.crew_wound(w)
	var stun := float(info.get("stun", 0.0))
	var hurt := _bomb_room(cell, BOMB_WOUND if wound > 0.0 else 0.0, stun, bool(info.get("kill", false)))
	if hurt != "":
		said.append(hurt)
	server.chat.say("Пираты стреляют (%s): бомба взорвалась у нас на борту (%s)! %s" % [gun,
		map.deck_names[map.deck_of(cell / map.width)].to_lower(), " ".join(said)])


func _bomb_room(cell: int, wound: float, stun: float, kill_one: bool) -> String:
	## (v62) A bomb bursts at that cell: everybody of ours in its room is wounded
	## (or struck senseless, `stun`); «Термит» burns one of them.
	var map = server.map
	if cell < 0 or (wound <= 0.0 and stun <= 0.0):
		return ""
	var room: int = map.room_of[cell]
	var names := PackedStringArray()
	var burnt := ""
	for p in server.players:
		if p == null or p.pirate or p.corpse or p.cond == Net.COND_DEAD:
			continue
		var at: int = p.st.y * map.width + p.st.x
		if at != cell and (room < 0 or map.room_of[at] != room):
			continue
		if stun > 0.0:
			if p.cond == Net.COND_OK:
				server.chat.sound(Net.SOUND_CRY, p.st.x, p.st.y, p.slot)
			p.health = maxf(p.health - stun, minf(p.health, STUN_FLOOR))
		else:
			server.combat.hurt(p, roundi(THERMITE_BURN if kill_one and burnt == "" else wound), null, server.combat.CAUSE_BLAST)
			if kill_one and burnt == "":
				burnt = p.name
		names.append(p.name)
	if names.is_empty():
		return "Отсек был пуст."
	if stun > 0.0:
		return "Ионный взрыв оглушил: %s." % ", ".join(names)
	return "Ранены взрывом: %s.%s" % [", ".join(names), (" %s в огне термита." % burnt) if burnt != "" else ""]


func _phase_two() -> void:
	## (v62, the author's K21) The flagship at a third of its hull: it mends all
	## its systems at once, its shield comes back full, and it fights harder: the
	## battleship's guns charge faster and it sends assault drones, the carrier
	## teleports more troops more often (Flagship).
	phase2 = true
	for k in systems.size():
		if k != Net.ESYS_CREW:
			systems[k] = systems_full[k]
		systems_out[k] = 0
	enemy_shield = Weapons.SHIELD_FULL if systems_full[Net.ESYS_SHIELDS] > 0 else 0.0
	if boss == 2:
		server.flagship.phase_two()
	server.chat.say("Флагман горит, но не сдаётся: вторая фаза! Его системы починены разом, щит снова полон, %s" % [
		"орудия заряжаются быстрее, и он выпускает штурмовых дронов." if boss == 1 else "и телепорт шлёт десант чаще и больше."])


func _offers_ransom() -> void:
	_offered = true
	ransom = maxi(roundi(reward * RANSOM_SHARE), 5)
	ransom_until = server.tick + roundi(RANSOM_SECONDS * Net.TICK_HZ)
	server.chat.say("Пираты сдаются и предлагают выкуп: %d кредитов и канистру топлива, если их отпустят. Пока ждут ответа (%d с), они не стреляют. Принять можно на пульте орудий; наш выстрел будет отказом." % [
		ransom, int(RANSOM_SECONDS)])


func _ransom_ends(why: String) -> void:
	## The offer is off: it runs.
	ransom = 0
	server.chat.say(why)
	_starts_to_flee()


func ransom_taken(p) -> void:
	if ransom <= 0 or not engaged():
		return
	if server.stations.ours_aboard:
		server.chat.tell(p, "Наши люди на борту пиратского корабля: пока они там, отпустить его нельзя.")
		return
	var ship = server.ship
	server.story.pirates_beaten()           # (v63) paying us off counts as beaten
	ship.credits += ransom
	ship.store[Net.ITEM_FUEL] = int(ship.store.get(Net.ITEM_FUEL, 0)) + 1
	var extra := ""
	if _rng.randf() < RANSOM_PRISONER and server.reserve < Net.RESERVE_MAX:
		server.reserve += 1
		extra = " Один из пиратов просится к нам: он теперь в резерве экипажа (%d)." % server.reserve
	server.chat.say("%s принимает выкуп: +%d кредитов и канистра топлива. Пиратский корабль уходит.%s%s" % [p.name, ransom, extra, _goal_paid()])
	ransom = 0
	enemy_hull = 0
	beam_left.fill(0)
	server.supplies.tell_store()
	server.derelict.pirates_escaped()


func swap_done(paid: int) -> void:
	## (v70, the author's J5) We gave their man back (for `paid` credits): their ship leaves, no parting volley.
	if not engaged():
		return
	if paid > 0:
		server.ship.credits = mini(server.ship.credits + paid, 65535)
	ransom = 0
	enemy_hull = 0
	beam_left.fill(0)
	server.supplies.tell_store()
	server.derelict.pirates_escaped()


func _wrecked() -> void:
	if _wing():
		# (v86) the wingman: it breaks up out in the dark, too far to search; its reward is paid
		server.ships_beaten += 1
		_over = true
		enemy_hull = 0
		reward = roundi(reward * server.outfit.salvage_share())
		server.ship.credits += reward
		server.chat.say("%s разбит! За него начислено %d кредитов. Его обломки унесло во тьму.%s" % [server.wing.name, reward,
			"" if not server.wing.engaged(0) else " Остался корабль у шлюза."])
		server.supplies.tell_store()
		return
	server.story.pirates_beaten()           # (v63) a bounty's or the courier's
	server.ships_beaten += 1                # (v75) for the run's summary
	_over = true
	var captured: bool = server.stations.ours_aboard and systems.size() > Net.ESYS_CREW and systems[Net.ESYS_CREW] == 0 \
		or (crewless and server.stations.ours_aboard and enemy_hull > 0 and systems.size() > Net.ESYS_DRONES and systems[Net.ESYS_DRONES] == 0)
	enemy_hull = 0
	beam_left.fill(0)
	var salvage: float = server.outfit.salvage_share()          # (v62) the salvage arm
	var parts: int = server.outfit.salvage_parts()
	if parts > 0:
		server.ship.store[Net.ITEM_PART] = int(server.ship.store.get(Net.ITEM_PART, 0)) + parts
	reward = roundi(reward * salvage)
	if captured:
		# (v55, the author) taken by boarding, whole: it is salvaged for more than a wreck gives
		var paid := roundi(reward * CAPTURE_SHARE)
		server.ship.credits += paid
		server.ship.store[Net.ITEM_PART] = int(server.ship.store.get(Net.ITEM_PART, 0)) + CAPTURE_PARTS
		server.ship.store[Net.ITEM_BOARD] = int(server.ship.store.get(Net.ITEM_BOARD, 0)) + 1     # (v71) and a circuit board
		server.ship.store[Net.ITEM_FUEL] = int(server.ship.store.get(Net.ITEM_FUEL, 0)) + 1
		var gun := _loot_gun(true) if boss == 0 else ""
		if boss > 0:
			server.derelict.becomes_wreck()
			_drop_nova()
			server.supplies.tell_store()
			server.flagship.won(captured)
			return
		server.derelict.becomes_wreck()
		server.salvage.captured()            # (v67) more scrap to cut off a ship taken whole
		if crewless:
			server.chat.say("Ядро дрон-корабля разбито: машина мертва, корабль наш! Он разобран на ценное: %d кредитов, %d запчасти и канистра топлива в трюм. Его можно обыскать.%s" % [paid, CAPTURE_PARTS + parts, gun])
		else:
			server.chat.say("Пиратский корабль захвачен: его экипаж перебит! Корабль разобран на ценное: %d кредитов, %d запчасти и канистра топлива в трюм. Его можно обыскать.%s%s" % [paid, CAPTURE_PARTS + parts, gun, _goal_paid()])
		server.supplies.tell_store()
		return
	if boss > 0:
		# (v57) the flagship at the goal point: the game is won; its wreck stays to be searched
		server.ship.credits += reward
		server.derelict.becomes_wreck()
		_drop_nova()
		server.supplies.tell_store()
		server.flagship.won(captured)
		return
	server.ship.credits += reward
	# it stays alongside, dead: what it holds is there for the taking. (v72, the author's note: "when we
	# kill the boarders' ship it must die, not run, and stay where we can dock and loot it") A boarding
	# ship wrecked before it docked used to fly off and leave a fuel can in our hold; now it is a wreck
	# like a raider's, and the can lies aboard it.
	var boarder: bool = not raid and not server.stations.ours_aboard
	server.derelict.becomes_wreck()
	if boarder:
		for i in Net.WRECK_FUEL:
			server.derelict.drop_thing(Net.ITEM_FUEL)
	var gun := _loot_gun(false)
	server.chat.say("Пиратский корабль разбит%s! За него начислено %d кредитов. Его обломки остались у шлюза: туда можно добраться через открытый космос или пристыковаться с пульта управления и обыскать.%s%s%s" % [
		", не успев пристыковаться" if boarder else "", reward, server.derelict.survivors_note(), gun, _goal_paid()])
	server.supplies.tell_store()


# ---------------------------------------------------------------- (v58) guns as loot

const WRECK_GUN := 0.3               # the share of wrecks that leave one of their guns aboard (the author: rare, a reward)
const LOOT_HIGHER := 0.1             # a looted gun is one tier higher this often (the next gun of its line)
const WRECK_GEAR := 0.5              # (v59) of those, the share that leave a crate of gear instead of a gun
const LOOT_DAMAGED := 0.4            # and damaged this often: mended at the workbench before it can be mounted (v67: wrecks leave no guns)
const CAPTURE_GUN_PARTS := 2         # (v67) gun parts from a ship taken by boarding
var wreck_gun_chance := WRECK_GUN    # (tests set it)
var wreck_gear_chance := WRECK_GEAR  # (tests set it)


func _loot_gun(captured: bool) -> String:
	## What survives of its guns. (v67, the author's B2: "you can salvage part of the ship for more
	## resources, but no full guns; guns come to you as a rare event") A wreck no longer leaves a whole
	## gun: one of its guns is broken down into parts of its kind, into the hold (CAPTURE_GUN_PARTS when
	## we took it by boarding, always; one part from a wreck, at WRECK_GUN), and a wreck may leave a crate
	## of ship gear lying aboard instead (to be carried home through the airlock). What to tell ("" = none).
	var guns: Array = Array(enemy_weapons).filter(func(w: int) -> bool: return Weapons.OURS.has(w))
	if not captured and _rng.randf() >= wreck_gun_chance:
		return ""
	if not captured and (guns.is_empty() or _rng.randf() < wreck_gear_chance):
		# (v59, the author: the wreck's chance holds for gear too) a crate of ship gear
		var far: int = server.sectors.far_from_start(server.ship.sector)
		var crate: int = server.outfit.loot(far, _rng, _rng.randf() < LOOT_HIGHER)
		if not server.derelict.drop_thing(crate):
			return ""
		return " Среди обломков уцелел ящик с корабельным модулем: %s. Его можно забрать и отнести в шкаф снабжения." % Items.name_of(crate).to_lower()
	if guns.is_empty():
		return ""
	var w: int = guns[_rng.randi_range(0, guns.size() - 1)]
	var n := CAPTURE_GUN_PARTS if captured else 1
	var item := Items.gun_parts(Weapons.kind(w))
	server.ship.store[item] = int(server.ship.store.get(item, 0)) + n
	return " Орудие «%s» разобрано на детали: %s ×%d в трюм." % [Weapons.name_of(w), Items.name_of(item).to_lower(), n]


func _drop_nova() -> void:
	## (v57, v58 the author: "like a BFG") The flagship leaves its own gun in its wreck: there is no other.
	var item := Weapons.item_of(Weapons.NOVA, Weapons.roll_fx(Weapons.NOVA, _rng))
	if server.derelict.drop_thing(item):
		server.chat.say("В обломках флагмана лежит его орудие, «Сверхновая»: второго такого нет. Заберите его и отнесите в шкаф снабжения.")


# ---------------------------------------------------------------- the enemy's guns

const PARTING_READY := 0.5           # (v67) its guns charged this far fire a parting volley when we jump away


func parting_volley() -> void:
	## (v67, the author's O3) Our ship jumps out of a fight: escaping is still always
	## possible, but every gun of the pirates' charged PARTING_READY or more fires once
	## as we go, landing at once, and the next hunter comes sooner (Road.escaped).
	if not engaged():
		return
	server.road.escaped()
	if down(Net.ESYS_WEAPONS) or ransom > 0:
		return
	var was := flies
	flies = false
	var fired := 0
	for k in enemy_weapons.size():
		if enemy_charge[k] >= PARTING_READY:
			enemy_charge[k] = 0.0
			fired += 1
			_enemy_fires(enemy_weapons[k], enemy_fx[k] if k < enemy_fx.size() else Weapons.FX_NONE)
	flies = was
	if fired > 0:
		server.chat.say("Уходя прыжком, корабль попал под прощальный залп пиратов (%d орудий)." % fired)


func _enemy_fires(w: int, fx: int = Weapons.FX_NONE, start: int = 0, k: int = 0) -> void:
	## A shot (or burst) of one of the pirate ship's guns. It goes for our guns
	## while one of them works (and all the more while it runs, to cover its
	## escape); otherwise it holes the hull, as near the crew as it can, or now
	## and then hits a bridge console or the shield generator. Our shield stops
	## what it can; ion and EMP that get through put a gun or the shield out for
	## a few seconds. (v58) Our point defence may shoot a rocket down; our shield
	## takes a point off a kinetic shell; a tier 3 gun's effect adds its own.
	if Weapons.bomb(w):
		_enemy_bomb(w, fx)
		return
	if flies and server.arena.on():
		_enemy_fires_arena(w, fx, start, k)
		return
	var map = server.map
	var ship = server.ship
	reveal(room_of_system(Net.ESYS_WEAPONS), "Вспышки выстрелов выдали отсек пиратов")
	if start == 0 and server.stations.our_dodge() > 0.0:
		server.stations.at_post(Net.POST_HELM).train(Net.SKILL_PILOT)   # (v60) piloting is learnt under fire
	var shots: int = Weapons.info(w)["shots"]
	var chance: float = float(Weapons.info(w)["hit"]) if enemy_hit_chance < 0.0 else enemy_hit_chance
	if enemy_hit_chance < 0.0:
		# (v55) our pilot's dodge and the battle position
		chance = clampf(chance + ENEMY_EDGE + server.stations.their_hit_bonus() - server.stations.our_dodge()
			- (server.stations.EVADE_DODGE if server.stations.evading() else 0.0), 0.05, 0.95)   # (v68) the pilot's evade
	if down(Net.ESYS_HELM):
		chance *= BLIND_ENEMY_HIT
	# (v56) every shot is rolled now and lands when its flight is over
	var log := {"w": w, "fx": fx, "left": shots, "misses": 0, "stopped": 0, "down": 0, "ricochet": 0, "said": PackedStringArray()}
	var shield: float = ship.shield
	var pierce := Weapons.FX_PIERCE_BY if fx == Weapons.FX_PIERCE else 0.0
	var kinetic := Weapons.klass(w) == Weapons.CLASS_KINETIC
	for s in shots:
		var delay := start + s * Weapons.BURST_GAP_TICKS
		if Weapons.guard_chance(w) > 0.0 and guard_ready():
			# (v58) our point defence fires at it, hit or miss (v60: at slow shells too, less surely)
			guard_charge = 0.0
			if map.guns.size() > 0:              # (heard by the guns: it has no place of its own)
				server.combat.jolt(Net.JOLT_FIRE, Weapons.GUARD, Vector2(map.guns[0] % map.width, map.guns[0] / map.width))
			if _rng.randf() < Weapons.guard_chance(w):
				var by: int = _hull_near_crew()
				var spot := _draw_theirs(w, by, Net.SHOT_DOWN, delay)
				_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, Net.SHOT_DOWN, -1, -1, spot))
				continue
		if _rng.randf() >= chance:
			var by: int = map.hull[_fx.randi_range(0, map.hull.size() - 1)] if map.hull.size() > 0 else -1
			_draw_theirs(w, by, Net.MISSED, delay)
			_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, Net.MISSED, -1, -1, Vector2.ZERO))
			continue
		var target := _enemy_target()
		if Weapons.klass(w) == Weapons.CLASS_NEURAL:
			target = -1                      # (v57) it is aimed at people, not at a machine
		if kinetic and ship.armour > 0.0 and _rng.randf() < ship.armour:
			# (v59) our armour plating turns the shell aside: it does nothing
			var spot := _draw_theirs(w, target if target >= 0 else _hull_near_crew(), Net.RICOCHET, delay)
			_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, Net.RICOCHET, -1, -1, spot))
			continue
		var soft := false
		if kinetic and not Weapons.passes_shield(w) and our_shield_up() and shield > 0.0:
			# (v58) a shell through our shield: a point the less (none left: the shield held it)
			shield = maxf(shield - Weapons.KINETIC_WEAR, 0.0)
			soft = true
			if int(Weapons.info(w)["damage"]) <= Weapons.KINETIC_SHIELD:
				var spot := _draw_theirs(w, target if target >= 0 else _hull_near_crew(), 0, delay)
				_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, 0, -1, -1, spot))
				continue
		elif _meets_shield(w, server.outfit.hardened()) and our_shield_up() and _rng.randf() >= Weapons.through_chance(shield - pierce):
			shield = maxf(shield - Weapons.shield_damage(w), 0.0)
			var spot := _draw_theirs(w, target if target >= 0 else _hull_near_crew(), 0, delay)
			_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, 0, -1, -1, spot))
			continue
		var cell := target
		if Weapons.klass(w) == Weapons.CLASS_NEURAL:
			cell = _crew_cell()
			var spot := _draw_theirs(w, _hull_nearest(cell), Net.LANDED, delay)
			_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, Net.LANDED, -1, cell, spot))
			continue
		if Weapons.info(w).has("disable"):
			cell = target if target >= 0 and (map.guns.has(target) or target == shield_cell()) else _jam_choice()
		elif target < 0:
			cell = _hull_near_crew()
		var spot := _draw_theirs(w, cell, Net.LANDED, delay)
		_after(delay + Weapons.flight_ticks(w), _their_shot_lands.bind(log, Net.LANDED, target, cell, spot, soft))
	if fx == Weapons.FX_TWICE and start == 0 and _rng.randf() < Weapons.FX_TWICE_CHANCE:
		_enemy_fires(w, fx, shots * Weapons.BURST_GAP_TICKS + 6)


func _enemy_fires_arena(w: int, fx: int, start: int, k: int) -> void:
	## (v92) Its gun fires in the fight's space: each shot is aimed at what it means to hit (a gun, a
	## console, the shield generator, the hull near our people) and flies; how far off it goes depends
	## on how good the gun and its crew are, and whether it hits depends on where our ship is by then.
	reveal(room_of_system(Net.ESYS_WEAPONS), "Вспышки выстрелов выдали отсек пиратов")
	var shots: int = Weapons.space_shots(w)
	var chance: float = float(Weapons.info(w)["hit"]) if enemy_hit_chance < 0.0 else enemy_hit_chance
	if enemy_hit_chance < 0.0:
		chance = clampf(chance + ENEMY_EDGE + server.stations.their_hit_bonus(), 0.05, 0.95)
		if down(Net.ESYS_HELM):
			chance *= BLIND_ENEMY_HIT
	var log := {"w": w, "fx": fx, "left": shots, "misses": 0, "stopped": 0, "down": 0, "ricochet": 0, "said": PackedStringArray()}
	for s in shots:
		var target := _enemy_target()
		var cell := target
		if Weapons.klass(w) == Weapons.CLASS_NEURAL:
			target = -1
			cell = _crew_cell()
		elif target < 0:
			cell = _hull_near_crew()
		server.arena.fire_theirs(server.wing.on, k, w, cell, 1.0 - chance, start + s * Weapons.BURST_GAP_TICKS,
			{"log": log, "target": target, "cell": cell, "ship": server.fleet.on, "fx": fx})
	if fx == Weapons.FX_TWICE and start == 0 and _rng.randf() < Weapons.FX_TWICE_CHANCE:
		_enemy_fires_arena(w, fx, shots * Weapons.BURST_GAP_TICKS + 6, k)


# ---------------------------------------------------------------- (v92) shots in the fight's space (Arena)

func arena_bubble(p: Dictionary, body_id: int, at: Vector2) -> bool:
	## A shot stopped by the shield's bubble of the ship `body_id` ((v94) Arena decides, and heats that ship): told.
	var meta: Dictionary = p["meta"]
	var w: int = p["w"]
	if int(p["side"]) == 0:
		server.fleet.use(int(meta["ship"]))
		server.wing.use(body_id - server.arena.LEAD)
		var room := _fx_room()
		server.combat.tell_volley(Net.VOLLEY_OURS, _shot_kind(w), 0, room, 0, 1)
		_our_shot_lands(meta["log"], true, room, true, _room_spot(room))
		server.wing.use(0)
		server.fleet.use(0)
		return true
	server.fleet.use(body_id)
	server.wing.use(int(p["foe"]))
	_their_shot_lands(meta["log"], 0, -1, -1, server.arena._grid_spot(server.arena.bodies[body_id], server.arena.bodies[body_id].local(at)))
	server.wing.use(0)
	server.fleet.use(0)
	return true


func arena_hit(p: Dictionary, body_id: int, local: Vector2, cells: PackedInt32Array, at: Vector2) -> int:
	## A shot strikes the hull of the ship `body_id` at that point (`cells`: the drawing's cells there,
	## one per deck). What it does is what a hit did before v92, at the place it struck. Returns how it
	## ended (Net.LANDED, RICOCHET) for the drawing.
	var meta: Dictionary = p["meta"]
	var w: int = p["w"]
	var arena = server.arena
	_units = int(meta.get("units", -1)) if Weapons.meets_armour(w) else -1   # (v94) the hits inside its hull points made
	var how_now := _arena_hit(p, body_id, local, cells, at)
	_units = -1
	return how_now


func _arena_hit(p: Dictionary, body_id: int, local: Vector2, cells: PackedInt32Array, at: Vector2) -> int:
	var meta: Dictionary = p["meta"]
	var w: int = p["w"]
	var arena = server.arena
	if int(p["side"]) == 0:
		server.fleet.use(int(meta["ship"]))
		server.wing.use(body_id - arena.LEAD)
		var lay = server.map.others[arena.bodies[body_id].layout]
		var cell: int = cells[_rng.randi_range(0, cells.size() - 1)] if not cells.is_empty() else -1
		var room := _room_by(lay, cell)
		var how := HOW_PLAIN
		if p.has("armour"):
			how = HOW_RICOCHET if int(p["armour"]) == Net.RICOCHET else HOW_HELD   # (v93) Arena's armour met it
		elif meta.has("soft"):
			how = HOW_SOFT
		var spot := Vector2(-1, -1)
		if not _wing() and cell >= 0 and server.map.other_at != server.map.NO_OTHER:
			var c: int = server.derelict._cell(server.map.other_at, cell)
			spot = Vector2(c % server.map.width + 0.5, c / server.map.width + 0.5)
		var ends := Net.RICOCHET if how == HOW_RICOCHET else (Net.HELD if how == HOW_HELD else Net.LANDED)
		server.combat.tell_volley(Net.VOLLEY_OURS, _shot_kind(w), Net.RICOCHET if how == HOW_HELD else ends, room, 0, 1)
		_our_shot_lands(meta["log"], true, room, false, spot, how)
		server.wing.use(0)
		server.fleet.use(0)
		return ends
	server.fleet.use(body_id)
	server.wing.use(int(p["foe"]))
	var map = server.map
	var b = arena.bodies[body_id]
	var struck: int = cells[_rng.randi_range(0, cells.size() - 1)] if not cells.is_empty() else -1
	var hull := _hull_nearest(struck) if struck >= 0 else _hull_near_crew()
	if hull >= 0 and struck >= 0 and Vector2(hull % map.width, hull / map.width).distance_to(Vector2(struck % map.width, struck / map.width)) > 3.0:
		hull = struck if map.hull.has(struck) else hull
	var spot: Vector2 = arena._grid_spot(b, local)
	if hull >= 0:
		spot = Vector2(hull % map.width + 0.5, hull / map.width + 0.5)
	var target: int = meta["target"]
	if target >= 0 and b.shape.local_of(target).distance_to(local) > arena.HIT_NEAR:
		target = -1                          # it struck elsewhere than it aimed
	var how := Net.LANDED
	var log: Dictionary = meta["log"]
	if Weapons.klass(w) == Weapons.CLASS_NEURAL:
		var person: int = meta["cell"]
		if person < 0 or b.shape.local_of(person).distance_to(local) > arena.HIT_NEAR * 2.0:
			person = _crew_near(struck)
		_their_shot_lands(log, Net.LANDED, -1, person, spot)
	elif p.has("armour"):
		how = int(p["armour"])               # (v93) our armour held it, or it glanced off (Arena)
		_their_shot_lands(log, how, -1, -1, spot)
	else:
		var cell := hull
		if Weapons.info(w).has("disable"):
			cell = target if target >= 0 and (map.guns.has(target) or target == shield_cell()) else _jam_choice()
		elif target >= 0:
			cell = target
		if cell < 0:
			_their_shot_lands(log, Net.MISSED, -1, -1, spot)
		else:
			_their_shot_lands(log, Net.LANDED, target, cell, spot, meta.has("soft"))
	server.wing.use(0)
	server.fleet.use(0)
	return how


func arena_miss(p: Dictionary, at: Vector2) -> void:
	## A shot flew its whole way and found nothing (or its ship left the fight first).
	var meta: Dictionary = p["meta"]
	if int(p["side"]) == 0:
		server.fleet.use(int(meta.get("ship", 0)))
		server.wing.use(int(meta.get("foe", 0)))
		_our_shot_lands(meta["log"], false, -1, false, Vector2(-1, -1))
	else:
		server.fleet.use(int(meta.get("ship", 0)))
		server.wing.use(int(p.get("foe", 0)))
		_their_shot_lands(meta["log"], Net.MISSED, -1, -1, Vector2.ZERO)
	server.wing.use(0)
	server.fleet.use(0)


func arena_guard(p: Dictionary, body_id: int, at: Vector2) -> bool:
	## A rocket (or a slow shell) comes within reach of the point defence of the ship `body_id`:
	## true if it is shot down.
	var meta: Dictionary = p["meta"]
	var w: int = p["w"]
	var down_now := false
	if int(p["side"]) == 1:
		server.fleet.use(body_id)
		server.wing.use(int(p["foe"]))
		if guard_ready():
			guard_charge = 0.0
			if server.map.guns.size() > 0:
				server.combat.jolt(Net.JOLT_FIRE, Weapons.GUARD, Vector2(server.map.guns[0] % server.map.width, server.map.guns[0] / server.map.width))
			if _rng.randf() < Weapons.guard_chance(w):
				down_now = true
				_their_shot_lands(meta["log"], Net.SHOT_DOWN, -1, -1, server.arena._grid_spot(server.arena.bodies[body_id], Vector2.ZERO))
	else:
		server.fleet.use(int(meta["ship"]))
		server.wing.use(body_id - server.arena.LEAD)
		if enemy_guard and not down(Net.ESYS_WEAPONS) and server.tick >= _enemy_guard_ready:
			_enemy_guard_ready = server.tick + Weapons.charge_ticks(Weapons.GUARD)
			if _rng.randf() < Weapons.guard_chance(w):
				down_now = true
				_our_shot_lands(meta["log"], false, -1, false, _room_spot(_fx_room()), HOW_DOWN)
	server.wing.use(0)
	server.fleet.use(0)
	return down_now


static func _room_by(lay: RefCounted, cell: int) -> int:
	## The room of a pirate's drawing a hit at that cell of it falls in: its own, or (a wall) the nearest one beside.
	if cell < 0:
		return -1
	if lay.room_of[cell] >= 0:
		return lay.room_of[cell]
	var x: int = cell % lay.width
	var y: int = cell / lay.width
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= lay.width or ny >= lay.height:
					continue
				var c: int = ny * lay.width + nx
				if lay.room_of[c] >= 0:
					return lay.room_of[c]
	return -1


func _crew_near(cell: int) -> int:
	## (v92) The cell of one of our people nearest that cell (a neural shot that struck off its mark): -1, none aboard.
	var map = server.map
	var best := -1
	var best_d := INF
	for p in server.players:
		if p == null or p.pirate or p.ally or p.corpse or p.cond == Net.COND_DEAD:
			continue
		var at: int = p.st.y * map.width + p.st.x
		if not map.on_ship(at):
			continue
		var d := Vector2(p.st.x, p.st.y).distance_to(Vector2(cell % map.width, cell / map.width)) if cell >= 0 else 0.0
		if d < best_d:
			best_d = d
			best = at
	return best


func _their_shot_lands(log: Dictionary, ends: int, target: int, cell: int, spot: Vector2, soft: bool = false) -> void:
	## One of its shots arrives (see _enemy_fires): what it does, and the volley
	## told in one line once its last shot is in.
	var map = server.map
	var ship = server.ship
	var w: int = log["w"]
	var fx: int = log.get("fx", Weapons.FX_NONE)
	var said: PackedStringArray = log["said"]
	log["left"] -= 1
	if ends == Net.SHOT_DOWN:
		log["down"] += 1
		server.combat.jolt(Net.JOLT_SHIELD, Net.SHOT_FLAK, spot)
	elif ends == Net.MISSED:
		log["misses"] += 1
	elif ends == Net.RICOCHET:
		log["ricochet"] += 1
		server.combat.jolt(Net.JOLT_HULL, _shot_kind(w), spot)
	elif ends == Net.HELD:
		log["held"] = int(log.get("held", 0)) + 1          # (v93) our armour held: a blow, nothing inside
		server.combat.jolt(Net.JOLT_HULL, _shot_kind(w), spot)
	elif ends == 0:
		if not server.arena.on():
			ship.shield = maxf(ship.shield - Weapons.shield_damage(w), 0.0)
		log["stopped"] += 1
		server.combat.jolt(Net.JOLT_SHIELD, _shot_kind(w), spot)
	elif cell >= 0:
		var info := Weapons.info(w)
		var damage: int = info.get("damage", 0) if _units < 0 else _units
		if soft:
			damage = maxi(damage - Weapons.KINETIC_SHIELD, 0)
			ship.shield = maxf(ship.shield - Weapons.KINETIC_WEAR, 0.0)
		var heavy := damage >= 2 or Weapons.klass(w) == Weapons.CLASS_ROCKET
		server.combat.jolt(Net.JOLT_HEAVY if heavy else Net.JOLT_HULL, _shot_kind(w), spot)
		if Weapons.klass(w) == Weapons.CLASS_NEURAL:
			said.append(_stun_room(cell, float(info["stun"])))
		elif info.has("disable"):
			# ion and EMP: a gun or the shield stops for a while, no damage
			ship.jammed[cell] = maxi(int(ship.jammed.get(cell, 0)), server.tick + roundi(float(info["disable"]) * Net.TICK_HZ))
			said.append("%s выключено на %d с." % [_cap(map.device_name(cell)), int(info["disable"])])
		elif target >= 0:
			# a gun, a console or the shield generator put out of order
			ship.broken[target] = true
			server.to_all(ship.devices_packet())
			server.crew.hull_hit(_armoured(Net.HULL_PER_SYSTEM_HIT * damage))
			if map.engine.has(target):
				server.systems.power_changed()        # (v57: the battleship aims at it) the whole ship goes dark
				said.append("Двигатель выбит: корабль обесточен! Почините его на нижней палубе.")
			else:
				said.append("Не работает: %s." % map.device_name(target))
		elif (Weapons.hole_chance(w) >= 1.0 or fx == Weapons.FX_HOLE or _rng.randf() < Weapons.hole_chance(w)) \
				and not (not server.arena.on() and server.outfit.no_hole() > 0.0 and _rng.randf() < server.outfit.no_hole()):
			# ((v93) in the fight in space the plating's points of armour (Arena) take the place of its chance)
			said.append("Обшивка пробита.")
			if server.systems.breach(cell):
				server.crew.hull_hit(_armoured(Net.HULL_PER_HOLE * (damage - 1)))
			else:
				server.crew.hull_hit(_armoured(Net.HULL_PER_HOLE * damage))
		elif Weapons.klass(w) != Weapons.CLASS_ROCKET:
			# (v59) it would have holed the hull, but our armour plating held
			server.crew.hull_hit(_armoured(Net.HULL_PER_HOLE * damage))
			said.append("Броня выдержала: пробоины нет, прочность %d из %d." % [ship.hull, server.ship.hull_max])
		else:
			server.crew.hull_hit(_armoured(Net.HULL_PER_HOLE * damage))
			said.append("Ракета разорвалась на обшивке: прочность %d из %d." % [ship.hull, server.ship.hull_max])
		if Weapons.klass(w) != Weapons.CLASS_NEURAL and not info.has("disable") and target < 0 \
				and server.systems.knock_on(cell, heavy) != "":
			said.append("От удара что-то сломалось рядом.")     # (v68, the author's E1) breakdowns come from hits
		if Weapons.pierce(w) > 0 or fx == Weapons.FX_HOLE:
			# (v58) it goes on through, or tears a second hole: one more breach beside the crew
			var past := _hull_near_crew()
			if past >= 0 and server.systems.breach(past):
				said.append("Пробито навылет." if Weapons.pierce(w) > 0 else "Вторая пробоина.")
		if fx == Weapons.FX_STUN and Weapons.klass(w) != Weapons.CLASS_NEURAL:
			said.append(_stun_room(cell, Weapons.FX_STUN_HEALTH))
		elif fx == Weapons.FX_KNOCK and (map.guns.has(cell) or cell == shield_cell()):
			ship.jammed[cell] = maxi(int(ship.jammed.get(cell, 0)), server.tick + roundi(Weapons.FX_KNOCK_SECONDS * Net.TICK_HZ))
			said.append("Сбой: %s на %d с." % [map.device_name(cell), int(Weapons.FX_KNOCK_SECONDS)])
	if int(log["left"]) > 0:
		return
	var parts := PackedStringArray()
	var stopped: int = log["stopped"]
	var misses: int = log["misses"]
	if stopped > 0:
		parts.append("щит отразил" + ("" if stopped == 1 else " %d" % stopped) + " (щит %d)" % roundi(ship.shield))
	if misses > 0:
		parts.append("мимо" + ("" if misses == 1 else " ×%d" % misses))
	if int(log["down"]) > 0:
		var rocket := Weapons.klass(w) == Weapons.CLASS_ROCKET
		parts.append(("«Заслон» сбил " + ("ракету" if rocket else "снаряд")) if int(log["down"]) == 1
			else "«Заслон» сбил %s (%d)" % ["ракеты" if rocket else "снаряды", int(log["down"])])
	if int(log.get("ricochet", 0)) > 0:
		parts.append("рикошет от нашей брони" + ("" if int(log["ricochet"]) == 1 else " ×%d" % int(log["ricochet"])))
	if int(log.get("held", 0)) > 0:
		parts.append("наша броня выдержала" + ("" if int(log["held"]) == 1 else " ×%d" % int(log["held"])))
	if parts.is_empty() and said.is_empty() or said.is_empty() and server.arena.on():
		return                               # (v94) in space: only what got inside is told
	var line := "Пираты стреляют (%s)%s%s" % [Weapons.lower_name(w, fx), (": " + ", ".join(parts) + ".") if not parts.is_empty() else ".",
		"" if said.is_empty() else " Попадание! " + " ".join(said)]
	# (v68, the author's G3) what the volley did to us is a warning for everybody; misses and the shield are the bridge's
	if said.is_empty():
		server.chat.say_bridge(line)
	else:
		server.chat.say(line)


func _armoured(strength: int) -> int:
	## (v59) What a pirate hit takes from our hull, with our armour plating.
	return roundi(strength * server.outfit.hull_share()) if strength > 0 else strength


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


func _jam_choice() -> int:
	## What an ion or EMP hit on our hull puts out: the shield generator if we have one, else a gun.
	var gen := shield_cell()
	if gen >= 0 and not server.ship.broken.has(gen):
		return gen
	var map = server.map
	return map.guns[_rng.randi_range(0, map.guns.size() - 1)] if map.guns.size() > 0 else -1


func _enemy_target() -> int:
	## Where its shot is meant to land: a gun, a bridge console or the shield
	## generator (cells of `map.guns` and the like), or -1: the hull.
	var map = server.map
	var guns := PackedInt32Array()
	for g: int in map.guns:
		if not server.ship.broken.has(g) and server.ship.mounts[map.guns.find(g)] != Weapons.NONE:
			guns.append(g)
	if boss == 1:
		return _boss_target(guns)
	var t: Dictionary = Hulls.temper(temper)
	var at_guns := 0.0 if guns.is_empty() else minf(float(t["at_guns"]) + (0.2 if fleeing() else 0.0), 0.95)
	var devices := PackedInt32Array()
	if server.systems.can_break("console"):
		for c: int in map.chart.keys() + map.helm.keys():
			devices.append(c)
	var gen := shield_cell()
	if gen >= 0 and not server.ship.broken.has(gen):
		devices.append(gen)
		devices.append(gen)              # it knows what keeps its shots off
	for c: int in map.smes:              # (v61, the author's V8) and what keeps our power up
		if not server.ship.broken.has(c):
			devices.append(c)
	var roll := _rng.randf()
	if roll < at_guns:
		return guns[_rng.randi_range(0, guns.size() - 1)]
	if roll < at_guns + (1.0 - at_guns) * float(t["devices"]) and not devices.is_empty():
		return devices[_rng.randi_range(0, devices.size() - 1)]
	return -1


func _boss_target(guns: PackedInt32Array) -> int:
	## (v57, the author: "better AI to target our engine and shield room, not
	## random rooms") The battleship goes for our shield generator while it works,
	## then the engine (which darkens the whole ship), then our guns. The rule of
	## one way out does not hold against it (the author: "you win or you lose").
	if _rng.randf() >= BOSS_AIM:
		return -1
	var gen := shield_cell()
	if gen >= 0 and not server.ship.broken.has(gen) and server.ship.shield_on:
		return gen
	var engine: Array = server.map.engine.keys().filter(func(c: int) -> bool: return not server.ship.broken.has(c))
	if not engine.is_empty():
		return engine[_rng.randi_range(0, engine.size() - 1)]
	for c: int in server.map.smes:       # (v61) then the SMES that carries the ship without its engine
		if not server.ship.broken.has(c):
			return c
	if not guns.is_empty():
		return guns[_rng.randi_range(0, guns.size() - 1)]
	return -1


func _crew_cell() -> int:
	## (v57) Where one of our people stands, by lot (a neural shot is aimed at
	## people; those at the posts first, as they see them): -1 = nobody aboard.
	var map = server.map
	var crew: Array = []
	for p in server.players:
		if p != null and not p.pirate and not p.ally and not p.corpse and p.cond != Net.COND_DEAD and map.on_ship(p.st.y * map.width + p.st.x):
			crew.append(p)
	if crew.is_empty():
		return -1
	var who = crew[_rng.randi_range(0, crew.size() - 1)]
	return who.st.y * map.width + who.st.x


func _hull_nearest(cell: int) -> int:
	## (v57) The cell of our hull nearest that place, on its deck (any, if it cannot tell).
	var map = server.map
	if map.hull.is_empty():
		return -1
	if cell < 0:
		return map.hull[_fx.randi_range(0, map.hull.size() - 1)]
	var best := -1
	var best_d := INF
	for c: int in map.hull:
		if map.deck_of(c / map.width) != map.deck_of(cell / map.width):
			continue
		var d := Vector2(c % map.width, c / map.width).distance_squared_to(Vector2(cell % map.width, cell / map.width))
		if d < best_d:
			best_d = d
			best = c
	return best if best >= 0 else map.hull[0]


func _stun_room(cell: int, stun: float) -> String:
	## (v57) A neural shot bursts at that cell: everybody of ours in its room
	## (or on that very cell, in a doorway) is struck senseless for a while. It
	## leaves no wound: they come round by themselves, if nobody finishes them.
	var map = server.map
	if cell < 0:
		return "Нейроудар пришёлся в пустоту."
	var room: int = map.room_of[cell]
	var names := PackedStringArray()
	for p in server.players:
		if p == null or p.pirate or p.corpse or p.cond == Net.COND_DEAD:
			continue
		var at: int = p.st.y * map.width + p.st.x
		if at != cell and (room < 0 or map.room_of[at] != room):
			continue
		if p.cond == Net.COND_OK:
			server.chat.sound(Net.SOUND_CRY, p.st.x, p.st.y, p.slot)
		p.health = maxf(p.health - stun, minf(p.health, STUN_FLOOR))
		names.append(p.name)
	if names.is_empty():
		return "Нейроудар пришёлся в пустой отсек."
	return "Нейроудар оглушил: %s." % ", ".join(names)


func _hull_near_crew() -> int:
	## A whole cell of our hull to hole: half the time the one nearest somebody
	## of the crew (it sees where they are), else anywhere. -1 = none left.
	var map = server.map
	var choice := PackedInt32Array()
	for c: int in map.hull:
		if not server.air.holes.has(c):
			choice.append(c)
	if choice.is_empty():
		return -1
	var crew: Array = []
	for p in server.players:
		if p != null and not p.pirate and not p.ally and not p.corpse and p.cond != Net.COND_DEAD and map.on_ship(p.st.y * map.width + p.st.x):
			crew.append(p)
	if crew.is_empty() or _rng.randf() < 0.5:
		return choice[_rng.randi_range(0, choice.size() - 1)]
	var who = crew[_rng.randi_range(0, crew.size() - 1)]
	var best := -1
	var best_d := INF
	for c: int in choice:
		if map.deck_of(c / map.width) != map.deck_of(who.st.y):
			continue
		var d := Vector2(c % map.width, c / map.width).distance_squared_to(Vector2(who.st.x, who.st.y))
		if d < best_d:
			best_d = d
			best = c
	return best if best >= 0 else choice[_rng.randi_range(0, choice.size() - 1)]


func _outward(cell: int) -> Vector2i:
	## Which way is space from this wall cell (up if it cannot tell).
	var map = server.map
	var x: int = cell % map.width
	var y: int = cell / map.width
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if map.is_space(x + d.x, y + d.y):
			return d
	return Vector2i(0, -1)


# ---------------------------------------------------------------- (v55) our boarders

func crew_lost(alive: int, crossed: int = 0) -> void:
	## Its crew, come to life as pirates (EnemyCrew.in_world), are down to `alive`:
	## the count of its crew follows, and the fight may be over. (v64) `crossed` of
	## those gone walked over onto our ship alive: they are boarders now, not dead.
	if systems.size() <= Net.ESYS_CREW or _over:
		return
	var was := boarders_left()
	systems[Net.ESYS_CREW] = mini(systems[Net.ESYS_CREW], maxi(alive, 0) * HITS_PER_BOARDER)
	server.derelict._pirates_party = boarders_left()
	var gone := was - boarders_left()
	if crossed > 0 and gone > 0:
		server.chat.say("Пират перебрался с их корабля на наш! На пиратском корабле их осталось %d." % boarders_left())
	elif gone > 0 and boarders_left() > 0:
		server.chat.say("На пиратском корабле убит пират: их осталось %d." % boarders_left())
	_settle()


func crew_sent(n: int, room: int) -> void:
	## (v62) `n` of its crew have gone over to us by teleporter (Assault): its crew counts follow.
	if systems.size() <= Net.ESYS_CREW:
		return
	systems[Net.ESYS_CREW] = maxi(systems[Net.ESYS_CREW] - n * HITS_PER_BOARDER, HITS_PER_BOARDER)
	server.derelict._pirates_party = boarders_left()
	server.enemy_crew.keep(boarders_left(), room)


func wear_by_hand(system: int) -> void:
	## One of our boarders wrecks a point of the system in the room it stands in.
	if system < 0 or system >= systems.size() or systems[system] == 0 or system == Net.ESYS_CREW:
		return
	systems[system] -= 1
	reveal(room_of_system(system))
	if systems[system] == 0:
		if system == Net.ESYS_SHIELDS:
			enemy_shield = 0.0
		server.chat.say("Наши на борту пиратов вывели из строя: %s. %s" % [Net.ESYS_NAMES[system].to_lower(), DOWN_TEXT[system]])
	else:
		server.chat.say_bridge(SABOTAGE_TEXT % [Net.ESYS_NAMES[system].to_lower(), systems[system], systems_full[system]])
	if crewless and system == Net.ESYS_DRONES and systems[system] == 0:
		_settle()                            # (v62) its core wrecked by hand: the drone ship is ours
