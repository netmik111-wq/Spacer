extends RefCounted
## The ship's machines and hull: power, breakdowns (bridge consoles, the engine,
## the air plant, doors and their emergency shutters), the airlock pumps, holes
## in the hull, and doors opening and shutting.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Doors := preload("res://src/shared/doors.gd")
const Mover := preload("res://src/shared/mover.gd")
const Player := preload("res://src/server/player.gd")
const Air := preload("res://src/server/air.gd")

const PUMP_OUT := 1
const PUMP_IN := 2
const PUMP_CLOSE := 0.05               # a chamber this close to the docked ship's pressure needs no pumping
const PUMP_PER_STEP := 0.02            # air moved per chamber cell per air step (two ticks): about 5 s for a full chamber

var server: GameServer
var pump_goal := {}                    # (v73) pump cell -> the chamber air it stops at (0..1)
var cycles := {}                     # (v69) airlock pump cell -> [the door pressed, the tick it was pressed] (see call_lock)
var vents_on := true                 # (v69) the room vents (tests switch them off)
var panes_down := {}                 # (v91) window cell -> true: its shutter is down (see update_panes)
var panes_on := true                 # (v91) window shutters work (tests that want a window's hole left open switch them off)
var _pane_torn := {}                 # (v91) window cell -> the tick a hole was torn in it
var _pane_sent := {}                 # (v91) window cell -> the hull state clients were last told (see pane_state)
const PANE_SHUT_TICKS := 20          # (v91, the author's W1b) a broken window's shutter shuts 1 s after the hole
const CYCLE_SECONDS := 40            # a press gives up after this long
const CYCLE_OPEN_TICKS := 60         # the door it opens stays open at least this long (3 s)
const VENT_PER_STEP := 0.012         # (v69) air a room's vent blows into it per air step: as an air plant does
const VENT_UNTIL := 0.95             # it tops a room up to this share of normal pressure


func setup(p_server: GameServer) -> void:
	server = p_server
	cycles = {}


func at_console(p: Player, cells: Dictionary) -> bool:
	## Does this player stand facing a working console of that kind?
	if p.cond != Net.COND_OK or p.concussed > 0 and not p.bot:
		return false                         # (v70) concussed, a person cannot make sense of a console
	var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	return ahead >= 0 and cells.has(ahead) and not server.ship.broken.has(ahead) and server.power.at(ahead)


func power_changed() -> void:
	## Looks whether the power has gone or come back since clients were last told,
	## and does what goes with it. Called every tick and after anything that changes it.
	var on := server.powered()
	var backup: bool = server.power.backup_on()
	if on == server.ship.power_told and backup == server.ship.backup_told:
		return
	var was: bool = server.ship.power_told
	server.ship.power_told = on
	server.ship.backup_told = backup
	server.doors.manual = not on
	server.replication.sight_changed()
	server.to_all(server.ship.power_packet())
	if on == was:
		if backup:
			server.chat.say("Корабль обесточен. Резервный СМЭС держит мостик: свет и пульты там работают.")
		return
	if backup:
		server.chat.say("Корабль обесточен. Резервный СМЭС держит мостик: свет и пульты там работают.")
	if on:
		server.chat.say("Питание восстановлено: системы корабля снова работают.")
		return
	# without power the ship stops where it is and a jump being charged is lost
	if server.ship.moving:
		server.ship.moving = false
		server.ship.dest = server.ship.pos
		server.to_all(server.ship.helm_packet(server.tick))
	if server.ship.jump_to != Net.NO_SECTOR:
		server.ship.jump_to = Net.NO_SECTOR
		server.navigation.tell_nav()
		server.chat.say("Прыжок сорван.")


func power_glitch() -> bool:
	## The power fails for a few seconds and comes back by itself.
	## (v61, my V7 pick) It is the engine stalling: the SMES carries the ship through it if it can.
	if not server.power.engine_running():
		return false
	server.ship.power_out_until = server.tick + server.rng.randi_range(8, 15) * Net.TICK_HZ
	server.chat.say("Сбой питания: двигатель заглох на несколько секунд, корабль держится на СМЭС." if server.power.carrying()
		else "Сбой питания: все системы стоят.")
	power_changed()
	return true


