extends SceneTree
## (v97) Checks derelicts made from pieces, who lives on them, their vaults and our teleporter, on a real server
## stepped by hand:
##   godot --headless --path . --script res://tools/placetest.gd
## Every drawing PlaceMaker makes builds with no problem, has one outer door and lies off ship02's airlock; a
## campaign makes its own set, sent to guests and kept in the save. A made derelict comes with its own name, the
## sensors say who moves aboard, its vault is welded shut and holds its prize; the first of ours aboard wakes its
## rogue robots and the vault's keeper, who hold their places; who is left alive and a vault cut open stay so for
## the next visit. Our teleporter: a module that sends whoever stands by the bay (and armed bots told «К оружию»)
## onto the ship alongside after its hum, brings them home after its recharge, takes its bots home once no foe is
## left, and takes everybody home when that ship leaves. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Items := preload("res://src/shared/items.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const MapBuilder := preload("res://src/shared/map_builder.gd")
const PlaceMaker := preload("res://src/shared/place_maker.gd")
const Campaign := preload("res://src/server/campaign.gd")

var failed := 0
var server: GameServer
var seed_used := 0
var said: Array = []                 # what the ship said aloud


func _initialize() -> void:
	_drawings()
	_choose_set()
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26650, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.log_line.connect(func(t: String) -> void: said.append(t))
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.ransom_chance = 0.0
	server.stations.volunteers = false
	server.pirates.goals_on = false
	server.wing.chance_for_test = 0.0
	server.defence.on = false
	server.systems.vents_on = false
	for q in server.players:
		if q != null and q.bot:
			q.order = Net.POST_FREE
	server.ship.pos = Vector2(100, 100)
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	_run(2)
	_campaign_set()
	_derelict()
	_teleporter()
	print("placetest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	quit(0 if failed == 0 else 1)


# ---------------------------------------------------------------- drawings

func _drawings() -> void:
	print("  -- drawings made from pieces")
	var ship := ShipMap.new()
	ship.load_from("ship02")
	var ours: Vector2i = ship.doors[int(ship.lock_pump.values()[0]["outer"])]
	var bad := 0
	var tall := 0
	var doors_bad := 0
	var misfit := 0
	var vaults := 0
	var tiles := FileAccess.get_file_as_string("res://assets/tiles.json")
	for s in 40:
		var made := PlaceMaker.make_set(1000 + s)
		for n: String in made:
			if MapBuilder.kind_of(n, str(made[n])) != "derelict":
				continue                     # ((v99) the asteroids: asteroidtest)
			var built := MapBuilder.build("derelict", str(made[n]))
			if not (built["problems"] as Array).is_empty():
				bad += 1
				if bad <= 3:
					print("    %s\n%s" % [(built["problems"][0] as Dictionary), made[n]])
				continue
			var o := ShipMap.new()
			if o.load_data(n, tiles, built["data"], false) != "":
				bad += 1
				continue
			if o.height > (PlaceMaker.HEIGHT if str(made[n]).contains("(v97)") else 20):
				tall += 1                    # ((v99) a station: as tall as ship02's 24 empty rows take)
			var outer := Vector2i(-1, -1)
			var count := 0
			for d in o.doors.size():
				if o.door_vent[d] == 1:
					count += 1
					outer = o.doors[d]
			if count != 1:
				doors_bad += 1
				continue
			var docked_at := ours - outer - Vector2i(0, 1)
			ship.others = [o]
			ship.other = o
			if not ship.other_fits(docked_at) or not ship.other_fits(docked_at - Vector2i(0, 3)):
				misfit += 1
			if (PlaceMaker.info(str(made[n]))["vault"] as Vector2i).x >= 0:
				vaults += 1
	_expect(bad == 0, "every drawing of 40 sets builds with no problem (%d bad)" % bad)
	_expect(tall == 0 and doors_bad == 0, "each is at most %d rows (a station 20) and has one outer door (%d too tall, %d with another count)" % [PlaceMaker.HEIGHT, tall, doors_bad])
	_expect(misfit == 0, "each lies off ship02's airlock, alongside and docked (%d do not)" % misfit)
	_expect(vaults > 40 and vaults < 300, "some have a vault (%d of 320)" % vaults)
	var a := PlaceMaker.make_set(7)
	var b := PlaceMaker.make_set(7)
	_expect(a == b and a.size() == PlaceMaker.COUNT + PlaceMaker.ROCKS, "the same seed makes the same %d drawings" % a.size())


func _choose_set() -> void:
	## A campaign's set with a vault and robots in one drawing (the checks need one).
	for s in range(1, 400):
		var made := PlaceMaker.make_set(s)
		for n: String in made:
			var info := PlaceMaker.info(str(made[n]))
			if (info["vault"] as Vector2i).x >= 0 and int(info["dwellers"]) >= 2:
				seed_used = s
				ShipMap.drawings = {}
				ShipMap.make_places(s)
				return


func _campaign_set() -> void:
	print("  -- the campaign's own set")
	_expect(ShipMap.made_others.size() == PlaceMaker.COUNT + PlaceMaker.ROCKS, "the campaign has its own %d derelicts and asteroids" % ShipMap.made_others.size())
	var names := ShipMap.other_maps()
	var all_in := true
	for n: String in ShipMap.made_others:
		var kind := "asteroid" if ShipMap.made_others.find(n) >= PlaceMaker.COUNT else "derelict"   # ((v99) the asteroids after)
		all_in = all_in and names.has(n) and server.map.others_of(kind).has(names.find(n))
	_expect(all_in, "each is one of the drawings that come alongside, a derelict or an asteroid")
	var spots := 0
	for k: int in server.map.others_of("derelict"):
		if server.derelict._spots.has(k):
			spots += 1
	_expect(spots == PlaceMaker.COUNT + 1, "every one fits off our airlock, with the old one (%d)" % spots)
	var maps := ShipMap.unpack_maps(ShipMap.pack_maps("ship02"), 0)
	var sent := true
	for n: String in ShipMap.made_others:
		sent = sent and (maps["drawings"] as Dictionary).get(n, "") == ShipMap.drawings[n]
	_expect(sent and (maps["others"] as Array) == names, "the welcome sends guests their texts")
	var saved := Campaign.snapshot(server)
	_expect((saved["made_others"] as Array) == ShipMap.made_others and (saved["drawings"] as Dictionary).has(ShipMap.made_others[0]),
		"the save keeps them")
	_expect(Gear.of_item(Net.ITEM_TELEPORTER) == Gear.TELEPORT and Gear.item_of(Gear.TELEPORT) == Net.ITEM_TELEPORTER
		and Gear.of_item(Net.ITEM_NVG) == Gear.NONE and Items.name_of(Net.ITEM_TELEPORTER) != "", "the teleporter is a crate of its own")
	_expect(not Gear.of_tier(1).has(Gear.TELEPORT) and not Gear.of_tier(2).has(Gear.TELEPORT) and not Gear.of_tier(3).has(Gear.TELEPORT),
		"no trader or derelict rolls it")


# ---------------------------------------------------------------- a made derelict

var _vault_layout := -1


func _made_with_vault() -> int:
	for n: String in ShipMap.made_others:
		var info := PlaceMaker.info(str(ShipMap.drawings[n]))
		if (info["vault"] as Vector2i).x >= 0 and int(info["dwellers"]) >= 2:
			return ShipMap.other_maps().find(n)
	return -1


func _derelict() -> void:
	print("  -- who lives on a made derelict")
	var der = server.derelict
	var map := server.map
	for q in server.players.duplicate():      # (no crew bots about: what the robots see and hear is the checks' own)
		if q != null and q.bot and not q.pirate:
			server.crew.remove(q)
	_vault_layout = _made_with_vault()
	_expect(_vault_layout >= 0, "(a drawing with a vault and robots, seed %d)" % seed_used)
	der.layout_for_test = _vault_layout
	der.teleporter_chance = 1.0
	said.clear()
	der._arrive()
	var info: Dictionary = der.made
	_expect(der.here and der.layout == _vault_layout and der.ship.name.begins_with("Брошенный "), "it comes with its own name (%s)" % der.ship.name)
	_expect(" ".join(said).contains("на борту движение") and " ".join(said).contains("заварен"), "the sensors say something moves aboard and a room is welded")
	_expect(der.vault_door >= 0 and server.doors.welded[der.vault_door] == 1, "the vault's door is welded shut")
	var prize := false
	for c: int in der.vault_cells():
		if server.floor_things.has(c) and (server.floor_things[c] as PackedByteArray).has(Net.ITEM_TELEPORTER):
			prize = true
	_expect(prize and der.teleporter_found, "the vault holds the teleporter")
	_expect(der.dock(true) == "" and server.doors.welded[der.vault_door] == 1, "docking keeps the weld")
	var robots := mini(int(info["dwellers"]) + server.road.depth, der.DWELLERS_MAX)
	_expect(_dwellers(1).is_empty(), "nobody shows before one of ours sets foot aboard")
	var p = server.crew.new_player("Разведчик", 0)
	var entry := _entry()
	p.st.place(entry % map.width, entry / map.width)
	_run(3)
	var found := _dwellers(1)
	var keeper := _dwellers(2)
	_expect(found.size() == robots, "the first of ours aboard wakes its rogue robots (%d of %d)" % [found.size(), robots])
	_expect(keeper.size() == 1 and der.vault_cells().has(keeper[0].st.y * map.width + keeper[0].st.x) and keeper[0].toughness < 0.5,
		"its keeper stands in the vault, tough")
	var still := true
	var at := {}
	for r in found + keeper:
		r.ai_fire_tick = 1 << 30
		r.ready_tick = 1 << 30
		at[r] = Vector2i(r.st.x, r.st.y)
	p.st.place(0, 0)                          # out of everybody's sight
	for r in at:
		r.ai_target = -1                      # (whoever saw the scout come aboard forgets it)
		r.ai_goal = Vector2i(-1, -1)
	_run(Net.TICK_HZ * 5)
	for r in at:
		still = still and Vector2i(r.st.x, r.st.y) == at[r]
	_expect(still, "with nobody in sight they hold their places")
	# cut the weld, one robot dies, leave and come back
	server.repairs.weld(p, der.vault_door)
	_expect(server.doors.welded[der.vault_door] == 0, "a welder cuts the vault open")
	var dead = found[0]
	dead.health = Net.HEALTH_DEAD
	dead.cond = Net.COND_DEAD
	server.crew.becomes_corpse(dead)
	server.crew.remove(p)
	_run(2)
	der.dock(false)
	der._leave(true)
	_expect(_dwellers(1).is_empty() and _dwellers(2).is_empty(), "leaving it takes its robots along")
	said.clear()
	der._arrive()
	_expect(server.doors.welded[der.vault_door] == 0 and not " ".join(said).contains("заварен"), "a vault cut open stays open")
	var q = server.crew.new_player("Разведчик 2", 0)
	q.st.place(_entry() % map.width, _entry() / map.width)
	_run(3)
	_expect(_dwellers(1).size() == robots - 1 and _dwellers(2).size() == 1, "who was alive is there again (%d robots)" % _dwellers(1).size())
	q.st.place(0, 0)
	server.crew.remove(q)
	_run(2)


func _mute() -> void:
	## The robots aboard never shoot (the checks are about getting there and back).
	for r in _dwellers(1) + _dwellers(2):
		r.ai_fire_tick = 1 << 30
		r.ready_tick = 1 << 30


func _entry() -> int:
	## A floor cell of the ship alongside by its outer door.
	var map := server.map
	for d in range(map.other_first_door, map.doors.size()):
		if map.doors[d] != ShipMap.NO_OTHER and map.other.door_vent[d - map.other_first_door] == 1:
			return (map.doors[d].y - 1) * map.width + map.doors[d].x
	return -1


func _dwellers(kind: int) -> Array:
	var out: Array = []
	for r in server.players:
		if r != null and r.dweller == kind and not r.corpse and r.cond != Net.COND_DEAD:
			out.append(r)
	return out


# ---------------------------------------------------------------- our teleporter

func _teleporter() -> void:
	print("  -- our teleporter")
	var map := server.map
	var t = server.teleporter
	var der = server.derelict
	_expect(map.teleporter.size() == 1, "ship02 has a teleporter's pad")
	var pad: int = map.teleporter.keys()[0]
	var front: int = map.teleporter[pad]
	if not der.here:
		der._arrive()
	der.dock(true)
	for c in map.other_cells:                 # (air over there: the checks are not about breathing)
		if map.walk[c] == 1:
			server.air.air[c] = 1.0
	server.air.wake()
	var p = server.crew.new_player("Телепортист", 0)
	p.st.place(front % map.width, front / map.width)
	t.asked(p, Net.TELE_SEND)
	_expect(t.hums.is_empty() and t._packet(p)[1] == Net.TELE_NONE and not server.ship.teleporter, "the pad is empty: nothing happens")
	p.job = Net.JOB_ENGINEER
	p.slots[p.hand] = Net.ITEM_TELEPORTER
	_expect(server.outfit.can(p, pad) == "" and server.outfit.can(p, map.bay.keys()[0]) == server.outfit.NOT_HERE,
		"an engineer may install the found teleporter in the pad, not in the module bay")
	server.outfit.finish(p, pad)
	_expect(server.ship.teleporter and p.in_hand() == Net.ITEM_NONE and t._packet(p)[1] == Net.TELE_READY, "installed, the player is told it is ready")
	var bot = server.crew.new_player("Бот-боец", 0)
	bot.bot = true
	bot.defends = true
	bot.slots.fill(Net.ITEM_NONE)
	bot.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	bot.st.place(front % map.width + 1, front / map.width)
	for r in _dwellers(1) + _dwellers(2):
		r.ai_fire_tick = 1 << 30
		r.ready_tick = 1 << 30
	t.asked(p, Net.TELE_SEND)
	_expect(t.hums.size() == 1 and not map.is_other(p.st.y * map.width + p.st.x), "it hums first")
	var bot_at := Vector2i(bot.st.x, bot.st.y)
	for i in roundi(Gear.TELEPORT_HUM * Net.TICK_HZ):
		server._tick()
		if not t.hums.is_empty():
			bot.st.place(bot_at.x, bot_at.y)     # (the bot waits by the pad: its own errands are not checked here)
			bot.st.dir = Net.DIR_NONE
	_run(1)
	_mute()
	var p_over: bool = map.is_other(p.st.y * map.width + p.st.x)
	var bot_over: bool = map.is_other(bot.st.y * map.width + bot.st.x)
	_expect(p_over and bot_over, "the player and an armed bot told «К оружию» beside the bay stand on the ship alongside")
	_expect(p.st.y * map.width + p.st.x != bot.st.y * map.width + bot.st.x, "each where it lands on its own")
	t.asked(p, Net.TELE_HOME)
	_expect(t.hums.is_empty(), "it does not beam again before its recharge")
	var landed := Vector2i(bot.st.x, bot.st.y)
	_hold(bot, landed, roundi(Gear.TELEPORT_SECONDS * Net.TICK_HZ))
	t.asked(p, Net.TELE_HOME)
	_hold(bot, landed, roundi(Gear.TELEPORT_HUM * Net.TICK_HZ) + 1)
	_expect(map.on_ship(p.st.y * map.width + p.st.x) and not map.is_other(p.st.y * map.width + p.st.x), "after it, the player is beamed home")
	_expect(map.is_other(bot.st.y * map.width + bot.st.x), "the bot stays to fight while robots are aboard")
	for r in _dwellers(1) + _dwellers(2):
		r.health = Net.HEALTH_DEAD
		r.cond = Net.COND_DEAD
		server.crew.becomes_corpse(r)
	_run(roundi((Gear.TELEPORT_SECONDS + Gear.TELEPORT_HUM + 2.0) * Net.TICK_HZ))
	_expect(not map.is_other(bot.st.y * map.width + bot.st.x), "with no foe left the bot comes home by itself")
	# sent again, the ship leaves: home at once
	_run(roundi(Gear.TELEPORT_SECONDS * Net.TICK_HZ))
	p.st.place(front % map.width, front / map.width)
	t.asked(p, Net.TELE_SEND)
	_run(roundi(Gear.TELEPORT_HUM * Net.TICK_HZ) + 1)
	_expect(map.is_other(p.st.y * map.width + p.st.x), "(sent over again)")
	der._leave(true)
	_expect(map.on_ship(p.st.y * map.width + p.st.x) and not der.here, "a ship that leaves sends whoever our teleporter put there home")
	server.power.set_charge(0.0)
	server.ship.broken[map.engine.keys()[0]] = true
	_run(roundi(Gear.TELEPORT_SECONDS * Net.TICK_HZ))
	der._arrive()
	t.asked(p, Net.TELE_SEND)
	_expect(t.hums.is_empty() and t._charged(0) != "", "without power it does not beam")


func _hold(q, at: Vector2i, ticks: int) -> void:
	## Runs the game with one bot kept where it stands: it would walk home through the airlock to its post, and
	## the check is about what the teleporter does with it, not its own errands.
	for i in ticks:
		server._tick()
		if server.map.is_other(at.y * server.map.width + at.x):
			q.st.place(at.x, at.y)
			q.st.dir = Net.DIR_NONE


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
