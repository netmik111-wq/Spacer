extends RefCounted
## The ship's guns and shield, and the guns and shield of a pirate ship that
## comes for us. Server only.
##
## Our guns sit in the hull ('T' in the map) and are fired from the gun
## console on the bridge. Each gun mount holds one weapon (Weapons.*), or none;
## a weapon taken down goes into the cargo (the supply locker) as a thing, and
## another from the cargo goes up in its place (v49, the author's request).
## An armed weapon draws power from the reactor (Weapons.REACTOR, shared with
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

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const CHARGE_SECONDS := 8.0          # (the plain laser's; each weapon has its own, see Weapons)
const ENEMY_HULL := 12               # damage a pirate ship takes before it is wrecked (v49: was 6)
const ENEMY_SLOWER := 1.3            # its guns charge this much slower than ours
const ENEMY_SHIELD_CHANCE := 0.7     # share of pirate ships with a shield generator
const WRECK_REWARD := 40             # credits for a wrecked pirate ship
const SYSTEM_STRENGTH := 3           # damage that puts one of its systems out
const HITS_PER_BOARDER := 2          # damage on its quarters that kills one of its boarding party
const ENEMY_REPAIR_SECONDS := 15.0   # its crew mends one point of a worn system this often
const ENEMY_BREACH_SHARE := 0.6      # of its hits not at our guns, those that hole the hull (the rest put a console or the shield out)
const DOWN_TEXT: Array[String] = ["Пираты не могут стрелять.", "Пираты не могут уклоняться и стреляют мимо.",
	"Пираты не могут ни подойти, ни уйти прыжком.", "", "Пираты не могут уйти прыжком.", "Щит пиратов погас."]
const FLEE_HULL := 4                 # hull left at which it gives up and runs
const FLEE_SECONDS := 20.0           # to charge its jump with the drive whole (the author's number); worn, longer
const AIM_GUNS := 0.55               # share of its shots that go for our guns while one of them works
const BLIND_ENEMY_HIT := 0.5         # its shots hit this much less often while its bridge is out
# what a pirate ship may carry: its first gun, its second, and a third far from the start
const ENEMY_FIRST: Array[int] = [Weapons.LASER]
const ENEMY_SECOND: Array[int] = [Weapons.LASER, Weapons.RAPID, Weapons.BLASTER, Weapons.ION, Weapons.ROCKET, Weapons.HEAVY]
const ENEMY_THIRD: Array[int] = [Weapons.HEAVY, Weapons.RAPID, Weapons.BLASTER, Weapons.ION_CANNON, Weapons.ROCKET, Weapons.EMP]
const THIRD_GUN_FROM := 5            # jumps from the start at which pirates carry a third gun

var enemy_hit_chance := -1.0         # (tests set it to 0 or 1: their shots always miss or always hit)
var shield_chance := ENEMY_SHIELD_CHANCE   # (tests set it)
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
var enemy_charge := PackedFloat32Array()
var aim := Net.AIM_ANY               # where our guns aim (Net.ESYS_* or Net.AIM_ANY)
var raid := false                    # it came to fight at a distance, not to board
var flee := -1.0                     # ticks' worth of its jump charged while it runs (-1 = it is not running)
var _mend_next := 0                  # the tick the enemy's crew mends something next
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	var n: int = server.map.guns.size()
	var ship = server.ship
	if ship.mounts.size() != n:
		ship.mounts.resize(n)
		ship.mounts.fill(Weapons.LASER)
		ship.armed.resize(n)
		ship.armed.fill(1)
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


func enemy_arrives(boarders: int, p_raid: bool = false) -> void:
	enemy_hull = ENEMY_HULL
	raid = p_raid
	flee = -1.0
	_mend_next = server.tick + roundi(ENEMY_REPAIR_SECONDS * Net.TICK_HZ)
	var shielded := _rng.randf() < shield_chance
	systems_full = PackedByteArray([SYSTEM_STRENGTH, SYSTEM_STRENGTH, SYSTEM_STRENGTH, maxi(boarders, 1) * HITS_PER_BOARDER,
		SYSTEM_STRENGTH, SYSTEM_STRENGTH if shielded else 0])
	systems = systems_full.duplicate()
	systems_out = PackedInt32Array()
	systems_out.resize(Net.ESYS_COUNT)
	enemy_shield = Weapons.SHIELD_FULL if shielded else 0.0
	enemy_weapons = loadout_for_test.duplicate() if not loadout_for_test.is_empty() else _loadout()
	enemy_charge = PackedFloat32Array()
	for w in enemy_weapons:
		enemy_charge.append(_rng.randf_range(0.0, 0.4))       # it comes with its guns part charged
	aim = Net.AIM_ANY


