extends SceneTree
## (v99) Checks the made asteroids, landing on them, their mantises and the made stations, on a real server
## stepped by hand:
##   godot --headless --path . --script res://tools/asteroidtest.gd
## Every asteroid and station PlaceMaker makes builds with no problem and lies off ship02's airlock (an asteroid
## with caves both alongside and landed on: its mouth right over our outer door); the caves join the mouth. By an
## asteroid place a made asteroid comes, says it has caves; the ship lands on it from the helm (and not on a solid
## one), stays put and is out of the meteors' way while landed. The first of ours on it wakes its mantises deep in
## the caves, asleep until they see somebody; a mantis leaps over the one cell between it and its target and
## strikes 30 at once, strikes again 1.2 s on, takes less from bullets (chitin) than from lasers, needs no air, dies
## at 0 leaving a claw on its body, is no foe of pirates; it follows one aboard and stays there when the asteroid
## is left, while those still on the asteroid are there again next time. A station's rooms hold what their kinds
## do. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const MapBuilder := preload("res://src/shared/map_builder.gd")
const PlaceMaker := preload("res://src/shared/place_maker.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Combat := preload("res://src/server/combat.gd")

var failed := 0
var server: GameServer
var said: Array = []


func _initialize() -> void:
	_drawings()
	_choose_set()
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26660, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.log_line.connect(func(t: String) -> void: said.append(t))
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.stations.volunteers = false
	server.pirates.goals_on = false
	server.wing.chance_for_test = 0.0
	server.defence.on = false
	server.systems.vents_on = false
	for q in server.players.duplicate():
		if q != null and q.bot:
			server.crew.remove(q)            # (no crew bots about: what the mantises see is the checks' own)
	server.ship.pos = Vector2(100, 100)
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	_run(2)
	_asteroid()
	_mantises()
	_station()
	print("asteroidtest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	quit(0 if failed == 0 else 1)


# ---------------------------------------------------------------- drawings

func _drawings() -> void:
	print("  -- asteroids and stations made from pieces")
	var ship := ShipMap.new()
	ship.load_from("ship02")
	var ours: Vector2i = ship.doors[int(ship.lock_pump.values()[0]["outer"])]
	var tiles := FileAccess.get_file_as_string("res://assets/tiles.json")
	var bad := 0
	var misfit := 0
	var mouths := 0
	var cut_off := 0
	var small_caves := 0
	var stations := 0
	var rooms_bad := 0
	for s in 40:
		var made := PlaceMaker.make_set(2000 + s)
		for n: String in made:
			var text := str(made[n])
			var built := MapBuilder.build(n, text)
			if not (built["problems"] as Array).is_empty():
				bad += 1
				if bad <= 3:
					print("    %s\n%s" % [(built["problems"][0] as Dictionary), text])
				continue
			var o := ShipMap.new()
			if o.load_data(n, tiles, built["data"], false) != "":
				bad += 1
				continue
			var info := PlaceMaker.info(text)
			ship.others = [o]
			ship.other = o
			if str(built["kind"]) == "asteroid":
				var mouth: Vector2i = info["mouth"]
				if mouth.x < 0:
					continue
				mouths += 1
				var at := ours - mouth - Vector2i(0, 1)
				if mouth.y != o.height - 1 or not ship.other_fits(at) or not ship.other_fits(at - Vector2i(0, 3)):
					misfit += 1
				# every bare cell joins the mouth
				var ground := {}
				for i in o.cells.size():
					if o.walk[i] == 1:
						ground[Vector2i(i % o.width, i / o.width)] = true
				var seen := {mouth: true}
				var todo := [mouth]
				while not todo.is_empty():
					var c: Vector2i = todo.pop_back()
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if ground.has(c + d) and not seen.has(c + d):
							seen[c + d] = true
							todo.append(c + d)
				if seen.size() != ground.size():
					cut_off += 1
				if ground.size() < 12:
					small_caves += 1
			elif text.contains("abandoned station"):
				stations += 1
				for e: Array in info["rooms"]:
					var c: Vector2i = e[0]
					if o.walk[c.y * o.width + c.x] != 1:
						rooms_bad += 1
	_expect(bad == 0, "every drawing of 40 sets builds with no problem (%d bad)" % bad)
	_expect(mouths == 40 * 6 and misfit == 0, "the caved asteroids' mouths are in their bottom row, over ship02's airlock, alongside and landed (%d of %d do not)" % [misfit, mouths])
	_expect(cut_off == 0 and small_caves == 0, "their caves join the mouth and are no mere hole (%d cut off, %d small)" % [cut_off, small_caves])
	_expect(stations == 40 * (PlaceMaker.COUNT - PlaceMaker.SHIPS) and rooms_bad == 0, "the stations' rooms are marked on their floor (%d bad)" % rooms_bad)


var seed_used := 0


func _choose_set() -> void:
	## A campaign's set whose large asteroid has mantises (the checks need one).
	for s in range(1, 400):
		var made := PlaceMaker.make_set(s)
		var info := PlaceMaker.info(str(made["made:%d" % (PlaceMaker.COUNT + PlaceMaker.ROCKS)]))
		if int(info["mantises"]) >= 1:
			seed_used = s
			ShipMap.drawings = {}
			ShipMap.make_places(s)
			return


# ---------------------------------------------------------------- an asteroid, landing

var rock_layout := -1


func _asteroid() -> void:
	print("  -- a made asteroid, landing on it")
	var map := server.map
	var der = server.derelict
	rock_layout = ShipMap.other_maps().find("made:%d" % (PlaceMaker.COUNT + PlaceMaker.ROCKS))
	var solid := ShipMap.other_maps().find("made:%d" % (PlaceMaker.COUNT + 1))
	_expect(der._rock_spots().has(rock_layout) and der._rock_spots().has(solid) and not der._rock_spots().has(map.others_of("asteroid")[0]),
		"the campaign's asteroids come instead of the old two")
	der.layout_for_test = solid
	_place_rock()
	_expect(der.here and der.layout == solid, "a small one comes alongside")
	_expect(der.dock(true) != "" and not der.docked, "a solid one cannot be landed on")
	_leave_rock()
	der._homes.clear()                       # (the same place: in a game it always brings the same drawing)
	der._left.clear()
	der.layout_for_test = rock_layout
	said.clear()
	_place_rock()
	_expect(der.here and der.layout == rock_layout and der.ship.name == "Большой астероид", "a large one comes, with its name")
	_expect(" ".join(said).contains("пещеры") and " ".join(said).contains("движение"), "the sensors say it has caves and something moves in them")
	var outer: Vector2i = map.doors[int(map.lock_pump.values()[0]["outer"])]
	_expect(not map.walkable(outer.x, outer.y - 1), "alongside, open space lies over our airlock")
	_expect(der.dock(true) == "" and der.docked and map.is_other((outer.y - 1) * map.width + outer.x) and map.walkable(outer.x, outer.y - 1),
		"landed: the cave's mouth is right over our airlock")
	_expect(server.air.air[(outer.y - 1) * map.width + outer.x] < 0.01, "and there is no air in it")
	_expect(der.holds_ship().contains("астероиде"), "the ship holds still while landed")
	_expect(not server.stations.meteor_seen(), "no meteor finds a landed ship")
	_run(20)
	_expect(der.here and der.docked, "it stays")
	_expect(der.dock(false) == "" and not der.docked and der.dock(true) == "", "it takes off and lands again")


func _place_rock() -> void:
	server.road._here_places = [[Sectors.P_ASTEROID, server.ship.pos]]
	server.road._places_for = server.ship.sector
	server.road.work[server.road._key(0)] = 50
	server.ship.moving = false
	_run(3)


func _leave_rock() -> void:
	server.road._here_places = []
	_run(3)


# ---------------------------------------------------------------- mantises

func _mantises() -> void:
	print("  -- mantises")
	var map := server.map
	var der = server.derelict
	var key: String = der.rock_key()
	var nest := int(der._homes[key]["mantises"])
	_expect(nest >= 1 and nest <= der.MANTISES_MAX, "it has a nest (%d)" % nest)
	_expect(_mantises_alive().is_empty(), "nobody shows before one of ours sets foot on it")
	var outer: Vector2i = map.doors[int(map.lock_pump.values()[0]["outer"])]
	var p = server.crew.new_player("Шахтёр", 0)
	p.st.place(outer.x, outer.y - 1)
	p.worn.fill(Net.ITEM_NONE)               # (what it takes is the claws' whole)
	_run(2)
	var found := _mantises_alive()
	_expect(found.size() == nest, "the first of ours on it wakes them (%d)" % found.size())
	var deep := true
	var mouth := Vector2(outer.x, outer.y - 1)
	var cells := der._ground_cells()
	var far := Vector2(cells[0] % map.width, cells[0] / map.width).distance_to(mouth)
	for m in found:
		deep = deep and Vector2(m.st.x, m.st.y).distance_to(mouth) >= far * 0.4
	_expect(deep, "deep in the caves")
	var m = found[0]
	p.st.place(outer.x, outer.y + 3)          # back aboard, out of sight
	_run(10)
	for o in found:
		o.ai_target = -1
		o.ai_goal = Vector2i(-1, -1)
	var at := Vector2i(m.st.x, m.st.y)
	_run(30)
	_expect(Vector2i(m.st.x, m.st.y) == at and m.health == Net.HEALTH_FULL, "asleep, it holds its place, and needs no air")
	_expect(server.pirates.foe(m, p) and not server.pirates.foe(m, _a_pirate()), "it is a foe of ours, not of pirates")
	# the leap: one empty cell between it and its target, straight
	var spot := _line_of_three()
	_expect(spot.size() == 3, "(three cells of ground in a row)")
	if spot.size() < 3:
		return
	for o in found:
		if o != m:
			o.st.place(outer.x, outer.y + 3)
			server.crew.remove(o)
	m.st.place(spot[0].x, spot[0].y)
	m.st.facing = Net.dir_of(signi(spot[2].x - spot[0].x), signi(spot[2].y - spot[0].y))
	m.ai_target = -1
	m.leap_ready = 0
	p.st.place(spot[2].x, spot[2].y)
	p.health = Net.HEALTH_FULL
	p.wounds = 0.0
	var leaps: int = server.mantises.leaps
	var first_hit := -1
	for t in 20:
		_run(1)
		if p.wounds > 0.0 and first_hit < 0:
			first_hit = t
	_expect(server.mantises.leaps == leaps + 1 and Vector2i(m.st.x, m.st.y) == spot[1], "it leaps over the cell between")
	_expect(first_hit >= 0 and first_hit <= 8 and absf(p.wounds - 30.0) < 0.5,
		"and strikes 30 as it lands (%d ticks, %.1f taken)" % [first_hit, p.wounds])
	_expect(m.ready_tick - server.tick > 0 and m.ready_tick - server.tick <= roundi(server.mantises.BLOW_SECONDS * Net.TICK_HZ),
		"the next blow comes 1.2 s on")
	p.wounds = 0.0
	p.health = Net.HEALTH_FULL
	_run(roundi(server.mantises.BLOW_SECONDS * Net.TICK_HZ) + 2)
	_expect(p.wounds >= 29.0, "and it comes (%.1f)" % p.wounds)
	# armour of the blow's kind takes its share
	p.worn[Net.WEAR_BODY] = Net.ITEM_VEST
	p.slots.fill(Net.ITEM_NONE)
	p.wounds = 0.0
	p.health = Net.HEALTH_FULL
	_run(roundi(server.mantises.BLOW_SECONDS * Net.TICK_HZ) + 2)
	_expect(p.wounds > 5.0 and p.wounds < 20.0, "a vest takes much of a blow (%.1f)" % p.wounds)
	server.crew.remove(p)
	# chitin, death, the claw
	var h0: float = m.health
	server.combat.hurt(m, 30, null, Combat.CAUSE_SHOT)
	var hp: float = server.mantises.MANTIS_HEALTH
	_expect(absf((h0 - m.health) / Net.HEALTH_FULL * hp - 24.0) < 0.01, "of its 80, a bullet takes 24 off its chitin (%.1f)" % ((h0 - m.health) / Net.HEALTH_FULL * hp))
	h0 = m.health
	server.combat.hurt(m, 30, null, Combat.CAUSE_LASER)
	_expect(absf((h0 - m.health) / Net.HEALTH_FULL * hp - 30.0) < 0.01, "a laser goes through whole")
	server.combat.hurt(m, 30, null, Combat.CAUSE_LASER)
	_run(2)
	_expect(m.cond == Net.COND_DEAD and m.corpse, "at 0 it dies (never out cold), and its body stays")
	_expect(m.slots.has(Net.ITEM_MANTIS_CLAW) and not m.slots.has(Net.ITEM_CLAWS), "a claw can be taken off it")
	_expect(Items.price(Net.ITEM_MANTIS_CLAW) > 0 and Items.kept_in_locker().has(Net.ITEM_MANTIS_CLAW), "the claw is kept and sold")
	# one follows aboard; leaving and coming back
	var aboard = server.mantises.spawn(outer.x + 1, outer.y + 3)
	var left := _mantises_alive().filter(func(q) -> bool: return map.is_other(q.st.y * map.width + q.st.x)).size()
	der.dock(false)
	_leave_rock()
	_expect(not der.here and server.players.has(aboard) and not aboard.corpse, "a mantis aboard stays when the asteroid is left")
	_expect(int(der._homes[key]["mantises"]) == left, "those left on it are remembered (%d, %d)" % [left, int(der._homes[key]["mantises"])])
	server.crew.remove(aboard)
	_place_rock()
	var q = server.crew.new_player("Шахтёр 2", 0)
	der.dock(true)
	q.st.place(outer.x, outer.y - 1)
	_run(2)
	_expect(_mantises_alive().size() == left, "and are there again next time")
	var bodies := 0
	for c in server.players:
		if c != null and c.corpse and c.monster:
			bodies += 1
	_expect(bodies >= 1, "with the bodies left there")
	server.crew.remove(q)
	der.dock(false)
	_leave_rock()


func _mantises_alive() -> Array:
	var out := []
	for q in server.players:
		if q != null and q.monster and not q.corpse and q.cond != Net.COND_DEAD:
			out.append(q)
	return out


func _a_pirate():
	for q in server.players:
		if q != null and q.pirate and not q.monster:
			return q
	return server.pirates.spawn(1, 1, false)


func _line_of_three() -> Array:
	## Three cells of the asteroid's ground in a row, across.
	var map := server.map
	for c: int in server.derelict._ground_cells():
		var x := c % map.width
		var y := c / map.width
		if map.walkable(x + 1, y) and map.walkable(x + 2, y) and map.is_other(c + 2) and map.door_at(x + 1, y) < 0:
			return [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y)]
	return []


# ---------------------------------------------------------------- a station

func _station() -> void:
	print("  -- a made station")
	var der = server.derelict
	var map := server.map
	var k := ShipMap.other_maps().find("made:%d" % PlaceMaker.COUNT)
	der.layout_for_test = k
	der._arrive()
	var info: Dictionary = der.made
	_expect(der.here and der.layout == k and der.ship.name.begins_with("Заброшенная "), "it comes with its own name (%s)" % der.ship.name)
	var empty := 0
	for e: Array in info["rooms"]:
		var c: Vector2i = e[0]
		var inside := (map.other_at.y + c.y) * map.width + map.other_at.x + c.x
		var any := false
		for room: Array in der._rooms():
			if room.has(inside):
				for r: int in room:
					any = any or server.floor_things.has(r)
		if not any:
			empty += 1
	_expect(not (info["rooms"] as Array).is_empty() and empty == 0, "every room holds something (%d empty)" % empty)
	_expect(der.dock(true) == "" and der.docked, "it docks")


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
