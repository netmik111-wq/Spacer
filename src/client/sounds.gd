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
##
## (v56) Any sound can be swapped for a file of one's own: put NAME.ogg or
## NAME.wav (NAMES below: step.wav, hull_hit.ogg ...) into a folder "sounds"
## next to the game, and that file plays instead of the one made here.

const Net := preload("res://src/shared/net.gd")
const Options := preload("res://src/client/options.gd")

const RATE := 22050
const VOICES := 16                   # sounds that can play at once
const MUFFLED_BUS := "Muffled"
const TELEPORT_HUM := 5.0            # (v89) seconds: as long as the teleport's warning (Assault.TELEPORT_WARN)

# (v56) the name of each sound, for files that replace it (see above)
const NAMES := {Net.SOUND_STEP: "step", Net.SOUND_DOOR: "door", Net.SOUND_HISS: "hiss", Net.SOUND_THUD: "thud",
	Net.SOUND_DROP: "drop", Net.SOUND_LADDER: "ladder", Net.SOUND_SHOT: "shot", Net.SOUND_BLOW: "blow",
	Net.SOUND_PHASE: "phase", Net.SOUND_LOAD: "load", Net.SOUND_BANG: "bang", Net.SOUND_BEEP: "beep",
	Net.SOUND_SHOTGUN: "shotgun", Net.SOUND_ZAP: "zap",
	Net.SOUND_CRY: "cry", Net.SOUND_CLICK: "click", Net.SOUND_RELOAD: "reload", Net.SOUND_PICKUP: "pickup",
	Net.SOUND_SWING: "swing", Net.SOUND_TELEPORT: "teleport"}   # (v82; v84 the swing; v89 the teleport)
# (v56) sounds of the ship fight (Net.JOLT_*), by name
const GUN_LASER := "gun_laser"       # a laser or blaster of ours firing (heard aboard, near the gun loudest)
const GUN_HEAVY := "gun_heavy"       # a heavy or siege laser
const GUN_ROCKET := "gun_rocket"     # a rocket or EMP leaving its launcher
const GUN_ION := "gun_ion"           # an ion gun
const GUN_BEAM := "gun_beam"         # a beam burning (cutter, tractor, siphon)
const HULL_HIT := "hull_hit"         # a shot landing on our hull: a boom carried through the ship
const HULL_HEAVY := "hull_heavy"     # a heavy one, a rocket or a meteor: a deep boom and the hull groaning
const SHIELD_HIT := "shield_hit"     # our shield taking a shot: an electric crack and hum
const THEIR_HIT := "their_hit"       # one of ours blowing up on the pirate ship
const THEIR_SHIELD := "their_shield" # their shield stopping one of ours
# (v58) the new guns: every named gun is known by its sound
const GUN_AUTOCANNON := "gun_autocannon"   # an autocannon: a quick rattle of heavy thumps
const GUN_RAIL := "gun_rail"               # a railgun: a charging whine and a sharp electric crack
const GUN_HAMMER := "gun_hammer"           # the «Молот»: a huge deep slam
const GUN_PHOENIX := "gun_phoenix"         # the «Феникс»: a roaring fiery blast
const GUN_STORM := "gun_storm"             # the «Буря»: a deep crackling thunder
const GUN_DEVASTATOR := "gun_devastator"   # the «Опустошитель»: a heavy rocket's long roar
const GUN_REAPER := "gun_reaper"           # the «Жнец»: a low droning beam
const GUN_FLAK := "gun_flak"               # point defence firing: a short burst of pops
const GUN_NOVA := "gun_nova"               # the «Сверхновая»: a rising scream and a blinding boom
const GUN_BOMB := "gun_bomb"               # (v62) a bomb launcher: a teleport's warbling hum and a pop
const GUN_SHRAPNEL := "gun_shrapnel"       # (v62) «Шрапнель»: a dry, scattered crackle
const ALERT_YELLOW := "alert_yellow"       # (v68) the alert going up to yellow: two falling chimes
const ALERT_RED := "alert_red"             # (v68) red alert: a rising and falling siren, heard by everyone aboard
const HIT := "hit"                         # (v75, the author's F1) a blow or a shot landing on somebody
const HIT_METAL := "hit_metal"             # (v75) the same on a robot: a clang
const AMB_VENT := "amb_vent"               # (v75, the author's F5) a room's vent breathing
const AMB_PIPE := "amb_pipe"               # (v75) a pipe in the wall knocking
const AMB_CREAK := "amb_creak"             # (v75) the hull settling after a jump: a long low groan
const MUSIC_MENU := "music_menu"           # (v75, the author's F4) the menu's music (a loop; a file of one's own replaces it)
const MUSIC_FIGHT := "music_fight"         # (v75) a low dark drone while there is a fight or boarders (a loop)
const UI_OPEN := "ui_open"                   # (v82) a console's screen coming up
const UI_CLOSE := "ui_close"                 # (v82) and going off
const UI_DENY := "ui_deny"                   # (v82) a console that will not open (no power)
const UI_WORK := "ui_work"                   # (v82, his F1 note "a little sound for everything we do") a job held with E ticking on
const UI_DONE := "ui_done"                   # (v82) and finished
const UI_SLOT := "ui_slot"                   # (v82) another thing taken into the hand
const MORE_NAMES := [HIT, HIT_METAL, AMB_VENT, AMB_PIPE, AMB_CREAK, MUSIC_MENU, MUSIC_FIGHT, UI_OPEN, UI_CLOSE, UI_DENY,
	UI_WORK, UI_DONE, UI_SLOT]
