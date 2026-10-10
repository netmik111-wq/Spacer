extends SceneTree
## Load-test server, second version. Same world and rules as server.gd, with:
##  - networking on its own thread (raw ENetConnection serviced continuously),
##  - atmosphere computed on a worker thread, published at tick boundaries,
##  - reliable delta replication: clients get only what changed in the 3x3
##    chunks around them, full chunk contents only when a chunk enters view,
##  - clients send input only when it changes.
## Every ~2 s each client also gets checksums of what it should know, so the
## test can prove the deltas reconstruct the true state.

const W := 128
const H := 96
const CW := 8
const CH := 6
const NCH := CW * CH
const TICK_HZ := 20
const MOVE_COOLDOWN := 4
const NET_IDLE_SLEEP_USEC := 1000

var port := 24500
var expect := 16
var duration := 20.0
var crowded := false
var compress := false
var net_thread_on := true
var async_atmos := true
var send_every := 1
var stamp := false         # append a send-time stamp to every packet (latency tests)

var atmos
var host: ENetConnection

# --- network thread state (touched only by whoever runs _net_pump) ---
var net_thread: Thread
var net_running := true
var net_peers: Array = []
var net_slot_of := {}
# --- queues between simulation and network ---
var in_mutex := Mutex.new()
var in_queue: Array = []
var out_mutex := Mutex.new()
var out_queue: Array = []
var stat_mutex := Mutex.new()
var stat_want := false
var stat_serial := 0
var stat_vals := PackedFloat64Array([0, 0, 0, 0])

# --- simulation state (main thread only) ---
var alive := PackedByteArray()
var px := PackedInt32Array()
var py := PackedInt32Array()
var pdir := PackedByteArray()
var pcool := PackedByteArray()
var pinput := PackedByteArray()
var view_cx := PackedInt32Array()
var view_cy := PackedInt32Array()
var nslots := 0
var nalive := 0
var rng := RandomNumberGenerator.new()

var change_bufs: Array = []      # per chunk: entity records changed since last send
var atmos_out: Array = []        # per chunk: (tile, value) pairs changed since last send
var full_bufs: Array = []        # per chunk: every entity in it (built lazily per tick)
var ent_sums := PackedInt64Array()
var full_tick := -1
var atmos_task := -1
var atmos_gen := 0
var atmos_full_cache: Array = []
var atmos_full_gen := PackedInt32Array()
var atmos_sum_cache := PackedInt64Array()
var atmos_sum_gen := PackedInt32Array()

var tick := 0
var send_no := 0
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
var packets_queued := 0
var atmos_steps := 0
var shut := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"n": expect = int(kv[1])
			"port": port = int(kv[1])
			"duration": duration = float(kv[1])
			"crowded": crowded = kv[1] == "1"
			"compress": compress = kv[1] == "1"
			"netthread": net_thread_on = kv[1] == "1"
			"async": async_atmos = kv[1] == "1"
			"sendevery": send_every = int(kv[1])
			"stamp": stamp = kv[1] == "1"
	Engine.physics_ticks_per_second = TICK_HZ
	Engine.max_fps = 60
	rng.seed = 99
	atmos = load("res://atmos2.gd").new(W, H, 1234)
	atmos.breach = 40 * W + 20
	for c in NCH:
		change_bufs.append(PackedByteArray())
		atmos_out.append(PackedByteArray())
		full_bufs.append(PackedByteArray())
		atmos_full_cache.append(PackedByteArray())
	ent_sums.resize(NCH)
	atmos_full_gen.resize(NCH)
	atmos_sum_cache.resize(NCH)
	atmos_sum_gen.resize(NCH)
	for c in NCH:
		atmos_full_gen[c] = -1
		atmos_sum_gen[c] = -1
	host = ENetConnection.new()
	var err := host.create_host_bound("*", port, 4095, 2)
	if err != OK:
		print("SERVER_FAIL create_host_bound err=", err)
		quit(1)
		return
	if compress:
		host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	if net_thread_on:
		net_thread = Thread.new()
		net_thread.start(_net_loop)
	t_boot = Time.get_ticks_msec()
	print("SERVER2_UP port=%d expect=%d crowded=%s compress=%s netthread=%s async_atmos=%s send_every=%d" % [
		port, expect, crowded, compress, net_thread_on, async_atmos, send_every])

# ---------------------------------------------------------------- network

func _net_loop() -> void:
	# ENetConnection.service(timeout) in Godot 4.7.2 spins the CPU while it
	# waits (measured: 2 s of waiting = 2 s of CPU), so poll with timeout 0
	# and sleep briefly whenever there was nothing to do.
	while net_running:
		if not _net_pump():
			OS.delay_usec(NET_IDLE_SLEEP_USEC)

