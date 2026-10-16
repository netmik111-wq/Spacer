extends RefCounted
## (v55) Our own crew at their posts in a fight, the bots that take the
## captain's orders, the battle position the pilot picks, and our people
## boarding a pirate ship. Server only.
##
## Posts mirror the pirates' (EnemyCrew): whoever stands at the ship's
## controls facing them flies the ship, and the enemy's shots miss more often
## (more with a pilot by job, a little more again with somebody minding the
## engine); nobody there, and nothing is dodged, as before v55. Somebody at the
## shield generator makes it refill faster. The gun console is where shots are
## fired from, as before.
##
## Bots (the author's notebook: "bots and people are the ship's crew; bots play
## on their own and carry out the orders of whoever commands the ship") take
## a standing order from the captain, or from anybody while no captain is
## aboard (the author's yes): a post, mending what is broken, following, or
## free (they wander as before). A bot at the gun console fires whatever is
## ready, where the guns aim; one mending takes spare parts and patches from
## the hold. Bots keep to our own ship: they never go out into space.
##
## The battle position (the author's notebook: the engine moves the ship about
## the battlefield; my halfway version, one choice instead of steering): close
## in (as before), keep at a distance (both sides hit less, their boarding comes
## at half the pace), or take its flank (we hit better, dodge worse). Changing
## it is a manoeuvre of MANOEUVRE_SECONDS with no dodge; anything but close in
## needs somebody at the controls and the engine going, and nobody of ours out
## in space.
##
## Boarding: while close in, our people can cross through space to the pirate
## ship. When the first of them steps aboard, its crew come to life as pirates
## (EnemyCrew.come_to_life) and fight; whoever of ours stands in a room with a
## system in it wrecks it a point every SABOTAGE_SECONDS; with its crew all dead
## it is captured (Gunnery._wrecked). It cannot jump away, nor be let go for a
## ransom, while any of ours is aboard.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Vitals := preload("res://src/server/vitals.gd")

const HELM_DODGE := 0.15             # the enemy's shots miss this much more often with somebody at the controls
const PILOT_DODGE := 0.05            # and this much more again with a pilot by job there
const ENGINE_DODGE := 0.05           # and with somebody minding the engine
const SHIELD_PACE := 1.25            # the shield refills this much faster with somebody at its generator
const MANOEUVRE_SECONDS := 8.0       # to change the battle position, without dodging meanwhile
const FAR_HIT := 0.15                # at a distance both sides hit this much less
const FLANK_HIT := 0.15              # from its flank we hit this much better...
const FLANK_DODGE := 0.5             # ... and dodge only half as well
const LAPSE_SECONDS := 5.0           # far or flank, nobody at the controls this long: back close in
const SABOTAGE_SECONDS := 8.0        # one of our boarders in a system's room wrecks a point of it this often
const BOT_PLAN_TICKS := 10           # how often a bot under orders looks again at where to go
const BOT_AIR := 0.5                 # a bot does not go where the air is thinner than this

var server: GameServer
var position := Net.POS_CLOSE
var goal := Net.POS_NONE             # the position the ship is manoeuvring to (POS_NONE = none)
var manoeuvre_until := 0
var ours_aboard := false             # somebody of ours, alive, is on the pirate ship now
var spots := {}                      # Net.POST_* -> Array of [cell to stand on, facing]
var _at := {}                        # Net.POST_* -> the Player at that post now
var _lapse := 0
var _sabotage := PackedFloat32Array()
var _told := PackedByteArray()


func setup(p_server: GameServer) -> void:
	server = p_server
	position = Net.POS_CLOSE
	goal = Net.POS_NONE
	_sabotage.resize(Net.ESYS_COUNT)
	var map := server.map
	spots = {}
	for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD]:
		var list: Array = []
		for c: int in _devices(post).keys():
			list.append_array(_spots_for(c))
		spots[post] = list