const FIGHT_NAMES := [ALERT_YELLOW, ALERT_RED, GUN_LASER, GUN_HEAVY, GUN_ROCKET, GUN_ION, GUN_BEAM, HULL_HIT, HULL_HEAVY, SHIELD_HIT, THEIR_HIT, THEIR_SHIELD,
	GUN_AUTOCANNON, GUN_RAIL, GUN_HAMMER, GUN_PHOENIX, GUN_STORM, GUN_DEVASTATOR, GUN_REAPER, GUN_FLAK, GUN_NOVA,
	GUN_BOMB, GUN_SHRAPNEL]

static var _streams := {}            # sound kind (or name) -> Array of AudioStream (variants), made once
static var own_files := PackedStringArray()   # (v56) the sounds replaced by files (told in the log)
static var _hum_stream: AudioStream
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
	_streams[Net.SOUND_PHASE] = [_phase()]
	_streams[Net.SOUND_LOAD] = [_load()]
	_streams[Net.SOUND_BANG] = [_bang()]
	_streams[Net.SOUND_BEEP] = [_beep()]
	_streams[Net.SOUND_SHOTGUN] = [_shotgun()]
	_streams[Net.SOUND_ZAP] = [_zap()]
	_streams[Net.SOUND_CRY] = [_cry(1.0), _cry(0.86), _cry(1.15)]   # (v82: a cry was only ever a mark)
	_streams[Net.SOUND_CLICK] = [_click()]           # (v82)
	_streams[Net.SOUND_RELOAD] = [_reload()]
	_streams[Net.SOUND_PICKUP] = [_pickup()]
	_streams[Net.SOUND_SWING] = [_swing(1.0), _swing(0.85)]   # (v84)
	_streams[Net.SOUND_TELEPORT] = [_teleport()]        # (v89)
	_streams[UI_OPEN] = [_ui_blip(1.0)]
	_streams[UI_CLOSE] = [_ui_blip(0.75)]
	_streams[UI_DENY] = [_ui_deny()]
	_streams[UI_WORK] = [_ui_work(1.0), _ui_work(0.9), _ui_work(1.12)]
	_streams[UI_DONE] = [_ui_done()]
	_streams[UI_SLOT] = [_ui_slot()]
	_streams[ALERT_YELLOW] = [_alert_yellow()]
	_streams[ALERT_RED] = [_alert_red()]
	_streams[GUN_LASER] = [_gun_laser(1.0), _gun_laser(1.07)]
	_streams[GUN_HEAVY] = [_gun_heavy()]
	_streams[GUN_ROCKET] = [_gun_rocket()]
	_streams[GUN_ION] = [_gun_ion()]
	_streams[GUN_BEAM] = [_gun_beam()]
	_streams[HULL_HIT] = [_hull_hit(1.0), _hull_hit(0.9)]
	_streams[HULL_HEAVY] = [_hull_heavy()]
	_streams[SHIELD_HIT] = [_shield_hit()]
	_streams[THEIR_HIT] = [_their_hit(1.0), _their_hit(0.88)]
	_streams[THEIR_SHIELD] = [_their_shield()]
	_streams[GUN_AUTOCANNON] = [_gun_autocannon(1.0), _gun_autocannon(1.06)]
	_streams[GUN_RAIL] = [_gun_rail()]
	_streams[GUN_HAMMER] = [_gun_hammer()]
	_streams[GUN_PHOENIX] = [_gun_phoenix()]
	_streams[GUN_STORM] = [_gun_storm()]
	_streams[GUN_DEVASTATOR] = [_gun_devastator()]
	_streams[GUN_REAPER] = [_gun_reaper()]
	_streams[GUN_FLAK] = [_gun_flak()]
	_streams[GUN_NOVA] = [_gun_nova()]
	_streams[GUN_BOMB] = [_gun_bomb()]
	_streams[GUN_SHRAPNEL] = [_gun_shrapnel()]
	_streams[HIT] = [_hit(1.0), _hit(0.85)]
	_streams[HIT_METAL] = [_hit_metal()]
	_streams[AMB_VENT] = [_amb_vent()]
	_streams[AMB_PIPE] = [_amb_pipe(1.0), _amb_pipe(1.3)]
	_streams[AMB_CREAK] = [_amb_creak()]
	_streams[MUSIC_MENU] = [_music_menu()]
	_streams[MUSIC_FIGHT] = [_music_fight()]
	_hum_stream = _engine_hum()
	# (v56) files of one's own in place of these
	for kind in NAMES:
		_own_file(kind, NAMES[kind])
	for name: String in FIGHT_NAMES + MORE_NAMES:
		_own_file(name, name)
	for name: String in [MUSIC_MENU, MUSIC_FIGHT]:
		_loop_it(name)
	var hum = _load_own("hum")
	if hum != null:
		_hum_stream = hum
		own_files.append("hum")
	if not own_files.is_empty():
		print("sounds of one's own: %s" % ", ".join(own_files))


