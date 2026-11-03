extends SceneTree
## Checks v103 (his P1, P2, S2, L14 answers on the run-length page), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/heattest.gd
## Heat instead of the hunters' clock (it rises by itself at the mode's pace, noise adds to it, a harbour and
## a nebula drain it, full it brings a hunter and starts again, a new cluster starts at 0), the cluster's
## contract (offered a little after coming in, never in the flagship's cluster; cargo, survey and captain done,
## paid with credits, a crate and less heat), the second chance once an act on normal only, the chart's packet,
## the save, and the story so far for a continued run. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Road := preload("res://src/server/road.gd")
const Story := preload("res://src/server/story.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Gear := preload("res://src/shared/gear.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = _new_server(26610)
	if server == null:
		quit(1)
		return
	_heat()
	_contracts()
	_chance()
	_saved()
	server.stop()
	server.free()
	print("heattest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _new_server(port: int) -> GameServer:
	var s := GameServer.new()
	get_root().add_child(s)
	var problem := s.start(port, "ship02", 1)
	if problem != "":
		print(problem)
		return null
	s.director.auto = true             # (heat counts only while the director sends things; its own events are held off in _run)
	s.director.quiet_start = false
	s.story.auto = false
	s.road.auto = true
	s.road.breather = 0.0
	s.gunnery.flies = false
	s.arena.enabled = false            # (the old fight: the captain's ship comes out and is wrecked by hand)
	s.wing.chance_for_test = 0.0
	s.systems.knock_chance = 0.0
	s.stations.volunteers = false
	return s


func _run(ticks: int, keep_hull: bool = true) -> void:
	for t in ticks:
		server.director._next_tick = 1 << 40   # (no events of the director's own)
		if keep_hull:
			server.ship.hull = server.ship.hull_max
		server._tick()


func _calm() -> void:
	if server.derelict.here:
		server.derelict._leave(true)
	server.gunnery.enemy_gone()
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	server.road._fight = {}
	server.road.hunters = []
	server.road.hulks = {}
	_run(2)


func _arrive_at(cell: Vector2i) -> void:
	server.been[Sectors.key(cell)] = true
	server.road.build(cell)
	server.ship.sector = server.sectors.here
	server.sectors.visited[server.ship.sector] = 1
	server.ship.pos = server.sectors.entry[server.ship.sector]
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	server.story.entered_sector()
	_run(1)


func _enter_cluster(depth: int) -> void:
	server.road.depth = depth
	server.road.entry = Vector2i(6 * depth, 0)
	server.road.hunters = []
	server.road._restart_clock()
	_arrive_at(server.road.entry)


func _plain() -> int:
	## A system of this cluster that is no harbour, no nebula and not the flagship's (not where we are).
	var s: Sectors = server.sectors
	for i in s.count:
		if i != server.ship.sector and s.kind[i] != Sectors.STATION and s.kind[i] != Sectors.FLAGSHIP and s.fog[i] == 0:
			return i
	return -1


func _near(a: float, b: float, what: String) -> void:
	_expect(absf(a - b) < 0.5, "%s (%.1f, wanted %.1f)" % [what, a, b])


# --------------------------------------------------------------- heat

func _heat() -> void:
	print("  -- heat")
	var r: Road = server.road
	var s: Sectors = server.sectors
	_enter_cluster(0)
	_arrive_at(s.cell[_plain()])
	r.heat = 0.0
	server.mode = Net.MODE_NORMAL
	_run(60 * Net.TICK_HZ)
	_near(r.heat, 60.0 * Road.HEAT_FULL / Road.HEAT_QUIET, "a quiet minute on normal in the frontier")
	r.heat = 0.0
	server.mode = Net.MODE_EASY
	_run(60 * Net.TICK_HZ)
	_near(r.heat, 60.0 * Road.HEAT_FULL / Road.HEAT_QUIET / 2.0, "half that on easy (the mode's pace is no longer swapped)")
	r.heat = 0.0
	server.mode = Net.MODE_HARD
	_run(60 * Net.TICK_HZ)
	_near(r.heat, 60.0 * Road.HEAT_FULL / Road.HEAT_QUIET / 0.75, "more on hard")
	server.mode = Net.MODE_NORMAL
	# noise
	r.heat = 0.0
	_expect(server.derelict.pirates_come(2, true), "")
	_near(r.heat, Road.HEAT_FIGHT, "a pirate ship coming out to fight is heard")
	server.gunnery.parting_volley()
	_near(r.heat, Road.HEAT_FIGHT + Road.HEAT_ESCAPE, "jumping away from it, more")
	_calm()
	r.heat = 0.0
	_arrive_at(s.cell[_plain()])
	_near(r.heat, Road.HEAT_JUMP, "a jump")
	# a harbour drains it, a nebula keeps it from rising
	var st := s.kind.find(Sectors.STATION)
	_arrive_at(s.cell[st])
	_expect(r.harbour() and r.road_flags() & Net.ROAD_HARBOUR != 0 and r.road_flags() & Net.ROAD_COOLING != 0, "a station's system is a harbour")
	r.heat = 50.0
	_run(30 * Net.TICK_HZ)
	_near(r.heat, 50.0 - 30.0 * Road.HEAT_FULL / Road.HEAT_HARBOUR, "the harbour drains it")
	_arrive_at(s.cell[_plain()])
	var fog_was: int = s.fog[server.ship.sector]
	s.fog[server.ship.sector] = 1
	r.heat = 50.0
	_run(60 * Net.TICK_HZ)
	_expect(r.heat < 50.0 and r.heat > 35.0, "a nebula slowly drains it (%.1f)" % r.heat)
	s.fog[server.ship.sector] = fog_was
	# full, a hunter comes and it starts again
	_calm()
	r.heat = Road.HEAT_FULL - 0.01
	_run(Net.TICK_HZ + 1)
	_expect(r.hunters.size() == 1 and r.heat < 1.0, "full, a hunter comes into the cluster and the heat starts again")
	r.hunters = []
	# quiet start and tests' switch keep it still
	r.auto = false
	r.heat = 20.0
	_run(10 * Net.TICK_HZ)
	_expect(r.heat == 20.0 and r.road_flags() & Net.ROAD_HEATING == 0, "with hunters off it stays still")
	r.auto = true
	# the packet
	var client := GameClient.new()
	r.heat = 42.0
	client._read_road(r.packet())
	_expect(int(client.road["heat"]) == 42 and int(client.road["road_flags"]) == r.road_flags(), "the client reads the heat and its flags")
	client.free()
	# a new cluster starts at 0
	r.heat = 80.0
	r.next_cluster(0)
	_run(1)
	_expect(r.heat < 1.0 and r.depth == 1, "a new cluster starts quiet")
	_calm()


# --------------------------------------------------------------- contracts

func _contracts() -> void:
	print("  -- contracts")
	var r: Road = server.road
	var st: Story = server.story
	var s: Sectors = server.sectors
	_enter_cluster(1)
	st.quests = []
	st.contract_for = -1
	_run(roundi(Story.CONTRACT_AFTER * Net.TICK_HZ) + Net.TICK_HZ)
	var c := st.contract()
	_expect(not c.is_empty() and st.contract_for == 1, "a contract comes over the comms a little after coming into a cluster")
	_expect(not c.is_empty() and int(c["reward"]) == Story.CONTRACT_BASE + Story.CONTRACT_STEP, "paid %d" % (Story.CONTRACT_BASE + Story.CONTRACT_STEP))
	var side := st._side_quests()
	_expect(side == 0, "it is not one of the side quests")
	_run(30 * Net.TICK_HZ)
	_expect(st.quests.size() == 1, "and only one a cluster")
	# (a cluster with a station and a wreck: a dead zone has no station, some clusters no wreck)
	for depth in range(1, 12):
		if depth == Sectors.FLAG_DEPTH:
			continue
		_enter_cluster(depth)
		if s.kind.count(Sectors.STATION) > 0 and s.kind.count(Sectors.DERELICT) > 0 and s.kind[server.ship.sector] != Sectors.STATION:
			break
	st.contract_for = r.depth
	# cargo
	st.quests = []
	var crates: int = int(server.ship.store.get(Net.ITEM_CARGO, 0))
	_expect(st.offer_contract(Net.QUEST_CARGO), "a cargo contract")
	c = st.contract()
	_expect(int(server.ship.store.get(Net.ITEM_CARGO, 0)) == crates + 1, "its crate goes into the locker")
	var credits: int = server.ship.credits
	var gear := _gear_count()
	r.heat = 70.0
	_arrive_at(c["at"])
	_expect(st.contract().is_empty() and server.ship.credits == credits + int(c["reward"]), "delivered at its station: paid")
	_expect(_gear_count() == gear + 1, "with a crate of ship gear")
	_expect(r.heat <= 70.0 - Road.HEAT_CONTRACT + Road.HEAT_JUMP + 0.5, "and the heat falls (%.1f)" % r.heat)
	# survey
	_calm()
	_expect(st.offer_contract(Net.QUEST_SURVEY), "a survey contract")
	c = st.contract()
	_arrive_at(c["at"])
	_expect(server.derelict.pirates_come(2, true), "")
	_run(70 * Net.TICK_HZ)
	_expect(not st.contract().is_empty(), "in a fight it surveys nothing")
	_calm()
	credits = server.ship.credits
	_run((Story.SURVEY_SECONDS + 2) * Net.TICK_HZ)
	_expect(st.contract().is_empty() and server.ship.credits == credits + int(c["reward"]), "held still %d s: done" % Story.SURVEY_SECONDS)
	# a captain
	_calm()
	_expect(st.offer_contract(Net.QUEST_BOUNTY), "a captain's contract")
	c = st.contract()
	_arrive_at(c["at"])
	_run(roundi((Story.HUNT_DELAY + 1) * Net.TICK_HZ))
	_expect(server.gunnery.fighting() and str(server.derelict.design.get("name", "")).contains(str(c["pirate"])), "the captain comes out to fight")
	credits = server.ship.credits
	server.gunnery._wrecked()
	_run(Net.TICK_HZ)
	_expect(st.contract().is_empty() and server.ship.credits >= credits + int(c["reward"]), "wrecked: done")
	_calm()
	# a black box: a wreck's system
	st.quests = []
	_expect(st.offer_contract(Net.QUEST_BLACKBOX) and s.kind[s.cell.find(st.contract()["at"])] == Sectors.DERELICT, "a black box from a wreck")
	# lost with the cluster
	r.next_cluster(0)
	_run(1)
	_expect(st.contract().is_empty(), "leaving the cluster loses it")
	# none in the flagship's cluster
	_enter_cluster(Sectors.FLAG_DEPTH)
	st.quests = []
	st.contract_for = -1
	_run(roundi(Story.CONTRACT_AFTER * Net.TICK_HZ) + Net.TICK_HZ)
	_expect(st.contract().is_empty() and st.contract_for == Sectors.FLAG_DEPTH, "none in the flagship's cluster: the flagship is its task")
	_calm()


func _gear_count() -> int:
	var n := 0
	for item: int in server.ship.store:
		if Gear.of_item(item) != Gear.NONE or Weapons.of_item(item) != Weapons.NONE:
			n += int(server.ship.store[item])
	return n


# --------------------------------------------------------------- the second chance

func _chance() -> void:
	print("  -- the second chance")
	var other := _new_server(26611)
	_expect(str(other.run_log.lines[0]).contains(Net.MODE_NAMES[other.mode].to_lower()), "the run log names the mode right (%s)" % other.run_log.lines[0])
	other.mode = Net.MODE_NORMAL
	var r: Road = other.road
	r.depth = 0
	_expect(r.chance_left(), "normal mode: act 1 has its chance")
	other.crew.hull_hit(other.ship.hull)
	_expect(other.over == Net.OVER_NONE and other.ship.hull_max == Net.HULL_MAX - Net.EASY_HULL_LOSS and other.ship.hull == other.ship.hull_max,
		"the hull gives way: the frame holds once, top strength -%d" % Net.EASY_HULL_LOSS)
	_expect(not r.chance_left() and r.road_flags() & Net.ROAD_CHANCE == 0, "spent for this act")
	r.depth = Road.ACT_CLUSTERS
	_expect(r.chance_left(), "the next act has its own")
	r.depth = 1
	other.crew.hull_hit(other.ship.hull)
	_expect(other.over == Net.OVER_WRECKED, "a second time in the same act the run is lost")
	other.stop()
	other.free()
	var hard := _new_server(26612)
	hard.mode = Net.MODE_HARD
	_expect(not hard.road.chance_left(), "hard mode has none")
	hard.crew.hull_hit(hard.ship.hull)
	_expect(hard.over == Net.OVER_WRECKED, "one life on hard")
	hard.stop()
	hard.free()


# --------------------------------------------------------------- saving

func _saved() -> void:
	print("  -- saving and the story so far")
	var r: Road = server.road
	_enter_cluster(2)
	server.story.quests = []
	server.story.contract_for = -1
	_run(roundi(Story.CONTRACT_AFTER * Net.TICK_HZ) + Net.TICK_HZ)
	r.heat = 33.0
	r.chances = {0: true}
	var c := server.story.contract()
	var json: Dictionary = JSON.parse_string(JSON.stringify(Campaign.snapshot(server)))
	var other := _new_server(26613)
	var problem := Campaign.restore(other, json)
	_expect(problem == "", "it restores (%s)" % problem)
	_expect(is_equal_approx(other.road.heat, 33.0) and other.road.chances.has(0), "the heat and the spent chance")
	var oc: Dictionary = other.story.contract()
	_expect(other.story.contract_for == 2 and not oc.is_empty() and Story.job(oc) == Story.job(c) and oc["at"] == c["at"], "the contract")
	_expect(other.run_log.resumed, "a continued run")
	var pkt: PackedByteArray = other.run_log.recap_packet()
	var client := GameClient.new()
	client._on_packet(pkt)
	var text: String = pkt.slice(3, 3 + pkt.decode_u16(1)).get_string_from_utf8()
	_expect(pkt[0] == Net.S_RECAP and text.contains("Шум: 33") and text.contains(str(c["text"])) and client.recap == text, "the story so far tells the heat and the contract (and the client keeps it)")
	client.free()
	other.stop()
	other.free()


func _expect(ok: bool, what: String) -> void:
	if what == "":
		if not ok:
			failed += 1
			print("  FAIL  (a step above)")
		return
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
