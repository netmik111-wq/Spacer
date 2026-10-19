extends SceneTree
## Plays whole games on its own and records what happened (2026-10-19, the
## author: "simulate the full game from start to finish, I need numbers").
## Not a test: it always passes.
##   godot --headless --path . --script res://tools/playthrough.gd -- OUT_DIR [runs] [first run number] [mode] [hours] [stay]
## Each run is a fresh campaign on a real server stepped by hand: ship02, a
## captain (this script) and three bots. The bots get orders as a sensible
## captain would give them: one at the helm (dodging), two on «Работы» (they
## mend, patch holes, fetch supplies). The captain:
##   - in a fight sits at the gun console, aims like tools/fightbench.gd and fires
##     whatever is ready; takes a ransom when offered; jumps away if it can (never
##     from the flagship) with the hull under a quarter, three holes open, one of ours
##     knocked out, or a minute of fire that has not dented the enemy's hull;
##   - short of fuel or food in the locker, fetches cans and rations lying about (the
##     floor, bodies, a wreck alongside) at once, and draws off from a docked wreck;
##   - answers every comms call with a choice open to it (a blue one first);
##   - at a trader or a station flies up to it and buys fuel, food, hull and
##     patches as it needs them;
##   - travels: in each cluster to the nearest exit (the flagship's cluster: to the
##     flagship), stopping at a trader or station on the way when short of fuel,
##     food or hull;
##   - stays about `stay` seconds in each system before jumping on (0.6 to 1.4 times
##     it, by lot), as a person who looks round, loots and mends would; 0 = it
##     jumps as soon as the drive is ready. The director's events come every few
##     minutes, so a captain who never stays meets almost none of them.
## The captain steps from console to console at once (no walking), so the ship is
## run a little better than by a person who walks. A run ends when the flagship is
## beaten (won), the campaign is lost, or after `hours` of game time.
## Writes OUT_DIR/run-NN.json (summary, counts, a line per jump) and OUT_DIR/run-NN.log
## (the ship's log: every line the ship said), and prints a one-line summary per run.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Net := preload("res://src/shared/net.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Tales := preload("res://src/server/tales.gd")

const BOTS := 3
const KIND_NAMES := ["quiet", "meteors", "trader", "station", "derelict", "flagship", "ion storm"]
const WANT_FUEL := 3                  # cans the captain keeps in the locker when it can buy (v67: each 100 units)
const WANT_FOOD := 8
const WANT_PATCHES := 4
const LOW_FUEL := 4                   # (v67: jumps' worth of fuel, tank and cans) under this (on top of a long jump's) it goes out of its way to a trader
const LOW_HULL := 0.5                 # under this share of the hull, likewise
const EXPLORE_SHARE := 0.6            # it looks round this share of a cluster's systems before leaving it...
const EXPLORE_TICKS := 20 * 60 * 20   # ... or for this long at most (the flagship's cluster: straight to it)
const KEEP_CREDITS := 40              # what it keeps in hand when it buys a better gun

var server: GameServer
var cap = null                        # the captain (a Player)
var out_dir := ""
var limit_ticks := 0

# what one run has seen so far
var rec := {}
var log_lines: PackedStringArray = []
var timeline: Array = []
var _credits := 0
var _hull := 0
var _fuel := 0
var _food := 0
var _fight := {}                      # the fight now on: {start, class, temper, boss, hull, hunter}
var _cause := ""                      # what the credits that change this tick are for
var _we_fled := false
var _ransom_taken := false
var _known_corpses := {}
var _last_sector := -1
var _last_depth := 0
var _holes := 0
var _shopped := -1                    # the visit (jumps, cluster) the captain last shopped in
var _cluster_since := 0               # the tick the ship came into this cluster
var _foe_hull := -1                   # the enemy's hull when last looked at, and the tick it last changed
var _foe_hit_at := 0
var _refilling := false
var _stay := 0.0                      # seconds it means to stay in each system
var _leave_at := 0                    # the tick it may jump on from this system


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "user://playthrough"
	var runs := int(args[1]) if args.size() > 1 else 1
	var first := int(args[2]) if args.size() > 2 else 1
	var mode := Net.MODE_KEYS.find(args[3]) if args.size() > 3 else Net.MODE_NORMAL
	var hours := float(args[4]) if args.size() > 4 else 3.0
	limit_ticks = roundi(hours * 3600.0 * Net.TICK_HZ)
	_stay = float(args[5]) if args.size() > 5 else 0.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	for r in runs:
		_run(first + r, maxi(mode, 0))
	quit(0)