func _devices(post: int) -> Dictionary:
	var map := server.map
	match post:
		Net.POST_HELM:
			return map.helm
		Net.POST_GUNS:
			return map.gun_console
		Net.POST_ENGINE:
			return map.engine
		Net.POST_SHIELD:
			return map.shield
	return {}


func _spots_for(target: int) -> Array:
	## Where one can stand to work on that cell (a machine, a door, a hole): [cell, facing] each.
	var map := server.map
	var out: Array = []
	var tx := target % map.width
	var ty := target / map.width
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := tx + dx
			var y := ty + dy
			if (dx == 0 and dy == 0) or not map.walkable(x, y) or map.door_at(x, y) >= 0 or not map.on_ship(y * map.width + x):
				continue
			for f in range(1, 5):
				if map.use_ahead(x, y, f, server.air.holes) == target:
					out.append([y * map.width + x, f])
	return out


# ---------------------------------------------------------------- who stands where

func _scan() -> void:
	## Who is at which post now, and whether any of ours is on the pirate ship.
	var map := server.map
	_at = {}
	ours_aboard = false
	var enemy: bool = server.derelict.here and server.derelict.kind == Net.OTHER_PIRATE and not server.derelict.wreck
	for p: Player in server.players:
		if p == null or p.pirate or p.corpse or p.cond == Net.COND_DEAD:
			continue
		if enemy and map.is_other(p.st.y * map.width + p.st.x):
			ours_aboard = true
		if p.cond != Net.COND_OK or not server.powered():
			continue
		var ahead := map.use_ahead(p.st.x, p.st.y, p.st.facing)
		if ahead < 0 or server.ship.broken.has(ahead):
			continue
		for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD]:
			if _devices(post).has(ahead) and not _at.has(post):
				_at[post] = p


func manned(post: int) -> bool:
	return _at.has(post)


func at_post(post: int) -> Player:
	return _at.get(post, null)


func our_dodge() -> float:
	## How much less often the enemy's shots hit us now.
	if not server.gunnery.fighting() or not server.powered() or server.engine_down() or goal != Net.POS_NONE:
		return 0.0
	var pilot: Player = _at.get(Net.POST_HELM, null)
	if pilot == null:
		return 0.0
	var d := HELM_DODGE + (PILOT_DODGE if pilot.job == Net.JOB_PILOT else 0.0) + (ENGINE_DODGE if _at.has(Net.POST_ENGINE) else 0.0)
	return d * (FLANK_DODGE if position == Net.POS_FLANK else 1.0)


func our_hit_bonus() -> float:
	match position:
		Net.POS_FAR:
			return -FAR_HIT
		Net.POS_FLANK:
			return FLANK_HIT
	return 0.0


func their_hit_bonus() -> float:
	return -FAR_HIT if position == Net.POS_FAR else 0.0


func shield_pace() -> float:
	return SHIELD_PACE if _at.has(Net.POST_SHIELD) else 1.0


func slows_docking() -> bool:
	return position == Net.POS_FAR and server.gunnery.fighting()


# ---------------------------------------------------------------- the battle position

func position_asked(p: Player, to: int) -> void:
	## The pilot at the ship's controls takes the ship to a battle position.
	if not server.systems.at_console(p, server.map.helm) or to < 0 or to > Net.POS_FLANK:
		return
	if not server.gunnery.fighting():
		server.chat.tell(p, "Боя нет: позицию выбирать не нужно.")
		return
	if to == (goal if goal != Net.POS_NONE else position):
		return
	if server.engine_down():
		server.chat.tell(p, "Двигатель не работает: манёвр невозможен.")
		return
	if to != Net.POS_CLOSE and server.derelict.someone_outside():
		server.chat.tell(p, "Кто-то из наших снаружи корабля: без них не отойти.")
		return
	goal = to
	manoeuvre_until = server.tick + roundi(MANOEUVRE_SECONDS * Net.TICK_HZ)
	server.chat.say("%s ведёт корабль на позицию «%s»: манёвр %d с, пока он идёт, мы не уклоняемся." % [
		p.name, Net.POS_NAMES[to].to_lower(), int(MANOEUVRE_SECONDS)])


