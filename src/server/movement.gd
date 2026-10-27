extends RefCounted
## Walking: a character's held keys turned into steps every tick, ladders, and
## the bots that wander about.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Player := preload("res://src/server/player.gd")
const Vitals := preload("res://src/server/vitals.gd")

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func move(p: Player) -> void:
	## One tick of a character's walking: the inputs that are due, a bot's or a
	## pirate's mind, the step itself (with whoever it hauls), a ladder press
	## waiting for its tick.
	var tick := server.tick
	while not p.inputs.is_empty() and int(p.inputs[0][0]) <= tick:
		var inp: Array = p.inputs.pop_front()
		Mover.apply_input(p.st, inp[1])
		if int(inp[1]) == Mover.LIE or int(inp[1]) == Mover.HOLD:
			server.usage.note(p, "crawl" if int(inp[1]) == Mover.LIE else "hold")   # (v82)
		p.last_seq = inp[2]
		p.self_dirty = true
	if p.bot:
		bot_think(p)
	elif p.pirate or p.ally:
		server.pirates.think(p)          # (v62) our security robots fight by the same mind
	# (v78) players step a quarter of a tile at a time; bots, pirates and robots whole tiles
	p.st.fine = p.quarters and not p.bot and not p.pirate and not p.ally
	if p.st.prone and (p.bot and not server.defence.busy(p) or p.cond != Net.COND_OK):
		p.st.prone = false               # a bot that took over, or one knocked out, is not lying low any more
		                                 # ((v79) a bot hiding from pirates lies low on purpose)
		p.st.rise = 0
	var was_x := p.st.x
	var was_y := p.st.y
	# ((v91) a step onto the stairs' far end, once over, comes out on the other deck, step or none)
	if Mover.step(p.st, server.map, server.doors, tick) or p.st.x != was_x or p.st.y != was_y:
		p.self_dirty = true
		if p.st.x != was_x or p.st.y != was_y:
			p.steps += 1
			if p.steps % 2 == 0:
				server.chat.sound(Net.SOUND_STEP, p.st.x, p.st.y, p.slot)
			if p.dragging >= 0:
				server.looting.haul(p, was_x, was_y)
	if p.climb_tick >= 0 and tick >= p.climb_tick:
		p.climb_tick = -1
		server.repairs.press(p)
	p.history[tick % Player.HISTORY] = Mover.visual_pos(p.st, tick)


func mark_held() -> void:
	## (v81, the author's human wall) The tiles held this tick: nobody else walks into them.
	server.map.held.clear()
	for p: Player in server.players:
		if p != null and p.st.hold and not p.corpse:
			if p.cond != Net.COND_OK:
				p.st.hold = false
				p.self_dirty = true
				continue
			for t in Mover.body_tiles(p.st):
				server.map.held[t.y * server.map.width + t.x] = p.slot


func climb(p: Player, on_way: bool = false) -> bool:
	## The "use" key was pressed. On a ladder, with nothing else to use in front,
	## the character goes to the other deck, and takes along whoever it hauls.
	## (v89, the author's notes: bots stuck on a ladder by a door) a bot whose way goes
	## up or down the ladder (`on_way`) climbs whatever is in front of it.
	if p.cond != Net.COND_OK or p.corpse:
		return false
	var to := server.map.climb[p.st.y * server.map.width + p.st.x]
	if to < 0 or not on_way and server.repairs.usable_ahead(p):
		return false
	# Only the place changes: a key the player holds goes on being held, so the
	# client's replay of its unconfirmed inputs still matches.
	server.chat.sound(Net.SOUND_LADDER, p.st.x, p.st.y, p.slot)
	p.st.place(to % server.map.width, to / server.map.width)
	p.self_dirty = true
	p.climbs += 1
	server.chat.sound(Net.SOUND_LADDER, p.st.x, p.st.y, p.slot)
	if p.dragging >= 0:
		var body: Player = server.players[p.dragging]
		body.st.place(p.st.x, p.st.y)
		body.self_dirty = true
	return true


func bot_think(p: Player) -> void:
	server.stations.bot_breathe(p)  # (v60) its suit's supply in thin air
	if server.defence.think(p):
		return                       # (v79) armed pirates about: it runs, hides or (a guard) fights
	if server.stations.bot_think(p):
		return                       # (v55) it has an order from the captain
	var st := p.st
	var blocked := st.dir != 0 and (not server.map.walkable(st.x + Net.DX[st.dir], st.y + Net.DY[st.dir]) or _would_vent(st.x, st.y, st.dir))
	if blocked:
		st.dir = Net.DIR_NONE
	if server.tick < p.bot_until and not blocked:
		return
	if server.map.climb[st.y * server.map.width + st.x] >= 0 and server.rng.randf() < 0.3 and climb(p):
		p.bot_until = server.tick + server.rng.randi_range(4, 12)
		return
	# now and then it switches its flashlight, puts it down or picks something up
	# (which also keeps the floor busy in network tests)
	var whim := server.rng.randf()
	if st.cd == 0 and whim < 0.04:
		server.inventory.act(p)
	elif st.cd == 0 and whim < 0.06:
		server.inventory.put_down(p)
	elif st.cd == 0 and whim < 0.1:
		server.inventory.pick_up(p)
	if server.rng.randf() < 0.2 and not blocked:
		st.dir = Net.DIR_NONE
		p.bot_until = server.tick + server.rng.randi_range(10, 40)
		return
	for attempt in 6:
		var d := server.rng.randi_range(1, Net.DIRS)   # (v77) a slant too
		if server.map.walkable(st.x + Net.DX[d], st.y + Net.DY[d]) and not _would_vent(st.x, st.y, d):
			st.dir = d
			break
	p.bot_until = server.tick + server.rng.randi_range(4, 30)


func _would_vent(x: int, y: int, dir: int) -> bool:
	## True if stepping that way opens a shut door with very different pressure
	## behind it. Bots leave such doors alone, so they do not empty the ship.
	var dx: int = x + Net.DX[dir]
	var dy: int = y + Net.DY[dir]
	var d := server.map.door_at(dx, dy)
	if d < 0 or not server.doors.is_shut(d):
		return false
	var fx: int = dx + Net.DX[dir]
	var fy: int = dy + Net.DY[dir]
	if not server.map.walkable(fx, fy):
		return false
	if server.systems.lock_door(d) and server.doors.is_shut(server.doors.partner[d]):
		return false                # (v66) an airlock's door: only its own chamber fills or empties
	var here := server.air.air[y * server.map.width + x]
	if here < Vitals.BREATH_MIN:
		return false                # it is suffocating: getting out matters more
	return absf(here - server.air.air[fy * server.map.width + fx]) > 0.25