# ----------------------------------------------------------------- one run

func _run(number: int, mode: int) -> void:
	server = GameServer.new()
	get_root().add_child(server)
	server.mode = mode
	var problem := server.start(27000 + number, "ship02", BOTS)
	if problem != "":
		print("run %d: %s" % [number, problem])
		server.free()
		return
	server.log_line.connect(_heard)
	log_lines = []
	timeline = []
	_fight = {}
	_known_corpses = {}
	cap = server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	_give_orders()
	rec = {
		"run": number, "seed": server.space_seed, "mode": Net.MODE_KEYS[mode], "stay_seconds": _stay, "outcome": "", "game_minutes": 0.0,
		"jumps": 0, "long_jumps": 0, "clusters_reached": 1, "systems_visited": 0, "farthest": 0,
		"credits": {"start": server.ship.credits, "end": 0, "earned": 0, "spent": 0, "most_held": server.ship.credits,
			"earned_by": {}, "spent_on": {}},
		"bought": {}, "fuel": {"bought": 0, "used": 0, "found": 0, "ran_dry": 0},
		"food": {"bought": 0, "eaten": 0, "grown_or_found": 0},
		"hull": {"start": server.ship.hull, "lost": 0, "mended": 0, "lowest": server.ship.hull, "end": 0},
		"holes_made": 0,
		"fights": {"total": 0, "seconds": 0, "hull_lost": 0, "by_class": {}, "by_end": {}, "hunters": 0},
		"flagship": {"met": false, "growth_when_met": -1, "result": ""},
		"crew": {"deaths": 0, "bot_deaths": 0, "captain_deaths": 0, "respawns": 0, "reserve_end": 0, "hired": 0},
		"pirates_killed": 0, "boarders_seen": 0, "guns_bought": [],
		"calls": {"received": 0, "answered": 0, "unanswered": 0, "titles": {}},
		"quests": {"done": 0, "failed": 0},
		"sectors_by_kind": {}, "places_taken": 0,
	}
	_credits = server.ship.credits
	_hull = server.ship.hull
	_fuel = _jumps_left()
	_food = int(server.ship.store.get(Net.ITEM_FOOD, 0))
	_last_sector = server.ship.sector
	_last_depth = 0
	_cluster_since = server.tick
	_shopped = -1
	_holes = server.air.holes.size()
	_count_kind(server.navigation.sector_kind())
	var start := server.tick
	var stuck_since := server.tick
	var last_jumps := 0
	while server.over == Net.OVER_NONE and not server.won and server.tick - start < limit_ticks:
		_cause = ""
		if server.tick % 5 == 0:
			_think()
		server._tick()
		_watch()
		if server.jumps != last_jumps:
			last_jumps = server.jumps
			stuck_since = server.tick
		elif server.tick - stuck_since > 8 * 60 * Net.TICK_HZ and server.tick % (60 * Net.TICK_HZ) == 0 and _unstick():
			pass
		elif server.tick - stuck_since > 25 * 60 * Net.TICK_HZ:
			rec["outcome"] = "stuck (no jump for 25 min)"
			var sh = server.ship
			rec["stuck_why"] = {"target": _target(), "here": sh.sector, "fuel": _jumps_left(), "engine_down": server.engine_down(),
				"powered": server.powered(), "holds_ship": server.derelict.holds_ship(), "holds_jump": server.flagship.holds_jump(),
				"cannot_jump": str(server.navigation.cannot_jump()), "broken": str(sh.broken), "credits": sh.credits,
				"fighting": server.gunnery.fighting(), "here_kind": server.navigation.sector_kind(), "drive_wait": sh.drive_ready - server.tick,
				"captain_cond": cap.cond, "captain_health": cap.health, "hunger": server.garden.hunger_of(cap),
				"food": int(sh.store.get(Net.ITEM_FOOD, 0)), "docked": server.derelict.docked}
			if cap.cond == Net.COND_CRIT:
				rec["outcome"] = "stuck: the captain is down and cannot wake (hunger %.0f)" % server.garden.hunger_of(cap)
			break
	if rec["outcome"] == "":
		if server.won:
			rec["outcome"] = "won"
		elif server.over != Net.OVER_NONE:
			rec["outcome"] = ["", "lost: hull gave way", "lost: crew dead", "lost: captured"][server.over]
		else:
			rec["outcome"] = "time limit"
	_finish(server.tick - start)
	server.stop()
	server.free()


