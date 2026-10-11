extends Node
## The client's side of the connection. It keeps what the server says about
## the world (`ents`), and predicts the player's own character so that it
## reacts to keys at once instead of waiting for the server's answer.
##
## Two clocks are kept, both measured in server ticks:
##  - the "received" clock: roughly the newest tick we have data for. Other
##    characters are drawn a little behind it, so their movement is smooth
##    even when packets arrive unevenly;
##  - the "predicted" clock: runs ahead by the connection delay. Our own
##    inputs are stamped with it, so they reach the server just before the
##    tick they are meant for, and server and client simulate them alike.

signal joined                        # accepted by the server; map is loaded
signal failed(reason: String)        # could not get in
signal lost(reason: String)          # dropped while playing
signal roster_changed
signal chat(from_id: int, text: String)
signal notice(text: String)
signal arrived                       # the ship has just landed in another sector

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Sectors := preload("res://src/shared/sectors.gd")

const INTERP_TICKS := 2.0            # others are drawn this far in the past (0.1 s)
const PRED_MARGIN := 1.5             # safety margin of the predicted clock, in ticks
const CLOCK_SNAP := 6.0              # a clock this far off is set at once instead of eased
const CONNECT_TIMEOUT_MS := 6000
const INPUT_COPIES := 2              # extra copies of every input change, one per frame

enum { IDLE, CONNECTING, GREETING, PLAYING }


class Ent:
	var id := 0
	var x := 0
	var y := 0
	var facing := 2
	var cond := 0                    # Net.COND_*
	var look := 2                    # facing and condition as the server packs them (for the checksum)
	var steps: Array = []            # recent steps: [start tick, from x, from y, to x, to y, facing]


var phase := IDLE
var my_id := -1
var map := ShipMap.new()
var roster := {}                     # id -> {"name": String, "colour": int, "kind": Net.KIND_*}
var ents := {}                       # id -> Ent, exactly as the server reported
var predict := true                  # predict our own character (false = wait for the server)
var admin_token := ""                # set when this game started the server: unlocks the host's test tools

# the ship itself, as the server last described it
var doors := Doors.new()
var air := PackedByteArray()         # per cell: 0..Net.AIR_FULL (cells outside our view keep their last value)
var holes := {}                      # breached hull cell -> true
var ship_changes := 0                # goes up whenever doors, hull or air change: views redraw on it

# where the ship is
var sectors := Sectors.new()
var sector := 0                      # the sector the ship is in
var jump_to := Net.NO_SECTOR         # the sector it is jumping to, if any
var jump_tick := 0                   # the server tick the jump lands on
var drive_ready := 0                 # the server tick from which the drive can be used again
var visited := 1                     # sectors the ship has been in, as bits

# our own character's body
var health := 100                    # 100 = unhurt, 0 and below = unconscious, Net.HEALTH_DEAD = dead
var my_cond := 0                     # Net.COND_*
var tank := Net.TANK_FULL            # oxygen left in the suit's tank, 0..Net.TANK_FULL
var supply := false                  # breathing from the tank
var work := 0                        # progress of what we are doing with the "use" key, 0..100
var want_dir := 0                    # direction the player holds right now; set by the game screen

# for the debug overlay
var rtt_ms := 0.0
var server_tick := 0
var mispredicts := 0
var steps_predicted := 0
var checks_ok := 0
var checks_bad := 0
var ship_checks_bad := 0             # of those, the ones where doors, hull or air disagreed
var bytes_in := 0
var packets_in := 0

var pred := Mover.State.new()        # our own character, predicted
var pred_tick := 0                   # last tick simulated for it
var pred_doors := Doors.new()        # the doors as our own predicted walking leaves them

var _auth := Mover.State.new()       # the server's last word on our character...
var _auth_tick := 0                  # ...and the tick it was true on

var _host: ENetConnection = null
var _peer: ENetPacketPeer = null
var _name := ""
var _t_connect := 0
var _view_cx := -100
var _view_cy := -100

var _have_clock := false
var _recv_offset := 0.0
var _recv_target := 0.0
var _pred_offset := 0.0
var _pred_target := 0.0
var _ahead_best := PackedFloat64Array()   # freshest clock reading in each of the last few half-seconds
var _ahead_slot := -1

