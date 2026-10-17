class_name GameServer
extends Node
## The authoritative game server. It owns the world: clients only send what
## keys they hold, the server decides where everyone is and tells each client
## what changed near it. Runs in one thread, 20 steps ("ticks") per second.
##
## The same node is used for a dedicated server (no window) and for hosting
## from inside the game; a hosting player connects to it like anyone else.
##
## This file holds the state of the world, the network loop and the order of
## a tick. What happens in the world is split by topic into parts the server
## keeps one of each (see each file for what it does):
##   chat         speech, radio, intercoms, sounds, lines from the ship
##   crew         players coming and going, bots, bodies, the reserve, health, losing the campaign
##   movement     walking, ladders, bots
##   inventory    things in the hands and on the floor, clothes, the suit's oxygen
##   looting      searching and dragging somebody lying down
##   combat       shots, blows, wounds, healing
##   repairs      the "use" key: mending, forcing shutters, filling tanks, pumps
##   systems      power, breakdowns, airlock pumps, the hull, doors
##   navigation   steering, jumps, sectors
##   supplies     the supply locker and the trader
##   replication  what each client is told, and which characters it may see
##   admin        the admin panel: giving things, healing, moving people, mending, events
##   holomap      the holomap monitors: the whole ship's air, holes and doors, to those watching
##   enemy_crew   (v54) the pirate ship's crew at their posts while it fights us
##   drone        (v54) the scouting drone, steered from the drone monitor
##   stations     (v55) our crew at their posts in a fight, bots under orders, the battle position, our boarders
##   flagship     (v57) the goal: the pirates' flagship, its teleporter, winning and losing the ship
##   workshop     (v58) the workbench: guns taken apart, mended and upgraded by engineers
## and, from before: director (events), pirates, derelict (another ship
## alongside), gunnery (ship's guns), campaign (saving), shipyard (v53: rolls
## every pirate ship that comes). The crew's ship itself
## is one object with a network id (Ship); another one alongside gets its own.

