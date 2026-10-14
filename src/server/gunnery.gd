extends RefCounted
## The ship's guns, and the guns of a pirate ship that comes for us. Server only.
##
## Our guns sit in the hull ('T' in the map) and are fired from the gun
## console on the bridge. Each charges by itself while the ship has power and
## the gun is whole; a charged gun fires at the enemy when told to. A pirate
## ship off the airlock shoots back until it docks: its hits tear the hull or
## put a gun or a bridge console out of order. Its own hull takes ENEMY_HULL
## hits; then it is wrecked and goes, and the ship is paid for it.
##
## The guns aim at one of the enemy's systems (Net.ESYS_*), each in a room of
## its drawing (ShipMap.zones), or anywhere. A hit takes one from its hull and
## one from the system in the room it lands in; a system worn to nothing stops
## working (its guns fall silent, its bridge cannot aim or dodge, its engine
## cannot close in) until its crew mends it, a point every ENEMY_REPAIR_SECONDS.
## Every HITS_PER_BOARDER hits on its quarters kill one of its crew; a ship
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

const Net := preload("res://src/shared/net.gd")

const CHARGE_SECONDS := 8.0          # from fired to ready again
const HIT_CHANCE := 0.75             # our shot hits
const ENEMY_HULL := 6                # hits a pirate ship takes before it is wrecked
const ENEMY_GAP := [9.0, 13.0]       # seconds between the pirate ship's shots
const ENEMY_HIT_CHANCE := 0.7
const ENEMY_BREACH_SHARE := 0.6      # of its hits, those that hole the hull (the rest put something out of order)
const WRECK_REWARD := 25             # credits for a wrecked pirate ship
const SYSTEM_STRENGTH := 2           # hits that put one of its systems out
const HITS_PER_BOARDER := 2          # hits on its quarters that kill one of its boarding party
const ENEMY_REPAIR_SECONDS := 15.0   # its crew mends one point of a worn system this often
const BLIND_HIT_CHANCE := 0.95       # our shot hits while its bridge is out: it cannot dodge
const BLIND_ENEMY_HIT := 0.5         # and its own shots hit this much less often
const DOWN_TEXT: Array[String] = ["Пираты не могут стрелять.", "Пираты не могут уклоняться и стреляют мимо.",
	"Пираты не могут ни подойти, ни уйти прыжком.", "", "Пираты не могут уйти прыжком."]
const FLEE_HULL := 2                 # hull left at which it gives up and runs
const FLEE_SECONDS := 20.0           # to charge its jump with the drive whole (the author's number); worn, longer
const AIM_GUNS := 0.55               # share of its shots that go for our guns while one of them works

var enemy_hit_chance := ENEMY_HIT_CHANCE   # (tests set it to 1)
var server: Node
var charge := PackedFloat32Array()   # per gun, 0..1
var enemy_hull := 0                  # hits the enemy can still take; 0 = no enemy
var systems := PackedByteArray()     # per Net.ESYS_*: the strength the enemy's system has left
var systems_full := PackedByteArray() # and when whole
var aim := Net.AIM_ANY               # where our guns aim (Net.ESYS_* or Net.AIM_ANY)
var raid := false                    # it came to fight at a distance, not to board
var flee := -1.0                     # ticks' worth of its jump charged while it runs (-1 = it is not running)
var _enemy_next := 0                 # the tick the enemy fires next
var _mend_next := 0                  # the tick the enemy's crew mends something next
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	charge.resize(server.map.guns.size())
	charge.fill(1.0)
	enemy_hull = 0
	systems = PackedByteArray()
	systems_full = PackedByteArray()
	aim = Net.AIM_ANY
	_told = PackedByteArray()
	_rng.randomize()


func enemy_arrives(boarders: int, p_raid: bool = false) -> void:
	enemy_hull = ENEMY_HULL
	raid = p_raid
	flee = -1.0
	_enemy_next = server.tick + roundi(_rng.randf_range(ENEMY_GAP[0], ENEMY_GAP[1]) * Net.TICK_HZ)
	_mend_next = server.tick + roundi(ENEMY_REPAIR_SECONDS * Net.TICK_HZ)
	systems_full = PackedByteArray([SYSTEM_STRENGTH, SYSTEM_STRENGTH, SYSTEM_STRENGTH, maxi(boarders, 1) * HITS_PER_BOARDER,
		SYSTEM_STRENGTH])
	systems = systems_full.duplicate()
	aim = Net.AIM_ANY


func enemy_gone() -> void:
	enemy_hull = 0
	flee = -1.0
	systems = PackedByteArray()
	systems_full = PackedByteArray()