func _door_free(d: int) -> bool:
	## Nobody stands in this doorway.
	for p: Player in server.players:
		if p != null and server.map.door_at(p.st.x, p.st.y) == d:
			return false
		if p != null and (p.st.ox != 0 or p.st.oy != 0):
			for c: Vector2i in Mover.body_tiles(p.st):      # (v78) half in it counts too
				if server.map.door_at(c.x, c.y) == d:
					return false
	return true


func _count(flags: PackedByteArray) -> int:
	var n := 0
	for v in flags:
		n += v
	return n


func _close(cell: int, near: int) -> bool:
	## (v68) Is `cell` within KNOCK_REACH of `near`, on its deck (near < 0: anywhere)?
	if near < 0:
		return true
	var map := server.map
	return map.deck_of_cell(cell) == map.deck_of_cell(near) \
		and absi(cell % map.width - near % map.width) + absi(cell / map.width - near / map.width) <= KNOCK_REACH


func _door_cell(d: int) -> int:
	var at: Vector2i = server.map.doors[d]
	return at.y * server.map.width + at.x


func jam_door(near: int = -1) -> bool:
	## A door slides open and sticks there: air passes freely until somebody mends it.
	## (v68) `near`: only a door close to that cell (a hit that shook it).
	if not can_break("door"):
		return false
	var choice := PackedInt32Array()
	for d in server.map.other_first_door:
		if server.doors.jammed[d] == 0 and server.doors.faulty[d] == 0 and _close(_door_cell(d), near):
			choice.append(d)
	if choice.is_empty():
		return false
	var d := choice[server.rng.randi_range(0, choice.size() - 1)]
	server.doors.jammed[d] = 1
	server.doors.locked[d] = 0
	if server.doors.ready[d] == Doors.CLOSED:
		server.doors.ready[d] = server.tick
	server.air.wake()
	server.chat.say("Одну из дверей заклинило в открытом положении.")
	return true


func fault_shutter(near: int = -1) -> bool:
	## An emergency shutter stops working by itself. Half the time it also
	## drops for no reason; otherwise it will simply not be there when needed.
	if not can_break("shutter"):
		return false
	var choice := PackedInt32Array()
	for d in server.map.other_first_door:
		if server.doors.jammed[d] == 0 and server.doors.faulty[d] == 0 and _close(_door_cell(d), near):
			choice.append(d)
	if choice.is_empty():
		return false
	var d := choice[server.rng.randi_range(0, choice.size() - 1)]
	server.doors.faulty[d] = 1
	if server.rng.randf() < 0.5 and _door_free(d):
		server.doors.locked[d] = 1
		server.door_hold[d] = mini(server.door_hold[d], server.tick)
	server.chat.say("Неисправность аварийного шлюза на одной из дверей.")
	return true


func _any_broken(cells: Dictionary) -> bool:
	for cell: int in cells.keys():
		if server.ship.broken.has(cell):
			return true
	return false


func can_break(what: String) -> bool:
	## Can this kind of trouble happen now? Things that stand between the crew
	## and an escape break one at a time: while a bridge console is out, the
	## engine holds, and the other way round. Doors go wrong two at a time at most.
	var way_out_hurt := _any_broken(server.map.chart) or _any_broken(server.map.helm) or _any_broken(server.map.engine)
	match what:
		"console":
			return not way_out_hurt and not (server.map.chart.is_empty() and server.map.helm.is_empty())
		"engine":
			return not way_out_hurt and not server.map.engine.is_empty()
		"air_plant":
			return not server.map.air_plant.is_empty() and not _any_broken(server.map.air_plant)
		"door":
			return _count(server.doors.jammed) < 2 and _count(server.doors.jammed) + _count(server.doors.faulty) < server.doors.ready.size()
		"shutter":
			return _count(server.doors.faulty) < 2 and _count(server.doors.jammed) + _count(server.doors.faulty) < server.doors.ready.size()
		"power":
			return server.power.engine_running()
	return false


