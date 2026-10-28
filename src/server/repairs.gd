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
const Upkeep := preload("res://src/shared/upkeep.gd")

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func update(p: Player) -> void:
	## Holding "use" on what the character faces: a hole, a broken machine or a
	## door that has gone wrong is mended, an emergency shutter is forced up, an
	## oxygen station fills the tank.
	if server.combat.update_treatment(p):
		return
	if not p.bench.is_empty():
		return                               # (v58) at work at the workbench (see Workshop.update)
	if not p.using or p.cond != Net.COND_OK or p.st.cd > 0 or p.st.dir != Net.DIR_NONE:
		p.work = 0
		p.mended = -1
		return
	var bomb := server.pirates.bomb_by(p)
	if bomb >= 0:
		# (v70) a pirates' bomb in front or underfoot: held E disarms it (an engineer is quicker)
		if _work_done(p, bomb, server.pirates.defuse_ticks(p)):
			server.pirates.defuse(p, bomb)
		return
	var cell := server.map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
	var door := server.map.door_of[cell] if cell >= 0 else -1
	# a spare part makes mending a machine or a door quick; without one it can still be done, slowly
	# and the skill of the one at work makes it quicker, down to half the time
	# (v71, the author's H1) with complex repairs, only the machine's own kind of part, and a toolbox (see Upkeep)
	var knack := 1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)
	var spare := spare_for(p, cell)
	var mend_ticks := roundi(Net.REPAIR_TICKS * Upkeep.slower(server.complex_repairs, spare, p.count(Net.ITEM_TOOLBOX) > 0) * knack)
	if cell >= 0 and server.air.holes.has(cell):
		if p.count(Net.ITEM_PATCH) == 0:
			p.work = 0                       # nothing to close it with
		elif _work_done(p, cell, roundi(Net.REPAIR_TICKS * knack)):
			p.train(Net.SKILL_REPAIR)
			p.remove(Net.ITEM_PATCH)
			server.air.set_hole(cell, false)
			server.replication.hull_record(cell, server.systems.pane_state(cell))
			server.chat.say("%s заделывает пробоину. Вентиляция понемногу вернёт воздух в отсек." % p.name)
	elif server.outside.can_mend(p, cell):
		# (v61) the hull's strength mended from outside, a patch at a time
		if _work_done(p, cell, server.outside.mend_ticks(p)):
			server.outside.mended(p)
	elif cell >= 0 and server.ship.broken.has(cell):
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			_use_spare(p, spare)
			server.ship.broken.erase(cell)
			p.mended = cell
			server.to_all(server.ship.devices_packet())
			server.chat.say("%s заканчивает ремонт: %s снова работает." % [p.name, server.map.device_name(cell)])
			server.systems.power_changed()
	elif cell >= 0 and can_pour(p, cell):
		# (v67) a can of fuel poured into the tank at the engine
		if _work_done(p, cell, Net.POUR_TICKS):
			pour(p)
	elif cell >= 0 and server.salvage.can_mine(p, cell) == "":
		# (v81) ore dug out of a vein of the asteroid alongside
		if _work_done(p, cell, server.salvage.mine_ticks(p)):
			server.salvage.mine(p, cell)
	elif cell >= 0 and server.salvage.can_cut(p, cell) == "":
		# (v67, the author's B2) scrap cut off a wreck or a derelict alongside (see Salvage)
		if _work_done(p, cell, server.salvage.cut_ticks(p)):
			server.salvage.cut(p, cell)
	elif cell >= 0 and server.outfit.can(p, cell) == "":
		# (v59) an engineer installs the crate of gear in hand (or takes a module out of the bay)
		if _work_done(p, cell, server.outfit.ticks(p)):
			server.outfit.finish(p, cell)
	elif cell >= 0 and server.mounts.can(p, cell) == "":
		# (v60) a gun carried up onto its mount, or taken down into the hands
		if _work_done(p, cell, server.mounts.ticks(p)):
			server.mounts.finish(p, cell)
	elif cell >= 0 and server.map.autodoc.has(cell) and server.medbay.tending(p, cell):
		p.work = 0                           # (v60) tending whoever lies in the autodoc (see Medbay)
	elif cell >= 0 and server.garden.can(p, cell) == "":
		# (v63) a hydroponic tray: planting, tending, harvesting, clearing (see Garden)
		if _work_done(p, cell, server.garden.ticks(cell)):
			server.garden.finish(p, cell)
	elif door >= 0 and p.in_hand() == Net.ITEM_WELDER and server.doors.is_shut(door):
		# (v70, the author's W1) a welder seals a shut door, or cuts a welded one open
		if _work_done(p, cell, WELD_TICKS):
			weld(p, door)
	elif door >= 0 and server.doors.jammed[door] == 1:
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			_use_spare(p, spare)
			server.doors.jammed[door] = 0
			server.door_hold[door] = server.tick          # it may shut again as soon as the doorway is clear
			server.chat.say("%s чинит заклинившую дверь." % p.name)
	elif door >= 0 and server.doors.faulty[door] == 1:
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			_use_spare(p, spare)
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
			if not p.bot or server.stations.shutter_forced(p, door):
				server.chat.say("%s вручную поднимает аварийный шлюз." % p.name)
	elif door >= 0 and server.doors.barred(door, server.map.door_access[door], p.st.access) and not server.map.leaving(p.st.x, p.st.y, door):
		# no access: the lock can still be broken, slowly and for all to hear;
		# (v69) broken, it opens for anybody until somebody mends it
		if _work_done(p, cell, Net.HACK_TICKS):
			server.doors.picked[door] = 1
			server.doors.ready[door] = server.tick + Doors.OPEN_TICKS
			server.door_hold[door] = server.tick + Doors.OPEN_TICKS + Doors.HOLD_TICKS
			server.chat.sound(Net.SOUND_BLOW, cell % server.map.width, cell / server.map.width, p.slot)
			server.chat.say("%s взламывает замок двери: %s." % [p.name, Net.ACCESS_NAMES.get(server.map.door_access[door], "отсек")])
	elif door >= 0 and server.doors.picked[door] == 1:
		# (v69) a broken lock mended: the door asks for its access again
		if _work_done(p, cell, mend_ticks):
			p.train(Net.SKILL_REPAIR)
			_use_spare(p, spare)
			server.doors.picked[door] = 0
			server.chat.say("%s чинит взломанный замок: %s." % [p.name, Net.ACCESS_NAMES.get(server.map.door_access[door], "отсек")])
	elif cell >= 0 and server.map.oxygen.has(cell) and server.powered() and p.has_suit():
		p.work = 0
		p.tank = minf(p.tank + Net.TICK_SEC / Vitals.REFILL_SECONDS, 1.0)
	else:
		p.work = 0