func down(which: int) -> bool:
	## Is that system of the enemy out of action?
	return which < systems.size() and systems[which] == 0


func boarders_left() -> int:
	## How many of its boarding party are still alive (two hits on its quarters kill one).
	return 0 if systems.size() <= Net.ESYS_CREW else (systems[Net.ESYS_CREW] + HITS_PER_BOARDER - 1) / HITS_PER_BOARDER


func aim_asked(p, which: int) -> void:
	## Somebody at the gun console points the guns at one of the enemy's systems, or anywhere.
	if not server.systems.at_console(p, server.map.gun_console):
		return
	if which != Net.AIM_ANY and (which < 0 or which >= Net.ESYS_COUNT):
		return
	aim = which


func fighting() -> bool:
	## A pirate ship lies off the airlock and has not docked yet: guns can reach it, and it shoots.
	var d = server.derelict
	return enemy_hull > 0 and d.here and d.kind == Net.OTHER_PIRATE and not d.docked and not d.wreck


func fleeing() -> bool:
	return flee >= 0.0


func _jump_rate() -> float:
	## How fast its jump charges now: 1 with the drive whole, slower worn, 0 with it or the engine out.
	if down(Net.ESYS_ENGINE) or down(Net.ESYS_JUMP) or systems.size() <= Net.ESYS_JUMP:
		return 0.0
	return float(systems[Net.ESYS_JUMP]) / maxf(systems_full[Net.ESYS_JUMP], 1.0)


func jump_seconds_left() -> int:
	## Seconds until it jumps away at the pace it charges now (65535 = it cannot charge now).
	var rate := _jump_rate()
	if rate <= 0.0:
		return 65535
	return int(ceil((FLEE_SECONDS * Net.TICK_HZ - flee) / rate / Net.TICK_HZ))


func tick() -> void:
	var map = server.map
	var step := 1.0 / (CHARGE_SECONDS * Net.TICK_HZ)
	for i in charge.size():
		if server.powered() and not server.ship.broken.has(map.guns[i]):
			charge[i] = minf(charge[i] + step, 1.0)
	if fighting():
		if not fleeing() and (enemy_hull <= FLEE_HULL or (down(Net.ESYS_WEAPONS) and enemy_hull * 2 <= ENEMY_HULL)):
			_starts_to_flee()
		if (down(Net.ESYS_ENGINE) or fleeing()) and server.derelict._pirates_dock_at >= 0:
			server.derelict._pirates_dock_at += 1          # it drifts, or runs: the time to fight it off stands still
		if fleeing():
			flee += _jump_rate()
			if flee >= FLEE_SECONDS * Net.TICK_HZ:
				_escaped()
		if fighting() and server.tick >= _enemy_next:
			_enemy_next = server.tick + roundi(_rng.randf_range(ENEMY_GAP[0], ENEMY_GAP[1]) * Net.TICK_HZ * _weapons_slowness())
			if not down(Net.ESYS_WEAPONS):
				_enemy_fires()
		if fighting() and server.tick >= _mend_next:
			_mend_next = server.tick + roundi(ENEMY_REPAIR_SECONDS * Net.TICK_HZ)
			_enemy_mends()
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func packet() -> PackedByteArray:
	var map = server.map
	var out := PackedByteArray([Net.S_GUNS, server.ship.id & 0xFF, server.ship.id >> 8, charge.size()])
	for i in charge.size():
		out.append(255 if server.ship.broken.has(map.guns[i]) else roundi(charge[i] * 20.0) * 5)
	out.append(enemy_hull if fighting() else 0)
	out.append(ENEMY_HULL if fighting() else 0)
	var left := 0
	if fighting() and server.derelict._pirates_dock_at >= 0:
		left = maxi(int(ceil(float(server.derelict._pirates_dock_at - server.tick) / Net.TICK_HZ)), 0)
	out.append(left & 0xFF)
	out.append(left >> 8)
	out.append(aim)
	if fighting():
		out.append(systems.size())
		for i in systems.size():
			out.append(systems[i])
			out.append(systems_full[i])
	else:
		out.append(0)
	out.append(((Net.ENEMY_RAID if raid else 0) | (Net.ENEMY_FLEEING if fleeing() else 0)) if fighting() else 0)
	var jump := jump_seconds_left() if fighting() and fleeing() else 0
	out.append(jump & 0xFF)
	out.append(jump >> 8)
	return out


func _weapons_slowness() -> float:
	## Its guns fire slower as they are worn down.
	if systems.size() <= Net.ESYS_WEAPONS or systems[Net.ESYS_WEAPONS] == 0:
		return 1.0
	return float(systems_full[Net.ESYS_WEAPONS]) / float(systems[Net.ESYS_WEAPONS])