static func _own_file(key, name: String) -> void:
	var stream = _load_own(name)
	if stream != null:
		_streams[key] = [stream]
		own_files.append(name)


static func _loop_it(name: String) -> void:
	## (v75) Music plays round and round, a file of one's own too.
	var st = (_streams[name] as Array)[0]
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(st as AudioStreamWAV).loop_end = (st as AudioStreamWAV).data.size() / 2


static func stream(name: String) -> AudioStream:
	## (v75) One sound made beforehand, for a player of its own (the music).
	var variants: Array = _streams.get(name, [])
	return variants[0] if not variants.is_empty() else null


static func sound_dirs() -> PackedStringArray:
	## Where files of one's own are looked for: next to the game, and (run from the project) in its folder.
	return PackedStringArray([OS.get_executable_path().get_base_dir().path_join("sounds"),
		ProjectSettings.globalize_path("res://").path_join("sounds")])


static func _load_own(name: String) -> AudioStream:
	for dir in sound_dirs():
		var ogg := dir.path_join(name + ".ogg")
		if FileAccess.file_exists(ogg):
			var o := AudioStreamOggVorbis.load_from_file(ogg)
			if o != null:
				return o
		var wav := dir.path_join(name + ".wav")
		if FileAccess.file_exists(wav):
			var w := AudioStreamWAV.load_from_file(wav)
			if w != null:
				return w
	return null


func _ready() -> void:
	prepare()
	Options.ensure_buses()
	if AudioServer.get_bus_index(MUFFLED_BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, MUFFLED_BUS)
		AudioServer.set_bus_send(i, Options.WORLD_BUS)
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
	_hum.bus = Options.HUM_BUS
	add_child(_hum)


func play(kind, at: Vector2, reach_cells: float, muffled: bool, volume_db: float = 0.0) -> void:
	## Plays a sound of that kind (Net.SOUND_*, or a name of the fight's) at a place of the shown deck (pixels).
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
	p.bus = MUFFLED_BUS if muffled else Options.WORLD_BUS
	p.volume_db = volume_db - (8.0 if muffled else 0.0)
	p.play()


func hum(on: bool, at: Vector2, muffled: bool) -> void:
	## The engine's hum, from where the engine is (on: it runs and we are on its deck, in air).
	if not on:
		if _hum.playing:
			_hum.stop()
		return
	_hum.position = at
	_hum.bus = MUFFLED_BUS if muffled else Options.HUM_BUS
	# (through the muffled bus the hum's own volume setting is applied here)
	_hum.volume_db = -14.0 + (linear_to_db(maxf(Options.hum_volume, 0.0001)) if muffled else 0.0)
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
	# (v56: the author found them hurting the ears: softer, duller, no ring)
	var out := _buffer(0.14)
	_noise(out, 0.0, 0.14, 0.16, 55.0, 0.9)
	_tone(out, 0.0, 90.0 * pitch, 0.16, 45.0)
	_fade(out, 0.006)
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


static func _load() -> AudioStreamWAV:
	# (v68) a round pushed into a breech: a slide, then a heavy clack of the lock
	var out := _buffer(0.6)
	_noise(out, 0.0, 0.3, 0.25, 6.0, 0.7)
	_tone(out, 0.32, 140.0, 0.5, 18.0)
	_tone(out, 0.32, 1400.0, 0.2, 60.0)
	_noise(out, 0.32, 0.45, 0.4, 40.0, 0.5)
	_fade(out, 0.01)
	return _wav(out)


static func _bang() -> AudioStreamWAV:
	# (v70) a flashbang or a bomb: a sharp crack and a ringing boom
	var out := _buffer(1.2)
	_noise(out, 0.0, 0.08, 0.9, 30.0, 0.2)
	_noise(out, 0.0, 1.1, 0.6, 5.0, 0.95)
	_tone(out, 0.0, 55.0, 0.6, 4.0)
	_tone(out, 0.05, 3200.0, 0.06, 2.0)
	_fade(out, 0.002)
	return _wav(out)


static func _beep() -> AudioStreamWAV:
	# (v70) a short electronic beep
	var out := _buffer(0.18)
	_tone(out, 0.0, 1650.0, 0.3, 12.0)
	_fade(out, 0.004)
	return _wav(out)


static func _shotgun() -> AudioStreamWAV:
	# (v70) a shotgun: a heavy blast with a long tail
	var out := _buffer(0.7)
	_noise(out, 0.0, 0.7, 0.85, 8.0, 0.6)
	_tone(out, 0.0, 85.0, 0.5, 9.0)
	_fade(out, 0.002)
	return _wav(out)


