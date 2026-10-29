extends RefCounted
## (v85, the author's FS1-FS8) Our fleet: up to Net.FLEET_MAX crewed ships of ours, laid one below another in
## the one grid (ShipMap fleet names, see MapBuilder.fleet_text). Each has its own hull, power, air plant,
## guns and shield, lockers, fuel and food, bots and posts; they fly and jump together (either helm moves
## them all), share one purse, and the run is lost only when every ship is lost.
##
## The rest of the server was written for one ship, and still is: `server.ship` and the parts' state are
## "the ship we work for now". This part keeps every ship's own share of that state and puts one ship's in
## place at a time (use): the Ship itself, the ship's own fittings in the map (ShipMap.use_ship), and the
## fields of the parts named in OWN. A tick runs the ship-wide parts once per ship; whatever a player
## does is done for the ship they stand in (use_for). With one ship nothing ever changes place.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Ship := preload("res://src/server/ship.gd")
const Player := preload("res://src/server/player.gd")

# part -> the fields each ship has its own of
const OWN := {
	"power": ["units", "_told", "_was_on", "breaker", "engines", "over_until", "over_rest_until"],
	"outfit": ["_told"],
	"mounts": ["gunners", "wanted", "loaded", "clip", "_told"],
	"gunnery": ["charge", "beam_left", "_beam_next", "_beam_room", "_beam_log", "guard_charge", "aim", "_told", "foe"],
	"stations": ["position", "goal", "manoeuvre_until", "spots", "_at", "_lapse", "_sabotage", "_told", "evade_until",
		"evade_ready", "meteor_at", "meteor_tried", "meteor_missed", "alert", "_alert_auto", "_fight_seen"],
	"garden": ["plants", "stage", "growth", "care_at", "neglect", "hunger", "_hungry", "starved", "_sent"],
	"holomap": ["cells"],
	"crew": ["_campaign_told"],
}
# the parts whose setup makes every ship's own state (run for each ship after the first at the start)
const SETUPS: Array[String] = ["power", "gunnery", "mounts", "stations", "garden", "holomap", "outfit"]
const TARGET_WEAKER := 0.7           # (the author's FS5) the share of pirates that pick the weaker ship of ours

var server: GameServer
var ships: Array = []                # Ship per ship of the fleet; [0] is the first (the lead)
var on := 0                          # the ship whose state is in place now
var lost: Array = []                 # per ship: it is lost (its hull broke): dark, out of the fight
var _kept: Array = []                # per ship: "part.field" -> its own value while another is in place


func setup(p_server: GameServer) -> void:
	server = p_server
	ships = [server.ship]
	lost = [false]
	on = 0
	_kept = [{}]
	for i in range(1, server.map.fleet_size()):
		var s := Ship.new()
		s.id = server.new_ship_id()
		s.kind = Net.SHIP_CREW
		s.map = server.map
		s.name = server.map.fleet_names[i]
		s.purse = server.ship
		var lead: Ship = server.ship         # starts as the first one does (GameServer.start)
		s.store = lead.store.duplicate()
		s.store_air = lead.store_air
		s.tank = lead.tank
		s.hull_max = lead.hull_max
		s.hull = lead.hull
		s.sector = lead.sector
		s.pos = lead.pos
		s.dest = lead.dest
		s.in_reach = lead.in_reach
		ships.append(s)
		lost.append(false)
		_kept.append({})


func size() -> int:
	return ships.size()


func many() -> bool:
	return ships.size() > 1


func each(work: Callable) -> void:
	## Runs `work` once for every ship, with that ship's state in place; the first is in place after.
	for i in ships.size():
		use(i)
		work.call()
	use(0)


func prepare(setups: Array[String]) -> void:
	## At the start (the first ship is in place): every other ship's own state made by those parts' setup.
	for i in range(1, ships.size()):
		use(i)
		for part: String in setups:
			server.get(part).setup(server)
	use(0)


func use(i: int) -> void:
	if i == on or i < 0 or i >= ships.size():
		return
	var keep: Dictionary = _kept[on]
	var put: Dictionary = _kept[i]
	for part: String in OWN.keys():
		var o: Object = server.get(part)
		for f: String in OWN[part]:
			var key := part + "." + f
			keep[key] = o.get(f)
			if put.has(key):
				o.set(f, put[key])
			elif typeof(keep[key]) >= TYPE_DICTIONARY:
				# (its first time in place: not the other ship's own; v87: packed arrays too, which Godot
				# passes by reference: the ships shared their guns' charge, so one ship's shot emptied both)
				o.set(f, keep[key].duplicate(true) if not _packed(keep[key]) else keep[key].duplicate())
	on = i
	server.ship = ships[i]
	server.map.use_ship(i)


static func _packed(v: Variant) -> bool:
	return typeof(v) > TYPE_ARRAY


func of_cell(cell: int) -> int:
	## The ship a cell is in (the one in place for a cell of the ship alongside or of space between).
	var i: int = server.map.fleet_of(cell)
	return i if i >= 0 else on


func mine(cell: int) -> bool:
	## Is that cell in the ship in place now?
	return ships.size() < 2 or server.map.fleet_of(cell) == on


func use_cell(cell: int) -> void:
	if ships.size() > 1:
		use(of_cell(cell))


func use_for(p: Player) -> void:
	## The ship that player stands in; out in space or on the ship alongside, their own.
	if ships.size() < 2 or p == null:
		return
	var i: int = server.map.fleet_of(p.st.y * server.map.width + p.st.x)
	use(i if i >= 0 and not server.map.floats(p.st.x, p.st.y) else clampi(p.fleet_ship, 0, ships.size() - 1))