func _give_orders() -> void:
	var st = server.stations
	var bots: Array = []
	for q in server.players:
		if q != null and q.bot and not q.pirate and not q.ally:
			bots.append(q)
	var posts := [Net.POST_HELM, Net.POST_REPAIR, Net.POST_REPAIR, Net.POST_REPAIR]
	for i in bots.size():
		st.order_asked(cap, bots[i].slot, posts[mini(i, posts.size() - 1)])


# ------------------------------------------------------------- the captain

func _think() -> void:
	if cap.corpse or cap.cond == Net.COND_DEAD:
		if server.reserve > 0:
			server.crew.respawn_from_reserve(cap)
			rec["crew"]["respawns"] += 1
		return
	if cap.cond != Net.COND_OK:
		return
	if _breathe():
		return
	cap.using = false                        # (held again below while it mends a broken console)
	var g = server.gunnery
	if g.fighting():
		_fight_tick()
		return
	if not server.story.call.is_empty():
		_answer_call()
		return
	if server.tick % (5 * Net.TICK_HZ) == 0:
		_arm_guns()
		_fetch(Net.ITEM_FUEL, 2)
		_pour()
		_fetch(Net.ITEM_FOOD, 2)
	if server.derelict.docked and _jumps_left() > 0 and server.tick >= _leave_at:
		server.derelict.dock(false)          # (a pirate ship that docked by force, or its wreck: draw off to jump on)
	if server.ship.jump_to != Net.NO_SECTOR:
		return
	var kind: int = server.navigation.sector_kind()
	var visit := server.jumps * 1000 + server.road.depth
	if (kind == Sectors.TRADER or (kind == Sectors.STATION and server.ship.store_air < Net.STORE_AIR_FULL * 0.5)) \
			and _shopped != visit and _wants_shopping():
		if not server.ship.in_reach:
			_fly_to(server.sectors.spot[server.ship.sector])
			return
		_shop()
		_shopped = visit                     # (once a visit: what it could not buy here it will not find by waiting)
	_travel()


func _breathe() -> bool:
	## The suit's oxygen on in thin air (as bots do), and a low tank filled at an oxygen
	## station before anything else. True while it is filling.
	server.stations.bot_breathe(cap)
	var filling: bool = _refilling and cap.tank < 0.95
	if cap.has_suit() and (cap.tank < 0.35 or filling) and not server.map.oxygen.is_empty() and server.powered() \
			and _at(server.map.oxygen):
		cap.using = true
		_refilling = true
		return true
	if _refilling:
		_refilling = false
		cap.using = false
		rec["crew"]["tank_refills"] = int(rec["crew"].get("tank_refills", 0)) + 1
	return false


func _unstick() -> bool:
	## Eight minutes with no jump outside a fight: the captain's plan has run into
	## something it does not handle. Note what it was (once), give up on this
	## system's trader and jump to a neighbour. True if a jump was set.
	var sh = server.ship
	if server.gunnery.fighting() or cap.cond != Net.COND_OK or _jumps_left() < 1 or sh.jump_to != Net.NO_SECTOR:
		return false
	if not rec.has("first_stall"):
		rec["first_stall"] = {"t": snappedf(server.voyage_ticks / float(Net.TICK_HZ) / 60.0, 0.1), "target": _target(), "here": sh.sector,
			"kind": server.navigation.sector_kind(), "fuel": _jumps_left(), "credits": sh.credits, "in_reach": sh.in_reach,
			"moving": sh.moving, "shopped": _shopped == server.jumps * 1000 + server.road.depth, "wants_shopping": _wants_shopping(),
			"call_open": not server.story.call.is_empty(), "holds_ship": server.derelict.holds_ship(),
			"holds_jump": server.flagship.holds_jump(), "derelict_here": server.derelict.here, "leave_wait": _leave_at - server.tick,
			"broken": str(sh.broken.keys()), "engine_down": server.engine_down(), "powered": server.powered()}
	rec["stalls"] = int(rec.get("stalls", 0)) + 1
	_shopped = server.jumps * 1000 + server.road.depth
	if not server.story.call.is_empty():
		server.story.answer_asked(cap, 0)
	server.derelict.dock(false)
	var ns: PackedInt32Array = server.sectors.neighbours(sh.sector)
	if ns.is_empty() or not _at(server.map.chart):
		return false
	server.navigation.jump_asked(cap, ns[randi() % ns.size()])
	return sh.jump_to != Net.NO_SECTOR


