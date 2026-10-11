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

var _cw := 1                        # chunks across / down
var _ch := 1
var _change: Array = []             # per chunk: entity records changed this tick
var _full: Array = []               # per chunk: every entity in it (built on demand)
var _sums := PackedInt64Array()
var _full_tick := -1

# the ship itself: doors, hull, air
var doors := Doors.new()
var air := Air.new()
var _door_hold := PackedInt32Array()   # per door: it will not close before this tick
var _door_sent := PackedInt32Array()   # per door: the state clients were last told
var _doors_in: Array = []              # per chunk: the doors in it
var _door_change: Array = []           # per chunk: door records changed this tick
var _hull_change: Array = []           # per chunk: hull records changed this tick
var _air_change: Array = []            # per chunk: (cell, air) pairs changed since the last air send
var _air_sent := PackedByteArray()     # per cell: the air level clients were last told
var _ship_sums := PackedInt64Array()   # per chunk: checksum of doors, hull and air as clients know them
var _ship_sums_tick := -1

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
	_change.clear()
	_full.clear()
	_door_change.clear()
	_hull_change.clear()
	_air_change.clear()
	_doors_in.clear()
	for c in _cw * _ch:
		_change.append(PackedByteArray())
		_full.append(PackedByteArray())
		_door_change.append(PackedByteArray())
		_hull_change.append(PackedByteArray())
		_air_change.append(PackedByteArray())
		_doors_in.append(PackedInt32Array())
	_sums.resize(_cw * _ch)
	_ship_sums.resize(_cw * _ch)
	doors.setup(map.doors.size())
	_door_hold.resize(map.doors.size())
	_door_hold.fill(0)
	_door_sent = doors.ready.duplicate()
	for d in map.doors.size():
		var in_chunk: PackedInt32Array = _doors_in[_chunk_of(map.doors[d].x, map.doors[d].y)]
		in_chunk.append(d)
	air.setup(map)
	_air_sent = air.level.duplicate()
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
		p.using = pkt.size() > 1 and pkt[1] != 0
	elif kind == Net.C_SUIT:
		if p.cond == Net.COND_OK and pkt.size() > 1:
			p.supply = pkt[1] != 0 and p.tank > 0.0
	elif kind == Net.C_RESPAWN:
		if p.cond == Net.COND_DEAD and tick - p.died_tick >= Net.RESPAWN_TICKS:
			_respawn(p)
	elif kind == Net.C_ADMIN:
		if pkt.size() > 2 and shutdown_token != "" and pkt.slice(2).get_string_from_utf8() == shutdown_token:
			if pkt[1] == Net.ADMIN_BREACH:
				# the wall the player faces, if it can be breached; otherwise the nearest that can
				var ahead := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
				if not (ahead >= 0 and map.hull.has(ahead) and breach(ahead)):
					breach_near(p.st.x, p.st.y)
			elif pkt[1] == Net.ADMIN_SEAL:
				seal_all()


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
	## The character is about to be given a new body: its old one stays where it lies.
	var c := _alloc(p.name)
	c.colour = p.colour
	c.st.copy_from(p.st)
	c.st.dir = Net.DIR_NONE
	c.st.down = true
	c.cond = Net.COND_DEAD
	c.health = Net.HEALTH_DEAD
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


# ------------------------------------------------------------------- hull

func breach(cell: int) -> bool:
	## Tears a hole in a hull cell. Returns false if there already is one.
	if not air.set_hole(cell, true):
		return false
	_hull_record(cell, 1)
	_ship_says("Разгерметизация! Пробоина в обшивке.")
	return true


func breach_near(x: int, y: int) -> bool:
	## A hole in the whole hull cell closest to the given place.
	var best := -1
	var best_d := 1 << 30
	for cell in map.hull:
		if air.holes.has(cell):
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
		if Mover.step(p.st, map, doors, tick):
			p.self_dirty = true
		_update_vitals(p)
		_update_work(p)
		if p.st.x != p.rep_x or p.st.y != p.rep_y or Net.pack_look(p.st.facing, p.cond) != p.rep_look:
			_record(p)
	_update_doors()
	if tick % Net.AIR_EVERY == 0:
		air.step(doors, tick)
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
	## Holding "use" on what the character faces: a hole is mended, an oxygen station fills the tank.
	if not p.using or p.cond != Net.COND_OK or p.st.cd > 0 or p.st.dir != Net.DIR_NONE:
		p.work = 0
		return
	var cell := map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	if cell >= 0 and air.holes.has(cell):
		if p.work_cell != cell:
			p.work_cell = cell
			p.work = 0
		p.work += 1
		if p.work >= Net.REPAIR_TICKS:
			p.work = 0
			air.set_hole(cell, false)
			_hull_record(cell, 0)
			_ship_says("%s заделывает пробоину. Воздух сам не вернётся: его дадут соседние отсеки." % p.name)
	elif cell >= 0 and map.oxygen.has(cell):
		p.work = 0
		p.tank = minf(p.tank + Net.TICK_SEC / Vitals.REFILL_SECONDS, 1.0)
	else:
		p.work = 0


