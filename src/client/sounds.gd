extends Node2D
## What the player hears. Every sound is made here, from noise and a few
## tones, when the game starts: dry and short, the way things sound on a
## metal ship, with nothing borrowed from anywhere.
##
## A sound plays at its place in the deck, so it comes from the left or the
## right and fades with distance. One that comes from somewhere our character
## cannot see (behind a wall or a door), or reaches a character standing in
## thin air, is muffled: quieter, and only its low part comes through.
## A vacuum carries nothing; the server only sends what can be heard at all.

const Net := preload("res://src/shared/net.gd")

const RATE := 22050
const VOICES := 16                   # sounds that can play at once
const MUFFLED_BUS := "Muffled"

static var _streams := {}            # sound kind -> Array of AudioStreamWAV (variants), made once
static var _hum_stream: AudioStreamWAV
static var _rng := RandomNumberGenerator.new()
var _players: Array[AudioStreamPlayer2D] = []
var _next := 0
var _hum: AudioStreamPlayer2D


static func prepare() -> void:
	## Makes every sound. It takes a moment, so the game does it while the menu
	## is up rather than when a game starts (a stall then would upset the clock
	## the client keeps with the server).
	if not _streams.is_empty():
		return
	_rng.seed = 7                    # the same sounds every time
	_streams[Net.SOUND_STEP] = [_step(0.9), _step(1.0), _step(1.12)]
	_streams[Net.SOUND_DOOR] = [_door()]
	_streams[Net.SOUND_HISS] = [_hiss()]
	_streams[Net.SOUND_THUD] = [_thud()]
	_streams[Net.SOUND_DROP] = [_drop()]
	_streams[Net.SOUND_LADDER] = [_ladder(1.0), _ladder(1.08)]
	_streams[Net.SOUND_SHOT] = [_shot()]
	_streams[Net.SOUND_BLOW] = [_blow()]
	_hum_stream = _engine_hum()


func _ready() -> void:
	prepare()
	if AudioServer.get_bus_index(MUFFLED_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, MUFFLED_BUS)
		AudioServer.set_bus_send(i, "Master")
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = 700.0
		AudioServer.add_bus_effect(i, low)
	for i in VOICES:
		var p := AudioStreamPlayer2D.new()
		p.attenuation = 1.4
		add_child(p)
		_players.append(p)
	_hum = AudioStreamPlayer2D.new()
	_hum.stream = _hum_stream
	_hum.volume_db = -14.0
	_hum.max_distance = 14.0 * 32.0
	_hum.attenuation = 1.2
	add_child(_hum)


func play(kind: int, at: Vector2, reach_cells: float, muffled: bool, volume_db: float = 0.0) -> void:
	## Plays a sound of that kind at a place of the shown deck (pixels).
	var variants: Array = _streams.get(kind, [])
	if variants.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stop()
	p.stream = variants[_rng.randi_range(0, variants.size() - 1)]
	p.position = at
	p.max_distance = maxf(reach_cells, 1.0) * 32.0 * 1.3
	p.pitch_scale = _rng.randf_range(0.94, 1.06)
	p.bus = MUFFLED_BUS if muffled else "Master"
	p.volume_db = volume_db - (8.0 if muffled else 0.0)
	p.play()


func hum(on: bool, at: Vector2, muffled: bool) -> void:
	## The engine's hum, from where the engine is (on: it runs and we are on its deck, in air).
	if not on:
		if _hum.playing:
			_hum.stop()
		return
	_hum.position = at
	_hum.bus = MUFFLED_BUS if muffled else "Master"
	if not _hum.playing:
		_hum.play()


# ------------------------------------------------------------------ making the sounds

static func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


static func _noise(out: PackedFloat32Array, from: float, to: float, gain: float, decay: float, smooth: float) -> void:
	## Adds noise from `from` to `to` seconds, dying away at `decay` per second,
	## smoothed by a simple low-pass (0 = raw hiss, near 1 = a dull rumble).
	var low := 0.0
	var a := int(from * RATE)
	var b := mini(int(to * RATE), out.size())
	for i in range(a, b):
		var t := float(i - a) / RATE
		low = lerpf(_rng.randf_range(-1.0, 1.0), low, smooth)
		out[i] += low * gain * exp(-decay * t) * (1.0 / (1.0 - smooth * 0.9))


static func _tone(out: PackedFloat32Array, from: float, freq: float, gain: float, decay: float, sweep: float = 0.0) -> void:
	## Adds a ringing tone starting at `from` seconds; `sweep` bends it (Hz per second).
	var a := int(from * RATE)
	var phase := 0.0
	for i in range(a, out.size()):
		var t := float(i - a) / RATE
		var env := exp(-decay * t)
		if env < 0.001:
			break
		phase += TAU * (freq + sweep * t) / RATE
		out[i] += sin(phase) * gain * env


static func _fade(out: PackedFloat32Array, attack: float) -> void:
	var n := mini(int(attack * RATE), out.size())
	for i in n:
		out[i] *= float(i) / n


