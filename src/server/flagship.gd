extends RefCounted
## (v57) The goal of the game: the pirates' flagship (the author: "a linear
## point in the game where we go... a boss fight with a big ship... win the
## boss, end of the game"). Server only.
##
## The flagship waits in the sector Sectors.goal names. When our ship
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
##
## (v64, the author's C3 and my V1, V2) It waits in the fourth cluster
## (Sectors.FLAG_DEPTH), at the system Sectors.build puts it in, and wakes as
## soon as our ship comes into that cluster; then it roams the whole cluster
## along its lanes (never into a station's system). While it lives, the
## cluster's exits are shut (its jammer).
##
## (v63, the author's R7: "the flagship roams its sector FTL-style and grows
## stronger the longer you take") It sleeps at the goal until our ship first
## comes into its area (v64: its cluster). Then it wakes and roams: every MOVE_SECONDS it
## moves to a neighbouring sector of its area (along a route), shown on the
## chart; meeting it in a sector (we arrive, or it comes to us, WARN_SECONDS
## after a warning) is the fight. From waking its growth clock runs, even while
## we are far away: every GROW_SECONDS (GROW_HARD on the hard mode) it takes a
## step, up to GROWTH_MAX: 1 its guns charge faster, 2 its shield refills faster
## and its systems take one more hit, 3 it carries boarders (the battleship gets a
## teleporter too), 4 point defence. The chapter's codes take one step off.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Player := preload("res://src/server/player.gd")

const COME_SECONDS := 5.0            # after we arrive in its sector, it comes out this much later
const TELEPORT_FIRST := 20.0         # (the carrier) its first boarders come this long into the fight...
const TELEPORT_SECONDS := 40.0       # ... and then this often
const TELEPORT_PARTY := 2            # boarders it sends at a time
const TROOPS := 8                    # boarders it carries besides its crew
const MAX_ABOARD := 4                # it sends nobody while this many pirates are aboard already
const PHASE2_SECONDS := 25.0         # (v62) in its second phase the carrier teleports this often...
const PHASE2_PARTY := 3              # ... this many at a time...
const PHASE2_TROOPS := 4             # ... and calls up this many more troops
const CAPTURE_SECONDS := 10          # the whole crew down this long with its boarders aboard: the ship is theirs
const MOVE_SECONDS := 90.0           # (v63) it moves on this often
const WARN_SECONDS := 20.0           # (v63) coming into our sector, it is seen this long before it comes out
const GROW_SECONDS := 180.0          # (v63) it takes a step of growth this often once awake...
const GROW_HARD := 120.0             # ... on the hard mode this often
const GROWTH_MAX := 4
const GROWN_TROOPS := 4              # (v63) the boarders it carries from its third step (the carrier: more)
const GROWTH_NAMES: Array[String] = ["", "его орудия заряжаются быстрее", "его системы прочнее, а щит восстанавливается быстрее",
	"он взял на борт абордажников", "он поставил противоракетную защиту"]

var server: GameServer
var forced := 0                      # (admin, tests) the flagship's kind; 0 = the game's own
var troops := 0                      # (the carrier) boarders it still has to send
var capture := 0                     # seconds its boarders have held our bridge, with none of ours there
var _come_at := -1                   # the tick it comes out (-1: not due)
var _sector_key := 0
var _teleport_at := 0
var _every := TELEPORT_SECONDS
var _party := TELEPORT_PARTY
var _rng := RandomNumberGenerator.new()
var awake := false                   # (v63) it has woken and roams
var at := Vector2i.ZERO              # (v63) its sector while it roams
var growth := 0                      # (v63) its steps of growth
var grow_ticks := 0                  # (v63) ticks of growth clock since its last step
var move_ticks := 0


func setup(p_server: GameServer) -> void:
	server = p_server
	forced = 0
	troops = 0
	capture = 0
	_come_at = -1
	_sector_key = 0
	_rng.randomize()
	awake = false
	at = goal()
	growth = 0
	grow_ticks = 0
	move_ticks = 0


func kind() -> int:
	## Which of the two the flagship of this game is: 1 battleship, 2 carrier.
	if forced > 0:
		return forced
	return 1 + ((server.space_seed >> 7) & 1)


