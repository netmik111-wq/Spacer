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
	return "секторов пройдено: %d, продержались %s, в резерве %d" % [(data.get("been", []) as Array).size(),
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
	var floor := {}
	for cell: int in server.floor_things:
		if not map.is_other(cell):
			floor[str(cell)] = Array(server.floor_things[cell])
	var crew: Array = []
	var here := {}
	for p in server.players:
		if p == null or p.bot or p.pirate or map.is_other(p.st.y * map.width + p.st.x):
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
		"store": store, "store_air": server.ship.store_air, "credits": server.ship.credits,
		"reserve": server.reserve, "hull": server.ship.hull, "voyage": server.voyage_ticks,
		"jumps": server.jumps, "farthest": server.farthest, "dead_names": server.dead_names.keys(),
		"holes": holes, "broken": broken,
		"air": Marshalls.raw_to_base64(server.air.air.to_byte_array()),
		"jammed": Marshalls.raw_to_base64(jammed), "faulty": Marshalls.raw_to_base64(faulty),
		"floor": floor, "crew": crew,
	}


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
	server.been = {}
	for k in data["been"]:
		server.been[int(k)] = true
	var at := Vector2i(int(data["at"][0]), int(data["at"][1]))
	server.been[Sectors.key(at)] = true
	server.sectors.build(server.space_seed, at, server.been)
	server.ship.sector = server.sectors.here
	server.ship.pos = Vector2(float(data["pos"][0]), float(data["pos"][1]))
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	server.ship.in_reach = server.sectors.within_reach(server.ship.sector, server.ship.pos)
	server.ship.store.clear()
	for item: String in data["store"]:
		server.ship.store[int(item)] = int(data["store"][item])
	server.ship.store_air = float(data["store_air"])
	server.ship.credits = int(data["credits"])
	server.reserve = int(data["reserve"])
	server.ship.hull = int(data["hull"])
	server.voyage_ticks = int(data["voyage"])
	server.jumps = int(data["jumps"])
	server.farthest = int(data["farthest"])
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