static func _zap() -> AudioStreamWAV:
	# (v70) a stun baton: a crackling electric snap
	var out := _buffer(0.3)
	_noise(out, 0.0, 0.25, 0.5, 18.0, 0.1)
	_tone(out, 0.0, 2400.0, 0.15, 14.0, -1500.0)
	_tone(out, 0.0, 120.0, 0.2, 20.0)
	_fade(out, 0.002)
	return _wav(out)


static func _alert_yellow() -> AudioStreamWAV:
	# (v68) two falling chimes
	var out := _buffer(1.1)
	_tone(out, 0.0, 880.0, 0.3, 3.5)
	_tone(out, 0.0, 1760.0, 0.08, 5.0)
	_tone(out, 0.45, 660.0, 0.3, 3.5)
	_tone(out, 0.45, 1320.0, 0.08, 5.0)
	_fade(out, 0.005)
	return _wav(out)


static func _alert_red() -> AudioStreamWAV:
	# (v68) a siren: three rises and falls of a harsh tone
	var seconds := 2.4
	var out := _buffer(seconds)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var f := 520.0 + 380.0 * (0.5 - 0.5 * cos(TAU * t / 0.8))
		phase += TAU * f / RATE
		var v := sin(phase) + 0.35 * sin(phase * 2.0) + 0.2 * sin(phase * 3.0)
		out[i] += v * 0.22 * minf(1.0, (seconds - t) * 4.0)
	_fade(out, 0.02)
	return _wav(out)


static func _cry(pitch: float) -> AudioStreamWAV:
	# (v82, his O1 note "a little ugh") a short grunt: a low voice falling, breath round it
	var out := _buffer(0.32)
	_tone(out, 0.0, 150.0 * pitch, 0.3, 7.0, -150.0 * pitch)
	_tone(out, 0.0, 300.0 * pitch, 0.16, 9.0, -300.0 * pitch)
	_tone(out, 0.0, 450.0 * pitch, 0.08, 12.0, -450.0 * pitch)
	_tone(out, 0.0, 720.0 * pitch, 0.05, 16.0, -720.0 * pitch)
	_noise(out, 0.0, 0.3, 0.07, 10.0, 0.85)
	_fade(out, 0.012)
	return _wav(out)


static func _click() -> AudioStreamWAV:
	# (v82) a hammer falling on nothing: one dry tick
	var out := _buffer(0.08)
	_tone(out, 0.0, 3200.0, 0.22, 140.0)
	_noise(out, 0.0, 0.03, 0.3, 160.0, 0.3)
	return _wav(out)


static func _reload() -> AudioStreamWAV:
	# (v82) a magazine out, a new one in and the slide racked
	var out := _buffer(0.5)
	_noise(out, 0.0, 0.06, 0.25, 70.0, 0.5)
	_tone(out, 0.0, 900.0, 0.1, 50.0)
	_noise(out, 0.2, 0.26, 0.35, 90.0, 0.4)
	_tone(out, 0.2, 1500.0, 0.14, 70.0)
	_noise(out, 0.36, 0.44, 0.4, 60.0, 0.3)
	_tone(out, 0.36, 2300.0, 0.12, 60.0)
	return _wav(out)


static func _pickup() -> AudioStreamWAV:
	# (v82) a thing lifted off the floor: a soft scrape and a light knock
	var out := _buffer(0.2)
	_noise(out, 0.0, 0.08, 0.14, 40.0, 0.7)
	_tone(out, 0.03, 1250.0, 0.08, 60.0)
	return _wav(out)


static func _swing(pitch: float) -> AudioStreamWAV:
	# (v84, the author's S1) a blow through empty air: a soft rising and falling whoosh
	var out := _buffer(0.24)
	_noise(out, 0.0, 0.22, 0.22 * pitch, 6.0, 0.15)
	_tone(out, 0.02, 180.0 * pitch, 0.04, 10.0, 120.0)
	_fade(out, 0.03)
	return _wav(out)


static func _teleport() -> AudioStreamWAV:
	# (v89, his note) a pirate teleport charging: a hum rising over the seconds of warning, with a crackle
	var out := _buffer(TELEPORT_HUM)
	var steps := 12
	for k in steps:
		var t := TELEPORT_HUM * k / steps
		_tone(out, t, 140.0 + 60.0 * k, 0.05 + 0.006 * k, 2.5)
	_noise(out, TELEPORT_HUM - 0.5, TELEPORT_HUM, 0.25, 8.0, 0.4)
	_fade(out, 0.05)
	return _wav(out)


static func _ui_blip(pitch: float) -> AudioStreamWAV:
	# (v82) a console's screen: two soft quick tones, up when it opens, down when it closes
	var out := _buffer(0.16)
	_tone(out, 0.0, 880.0 * pitch, 0.07, 30.0)
	_tone(out, 0.05, 1320.0 * pitch * pitch, 0.06, 30.0)
	_fade(out, 0.004)
	return _wav(out)


static func _ui_deny() -> AudioStreamWAV:
	# (v82) a console refusing: a low double buzz
	var out := _buffer(0.3)
	_tone(out, 0.0, 220.0, 0.16, 14.0)
	_tone(out, 0.0, 233.0, 0.12, 14.0)
	_tone(out, 0.14, 196.0, 0.14, 14.0)
	_fade(out, 0.004)
	return _wav(out)