var _have_self := false
var _have_auth := false
var _nav_known := false
var _inputs: Array = []              # input changes not yet confirmed: [seq, apply tick, dir, applied]
var _seq := 0
var _sent_dir := 0
var _last_apply := 0
var _corr := Vector2.ZERO            # leftover of a correction, eased out so the sprite does not jump
var _repeat_msg := PackedByteArray() # the newest input change, repeated in case the first copy is lost
var _repeat_left := 0


func connect_to(address: String, port: int, player_name: String) -> String:
	## Starts connecting. Returns "" or what went wrong straight away;
	## later results come through the `joined` / `failed` signals.
	close()
	_host = ENetConnection.new()
	if _host.create_host(1, 2) != OK:
		_host = null
		return "Не удалось открыть сетевое соединение."
	_peer = _host.connect_to_host(address, port, 2)
	if _peer == null:
		_host.destroy()
		_host = null
		return "Не удалось начать подключение к %s:%d. Проверьте адрес." % [address, port]
	_name = player_name
	_t_connect = Time.get_ticks_msec()
	phase = CONNECTING
	return ""


func close() -> void:
	if _host != null:
		if _peer != null and _peer.is_active():
			_peer.peer_disconnect()
			_host.flush()
		_host.destroy()
	_host = null
	_peer = null
	phase = IDLE
	my_id = -1
	roster.clear()
	ents.clear()
	_inputs.clear()
	_have_clock = false
	_ahead_best.clear()
	_ahead_slot = -1
	_have_self = false
	_have_auth = false
	_view_cx = -100
	_view_cy = -100
	_sent_dir = 0
	_last_apply = 0
	_repeat_left = 0
	_corr = Vector2.ZERO
	want_dir = 0
	mispredicts = 0
	steps_predicted = 0
	checks_ok = 0
	checks_bad = 0
	ship_checks_bad = 0
	holes.clear()
	admin_token = ""
	health = 100
	my_cond = 0
	tank = Net.TANK_FULL
	supply = false
	work = 0
	sector = 0
	jump_to = Net.NO_SECTOR
	visited = 1
	_nav_known = false
	bytes_in = 0
	packets_in = 0


func send_chat(text: String) -> void:
	if phase != PLAYING:
		return
	var body := text.left(Net.MAX_CHAT).to_utf8_buffer()
	if body.is_empty():
		return
	var msg := PackedByteArray()
	msg.resize(3)
	msg.encode_u8(0, Net.C_CHAT)
	msg.encode_u16(1, body.size())
	msg.append_array(body)
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func stop_server_and_close(token: String) -> void:
	## Asks the server to stop (it obeys only the game that started it, see
	## main.gd), waits a moment for it to hang up on us, then closes.
	## The wait matters: a goodbye sent right behind the request would make
	## the server drop the request unread.
	if _peer != null and _peer.is_active() and not token.is_empty():
		var msg := PackedByteArray([Net.C_SHUTDOWN])
		msg.append_array(token.to_utf8_buffer())
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
		var deadline := Time.get_ticks_msec() + 500
		while Time.get_ticks_msec() < deadline and _peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			_host.service(0)
			OS.delay_msec(5)
	close()


func send_use(held: bool) -> void:
	## The "use" key went down or up. The server decides what it does (see GameServer._update_work).
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_USE, 1 if held else 0]), ENetPacketPeer.FLAG_RELIABLE)


func send_jump(target: int) -> void:
	## Asks for a jump. The server agrees only while our character stands at the sector console.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_JUMP, target]), ENetPacketPeer.FLAG_RELIABLE)


func server_now() -> float:
	## Our best guess of the server's tick right now.
	return now_ticks() + _recv_offset


func knows_sector(id: int) -> bool:
	## The crew knows what is in a sector it has been to or can reach in one jump.
	return (visited & (1 << id)) != 0 or sectors.linked(sector, id)


func send_suit(on: bool) -> void:
	## Turns the suit's oxygen supply on or off.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_SUIT, 1 if on else 0]), ENetPacketPeer.FLAG_RELIABLE)


