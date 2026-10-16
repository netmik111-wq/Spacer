extends RefCounted
## (v57) The goal of the game: the pirates' flagship (the author: "a linear
## point in the game where we go... a boss fight with a big ship... win the
## boss, end of the game"). Server only.
##
## The flagship waits in the sector Sectors.goal_of names. When our ship
## arrives there it comes out a few seconds later and fights to the end: it
## never runs and never offers a ransom (Gunnery, with `boss` set). Jump away
## and it stays behind; come back and it is there again, mended. Each game
## has one of the author's two kinds, by lot from the game's seed:
##   1 the battleship: a row of ordinary guns that aim well, at our shield
##     generator first, then the engine, then the guns (Gunnery._boss_target);
##   2 the carrier: neural emitters that stun everybody in the room they hit
##     (Gunnery._stun_room), and a teleporter (Net.ESYS_TELEPORT, a room of its
##     own) that puts its boarders straight onto our bridge every so often.
##     Its boarders hold the bridge (Player.hold) and fight whoever comes. If
##     every one of our crew is down while they are aboard, for CAPTURE_SECONDS,
##     the ship is theirs and the game is lost (the author's word).
## There is no way out of this fight (the author: "you win or you lose"): no
## jump while it fights, and the battleship goes for the engine even when a
## bridge console is broken. Wrecking the flagship, or killing its whole crew
## by boarding it, wins the game (GameServer.won); the voyage goes on after.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Player := preload("res://src/server/player.gd")

const COME_SECONDS := 5.0            # after we arrive in its sector, it comes out this much later
const TELEPORT_FIRST := 20.0         # (the carrier) its first boarders come this long into the fight...
const TELEPORT_SECONDS := 40.0       # ... and then this often
const TELEPORT_PARTY := 2            # boarders it sends at a time
const TROOPS := 8                    # boarders it carries besides its crew
const MAX_ABOARD := 4                # it sends nobody while this many pirates are aboard already
const CAPTURE_SECONDS := 10          # the whole crew down this long with its boarders aboard: the ship is theirs

var server: GameServer
var forced := 0                      # (admin, tests) the flagship's kind; 0 = the game's own
var troops := 0                      # (the carrier) boarders it still has to send
var capture := 0                     # seconds its boarders have held our bridge, with none of ours there
var _come_at := -1                   # the tick it comes out (-1: not due)
var _sector_key := 0
var _teleport_at := 0
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	forced = 0
	troops = 0
	capture = 0
	_come_at = -1
	_sector_key = 0
	_rng.randomize()


func kind() -> int:
	## Which of the two the flagship of this game is: 1 battleship, 2 carrier.
	if forced > 0:
		return forced
	return 1 + ((server.space_seed >> 7) & 1)


func goal() -> Vector2i:
	return Sectors.goal_of(server.space_seed)


func call_in(which: int = 0) -> bool:
	## The flagship comes out here and now (the director's event for the host's
	## tests; `which` 0 = the game's own kind). False if no ship can come alongside now.
	## Any jump being charged is cut off: there is no leaving it.
	var d = server.derelict
	if not d.pirates_can_come():
		return false
	var design: Dictionary = server.shipyard.flagship(which if which > 0 else kind(), d._pirate_spots())
	if design.is_empty():
		return false
	if not d.pirates_come(0, true, design):
		return false
	troops = TROOPS if int(design["boss"]) == 2 else 0
	if server.ship.jump_to != Net.NO_SECTOR:
		server.ship.jump_to = Net.NO_SECTOR
		server.navigation.tell_nav()
		server.chat.say("Прыжок сорван: флагман глушит гипердвигатель.")
	_teleport_at = server.tick + roundi(TELEPORT_FIRST * Net.TICK_HZ)
	capture = 0
	return true


func tick() -> void:
	if server.over != Net.OVER_NONE:
		return
	_watch_arrival()
	var g = server.gunnery
	if g.boss == 2 and g.fighting():
		_teleport_tick()
	if server.tick % Net.TICK_HZ == 0:
		_watch_crew()


func _watch_arrival() -> void:
	## Arriving in its sector, the ship meets it a few seconds later.
	var key := Sectors.key(server.sectors.cell[server.ship.sector])
	if key != _sector_key:
		_sector_key = key
		_come_at = server.tick + roundi(COME_SECONDS * Net.TICK_HZ) if server.sectors.kind[server.ship.sector] == Sectors.FLAGSHIP else -1
	if _come_at >= 0 and server.won:
		_come_at = -1                        # beaten once, it is not there any more
	if _come_at >= 0 and server.tick >= _come_at and not server.derelict.here:
		if call_in():
			_come_at = -1
		else:
			_come_at = server.tick + Net.TICK_HZ   # (somebody is out in space: it waits for them to come in)