func break_engine() -> bool:
	if not can_break("engine"):
		return false
	var cells: Array = server.map.engine.keys()
	var cell: int = cells[server.rng.randi_range(0, cells.size() - 1)]
	server.ship.broken[cell] = true
	server.to_all(server.ship.devices_packet())
	if server.power.carrying():
		server.chat.say("Отказ двигателя: корабль идёт на СМЭС, заряда хватит примерно на %s. Почините двигатель на нижней палубе, пока СМЭС не сел." % server.power._time(server.power.seconds_left_at(server.power.draw())))
	else:
		server.chat.say("Отказ двигателя: корабль обесточен, все системы стоят, двери открываются только вручную. Двигатель на нижней палубе.")
	power_changed()
	return true


func break_air_plant(near: int = -1) -> bool:
	if not can_break("air_plant"):
		return false
	var cells: Array = server.map.air_plant.keys().filter(func(c: int) -> bool: return _close(c, near))
	if cells.is_empty():
		return false
	var cell: int = cells[server.rng.randi_range(0, cells.size() - 1)]
	server.ship.broken[cell] = true
	server.to_all(server.ship.devices_packet())
	server.chat.say("Воздушная установка остановилась. Она на нижней палубе.")
	return true


func lock_air(pump: int) -> float:
	## The air in the chamber of an airlock, 0..1.
	var cells: PackedInt32Array = server.map.lock_pump[pump]["chamber"]
	var sum := 0.0
	for c in cells:
		sum += server.air.air[c]
	return sum / cells.size()


func lock_shut(pump: int) -> bool:
	var lock: Dictionary = server.map.lock_pump[pump]
	return server.doors.is_shut(int(lock["inner"])) and server.doors.is_shut(int(lock["outer"]))


func docked_air(pump: int) -> float:
	## The air of the ship docked at that airlock's outer door (0..1), or -1 when
	## there is none or it holds next to no air (v54, the author's note: a chamber
	## in vacuum kept the door to a docked ship with air shut, and the pump only
	## knew the corridor and space).
	var beyond := server.map.lock_beyond(pump)
	if beyond < 0 or server.air.air[beyond] < Net.SHUTTER_LIFT:
		return -1.0
	return server.air.air[beyond]


func _pump_way(pump: int) -> int:
	## Which way the pump must work: towards the docked ship's pressure when one
	## with air is docked, else out to open on space or in to open on the ship.
	## (v73, the author's note: stuck in the airlock beside a pirate ship) a chamber
	## already at the docked ship's pressure is brought back to the ship's own.
	var docked := docked_air(pump)
	var have := lock_air(pump)
	if docked >= 0.0:
		if absf(have - docked) < PUMP_CLOSE:
			return _way_to(pump, inside_air(pump))
		return PUMP_OUT if have > docked else PUMP_IN
	return PUMP_OUT if have > 0.5 else PUMP_IN


func inside_air(pump: int) -> float:
	## (v73) The air on our own side of the airlock's inner door (0..1).
	var c := server.map.lock_inside(pump)
	return server.air.air[c] if c >= 0 else 1.0


func _way_to(pump: int, goal: float) -> int:
	var have := lock_air(pump)
	if absf(have - goal) < PUMP_CLOSE:
		return 0
	return PUMP_OUT if have > goal else PUMP_IN


func _default_goal(pump: int, way: int) -> float:
	## Where a pump started without a goal stops: the docked ship's pressure (our
	## own, when the chamber is at it already), else empty when letting out and
	## full when filling.
	var docked := docked_air(pump)
	if docked >= 0.0:
		if absf(lock_air(pump) - docked) < PUMP_CLOSE:
			return inside_air(pump)
		return docked
	return 0.0 if way == PUMP_OUT else 1.0


