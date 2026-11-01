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
const Mover := preload("res://src/shared/mover.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")

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
const MOVE_SECONDS := 10.0           # (v101, his N2 A) an engineer takes an empty mount down, or sets one up, in this long

var server: GameServer
var gunners: Array = []              # per mount: the Player at it now, or null
var wanted := PackedByteArray()      # per mount: the gun (a thing) the console ordered onto it, WANT_NONE or WANT_DOWN
var loaded := PackedByteArray()      # (v68) per mount: rounds loaded into its breech by hand
var clip := PackedInt32Array()       # (v94) per mount: bursts left of the round in use (in space a round feeds Weapons.clip bursts)
var _told := PackedByteArray()
var _told_cells := PackedByteArray() # (v101) the last S_MOUNT_CELLS sent for this ship


func setup(p_server: GameServer) -> void:
	server = p_server
	gunners = []
	gunners.resize(server.map.guns.size())
	wanted = PackedByteArray()
	wanted.resize(server.map.guns.size())
	loaded = PackedByteArray()
	loaded.resize(server.map.guns.size())
	clip = PackedInt32Array()
	clip.resize(server.map.guns.size())
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
	if i < clip.size() and clip[i] > 0 and server.arena.flying():
		clip[i] -= 1                         # (v94) the round in use still feeds bursts
		return true
	var space_clip: int = Weapons.clip(ship.mounts[i]) - 1 if server.arena.flying() else 0   # (v95) firing with no enemy too
	if loaded[i] > 0:
		loaded[i] -= 1
		if i < clip.size():
			clip[i] = space_clip
		return true
	if int(ship.store.get(ammo, 0)) <= 0:
		return false
	ship.store[ammo] -= 1
	if i < clip.size():
		clip[i] = space_clip
	server.supplies.tell_store()
	return true


func has_round(i: int) -> bool:
	var ammo := ammo_of(i)
	return ammo == 0 or loaded[i] > 0 or int(server.ship.store.get(ammo, 0)) > 0 or (i < clip.size() and clip[i] > 0 and server.arena.flying())


func unload(i: int) -> void:
	## (v68) The gun comes down: what was in its breech goes back into the locker.
	var ammo := ammo_of(i)
	if ammo != 0 and loaded[i] > 0:
		server.ship.store[ammo] = int(server.ship.store.get(ammo, 0)) + loaded[i]
	loaded[i] = 0
	if i < clip.size():
		clip[i] = 0                          # (v94) what was left of the round in use is spent


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
	var item := p.in_hand()
	if item == Net.ITEM_MOUNT:
		return can_set(p, cell)
	if i < 0:
		return NOT_HERE
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
		var why := misfit(w, cell)
		if why != "":
			return why                       # (v94.1, his M2 note) it does not go on that kind of mount
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
		if not p.bot and server.arena.on():
			return NOT_HERE                  # (v92) in a fight "use" at a gun takes its controls (Arena), not the gun down
		return ""
	if item == Net.ITEM_NONE and on == Weapons.NONE and not p.bot:
		# (v101, his N2 A) an empty mount: an engineer takes it down, to set it up elsewhere
		if server.ship.broken.has(cell):
			return NOT_HERE                  # (mended first)
		if p.job != Net.JOB_ENGINEER:
			return "Пустое гнездо снимает и переносит только инженер."
		if server.arena.on():
			return "В бою гнездо не снять."
		if wanted[i] != WANT_NONE:
			return "К этому гнезду уже несут орудие: сначала отмените приказ на пульте орудий."
		return ""
	return NOT_HERE


func can_set(p: Player, cell: int) -> String:
	## (v101, his N2 A and N3 A) "" if `p` may set the mount in its hands up on that cell (a clean outer wall, or the
	## floor of the top or bottom deck: a turret); otherwise why not. GameClient.mount_here gives the same answers.
	var map = server.map
	if p.in_hand() != Net.ITEM_MOUNT or p.bot or cell < 0:
		return NOT_HERE
	if map.guns.has(cell):
		return "Здесь уже стоит гнездо."
	if Net.diagonal(p.st.facing) or map.cells[p.st.y * map.width + p.st.x] < 0:
		return "Встаньте внутри корабля прямо перед этим местом."
	var why: String = map.can_mount(cell)
	if why != "":
		return why
	if p.job != Net.JOB_ENGINEER:
		return "Гнездо ставит только инженер."
	if server.arena.on():
		return "В бою гнездо не поставить."
	if map.first_stowed() < 0:
		return "На корабле больше нет места под гнёзда: у него их %d." % map.guns.size()
	if map.walk[cell] == 1:
		if server.floor_things.has(cell):
			return "Сначала уберите с пола то, что там лежит."
		for q: Player in server.players:
			if q != null and q != p and not q.in_shuttle and Mover.body_tiles(q.st).has(Vector2i(cell % map.width, cell / map.width)):
				return "Здесь кто-то есть."
	return ""


