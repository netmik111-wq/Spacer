extends RefCounted
## (v61, the author's K16 and my V11-V14 picks) The hazards of space, for us and
## for whoever fights us there. Server only.
##
## An ion storm is a kind of sector (Sectors.ION_STORM). Inside it our reactor
## gives half (Power.reactor_now asks in_storm), and every SURGE_MIN..SURGE_MAX
## seconds a surge puts out one of our guns, the shield generator, the point
## defence or an SMES for SURGE_SECONDS (never the engine nor a console, so a way
## out always stays). The storm is no kinder to a pirate fighting us there: its
## guns charge STORM_PACE times slower, its shield refills at STORM_REGEN of its
## pace, and the same surges put out one of its systems.
## A meteor that strikes our hull in a fight strikes the pirate ship alongside
## too (meteor_on_enemy: a point off its hull and a point of wear on a room).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Player := preload("res://src/server/player.gd")

const SURGE_MIN := 40.0              # seconds between surges, at the least
const SURGE_MAX := 70.0
const SURGE_SECONDS := 10.0          # what a surge puts out stays out this long
const STEER_CLEAR := 0.4             # (v70, the author's H2) a pilot at the controls steers clear of a surge this often...
const STEER_SKILL := 0.2             # ... and this much more with the best skill (a bot at the controls: half)
var steer_roll := -1.0               # (tests: a fixed lot; -1 = dice)
const STORM_PACE := 1.5              # a pirate's guns charge this many times slower in a storm
const STORM_REGEN := 0.5             # and its shield refills at this share of its pace

var server: GameServer
var _next_surge := 0                 # the tick of the next surge (0 = not in a storm)
var _rng := RandomNumberGenerator.new()   # its own lots, so the game's own sequence stays as it was


func setup(p_server: GameServer) -> void:
	server = p_server
	_rng.seed = 6161


func in_storm() -> bool:
	## Is our ship inside an ion storm now?
	return server.navigation != null and server.navigation.sector_kind() == Sectors.ION_STORM and server.ship.in_reach


func storm_changed(now_in: bool, quiet: bool = false) -> void:
	## The ship went into the storm or came out of it.
	_next_surge = server.tick + _gap() if now_in else 0
	if not quiet:
		server.chat.say("Корабль вошёл в ионный шторм: реактор даёт половину энергии, разряды будут выбивать системы." if now_in
			else "Корабль вышел из ионного шторма: реактор снова даёт полную энергию.")


func _gap() -> int:
	return roundi(_rng.randf_range(SURGE_MIN, SURGE_MAX) * Net.TICK_HZ)


func enemy_pace() -> float:
	## How fast a pirate's guns charge here, as a share of their own pace.
	return 1.0 / STORM_PACE if in_storm() else 1.0


func enemy_regen() -> float:
	return STORM_REGEN if in_storm() else 1.0


func tick() -> void:
	if not in_storm():
		_next_surge = 0
		return
	if _next_surge == 0:
		_next_surge = server.tick + _gap()
	if server.tick >= _next_surge:
		_next_surge = server.tick + _gap()
		surge()


func surge() -> String:
	## A surge of the storm: one thing of ours out for a while, and one of the pirate's in a fight.
	## Returns what was said (tests and the admin panel use it).
	var said := ""
	var cell := _our_victim()
	var pilot: Player = server.stations.at_post(Net.POST_HELM)
	if cell >= 0 and pilot != null and (steer_roll if steer_roll >= 0.0 else _rng.randf()) \
			< (STEER_CLEAR + STEER_SKILL * pilot.skill(Net.SKILL_PILOT)) * server.stations.share(pilot):
		cell = -1                            # (v70) the pilot took the ship round the discharge
		said = "Ионный разряд: %s уводит корабль в сторону, разряд проходит мимо." % pilot.name
	if cell >= 0:
		server.ship.jammed[cell] = server.tick + roundi(SURGE_SECONDS * Net.TICK_HZ)
		server.combat.jolt(Net.JOLT_HULL, 0, Vector2(cell % server.map.width, cell / server.map.width))
		said = "Ионный разряд: %s не работает %d с." % [_name(cell), roundi(SURGE_SECONDS)]
	var g = server.gunnery
	if g.fighting():
		var theirs: Array = []
		for sys in g.systems.size():
			if sys != Net.ESYS_CREW and g.systems_full[sys] > 0 and g.systems[sys] > 0:
				theirs.append(sys)
		if not theirs.is_empty():
			var sys: int = theirs[_rng.randi_range(0, theirs.size() - 1)]
			g.systems_out[sys] = maxi(g.systems_out[sys], server.tick + roundi(SURGE_SECONDS * Net.TICK_HZ))
			if sys == Net.ESYS_SHIELDS:
				g.enemy_shield = 0.0
			said += ("" if said == "" else " ") + "Разряд задел и пиратов: %s." % Net.ESYS_NAMES[sys].to_lower()
	if said == "":
		said = "Ионный разряд прошёл мимо."
	server.chat.say(said)
	return said


func _our_victim() -> int:
	## What a surge puts out: a gun with a weapon on it, the shield generator, the
	## point defence's mount (a gun console stands for it) or an SMES; never the engine nor a console.
	var map = server.map
	var ship = server.ship
	var can: Array = []
	for i in map.guns.size():
		if ship.mounts[i] != Weapons.NONE and not ship.broken.has(map.guns[i]):
			can.append(map.guns[i])
	var gen: int = server.gunnery.shield_cell()
	if gen >= 0 and not ship.broken.has(gen):
		can.append(gen)
	for c: int in map.smes.keys() + map.smes_small.keys():
		if not ship.broken.has(c):
			can.append(c)
	if can.is_empty():
		return -1
	return can[_rng.randi_range(0, can.size() - 1)]


func _name(cell: int) -> String:
	var map = server.map
	if map.guns.has(cell):
		return "орудие %d" % (map.guns.find(cell) + 1)
	return map.device_name(cell)


func meteor_on_enemy() -> void:
	## A meteor that struck us struck the pirate ship alongside too.
	var g = server.gunnery
	if not g.fighting():
		return
	g.enemy_hull -= 1
	var rooms := PackedInt32Array()
	for r in g.room_sys.size():
		rooms.append(r)
	var said := ""
	if not rooms.is_empty():
		var room := rooms[_rng.randi_range(0, rooms.size() - 1)]
		said = g._wear_room(g.system_in(room), room, 1)
	server.chat.say("Метеор задел и пиратский корабль." + ("" if said == "" else " " + said))
	g._settle()