func _fetch(item: int, want: int) -> void:
	## Short of fuel or food in the locker, the crew fetch what lies about (the floor, bodies, a wreck
	## alongside) and put it in: a person would walk over for it; the captain here does it at once.
	var ship = server.ship
	var have := int(ship.store.get(item, 0))
	if have >= want:
		return
	var got := 0
	for cell: int in server.floor_things.keys():
		var things: PackedByteArray = server.floor_things[cell]
		var changed := false
		for i in things.size():
			if things[i] == item and have + got < want:
				things[i] = Net.ITEM_NONE
				got += 1
				changed = true
		if changed:
			server.floor_things[cell] = things
			server.replication.floor_record(cell)
	for q in server.players:
		if q != null and (q.corpse or q.cond == Net.COND_DEAD) and q != cap:
			while have + got < want and q.count(item) > 0 and q.remove(item):
				got += 1
	if got > 0:
		ship.store[item] = have + got
		server.supplies.tell_store()
		var k := "fuel" if item == Net.ITEM_FUEL else "food"
		rec[k]["fetched"] = int(rec[k].get("fetched", 0)) + got
		_food = int(ship.store.get(Net.ITEM_FOOD, 0))
		_fuel = _jumps_left()


func _fight_tick() -> void:
	var g = server.gunnery
	if g.ransom > 0 and not server.stations.ours_aboard:
		_at(server.map.gun_console)
		_ransom_taken = true
		_cause = "ransom"
		g.ransom_taken(cap)
		return
	var ship = server.ship
	if g.enemy_hull != _foe_hull:
		_foe_hull = g.enemy_hull
		_foe_hit_at = server.tick
	if g.boss == 0 and _losing() and not server.navigation.cannot_jump() and server.tick >= ship.drive_ready \
			and ship.jump_to == Net.NO_SECTOR and server.derelict.holds_ship() == "":
		var next := _next_hop(_target())
		if next >= 0 and _at(server.map.chart):
			server.navigation.jump_asked(cap, next)
			if ship.jump_to != Net.NO_SECTOR:
				_we_fled = true
				return
	if _at(server.map.gun_console):
		g.aim = _aim(g)
		g.fire(cap, 255)


func _losing() -> bool:
	## Would a sensible captain cut and run now? The hull under a quarter, three holes
	## letting the air out, one of ours down, or a minute of fire without denting its hull.
	var ship = server.ship
	if ship.hull < ship.hull_max / 4 or server.air.holes.size() >= 3:
		return true
	if server.tick - _foe_hit_at > 60 * Net.TICK_HZ:
		return true
	for q in server.players:
		if q != null and not q.pirate and not q.ally and not q.corpse and q.cond != Net.COND_OK:
			return true
	return false


func _aim(g) -> int:
	## Where a sensible gunner aims now (as tools/fightbench.gd).
	var want: Array = []
	if g.fleeing():
		want = [Net.ESYS_JUMP, Net.ESYS_ENGINE]
	if g.systems.size() > Net.ESYS_SHIELDS and g.systems_full[Net.ESYS_SHIELDS] > 0 and not g.down(Net.ESYS_SHIELDS):
		want.append(Net.ESYS_SHIELDS)
	if g.systems_full.size() > Net.ESYS_TELEPORT and g.systems_full[Net.ESYS_TELEPORT] > 0:
		want.append(Net.ESYS_TELEPORT)
	want.append_array([Net.ESYS_WEAPONS, Net.ESYS_CREW])
	for s: int in want:
		var room: int = g.room_of_system(s)
		if room >= 0 and g.revealed[room] == 1 and not g.down(s):
			return s
	return Net.AIM_ANY


func _answer_call() -> void:
	var st = server.story
	if not _at(server.map.comms):
		return
	st._refresh_flags()
	var flags: PackedByteArray = st.call["flags"]
	var open: Array = []
	var blue: Array = []
	for i in flags.size():
		if flags[i] & Net.CHOICE_SHUT:
			continue
		open.append(i)
		if flags[i] & Net.CHOICE_BLUE:
			blue.append(i)
	if open.is_empty():
		return
	var title: String = Tales.EVENTS[int(st.call["event"])]["title"]
	var pick: int = blue[randi() % blue.size()] if not blue.is_empty() else open[randi() % open.size()]
	_cause = "calls"
	st.answer_asked(cap, pick)
	rec["calls"]["answered"] += 1
	var titles: Dictionary = rec["calls"]["titles"]
	titles[title] = int(titles.get(title, 0)) + 1


func _wants_shopping() -> bool:
	var ship = server.ship
	if ship.credits < 5:
		return false
	return ship.fuel() < WANT_FUEL or int(ship.store.get(Net.ITEM_FOOD, 0)) < WANT_FOOD or ship.hull < ship.hull_max \
		or server.supplies.patches_aboard() < WANT_PATCHES or ship.store_air < Net.STORE_AIR_FULL * 0.5


