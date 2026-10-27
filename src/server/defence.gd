extends RefCounted
## (v79, the author's B1 "B") Our bots when armed boarders are aboard. Server only.
##
## Before v79 a bot went on with its work whatever came at it, so one boarder
## could walk the ship and kill the bots one by one. Now a bot that sees an armed
## pirate (or a pirate's robot) close, or is hurt by one, drops its work and runs:
## to where our people are, else as far from the pirates as it can get on our
## ship, and lies down there while they are still about (shots fly over one lying
## low, as for players). CALM_SECONDS after the last pirate it knows of is gone
## (dead, a prisoner, off our ship, or unseen for LOST_SECONDS) it gets up and goes
## back to its order. A bot with the guard's job does not run while there
## is a pistol or a shotgun for it: it fetches one from the supply locker (with
## ammunition), then goes after the pirates by the pirates' own mind
## (Pirates.think, with the sides turned round, as our security robots do) until
## none is left about; it keeps the gun. The author's "people over bots" (v70)
## still holds for everyone else: the other bots never fight, (v89, his note "or only some
## of our crew fights back") unless the captain tells them to (Player.defends).
## Part of the server: GameServer keeps one of these and Movement asks it first
## each tick of a bot's mind.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")

const LOOK_EVERY := 4                # ticks between a bot's looks round for pirates
const NEAR := 4.0                    # cells: a pirate this close with nothing between is noticed whichever way the bot looks
const CALM_SECONDS := 8.0            # this long after the last pirate it knew of is gone, a bot goes back to work
const LOST_SECONDS := 45.0           # a pirate not seen again for this long counts as gone
const SAFE_FROM := 10.0              # cells: where a running bot makes for is at least this far from every pirate...
const CREW_NEAR := 2.0               # ... and, if it can, this close to one of our people
const CREW_SAFE := 6.0               # (one of ours at least this far from the pirates)
const PLAN_TICKS := 10               # how often a running bot looks again at where to go
const AMMO_TAKEN := 2                # magazines (or boxes of shells) a guard takes with its gun

var server: GameServer
var on := true                       # tests: false = bots take no notice of pirates (as before v79)
var _known := {}                     # bot slot -> {pirate slot: [last cell seen, tick]}
var _since := {}                     # bot slot -> the tick it first took notice (for the log)


func setup(p_server: GameServer) -> void:
	server = p_server
	_known.clear()
	_since.clear()


func armed(q: Player) -> bool:
	## A pirate a bot runs from: one of their robots, or one carrying any weapon.
	if q == null or not q.pirate or q.prisoner or q.taken or q.corpse or q.cond != Net.COND_OK:
		return false
	if q.robot:
		return true
	for v in q.slots:
		if Items.is_weapon(v):
			return true
	return false


func hurt_by(q: Player, by: Player) -> void:
	## Combat: a bot was hurt. If a pirate did it, the bot knows where it is.
	if not on or by == null or not q.bot or not armed(by):
		return
	_note(q, by)


func busy(p: Player) -> bool:
	## True while this bot takes notice of pirates (running, hiding or fighting): its order waits.
	return _known.has(p.slot)


func think(p: Player) -> bool:
	## One tick of a bot's mind about pirates. True: it ran or fought this tick, and
	## its order waits; false: nothing about, it goes on with its order.
	if not on or p.cond != Net.COND_OK:
		_forget(p)
		return false
	if p.order == Net.POST_FOLLOW or server.outside.out_now(p) or server.medbay.bed_of(p) >= 0:
		_forget(p)                           # following one of ours, out on the hull, or lying in an autodoc
		return false
	if (server.tick + p.slot) % LOOK_EVERY == 0:
		_look(p)
	var known: Dictionary = _known.get(p.slot, {})
	var calm := roundi(CALM_SECONDS * Net.TICK_HZ)
	var lost := roundi(LOST_SECONDS * Net.TICK_HZ)
	for k: int in known.keys():
		var q: Player = server.players[k] if k < server.players.size() else null
		# remembered while that pirate is about on our ship (where it was last seen); gone, or
		# not seen for a long while, it is forgotten CALM_SECONDS later
		var about: bool = armed(q) and server.map.on_ship(q.st.y * server.map.width + q.st.x) \
			and server.tick - int(known[k][1]) <= lost
		if about:
			known[k][2] = server.tick
		elif server.tick - int(known[k][2]) > calm:
			known.erase(k)
	if known.is_empty():
		if _known.has(p.slot):
			_forget(p)
			server.chat.bot_log(p, "пираты ушли: возвращаюсь к работе.")
		return false
	if not _since.has(p.slot):
		_since[p.slot] = server.tick
		server.stations._took(p, -1)          # the repair it had is free for another bot
		p.using = false
	if (p.job == Net.JOB_GUARD or p.defends) and _guard(p, known):
		return true
	_run(p, known)
	return true