func toggle_pump(p: Player, cell: int, way: int = 0, goal: float = -1.0) -> void:
	## The "use" key on a pump: start it the way the chamber needs (or `way`, to
	## `goal`), or stop it.
	if server.ship.pumps.has(cell):
		server.ship.pumps.erase(cell)
		pump_goal.erase(cell)
	elif not server.powered() or not lock_shut(cell):
		return
	else:
		if way == 0:
			way = _pump_way(cell)
		if way == 0 or (way == PUMP_IN and server.ship.store_air <= 0.0):
			return
		server.ship.pumps[cell] = way
		pump_goal[cell] = goal if goal >= 0.0 else _default_goal(cell, way)
	server.chat.sound(Net.SOUND_HISS, cell % server.map.width, cell / server.map.width, p.slot)
	server.to_all(server.ship.devices_packet())


func run_pumps() -> void:
	if server.ship.pumps.is_empty():
		return
	var done := []
	for cell: int in server.ship.pumps.keys():
		if not server.powered() or not lock_shut(cell):
			done.append(cell)
			continue
		var cells: PackedInt32Array = server.map.lock_pump[cell]["chamber"]
		var out: bool = server.ship.pumps[cell] == PUMP_OUT
		var goal: float = pump_goal.get(cell, _default_goal(cell, server.ship.pumps[cell]))
		var left := 0.0
		for c in cells:
			if out:
				var take := clampf(server.air.air[c] - goal, 0.0, PUMP_PER_STEP)
				server.air.air[c] -= take
				server.ship.store_air = minf(server.ship.store_air + take, Net.STORE_AIR_FULL)   # what does not fit is let out
				left = maxf(left, server.air.air[c] - goal)
			else:
				var give := minf(clampf(goal - server.air.air[c], 0.0, PUMP_PER_STEP), server.ship.store_air)
				server.air.air[c] += give
				server.ship.store_air -= give
				left = maxf(left, goal - server.air.air[c])
		server.air.wake()
		if left < 0.001 or (not out and server.ship.store_air <= 0.0):
			done.append(cell)
	for cell: int in done:
		server.ship.pumps.erase(cell)
		pump_goal.erase(cell)
	if not done.is_empty():
		server.to_all(server.ship.devices_packet())


func feed_air() -> void:
	## Every working air plant blows a little air into the room it faces, for as
	## long as the ship has air in store for it. (v68) Not with its breaker off.
	if not server.powered() or not server.power.air_on():
		return
	for cell: int in server.map.air_plant.keys():
		if not server.ship.broken.has(cell) and server.ship.store_air > 0.0:
			server.ship.store_air = maxf(server.ship.store_air - server.air.feed(server.map.air_plant[cell], minf(Air.PLANT_PER_STEP, server.ship.store_air)), 0.0)
	_vents()


func _vents() -> void:
	## (v69, the author's idea: "a vent in every room, so we get the air back; bots
	## collapse without it") Each room of our ship has a vent (ShipMap.vents) fed by
	## the air plant from the ship's store: it tops the room up toward normal pressure.
	## It needs the plant whole, and it shuts in a room with a hole in the hull (it
	## would only blow the store into space).
	if not vents_on or server.ship.store_air <= 0.0:
		return
	var plant_ok := false
	for cell: int in server.map.air_plant.keys():
		plant_ok = plant_ok or not server.ship.broken.has(cell)
	if not plant_ok:
		return
	var map := server.map
	for k in map.vents.size():
		var room: PackedInt32Array = map.rooms[map.room_of[map.vents[k]]]
		var sum := 0.0
		for c in room:
			sum += server.air.air[c]
		if sum / room.size() >= VENT_UNTIL or _holed(room):
			continue
		server.ship.store_air = maxf(server.ship.store_air - server.air.feed(map.vents[k], minf(VENT_PER_STEP, server.ship.store_air)), 0.0)
		if server.ship.store_air <= 0.0:
			return


func _holed(room: PackedInt32Array) -> bool:
	## Is there a hole in the hull next to this room (or a door of it open to space)?
	var w := server.map.width
	for c in room:
		for o: int in [1, -1, w, -w]:
			if server.air.holes.has(c + o):
				return true
	return false


