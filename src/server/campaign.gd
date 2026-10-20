extends RefCounted
## The campaign saved between evenings: one file the server writes now and
## then and reads back when a game is continued.
##
## What is kept is what a crew would be sorry to lose: where in space the ship
## is and where it has been, its supplies, money, reserve and hull, what is
## broken or holed, the air in every compartment, what lies on the floor, the
## bodies, and every player's character by name (where it stood, its health,
## what it carried and wore, its job and skills). A player who comes back
## under the same name gets their character back.
## Not kept: a derelict or pirate ship alongside (it has gone by the next
## evening), the director's mood, pirates aboard, and bots.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Gear := preload("res://src/shared/gear.gd")

const PATH := "user://campaign.json"
const VERSION := 1
const AUTOSAVE_TICKS := 60 * Net.TICK_HZ


static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func summary(path: String = PATH) -> String:
	## A line for the menu about the saved campaign, or "" if there is none.
	var data := read(path)
	if data.is_empty():
		return ""
	var minutes := int(data.get("voyage", 0)) / Net.TICK_HZ / 60
	return "%s, секторов пройдено: %d, продержались %s, в резерве %d" % [Net.MODE_NAMES[clampi(int(data.get("mode", 0)), 0, 2)].to_lower() + " режим",
		(data.get("been", []) as Array).size(),
		("%d ч %02d мин" % [minutes / 60, minutes % 60]) if minutes >= 60 else ("%d мин" % minutes), int(data.get("reserve", 0))]


static func read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		return {}
	return data