func _note(p: Player, q: Player) -> void:
	var known: Dictionary = _known.get(p.slot, {})
	known[q.slot] = [Vector2i(q.st.x, q.st.y), server.tick, server.tick]   # where, when seen, when last thought about
	_known[p.slot] = known


func _look(p: Player) -> void:
	## Pirates it sees (by the crew's rules of sight, Pirates._sees), or that are close with nothing between.
	var map := server.map
	var here := Vector2(p.st.x, p.st.y)
	for q: Player in server.players:
		if not armed(q) or map.deck_of(q.st.y) != map.deck_of(p.st.y):
			continue
		var at := Vector2(q.st.x, q.st.y)
		var d := here.distance_to(at)
		if d > Sight.SIGHT_REACH:
			continue
		if server.pirates._sees(p, q) or d <= NEAR and Sight.clear_cached(map, server.doors, Vector2i(p.st.x, p.st.y), Vector2i(q.st.x, q.st.y), server.replication.lines):
			_note(p, q)


func _forget(p: Player) -> void:
	if not _known.has(p.slot):
		return
	_known.erase(p.slot)
	_since.erase(p.slot)
	p.st.prone = false
	p.ai_target = -1
	p.ai_goal = Vector2i(-1, -1)
	p.bot_plan_tick = -1000                  # its order works its way out again
	p.bot_goal = -1


func _run(p: Player, known: Dictionary) -> void:
	## Away to safety, and down on the floor once there (or with nowhere to go).
	var map := server.map
	var here := p.st.y * map.width + p.st.x
	if server.tick - p.bot_plan_tick >= PLAN_TICKS or here != p.bot_from or p.bot_task != -1:
		p.bot_plan_tick = server.tick
		p.bot_from = here
		p.bot_task = -1                      # (not one of Stations' tasks: its plan is made again when it goes back)
		var safe := _safe_cells(p, known)
		var r: Array = [0, here] if safe.has(here) else server.stations._route(here, safe)
		p.bot_step = int(r[0])
		p.bot_goal = int(r[1])
		if _since.get(p.slot, -1) == server.tick:
			server.chat.bot_log(p, "вижу вооружённого пирата: %s." % ("ухожу к своим" if p.bot_goal >= 0 else "прячусь здесь"))
	p.doing = Net.DOING_HIDE
	p.using = false
	if p.bot_step == -1 and p.st.cd == 0:
		p.st.prone = false
		p.st.dir = Net.DIR_NONE
		server.movement.climb(p, true)
		p.bot_plan_tick = -1000
		return
	if p.bot_step > 0 and p.bot_goal != here:
		p.st.prone = false
		p.st.dir = Net.DIR_NONE if server.movement._would_vent(p.st.x, p.st.y, p.bot_step) else p.bot_step
		return
	# there, or no way anywhere: it lies low
	p.st.dir = Net.DIR_NONE
	if p.st.cd == 0:
		p.st.prone = true


func _safe_cells(p: Player, known: Dictionary) -> Dictionary:
	## Our ship's open floor far from every pirate it knows of (and out of their rooms);
	## of those, the ones by our people if there are any.
	var map := server.map
	var w := map.width
	var threats: Array = []
	var rooms := {}
	for k: int in known.keys():
		var at: Vector2i = known[k][0]
		threats.append(at)
		var r := map.room_of[at.y * w + at.x]
		if r >= 0:
			rooms[r] = true
	var people: Array = []
	for q: Player in server.players:
		if q == null or q.bot or q.pirate or q.ally or q.corpse or q.cond != Net.COND_OK:
			continue
		if _far(map, Vector2i(q.st.x, q.st.y), threats, CREW_SAFE):
			people.append(Vector2i(q.st.x, q.st.y))
	var far := {}
	var by_crew := {}
	for c in map.walk.size():
		if map.walk[c] != 1 or map.door_of[c] >= 0 or not map.on_ship(c) or rooms.has(map.room_of[c]):
			continue
		var cell := Vector2i(c % w, c / w)
		if not _far(map, cell, threats, SAFE_FROM) or not server.stations._breathable(p, c):
			continue
		far[c] = 0
		for at: Vector2i in people:
			if map.deck_of(at.y) == map.deck_of(cell.y) and Vector2(at).distance_to(Vector2(cell)) <= CREW_NEAR:
				by_crew[c] = 0
				break
	return by_crew if not by_crew.is_empty() else far