static func _ui_work(pitch: float) -> AudioStreamWAV:
	# (v82) hands at work: a soft tool tick, a little different each time
	var out := _buffer(0.09)
	_noise(out, 0.0, 0.035, 0.16, 120.0, 0.45)
	_tone(out, 0.0, 1650.0 * pitch, 0.07, 90.0)
	return _wav(out)


static func _ui_done() -> AudioStreamWAV:
	# (v82) a job done: a small bright knock and a rising note
	var out := _buffer(0.28)
	_tone(out, 0.0, 1400.0, 0.12, 60.0)
	_tone(out, 0.06, 1980.0, 0.09, 18.0)
	_fade(out, 0.004)
	return _wav(out)


static func _ui_slot() -> AudioStreamWAV:
	# (v82) a thing taken in hand: a short cloth-and-metal flick
	var out := _buffer(0.07)
	_noise(out, 0.0, 0.04, 0.1, 110.0, 0.6)
	_tone(out, 0.0, 2600.0, 0.05, 140.0)
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


# (v56) the ship fight

static func _gun_laser(pitch: float) -> AudioStreamWAV:
	# a laser bolt leaving its mount: a bright falling zap over a thump of the mount
	var out := _buffer(0.55)
	_tone(out, 0.0, 1500.0 * pitch, 0.32, 9.0, -2200.0)
	_tone(out, 0.0, 760.0 * pitch, 0.22, 7.0, -900.0)
	_noise(out, 0.0, 0.12, 0.3, 40.0, 0.3)
	_noise(out, 0.0, 0.5, 0.5, 11.0, 0.93)
	_tone(out, 0.0, 70.0, 0.35, 10.0)
	_fade(out, 0.002)
	return _wav(out)


static func _gun_heavy() -> AudioStreamWAV:
	# a heavy laser: a deep charged blast that rattles the plates
	var out := _buffer(1.1)
	_tone(out, 0.0, 900.0, 0.3, 5.0, -1100.0)
	_tone(out, 0.0, 300.0, 0.3, 4.0, -150.0)
	_noise(out, 0.0, 1.1, 0.75, 5.5, 0.95)
	_tone(out, 0.0, 48.0, 0.5, 4.0)
	_noise(out, 0.03, 0.5, 0.18, 9.0, 0.6)
	_fade(out, 0.003)
	return _wav(out)


static func _gun_rocket() -> AudioStreamWAV:
	# a rocket launched: a clunk of the rack, then a roaring rush fading away
	var out := _buffer(1.3)
	_tone(out, 0.0, 140.0, 0.4, 25.0)
	_noise(out, 0.0, 0.08, 0.5, 50.0, 0.7)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf((t - 0.05) / 0.08, 0.0, 1.0) * exp(-2.6 * maxf(t - 0.12, 0.0))
		out[i] += _rng.randf_range(-1.0, 1.0) * 0.32 * env
	var low := 0.0
	for i in out.size():
		low = lerpf(out[i], low, 0.55)
		out[i] = low * 1.5
	_noise(out, 0.0, 1.0, 0.4, 3.5, 0.96)
	return _wav(out)


static func _gun_ion() -> AudioStreamWAV:
	# an ion gun: a rising whine and a crackling snap
	var out := _buffer(0.7)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.12, 0.0, 1.0) * exp(-7.0 * maxf(t - 0.12, 0.0))
		out[i] += sin(TAU * (500.0 + 2400.0 * t) * t) * 0.18 * env
		if _rng.randf() < 0.04 * env:
			out[i] += _rng.randf_range(-0.8, 0.8)
	_noise(out, 0.12, 0.7, 0.35, 14.0, 0.2)
	_tone(out, 0.12, 90.0, 0.3, 12.0)
	_fade(out, 0.004)
	return _wav(out)


static func _gun_beam() -> AudioStreamWAV:
	# a beam burning for a second: a buzzing hum with a hiss in it
	var out := _buffer(1.0)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.05, 0.0, 1.0) * clampf((1.0 - t) / 0.2, 0.0, 1.0)
		out[i] += (sin(TAU * 220.0 * t) * 0.16 + sin(TAU * 330.0 * t) * 0.08 + signf(sin(TAU * 110.0 * t)) * 0.05) * env
		out[i] += _rng.randf_range(-1.0, 1.0) * 0.05 * env
	return _wav(out)


# (v58) the new guns

static func _gun_autocannon(pitch: float) -> AudioStreamWAV:
	# three quick heavy thumps, each with a metallic clack of the breech
	var out := _buffer(0.75)
	for k in 3:
		var at := k * 0.16
		_tone(out, at, 95.0 * pitch, 0.45, 22.0, -40.0)
		_noise(out, at, at + 0.12, 0.45, 35.0, 0.55)
		_tone(out, at + 0.01, 1900.0 * pitch, 0.08, 60.0)
	_noise(out, 0.0, 0.75, 0.18, 6.0, 0.93)
	_fade(out, 0.002)
	return _wav(out)


