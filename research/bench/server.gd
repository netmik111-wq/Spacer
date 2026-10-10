extends SceneTree
## Authoritative headless server for the load test.
## 20 Hz tick: validate tile movement, run atmosphere at 10 Hz, then send each
## client only what is near it (3x3 chunks of 16x16 tiles) plus a 21x15 window
## of tile pressures at 4 Hz. Uses ENet through Godot's SceneMultiplayer.

const W := 128
const H := 96
const CHUNK := 16
const CW := 8
const CH := 6
const TICK_HZ := 20
const MOVE_COOLDOWN := 4
const VIEW_W := 21
const VIEW_H := 15
const ENT_BYTES := 7

var port := 24500
var expect := 16
var duration := 20.0
var crowded := false
var compress := false
var polls := 1   # network polls per frame; 1 = engine default
var midtick := false  # also poll between the phases of a tick

var atmos
var mp: SceneMultiplayer
var enet: ENetMultiplayerPeer

var slot_of := {}
var ids := PackedInt32Array()
var px := PackedInt32Array()
var py := PackedInt32Array()
var pdir := PackedByteArray()
var pcool := PackedByteArray()
var pinput := PackedByteArray()
var nslots := 0
var chunk_bufs: Array[PackedByteArray] = []
var rng := RandomNumberGenerator.new()

var tick := 0
var measuring := false
var t_start := 0
var t_boot := 0
var cpu0 := 0
var ready_at := -1
var samples := PackedFloat64Array()
var s_move := 0.0
var s_atmos := 0.0
var s_net := 0.0
var inputs_received := 0
var snapshots_sent := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"n": expect = int(kv[1])
			"port": port = int(kv[1])
			"duration": duration = float(kv[1])
			"crowded": crowded = kv[1] == "1"
			"compress": compress = kv[1] == "1"
			"polls": polls = int(kv[1])
			"midtick": midtick = kv[1] == "1"
	Engine.physics_ticks_per_second = TICK_HZ
	Engine.max_fps = 60
	rng.seed = 99
	atmos = load("res://atmos.gd").new(W, H, 1234)
	atmos.breach = 40 * W + 20
	chunk_bufs.resize(CW * CH)
	for i in chunk_bufs.size():
		chunk_bufs[i] = PackedByteArray()
	enet = ENetMultiplayerPeer.new()
	var err := enet.create_server(port, 4095)
	if err != OK:
		print("SERVER_FAIL create_server err=", err)
		quit(1)
		return
	if compress:
		enet.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	mp = get_multiplayer() as SceneMultiplayer
	mp.server_relay = false
	mp.multiplayer_peer = enet
	mp.peer_connected.connect(_on_join)
	mp.peer_disconnected.connect(_on_leave)
	mp.peer_packet.connect(_on_packet)
	if polls > 1:
		multiplayer_poll = false
	t_boot = Time.get_ticks_msec()
	print("SERVER_UP port=%d expect=%d crowded=%s compress=%s polls=%d" % [port, expect, crowded, compress, polls])

func _cpu_ticks() -> int:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var line := f.get_line()
	var rest := line.substr(line.rfind(")") + 2).split(" ")
	return int(rest[11]) + int(rest[12])

func _on_join(id: int) -> void:
	var s := nslots
	nslots += 1
	ids.append(id); pdir.append(0); pcool.append(0); pinput.append(0)
	var x := 0
	var y := 0
	while true:
		if crowded:
			x = rng.randi_range(49, 63); y = rng.randi_range(33, 47)
		else:
			x = rng.randi_range(1, W - 2); y = rng.randi_range(1, H - 2)
		if atmos.walls[y * W + x] == 0:
			break
	px.append(x); py.append(y)
	slot_of[id] = s

func _on_leave(id: int) -> void:
	if slot_of.has(id):
		ids[slot_of[id]] = 0
		slot_of.erase(id)

func _on_packet(id: int, pkt: PackedByteArray) -> void:
	if pkt.size() >= 2 and pkt[0] == 1 and slot_of.has(id):
		pinput[slot_of[id]] = pkt[1]
		inputs_received += 1

func _process(_delta: float) -> bool:
	if polls > 1:
		for i in polls:
			mp.poll()
	return false