func _far(map, cell: Vector2i, threats: Array, reach: float) -> bool:
	for at: Vector2i in threats:
		if map.deck_of(at.y) == map.deck_of(cell.y) and Vector2(at).distance_to(Vector2(cell)) < reach:
			return false
	return true


# ------------------------------------------------------------ the guard

func gun_slot(p: Player) -> int:
	## The slot of a pistol or shotgun it can shoot (loaded, or with its ammunition), or -1.
	for k in p.slots.size():
		var v: int = p.slots[k]
		if Items.rounds(v) > 0 or Items.rounds(v) == 0 and p.slots.has(Items.ammo_of(v)):
			return k
	return -1


func _locker_gun() -> int:
	var store: Dictionary = server.ship.store
	for kind: int in [Net.ITEM_PISTOL, Net.ITEM_SHOTGUN]:
		if int(store.get(kind, 0)) > 0:
			return kind
	return Net.ITEM_NONE


func _guard(p: Player, known: Dictionary) -> bool:
	## A guard bot fights when it has a gun, or fetches one from the locker. False: no gun
	## to be had (it runs like the others).
	var k := gun_slot(p)
	if k >= 0:
		p.st.prone = false
		p.hand = k
		if p.doing != Net.DOING_FIGHT:
			server.chat.bot_log(p, "иду на пиратов с оружием.")
		p.doing = Net.DOING_FIGHT
		p.bot_task = -1
		p.bot_goal = -1
		# where it last knew one to be, when it sees none (Pirates.think goes after one it sees)
		if p.ai_target < 0:
			var latest := -1
			for s: int in known.keys():
				if int(known[s][1]) > latest:
					latest = int(known[s][1])
					p.ai_goal = known[s][0]
		server.pirates.think(p)
		return true
	var kind := _locker_gun()
	if kind == Net.ITEM_NONE or p.count(Net.ITEM_NONE) == 0 or server.map.locker.is_empty():
		return false
	p.st.prone = false
	var map := server.map
	var here := p.st.y * map.width + p.st.x
	var ahead := map.use_ahead(p.st.x, p.st.y, p.st.facing)
	if map.locker.has(ahead) and p.st.cd == 0:
		# at the locker: the gun and its ammunition
		var sup = server.supplies
		sup.store_asked(p, Net.STORE_TAKE, kind)
		for n in AMMO_TAKEN:
			if p.count(Net.ITEM_NONE) > 0:
				sup.store_asked(p, Net.STORE_TAKE, Items.ammo_of(kind))
		server.chat.bot_log(p, "беру %s из шкафчика." % Items.name_of(kind).to_lower())
		p.bot_plan_tick = -1000
		return true
	if server.tick - p.bot_plan_tick >= PLAN_TICKS or here != p.bot_from or p.bot_task != -2:
		p.bot_plan_tick = server.tick
		p.bot_from = here
		p.bot_task = -2
		var goals := {}
		server.stations._locker_goals(p, goals, {})
		var r: Array = [0, here] if goals.has(here) else server.stations._route(here, goals)
		p.bot_step = int(r[0])
		p.bot_goal = int(r[1])
		p.bot_face = int(goals.get(p.bot_goal, 0))
		if p.bot_goal < 0:
			return false                     # no way to the locker: it runs instead
		server.chat.bot_log(p, "иду за оружием к шкафчику.")
	p.doing = Net.DOING_CARRY
	p.using = false
	if p.bot_step == -1 and p.st.cd == 0:
		p.st.dir = Net.DIR_NONE
		server.movement.climb(p, true)
		p.bot_plan_tick = -1000
	elif p.bot_step > 0 and p.bot_goal != here:
		p.st.dir = Net.DIR_NONE if server.movement._would_vent(p.st.x, p.st.y, p.bot_step) else p.bot_step
	else:
		p.st.dir = Net.DIR_NONE
		if p.bot_face > 0 and p.st.facing != p.bot_face and p.st.cd == 0:
			p.st.facing = p.bot_face
			p.self_dirty = true
	return true
