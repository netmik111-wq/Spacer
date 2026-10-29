extends RefCounted
## (v59, the author's tiers plan, part 2) The ship's gear: what its systems'
## tiers and the modules in its bay do, and an engineer installing them. Server only.
##
## A crate of gear (see Gear) is carried in a hand to where it goes: a system's
## crate to its machine (the shield generator; the reactor and the engine both
## to the engine; the sensors to a holomap; v61: the coils to the SMES), a module to the module bay ('U' in
## the map). Facing it with the crate in hand, an engineer holds "use" for
## Gear.INSTALL_SECONDS (the repair skill makes it up to twice as quick); the
## crate goes in, and what it replaces comes out into the hand (a built-in
## system leaves nothing: it is part of the ship). With empty hands at the bay
## an engineer takes the last module out the same way. Only an engineer may do
## it (the author's word for the workbench, kept for gear). A broken machine is
## mended first: holding "use" on it mends it, as before.
##
## (v62, the author's K2 and K3) Four passive modules more (the jump jammer,
## the welding drone, the salvage arm, the auto-loader), and the bay's
## extender: installed at the bay like a module, it is used up and gives the
## bay a third slot for good.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Items := preload("res://src/shared/items.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Player := preload("res://src/server/player.gd")

const CUT_SHIELD := -2               # (v89) in Ship.cut: the shield; sorted first, so it comes back first
const CUT_GUARD := -1                # (v89) in Ship.cut: the point defence
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


func jump_fuel(long_jump: bool = false) -> int:
	## (v67) Fuel a lane jump burns, by the engine's tier; the long jump out of a cluster twice that.
	return Gear.JUMP_FUEL[tier(Gear.SYS_ENGINE)] * (Sectors.EXIT_FUEL if long_jump else 1)


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


func jump_jam() -> float:
	## (v62) Of the pace the enemy's escape jump charges at (the jump jammer slows it).
	return Gear.JAMMER_SHARE if Gear.has_module(server.ship.modules, Gear.MOD_JAMMER) else 1.0


func welder() -> int:
	## (v62) Hull strength the welding drone mends after a jump (0: none in the bay).
	return Gear.WELDER_HULL if Gear.has_module(server.ship.modules, Gear.MOD_WELDER) else 0


func salvage_share() -> float:
	return Gear.SALVAGE_SHARE if Gear.has_module(server.ship.modules, Gear.MOD_SALVAGE) else 1.0


func salvage_parts() -> int:
	return Gear.SALVAGE_PARTS if Gear.has_module(server.ship.modules, Gear.MOD_SALVAGE) else 0


func loader() -> float:
	## (v62) How much faster a gun with nobody at it charges (the auto-loader).
	return Gear.LOADER_PACE if Gear.has_module(server.ship.modules, Gear.MOD_LOADER) else 1.0


func jumped() -> void:
	## (v62) After every jump: the welding drone mends the hull.
	var n := welder()
	if n <= 0 or server.ship.hull >= server.ship.hull_max:
		return
	var was: int = server.ship.hull
	server.ship.hull = mini(server.ship.hull + n, server.ship.hull_max)
	server.chat.say("Сварочный дрон прошёл по обшивке после прыжка: прочность %d из %d (+%d)." % [server.ship.hull, server.ship.hull_max, server.ship.hull - was])


func phase_used() -> void:
	server.ship.phase_ready = server.tick + roundi(Gear.PHASE_SECONDS * Net.TICK_HZ)


func refresh() -> void:
	## After the gear changed: the armour's share of ricochets, the SMES's coils, and
	## guns cut if the power no longer feeds them all (a weaker reactor went in).
	var ship = server.ship
	ship.armour = Gear.ARMOUR_RICOCHET[armour_tier()]
	ship.jump_cost = jump_fuel()             # (v67)
	if server.power != null:
		server.power.coils_changed()
	fit_power()