func break_console(near: int = -1) -> bool:
	## A bridge console goes out of order. One at a time: while one is broken,
	## the other stays whole, so the crew always has one way out left.
	if not can_break("console"):
		return false
	var all: Array = (server.map.chart.keys() + server.map.helm.keys()).filter(func(c: int) -> bool: return _close(c, near))
	if all.is_empty():
		return false
	var cell: int = all[server.rng.randi_range(0, all.size() - 1)]
	server.ship.broken[cell] = true
	server.to_all(server.ship.devices_packet())
	server.chat.say("Замыкание на мостике: %s не работает." % server.map.device_name(cell))
	return true


# (v68, the author's E1: "random breaks should happen in fights; they should not
# come from nothing but create more danger") a pirate hit on the hull may break a
# machine near where it lands, instead of the eventer breaking them out of nowhere
const KNOCK_REACH := 6               # cells (along the grid) from the hit
const KNOCK_CHANCE := 0.3            # the chance a hit breaks something near it...
const KNOCK_HEAVY := 0.45            # ... a heavy one
var knock_chance := -1.0             # (tests set it: 0 = never, 1 = always)


func knock_on(cell: int, heavy: bool) -> String:
	## A hit landed at `cell`: by lot something near it breaks. What broke, or "".
	var chance := knock_chance if knock_chance >= 0.0 else (KNOCK_HEAVY if heavy else KNOCK_CHANCE)
	if cell < 0 or server.rng.randf() >= chance:
		return ""
	var kinds: Array = ["door", "shutter", "air_plant", "console", "power"]
	for i in range(kinds.size() - 1, 0, -1):
		var j := server.rng.randi_range(0, i)
		var t: String = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	for k: String in kinds:
		match k:
			"door":
				if jam_door(cell):
					return k
			"shutter":
				if fault_shutter(cell):
					return k
			"air_plant":
				if break_air_plant(cell):
					return k
			"console":
				if break_console(cell):
					return k
			"power":
				# the engine shaken: it stalls a few seconds (it breaks only from an overcharge or a hit on it)
				for e: int in server.map.engine.keys():
					if _close(e, cell) and can_break("power") and power_glitch():
						return k
	return ""


func breach(cell: int) -> bool:
	## Tears a hole in a hull cell. Returns false if there already is one.
	if not server.air.set_hole(cell, true):
		return false
	if panes_down.has(cell):
		server.air.seal(cell, true)          # (v91) the window's shutter was down already: no air is lost
	server.replication.hull_record(cell, pane_state(cell))
	server.chat.alarm("Разгерметизация! Пробоина в обшивке.")
	if server.map.hull.has(cell):
		server.crew.hull_hit(Net.HULL_PER_HOLE)
	return true


func breach_near(x: int, y: int) -> bool:
	## A hole in the whole hull cell closest to the given place, on the same deck.
	var best := -1
	var best_d := 1 << 30
	for cell in server.map.hull:
		if server.air.holes.has(cell) or server.map.deck_of_cell(cell) != server.map.deck_of(y):
			continue
		var d := absi(cell % server.map.width - x) + absi(cell / server.map.width - y)
		if d < best_d or (d == best_d and server.rng.randf() < 0.5):
			best_d = d
			best = cell
	return best >= 0 and breach(best)


func breach_random() -> bool:
	var whole := PackedInt32Array()
	for cell in server.map.hull:
		if not server.air.holes.has(cell):
			whole.append(cell)
	if whole.is_empty():
		return false
	var cell := whole[server.rng.randi_range(0, whole.size() - 1)]
	server.combat.jolt(Net.JOLT_HEAVY, 0, Vector2(cell % server.map.width, cell / server.map.width))   # (v56) a meteor strikes
	return breach(cell)


func seal_all() -> void:
	if server.air.holes.is_empty():
		return
	for cell: int in server.air.holes.keys():
		server.air.set_hole(cell, false)
		server.replication.hull_record(cell, pane_state(cell))
	server.chat.say("Пробоины заделаны.")


