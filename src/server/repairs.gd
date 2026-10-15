extends RefCounted
## The "use" key on what a character faces: mending holes, machines and doors,
## forcing an emergency shutter or an airlock's lock, breaking a door's lock,
## filling a suit's tank, starting an airlock pump. A press also picks things
## up and takes ladders.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Doors := preload("res://src/shared/doors.gd")
const Player := preload("res://src/server/player.gd")
const Vitals := preload("res://src/server/vitals.gd")

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func update(p: Player) -> void:
	## Holding "use" on what the character faces: a hole, a broken machine or a
	## door that has gone wrong is mended, an emergency shutter is forced up, an
	## oxygen station fills the tank.
	if server.combat.update_treatment(p):
		return
	if not p.using or p.cond != Net.COND_OK or p.st.cd > 0 or p.st.dir != Net.DIR_NONE:
		p.work = 0
		return
	var cell := server.map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
	var door := server.map.door_of[cell] if cell >= 0 else -1
	# a spare part makes mending a machine or a door quick; without one it can still be done, slowly
	# and the skill of the one at work makes it quicker, down to half the time
	var knack := 1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)
	var mend_ticks := roundi((Net.REPAIR_TICKS if p.count(Net.ITEM_PART) > 0 else Net.REPAIR_TICKS * Net.NO_PART_SLOWER) * knack)
	if cell >= 0 and server.air.holes.has(cell):
		if p.count(Net.ITEM_PATCH) == 0:
			p.work = 0                       # nothing to close it with
		elif _work_done(p, cell, roundi(Net.REPAIR_TICKS * knack)):
			p.train(Net.SKILL_REPAIR)
			p.remove(Net.ITEM_PATCH)
			server.air.set_hole(cell, false)
			server.replication.hull_record(cell, 0)
			server.chat.say("%s заделывает пробоину. Воздух сам не вернётся: его дадут соседние отсеки." % p.name)
	elif cell >= 0 and server.ship.broken.has(cell):
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			p.remove(Net.ITEM_PART)
			server.ship.broken.erase(cell)
			server.to_all(server.ship.devices_packet())
			server.chat.say("%s заканчивает ремонт: %s снова работает." % [p.name, server.map.device_name(cell)])
			server.systems.power_changed()
	elif door >= 0 and server.doors.jammed[door] == 1:
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			p.remove(Net.ITEM_PART)
			server.doors.jammed[door] = 0
			server.door_hold[door] = server.tick          # it may shut again as soon as the doorway is clear
			server.chat.say("%s чинит заклинившую дверь." % p.name)
	elif door >= 0 and server.doors.faulty[door] == 1:
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			p.remove(Net.ITEM_PART)
			server.doors.faulty[door] = 0           # from here on the pressure decides again
			server.chat.say("%s чинит аварийный шлюз." % p.name)
	elif door >= 0 and server.doors.is_shut(door) and server.doors.held_by_partner(door):
		# the other door of the airlock is open (or stuck open): the lock is overridden by hand
		if _work_done(p, cell, Net.FORCE_TICKS):
			server.doors.forced[door] = 1
			server.doors.locked[door] = 0
			server.forced_until[door] = server.tick + Net.FORCED_OPEN_TICKS
			server.chat.say("%s вручную снимает блокировку двери шлюза." % p.name)
	elif door >= 0 and server.doors.is_sealed(door):
		if _work_done(p, cell, Net.FORCE_TICKS):
			server.doors.locked[door] = 0
			server.forced_until[door] = server.tick + Net.FORCED_OPEN_TICKS
			server.chat.say("%s вручную поднимает аварийный шлюз." % p.name)
	elif door >= 0 and server.doors.barred(door, server.map.door_access[door], p.st.access):
		# no access: the lock can still be broken, slowly and for all to hear
		if _work_done(p, cell, Net.HACK_TICKS):
			server.doors.ready[door] = server.tick + Doors.OPEN_TICKS
			server.door_hold[door] = server.tick + Doors.OPEN_TICKS + Doors.HOLD_TICKS
			server.chat.sound(Net.SOUND_BLOW, cell % server.map.width, cell / server.map.width, p.slot)
			server.chat.say("%s взламывает замок двери: %s." % [p.name, Net.ACCESS_NAMES.get(server.map.door_access[door], "отсек")])
	elif cell >= 0 and server.map.oxygen.has(cell) and server.powered() and p.has_suit():
		p.work = 0
		p.tank = minf(p.tank + Net.TICK_SEC / Vitals.REFILL_SECONDS, 1.0)
	else:
		p.work = 0


func _work_done(p: Player, cell: int, ticks: int) -> bool:
	## One more tick of work on the thing in that cell. True when the job is finished.
	if p.work_cell != cell or p.work_total != ticks:
		p.work_cell = cell
		p.work_total = ticks
		p.work = 0
	p.work += 1
	if p.work < ticks:
		return false
	p.work = 0
	return true


func usable_ahead(p: Player) -> bool:
	## Is there something in front of the character that the "use" key works on
	## (or that it opens a screen for)? The same things, in the same order, as
	## GameClient.use_target finds before somebody lying, things on the floor and ladders.
	var map := server.map
	var cell := map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
	if cell < 0:
		return false
	if server.air.holes.has(cell) or server.ship.broken.has(cell) or map.oxygen.has(cell) or map.chart.has(cell) \
			or map.helm.has(cell) or map.engine.has(cell) or map.air_plant.has(cell) or map.locker.has(cell) \
			or map.lock_pump.has(cell) or map.gun_console.has(cell) or map.guns.has(cell) or map.intercom.has(cell) or map.holo.has(cell) \
			or map.drone_console.has(cell):
		return true
	var door := map.door_of[cell]
	return door >= 0 and ((server.doors.is_shut(door) and server.doors.held_by_partner(door)) or server.doors.jammed[door] == 1
		or server.doors.faulty[door] == 1 or server.doors.is_sealed(door) or server.doors.barred(door, map.door_access[door], p.st.access))


func _lying_near(p: Player) -> bool:
	## Is somebody lying (out cold or dead) in the cell ahead or underfoot? The
	## "use" key searches them then (the client asks for that), and takes nothing else.
	var ahead := server.map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	var here := p.st.y * server.map.width + p.st.x
	for q: Player in server.players:
		if q != null and q != p and q.cond != Net.COND_OK:
			var cell := q.st.y * server.map.width + q.st.x
			if cell == ahead or cell == here:
				return true
	return false


func press(p: Player) -> void:
	## The "use" key went down (on the tick the client pressed it). Most of what
	## it does is holding it (see update); a press itself starts or stops an
	## airlock pump, or picks up a thing lying in front or underfoot, or else
	## takes a ladder: in the order GameClient.use_target shows the player.
	if p.cond != Net.COND_OK or p.corpse:
		return
	var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	if ahead >= 0 and server.map.lock_pump.has(ahead):
		server.systems.toggle_pump(p, ahead)
	elif usable_ahead(p) or _lying_near(p):
		return
	elif not server.inventory.pick_up(p):
		server.movement.climb(p)