func _loadout() -> PackedByteArray:
	## The pirate ship's guns: more of them, and worse ones, the farther from the start.
	var far: int = server.sectors.far_from_start(server.ship.sector) if server.sectors.count > 0 else 0
	var out := PackedByteArray([ENEMY_FIRST[_rng.randi_range(0, ENEMY_FIRST.size() - 1)],
		ENEMY_SECOND[_rng.randi_range(0, ENEMY_SECOND.size() - 1)]])
	if far >= THIRD_GUN_FROM:
		out.append(ENEMY_THIRD[_rng.randi_range(0, ENEMY_THIRD.size() - 1)])
	return out


func enemy_gone() -> void:
	enemy_hull = 0
	flee = -1.0
	held_until = 0
	systems = PackedByteArray()
	systems_full = PackedByteArray()
	systems_out = PackedInt32Array()
	enemy_shield = 0.0
	enemy_weapons = PackedByteArray()
	enemy_charge = PackedFloat32Array()
	beam_left.fill(0)


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


# ---------------------------------------------------------------- our guns and shield

func shield_cell() -> int:
	## Our shield generator's wall cell, or -1 if the ship has none.
	return server.map.shield.keys()[0] if not server.map.shield.is_empty() else -1


func jammed(cell: int) -> bool:
	return server.tick < int(server.ship.jammed.get(cell, -1))


func power_used() -> int:
	## Power the armed guns and the shield draw from the reactor.
	var ship = server.ship
	var n := 0
	for i in ship.mounts.size():
		if ship.armed[i] == 1:
			n += Weapons.power(ship.mounts[i])
	if ship.shield_on and shield_cell() >= 0:
		n += Weapons.SHIELD_POWER
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
		Net.GUNSET_ARM:
			if a >= ship.mounts.size() or ship.mounts[a] == Weapons.NONE:
				return
			if b == 0:
				ship.armed[a] = 0
				charge[a] = 0.0              # a gun without power loses its charge
			elif ship.armed[a] == 0:
				if power_used() + Weapons.power(ship.mounts[a]) > Weapons.REACTOR:
					server.chat.tell(p, "Не хватает энергии реактора: %s берёт %d, свободно %d. Отключите другое орудие или щит." % [
						Weapons.name_of(ship.mounts[a]), Weapons.power(ship.mounts[a]), Weapons.REACTOR - power_used()])
					return
				ship.armed[a] = 1
		Net.GUNSET_SHIELD:
			if shield_cell() < 0:
				return
			if b == 0:
				ship.shield_on = false
				ship.shield = 0.0
			elif not ship.shield_on:
				if power_used() + Weapons.SHIELD_POWER > Weapons.REACTOR:
					server.chat.tell(p, "Не хватает энергии реактора на щит: нужно %d, свободно %d." % [Weapons.SHIELD_POWER, Weapons.REACTOR - power_used()])
					return
				ship.shield_on = true
		Net.GUNSET_MOUNT:
			if a >= ship.mounts.size() or (b != Weapons.NONE and not Weapons.known(b)) or b == ship.mounts[a]:
				return
			if b != Weapons.NONE and int(ship.store.get(Weapons.item_of(b), 0)) <= 0:
				return
			var old: int = ship.mounts[a]
			if old != Weapons.NONE:
				ship.store[Weapons.item_of(old)] = int(ship.store.get(Weapons.item_of(old), 0)) + 1
			if b != Weapons.NONE:
				ship.store[Weapons.item_of(b)] -= 1
			ship.mounts[a] = b
			ship.armed[a] = 0
			charge[a] = 0.0
			beam_left[a] = 0
			server.supplies.tell_store()
			if b == Weapons.NONE:
				server.chat.say("%s снимает с орудия %d: %s (в трюм)." % [p.name, a + 1, Weapons.name_of(old).to_lower()])
			else:
				server.chat.say("%s ставит на орудие %d: %s.%s Включите ему питание." % [p.name, a + 1, Weapons.name_of(b).to_lower(),
					"" if old == Weapons.NONE else " Снятое (%s) убрано в трюм." % Weapons.name_of(old).to_lower()])