func update_panes() -> void:
	## (v91, the author's W1) Window shutters: every window of ours has one. At red alert they all come
	## down; a hole torn in a window lets the air out for a moment, then its shutter shuts over it
	## (PANE_SHUT_TICKS) and the room keeps its air until the hole is mended, when it lifts again. A
	## shutter down stops sight and light as a wall does. They need power, as the doors' shutters do:
	## without it nothing drops and nothing lifts.
	var red := server.stations.alert == Net.ALERT_RED
	var powered := server.powered() and panes_on
	var changed := false
	for c: int in server.map.panes:
		if not server.fleet.mine(c):
			continue                         # (another ship of the fleet's, by its own alert and power)
		var hole := server.air.holes.has(c)
		if not hole:
			_pane_torn.erase(c)
		elif not _pane_torn.has(c):
			_pane_torn[c] = server.tick
		var down := panes_down.has(c)
		if powered:
			down = red or (hole and server.tick - int(_pane_torn[c]) >= PANE_SHUT_TICKS)
		if down != panes_down.has(c):
			changed = true
			if down:
				panes_down[c] = true
			else:
				panes_down.erase(c)
			server.map.set_pane(c, down)
			if down and hole and not red:
				server.chat.say("Ставень закрыл разбитое окно: отсек держит воздух.")
		if hole:
			server.air.seal(c, down)
		var state := pane_state(c)
		if state != int(_pane_sent.get(c, 0)):
			_pane_sent[c] = state
			server.replication.hull_record(c, state)
	if changed:
		server.replication.lines.clear()     # (the lines of sight remember walls: a shutter is one now)
		server.replication.sight_changed()


func pane_state(cell: int) -> int:
	## A hull cell as clients are told it: 0 whole, 1 a hole, (v91) 2 a hole behind a window's shutter,
	## 3 a window's shutter down.
	var down := panes_down.has(cell)
	if server.air.holes.has(cell):
		return 2 if down else 1
	return 3 if down else 0


func update_shutters() -> void:
	## Emergency shutters: every door has one. It drops by itself when the
	## pressure on the two sides of the door differs too much, and lifts when
	## the difference is gone. It needs power: without it nothing drops and
	## nothing lifts. A faulty one does neither, and a jammed door has nothing to shut.
	if not server.powered():
		return
	for d in server.map.other_first_door:                 # (the other ship's doors have no power)
		if not server.fleet.mine(server.map.doors[d].y * server.map.width + server.map.doors[d].x):
			continue                                         # (v85) another ship of the fleet's, by its own power
		var a := server.map.door_sides[d * 2]
		var b := server.map.door_sides[d * 2 + 1]
		if server.doors.faulty[d] == 1 or server.doors.jammed[d] == 1:
			continue
		if (a < 0 or b < 0) and server.map.door_vent[d] == 0:
			continue
		# the outer door of an airlock has space on one side: no air there
		var gap := absf((server.air.air[a] if a >= 0 else 0.0) - (server.air.air[b] if b >= 0 else 0.0))
		if server.doors.locked[d] == 1:
			if gap < Net.SHUTTER_LIFT:
				server.doors.locked[d] = 0
		elif gap >= Net.SHUTTER_DROP and server.tick >= server.forced_until[d]:
			server.doors.locked[d] = 1
			server.door_hold[d] = mini(server.door_hold[d], server.tick)    # an open door shuts at once, unless somebody stands in it


