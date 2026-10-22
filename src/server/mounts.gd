extends RefCounted
## (v60, the author's "crew at work") The gun mounts in the hull ('T' in the map)
## as places where people work. Server only.
##
## A gunner: whoever stands facing a mount from inside its gun bay while the ship
## has power makes that gun charge faster (MOUNT_PACE, more with the gunnery
## skill, up to MOUNT_SKILL_PACE more), and learns gunnery with every shot it
## fires. A gun with nobody at it charges as before (the author's W1: a bonus,
## so that a small crew can still fight).
##
## Guns are carried (the author's N1: bots carry guns from storage and mount
## them). A ship gun is a thing taken from the supply locker; facing a mount
## with it in hand, anybody holds "use" for MOUNT_SECONDS (the repair skill
## makes it up to twice as quick) and it goes up, and the gun that was there
## comes down into the hand, to be carried back to the locker. With empty hands
## at a mounted gun the same hold (UNMOUNT_SECONDS) takes it down. The gun
## console no longer swaps guns by itself: it gives the order (`order`), which
## bots on "work" carry out (see Stations) and anybody else may. The point
## defence has no place in the hull, so it is still set from the console.
##
## (v68, the author's F3: "a loaded mount fires faster, an empty one still takes from
## the locker") A gun that fires shells or rockets can be fed by hand: facing its
## mount with the right round in hand, hold "use" LOAD_SECONDS and it goes into the
## breech (LOAD_MAX at most). While it holds a round the gun charges LOADED_PACE
## faster, and it fires the loaded round before taking one from the locker.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Player := preload("res://src/server/player.gd")

const MOUNT_PACE := 0.25             # a gun with a gunner at it charges this much faster (the author's W1)...
const MOUNT_SKILL_PACE := 0.25       # ... and this much more again with the best gunnery skill
const MOUNT_SECONDS := 8.0           # to put a carried gun up on its mount
const UNMOUNT_SECONDS := 5.0         # to take one down into the hands
const LOAD_SECONDS := 2.0            # (v68) to push one round into a mount's breech
const LOAD_MAX := 4                  # rounds a mount's breech holds
const LOADED_PACE := 1.3             # a gun with a round loaded by hand charges this much faster
const WANT_NONE := 0                 # no order for that mount
const WANT_DOWN := 255               # the order: take its gun down into the locker
const NOT_HERE := "-"                # can(): not a mount, or nothing to do at it with what is in hand

var server: GameServer
var gunners: Array = []              # per mount: the Player at it now, or null
var wanted := PackedByteArray()      # per mount: the gun (a thing) the console ordered onto it, WANT_NONE or WANT_DOWN
var loaded := PackedByteArray()      # (v68) per mount: rounds loaded into its breech by hand
var _told := PackedByteArray()


func setup(p_server: GameServer) -> void:
	server = p_server
	gunners = []
	gunners.resize(server.map.guns.size())
	wanted = PackedByteArray()
	wanted.resize(server.map.guns.size())
	loaded = PackedByteArray()
	loaded.resize(server.map.guns.size())
	_told = PackedByteArray()


# ---------------------------------------------------------------- gunners

func _scan() -> void:
	gunners.fill(null)
	if not server.powered():
		return
	var map := server.map
	for p: Player in server.players:
		if p == null or p.pirate or p.ally or p.corpse or p.cond != Net.COND_OK or p.st.cd > 0:
			continue
		var i := map.guns.find(map.use_ahead(p.st.x, p.st.y, p.st.facing))
		if i >= 0 and gunners[i] == null:
			gunners[i] = p


func gunner(i: int) -> Player:
	return gunners[i] if i >= 0 and i < gunners.size() else null


func pace(i: int) -> float:
	## How much faster that gun charges for its gunner (1 = nobody at it).
	var p := gunner(i)
	var fed := LOADED_PACE if i >= 0 and i < loaded.size() and loaded[i] > 0 else 1.0   # (v68) loaded by hand
	if p == null:
		return server.outfit.loader() * fed  # (v62) the auto-loader stands in for nobody
	return (1.0 + (MOUNT_PACE + MOUNT_SKILL_PACE * p.skill(Net.SKILL_GUNS)) * server.stations.share(p)) * fed   # (v70) a bot, half


func ammo_of(i: int) -> int:
	## (v68) The round the gun on that mount fires (Net.ITEM_SHELL, ITEM_ROCKET...), 0 = none.
	var ship = server.ship
	return Weapons.ammo(ship.mounts[i]) if i >= 0 and i < ship.mounts.size() and ship.mounts[i] != Weapons.NONE else 0


