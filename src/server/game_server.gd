extends Node
## The authoritative game server. It owns the world: clients only send what
## keys they hold, the server decides where everyone is and tells each client
## what changed near it. Runs in one thread, 20 steps ("ticks") per second.
##
## The same node is used for a dedicated server (no window) and for hosting
## from inside the game; a hosting player connects to it like anyone else.

signal log_line(text: String)
signal shutdown_requested            # the hosting player's game asked this server to stop

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Player := preload("res://src/server/player.gd")
const Air := preload("res://src/server/air.gd")
const Vitals := preload("res://src/server/vitals.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Director := preload("res://src/server/director.gd")
const Items := preload("res://src/shared/items.gd")

const HELLO_TIMEOUT_MS := 5000      # a connection must introduce itself within this time
const HEARTBEAT_TICKS := 10         # a client hears from the server at least this often
const SELF_REFRESH_TICKS := 20      # own state is re-confirmed at least this often
const CHECK_TICKS := 40             # how often a client gets a checksum of what it should know
const MAX_INPUT_QUEUE := 32
const MAX_INPUT_LEAD := 40          # inputs stamped further ahead than this are pulled back
const CHAT_BURST := 5               # messages allowed per CHAT_WINDOW_MS
const CHAT_WINDOW_MS := 5000
const BOT_RESPAWN_TICKS := 300      # a dead bot is replaced after 15 s
const MAX_CORPSES := 30             # the oldest body is cleared away when there are more
const HAND_SEARCH := 1              # what a press of "search" or "drag" asks for (Player.want_kind)
const HAND_DRAG := 2
const HAND_WAIT_TICKS := 10         # a drag asked for in mid-step waits this long for the step to end

var port := Net.DEFAULT_PORT
var max_players := 32
var map := ShipMap.new()
var running := false
var tick := 0
var shutdown_token := ""            # only a client that knows this text may stop the server ("" = nobody)

var _host: ENetConnection = null
var _acc := 0.0
var _pending := {}                  # peer -> msec when it connected (waiting for C_HELLO)
var _slot_of := {}                  # peer -> slot
var players: Array = []             # slot -> Player, or null when the slot is free
var _free: Array[int] = []
var _corpses: Array[int] = []       # slots of the bodies left behind, oldest first
var _rng := RandomNumberGenerator.new()

var _cw := 1                        # chunks across
var _ch := 1                        # chunk rows of one deck
var _deck_rows := 1                 # chunk rows from one deck to the next
var _change: Array = []             # per chunk: entity records changed this tick
var _full: Array = []               # per chunk: every entity in it (built on demand)
var _sums := PackedInt64Array()
var _full_tick := -1
var _window := 0                    # goes up every time the lists of changes are sent and emptied

# the ship itself: doors, hull, air
var doors := Doors.new()
var air := Air.new()
var _door_hold := PackedInt32Array()   # per door: it will not close before this tick
var _door_sent := PackedInt32Array()   # per door: the state clients were last told
var _flags_sent := PackedByteArray()   # per door: its troubles as clients were last told (see Doors.flags)
var _forced_until := PackedInt32Array()  # per door: its shutter was forced up and stays up until this tick
var _doors_in: Array = []              # per chunk: the doors in it
var _door_change: Array = []           # per chunk: door records changed this tick
var _hull_change: Array = []           # per chunk: hull records changed this tick
var _air_change: Array = []            # per chunk: (cell, air) pairs changed since the last air send
var _floor_change: Array = []         # per chunk: floor records changed this tick
var floor_things := {}                # things lying on the floor: cell -> PackedByteArray of Net.FLOOR_STACK
                                      # (bottom first, ITEM_NONE where there is nothing)
var _air_sent := PackedByteArray()     # per cell: the air level clients were last told
var _ship_sums := PackedInt64Array()   # per chunk: checksum of doors, hull and air as clients know them
var _ship_sums_tick := -1

# where the ship is
var sectors := Sectors.new()
var sector := 0                        # the sector the ship is in: its number in the window `sectors` holds
var space_seed := 0                    # what this game's space is made from
var been := {}                         # the sectors the ship has visited: Sectors.key -> true
var jump_to := Net.NO_SECTOR           # the sector it is jumping to, if any
var jump_tick := 0                     # the tick the jump lands on
var drive_ready := 0                   # the tick from which the drive can be used again
var ship_pos := Vector2.ZERO           # where the ship is inside its sector (see Sectors.SPAN)
var ship_dest := Vector2.ZERO          # where it is heading
var ship_moving := false
var in_reach := false                  # inside the sector's meteor stream, or docked at its station or trader
var broken := {}                       # things out of order (bridge consoles, the engine, the air plant): wall cell -> true
# the ship's supplies, kept in the supply locker
var store := {}                         # the supply locker: thing (Net.ITEM_*) -> how many
var store_air := 0.0                   # air the air plant still has to give, in cells' worth
var credits := 0
var _store_told := PackedByteArray()   # the supplies as clients were last told
var _power_out_until := 0              # a passing power failure lasts until this tick
var _power_told := true                # the state of the power as clients were last told
var director := Director.new()

# counters for the status line
var packets_in := 0
var late_inputs := 0


func start(p_port: int, map_name: String, bots: int) -> String:
	## Opens the port and starts ticking. Returns "" or what went wrong.
	var problem := map.load_from(map_name)
	if problem != "":
		return problem
	_host = ENetConnection.new()
	var err := _host.create_host_bound("*", p_port, max_players + 16, 2)
	if err != OK:
		_host = null
		return "Не удалось открыть порт %d. Возможно, он занят другим сервером." % p_port
	port = p_port
	_cw = map.chunks_wide()
	_ch = map.chunks_high()
	_deck_rows = map.deck_stride >> Net.CHUNK_SHIFT
	var chunks := _cw * map.chunk_rows()
	_change.clear()
	_full.clear()
	_door_change.clear()
	_hull_change.clear()
	_air_change.clear()
	_floor_change.clear()
	_doors_in.clear()
	for c in chunks:
		_change.append(PackedByteArray())
		_full.append(PackedByteArray())
		_door_change.append(PackedByteArray())
		_hull_change.append(PackedByteArray())
		_air_change.append(PackedByteArray())
		_floor_change.append(PackedByteArray())
		_doors_in.append(PackedInt32Array())
	_sums.resize(chunks)
	_ship_sums.resize(chunks)
	doors.setup(map.doors.size())
	_door_hold.resize(map.doors.size())
	_door_hold.fill(0)
	_door_sent = doors.ready.duplicate()
	_flags_sent = doors.locked.duplicate()
	_power_out_until = 0
	_power_told = true
	store.clear()
	for item in Items.kept_in_locker():
		store[item] = Items.stock(item)
	store_air = Net.STORE_AIR_FULL
	credits = Net.START_CREDITS
	_store_told = PackedByteArray()
	floor_things.clear()
	_forced_until.resize(map.doors.size())
	_forced_until.fill(0)
	for d in map.doors.size():
		var in_chunk: PackedInt32Array = _doors_in[_chunk_of(map.doors[d].x, map.doors[d].y)]
		in_chunk.append(d)
	air.setup(map)
	_air_sent = air.level.duplicate()
	space_seed = _rng.randi()
	been = {Sectors.key(Vector2i.ZERO): true}
	sectors.build(space_seed, Vector2i.ZERO, been)
	sector = sectors.here
	jump_to = Net.NO_SECTOR
	jump_tick = 0
	drive_ready = 0
	ship_pos = sectors.entry[sector]
	ship_dest = ship_pos
	ship_moving = false
	in_reach = sectors.within_reach(sector, ship_pos)
	broken.clear()
	director.setup(self)
	_rng.randomize()
	tick = 0
	_acc = 0.0
	running = true
	for i in bots:
		_add_bot()
	log_line.emit("Сервер запущен: порт %d, карта «%s», ботов %d." % [port, map.map_name, bots])
	return ""


func stop() -> void:
	if not running:
		return
	running = false
	# Tell everyone the server is closing, and stay just long enough for the
	# goodbyes to go out; otherwise the players would sit in a frozen game until
	# their connection times out.
	var leaving: Array = _slot_of.keys() + _pending.keys()
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
	_slot_of.clear()
	_pending.clear()
	players.clear()
	_free.clear()
	_corpses.clear()
	log_line.emit("Сервер остановлен.")


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
		_tick()
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
				_pending[peer] = Time.get_ticks_msec()
				peer.set_timeout(32, 4000, 12000)
			ENetConnection.EVENT_DISCONNECT:
				_drop(peer)
			ENetConnection.EVENT_RECEIVE:
				packets_in += 1
				_on_packet(peer, peer.get_packet())
		ev = _host.service(0)
	if not _pending.is_empty():
		var now := Time.get_ticks_msec()
		for peer: ENetPacketPeer in _pending.keys():
			if now - int(_pending[peer]) > HELLO_TIMEOUT_MS:
				_pending.erase(peer)
				peer.peer_disconnect()


func _on_packet(peer: ENetPacketPeer, pkt: PackedByteArray) -> void:
	if pkt.is_empty():
		return
	var kind := pkt[0]
	if not _slot_of.has(peer):
		if kind == Net.C_HELLO and _pending.has(peer):
			_hello(peer, pkt)
		return
	var p: Player = players[_slot_of[peer]]
	if kind == Net.C_INPUT:
		if pkt.size() < 8:
			return
		var dir := pkt[7]
		if dir > 4:
			return
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
			_chat(p, pkt.slice(3, 3 + n).get_string_from_utf8())
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
				_press(p)
		p.using = held
	elif kind == Net.C_SUIT:
		if p.cond == Net.COND_OK and pkt.size() > 1:
			p.supply = pkt[1] != 0 and p.tank > 0.0
	elif kind == Net.C_RESPAWN:
		if p.cond == Net.COND_DEAD and tick - p.died_tick >= Net.RESPAWN_TICKS:
			_respawn(p)
	elif kind == Net.C_JUMP:
		if pkt.size() > 1:
			_jump_asked(p, pkt[1])
	elif kind == Net.C_HELM:
		if pkt.size() > 3:
			_helm_asked(p, pkt[1] != 0, Vector2(pkt[2], pkt[3]))
	elif kind == Net.C_STORE:
		if pkt.size() > 2:
			_store_asked(p, pkt[1], pkt[2])
	elif kind == Net.C_HAND:
		if pkt.size() > 1 and pkt[1] < Net.SLOTS:
			p.hand = pkt[1]
	elif kind == Net.C_DROP:
		_put_down(p)
	elif kind == Net.C_ACT:
		_act(p)
	elif kind == Net.C_SEARCH or kind == Net.C_DRAG:
		if pkt.size() >= 7:
			_hands_asked(p, HAND_SEARCH if kind == Net.C_SEARCH else HAND_DRAG, pkt.decode_u16(1), pkt.decode_u32(3))
	elif kind == Net.C_LOOT:
		if pkt.size() > 2:
			_loot_asked(p, pkt[1] != 0, pkt[2])
	elif kind == Net.C_ADMIN:
		if pkt.size() > 3 and shutdown_token != "" and pkt.slice(3).get_string_from_utf8() == shutdown_token:
			if pkt[1] == Net.ADMIN_BREACH:
				# the wall the player faces, if it can be breached; otherwise the nearest that can
				var ahead := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
				if not (ahead >= 0 and map.hull.has(ahead) and breach(ahead)):
					breach_near(p.st.x, p.st.y)
			elif pkt[1] == Net.ADMIN_SEAL:
				seal_all()
			elif pkt[1] == Net.ADMIN_EVENT:
				director.fire(pkt[2])
			elif pkt[1] == Net.ADMIN_AUTO:
				director.auto = pkt[2] != 0
				_ship_says("Ивентер: события идут сами." if director.auto else "Ивентер: события только вручную.")


func _reject(peer: ENetPacketPeer, reason: int) -> void:
	peer.send(0, PackedByteArray([Net.S_REJECT, reason]), ENetPacketPeer.FLAG_RELIABLE)
	peer.peer_disconnect_later()
	_pending.erase(peer)


func _hello(peer: ENetPacketPeer, pkt: PackedByteArray) -> void:
	if pkt.size() < 4:
		_reject(peer, Net.REJECT_BAD_HELLO)
		return
	if pkt.decode_u16(1) != Net.PROTOCOL:
		_reject(peer, Net.REJECT_VERSION)
		return
	if player_count() >= max_players:
		_reject(peer, Net.REJECT_FULL)
		return
	var n := pkt[3]
	if pkt.size() < 4 + n:
		_reject(peer, Net.REJECT_BAD_HELLO)
		return
	var p := _new_player(_unique_name(_clean(pkt.slice(4, 4 + n).get_string_from_utf8(), Net.MAX_NAME, "Игрок")))
	p.peer = peer
	p.add(Net.ITEM_PATCH)                # a newcomer has a little on them; the rest is in the locker
	p.add(Net.ITEM_PART)
	_pending.erase(peer)
	_slot_of[peer] = p.slot

	var map_name := map.map_name.to_utf8_buffer()
	var w := PackedByteArray()
	w.resize(12)
	w.encode_u8(0, Net.S_WELCOME)
	w.encode_u16(1, p.slot)
	w.encode_u32(3, tick)
	w.encode_u32(7, map.crc)
	w.encode_u8(11, map_name.size())
	w.append_array(map_name)
	peer.send(0, w, ENetPacketPeer.FLAG_RELIABLE)

	var roster := PackedByteArray()
	roster.resize(3)
	roster.encode_u8(0, Net.S_ROSTER)
	var count := 0
	for q: Player in players:
		if q != null:
			roster.append_array(_roster_entry(q))
			count += 1
	roster.encode_u16(1, count)
	peer.send(0, roster, ENetPacketPeer.FLAG_RELIABLE)

	peer.send(0, _sectors_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, _nav_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, _helm_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, _devices_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, PackedByteArray([Net.S_POWER, 1 if _power_told else 0]), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, _store_packet(), ENetPacketPeer.FLAG_RELIABLE)

	_announce_join(p, peer)
	log_line.emit("%s подключился (игроков: %d)." % [p.name, player_count()])


func _alloc(player_name: String) -> Player:
	## A new record in a free slot. The slot number is the character's id.
	var p := Player.new()
	if _free.is_empty():
		p.slot = players.size()
		players.append(p)
	else:
		p.slot = _free.pop_back()
		players[p.slot] = p
	p.name = player_name
	return p


func _new_player(player_name: String) -> Player:
	var p := _alloc(player_name)
	p.colour = p.slot % Net.SUIT_COLOURS
	var spot := _spawn_point()
	p.st.place(spot.x, spot.y)
	_record(p)
	return p


func _add_bot() -> void:
	var n := 1
	for q: Player in players:
		if q != null and q.bot:
			n += 1
	var p := _new_player(_unique_name("Бот %d" % n))
	p.bot = true
	p.add(Net.ITEM_FLASHLIGHT, true)
	_announce_join(p, null)


func _announce_join(p: Player, except: ENetPacketPeer) -> void:
	var msg := PackedByteArray([Net.S_JOIN])
	msg.append_array(_roster_entry(p))
	for q: Player in players:
		if q != null and q.peer != null and q.peer != except:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func _roster_entry(p: Player) -> PackedByteArray:
	var name_bytes := p.name.to_utf8_buffer()
	var e := PackedByteArray()
	e.resize(5)
	e.encode_u16(0, p.slot)
	e.encode_u8(2, p.colour)
	e.encode_u8(3, Net.KIND_CORPSE if p.corpse else (Net.KIND_BOT if p.bot else Net.KIND_PLAYER))
	e.encode_u8(4, name_bytes.size())
	e.append_array(name_bytes)
	return e


func _spawn_point() -> Vector2i:
	# prefer a spawn tile nobody is standing on
	var start := _rng.randi_range(0, map.spawns.size() - 1)
	for i in map.spawns.size():
		var s: Vector2i = map.spawns[(start + i) % map.spawns.size()]
		var taken := false
		for q: Player in players:
			if q != null and q.st.x == s.x and q.st.y == s.y:
				taken = true
				break
		if not taken:
			return s
	return map.spawns[start]


func _drop(peer: ENetPacketPeer) -> void:
	_pending.erase(peer)
	if not _slot_of.has(peer):
		return
	var p: Player = players[_slot_of[peer]]
	_slot_of.erase(peer)
	if p.cond == Net.COND_DEAD:
		# the dead stay where they fell, whether or not their player is still here
		p.peer = null
		_becomes_corpse(p)
	else:
		_remove(p)
	log_line.emit("%s вышел (игроков: %d)." % [p.name, player_count()])


func _remove(p: Player) -> void:
	## Takes a character out of the world altogether.
	if p.dragging >= 0:
		_let_go(p)
	if p.dragged_by >= 0 and players[p.dragged_by] != null:
		_let_go(players[p.dragged_by])
	_record(p, true)
	players[p.slot] = null
	_free.append(p.slot)
	_corpses.erase(p.slot)
	var msg := PackedByteArray()
	msg.resize(3)
	msg.encode_u8(0, Net.S_LEAVE)
	msg.encode_u16(1, p.slot)
	for q: Player in players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func _becomes_corpse(c: Player) -> void:
	## Marks a record as a body nobody controls and tells everyone what it is now.
	c.corpse = true
	c.bot = false
	c.using = false
	c.inputs.clear()
	_corpses.append(c.slot)
	_announce_join(c, null)
	if _corpses.size() > MAX_CORPSES:
		_remove(players[_corpses[0]])


func _leave_body(p: Player) -> void:
	## The character is about to be given a new body: its old one stays where it
	## lies, with everything it carried. Whoever was hauling or searching the
	## dead character goes on with the body.
	var c := _alloc(p.name)
	c.colour = p.colour
	c.st.copy_from(p.st)
	c.st.dir = Net.DIR_NONE
	c.st.down = true
	c.cond = Net.COND_DEAD
	c.health = Net.HEALTH_DEAD
	c.slots = p.slots.duplicate()
	c.hand = p.hand
	for q: Player in players:
		if q == null:
			continue
		if q.dragging == p.slot:
			q.dragging = c.slot
			c.dragged_by = q.slot
		if q.searching == p.slot:
			q.searching = c.slot
			q.search_sent = PackedByteArray()
	p.dragged_by = -1
	p.st.slow = false
	_becomes_corpse(c)
	_record(c)


func _clean(text: String, limit: int, fallback: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 32 and c != 127:
			out += text[i]
	out = out.strip_edges().left(limit)
	return fallback if out.is_empty() else out


func _unique_name(wanted: String) -> String:
	var candidate := wanted
	var n := 1
	while true:
		var clash := false
		for q: Player in players:
			if q != null and not q.corpse and q.name == candidate:
				clash = true
				break
		if not clash:
			return candidate
		n += 1
		candidate = "%s %d" % [wanted.left(Net.MAX_NAME - 3), n]
	return candidate


func _chat(p: Player, raw: String) -> void:
	var now := Time.get_ticks_msec()
	while not p.chat_times.is_empty() and now - p.chat_times[0] > CHAT_WINDOW_MS:
		p.chat_times.pop_front()
	if p.chat_times.size() >= CHAT_BURST:
		return
	var text := _clean(raw, Net.MAX_CHAT, "")
	if text.is_empty():
		return
	p.chat_times.append(now)
	var body := text.to_utf8_buffer()
	var msg := PackedByteArray()
	msg.resize(5)
	msg.encode_u8(0, Net.S_CHAT)
	msg.encode_u16(1, p.slot)
	msg.encode_u16(3, body.size())
	msg.append_array(body)
	for q: Player in players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	log_line.emit("[чат] %s: %s" % [p.name, text])


func _ship_says(text: String) -> void:
	## A line in everybody's chat from the ship itself.
	var body := text.to_utf8_buffer()
	var msg := PackedByteArray()
	msg.resize(5)
	msg.encode_u8(0, Net.S_CHAT)
	msg.encode_u16(1, Net.SYSTEM_ID)
	msg.encode_u16(3, body.size())
	msg.append_array(body)
	for q: Player in players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	log_line.emit("[корабль] %s" % text)


# ---------------------------------------------------------------- sectors

func sector_kind() -> int:
	return sectors.kind[sector]


func danger_kind() -> int:
	## What the director should treat the ship's surroundings as: a meteor
	## stream is only dangerous while the ship is inside it.
	if sector_kind() == Sectors.METEORS and not in_reach:
		return Sectors.EMPTY
	return sector_kind()


func _to_all(msg: PackedByteArray) -> void:
	for q: Player in players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func _helm_packet() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u8(0, Net.S_HELM)
	out.encode_s16(1, roundi(ship_pos.x * 10.0))
	out.encode_s16(3, roundi(ship_pos.y * 10.0))
	out.encode_u8(5, 1 if ship_moving else 0)
	out.encode_u8(6, roundi(ship_dest.x))
	out.encode_u8(7, roundi(ship_dest.y))
	out.encode_u32(8, tick)
	return out


func _devices_packet() -> PackedByteArray:
	var out := PackedByteArray([Net.S_DEVICES, broken.size()])
	for cell: int in broken.keys():
		out.append(cell & 0xFF)
		out.append(cell >> 8)
	return out


func _at_console(p: Player, cells: Dictionary) -> bool:
	## Does this player stand facing a working console of that kind?
	if p.cond != Net.COND_OK or not powered():
		return false
	var ahead := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	return ahead >= 0 and cells.has(ahead) and not broken.has(ahead)


func engine_down() -> bool:
	## The ship has an engine and it is out of order: no way under its own power, no jump.
	if map.engine.is_empty():
		return false
	for cell: int in map.engine.keys():
		if not broken.has(cell):
			return false
	return true


func powered() -> bool:
	## The engine is what powers the ship. Without it every system stands still
	## (none of them breaks): the bridge consoles, the air plant, the oxygen
	## stations, the emergency shutters; doors have to be pushed open by hand.
	## The power can also fail for a few seconds by itself and come back.
	return not engine_down() and tick >= _power_out_until


func _power_changed() -> void:
	## Looks whether the power has gone or come back since clients were last told,
	## and does what goes with it. Called every tick and after anything that changes it.
	var on := powered()
	if on == _power_told:
		return
	_power_told = on
	doors.manual = not on
	_to_all(PackedByteArray([Net.S_POWER, 1 if on else 0]))
	if on:
		_ship_says("Питание восстановлено: системы корабля снова работают.")
		return
	# without power the ship stops where it is and a jump being charged is lost
	if ship_moving:
		ship_moving = false
		ship_dest = ship_pos
		_to_all(_helm_packet())
	if jump_to != Net.NO_SECTOR:
		jump_to = Net.NO_SECTOR
		_tell_nav()
		_ship_says("Прыжок сорван.")


func power_glitch() -> bool:
	## The power fails for a few seconds and comes back by itself.
	if not powered():
		return false
	_power_out_until = tick + _rng.randi_range(8, 15) * Net.TICK_HZ
	_ship_says("Сбой питания: все системы стоят.")
	_power_changed()
	return true


func _door_free(d: int) -> bool:
	## Nobody stands in this doorway.
	for p: Player in players:
		if p != null and map.door_at(p.st.x, p.st.y) == d:
			return false
	return true


func _count(flags: PackedByteArray) -> int:
	var n := 0
	for v in flags:
		n += v
	return n


func jam_door() -> bool:
	## A door slides open and sticks there: air passes freely until somebody mends it.
	if not can_break("door"):
		return false
	var choice := PackedInt32Array()
	for d in doors.ready.size():
		if doors.jammed[d] == 0 and doors.faulty[d] == 0:
			choice.append(d)
	var d := choice[_rng.randi_range(0, choice.size() - 1)]
	doors.jammed[d] = 1
	doors.locked[d] = 0
	if doors.ready[d] == Doors.CLOSED:
		doors.ready[d] = tick
	air.wake()
	_ship_says("Одну из дверей заклинило в открытом положении.")
	return true


func fault_shutter() -> bool:
	## An emergency shutter stops working by itself. Half the time it also
	## drops for no reason; otherwise it will simply not be there when needed.
	if not can_break("shutter"):
		return false
	var choice := PackedInt32Array()
	for d in doors.ready.size():
		if doors.jammed[d] == 0 and doors.faulty[d] == 0:
			choice.append(d)
	var d := choice[_rng.randi_range(0, choice.size() - 1)]
	doors.faulty[d] = 1
	if _rng.randf() < 0.5 and _door_free(d):
		doors.locked[d] = 1
		_door_hold[d] = mini(_door_hold[d], tick)
	_ship_says("Неисправность аварийного шлюза на одной из дверей.")
	return true


func _any_broken(cells: Dictionary) -> bool:
	for cell: int in cells.keys():
		if broken.has(cell):
			return true
	return false


func can_break(what: String) -> bool:
	## Can this kind of trouble happen now? Things that stand between the crew
	## and an escape break one at a time: while a bridge console is out, the
	## engine holds, and the other way round. Doors go wrong two at a time at most.
	var way_out_hurt := _any_broken(map.chart) or _any_broken(map.helm) or _any_broken(map.engine)
	match what:
		"console":
			return not way_out_hurt and not (map.chart.is_empty() and map.helm.is_empty())
		"engine":
			return not way_out_hurt and not map.engine.is_empty()
		"air_plant":
			return not map.air_plant.is_empty() and not _any_broken(map.air_plant)
		"door":
			return _count(doors.jammed) < 2 and _count(doors.jammed) + _count(doors.faulty) < doors.ready.size()
		"shutter":
			return _count(doors.faulty) < 2 and _count(doors.jammed) + _count(doors.faulty) < doors.ready.size()
		"power":
			return powered()
	return false


func break_engine() -> bool:
	if not can_break("engine"):
		return false
	var cells: Array = map.engine.keys()
	var cell: int = cells[_rng.randi_range(0, cells.size() - 1)]
	broken[cell] = true
	_to_all(_devices_packet())
	_ship_says("Отказ двигателя: корабль обесточен, все системы стоят, двери открываются только вручную. Двигатель на нижней палубе.")
	_power_changed()
	return true


func break_air_plant() -> bool:
	if not can_break("air_plant"):
		return false
	var cells: Array = map.air_plant.keys()
	var cell: int = cells[_rng.randi_range(0, cells.size() - 1)]
	broken[cell] = true
	_to_all(_devices_packet())
	_ship_says("Воздушная установка остановилась. Она на нижней палубе.")
	return true





func _feed_air() -> void:
	## Every working air plant blows a little air into the room it faces, for as
	## long as the ship has air in store for it.
	if not powered():
		return
	for cell: int in map.air_plant.keys():
		if not broken.has(cell) and store_air > 0.0:
			store_air = maxf(store_air - air.feed(map.air_plant[cell], minf(Air.PLANT_PER_STEP, store_air)), 0.0)


# --------------------------------------------------------------- supplies

func _store_packet() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6)
	out.encode_u8(0, Net.S_STORE)
	out.encode_u16(1, roundi(store_air * 10.0))
	out.encode_u16(3, credits)
	out.encode_u8(5, store.size())
	for item: int in store.keys():
		var o := out.size()
		out.resize(o + 3)
		out.encode_u8(o, item)
		out.encode_u16(o + 1, store[item])
	return out


func _tell_store() -> void:
	## Tells everyone the ship's supplies, if they changed since the last time.
	var now := _store_packet()
	if now != _store_told:
		_store_told = now
		_to_all(now)


func can_trade() -> bool:
	## Docked with a trader, with power for the link.
	return powered() and sector_kind() == Sectors.TRADER and in_reach


func patches_aboard() -> int:
	## Every patch the crew could still use: in the locker, in pockets, on bodies and on the floor.
	var n: int = store.get(Net.ITEM_PATCH, 0)
	for p: Player in players:
		if p != null:
			n += p.count(Net.ITEM_PATCH)
	for things: PackedByteArray in floor_things.values():
		n += things.count(Net.ITEM_PATCH)
	return n


func _store_asked(p: Player, action: int, item: int) -> void:
	## A player at the supply locker takes something, puts it back, or buys from a trader.
	if p.cond != Net.COND_OK:
		return
	var ahead := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	if ahead < 0 or not map.locker.has(ahead):
		return
	match action:
		Net.STORE_TAKE:
			if int(store.get(item, 0)) > 0 and p.add(item, true):
				store[item] -= 1
		Net.STORE_PUT_BACK:
			for at in Net.SLOTS:
				var kind := Items.kind_of(p.slots[at])
				if p.slots[at] != Net.ITEM_NONE and store.has(kind):
					store[kind] += 1
					p.slots[at] = Net.ITEM_NONE
		Net.STORE_BUY:
			var price := Items.price(item)
			if can_trade() and store.has(item) and price > 0 and credits >= price:
				credits -= price
				store[item] += 1
		Net.STORE_BUY_AIR:
			if can_trade() and credits >= Net.PRICE_AIR and store_air < Net.STORE_AIR_FULL:
				credits -= Net.PRICE_AIR
				store_air = minf(store_air + Net.AIR_LOT, Net.STORE_AIR_FULL)
	_tell_store()


func _helm_asked(p: Player, go: bool, to: Vector2) -> void:
	## A player at the ship's controls sets a course inside the sector, or stops the ship.
	if not _at_console(p, map.helm) or jump_to != Net.NO_SECTOR or engine_down():
		return
	ship_moving = go
	ship_dest = to.clamp(Vector2.ZERO, Vector2(Sectors.SPAN, Sectors.SPAN)) if go else ship_pos
	_to_all(_helm_packet())


func _update_ship() -> void:
	if ship_moving:
		ship_pos = ship_pos.move_toward(ship_dest, Sectors.SHIP_SPEED * Net.TICK_SEC)
		if ship_pos.is_equal_approx(ship_dest):
			ship_moving = false
			_to_all(_helm_packet())
	var now_in := sectors.within_reach(sector, ship_pos)
	if now_in == in_reach:
		return
	in_reach = now_in
	match sector_kind():
		Sectors.METEORS:
			_ship_says("Корабль вошёл в метеорный поток." if now_in else "Корабль вышел из метеорного потока.")
			director.surroundings_changed()
		Sectors.STATION:
			if now_in:
				air.refill()
				store_air = Net.STORE_AIR_FULL
				_ship_says("Стыковка со станцией снабжения. Воздух в отсеках и запас воздушной установки восполнены.")
		Sectors.TRADER:
			if now_in:
				_ship_says("Торговец на связи. Покупки делаются у шкафа снабжения на нижней палубе.")


func break_console() -> bool:
	## A bridge console goes out of order. One at a time: while one is broken,
	## the other stays whole, so the crew always has one way out left.
	if not can_break("console"):
		return false
	var all: Array = map.chart.keys() + map.helm.keys()
	if all.is_empty():
		return false
	var cell: int = all[_rng.randi_range(0, all.size() - 1)]
	broken[cell] = true
	_to_all(_devices_packet())
	_ship_says("Замыкание на мостике: %s не работает." % map.device_name(cell))
	return true


func _sectors_packet() -> PackedByteArray:
	var out := PackedByteArray([Net.S_SECTORS])
	out.append_array(sectors.pack())
	return out


func _nav_packet() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(11)
	out.encode_u8(0, Net.S_NAV)
	out.encode_u8(1, sector)
	out.encode_u8(2, jump_to)
	out.encode_u32(3, jump_tick)
	out.encode_u32(7, drive_ready)
	return out


func _tell_nav() -> void:
	var msg := _nav_packet()
	for q: Player in players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func _jump_asked(p: Player, target: int) -> void:
	## A player at the sector console asks for a jump.
	if not _at_console(p, map.chart) or jump_to != Net.NO_SECTOR or tick < drive_ready or engine_down():
		return
	if target >= sectors.count or not sectors.linked(sector, target):
		return
	start_jump(target, p.name)


func start_jump(target: int, by: String) -> void:
	jump_to = target
	jump_tick = tick + Net.JUMP_TICKS
	_tell_nav()
	_ship_says("%s задаёт курс: %s. Прыжок через %d секунд." % [by, sectors.describe(target), Net.JUMP_TICKS / Net.TICK_HZ])
	if ship_moving and not ship_pos.is_equal_approx(ship_dest):
		# The ship is leaving for the jump: the course it was on no longer counts.
		# It coasts straight on, on its inertia, until the jump takes it.
		var way := (ship_dest - ship_pos).normalized()
		var room := 1000.0                   # how far it can go that way before the edge of the sector
		if way.x > 0.0:
			room = minf(room, (Sectors.SPAN - ship_pos.x) / way.x)
		elif way.x < 0.0:
			room = minf(room, -ship_pos.x / way.x)
		if way.y > 0.0:
			room = minf(room, (Sectors.SPAN - ship_pos.y) / way.y)
		elif way.y < 0.0:
			room = minf(room, -ship_pos.y / way.y)
		ship_dest = (ship_pos + way * room).clamp(Vector2.ZERO, Vector2(Sectors.SPAN, Sectors.SPAN)).round()
		_to_all(_helm_packet())


func _update_jump() -> void:
	if jump_to == Net.NO_SECTOR or tick < jump_tick:
		return
	# The ship is somewhere else now: the chart is drawn anew around the new
	# sector, which is how space goes on for ever without being kept anywhere.
	var arrived: Vector2i = sectors.cell[jump_to]
	jump_to = Net.NO_SECTOR
	drive_ready = tick + Net.DRIVE_REST_TICKS
	if not been.has(Sectors.key(arrived)):
		credits += Net.EXPLORE_REWARD
		_ship_says("За разведку нового сектора начислено %d кредитов." % Net.EXPLORE_REWARD)
	been[Sectors.key(arrived)] = true
	sectors.build(space_seed, arrived, been)
	sector = sectors.here
	_to_all(_sectors_packet())
	ship_pos = sectors.entry[sector]
	ship_dest = ship_pos
	ship_moving = false
	in_reach = sectors.within_reach(sector, ship_pos)
	_tell_nav()
	_to_all(_helm_packet())
	match sector_kind():
		Sectors.METEORS:
			_ship_says("Сектор %s. Корабль внутри потока: уйти можно своим ходом с пульта управления или прыжком." % sectors.describe(sector))
		Sectors.TRADER:
			_ship_says("Сектор %s. Торговец где-то рядом: подойдите к нему." % sectors.describe(sector))
		Sectors.STATION:
			_ship_says("Сектор %s. Подойдите к станции, чтобы восполнить воздух." % sectors.describe(sector))
		_:
			_ship_says("Сектор %s." % sectors.describe(sector))
	director.entered_sector()


# ------------------------------------------------------------------- hull

func breach(cell: int) -> bool:
	## Tears a hole in a hull cell. Returns false if there already is one.
	if not air.set_hole(cell, true):
		return false
	_hull_record(cell, 1)
	_ship_says("Разгерметизация! Пробоина в обшивке.")
	return true


func breach_near(x: int, y: int) -> bool:
	## A hole in the whole hull cell closest to the given place, on the same deck.
	var best := -1
	var best_d := 1 << 30
	for cell in map.hull:
		if air.holes.has(cell) or map.deck_of_cell(cell) != map.deck_of(y):
			continue
		var d := absi(cell % map.width - x) + absi(cell / map.width - y)
		if d < best_d or (d == best_d and _rng.randf() < 0.5):
			best_d = d
			best = cell
	return best >= 0 and breach(best)


func breach_random() -> bool:
	var whole := PackedInt32Array()
	for cell in map.hull:
		if not air.holes.has(cell):
			whole.append(cell)
	return not whole.is_empty() and breach(whole[_rng.randi_range(0, whole.size() - 1)])


func seal_all() -> void:
	if air.holes.is_empty():
		return
	for cell: int in air.holes.keys():
		air.set_hole(cell, false)
		_hull_record(cell, 0)
	_ship_says("Пробоины заделаны.")


func _hull_record(cell: int, state: int) -> void:
	var x := cell % map.width
	var y := cell / map.width
	var buf: PackedByteArray = _hull_change[_chunk_of(x, y)]
	var o := buf.size()
	buf.resize(o + Net.HULL_BYTES)
	buf.encode_s16(o, x)
	buf.encode_s16(o + 2, y)
	buf.encode_u8(o + 4, state)
	_ship_sums_tick = -1


# ------------------------------------------------------------- simulation

func _tick() -> void:
	tick += 1
	for p: Player in players:
		if p == null or p.corpse:
			continue
		while not p.inputs.is_empty() and int(p.inputs[0][0]) <= tick:
			var inp: Array = p.inputs.pop_front()
			p.st.dir = inp[1]
			p.last_seq = inp[2]
			p.self_dirty = true
		if p.bot:
			_bot_think(p)
		var was_x := p.st.x
		var was_y := p.st.y
		if Mover.step(p.st, map, doors, tick):
			p.self_dirty = true
			if p.dragging >= 0:
				_haul(p, was_x, was_y)
		if p.climb_tick >= 0 and tick >= p.climb_tick:
			p.climb_tick = -1
			_press(p)
		_update_vitals(p)
		_update_hands(p)
		_update_work(p)
		if p.st.x != p.rep_x or p.st.y != p.rep_y or _look(p) != p.rep_look:
			_record(p)
	_power_changed()
	_tell_store()
	_update_doors()
	_update_jump()
	_update_ship()
	director.tick()
	if tick % Net.AIR_EVERY == 0:
		_feed_air()
		air.step(doors, tick)
		_update_shutters()
	if tick % Net.AIR_SEND_EVERY == 0:
		_collect_air()
	_send_world()


func _update_vitals(p: Player) -> void:
	## What the air in its cell does to one character this tick.
	if p.cond == Net.COND_DEAD:
		if p.bot and tick - p.died_tick >= BOT_RESPAWN_TICKS:
			_respawn(p)
		return
	var breathes := air.air[p.st.y * map.width + p.st.x]
	if p.supply:
		# on the tank: the air around does not matter while there is oxygen left
		p.tank = maxf(p.tank - Net.TICK_SEC / Vitals.TANK_SECONDS, 0.0)
		if p.tank > 0.0:
			breathes = 1.0
		else:
			p.supply = false
	p.health = Vitals.advance(p.health, p.cond, breathes, Net.TICK_SEC)
	var cond := Vitals.condition(p.health, p.cond)
	if cond == p.cond:
		return
	if cond == Net.COND_CRIT:
		_ship_says("%s теряет сознание." % p.name)
	elif cond == Net.COND_DEAD:
		p.died_tick = tick
		_ship_says("%s погибает." % p.name)
	elif p.cond == Net.COND_CRIT:
		_ship_says("%s приходит в себя." % p.name)
	p.cond = cond
	p.st.down = cond != Net.COND_OK
	p.st.dir = Net.DIR_NONE
	p.inputs.clear()
	p.self_dirty = true


func _update_work(p: Player) -> void:
	## Holding "use" on what the character faces: a hole, a broken machine or a
	## door that has gone wrong is mended, an emergency shutter is forced up, an
	## oxygen station fills the tank.
	if not p.using or p.cond != Net.COND_OK or p.st.cd > 0 or p.st.dir != Net.DIR_NONE:
		p.work = 0
		return
	var cell := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	var door := map.door_of[cell] if cell >= 0 else -1
	# a spare part makes mending a machine or a door quick; without one it can still be done, slowly
	var mend_ticks := Net.REPAIR_TICKS if p.count(Net.ITEM_PART) > 0 else Net.REPAIR_TICKS * Net.NO_PART_SLOWER
	if cell >= 0 and air.holes.has(cell):
		if p.count(Net.ITEM_PATCH) == 0:
			p.work = 0                       # nothing to close it with
		elif _work_done(p, cell, Net.REPAIR_TICKS):
			p.remove(Net.ITEM_PATCH)
			air.set_hole(cell, false)
			_hull_record(cell, 0)
			_ship_says("%s заделывает пробоину. Воздух сам не вернётся: его дадут соседние отсеки." % p.name)
	elif cell >= 0 and broken.has(cell):
		if _work_done(p, cell, mend_ticks):
			p.remove(Net.ITEM_PART)
			broken.erase(cell)
			_to_all(_devices_packet())
			_ship_says("%s заканчивает ремонт: %s снова работает." % [p.name, map.device_name(cell)])
			_power_changed()
	elif door >= 0 and doors.jammed[door] == 1:
		if _work_done(p, cell, mend_ticks):
			p.remove(Net.ITEM_PART)
			doors.jammed[door] = 0
			_door_hold[door] = tick          # it may shut again as soon as the doorway is clear
			_ship_says("%s чинит заклинившую дверь." % p.name)
	elif door >= 0 and doors.faulty[door] == 1:
		if _work_done(p, cell, mend_ticks):
			p.remove(Net.ITEM_PART)
			doors.faulty[door] = 0           # from here on the pressure decides again
			_ship_says("%s чинит аварийный шлюз." % p.name)
	elif door >= 0 and doors.is_sealed(door):
		if _work_done(p, cell, Net.FORCE_TICKS):
			doors.locked[door] = 0
			_forced_until[door] = tick + Net.FORCED_OPEN_TICKS
			_ship_says("%s вручную поднимает аварийный шлюз." % p.name)
	elif cell >= 0 and map.oxygen.has(cell) and powered():
		p.work = 0
		p.tank = minf(p.tank + Net.TICK_SEC / Vitals.REFILL_SECONDS, 1.0)
	else:
		p.work = 0


func _work_done(p: Player, cell: int, ticks: int) -> bool:
	## One more tick of work on the thing in that cell. True when the job is finished.
	if p.work_cell != cell or p.work_total != ticks:
		p.work_cell = cell
		p.work_total = ticks
		p.work = 0
	p.work += 1
	if p.work < ticks:
		return false
	p.work = 0
	return true


func _usable_ahead(p: Player) -> bool:
	## Is there something in front of the character that the "use" key works on?
	var cell := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	if cell < 0:
		return false
	var door := map.door_of[cell]
	return air.holes.has(cell) or broken.has(cell) or map.oxygen.has(cell) \
		or map.chart.has(cell) or map.helm.has(cell) or map.locker.has(cell) \
		or (door >= 0 and (doors.is_sealed(door) or doors.jammed[door] == 1 or doors.faulty[door] == 1))


func _press(p: Player) -> void:
	## The "use" key went down (on the tick the client pressed it). Most of what
	## it does is holding it (see _update_work); a press itself picks up a thing
	## lying in front or underfoot, or else takes a ladder.
	if not _pick_up(p):
		_climb(p)


func _lying_in(cell: int) -> bool:
	for q: Player in players:
		if q != null and q.cond != Net.COND_OK and q.st.y * map.width + q.st.x == cell:
			return true
	return false


func _pick_up(p: Player) -> bool:
	## Picks up the top thing lying in the cell in front, or else in its own cell:
	## into the hand if the hand is free. Somebody lying there is searched instead
	## (the client asks for that), and a thing on the wall in front comes first.
	if p.cond != Net.COND_OK or p.corpse or _usable_ahead(p):
		return false
	var here := p.st.y * map.width + p.st.x
	var ahead := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	for cell: int in [ahead, here]:
		if cell < 0 or not floor_things.has(cell) or _lying_in(cell):
			continue
		var things: PackedByteArray = floor_things[cell]
		var top := Net.FLOOR_STACK - 1
		while top >= 0 and things[top] == Net.ITEM_NONE:
			top -= 1
		if top < 0 or not p.add(things[top], true):
			return false
		things[top] = Net.ITEM_NONE
		if things.count(Net.ITEM_NONE) == Net.FLOOR_STACK:
			floor_things.erase(cell)
		else:
			floor_things[cell] = things
		_floor_record(cell)
		return true
	return false


func _put_down(p: Player) -> bool:
	## Puts the thing in the hand down in its own cell, if there is room there.
	var item := p.in_hand()
	if p.cond != Net.COND_OK or p.corpse or item == Net.ITEM_NONE:
		return false
	var cell := p.st.y * map.width + p.st.x
	var things: PackedByteArray = floor_things.get(cell, PackedByteArray())
	if things.is_empty():
		things.resize(Net.FLOOR_STACK)
	var at := things.find(Net.ITEM_NONE)
	if at < 0:
		return false                         # the cell is full
	things[at] = item
	floor_things[cell] = things
	p.slots[p.hand] = Net.ITEM_NONE
	_floor_record(cell)
	return true


func _act(p: Player) -> bool:
	## Uses the thing in the hand by itself: switches a flashlight on or off.
	var item := p.in_hand()
	if p.cond != Net.COND_OK or p.corpse or Items.switched(item) == Net.ITEM_NONE:
		return false
	p.slots[p.hand] = Items.switched(item)
	return true


func _floor_record(cell: int) -> void:
	var buf: PackedByteArray = _floor_change[_chunk_of(cell % map.width, cell / map.width)]
	_put_floor(buf, cell)
	_ship_sums_tick = -1


func _put_floor(buf: PackedByteArray, cell: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.FLOOR_BYTES)
	buf.encode_s16(o, cell % map.width)
	buf.encode_s16(o + 2, cell / map.width)
	var things: PackedByteArray = floor_things.get(cell, PackedByteArray())
	for k in Net.FLOOR_STACK:
		buf[o + 4 + k] = things[k] if k < things.size() else Net.ITEM_NONE


func _climb(p: Player) -> bool:
	## The "use" key was pressed. On a ladder, with nothing else to use in front,
	## the character goes to the other deck, and takes along whoever it hauls.
	if p.cond != Net.COND_OK or p.corpse:
		return false
	var to := map.climb[p.st.y * map.width + p.st.x]
	if to < 0 or _usable_ahead(p):
		return false
	# Only the place changes: a key the player holds goes on being held, so the
	# client's replay of its unconfirmed inputs still matches.
	p.st.place(to % map.width, to / map.width)
	p.self_dirty = true
	p.climbs += 1
	_record(p)
	if p.dragging >= 0:
		var body: Player = players[p.dragging]
		body.st.place(p.st.x, p.st.y)
		body.self_dirty = true
		_record(body)
	return true


# ------------------------------------------------- searching and hauling

func _look(p: Player) -> int:
	## Facing, condition, light and "moves slowly" as one byte (see Net.pack_look).
	return Net.pack_look(p.st.facing, p.cond, p.st.slow, not Items.light(p.in_hand()).is_empty())


func _can_reach(p: Player, id: int) -> bool:
	## Can this character lay hands on that one: it is on its feet, the other is
	## lying (unconscious or dead), and they are in the same cell or next to each other.
	if p.cond != Net.COND_OK or id < 0 or id >= players.size() or id == p.slot:
		return false
	var other: Player = players[id]
	return other != null and other.cond != Net.COND_OK \
		and absi(other.st.x - p.st.x) + absi(other.st.y - p.st.y) <= 1


func _hands_asked(p: Player, kind: int, id: int, at: int) -> void:
	## A press of "search" or "drag". Like a press on a ladder, it is judged on
	## the tick the client pressed it, where the client saw its character stand.
	p.want_kind = kind
	p.want_id = id
	p.want_tick = clampi(at, tick, tick + MAX_INPUT_LEAD)
	if p.want_tick == tick:
		_do_hands(p)


func _do_hands(p: Player) -> void:
	var id := p.want_id
	if p.want_kind == HAND_SEARCH:
		p.want_kind = 0
		if id == Net.NOBODY:
			_stop_search(p)
		elif _can_reach(p, id):
			p.searching = id
			p.search_sent = PackedByteArray()        # so that the pockets are sent at once
	elif p.want_kind == HAND_DRAG:
		if id == Net.NOBODY:
			p.want_kind = 0
			_let_go(p)
			return
		if p.st.cd > 0 and tick < p.want_tick + HAND_WAIT_TICKS:
			return                                   # in mid-step: take hold when the step is done
		p.want_kind = 0
		if p.dragging < 0 and p.st.cd == 0 and _can_reach(p, id) and players[id].dragged_by < 0:
			var body: Player = players[id]
			p.dragging = id
			body.dragged_by = p.slot
			p.st.slow = true
			body.st.slow = true
			p.self_dirty = true
			_record(p)
			_record(body)


func _let_go(p: Player) -> void:
	## Stops hauling.
	if p.dragging < 0:
		return
	var body: Player = players[p.dragging] if p.dragging < players.size() else null
	if body != null and body.dragged_by == p.slot:
		body.dragged_by = -1
		body.st.slow = false
		_record(body)
	p.dragging = -1
	p.st.slow = false
	p.self_dirty = true
	_record(p)


func _stop_search(p: Player) -> void:
	if p.searching < 0:
		return
	p.searching = -1
	if p.peer != null:
		var msg := PackedByteArray([Net.S_SEARCH, 0xFF, 0xFF])
		msg.resize(3 + Net.SLOTS)
		p.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func _haul(p: Player, to_x: int, to_y: int) -> void:
	## The character has just stepped away from that cell: whoever it hauls slides into it.
	var body: Player = players[p.dragging]
	if body == null:
		return
	body.st.fx = body.st.x
	body.st.fy = body.st.y
	body.st.x = to_x
	body.st.y = to_y
	body.st.move_tick = tick
	body.st.span = p.st.span
	body.self_dirty = true
	_record(body)


func _update_hands(p: Player) -> void:
	## Keeps hauling and searching honest: both end when either side is no
	## longer in a state for it, or they are no longer together.
	if p.want_kind != 0 and tick >= p.want_tick:
		_do_hands(p)
	if p.dragging >= 0 and not _can_reach(p, p.dragging):
		_let_go(p)
	if p.searching >= 0:
		if not _can_reach(p, p.searching):
			_stop_search(p)
		else:
			var other: Player = players[p.searching]
			if other.slots != p.search_sent:
				p.search_sent = other.slots.duplicate()
				if p.peer != null:
					var msg := PackedByteArray([Net.S_SEARCH, p.searching & 0xFF, p.searching >> 8])
					msg.append_array(other.slots)
					p.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func _loot_asked(p: Player, theirs: bool, index: int) -> void:
	## While searching: take the thing in one of their slots, or give them one of ours.
	if p.searching < 0 or index >= Net.SLOTS or not _can_reach(p, p.searching):
		return
	var other: Player = players[p.searching]
	var from := other if theirs else p
	var to := p if theirs else other
	var item := from.slots[index]
	if item != Net.ITEM_NONE and to.add(item):
		from.slots[index] = Net.ITEM_NONE
		if _look(other) != other.rep_look:
			_record(other)                       # a lit flashlight taken out of their hand


func _respawn(p: Player) -> void:
	## A dead character comes back as a fresh crew member at a spawn point; the body stays.
	_leave_body(p)
	p.tank = 1.0
	p.supply = false
	p.using = false
	p.work = 0
	p.slots.fill(Net.ITEM_NONE)          # what the dead one carried stays with the body (see _leave_body)
	var spot := _spawn_point()
	p.st.place(spot.x, spot.y)
	p.st.dir = Net.DIR_NONE
	p.st.down = false
	p.st.facing = Net.DIR_DOWN
	p.health = Net.HEALTH_FULL
	p.cond = Net.COND_OK
	p.inputs.clear()
	p.self_dirty = true
	_record(p)
	_ship_says("%s снова в строю." % p.name)


func _update_shutters() -> void:
	## Emergency shutters: every door has one. It drops by itself when the
	## pressure on the two sides of the door differs too much, and lifts when
	## the difference is gone. It needs power: without it nothing drops and
	## nothing lifts. A faulty one does neither, and a jammed door has nothing to shut.
	if not powered():
		return
	for d in doors.ready.size():
		var a := map.door_sides[d * 2]
		var b := map.door_sides[d * 2 + 1]
		if a < 0 or b < 0 or doors.faulty[d] == 1 or doors.jammed[d] == 1:
			continue
		var gap := absf(air.air[a] - air.air[b])
		if doors.locked[d] == 1:
			if gap < Net.SHUTTER_LIFT:
				doors.locked[d] = 0
		elif gap >= Net.SHUTTER_DROP and tick >= _forced_until[d]:
			doors.locked[d] = 1
			_door_hold[d] = mini(_door_hold[d], tick)    # an open door shuts at once, unless somebody stands in it


func _update_doors() -> void:
	# doors pushed this tick stay open for a while
	for d in doors.bumped:
		_door_hold[d] = tick + Doors.HOLD_TICKS
	doors.bumped.clear()
	# a door does not close on somebody standing in it
	for p: Player in players:
		if p != null:
			var d := map.door_at(p.st.x, p.st.y)
			if d >= 0 and _door_hold[d] < tick + Net.MOVE_TICKS + 2:
				_door_hold[d] = tick + Net.MOVE_TICKS + 2
	for d in doors.ready.size():
		if doors.ready[d] != Doors.CLOSED and tick >= doors.ready[d] and tick >= _door_hold[d] and doors.jammed[d] == 0:
			doors.ready[d] = Doors.CLOSED
		if doors.ready[d] != _door_sent[d] or doors.flags(d) != _flags_sent[d]:
			if doors.ready[d] != _door_sent[d]:
				air.wake()
			_door_sent[d] = doors.ready[d]
			_flags_sent[d] = doors.flags(d)
			var buf: PackedByteArray = _door_change[_chunk_of(map.doors[d].x, map.doors[d].y)]
			_put_door(buf, d)
			_ship_sums_tick = -1


func _put_door(buf: PackedByteArray, d: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.DOOR_BYTES)
	buf.encode_u16(o, d)
	buf.encode_s32(o + 2, -1 if doors.ready[d] == Doors.CLOSED else doors.ready[d])
	buf.encode_u8(o + 6, doors.flags(d))


func _collect_air() -> void:
	## Notes which cells' air differs from what clients were last told.
	if air.settled and _air_sent == air.level:
		return
	var level := air.level
	var w := map.width
	for i in level.size():
		if level[i] != _air_sent[i]:
			_air_sent[i] = level[i]
			var x := i % w
			var y := i / w
			var buf: PackedByteArray = _air_change[_chunk_of(x, y)]
			buf.append((y & 15) * 16 + (x & 15))
			buf.append(level[i])
			_ship_sums_tick = -1


func _ensure_ship_sums() -> void:
	if _ship_sums_tick == tick:
		return
	_ship_sums_tick = tick
	_ship_sums.fill(0)
	for d in doors.ready.size():
		var at: Vector2i = map.doors[d]
		_ship_sums[_chunk_of(at.x, at.y)] += Net.door_hash(d, -1 if _door_sent[d] == Doors.CLOSED else _door_sent[d], _flags_sent[d])
	for cell: int in air.holes.keys():
		_ship_sums[_chunk_of(cell % map.width, cell / map.width)] += Net.hull_hash(cell % map.width, cell / map.width)
	for cell: int in floor_things.keys():
		_ship_sums[_chunk_of(cell % map.width, cell / map.width)] += Net.floor_hash(cell % map.width, cell / map.width, floor_things[cell])
	var w := map.width
	for i in _air_sent.size():
		if _air_sent[i] != 0:
			_ship_sums[_chunk_of(i % w, i / w)] += Net.air_hash(i % w, i / w, _air_sent[i])


func _append_ship_full(out: PackedByteArray, c: int, cx: int, cy: int) -> void:
	## Everything about the ship in one chunk, for a client that has just come within sight of it.
	var in_chunk: PackedInt32Array = _doors_in[c]
	if not in_chunk.is_empty():
		var buf := PackedByteArray()
		for d in in_chunk:
			_put_door(buf, d)
		_append_records(out, Net.SEC_DOOR, buf, Net.DOOR_BYTES)
	var holes := PackedByteArray()
	for cell: int in air.holes.keys():
		if _chunk_of(cell % map.width, cell / map.width) == c:
			var o := holes.size()
			holes.resize(o + Net.HULL_BYTES)
			holes.encode_s16(o, cell % map.width)
			holes.encode_s16(o + 2, cell / map.width)
			holes.encode_u8(o + 4, 1)
	if not holes.is_empty():
		_append_records(out, Net.SEC_HULL, holes, Net.HULL_BYTES)
	var things := PackedByteArray()
	for cell: int in floor_things.keys():
		if _chunk_of(cell % map.width, cell / map.width) == c:
			_put_floor(things, cell)
	if not things.is_empty():
		_append_records(out, Net.SEC_FLOOR, things, Net.FLOOR_BYTES)
	var o2 := out.size()
	out.resize(o2 + 3 + 256)
	out.encode_u8(o2, Net.SEC_AIR_FULL)
	out.encode_u8(o2 + 1, cx)
	out.encode_u8(o2 + 2, cy)
	for ly in 16:
		var y := cy * 16 + ly
		if y >= map.height:
			break
		for lx in 16:
			var x := cx * 16 + lx
			if x >= map.width:
				break
			out[o2 + 3 + ly * 16 + lx] = _air_sent[y * map.width + x]


func _append_records(out: PackedByteArray, section: int, records: PackedByteArray, record_bytes: int) -> void:
	var o := out.size()
	out.resize(o + 3)
	out.encode_u8(o, section)
	out.encode_u16(o + 1, records.size() / record_bytes)
	out.append_array(records)


func _bot_think(p: Player) -> void:
	var st := p.st
	var blocked := st.dir != 0 and (not map.walkable(st.x + Net.DX[st.dir], st.y + Net.DY[st.dir]) or _would_vent(st.x, st.y, st.dir))
	if blocked:
		st.dir = Net.DIR_NONE
	if tick < p.bot_until and not blocked:
		return
	if map.climb[st.y * map.width + st.x] >= 0 and _rng.randf() < 0.3 and _climb(p):
		p.bot_until = tick + _rng.randi_range(4, 12)
		return
	# now and then it switches its flashlight, puts it down or picks something up
	# (which also keeps the floor busy in network tests)
	var whim := _rng.randf()
	if st.cd == 0 and whim < 0.04:
		_act(p)
	elif st.cd == 0 and whim < 0.06:
		_put_down(p)
	elif st.cd == 0 and whim < 0.1:
		_pick_up(p)
	if _rng.randf() < 0.2 and not blocked:
		st.dir = Net.DIR_NONE
		p.bot_until = tick + _rng.randi_range(10, 40)
		return
	for attempt in 6:
		var d := _rng.randi_range(1, 4)
		if map.walkable(st.x + Net.DX[d], st.y + Net.DY[d]) and not _would_vent(st.x, st.y, d):
			st.dir = d
			break
	p.bot_until = tick + _rng.randi_range(4, 30)


func _would_vent(x: int, y: int, dir: int) -> bool:
	## True if stepping that way opens a shut door with very different pressure
	## behind it. Bots leave such doors alone, so they do not empty the ship.
	var dx: int = x + Net.DX[dir]
	var dy: int = y + Net.DY[dir]
	var d := map.door_at(dx, dy)
	if d < 0 or not doors.is_shut(d):
		return false
	var fx: int = dx + Net.DX[dir]
	var fy: int = dy + Net.DY[dir]
	if not map.walkable(fx, fy):
		return false
	var here := air.air[y * map.width + x]
	if here < Vitals.BREATH_MIN:
		return false                # it is suffocating: getting out matters more
	return absf(here - air.air[fy * map.width + fx]) > 0.25


func _chunk_of(x: int, y: int) -> int:
	return (y >> Net.CHUNK_SHIFT) * _cw + (x >> Net.CHUNK_SHIFT)


func _put_record(buf: PackedByteArray, slot: int, x: int, y: int, facing: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.ENT_BYTES)
	buf.encode_u16(o, slot)
	buf.encode_s16(o + 2, x)
	buf.encode_s16(o + 4, y)
	buf.encode_u8(o + 6, facing)


func _record(p: Player, gone: bool = false) -> void:
	## Notes that a character changed, for everyone who can see where it is or was.
	var facing := Net.FACING_GONE if gone else _look(p)
	var now_chunk := _chunk_of(p.st.x, p.st.y)
	var buf: PackedByteArray = _change[now_chunk]
	_put_record(buf, p.slot, p.st.x, p.st.y, facing)
	var old_chunk := now_chunk if p.rep_x == -9999 else _chunk_of(p.rep_x, p.rep_y)
	if old_chunk != now_chunk:
		# it left a chunk: those who see that chunk are told where it went
		var old_buf: PackedByteArray = _change[old_chunk]
		_put_record(old_buf, p.slot, p.st.x, p.st.y, facing)
		p.left_chunk = old_chunk
		p.left_window = _window
	elif p.left_window == _window and p.left_chunk != now_chunk:
		# It left a chunk earlier in this same send (a ladder, then a step) and has
		# changed again. A client that sees both chunks reads both lists, in an
		# order of its own, so the list of the chunk it left must end with the
		# newest word too.
		var left_buf: PackedByteArray = _change[p.left_chunk]
		_put_record(left_buf, p.slot, p.st.x, p.st.y, facing)
	p.rep_x = p.st.x
	p.rep_y = p.st.y
	p.rep_look = _look(p)


func _ensure_full() -> void:
	if _full_tick == tick:
		return
	_full_tick = tick
	for c in _full.size():
		_full[c] = PackedByteArray()
		_sums[c] = 0
	for p: Player in players:
		if p == null:
			continue
		var c := _chunk_of(p.st.x, p.st.y)
		var buf: PackedByteArray = _full[c]
		var look := _look(p)
		_put_record(buf, p.slot, p.st.x, p.st.y, look)
		_sums[c] += Net.ent_hash(p.slot, p.st.x, p.st.y, look)


func _append_ents(out: PackedByteArray, records: PackedByteArray) -> void:
	var o := out.size()
	out.resize(o + 3)
	out.encode_u8(o, Net.SEC_ENT)
	out.encode_u16(o + 1, records.size() / Net.ENT_BYTES)
	out.append_array(records)


func _send_world() -> void:
	for p: Player in players:
		if p == null or p.peer == null:
			continue
		# The view is centred on a chunk of the character's deck, and takes in the
		# same chunks of every other deck: what is seen through a glass floor is
		# straight below, and a change of deck brings nothing new into view.
		var st := p.st
		var cx := st.x >> Net.CHUNK_SHIFT
		var cy := map.local_y(st.y) >> Net.CHUNK_SHIFT
		var old_cx := p.view_cx
		var old_cy := p.view_cy
		var view_moved := cx != old_cx or cy != old_cy
		var check := (tick + p.slot) % CHECK_TICKS == 0
		var out := PackedByteArray()
		out.resize(5)
		out.encode_u8(0, Net.S_WORLD)
		out.encode_u32(1, tick)
		if view_moved:
			out.append(Net.SEC_VIEW)
			out.append(cx)
			out.append(cy)
			p.view_cx = cx
			p.view_cy = cy
		if view_moved or check:
			_ensure_full()
		if check:
			_ensure_ship_sums()
		var sum := 0
		var ship_sum := 0
		for deck in map.deck_count:
			for yy in range(maxi(cy - 1, 0), mini(cy + 2, _ch)):
				var row := deck * _deck_rows + yy          # the chunk row in the whole grid
				for xx in range(maxi(cx - 1, 0), mini(cx + 2, _cw)):
					var c := row * _cw + xx
					if view_moved and (absi(xx - old_cx) > 1 or absi(yy - old_cy) > 1):
						# this chunk just came into view: send everything in it
						var everything: PackedByteArray = _full[c]
						if not everything.is_empty():
							_append_ents(out, everything)
						_append_ship_full(out, c, xx, row)
					else:
						var changes: PackedByteArray = _change[c]
						if not changes.is_empty():
							_append_ents(out, changes)
						var door_changes: PackedByteArray = _door_change[c]
						if not door_changes.is_empty():
							_append_records(out, Net.SEC_DOOR, door_changes, Net.DOOR_BYTES)
						var hull_changes: PackedByteArray = _hull_change[c]
						if not hull_changes.is_empty():
							_append_records(out, Net.SEC_HULL, hull_changes, Net.HULL_BYTES)
						var floor_changes: PackedByteArray = _floor_change[c]
						if not floor_changes.is_empty():
							_append_records(out, Net.SEC_FLOOR, floor_changes, Net.FLOOR_BYTES)
						var air_changes: PackedByteArray = _air_change[c]
						if not air_changes.is_empty():
							var oa := out.size()
							out.resize(oa + 5)
							out.encode_u8(oa, Net.SEC_AIR)
							out.encode_u8(oa + 1, xx)
							out.encode_u8(oa + 2, row)
							out.encode_u16(oa + 3, air_changes.size() / 2)
							out.append_array(air_changes)
					if check:
						sum += _sums[c]
						ship_sum += _ship_sums[c]
		var health_now := roundi(p.health)
		var tank_now := roundi(p.tank * Net.TANK_FULL)
		var work_now := p.work * 100 / maxi(p.work_total, 1)
		var vitals := ((health_now + 200) << 20) | (tank_now << 10) | (work_now << 1) | (1 if p.supply else 0)
		if vitals != p.vitals_sent or p.slots != p.slots_sent:
			p.vitals_sent = vitals
			p.slots_sent = p.slots.duplicate()
			var ov := out.size()
			out.resize(ov + 1 + Net.VITALS_BYTES)
			out.encode_u8(ov, Net.SEC_VITALS)
			out.encode_s16(ov + 1, health_now)
			out.encode_u8(ov + 3, tank_now)
			out.encode_u8(ov + 4, 1 if p.supply else 0)
			out.encode_u8(ov + 5, work_now)
			for k in Net.SLOTS:
				out.encode_u8(ov + 6 + k, p.slots[k])
		if p.self_dirty or tick - p.last_self_tick >= SELF_REFRESH_TICKS:
			var o := out.size()
			out.resize(o + 1 + Net.SELF_BYTES)
			out.encode_u8(o, Net.SEC_SELF)
			out.encode_s16(o + 1, st.x)
			out.encode_s16(o + 3, st.y)
			out.encode_u8(o + 5, st.cd)
			out.encode_u8(o + 6, _look(p) | (Net.LOOK_LONG_STEP if st.span > Net.MOVE_TICKS else 0))
			out.encode_u8(o + 7, st.dir)
			out.encode_u16(o + 8, p.last_seq)
			out.encode_s32(o + 10, st.move_tick)
			out.encode_s16(o + 14, st.fx)
			out.encode_s16(o + 16, st.fy)
			p.self_dirty = false
			p.last_self_tick = tick
		if check:
			var o2 := out.size()
			out.resize(o2 + 9)
			out.encode_u8(o2, Net.SEC_CHECK)
			out.encode_u32(o2 + 1, sum & 0xFFFFFFFF)
			out.encode_u32(o2 + 5, ship_sum & 0xFFFFFFFF)
		if out.size() > 5 or tick - p.last_packet_tick >= HEARTBEAT_TICKS:
			p.peer.send(0, out, ENetPacketPeer.FLAG_RELIABLE)
			p.last_packet_tick = tick
	_window += 1
	for c in _change.size():
		var b: PackedByteArray = _change[c]
		if not b.is_empty():
			_change[c] = PackedByteArray()
		if not (_door_change[c] as PackedByteArray).is_empty():
			_door_change[c] = PackedByteArray()
		if not (_hull_change[c] as PackedByteArray).is_empty():
			_hull_change[c] = PackedByteArray()
		if not (_floor_change[c] as PackedByteArray).is_empty():
			_floor_change[c] = PackedByteArray()
		if not (_air_change[c] as PackedByteArray).is_empty():
			_air_change[c] = PackedByteArray()
