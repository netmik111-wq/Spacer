extends SceneTree
## Clients for server2.gd: N raw ENet connections in one process.
## Every bot walks randomly and sends input only when its direction changes.
## Every `verify_every`-th bot also rebuilds the world from the deltas it
## receives and compares it with the checksums the server sends.

const W := 128
const H := 96
const CW := 8
const CH := 6

var n := 16
var port := 24500
var duration := 20.0
var compress := false
var spawn_per_frame := 4
var verify_every := 8
var cport := 0            # port to connect to (a relay), 0 = the server port
var stamp := false
var lat := PackedInt32Array()

var hosts: Array = []
var peers: Array = []
var state := PackedByteArray()     # 0 connecting, 1 connected, 2 gone
var dirs := PackedByteArray()
var ent: Array = []                # verifiers: Dictionary id -> packed (x, y, dir)
var atm: Array = []                # verifiers: PackedByteArray of tile pressures
var vcx := PackedInt32Array()
var vcy := PackedInt32Array()

var created := 0
var seq := 0
var rng := RandomNumberGenerator.new()
var all_at := -1
var measuring := false
var done := false
var t_start := 0
var t_boot := 0
var cpu0 := 0
var last_report := 0

var packets := 0
var bytes := 0
var inputs_sent := 0
var checks_ok := 0
var checks_bad_ent := 0
var checks_bad_atm := 0
var known_sum := 0
var known_cnt := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"n": n = int(kv[1])
			"port": port = int(kv[1])
			"duration": duration = float(kv[1])
			"compress": compress = kv[1] == "1"
			"spawn": spawn_per_frame = int(kv[1])
			"verify": verify_every = int(kv[1])
			"cport": cport = int(kv[1])
			"stamp": stamp = kv[1] == "1"
	Engine.max_fps = 60
	rng.seed = 7
	state.resize(n); dirs.resize(n); vcx.resize(n); vcy.resize(n)
	t_boot = Time.get_ticks_msec()

func _cpu_ticks() -> int:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var line := f.get_line()
	var rest := line.substr(line.rfind(")") + 2).split(" ")
	return int(rest[11]) + int(rest[12])

func _spawn(i: int) -> void:
	var h := ENetConnection.new()
	var err := h.create_host(1, 2)
	if err != OK:
		print("BOT_FAIL create_host ", i, " err=", err)
	if compress:
		h.compress(ENetConnection.COMPRESS_RANGE_CODER)
	hosts.append(h)
	peers.append(h.connect_to_host("127.0.0.1", cport if cport > 0 else port, 2))
	if i % verify_every == 0:
		ent.append({})
		var a := PackedByteArray()
		a.resize(W * H)
		atm.append(a)
	else:
		ent.append(null)
		atm.append(null)
	vcx[i] = -100
	vcy[i] = -100

func _apply(i: int, pkt: PackedByteArray) -> void:
	var table: Dictionary = ent[i]
	var a: PackedByteArray = atm[i]
	var cx := vcx[i]
	var cy := vcy[i]
	var size := pkt.size()
	var pos := 1
	while pos < size:
		var sec := pkt[pos]
		pos += 1
		if sec == 1:
			var cnt := pkt.decode_u16(pos)
			pos += 2
			for r in cnt:
				var id := pkt.decode_u16(pos)
				var x := pkt.decode_s16(pos + 2)
				var y := pkt.decode_s16(pos + 4)
				var d := pkt[pos + 6]
				pos += 7
				if d == 255 or absi((x >> 4) - cx) > 1 or absi((y >> 4) - cy) > 1:
					table.erase(id)
				else:
					table[id] = x | (y << 16) | (d << 32)
		elif sec == 2:
			var c := pkt[pos]
			var cnt2 := pkt.decode_u16(pos + 1)
			pos += 3
			var base := (c / CW) * 16 * W + (c % CW) * 16
			for r in cnt2:
				var t := pkt[pos]
				a[base + (t >> 4) * W + (t & 15)] = pkt[pos + 1]
				pos += 2
		elif sec == 3:
			var c2 := pkt[pos]
			pos += 1
			var base2 := (c2 / CW) * 16 * W + (c2 % CW) * 16
			for r in 16:
				for q in 16:
					a[base2 + r * W + q] = pkt[pos + r * 16 + q]
			pos += 256
		elif sec == 4:
			cx = pkt[pos]
			cy = pkt[pos + 1]
			pos += 2
			vcx[i] = cx
			vcy[i] = cy
			for id2 in table.keys():
				var v: int = table[id2]
				if absi(((v & 0xFFFF) >> 4) - cx) > 1 or absi((((v >> 16) & 0xFFFF) >> 4) - cy) > 1:
					table.erase(id2)
		elif sec == 5:
			var want_e := pkt.decode_u32(pos)
			var want_a := pkt.decode_u32(pos + 4)
			pos += 8
			var es := 0
			for id3 in table:
				var v2: int = table[id3]
				es += id3 * 31 + (v2 & 0xFFFF) * 17 + ((v2 >> 16) & 0xFFFF) * 13 + ((v2 >> 32) & 0xFF) * 7 + 1
			var asum := 0
			for yy in range(maxi(cy - 1, 0), mini(cy + 2, CH)):
				for xx in range(maxi(cx - 1, 0), mini(cx + 2, CW)):
					var b := yy * 16 * W + xx * 16
					for t2 in 256:
						asum += a[b + (t2 >> 4) * W + (t2 & 15)] * (t2 + 1)
			if measuring:
				var ok := true
				if (es & 0xFFFFFFFF) != want_e:
					checks_bad_ent += 1
					ok = false
				if (asum & 0xFFFFFFFF) != want_a:
					checks_bad_atm += 1
					ok = false
				if ok:
					checks_ok += 1
				known_sum += table.size()
				known_cnt += 1
		elif sec == 6:
			pos += 4
		else:
			print("BOT_FAIL bad section ", sec, " at ", pos, " of ", size)
			return