func take_round(i: int) -> bool:
	## (v68) The gun on that mount fires: a round from its breech, else from the locker. False: none.
	var ship = server.ship
	var ammo := ammo_of(i)
	if ammo == 0:
		return true
	if loaded[i] > 0:
		loaded[i] -= 1
		return true
	if int(ship.store.get(ammo, 0)) <= 0:
		return false
	ship.store[ammo] -= 1
	server.supplies.tell_store()
	return true


func has_round(i: int) -> bool:
	var ammo := ammo_of(i)
	return ammo == 0 or loaded[i] > 0 or int(server.ship.store.get(ammo, 0)) > 0


func unload(i: int) -> void:
	## (v68) The gun comes down: what was in its breech goes back into the locker.
	var ammo := ammo_of(i)
	if ammo != 0 and loaded[i] > 0:
		server.ship.store[ammo] = int(server.ship.store.get(ammo, 0)) + loaded[i]
	loaded[i] = 0


func fired(i: int) -> void:
	## That gun fired: its gunner learns from it.
	var p := gunner(i)
	if p != null:
		p.train(Net.SKILL_GUNS)


# ---------------------------------------------------------------- carrying guns

static func _is_gun(item: int) -> bool:
	return item != Net.ITEM_NONE and Weapons.of_item(item) != Weapons.NONE


func can(p: Player, cell: int) -> String:
	## "" if `p` may put the gun in its hand up on the mount at that cell (or, with
	## empty hands, take down the gun on it); NOT_HERE if there is nothing of that
	## to do there; otherwise why not, in the player's words. GameClient.mount_here
	## gives the same answers.
	var i := server.map.guns.find(cell)
	if i < 0:
		return NOT_HERE
	var item := p.in_hand()
	var on: int = server.ship.mounts[i]
	if item != Net.ITEM_NONE and on != Weapons.NONE and item == Weapons.ammo(on):
		# (v68) a round for its breech
		if server.ship.broken.has(cell):
			return NOT_HERE
		if loaded[i] >= LOAD_MAX:
			return "Казённик орудия полон: %d из %d." % [loaded[i], LOAD_MAX]
		return ""
	if _is_gun(item):
		var w := Weapons.of_item(item)
		if w == Weapons.GUARD:
			return "«Заслон» ставят в его собственное гнездо с пульта орудий."
		if Weapons.damaged(item):
			return "Орудие повреждено: сначала его чинят на верстаке."
		if server.ship.broken.has(cell):
			return NOT_HERE                  # (mended first: holding "use" on it mends it)
		if p.bot and wanted[i] != item:
			return NOT_HERE                  # (v80) a bot puts up only the gun the console ordered there
		return ""
	if item == Net.ITEM_NONE and on != Weapons.NONE:
		if server.ship.broken.has(cell):
			return NOT_HERE
		if p.bot and wanted[i] != WANT_DOWN:
			# (v80, the author's note: "bots take the ship's guns without an order") a bot holding
			# "use" at a mount for anything else never takes its gun down
			return NOT_HERE
		if p.mended == cell:
			return NOT_HERE                  # (v80) the same hold that mended it does not go on to take it down
		return ""
	return NOT_HERE


func ticks(p: Player) -> int:
	if p.in_hand() != Net.ITEM_NONE and not _is_gun(p.in_hand()):
		return roundi(LOAD_SECONDS * Net.TICK_HZ)   # (v68) a round into the breech
	var seconds := UNMOUNT_SECONDS if p.in_hand() == Net.ITEM_NONE else MOUNT_SECONDS
	return roundi(seconds * Net.TICK_HZ * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)))


