extends RefCounted
## (v96, the author's P4: "our pods with the places' build") Our boarding pods. A bay ('k' in the drawing) is set
## into the hull of a ship of our fleet. In a fight with the pirate ship alongside, E at the bay sits one in
## (Net.POD_SEATS seats); the pod flies when its seats are taken or WAIT seconds after the first sat in (longer
## while a bot called to the free seat is on its way, my B3 pick). It is a slow thing in space (Arena: "pod" "ours")
## that passes the pirates' shield, meets their point defence once, and strikes their hull where it meets it: the
## riders step out inside, by that spot, and the pirates' crew come to life (Stations._boarding). The pod stays in
## their hull (POD_STUCK): E at that hull cell sits one in for home (my B2 pick); with nobody of ours left on that
## ship once the fight is over, the empty pod comes home by itself. Shot down on its way, it is thrown back to its
## bay with its riders bruised, and needs MEND seconds before it flies again.
##
## Riders are out of the world while they fly, as the shuttle's passengers are (Player.in_shuttle; Player.in_pod
## says which bay). Bots: when one of ours sits in, the nearest bot told «К оружию» (or the guard) comes to take
## the free seat, fetching a gun on its way; aboard the pirate ship it fights them by the pirates' own mind, and
## with none of them left it goes back to the pod and rides home (bot_think, before Defence).
## Part of the server: GameServer keeps one of these.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

const WAIT := 5.0                    # (my B1 pick) seconds from the first rider to the take-off
const BOT_WAIT := 15.0               # the most it waits for a bot called to the free seat
const HOME_WAIT := 3.0               # at their hull, seconds from the first rider for home to the take-off
const HOME_SECONDS := 6.0            # (my B2 pick) the flight home
const MEND := 30.0                   # seconds a pod shot down is made good at its bay
const BRUISE := 15                   # what each rider of a pod shot down takes
const PLAN_TICKS := 10

var server: GameServer
var bays := {}                       # the bay's wall cell -> {"state": POD_*, "riders": Array[Player], "go": tick, "stuck": the
                                     # pirate's hull cell (grid), "inside": the floor cell by it, "until": tick (home, mended)}
var bots_ride := true                # (tests: false keeps the bots out of the pods)
var _told := {}                      # Player -> the S_POD last sent to them (a newcomer is told at once)


func setup(p_server: GameServer) -> void:
	server = p_server
	bays.clear()
	for c: int in server.map.pod.keys():
		bays[c] = _fresh()
	_told = {}


static func _fresh() -> Dictionary:
	return {"state": Net.POD_READY, "riders": [], "go": -1, "stuck": -1, "inside": -1, "until": -1}


func fight_on() -> bool:
	## Is there a pirate ship alongside fighting us in space, for a pod to fly at?
	var d = server.derelict
	return d.here and d.kind == Net.OTHER_PIRATE and not d.wreck and server.arena.on() and server.arena.body(server.arena.LEAD) != null \
		and server.arena.body(server.arena.LEAD).on


func state(bay: int) -> int:
	return int((bays[bay] as Dictionary)["state"]) if bays.has(bay) else -1


func stuck_bay(cell: int) -> int:
	## The bay whose pod is stuck in the pirate's hull at that cell (-1: none).
	for bay: int in bays.keys():
		var b: Dictionary = bays[bay]
		if int(b["state"]) == Net.POD_STUCK and int(b["stuck"]) == cell:
			return bay
	return -1


# ---------------------------------------------------------------- sitting in

func press(p: Player, cell: int) -> bool:
	## E at a pod bay of ours, or at our pod stuck in the pirate's hull. True: it was one.
	if bays.has(cell):
		_at_bay(p, cell)
		return true
	var bay := stuck_bay(cell)
	if bay >= 0:
		_at_hull(p, bay)
		return true
	return false


func _at_bay(p: Player, bay: int) -> void:
	var b: Dictionary = bays[bay]
	var st: int = b["state"]
	if st == Net.POD_MENDING:
		_tell(p, "Капсулу чинят после попадания: ещё %d с." % ceili(float(int(b["until"]) - server.tick) / Net.TICK_HZ))
		return
	if st == Net.POD_OUT or st == Net.POD_STUCK or st == Net.POD_HOME:
		_tell(p, "Капсулы нет на месте: она у пиратского корабля или в полёте.")
		return
	if not fight_on():
		_tell(p, "Капсула летит только к пиратскому кораблю у нашего борта, в бою.")
		return
	if not server.powered():
		_tell(p, "Отсек капсулы обесточен.")
		return
	_sit(p, bay, false)


