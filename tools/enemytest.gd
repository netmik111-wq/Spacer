extends SceneTree
## Checks the enemies of v62 (the author's road plan), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/enemytest.gd
## A drone ship comes only to fight at a distance, with no air and no crew; it
## sends assault drones while its core works, its repair drones mend it, it is
## taken by wrecking its core by hand. A pirate's teleporter puts some of its
## crew aboard us and its counts stay in step. Boarders may come without suits
## or in heavy armour. Bombs go past the shield into the room aimed at; theirs
## burst inside our ship. «Шрапнель» spreads into the next room. The flagship's
## second phase mends it and makes it fight harder. The new modules and the
## bay's extender do what they say. Our security robot is set down, fights
## pirates, is no crewman and goes back into the locker when saved.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Assault := preload("res://src/server/assault.gd")
const Pirates := preload("res://src/server/pirates.gd")
const Robots := preload("res://src/server/robots.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Items := preload("res://src/shared/items.gd")

var failed := 0
var server: GameServer
var kept: Array = []


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26390, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	_drone_ship()
	_teleport()
	_boarders()
	_bombs()
	_phase_two()
	_modules()
	_robots()
	server.stop()
	print("enemytest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _drone_ship() -> void:
	print("  -- the drone ship")
	var d = server.derelict
	var g = server.gunnery
	var map = server.map
	server.shipyard.force_class = Net.ECLASS_DRONE
	_expect(d.pirates_come(3, false) and d.raid and g.crewless, "a drone ship comes, and only to fight at a distance")
	server.shipyard.force_class = -1
	_expect(g.temper == Net.TEMPER_MACHINE and float(Hulls.temper(g.temper)["flee"]) == 0.0, "a machine: it never runs")
	_expect(g.room_of_system(Net.ESYS_DRONES) >= 0 and g.room_of_system(Net.ESYS_HELM) < 0 and g.room_of_system(Net.ESYS_CREW) < 0,
		"it has a control core, and no cockpit or quarters")
	var airless := true
	for c in map.other_cells:
		if map.walk[c] == 1 and server.air.air[c] > 0.01:
			airless = false
	_expect(airless, "there is no air aboard it")
	_expect(server.enemy_crew.manned(Net.ESYS_WEAPONS) and server.enemy_crew.manned(Net.ESYS_HELM), "nobody need man its posts")
	_expect(g.boarders_left() == server.enemy_crew.count() and g.boarders_left() == 2, "two guard robots stand by its core (%d)" % g.boarders_left())
	# its assault drones
	g.enemy_hit_chance = 0.0
	server.ship.guard_armed = false
	_expect(server.assault.sends_drones(), "while its core works it sends assault drones")
	var before: int = server.assault.robots_aboard()
	_expect(server.assault.launch(), "one sets off")
	_run(roundi(Assault.DRONE_FLIGHT * Net.TICK_HZ) + 2)
	_expect(server.assault.robots_aboard() == before + 1, "it cuts its way in and comes aboard")
	var robot = null
	for p in server.players:
		if p != null and p.pirate and p.robot and not p.corpse and map.on_ship(p.st.y * map.width + p.st.x):
			robot = p
	_expect(robot != null and not robot.has_suit() and robot.colour == Net.ROBOT_COLOUR, "a robot, wearing nothing")
	if robot != null:
		server.air.air[robot.st.y * map.width + robot.st.x] = 0.0
		var health: float = robot.health
		_run(Net.TICK_HZ * 5)
		_expect(robot.health >= health - 0.01, "it needs no air")
		server.combat.hurt(robot, 999, null)
		_run(2)
	server.assault.launch()
	server.assault.launch()
	server.assault.launch()
	_expect(server.assault.robots_aboard() + server.assault._landing.size() <= Assault.DRONES_ABOARD, "no more than %d at once" % Assault.DRONES_ABOARD)
	server.assault._landing = PackedInt32Array()
	# its repair drones
	g._mend_next = 0
	g.systems[Net.ESYS_WEAPONS] = 0
	_run(roundi(Gunnery.ENEMY_REPAIR_SECONDS / Gunnery.DRONE_REPAIR * Net.TICK_HZ) + 10)
	_expect(g.systems[Net.ESYS_WEAPONS] >= 1, "its repair drones mend its guns")
	g.systems[Net.ESYS_WEAPONS] = 0
	g.systems[Net.ESYS_DRONES] = 0
	_run(roundi(Gunnery.ENEMY_REPAIR_SECONDS / Gunnery.DRONE_REPAIR * Net.TICK_HZ) + 10)
	_expect(g.systems[Net.ESYS_WEAPONS] == 0 and not server.assault.sends_drones(), "its core out: no mending, no drones")
	g.systems[Net.ESYS_DRONES] = g.systems_full[Net.ESYS_DRONES]
	# taken by hand
	var credits: int = server.ship.credits
	var reward: int = g.reward
	var boarder = server.crew.new_player("Абордажник")
	boarder.worn[Net.WEAR_SUIT] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	var room: int = g.room_of_system(Net.ESYS_DRONES)
	var cell: int = d._cell(map.other_at, map.other.rooms[room][0])
	boarder.st.place(cell % map.width, cell / map.width)
	kept = [boarder]
	_run(2)
	var guards := 0
	for p in server.enemy_crew.people:
		if p != null and p.robot:
			guards += 1
	_expect(server.enemy_crew.in_world and guards == 2, "its guard robots wake when we board (%d)" % guards)
	_expect(g.fighting(), "killing them does not take it")
	for k in g.systems_full[Net.ESYS_DRONES]:
		g.wear_by_hand(Net.ESYS_DRONES)
	_run(2)
	_expect(not g.fighting() and d.wreck, "its core wrecked by hand: it is ours")
	_expect(server.ship.credits - credits == roundi(reward * Gunnery.CAPTURE_SHARE), "and pays as a capture (%d)" % (server.ship.credits - credits))
	kept = []
	server.crew.remove(boarder)
	for p in server.players:
		if p != null and p.pirate:
			server.crew.remove(p)
	d._leave(true)
	g.enemy_hit_chance = -1.0
	_run(2)


func _teleport() -> void:
	print("  -- the teleporter")
	var d = server.derelict
	var g = server.gunnery
	var map = server.map
	server.shipyard.force_class = Net.ECLASS_CRUISER
	server.shipyard.force_teleport = true
	var tries := 0
	while tries < 20:
		tries += 1
		_expect_quiet(d.pirates_come(3, true))
		if g.teleport and g.boarders_left() >= Assault.TELEPORT_KEEP + 2:
			break
		g.enemy_gone()
		d.pirates_wrecked()
		_run(2)
	server.shipyard.force_class = -1
	server.shipyard.force_teleport = false
	_expect(g.teleport and g.room_of_system(Net.ESYS_TELEPORT) >= 0, "a pirate may carry a teleporter, in a room of its own")
	g.enemy_hit_chance = 0.0
	_run(Net.TICK_HZ * 3)                                    # (its crew walk to their posts)
	var crew: int = g.boarders_left()
	var aboard: int = server.pirates.aboard()
	var n: int = server.assault.teleport()
	_expect(n > 0 and n <= Assault.TELEPORT_PARTY and server.assault.charging() and server.pirates.aboard() == aboard,
		"(v89) its teleport charges first, nobody yet (%d to come)" % n)
	_run(roundi(Assault.TELEPORT_WARN * Net.TICK_HZ) + 1)
	_expect(not server.assault.charging(), "and lands them %d s later" % roundi(Assault.TELEPORT_WARN))
	var landed := 0
	var suited := 0
	var rooms := {}
	for p in server.players:
		if p != null and p.pirate and not p.corpse and map.on_ship(p.st.y * map.width + p.st.x):
			landed += 1
			suited += 1 if p.has_suit() or p.toughness < 1.0 else 0
			rooms[map.room_at(p.st.x, p.st.y)] = true
	_expect(landed == n and server.pirates.aboard() == aboard + n, "they stand on our ship")
	_expect(suited == landed, "(v89) all in suits (or heavy armour)")
	_expect(rooms.size() == landed, "(v89) each in a room of its own")
	_expect(g.boarders_left() == crew - n and server.enemy_crew.count() == crew - n and d._pirates_party == crew - n,
		"its crew counts follow (%d left)" % g.boarders_left())
	g.systems[Net.ESYS_TELEPORT] = 0
	_expect(server.assault.teleport() == 0, "with its teleporter out, nobody comes")
	for p in server.players:
		if p != null and p.pirate:
			server.crew.remove(p)
	g.enemy_gone()
	d.pirates_wrecked()
	g.enemy_hit_chance = -1.0
	_run(2)


func _boarders() -> void:
	print("  -- boarders without suits")
	var bare := 0
	var heavy := 0
	var near_bare := 0
	for i in 200:
		var p = server.pirates.spawn_boarder(1, 1, true, 10)
		if not p.has_suit():
			bare += 1
		if p.toughness < 1.0:
			heavy += 1
		server.crew.remove(p)
		var q = server.pirates.spawn_boarder(1, 1, true, 1)
		if not q.has_suit():
			near_bare += 1
		server.crew.remove(q)
	_expect(bare > 20 and heavy > 5, "far out, some come without a suit (%d of 200), some in heavy armour (%d)" % [bare, heavy])
	_expect(near_bare == 0, "near the start, all wear suits")
	var tough = null
	for i in 400:
		var p = server.pirates.spawn_boarder(1, 1, true, 10)
		if p.toughness < 1.0:
			tough = p
			break
		server.crew.remove(p)
	if tough != null:
		var h: float = tough.health
		server.combat.hurt(tough, 40, null)
		_expect(absf(h - tough.health - 40 * Pirates.HEAVY_TOUGHNESS) < 0.01, "heavy armour takes half of a wound")
		server.crew.remove(tough)


func _bombs() -> void:
	print("  -- bombs and fragments")
	var d = server.derelict
	var g = server.gunnery
	var map = server.map
	server.shipyard.force_class = Net.ECLASS_GUNSHIP
	_expect(d.pirates_come(3, true), "(a gunship to fight)")
	server.shipyard.force_class = -1
	g.enemy_hit_chance = 0.0
	g.enemy_shield = Weapons.SHIELD_FULL
	g.aim = Net.ESYS_ENGINE
	g.revealed.fill(1)
	var hull: int = g.enemy_hull
	var landed := false
	for i in 20:
		var was: int = g.systems[Net.ESYS_ENGINE]
		g._our_bomb(0, Weapons.HORNET, Weapons.FX_NONE)
		if g.systems[Net.ESYS_ENGINE] < was:
			landed = was - g.systems[Net.ESYS_ENGINE] == mini(was, 2)
			break
	_expect(landed, "our bomb lands in the room aimed at and wears its system by 2")
	_expect(g.enemy_hull == hull and g.enemy_shield == Weapons.SHIELD_FULL, "past its full shield, and the hull untouched")
	var room: int = g.room_of_system(Net.ESYS_WEAPONS)
	var other := false
	for i in 20:
		other = other or g._beside(room) != room
	_expect(other, "«Шрапнель» can spread into a room next door")
	# theirs, on us
	var crewman = server.crew.new_player("Механик")
	kept = []
	g.enemy_hit_chance = 1.0
	var our_hull: int = server.ship.hull
	var hurt := false
	# (aimed at a device, a bomb hurts only who stands in that room: with every
	# device it could aim at already out, it goes for the crewman himself)
	var was_broken: Dictionary = server.ship.broken.duplicate()
	for c: int in Array(server.map.guns) + server.map.chart.keys() + server.map.helm.keys() + server.map.smes.keys() + [g.shield_cell()]:
		if c >= 0:
			server.ship.broken[c] = true
	# (it then picks one of our people by lot, bots too, so look at everybody aboard)
	for i in 10:
		for p in server.players:
			if p != null and not p.pirate and not p.corpse:
				p.health = 100.0
				p.wounds = 0.0
		g._enemy_bomb(Weapons.THERMITE, Weapons.FX_NONE)
		for p in server.players:
			if p != null and not p.pirate and not p.corpse:
				hurt = hurt or p.health < 100.0
	_expect(server.ship.hull < our_hull, "their «Термит» burns our hull from inside (%d -> %d)" % [our_hull, server.ship.hull])
	_expect(hurt, "and hurts whoever is in the room it bursts in")
	server.ship.broken = was_broken
	server.systems.power_changed()
	server.ship.hull = Net.HULL_MAX
	server.crew.remove(crewman)
	g.enemy_hit_chance = -1.0
	g.aim = Net.AIM_ANY
	g.enemy_gone()
	d.pirates_wrecked()
	_run(2)
	for c: int in server.air.holes.keys():
		server.air.set_hole(c, false)
	_run(2)


func _phase_two() -> void:
	print("  -- the flagship's second phase")
	var g = server.gunnery
	_expect(server.flagship.call_in(1), "(the battleship comes)")
	g.enemy_hit_chance = 0.0
	_expect(not g.phase2 and not server.assault.sends_drones(), "at first it sends no drones")
	g.systems[Net.ESYS_SHIELDS] = 0
	g.systems[Net.ESYS_WEAPONS] = 1
	g.enemy_shield = 0.0
	g.enemy_hull = roundi(g.hull_full() / 3.0)
	_run(2)
	_expect(g.phase2, "at a third of its hull it goes into its second phase")
	_expect(g.systems[Net.ESYS_SHIELDS] == g.systems_full[Net.ESYS_SHIELDS] and g.systems[Net.ESYS_WEAPONS] == g.systems_full[Net.ESYS_WEAPONS]
		and g.enemy_shield > 0.0, "everything mended at once, its shield back")
	_expect(server.assault.sends_drones(), "and now it sends assault drones")
	g.enemy_gone()
	server.derelict.pirates_wrecked()
	_run(2)
	_expect(server.flagship.call_in(2), "(the carrier comes)")
	var troops: int = server.flagship.troops
	g.enemy_hull = roundi(g.hull_full() / 3.0)
	_run(2)
	_expect(g.phase2 and server.flagship.troops == troops + 4 and server.flagship._party == 3, "the carrier calls up more troops, sends more at a time")
	for p in server.players:
		if p != null and p.pirate:
			server.crew.remove(p)
	g.enemy_gone()
	server.derelict.pirates_wrecked()
	g.enemy_hit_chance = -1.0
	_run(2)


func _modules() -> void:
	print("  -- the new modules and the bay's extender")
	var ship = server.ship
	var g = server.gunnery
	ship.modules = PackedByteArray([0, 0])
	server.outfit.refresh()
	_expect(server.outfit.jump_jam() == 1.0 and server.outfit.welder() == 0 and server.outfit.loader() == 1.0, "(none in the bay)")
	ship.modules = PackedByteArray([Gear.JAMMER, Gear.WELDER])
	server.outfit.refresh()
	_expect(server.outfit.jump_jam() == Gear.JAMMER_SHARE, "the jump jammer slows their escape jump")
	ship.hull = 100
	server.outfit.jumped()
	_expect(ship.hull == 100 + Gear.WELDER_HULL, "the welding drone mends the hull after a jump")
	ship.modules = PackedByteArray([Gear.SALVAGE, Gear.LOADER])
	server.outfit.refresh()
	_expect(server.outfit.salvage_share() == Gear.SALVAGE_SHARE and server.outfit.salvage_parts() == 1, "the salvage arm")
	_expect(server.mounts.pace(0) == Gear.LOADER_PACE, "the auto-loader: a gun with nobody at it charges faster")
	# the extender, by an engineer at the bay
	var eng = server.crew.new_player("Инженер")
	eng.job = Net.JOB_ENGINEER
	var bay: int = server.map.bay.keys()[0]
	eng.slots[eng.hand] = Gear.item_of(Gear.BAY_SLOT)
	_expect(server.outfit.can(eng, bay) == "", "an engineer may fit the extender at the bay")
	server.outfit.finish(eng, bay)
	_expect(ship.modules.size() == 3 and eng.slots[eng.hand] == Net.ITEM_NONE, "the bay has a third slot, and the extender is used up")
	eng.slots[eng.hand] = Gear.item_of(Gear.BAY_SLOT)
	_expect(server.outfit.can(eng, bay) != "", "a second one does not go in")
	eng.slots[eng.hand] = Gear.item_of(Gear.FOCUS)
	_expect(server.outfit.can(eng, bay) == "", "a third module goes in")
	server.outfit.finish(eng, bay)
	_expect(ship.modules.has(Gear.FOCUS) and ship.modules.has(Gear.SALVAGE) and ship.modules.has(Gear.LOADER), "three modules at once")
	var data: Dictionary = JSON.parse_string(JSON.stringify(Campaign.snapshot(server)))
	ship.modules = PackedByteArray([0, 0])
	var why := Campaign.restore(server, data)
	_expect(why == "" and ship.modules.size() == 3 and ship.modules.has(Gear.FOCUS), "the third slot survives a save")
	server.crew.remove(eng)
	ship.modules = PackedByteArray([0, 0])
	server.outfit.refresh()


func _robots() -> void:
	print("  -- our security robots")
	var map = server.map
	var p = server.crew.new_player("Охранник")
	kept = [p]
	var living: int = server.crew.living_crew()
	var spot := _free_beside(p)
	_expect(spot.x >= 0, "(a free cell beside)")
	p.slots[p.hand] = Net.ITEM_NONE
	p.add(Net.ITEM_ROBOT, true)
	_expect(Items.price(Net.ITEM_ROBOT) > 0 and Items.kept_in_locker().has(Net.ITEM_ROBOT), "a robot comes in a crate, kept in the locker")
	_expect(server.robots.deploy(p, spot), "set down beside its carrier, it switches on")
	var robots: Array = server.robots.aboard()
	_expect(robots.size() == 1 and robots[0].ally and robots[0].robot and not robots[0].pirate and not robots[0].has_suit(),
		"a machine on our side, wearing nothing")
	_expect(server.crew.living_crew() == living, "it is no crewman")
	_expect(p.slots[p.hand] == Net.ITEM_NONE, "the crate is gone from the hand")
	# it fights a pirate in sight
	var robot = robots[0]
	var foe = null
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(3, 0), Vector2i(-3, 0)]:
		var c: Vector2i = Vector2i(robot.st.x, robot.st.y) + d
		if map.walkable(c.x, c.y) and map.on_ship(c.y * map.width + c.x) and map.door_at(c.x, c.y) < 0:
			# (in sight: facing it and in the same room, else it may never notice an unarmed one)
			server.pirates._face(robot, Vector2(c))
			foe = server.pirates.spawn(c.x, c.y, false)
			if server.pirates._sees(robot, foe):
				break
			server.crew.remove(foe)
			foe = null
	_expect(foe != null, "(a pirate set down in its sight)")
	if foe != null:
		foe.slots.fill(Net.ITEM_NONE)                     # (unarmed: it is the robot we watch)
		var h: float = foe.health
		var at := Vector2i(foe.st.x, foe.st.y)
		for t in Net.TICK_HZ * 15:
			if foe.corpse or foe.health < h:
				break
			if Vector2i(foe.st.x, foe.st.y) != at:
				foe.st.place(at.x, at.y)                  # (kept where it was set down: a shot may miss, and it would wander off)
			server._tick()
		_expect(foe.corpse or foe.health < h or foe.cond != Net.COND_OK, "it shoots a pirate it sees (%.0f -> %.0f)" % [h, foe.health])
		if not foe.corpse:
			server.crew.remove(foe)
	# no more than two
	p.add(Net.ITEM_ROBOT, true)
	var second := _free_beside(p)
	_expect(server.robots.deploy(p, second), "a second one")
	p.add(Net.ITEM_ROBOT, true)
	var third := _free_beside(p)
	_expect(not server.robots.deploy(p, third), "but not a third")
	p.slots[p.hand] = Net.ITEM_NONE
	# saved: back into the locker
	var had := int(server.ship.store.get(Net.ITEM_ROBOT, 0))
	var data: Dictionary = Campaign.snapshot(server)
	_expect(int(data["store"][str(Net.ITEM_ROBOT)]) == had + server.robots.aboard().size(), "a save puts them back into the locker in their crates")
	# broken, it may leave a part
	var r = server.robots.aboard()[0]
	server.combat.hurt(r, 999, null)
	_run(3)
	_expect(server.robots.aboard().size() == 1, "one broken: it is gone from the guard")
	kept = []


func _free_beside(p) -> Vector2i:
	var map = server.map
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var c: Vector2i = Vector2i(p.st.x, p.st.y) + d
		var taken := false
		for q in server.players:
			if q != null and q.st.x == c.x and q.st.y == c.y:
				taken = true
		if not taken and map.walkable(c.x, c.y) and map.door_at(c.x, c.y) < 0 and map.on_ship(c.y * map.width + c.x):
			return c
	return Vector2i(-1, -1)


func _run(ticks: int) -> void:
	for t in ticks:
		for k in kept:
			k.health = 100.0
			k.wounds = 0.0
			k.tank = 1.0
		server._tick()


func _expect_quiet(ok: bool) -> void:
	if not ok:
		print("  (a pirate ship could not come)")


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