func update_doors() -> void:
	# doors pushed this tick stay open for a while
	for d in server.doors.bumped:
		if server.door_sent[d] == Doors.CLOSED and server.door_hold[d] < server.tick and server.map.door_here(d):
			server.chat.sound(Net.SOUND_DOOR, server.map.doors[d].x, server.map.doors[d].y)
		server.door_hold[d] = server.tick + Doors.HOLD_TICKS
	server.doors.bumped.clear()
	# a door does not close on somebody standing in it
	for p: Player in server.players:
		if p != null:
			_hold_under(server.map.door_at(p.st.x, p.st.y))
			if p.st.ox != 0 or p.st.oy != 0:
				for c: Vector2i in Mover.body_tiles(p.st):    # (v78) nor on a body half in its doorway
					_hold_under(server.map.door_at(c.x, c.y))
	for d in server.doors.ready.size():
		if server.doors.forced[d] == 1 and server.tick >= server.forced_until[d] and server.doors.ready[d] == Doors.CLOSED:
			server.doors.forced[d] = 0              # the lock holds again once the door has shut
		if server.doors.ready[d] == server.tick:
			server.air.wake()                       # it has just finished opening: air may pass now
			server.replication.sight_changed()      # and sight
		if server.doors.ready[d] != Doors.CLOSED and server.tick >= server.doors.ready[d] and server.tick >= server.door_hold[d] and server.doors.jammed[d] == 0:
			server.doors.ready[d] = Doors.CLOSED
		if server.doors.ready[d] != server.door_sent[d] or server.doors.flags(d) != server.flags_sent[d]:
			if server.doors.ready[d] != server.door_sent[d]:
				server.air.wake()
			server.door_sent[d] = server.doors.ready[d]
			server.flags_sent[d] = server.doors.flags(d)
			server.replication.door_record(d)


func _hold_under(d: int) -> void:
	if d >= 0 and server.door_hold[d] < server.tick + Net.MOVE_TICKS + 2:
		server.door_hold[d] = server.tick + Net.MOVE_TICKS + 2


# ------------------------------------------------- (v66) getting past an airlock

func lock_door(door: int) -> bool:
	## Is this a door of one of our airlocks?
	return door >= 0 and door < server.doors.partner.size() and server.doors.partner[door] >= 0


func lock_bars(door: int) -> bool:
	## A shut airlock door that walking into does not open now: its shutter is
	## down (the chamber's pressure differs from the other side) or the other door
	## of the chamber is not shut.
	var doors := server.doors
	return lock_door(door) and doors.is_shut(door) and (doors.locked[door] == 1 or doors.held_by_partner(door))


func call_lock(p: Player, door: int) -> bool:
	## (v66, the author's answer to L1) The button by each airlock door, on both
	## sides. (v69, the author's idea "buttons for the room where we go to space")
	## A press does the whole trip: the chamber's other door shuts, the pump empties
	## the chamber into the ship's air store or fills it from there (or matches a
	## docked ship), and the door pressed opens by itself (see run_cycles). True if
	## the trip has begun.
	var pump := _pump_of(door)
	if pump < 0 or not lock_bars(door):
		return false
	var doors := server.doors
	var other: int = doors.partner[door]
	if doors.held_by_partner(door):
		if doors.jammed[other] == 1 or doors.forced[other] == 1 or not server.powered():
			return false                     # stuck open: only forcing by hand gets past
	elif not _pump_helps(pump, door):
		return false
	if not cycles.has(pump) and p != null and p.peer != null:
		server.chat.tell(p, "Шлюз: %s." % ("выход наружу" if door == int(server.map.lock_pump[pump]["outer"]) else "вход в корабль"))
	cycles[pump] = [door, server.tick]
	if not doors.held_by_partner(door) and not server.ship.pumps.has(pump):
		var inner := door == int(server.map.lock_pump[pump]["inner"])
		toggle_pump(p, pump, _way_through(pump, door), inside_air(pump) if inner and docked_air(pump) >= 0.0 else -1.0)
	return true