static func _gun_rail() -> AudioStreamWAV:
	# a rising charge whine, then a sharp crack and a ringing hiss
	var out := _buffer(1.0)
	for i in out.size():
		var t := float(i) / RATE
		if t < 0.22:
			out[i] += sin(TAU * (900.0 + 9000.0 * t) * t) * 0.12 * (t / 0.22)
	_noise(out, 0.22, 0.3, 0.9, 45.0, 0.05)
	_tone(out, 0.22, 2600.0, 0.2, 9.0, -1800.0)
	_noise(out, 0.24, 1.0, 0.3, 5.0, 0.4)
	_tone(out, 0.22, 60.0, 0.4, 8.0)
	_fade(out, 0.002)
	return _wav(out)


static func _phase() -> AudioStreamWAV:
	# (v59) the phase drive: a falling warble as the ship slips out, a soft thump as it lands
	var out := _buffer(1.1)
	for i in out.size():
		var t := float(i) / RATE
		if t < 0.7:
			var f := 1400.0 - 1500.0 * t + 90.0 * sin(TAU * 11.0 * t)
			out[i] += sin(TAU * f * t) * 0.18 * sin(PI * t / 0.7)
	_noise(out, 0.0, 0.7, 0.12, 4.0, 0.95)
	_tone(out, 0.7, 70.0, 0.4, 7.0)
	_noise(out, 0.7, 0.3, 0.25, 12.0, 0.6)
	_fade(out, 0.004)
	return _wav(out)


static func _gun_hammer() -> AudioStreamWAV:
	# a huge slam that shakes the frame
	var out := _buffer(1.4)
	_tone(out, 0.0, 55.0, 0.8, 3.5, -10.0)
	_tone(out, 0.0, 130.0, 0.45, 9.0)
	_noise(out, 0.0, 0.15, 0.8, 30.0, 0.5)
	_noise(out, 0.0, 1.4, 0.6, 3.0, 0.97)
	_tone(out, 0.02, 1200.0, 0.06, 4.0)
	_fade(out, 0.002)
	return _wav(out)


static func _gun_phoenix() -> AudioStreamWAV:
	# a roaring burst of fire with a bright laser zap on top
	var out := _buffer(1.2)
	_tone(out, 0.0, 1100.0, 0.25, 6.0, -1300.0)
	_noise(out, 0.0, 1.2, 0.8, 3.2, 0.88)
	_noise(out, 0.0, 0.6, 0.4, 7.0, 0.6)
	_tone(out, 0.0, 65.0, 0.45, 5.0)
	_fade(out, 0.004)
	return _wav(out)


static func _gun_storm() -> AudioStreamWAV:
	# a deep crackling thunder: an ion gun's whine an octave lower, and lightning in it
	var out := _buffer(1.3)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.15, 0.0, 1.0) * exp(-3.0 * maxf(t - 0.15, 0.0))
		out[i] += sin(TAU * (200.0 + 900.0 * t) * t) * 0.2 * env
		if _rng.randf() < 0.07 * env:
			out[i] += _rng.randf_range(-1.0, 1.0)
	_noise(out, 0.15, 1.3, 0.5, 3.5, 0.9)
	_tone(out, 0.15, 50.0, 0.4, 5.0)
	_fade(out, 0.004)
	return _wav(out)


static func _gun_bomb() -> AudioStreamWAV:
	# (v62) a teleport sending a bomb off: a warbling rising hum that ends in a soft pop
	var out := _buffer(0.8)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.05, 0.0, 1.0) * exp(-3.0 * t)
		out[i] += sin(TAU * (300.0 + 700.0 * t) * t + 3.0 * sin(TAU * 18.0 * t)) * 0.25 * env
	_noise(out, 0.45, 0.6, 0.35, 30.0, 0.6)
	_tone(out, 0.45, 120.0, 0.3, 18.0)
	_fade(out, 0.004)
	return _wav(out)


static func _gun_shrapnel() -> AudioStreamWAV:
	# (v62) fragments: a heavy cough, then a dry crackle scattered over a moment
	var out := _buffer(0.7)
	_tone(out, 0.0, 70.0, 0.5, 16.0)
	_noise(out, 0.0, 0.06, 0.6, 50.0, 0.5)
	for k in 14:
		var at := 0.05 + _rng.randf() * 0.45
		_noise(out, at, at + 0.02, 0.35, 120.0, 0.2)
	_fade(out, 0.003)
	return _wav(out)


static func _gun_devastator() -> AudioStreamWAV:
	# a heavy rocket: a big clunk and a long, low roar
	var out := _buffer(1.8)
	_tone(out, 0.0, 90.0, 0.55, 14.0)
	_noise(out, 0.0, 0.1, 0.6, 40.0, 0.7)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf((t - 0.06) / 0.1, 0.0, 1.0) * exp(-1.6 * maxf(t - 0.16, 0.0))
		out[i] += _rng.randf_range(-1.0, 1.0) * 0.4 * env
	var low := 0.0
	for i in out.size():
		low = lerpf(out[i], low, 0.7)
		out[i] = low * 1.8
	return _wav(out)