signal log_line(text: String)
signal shutdown_requested            # the hosting player's game asked this server to stop

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Player := preload("res://src/server/player.gd")
const Air := preload("res://src/server/air.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Director := preload("res://src/server/director.gd")
const Pirates := preload("res://src/server/pirates.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Shipyard := preload("res://src/server/shipyard.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Ship := preload("res://src/server/ship.gd")
const Chat := preload("res://src/server/chat.gd")
const Crew := preload("res://src/server/crew.gd")
const Movement := preload("res://src/server/movement.gd")
const Inventory := preload("res://src/server/inventory.gd")
const Looting := preload("res://src/server/looting.gd")
const Combat := preload("res://src/server/combat.gd")
const Repairs := preload("res://src/server/repairs.gd")
const Systems := preload("res://src/server/systems.gd")
const Navigation := preload("res://src/server/navigation.gd")
const Supplies := preload("res://src/server/supplies.gd")
const Replication := preload("res://src/server/replication.gd")
const Admin := preload("res://src/server/admin.gd")
const Holomap := preload("res://src/server/holomap.gd")
const EnemyCrew := preload("res://src/server/enemy_crew.gd")
const Drone := preload("res://src/server/drone.gd")
const Stations := preload("res://src/server/stations.gd")
const Flagship := preload("res://src/server/flagship.gd")
const Workshop := preload("res://src/server/workshop.gd")

const HELLO_TIMEOUT_MS := 5000      # a connection must introduce itself within this time
const MAX_INPUT_QUEUE := 32
const MAX_INPUT_LEAD := 40          # inputs stamped further ahead than this are pulled back

var port := Net.DEFAULT_PORT
var max_players := 32
var map := ShipMap.new()
var running := false
var tick := 0
var shutdown_token := ""            # only a client that knows this text may stop the server ("" = nobody)

var _host: ENetConnection = null
var _acc := 0.0
var pending := {}                   # peer -> msec when it connected (waiting for C_HELLO)
var slot_of := {}                   # peer -> slot
var players: Array = []             # slot -> Player, or null when the slot is free
var free_slots: Array[int] = []
var corpses: Array[int] = []        # slots of the bodies left behind, oldest first
var rng := RandomNumberGenerator.new()

# the grid both ships lie in: doors, air, what lies on the floor
var doors := Doors.new()
var air := Air.new()
var door_hold := PackedInt32Array()    # per door: it will not close before this tick
var door_sent := PackedInt32Array()    # per door: the state clients were last told
var flags_sent := PackedByteArray()    # per door: its troubles as clients were last told (see Doors.flags)
var forced_until := PackedInt32Array() # per door: its shutter was forced up and stays up until this tick
var floor_things := {}                 # things lying on the floor: cell -> PackedByteArray of Net.FLOOR_STACK
                                       # (bottom first, ITEM_NONE where there is nothing)

# the ships: the crew's own, and another alongside if there is one (Derelict.ship)
var ship := Ship.new()
var _next_ship_id := Net.CREW_SHIP + 1
var _ships_told := PackedByteArray()   # the list of ships as clients were last told

# space and the campaign
var sectors := Sectors.new()           # the part of space around the crew's ship
var space_seed := 0                    # what this game's space is made from
var been := {}                         # the sectors the ship has visited: Sectors.key -> true
var reserve := 0                       # crew members waiting to replace the dead
var over := Net.OVER_NONE              # how the campaign ended, or OVER_NONE while it goes on
var won := false                       # (v57) the flagship is beaten: the game is won, and the voyage goes on
var voyage_ticks := 0                  # ticks the campaign has lasted, over every evening it was played
var jumps := 0
var farthest := 0                      # the most jumps from the start the ship has been
var dead_names := {}                   # players whose character died and who left before coming back: name -> true
var saved_crew := {}                   # characters of the saved campaign whose players have not come back yet: name -> what was saved
var save_path := ""                    # where the campaign is saved ("" = nowhere: tests, see Campaign)

# the parts of the server, by topic
var director := Director.new()
var pirates := Pirates.new()
var derelict := Derelict.new()
var gunnery := Gunnery.new()
var shipyard := Shipyard.new()
var chat := Chat.new()
var crew := Crew.new()
var movement := Movement.new()
var inventory := Inventory.new()
var looting := Looting.new()
var combat := Combat.new()
var repairs := Repairs.new()
var systems := Systems.new()
var navigation := Navigation.new()
var supplies := Supplies.new()
var replication := Replication.new()
var admin := Admin.new()
var holomap := Holomap.new()
var enemy_crew := EnemyCrew.new()
var drone := Drone.new()
var stations := Stations.new()
var flagship := Flagship.new()
var workshop := Workshop.new()
var keep_heard := false                # tests: remember in Player.heard what each character was sent to hear

# counters for the status line
var packets_in := 0
var late_inputs := 0
# measurements for tools/bench.sh (only kept while `measure` is on)
var measure := false
var tick_usec := PackedInt32Array()     # how long each tick took
var tick_players := PackedByteArray()   # and how many players were connected on it
var hello_usec := PackedInt32Array()    # how long the server took over each player's coming aboard
var part_usec := {}                     # the parts of a tick: name -> microseconds over the whole run
var part_ticks := 0                    # ticks those were counted over (with somebody connected)
var lap_at := -1


func start(p_port: int, map_name: String, bots: int) -> String:
	## Opens the port and starts ticking. Returns "" or what went wrong.
	var problem := map.load_from(map_name)
	for other_map in Net.OTHER_MAPS:
		if problem == "" and map.add_other(other_map) < 0:
			problem = "Не найдена карта «%s»." % other_map
	if problem != "":
		return problem
	_host = ENetConnection.new()
	var err := _host.create_host_bound("*", p_port, max_players + 16, 2)
	if err != OK:
		_host = null
		return "Не удалось открыть порт %d. Возможно, он занят другим сервером." % p_port
	port = p_port
	chat.setup(self)
	crew.setup(self)
	movement.setup(self)
	inventory.setup(self)
	looting.setup(self)
	combat.setup(self)
	repairs.setup(self)
	systems.setup(self)
	navigation.setup(self)
	supplies.setup(self)
	workshop.setup(self)
	admin.setup(self)
	holomap.setup(self)
	enemy_crew.setup(self)
	drone.setup(self)
	doors.setup(map.doors.size())
	doors.partner = map.door_partner
	for d in range(map.other_first_door, map.doors.size()):
		doors.dead[d] = 1
	door_hold.resize(map.doors.size())
	door_hold.fill(0)
	door_sent = doors.ready.duplicate()
	flags_sent = doors.locked.duplicate()
	forced_until.resize(map.doors.size())
	forced_until.fill(0)
	floor_things.clear()
	air.setup(map)
	replication.setup(self)
	# the crew's ship
	ship = Ship.new()
	ship.map = map
	ship.name = map.map_name
	for item in Items.kept_in_locker():
		ship.store[item] = Items.stock(item)
	ship.store_air = Net.STORE_AIR_FULL
	ship.credits = Net.START_CREDITS
	ship.hull = Net.HULL_MAX
	_next_ship_id = Net.CREW_SHIP + 1
	_ships_told = PackedByteArray()
	# the campaign
	reserve = Net.START_RESERVE
	over = Net.OVER_NONE
	won = false
	voyage_ticks = 0
	jumps = 0
	farthest = 0
	dead_names.clear()
	saved_crew.clear()
	space_seed = rng.randi()
	been = {Sectors.key(Vector2i.ZERO): true}
	sectors.build(space_seed, Vector2i.ZERO, been)
	ship.sector = sectors.here
	ship.pos = sectors.entry[ship.sector]
	ship.dest = ship.pos
	ship.in_reach = sectors.within_reach(ship.sector, ship.pos)
	derelict.setup(self)
	gunnery.setup(self)
	shipyard.setup(self)
	pirates.setup(self)
	director.setup(self)
	stations.setup(self)
	flagship.setup(self)
	rng.randomize()
	tick = 0
	_acc = 0.0
	running = true
	for i in bots:
		crew.add_bot()
	log_line.emit("Сервер запущен: порт %d, карта «%s», ботов %d." % [port, map.map_name, bots])
	return ""


func stop() -> void:
	if not running:
		return
	save_campaign()
	running = false
	# Tell everyone the server is closing, and stay just long enough for the
	# goodbyes to go out; otherwise the players would sit in a frozen game until
	# their connection times out.
	var leaving: Array = slot_of.keys() + pending.keys()
	for peer: ENetPacketPeer in leaving:
		peer.peer_disconnect()
	var deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
		_host.service(0)
		var waiting := false
		for peer: ENetPacketPeer in leaving:
			if peer.get_state() != ENetPacketPeer.STATE_DISCONNECTED:
				waiting = true
		if not waiting:
			break
		OS.delay_msec(5)
	_host.destroy()
	_host = null
	slot_of.clear()
	pending.clear()
	players.clear()
	free_slots.clear()
	corpses.clear()
	log_line.emit("Сервер остановлен.")


func bench_report() -> Dictionary:
	## What tools/bench.sh reads: every tick's length and how many were aboard then.
	return {"tick_usec": Array(tick_usec), "tick_players": Array(tick_players), "hello_usec": Array(hello_usec),
		"cpus": OS.get_processor_count(), "cpu": OS.get_processor_name(), "parts": part_usec, "part_ticks": part_ticks}


func _lap(part: String) -> void:
	## (measure only) Adds the time since the last lap to that part of the tick.
	if lap_at >= 0:
		var now := Time.get_ticks_usec()
		part_usec[part] = int(part_usec.get(part, 0)) + now - lap_at
		lap_at = now


func player_count() -> int:
	var n := 0
	for p: Player in players:
		if p != null and p.peer != null:
			n += 1
	return n


func _process(delta: float) -> void:
	if not running:
		return
	_poll()
	_acc += delta
	if _acc > 0.5:
		_acc = 0.5                  # after a long stall, do not replay more than half a second
	var ticked := false
	while _acc >= Net.TICK_SEC:
		_acc -= Net.TICK_SEC
		var t0 := Time.get_ticks_usec()
		_tick()
		if measure:
			tick_usec.append(Time.get_ticks_usec() - t0)
			tick_players.append(mini(player_count(), 255))
		ticked = true
	if ticked:
		_host.flush()


# ---------------------------------------------------------------- network

func _poll() -> void:
	var ev: Array = _host.service(0)
	while int(ev[0]) > 0:
		var peer: ENetPacketPeer = ev[1]
		match int(ev[0]):
			ENetConnection.EVENT_CONNECT:
				pending[peer] = Time.get_ticks_msec()
				peer.set_timeout(32, 4000, 12000)
			ENetConnection.EVENT_DISCONNECT:
				crew.drop(peer)
			ENetConnection.EVENT_RECEIVE:
				packets_in += 1
				_on_packet(peer, peer.get_packet())
		ev = _host.service(0)
	if not pending.is_empty():
		var now := Time.get_ticks_msec()
		for peer: ENetPacketPeer in pending.keys():
			if now - int(pending[peer]) > HELLO_TIMEOUT_MS:
				pending.erase(peer)
				peer.peer_disconnect()


func _on_packet(peer: ENetPacketPeer, pkt: PackedByteArray) -> void:
	if pkt.is_empty():
		return
	var kind := pkt[0]
	if not slot_of.has(peer):
		if kind == Net.C_HELLO and pending.has(peer):
			var t0 := Time.get_ticks_usec()
			crew.hello(peer, pkt)
			if measure:
				hello_usec.append(Time.get_ticks_usec() - t0)
		return
	var p: Player = players[slot_of[peer]]
	if kind == Net.C_INPUT:
		if pkt.size() < 8:
			return
		var dir := pkt[7]
		if dir > 4 and (dir <= Mover.TURN or dir > Mover.TURN + 4):
			return                  # a direction, or a turn (Mover.TURN + a direction)
		# A client sends every input change several times, so that one lost
		# packet does not hold it up. Keep one copy of each, in order.
		var seq := pkt.decode_u16(1)
		var ahead := (seq - p.last_seq) & 0xFFFF
		if ahead == 0 or ahead >= 0x8000:
			return                  # already applied, or older than what was applied
		var at := p.inputs.size()
		for i in p.inputs.size():
			var d := (int(p.inputs[i][2]) - seq) & 0xFFFF
			if d == 0:
				return              # this copy is already waiting
			if d < 0x8000:
				at = i              # the queued one is newer: this one goes before it
				break
		if p.inputs.size() >= MAX_INPUT_QUEUE:
			return
		var apply := pkt.decode_u32(3)
		if apply > tick + MAX_INPUT_LEAD:
			apply = tick + MAX_INPUT_LEAD
		if apply <= tick:
			late_inputs += 1        # arrived after the tick it was meant for; applied on the next one
		p.inputs.insert(at, [apply, dir, seq])
	elif kind == Net.C_CHAT:
		if pkt.size() < 3:
			return
		var n := pkt.decode_u16(1)
		if n > 0 and pkt.size() >= 3 + n:
			chat.talk(p, pkt.slice(3, 3 + n).get_string_from_utf8())
	elif kind == Net.C_SHUTDOWN:
		if shutdown_token != "" and pkt.slice(1).get_string_from_utf8() == shutdown_token:
			shutdown_requested.emit()
	elif kind == Net.C_USE:
		var held := pkt.size() > 1 and pkt[1] != 0
		if held and not p.using:
			# a press may take a ladder: on the tick the client pressed it, which is
			# usually a little ahead of us
			var at := pkt.decode_u32(2) if pkt.size() >= 6 else tick
			p.climb_tick = clampi(at, tick, tick + MAX_INPUT_LEAD)
			if p.climb_tick == tick:
				p.climb_tick = -1
				repairs.press(p)
		p.using = held
	elif kind == Net.C_SUIT:
		if pkt.size() > 1:
			inventory.set_supply(p, pkt[1] != 0)
	elif kind == Net.C_RESPAWN:
		if p.cond == Net.COND_DEAD and tick - p.died_tick >= Net.RESPAWN_TICKS:
			crew.respawn_from_reserve(p)
	elif kind == Net.C_JUMP:
		if pkt.size() > 1:
			navigation.jump_asked(p, pkt[1])
	elif kind == Net.C_HELM:
		if pkt.size() > 3:
			navigation.helm_asked(p, pkt[1] != 0, Vector2(pkt[2], pkt[3]))
	elif kind == Net.C_GUNS:
		if pkt.size() > 1:
			gunnery.fire(p, pkt[1])
	elif kind == Net.C_AIM:
		if pkt.size() > 1:
			gunnery.aim_asked(p, pkt[1])
	elif kind == Net.C_GUNSET:
		if pkt.size() > 3:
			gunnery.setup_asked(p, pkt[1], pkt[2], pkt[3])
	elif kind == Net.C_HOLO:
		if pkt.size() > 1:
			holomap.asked(p, pkt[1] != 0)
	elif kind == Net.C_DRONE:
		if pkt.size() > 2:
			drone.asked(p, pkt[1], pkt[2])
	elif kind == Net.C_ORDER:
		if pkt.size() > 3:
			stations.order_asked(p, pkt.decode_u16(1), pkt[3])
	elif kind == Net.C_POSITION:
		if pkt.size() > 1:
			stations.position_asked(p, pkt[1])
	elif kind == Net.C_WEAR:
		if pkt.size() > 1 and pkt[1] < Net.WORN:
			inventory.take_off(p, pkt[1])
	elif kind == Net.C_DOCK:
		if pkt.size() > 1 and systems.at_console(p, map.helm):
			var why := derelict.dock(pkt[1] != 0)
			if why != "":
				chat.say(why)
			elif derelict.here:
				chat.say("%s: %s." % [p.name, ("стыковка: " + derelict.ship.name.to_lower()) if derelict.docked else "расстыковка"])
	elif kind == Net.C_BENCH:
		if pkt.size() > 2:
			workshop.asked(p, pkt[1], pkt[2])
	elif kind == Net.C_STORE:
		if pkt.size() > 2:
			supplies.store_asked(p, pkt[1], pkt[2])
	elif kind == Net.C_HAND:
		if pkt.size() > 1 and pkt[1] < Net.SLOTS:
			p.hand = pkt[1]
	elif kind == Net.C_DROP:
		inventory.put_down(p)
	elif kind == Net.C_ACT:
		inventory.act(p)
	elif kind == Net.C_FIRE:
		if pkt.size() >= 9:
			combat.use_at(p, pkt.decode_u32(1), Vector2(pkt.decode_s16(5), pkt.decode_s16(7)) / 16.0)
	elif kind == Net.C_SEARCH or kind == Net.C_DRAG:
		if pkt.size() >= 7:
			looting.hands_asked(p, Looting.HAND_SEARCH if kind == Net.C_SEARCH else Looting.HAND_DRAG, pkt.decode_u16(1), pkt.decode_u32(3))
	elif kind == Net.C_LOOT:
		if pkt.size() > 2:
			looting.loot_asked(p, pkt[1] != 0, pkt[2])
	elif kind == Net.C_ADMIN:
		admin.asked(p, pkt)


func _reject(peer: ENetPacketPeer, reason: int) -> void:
	peer.send(0, PackedByteArray([Net.S_REJECT, reason]), ENetPacketPeer.FLAG_RELIABLE)
	peer.peer_disconnect_later()
	pending.erase(peer)


# --------------------------------------------------------------- campaign

func resume_campaign(path: String = Campaign.PATH) -> String:
	## Goes on with the saved campaign (right after start, before anybody joins).
	## Returns "" or what went wrong; with nothing saved a new campaign simply starts.
	var data := Campaign.read(path)
	if data.is_empty():
		return ""
	var problem := Campaign.restore(self, data)
	if problem == "":
		systems.power_changed()
		log_line.emit("Кампания продолжена: секторов пройдено %d, в резерве %d." % [been.size(), reserve])
	return problem


func save_campaign() -> bool:
	if save_path == "" or over != Net.OVER_NONE:
		return false
	if not Campaign.write(self, save_path):
		log_line.emit("Не удалось сохранить кампанию в %s." % save_path)
		return false
	return true


# ------------------------------------------------------------------ ships

func new_ship_id() -> int:
	## A network id for a ship that has just come (never one used before in this game).
	_next_ship_id += 1
	return _next_ship_id - 1


func ships_packet() -> PackedByteArray:
	## Net.S_SHIPS: every ship in the world now.
	var all: Array = [ship]
	if derelict.ship != null:
		all.append(derelict.ship)
	var out := PackedByteArray([Net.S_SHIPS, all.size()])
	for s: Ship in all:
		out.append_array(s.entry())
	return out


func _tell_ships() -> void:
	## Tells everyone the list of ships when a ship came, went, docked or moved.
	var now := ships_packet()
	if now != _ships_told:
		_ships_told = now
		to_all(now)


func to_all(msg: PackedByteArray) -> void:
	for q: Player in players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func powered() -> bool:
	## Does the crew's ship have power (see Ship.powered)?
	return ship.powered(tick)


func engine_down() -> bool:
	return ship.engine_down()


func put_on_floor(cell: int, item: int) -> bool:
	## Lays a thing on the floor of that cell, on top of what lies there. False if the cell is full.
	var things: PackedByteArray = floor_things.get(cell, PackedByteArray())
	if things.is_empty():
		things.resize(Net.FLOOR_STACK)
	var at := things.find(Net.ITEM_NONE)
	if at < 0:
		return false
	things[at] = item
	floor_things[cell] = things
	replication.floor_record(cell)
	return true


func chunk_of(x: int, y: int) -> int:
	return replication.chunk_of(x, y)


# ------------------------------------------------------------- simulation

func _tick() -> void:
	tick += 1
	lap_at = -1
	if measure and not slot_of.is_empty():
		lap_at = Time.get_ticks_usec()
		part_ticks += 1
	for p: Player in players:
		if p == null or p.corpse:
			continue
		movement.move(p)
		crew.update_vitals(p)
		looting.update(p)
		repairs.update(p)
		workshop.update(p)
		crew.tell_me(p)
	_lap("players")
	systems.power_changed()
	supplies.tell_store()
	if over == Net.OVER_NONE:
		voyage_ticks += 1
		if tick % Net.TICK_HZ == 0:
			crew.check_crew()
		if tick % Campaign.AUTOSAVE_TICKS == 0:
			save_campaign()
	crew.tell_campaign()
	systems.update_doors()
	navigation.update_jump()
	navigation.update()
	derelict.update()
	flagship.tick()
	stations.tick()
	gunnery.tick()
	enemy_crew.tick()
	drone.tick()
	holomap.tick()
	director.tick()
	_lap("ship")
	if tick % Net.AIR_EVERY == 0:
		systems.feed_air()
		systems.run_pumps()
		air.step(doors, tick)
		systems.update_shutters()
	if tick % Net.AIR_SEND_EVERY == 0:
		replication.collect_air()
	if tick % Net.TICK_HZ == 0:
		for cell: int in air.holes.keys():
			chat.sound(Net.SOUND_HISS, cell % map.width, cell / map.width)
	_lap("air")
	crew.tell_looks()
	_tell_ships()
	replication.send()
	_lap("send")