func run_cycles() -> void:
	## (v69) Airlock trips under way (call_lock): one step each tick.
	if cycles.is_empty():
		return
	var doors := server.doors
	for pump: int in cycles.keys():
		if not server.fleet.mine(pump):
			continue                         # (v85) another ship of the fleet: its own turn (Fleet.each)
		var door: int = cycles[pump][0]
		var other: int = doors.partner[door]
		if server.tick - int(cycles[pump][1]) > CYCLE_SECONDS * Net.TICK_HZ or not server.powered():
			cycles.erase(pump)
			continue
		if not doors.is_shut(other):
			if doors.jammed[other] == 1 or doors.forced[other] == 1:
				cycles.erase(pump)
				continue
			server.door_hold[other] = mini(server.door_hold[other], server.tick)   # it shuts once its doorway is clear
			continue
		if doors.locked[door] == 1:
			if not server.ship.pumps.has(pump):
				if _pump_helps(pump, door):
					server.ship.pumps[pump] = _way_through(pump, door)
					server.to_all(server.ship.devices_packet())
				elif server.tick - int(cycles[pump][1]) > Net.TICK_HZ:
					cycles.erase(pump)           # the pump cannot do it (no air in store): forcing by hand is left
			continue
		if doors.is_shut(door) and doors.blast[door] == 0:
			doors.ready[door] = server.tick + Doors.OPEN_TICKS
			server.door_hold[door] = server.tick + Doors.OPEN_TICKS + CYCLE_OPEN_TICKS
			server.chat.sound(Net.SOUND_DOOR, server.map.doors[door].x, server.map.doors[door].y)
		cycles.erase(pump)


func get_past(p: Player, door: int, ours: bool) -> bool:
	## (v66, the author's note "feels like bots cannot do it") One tick of a bot or a
	## pirate whose way leads through an airlock door that will not open
	## (`lock_bars`). Once it stands before the door, a bot presses the door's
	## button (`call_lock`) and waits for the pump; when the pump cannot help (no
	## power, no air in the reserve) it forces the door by hand (Repairs: the lock,
	## then the shutter). It waits while the chamber's other door is merely open:
	## that one shuts by itself. `ours`: one of our bots (it never overrides the
	## lock while the other door is stuck open); pirates only force.
	## False: nothing to do here yet (it walks on to the door).
	var doors := server.doors
	var at: Vector2i = server.map.doors[door]
	var facing := 0
	for d in range(1, 5):
		if p.st.x + Net.DX[d] == at.x and p.st.y + Net.DY[d] == at.y:
			facing = d
	if facing == 0:
		return false
	var other: int = doors.partner[door]
	p.using = false
	p.st.dir = Net.DIR_NONE
	if p.st.facing != facing:
		p.st.facing = facing
		p.self_dirty = true
	if doors.held_by_partner(door) and (ours or doors.jammed[other] == 0 and doors.forced[other] == 0):
		# the other door is in use and shuts after it; or it is stuck open, and a
		# bot will not override the lock and let the ship's air out (a pirate will)
		if doors.jammed[other] == 1 or doors.forced[other] == 1:
			p.doing = Net.DOING_NO_WAY
		return true
	p.doing = Net.DOING_GOING
	if ours and call_lock(p, door):
		return true
	p.using = true
	return true


func _pump_helps(pump: int, door: int) -> bool:
	## Can the pump clear the way through that door now (rather than forcing it)?
	if server.doors.locked[door] == 0 or not server.powered() or server.ship.broken.has(pump) or not lock_shut(pump) \
			or not server.map.on_ship(server.map.fitting_front(pump)):
		return false
	var way := _way_through(pump, door)
	return way != 0 and (way == PUMP_OUT or server.ship.store_air > 0.0)


func _way_through(pump: int, door: int) -> int:
	## Which way to pump to open that door: in for the inner one; out for the outer
	## one, or toward the pressure of a ship docked there.
	if door == int(server.map.lock_pump[pump]["inner"]):
		# (v73) docked, the chamber may hold the other ship's air: back to our own
		return _way_to(pump, inside_air(pump)) if docked_air(pump) >= 0.0 else PUMP_IN
	return _way_to(pump, docked_air(pump)) if docked_air(pump) >= 0.0 else PUMP_OUT


func _pump_of(door: int) -> int:
	for c: int in server.map.lock_pump.keys():
		var lock: Dictionary = server.map.lock_pump[c]
		if int(lock["inner"]) == door or int(lock["outer"]) == door:
			return c
	return -1