func _shop() -> void:
	if not _at(server.map.locker):
		return
	var ship = server.ship
	var offers: Dictionary = server.supplies.offers()
	_cause = "trade"
	# the hull first while it is low, then fuel, food, patches, then the rest of the hull
	var tries := 0
	while tries < 60 and ship.hull < ship.hull_max * 0.6 and ship.credits >= Net.PRICE_HULL:
		_buy_hull()
		tries += 1
	_buy_up(Net.ITEM_FUEL, WANT_FUEL, offers)
	_buy_up(Net.ITEM_FOOD, WANT_FOOD, offers)
	_buy_up(Net.ITEM_PATCH, WANT_PATCHES, offers)
	while tries < 60 and ship.hull < ship.hull_max and ship.credits >= Net.PRICE_HULL + 20:
		_buy_hull()
		tries += 1
	if ship.store_air < Net.STORE_AIR_FULL * 0.5 and ship.credits >= Net.PRICE_AIR:
		server.supplies.store_asked(cap, Net.STORE_BUY_AIR, 0)
		_note_buy("air", Net.PRICE_AIR)
	_better_gun(offers)
	if server.reserve < 1 and ship.credits >= Net.PRICE_CREW + 40:
		server.supplies.store_asked(cap, Net.STORE_HIRE, 0)
		rec["crew"]["hired"] += 1
		_note_buy("crew", Net.PRICE_CREW)


func _better_gun(offers: Dictionary) -> void:
	## With money to spare, a gun clearly better than our weakest (by its price), put on in its place.
	var ship = server.ship
	var weakest := -1
	for i in ship.mounts.size():
		if weakest < 0 or _worth(ship.mounts[i]) < _worth(ship.mounts[weakest]):
			weakest = i
	if weakest < 0:
		return
	var best := -1
	for item: int in offers.keys():
		var w := Weapons.of_item(item)
		if w == Weapons.NONE or w == Weapons.GUARD or Weapons.ammo(w) != 0 or Weapons.damaged(item):
			continue
		if int(offers[item]) > ship.credits - KEEP_CREDITS or _worth(w) < _worth(ship.mounts[weakest]) * 1.3:
			continue
		if best < 0 or _worth(w) > _worth(Weapons.of_item(best)):
			best = item
	if best < 0:
		return
	var price: int = offers[best]
	server.supplies.store_asked(cap, Net.STORE_BUY, best)
	if int(ship.store.get(best, 0)) <= 0:
		return
	_note_buy("ship guns", price)
	var guns: Array = rec["guns_bought"]
	guns.append(Weapons.name_of(Weapons.of_item(best)))
	if _at(server.map.gun_console):
		server.gunnery.setup_asked(cap, Net.GUNSET_MOUNT, weakest, best)
	_at(server.map.locker)


func _worth(w: int) -> int:
	return 0 if w == Weapons.NONE else int(Weapons.info(w).get("price", 0))


func _arm_guns() -> void:
	var ship = server.ship
	for i in ship.mounts.size():
		if ship.mounts[i] != Weapons.NONE and ship.armed[i] == 0:
			if _at(server.map.gun_console):
				server.gunnery.arm(cap, i, true)


func _buy_hull() -> void:
	var was: int = server.ship.hull
	server.supplies.store_asked(cap, Net.STORE_BUY_HULL, 0)
	if server.ship.hull > was:
		_note_buy("hull", Net.PRICE_HULL)


func _buy_up(item: int, want: int, offers: Dictionary) -> void:
	var price: int = offers.get(item, 0)
	if price <= 0:
		return
	var n := 0
	while int(server.ship.store.get(item, 0)) < want and server.ship.credits >= price and n < 20:
		server.supplies.store_asked(cap, Net.STORE_BUY, item)
		n += 1
		_note_buy(Items.name_of(item), price)
		if item == Net.ITEM_FUEL:
			rec["fuel"]["bought"] += 1
		elif item == Net.ITEM_FOOD:
			rec["food"]["bought"] += 1


func _note_buy(what: String, price: int) -> void:
	var b: Dictionary = rec["bought"]
	b[what] = int(b.get(what, 0)) + 1
	var s: Dictionary = rec["credits"]["spent_on"]
	s[what] = int(s.get(what, 0)) + price


