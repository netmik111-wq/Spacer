extends SceneTree
## Checks build v70 (people over bots), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/peopletest.gd
## A bot at a post gives half the help a person does; a newcomer takes a free
## job; the autodoc alone heals only out of danger and tended mends injuries;
## wounds bleed, bones break and splints set them, a concussion keeps a person
## from consoles; the pilot steers round meteors and ion surges; pirates downed
## are cuffed, held in the brig, slip their cuffs elsewhere, are sold and talk;
## boarders wreck, rob, plant bombs (which beep, burst or are disarmed) and drag
## our people off; the shotgun, the stun baton, the flashbang and the welder work.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Pirates := preload("res://src/server/pirates.gd")
const Stations := preload("res://src/server/stations.gd")
const Medbay := preload("res://src/server/medbay.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26620, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0
	server.systems.vents_on = false
	_halves()
	_jobs()
	_autodoc()
	_injuries()
	_concussion()
	_meteors()
	_storm()
	_prisoners()
	_goals()
	_bombs()
	_drag()
	_weapons()
	_welder()
	server.stop()
	server.free()
	print("peopletest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for t in ticks:
		server.ship.hull = server.ship.hull_max
		server._tick()


func _clear() -> void:
	## Nobody aboard but what a check puts there.
	for q in server.players:
		if q != null:
			server.crew.remove(q)
	server.pirates.bombs = {}
	server.combat.bangs = []
	for cell: int in server.air.holes.keys():
		server.air.set_hole(cell, false)
	server.ship.broken = {}
	_run(2)


func _place(p, cell: int, facing: int = Net.DIR_DOWN) -> void:
	p.st.place(cell % server.map.width, cell / server.map.width)
	p.st.dir = Net.DIR_NONE
	p.st.facing = facing


func _near_floor(cell: int) -> int:
	## A plain floor cell of our ship two to four steps from that one (no door).
	var map := server.map
	var w := map.width
	for r in range(2, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := cell % w + dx
				var y := cell / w + dy
				if absi(dx) + absi(dy) == r and map.walkable(x, y) and map.door_at(x, y) < 0 and map.on_ship(y * w + x) \
						and map.deck_of(y) == map.deck_of(cell / w) and map.climb[y * w + x] < 0 and map.stair_to[y * w + x] < 0:
					return y * w + x
	return cell


func _floor() -> int:
	var at: Vector2i = server.crew.spawn_point()
	return at.y * server.map.width + at.x


# a spawn tile with `n` floor cells of the same room to its right: a random spawn may sit by a
# wall, and a pirate put two cells on then stands in the next room (a shot or "in the room" fails)
func _floor_row(n: int) -> int:
	var map := server.map
	for s: Vector2i in map.spawns:
		var room := map.room_at(s.x, s.y)
		var fits := room >= 0
		for k in range(1, n + 1):
			if not fits:
				break
			fits = map.walkable(s.x + k, s.y) and map.room_at(s.x + k, s.y) == room
		if fits:
			return s.y * map.width + s.x
	return _floor()


# --------------------------------------------------------------- bots give half

func _halves() -> void:
	print("  -- a bot at a post gives half")
	_clear()
	var man := server.crew.new_player("Человек")
	var bot := server.crew.new_player("Бот")
	bot.bot = true
	_expect(Stations.share(man) == 1.0 and Stations.share(bot) == 0.5, "a person gives all of a post's help, a bot half")
	server.stations._at = {Net.POST_SHIELD: man}
	var by_man := server.stations.shield_pace()
	server.stations._at = {Net.POST_SHIELD: bot}
	var by_bot := server.stations.shield_pace()
	_expect(is_equal_approx(by_man, Stations.SHIELD_PACE) and is_equal_approx(by_bot, 1.0 + (Stations.SHIELD_PACE - 1.0) * 0.5),
		"the shield refills %.3f× with a person at it, %.3f× with a bot" % [by_man, by_bot])
	var keep: Array = server.mounts.gunners.duplicate()
	server.mounts.gunners[0] = man
	var gun_man := server.mounts.pace(0)
	server.mounts.gunners[0] = bot
	var gun_bot := server.mounts.pace(0)
	_expect(gun_bot > 1.0 and gun_bot - 1.0 < (gun_man - 1.0) * 0.51, "a gun charges quicker for a person (%.2f×) than a bot (%.2f×)" % [gun_man, gun_bot])
	server.mounts.gunners = keep
	server.stations._at = {}
	_clear()


# --------------------------------------------------------------- jobs

func _jobs() -> void:
	print("  -- a newcomer takes a free job")
	_clear()
	server.saved_crew = {}
	var a := server.crew.new_player("Первый")
	a.take_job(server.crew.free_job(Net.JOB_PILOT, a))
	_expect(a.job == Net.JOB_PILOT, "the first one gets the job asked for")
	var b := server.crew.new_player("Второй")
	b.take_job(server.crew.free_job(Net.JOB_PILOT, b))
	_expect(b.job != Net.JOB_PILOT and b.job != Net.JOB_CAPTAIN and b.job >= Net.JOB_CAPTAIN, "the second asking for it gets another free job (%s)" % Net.JOB_NAMES[b.job])
	_expect(server.crew.free_job(0, null) >= Net.JOB_CAPTAIN, "nobody is a sailor any more")
	_clear()


# --------------------------------------------------------------- the autodoc

func _autodoc() -> void:
	print("  -- the autodoc alone heals slowly past danger")
	_clear()
	var map := server.map
	var doc: int = map.autodoc.keys()[0]
	var bed: int = map.autodoc[doc]
	var hurt := server.crew.new_player("Раненый")
	_place(hurt, bed)
	hurt.health = 10.0
	hurt.wounds = 90.0
	hurt.leg = true
	hurt.st.slow = true
	_run(30 * Net.TICK_HZ)
	# (v82) past the cap it goes on alone at half its pace: 10 -> 50 in ~13 s, then ~1.5 a second
	_expect(hurt.health > Medbay.UNTENDED_CAP + 10.0 and hurt.health < Medbay.UNTENDED_CAP + 35.0, "untended it slows past %d health (%.1f)" % [int(Medbay.UNTENDED_CAP), hurt.health])
	_expect(hurt.leg, "and leaves the broken leg alone")
	var medic := server.crew.new_player("Медик")
	medic.take_job(Net.JOB_MEDIC)
	var spots: Array = server.stations._spots_for(doc).filter(func(s: Array) -> bool: return int(s[0]) != bed)
	_place(medic, int(spots[0][0]), int(spots[0][1]))
	var was := hurt.health
	for t in 4 * Net.TICK_HZ:
		server.medbay.tending(medic, doc)
		_run(1)
	_expect(hurt.health > was + 5.0, "tended, it heals on (%.1f → %.1f)" % [was, hurt.health])
	_expect(not hurt.leg and not hurt.st.slow, "and mends the broken leg")
	_clear()


# --------------------------------------------------------------- injuries

func _injuries() -> void:
	print("  -- bleeding, broken bones, splints")
	_clear()
	var a := server.crew.new_player("Подранок")
	_place(a, _floor())
	var bled := false
	for i in 60:
		a.health = 100.0
		a.wounds = 0.0
		server.combat.hurt(a, 5, null, server.combat.CAUSE_SHOT)
		if a.bleeding > 0:
			bled = true
			break
	_expect(bled, "a bullet wound may start bleeding")
	a.health = 100.0
	a.wounds = 0.0
	a.bleeding = roundi(30.0 * Net.TICK_HZ)
	_run(10 * Net.TICK_HZ)
	_expect(a.wounds > 3.0, "bleeding opens the wounds a little every second (%.1f)" % a.wounds)
	a.slots.fill(Net.ITEM_NONE)
	a.hand = 0
	a.slots[0] = Net.ITEM_MEDPATCH
	server.inventory.act(a)
	_expect(a.bleeding == 0, "a patch stops it")
	var broke := false
	for i in 200:
		a.health = 100.0
		a.wounds = 0.0
		server.combat.hurt(a, 30, null, server.combat.CAUSE_BLOW)
		if a.leg:
			broke = true
			break
	_expect(broke and a.st.slow, "a heavy blow may break a leg, and the leg slows its steps")
	a.health = 100.0
	a.wounds = 0.0
	a.concussed = 0
	a.slots[0] = Net.ITEM_SPLINT
	server.inventory.act(a)
	_expect(a.treating == a.slot, "Z with a splint sets one's own bone")
	_run(server.combat.SPLINT_TICKS + 5)
	_expect(not a.leg and not a.st.slow and a.slots[0] == Net.ITEM_NONE, "standing still, the leg is set and the splint used")
	_clear()


func _concussion() -> void:
	print("  -- a concussion keeps a person from consoles")
	_clear()
	var spot: Array = server.stations.spots[Net.POST_HELM][0]
	var p := server.crew.new_player("Контуженый")
	_place(p, int(spot[0]), int(spot[1]))
	_expect(server.systems.at_console(p, server.map.helm), "at the helm, the helm answers")
	p.concussed = server.tick + 100
	_expect(not server.systems.at_console(p, server.map.helm), "concussed, it does not")
	p.bot = true
	_expect(server.systems.at_console(p, server.map.helm), "(a bot keeps to its post)")
	_clear()


# --------------------------------------------------------------- the pilot outside fights

func _meteors() -> void:
	print("  -- steering round meteors")
	_clear()
	server.arena.enabled = false             # (v96: meteors flying in space are podtest's; this is the old lot)
	var spot: Array = server.stations.spots[Net.POST_HELM][0]
	var pilot := server.crew.new_player("Пилот")
	pilot.take_job(Net.JOB_PILOT)
	_place(pilot, int(spot[0]), int(spot[1]))
	server.power.set_charge(1000.0)
	_run(2)
	server.stations.meteor_roll = 0.0
	_expect(server.stations.meteor_seen(), "a meteor in a stream is seen coming")
	server.stations.evade_asked(pilot)
	_expect(server.stations.meteor_tried and server.stations.meteor_missed, "the pilot at the controls steers (space)")
	var holes := server.air.holes.size()
	_run(roundi(Stations.METEOR_WARN * Net.TICK_HZ) + 2)
	_expect(server.air.holes.size() == holes and server.stations.meteor_at == 0, "and the meteor goes by")
	server.crew.remove(pilot)
	_run(2)
	server.stations.meteor_seen()
	_run(roundi(Stations.METEOR_WARN * Net.TICK_HZ) + 2)
	_expect(server.air.holes.size() == holes + 1, "with nobody at the controls it holes the hull")
	var bot := server.crew.new_player("Бот-пилот")
	bot.bot = true
	bot.order = Net.POST_HELM
	_place(bot, int(spot[0]), int(spot[1]))
	_run(2)
	_expect(server.stations.at_post(Net.POST_HELM) == bot, "(the bot keeps the helm)")
	server.stations.meteor_roll = 0.29
	server.stations.meteor_seen()
	_run(roundi(Stations.METEOR_WARN * Net.TICK_HZ) + 2)
	_expect(server.stations.meteor_missed, "a bot at the controls steers by itself (30%: a lot of 0.29 misses)")
	server.stations.meteor_roll = 0.31
	server.stations.meteor_seen()
	_run(roundi(Stations.METEOR_WARN * Net.TICK_HZ) + 2)
	_expect(not server.stations.meteor_missed, "but only half as often as a person (a lot of 0.31 hits)")
	server.stations.meteor_roll = -1.0
	server.arena.enabled = true
	_clear()


func _storm() -> void:
	print("  -- steering clear of ion surges")
	_clear()
	var spot: Array = server.stations.spots[Net.POST_HELM][0]
	var pilot := server.crew.new_player("Пилот")
	_place(pilot, int(spot[0]), int(spot[1]))
	_run(2)
	server.hazards.steer_roll = 0.0
	var said := server.hazards.surge()
	_expect(said.contains("мимо") and server.ship.jammed.is_empty() or said.contains("уводит"), "a pilot at the controls steers the ship round a surge: «%s»" % said)
	server.hazards.steer_roll = 0.99
	said = server.hazards.surge()
	_expect(not said.contains("уводит"), "not every time: «%s»" % said)
	server.hazards.steer_roll = -1.0
	server.ship.jammed = {}
	_clear()


# --------------------------------------------------------------- prisoners

func _far_from(cell: int) -> int:
	## A floor cell in another room than `cell`'s.
	var map := server.map
	var room: int = map.room_of[cell]
	for c in map.walk.size():
		if map.walk[c] == 1 and map.door_of[c] < 0 and map.room_of[c] >= 0 and map.room_of[c] != room and map.on_ship(c):
			return c
	return -1


func _brig_cell() -> int:
	var map := server.map
	for c in map.access_in.size():
		if (map.access_in[c] & Net.ACCESS_ARMORY) != 0 and map.walkable(c % map.width, c / map.width) and map.door_of[c] < 0:
			return c
	return -1


func _prisoners() -> void:
	print("  -- prisoners")
	_clear()
	var guard := server.crew.new_player("Охранник")
	guard.take_job(Net.JOB_GUARD)
	var here := _floor_row(3)
	_place(guard, here, Net.DIR_RIGHT)
	var pirate = server.pirates.spawn(here % server.map.width + 1, here / server.map.width, true)
	pirate.goal = 0
	guard.slots.fill(Net.ITEM_NONE)
	guard.hand = 0
	guard.slots[0] = Net.ITEM_STUNNER
	server.combat.use_at(guard, server.tick, Vector2(pirate.st.x, pirate.st.y))
	_run(2)
	_expect(pirate.cond == Net.COND_CRIT, "a stun baton knocks a pirate down")
	guard.slots[0] = Net.ITEM_CUFFS
	guard.ready_tick = 0
	server.combat.use_at(guard, server.tick, Vector2(pirate.st.x, pirate.st.y))
	_expect(pirate.prisoner and server.pirates.aboard() == 0 and server.prisons.count() == 1, "handcuffs make him a prisoner: no longer a pirate aboard")
	_expect(pirate.slots.count(Net.ITEM_NONE) == Net.SLOTS, "what he fought with falls to the floor")
	var robot := server.crew.new_player("Робот")
	robot.ally = true
	_expect(not server.pirates.foe(robot, pirate), "nobody fights a prisoner, our robots neither")
	server.crew.remove(robot)
	_run(Net.TICK_HZ * 10)
	_expect(pirate.cond == Net.COND_CRIT, "he stays down, bound, long after the stun")
	server.prisons.talk(guard, pirate)
	_expect(pirate.talked, "searched, he talks")
	var brig := _brig_cell()
	_expect(brig >= 0, "the armory is the brig")
	_place(pirate, brig)
	pirate.loose_at = server.tick
	_run(Net.TICK_HZ * 2)
	_expect(pirate.prisoner, "in the brig he never slips his cuffs")
	var cells: Array = server.map.brig_cells()
	_expect(cells.size() == 4, "(v75) the ship has a brig of 4 cells (%d)" % cells.size())
	if not cells.is_empty():
		_place(pirate, int((cells[0] as PackedInt32Array)[0]))
		pirate.loose_at = server.tick
		_run(Net.TICK_HZ * 2)
		_expect(pirate.prisoner and server.prisons.in_brig(pirate), "(v75) nor in a brig cell")
	_place(pirate, here + 2)
	pirate.health = 20.0
	pirate.loose_at = server.tick
	_run(Net.TICK_HZ * 2)
	_expect(pirate.prisoner and not pirate.slots.has(Net.ITEM_BATON), "(v75, the author's note) badly hurt, he never gets loose")
	pirate.health = 100.0
	_place(guard, here + 3)
	pirate.loose_at = server.tick
	_run(Net.TICK_HZ * 2)
	_expect(pirate.prisoner, "(v75) nor while one of ours is in the room with him")
	_place(guard, _far_from(here))
	for q in server.players:
		if q != null and q != pirate and q != guard and not q.pirate and not q.corpse and server.map.room_at(q.st.x, q.st.y) == server.map.room_at(pirate.st.x, pirate.st.y):
			_place(q, _far_from(here))
	pirate.loose_at = server.tick
	_run(Net.TICK_HZ * 2)
	_expect(not pirate.prisoner and pirate.slots.has(Net.ITEM_BATON), "elsewhere, fit and unwatched, in time he gets loose and grabs a pipe")
	server.crew.remove(pirate)
	var second = server.pirates.spawn(here % server.map.width + 1, here / server.map.width, false)
	second.stun_until = server.tick + 100
	_run(2)
	server.combat.cuff(guard, second)
	var credits: int = server.ship.credits
	server.prisons.sell(guard)
	_expect(server.ship.credits == credits + Net.PRISONER_PAYS and server.prisons.count() == 0, "a station or a trader pays %d for him" % Net.PRISONER_PAYS)
	_clear()


# --------------------------------------------------------------- boarders' goals

func _alone_pirate(goal: int):
	var map := server.map
	var inside: Vector2i = server.pirates.cut_in()
	for cell: int in server.air.holes.keys():
		server.air.set_hole(cell, false)          # (the hole it cut does not matter here)
	var p = server.pirates.spawn(inside.x, inside.y, true)
	p.goal = goal
	p.goal_cell = -1
	return p


func _goals() -> void:
	print("  -- boarders come for something")
	_clear()
	server.pirates.goals_on = true
	var wrecker = _alone_pirate(Pirates.GOAL_WRECK)
	var broke := false
	for t in 120 * Net.TICK_HZ:
		_run(1)
		if not server.ship.broken.is_empty():
			broke = true
			break
	_expect(broke, "a wrecker goes to a machine and breaks it (%s)" % [server.map.device_name(server.ship.broken.keys()[0]) if broke else
		"nothing broke: it is at %d,%d, goal %d at %d, work %d" % [wrecker.st.x, wrecker.st.y, wrecker.goal, wrecker.goal_cell, wrecker.goal_work]])
	_expect(not server.ship.broken.keys().any(func(c: int) -> bool: return server.map.chart.has(c) or server.map.helm.has(c)), "never a bridge console")
	server.crew.remove(wrecker)
	_clear()
	server.ship.store[Net.ITEM_PATCH] = 10
	var stock := 0
	for k: int in server.ship.store:
		stock += int(server.ship.store[k])
	var robber = _alone_pirate(Pirates.GOAL_ROB)
	var left := false
	for t in 150 * Net.TICK_HZ:
		_run(1)
		if server.players[robber.slot] != robber:
			left = true
			break
	var after := 0
	for k: int in server.ship.store:
		after += int(server.ship.store[k])
	_expect(after == stock - Pirates.ROB_TAKES, "a robber takes %d things from the locker (%d → %d)" % [Pirates.ROB_TAKES, stock, after])
	_expect(left, "and leaves the way it came in (it is at %d,%d, goal %d, came in at %d,%d)" % [robber.st.x, robber.st.y, robber.goal,
		robber.way_in % server.map.width, robber.way_in / server.map.width])
	_clear()
	var parties := 0
	for i in 40:
		server.pirates._party_tick = -1000
		var a = server.pirates.spawn(5, 5, true)
		server.pirates.give_goal(a)
		if a.goal != Pirates.GOAL_NONE:
			parties += 1
		server.crew.remove(a)
	_expect(parties > 8 and parties < 32, "about half come with a goal (%d of 40)" % parties)


func _bombs() -> void:
	print("  -- a bomb")
	_clear()
	var cell := _floor()
	var near := server.crew.new_player("Рядом")
	_place(near, cell + 1)
	server.floor_things.erase(cell)         # (things left there by the checks before, by lot, one run in 10)
	server.pirates.plant(cell)
	_expect(server.pirates.bombs.has(cell) and (server.floor_things[cell] as PackedByteArray).has(Net.ITEM_BOMB), "a planted bomb lies on the floor")
	near.slots.fill(Net.ITEM_NONE)
	near.st.facing = Net.DIR_LEFT
	_expect(not server.inventory.pick_up(near), "it cannot be picked up")
	var health := near.health
	_run(roundi(Pirates.BOMB_SECONDS * Net.TICK_HZ) + 2)
	_expect(server.pirates.bombs.is_empty() and not server.floor_things.has(cell), "in %d s it goes off" % int(Pirates.BOMB_SECONDS))
	_expect(near.health < health - 10.0, "and wounds who stands by it (%.0f → %.0f)" % [health, near.health])
	_clear()
	var eng := server.crew.new_player("Инженер")
	eng.take_job(Net.JOB_ENGINEER)
	_place(eng, cell + 1, Net.DIR_LEFT)
	server.pirates.plant(cell)
	eng.using = true
	_run(server.pirates.defuse_ticks(eng) + 2)
	_expect(server.pirates.bombs.is_empty() and server.air.holes.is_empty(), "held E disarms it, an engineer in %.1f s" % (server.pirates.defuse_ticks(eng) / float(Net.TICK_HZ)))
	_clear()


func _drag() -> void:
	print("  -- dragged off")
	_clear()
	var victim := server.crew.new_player("Жертва")
	var p = _alone_pirate(Pirates.GOAL_DRAG)
	_place(victim, _near_floor(p.way_in))
	victim.health = -10.0
	victim.cond = Net.COND_CRIT
	victim.st.down = true
	var gone := false
	for t in 60 * Net.TICK_HZ:
		_run(1)
		if victim.taken:
			gone = true
			break
	_expect(gone and victim.cond == Net.COND_DEAD, "a kidnapper hauls one of ours lying to its hole and off he goes")
	_expect(server.players[p.slot] != p, "and the pirate with him")
	var bodies := server.corpses.size()
	server.crew.respawn(victim)
	_expect(server.corpses.size() == bodies and victim.cond == Net.COND_OK and not victim.taken, "no body is left behind: he comes back from the reserve")
	_clear()


# --------------------------------------------------------------- weapons

func _weapons() -> void:
	print("  -- the shotgun and the flashbang")
	_clear()
	var map := server.map
	var here := _floor_row(3)
	var shooter := server.crew.new_player("Стрелок")
	_place(shooter, here, Net.DIR_RIGHT)
	var target = server.pirates.spawn(here % map.width + 2, here / map.width, true)
	target.goal = 0
	shooter.slots.fill(Net.ITEM_NONE)
	shooter.hand = 0
	shooter.slots[0] = Net.ITEM_SHOTGUN + Net.SHOTGUN_ROUNDS
	var health: float = target.health
	server.combat.use_at(shooter, server.tick, Vector2(target.st.x, target.st.y))
	_expect(target.health < health - Items.PELLET_DAMAGE * 2 + 0.5, "a shotgun blast at two cells hits with several pellets (%.0f → %.0f)" % [health, target.health])
	_expect(shooter.slots[0] == Net.ITEM_SHOTGUN + Net.SHOTGUN_ROUNDS - 1, "and spends one shell")
	server.crew.remove(target)
	_run(2)
	var dazed = server.pirates.spawn(here % map.width + 3, here / map.width, true)
	dazed.goal = 0
	dazed.st.facing = Net.DIR_LEFT
	shooter.slots[0] = Net.ITEM_FLASHBANG
	shooter.ready_tick = 0
	server.combat.use_at(shooter, server.tick, Vector2(dazed.st.x, dazed.st.y))
	_expect(shooter.slots[0] == Net.ITEM_NONE and server.combat.bangs.size() == 1, "a flashbang is thrown")
	_run(server.combat.FLASH_FUSE + 3)
	_expect(dazed.cond == Net.COND_CRIT, "and knocks down who sees it burst")
	_clear()


func _welder() -> void:
	print("  -- the welder")
	_clear()
	var map := server.map
	var door := -1
	var stand := -1
	var face := Net.DIR_RIGHT
	for c in map.width * map.height:
		var d: int = map.door_of[c]
		if d < 0 or d >= map.other_first_door or map.door_access[d] != 0 or server.doors.partner[d] >= 0:
			continue
		var x := c % map.width
		var y := c / map.width
		for f in range(1, 5):
			var sx: int = x - Net.DX[f]
			var sy: int = y - Net.DY[f]
			if map.walkable(sx, sy) and map.door_at(sx, sy) < 0 and map.on_ship(sy * map.width + sx) and map.use_ahead(sx, sy, f) == c:
				door = d
				stand = sy * map.width + sx
				face = f
				break
		if door >= 0:
			break
	_expect(door >= 0, "a plain door to weld")
	var p := server.crew.new_player("Сварщик")
	_place(p, stand, face)
	p.slots.fill(Net.ITEM_NONE)
	p.hand = 0
	p.slots[0] = Net.ITEM_WELDER
	_expect(server.doors.is_shut(door) and server.repairs.usable_ahead(p), "a shut door with a welder in hand")
	p.using = true
	_run(server.repairs.WELD_TICKS + 2)
	p.using = false
	_run(1)
	_expect(server.doors.welded[door] == 1, "held E welds it shut")
	_expect(server.doors.blocks(door, Net.ACCESS_OURS | Net.ACCESS_ALL), "and it opens for nobody, ours neither")
	p.slots[0] = Net.ITEM_NONE
	p.st.dir = face
	_run(10)
	_expect(p.st.y * map.width + p.st.x == stand, "walking into it gets nowhere")
	p.st.dir = Net.DIR_NONE
	p.slots[0] = Net.ITEM_WELDER
	p.using = true
	_run(server.repairs.WELD_TICKS + 2)
	p.using = false
	_expect(server.doors.welded[door] == 0, "held E again cuts the weld")
	_clear()


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		failed += 1
		print("FAIL ", what)