func _position_tick() -> void:
	if not server.gunnery.fighting():
		position = Net.POS_CLOSE
		goal = Net.POS_NONE
		_lapse = 0
		return
	if goal != Net.POS_NONE:
		if server.engine_down() or not server.powered():
			goal = Net.POS_NONE
			server.chat.say("Манёвр сорван: двигатель стоит.")
		elif goal != Net.POS_CLOSE and server.tick % 10 == 0 and server.derelict.someone_outside():
			goal = Net.POS_NONE
			server.chat.say("Манёвр сорван: кто-то из наших снаружи.")
		elif server.tick >= manoeuvre_until:
			position = goal
			goal = Net.POS_NONE
			_lapse = 0
			server.chat.say("Корабль на позиции «%s». %s" % [Net.POS_NAMES[position].to_lower(), _about(position)])
	if position == Net.POS_CLOSE:
		return
	if server.tick % 10 == 0 and server.derelict.someone_outside():
		position = Net.POS_CLOSE
		server.chat.say("Кто-то из наших вышел наружу: корабль подходит к пиратам вплотную, чтобы не бросить его.")
		return
	if server.powered() and not server.engine_down() and _at.has(Net.POST_HELM):
		_lapse = 0
		return
	_lapse += 1
	if _lapse >= roundi(LAPSE_SECONDS * Net.TICK_HZ):
		_lapse = 0
		position = Net.POS_CLOSE
		server.chat.say("Позицию некому держать (никого за штурвалом или двигатель стоит): пираты подходят вплотную.")


static func _about(pos: int) -> String:
	match pos:
		Net.POS_FAR:
			return "Обе стороны попадают реже (−%d%%), пираты подходят к шлюзу вдвое медленнее, на абордаж не перейти." % roundi(FAR_HIT * 100)
		Net.POS_FLANK:
			return "Мы попадаем лучше (+%d%%), но уклоняемся вдвое хуже; на абордаж не перейти." % roundi(FLANK_HIT * 100)
	return "Бой как обычно; к пиратам можно перейти через открытый космос."


# ---------------------------------------------------------------- orders

func may_order(p: Player) -> bool:
	## The captain gives orders; while no captain is aboard, anybody may (the author's yes).
	if p == null or p.bot or p.pirate or p.corpse or p.cond != Net.COND_OK:
		return false
	if p.job == Net.JOB_CAPTAIN:
		return true
	for q: Player in server.players:
		if q != null and q.peer != null and not q.bot and not q.pirate and not q.corpse and q.job == Net.JOB_CAPTAIN \
				and q.cond != Net.COND_DEAD:
			return false
	return true


func order_asked(p: Player, id: int, post: int) -> void:
	if not may_order(p):
		server.chat.tell(p, "Приказы экипажу отдаёт капитан.")
		return
	if id == Net.NOBODY:
		if post == Net.POST_ALL:
			_all_to_posts(p)
		elif post == Net.POST_FREE:
			for q: Player in _bots():
				_set_order(q, Net.POST_FREE, p)
			server.chat.say("%s: «Отбой, все свободны»." % p.name)
		return
	if id >= server.players.size() or post >= Net.POSTS:
		return
	var q: Player = server.players[id]
	if q == null or not q.bot or q.corpse:
		return
	_set_order(q, post, p)
	server.chat.say("%s: «%s, %s»." % [p.name, q.name, _order_words(post)])


static func _order_words(post: int) -> String:
	match post:
		Net.POST_HELM:
			return "к штурвалу"
		Net.POST_GUNS:
			return "к орудиям"
		Net.POST_ENGINE:
			return "к двигателю"
		Net.POST_SHIELD:
			return "к щитам"
		Net.POST_REPAIR:
			return "чинить всё, что сломано"
		Net.POST_FOLLOW:
			return "за мной"
	return "вольно"