func tick() -> void:
	var map = server.map
	var ship = server.ship
	for cell: int in ship.jammed.keys():
		if server.tick >= int(ship.jammed[cell]):
			ship.jammed.erase(cell)
	for i in charge.size():
		var w: int = ship.mounts[i]
		if w == Weapons.NONE or ship.armed[i] == 0:
			charge[i] = 0.0
		elif server.powered() and not ship.broken.has(map.guns[i]) and not jammed(map.guns[i]):
			charge[i] = minf(charge[i] + 1.0 / Weapons.charge_ticks(w), 1.0)
	# our shield: it falls without power, its generator or when switched off; it holds while ionised
	var gen := shield_cell()
	if gen < 0 or not ship.shield_on or not server.powered() or ship.broken.has(gen):
		ship.shield = 0.0
	elif not jammed(gen):
		ship.shield = minf(ship.shield + Weapons.SHIELD_REGEN / Net.TICK_HZ, Weapons.SHIELD_FULL)
	if fighting():
		if not fleeing() and (enemy_hull <= FLEE_HULL or (down(Net.ESYS_WEAPONS) and enemy_hull * 2 <= ENEMY_HULL)):
			_starts_to_flee()
		if (down(Net.ESYS_ENGINE) or fleeing() or held()) and server.derelict._pirates_dock_at >= 0:
			server.derelict._pirates_dock_at += 1          # it drifts, runs or is held: the time to fight it off stands still
		if fleeing() and not held():
			flee += _jump_rate()
			if flee >= FLEE_SECONDS * Net.TICK_HZ:
				_escaped()
		_enemy_shield_tick()
		if fighting() and not down(Net.ESYS_WEAPONS):
			var pace := 1.0 / _weapons_slowness() / ENEMY_SLOWER
			for k in enemy_weapons.size():
				enemy_charge[k] = minf(enemy_charge[k] + pace / Weapons.charge_ticks(enemy_weapons[k]), 1.0)
				if enemy_charge[k] >= 1.0 and fighting():
					enemy_charge[k] = 0.0
					_enemy_fires(enemy_weapons[k])
		if fighting() and server.tick >= _mend_next:
			_mend_next = server.tick + roundi(ENEMY_REPAIR_SECONDS * Net.TICK_HZ)
			_enemy_mends()
	for i in beam_left.size():
		if beam_left[i] > 0 and server.tick >= _beam_next[i]:
			_beam_pulse(i)
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func _enemy_shield_tick() -> void:
	## Its shield refills as fast as its generator is whole; knocked out, it falls.
	if systems.size() <= Net.ESYS_SHIELDS or systems_full[Net.ESYS_SHIELDS] == 0 or systems[Net.ESYS_SHIELDS] == 0:
		enemy_shield = 0.0
	elif server.tick >= systems_out[Net.ESYS_SHIELDS]:
		enemy_shield = minf(enemy_shield + Weapons.SHIELD_REGEN / Net.TICK_HZ * systems[Net.ESYS_SHIELDS] / systems_full[Net.ESYS_SHIELDS],
			Weapons.SHIELD_FULL)


func held() -> bool:
	## Does our tractor beam hold it now?
	return fighting() and server.tick < held_until


func _enemy_shield_up() -> bool:
	return enemy_shield > 0.0 and systems.size() > Net.ESYS_SHIELDS and not down(Net.ESYS_SHIELDS)


func packet() -> PackedByteArray:
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
			| (Net.GUNF_NO_AMMO if ammo != 0 and int(ship.store.get(ammo, 0)) <= 0 else 0))
	out.append(power_used())
	out.append(Weapons.REACTOR)
	var gen := shield_cell()
	out.append(roundi(ship.shield))
	out.append(0 if gen < 0 else (Net.SHF_HAS | (Net.SHF_ON if ship.shield_on else 0) | (Net.SHF_BROKEN if ship.broken.has(gen) else 0)
		| (Net.SHF_JAMMED if jammed(gen) else 0) | (Net.SHF_HARDENED if ship.hardened else 0)))
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
			out.append(clampi(int(ceil(float(systems_out[i] - server.tick) / Net.TICK_HZ)), 0, 255))
	else:
		out.append(0)
	out.append(((Net.ENEMY_RAID if raid else 0) | (Net.ENEMY_FLEEING if fleeing() else 0) | (Net.ENEMY_HELD if held() else 0))
		if fighting() else 0)
	var jump := jump_seconds_left() if fighting() and fleeing() else 0
	out.append(jump & 0xFF)
	out.append(jump >> 8)
	out.append(roundi(enemy_shield) if fighting() else 0)
	if fighting():
		out.append(enemy_weapons.size())
		out.append_array(enemy_weapons)
	else:
		out.append(0)
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
	beam_left.fill(0)
	server.derelict.pirates_escaped()
	server.chat.say("Пиратский корабль ушёл в прыжок. Упустили.")