func _at_hull(p: Player, bay: int) -> void:
	var b: Dictionary = bays[bay]
	if (b["riders"] as Array).size() >= Net.POD_SEATS:
		_tell(p, "В капсуле нет мест.")
		return
	_sit(p, bay, true)


func _sit(p: Player, bay: int, home: bool) -> void:
	var b: Dictionary = bays[bay]
	var riders: Array = b["riders"]
	if riders.size() >= Net.POD_SEATS:
		_tell(p, "В капсуле нет мест: в ней %d." % Net.POD_SEATS)
		return
	if p.dragging >= 0 or p.dragged_by >= 0:
		_tell(p, "С ношей в капсулу не сесть.")
		return
	p.in_shuttle = true
	p.in_pod = bay
	p.pod_call = -1
	p.inputs.clear()
	p.st.dir = 0
	p.st.prone = false
	p.using = false
	riders.append(p)
	server.chat.sound(Net.SOUND_DOOR, p.st.x, p.st.y)
	server.replication.sight_changed()
	if not p.bot:
		server.usage.note(p, "pod")
	var wait := HOME_WAIT if home else WAIT
	if int(b["go"]) < 0:
		b["go"] = server.tick + roundi(wait * Net.TICK_HZ)
		if not home:
			b["state"] = Net.POD_WAITING
			if not p.bot and bots_ride and _call_bot(bay):
				b["go"] = server.tick + roundi(BOT_WAIT * Net.TICK_HZ)
	if riders.size() >= Net.POD_SEATS:
		b["go"] = server.tick
	if p.bot:
		server.chat.bot_log(p, "сажусь в абордажную капсулу.")
	else:
		_tell(p, "Вы в капсуле. Взлёт через %d с%s." % [ceili(float(int(b["go"]) - server.tick) / Net.TICK_HZ),
			"" if home or riders.size() >= Net.POD_SEATS else " (или сразу, когда займут второе место; Esc: выйти)"])


func asked(p: Player, action: int) -> void:
	## C_POD: step out of a pod still waiting at its bay (or at their hull).
	if action != Net.POD_LEAVE or p.in_pod < 0 or not bays.has(p.in_pod):
		return
	var b: Dictionary = bays[p.in_pod]
	if int(b["state"]) != Net.POD_WAITING and int(b["state"]) != Net.POD_STUCK:
		return
	var bay := p.in_pod
	(b["riders"] as Array).erase(p)
	if int(b["state"]) == Net.POD_STUCK:
		_out_at(p, int(b["inside"]))
	else:
		_out_at(p, int(server.map.pod[bay]))
	if (b["riders"] as Array).is_empty():
		b["go"] = -1
		if int(b["state"]) == Net.POD_WAITING:
			b["state"] = Net.POD_READY


func _call_bot(bay: int) -> bool:
	## (my B3 pick) The nearest bot of that ship told «К оружию» (or the guard) comes to the free seat.
	var map = server.map
	var front: int = map.pod[bay]
	var ship: int = maxi(map.fleet_of(bay), 0)
	var best: Player = null
	var best_d := INF
	for q: Player in server.players:
		if q == null or not q.bot or q.pirate or q.ally or q.corpse or q.cond != Net.COND_OK or q.in_shuttle or q.pod_call >= 0:
			continue
		if not (q.defends or q.job == Net.JOB_GUARD) or q.fleet_ship != ship or not map.on_ship(q.st.y * map.width + q.st.x):
			continue
		var d := Vector2(q.st.x, q.st.y).distance_to(Vector2(front % map.width, front / map.width))
		if d < best_d:
			best_d = d
			best = q
	if best == null:
		return false
	best.pod_call = bay
	best.bot_plan_tick = -1000
	server.chat.bot_log(best, "иду к абордажной капсуле: второе место моё.")
	return true


# ---------------------------------------------------------------- every tick