func _bots() -> Array:
	var out: Array = []
	for q: Player in server.players:
		if q != null and q.bot and not q.corpse:
			out.append(q)
	return out


func _set_order(q: Player, post: int, by: Player) -> void:
	q.order = post
	q.order_by = by.slot if by != null else -1
	q.bot_goal = -1
	q.bot_plan_tick = -1000
	q.bot_step = 0
	q.using = false
	q.st.dir = Net.DIR_NONE


func _all_to_posts(by: Player) -> void:
	## Every bot to a post nobody of the players mans: the controls, the guns, the shield, the engine; the rest mend.
	var wanted: Array = []
	for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_SHIELD, Net.POST_ENGINE]:
		if (spots[post] as Array).is_empty():
			continue
		var p: Player = _at.get(post, null)
		if p == null or p.bot:
			wanted.append(post)
	var bots := _bots()
	for i in bots.size():
		_set_order(bots[i], wanted[i] if i < wanted.size() else Net.POST_REPAIR, by)
	server.chat.say("%s: «Все по местам!»" % by.name)


# ---------------------------------------------------------------- a bot under orders

func bot_think(p: Player) -> bool:
	## One tick of a bot's mind while it has an order. False: it has none (it wanders, see Movement).
	if p.order == Net.POST_FREE:
		p.doing = Net.DOING_IDLE
		return false
	if p.cond != Net.COND_OK:
		p.doing = Net.DOING_DOWN
		p.using = false
		return true
	var map := server.map
	var here := p.st.y * map.width + p.st.x
	if server.tick - p.bot_plan_tick >= BOT_PLAN_TICKS or here != p.bot_from:
		_plan(p, here)
	if p.bot_step == -1:
		p.st.dir = Net.DIR_NONE
		p.using = false
		if p.st.cd > 0:
			return true
		server.movement.climb(p)
		p.bot_plan_tick = -1000
		return true
	if p.bot_step > 0:
		p.using = false
		p.st.dir = Net.DIR_NONE if server.movement._would_vent(p.st.x, p.st.y, p.bot_step) else p.bot_step
		return true
	p.st.dir = Net.DIR_NONE
	if p.bot_goal == here:
		if p.bot_face > 0 and p.st.facing != p.bot_face:
			p.st.facing = p.bot_face
			p.self_dirty = true
		_work(p)
	return true


func _plan(p: Player, here: int) -> void:
	p.bot_plan_tick = server.tick
	p.bot_from = here
	var goals := {}                    # cell -> facing (0 = any)
	match p.order:
		Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD:
			var taken := _taken(p)
			for s: Array in spots[p.order]:
				if not taken.has(int(s[0])) and _breathable(p, int(s[0])):
					goals[int(s[0])] = int(s[1])
		Net.POST_REPAIR:
			goals = _repair_goals(p)
		Net.POST_FOLLOW:
			var lead: Player = server.players[p.order_by] if p.order_by >= 0 and p.order_by < server.players.size() else null
			if lead != null and not lead.corpse and lead.cond != Net.COND_DEAD and server.map.on_ship(lead.st.y * server.map.width + lead.st.x):
				var w := server.map.width
				for o: int in [1, -1, w, -w]:
					var c := lead.st.y * w + lead.st.x + o
					if server.map.walkable(c % w, c / w) and server.map.on_ship(c):
						goals[c] = 0
	if goals.is_empty():
		p.bot_goal = -1
		p.bot_step = 0
		p.using = false
		p.doing = Net.DOING_IDLE
		return
	if goals.has(here):
		p.bot_goal = here
		p.bot_face = goals[here]
		p.bot_step = 0
		p.doing = Net.DOING_WORK if p.order == Net.POST_REPAIR else Net.DOING_POST
		return
	var r := _route(here, goals)
	p.bot_step = r[0]
	p.bot_goal = r[1]
	p.bot_face = int(goals.get(r[1], 0))
	p.using = false
	p.doing = Net.DOING_NO_WAY if p.bot_goal < 0 else Net.DOING_GOING