static func _gun_reaper() -> AudioStreamWAV:
	# a crimson beam: a low droning buzz, rougher than the cutting beam
	var out := _buffer(1.0)
	for i in out.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.05, 0.0, 1.0) * clampf((1.0 - t) / 0.2, 0.0, 1.0)
		out[i] += (sin(TAU * 110.0 * t) * 0.2 + signf(sin(TAU * 55.0 * t)) * 0.09 + sin(TAU * 165.0 * t) * 0.07) * env
		out[i] += _rng.randf_range(-1.0, 1.0) * 0.07 * env
	return _wav(out)


static func _gun_flak() -> AudioStreamWAV:
	# point defence: a fast burst of small pops
	var out := _buffer(0.6)
	for k in 6:
		var at := k * 0.07
		_noise(out, at, at + 0.05, 0.5, 70.0, 0.3)
		_tone(out, at, 260.0, 0.18, 50.0)
	_fade(out, 0.002)
	return _wav(out)


static func _gun_nova() -> AudioStreamWAV:
	# a rising scream, then a blinding boom
	var out := _buffer(2.0)
	for i in out.size():
		var t := float(i) / RATE
		if t < 0.5:
			out[i] += sin(TAU * (300.0 + 3000.0 * t) * t) * 0.16 * (t / 0.5)
	_noise(out, 0.5, 2.0, 1.0, 2.6, 0.95)
	_tone(out, 0.5, 45.0, 0.6, 3.0)
	_tone(out, 0.5, 1600.0, 0.15, 6.0, -1200.0)
	_fade(out, 0.003)
	return _wav(out)


static func _hull_hit(pitch: float) -> AudioStreamWAV:
	# a shot bursting on our hull, heard from inside: a sharp crack, a boom
	# through the frame and the plates ringing after
	var out := _buffer(1.6)
	_noise(out, 0.0, 0.2, 0.9, 30.0, 0.2)
	_noise(out, 0.0, 1.6, 1.0, 4.0, 0.96)
	_tone(out, 0.0, 52.0 * pitch, 0.6, 3.5)
	_tone(out, 0.0, 180.0 * pitch, 0.18, 6.0)
	_tone(out, 0.02, 523.0 * pitch, 0.07, 3.0)
	_tone(out, 0.02, 811.0 * pitch, 0.05, 3.5)
	_noise(out, 0.15, 1.2, 0.12, 3.0, 0.5)              # bits falling on the deck
	_fade(out, 0.002)
	return _wav(out)


static func _hull_heavy() -> AudioStreamWAV:
	# a heavy blow: a deep boom, the whole frame groaning after it
	var out := _buffer(2.6)
	_noise(out, 0.0, 0.25, 1.0, 22.0, 0.25)
	_noise(out, 0.0, 2.6, 1.2, 2.2, 0.97)
	_tone(out, 0.0, 38.0, 0.7, 2.0)
	_tone(out, 0.0, 76.0, 0.3, 3.0)
	for i in range(int(0.4 * RATE), out.size()):
		var t := float(i) / RATE - 0.4
		var env := clampf(t / 0.3, 0.0, 1.0) * exp(-1.6 * t)
		out[i] += sin(TAU * (130.0 - 25.0 * t + 6.0 * sin(TAU * 3.0 * t)) * t) * 0.12 * env   # the metal groaning
	_noise(out, 0.2, 2.0, 0.1, 2.0, 0.5)
	_fade(out, 0.002)
	return _wav(out)


static func _shield_hit() -> AudioStreamWAV:
	# our shield taking a shot: an electric crack and a falling hum
	var out := _buffer(1.0)
	_noise(out, 0.0, 0.1, 0.6, 45.0, 0.1)
	_tone(out, 0.0, 420.0, 0.3, 4.5, -180.0)
	_tone(out, 0.0, 630.0, 0.15, 6.0, -260.0)
	_tone(out, 0.0, 60.0, 0.35, 5.0)
	for i in out.size():
		var t := float(i) / RATE
		out[i] *= 0.8 + 0.2 * sin(TAU * 31.0 * t)
	_fade(out, 0.002)
	return _wav(out)


static func _their_hit(pitch: float) -> AudioStreamWAV:
	# one of ours bursting on the pirate ship (as the ship's sensors give it): a punchy boom
	var out := _buffer(1.3)
	_noise(out, 0.0, 0.15, 0.7, 30.0, 0.4)
	_noise(out, 0.0, 1.3, 1.0, 4.5, 0.95)
	_tone(out, 0.0, 60.0 * pitch, 0.5, 4.5)
	_tone(out, 0.0, 120.0 * pitch, 0.2, 8.0)
	_fade(out, 0.002)
	return _wav(out)


static func _their_shield() -> AudioStreamWAV:
	# their shield stopping one of ours: a dull electric thud
	var out := _buffer(0.7)
	_noise(out, 0.0, 0.08, 0.4, 50.0, 0.3)
	_tone(out, 0.0, 300.0, 0.22, 7.0, -150.0)
	_tone(out, 0.0, 75.0, 0.3, 8.0)
	_fade(out, 0.002)
	return _wav(out)