func _jumps_left() -> int:
	## (v67) Jumps' worth of fuel aboard: in the tank, and in cans in the locker.
	var ship = server.ship
	return floori((ship.tank + ship.fuel() * Net.CAN_FUEL) / maxi(ship.jump_cost, 1))


func _pour() -> void:
	## (v67) The crew pour a can into the tank when it runs low (as a bot on work does, at once).
	var ship = server.ship
	while ship.tank < ship.jump_cost * 2 and ship.fuel() > 0 and ship.tank <= Net.FUEL_MAX - Net.CAN_FUEL:
		ship.store[Net.ITEM_FUEL] = ship.fuel() - 1
		ship.tank += Net.CAN_FUEL
	server.supplies.tell_store()


func _travel() -> void:
	var ship = server.ship
	if server.tick < ship.drive_ready or server.engine_down() or server.derelict.holds_ship() != "" or server.flagship.holds_jump() != "":
		return
	if _jumps_left() < 1 or server.tick < _leave_at:
		return
	var s = server.sectors
	var here: int = ship.sector
	var target := _target()
	if target == here and s.exit_of(here) >= 0 and server.road.can_leave() == "" and not _flagship_cluster():
		if _at(server.map.chart):
			server.navigation.jump_asked(cap, Sectors.EXIT_JUMP)
		return
	if target == here:
		return
	var next := _next_hop(target)
	if next >= 0 and _at(server.map.chart):
		server.navigation.jump_asked(cap, next)


func _flagship_cluster() -> bool:
	return server.road.depth >= Sectors.FLAG_DEPTH and not server.won


func _target() -> int:
	## The system the captain makes for now.
	var s = server.sectors
	var ship = server.ship
	var here: int = ship.sector
	var dist: PackedInt32Array = s.distances(here)
	# short of something: the nearest trader or station, if one is near enough
	var short: bool = _jumps_left() < LOW_FUEL + Sectors.EXIT_FUEL or ship.hull < ship.hull_max * LOW_HULL \
		or int(ship.store.get(Net.ITEM_FOOD, 0)) < 2
	if short and ship.credits >= 10:
		var best := -1
		for i in s.count:
			var reach := 3 if _jumps_left() >= LOW_FUEL else 99      # (nearly dry: any trader at all)
			if s.kind[i] == Sectors.TRADER and dist[i] >= 0 and dist[i] <= reach and (best < 0 or dist[i] < dist[best]) \
					and not (i == here and _shopped == server.jumps * 1000 + server.road.depth):
				best = i
		if best >= 0:
			return best
	if _flagship_cluster():
		var f = server.flagship
		var at: int = s.index_of(f.where())
		if at >= 0:
			return at
	if _cluster_ticks() < EXPLORE_TICKS and _seen_share() < EXPLORE_SHARE:
		var near := -1
		for i in s.count:
			if s.visited[i] == 0 and dist[i] > 0 and s.kind[i] != Sectors.FLAGSHIP and (near < 0 or dist[i] < dist[near]):
				near = i
		if near >= 0:
			return near
	var exit := -1
	for e in s.exits:
		if dist[e] >= 0 and (exit < 0 or dist[e] < dist[exit]):
			exit = e
	return exit if exit >= 0 else here


func _cluster_ticks() -> int:
	return server.tick - _cluster_since


func _seen_share() -> float:
	var s = server.sectors
	var n := 0
	for i in s.count:
		n += int(s.visited[i])
	return float(n) / maxf(s.count, 1)


func _next_hop(target: int) -> int:
	var s = server.sectors
	var here: int = server.ship.sector
	if target < 0 or target == here:
		var ns: PackedInt32Array = s.neighbours(here)
		return ns[randi() % ns.size()] if not ns.is_empty() else -1
	var to_target: PackedInt32Array = s.distances(target)
	var best := -1
	for n in s.neighbours(here):
		if to_target[n] >= 0 and (best < 0 or to_target[n] < to_target[best]):
			best = n
	return best


func _fly_to(spot: Vector2) -> void:
	if server.ship.moving and server.ship.dest.is_equal_approx(spot):
		return
	if _at(server.map.helm):
		server.navigation.helm_asked(cap, true, spot)


func _at(cells: Dictionary) -> bool:
	## Steps the captain in front of a working console of that kind, facing it. If every
	## one of them is broken it steps up to one and mends it (slowly without a spare part).
	if server.systems.at_console(cap, cells):
		return true
	for c: int in cells.keys():
		if not server.ship.broken.has(c) and _face(c):
			return server.systems.at_console(cap, cells)
	for c: int in cells.keys():
		if _face(c):
			if not cap.using:
				rec["crew"]["captain_repairs"] = int(rec["crew"].get("captain_repairs", 0)) + 1     # (once per think: 5 ticks of mending)
			cap.using = true
			return false
	return false