static func _step(pitch: float) -> AudioStreamWAV:
	# a boot on a metal deck plate: a dull knock and a short ring of the plate
	var out := _buffer(0.16)
	_noise(out, 0.0, 0.16, 0.35, 45.0, 0.85)
	_tone(out, 0.0, 95.0 * pitch, 0.35, 40.0)
	_tone(out, 0.0, 410.0 * pitch, 0.06, 60.0)
	_fade(out, 0.002)
	return _wav(out)


static func _door() -> AudioStreamWAV:
	# a door sliding open: a short motor whine, air on the seals, a stop at the end
	var out := _buffer(0.5)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.05, 0.0, 1.0) * clampf((0.36 - t) / 0.08, 0.0, 1.0)
		out[i] += sin(TAU * (240.0 - 60.0 * t) * t) * 0.12 * env
		out[i] += sin(TAU * (480.0 - 120.0 * t) * t) * 0.04 * env
	_noise(out, 0.0, 0.36, 0.12, 2.0, 0.6)
	_noise(out, 0.33, 0.5, 0.45, 35.0, 0.9)
	_tone(out, 0.33, 70.0, 0.3, 30.0)
	_fade(out, 0.01)
	return _wav(out)


static func _hiss() -> AudioStreamWAV:
	# air rushing out through a hole: hard hiss, swelling in and out
	var out := _buffer(1.2)
	_noise(out, 0.0, 1.2, 0.3, 0.6, 0.05)
	for i in out.size():
		var t := float(i) / RATE
		out[i] *= clampf(t / 0.08, 0.0, 1.0) * clampf((1.2 - t) / 0.3, 0.0, 1.0) * (0.85 + 0.15 * sin(TAU * 7.0 * t))
	return _wav(out)


static func _thud() -> AudioStreamWAV:
	# somebody falling onto the deck
	var out := _buffer(0.45)
	_noise(out, 0.0, 0.45, 0.6, 14.0, 0.92)
	_tone(out, 0.0, 62.0, 0.55, 11.0)
	_noise(out, 0.07, 0.3, 0.25, 25.0, 0.8)
	_fade(out, 0.004)
	return _wav(out)


static func _drop() -> AudioStreamWAV:
	# a thing put down on metal: a click and a smaller one after
	var out := _buffer(0.25)
	_tone(out, 0.0, 1850.0, 0.18, 70.0)
	_tone(out, 0.0, 2730.0, 0.1, 90.0)
	_noise(out, 0.0, 0.05, 0.25, 90.0, 0.4)
	_tone(out, 0.07, 2100.0, 0.08, 80.0)
	return _wav(out)


static func _ladder(pitch: float) -> AudioStreamWAV:
	# a hand and a boot on a steel rung
	var out := _buffer(0.4)
	_tone(out, 0.0, 520.0 * pitch, 0.18, 14.0)
	_tone(out, 0.0, 1243.0 * pitch, 0.08, 20.0)
	_tone(out, 0.0, 2210.0 * pitch, 0.04, 30.0)
	_noise(out, 0.0, 0.04, 0.3, 80.0, 0.5)
	return _wav(out)


static func _shot() -> AudioStreamWAV:
	# a pistol shot indoors: a sharp crack, a short boom, the room answering
	var out := _buffer(0.7)
	_noise(out, 0.0, 0.7, 1.0, 38.0, 0.1)
	_noise(out, 0.0, 0.7, 0.7, 9.0, 0.95)
	_tone(out, 0.0, 55.0, 0.4, 8.0)
	_noise(out, 0.05, 0.7, 0.12, 7.0, 0.5)
	return _wav(out)


static func _blow() -> AudioStreamWAV:
	# a baton landing
	var out := _buffer(0.2)
	_noise(out, 0.0, 0.2, 0.55, 40.0, 0.88)
	_tone(out, 0.0, 120.0, 0.35, 30.0)
	_fade(out, 0.002)
	return _wav(out)


static func _engine_hum() -> AudioStreamWAV:
	# the engine: a low, even hum with a little roughness in it (a whole number
	# of every wave fits the loop, so it joins without a click)
	var out := _buffer(2.0)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = 0.35 * sin(TAU * 50.0 * t) + 0.2 * sin(TAU * 100.0 * t) + 0.08 * sin(TAU * 150.0 * t) \
			+ 0.05 * sin(TAU * 350.0 * t) * (0.6 + 0.4 * sin(TAU * 2.0 * t))
	var low := 0.0
	var noise := PackedFloat32Array()
	noise.resize(out.size())
	for i in out.size():
		low = lerpf(_rng.randf_range(-1.0, 1.0), low, 0.97)
		noise[i] = low
	var join := int(0.05 * RATE)       # the noise fades across the seam
	for i in out.size():
		var k := 1.0
		if i < join:
			k = float(i) / join
		elif i > out.size() - join:
			k = float(out.size() - i) / join
		out[i] += noise[i] * 0.6 * k
	return _wav(out, true)