func fire(p, which: int) -> void:
	## Somebody at the gun console fires one gun, or every gun that is ready (which = 255).
	var map = server.map
	var ship = server.ship
	if not server.systems.at_console(p, map.gun_console):
		return
	if not fighting():
		server.chat.say("Стрелять не по кому: целей нет.")
		return
	var fired := 0
	for i in charge.size():
		if not ((which == 255 or which == i) and charge[i] >= 1.0 and ship.armed[i] == 1 and not ship.broken.has(map.guns[i]) \
				and not jammed(map.guns[i]) and beam_left[i] == 0):
			continue
		var w: int = ship.mounts[i]
		var ammo := Weapons.ammo(w)
		if ammo != 0:
			if int(ship.store.get(ammo, 0)) <= 0:
				server.chat.tell(p, "Орудие %d: нет ракет в трюме (%s)." % [i + 1, Weapons.name_of(w).to_lower()])
				continue
			ship.store[ammo] -= 1
			server.supplies.tell_store()
		charge[i] = 0.0
		fired += 1
		if Weapons.klass(w) == Weapons.CLASS_BEAM or Weapons.klass(w) == Weapons.CLASS_SIPHON:
			beam_left[i] = Weapons.BEAM_PULSES if Weapons.klass(w) == Weapons.CLASS_BEAM else Weapons.SIPHON_PULSES
			_beam_next[i] = server.tick
			_beam_room[i] = _rng.randi_range(0, Net.ESYS_COUNT - 1)
			_beam_log[i] = [0, 0, PackedStringArray()]        # pulses that burned, pulses the shield stopped, what came of it
			_beam_pulse(i)
		elif Weapons.klass(w) == Weapons.CLASS_TRACTOR:
			_tractor(i, w)
		else:
			_our_volley(i, w)
		if not fighting() or _settle():
			break
	if fired > 0:
		_settle()


func _settle() -> bool:
	## After our hits: is it wrecked, or is its boarding party dead? True if the fight is over.
	if enemy_hull <= 0 and systems.size() > 0:
		_wrecked()
		return true
	if systems.size() > 0 and enemy_hull > 0 and systems[Net.ESYS_CREW] == 0:
		if raid:
			_wrecked()                       # nobody left alive aboard: it drifts, a dead hulk
		else:
			_broken_off()
		return true
	return false


func _broken_off() -> void:
	## Its boarding party is dead: with nobody to send over it gives up and goes.
	enemy_hull = 0
	beam_left.fill(0)
	server.derelict.pirates_wrecked()
	server.chat.say("Абордажная команда пиратов перебита! Пиратский корабль прекращает атаку и уходит.")


func _hit_chance(w: int) -> float:
	## Ours: better while its bridge is out (it cannot dodge) and while our tractor beam holds it.
	var hit := float(Weapons.info(w)["hit"])
	var bonus := (Weapons.BLIND_BONUS if down(Net.ESYS_HELM) else 0.0) + (Weapons.TRACTOR_BONUS if held() else 0.0)
	if bonus > 0.0:
		hit = maxf(hit, minf(hit + bonus, Weapons.BEST_HIT))
	return hit


func _tractor(i: int, w: int) -> void:
	## The tractor beam: it never misses; unless the shield stops it, it holds the ship.
	var map = server.map
	var cell: int = map.guns[i]
	var at := Vector2(cell % map.width, cell / map.width)
	server.combat.tell_shot(Net.SHOT_TRACTOR, true, at, at + Vector2(_outward(cell)) * 12.0, int(at.y))
	if _meets_shield(w, false) and _enemy_shield_up() and _rng.randf() >= Weapons.through_chance(enemy_shield):
		enemy_shield = maxf(enemy_shield - Weapons.shield_damage(w), 0.0)
		server.chat.say("Орудие %d (захватный луч): щит пиратов не пустил луч.%s" % [i + 1, _enemy_state()])
		return
	var hold := float(Weapons.info(w)["hold"]) if Weapons.info(w).has("hold") else Weapons.TRACTOR_HOLD
	held_until = maxi(held_until, server.tick + roundi(hold * Net.TICK_HZ))
	server.chat.say("Орудие %d (захватный луч): пиратский корабль схвачен на %d с: не уклоняется, не уходит прыжком и не подходит к шлюзу.%s" % [
		i + 1, int(hold), _enemy_state()])