static func _hit(pitch: float) -> AudioStreamWAV:
	# (v75) a blow landing on a body: a short dull smack
	var out := _buffer(0.18)
	_noise(out, 0.0, 0.18, 0.5, 30.0, 0.8)
	_tone(out, 0.0, 95.0 * pitch, 0.4, 28.0, -120.0)
	_noise(out, 0.0, 0.03, 0.25, 90.0, 0.2)
	_fade(out, 0.002)
	return _wav(out)


static func _hit_metal() -> AudioStreamWAV:
	# (v75) a blow on a robot's plating: a clang with a short ring
	var out := _buffer(0.45)
	_tone(out, 0.0, 830.0, 0.22, 9.0)
	_tone(out, 0.0, 1310.0, 0.14, 12.0)
	_tone(out, 0.0, 210.0, 0.25, 20.0)
	_noise(out, 0.0, 0.05, 0.3, 60.0, 0.3)
	_fade(out, 0.001)
	return _wav(out)


static func _amb_vent() -> AudioStreamWAV:
	# (v75) a room's vent breathing: soft air swelling and fading
	var out := _buffer(2.4)
	_noise(out, 0.0, 2.4, 0.12, 0.0, 0.6)
	for i in out.size():
		var t := float(i) / RATE
		out[i] *= sin(PI * t / 2.4)
	return _wav(out)


static func _amb_pipe(pitch: float) -> AudioStreamWAV:
	# (v75) a pipe knocking in the wall, two or three times
	var out := _buffer(0.9)
	for k in 3:
		var at := 0.0 + 0.22 * k + 0.03 * k * k
		_tone(out, at, 420.0 * pitch, 0.18 / (k + 1), 18.0)
		_tone(out, at, 160.0 * pitch, 0.2 / (k + 1), 25.0)
		_noise(out, at, at + 0.04, 0.12 / (k + 1), 80.0, 0.5)
	_fade(out, 0.002)
	return _wav(out)


static func _amb_creak() -> AudioStreamWAV:
	# (v75) the hull settling: a long, low, bending groan
	var out := _buffer(2.2)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (55.0 + 18.0 * sin(TAU * 0.6 * t) + 9.0 * sin(TAU * 3.1 * t)) / RATE
		var env := sin(PI * t / 2.2)
		out[i] += (sin(phase) * 0.25 + sin(phase * 2.01) * 0.1) * env * env
	_noise(out, 0.0, 2.2, 0.08, 0.5, 0.93)
	_fade(out, 0.05)
	return _wav(out)


static func _music_menu() -> AudioStreamWAV:
	# (v75, the author's F4) a slow, dark pad in a minor key: four chords, 16 seconds, round and round
	var seconds := 16.0
	var out := _buffer(seconds)
	var chords := [[55.0, 65.41, 82.41], [43.65, 65.41, 87.31], [49.0, 61.74, 73.42], [41.2, 61.74, 82.41]]
	var n := out.size()
	for c in chords.size():
		var from := int(c * seconds / chords.size() * RATE)
		var to := int((c + 1) * seconds / chords.size() * RATE)
		for f: float in chords[c]:
			for i in range(from, to):
				var t := float(i) / RATE
				var u := float(i - from) / (to - from)
				var env := clampf(u / 0.25, 0.0, 1.0) * clampf((1.0 - u) / 0.25, 0.0, 1.0)
				out[i] += (sin(TAU * f * t) * 0.09 + sin(TAU * f * 2.0 * t) * 0.035 + sin(TAU * f * 1.003 * t) * 0.05) * env
	var low := 0.0
	for i in n:
		low = lerpf(_rng.randf_range(-1.0, 1.0), low, 0.985)
		out[i] += low * 0.25 * (0.6 + 0.4 * sin(TAU * float(i) / n))
	return _wav(out, true)


static func _music_fight() -> AudioStreamWAV:
	# (v75) a low dark drone with a slow heartbeat pulse under it, 8 seconds, round and round
	var seconds := 8.0
	var out := _buffer(seconds)
	for i in out.size():
		var t := float(i) / RATE
		out[i] += sin(TAU * 41.2 * t) * 0.22 + sin(TAU * 61.74 * t) * 0.08 + sin(TAU * 43.65 * t) * 0.1 * (0.5 + 0.5 * sin(TAU * 0.25 * t))
		var beat := fposmod(t, 1.0)
		out[i] += sin(TAU * 52.0 * beat) * 0.35 * exp(-beat * 14.0) + sin(TAU * 48.0 * maxf(beat - 0.22, 0.0)) * 0.25 * exp(-maxf(beat - 0.22, 0.0) * 14.0) * (1.0 if beat > 0.22 else 0.0)
	var low := 0.0
	for i in out.size():
		low = lerpf(_rng.randf_range(-1.0, 1.0), low, 0.97)
		out[i] += low * 0.12
	return _wav(out, true)


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