func tick() -> void:
	for bay: int in bays.keys():
		var b: Dictionary = bays[bay]
		var riders: Array = b["riders"]
		for q: Player in riders.duplicate():
			if q == null or q.corpse or q.slot < 0 or q.slot >= server.players.size() or server.players[q.slot] != q:
				riders.erase(q)              # left the game
		match int(b["state"]):
			Net.POD_WAITING:
				if not fight_on() or not server.powered():
					for q: Player in riders:
						_out_at(q, int(server.map.pod[bay]))
						_tell(q, "Бой окончен: капсула никуда не летит." if not fight_on() else "Отсек капсулы обесточен: взлёта не будет.")
					riders.clear()
					b["go"] = -1
					b["state"] = Net.POD_READY
				elif riders.is_empty():
					b["go"] = -1
					b["state"] = Net.POD_READY
				elif server.tick >= int(b["go"]):
					_launch(bay)
			Net.POD_STUCK:
				if not riders.is_empty() and server.tick >= int(b["go"]):
					_fly_home(bay)
				elif riders.is_empty() and not _ours_over_there() and (not fight_on() or not server.derelict.here):
					_fly_home(bay)           # (my B2 pick) the empty pod comes home by itself after the fight
			Net.POD_HOME:
				if server.tick >= int(b["until"]):
					for q: Player in riders:
						_out_at(q, int(server.map.pod[bay]))
					if not riders.is_empty():
						server.chat.say("Абордажная капсула вернулась к нашему борту.")
					riders.clear()
					b["go"] = -1
					b["state"] = Net.POD_READY
			Net.POD_MENDING:
				if server.tick >= int(b["until"]):
					b["state"] = Net.POD_READY
	if bays.is_empty():
		return
	var pkt := packet()
	for p: Player in server.players:
		if p != null and p.peer != null and _told.get(p, PackedByteArray()) != pkt:
			_told[p] = pkt
			p.peer.send(0, pkt, ENetPacketPeer.FLAG_RELIABLE)


func _launch(bay: int) -> void:
	var b: Dictionary = bays[bay]
	var ship: int = maxi(server.map.fleet_of(bay), 0)
	if not server.arena.launch_our_pod(ship, bay):
		for q: Player in b["riders"]:
			_out_at(q, int(server.map.pod[bay]))
		(b["riders"] as Array).clear()
		b["go"] = -1
		b["state"] = Net.POD_READY
		return
	b["state"] = Net.POD_OUT
	b["go"] = -1
	var names := PackedStringArray()
	for q: Player in b["riders"]:
		names.append(q.name)
	server.chat.say("Абордажная капсула стартовала к пиратскому кораблю: %s." % ", ".join(names))


func landed(bay: int, locals: PackedInt32Array) -> void:
	## (Arena) Our pod struck the pirate ship alongside at those cells of its drawing: its riders step out inside.
	if not bays.has(bay):
		return
	var b: Dictionary = bays[bay]
	var d = server.derelict
	var map = server.map
	if not d.here or d.kind != Net.OTHER_PIRATE or map.other == null:
		lost(bay, false)
		return
	var hull := -1
	var inside := -1
	for local: int in locals:
		var c: int = d._cell(map.other_at, local)
		if c < 0 or c >= map.cells.size() or not map.is_other(c):
			continue
		if map.walk[c] == 1 and map.door_of[c] < 0:
			inside = c
		elif hull < 0:
			hull = c
	if inside < 0:
		inside = _floor_near(hull)
	if inside < 0:
		lost(bay, false)
		return
	if hull < 0 or map.walk[hull] == 1:
		hull = _wall_near(inside)
	b["state"] = Net.POD_STUCK
	b["stuck"] = hull if hull >= 0 else inside
	b["inside"] = inside
	b["go"] = -1
	var spots := [inside]
	for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var c: int = inside + dv.y * map.width + dv.x
		if c >= 0 and c < map.cells.size() and map.is_other(c) and map.walk[c] == 1 and map.door_of[c] < 0 and map.stair_to[c] < 0:
			spots.append(c)
	var riders: Array = b["riders"]
	for i in riders.size():
		_out_at(riders[i], spots[mini(i, spots.size() - 1)])
	var x: int = inside % map.width
	var y: int = inside / map.width
	server.combat.jolt(Net.JOLT_HEAVY, Net.SHOT_SHELL, Vector2(x, y))
	server.chat.sound(Net.SOUND_DOOR, x, y)
	server.chat.say("Наша абордажная капсула пробила обшивку пиратского корабля! На борту: %d. Вернуться: E у капсулы." % riders.size())
	riders.clear()


func lost(bay: int, shot_down: bool) -> void:
	## (Arena) Our pod on its way was shot down by their point defence (thrown back to its bay, riders bruised), or
	## missed (it comes back).
	if not bays.has(bay):
		return
	var b: Dictionary = bays[bay]
	var riders: Array = b["riders"]
	for q: Player in riders:
		_out_at(q, int(server.map.pod[bay]))
		if shot_down:
			server.combat.hurt(q, BRUISE, null, server.combat.CAUSE_SHOT)
	if shot_down:
		server.chat.alarm("«Заслон» пиратов сбил нашу абордажную капсулу! Её отбросило к нашему борту: ремонт %d с." % int(MEND))
		b["state"] = Net.POD_MENDING
		b["until"] = server.tick + roundi(MEND * Net.TICK_HZ)
	else:
		server.chat.say("Абордажная капсула не долетела и вернулась к нашему борту.")
		b["state"] = Net.POD_READY
	riders.clear()
	b["go"] = -1