func _physics_process(_delta: float) -> bool:
	var t0 := Time.get_ticks_usec()
	tick += 1
	# 1. movement, validated against walls
	var walls: PackedByteArray = atmos.walls
	for s in nslots:
		if ids[s] == 0:
			continue
		var cd := pcool[s]
		if cd > 0:
			pcool[s] = cd - 1
			continue
		var d := pinput[s]
		if d == 0:
			continue
		var nx := px[s]
		var ny := py[s]
		match d:
			1: ny -= 1
			2: ny += 1
			3: nx -= 1
			4: nx += 1
		if crowded and (nx < 49 or nx > 63 or ny < 33 or ny > 47):
			continue
		if walls[ny * W + nx] == 0:
			px[s] = nx; py[s] = ny; pdir[s] = d; pcool[s] = MOVE_COOLDOWN - 1
	var t1 := Time.get_ticks_usec()
	# 2. atmosphere at 10 Hz
	if tick % 2 == 0:
		atmos.step(0.2)
	if midtick:
		mp.poll()
	var t2 := Time.get_ticks_usec()
	# 3. replication: encode each entity once into its chunk, then give every
	#    client the 3x3 chunks around it
	for c in chunk_bufs.size():
		chunk_bufs[c].clear()
	for s in nslots:
		if ids[s] == 0:
			continue
		var c := (py[s] / CHUNK) * CW + px[s] / CHUNK
		var buf := chunk_bufs[c]
		var o := buf.size()
		buf.resize(o + ENT_BYTES)
		buf.encode_u16(o, s)
		buf.encode_s16(o + 2, px[s])
		buf.encode_s16(o + 4, py[s])
		buf.encode_u8(o + 6, pdir[s])
		chunk_bufs[c] = buf
	var send_atmos := tick % 5 == 0
	var pq: PackedByteArray = atmos.pressure_q
	for s in nslots:
		var id := ids[s]
		if id == 0:
			continue
		var cx := px[s] / CHUNK
		var cy := py[s] / CHUNK
		var out := PackedByteArray()
		out.resize(7)
		out.encode_u8(0, 1)
		out.encode_u32(1, tick)
		out.encode_u16(5, s)
		for yy in range(maxi(cy - 1, 0), mini(cy + 2, CH)):
			for xx in range(maxi(cx - 1, 0), mini(cx + 2, CW)):
				out.append_array(chunk_bufs[yy * CW + xx])
		mp.send_bytes(out, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 0)
		snapshots_sent += 1
		if midtick and (s & 63) == 63:
			mp.poll()
		if send_atmos:
			var x0 := clampi(px[s] - VIEW_W / 2, 0, W - VIEW_W)
			var y0 := clampi(py[s] - VIEW_H / 2, 0, H - VIEW_H)
			var ab := PackedByteArray()
			ab.resize(5)
			ab.encode_u8(0, 2)
			ab.encode_s16(1, x0)
			ab.encode_s16(3, y0)
			for r in VIEW_H:
				var st := (y0 + r) * W + x0
				ab.append_array(pq.slice(st, st + VIEW_W))
			mp.send_bytes(ab, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 0)
	var t3 := Time.get_ticks_usec()
	if measuring:
		samples.append((t3 - t0) / 1000.0)
		s_move += (t1 - t0) / 1000.0
		s_atmos += (t2 - t1) / 1000.0
		s_net += (t3 - t2) / 1000.0
	_control()
	return false

func _control() -> void:
	var now := Time.get_ticks_msec()
	if not measuring:
		if ready_at < 0 and slot_of.size() >= expect:
			ready_at = now + 3000
		if ready_at < 0 and now - t_boot > 60000:
			print("SERVER_FAIL only %d of %d clients connected after 60 s" % [slot_of.size(), expect])
			quit(1)
		if ready_at >= 0 and now >= ready_at:
			measuring = true
			t_start = now
			cpu0 = _cpu_ticks()
			inputs_received = 0
			snapshots_sent = 0
			enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
			enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
			enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
			print("MEASURE_START clients=%d" % slot_of.size())
		return
	var el := (now - t_start) / 1000.0
	if el < duration:
		return
	var cpu := (_cpu_ticks() - cpu0) / 100.0
	var sent := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var recv := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
	var pk := enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
	var n := slot_of.size()
	var cnt := samples.size()
	var sum := 0.0
	for v in samples:
		sum += v
	samples.sort()
	print("RESULT clients=%d crowded=%s compress=%s polls=%d seconds=%.1f ticks=%d (%.1f Hz)" % [n, crowded, compress, polls, el, cnt, cnt / el])
	print("  tick ms: avg=%.3f p95=%.3f max=%.3f | parts avg: move=%.3f atmos=%.3f replicate=%.3f" % [
		sum / cnt, samples[int(cnt * 0.95)], samples[cnt - 1], s_move / cnt, s_atmos / cnt, s_net / cnt])
	print("  server process CPU: %.1f%% of one core" % [cpu / el * 100.0])
	print("  net: down to each client %.1f kbit/s, up from each client %.1f kbit/s, server total out %.2f Mbit/s, udp packets out %.0f/s" % [
		sent * 8.0 / el / n / 1000.0, recv * 8.0 / el / n / 1000.0, sent * 8.0 / el / 1e6, pk / el])
	print("  inputs received per client per second: %.1f, snapshots sent per client per second: %.1f" % [inputs_received / el / n, snapshots_sent / el / n])
	quit()