func finish(p: Player, cell: int) -> void:
	## The work at that mount is done (see Repairs.update): the gun goes up or comes down.
	if can(p, cell) != "":
		return
	var i := server.map.guns.find(cell)
	var ship = server.ship
	var g = server.gunnery
	var item := p.in_hand()
	if item != Net.ITEM_NONE and not _is_gun(item):
		# (v68) a round pushed into the breech
		loaded[i] += 1
		p.slots[p.hand] = Net.ITEM_NONE
		p.train(Net.SKILL_GUNS)
		server.chat.sound(Net.SOUND_LOAD, cell % server.map.width, cell / server.map.width, p.slot)
		server.usage.note(p, "load")       # (v82)
		server.chat.tell(p, "Орудие %d заряжено вручную: %d из %d. Оно заряжается быстрее." % [i + 1, loaded[i], LOAD_MAX])
		return
	unload(i)
	var old: int = ship.mounts[i]
	var old_fx: int = ship.mount_fx[i]
	var out := Weapons.item_of(old, old_fx) if old != Weapons.NONE else Net.ITEM_NONE
	if item == Net.ITEM_NONE:
		ship.mounts[i] = Weapons.NONE
		ship.mount_fx[i] = Weapons.FX_NONE
	else:
		ship.mounts[i] = Weapons.of_item(item)
		ship.mount_fx[i] = Weapons.fx_of(item)
	ship.armed[i] = 0
	g.charge[i] = 0.0
	g.beam_left[i] = 0
	p.slots[p.hand] = out
	p.train(Net.SKILL_REPAIR)
	if wanted[i] == WANT_DOWN and ship.mounts[i] == Weapons.NONE or wanted[i] != WANT_NONE and wanted[i] != WANT_DOWN \
			and Weapons.item_of(ship.mounts[i], ship.mount_fx[i]) == wanted[i]:
		wanted[i] = WANT_NONE
	if item == Net.ITEM_NONE:
		server.chat.say("%s снимает с орудия %d: %s. Его относят в шкаф снабжения." % [p.name, i + 1, Weapons.lower_name(old, old_fx)])
	else:
		server.chat.say("%s ставит на орудие %d: %s.%s Включите ему питание на пульте орудий." % [p.name, i + 1,
			Weapons.lower_name(ship.mounts[i], ship.mount_fx[i]),
			"" if old == Weapons.NONE else " Снятое (%s) — в руках." % Weapons.lower_name(old, old_fx)])
	server.supplies.tell_store()


func order(p: Player, i: int, item: int) -> void:
	## Somebody at the gun console orders a gun from the locker onto mount `i`, or
	## its gun down into the locker (ITEM_NONE). Carried out by hand (see above).
	var ship = server.ship
	if i < 0 or i >= ship.mounts.size():
		return
	var on := Weapons.item_of(ship.mounts[i], ship.mount_fx[i]) if ship.mounts[i] != Weapons.NONE else Net.ITEM_NONE
	if item == Net.ITEM_NONE:
		if on == Net.ITEM_NONE:
			wanted[i] = WANT_NONE
			return
		wanted[i] = WANT_DOWN
		server.chat.say("%s: «Орудие %d (%s) снять и убрать в шкаф снабжения»." % [p.name, i + 1, Weapons.lower_name(ship.mounts[i], ship.mount_fx[i])])
		return
	var w := Weapons.of_item(item)
	if w == Weapons.NONE or w == Weapons.GUARD or Weapons.damaged(item) or int(ship.store.get(item, 0)) <= 0:
		return
	if item == on:
		wanted[i] = WANT_NONE
		return
	if wanted[i] == item:
		wanted[i] = WANT_NONE                # the same order again takes it back
		server.chat.say("%s отменяет приказ по орудию %d." % [p.name, i + 1])
		return
	wanted[i] = item
	server.chat.say("%s: «На орудие %d — %s. Принести из шкафа снабжения и поставить»." % [p.name, i + 1, Items.name_of(item).to_lower()])


func order_for(item: int) -> int:
	## The mount an order is waiting for that gun at, or -1.
	for i in wanted.size():
		if wanted[i] == item and item != WANT_NONE and item != WANT_DOWN:
			return i
	return -1


# ---------------------------------------------------------------- every tick

func tick() -> void:
	_scan()
	var ship = server.ship
	for i in wanted.size():
		# an order nothing can carry out any more is dropped
		var want := wanted[i]
		if want == WANT_DOWN and ship.mounts[i] == Weapons.NONE:
			wanted[i] = WANT_NONE
		elif want != WANT_NONE and want != WANT_DOWN and Weapons.item_of(ship.mounts[i], ship.mount_fx[i]) == want:
			wanted[i] = WANT_NONE
		elif want != WANT_NONE and want != WANT_DOWN and int(ship.store.get(want, 0)) <= 0 and not _carried(want):
			wanted[i] = WANT_NONE
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func _carried(item: int) -> bool:
	for p: Player in server.players:
		if p != null and not p.corpse and not p.pirate and p.slots.has(item):
			return true
	return false


func packet() -> PackedByteArray:
	## Net.S_MOUNTS: per mount, whether a gunner stands at it, what the console ordered onto it, (v68) rounds loaded.
	var ship = server.ship
	var out := PackedByteArray([Net.S_MOUNTS, ship.id & 0xFF, ship.id >> 8, wanted.size()])
	for i in wanted.size():
		out.append(1 if gunners[i] != null else 0)
		out.append(wanted[i])
		out.append(loaded[i])            # (v68) rounds in its breech
	return out