func _our_volley(i: int, w: int) -> void:
	## One gun's shot (or burst) at the enemy, told in one line.
	var map = server.map
	var cell: int = map.guns[i]
	var x: int = cell % map.width
	var y: int = cell / map.width
	var out := _outward(cell)
	server.chat.sound(Net.SOUND_SHOT, x, y)
	var shots: int = Weapons.info(w)["shots"]
	var misses := 0
	var stopped := 0
	var hits := PackedStringArray()
	var said := PackedStringArray()
	for s in shots:
		var hit := _rng.randf() < _hit_chance(w)
		var spread := Vector2(out).orthogonal() * (s - shots / 2.0) * 0.6
		server.combat.tell_shot(_shot_kind(w), hit, Vector2(x, y), Vector2(x, y) + Vector2(out) * 12.0 + spread, y)
		if not hit:
			misses += 1
			continue
		var room := aim if aim != Net.AIM_ANY else _rng.randi_range(0, Net.ESYS_COUNT - 1)
		var r := _land_on_enemy(w, room)
		if r == "":
			stopped += 1
		else:
			hits.append(Net.ESYS_NAMES[room].to_lower())
			if r != "+":
				said.append(r)
		if enemy_hull <= 0 or (systems.size() > Net.ESYS_CREW and systems[Net.ESYS_CREW] == 0):
			break
	var parts := PackedStringArray()
	if not hits.is_empty():
		parts.append(("попадание: " if hits.size() == 1 else "попадания (%d): " % hits.size()) + ", ".join(_unique(hits)))
	if stopped > 0:
		parts.append("щит остановил" + ("" if stopped == 1 else " %d" % stopped))
	if misses > 0:
		parts.append("промах" + ("" if misses == 1 else " ×%d" % misses))
	server.chat.say("Орудие %d (%s): %s.%s%s" % [i + 1, Weapons.name_of(w).to_lower(), "; ".join(parts),
		"" if said.is_empty() else " " + " ".join(_unique(said)), _enemy_state()])


func _beam_pulse(i: int) -> void:
	## A cutting beam burns a second more: never a miss, the shield permitting.
	var map = server.map
	if not fighting():
		beam_left[i] = 0
		return
	var w: int = server.ship.mounts[i]
	if Weapons.klass(w) == Weapons.CLASS_SIPHON:
		_siphon_pulse(i)
		return
	var cell: int = map.guns[i]
	var at := Vector2(cell % map.width, cell / map.width)
	server.combat.tell_shot(Net.SHOT_BEAM, true, at, at + Vector2(_outward(cell)) * 12.0, int(at.y))
	var room := aim if aim != Net.AIM_ANY else _beam_room[i]
	var r := _land_on_enemy(w, room)
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
			parts.append("прожёг %d раз (%s)" % [log[0], Net.ESYS_NAMES[room].to_lower()])
		if log[1] > 0:
			parts.append("щит не пустил %d раз" % log[1])
		server.chat.say("Орудие %d (резак): %s.%s%s" % [i + 1, ", ".join(parts),
			"" if (log[2] as PackedStringArray).is_empty() else " " + " ".join(_unique(log[2])), _enemy_state()])
	if fighting():
		_settle()


func _siphon_pulse(i: int) -> void:
	## A siphon beam drinks a second more of the enemy's shield and pours it into ours.
	var map = server.map
	var ship = server.ship
	var cell: int = map.guns[i]
	var at := Vector2(cell % map.width, cell / map.width)
	server.combat.tell_shot(Net.SHOT_SIPHON, true, at, at + Vector2(_outward(cell)) * 12.0, int(at.y))
	var log: Array = _beam_log[i]
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
			what = "у пиратов нет щита, тянуть нечего."
		else:
			what = "вытянул из щита пиратов %d, нашему щиту %s." % [roundi(log[0]),
				("+%d" % roundi(log[1])) if log[1] > 0.0 else "ничего (генератор не работает или щит полон)"]
		server.chat.say("Орудие %d (сифон): %s%s" % [i + 1, what, _enemy_state()])