func use_target() -> int:
	## What our character would use right now: 0 = nothing, 1 = a hole to mend,
	## 2 = an oxygen station, 3 = the sector console, 4 = the ship's controls.
	if phase != PLAYING or my_cond != Net.COND_OK:
		return 0
	var cell := map.cell_ahead(pred.x, pred.y, pred.facing)
	if cell < 0:
		return 0
	if holes.has(cell):
		return 1
	if map.oxygen.has(cell):
		return 2
	if map.chart.has(cell):
		return 3
	if map.helm.has(cell):
		return 4
	return 0


func crew_count() -> int:
	## Everybody aboard who is not a body left behind.
	var n := 0
	for id: int in roster.keys():
		if int(roster[id]["kind"]) != Net.KIND_CORPSE:
			n += 1
	return n


func is_corpse(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_CORPSE


func send_respawn() -> void:
	## Dead: ask to come back as a new crew member (the server allows it after a few seconds).
	if phase == PLAYING and my_cond == Net.COND_DEAD:
		_peer.send(0, PackedByteArray([Net.C_RESPAWN]), ENetPacketPeer.FLAG_RELIABLE)


func send_admin(command: int, argument: int = 0) -> void:
	## The hosting player's test tools (Net.ADMIN_*). The server ignores them without the right token.
	if phase != PLAYING or admin_token.is_empty():
		return
	var msg := PackedByteArray([Net.C_ADMIN, command, argument])
	msg.append_array(admin_token.to_utf8_buffer())
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func air_at(x: int, y: int) -> int:
	## Air in a cell, 0..Net.AIR_FULL; -1 where nobody can stand.
	if not map.walkable(x, y):
		return -1
	return air[y * map.width + x]


func door_open_amount(door: int) -> float:
	## 0 = shut, 1 = open, in between while it slides. Our own pushes show at once.
	var table := pred_doors if (predict and _have_self) else doors
	var ready := table.ready[door]
	if ready == Doors.CLOSED:
		return 0.0
	var t := pred_time() if (predict and _have_self) else now_ticks() + _recv_offset
	return clampf(1.0 - (float(ready) - t) / float(Doors.OPEN_TICKS), 0.0, 1.0)


func player_name(id: int) -> String:
	return str(roster[id]["name"]) if roster.has(id) else "?"


func is_bot(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_BOT


func player_colour(id: int) -> int:
	return int(roster[id]["colour"]) if roster.has(id) else 0


# ------------------------------------------------------------------ clocks

func now_ticks() -> float:
	return Time.get_ticks_usec() * 0.000001 * Net.TICK_HZ


func render_tick() -> float:
	return now_ticks() + _recv_offset - INTERP_TICKS


func pred_time() -> float:
	return now_ticks() + _pred_offset


func _update_clock(s_tick: int) -> void:
	var now := now_ticks()
	rtt_ms = minf(_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), 400.0)
	var recv := float(s_tick) - now
	var ahead := float(s_tick) + rtt_ms * 0.001 * Net.TICK_HZ + PRED_MARGIN - now
	# A packet that was held up on the way (a resend after a loss, a stalled
	# link) reads as "the server is further behind" and would slow our clock, so
	# our inputs would start arriving late. A delay can only make a reading
	# smaller, never larger, so the largest recent reading is the truthful one.
	# On an uneven link this also adds headroom by itself: the clock follows the
	# fastest packets while the inputs travel at the average speed.
	var slot := Time.get_ticks_msec() / 500
	if slot != _ahead_slot:
		_ahead_slot = slot
		_ahead_best.append(ahead)
		if _ahead_best.size() > 4:
			_ahead_best.remove_at(0)
	else:
		_ahead_best[_ahead_best.size() - 1] = maxf(_ahead_best[_ahead_best.size() - 1], ahead)
	for v in _ahead_best:
		ahead = maxf(ahead, v)
	if not _have_clock:
		_have_clock = true
		_recv_target = recv
		_recv_offset = recv
		_pred_target = ahead
		_pred_offset = ahead
		pred_tick = int(floor(now + _pred_offset))
	else:
		_recv_target += (recv - _recv_target) * 0.1
		_pred_target += (ahead - _pred_target) * 0.1


func _ease_clock(current: float, target: float, dt_ticks: float) -> float:
	var d := target - current
	if absf(d) > CLOCK_SNAP:
		return target
	var limit := dt_ticks * 0.15      # run at most 15% faster or slower than real time
	return current + clampf(d, -limit, limit)


# ----------------------------------------------------------------- network

func _process(delta: float) -> void:
	if phase == IDLE:
		return
	_poll()
	if phase == CONNECTING or phase == GREETING:
		if Time.get_ticks_msec() - _t_connect > CONNECT_TIMEOUT_MS:
			close()
			failed.emit("Сервер не отвечает. Проверьте адрес, порт и что сервер запущен.")
	elif phase == PLAYING:
		_advance(delta)


func _poll() -> void:
	var ev: Array = _host.service(0)
	while phase != IDLE and int(ev[0]) > 0:
		match int(ev[0]):
			ENetConnection.EVENT_CONNECT:
				_peer.set_timeout(32, 4000, 12000)
				var name_bytes := _name.to_utf8_buffer()
				var hello := PackedByteArray()
				hello.resize(4)
				hello.encode_u8(0, Net.C_HELLO)
				hello.encode_u16(1, Net.PROTOCOL)
				hello.encode_u8(3, name_bytes.size())
				hello.append_array(name_bytes)
				_peer.send(0, hello, ENetPacketPeer.FLAG_RELIABLE)
				phase = GREETING
			ENetConnection.EVENT_DISCONNECT:
				var was_playing := phase == PLAYING
				close()
				if was_playing:
					lost.emit("Соединение с сервером потеряно.")
				else:
					failed.emit("Не удалось подключиться к серверу.")
				return
			ENetConnection.EVENT_RECEIVE:
				var pkt := _peer.get_packet()
				packets_in += 1
				bytes_in += pkt.size()
				if not pkt.is_empty():
					_on_packet(pkt)
		if phase == IDLE:
			return
		ev = _host.service(0)


func _on_packet(pkt: PackedByteArray) -> void:
	match pkt[0]:
		Net.S_WORLD:
			if phase == PLAYING:
				_on_world(pkt)
		Net.S_WELCOME:
			_on_welcome(pkt)
		Net.S_REJECT:
			var reason := pkt[1] if pkt.size() > 1 else 0
			close()
			failed.emit(Net.reject_text(reason))
		Net.S_ROSTER:
			roster.clear()
			var count := pkt.decode_u16(1)
			var pos := 3
			for i in count:
				pos = _read_roster_entry(pkt, pos)
			roster_changed.emit()
		Net.S_JOIN:
			var id := pkt.decode_u16(1)
			_read_roster_entry(pkt, 1)
			roster_changed.emit()
			if id != my_id and not is_corpse(id):
				notice.emit("%s на борту." % player_name(id))
		Net.S_LEAVE:
			var gone := pkt.decode_u16(1)
			if roster.has(gone) and not is_corpse(gone):
				notice.emit("%s покинул корабль." % player_name(gone))
			roster.erase(gone)
			ents.erase(gone)
			roster_changed.emit()
		Net.S_SECTORS:
			sectors.unpack(pkt, 1)
		Net.S_NAV:
			var was := sector if _nav_known else int(pkt[1])
			_nav_known = true
			sector = pkt[1]
			jump_to = pkt[2]
			jump_tick = pkt.decode_u32(3)
			drive_ready = pkt.decode_u32(7)
			visited = pkt.decode_u32(11)
			if sector != was and phase == PLAYING:
				arrived.emit()
		Net.S_CHAT:
			var n := pkt.decode_u16(3)
			chat.emit(pkt.decode_u16(1), pkt.slice(5, 5 + n).get_string_from_utf8())


func _read_roster_entry(pkt: PackedByteArray, pos: int) -> int:
	var n := pkt[pos + 4]
	roster[pkt.decode_u16(pos)] = {
		"colour": pkt[pos + 2],
		"kind": pkt[pos + 3],
		"name": pkt.slice(pos + 5, pos + 5 + n).get_string_from_utf8(),
	}
	return pos + 5 + n


func _on_welcome(pkt: PackedByteArray) -> void:
	my_id = pkt.decode_u16(1)
	server_tick = pkt.decode_u32(3)
	var crc := pkt.decode_u32(7)
	var n := pkt[11]
	var map_name := pkt.slice(12, 12 + n).get_string_from_utf8()
	var problem := map.load_from(map_name)
	if problem == "" and map.crc != crc:
		problem = "Карта «%s» на сервере отличается от вашей. Нужна одинаковая сборка игры." % map_name
	if problem != "":
		close()
		failed.emit(problem)
		return
	doors.setup(map.doors.size())
	pred_doors.setup(map.doors.size())
	air.resize(map.width * map.height)
	air.fill(0)
	holes.clear()
	phase = PLAYING
	joined.emit()


func _on_world(pkt: PackedByteArray) -> void:
	var s_tick := pkt.decode_u32(1)
	server_tick = s_tick
	_update_clock(s_tick)
	var size := pkt.size()
	var pos := 5
	var doors_moved := false
	var reconciled := false
	while pos < size:
		var sec := pkt[pos]
		pos += 1
		if sec == Net.SEC_ENT:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				_apply_record(pkt.decode_u16(pos), pkt.decode_s16(pos + 2), pkt.decode_s16(pos + 4), pkt[pos + 6], s_tick)
				pos += Net.ENT_BYTES
		elif sec == Net.SEC_SELF:
			_reconcile(s_tick, pkt, pos)
			reconciled = true
			pos += Net.SELF_BYTES
		elif sec == Net.SEC_VITALS:
			health = pkt.decode_s16(pos)
			tank = pkt[pos + 2]
			supply = (pkt[pos + 3] & 1) != 0
			work = pkt[pos + 4]
			pos += Net.VITALS_BYTES
		elif sec == Net.SEC_DOOR:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				var ready := pkt.decode_s32(pos + 2)
				doors.ready[pkt.decode_u16(pos)] = Doors.CLOSED if ready < 0 else ready
				pos += Net.DOOR_BYTES
			doors_moved = true
			ship_changes += 1
		elif sec == Net.SEC_HULL:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				var cell := pkt.decode_s16(pos + 2) * map.width + pkt.decode_s16(pos)
				if pkt[pos + 4] != 0:
					holes[cell] = true
				else:
					holes.erase(cell)
				pos += Net.HULL_BYTES
			ship_changes += 1
		elif sec == Net.SEC_AIR:
			var x0 := pkt[pos] * 16
			var y0 := pkt[pos + 1] * 16
			var count := pkt.decode_u16(pos + 2)
			pos += 4
			for i in count:
				var local := pkt[pos]
				air[(y0 + (local >> 4)) * map.width + x0 + (local & 15)] = pkt[pos + 1]
				pos += 2
			ship_changes += 1
		elif sec == Net.SEC_AIR_FULL:
			var x0 := pkt[pos] * 16
			var y0 := pkt[pos + 1] * 16
			pos += 2
			for ly in 16:
				if y0 + ly >= map.height:
					break
				for lx in 16:
					if x0 + lx >= map.width:
						break
					air[(y0 + ly) * map.width + x0 + lx] = pkt[pos + ly * 16 + lx]
			pos += 256
			ship_changes += 1
		elif sec == Net.SEC_VIEW:
			_view_cx = pkt[pos]
			_view_cy = pkt[pos + 1]
			pos += 2
			for id: int in ents.keys():
				var e: Ent = ents[id]
				if _outside_view(e.x, e.y):
					ents.erase(id)
			for cell: int in holes.keys():
				if _outside_view(cell % map.width, cell / map.width):
					holes.erase(cell)
		elif sec == Net.SEC_CHECK:
			var want := pkt.decode_u32(pos)
			var want_ship := pkt.decode_u32(pos + 4)
			pos += 8
			var sum := 0
			for e: Ent in ents.values():
				sum += Net.ent_hash(e.id, e.x, e.y, e.look)
			var ship_ok := (_ship_sum() & 0xFFFFFFFF) == want_ship
			if (sum & 0xFFFFFFFF) == want and ship_ok:
				checks_ok += 1
			else:
				checks_bad += 1
				if not ship_ok:
					ship_checks_bad += 1
		else:
			push_warning("Непонятный раздел %d в пакете сервера." % sec)
			return
	if doors_moved and not reconciled:
		_rebuild_prediction()     # a door somebody else moved may change where our own walking ends up


func _ship_sum() -> int:
	## Checksum of the doors, holes and air in the chunks we are shown (see Net.*_hash).
	var sum := 0
	for d in doors.ready.size():
		var at: Vector2i = map.doors[d]
		if not _outside_view(at.x, at.y):
			sum += Net.door_hash(d, -1 if doors.ready[d] == Doors.CLOSED else doors.ready[d])
	for cell: int in holes.keys():
		sum += Net.hull_hash(cell % map.width, cell / map.width)
	for cy in range(maxi(_view_cy - 1, 0), mini(_view_cy + 2, map.chunks_high())):
		for cx in range(maxi(_view_cx - 1, 0), mini(_view_cx + 2, map.chunks_wide())):
			for y in range(cy * 16, mini(cy * 16 + 16, map.height)):
				var row := y * map.width
				for x in range(cx * 16, mini(cx * 16 + 16, map.width)):
					var a := air[row + x]
					if a != 0:
						sum += Net.air_hash(x, y, a)
	return sum


func _outside_view(x: int, y: int) -> bool:
	return absi((x >> Net.CHUNK_SHIFT) - _view_cx) > 1 or absi((y >> Net.CHUNK_SHIFT) - _view_cy) > 1


func _apply_record(id: int, x: int, y: int, look: int, s_tick: int) -> void:
	if look == Net.FACING_GONE or _outside_view(x, y):
		ents.erase(id)
		return
	var facing := Net.look_facing(look)
	var e: Ent = ents.get(id)
	if e == null:
		e = Ent.new()
		e.id = id
		e.x = x
		e.y = y
		e.facing = facing
		e.look = look
		e.cond = Net.look_cond(look)
		ents[id] = e
		return
	e.look = look
	e.cond = Net.look_cond(look)
	if e.x != x or e.y != y:
		if absi(e.x - x) + absi(e.y - y) == 1:
			e.steps.append([s_tick, e.x, e.y, x, y, facing])
			if e.steps.size() > 8:
				e.steps.pop_front()
		else:
			e.steps.clear()          # moved further than one step: place it there
		e.x = x
		e.y = y
	e.facing = facing


# ------------------------------------------------------------- prediction

func _advance(delta: float) -> void:
	if not _have_clock:
		return
	var dt_ticks := delta * Net.TICK_HZ
	_recv_offset = _ease_clock(_recv_offset, _recv_target, dt_ticks)
	_pred_offset = _ease_clock(_pred_offset, _pred_target, dt_ticks)
	_corr = _corr.lerp(Vector2.ZERO, 1.0 - exp(-delta * 16.0))
	if not _have_self:
		return
	# a change of the held direction is stamped with the tick it takes effect on
	if want_dir != _sent_dir and _last_apply - pred_tick < 6:
		var at := maxi(pred_tick + 1, _last_apply + 1)
		_seq += 1
		_inputs.append([_seq, at, want_dir, false])
		_sent_dir = want_dir
		_last_apply = at
		var msg := PackedByteArray()
		msg.resize(8)
		msg.encode_u8(0, Net.C_INPUT)
		msg.encode_u16(1, _seq & 0xFFFF)
		msg.encode_u32(3, at)
		msg.encode_u8(7, want_dir)
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
		_host.flush()
		_repeat_msg = msg
		_repeat_left = INPUT_COPIES
	elif _repeat_left > 0:
		# The same change again, in a packet of its own on the frames that follow.
		# If the first copy is lost, the server would otherwise learn about it only
		# after a resend, too late for the tick it was meant for.
		_repeat_left -= 1
		_peer.send(1, _repeat_msg, ENetPacketPeer.FLAG_UNSEQUENCED)
		_host.flush()
	_simulate_to_now()


func _simulate_to_now() -> void:
	## Brings the predicted character up to the current predicted tick. Called
	## every frame and again before drawing, so the picture never lags a tick
	## behind the clock, whatever order the nodes are processed in.
	if not _have_self:
		return
	var target := int(floor(now_ticks() + _pred_offset))
	if target - pred_tick > 40:
		pred_tick = target - 40      # after a long freeze, do not replay everything
	while pred_tick < target:
		pred_tick += 1
		for inp: Array in _inputs:
			if not inp[3] and int(inp[1]) <= pred_tick:
				pred.dir = inp[2]
				inp[3] = true
		if Mover.step(pred, map, pred_doors, pred_tick):
			steps_predicted += 1
	pred_doors.bumped.clear()


func _reconcile(s_tick: int, pkt: PackedByteArray, o: int) -> void:
	## The server's word on our own character at tick `s_tick`.
	_auth.x = pkt.decode_s16(o)
	_auth.y = pkt.decode_s16(o + 2)
	_auth.cd = pkt[o + 4]
	_auth.facing = Net.look_facing(pkt[o + 5])
	my_cond = Net.look_cond(pkt[o + 5])
	_auth.down = my_cond != Net.COND_OK
	_auth.dir = pkt[o + 6]
	var ack := pkt.decode_u16(o + 7)
	_auth.move_tick = pkt.decode_s32(o + 9)
	_auth.fx = pkt.decode_s16(o + 13)
	_auth.fy = pkt.decode_s16(o + 15)
	_auth_tick = s_tick
	for i in _inputs.size():
		if (int(_inputs[i][0]) & 0xFFFF) == ack:
			_inputs = _inputs.slice(i + 1)
			break
	_have_auth = true
	_rebuild_prediction()


func _rebuild_prediction() -> void:
	## Rebuilds the prediction from the server's last word: start from that
	## state and the doors as the server describes them, and replay the input
	## changes the server has not confirmed yet.
	## (A door the server has shut since is treated as shut for the whole
	## replay. That is safe while doors stay open longer than the replayed
	## stretch: see Doors.HOLD_TICKS.)
	if not _have_auth:
		return
	var st := Mover.State.new()
	st.copy_from(_auth)
	var table := Doors.new()
	table.copy_from(doors)
	if pred_tick < _auth_tick:
		pred_tick = _auth_tick       # our predicted clock was behind the server
	var t := _auth_tick
	var k := 0
	while t < pred_tick:
		t += 1
		while k < _inputs.size() and int(_inputs[k][1]) <= t:
			st.dir = _inputs[k][2]
			k += 1
		Mover.step(st, map, table, t)
	table.bumped.clear()
	pred_doors = table
	for i in _inputs.size():
		_inputs[i][3] = i < k
	if not _have_self:
		_have_self = true
		pred.copy_from(st)
		return
	if st.same_as(pred):
		return
	if st.x != pred.x or st.y != pred.y:
		mispredicts += 1
	var tnow := pred_time()
	var before := Mover.visual_pos(pred, tnow) + _corr
	pred.copy_from(st)
	_corr = before - Mover.visual_pos(pred, tnow)
	if _corr.length() > 2.5:
		_corr = Vector2.ZERO


# ---------------------------------------------------------------- drawing

func sample(id: int) -> Array:
	## Where to draw a character right now:
	## [position in tiles, facing, is moving, tick its current step started on, condition].
	## Empty if the character is not known.
	if id == my_id and predict and _have_self:
		_simulate_to_now()
		var t := pred_time()
		return [Mover.visual_pos(pred, t) + _corr, pred.facing, Mover.is_sliding(pred, t), pred.move_tick, my_cond]
	var e: Ent = ents.get(id)
	if e == null:
		return []
	var rt := render_tick()
	var last := e.steps.size() - 1
	for i in range(last, -1, -1):
		var s: Array = e.steps[i]
		if rt >= float(s[0]):
			var k := (rt - float(s[0])) / float(Net.MOVE_TICKS)
			if k < 1.0:
				return [Vector2(lerpf(s[1], s[3], k), lerpf(s[2], s[4], k)), s[5], true, s[0], e.cond]
			return [Vector2(s[3], s[4]), e.facing if i == last else int(s[5]), false, s[0], e.cond]
	if last >= 0:
		var first: Array = e.steps[0]
		return [Vector2(first[1], first[2]), first[5], false, first[0], e.cond]
	return [Vector2(e.x, e.y), e.facing, false, 0, e.cond]