const WELD_TICKS := 80               # (v70) 4 s to weld a door shut, or to cut the weld


func weld(p: Player, door: int) -> void:
	var doors := server.doors
	doors.welded[door] = 1 - doors.welded[door]
	server.usage.note(p, "weld")           # (v82)
	server.chat.sound(Net.SOUND_ZAP, p.st.x, p.st.y, p.slot)
	server.replication.sight_changed()
	server.chat.say("%s %s." % [p.name, "заваривает дверь: теперь её не откроет никто, пока не срежут шов" if doors.welded[door] == 1
		else "срезает шов: дверь снова открывается"])


func can_pour(p: Player, cell: int) -> bool:
	## (v67) A can of fuel in hand, facing a working engine, with room in the tank for it?
	return p.in_hand() == Net.ITEM_FUEL and server.map.engine.has(cell) and not server.ship.broken.has(cell) \
		and server.ship.tank <= Net.FUEL_MAX - Net.CAN_FUEL


func pour(p: Player) -> void:
	p.slots[p.hand] = Net.ITEM_NONE
	server.ship.tank = minf(server.ship.tank + Net.CAN_FUEL, Net.FUEL_MAX)
	server.supplies.tell_store()
	server.chat.say("%s заливает канистру в бак: топлива %d из %d." % [p.name, floori(server.ship.tank), Net.FUEL_MAX])


func spare_for(p: Player, cell: int) -> int:
	## (v71) The spare part mending what is in that cell would use up (ITEM_NONE = none would do).
	if cell < 0:
		return Net.ITEM_NONE
	return Upkeep.spare(server.complex_repairs, Upkeep.part_for(server.map, cell), func(item: int) -> bool: return p.count(item) > 0)


func _use_spare(p: Player, spare: int) -> void:
	if spare != Net.ITEM_NONE:
		p.remove(spare)