func _fly_home(bay: int) -> void:
	var b: Dictionary = bays[bay]
	b["state"] = Net.POD_HOME
	b["until"] = server.tick + roundi(HOME_SECONDS * Net.TICK_HZ)
	b["go"] = -1
	server.arena.pod_home(maxi(server.map.fleet_of(bay), 0))
	if not (b["riders"] as Array).is_empty():
		server.chat.say("Абордажная капсула отходит от пиратского корабля и летит домой: %d с." % int(HOME_SECONDS))


func _ours_over_there() -> bool:
	## Anybody of ours, alive, on the ship alongside.
	var map = server.map
	for q: Player in server.players:
		if q != null and not q.pirate and not q.ally and not q.corpse and q.cond != Net.COND_DEAD and not q.in_shuttle \
				and map.is_other(q.st.y * map.width + q.st.x):
			return true
	return false


func _out_at(p: Player, cell: int) -> void:
	## Back into the world at that floor cell (or the nearest free one).
	var map = server.map
	var spot := _free_near(cell, p)
	p.in_shuttle = false
	p.in_pod = -1
	p.st.place(spot % map.width, spot / map.width)
	p.inputs.clear()
	p.self_dirty = true
	p.bot_plan_tick = -1000
	p.ai_goal = Vector2i(-1, -1)
	p.ai_target = -1
	server.replication.sight_changed()


func _free_near(cell: int, p: Player) -> int:
	var map = server.map
	var seen := {cell: true}
	var queue: Array[int] = [cell]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if map.walk[c] == 1 and not map.held.has(c) and not _someone_at(c, p):
			return c
		for dd: int in [1, -1, map.width, -map.width]:
			var n := c + dd
			if n >= 0 and n < map.cells.size() and not seen.has(n) and map.walk[n] == 1 and map.door_of[n] < 0 and seen.size() < 200:
				seen[n] = true
				queue.append(n)
	return cell


func _someone_at(c: int, p: Player) -> bool:
	var w: int = server.map.width
	for q: Player in server.players:
		if q != null and q != p and not q.in_shuttle and not q.corpse and q.st.y * w + q.st.x == c:
			return true
	return false


func _floor_near(cell: int) -> int:
	## The pirate ship's floor cell nearest to that one (-1: none).
	var map = server.map
	if cell < 0:
		return -1
	var best := -1
	var best_d := 1 << 30
	for c: int in map.other_cells:
		if map.walk[c] != 1 or map.door_of[c] >= 0 or map.deck_of_cell(c) != map.deck_of_cell(cell):
			continue
		var d := absi(c % map.width - cell % map.width) + absi(c / map.width - cell / map.width)
		if d < best_d:
			best_d = d
			best = c
	return best


func _wall_near(cell: int) -> int:
	## A wall cell right by that floor cell (where the pod sticks out of the hull).
	var map = server.map
	for dd: int in [map.width, -map.width, 1, -1]:
		var n := cell + dd
		if n >= 0 and n < map.cells.size() and map.is_other(n) and map.walk[n] == 0 and map.door_of[n] < 0:
			return n
	return -1


# ---------------------------------------------------------------- (my B3 pick) bots

func bot_think(p: Player) -> bool:
	## A tick of a bot's mind about the pods: called to a seat, it goes there (with a gun); aboard the pirate
	## ship by a pod, it fights, then rides home. True: its other thoughts wait.
	if p.pod_call >= 0:
		return _to_seat(p)
	var map = server.map
	if not map.is_other(p.st.y * map.width + p.st.x) or not server.derelict.here:
		return false
	var bay := -1
	for k: int in bays.keys():
		if int((bays[k] as Dictionary)["state"]) == Net.POD_STUCK:
			bay = k
	if bay < 0:
		return false
	var foe := _nearest_pirate(p)
	var k := server.defence.gun_slot(p)
	if foe != null and k >= 0:
		p.hand = k
		p.doing = Net.DOING_FIGHT
		if p.ai_target < 0:
			p.ai_goal = Vector2i(foe.st.x, foe.st.y)
		server.pirates.think(p)
		return true
	if foe != null:
		return false                         # unarmed over there: as it would anyway (runs, hides)
	var b: Dictionary = bays[bay]
	var inside: int = b["inside"]
	var here: int = p.st.y * map.width + p.st.x
	p.doing = Net.DOING_GOING
	if here == inside or (absi(p.st.x - inside % map.width) <= 1 and absi(p.st.y - inside / map.width) <= 1 and p.st.cd == 0):
		p.st.dir = Net.DIR_NONE
		_at_hull(p, bay)
		return true
	if p.st.cd > 1:
		return true
	var step: int = server.pirates._first_step(p, Vector2i(inside % map.width, inside / map.width))
	p.st.dir = step if step > 0 else Net.DIR_NONE
	return true


