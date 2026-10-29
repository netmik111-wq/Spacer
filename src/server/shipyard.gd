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
##   (v62) drone (a drone ship: no crew, Gunnery.crewless), teleport (it carries a teleporter)

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
var force_temper := -1               # (v60.1, admin) this temper, not a rolled one
var force_pods := false              # (v95, tests) every rolled pirate carries a pod bay
var force_teleport := false          # (v62, tests) a teleporter wherever it fits, however near the start
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	_rng.randomize()


func make(party: int, raid: bool, fits: Array, harder: int = 0, temper_of: int = -1) -> Dictionary:
	## A pirate ship for this place: `party` is the boarding party the director
	## sends (a raider's own crew is its class's), `fits` the drawings that
	## can lie off our airlock. (v64) A hunter comes `harder` steps of danger
	## harder than the place, with its own temper (`temper_of`).
	var far: int = (server.sectors.far_from_start(server.ship.sector) if server.sectors.count > 0 else 0) + harder
	if classic and fits.has(Net.OTHER_PIRATE):
		return _classic(party, far)
	# the class: one that may come this far out and has a hull that fits; (v84) the pirate ships one drew
	# oneself are hulls of every class but the drone ship's and the flagships'
	var own: Array = server.map.others_of("pirate").filter(func(l: int) -> bool: return l >= Net.OTHER_MAPS.size())
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
		if not c.get("drone", false):
			hulls.append_array(own.filter(func(l: int) -> bool: return fits.has(l)))   # (v84, the author's H5)
		if hulls.is_empty():
			continue
		choice.append([k, hulls])
		total += int(c["weight"])
	if harder > 0 and force_class < 0:
		# (v64, my V8) a hunter: the biggest class that may come this far out (never a drone ship)
		var top := -1
		for e: Array in choice:
			var c: Dictionary = Hulls.CLASSES[e[0]]
			if not c.get("drone", false):
				top = maxi(top, int(c["from"]))
		var big := choice.filter(func(e: Array) -> bool:
			return int(Hulls.CLASSES[e[0]]["from"]) == top and not Hulls.CLASSES[e[0]].get("drone", false))
		if not big.is_empty():
			choice = big
			total = 0
			for e: Array in choice:
				total += int(Hulls.CLASSES[e[0]]["weight"])
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
	# its guns: (v58) each one's tier by how far out we are; the first of its pool first if that is tier 1
	var pool: Array = info["pool"]
	var count: int = (info["guns"] as Array)[1] if far >= int(info["more_from"]) else (info["guns"] as Array)[0]
	var tiers := Weapons.tiers_for(far, count, _rng)
	var weapons := PackedByteArray()
	var fx := PackedByteArray()
	for k in count:
		var w: int = pool[0] if k == 0 and tiers[k] == 1 else Weapons.pick_of_tier(tiers[k], pool, _rng)
		weapons.append(w)
		fx.append(Weapons.roll_fx(w, _rng))
	var drone: bool = info.get("drone", false)
	var crew_range: Array = info["crew"]
	var crew := _rng.randi_range(crew_range[0], crew_range[1]) if raid or drone else party
	var tempers: Array = Hulls.TEMPERS.keys().filter(func(t: int) -> bool:
		return not Hulls.temper(t).has("boss") and not Hulls.temper(t).has("machine"))
	var temper: int = tempers[_rng.randi_range(0, tempers.size() - 1)]
	if server.mode == Net.MODE_HARD and temper == Net.TEMPER_CAUTIOUS:
		temper = Net.TEMPER_RECKLESS if _rng.randf() < 0.5 else Net.TEMPER_HUNTER   # (v63) the hard mode: no cautious ones
	if force_temper >= 0 and tempers.has(force_temper):
		temper = force_temper
	elif temper_of >= 0:
		temper = temper_of
	if drone:
		temper = Net.TEMPER_MACHINE          # (v62) a machine fights the same way every time
	# (v62, the author's E5) a teleporter, now and then, far enough out
	var teleport: bool = not drone and far >= Hulls.TELEPORT_FROM and _rng.randf() < float(info.get("teleport", 0.0))
	teleport = teleport or (force_teleport and not drone)
	if teleport and server.map.others[layout].rooms.size() < Net.ESYS_TELEPORT + (1 if shielded else 0):
		teleport = false                     # (no room to spare for it in this hull)
	# (v95, his P2 note) a pod bay for boarding pods, by class
	var pods: bool = not drone and (force_pods or _rng.randf() < float(info.get("pods", 0.0)))
	var title := "%s «%s»" % [_cap(str(info["name"])), Hulls.NAMES[_rng.randi_range(0, Hulls.NAMES.size() - 1)]]
	if drone:
		title = "%s «%s»" % [_cap(str(info["name"])), Hulls.DRONE_NAMES[_rng.randi_range(0, Hulls.DRONE_NAMES.size() - 1)]]
	return {
		"klass": klass, "layout": layout, "temper": temper, "drone": drone, "teleport": teleport, "pods": pods,
		"name": title,
		"hull": int(info["hull"]), "strength": int(info["strength"]), "shield": shielded, "regen": float(info["regen"]),
		"slower": float(info["slower"]), "dodge": float(info["dodge"]), "weapons": weapons, "crew": maxi(crew, 1),
		"reward": roundi(int(info["reward"]) * (HARD_REWARD if server.mode == Net.MODE_HARD else 1.0)), "loot": info["loot"],
		"room_sys": _lay_out(layout, shielded, teleport, drone),
		"fx": fx, "armour": float(info.get("armour", 0.0)), "guard": far >= 4 and _rng.randf() < float(info.get("guard", 0.0)),
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
	var grown: int = server.flagship.growth          # (v63) how far it has grown while we took our time
	var teleport := kind == 2 or grown >= 3
	var crew: int = (info["crew"] as Array)[0]
	var weapons := PackedByteArray(info["pool"])
	var extra: Array = info["extra"]
	for i in mini(upgrades(), extra.size()):
		weapons.append(extra[i])            # (v67: none; see upgrades)
	var fx := PackedByteArray()
	for w in weapons:
		fx.append(Weapons.roll_fx(w, _rng))
	return {
		"klass": klass, "layout": layout, "temper": Net.TEMPER_SIEGE if kind == 1 else Net.TEMPER_STORM,
		"name": "%s «%s»" % [_cap(str(info["name"])), "Владыка пустоты" if kind == 1 else "Пожиратель"],
		"hull": int(info["hull"]) + GEAR_HULL * gear_upgrades(), "strength": int(info["strength"]) + (1 if grown >= 2 else 0), "shield": true,
		"regen": float(info["regen"]) * (1.0 + GEAR_REGEN * gear_upgrades()) * (GROWN_REGEN if grown >= 2 else 1.0),
		"slower": float(info["slower"]) * (GROWN_PACE if grown >= 1 else 1.0), "dodge": float(info["dodge"]), "weapons": weapons, "crew": crew,
		"reward": int(info["reward"]), "loot": info["loot"], "room_sys": _lay_out(layout, true, teleport),
		"boss": kind, "teleport": teleport,
		"fx": fx, "armour": float(info.get("armour", 0.0)), "guard": float(info.get("guard", 0.0)) >= 1.0 or grown >= 4,
	}


func upgrades() -> int:
	## (v57) How many guns the flagship adds for how far our ship is armed past its
	## start. (v58, the author: it grows by half of our tier points) (v67, the author's O1:
	## the flagship grows only with time, never with our guns or gear, so upgrading is
	## never a trap.) Nothing now; kept for the guns `extra` a later rule may give.
	return 0


const HARD_REWARD := 0.75            # (v63) on the hard mode a pirate ship pays this much of its reward
const GROWN_PACE := 0.8              # (v63) grown one step, its guns charge in this much of the time
const GROWN_REGEN := 1.5             # (v63) grown two steps, its shield refills this much faster (and each of its systems takes one more hit)
const GEAR_HULL := 2                 # (v59) the flagship's hull grows this much per step of our gear...
const GEAR_REGEN := 0.1              # ... and its shield refills this much faster


func gear_upgrades() -> int:
	## (v59) Our gear grew the flagship too, by half its tier points (Outfit.tier_points).
	## (v67, the author's O1) No more: it grows only with time (Flagship.growth).
	return 0


func tier_points() -> int:
	var n := 0
	for w in server.ship.mounts:
		n += maxi(Weapons.tier(w) - 1, 0)
	return n


func _lay_out(layout: int, shielded: bool, teleport: bool = false, drone: bool = false) -> PackedByteArray:
	## Its systems, each in a room of the hull picked by lot; the rooms left over are empty.
	## (v62) A drone ship has no cockpit, quarters or jump drive room, but a control core.
	var rooms: Array = server.map.others[layout].rooms
	var out := PackedByteArray()
	out.resize(rooms.size())
	out.fill(Net.ROOM_EMPTY)
	var order := range(rooms.size())
	_shuffle(order)
	var k := 0
	for system in Net.ESYS_COUNT:
		if (system == Net.ESYS_SHIELDS and not shielded) or (system == Net.ESYS_TELEPORT and not teleport) \
				or (system == Net.ESYS_DRONES and not drone) \
				or (drone and (system == Net.ESYS_HELM or system == Net.ESYS_CREW or system == Net.ESYS_JUMP)):
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