func _taken(p: Player) -> Dictionary:
	## Cells others stand on or make for.
	var out := {}
	for q: Player in server.players:
		if q == null or q == p or q.corpse:
			continue
		out[q.st.y * server.map.width + q.st.x] = true
		if q.bot and q.order != Net.POST_FREE and q.bot_goal >= 0:
			out[q.bot_goal] = true
	return out


func _breathable(p: Player, cell: int) -> bool:
	return server.air.air[cell] >= BOT_AIR or (p.supply and p.tank > 0.0)


func _repair_goals(p: Player) -> Dictionary:
	## Where it can stand to mend something: broken machines, doors gone wrong, holes (with a patch to hand).
	var map := server.map
	var jobs: Array = []
	for c: int in server.ship.broken.keys():
		jobs.append(c)
	for d in mini(map.other_first_door, map.doors.size()):
		if server.doors.jammed[d] == 1 or server.doors.faulty[d] == 1:
			var at: Vector2i = map.doors[d]
			jobs.append(at.y * map.width + at.x)
	if p.count(Net.ITEM_PATCH) > 0 or int(server.ship.store.get(Net.ITEM_PATCH, 0)) > 0:
		for c: int in server.air.holes.keys():
			if not map.is_other(c):
				jobs.append(c)
	var taken := _taken(p)
	var out := {}
	for c: int in jobs:
		for s: Array in _spots_for(c):
			if not taken.has(int(s[0])) and _breathable(p, int(s[0])):
				out[int(s[0])] = int(s[1])
	return out


func _route(start: int, goals: Dictionary) -> Array:
	## [the first step of a shortest way to the nearest of the goals (a direction,
	## -1 = the ladder underfoot, 0 = none), that goal (-1 = none reachable)].
	## Our own ship only, ladders included, around shutters that are down.
	var map := server.map
	var w := map.width
	var first := {start: 0}
	var queue := PackedInt32Array([start])
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		var x := cell % w
		var y := cell / w
		var nexts: Array = []
		for d in range(1, 5):
			var nx: int = x + Net.DX[d]
			var ny: int = y + Net.DY[d]
			var j := ny * w + nx
			if not map.walkable(nx, ny) or not map.on_ship(j):
				continue
			var door := map.door_of[j]
			if door >= 0 and server.doors.is_sealed(door):
				continue
			nexts.append([j, d])
		if map.climb[cell] >= 0:
			nexts.append([map.climb[cell], -1])
		for n: Array in nexts:
			var to: int = n[0]
			if first.has(to):
				continue
			first[to] = n[1] if cell == start else first[cell]
			if goals.has(to):
				return [first[to], to]
			queue.append(to)
	return [0, -1]


func _work(p: Player) -> void:
	## What a bot does at the end of its way.
	match p.order:
		Net.POST_GUNS:
			p.doing = Net.DOING_POST
			var g = server.gunnery
			if g.fighting() and g.ransom == 0 and server.systems.at_console(p, server.map.gun_console) and _a_gun_ready():
				g.fire(p, 255)
		Net.POST_REPAIR:
			var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
			var hole := server.air.holes.has(ahead)
			var door := server.map.door_of[ahead] if ahead >= 0 else -1
			if not hole and not server.ship.broken.has(ahead) and not (door >= 0 and (server.doors.jammed[door] == 1 or server.doors.faulty[door] == 1)):
				p.using = false
				p.bot_plan_tick = -1000          # done here: on to the next
				return
			var item := Net.ITEM_PATCH if hole else Net.ITEM_PART
			if p.count(item) == 0 and int(server.ship.store.get(item, 0)) > 0 and p.count(Net.ITEM_NONE) > 0:
				server.ship.store[item] -= 1
				p.add(item)
				server.supplies.tell_store()
			if hole and p.count(Net.ITEM_PATCH) == 0:
				p.using = false
				p.doing = Net.DOING_IDLE
				return
			p.using = true
			p.doing = Net.DOING_WORK
		_:
			p.doing = Net.DOING_POST