func _net_pump() -> bool:
	out_mutex.lock()
	var out := out_queue
	out_queue = []
	out_mutex.unlock()
	for item in out:
		var p: ENetPacketPeer = net_peers[item[0]]
		if p != null:
			p.send(0, item[1], ENetPacketPeer.FLAG_RELIABLE)
	var batch: Array = []
	var ev: Array = host.service(0)
	while ev[0] > 0:
		var kind: int = ev[0]
		var peer: ENetPacketPeer = ev[1]
		if kind == ENetConnection.EVENT_CONNECT:
			var slot := net_peers.size()
			net_peers.append(peer)
			net_slot_of[peer] = slot
			batch.append([slot, 1, null])
		elif kind == ENetConnection.EVENT_DISCONNECT:
			if net_slot_of.has(peer):
				var slot2: int = net_slot_of[peer]
				net_peers[slot2] = null
				net_slot_of.erase(peer)
				batch.append([slot2, 2, null])
		elif kind == ENetConnection.EVENT_RECEIVE:
			var pkt := peer.get_packet()
			if net_slot_of.has(peer):
				batch.append([net_slot_of[peer], 3, pkt])
		ev = host.service(0)
	if not batch.is_empty():
		in_mutex.lock()
		in_queue.append_array(batch)
		in_mutex.unlock()
	if stat_want:
		stat_mutex.lock()
		stat_vals[0] = host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		stat_vals[1] = host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
		stat_vals[2] = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)
		stat_vals[3] = host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
		stat_want = false
		stat_serial += 1
		stat_mutex.unlock()
	return not batch.is_empty() or not out.is_empty()

func _pop_stats() -> PackedFloat64Array:
	var before := stat_serial
	stat_want = true
	if not net_thread_on:
		_net_pump()
	var waited := 0
	while stat_serial == before and waited < 500:
		OS.delay_msec(2)
		waited += 2
	stat_mutex.lock()
	var r := stat_vals.duplicate()
	stat_mutex.unlock()
	return r

func _process(_delta: float) -> bool:
	if not net_thread_on and not shut:
		_net_pump()
	return false

# ------------------------------------------------------------- simulation

func _cpu_ticks() -> int:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var line := f.get_line()
	var rest := line.substr(line.rfind(")") + 2).split(" ")
	return int(rest[11]) + int(rest[12])

func _record(c: int, s: int, d: int) -> void:
	var buf: PackedByteArray = change_bufs[c]
	var o := buf.size()
	buf.resize(o + 7)
	buf.encode_u16(o, s)
	buf.encode_s16(o + 2, px[s])
	buf.encode_s16(o + 4, py[s])
	buf.encode_u8(o + 6, d)

func _join(s: int) -> void:
	while nslots <= s:
		alive.append(0); px.append(0); py.append(0); pdir.append(0); pcool.append(0); pinput.append(0)
		view_cx.append(-100); view_cy.append(-100)
		nslots += 1
	var x := 0
	var y := 0
	while true:
		if crowded:
			x = rng.randi_range(49, 63); y = rng.randi_range(33, 47)
		else:
			x = rng.randi_range(1, W - 2); y = rng.randi_range(1, H - 2)
		if atmos.walls[y * W + x] == 0:
			break
	px[s] = x; py[s] = y; pdir[s] = 0; alive[s] = 1
	view_cx[s] = -100; view_cy[s] = -100
	nalive += 1
	_record((y >> 4) * CW + (x >> 4), s, 0)

func _leave(s: int) -> void:
	if s < nslots and alive[s] == 1:
		alive[s] = 0
		nalive -= 1
		_record((py[s] >> 4) * CW + (px[s] >> 4), s, 255)

func _ensure_full() -> void:
	if full_tick == tick:
		return
	full_tick = tick
	for c in NCH:
		full_bufs[c] = PackedByteArray()
		ent_sums[c] = 0
	for s in nslots:
		if alive[s] == 0:
			continue
		var x := px[s]
		var y := py[s]
		var d := pdir[s]
		var c := (y >> 4) * CW + (x >> 4)
		var buf: PackedByteArray = full_bufs[c]
		var o := buf.size()
		buf.resize(o + 7)
		buf.encode_u16(o, s)
		buf.encode_s16(o + 2, x)
		buf.encode_s16(o + 4, y)
		buf.encode_u8(o + 6, d)
		ent_sums[c] += s * 31 + x * 17 + y * 13 + d * 7 + 1

