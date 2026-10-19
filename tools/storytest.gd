extends SceneTree
## Checks the road and its story (v63), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/storytest.gd
## The comms console's calls (answers, blue and shut ones, the plain answer
## when nobody answers), quests (cargo, a bounty, a black box), the chapter's two
## missions, SOS sectors, help for a ship dry of fuel, food and hunger, the
## hydroponic trays (planting, tending, withering, harvest, mutation, hybrids,
## bots at work there), the cryopods, the roaming flagship that grows, the easy
## and hard modes, and that it all survives a save.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Story := preload("res://src/server/story.gd")
const Tales := preload("res://src/server/tales.gd")
const Garden := preload("res://src/server/garden.gd")
const Flagship := preload("res://src/server/flagship.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Plants := preload("res://src/shared/plants.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")

var failed := 0
var server: GameServer
var kept: Array = []
var keep_hull := false


func _initialize() -> void:
	server = _new_server(26400)
	if server == null:
		quit(1)
		return
	_calls()
	_blue()
	_cargo()
	_bounty()
	_blackbox()
	_missions()
	_sos()
	_dry()
	var main := server
	server = _new_server(26402)          # (a ship of its own: nothing else may hurt the crew while they starve)
	_food()
	server.stop()
	server = main
	_trays()
	_hybrids()
	_bots_tend()
	_cryo()
	_flagship()
	_modes()
	_saved()
	print("storytest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _new_server(port: int) -> GameServer:
	var s := GameServer.new()
	get_root().add_child(s)
	var problem := s.start(port, "ship02", 2)
	if problem != "":
		print(problem)
		return null
	s.director.auto = false
	s.story.auto = false
	s.gunnery.flies = false
	s.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	return s


func _at_comms(p) -> void:
	var cell: int = server.map.comms.keys()[0]
	var s: Array = server.stations._spots_for(cell)[0]
	p.st.place(int(s[0]) % server.map.width, int(s[0]) / server.map.width)
	p.st.facing = int(s[1])


func _calls() -> void:
	print("  -- calls on the comms console")
	_expect(server.map.comms.size() == 1 and server.map.trays.size() == 4 and server.map.cryo.size() == 4,
		"ship02 has a comms console, 4 hydroponic trays and 4 cryopods")
	var st: Story = server.story
	var p = server.crew.new_player("Связист")
	kept = [p]
	var toll := Tales.find("toll")
	_expect(st.open(toll), "a call comes in")
	_expect(not st.open(Tales.find("capsule")), "only one at a time")
	var flags: PackedByteArray = st.call["flags"]
	server.ship.credits = 100
	st._refresh_flags()
	flags = st.call["flags"]
	_expect(flags[0] == 0, "paying 30 is open with 100 credits")
	_expect(flags[2] & Net.CHOICE_BLUE != 0, "the pilot's answer is blue")
	st.answer_asked(p, 0)
	_expect(not st.call.is_empty(), "away from the console nobody can answer")
	_at_comms(p)
	_expect(server.repairs.usable_ahead(p), "at the console the use key works on it")
	st.answer_asked(p, 0)
	_expect(st.call.is_empty() and server.ship.credits == 70, "answered: the call is over and 30 credits paid (%d)" % server.ship.credits)
	_expect(st.last_title.contains("Пиратская застава"), "the console shows the outcome")
	# nobody answers: the plain answer
	server.ship.credits = 10
	st.open(toll)
	_run(roundi(Story.ANSWER_SECONDS * Net.TICK_HZ) + 2)
	_expect(st.call.is_empty(), "unanswered, it ends by itself after %d s" % int(Story.ANSWER_SECONDS))
	_expect(server.ship.credits == 10, "the plain answer could not be paid, so another was taken (credits kept)")
	server.derelict._leave(true)
	server.gunnery.enemy_gone()
	# a packet that reads back
	st.open(Tales.find("capsule"))
	var pkt := st.comms_packet()
	_expect(pkt[0] == Net.S_COMMS and pkt[1] == Net.COMMS_CALL and pkt.size() > 40, "the console's packet carries the call (%d bytes)" % pkt.size())
	st.call = {}
	server.crew.remove(p)
	kept = []


func _blue() -> void:
	print("  -- blue answers")
	var st: Story = server.story
	for q in server.players:
		if q != null and not q.pirate and q.job == Net.JOB_MEDIC:
			q.take_job(Net.JOB_CREWMAN)
	st.open(Tales.find("capsule"))
	_expect(st.call["flags"][1] & Net.CHOICE_SHUT != 0, "with no doctor aboard the doctor's answer is shut")
	var doc = server.crew.new_player("Доктор")
	doc.take_job(Net.JOB_MEDIC)
	kept = [doc]
	st._refresh_flags()
	_expect(st.call["flags"][1] == Net.CHOICE_BLUE, "a doctor aboard opens it")
	_at_comms(doc)
	var reserve := server.reserve
	var food := int(server.ship.store.get(Net.ITEM_FOOD, 0))
	st.answer_asked(doc, 1)
	_expect(server.reserve == mini(reserve + 1, Net.RESERVE_MAX) and int(server.ship.store[Net.ITEM_FOOD]) == food + 3,
		"the survivor joins the reserve and gives his food")
	st.open(Tales.find("container"))
	server.ship.store[Net.ITEM_PROBE] = 0
	st._refresh_flags()
	_expect(st.call["flags"][1] & Net.CHOICE_SHUT != 0, "no probe in the locker: the probe's answer is shut")
	server.ship.store[Net.ITEM_PROBE] = 1
	st._refresh_flags()
	_expect(st.call["flags"][1] == Net.CHOICE_BLUE, "a probe in the locker opens it")
	var parts := int(server.ship.store.get(Net.ITEM_PART, 0))
	st.answer_asked(doc, 1)
	_expect(int(server.ship.store[Net.ITEM_PART]) == parts + 2 and int(server.ship.store[Net.ITEM_PROBE]) == 1, "it pays off, and the probe stays")
	server.crew.remove(doc)
	kept = []


func _answer(event: String, choice: int) -> void:
	var st: Story = server.story
	st.call = {}
	st.open(Tales.find(event))
	st._answer(choice, "тест")


func _calm() -> void:
	## No pirates about and no call waiting: what a section before may have left (an SOS trap, a bounty).
	server.story.quests.clear()
	server.story.call = {}
	server.story._due_at = -1
	if server.derelict.here:
		server.derelict._leave(true)
	server.gunnery.enemy_gone()
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	_run(2)


func _arrive_at(cell: Vector2i) -> void:
	## The ship is in that sector of space now, as if it had jumped there.
	server.been[Sectors.key(cell)] = true
	server.road.build(cell)
	server.ship.sector = server.sectors.here
	server.ship.pos = server.sectors.entry[server.ship.sector]
	server.story.entered_sector()
	_run(1)


func _kind(c: Vector2i) -> int:
	## (v64) The kind of that system of the cluster we are in (-1: not in it).
	var i := server.sectors.index_of(c)
	return -1 if i < 0 else int(server.sectors.kind[i])


func _enter_cluster(depth: int) -> void:
	## (v64) The ship is at the start of the cluster `depth` steps along the road, as if it had come in.
	server.road.depth = depth
	server.road.entry = Vector2i(6 * depth, 0)
	server.road.hunters = []
	_arrive_at(server.road.entry)


func _cargo() -> void:
	print("  -- a cargo quest")
	var st: Story = server.story
	st.quests.clear()
	_answer("smuggler", 0)
	_expect(st.quests.size() == 1 and int(st.quests[0]["kind"]) == Net.QUEST_CARGO, "the quest is taken")
	if st.quests.is_empty():
		return
	var q: Dictionary = st.quests[0]
	var d: int = server.sectors.hops_between(st.here(), q["at"])
	var in_range: bool = d <= Story.QUEST_FAR or st._targets([Sectors.STATION], Story.QUEST_NEAR, Story.QUEST_FAR, false).is_empty()
	_expect(d >= 1 and in_range, "its station is %d jumps away" % d)   # (v64: further only when the cluster has none in range)
	_expect(_kind(q["at"]) == Sectors.STATION, "and it is a station of this cluster")
	_expect(int(server.ship.store.get(Net.ITEM_CARGO, 0)) == 1, "the crate is in the locker")
	var pkt := st.story_packet()
	_expect(pkt[9] == 1, "the story packet lists it")
	var credits: int = server.ship.credits
	_arrive_at(q["at"])
	_expect(st.quests.is_empty() and server.ship.credits == credits + int(q["reward"]), "delivered at the station: paid %d" % int(q["reward"]))
	_expect(int(server.ship.store.get(Net.ITEM_CARGO, 0)) == 0, "and the crate is gone")
	for i in Story.MAX_QUESTS + 1:
		_answer("smuggler", 0)
	_expect(st.quests.size() <= Story.MAX_QUESTS, "no more than %d quests at a time" % Story.MAX_QUESTS)
	st.quests.clear()
	server.ship.store[Net.ITEM_CARGO] = 0


func _bounty() -> void:
	print("  -- a bounty")
	var st: Story = server.story
	_answer("bounty", 0)
	_expect(st.quests.size() == 1, "the bounty is taken")
	if st.quests.is_empty():
		return
	var q: Dictionary = st.quests[0]
	_arrive_at(q["at"])
	_run(roundi(Story.HUNT_DELAY * Net.TICK_HZ) + 5)
	var g = server.gunnery
	_expect(g.fighting() and server.derelict.ship.name.contains(str(q["pirate"])),
		"its pirate comes out (%s)" % (server.derelict.ship.name if server.derelict.ship != null else "-"))
	var credits: int = server.ship.credits
	g._wrecked()
	_run(Net.TICK_HZ)
	_expect(st.quests.is_empty() and server.ship.credits >= credits + int(q["reward"]), "wrecked: the bounty is paid")
	server.derelict._leave(true)
	_run(2)
	# one that gets away
	_answer("bounty", 0)
	q = st.quests[0]
	_arrive_at(q["at"])
	_run(roundi(Story.HUNT_DELAY * Net.TICK_HZ) + 5)
	g.enemy_hull = 0
	server.derelict.pirates_escaped()
	server.derelict._leave(true)
	_run(Net.TICK_HZ)
	_expect(st.quests.is_empty(), "if it gets away, the quest is lost")


func _blackbox() -> void:
	print("  -- a black box")
	var st: Story = server.story
	_answer("beacon", 0)
	_expect(st.quests.size() == 1 and int(st.quests[0]["kind"]) == Net.QUEST_BLACKBOX, "the quest is taken")
	if st.quests.is_empty():
		return
	var q: Dictionary = st.quests[0]
	_expect(_kind(q["at"]) == Sectors.DERELICT, "it points at a derelict of this cluster")
	_arrive_at(q["at"])
	var cells := PackedInt32Array([server.map.spawns[0].y * server.map.width + server.map.spawns[0].x])
	server.floor_things.erase(cells[0])
	st.derelict_arrived(cells)
	_expect((server.floor_things.get(cells[0], PackedByteArray()) as PackedByteArray).has(Net.ITEM_BLACKBOX), "the box lies on the wreck")
	server.floor_things.erase(cells[0])
	var credits: int = server.ship.credits
	server.ship.store[Net.ITEM_BLACKBOX] = 1
	_run(Net.TICK_HZ + 1)
	_expect(st.quests.is_empty() and server.ship.credits == credits + int(q["reward"]), "put into the locker: the quest is done")


func _missions() -> void:
	print("  -- the chapter's missions")
	var st: Story = server.story
	st.chapter = 0
	st.m1_next = 0
	# somewhere in the second cluster that is quiet and not an SOS
	st.quests.clear()
	_enter_cluster(1)
	st._due_at = -1
	st.m1_next = 0                           # (coming in at its start may already have offered it)
	var s: Sectors = server.sectors
	var at := Vector2i.MAX
	for i in s.count:
		if at == Vector2i.MAX and i != s.start and not Story.sos_at(server.space_seed, s.cell[i], s.kind[i]):
			at = s.cell[i]
	_arrive_at(at)
	_expect(st._due_event == Tales.find("m1") and st._due_at > 0, "the first mission is offered %d jumps out" % server.sectors.far_from_start(server.ship.sector))
	_run(5 * Net.TICK_HZ)
	_expect(not st.call.is_empty() and int(st.call["event"]) == Tales.find("m1"), "the call comes")
	st._answer(0, "тест")
	_expect(st.chapter == 1 and st.quests.size() == 1, "taken: the convoy is sought")
	if st.quests.is_empty():
		return
	var q: Dictionary = st.quests[0]
	q["placed"] = true
	server.ship.store[Net.ITEM_BLACKBOX] = 1
	_run(Net.TICK_HZ + 1)
	_expect(st.chapter == 1 and not st.call.is_empty() and int(st.call["event"]) == Tales.find("m2"), "the log delivered: the second mission calls")
	_expect(_gear_in_locker(), "and the fleet sent a crate of gear")
	st._answer(0, "тест")
	_expect(st.chapter == 2 and st.quests.size() == 1, "the courier is sought")
	if st.quests.is_empty():
		return
	q = st.quests[0]
	server.flagship.growth = 2
	_arrive_at(q["at"])
	_run(roundi(Story.HUNT_DELAY * Net.TICK_HZ) + 5)
	var g = server.gunnery
	_expect(g.fighting() and server.derelict.design["klass"] == Net.ECLASS_GUNSHIP, "the courier is a gunship")
	g._wrecked()
	_run(Net.TICK_HZ)
	_expect(st.chapter == 3 and st.codes, "beaten: the flagship's codes are ours")
	_expect(server.flagship.growth == 1, "and its growth goes a step back")
	server.derelict._leave(true)
	_enter_cluster(0)
	_run(2)


func _gear_in_locker() -> bool:
	for item: int in server.ship.store.keys():
		if item >= Net.ITEM_GEAR and item < Net.ITEM_GEAR + 25 and int(server.ship.store[item]) > 0:
			return true
	return false


func _sos() -> void:
	print("  -- SOS sectors")
	var st: Story = server.story
	_calm()
	var found := Vector2i.MAX
	var n := 0
	var depth := -1
	for dp in 16:                            # cluster after cluster along the road, but the flagship's
		if dp == Sectors.FLAG_DEPTH:
			continue
		var s := Sectors.new()
		var at := Vector2i(6 * dp, 0)
		s.build(server.space_seed, at, {}, dp, at)
		for i in s.count:
			if s.kind[i] == Sectors.EMPTY and s.cell[i] != Vector2i.ZERO:
				n += 1
				if found == Vector2i.MAX and Story.sos_at(server.space_seed, s.cell[i], s.kind[i]) and not st.sos_done.has(Sectors.key(s.cell[i])):
					found = s.cell[i]
					depth = dp
	_expect(found != Vector2i.MAX, "some quiet systems send an SOS (%d quiet in fifteen clusters)" % n)
	if found == Vector2i.MAX:
		return
	st.call = {}
	_enter_cluster(depth)
	_arrive_at(found)
	_expect(st._due_event == Tales.find("sos"), "arriving there brings the SOS call")
	_expect(st.sos_done.has(Sectors.key(found)), "and the SOS is marked answered")
	st._due_at = -1
	_enter_cluster(0)
	st._due_at = -1


func _dry() -> void:
	print("  -- dry of fuel")
	var st: Story = server.story
	st.call = {}
	var got := false
	for i in 30:
		if st.dry_call():
			got = true
			break
	_expect(got and str(Tales.EVENTS[int(st.call["event"])]["tag"]) == "dry", "a passing ship calls")
	# (v67, the author's O2) free help is rare: begged, the trader leaves a can only now and then
	var given := 0
	for i in 40:
		st.call = {}
		st.open(Tales.find("dry_trader"))
		server.ship.store[Net.ITEM_FUEL] = 0
		server.ship.credits = 0
		st._refresh_flags()
		st._unanswered()
		given += int(server.ship.store[Net.ITEM_FUEL])
	_expect(given > 0 and given < 30, "with no money and no answer, the trader leaves a can now and then (%d times in 40)" % given)
	st.call = {}


func _food() -> void:
	print("  -- food")
	var gd: Garden = server.garden
	_expect(Items.stock(Net.ITEM_FOOD) > 0, "the ship starts with rations (%d)" % Items.stock(Net.ITEM_FOOD))
	var eaters := gd.eaters()
	server.ship.store[Net.ITEM_FOOD] = 10
	gd.jumped()
	_expect(int(server.ship.store[Net.ITEM_FOOD]) == 10 - ceili(eaters / 2.0), "a jump eats one for every two of the crew (%d of them)" % eaters)
	_expect(not gd.starving(), "fed: no hunger")
	server.ship.store[Net.ITEM_FOOD] = 0
	gd.jumped()
	_expect(gd.starving(), "nothing to eat: they starve")
	var p = server.crew.new_player("Голодный")
	_run(Net.TICK_HZ * 900)
	_expect(p.health >= Garden.STARVE_FLOOR - 0.01 and p.health < 40.0, "health sinks, but not below %d (%.0f)" % [int(Garden.STARVE_FLOOR), p.health])
	_expect(p.cond == Net.COND_OK, "nobody dies of hunger")
	# knocked out while starving, with light wounds: it still comes round (the playthrough's soft lock)
	p.wounds = 30.0
	p.health = -5.0
	p.cond = Net.COND_CRIT
	p.st.down = true
	server.air.air[p.st.y * server.map.width + p.st.x] = 1.0
	_run(Net.TICK_HZ * 60)
	_expect(p.cond == Net.COND_OK, "out cold, starving and lightly wounded: still comes round (%.0f)" % p.health)
	p.wounds = 0.0
	server.ship.store[Net.ITEM_FOOD] = 5
	_run(Net.TICK_HZ * 80)
	_expect(not gd.starving() and gd.hunger == 0.0 and p.health > 90.0, "food again: the hunger passes (%.0f)" % p.health)
	server.crew.remove(p)


func _tray_spot(p, t: int) -> void:
	var cell: int = server.map.trays[t]
	var s: Array = server.stations._spots_for(cell)[0]
	p.st.place(int(s[0]) % server.map.width, int(s[0]) / server.map.width)
	p.st.facing = int(s[1])


func _hold(p, seconds: float) -> void:
	p.using = true
	_run(roundi(seconds * Net.TICK_HZ) + 2)
	p.using = false
	_run(1)


func _trays() -> void:
	print("  -- the hydroponic trays")
	_calm()
	var gd: Garden = server.garden
	var p = server.crew.new_player("Агроном")
	kept = [p]
	_tray_spot(p, 0)
	for item: int in server.ship.store.keys():
		if Plants.is_seed(item):
			server.ship.store[item] = 0
	_expect(gd.can(p, server.map.trays[0]) != "", "no seeds: nothing to plant")
	var seed := Plants.seed_item(Plants.MUSHROOM)
	p.slots[0] = seed
	p.hand = 0
	_expect(server.repairs.usable_ahead(p) and gd.can(p, server.map.trays[0]) == "", "a seed in hand at the tray: it can be planted")
	_hold(p, Garden.PLANT_SECONDS)
	_expect(gd.stage[0] == Net.GROW_GROWING and gd.plants[0] == seed and p.slots[0] == Net.ITEM_NONE, "planted, and the seed is gone from the hand")
	# it wants tending; left, it grows slower
	_run(roundi((gd.care_at[0] + 2.0) * Net.TICK_HZ))
	_expect(gd.wants_care(0), "after a while it wants tending (%d%%)" % roundi(gd.growth[0] * 100.0))
	var g0 := gd.growth[0]
	_run(10 * Net.TICK_HZ)
	_expect(absf((gd.growth[0] - g0) - 10.0 * Garden.NEGLECT_PACE / Plants.seconds(seed)) < 0.002, "wanting care it grows at half pace")
	_hold(p, Garden.TEND_SECONDS)
	_expect(not gd.wants_care(0), "tended")
	# no power: it stands still, but mushrooms grow in the dark
	server.ship.store[Net.ITEM_FOOD] = 50
	gd.plant(1, Plants.seed_item(Plants.POTATO))
	server.ship.broken[server.map.engine.keys()[0]] = true
	server.power.set_charge(0.0)
	var a := gd.growth[0]
	var b := gd.growth[1]
	_run(10 * Net.TICK_HZ)
	_expect(not server.powered() and gd.growth[1] == b and gd.growth[0] > a, "without power potatoes stand still, mushrooms grow")
	server.ship.broken.erase(server.map.engine.keys()[0])
	server.power.set_charge(1.0)
	_run(2)
	# withering
	gd.care_at[1] = 0.0
	gd.neglect[1] = Garden.WITHER_SECONDS - 1.0
	_run(2 * Net.TICK_HZ)
	_expect(gd.stage[1] == Net.GROW_DEAD, "left untended too long, it withers")
	_tray_spot(p, 1)
	_hold(p, Garden.CLEAR_SECONDS)
	_expect(gd.stage[1] == Net.GROW_EMPTY, "the withered one is cleared by hand")
	# harvest
	gd.stage[0] = Net.GROW_RIPE
	gd.growth[0] = 1.0
	var food := int(server.ship.store.get(Net.ITEM_FOOD, 0))
	_tray_spot(p, 0)
	_hold(p, Garden.HARVEST_SECONDS)
	_expect(gd.stage[0] == Net.GROW_EMPTY and int(server.ship.store[Net.ITEM_FOOD]) == food + Plants.food(seed), "harvested: %d rations into the locker" % Plants.food(seed))
	# a seed from the locker when the hand is empty
	server.ship.store[Plants.seed_item(Plants.SOY, Plants.RICH)] = 1
	_hold(p, Garden.PLANT_SECONDS)
	_expect(gd.plants[0] == Plants.seed_item(Plants.SOY, Plants.RICH), "empty-handed, the best seed comes from the locker")
	_expect(Plants.food(Plants.seed_item(Plants.SOY, Plants.RICH)) == Plants.food(Plants.seed_item(Plants.SOY)) + 1, "a rich seed gives one ration more")
	_expect(Plants.seconds(Plants.seed_item(Plants.SOY, Plants.EARLY)) < Plants.seconds(Plants.seed_item(Plants.SOY)), "an early one ripens sooner")
	_expect(Plants.mutate(Plants.PLAIN, 0.1) == Plants.RICH and Plants.mutate(Plants.RICH, 0.9) == Plants.CHOICE, "mutations add what a seed lacks")
	var pkt := gd.packet()
	_expect(pkt[0] == Net.S_GARDEN and pkt[1] == 4 and pkt.size() == 2 + 4 * 6, "the trays' packet")
	server.crew.remove(p)
	kept = []


func _hybrids() -> void:
	print("  -- hybrids and seeds coming back")
	var gd: Garden = server.garden
	_expect(gd._beside(0, 1), "trays 1 and 2 stand side by side")
	var hybrids := 0
	var back := 0
	var mutated := 0
	for i in 200:
		gd.plant(0, Plants.seed_item(Plants.POTATO))
		gd.plant(1, Plants.seed_item(Plants.SOY))
		gd.stage[0] = Net.GROW_RIPE
		gd.stage[1] = Net.GROW_RIPE
		var tuber := int(server.ship.store.get(Plants.seed_item(Plants.TUBER), 0))
		var plain := int(server.ship.store.get(Plants.seed_item(Plants.POTATO), 0))
		var rich := int(server.ship.store.get(Plants.seed_item(Plants.POTATO, Plants.RICH), 0)) + int(server.ship.store.get(Plants.seed_item(Plants.POTATO, Plants.EARLY), 0))
		gd.harvest(0, "тест")
		gd.harvest(1, "тест")
		if int(server.ship.store.get(Plants.seed_item(Plants.TUBER), 0)) > tuber:
			hybrids += 1
		if int(server.ship.store.get(Plants.seed_item(Plants.POTATO), 0)) > plain:
			back += 1
		if int(server.ship.store.get(Plants.seed_item(Plants.POTATO, Plants.RICH), 0)) + int(server.ship.store.get(Plants.seed_item(Plants.POTATO, Plants.EARLY), 0)) > rich:
			mutated += 1
	_expect(hybrids > 40 and hybrids < 110, "potato beside soy, ripe together: a sweet tuber now and then (%d of 200)" % hybrids)
	_expect(back > 70 and back < 130 and mutated > 5 and mutated < 50, "seeds come back (%d), some mutated (%d)" % [back, mutated])
	_expect(Plants.cross(Plants.MUSHROOM, Plants.CHLORELLA) == Plants.HERB and Plants.plasters(Plants.seed_item(Plants.HERB)) > 0, "mushroom and chlorella give the healing herb")


func _bots_tend() -> void:
	print("  -- bots at the trays")
	_calm()
	var gd: Garden = server.garden
	for t in 4:
		gd.plants[t] = 0
		gd.stage[t] = Net.GROW_EMPTY
	gd.plant(2, Plants.seed_item(Plants.CHLORELLA))
	gd.care_at[2] = 0.0
	gd.growth[2] = 0.1
	var cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	kept = [cap]
	for b in server.players:
		if b != null and b.bot and not b.corpse:
			server.stations.order_asked(cap, b.slot, Net.POST_REPAIR)
	for item: int in server.ship.store.keys():
		if Plants.is_seed(item):
			server.ship.store[item] = 0
	var ticks := 0
	while gd.wants_care(2) and ticks < 60 * Net.TICK_HZ:
		_run(1)
		ticks += 1
	_expect(not gd.wants_care(2), "a bot on work tends a plant that wants it (%d s)" % (ticks / Net.TICK_HZ))
	server.ship.store[Plants.seed_item(Plants.MUSHROOM)] = 1
	ticks = 0
	while gd.stage[3] == Net.GROW_EMPTY and gd.stage[0] == Net.GROW_EMPTY and gd.stage[1] == Net.GROW_EMPTY and ticks < 60 * Net.TICK_HZ:
		_run(1)
		ticks += 1
	_expect(int(server.ship.store[Plants.seed_item(Plants.MUSHROOM)]) == 0, "and plants a seed from the locker in an empty tray (%d s)" % (ticks / Net.TICK_HZ))
	for b in server.players:
		if b != null and b.bot:
			b.order = Net.POST_FREE
	server.crew.remove(cap)
	kept = []


func _cryo() -> void:
	print("  -- the cryopods")
	var p = server.crew.new_player("Спящий")
	server.reserve = 2
	p.health = Net.HEALTH_DEAD
	p.cond = Net.COND_DEAD
	server.crew.respawn_from_reserve(p)
	var here: int = p.st.y * server.map.width + p.st.x
	var near := false
	for pod: int in server.map.cryo:
		near = near or absi(pod % server.map.width - p.st.x) + absi(pod / server.map.width - p.st.y) == 1
	_expect(near and server.reserve == 1, "one from the reserve wakes in front of a cryopod")
	server.crew.remove(p)
	for c in server.corpses.duplicate():
		pass
	_expect(here >= 0, "")


func _flagship() -> void:
	print("  -- the roaming flagship")
	var f: Flagship = server.flagship
	f.setup(server)
	f.forced = 1                         # (the battleship: it cannot take the ship while the test waits)
	keep_hull = true
	server.story.codes = false
	_enter_cluster(0)
	_run(2)
	_expect(not f.awake and f.goal() == Sectors.NO_GOAL, "in another cluster, it sleeps out of sight")
	_enter_cluster(Sectors.FLAG_DEPTH)
	var goal := f.goal()
	_run(2)
	_expect(f.awake and goal != Sectors.NO_GOAL, "come into its cluster, it wakes")
	var pkt := server.story.story_packet()
	_expect(pkt[1] & Net.STORY_FLAGSHIP != 0, "the chart is told where it is")
	_run(roundi(Flagship.GROW_SECONDS * Net.TICK_HZ) + 2)
	_expect(f.growth == 1, "after %d s it has grown a step" % int(Flagship.GROW_SECONDS))
	if server.derelict.here:                   # (it may have found us meanwhile)
		server.derelict._leave(true)
	server.gunnery.enemy_gone()
	var away: Vector2i = server.sectors.cell[server.ship.sector]   # away from it again: it roams on its own
	var dist := server.sectors.distances(server.sectors.index_of(f.at))
	for i in server.sectors.count:
		if dist[i] > dist[server.sectors.index_of(away)] and server.sectors.kind[i] != Sectors.FLAGSHIP:
			away = server.sectors.cell[i]
	_arrive_at(away)
	f._come_at = -1
	_run(2)
	var moved := false
	var start := f.at
	for i in 6:
		_run(roundi(Flagship.MOVE_SECONDS * Net.TICK_HZ))
		moved = moved or f.at != start
		_expect(f.in_area(f.at), "")
	_expect(moved, "it moves about its cluster")
	f.growth = 0
	var plain: Dictionary = server.shipyard.flagship(1, server.derelict._pirate_spots())
	f.growth = 4
	var grown: Dictionary = server.shipyard.flagship(1, server.derelict._pirate_spots())
	_expect(float(grown["slower"]) < float(plain["slower"]) and float(grown["regen"]) > float(plain["regen"]), "grown: faster guns, a quicker shield")
	_expect(bool(grown["teleport"]) and not bool(plain["teleport"]) and bool(grown["guard"]), "and the battleship carries boarders and point defence")
	var room_sys: PackedByteArray = grown["room_sys"]
	_expect(room_sys.has(Net.ESYS_TELEPORT), "its teleporter has a room")
	# it comes into our sector
	f.growth = 1                         # (no boarders: they could take the ship while the test waits)
	if server.derelict.here:
		server.derelict._leave(true)
	var ours: Vector2i = server.sectors.cell[server.ship.sector]
	f.at = ours
	f._come_at = server.tick + roundi(Flagship.WARN_SECONDS * Net.TICK_HZ)
	_run(roundi(Flagship.WARN_SECONDS * Net.TICK_HZ) + 5)
	_expect(server.gunnery.boss == 1 and server.gunnery.fighting(), "meeting it, the fight begins")
	var gnow := f.growth
	_run(roundi(Flagship.GROW_SECONDS * Net.TICK_HZ) + 5)
	_expect(f.growth == gnow and f.caught(), "while it fights it neither grows nor moves")
	server.derelict._leave(true)
	server.gunnery.enemy_gone()
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	_run(2)
	keep_hull = false


func _modes() -> void:
	print("  -- the modes")
	server.over = Net.OVER_NONE          # (the flagship's anti-crew guns may have taken the ship just before)
	server.mode = Net.MODE_EASY
	server.ship.hull_max = Net.HULL_MAX
	server.ship.hull = 10
	server.crew.hull_hit(20)
	_expect(server.over == Net.OVER_NONE and server.ship.hull_max == Net.HULL_MAX - Net.EASY_HULL_LOSS and server.ship.hull == server.ship.hull_max,
		"easy: a hull worn through costs %d of its top strength, not the voyage" % Net.EASY_HULL_LOSS)
	server.mode = Net.MODE_NORMAL
	var party := server.director._party()
	server.mode = Net.MODE_HARD
	_expect(server.director._party() == party + 1, "hard: one boarder more")
	var r := 0
	for i in 20:
		var d: Dictionary = server.shipyard.make(1, true, server.derelict._pirate_spots())
		r += int(d["temper"] == Net.TEMPER_CAUTIOUS)
	_expect(r == 0, "hard: no cautious pirates")
	_expect(server.flagship._grow_period() == Flagship.GROW_HARD, "hard: the flagship grows faster")
	server.mode = Net.MODE_NORMAL


func _saved() -> void:
	print("  -- saving")
	server.mode = Net.MODE_HARD
	server.ship.hull_max = 150
	server.ship.hull = 120
	_answer("beacon", 0)
	var quests := server.story.quests.size()
	server.story.chapter = 2
	server.story.sos_done[12345] = true
	server.garden.plant(3, Plants.seed_item(Plants.SOY, Plants.CHOICE))
	server.garden.growth[3] = 0.4
	server.flagship.awake = true
	server.flagship.growth = 3
	server.flagship.at = server.sectors.cell[server.ship.sector]
	var data := Campaign.snapshot(server)
	var json: Dictionary = JSON.parse_string(JSON.stringify(data))
	var other := _new_server(26401)
	var problem := Campaign.restore(other, json)
	_expect(problem == "", "it restores (%s)" % problem)
	_expect(other.mode == Net.MODE_HARD and other.ship.hull_max == 150 and other.ship.hull == 120, "the mode and the hull's top strength")
	_expect(other.story.quests.size() == quests and other.story.chapter == 2 and other.story.sos_done.has(12345), "quests, the chapter, SOS answered")
	_expect(other.garden.plants[3] == Plants.seed_item(Plants.SOY, Plants.CHOICE) and absf(other.garden.growth[3] - 0.4) < 0.01, "the trays")
	_expect(other.flagship.awake and other.flagship.growth == 3 and other.flagship.at == server.flagship.at, "the flagship's roaming and growth")
	other.stop()


func _run(ticks: int) -> void:
	for t in ticks:
		if keep_hull:
			server.ship.hull = server.ship.hull_max
		for k in kept:
			k.health = 100.0
			k.wounds = 0.0
			k.tank = 1.0
		server._tick()


func _expect(ok: bool, what: String) -> void:
	if what == "":
		if not ok:
			failed += 1
			print("  FAIL  (a step above)")
		return
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