func _a_gun_ready() -> bool:
	var g = server.gunnery
	var ship = server.ship
	for i in g.charge.size():
		if g.charge[i] >= 1.0 and ship.armed[i] == 1 and g.beam_left[i] == 0 and not ship.broken.has(server.map.guns[i]) \
				and (Weapons.ammo(ship.mounts[i]) == 0 or int(ship.store.get(Weapons.ammo(ship.mounts[i]), 0)) > 0):
			return true
	return false


# ---------------------------------------------------------------- boarding

func _boarding() -> void:
	var g = server.gunnery
	var em = server.enemy_crew
	if not g.fighting() or em.o == null:
		_sabotage.fill(0.0)
		return
	if ours_aboard and not em.in_world:
		var who := ""
		for p: Player in server.players:
			if p != null and not p.pirate and not p.corpse and p.cond != Net.COND_DEAD and server.map.is_other(p.st.y * server.map.width + p.st.x):
				who = p.name
				break
		em.come_to_life()
		server.chat.say("%s поднимается на борт пиратского корабля! Его экипаж (%d) бросает посты и хватается за оружие." % [who, em.count()])
	if not em.in_world:
		return
	if em.count() < g.boarders_left():
		g.crew_lost(em.count())
		if not g.fighting():
			return
	# ours in a room with a system in it wreck it
	var map := server.map
	var hands := PackedInt32Array()
	hands.resize(Net.ESYS_COUNT)
	for p: Player in server.players:
		if p == null or p.pirate or p.corpse or p.cond != Net.COND_OK:
			continue
		var cell := p.st.y * map.width + p.st.x
		if not map.is_other(cell):
			continue
		var local: int = server.derelict._local(cell, map.other_at)
		var system: int = g.system_in(em.o.room_of[local]) if local >= 0 and local < em.o.room_of.size() else -1
		if system >= 0 and system != Net.ESYS_CREW:
			hands[system] += 1
	for k in Net.ESYS_COUNT:
		if hands[k] == 0 or k >= g.systems.size() or g.systems[k] == 0:
			_sabotage[k] = 0.0
			continue
		_sabotage[k] += mini(hands[k], 2) / (SABOTAGE_SECONDS * Net.TICK_HZ)
		if _sabotage[k] >= 0.9999:
			_sabotage[k] = 0.0
			g.wear_by_hand(k)


# ---------------------------------------------------------------- every tick

func tick() -> void:
	_scan()
	_position_tick()
	_boarding()
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func packet() -> PackedByteArray:
	var ship = server.ship
	var out := PackedByteArray([Net.S_STATIONS, ship.id & 0xFF, ship.id >> 8, position, goal,
		clampi(int(ceil(float(manoeuvre_until - server.tick) / Net.TICK_HZ)), 0, 255) if goal != Net.POS_NONE else 0,
		roundi(our_dodge() * 100.0), 100 + roundi(our_hit_bonus() * 100.0), 100 + roundi(their_hit_bonus() * 100.0)])
	var bits := 0
	for post: int in _at.keys():
		bits |= 1 << (post - 1)
	out.append(bits)
	var bots := _bots()
	out.append(mini(bots.size(), 255))
	for q: Player in bots:
		out.append(q.slot & 0xFF)
		out.append(q.slot >> 8)
		out.append(q.order)
		out.append(q.doing if q.cond == Net.COND_OK else Net.DOING_DOWN)
	return out