static func misfit_of(w: int, kind: int) -> String:
	## (v94.1) "" if that gun goes on a mount of that kind, else why not, in the player's words. GameClient.mount_here
	## and the gun console ask the same.
	if Weapons.fits(w, kind):
		return ""
	return "%s не встаёт в гнездо «%s». %s" % [Weapons.name_of(w), ArenaShape.MOUNT_NAMES_OF[kind], Weapons.fit_words(w)]


func misfit(w: int, cell: int) -> String:
	return misfit_of(w, ArenaShape.kind_in_fleet(server.map, cell))


func ticks(p: Player) -> int:
	if p.in_hand() == Net.ITEM_MOUNT or p.in_hand() == Net.ITEM_NONE and _empty_ahead(p):
		return roundi(MOVE_SECONDS * Net.TICK_HZ * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)))   # (v101) a mount moved
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
	if item == Net.ITEM_MOUNT:
		_set_up(p, cell)
		return
	if item == Net.ITEM_NONE and ship.mounts[i] == Weapons.NONE:
		_take_down(p, i)
		return
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
	if server.map.stowed(i):
		server.chat.tell(p, "Орудие %d: гнездо снято, ставить некуда." % (i + 1))   # (v101)
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
	var why := misfit(w, server.map.guns[i])
	if why != "":
		server.chat.tell(p, "Орудие %d: %s" % [i + 1, why])
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
	var cells := cells_packet()
	if cells != _told_cells:
		_told_cells = cells
		server.to_all(cells)


func _carried(item: int) -> bool:
	for p: Player in server.players:
		if p != null and not p.corpse and not p.pirate and p.slots.has(item):
			return true
	return false


func cells_packet() -> PackedByteArray:
	## (v101) Net.S_MOUNT_CELLS for the ship in place: where each of its mounts is (-1: taken down, or a spare).
	var cells: PackedInt32Array = server.map.mount_cells()
	var out := PackedByteArray([Net.S_MOUNT_CELLS, server.fleet.on, cells.size()])
	for c: int in cells:
		var at := out.size()
		out.resize(at + 4)
		out.encode_s32(at, c)
	return out


func packet() -> PackedByteArray:
	## Net.S_MOUNTS: per mount, whether a gunner stands at it, what the console ordered onto it, (v68) rounds loaded.
	var ship = server.ship
	var out := PackedByteArray([Net.S_MOUNTS, ship.id & 0xFF, ship.id >> 8, wanted.size()])
	for i in wanted.size():
		out.append(1 if gunners[i] != null else 0)
		out.append(wanted[i])
		out.append(loaded[i])            # (v68) rounds in its breech
	return out


# ---------------------------------------------------------------- (v101) mounts moved about the hull

func _empty_ahead(p: Player) -> bool:
	var i := server.map.guns.find(server.map.use_ahead(p.st.x, p.st.y, p.st.facing))
	return i >= 0 and server.ship.mounts[i] == Weapons.NONE


func _clear(i: int) -> void:
	## A mount set up or taken down starts bare: no gun, nothing loaded, no order, no charge.
	var ship = server.ship
	ship.mounts[i] = Weapons.NONE
	ship.mount_fx[i] = Weapons.FX_NONE
	ship.armed[i] = 1
	loaded[i] = 0
	clip[i] = 0
	wanted[i] = WANT_NONE
	gunners[i] = null
	server.gunnery.charge[i] = 0.0
	server.gunnery.beam_left[i] = 0


func _take_down(p: Player, i: int) -> void:
	var map = server.map
	var cell: int = map.guns[i]
	var floor_one: bool = map.on_floor.has(cell)
	server.ship.jammed.erase(cell)
	map.set_gun(i, -1)
	_clear(i)
	p.slots[p.hand] = Net.ITEM_MOUNT
	p.train(Net.SKILL_REPAIR)
	server.usage.note(p, "mount_moved")
	_moved(cell)
	server.chat.say("%s снимает %s орудия %d. Его можно поставить в другую наружную стену или на пол верхней или нижней палубы." \
		% [p.name, "башню" if floor_one else "гнездо", i + 1])


func _set_up(p: Player, cell: int) -> void:
	var map = server.map
	var i: int = map.first_stowed()
	if i < 0:
		return
	map.set_gun(i, cell)
	_clear(i)
	p.slots[p.hand] = Net.ITEM_NONE
	p.train(Net.SKILL_REPAIR)
	server.usage.note(p, "mount_moved")
	_moved(cell)
	var kind := ArenaShape.kind_in_fleet(map, cell)
	server.chat.say("%s ставит гнездо: орудие %d, %s. Орудие на него несут из шкафа снабжения." % [p.name, i + 1,
		("башня на крыше" if map.roof(cell) else "башня на днище") + ", бьёт во все стороны, но слабее" if map.on_floor.has(cell) \
		else "в борту, " + ArenaShape.MOUNT_NAMES[kind]])


func _moved(cell: int) -> void:
	## Everything that knew where the mounts were learns it again.
	ArenaShape.forget_kinds()
	server.arena.mounts_moved()
	server.replication.sight_changed()
	server.to_all(server.gunnery.packet())
	var x: int = cell % server.map.width
	server.chat.sound(Net.SOUND_LOAD, x, cell / server.map.width, -1)