func _enemy_state() -> String:
	if enemy_hull <= 0:
		return ""
	var s := " Корпус пиратов: %d из %d." % [enemy_hull, ENEMY_HULL]
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
	match Weapons.klass(w):
		Weapons.CLASS_ION:
			return Net.SHOT_ION
		Weapons.CLASS_ROCKET:
			return Net.SHOT_ROCKET
		Weapons.CLASS_BLASTER:
			return Net.SHOT_PLASMA
		Weapons.CLASS_BEAM:
			return Net.SHOT_BEAM
	return Net.SHOT_CANNON


func _meets_shield(w: int, hardened: bool) -> bool:
	## Does this shot have to get through the shield at all?
	match Weapons.klass(w):
		Weapons.CLASS_ROCKET:
			return hardened
		Weapons.CLASS_BLASTER:
			return _rng.randf() >= Weapons.BLASTER_SLIP
	return true


func _land_on_enemy(w: int, room: int) -> String:
	## A shot of ours that found the enemy. "" = its shield stopped it; otherwise
	## it got through: "+" when there is nothing to tell, else what came of it.
	if _meets_shield(w, false) and _enemy_shield_up() and _rng.randf() >= Weapons.through_chance(enemy_shield):
		enemy_shield = maxf(enemy_shield - Weapons.shield_damage(w), 0.0)
		return ""
	var info := Weapons.info(w)
	if info.has("disable"):
		# ion and EMP: the system there stops for a while; no damage
		if room < systems_out.size():
			systems_out[room] = maxi(systems_out[room], server.tick + roundi(float(info["disable"]) * Net.TICK_HZ))
			if room == Net.ESYS_SHIELDS and systems_full[room] > 0:
				return "Щит пиратов выключен на %d с." % int(info["disable"])
			return "%s пиратов выключено на %d с." % [Net.ESYS_NAMES[room], int(info["disable"])]
		return "+"
	var damage: int = info["damage"]
	enemy_hull -= damage
	if Weapons.klass(w) != Weapons.CLASS_ROCKET or _rng.randf() < Weapons.ROCKET_HOLE:
		_hole_near(room)
	if room >= systems.size() or systems[room] == 0:
		return "+"
	var was: int = systems[room]
	systems[room] = maxi(was - damage, 0)
	if room == Net.ESYS_CREW:
		var left := boarders_left()
		if left < server.derelict._pirates_party:
			server.derelict._pirates_party = left
			return ("Убит пират из экипажа, осталось %d." if raid else "Убит абордажник, осталось %d.") % left
		return "Пираты в кубрике ранены." if raid else "Абордажники ранены."
	if systems[room] == 0:
		if room == Net.ESYS_SHIELDS:
			enemy_shield = 0.0
		var what := "Выведено из строя: %s. %s" % [Net.ESYS_NAMES[room].to_lower(), DOWN_TEXT[room]]
		if fleeing() and (room == Net.ESYS_ENGINE or room == Net.ESYS_JUMP):
			what += " Прыжок сорван, пока не починят."
		return what
	if room == Net.ESYS_JUMP and fleeing():
		return "Гипердвигатель повреждён: прыжок заряжается медленнее, ещё %d с." % jump_seconds_left()
	return "+"


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
	var order: Array = [Net.ESYS_JUMP, Net.ESYS_ENGINE, Net.ESYS_WEAPONS, Net.ESYS_SHIELDS, Net.ESYS_HELM] if fleeing() \
		else [Net.ESYS_WEAPONS, Net.ESYS_SHIELDS, Net.ESYS_HELM, Net.ESYS_ENGINE, Net.ESYS_JUMP]
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
	beam_left.fill(0)
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


# ---------------------------------------------------------------- the enemy's guns

