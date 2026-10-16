extends RefCounted
## Rolls every pirate ship that comes (v53, the author's request: many
## different enemies, a different setup for each). Server only.
##
## A ship is one of the classes in Hulls (катер, рейдер, канонерка, крейсер):
## the farther from the start, the bigger the ones that may come. Its hull is
## one of its class's hand-drawn ones; everything inside it is rolled anew:
## which room holds which of its systems (the rest are empty rooms that only
## soak up shots), its guns, whether it has a shield, its crew, its temper and
## its name. What comes out is a design (a Dictionary) that Derelict lays into
## the grid and Gunnery fights with:
##   klass, layout (its number in Net.OTHER_MAPS), name, temper (Net.TEMPER_*),
##   hull, strength, shield (bool), regen, slower, dodge, weapons
##   (PackedByteArray), crew, reward, loot ([fewest, most]),
##   room_sys (per room of its drawing: Net.ESYS_* or Net.ROOM_EMPTY)

const Net := preload("res://src/shared/net.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const Weapons := preload("res://src/shared/weapons.gd")

# (the old pirate ship, kept for the tests written for it: see `classic`)
const CLASSIC_FIRST: Array[int] = [Weapons.LASER]
const CLASSIC_SECOND: Array[int] = [Weapons.LASER, Weapons.RAPID, Weapons.BLASTER, Weapons.ION, Weapons.ROCKET, Weapons.HEAVY]
const CLASSIC_THIRD: Array[int] = [Weapons.HEAVY, Weapons.RAPID, Weapons.BLASTER, Weapons.ION_CANNON, Weapons.ROCKET, Weapons.EMP]
const CLASSIC_THIRD_FROM := 5

var server: Node
var classic := false                 # (tests) always the old raider: its first hull, its rooms as drawn, its old numbers
var force_class := -1                # (tests, admin) this class only, if it may come at all
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	_rng.randomize()


func make(party: int, raid: bool, fits: Array) -> Dictionary:
	## A pirate ship for this place: `party` is the boarding party the director
	## sends (a raider's own crew is its class's), `fits` the drawings that
	## can lie off our airlock.
	var far: int = server.sectors.far_from_start(server.ship.sector) if server.sectors.count > 0 else 0
	if classic and fits.has(Net.OTHER_PIRATE):
		return _classic(party, far)
	# the class: one that may come this far out and has a hull that fits
	var choice: Array = []
	var total := 0
	for k: int in Hulls.CLASSES.keys():
		var c: Dictionary = Hulls.CLASSES[k]
		if c.has("boss"):
			continue                         # (v57) the flagship waits at the goal point; it is not met by chance
		if force_class >= 0 and k != force_class:
			continue
		if int(c["from"]) > far and force_class < 0:
			continue
		var hulls: Array = (c["layouts"] as Array).filter(func(l: int) -> bool: return fits.has(l))
		if hulls.is_empty():
			continue
		choice.append([k, hulls])
		total += int(c["weight"])
	if choice.is_empty():
		return _classic(party, far)
	var roll := _rng.randi_range(1, total)
	var pick: Array = choice[0]
	for e: Array in choice:
		roll -= int(Hulls.CLASSES[e[0]]["weight"])
		if roll <= 0:
			pick = e
			break
	var klass: int = pick[0]
	var info: Dictionary = Hulls.CLASSES[klass]
	var hulls: Array = pick[1]
	var layout: int = hulls[_rng.randi_range(0, hulls.size() - 1)]
	var shielded := _rng.randf() < float(info["shield"])
	# its guns: the first of its pool first, then any
	var pool: Array = info["pool"]
	var count: int = (info["guns"] as Array)[1] if far >= int(info["more_from"]) else (info["guns"] as Array)[0]
	var weapons := PackedByteArray([pool[0]])
	while weapons.size() < count:
		weapons.append(pool[_rng.randi_range(0, pool.size() - 1)])
	var crew_range: Array = info["crew"]
	var crew := _rng.randi_range(crew_range[0], crew_range[1]) if raid else party
	var tempers: Array = Hulls.TEMPERS.keys().filter(func(t: int) -> bool: return not Hulls.temper(t).has("boss"))
	var temper: int = tempers[_rng.randi_range(0, tempers.size() - 1)]
	return {
		"klass": klass, "layout": layout, "temper": temper,
		"name": "%s «%s»" % [_cap(str(info["name"])), Hulls.NAMES[_rng.randi_range(0, Hulls.NAMES.size() - 1)]],
		"hull": int(info["hull"]), "strength": int(info["strength"]), "shield": shielded, "regen": float(info["regen"]),
		"slower": float(info["slower"]), "dodge": float(info["dodge"]), "weapons": weapons, "crew": maxi(crew, 1),
		"reward": int(info["reward"]), "loot": info["loot"], "room_sys": _lay_out(layout, shielded),
	}


func flagship(kind: int, fits: Array) -> Dictionary:
	## (v57) The flagship at the goal point, of the author's kind 1 (a battleship:
	## guns that aim well) or 2 (a carrier: neural guns and a teleporter). Its
	## guns are its class's, all of them; its rooms are rolled like any other's.
	## Empty if its hull cannot lie off our airlock.
	var klass := Net.ECLASS_BATTLESHIP if kind == 1 else Net.ECLASS_CARRIER
	var info: Dictionary = Hulls.CLASSES[klass]
	var layout: int = (info["layouts"] as Array)[0]
	if not fits.has(layout):
		return {}
	var teleport := kind == 2
	var crew: int = (info["crew"] as Array)[0]
	var weapons := PackedByteArray(info["pool"])
	var extra: Array = info["extra"]
	for i in mini(upgrades(), extra.size()):
		weapons.append(extra[i])
	return {
		"klass": klass, "layout": layout, "temper": Net.TEMPER_SIEGE if kind == 1 else Net.TEMPER_STORM,
		"name": "%s «%s»" % [_cap(str(info["name"])), "Владыка пустоты" if kind == 1 else "Пожиратель"],
		"hull": int(info["hull"]), "strength": int(info["strength"]), "shield": true, "regen": float(info["regen"]),
		"slower": float(info["slower"]), "dodge": float(info["dodge"]), "weapons": weapons, "crew": crew,
		"reward": int(info["reward"]), "loot": info["loot"], "room_sys": _lay_out(layout, true, teleport),
		"boss": kind, "teleport": teleport,
	}


func upgrades() -> int:
	## (v57) How far our ship is armed past its start: guns on their mounts other
	## than the plain laser it set out with (spares in the cargo do not count).
	var n := 0
	for w in server.ship.mounts:
		if w != Weapons.NONE and w != Weapons.LASER:
			n += 1
	return n


func _lay_out(layout: int, shielded: bool, teleport: bool = false) -> PackedByteArray:
	## Its systems, each in a room of the hull picked by lot; the rooms left over are empty.
	var rooms: Array = server.map.others[layout].rooms
	var out := PackedByteArray()
	out.resize(rooms.size())
	out.fill(Net.ROOM_EMPTY)
	var order := range(rooms.size())
	_shuffle(order)
	var k := 0
	for system in Net.ESYS_COUNT:
		if (system == Net.ESYS_SHIELDS and not shielded) or (system == Net.ESYS_TELEPORT and not teleport):
			continue
		if k >= order.size():
			break
		out[order[k]] = system
		k += 1
	return out


func _classic(party: int, far: int) -> Dictionary:
	## The pirate ship as it was before v53: its first hull, the rooms its drawing names.
	var o = server.map.others[Net.OTHER_PIRATE]
	var room_sys := PackedByteArray()
	room_sys.resize(o.rooms.size())
	room_sys.fill(Net.ROOM_EMPTY)
	for system in o.zones.size():
		var cells: PackedInt32Array = o.zones[system]
		if not cells.is_empty() and o.room_of[cells[0]] >= 0:
			room_sys[o.room_of[cells[0]]] = system
	var weapons := PackedByteArray([CLASSIC_FIRST[_rng.randi_range(0, CLASSIC_FIRST.size() - 1)],
		CLASSIC_SECOND[_rng.randi_range(0, CLASSIC_SECOND.size() - 1)]])
	if far >= CLASSIC_THIRD_FROM:
		weapons.append(CLASSIC_THIRD[_rng.randi_range(0, CLASSIC_THIRD.size() - 1)])
	var info: Dictionary = Hulls.CLASSES[Net.ECLASS_RAIDER]
	return {
		"klass": Net.ECLASS_RAIDER, "layout": Net.OTHER_PIRATE, "temper": Net.TEMPER_CALCULATING, "name": "Пиратский корабль",
		"hull": int(info["hull"]), "strength": int(info["strength"]), "shield": _rng.randf() < server.gunnery.shield_chance,
		"regen": 1.0, "slower": float(info["slower"]), "dodge": 0.0, "weapons": weapons, "crew": maxi(party, 1),
		"reward": int(info["reward"]), "loot": info["loot"], "room_sys": room_sys, "classic": true,
	}


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)