func goal() -> Vector2i:
	## Its lair: a system of the flagship's cluster (Sectors.NO_GOAL while we are in another).
	return server.sectors.goal


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
	if growth >= 3:
		troops += GROWN_TROOPS
	if server.story.codes:
		server.gunnery.reveal_all()          # (v63) the chapter's codes show its rooms
		server.chat.say("Коды флагмана сработали: все его отсеки видны на пульте орудий.")
	if server.ship.jump_to != Net.NO_SECTOR:
		server.ship.jump_to = Net.NO_SECTOR
		server.navigation.tell_nav()
		server.chat.say("Прыжок сорван: флагман глушит гипердвигатель.")
	_teleport_at = server.tick + roundi(TELEPORT_FIRST * Net.TICK_HZ)
	_every = TELEPORT_SECONDS
	_party = TELEPORT_PARTY
	capture = 0
	return true


func tick() -> void:
	if server.over != Net.OVER_NONE:
		return
	_roam()
	_watch_arrival()
	var g = server.gunnery
	if g.boss > 0 and g.teleport and g.fighting():
		_teleport_tick()
	if server.tick % Net.TICK_HZ == 0:
		_watch_crew()


func where() -> Vector2i:
	## (v63) Its sector now: the goal while it sleeps.
	return at if awake else goal()


func is_at(c: Vector2i) -> bool:
	return not server.won and c == where()


func in_area(c: Vector2i) -> bool:
	## (v64) Its area is its whole cluster.
	return server.sectors.depth == Sectors.FLAG_DEPTH and server.sectors.goal != Sectors.NO_GOAL and server.sectors.index_of(c) >= 0


func caught() -> bool:
	## It is fighting us now (its clock stands still, it does not move).
	return server.gunnery.boss > 0 and server.gunnery.engaged()


func seconds_to_grow() -> int:
	if not awake or growth >= GROWTH_MAX or server.won:
		return 65535
	return maxi(roundi(_grow_period() - float(grow_ticks) / Net.TICK_HZ), 0)


func _grow_period() -> float:
	return GROW_HARD if server.mode == Net.MODE_HARD else GROW_SECONDS


func _roam() -> void:
	## (v63) Wakes when we come near, then moves about its area and grows.
	if server.won:
		return
	var ours: Vector2i = server.sectors.cell[server.ship.sector]
	if not awake:
		if in_area(ours):
			awake = true
			at = goal()
			grow_ticks = 0
			move_ticks = 0
			server.story.changed()
			server.chat.say("Сенсоры ловят тяжёлую сигнатуру: флагман пиратов проснулся и вышел на охоту. Его сектор виден на карте. Чем дольше мы тянем, тем он сильнее.")
		return
	if caught():
		return
	if growth < GROWTH_MAX:
		grow_ticks += 1
		if grow_ticks >= roundi(_grow_period() * Net.TICK_HZ):
			grow_ticks = 0
			growth += 1
			server.story.changed()
			server.chat.say("Разведка: флагман готовится к бою, %s." % GROWTH_NAMES[growth])
	if at == ours or _come_at >= 0:
		return                               # it has found us: it stays
	move_ticks += 1
	if move_ticks < roundi(MOVE_SECONDS * Net.TICK_HZ):
		return
	move_ticks = 0
	var s: Sectors = server.sectors
	var ways: Array = []
	for n in s.neighbours(s.index_of(at)):
		if s.kind[n] != Sectors.STATION:
			ways.append(s.cell[n])
	if ways.is_empty():
		# a dead end whose only lane leads to a station: it slips past the station (never stops there)
		for n in s.neighbours(s.index_of(at)):
			for m in s.neighbours(n):
				if s.kind[m] != Sectors.STATION and s.cell[m] != at:
					ways.append(s.cell[m])
	if ways.is_empty():
		return
	# it leans towards us when we are in its area
	var pick: Vector2i = ways[_rng.randi_range(0, ways.size() - 1)]
	if in_area(ours) and _rng.randf() < 0.5:
		for c: Vector2i in ways:
			if s.hops_between(c, ours) < s.hops_between(pick, ours):
				pick = c
	at = pick
	server.story.changed()
	if at == ours:
		_come_at = server.tick + roundi(WARN_SECONDS * Net.TICK_HZ)
		server.chat.alarm("Флагман пиратов вошёл в наш сектор! Он выйдет на нас через %d с. Успеем прыгнуть, или будем драться." % int(WARN_SECONDS))