func bridge_cells() -> PackedInt32Array:
	## The floor of our bridge: the room one stands in to fly the ship.
	var map = server.map
	var spots: Array = server.stations.spots.get(Net.POST_HELM, [])
	for s: Array in spots:
		var room: int = map.room_of[int(s[0])]
		if room >= 0:
			return map.rooms[room]
	return PackedInt32Array()


func _teleport_tick() -> void:
	## The carrier puts boarders onto our bridge every TELEPORT_SECONDS, while its
	## teleporter works and somebody of its crew is at it.
	var g = server.gunnery
	if server.tick < _teleport_at:
		return
	_teleport_at = server.tick + roundi(TELEPORT_SECONDS * Net.TICK_HZ)
	if troops <= 0 or g.down(Net.ESYS_TELEPORT) or not server.enemy_crew.manned(Net.ESYS_TELEPORT):
		return
	var room := g.room_of_system(Net.ESYS_TELEPORT)
	var n := mini(mini(TELEPORT_PARTY, troops), MAX_ABOARD - server.pirates.aboard())
	if n <= 0:
		return
	var floor := bridge_cells()
	var free: Array = []
	for c: int in floor:
		if server.map.door_of[c] < 0 and not _someone_at(c):
			free.append(c)
	if free.is_empty():
		return
	for i in n:
		var c: int = free[_rng.randi_range(0, free.size() - 1)]
		free.erase(c)
		var p = server.pirates.spawn(c % server.map.width, c / server.map.width, _rng.randf() < 0.6)
		p.hold = c                           # they hold the bridge, and fight whoever comes
		troops -= 1
		if free.is_empty():
			break
	g.reveal(room, "Вспышка выдала отсек пиратов")
	server.chat.say("Вспышка телепорта на мостике! Флагман высадил абордажников (%d) прямо к пультам. Если они удержат мостик %d с, корабль будет захвачен. Телепорт можно выбить из орудий (в запасе у флагмана ещё %d)." % [
		n, CAPTURE_SECONDS, troops])


func _someone_at(cell: int) -> bool:
	var w: int = server.map.width
	for p: Player in server.players:
		if p != null and not p.corpse and p.st.y * w + p.st.x == cell:
			return true
	return false


func _watch_crew() -> void:
	## Once a second, in the flagship's fight: is every one of our crew down
	## (nobody on their feet to resist) while its boarders are aboard? Then, after
	## CAPTURE_SECONDS, the ship is theirs (the author: "all crew are down and
	## nobody can resist").
	var taken := false
	if server.gunnery.boss > 0 and server.pirates.aboard() > 0:
		taken = true
		for p: Player in server.players:
			if p != null and not p.pirate and not p.corpse and p.cond == Net.COND_OK:
				taken = false
				break
	if not taken:
		if capture > 0:
			server.chat.say("Кто-то из экипажа снова на ногах: захват сорван.")
		capture = 0
		return
	capture += 1
	if capture == 1:
		server.chat.say("Весь экипаж лежит, а абордажники флагмана на борту! Если за %d с никто не поднимется, корабль будет захвачен." % CAPTURE_SECONDS)
	elif capture >= CAPTURE_SECONDS:
		server.crew.end_campaign(Net.OVER_CAPTURED)


func holds_jump() -> String:
	## (v57, the author: "this is the end of the adventure, you win or you lose,
	## no other exit") While the flagship fights, no jump can be made.
	if server.gunnery.boss > 0 and server.gunnery.fighting():
		return "Флагман глушит гипердвигатель: уйти прыжком нельзя. Здесь либо победа, либо гибель."
	return ""


func won(captured: bool) -> void:
	## The flagship is wrecked, or taken by our boarders: the game is won. The
	## voyage goes on (the author: "you can roam around after we kill the flagship").
	server.won = true
	server.chat.say("ПОБЕДА! Флагман пиратов %s. Цель пути достигнута: игра выиграна. Его обломки можно обыскать, а дальше лететь куда угодно." % (
		"взят на абордаж, его экипаж перебит" if captured else "разбит"))
	server.crew.tell_campaign()
	server.save_campaign()
