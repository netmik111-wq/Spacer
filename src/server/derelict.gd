extends RefCounted
## Another ship alongside: a derelict, or a pirate ship. Server only.
##
## A pirate ship comes as one of two events (v44). Boarding: it shows up off
## the airlock, and after a warning it docks by force, breaks both doors of the
## airlock open and sends its pirates aboard; once it is drawn off again (from
## the ship's controls) it leaves. A raid: it stays off the airlock and fights
## at a distance (Gunnery). Its own ship is lit and has air. A raider our guns
## wreck stays alongside, dark and dead, until our ship moves on: the crew can
## board it and take what is left. What they find there is settled when it is
## wrecked: most often its crew all dead (WRECK_ALL_DEAD), else the survivors
## fight, or give up and join our crew (into the reserve).
##
## A sector may hold a derelict. When our ship comes near it, it is laid into
## the grid over our own ship, a few cells of open space away from our
## airlock: the crew can push off through space to it. From the ship's
## controls it can be brought right up against the airlock (docked), outer
## door to outer door. While anybody alive is outside our own ship, or the
## derelict is docked, our ship does not move or jump.
##
## What it holds is made up when it first comes near; what is left of it when
## the ship leaves is remembered for that sector, so it is not there again.

const Net := preload("res://src/shared/net.gd")
const Doors := preload("res://src/shared/doors.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Ship := preload("res://src/server/ship.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const PIRATE_WARNING_TICKS := 90 * Net.TICK_HZ    # from showing up to docking by force: the time to fight it off
const RAID_BOARD_TICKS := 30 * Net.TICK_HZ    # (v54) a raider that sees us helpless closes in and boards after this
const GAP := 3                       # cells of open space between it and our airlock while not docked
const VACUUM_ROOM := 0.4             # share of its rooms with no air left at all
const HOLE_CHANCE := 0.5             # chance that a hole in its hull still leaks
const WRECK_ALL_DEAD := 0.7          # chance that nobody aboard a wreck is alive (the author's number)
const WRECK_FIGHT := 0.5             # of the rest: the survivors fight (else they join us)
# what pirates keep on their ship: [thing, weight]
const PIRATE_LOOT := [
	[Net.ITEM_MAG, 5], [Net.ITEM_MEDPATCH, 4], [Net.ITEM_PATCH, 2], [-Net.ITEM_PISTOL, 2], [Net.ITEM_BATON, 2], [Net.ITEM_FUEL, 3],
]
const DERELICT_GUN := 0.25           # (v58) the share of derelicts with a ship gun aboard
const DERELICT_GUN_DAMAGED := 0.6    # and of those guns, the share that are damaged
const DERELICT_GEAR := 0.5           # (v59) the share of those finds that are a crate of ship gear instead
var derelict_gear_chance := DERELICT_GEAR   # (tests set it)
# what may lie about on a derelict: [thing, weight]
const LOOT := [
	[Net.ITEM_PATCH, 6], [Net.ITEM_PART, 5], [Net.ITEM_MEDPATCH, 4], [Net.ITEM_MAG, 3],
	[Net.ITEM_FLASHLIGHT, 2], [Net.ITEM_BATON, 2], [-Net.ITEM_MEDKIT, 2], [-Net.ITEM_PISTOL, 1], [Net.ITEM_FUEL, 5],
]

var server: Node
var map: ShipMap
var here := false                    # a ship lies alongside now
var ship: Ship = null                # and that is it, with its own network id (see GameServer.ships_packet)
var kind := Net.OTHER_DERELICT       # which kind it is (Net.OTHER_*)
var layout := Net.OTHER_DERELICT     # its drawing: its number in Net.OTHER_MAPS (v53: a pirate ship has several)
var design := {}                     # (a pirate ship) what Shipyard rolled for it
var docked := false
var _spots := {}                     # drawing -> [where its corner lies alongside, where docked], for the drawings that fit
var _pirates_dock_at := -1           # the tick a pirate ship alongside docks by force (-1 = it has)
var _pirates_party := 0             # its crew (or boarding party) still alive
var raid := false                    # (a pirate ship) it came to fight at a distance, not to board
var wreck := false                   # (a pirate ship) our guns wrecked it: no power, no light, no fight
var _crew_total := 0                 # its crew when it came
var _outcome := ""                   # (a wreck) what the first of us aboard finds: "dead", "fight" or "join"
var _boarded := false                # somebody of our crew has set foot on the wreck
var _came_in := 0                    # the sector it came in (Sectors.key): it does not follow a jump
var _left := {}                      # sector key -> [[cell inside it, things], ...]: what was left on it
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	map = server.map
	here = false
	docked = false
	ship = null
	_left.clear()
	_rng.randomize()
	_spots = {}
	_pirates_dock_at = -1
	if map.others.is_empty() or map.lock_pump.is_empty():
		return
	# its outer door goes right against ours
	var ours: Vector2i = map.doors[int(map.lock_pump.values()[0]["outer"])]
	for k in map.others.size():
		var o = map.others[k]
		var theirs := Vector2i(-1, -1)
		for d in o.doors.size():
			if o.door_vent[d] == 1:
				theirs = o.doors[d]
		if theirs.x < 0:
			continue
		var docked_at := ours - theirs - Vector2i(0, 1)
		var alongside := docked_at - Vector2i(0, GAP)
		if map.other_fits_kind(k, docked_at) and map.other_fits_kind(k, alongside):
			_spots[k] = [alongside, docked_at]


func possible(of_kind: int = Net.OTHER_DERELICT) -> bool:
	if of_kind == Net.OTHER_DERELICT:
		return _spots.has(Net.OTHER_DERELICT)
	return not _pirate_spots().is_empty()


func _pirate_spots() -> Array:
	## The pirate ships' drawings that can lie off our airlock.
	var out := []
	for k: int in _spots.keys():
		if k >= Net.OTHER_PIRATE:
			out.append(k)
	return out


func _comes(of_kind: int, of_layout: int, of_name: String) -> void:
	## A ship of that kind comes alongside: it gets a network id of its own.
	kind = of_kind
	layout = of_layout
	here = true
	docked = false
	raid = false
	wreck = false
	_boarded = false
	_outcome = ""
	_came_in = Sectors.key(server.sectors.cell[server.ship.sector])
	ship = Ship.new()
	ship.id = server.new_ship_id()
	ship.kind = Net.SHIP_PIRATE if of_kind == Net.OTHER_PIRATE else Net.SHIP_DERELICT
	ship.name = of_name
	ship.layout = of_layout
	ship.map = map


func _set_docked(on: bool) -> void:
	docked = on
	if ship != null:
		ship.docked = on


func pirates_can_come() -> bool:
	## Can a pirate ship come up to the airlock now?
	return possible(Net.OTHER_PIRATE) and not here and not someone_outside()


func pirates_come(party: int, p_raid: bool = false, given: Dictionary = {}) -> bool:
	## A pirate ship shows up off the airlock: to dock by force before long, or
	## (a raid) to fight it out at a distance. (v57) `given` is a ship already
	## made (the flagship, Flagship.call_in); else Shipyard rolls one.
	if not pirates_can_come():
		return false
	design = given if not given.is_empty() else server.shipyard.make(party, p_raid, _pirate_spots())
	_comes(Net.OTHER_PIRATE, int(design["layout"]), str(design["name"]))
	raid = p_raid
	_place(_spots[layout][0])
	for c in map.other_cells:
		if map.walk[c] == 1:
			server.air.air[c] = 1.0
	_pirates_dock_at = -1 if raid else server.tick + PIRATE_WARNING_TICKS
	_pirates_party = int(design["crew"])
	_crew_total = _pirates_party
	var loot: Array = design["loot"]
	for i in _rng.randi_range(loot[0], loot[1]):
		_drop(_floor_cells(), PIRATE_LOOT)
	server.air.wake()
	server.gunnery.enemy_arrives(design, raid)
	var who := "Пиратский корабль" if design.has("classic") else str(design["name"])
	if design.has("boss"):
		server.chat.say(("Тревога! Из тени выходит %s, флагман пиратов. Это цель пути: бой до конца, он не бежит и не сдаётся. Разбейте его, и игра выиграна. " % who) +
			("Он бьёт прицельно: сначала по генератору щита, потом по двигателю. Держите ремонтников наготове." if int(design["boss"]) == 1 else
			"Его нейроизлучатели оглушают всех в отсеке, а телепорт высаживает абордажников прямо на мостик. Не отдавайте мостик!"))
	elif raid:
		server.chat.say("Тревога! %s выходит на дистанцию огня и атакует. На абордаж он не идёт: это бой до конца. Разбейте его из орудий (пульт орудий на мостике), и его можно будет обыскать. Его отсеки пока не видны: их покажут сканеры, попадания и зонд." % who)
	else:
		server.chat.say("Тревога! К шлюзу подходит %s и открывает огонь. Через %d секунд он пристыкуется силой и вскроет шлюз, если его не разбить из орудий (пульт орудий на мостике)." % [
			who if design.has("classic") else who.substr(0, 1).to_lower() + who.substr(1), PIRATE_WARNING_TICKS / Net.TICK_HZ])
	return true


func someone_outside() -> bool:
	## Is anybody alive outside our own ship (on the derelict, or out in space)?
	for p in server.players:
		if p != null and not p.corpse and not p.pirate and p.cond != Net.COND_DEAD \
				and not map.on_ship(p.st.y * map.width + p.st.x):
			return true
	return false


func holds_ship() -> String:
	## Why our ship may not move or jump right now ("" = it may).
	if docked:
		return "Корабль пристыкован: сначала расстыкуйтесь с пульта управления."
	if someone_outside():
		return "Не все на борту: кто-то снаружи корабля."
	return ""


func update() -> void:
	## Brings a derelict alongside when the ship is near it, and takes it away
	## when not; docks a pirate ship when its time comes, and lets it go.
	if here and kind == Net.OTHER_PIRATE:
		var free := holds_ship() == ""
		if free and Sectors.key(server.sectors.cell[server.ship.sector]) != _came_in:
			# our ship has jumped away: it is left behind
			_leave(true)
			server.chat.say("Пиратский корабль остался позади, в другом секторе.")
			return
		if wreck:
			_watch_boarding()
			if free and (server.ship.moving or server.ship.jump_to != Net.NO_SECTOR):
				_leave()                     # we move on: the hulk stays where it drifts
			return
		if raid:
			_raid_closes_in()
		if _pirates_dock_at >= 0 and server.tick >= _pirates_dock_at:
			_pirates_board()
		elif _pirates_dock_at < 0 and not raid and not docked and free:
			_leave()
		return
	if not possible():
		return
	var want: bool = server.navigation.sector_kind() == Sectors.DERELICT and server.ship.in_reach
	if want and not here:
		_arrive()
	elif not want and here and holds_ship() == "":
		_leave()


func dock(on: bool) -> String:
	## Brings it up against our airlock, or draws it off again. Returns what went wrong, or "".
	if not here or on == docked:
		return ""
	if kind == Net.OTHER_PIRATE and on and not wreck:
		return "Стыковаться с пиратами по своей воле никто не станет."
	var from: Vector2i = map.other_at
	var to: Vector2i = _spots[layout][1] if on else _spots[layout][0]
	if _anyone_in_way(from, to):
		return "Стыковка невозможна: между кораблями кто-то есть." if on else "Расстыковка невозможна: рядом кто-то есть."
	_move(from, to)
	_set_docked(on)
	return ""


# ---------------------------------------------------------------- inside

func pirates_wrecked() -> void:
	## Our guns have wrecked the pirate ship before it docked: it goes, with its crew.
	_pirates_dock_at = -1
	_leave(true)


func pirates_escaped() -> void:
	## It has jumped away.
	_pirates_dock_at = -1
	_leave(true)


func dark() -> bool:
	## Is the ship alongside without light of its own (a derelict, or a wreck)?
	return here and (kind == Net.OTHER_DERELICT or wreck)


func becomes_wreck() -> void:
	## Our guns have wrecked a raider: it stays alongside, dead. Who is aboard it
	## and alive is settled now and found out when the first of us comes aboard.
	_pirates_dock_at = -1
	raid = false
	wreck = true
	ship.kind = Net.SHIP_WRECK
	ship.name = "Разбитый пиратский корабль" if design.has("classic") else "Обломки: " + ship.name.substr(0, 1).to_lower() + ship.name.substr(1)
	for d in range(map.other_first_door, map.doors.size()):
		server.doors.dead[d] = 1
	var alive := _pirates_party
	if server.enemy_crew.in_world:
		# (v55) our boarders are aboard and its crew are pirates in the world already:
		# whoever is alive goes on fighting, the dead lie where they fell
		for p in server.enemy_crew.people:
			if p != null:
				p.home = -1
		_outcome = "dead"
		_boarded = true
		_pirates_party = 0
		for i in _rng.randi_range(1, 3):
			_drop(_floor_cells(), PIRATE_LOOT)
		server.replication.sight_changed()
		return
	if alive <= 0 or _rng.randf() < WRECK_ALL_DEAD:
		_outcome = "dead"
		alive = 0
	else:
		_outcome = "fight" if _rng.randf() < WRECK_FIGHT else "join"
	_pirates_party = alive
	# the dead lie where they fell, with what they carried
	var cells := _floor_cells()
	for i in maxi(_crew_total - alive, 0):
		if cells.is_empty():
			break
		var c: int = cells[_rng.randi_range(0, cells.size() - 1)]
		var p = server.pirates.spawn(c % map.width, c / map.width, _rng.randf() < 0.6)
		p.health = Net.HEALTH_DEAD
		p.cond = Net.COND_DEAD
		p.died_tick = server.tick
		p.st.down = true
		p.st.facing = _rng.randi_range(1, 4)
		server.crew.becomes_corpse(p)
	for i in _rng.randi_range(1, 3):
		_drop(cells, PIRATE_LOOT)
	server.replication.sight_changed()


func _raid_closes_in() -> void:
	## (v54, the author's word) A raider only boards when we can neither fight nor
	## run: every gun of ours silent, and the engine out or no jump to be had.
	## It warns, closes in and docks by force after RAID_BOARD_TICKS; if one of
	## our guns speaks again before then, it pulls back to its distance.
	var g = server.gunnery
	if g.boss > 0:
		return                               # (v57) the flagship does not close in: it has its own ways
	var helpless: bool = g.fighting() and not g.fleeing() and g.ransom == 0 \
		and g.our_guns_silent() and server.navigation.cannot_jump()
	if helpless and _pirates_dock_at < 0:
		_pirates_dock_at = server.tick + RAID_BOARD_TICKS
		server.chat.say("Наши орудия молчат, а уйти прыжком мы не можем. Пиратский корабль идёт на сближение: через %d с он пристыкуется силой и пойдёт на абордаж!" % (RAID_BOARD_TICKS / Net.TICK_HZ))
	elif not helpless and _pirates_dock_at >= 0 and g.fighting():
		_pirates_dock_at = -1
		server.chat.say("Пиратский корабль отходит на прежнюю дистанцию: у нас снова есть чем ответить или куда уйти.")


func _watch_boarding() -> void:
	## The first of our crew to set foot on the wreck finds out who is left aboard.
	if _boarded:
		return
	var first = null
	for p in server.players:
		if p != null and not p.pirate and not p.corpse and not p.bot and p.cond != Net.COND_DEAD \
				and map.is_other(p.st.y * map.width + p.st.x):
			first = p
			break
	if first == null:
		return
	_boarded = true
	match _outcome:
		"dead":
			server.chat.say("%s поднимается на борт разбитого корабля. Живых здесь нет." % first.name)
		"fight":
			# they hid as far from the way in as they could, and come out armed
			var cells := _floor_cells()
			var here_at := Vector2(first.st.x, first.st.y)
			var sorted := Array(cells)
			sorted.sort_custom(func(a: int, b: int) -> bool:
				return Vector2(a % map.width, a / map.width).distance_squared_to(here_at) \
					> Vector2(b % map.width, b / map.width).distance_squared_to(here_at))
			for i in mini(_pirates_party, sorted.size()):
				var c: int = sorted[i]
				var p = server.pirates.spawn(c % map.width, c / map.width, _rng.randf() < 0.6)
				server.pirates.heard(p, first.st.x, first.st.y)
			server.chat.say("На разбитом корабле выжившие пираты (%d)! Они не сдаются и хватаются за оружие." % _pirates_party)
		"join":
			var before: int = server.reserve
			server.reserve = mini(server.reserve + _pirates_party, Net.RESERVE_MAX)
			server.chat.say("На разбитом корабле выжившие пираты (%d). Они сдаются и просятся в экипаж: резерв экипажа %d (+%d)." % [
				_pirates_party, server.reserve, server.reserve - before])
	_pirates_party = 0


func _pirates_board() -> void:
	## The pirate ship docks by force, breaks the airlock open and its crew comes aboard.
	var from: Vector2i = map.other_at
	var to: Vector2i = _spots[layout][1]
	if _anyone_in_way(from, to):
		return                               # it waits until the way is clear
	_pirates_dock_at = -1
	_move(from, to)
	_set_docked(true)
	var lock: Dictionary = map.lock_pump.values()[0]
	for d: int in [int(lock["inner"]), int(lock["outer"])]:
		server.doors.jammed[d] = 1
		server.doors.locked[d] = 0
		if server.doors.ready[d] == Doors.CLOSED:
			server.doors.ready[d] = server.tick
	server.air.wake()
	if server.enemy_crew.in_world:
		# (v55) they are in the world already (our boarders woke them): they just come across
		for p in server.enemy_crew.people:
			if p != null:
				p.home = -1
		server.chat.say("Пиратский корабль пристыковался силой и вскрыл обе двери шлюза! Его экипаж идёт к нам на борт. Двери шлюза заклинило: чинить, как обычную дверь.")
		return
	# they come out of their own door, one behind another
	var theirs: Vector2i = map.doors[int(lock["outer"])] - Vector2i(0, 2)
	for i in mini(_pirates_party, server.pirates.MAX_ABOARD):
		var at := theirs - Vector2i(0, i % 2)
		server.pirates.spawn(at.x + i / 2, at.y, _rng.randf() < 0.6)
	server.chat.say("Пиратский корабль пристыковался силой и вскрыл обе двери шлюза! Пираты идут на борт (их %d). Двери шлюза заклинило: чинить, как обычную дверь." % mini(_pirates_party, server.pirates.MAX_ABOARD))


func drop_thing(item: int) -> bool:
	## (v58) A thing left lying on the floor of the ship alongside (a gun in a wreck). False if there was no room.
	var cells := _floor_cells()
	for tries in 8:
		if cells.is_empty():
			return false
		if server.put_on_floor(cells[_rng.randi_range(0, cells.size() - 1)], item):
			return true
	return false


func _drop(cells: PackedInt32Array, table: Array) -> void:
	server.put_on_floor(cells[_rng.randi_range(0, cells.size() - 1)], _loot(table))


func _arrive() -> void:
	_comes(Net.OTHER_DERELICT, Net.OTHER_DERELICT, "Брошенный корабль")
	_place(_spots[layout][0])
	var key := Sectors.key(server.sectors.cell[server.ship.sector])
	var cells := _floor_cells()
	# air: room by room, some empty, the rest thin
	for room: Array in _rooms():
		var a := 0.0 if _rng.randf() < VACUUM_ROOM else _rng.randf_range(0.3, 0.9)
		for c: int in room:
			server.air.air[c] = a
	# a hole that still leaks, now and then
	if _rng.randf() < HOLE_CHANCE:
		var hull := _hull_cells()
		if not hull.is_empty():
			var c: int = hull[_rng.randi_range(0, hull.size() - 1)]
			server.air.set_hole(c, true)
			server.replication.hull_record(c, 1)
	# what lies about: made up the first time, as it was left after that
	if _left.has(key):
		for e: Array in _left[key]:
			_put(map.other_at, int(e[0]), e[1])
	else:
		for i in _rng.randi_range(5, 8):
			_drop(cells, LOOT)
		if _rng.randf() < DERELICT_GUN:
			# (v58, the author: derelicts may hide gear) a ship gun left behind, often in poor shape
			var far: int = server.sectors.far_from_start(server.ship.sector)
			var t: int = Weapons.tiers_for(far, 1, _rng)[0]
			var choice: Array = Weapons.OURS.filter(func(w: int) -> bool: return Weapons.tier(w) == t and not Weapons.unique(w) and w != Weapons.GUARD)
			var w: int = choice[_rng.randi_range(0, choice.size() - 1)]
			var item := Weapons.item_of(w, Weapons.roll_fx(w, _rng), _rng.randf() < DERELICT_GUN_DAMAGED)
			if _rng.randf() < derelict_gear_chance:
				item = server.outfit.loot(far, _rng)     # (v59) or a crate of ship gear
			server.put_on_floor(cells[_rng.randi_range(0, cells.size() - 1)], item)
	server.air.wake()
	server.chat.say("Рядом брошенный корабль. До него можно добраться через шлюз в открытом космосе или пристыковаться с пульта управления.")


func _leave(quiet: bool = false) -> void:
	var was_wreck := wreck
	# what is left on a derelict is remembered for this sector
	if kind == Net.OTHER_DERELICT:
		var key := Sectors.key(server.sectors.cell[server.ship.sector])
		var kept := []
		for c in map.other_cells:
			if server.floor_things.has(c):
				kept.append([_local(c, map.other_at), (server.floor_things[c] as PackedByteArray).duplicate()])
		_left[key] = kept
	# whoever lies on it (pirates struck down on their own ship) goes with it
	for p in server.players:
		if p != null and map.is_other(p.st.y * map.width + p.st.x) and (p.corpse or p.pirate):
			server.crew.remove(p)
	_clear_region()
	here = false
	raid = false
	wreck = false
	_set_docked(false)
	_place(ShipMap.NO_OTHER)
	ship = null
	server.gunnery.enemy_gone()
	if not quiet:
		server.chat.say("Брошенный корабль остался позади." if kind == Net.OTHER_DERELICT else
			("Разбитый пиратский корабль остался позади." if was_wreck else "Пиратский корабль отошёл от шлюза и ушёл."))


func _move(from: Vector2i, to: Vector2i) -> void:
	## Shifts it, with all that is on it, from one place to another.
	var shift := to - from
	var air_of := {}
	var things := []
	var holes := []
	for c in map.other_cells:
		air_of[_local(c, from)] = server.air.air[c]
		if server.floor_things.has(c):
			things.append([_local(c, from), (server.floor_things[c] as PackedByteArray).duplicate()])
		if server.air.holes.has(c):
			holes.append(_local(c, from))
	var aboard := []
	for p in server.players:
		if p != null and map.is_other(p.st.y * map.width + p.st.x):
			aboard.append(p)
	_clear_region()
	_place(to)
	for k: int in air_of.keys():
		var c := _cell(to, k)
		if map.walk[c] == 1:
			server.air.air[c] = air_of[k]
	for e: Array in things:
		_put(to, int(e[0]), e[1])
	for k: int in holes:
		var c := _cell(to, k)
		server.air.set_hole(c, true)
		server.replication.hull_record(c, 1)
	for p in aboard:
		p.st.place(p.st.x + shift.x, p.st.y + shift.y)
		p.self_dirty = true
	server.air.wake()


func _place(at: Vector2i) -> void:
	## Lays it into the grid there, and sets everything that depends on the shape of the ship.
	map.place_other(at, layout)
	if ship != null:
		ship.at = at
	for d in range(map.other_first_door, map.doors.size()):
		server.doors.ready[d] = Doors.CLOSED
		server.doors.set_flags(d, 0)
		server.doors.dead[d] = 1 if kind == Net.OTHER_DERELICT or wreck else 0     # a pirate ship has power, a wreck not
	server.replication.index_doors()
	server.air.reshape()


func _clear_region() -> void:
	## Takes away what lies on it and its holes (as changes clients are told about).
	for c in map.other_cells:
		if server.floor_things.has(c):
			server.floor_things.erase(c)
			server.replication.floor_record(c)
		if server.air.holes.has(c):
			server.air.set_hole(c, false)
			server.replication.hull_record(c, 0)


func _put(at: Vector2i, local: int, things: PackedByteArray) -> void:
	var c := _cell(at, local)
	server.floor_things[c] = things.duplicate()
	server.replication.floor_record(c)


func _local(cell: int, at: Vector2i) -> int:
	## A cell of our grid as a cell of its own drawing.
	var o = map.other
	return (cell / map.width - at.y) * o.width + (cell % map.width - at.x)


func _cell(at: Vector2i, local: int) -> int:
	var o = map.other
	return (at.y + local / o.width) * map.width + at.x + local % o.width


func _floor_cells() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in map.other_cells:
		if map.walk[c] == 1 and map.door_of[c] < 0:
			out.append(c)
	return out


func _hull_cells() -> PackedInt32Array:
	## Its walls with floor on one side and space on another.
	var out := PackedInt32Array()
	for c in map.other_cells:
		if map.walk[c] == 1:
			continue
		var x := c % map.width
		var y := c / map.width
		var inside := map.walkable(x - 1, y) or map.walkable(x + 1, y) or map.walkable(x, y - 1) or map.walkable(x, y + 1)
		var outside := map.is_space(x - 1, y) or map.is_space(x + 1, y) or map.is_space(x, y - 1) or map.is_space(x, y + 1)
		if inside and outside:
			out.append(c)
	return out


func _rooms() -> Array:
	## Its floor split into rooms by its doors (a doorway belongs to no room).
	var seen := {}
	var out := []
	for start in _floor_cells():
		if seen.has(start):
			continue
		var room := [start]
		seen[start] = true
		var i := 0
		while i < room.size():
			var c: int = room[i]
			i += 1
			for o: int in [1, -1, map.width, -map.width]:
				var j := c + o
				if j < 0 or j >= map.walk.size() or seen.has(j) or not map.is_other(j) or map.walk[j] == 0 or map.door_of[j] >= 0:
					continue
				seen[j] = true
				room.append(j)
		out.append(room)
	return out


func _loot(table: Array) -> int:
	var total := 0
	for e: Array in table:
		total += int(e[1])
	var roll := _rng.randi_range(1, total)
	for e: Array in table:
		roll -= int(e[1])
		if roll <= 0:
			var thing := int(e[0])
			if thing == -Net.ITEM_MEDKIT:
				return Net.ITEM_MEDKIT + _rng.randi_range(1, Net.MEDKIT_USES)
			if thing == -Net.ITEM_PISTOL:
				return Net.ITEM_PISTOL + _rng.randi_range(0, Net.PISTOL_ROUNDS)
			return thing
	return Net.ITEM_PATCH


func _anyone_in_way(from: Vector2i, to: Vector2i) -> bool:
	## Is anybody (or any body) out in the space it would move into?
	var o = map.other
	for p in server.players:
		if p == null or not map.floats(p.st.x, p.st.y):
			continue
		var local := Vector2i(p.st.x, p.st.y) - to
		if local.x >= 0 and local.y >= 0 and local.x < o.width and local.y < o.height \
				and o.cells[local.y * o.width + local.x] >= 0:
			return true
	return false
