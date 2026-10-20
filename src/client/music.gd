extends Node
## (v75, the author's F4: "a low dark drone that rises in fights and when boarders
## are aboard, silent otherwise; and music in the menu") One player for the music,
## kept by main.gd for the whole run. A piece fades in and out rather than cutting.
## The pieces are made in code (Sounds.MUSIC_*) and replaced by files of one's own
## in the «sounds» folder (music_menu.ogg, music_fight.ogg). Client only.

const Sounds := preload("res://src/client/sounds.gd")
const Options := preload("res://src/client/options.gd")

const FADE_SECONDS := 2.5            # a piece comes in and goes out over this long
const QUIET_DB := -40.0              # where a fade starts and ends

static var current: Node              # the one kept by main.gd (null in tests and on a server)

var _player: AudioStreamPlayer
var _want := ""                      # the piece that should play ("" = silence)
var _now := ""                       # the piece in the player


func _ready() -> void:
	Options.ensure_buses()
	_player = AudioStreamPlayer.new()
	_player.bus = Options.MUSIC_BUS
	_player.volume_db = QUIET_DB
	add_child(_player)
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func play(name: String) -> void:
	## Sets the piece to play ("" = silence). The same piece again changes nothing.
	_want = name


func playing() -> String:
	return _now if _player.playing else ""


func _process(delta: float) -> void:
	var step := (0.0 - QUIET_DB) * delta / FADE_SECONDS
	if _now != _want:
		# the old piece fades out first, then the new one starts
		_player.volume_db = maxf(_player.volume_db - step, QUIET_DB)
		if _player.volume_db <= QUIET_DB or not _player.playing:
			_player.stop()
			_now = _want
			if _now != "":
				_player.stream = Sounds.stream(_now)
				if _player.stream != null:
					_player.play()
	elif _now != "" and _player.playing:
		_player.volume_db = minf(_player.volume_db + step, 0.0)