func _face(c: int) -> bool:
	var map = server.map
	var x: int = c % map.width
	var y: int = c / map.width
	for d in [[0, 1, Net.DIR_UP], [0, -1, Net.DIR_DOWN], [1, 0, Net.DIR_LEFT], [-1, 0, Net.DIR_RIGHT]]:
		var sx: int = x + int(d[0])
		var sy: int = y + int(d[1])
		if not map.walkable(sx, sy) or map.door_at(sx, sy) >= 0:
			continue
		if map.use_ahead(sx, sy, int(d[2])) == c:
			cap.st.place(sx, sy)
			cap.st.facing = int(d[2])
			return true
	return false


# ------------------------------------------------------------- the records

func _heard(text: String) -> void:
	log_lines.append("[%s] %s" % [_clock(), text])
	if text.contains("Пульт связи: входящий вызов"):
		rec["calls"]["received"] += 1
	elif text.contains("(без ответа)"):
		rec["calls"]["unanswered"] += 1
	elif text.contains("выполнено.") and text.begins_with("[корабль] Задание"):
		rec["quests"]["done"] += 1
		_cause = "quests"
	elif text.contains("провалено.") and text.begins_with("[корабль] Задание"):
		rec["quests"]["failed"] += 1
	elif text.contains("За разведку нового сектора"):
		_cause = "exploring"


func _clock() -> String:
	var s: int = server.voyage_ticks / Net.TICK_HZ
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _watch() -> void:
	var ship = server.ship
	var g = server.gunnery
	# credits
	var dc: int = ship.credits - _credits
	if dc != 0:
		var c: Dictionary = rec["credits"]
		if dc > 0:
			c["earned"] += dc
			var why := _cause
			if why == "":
				why = "fights" if (g.fighting() or not _fight.is_empty()) else "other (calls, places, loot)"
			var by: Dictionary = c["earned_by"]
			by[why] = int(by.get(why, 0)) + dc
		else:
			c["spent"] += -dc
			if _cause != "trade":
				var s: Dictionary = c["spent_on"]
				var what := "calls" if _cause == "calls" else "other"
				s[what] = int(s.get(what, 0)) - dc
		c["most_held"] = maxi(int(c["most_held"]), ship.credits)
		_credits = ship.credits
	# hull
	var dh: int = ship.hull - _hull
	if dh < 0:
		rec["hull"]["lost"] += -dh
		if not _fight.is_empty():
			rec["fights"]["hull_lost"] += -dh
	elif dh > 0:
		rec["hull"]["mended"] += dh
	rec["hull"]["lowest"] = mini(int(rec["hull"]["lowest"]), ship.hull)
	_hull = ship.hull
	# fuel and food
	var df: int = _jumps_left() - _fuel
	if df < 0 and _cause != "trade":
		rec["fuel"]["used"] += -df
	elif df > 0 and _cause != "trade":
		rec["fuel"]["found"] += df
	_fuel = _jumps_left()
	var food := int(ship.store.get(Net.ITEM_FOOD, 0))
	var dfo := food - _food
	if dfo < 0:
		rec["food"]["eaten"] += -dfo
	elif dfo > 0 and _cause != "trade":
		rec["food"]["grown_or_found"] += dfo
	_food = food
	var holes: int = server.air.holes.size()
	if holes > _holes:
		rec["holes_made"] += holes - _holes
	_holes = holes
	# fights
	if g.fighting() and _fight.is_empty():
		_fight = {"start": server.tick, "class": Hulls.class_name_of(g.klass), "temper": str(Hulls.temper(g.temper)["name"]),
			"boss": g.boss, "hunter": not server.road._fight.is_empty()}
		_we_fled = false
		_ransom_taken = false
		_foe_hull = g.enemy_hull
		_foe_hit_at = server.tick
		rec["fights"]["total"] += 1
		if bool(_fight["hunter"]):
			rec["fights"]["hunters"] += 1
		var bc: Dictionary = rec["fights"]["by_class"]
		bc[_fight["class"]] = int(bc.get(_fight["class"], 0)) + 1
		if g.boss > 0:
			rec["flagship"]["met"] = true
			rec["flagship"]["growth_when_met"] = server.flagship.growth
	elif not g.fighting() and not _fight.is_empty():
		var how := "it went away"
		if server.won:
			how = "flagship beaten"
		elif server.over != Net.OVER_NONE:
			how = "we were lost"
		elif _ransom_taken:
			how = "ransom taken"
		elif _we_fled:
			how = "we jumped away"
		elif server.derelict.here and server.derelict.wreck:
			how = "wrecked or captured"
		elif g.fleeing() or not server.derelict.here:
			how = "it ran or left"
		var be: Dictionary = rec["fights"]["by_end"]
		be[how] = int(be.get(how, 0)) + 1
		rec["fights"]["seconds"] += (server.tick - int(_fight["start"])) / Net.TICK_HZ
		if int(_fight["boss"]) > 0:
			rec["flagship"]["result"] = how
		_fight = {}
	# the dead
	var aboard := 0
	for q in server.players:
		if q == null:
			continue
		if q.pirate and not q.corpse and q.cond != Net.COND_DEAD:
			aboard += 1
		if (q.corpse or q.cond == Net.COND_DEAD) and not _known_corpses.has(q.get_instance_id()):
			_known_corpses[q.get_instance_id()] = true
			if q.pirate:
				rec["pirates_killed"] += 1
			elif not q.ally and not q.corpse:   # (a body left behind on a respawn is not another death)
				rec["crew"]["deaths"] += 1
				if q.bot:
					rec["crew"]["bot_deaths"] += 1
				elif q == cap:
					rec["crew"]["captain_deaths"] += 1
		elif not q.corpse and q.cond != Net.COND_DEAD and _known_corpses.has(q.get_instance_id()):
			_known_corpses.erase(q.get_instance_id())        # (came back: the same Player is reused)
	rec["boarders_seen"] = maxi(int(rec["boarders_seen"]), aboard)
	# jumps
	if ship.sector != _last_sector or server.road.depth != _last_depth:
		if server.road.depth != _last_depth:
			rec["long_jumps"] += 1
			_last_depth = server.road.depth
			_cluster_since = server.tick
		_last_sector = ship.sector
		_leave_at = server.tick + roundi(_stay * randf_range(0.6, 1.4) * Net.TICK_HZ)
		_count_kind(server.navigation.sector_kind())
		timeline.append({"t": snappedf(server.voyage_ticks / float(Net.TICK_HZ) / 60.0, 0.1), "jump": server.jumps,
			"cluster": server.road.depth + 1, "kind": KIND_NAMES[server.navigation.sector_kind()],
			"credits": ship.credits, "hull": ship.hull, "fuel": _jumps_left(),
			"food": int(ship.store.get(Net.ITEM_FOOD, 0)), "reserve": server.reserve,
			"flagship_growth": server.flagship.growth})


