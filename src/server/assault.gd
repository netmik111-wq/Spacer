extends RefCounted
## (v62, the author's road plan: enemies) Boarders who come across without
## docking. Server only.
##
## Teleport (the author's E5: "teleporting boarders from about 8 jumps"): an
## ordinary pirate ship may carry a teleporter (Shipyard rolls it, Hulls says
## how often). TELEPORT_FIRST seconds into the fight, and every TELEPORT_SECONDS
## after, while its teleporter works and somebody of its crew is at it, it puts
## TELEPORT_PARTY of its own crew into a room of our ship, by lot. They leave
## its crew (Gunnery.crew_sent keeps the counts in step) and never leave it with
## fewer than TELEPORT_KEEP. Those who come this way may be without suits
## (Pirates.spawn_boarder). The flagship's carrier teleports on its own rules
## (Flagship).
##
## Assault drones (the author's E1: drone ships "assault with drones"): a drone
## ship whose control core works, and the battleship flagship in its second
## phase, send an assault drone across every DRONE_SECONDS (the first one
## DRONE_FIRST seconds in). It flies for DRONE_FLIGHT seconds; our point
## defence, if charged, shoots it down Weapons.GUARD_HIT of the time. One that
## gets there cuts through our hull and comes in: a robot that fights like a
## pirate (Pirates.spawn_robot) and needs no air. No more than DRONES_ABOARD
## are aboard at once.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Player := preload("res://src/server/player.gd")

const TELEPORT_FIRST := 25.0
const TELEPORT_SECONDS := 45.0
const TELEPORT_PARTY := 2
const TELEPORT_KEEP := 2             # it keeps this many of its crew at home
const DRONE_FIRST := 20.0
const DRONE_SECONDS := 35.0
const DRONE_FLIGHT := 3.0
const DRONES_ABOARD := 2

var server: GameServer
var drone_seconds := DRONE_SECONDS   # (tests set it)
var _teleport_at := -1
var _drone_at := -1
var _landing := PackedInt32Array()   # ticks the assault drones on their way get there
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	_rng.randomize()
	enemy_arrives()


func enemy_arrives() -> void:
	## A pirate ship has come: its clocks start.
	_teleport_at = server.tick + roundi(TELEPORT_FIRST * Net.TICK_HZ)
	_drone_at = server.tick + roundi(DRONE_FIRST * Net.TICK_HZ)
	_landing = PackedInt32Array()


func tick() -> void:
	var g = server.gunnery
	if not g.fighting():
		_landing = PackedInt32Array()
		return
	if g.teleport and g.boss == 0 and server.tick >= _teleport_at:
		_teleport_at = server.tick + roundi(TELEPORT_SECONDS * Net.TICK_HZ)
		teleport()
	if sends_drones() and server.tick >= _drone_at:
		_drone_at = server.tick + roundi(drone_seconds * Net.TICK_HZ)
		launch()
	var still := PackedInt32Array()
	for t in _landing:
		if server.tick >= t:
			_drone_lands()
		else:
			still.append(t)
	_landing = still


# ---------------------------------------------------------------- teleport

func teleport() -> int:
	## Its teleporter puts some of its crew aboard us. How many came (0 = none could).
	var g = server.gunnery
	var em = server.enemy_crew
	if g.down(Net.ESYS_TELEPORT) or not em.manned(Net.ESYS_TELEPORT) or em.in_world:
		return 0
	var n := mini(mini(TELEPORT_PARTY, g.boarders_left() - TELEPORT_KEEP), server.pirates.MAX_ABOARD - server.pirates.aboard())
	if n <= 0:
		return 0
	var cells := landing_cells()
	if cells.is_empty():
		return 0
	var room: int = g.room_of_system(Net.ESYS_TELEPORT)
	g.crew_sent(n, room)
	var w: int = server.map.width
	var where := ""
	for i in n:
		var c: int = cells[_rng.randi_range(0, cells.size() - 1)]
		cells.remove_at(cells.find(c))
		server.pirates.spawn_boarder(c % w, c / w, _rng.randf() < 0.6)
		where = server.map.deck_names[server.map.deck_of(c / w)].to_lower()
		if cells.is_empty():
			break
	g.reveal(room, "Вспышка выдала отсек пиратов")
	server.chat.alarm("Вспышка телепорта! Пираты высадили к нам на борт абордажников (%d, %s). Их телепорт можно выбить из орудий; у них осталось %d человек." % [
		n, where, g.boarders_left()])
	return n


func landing_cells() -> PackedInt32Array:
	## The free floor of one room of our ship, by lot: where teleported boarders appear.
	var map = server.map
	var rooms: Array = []
	for r in map.rooms.size():
		var cells: PackedInt32Array = map.rooms[r]
		if cells.size() >= 3 and map.on_ship(cells[0]):
			rooms.append(r)
	if rooms.is_empty():
		return PackedInt32Array()
	var room: int = rooms[_rng.randi_range(0, rooms.size() - 1)]
	var out := PackedInt32Array()
	for c: int in map.rooms[room]:
		if map.door_of[c] < 0 and map.climb[c] < 0 and not _someone_at(c):
			out.append(c)
	return out


func _someone_at(cell: int) -> bool:
	var w: int = server.map.width
	for p: Player in server.players:
		if p != null and not p.corpse and p.st.y * w + p.st.x == cell:
			return true
	return false


# ---------------------------------------------------------------- assault drones

func sends_drones() -> bool:
	## Does the enemy send assault drones now: a drone ship whose core works, or
	## the battleship flagship in its second phase?
	var g = server.gunnery
	return g.fighting() and ((g.crewless and not g.down(Net.ESYS_DRONES)) or (g.boss == 1 and g.phase2))


func robots_aboard() -> int:
	var n := 0
	for p: Player in server.players:
		if p != null and p.pirate and p.robot and not p.corpse and p.cond != Net.COND_DEAD \
				and server.map.on_ship(p.st.y * server.map.width + p.st.x):
			n += 1
	return n


func launch() -> bool:
	## One assault drone sets off for us. False if none went (enough aboard), or it was shot down.
	var g = server.gunnery
	if robots_aboard() + _landing.size() >= DRONES_ABOARD:
		return false
	if g.guard_ready():
		g.guard_charge = 0.0
		var map = server.map
		if map.guns.size() > 0:
			server.combat.jolt(Net.JOLT_FIRE, Weapons.GUARD, Vector2(map.guns[0] % map.width, map.guns[0] / map.width))
		if _rng.randf() < Weapons.GUARD_HIT:
			server.chat.say("«Заслон» сбил штурмовой дрон на подлёте.")
			return false
	_landing.append(server.tick + roundi(DRONE_FLIGHT * Net.TICK_HZ))
	server.chat.say("Враг выпустил штурмовой дрон: он идёт к нашей обшивке!")
	return true


func _drone_lands() -> void:
	var inside: Vector2i = server.pirates.cut_in()
	if inside.x < 0:
		return
	server.pirates.spawn_robot(inside.x, inside.y)
	server.chat.alarm("Штурмовой дрон прорезал обшивку и ворвался на борт (%s)! %s" % [
		server.map.deck_names[server.map.deck_of(inside.y)].to_lower(), "Он вооружён, воздух ему не нужен."])