func _starts_to_flee() -> void:
	flee = 0.0
	var why := "" if _jump_rate() > 0.0 else " Но %s выбит: пока его не починят, прыжка не будет." % \
		("двигатель" if down(Net.ESYS_ENGINE) else "гипердвигатель")
	server.chat.say("Пиратский корабль сильно повреждён и заряжает гипердвигатель, чтобы уйти: через %d с его не догнать. Выбейте двигатель или гипердвигатель, и он не уйдёт.%s" % [
		int(FLEE_SECONDS), why])


func _escaped() -> void:
	## It got its jump charged: it is gone, and nobody is paid for it.
	enemy_hull = 0
	server.derelict.pirates_escaped()
	server.chat.say("Пиратский корабль ушёл в прыжок. Упустили.")


func fire(p, which: int) -> void:
	## Somebody at the gun console fires one gun, or every gun that is ready (which = 255).
	var map = server.map
	if not server.systems.at_console(p, map.gun_console):
		return
	if not fighting():
		server.chat.say("Стрелять не по кому: целей нет.")
		return
	var fired := 0
	for i in charge.size():
		if (which == 255 or which == i) and charge[i] >= 1.0 and not server.ship.broken.has(map.guns[i]):
			charge[i] = 0.0
			fired += 1
			_our_shot(i)
			if enemy_hull <= 0 or down(Net.ESYS_CREW):
				break
	if fired > 0 and enemy_hull <= 0:
		_wrecked()
	elif fired > 0 and down(Net.ESYS_CREW):
		if raid:
			_wrecked()                       # nobody left alive aboard: it drifts, a dead hulk
		else:
			_broken_off()


func _broken_off() -> void:
	## Its boarding party is dead: with nobody to send over it gives up and goes.
	enemy_hull = 0
	server.derelict.pirates_wrecked()
	server.chat.say("Абордажная команда пиратов перебита! Пиратский корабль прекращает атаку и уходит.")


func _our_shot(i: int) -> void:
	var map = server.map
	var cell: int = map.guns[i]
	var x: int = cell % map.width
	var y: int = cell / map.width
	var out := _outward(cell)
	server.chat.sound(Net.SOUND_SHOT, x, y)
	var hit := _rng.randf() < (BLIND_HIT_CHANCE if down(Net.ESYS_HELM) else HIT_CHANCE)
	server.combat.tell_shot(Net.SHOT_CANNON, hit, Vector2(x, y), Vector2(x, y) + Vector2(out) * 12.0, y)
	if not hit:
		server.chat.say("Орудие %d: промах." % (i + 1))
		return
	enemy_hull -= 1
	var room := aim if aim != Net.AIM_ANY else _rng.randi_range(0, Net.ESYS_COUNT - 1)
	_hole_near(room)
	var what := ""
	if room < systems.size() and systems[room] > 0:
		systems[room] -= 1
		if room == Net.ESYS_CREW:
			var left := boarders_left()
			if left < server.derelict._pirates_party:
				server.derelict._pirates_party = left
				what = (" Убит пират из экипажа, осталось %d." if raid else " Убит абордажник, осталось %d.") % left
			else:
				what = " Пираты в кубрике ранены." if raid else " Абордажники ранены."
		elif systems[room] == 0:
			what = " Выведено из строя: %s. %s" % [Net.ESYS_NAMES[room].to_lower(), DOWN_TEXT[room]]
			if fleeing() and (room == Net.ESYS_ENGINE or room == Net.ESYS_JUMP):
				what += " Прыжок сорван, пока не починят."
		elif room == Net.ESYS_JUMP and fleeing():
			what = " Повреждено: гипердвигатель. Прыжок заряжается медленнее: ещё %d с." % jump_seconds_left()
		else:
			what = " Повреждено: %s." % Net.ESYS_NAMES[room].to_lower()
	server.chat.say("Орудие %d: попадание (%s)!%s Корпус пиратского корабля: %d из %d." % [i + 1, Net.ESYS_NAMES[room].to_lower(), what, maxi(enemy_hull, 0), ENEMY_HULL])


func _hole_near(room: int) -> void:
	## A hole in the enemy's hull, next to the room that was hit where it can be (where it shows otherwise).
	var hull: PackedInt32Array = server.derelict._hull_cells()
	if hull.is_empty():
		return
	var near := PackedInt32Array()
	var o = server.map.other
	if o != null and room < o.zones.size():
		var w: int = server.map.width
		for c: int in hull:
			for local: int in o.zones[room]:
				var z: int = server.derelict._cell(server.map.other_at, local)
				if absi(z % w - c % w) <= 1 and absi(z / w - c / w) <= 1:
					near.append(c)
					break
	var from := near if not near.is_empty() else hull
	var c: int = from[_rng.randi_range(0, from.size() - 1)]
	if server.air.set_hole(c, true):
		server.replication.hull_record(c, 1)