func _count_kind(kind: int) -> void:
	var k: Dictionary = rec["sectors_by_kind"]
	k[KIND_NAMES[kind]] = int(k.get(KIND_NAMES[kind], 0)) + 1


func _finish(ticks: int) -> void:
	var ship = server.ship
	if not _fight.is_empty():
		var be: Dictionary = rec["fights"]["by_end"]
		var how := "flagship beaten" if server.won else ("we were lost" if server.over != Net.OVER_NONE else "still on")
		be[how] = int(be.get(how, 0)) + 1
		rec["fights"]["seconds"] += (server.tick - int(_fight["start"])) / Net.TICK_HZ
		if int(_fight["boss"]) > 0:
			rec["flagship"]["result"] = how
	rec["game_minutes"] = snappedf(ticks / float(Net.TICK_HZ) / 60.0, 0.1)
	rec["jumps"] = server.jumps
	rec["clusters_reached"] = server.road.depth + 1
	rec["systems_visited"] = server.been.size()
	rec["farthest"] = server.farthest
	rec["credits"]["end"] = ship.credits
	rec["hull"]["end"] = ship.hull
	rec["crew"]["reserve_end"] = server.reserve
	rec["flagship"]["growth_end"] = server.flagship.growth
	rec["timeline"] = timeline
	var name := "run-%02d" % int(rec["run"])
	var f := FileAccess.open(out_dir.path_join(name + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rec, "  "))
	f.close()
	var l := FileAccess.open(out_dir.path_join(name + ".log"), FileAccess.WRITE)
	l.store_string("\n".join(log_lines))
	l.close()
	print("run %d: %s after %.0f min, %d jumps, cluster %d, credits +%d -%d, %d fights, %d crew deaths" % [
		int(rec["run"]), rec["outcome"], float(rec["game_minutes"]), server.jumps, server.road.depth + 1,
		int(rec["credits"]["earned"]), int(rec["credits"]["spent"]), int(rec["fights"]["total"]), int(rec["crew"]["deaths"])])