func _atmos_full(c: int) -> PackedByteArray:
	if atmos_full_gen[c] != atmos_gen:
		var pq: PackedByteArray = atmos.pressure_q
		var x0 := (c % CW) * 16
		var y0 := (c / CW) * 16
		var b := PackedByteArray()
		for r in 16:
			var st := (y0 + r) * W + x0
			b.append_array(pq.slice(st, st + 16))
		atmos_full_cache[c] = b
		atmos_full_gen[c] = atmos_gen
	return atmos_full_cache[c]

func _atmos_sum(c: int) -> int:
	if atmos_sum_gen[c] != atmos_gen:
		var b := _atmos_full(c)
		var t := 0
		for i in 256:
			t += b[i] * (i + 1)
		atmos_sum_cache[c] = t
		atmos_sum_gen[c] = atmos_gen
	return atmos_sum_cache[c]

func _take_atmos(deltas: Array) -> void:
	atmos_gen += 1
	atmos_steps += 1
	for c in NCH:
		var d: PackedByteArray = deltas[c]
		if d.size() > 0:
			# typed alias shares the stored array; a cast would append to a copy
			var ao: PackedByteArray = atmos_out[c]
			ao.append_array(d)
			atmos_out[c] = ao

func _physics_process(_delta: float) -> bool:
	var t0 := Time.get_ticks_usec()
	tick += 1
	# 0. what the network thread collected since last tick
	in_mutex.lock()
	var events := in_queue
	in_queue = []
	in_mutex.unlock()
	for e in events:
		var slot: int = e[0]
		match e[1]:
			1: _join(slot)
			2: _leave(slot)
			3:
				var pkt: PackedByteArray = e[2]
				if pkt.size() >= 2 and pkt[0] == 1 and slot < nslots:
					pinput[slot] = pkt[1]
					inputs_received += 1
	# 1. movement
	var walls: PackedByteArray = atmos.walls
	for s in nslots:
		if alive[s] == 0:
			continue
		var cd := pcool[s]
		if cd > 0:
			pcool[s] = cd - 1
			continue
		var d := pinput[s]
		if d == 0:
			continue
		var ox := px[s]
		var oy := py[s]
		var nx := ox
		var ny := oy
		match d:
			1: ny -= 1
			2: ny += 1
			3: nx -= 1
			4: nx += 1
		if crowded and (nx < 49 or nx > 63 or ny < 33 or ny > 47):
			continue
		if walls[ny * W + nx] == 0:
			px[s] = nx; py[s] = ny; pdir[s] = d; pcool[s] = MOVE_COOLDOWN - 1
			var oc := (oy >> 4) * CW + (ox >> 4)
			var nc := (ny >> 4) * CW + (nx >> 4)
			_record(nc, s, d)
			if oc != nc:
				_record(oc, s, d)
	var t1 := Time.get_ticks_usec()
	# 2. atmosphere at 10 Hz
	if async_atmos:
		if atmos_task >= 0 and WorkerThreadPool.is_task_completed(atmos_task):
			WorkerThreadPool.wait_for_task_completion(atmos_task)
			atmos_task = -1
			_take_atmos(atmos.publish())
		if tick % 2 == 0 and atmos_task < 0:
			atmos_task = WorkerThreadPool.add_task(atmos.compute_back.bind(0.2))
	elif tick % 2 == 0:
		atmos.compute_back(0.2)
		_take_atmos(atmos.publish())
	var t2 := Time.get_ticks_usec()
	# 3. replication
	if tick % send_every == 0:
		_send_all()
	var t3 := Time.get_ticks_usec()
	if measuring:
		samples.append((t3 - t0) / 1000.0)
		s_move += (t1 - t0) / 1000.0
		s_atmos += (t2 - t1) / 1000.0
		s_net += (t3 - t2) / 1000.0
	_control()
	return false