static func forget(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func write(server: Node, path: String = PATH) -> bool:
	var data := snapshot(server)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	# replace the old file only once the new one is whole
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


static func snapshot(server: Node) -> Dictionary:
	var map = server.map
	var been: Array = []
	for k: int in server.been:
		been.append(k)
	var store := {}
	for item: int in server.ship.store:
		store[str(item)] = server.ship.store[item]
	if server.robots != null and server.robots.pack_up() > 0:
		# (v62) our security robots still standing go back into the locker in their crates
		store[str(Net.ITEM_ROBOT)] = int(server.ship.store.get(Net.ITEM_ROBOT, 0)) + server.robots.pack_up()
	var holes: Array = []
	for cell: int in server.air.holes:
		if not map.is_other(cell):
			holes.append(cell)
	var broken: Array = []
	for cell: int in server.ship.broken:
		if not map.is_other(cell):
			broken.append(cell)
	var own_doors: int = map.other_first_door if map.other_kind >= 0 else map.doors.size()
	var jammed: PackedByteArray = server.doors.jammed.slice(0, own_doors)
	var faulty: PackedByteArray = server.doors.faulty.slice(0, own_doors)
	var picked: PackedByteArray = server.doors.picked.slice(0, own_doors)
	var floor := {}
	for cell: int in server.floor_things:
		if not map.is_other(cell):
			floor[str(cell)] = Array(server.floor_things[cell])
	var crew: Array = []
	var here := {}
	for p in server.players:
		if p == null or p.bot or p.pirate or p.ally or map.is_other(p.st.y * map.width + p.st.x):
			continue
		crew.append(character(p))
		if not p.corpse:
			here[p.name] = true
	for c: Dictionary in server.saved_crew.values():
		if not here.has(c["name"]):
			crew.append(c)                   # left this evening, or not back yet since the last
	return {
		"version": VERSION, "map": map.map_name,
		"seed": server.space_seed, "been": been,
		"at": [server.sectors.cell[server.ship.sector].x, server.sectors.cell[server.ship.sector].y],
		"pos": [server.ship.pos.x, server.ship.pos.y],
		"store": store, "store_air": server.ship.store_air, "credits": server.ship.credits, "tank": server.ship.tank,
		"reserve": server.reserve, "hull": server.ship.hull, "voyage": server.voyage_ticks,
		"jumps": server.jumps, "farthest": server.farthest, "won": server.won, "dead_names": server.dead_names.keys(),
		"holes": holes, "broken": broken,
		"air": Marshalls.raw_to_base64(server.air.air.to_byte_array()),
		"jammed": Marshalls.raw_to_base64(jammed), "faulty": Marshalls.raw_to_base64(faulty), "picked": Marshalls.raw_to_base64(picked),
		"floor": floor, "crew": crew, "admins": server.admin.names.keys(),
		"mounts": Array(server.ship.mounts), "armed": Array(server.ship.armed),
		"shield_on": server.ship.shield_on, "hardened": server.ship.hardened,
		"mount_fx": Array(server.ship.mount_fx), "guard": server.ship.guard, "guard_armed": server.ship.guard_armed,
		"loaded": Array(server.mounts.loaded), "panel": server.power.save_panel(),
		"bought": _keyed(server.supplies.bought), "sold": _keyed(server.supplies.sold),
		"gear": Array(server.ship.gear), "modules": Array(server.ship.modules),
		"smes": server.power.save(),
		"mode": server.mode, "hull_max": server.ship.hull_max,               # (v63)
		"complex": server.complex_repairs,                                      # (v71)
		"story": server.story.save(), "roam": server.flagship.save(), "garden": server.garden.save(),
		"road": server.road.save(),                                          # (v64)
	}


static func _keyed(d: Dictionary) -> Dictionary:
	## (v58) A dictionary by place in space (Sectors.key) with its keys as text, for JSON.
	var out := {}
	for k: int in d:
		out[str(k)] = d[k]
	return out


static func _unkeyed(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[int(k)] = d[k]
	return out


static func character(p: RefCounted) -> Dictionary:
	return {
		"name": p.name, "corpse": p.corpse or p.cond == Net.COND_DEAD, "colour": p.colour,
		"x": p.st.x, "y": p.st.y, "facing": p.st.facing,
		"health": p.health, "wounds": p.wounds, "tank": p.tank, "supply": p.supply,
		"slots": Array(p.slots), "worn": Array(p.worn), "hand": p.hand,
		"job": p.job, "skills": Array(p.skills),
	}


static func restore(server: Node, data: Dictionary) -> String:
	## Puts a freshly started server back where the saved campaign was. Returns "" or what was wrong.
	var map = server.map
	if str(data.get("map", "")) != map.map_name:
		return "Сохранённая кампания сыграна на другом корабле."
	server.space_seed = int(data["seed"])
	server.won = bool(data.get("won", false))
	server.been = {}
	var at := Vector2i(int(data["at"][0]), int(data["at"][1]))
	var old_map := not data.has("road")      # (v64, the author's C19) saved on the endless grid of before
	if old_map:
		# it goes on at the start of a fresh first cluster: the old map's places are gone (my V11)
		at = Vector2i.ZERO
		server.road.setup(server)
	else:
		for k in data["been"]:
			server.been[int(k)] = true
		server.road.load_from(data["road"])
	server.been[Sectors.key(at)] = true
	server.road.build(at)
	server.ship.sector = server.sectors.here
	server.ship.pos = Vector2(float(data["pos"][0]), float(data["pos"][1])) if not old_map else server.sectors.entry[server.ship.sector]
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	server.ship.in_reach = server.sectors.within_reach(server.ship.sector, server.ship.pos)
	server.ship.store.clear()
	for item in Items.kept_in_locker():
		server.ship.store[item] = 0          # (things new since the save was made: none of them)
	for item: String in data["store"]:
		server.ship.store[int(item)] = int(data["store"][item])
	if not (data["store"] as Dictionary).has(str(Net.ITEM_FOOD)):
		server.ship.store[Net.ITEM_FOOD] = Items.stock(Net.ITEM_FOOD)   # (v63) a save from before food: the start's rations
	server.ship.store_air = float(data["store_air"])
	server.ship.credits = int(data["credits"])
	server.ship.tank = float(data.get("tank", Net.FUEL_START))     # (v67; an older save: a fresh tank)
	server.reserve = int(data["reserve"])
	server.mode = int(data.get("mode", Net.MODE_NORMAL))           # (v63; older saves: the normal mode)
	server.complex_repairs = bool(data.get("complex", false))      # (v71; older saves: plain repairs)
	server.ship.hull_max = int(data.get("hull_max", Net.HULL_MAX))
	server.ship.hull = int(data["hull"])
	server.power.load_panel(data.get("panel", {}))          # (v68) the power panel's breakers and engines
	if data.has("mounts"):
		var mounts := PackedByteArray(data["mounts"])
		var armed := PackedByteArray(data.get("armed", []))
		if mounts.size() == server.ship.mounts.size() and armed.size() == mounts.size():
			server.ship.mounts = mounts
			server.ship.armed = armed
		server.ship.shield_on = bool(data.get("shield_on", true))
		server.ship.hardened = bool(data.get("hardened", false))
		var fx := PackedByteArray(data.get("mount_fx", []))
		server.ship.mount_fx.fill(0)
		if fx.size() == server.ship.mount_fx.size():
			server.ship.mount_fx = fx
		server.ship.guard = int(data.get("guard", 0))
		server.ship.guard_armed = bool(data.get("guard_armed", false))
		var loaded := PackedByteArray(data.get("loaded", []))   # (v68)
		if loaded.size() == server.mounts.loaded.size():
			server.mounts.loaded = loaded
	else:
		server.ship.hull = mini(server.ship.hull * 2, server.ship.hull_max)   # saved before v49, when the hull was 100
	server.supplies.bought.clear()
	server.supplies.sold.clear()
	server.supplies._offers_for = -1
	for k: int in _unkeyed(data.get("bought", {})):
		var gone: Array = []
		for item in data["bought"][str(k)]:
			gone.append(int(item))
		server.supplies.bought[k] = gone
	for k: int in _unkeyed(data.get("sold", {})):
		var back: Array = []
		for e in data["sold"][str(k)]:
			back.append([int(e[0]), int(e[1])])
		server.supplies.sold[k] = back
	# (v59) the ship's gear
	var gear := PackedByteArray(data.get("gear", []))
	while gear.size() < Gear.SYSTEMS:
		gear.append(1)                       # (v61) a save from before the SMES coils: built-in ones
	server.ship.gear = gear if gear.size() == Gear.SYSTEMS else PackedByteArray([1, 1, 1, 1, 1])
	var modules := PackedByteArray(data.get("modules", []))
	server.ship.modules = modules if modules.size() >= Gear.MODULE_SLOTS and modules.size() <= Gear.MODULE_SLOTS_MAX \
		else PackedByteArray([0, 0])         # (v62) three with the bay's extender
	server.ship.phase_ready = 0
	server.outfit.refresh()
	server.story.load_from(data.get("story", {}))
	server.flagship.load_from(data.get("roam", {}))
	if old_map:
		server.story.moved_to_clusters()
		server.flagship.awake = false        # (it waits in its own cluster now; its growth is kept)
		server.flagship.at = server.flagship.goal()
	server.garden.load_from(data.get("garden", {}))
	server.power.load_from(data.get("smes", []))     # (v61; an older save keeps the SMES as it starts: full)
	server.voyage_ticks = int(data["voyage"])
	server.jumps = int(data["jumps"])
	server.farthest = int(data["farthest"])
	server.admin.names.clear()
	for n in data.get("admins", []):
		server.admin.names[str(n)] = true
	server.dead_names.clear()
	for n in data["dead_names"]:
		server.dead_names[str(n)] = true
	var air_saved := Marshalls.base64_to_raw(str(data["air"])).to_float32_array()
	if air_saved.size() == server.air.air.size():
		server.air.air = air_saved
	for cell in data["holes"]:
		server.air.set_hole(int(cell), true)
	server.air.wake()
	for cell in data["broken"]:
		server.ship.broken[int(cell)] = true
	var jammed := Marshalls.base64_to_raw(str(data["jammed"]))
	var faulty := Marshalls.base64_to_raw(str(data["faulty"]))
	for d in mini(jammed.size(), server.doors.jammed.size()):
		server.doors.jammed[d] = jammed[d]
		server.doors.faulty[d] = faulty[d] if d < faulty.size() else 0
		if jammed[d] == 1:
			server.doors.ready[d] = 0                # stuck open
	var picked := Marshalls.base64_to_raw(str(data.get("picked", "")))    # (v69)
	for d in mini(picked.size(), server.doors.picked.size()):
		server.doors.picked[d] = picked[d]
	server.floor_things.clear()
	for cell: String in data["floor"]:
		server.floor_things[int(cell)] = PackedByteArray(data["floor"][cell])
	server.saved_crew.clear()
	for c: Dictionary in data["crew"]:
		if not bool(c["corpse"]):
			server.saved_crew[str(c["name"])] = c
	for c: Dictionary in data["crew"]:
		if bool(c["corpse"]):
			server.crew.restore_body(c)
			if not server.saved_crew.has(str(c["name"])):
				server.dead_names[str(c["name"])] = true   # died and never came back: that takes the reserve
	return ""