func _nearest_pirate(p: Player) -> Player:
	var map = server.map
	var best: Player = null
	var best_d := INF
	for q: Player in server.players:
		if q == null or not q.pirate or q.prisoner or q.taken or q.corpse or q.cond == Net.COND_DEAD:
			continue
		if not map.is_other(q.st.y * map.width + q.st.x) or map.deck_of(q.st.y) != map.deck_of(p.st.y) and best != null:
			continue
		var d := Vector2(q.st.x, q.st.y).distance_to(Vector2(p.st.x, p.st.y)) + (0.0 if map.deck_of(q.st.y) == map.deck_of(p.st.y) else 50.0)
		if d < best_d:
			best_d = d
			best = q
	return best


func _to_seat(p: Player) -> bool:
	var bay := p.pod_call
	var b: Dictionary = bays.get(bay, {})
	if b.is_empty() or int(b["state"]) != Net.POD_WAITING or (b["riders"] as Array).size() >= Net.POD_SEATS or p.cond != Net.COND_OK:
		p.pod_call = -1
		return false
	if server.defence.gun_slot(p) < 0:
		if server.defence._guard(p, {}):
			return true                      # on its way to the locker for a gun first
		p.pod_call = -1
		server.chat.bot_log(p, "оружия нет: в капсулу не сяду.")
		return false
	var map = server.map
	var front: int = map.pod[bay]
	var here: int = p.st.y * map.width + p.st.x
	var face := 0
	for f in range(1, 5):
		if map.use_ahead(front % map.width, front / map.width, f) == bay:
			face = f
	p.doing = Net.DOING_GOING
	if here == front and p.st.cd == 0:
		p.st.dir = Net.DIR_NONE
		_sit(p, bay, false)
		return true
	if server.tick - p.bot_plan_tick >= PLAN_TICKS or here != p.bot_from or p.bot_task != -3:
		p.bot_plan_tick = server.tick
		p.bot_from = here
		p.bot_task = -3
		var r: Array = server.stations._route(here, {front: face})
		p.bot_step = int(r[0])
		p.bot_goal = int(r[1])
		if p.bot_goal < 0:
			p.pod_call = -1
			server.chat.bot_log(p, "не пройти к капсуле.")
			return false
	if p.bot_step == -1 and p.st.cd == 0:
		p.st.dir = Net.DIR_NONE
		server.movement.climb(p, true)
		p.bot_plan_tick = -1000
	elif p.bot_step > 0:
		p.st.dir = Net.DIR_NONE if server.movement._would_vent(p.st.x, p.st.y, p.bot_step) else p.bot_step
	return true


# ---------------------------------------------------------------- what clients are told

func _tell(p: Player, text: String) -> void:
	if not p.bot:
		server.chat.tell(p, text)


func packet() -> PackedByteArray:
	var out := PackedByteArray([Net.S_POD, mini(bays.size(), 255)])
	for bay: int in bays.keys():
		var b: Dictionary = bays[bay]
		var st: int = b["state"]
		var secs := 0
		if st == Net.POD_WAITING or (st == Net.POD_STUCK and int(b["go"]) >= 0):
			secs = ceili(float(int(b["go"]) - server.tick) / Net.TICK_HZ)
		elif st == Net.POD_HOME or st == Net.POD_MENDING:
			secs = ceili(float(int(b["until"]) - server.tick) / Net.TICK_HZ)
		var o := out.size()
		out.resize(o + 6)
		out.encode_u16(o, bay & 0xFFFF)
		out[o + 2] = st
		out[o + 3] = clampi(secs, 0, 255)
		out.encode_u16(o + 4, int(b["stuck"]) & 0xFFFF if st == Net.POD_STUCK else 0xFFFF)
		var riders: Array = b["riders"]
		out.append(riders.size())
		for q: Player in riders:
			out.append(q.slot & 0xFF)
			out.append(q.slot >> 8)
	return out
