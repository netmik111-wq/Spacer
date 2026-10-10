extends SceneTree
## N independent ENet clients in one process. Each walks randomly, sends input
## at 20 Hz and counts what it receives from the server.

var n := 16
var port := 24500
var duration := 20.0
var compress := false

var apis: Array[SceneMultiplayer] = []
var connected := PackedByteArray()
var snap_count := PackedInt32Array()
var last_tick := PackedInt32Array()
var dirs := PackedByteArray()
var missed := 0
var atmos_packets := 0
var snap_bytes := 0
var visible_sum := 0
var created := 0
var acc := 0.0
var seq := 0
var rng := RandomNumberGenerator.new()
var all_at := -1
var measuring := false
var t_start := 0
var done := false
var cpu0 := 0
var t_boot := 0
var failed := 0
var spawn_per_frame := 8
var last_report := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"n": n = int(kv[1])
			"port": port = int(kv[1])
			"duration": duration = float(kv[1])
			"compress": compress = kv[1] == "1"
			"spawn": spawn_per_frame = int(kv[1])
	Engine.max_fps = 60
	rng.seed = 7
	connected.resize(n); snap_count.resize(n); last_tick.resize(n); dirs.resize(n)
	t_boot = Time.get_ticks_msec()

func _cpu_ticks() -> int:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var line := f.get_line()
	var rest := line.substr(line.rfind(")") + 2).split(" ")
	return int(rest[11]) + int(rest[12])

func _spawn(i: int) -> void:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client("127.0.0.1", port)
	if err != OK:
		print("BOT_FAIL create_client ", i, " err=", err)
	if compress:
		p.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	var api := SceneMultiplayer.new()
	api.root_path = ^"/root"
	api.multiplayer_peer = p
	api.connected_to_server.connect(func() -> void: connected[i] = 1)
	api.server_disconnected.connect(func() -> void: connected[i] = 0)
	api.connection_failed.connect(func() -> void: failed += 1)
	api.peer_packet.connect(_on_packet.bind(i))
	apis.append(api)

func _on_packet(_id: int, pkt: PackedByteArray, i: int) -> void:
	var kind := pkt[0]
	if kind == 1:
		var t := pkt.decode_u32(1)
		if measuring:
			var lt := last_tick[i]
			if lt != 0 and t > lt + 1:
				missed += t - lt - 1
			snap_count[i] += 1
			snap_bytes += pkt.size()
			visible_sum += (pkt.size() - 7) / 7
		last_tick[i] = t
	elif kind == 2 and measuring:
		atmos_packets += 1

func _process(delta: float) -> bool:
	var burst := 0
	while created < n and burst < spawn_per_frame:
		_spawn(created)
		created += 1
		burst += 1
	for api in apis:
		api.poll()
	# Each bot sends input at 20 Hz on its own phase (one third of the bots per
	# 60 fps frame), the way independent real clients would, instead of all
	# bots firing in the same millisecond.
	seq += 1
	var phase := seq % 3
	for i in created:
		if i % 3 != phase or connected[i] == 0:
			continue
		if rng.randf() < 0.15:
			dirs[i] = rng.randi_range(0, 4)
		var pkt := PackedByteArray([1, dirs[i], seq & 255, (seq >> 8) & 255])
		apis[i].send_bytes(pkt, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 0)
	var now := Time.get_ticks_msec()
	var live := 0
	for i in created:
		live += connected[i]
	if not done and not measuring and now - last_report > 5000:
		last_report = now
		print("BOT_PROGRESS t=%.0fs created=%d live=%d failed=%d" % [(now - t_boot) / 1000.0, created, live, failed])
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
			for i in n:
				snap_count[i] = 0
				last_tick[i] = 0
	elif measuring and (now - t_start) / 1000.0 >= duration - 1.5:
		var el := (now - t_start) / 1000.0
		measuring = false
		done = true
		var mn := 1 << 30
		var mx := 0
		var total := 0
		for i in n:
			mn = mini(mn, snap_count[i]); mx = maxi(mx, snap_count[i]); total += snap_count[i]
		print("BOTS n=%d seconds=%.1f snapshots/s per bot: min=%.2f avg=%.2f max=%.2f | missed=%d (%.3f%%) | avg entities per snapshot=%.1f avg snapshot bytes=%.0f | atmos packets/s per bot=%.2f | bot process CPU=%.0f%%" % [
			n, el, mn / el, float(total) / n / el, mx / el, missed, missed * 100.0 / maxf(total + missed, 1.0),
			float(visible_sum) / maxf(total, 1.0), float(snap_bytes) / maxf(total, 1.0), atmos_packets / el / n,
			(_cpu_ticks() - cpu0) / 100.0 / el * 100.0])
	if done and live == 0:
		return true
	if done and now - t_start > (duration + 15.0) * 1000.0:
		return true
	return false