func _enemy_mends() -> void:
	## The pirates' own crew mends a worn system by a point (its quarters are not
	## mended): what it needs most first. A system knocked out comes before one
	## only worn; while it runs, the jump drive and the engine come first, else its guns.
	var order: Array = [Net.ESYS_JUMP, Net.ESYS_ENGINE, Net.ESYS_WEAPONS, Net.ESYS_HELM] if fleeing() \
		else [Net.ESYS_WEAPONS, Net.ESYS_HELM, Net.ESYS_ENGINE, Net.ESYS_JUMP]
	var worst := -1
	for k: int in order:
		if k < systems.size() and systems[k] < systems_full[k] and (worst < 0 or (systems[k] == 0 and systems[worst] > 0)):
			worst = k
	if worst < 0:
		return
	systems[worst] += 1
	if systems[worst] == 1:
		server.chat.say("Пираты починили: %s снова работают." % Net.ESYS_NAMES[worst].to_lower())


func _wrecked() -> void:
	enemy_hull = 0
	server.ship.credits += WRECK_REWARD
	if raid:
		# it stays alongside, dead: what it holds is there for the taking
		server.derelict.becomes_wreck()
		server.chat.say("Пиратский корабль разбит! За него начислено %d кредитов. Его обломки остались у шлюза: туда можно добраться через открытый космос или пристыковаться с пульта управления и обыскать." % WRECK_REWARD)
	else:
		server.ship.store[Net.ITEM_FUEL] = int(server.ship.store.get(Net.ITEM_FUEL, 0)) + Net.WRECK_FUEL
		server.derelict.pirates_wrecked()
		server.chat.say("Пиратский корабль разбит и уходит, не успев пристыковаться! За него начислено %d кредитов, из обломков подобрана канистра топлива." % WRECK_REWARD)
	server.supplies.tell_store()


func _enemy_fires() -> void:
	## The pirate ship's shot. It goes for our guns while one of them works (and
	## all the more while it runs, to cover its escape); otherwise it holes the
	## hull, as near the crew as it can, or now and then hits a bridge console.
	var map = server.map
	if _rng.randf() >= enemy_hit_chance * (BLIND_ENEMY_HIT if down(Net.ESYS_HELM) else 1.0):
		server.chat.say("Пиратский корабль стреляет: мимо.")
		return
	var guns := PackedInt32Array()
	for g: int in map.guns:
		if not server.ship.broken.has(g):
			guns.append(g)
	var at_guns := 0.0 if guns.is_empty() else AIM_GUNS + (0.2 if fleeing() else 0.0)
	var consoles := PackedInt32Array()
	if server.systems.can_break("console"):
		for c: int in map.chart.keys() + map.helm.keys():
			consoles.append(c)
	var roll := _rng.randf()
	var hit := -1
	if roll < at_guns:
		hit = guns[_rng.randi_range(0, guns.size() - 1)]
	elif roll < at_guns + (1.0 - at_guns) * (1.0 - ENEMY_BREACH_SHARE) and not consoles.is_empty():
		hit = consoles[_rng.randi_range(0, consoles.size() - 1)]
	if hit < 0:
		var c := _hull_near_crew()
		if c >= 0:
			_tracer_to(c)
			server.systems.breach(c)
		return
	server.ship.broken[hit] = true
	server.to_all(server.ship.devices_packet())
	server.crew.hull_hit(Net.HULL_PER_SYSTEM_HIT)
	_tracer_to(hit)
	server.chat.say("Попадание пиратов! Не работает: %s." % map.device_name(hit))


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
		if p != null and not p.pirate and not p.corpse and p.cond != Net.COND_DEAD and map.on_ship(p.st.y * map.width + p.st.x):
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


func _tracer_to(cell: int) -> void:
	var map = server.map
	var at := Vector2(cell % map.width, cell / map.width)
	server.combat.tell_shot(Net.SHOT_CANNON, true, at + Vector2(_outward(cell)) * 12.0, at, int(at.y))
	server.chat.sound(Net.SOUND_THUD, int(at.x), int(at.y))


func _outward(cell: int) -> Vector2i:
	## Which way is space from this wall cell (up if it cannot tell).
	var map = server.map
	var x: int = cell % map.width
	var y: int = cell / map.width
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if map.is_space(x + d.x, y + d.y):
			return d
	return Vector2i(0, -1)
