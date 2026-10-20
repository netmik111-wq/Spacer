extends SceneTree
## Checks build v71 (upkeep), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/upkeeptest.gd
## Long hunger first slows the crew and at last kills; food stops it at once.
## The galley's stove cooks a stew, coffee and a broth from the locker, and
## each does what it says when eaten. Complex repairs want a toolbox and the
## machine's own kind of part (consoles a board), are only slower without them,
## and the plain game takes any part. Bots fetch what complex repairs want.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Upkeep := preload("res://src/shared/upkeep.gd")
const Garden := preload("res://src/server/garden.gd")
const Galley := preload("res://src/server/galley.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26630, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	_items()
	_hunger()
	_cooking()
	_meals()
	_complex()
	_plain()
	_bots()
	server.stop()
	server.free()
	print("upkeeptest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for t in ticks:
		server.ship.hull = server.ship.hull_max
		server._tick()


func _clear() -> void:
	for q in server.players:
		if q != null:
			server.crew.remove(q)
	for cell: int in server.air.holes.keys():
		server.air.set_hole(cell, false)
	server.ship.broken = {}
	_run(2)


func _man(name: String):
	var p = server.crew.new_player(name)
	p.slots.fill(Net.ITEM_NONE)
	p.skills = PackedByteArray([0, 0, 0, 0])
	p.job = Net.JOB_PILOT
	return p


func _stand_at(p, cell: int) -> void:
	## Puts p in front of the thing in that wall cell, facing it.
	var front: int = server.map.fitting_front(cell)
	var w: int = server.map.width
	p.st.place(front % w, front / w)
	p.st.dir = Net.DIR_NONE
	for d in range(1, 5):
		if front + Net.DX[d] + Net.DY[d] * w == cell:
			p.st.facing = d


# --------------------------------------------------------------- the things

func _items() -> void:
	print("  -- the new things")
	for item in [Net.ITEM_TOOLBOX, Net.ITEM_BOARD, Net.ITEM_STEW, Net.ITEM_COFFEE, Net.ITEM_BROTH]:
		_expect(Items.name_of(item) != "" and Items.kept_in_locker().has(item), "%s has a name and a place in the locker" % Items.name_of(item))
	_expect(Items.meal(Net.ITEM_STEW) and not Items.meal(Net.ITEM_FOOD), "a stew is a dish, a ration is not")
	_expect(not server.map.stove.is_empty(), "the ship has a galley stove")
	var helm: int = server.map.helm.keys()[0]
	var engine: int = server.map.engine.keys()[0]
	_expect(Upkeep.part_for(server.map, helm) == Net.ITEM_BOARD and Upkeep.part_for(server.map, engine) == Net.ITEM_PART,
		"the helm wants a board, the engine a mechanical part")


# --------------------------------------------------------------- hunger

func _hunger() -> void:
	print("  -- long hunger slows, then kills")
	_clear()
	var p = _man("Голодный")
	server.ship.store[Net.ITEM_FOOD] = 0
	server.garden.jumped()
	_expect(server.garden.starving(), "no rations at a jump: the crew starve")
	for s in int(Garden.WEAK_AFTER) - 1:
		server.garden._feed_tick()
	_expect(not p.weak and p.health >= Garden.STARVE_FLOOR - 0.01, "before %d s they are not weak yet, health %.0f" % [int(Garden.WEAK_AFTER), p.health])
	server.garden._feed_tick()
	_expect(p.weak and p.st.slow and p.slowed(), "after %d s of hunger they walk slowly" % int(Garden.WEAK_AFTER))
	for s in int(Garden.DEADLY_AFTER - Garden.WEAK_AFTER) - 1:
		server.garden._feed_tick()
	_expect(p.health >= Garden.STARVE_FLOOR - 0.01, "until hunger is deadly health stays at %.0f or more (%.1f)" % [Garden.STARVE_FLOOR, p.health])
	for s in 300:
		server.garden._feed_tick()
	_expect(p.health < Garden.STARVE_FLOOR - 10.0, "once deadly it sinks below the old floor (%.1f)" % p.health)
	while server.garden.hunger < Net.HEALTH_FULL - Net.HEALTH_DEAD and server.garden.starved < 20000.0:
		server.garden._feed_tick()
	server.garden._feed_tick()
	_run(1)
	_expect(p.cond == Net.COND_DEAD, "starved long enough, one dies (health %.0f)" % p.health)
	# fed again, it stops at once
	_clear()
	var q = _man("Сытый")
	server.ship.store[Net.ITEM_FOOD] = 0
	server.garden.jumped()
	for s in int(Garden.WEAK_AFTER) + 5:
		server.garden._feed_tick()
	_expect(q.weak, "starving again: weak")
	server.ship.store[Net.ITEM_FOOD] = 4
	server.garden._feed_tick()
	_expect(not server.garden.starving() and not q.weak and not q.st.slow and server.garden.starved == 0.0,
		"rations in the locker: the hunger passes, they walk as before")
	server.garden.hunger = 0.0
	_clear()


# --------------------------------------------------------------- the galley

func _cooking() -> void:
	print("  -- the galley's stove cooks")
	_clear()
	var p = _man("Кок")
	var stove: int = server.map.stove.keys()[0]
	_stand_at(p, stove)
	server.ship.store[Net.ITEM_FOOD] = 3
	server.ship.store[Net.ITEM_MEDPATCH] = 1
	server.ship.store[Net.ITEM_STEW] = 0
	server.ship.store[Net.ITEM_BROTH] = 0
	_expect(server.galley.at_stove(p) == stove, "the cook stands at the stove")
	server.workshop.asked(p, Net.BENCH_STEW, 0)
	_expect(not p.bench.is_empty(), "a stew is on")
	_run(roundi(Galley.COOK_SECONDS * Net.TICK_HZ) + 2)
	_expect(int(server.ship.store[Net.ITEM_STEW]) == 1 and int(server.ship.store[Net.ITEM_FOOD]) == 1,
		"a stew cooked of two rations (rations left %d)" % int(server.ship.store[Net.ITEM_FOOD]))
	server.workshop.asked(p, Net.BENCH_BROTH, 0)
	_run(roundi(Galley.COOK_SECONDS * Net.TICK_HZ) + 2)
	_expect(int(server.ship.store[Net.ITEM_BROTH]) == 1 and int(server.ship.store[Net.ITEM_FOOD]) == 0 and int(server.ship.store[Net.ITEM_MEDPATCH]) == 0,
		"a broth of a ration and a plaster")
	server.workshop.asked(p, Net.BENCH_COFFEE, 0)
	_expect(p.bench.is_empty(), "no rations left: nothing is put on")
	# stepping away puts it down
	server.ship.store[Net.ITEM_FOOD] = 2
	server.workshop.asked(p, Net.BENCH_COFFEE, 0)
	_run(10)
	p.st.facing = Net.DIR_UP if p.st.facing != Net.DIR_UP else Net.DIR_LEFT
	_run(roundi(Galley.COOK_SECONDS * Net.TICK_HZ) + 2)
	_expect(p.bench.is_empty() and int(server.ship.store.get(Net.ITEM_COFFEE, 0)) == 0, "turning away from the stove leaves the coffee uncooked")
	_clear()


func _meals() -> void:
	print("  -- the dishes do what they say")
	_clear()
	var p = _man("Едок")
	p.wounds = 20.0
	p.health = 80.0
	p.slots[0] = Net.ITEM_STEW
	p.hand = 0
	server.combat.use_at(p, server.tick, Vector2(p.st.x, p.st.y))
	_expect(p.meal == Net.ITEM_STEW and p.slots[0] == Net.ITEM_NONE, "a stew eaten")
	_run(Net.TICK_HZ * 30)
	_expect(p.wounds < 20.0 - 2.0 and p.wounds > 20.0 - 4.0, "in 30 s the stew closed ~3 wounds (%.1f left)" % p.wounds)
	p.slots[0] = Net.ITEM_COFFEE
	server.inventory.act(p)
	_expect(p.meal == Net.ITEM_COFFEE and is_equal_approx(p.pace(server.tick), 0.75), "coffee drunk with Z: work takes three quarters of its time")
	var hole := _hole_near(p)
	p.slots[1] = Net.ITEM_PATCH
	p.using = true
	var took := 0
	while server.air.holes.has(hole) and took < 2000:
		server.repairs.update(p)
		took += 1
	p.using = false
	_expect(took == roundi(Net.REPAIR_TICKS * 0.75), "a hole patched in %d ticks with coffee (%d plain)" % [took, Net.REPAIR_TICKS])
	_run(roundi(float(Items.INFO[Net.ITEM_COFFEE]["meal"]) * Net.TICK_HZ) + Net.TICK_HZ)
	_expect(p.meal == 0 and p.pace(server.tick) == 1.0, "the coffee wears off")
	# the broth, given to a neighbour
	var q = _man("Раненый")
	q.st.place(p.st.x + 1, p.st.y) if server.map.walkable(p.st.x + 1, p.st.y) else q.st.place(p.st.x - 1, p.st.y)
	q.bleeding = 200
	q.concussed = server.tick + 2000
	q.wounds = 30.0
	q.health = 70.0
	p.slots[0] = Net.ITEM_BROTH
	p.hand = 0
	server.combat.use_at(p, server.tick, Vector2(q.st.x, q.st.y))
	_expect(q.bleeding == 0 and q.concussed == 0 and is_equal_approx(q.wounds, 15.0), "a broth given to a neighbour: no bleeding, no concussion, 15 wounds closed")
	_clear()


func _hole_near(p) -> int:
	## A hole in the cell p faces (made there if it is a wall of our hull), or one below it.
	var w: int = server.map.width
	for d in range(1, 5):
		var c: int = (p.st.y + Net.DY[d]) * w + p.st.x + Net.DX[d]
		if server.map.hull.has(c) and not server.map.is_other(c):
			p.st.facing = d
			server.air.set_hole(c, true)
			return c
	# no hull beside it: move next to some hull wall
	for c: int in server.map.hull:
		if server.map.is_other(c):
			continue
		var x := c % w
		var y := c / w
		for d in range(1, 5):
			var fx := x - Net.DX[d]
			var fy := y - Net.DY[d]
			if server.map.walkable(fx, fy) and server.map.on_ship(fy * w + fx) and server.map.door_at(fx, fy) < 0:
				p.st.place(fx, fy)
				p.st.dir = Net.DIR_NONE
				p.st.facing = d
				server.air.set_hole(c, true)
				return c
	return -1


# --------------------------------------------------------------- complex repairs

func _mend_ticks(p, cell: int) -> int:
	## Holds "use" at the broken thing in that cell until it works again: the ticks it took.
	server.ship.broken[cell] = true
	_stand_at(p, cell)
	p.skills = PackedByteArray([0, 0, 0, 0])
	p.using = true
	p.work = 0
	var took := 0
	while server.ship.broken.has(cell) and took < 20000:
		server.repairs.update(p)
		took += 1
	p.using = false
	return took


func _complex() -> void:
	print("  -- complex repairs")
	_clear()
	server.complex_repairs = true
	var p = _man("Механик")
	var helm: int = server.map.helm.keys()[0]
	var engine: int = server.map.engine.keys()[0]
	var plain := Net.REPAIR_TICKS
	_expect(_mend_ticks(p, helm) == plain * Net.NO_PART_SLOWER * Net.NO_TOOLS_SLOWER, "the helm with nothing: %d× as long" % (Net.NO_PART_SLOWER * Net.NO_TOOLS_SLOWER))
	p.slots[0] = Net.ITEM_TOOLBOX
	p.slots[1] = Net.ITEM_PART
	_expect(_mend_ticks(p, helm) == plain * Net.NO_PART_SLOWER and p.slots[1] == Net.ITEM_PART,
		"the helm with a toolbox and a mechanical part: 3× as long, and the part is kept")
	p.slots[2] = Net.ITEM_BOARD
	_expect(_mend_ticks(p, helm) == plain and p.slots[2] == Net.ITEM_NONE and p.slots[0] == Net.ITEM_TOOLBOX,
		"the helm with a toolbox and a board: plain time, the board used up, the toolbox kept")
	_expect(_mend_ticks(p, engine) == plain and p.slots[1] == Net.ITEM_NONE, "the engine with a toolbox and a part: plain time")
	p.slots[0] = Net.ITEM_NONE
	p.slots[1] = Net.ITEM_PART
	_expect(_mend_ticks(p, engine) == plain * Net.NO_TOOLS_SLOWER, "the engine with a part but no toolbox: 3× as long")
	var e = _man("Инженер")
	e.slots.fill(Net.ITEM_NONE)
	e.job = Net.JOB_ENGINEER
	server.crew._kit_out(e)
	_expect(e.count(Net.ITEM_TOOLBOX) == 1 and e.count(Net.ITEM_BOARD) == 1, "with complex repairs an engineer comes aboard with a toolbox and a board")
	_expect(int(server.crew.campaign_packet()[17]) & Net.CAMPAIGN_COMPLEX != 0, "the campaign packet tells clients complex repairs are on")
	_clear()


func _plain() -> void:
	print("  -- the plain game takes any part")
	_clear()
	server.complex_repairs = false
	var p = _man("Ремонтник")
	var helm: int = server.map.helm.keys()[0]
	var engine: int = server.map.engine.keys()[0]
	_expect(_mend_ticks(p, engine) == Net.REPAIR_TICKS * Net.NO_PART_SLOWER, "no part: 3× as long, no toolbox needed")
	p.slots[0] = Net.ITEM_BOARD
	_expect(_mend_ticks(p, engine) == Net.REPAIR_TICKS and p.slots[0] == Net.ITEM_NONE, "a board mends the engine as quickly as a part")
	p.slots[0] = Net.ITEM_PART
	_expect(_mend_ticks(p, helm) == Net.REPAIR_TICKS and p.slots[0] == Net.ITEM_NONE, "a part mends the helm as quickly as a board")
	var e = _man("Инженер")
	e.slots.fill(Net.ITEM_NONE)
	e.job = Net.JOB_ENGINEER
	server.crew._kit_out(e)
	_expect(e.count(Net.ITEM_TOOLBOX) == 0, "without complex repairs nobody is handed a toolbox")
	_clear()


func _bots() -> void:
	print("  -- bots fetch what complex repairs want")
	_clear()
	server.complex_repairs = true
	var b = _man("Бот")
	b.bot = true
	server.ship.store[Net.ITEM_TOOLBOX] = 2
	server.ship.store[Net.ITEM_BOARD] = 2
	server.ship.store[Net.ITEM_PART] = 2
	server.ship.broken[server.map.helm.keys()[0]] = true
	var want: Array = server.stations._supplies_wanted(b)
	_expect(want.has(Net.ITEM_TOOLBOX) and want.has(Net.ITEM_BOARD) and not want.has(Net.ITEM_PART),
		"a broken helm: a bot fetches a toolbox and a board (%s)" % str(want))
	server.ship.broken = {}
	server.ship.broken[server.map.engine.keys()[0]] = true
	want = server.stations._supplies_wanted(b)
	_expect(want.has(Net.ITEM_PART) and not want.has(Net.ITEM_BOARD), "a broken engine: a mechanical part")
	server.complex_repairs = false
	want = server.stations._supplies_wanted(b)
	_expect(want == [Net.ITEM_PART], "plain repairs: just a part, as before")
	_clear()


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		failed += 1
		print("FAIL ", what)