func _send_all() -> void:
	send_no += 1
	var check_period := maxi(40 / send_every, 1)
	var stamp_ms := int(Time.get_unix_time_from_system() * 1000.0) & 0xFFFFFFFF
	var batch: Array = []
	for s in nslots:
		if alive[s] == 0:
			continue
		var cx := px[s] >> 4
		var cy := py[s] >> 4
		var vx := view_cx[s]
		var vy := view_cy[s]
		var moved_view := cx != vx or cy != vy
		var out := PackedByteArray([3])
		if moved_view:
			out.append(4); out.append(cx); out.append(cy)
			_ensure_full()
			view_cx[s] = cx
			view_cy[s] = cy
		var do_check := (send_no + s) % check_period == 0
		var esum := 0
		var asum := 0
		if do_check:
			_ensure_full()
		for yy in range(maxi(cy - 1, 0), mini(cy + 2, CH)):
			for xx in range(maxi(cx - 1, 0), mini(cx + 2, CW)):
				var c := yy * CW + xx
				if moved_view and (absi(xx - vx) > 1 or absi(yy - vy) > 1):
					var fb: PackedByteArray = full_bufs[c]
					if fb.size() > 0:
						var o := out.size()
						out.resize(o + 3)
						out.encode_u8(o, 1)
						out.encode_u16(o + 1, fb.size() / 7)
						out.append_array(fb)
					out.append(3); out.append(c)
					out.append_array(_atmos_full(c))
				else:
					var cb: PackedByteArray = change_bufs[c]
					if cb.size() > 0:
						var o2 := out.size()
						out.resize(o2 + 3)
						out.encode_u8(o2, 1)
						out.encode_u16(o2 + 1, cb.size() / 7)
						out.append_array(cb)
					var ad: PackedByteArray = atmos_out[c]
					if ad.size() > 0:
						var o3 := out.size()
						out.resize(o3 + 4)
						out.encode_u8(o3, 2)
						out.encode_u8(o3 + 1, c)
						out.encode_u16(o3 + 2, ad.size() / 2)
						out.append_array(ad)
				if do_check:
					esum += ent_sums[c]
					asum += _atmos_sum(c)
		if do_check:
			var o4 := out.size()
			out.resize(o4 + 9)
			out.encode_u8(o4, 5)
			out.encode_u32(o4 + 1, esum & 0xFFFFFFFF)
			out.encode_u32(o4 + 5, asum & 0xFFFFFFFF)
		if out.size() > 1:
			if stamp:
				var o5 := out.size()
				out.resize(o5 + 5)
				out.encode_u8(o5, 6)
				out.encode_u32(o5 + 1, stamp_ms)
			batch.append([s, out])
	for c in NCH:
		if (change_bufs[c] as PackedByteArray).size() > 0:
			change_bufs[c] = PackedByteArray()
		if (atmos_out[c] as PackedByteArray).size() > 0:
			atmos_out[c] = PackedByteArray()
	if not batch.is_empty():
		packets_queued += batch.size()
		out_mutex.lock()
		out_queue.append_array(batch)
		out_mutex.unlock()

func _shutdown() -> void:
	shut = true
	if atmos_task >= 0:
		WorkerThreadPool.wait_for_task_completion(atmos_task)
		atmos_task = -1
	if net_thread_on and net_thread != null:
		net_running = false
		net_thread.wait_to_finish()
	host.destroy()

func _control() -> void:
	var now := Time.get_ticks_msec()
	if not measuring:
		if ready_at < 0 and nalive >= expect:
			ready_at = now + 3000
		if ready_at < 0 and now - t_boot > 60000:
			print("SERVER_FAIL only %d of %d clients connected after 60 s" % [nalive, expect])
			_shutdown()
			quit(1)
			return
		if ready_at >= 0 and now >= ready_at:
			measuring = true
			t_start = now
			cpu0 = _cpu_ticks()
			inputs_received = 0
			packets_queued = 0
			atmos_steps = 0
			_pop_stats()
			print("MEASURE_START clients=%d" % nalive)
		return
	var el := (now - t_start) / 1000.0
	if el < duration:
		return
	var cpu := (_cpu_ticks() - cpu0) / 100.0
	var st := _pop_stats()
	var n := nalive
	var cnt := samples.size()
	var sum := 0.0
	for v in samples:
		sum += v
	samples.sort()
	print("RESULT2 clients=%d crowded=%s compress=%s netthread=%s async_atmos=%s send_every=%d seconds=%.1f ticks=%d (%.1f Hz) atmos_steps/s=%.1f" % [
		n, crowded, compress, net_thread_on, async_atmos, send_every, el, cnt, cnt / el, atmos_steps / el])
	print("  tick ms: avg=%.3f p95=%.3f max=%.3f | parts avg: move=%.3f atmos=%.3f replicate=%.3f" % [
		sum / cnt, samples[int(cnt * 0.95)], samples[cnt - 1], s_move / cnt, s_atmos / cnt, s_net / cnt])
	print("  server process CPU (all threads): %.1f%% of one core" % [cpu / el * 100.0])
	print("  net: down to each client %.1f kbit/s, up from each client %.1f kbit/s, server total out %.2f Mbit/s, udp out %.0f/s, udp in %.0f/s" % [
		st[0] * 8.0 / el / n / 1000.0, st[2] * 8.0 / el / n / 1000.0, st[0] * 8.0 / el / 1e6, st[1] / el, st[3] / el])
	print("  inputs received per client per second: %.2f, update packets per client per second: %.1f" % [inputs_received / el / n, packets_queued / el / n])
	_shutdown()
	quit()