func _respawn(p: Player) -> void:
	## A dead character comes back as a fresh crew member at a spawn point; the body stays.
	_leave_body(p)
	p.tank = 1.0
	p.supply = false
	p.using = false
	p.work = 0
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
		if doors.ready[d] != Doors.CLOSED and tick >= doors.ready[d] and tick >= _door_hold[d]:
			doors.ready[d] = Doors.CLOSED
		if doors.ready[d] != _door_sent[d]:
			_door_sent[d] = doors.ready[d]
			var buf: PackedByteArray = _door_change[_chunk_of(map.doors[d].x, map.doors[d].y)]
			_put_door(buf, d)
			air.wake()
			_ship_sums_tick = -1


func _put_door(buf: PackedByteArray, d: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.DOOR_BYTES)
	buf.encode_u16(o, d)
	buf.encode_s32(o + 2, -1 if doors.ready[d] == Doors.CLOSED else doors.ready[d])


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
		_ship_sums[_chunk_of(at.x, at.y)] += Net.door_hash(d, -1 if _door_sent[d] == Doors.CLOSED else _door_sent[d])
	for cell: int in air.holes.keys():
		_ship_sums[_chunk_of(cell % map.width, cell / map.width)] += Net.hull_hash(cell % map.width, cell / map.width)
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
	var facing := Net.FACING_GONE if gone else Net.pack_look(p.st.facing, p.cond)
	var now_chunk := _chunk_of(p.st.x, p.st.y)
	var buf: PackedByteArray = _change[now_chunk]
	_put_record(buf, p.slot, p.st.x, p.st.y, facing)
	if p.rep_x != -9999:
		var old_chunk := _chunk_of(p.rep_x, p.rep_y)
		if old_chunk != now_chunk:
			var old_buf: PackedByteArray = _change[old_chunk]
			_put_record(old_buf, p.slot, p.st.x, p.st.y, facing)
	p.rep_x = p.st.x
	p.rep_y = p.st.y
	p.rep_look = Net.pack_look(p.st.facing, p.cond)


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
		var look := Net.pack_look(p.st.facing, p.cond)
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
		var st := p.st
		var cx := st.x >> Net.CHUNK_SHIFT
		var cy := st.y >> Net.CHUNK_SHIFT
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
		for yy in range(maxi(cy - 1, 0), mini(cy + 2, _ch)):
			for xx in range(maxi(cx - 1, 0), mini(cx + 2, _cw)):
				var c := yy * _cw + xx
				if view_moved and (absi(xx - old_cx) > 1 or absi(yy - old_cy) > 1):
					# this chunk just came into view: send everything in it
					var everything: PackedByteArray = _full[c]
					if not everything.is_empty():
						_append_ents(out, everything)
					_append_ship_full(out, c, xx, yy)
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
					var air_changes: PackedByteArray = _air_change[c]
					if not air_changes.is_empty():
						var oa := out.size()
						out.resize(oa + 5)
						out.encode_u8(oa, Net.SEC_AIR)
						out.encode_u8(oa + 1, xx)
						out.encode_u8(oa + 2, yy)
						out.encode_u16(oa + 3, air_changes.size() / 2)
						out.append_array(air_changes)
				if check:
					sum += _sums[c]
					ship_sum += _ship_sums[c]
		var health_now := roundi(p.health)
		var tank_now := roundi(p.tank * Net.TANK_FULL)
		var work_now := p.work * 100 / Net.REPAIR_TICKS
		var vitals := ((health_now + 200) << 20) | (tank_now << 10) | (work_now << 1) | (1 if p.supply else 0)
		if vitals != p.vitals_sent:
			p.vitals_sent = vitals
			var ov := out.size()
			out.resize(ov + 1 + Net.VITALS_BYTES)
			out.encode_u8(ov, Net.SEC_VITALS)
			out.encode_s16(ov + 1, health_now)
			out.encode_u8(ov + 3, tank_now)
			out.encode_u8(ov + 4, 1 if p.supply else 0)
			out.encode_u8(ov + 5, work_now)
		if p.self_dirty or tick - p.last_self_tick >= SELF_REFRESH_TICKS:
			var o := out.size()
			out.resize(o + 1 + Net.SELF_BYTES)
			out.encode_u8(o, Net.SEC_SELF)
			out.encode_s16(o + 1, st.x)
			out.encode_s16(o + 3, st.y)
			out.encode_u8(o + 5, st.cd)
			out.encode_u8(o + 6, Net.pack_look(st.facing, p.cond))
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
	for c in _change.size():
		var b: PackedByteArray = _change[c]
		if not b.is_empty():
			_change[c] = PackedByteArray()
		if not (_door_change[c] as PackedByteArray).is_empty():
			_door_change[c] = PackedByteArray()
		if not (_hull_change[c] as PackedByteArray).is_empty():
			_hull_change[c] = PackedByteArray()
		if not (_air_change[c] as PackedByteArray).is_empty():
			_air_change[c] = PackedByteArray()