func _enemy_fires(w: int) -> void:
	## A shot (or burst) of one of the pirate ship's guns. It goes for our guns
	## while one of them works (and all the more while it runs, to cover its
	## escape); otherwise it holes the hull, as near the crew as it can, or now
	## and then hits a bridge console or the shield generator. Our shield stops
	## what it can; ion and EMP that get through put a gun or the shield out for
	## a few seconds.
	var map = server.map
	var ship = server.ship
	var shots: int = Weapons.info(w)["shots"]
	var chance: float = float(Weapons.info(w)["hit"]) if enemy_hit_chance < 0.0 else enemy_hit_chance
	if down(Net.ESYS_HELM):
		chance *= BLIND_ENEMY_HIT
	var misses := 0
	var stopped := 0
	var said := PackedStringArray()
	for s in shots:
		if _rng.randf() >= chance:
			misses += 1
			continue
		var target := _enemy_target()
		if _meets_shield(w, ship.hardened) and our_shield_up() and _rng.randf() >= Weapons.through_chance(ship.shield):
			ship.shield = maxf(ship.shield - Weapons.shield_damage(w), 0.0)
			stopped += 1
			_tracer_to(target if target >= 0 else _hull_near_crew(), _shot_kind(w), false)
			continue
		var info := Weapons.info(w)
		if info.has("disable"):
			# ion and EMP: a gun or the shield stops for a while, no damage
			var what := target if target >= 0 and (map.guns.has(target) or target == shield_cell()) else _jam_choice()
			if what >= 0:
				ship.jammed[what] = maxi(int(ship.jammed.get(what, 0)), server.tick + roundi(float(info["disable"]) * Net.TICK_HZ))
				_tracer_to(what, _shot_kind(w), true)
				said.append("%s выключено на %d с." % [_cap(map.device_name(what)), int(info["disable"])])
			continue
		var damage: int = info["damage"]
		if target >= 0:
			# a gun, a console or the shield generator put out of order
			ship.broken[target] = true
			server.to_all(ship.devices_packet())
			server.crew.hull_hit(Net.HULL_PER_SYSTEM_HIT * damage)
			_tracer_to(target, _shot_kind(w), true)
			said.append("Не работает: %s." % map.device_name(target))
			continue
		var c := target if target >= 0 else _hull_near_crew()
		if c < 0:
			continue
		_tracer_to(c, _shot_kind(w), true)
		if Weapons.klass(w) != Weapons.CLASS_ROCKET or _rng.randf() < Weapons.ROCKET_HOLE:
			said.append("Обшивка пробита.")
			if server.systems.breach(c):
				server.crew.hull_hit(Net.HULL_PER_HOLE * (damage - 1))
			else:
				server.crew.hull_hit(Net.HULL_PER_HOLE * damage)
		else:
			server.crew.hull_hit(Net.HULL_PER_HOLE * damage)
			said.append("Ракета разорвалась на обшивке: прочность %d из %d." % [ship.hull, Net.HULL_MAX])
	var parts := PackedStringArray()
	if stopped > 0:
		parts.append("щит отразил" + ("" if stopped == 1 else " %d" % stopped) + " (щит %d)" % roundi(ship.shield))
	if misses > 0:
		parts.append("мимо" + ("" if misses == 1 else " ×%d" % misses))
	if parts.is_empty() and said.is_empty():
		return
	server.chat.say("Пираты стреляют (%s)%s%s" % [Weapons.name_of(w).to_lower(), (": " + ", ".join(parts) + ".") if not parts.is_empty() else ".",
		"" if said.is_empty() else " Попадание! " + " ".join(said)])


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
	var at_guns := 0.0 if guns.is_empty() else AIM_GUNS + (0.2 if fleeing() else 0.0)
	var devices := PackedInt32Array()
	if server.systems.can_break("console"):
		for c: int in map.chart.keys() + map.helm.keys():
			devices.append(c)
	var gen := shield_cell()
	if gen >= 0 and not server.ship.broken.has(gen):
		devices.append(gen)
		devices.append(gen)              # it knows what keeps its shots off
	var roll := _rng.randf()
	if roll < at_guns:
		return guns[_rng.randi_range(0, guns.size() - 1)]
	if roll < at_guns + (1.0 - at_guns) * (1.0 - ENEMY_BREACH_SHARE) and not devices.is_empty():
		return devices[_rng.randi_range(0, devices.size() - 1)]
	return -1


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


func _tracer_to(cell: int, kind: int = Net.SHOT_CANNON, landed: bool = true) -> void:
	## Draws its shot coming in from space at a cell of our ship (short of it, if the shield stopped it).
	if cell < 0:
		return
	var map = server.map
	var at := Vector2(cell % map.width, cell / map.width)
	var out := Vector2(_outward(cell))
	server.combat.tell_shot(kind, landed, at + out * 12.0, at if landed else at + out * 2.5, int(at.y))
	if landed:
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