func is_lost(i: int = -1) -> bool:
	## Is that ship (the one in place) lost: its hull broke (the author's FS6)?
	i = on if i < 0 else i
	return i < lost.size() and bool(lost[i])


func standing() -> int:
	## How many of our ships are not lost.
	return lost.count(false)


func ship_lost() -> void:
	## The hull of the ship in place gave way while another of ours still stands: it goes dark and
	## drops out of the fight; the run goes on. Mended above nothing again (from outside), it comes back.
	lost[on] = true
	server.chat.alarm("Корабль %s потерян: обшивка не выдержала, он обесточен. Флотилия идёт дальше; его можно залатать снаружи." % name_of(on))
	server.systems.power_changed()


func name_of(i: int) -> String:
	## How chat names a ship of the fleet: by its number (both may be drawn alike).
	return str(i + 1)


func target() -> int:
	## (FS5) The ship of ours a pirate who comes picks to fight and board: mostly the weaker one.
	var best := -1
	var others: Array[int] = []
	for i in ships.size():
		if is_lost(i):
			continue
		others.append(i)
		if best < 0 or (ships[i] as Ship).hull * (ships[best] as Ship).hull_max < (ships[best] as Ship).hull * (ships[i] as Ship).hull_max:
			best = i
	if others.is_empty():
		return 0
	if others.size() > 1 and server.mode != Net.MODE_HARD and server.rng.randf() >= TARGET_WEAKER:   # (v86, the author's N3: hard focuses)
		return others[server.rng.randi_range(0, others.size() - 1)]
	return best


func can_jump(long_jump: bool) -> String:
	## "" or which ship has too little fuel for the jump (every ship not lost jumps on its own fuel).
	var was := on
	var short := ""
	for i in ships.size():
		if is_lost(i):
			continue
		use(i)
		if not server.ship.can_jump(long_jump):
			short = "Прыгнуть не на чем: кораблю %s нужно %d единиц топлива в баке, а там %d. Залейте канистры у его двигателя." % [
				name_of(i), server.outfit.jump_fuel(long_jump), floori(server.ship.tank)]
			break
	use(was)
	return short


func burn_jump(long_jump: bool) -> void:
	## Every ship not lost burns its own engine's fuel for the jump.
	var was := on
	for i in ships.size():
		if not is_lost(i):
			use(i)
			server.ship.tank = maxf(server.ship.tank - server.outfit.jump_fuel(long_jump), 0.0)
			server.supplies.tell_store()
	use(was)


func follow() -> void:
	## The other ships fly with the first: its place, course and jumps are theirs; each burns its own fuel.
	if ships.size() < 2:
		return
	var lead: Ship = ships[0]
	for i in range(1, ships.size()):
		var s: Ship = ships[i]
		var nav := s.sector != lead.sector or s.jump_to != lead.jump_to or s.jump_tick != lead.jump_tick or s.drive_ready != lead.drive_ready
		var helm := s.moving != lead.moving or s.dest != lead.dest or (not lead.moving and s.pos != lead.pos)
		if lead.moving and lead.jump_to == Net.NO_SECTOR and not is_lost(i) and (not server.arena.flying() or server.arena.pushing()):
			s.tank = maxf(s.tank - s.pos.distance_to(lead.pos) * Net.FLIGHT_FUEL, 0.0)
			if s.tank <= 0.0:
				lead.dest = lead.pos
				lead.moving = false
				server.arena.course = false
				server.to_all(lead.helm_packet(server.tick))
				server.chat.say("Баки корабля %s опустели: флотилия легла в дрейф. Залейте канистру топлива у его двигателя." % name_of(i))
				helm = true
		s.sector = lead.sector
		s.jump_to = lead.jump_to
		s.jump_tick = lead.jump_tick
		s.drive_ready = lead.drive_ready
		s.pos = lead.pos
		s.dest = lead.dest
		s.moving = lead.moving
		s.in_reach = lead.in_reach
		if nav:
			server.to_all(s.nav_packet())
		if helm:
			server.to_all(s.helm_packet(server.tick))


func tick() -> void:
	if ships.size() < 2:
		return
	for i in ships.size():
		if is_lost(i) and (ships[i] as Ship).hull > 0:
			lost[i] = false                  # its hull mended from outside: it is ours again
			server.chat.say("Корабль %s снова держит обшивку и снова в строю." % name_of(i))
	# who is aboard which ship: the client is told, and told that ship's state anew
	for p: Player in server.players:
		if p == null or p.peer == null or p.corpse:
			continue
		use_for(p)
		if p.aboard != on:
			p.aboard = on
			board(p)
	use(0)


func board(p: Player) -> void:
	## Tells a player the ship they are now aboard (Net.S_BOARD) and everything about it.
	var s: Ship = server.ship
	var msg := PackedByteArray([Net.S_BOARD, s.id & 0xFF, s.id >> 8, on])
	p.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	for pkt: PackedByteArray in [s.nav_packet(), s.helm_packet(server.tick), s.devices_packet(), s.power_packet(),
			s.store_packet(), server.crew.campaign_packet()]:
		p.peer.send(0, pkt, ENetPacketPeer.FLAG_RELIABLE)
	# what the ship's parts last told everybody is told again (only those aboard take it)
	for part: String in ["power", "outfit", "mounts", "gunnery", "stations", "garden"]:
		server.get(part).set("_told", PackedByteArray())


func index_of(s: Ship) -> int:
	return ships.find(s)


func by_id(id: int) -> int:
	for i in ships.size():
		if (ships[i] as Ship).id == id:
			return i
	return -1