func _work_done(p: Player, cell: int, ticks: int) -> bool:
	## One more tick of work on the thing in that cell. True when the job is finished.
	## (v71) Strong coffee makes all of it quicker (Player.pace).
	ticks = maxi(roundi(ticks * p.pace(server.tick)), 1)
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
	if server.pirates.bomb_by(p) >= 0:
		return true                          # (v70) a pirates' bomb to disarm
	var cell := map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
	if cell < 0:
		return false
	if server.outfit.can(p, cell) != server.outfit.NOT_HERE:
		return true                          # (v59) a crate of gear where it goes, or the module bay
	if server.outside.can_mend(p, cell) or map.smes.has(cell) or map.smes_small.has(cell):
		return true                          # (v61) the hull from outside; an SMES's terminal
	if server.salvage.can_cut(p, cell) != server.salvage.NOT_HERE or server.salvage.can_mine(p, cell) != server.salvage.NOT_HERE:
		return true                          # (v67) a wreck's wall to cut scrap off (or why not); (v81) an ore vein
	if server.air.holes.has(cell) or server.ship.broken.has(cell) or map.oxygen.has(cell) or map.chart.has(cell) \
			or map.helm.has(cell) or map.engine.has(cell) or map.air_plant.has(cell) or map.locker.has(cell) \
			or map.lock_pump.has(cell) or map.gun_console.has(cell) or map.guns.has(cell) or map.intercom.has(cell) or map.holo.has(cell) \
			or map.drone_console.has(cell) or map.bench.has(cell) or map.bay.has(cell) or map.autodoc.has(cell) or map.scanner.has(cell) \
			or map.comms.has(cell) or map.trays.has(cell) or map.cryo.has(cell) or map.stove.has(cell):
		return true
	var door := map.door_of[cell]
	if door >= 0 and p.in_hand() == Net.ITEM_WELDER and server.doors.is_shut(door):
		return true                          # (v70) a door to weld, or to cut open
	return door >= 0 and ((server.doors.is_shut(door) and server.doors.held_by_partner(door)) or server.doors.jammed[door] == 1
		or server.doors.faulty[door] == 1 or server.doors.is_sealed(door) or server.doors.picked[door] == 1
		or server.doors.barred(door, map.door_access[door], p.st.access) and not map.leaving(p.st.x, p.st.y, door))


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
	## airlock pump (or, v66, presses an airlock door's button), or picks up a thing lying in front or underfoot, or else
	## takes a ladder: in the order GameClient.use_target shows the player.
	if p.cond != Net.COND_OK or p.corpse:
		return
	var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	var gear_why := server.outfit.can(p, server.map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes))
	var gun_why := server.mounts.can(p, ahead)
	if ahead >= 0 and server.map.lock_pump.has(ahead):
		server.systems.toggle_pump(p, ahead)
	elif ahead >= 0 and server.systems.call_lock(p, server.map.door_of[ahead]):
		pass                                 # (v66) the airlock door's button: the pump is at work
	elif gear_why != "" and gear_why != server.outfit.NOT_HERE and not server.ship.broken.has(ahead):
		server.chat.tell(p, gear_why)        # (v59) why that crate cannot go in here
	elif ahead >= 0 and server.salvage.can_mine(p, ahead) != "" and server.salvage.can_mine(p, ahead) != server.salvage.NOT_HERE:
		server.chat.tell(p, server.salvage.can_mine(p, ahead))    # (v81) why no ore comes out of it
	elif ahead >= 0 and server.salvage.can_cut(p, ahead) != "" and server.salvage.can_cut(p, ahead) != server.salvage.NOT_HERE:
		server.chat.tell(p, server.salvage.can_cut(p, ahead))     # (v67) why nothing can be cut off here
	elif ahead >= 0 and server.map.engine.has(ahead) and p.in_hand() == Net.ITEM_FUEL and not can_pour(p, ahead):
		server.chat.tell(p, "Бак полон: канистра не войдёт." if not server.ship.broken.has(ahead) else "Двигатель сломан: сначала почините его.")
	elif gun_why != "" and gun_why != server.mounts.NOT_HERE:
		server.chat.tell(p, gun_why)         # (v60) why that gun cannot go up here
	elif ahead >= 0 and server.map.scanner.has(ahead):
		server.medbay.scan(p, ahead)         # (v60) the body scanner's report
	elif ahead >= 0 and server.map.trays.has(ahead) and server.garden.can(p, ahead) != "":
		server.chat.tell(p, server.garden.can(p, ahead))     # (v63) how the plant is doing, or why nothing can be planted
	elif ahead >= 0 and not server.supplies.box_kinds(ahead).is_empty():
		server.supplies.box(p, ahead)        # (v91) a first-aid box or a spare parts box on the wall
	elif ahead >= 0 and server.map.shield.has(server.map.machine_of(ahead)) and not server.ship.broken.has(server.map.machine_of(ahead)) \
			and gear_why == server.outfit.NOT_HERE and not server.map.is_other(ahead):
		server.gunnery.turn_shield(p)        # (v93, the author's D3 C) the shield's shape: a bubble or an arc to one side
	elif ahead >= 0 and server.map.cryo.has(ahead):
		server.chat.tell(p, "Криокапсула. Резерв экипажа спит здесь и не ест: %d чел. Замена погибшему выходит отсюда." % server.reserve)
	elif usable_ahead(p) or _lying_near(p):
		return
	elif p.in_hand() == Net.ITEM_ROBOT and server.robots.can_set(p, Vector2i(p.st.x + Net.DX[p.st.facing], p.st.y + Net.DY[p.st.facing])) != "-":
		server.robots.deploy(p, Vector2i(p.st.x + Net.DX[p.st.facing], p.st.y + Net.DY[p.st.facing]))   # (v62)
	elif not server.inventory.pick_up(p):
		server.movement.climb(p)
