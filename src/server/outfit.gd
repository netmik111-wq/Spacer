extends RefCounted
## (v59, the author's tiers plan, part 2) The ship's gear: what its systems'
## tiers and the modules in its bay do, and an engineer installing them. Server only.
##
## A crate of gear (see Gear) is carried in a hand to where it goes: a system's
## crate to its machine (the shield generator; the reactor and the engine both
## to the engine; the sensors to a holomap), a module to the module bay ('U' in
## the map). Facing it with the crate in hand, an engineer holds "use" for
## Gear.INSTALL_SECONDS (the repair skill makes it up to twice as quick); the
## crate goes in, and what it replaces comes out into the hand (a built-in
## system leaves nothing: it is part of the ship). With empty hands at the bay
## an engineer takes the last module out the same way. Only an engineer may do
## it (the author's word for the workbench, kept for gear). A broken machine is
## mended first: holding "use" on it mends it, as before.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Player := preload("res://src/server/player.gd")

const NOT_HERE := "-"                # can(): the thing ahead is not where that crate (or empty hands) does anything

var server: GameServer
var _told := PackedByteArray()


func setup(p_server: GameServer) -> void:
	server = p_server
	_told = PackedByteArray()
	refresh()


# ---------------------------------------------------------------- what the gear does

func tier(sys: int) -> int:
	return clampi(server.ship.gear[sys], 1, 3) if sys < server.ship.gear.size() else 1


func reactor() -> int:
	## Power the reactor gives the guns and the shield.
	return Gear.REACTOR_POWER[tier(Gear.SYS_REACTOR)]


func shield_regen() -> float:
	return Gear.SHIELD_REGEN[tier(Gear.SYS_SHIELD)]


func hardened() -> bool:
	## Does our shield stop rockets too (the top generator, or the hardening bought before v59)?
	return server.ship.hardened or tier(Gear.SYS_SHIELD) >= 3


func dodge_bonus() -> float:
	return Gear.ENGINE_DODGE[tier(Gear.SYS_ENGINE)]


func jump_share() -> float:
	## Of a jump's charge and the drive's rest after it.
	return Gear.ENGINE_JUMP[tier(Gear.SYS_ENGINE)]


func free_fuel() -> float:
	return Gear.ENGINE_FREE_FUEL[tier(Gear.SYS_ENGINE)]


func scan_seconds() -> float:
	return Gear.SENSOR_SECONDS[tier(Gear.SYS_SENSORS)]


func sees_charge() -> bool:
	## The top sensors show the pirates' guns charging on the gun console.
	return tier(Gear.SYS_SENSORS) >= 3


func armour_tier() -> int:
	return Gear.armour_tier(server.ship.modules)


func hull_share() -> float:
	## Of the hull's strength a pirate hit takes, against no armour.
	return Gear.ARMOUR_HULL[armour_tier()]


func no_hole() -> float:
	return Gear.ARMOUR_NO_HOLE[armour_tier()]


func focus() -> bool:
	return Gear.has_module(server.ship.modules, Gear.MOD_FOCUS)


func phase() -> bool:
	return Gear.has_module(server.ship.modules, Gear.MOD_PHASE)


func phase_ready() -> bool:
	return phase() and server.tick >= server.ship.phase_ready


func phase_used() -> void:
	server.ship.phase_ready = server.tick + roundi(Gear.PHASE_SECONDS * Net.TICK_HZ)


func refresh() -> void:
	## After the gear changed: the armour's share of ricochets, and guns cut if the
	## reactor no longer feeds them all (a weaker one went in).
	var ship = server.ship
	ship.armour = Gear.ARMOUR_RICOCHET[armour_tier()]
	if server.gunnery == null or ship.mounts.is_empty():
		return
	for i in range(ship.mounts.size() - 1, -1, -1):
		if server.gunnery.power_used() <= reactor():
			break
		if ship.armed[i] == 1:
			ship.armed[i] = 0
			server.gunnery.charge[i] = 0.0
	if server.gunnery.power_used() > reactor() and ship.guard_armed:
		ship.guard_armed = false
	if server.gunnery.power_used() > reactor() and ship.shield_on:
		ship.shield_on = false
		ship.shield = 0.0


# ---------------------------------------------------------------- installing

func _machines(sys: int) -> Dictionary:
	var map := server.map
	match sys:
		Gear.SYS_SHIELD:
			return map.shield
		Gear.SYS_REACTOR, Gear.SYS_ENGINE:
			return map.engine
		Gear.SYS_SENSORS:
			return map.holo
	return {}


func _slot_for(g: int) -> int:
	## The bay's slot a module goes into: the one with a module of its sort (it is
	## swapped), else a free one; -1 if both hold modules of other sorts.
	var mods: PackedByteArray = server.ship.modules
	for i in mods.size():
		if mods[i] != Gear.NONE and Gear.module_of(mods[i]) == Gear.module_of(g):
			return i
	return mods.find(Gear.NONE)