func fit_power() -> bool:
	## (v61) Guns switched off, last mount first, then the point defence and the shield,
	## while they draw more than the power there is now (Power.budget). True if any was.
	var ship = server.ship
	if server.gunnery == null or ship.mounts.is_empty() or server.power == null:
		return false
	var budget: int = server.power.budget()
	var cut := false
	while server.power.engines > 0 and server.gunnery.power_used() > budget:
		server.power.engines -= 1            # (v68) the engines' power goes first
		cut = true
	for i in range(ship.mounts.size() - 1, -1, -1):
		if server.gunnery.power_used() <= budget:
			break
		if ship.armed[i] == 1:
			ship.armed[i] = 0
			server.gunnery.charge[i] = 0.0
			_was_cut(i)
			cut = true
	if server.gunnery.power_used() > budget and ship.guard_armed:
		ship.guard_armed = false
		_was_cut(CUT_GUARD)
		cut = true
	if server.gunnery.power_used() > budget and ship.shield_on:
		ship.shield_on = false
		ship.shield = 0.0
		_was_cut(CUT_SHIELD)
		cut = true
	return cut


func _was_cut(what: int) -> void:
	if not server.ship.cut.has(what):
		server.ship.cut.append(what)


func restore_power() -> String:
	## (v89, his note: after an ion storm or a teleported raid the guns stayed off and the crew
	## could not tell how to bring them back) What a shortage switched off comes back on by itself,
	## the shield first, then the guns in their order, as soon as the power is there again.
	## Returns the names of what came back ("" for none).
	var ship = server.ship
	var g = server.gunnery
	if ship.cut.is_empty() or g == null or server.power == null or not server.powered():
		return ""
	var back := PackedStringArray()
	ship.cut.sort()
	for what: int in ship.cut.duplicate():
		var need := 0
		if what == CUT_SHIELD:
			need = Weapons.SHIELD_POWER if not ship.shield_on else 0
		elif what == CUT_GUARD:
			need = Weapons.power(ship.guard) if ship.guard != Weapons.NONE and not ship.guard_armed else 0
		elif what < ship.mounts.size() and ship.mounts[what] != Weapons.NONE and ship.armed[what] == 0:
			need = Weapons.power(ship.mounts[what])
		else:
			ship.cut.erase(what)               # taken down or already on
			continue
		if need == 0:
			ship.cut.erase(what)
			continue
		if g.power_used() + need > server.power.budget():
			continue
		ship.cut.erase(what)
		if what == CUT_SHIELD:
			ship.shield_on = true
			back.append("щит")
		elif what == CUT_GUARD:
			ship.guard_armed = true
			back.append(Weapons.name_of(ship.guard))
		else:
			ship.armed[what] = 1
			back.append(Weapons.name_of(ship.mounts[what]))
	return ", ".join(back)


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
		Gear.SYS_COILS:
			return map.smes
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
	if g == Gear.TELEPORT:
		# (v97, his T1 C) the teleporter goes into its pad
		if not server.map.teleporter.has(cell):
			return NOT_HERE
		if ship.teleporter:
			return "Телепорт уже стоит в платформе."
	elif g != Gear.NONE:
		var sys := Gear.system_of(g)
		if sys >= 0:
			if not _machines(sys).has(cell):
				return NOT_HERE
			if tier(sys) == Gear.tier(g):
				return "Это уже установлено: %s." % Gear.name_of(g).to_lower()
		else:
			if not server.map.bay.has(cell):
				return NOT_HERE
			if Gear.extender(g):
				if ship.modules.size() >= Gear.MODULE_SLOTS_MAX:
					return "Стойка уже расширена: третья ячейка на месте."
			elif ship.modules.has(g):
				return "Этот модуль уже стоит в стойке."
			elif _slot_for(g) < 0:
				return "Все ячейки стойки заняты: сначала выньте модуль (держите E с пустыми руками)."
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
	if g == Gear.TELEPORT:
		ship.teleporter = true
		p.slots[p.hand] = Net.ITEM_NONE
		server.chat.say("%s устанавливает телепорт в платформу. E у платформы — отправить тех, кто рядом, на корабль у борта." % p.name)
	elif g == Gear.NONE:
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
	elif Gear.extender(g):
		ship.modules.append(Gear.NONE)       # (v62) a third slot, for good: the extender is used up
		p.slots[p.hand] = Net.ITEM_NONE
		server.chat.say("%s расширяет модульную стойку: теперь в ней %d ячейки." % [p.name, ship.modules.size()])
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