func _watch_arrival() -> void:
	## Arriving in its sector, the ship meets it a few seconds later.
	var key := Sectors.key(server.sectors.cell[server.ship.sector])
	if key != _sector_key:
		_sector_key = key
		var ours: Vector2i = server.sectors.cell[server.ship.sector]
		_come_at = server.tick + roundi(COME_SECONDS * Net.TICK_HZ) if is_at(ours) else -1
		if not is_at(ours) and ours == goal() and awake and not server.won:
			server.chat.say("Флагмана здесь нет: он рыщет по соседним секторам.")
	elif _come_at >= 0 and not is_at(server.sectors.cell[server.ship.sector]):
		_come_at = -1
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
	_teleport_at = server.tick + roundi(_every * Net.TICK_HZ)
	if troops <= 0 or g.down(Net.ESYS_TELEPORT) or not server.enemy_crew.manned(Net.ESYS_TELEPORT):
		return
	var room := g.room_of_system(Net.ESYS_TELEPORT)
	var n := mini(mini(_party, troops), MAX_ABOARD + (_party - TELEPORT_PARTY) - server.pirates.aboard())
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
		var p = server.pirates.spawn_boarder(c % server.map.width, c / server.map.width, _rng.randf() < 0.6)
		p.hold = c                           # they hold the bridge, and fight whoever comes
		troops -= 1
		if free.is_empty():
			break
	g.reveal(room, "Вспышка выдала отсек пиратов")
	server.chat.alarm("Вспышка телепорта на мостике! Флагман высадил абордажников (%d) прямо к пультам. Если они удержат мостик %d с, корабль будет захвачен. Телепорт можно выбить из орудий (в запасе у флагмана ещё %d)." % [
		n, CAPTURE_SECONDS, troops])


func phase_two() -> void:
	## (v62, the author's K21) The carrier's second phase: more troops, sent more often, more at a time.
	_every = PHASE2_SECONDS
	_party = PHASE2_PARTY
	troops += PHASE2_TROOPS
	_teleport_at = mini(_teleport_at, server.tick + roundi(5.0 * Net.TICK_HZ))


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
			if p != null and not p.pirate and not p.ally and not p.corpse and p.cond == Net.COND_OK:
				taken = false
				break
	if not taken:
		if capture > 0:
			server.chat.say("Кто-то из экипажа снова на ногах: захват сорван.")
		capture = 0
		return
	capture += 1
	if capture == 1:
		server.chat.alarm("Весь экипаж лежит, а абордажники флагмана на борту! Если за %d с никто не поднимется, корабль будет захвачен." % CAPTURE_SECONDS)
	elif capture >= CAPTURE_SECONDS:
		server.crew.end_campaign(Net.OVER_CAPTURED)


func holds_jump() -> String:
	## (v57, the author: "this is the end of the adventure, you win or you lose,
	## no other exit") While the flagship fights, no jump can be made.
	if server.gunnery.boss > 0 and server.gunnery.engaged():
		return "Флагман глушит гипердвигатель: уйти прыжком нельзя. Здесь либо победа, либо гибель."
	return ""


func admin_grow() -> void:
	## (admin) It wakes (if it sleeps) and takes a step of growth.
	if not awake:
		awake = true
		at = goal()
	growth = mini(growth + 1, GROWTH_MAX)
	grow_ticks = 0
	server.story.changed()
	server.chat.say("Флагман: шаг роста %d из %d%s." % [growth, GROWTH_MAX, (", " + GROWTH_NAMES[growth]) if growth > 0 else ""])


func save() -> Dictionary:
	return {"awake": awake, "at": [at.x, at.y], "growth": growth, "grow": grow_ticks, "move": move_ticks}


func load_from(d: Dictionary) -> void:
	if d.is_empty():
		return
	awake = bool(d.get("awake", false))
	at = Vector2i(int(d["at"][0]), int(d["at"][1])) if d.has("at") else goal()
	growth = int(d.get("growth", 0))
	grow_ticks = int(d.get("grow", 0))
	move_ticks = int(d.get("move", 0))


func won(captured: bool) -> void:
	## The flagship is wrecked, or taken by our boarders: the game is won. The
	## voyage goes on (the author: "you can roam around after we kill the flagship").
	server.won = true
	server.sectors.locked = false            # (v64) its jammer is silent: the cluster's exits open
	server.to_all(server.navigation.sectors_packet())
	server.chat.say("ПОБЕДА! Флагман пиратов %s. Цель пути достигнута: игра выиграна. Его обломки можно обыскать, а дальше лететь куда угодно." % (
		"взят на абордаж, его экипаж перебит" if captured else "разбит"))
	server.crew.tell_campaign()
	server.to_all(server.crew.summary_packet())   # (v75) the run's story so far, for the victory screen
	server.save_campaign()
