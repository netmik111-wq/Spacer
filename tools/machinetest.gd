extends SceneTree
## Checks the ship's machines on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/machinetest.gd
## The engine powers the ship: without it nothing moves, jumps, makes air or
## fills a tank, and doors open by hand; nothing breaks, and mending the engine
## brings it all back. The air plant fills its own compartment and nothing else
## while the doors are shut. Emergency shutters drop on a pressure difference,
## can be forced by hand, and need power.
## Doors can jam open, shutters can fail, and the power can drop out for a
## few seconds: the director's smaller troubles.
## Supplies: a hole needs a patch, a machine is mended three times as slowly
## without a spare part, the air plant runs out, a trader sells and a station restocks.
## Fuel: a jump burns a can from the locker, there is no jump without one, a
## station tops it up, and a ship with none aboard finds some after a while.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Director := preload("res://src/server/director.gd")
const Doors := preload("res://src/shared/doors.gd")
const Items := preload("res://src/shared/items.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26190, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map
	_expect(map.engine.size() == 1 and map.air_plant.size() == 1, "the ship has an engine and an air plant")
	var engine: int = map.engine.keys()[0]
	var plant: int = map.air_plant.keys()[0]
	var p := server._new_player("Проверка")
	_give(p, 3, 3)                       # the first tester is restocked before every part; supplies are tried at the end

	print("the engine")
	_face(p, map.helm.keys()[0])
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(server.ship_moving, "with the engine running the helm sets a course")
	_expect(server.director.fire(Director.ENGINE_FAULT) and server.engine_down(), "the director can stop the engine")
	_expect(not server.ship_moving, "the ship stops when the engine does")
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(not server.ship_moving, "the helm does nothing without the engine")
	_face(p, map.chart.keys()[0])
	var target: int = server.sectors.neighbours(server.sector)[0]
	server._jump_asked(p, target)
	_expect(server.jump_to == Net.NO_SECTOR, "no jump without the engine")
	_expect(not server.break_console(), "a bridge console does not break while the engine is out")

	print("no power: every system stands still, none is broken")
	_give(p, 3, 3)
	_expect(server.broken.size() == 1, "only the engine itself is out of order")
	var air := server.air
	var out_cell: int = map.air_plant[plant]
	air.air[out_cell] = 0.5
	air.wake()
	var before := air.total()
	_run(5 * Net.TICK_HZ)
	_expect(absf(air.total() - before) < 0.001, "the air plant makes no air")
	_face(p, map.oxygen.keys()[0])
	p.tank = 0.2
	p.using = true
	_run(2 * Net.TICK_HZ)
	_expect(p.tank <= 0.2, "an oxygen station does not fill a tank")
	p.using = false
	var slow := _ticks_through_a_door(p)
	_expect(slow >= Doors.MANUAL_OPEN_TICKS and slow < Doors.MANUAL_OPEN_TICKS + 12, "a door is pushed open by hand: %.1f s to get through" % (slow / float(Net.TICK_HZ)))

	print("mending the engine brings everything back")
	_give(p, 3, 3)
	_face(p, engine)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(not server.engine_down() and server.broken.is_empty(), "holding use in front of the engine mends it")
	before = air.total()
	_run(5 * Net.TICK_HZ)
	_expect(air.total() > before + 0.05, "the air plant makes air again")
	_face(p, map.oxygen.keys()[0])
	p.using = true
	_run(2 * Net.TICK_HZ)
	_expect(p.tank > 0.5, "an oxygen station fills a tank again")
	p.using = false
	var quick := _ticks_through_a_door(p)
	_expect(quick < Doors.OPEN_TICKS + 12, "doors open by themselves again: %.1f s to get through" % (quick / float(Net.TICK_HZ)))
	_face(p, map.chart.keys()[0])
	server._jump_asked(p, target)
	_expect(server.jump_to == target, "the jump starts")
	_expect(server.break_engine() and server.jump_to == Net.NO_SECTOR, "an engine failure breaks off a jump being charged")
	_mend_all()
	_expect(server.break_console() and not server.break_engine(), "the engine does not break while a bridge console is out")
	_mend_all()

	print("the air plant")
	_give(p, 3, 3)
	p.tank = 1.0
	p.supply = true                      # the tester breathes from its tank: the ship is about to be emptied
	for i in air._cells:
		air.air[i] = 0.0
	air.wake()
	var seconds := 60
	_run(seconds * Net.TICK_HZ)
	var made := air.total()
	var expected := Net.TICK_HZ / float(Net.AIR_EVERY) * seconds * air.PLANT_PER_STEP
	print("  the air plant made %.1f cells' worth of air in %d s (%.1f expected)" % [made, seconds, expected])
	_expect(absf(made - expected) < 0.2, "an air plant makes air at its set rate")
	_expect(air.air[out_cell] > 0.05, "the air comes out in front of the plant (%.0f%% there)" % (air.air[out_cell] * 100.0))
	var above := -1
	for i in map.air_down.size():
		if map.air_down[i] >= 0 and map.deck_of_cell(map.air_down[i]) == map.deck_of_cell(out_cell):
			above = i
			break
	if above >= 0:
		_expect(air.air[above] > 0.01, "and rises through the catwalk to the deck above (%.0f%% there)" % (air.air[above] * 100.0))
	var far := (map.deck_stride + 1) * map.width + 5       # the room in the far corner of the lower deck
	_expect(air.air[far] == 0.0, "shut doors keep it out of the other compartments")
	_expect(server.director.fire(Director.AIR_PLANT_FAULT), "the director can stop the air plant")
	before = air.total()
	_run(10 * Net.TICK_HZ)
	_expect(absf(air.total() - before) < 0.001, "a plant that is out of order makes no air")
	_face(p, plant)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(server.broken.is_empty(), "holding use in front of the plant mends it")
	air.refill()
	_run(20 * Net.TICK_HZ)
	var top := 0.0
	for i in air._cells:
		top = maxf(top, air.air[i])
	_expect(top <= 1.0001 and absf(air.total() - air._cells.size()) < 0.01, "a full ship stays at normal pressure (highest cell %.3f)" % top)
	p.supply = false

	print("emergency shutters")
	_give(p, 3, 3)
	_expect(_sealed().is_empty(), "with the same pressure everywhere no shutter is down")
	# a hole in the room in the top left corner of the top deck: its two doors are 7,3 and 10,1
	var hole := -1
	for cell in map.hull:
		if cell / map.width == 0 and cell % map.width >= 5 and cell % map.width <= 9:
			hole = cell
			break
	var door_down := map.door_at(7, 3)
	var door_side := map.door_at(10, 1)
	server.breach(hole)
	var dropped := -1
	for t in 20 * Net.TICK_HZ:
		server._tick()
		if dropped < 0 and server.doors.locked[door_down] == 1:
			dropped = t
	var sealed := _sealed()
	_expect(dropped >= 0 and sealed.has(door_down) and sealed.has(door_side) and sealed.size() == 2,
		"a breach drops the shutters of that room's doors and no others (after %.1f s)" % (dropped / float(Net.TICK_HZ)))
	p.st.place(7, 4)
	p.st.dir = Net.DIR_UP
	_run(3 * Net.TICK_HZ)
	_expect(p.st.x == 7 and p.st.y == 4 and server.doors.is_shut(door_down), "walking into a door with its shutter down does not open it")
	p.st.dir = Net.DIR_NONE
	p.st.facing = Net.DIR_UP
	p.using = true
	_run(Net.FORCE_TICKS + 2)
	p.using = false
	_expect(server.doors.locked[door_down] == 0, "holding use for %d s forces the shutter up" % (Net.FORCE_TICKS / Net.TICK_HZ))
	p.st.dir = Net.DIR_UP
	_run(Net.TICK_HZ)
	_expect(p.st.y < 4, "and the door then opens as usual")
	p.st.place(9, 4)                     # step aside; the hole is still there
	p.st.dir = Net.DIR_NONE
	_run(Net.FORCED_OPEN_TICKS + 2 * Net.TICK_HZ)
	_expect(server.doors.is_sealed(door_down), "left alone, a forced shutter drops again and the door shuts")
	server.seal_all()
	air.refill()
	_run(2 * Net.TICK_HZ)
	_expect(_sealed().is_empty(), "when the pressure evens out the shutters lift by themselves")

	# without power nothing drops
	server.break_engine()
	server.breach(hole)
	_run(15 * Net.TICK_HZ)
	_expect(_sealed().is_empty(), "without power no shutter drops")
	_mend_all()
	_run(Net.TICK_HZ)
	_expect(_sealed().has(door_down), "with the power back they drop where they should")
	server.break_engine()
	server.seal_all()
	air.refill()
	_run(5 * Net.TICK_HZ)
	_expect(_sealed().has(door_down), "and one that is down stays down while there is no power")

	_mend_all()
	_run(Net.TICK_HZ)

	print("a door jammed open")
	_give(p, 3, 3)
	_expect(server.director.fire(Director.DOOR_JAM), "the director can jam a door")
	var stuck := -1
	for d in server.doors.jammed.size():
		if server.doors.jammed[d] == 1:
			stuck = d
	_run(Doors.HOLD_TICKS + 3 * Net.TICK_HZ)
	_expect(stuck >= 0 and not server.doors.is_shut(stuck), "it stands open and does not shut by itself")
	p.st.place(map.doors[stuck].x, map.doors[stuck].y)       # stand next to it, on whichever side has floor
	var beside := map.door_sides[stuck * 2] if map.door_sides[stuck * 2] >= 0 else map.door_sides[stuck * 2 + 1]
	p.st.place(beside % map.width, beside / map.width)
	p.st.facing = _towards(beside, map.doors[stuck])
	p.using = true
	_run(Net.REPAIR_TICKS + 2)
	p.using = false
	_run(Net.TICK_HZ)
	_expect(server.doors.jammed[stuck] == 0 and server.doors.is_shut(stuck), "mended, it shuts again")

	print("a faulty shutter")
	_give(p, 3, 3)
	# one that has dropped for no reason: it stays down although the pressure is even
	server.doors.faulty[door_down] = 1
	server.doors.locked[door_down] = 1
	_run(5 * Net.TICK_HZ)
	_expect(server.doors.is_sealed(door_down), "a faulty shutter that has dropped stays down in even pressure")
	p.st.place(7, 4)
	p.st.facing = Net.DIR_UP
	p.using = true
	_run(Net.REPAIR_TICKS + 2)
	p.using = false
	_run(Net.TICK_HZ)
	_expect(server.doors.faulty[door_down] == 0 and server.doors.locked[door_down] == 0, "mended, it lifts by itself")
	# one that will not drop: a breach on the other side leaves the door unguarded
	server.doors.faulty[door_down] = 1
	server.breach(hole)
	_run(10 * Net.TICK_HZ)
	_expect(server.doors.locked[door_down] == 0 and server.doors.locked[door_side] == 1, "a faulty shutter does not drop at a breach; its neighbour does")
	p.tank = 1.0
	p.supply = true
	p.using = true
	_run(Net.REPAIR_TICKS + 2)
	p.using = false
	_run(Net.TICK_HZ)
	_expect(server.doors.locked[door_down] == 1, "mended, it drops as it should")
	_expect(server.director.fire(Director.SHUTTER_FAULT) and server._count(server.doors.faulty) == 1, "the director can make a shutter fail")
	server.seal_all()
	air.refill()
	for d in server.doors.faulty.size():
		server.doors.faulty[d] = 0
	_run(2 * Net.TICK_HZ)
	p.supply = false

	print("a passing power failure")
	_give(p, 3, 3)
	_face(p, map.helm.keys()[0])
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(server.director.fire(Director.POWER_GLITCH) and not server.powered(), "the director can cut the power for a moment")
	_expect(server.broken.is_empty() and not server.engine_down(), "nothing is broken by it")
	_expect(not server.ship_moving and server.doors.manual, "the ship stops and doors go manual, as with the engine out")
	_run(16 * Net.TICK_HZ)
	_expect(server.powered() and not server.doors.manual, "the power comes back by itself within 15 s")
	server._helm_asked(p, true, Vector2(150, 150))
	_expect(server.ship_moving, "and the helm works again")

	print("supplies")
	var q := server._new_player("Кладовщик")
	_expect(q.count(Net.ITEM_PATCH) == 0 and q.count(Net.ITEM_PART) == 0 and map.locker.size() == 1, "the ship has a supply locker")
	var had_patches: int = server.store[Net.ITEM_PATCH]
	var had_parts: int = server.store[Net.ITEM_PART]
	server._store_asked(q, Net.STORE_TAKE, Net.ITEM_PATCH)
	_expect(q.count(Net.ITEM_PATCH) == 0, "nothing can be taken from across the ship")
	_face(q, map.locker.keys()[0])
	for i in 2:
		server._store_asked(q, Net.STORE_TAKE, Net.ITEM_PATCH)
		server._store_asked(q, Net.STORE_TAKE, Net.ITEM_PART)
	_expect(q.count(Net.ITEM_PATCH) == 2 and q.count(Net.ITEM_PART) == 2, "at the locker a crew member takes patches and parts into their slots")
	for i in 5:
		server._store_asked(q, Net.STORE_TAKE, Net.ITEM_PATCH)
	var open := Net.BASE_SLOTS + Net.POCKETS             # a jumpsuit, no backpack
	_expect(q.count(Net.ITEM_NONE) == 0 and q.count(Net.ITEM_PATCH) == open - 2, "but no more than there are slots for (%d)" % open)
	_expect(server.store[Net.ITEM_PATCH] == had_patches - q.count(Net.ITEM_PATCH) and server.store[Net.ITEM_PART] == had_parts - 2, "and the locker has that much less")
	server._store_asked(q, Net.STORE_PUT_BACK, 0)
	_expect(q.count(Net.ITEM_NONE) == open and server.store[Net.ITEM_PATCH] == had_patches and server.store[Net.ITEM_PART] == had_parts, "everything can be put back")

	# a hole needs a patch
	_give(p, 0, 0)
	server.breach(hole)
	p.tank = 1.0
	p.supply = true
	p.st.place(hole % map.width, 1)
	p.st.facing = Net.DIR_UP
	p.st.dir = Net.DIR_NONE
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	_expect(server.air.holes.has(hole), "without a patch a hole cannot be mended")
	_give(p, 1, 0)
	_run(Net.REPAIR_TICKS + 5)
	_expect(not server.air.holes.has(hole) and p.count(Net.ITEM_PATCH) == 0, "with one it can, and the patch is used up")
	p.using = false
	p.supply = false
	air.refill()
	_run(2 * Net.TICK_HZ)

	# a machine without a spare part: slower, but possible
	server.break_air_plant()
	_give(p, 0, 0)
	_face(p, plant)
	p.using = true
	_run(Net.REPAIR_TICKS + 5)
	_expect(not server.broken.is_empty(), "without a spare part a repair is not done in the usual time")
	_run(Net.REPAIR_TICKS * (Net.NO_PART_SLOWER - 1))
	_expect(server.broken.is_empty(), "but it is done in %d times as long" % Net.NO_PART_SLOWER)
	server.break_air_plant()
	_give(p, 0, 2)
	_run(Net.REPAIR_TICKS + 5)
	p.using = false
	_expect(server.broken.is_empty() and p.count(Net.ITEM_PART) == 1, "with a spare part it is quick, and the part is used up")

	# the air plant has only so much air to give
	server.store_air = 0.5
	for tester: RefCounted in [p, q]:    # both breathe from their tanks while the ship is empty
		tester.tank = 1.0
		tester.supply = true
	for i in air._cells:
		air.air[i] = 0.0
	air.wake()
	_run(20 * Net.TICK_HZ)
	_expect(server.store_air == 0.0 and absf(air.total() - 0.5) < 0.01, "the air plant stops when its store is empty (gave %.2f)" % air.total())
	air.refill()

	# a trader sells, a station restocks
	var here := server.sector
	server._store_asked(q, Net.STORE_BUY, Net.ITEM_PATCH)
	_expect(server.store[Net.ITEM_PATCH] == had_patches, "nothing can be bought with no trader alongside")
	server.sectors.kind[here] = Sectors.TRADER
	server.sectors.spot[here] = server.ship_pos
	server.sectors.reach[here] = Sectors.DOCK_RANGE
	_run(2)
	_expect(server.can_trade(), "docked with a trader, the ship can trade")
	var money := server.credits
	server._store_asked(q, Net.STORE_BUY, Net.ITEM_PATCH)
	server._store_asked(q, Net.STORE_BUY, Net.ITEM_PART)
	server._store_asked(q, Net.STORE_BUY_AIR, 0)
	_expect(server.store[Net.ITEM_PATCH] == had_patches + 1 and server.store[Net.ITEM_PART] == had_parts + 1 and server.store_air == Net.AIR_LOT
		and server.credits == money - Items.price(Net.ITEM_PATCH) - Items.price(Net.ITEM_PART) - Net.PRICE_AIR, "a patch, a part and air are bought for credits (%d left)" % server.credits)
	server.credits = 0
	server._store_asked(q, Net.STORE_BUY, Net.ITEM_PATCH)
	_expect(server.store[Net.ITEM_PATCH] == had_patches + 1, "and not without credits")
	server.sectors.kind[here] = Sectors.STATION
	server.in_reach = false
	_run(2)
	_expect(server.store_air == Net.STORE_AIR_FULL, "docking at a supply station restocks the air plant")
	server.sectors.kind[here] = Sectors.EMPTY
	server.sectors.reach[here] = 0
	_run(2)
	target = server.sectors.neighbours(server.sector)[0]
	var target_cell: Vector2i = server.sectors.cell[target]
	server.start_jump(target, "Проверка")
	_run(Net.JUMP_TICKS + 2)
	_expect(server.sectors.cell[server.sector] == target_cell and server.credits == Net.EXPLORE_REWARD, "the first visit to a sector earns %d credits" % Net.EXPLORE_REWARD)

	print("fuel")
	_expect(server.fuel() == Items.stock(Net.ITEM_FUEL) - 1, "the jump burned one can of fuel (%d left)" % server.fuel())
	_run(Net.DRIVE_REST_TICKS + 2)
	_face(q, map.chart.keys()[0])
	target = server.sectors.neighbours(server.sector)[0]
	var stayed := server.sector
	server.store[Net.ITEM_FUEL] = 0
	server._jump_asked(q, target)
	_expect(server.jump_to == Net.NO_SECTOR, "no jump with no fuel in the locker")
	server.store[Net.ITEM_FUEL] = 1
	server._jump_asked(q, target)
	_expect(server.jump_to == target, "with a can in the locker the jump starts")
	server.store[Net.ITEM_FUEL] = 0                  # somebody takes it out while the drive charges
	_run(Net.JUMP_TICKS + 2)
	_expect(server.jump_to == Net.NO_SECTOR and server.sector == stayed, "a jump whose last can was taken out of the locker fails")
	server.director._watch_fuel(server.tick)
	_expect(server.fuel() == 0, "a ship with no fuel aboard does not find some at once")
	server.director._watch_fuel(server.tick + int(Director.RESCUE_SECONDS * Net.TICK_HZ))
	_expect(server.fuel() == Director.RESCUE_FUEL, "but after %d s a drifting container brings %d cans" % [int(Director.RESCUE_SECONDS), Director.RESCUE_FUEL])
	server.store[Net.ITEM_FUEL] = 0
	here = server.sector
	server.sectors.kind[here] = Sectors.STATION
	server.sectors.spot[here] = server.ship_pos
	server.sectors.reach[here] = Sectors.DOCK_RANGE
	server.in_reach = false
	_run(2)
	_expect(server.fuel() == Net.STATION_FUEL, "a supply station tops the fuel up to %d cans" % Net.STATION_FUEL)
	server.sectors.kind[here] = Sectors.EMPTY
	server.sectors.reach[here] = 0
	_run(2)

	print("searching and hauling")
	air.refill()
	for tester: RefCounted in [p, q]:
		tester.supply = false
		tester.health = 100.0
	_run(2)
	p.st.place(8, 4)
	p.st.facing = Net.DIR_RIGHT
	p.st.dir = Net.DIR_NONE
	q.st.place(9, 4)
	_give(p, 0, 0)
	_give(q, 2, 1)
	server._hands_asked(p, GameServer.HAND_SEARCH, q.slot, server.tick)
	_run(1)
	_expect(p.searching < 0, "somebody on their feet cannot be searched")
	server._hands_asked(p, GameServer.HAND_DRAG, q.slot, server.tick)
	_run(1)
	_expect(p.dragging < 0, "nor hauled")
	q.health = -40.0                     # unconscious now
	_run(2)
	_expect(q.cond == Net.COND_CRIT, "(the other tester is unconscious)")
	server._hands_asked(p, GameServer.HAND_SEARCH, q.slot, server.tick)
	_run(1)
	_expect(p.searching == q.slot, "somebody unconscious next to us can be searched")
	server._loot_asked(p, true, q.slots.find(Net.ITEM_PART))
	_expect(p.count(Net.ITEM_PART) == 1 and q.count(Net.ITEM_PART) == 0, "a thing is taken from their slot into ours")
	server._loot_asked(p, false, p.slots.find(Net.ITEM_PART))
	_expect(p.count(Net.ITEM_PART) == 0 and q.count(Net.ITEM_PART) == 1, "and can be put back")
	p.st.place(6, 4)
	_run(1)
	_expect(p.searching < 0, "the search ends when we are no longer next to them")
	server._loot_asked(p, true, 0)
	_expect(p.count(Net.ITEM_PATCH) == 0, "and nothing can be taken from a distance")

	p.st.place(8, 4)
	server._hands_asked(p, GameServer.HAND_DRAG, q.slot, server.tick)
	_run(1)
	_expect(p.dragging == q.slot and q.dragged_by == p.slot, "somebody unconscious next to us can be taken hold of")
	p.st.dir = Net.DIR_LEFT
	_run(Net.DRAG_TICKS * 2)
	_expect(p.st.x == 6 and q.st.x == 7 and q.st.y == 4, "hauling: twice as slow, and they follow one cell behind (we are at %d, they at %d)" % [p.st.x, q.st.x])
	p.st.dir = Net.DIR_NONE
	_run(Net.DRAG_TICKS)
	# down the ladder at 5,5 with them
	p.st.dir = Net.DIR_LEFT
	_run(Net.DRAG_TICKS)
	p.st.dir = Net.DIR_DOWN
	_run(Net.DRAG_TICKS)
	p.st.dir = Net.DIR_NONE
	_run(Net.DRAG_TICKS)
	_expect(p.st.x == 5 and p.st.y == 5 and p.dragging == q.slot, "(we are on the ladder with them in tow)")
	server._climb(p)
	_expect(map.deck_of(p.st.y) == 1 and q.st.x == p.st.x and q.st.y == p.st.y, "they come down a ladder with us")
	server._hands_asked(p, GameServer.HAND_DRAG, Net.NOBODY, server.tick)
	_run(1)
	_expect(p.dragging < 0 and q.dragged_by < 0 and not p.st.slow, "letting go frees both")
	server._hands_asked(p, GameServer.HAND_DRAG, q.slot, server.tick)
	_run(1)
	q.health = 60.0                      # they come round
	_run(2)
	_expect(q.cond == Net.COND_OK and p.dragging < 0, "somebody who comes round is let go of")

	# the dead keep what they carried, and their body can be searched and hauled
	q.health = -150.0
	_run(2)
	_expect(q.cond == Net.COND_DEAD, "(the other tester is dead)")
	p.st.place(q.st.x, q.st.y)
	server._hands_asked(p, GameServer.HAND_DRAG, q.slot, server.tick)
	server._hands_asked(p, GameServer.HAND_SEARCH, q.slot, server.tick)
	_run(1)
	server._hands_asked(p, GameServer.HAND_DRAG, q.slot, server.tick)
	_run(1)
	var carried := q.count(Net.ITEM_PATCH)
	server._respawn(q)
	var body: RefCounted = server.players[p.dragging] if p.dragging >= 0 else null
	_expect(q.cond == Net.COND_OK and q.count(Net.ITEM_PATCH) == 1 and q.count(Net.ITEM_PART) == 1 and q.count(Net.ITEM_RADIO) == 1
		and q.count(Net.ITEM_NONE) == Net.BASE_SLOTS + Net.POCKETS - 3, "the one who comes back has only what a newcomer is given")
	_expect(body != null and body.corpse and body.count(Net.ITEM_PATCH) == carried and carried > 0, "the body keeps what they carried (%d patches)" % carried)
	_expect(p.searching == body.slot if body != null else false, "and whoever was hauling and searching goes on with the body")
	server._loot_asked(p, true, body.slots.find(Net.ITEM_PATCH))
	_expect(p.count(Net.ITEM_PATCH) == 1, "a body can be robbed")

	server.stop()
	server.free()
	print("MACHINETEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _towards(from_cell: int, to: Vector2i) -> int:
	## The way to face from a cell to look at the cell next to it.
	var w := server.map.width
	var fx := from_cell % w
	var fy := from_cell / w
	if to.x != fx:
		return Net.DIR_RIGHT if to.x > fx else Net.DIR_LEFT
	return Net.DIR_DOWN if to.y > fy else Net.DIR_UP


func _give(who: RefCounted, patches: int, parts: int) -> void:
	## Sets what a tester carries.
	who.slots.fill(Net.ITEM_NONE)
	for i in patches:
		who.add(Net.ITEM_PATCH)
	for i in parts:
		who.add(Net.ITEM_PART)


func _mend_all() -> void:
	server.broken.clear()
	server._power_changed()


func _sealed() -> Array:
	## The doors whose shutter is down.
	var out: Array = []
	for d in server.doors.locked.size():
		if server.doors.locked[d] == 1:
			out.append(d)
	return out


func _ticks_through_a_door(p: RefCounted) -> int:
	## Walks the character from the corridor up through the door at 7,3 and says how long it took.
	p.st.place(7, 4)
	p.st.dir = Net.DIR_UP
	var n := 0
	while p.st.y > 2 and n < 200:
		server._tick()
		n += 1
	p.st.dir = Net.DIR_NONE
	_run(Doors.HOLD_TICKS + 20)          # let the door shut behind
	return n


func _face(p: RefCounted, wall_cell: int) -> void:
	## Puts the character in front of a thing on a wall, looking at it.
	var map := server.map
	var x := wall_cell % map.width
	var y := wall_cell / map.width
	if map.walkable(x, y + 1):
		p.st.place(x, y + 1)
		p.st.facing = Net.DIR_UP
	else:
		p.st.place(x, y - 1)
		p.st.facing = Net.DIR_DOWN
	p.st.dir = Net.DIR_NONE


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