func _process(_delta: float) -> bool:
	var burst := 0
	while created < n and burst < spawn_per_frame:
		_spawn(created)
		created += 1
		burst += 1
	var live := 0
	for i in created:
		var h: ENetConnection = hosts[i]
		if h == null:
			continue
		var ev: Array = h.service(0)
		while ev[0] > 0:
			var kind: int = ev[0]
			if kind == ENetConnection.EVENT_CONNECT:
				state[i] = 1
			elif kind == ENetConnection.EVENT_DISCONNECT:
				state[i] = 2
			elif kind == ENetConnection.EVENT_RECEIVE:
				var pkt: PackedByteArray = (ev[1] as ENetPacketPeer).get_packet()
				if measuring:
					packets += 1
					bytes += pkt.size()
					if stamp and pkt.size() >= 6 and pkt[pkt.size() - 5] == 6:
						lat.append(((int(Time.get_unix_time_from_system() * 1000.0) & 0xFFFFFFFF) - pkt.decode_u32(pkt.size() - 4)) & 0xFFFFFFFF)
				if ent[i] != null and pkt.size() > 0 and pkt[0] == 3:
					_apply(i, pkt)
			ev = h.service(0)
		if state[i] == 1:
			live += 1
	# input: the direction changes now and then; only a change is sent
	seq += 1
	var phase := seq % 3
	for i in created:
		if i % 3 != phase or state[i] != 1:
			continue
		if rng.randf() < 0.15:
			var nd := rng.randi_range(0, 4)
			if nd != dirs[i]:
				dirs[i] = nd
				(peers[i] as ENetPacketPeer).send(0, PackedByteArray([1, nd]), ENetPacketPeer.FLAG_RELIABLE)
				if measuring:
					inputs_sent += 1
	var now := Time.get_ticks_msec()
	if not done and not measuring and now - last_report > 5000:
		last_report = now
		print("BOT_PROGRESS t=%.0fs created=%d live=%d" % [(now - t_boot) / 1000.0, created, live])
	if not measuring and not done:
		if all_at < 0 and live >= n:
			all_at = now + 3500
		if all_at < 0 and now - t_boot > 60000:
			print("BOT_FAIL only %d of %d connected after 60 s" % [live, n])
			return true
		if all_at >= 0 and now >= all_at:
			measuring = true
			t_start = now
			cpu0 = _cpu_ticks()
	elif measuring and (now - t_start) / 1000.0 >= duration - 1.5:
		var el := (now - t_start) / 1000.0
		measuring = false
		done = true
		print("BOTS2 n=%d seconds=%.1f | packets/s per bot=%.1f avg packet=%.0f bytes | inputs sent/s per bot=%.2f | verifier bots=%d checks ok=%d bad entities=%d bad atmosphere=%d | avg entities known=%.1f | bot process CPU=%.0f%%" % [
			n, el, packets / el / n, float(bytes) / maxf(packets, 1.0), inputs_sent / el / n,
			(n + verify_every - 1) / verify_every, checks_ok, checks_bad_ent, checks_bad_atm,
			float(known_sum) / maxf(known_cnt, 1.0), (_cpu_ticks() - cpu0) / 100.0 / el * 100.0])
		if lat.size() > 0:
			lat.sort()
			var m := lat.size()
			print("LATENCY ms from server tick to client: samples=%d p50=%d p90=%d p99=%d p99.9=%d max=%d | share above 150 ms=%.2f%%" % [m, lat[m / 2], lat[int(m * 0.9)], lat[int(m * 0.99)], lat[int(m * 0.999)], lat[m - 1], 100.0 * (m - lat.bsearch(151)) / m])
	if done and (live == 0 or now - t_start > (duration + 15.0) * 1000.0):
		return true
	return false