func _last_module() -> int:
	var mods: PackedByteArray = server.ship.modules
	for i in range(mods.size() - 1, -1, -1):
		if mods[i] != Gear.NONE:
			return i
	return -1


func can(p: Player, cell: int) -> String:
	## "" if `p` may install the crate in its hand at that wall cell (or, with empty
	## hands at the module bay, take a module out); NOT_HERE if that cell is not
	## the place for it; otherwise why not, in the player's words.
	if cell < 0:
		return NOT_HERE
	var g := Items.gear_of(p.in_hand())
	var ship = server.ship
	if g != Gear.NONE:
		var sys := Gear.system_of(g)
		if sys >= 0:
			if not _machines(sys).has(cell):
				return NOT_HERE
			if tier(sys) == Gear.tier(g):
				return "Это уже установлено: %s." % Gear.name_of(g).to_lower()
		else:
			if not server.map.bay.has(cell):
				return NOT_HERE
			if ship.modules.has(g):
				return "Этот модуль уже стоит в стойке."
			if _slot_for(g) < 0:
				return "Обе ячейки стойки заняты: сначала выньте модуль (держите E с пустыми руками)."
	elif p.in_hand() == Net.ITEM_NONE and server.map.bay.has(cell):
		if _last_module() < 0:
			return "Модульная стойка пуста: модули в ящиках носят из шкафа снабжения."
	else:
		return NOT_HERE
	if p.job != Net.JOB_ENGINEER:
		return "Корабельные модули ставят и снимают только инженеры."
	return ""


func ticks(p: Player) -> int:
	var seconds := Gear.REMOVE_SECONDS if p.in_hand() == Net.ITEM_NONE else Gear.INSTALL_SECONDS
	return roundi(seconds * Net.TICK_HZ * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)))


func finish(p: Player, cell: int) -> void:
	## The work at that cell is done (see Repairs.update): the crate goes in.
	if can(p, cell) != "":
		return
	var ship = server.ship
	var g := Items.gear_of(p.in_hand())
	p.train(Net.SKILL_REPAIR)
	if g == Gear.NONE:
		var at := _last_module()
		var out: int = ship.modules[at]
		ship.modules[at] = Gear.NONE
		p.slots[p.hand] = Gear.item_of(out)
		server.chat.say("%s вынимает из модульной стойки: %s." % [p.name, Gear.name_of(out).to_lower()])
	elif Gear.system_of(g) >= 0:
		var sys := Gear.system_of(g)
		var old := tier(sys)
		ship.gear[sys] = Gear.tier(g)
		var out := Gear.for_system(sys, old)
		p.slots[p.hand] = Gear.item_of(out) if out != Gear.NONE else Net.ITEM_NONE
		server.chat.say("%s устанавливает: %s.%s" % [p.name, Gear.name_of(g).to_lower(),
			(" Снятое (%s) — в руках." % Gear.name_of(out).to_lower()) if out != Gear.NONE else ""])
	else:
		var at := _slot_for(g)
		var out: int = ship.modules[at]
		ship.modules[at] = g
		p.slots[p.hand] = Gear.item_of(out) if out != Gear.NONE else Net.ITEM_NONE
		server.chat.say("%s ставит в модульную стойку: %s.%s" % [p.name, Gear.name_of(g).to_lower(),
			(" Снятое (%s) — в руках." % Gear.name_of(out).to_lower()) if out != Gear.NONE else ""])
	refresh()
	tick()


# ---------------------------------------------------------------- loot and the flagship

func loot(far: int, rng: RandomNumberGenerator, higher: bool = false) -> int:
	## A crate found this far out (the thing).
	return Gear.item_of(Gear.roll(far, rng, higher))


func tier_points() -> int:
	## (v59) Of our gear, as the flagship counts it: each system of tier 2 counts 1,
	## of tier 3 counts 2; armour the same; the focusing array and the phase drive 1.
	var n := 0
	for sys in Gear.SYSTEMS:
		n += tier(sys) - 1
	for g in server.ship.modules:
		if g != Gear.NONE:
			n += maxi(Gear.tier(g) - 1, 1) if Gear.module_of(g) != Gear.MOD_ARMOUR else Gear.tier(g) - 1
	return n


# ---------------------------------------------------------------- telling

func packet() -> PackedByteArray:
	var ship = server.ship
	var out := PackedByteArray([Net.S_GEAR, ship.id & 0xFF, ship.id >> 8, Gear.SYSTEMS])
	for sys in Gear.SYSTEMS:
		out.append(tier(sys))
	out.append(ship.modules.size())
	out.append_array(ship.modules)
	out.append(clampi(int(ceil(float(ship.phase_ready - server.tick) / Net.TICK_HZ)), 0, 255) if phase() else 0)
	out.append(Net.GEARF_HARDENED if hardened() else 0)
	return out


func tick() -> void:
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)
