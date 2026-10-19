extends SceneTree
## Checks the crew at work (v60), on a real server stepped by hand:
##   godot --headless --path . --script res://tools/worktest.gd
## A gunner at a mount charges its gun faster; guns are carried from the locker
## and put up on their mounts by hand, the gun console only orders it, and a bot
## on "work" carries an order out by itself; bots turn their suit's supply on in
## thin air, fill an empty tank at an oxygen station and lie down in an autodoc
## when badly hurt; the autodoc heals (quicker tended), the scanner reports;
## the holomap locks doors that pirates then cut through; the workbench makes
## shells and rockets; point defence shoots at slow shells; skills grow by
## doing; a joining player takes a bot's place and a bot takes a leaver's.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Stations := preload("res://src/server/stations.gd")
const Mounts := preload("res://src/server/mounts.gd")
const Medbay := preload("res://src/server/medbay.gd")
const Blast := preload("res://src/server/blast.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer
var kept: Array = []                    # (characters _run keeps whole)


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26350, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false
	server.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	_expect(server.map.autodoc.size() == 2 and server.map.scanner.size() == 1, "the medbay has two autodocs and a body scanner")
	_gunners()
	_carrying()
	_bots_haul()
	_bots_breathe()
	_medbay()
	_blast()
	_ammo()
	_skills()
	_crew_size()
	print("worktest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _bots() -> Array:
	var out: Array = []
	for p in server.players:
		if p != null and p.bot and not p.corpse:
			out.append(p)
	return out


func _face(p, target: int) -> void:
	## Puts a character where it can work on that cell, facing it.
	var s: Array = server.stations._spots_for(target)[0]
	var w := server.map.width
	p.st.place(int(s[0]) % w, int(s[0]) / w)
	p.st.facing = int(s[1])
	p.st.dir = Net.DIR_NONE


func _hold(p, item: int) -> void:
	## Puts a thing into the character's hand.
	var at: int = p.slots.find(Net.ITEM_NONE)
	if at < 0:
		at = 0
	p.slots[at] = item
	p.hand = at


func _gunners() -> void:
	print("  -- gunners at the mounts")
	var m: Mounts = server.mounts
	var p := server.crew.new_player("Канонир")
	p.take_job(Net.JOB_GUARD)
	kept = [p]
	_run(2)
	_expect(m.gunner(0) == null and is_equal_approx(m.pace(0), 1.0), "a gun with nobody at it charges as before")
	_face(p, server.map.guns[0])
	_run(2)
	_expect(m.gunner(0) == p, "somebody facing a mount is its gunner")
	var want := 1.0 + Mounts.MOUNT_PACE + Mounts.MOUNT_SKILL_PACE * p.skill(Net.SKILL_GUNS)
	_expect(is_equal_approx(m.pace(0), want), "a guard (gunnery by job) makes it charge %d%% faster" % roundi((want - 1.0) * 100))
	var before: int = p.skills[Net.SKILL_GUNS]
	m.fired(0)
	_expect(p.skills[Net.SKILL_GUNS] > before, "and learns gunnery with every shot it fires")
	server.crew.remove(p)
	kept = []


func _carrying() -> void:
	print("  -- guns are carried")
	var m: Mounts = server.mounts
	var ship = server.ship
	var g: Gunnery = server.gunnery
	var p := server.crew.new_player("Матрос")
	p.take_job(Net.JOB_CREWMAN)
	kept = [p]
	var heavy := Weapons.item_of(Weapons.HEAVY)
	ship.store[heavy] = 1
	# the console orders
	_to_console(p)
	g.setup_asked(p, Net.GUNSET_MOUNT, 1, heavy)
	_expect(ship.mounts[1] != Weapons.HEAVY and m.wanted[1] == heavy, "the gun console orders a gun onto a mount, it does not put it up")
	_expect(m.order_for(heavy) == 1, "(the order waits at mount 2)")
	# by hand
	server.supplies.store_asked(_at_locker(p), Net.STORE_TAKE, heavy)
	_expect(p.count(heavy) == 1 and int(ship.store[heavy]) == 0, "a ship gun is taken from the locker into the hands")
	p.hand = p.slots.find(heavy)
	var old: int = ship.mounts[1]
	_face(p, server.map.guns[1])
	_expect(m.can(p, server.map.guns[1]) == "", "with it in hand at the mount, the work can start")
	p.using = true
	_run(m.ticks(p) - 5)
	_expect(ship.mounts[1] == old, "it takes a while (%.1f s)" % (m.ticks(p) / float(Net.TICK_HZ)))
	_run(10)
	p.using = false
	_expect(ship.mounts[1] == Weapons.HEAVY and ship.armed[1] == 0, "then the heavy laser is up, unpowered")
	_expect(p.in_hand() == Weapons.item_of(old), "and the gun that was there is in the hands")
	_expect(m.wanted[1] == Mounts.WANT_NONE, "the order is done")
	server.supplies.store_asked(_at_locker(p), Net.STORE_PUT_ONE, p.hand)
	_expect(int(ship.store.get(Weapons.item_of(old), 0)) >= 1 and p.in_hand() == Net.ITEM_NONE, "carried back, it goes into the locker")
	# with empty hands the gun comes down
	_face(p, server.map.guns[1])
	p.using = true
	_run(m.ticks(p) + 3)
	p.using = false
	_expect(ship.mounts[1] == Weapons.NONE and p.in_hand() == heavy, "with empty hands the gun on a mount comes down into them")
	_face(p, server.map.guns[1])
	p.using = true
	_run(m.ticks(p) + 3)
	p.using = false
	_expect(ship.mounts[1] == Weapons.HEAVY, "(and back up)")
	# a damaged gun and the point defence do not go up by hand
	_hold(p, Weapons.item_of(Weapons.GUARD))
	_expect(m.can(p, server.map.guns[0]) not in ["", Mounts.NOT_HERE], "the point defence is not put on a hull mount")
	p.slots[p.hand] = Net.ITEM_NONE
	server.crew.remove(p)
	kept = []


func _bots_haul() -> void:
	print("  -- bots carry out the console's orders")
	var m: Mounts = server.mounts
	var ship = server.ship
	var st: Stations = server.stations
	ship.broken.clear()
	var siege := Weapons.item_of(Weapons.SIEGE)
	ship.store[siege] = 1
	var cap := server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	kept = [cap]
	for b in _bots():
		st.order_asked(cap, b.slot, Net.POST_REPAIR)
	var old: int = ship.mounts[2]
	m.order(cap, 2, siege)
	_expect(m.wanted[2] == siege, "an order: the siege laser onto gun 3")
	var carried := false
	var ticks := 0
	while ticks < 180 * Net.TICK_HZ and ship.mounts[2] != Weapons.SIEGE:
		_run(Net.TICK_HZ)
		ticks += Net.TICK_HZ
		for b in _bots():
			if b.slots.has(siege):
				carried = true
	_expect(carried, "a bot on \"work\" fetches it from the locker")
	_expect(ship.mounts[2] == Weapons.SIEGE, "and puts it up (%d s)" % (ticks / Net.TICK_HZ))
	var back := 0
	while back < 120 and old != Weapons.NONE and int(ship.store.get(Weapons.item_of(old), 0)) == 0:
		_run(Net.TICK_HZ)
		back += 1
	_expect(old == Weapons.NONE or int(ship.store.get(Weapons.item_of(old), 0)) >= 1, "the gun it took down goes back into the locker")
	m.order(cap, 2, Net.ITEM_NONE)
	_expect(m.wanted[2] == Mounts.WANT_DOWN, "an order to take a gun down")
	ticks = 0
	while ticks < 180 and ship.mounts[2] != Weapons.NONE:
		_run(Net.TICK_HZ)
		ticks += 1
	_expect(ship.mounts[2] == Weapons.NONE, "is carried out too")
	ticks = 0
	while ticks < 120 and int(ship.store.get(siege, 0)) == 0:
		_run(Net.TICK_HZ)
		ticks += 1
	_expect(int(ship.store.get(siege, 0)) == 1, "and the gun goes into the locker")
	ship.mounts[2] = old if old != Weapons.NONE else Weapons.LASER
	# a bot without a suit fetches one
	var b: Object = _bots()[0]
	var full_suit := Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	ship.store[full_suit] = maxi(int(ship.store.get(full_suit, 0)), 1)
	b.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	ticks = 0
	while ticks < 120 and not b.has_suit():
		_run(Net.TICK_HZ)
		ticks += 1
	_expect(b.has_suit(), "a bot with no suit fetches one from the locker (%d s)" % ticks)
	server.crew.remove(cap)
	kept = []


func _bots_breathe() -> void:
	print("  -- bots and the air")
	var st: Stations = server.stations
	var b: Object = _bots()[0]
	b.health = 100.0
	var cell: int = b.st.y * server.map.width + b.st.x
	var was: float = server.air.air[cell]
	server.air.air[cell] = 0.1
	st.bot_breathe(b)
	_expect(b.supply, "a bot in thin air turns its suit's supply on")
	server.air.air[cell] = was
	st.bot_breathe(b)
	_expect(not b.supply, "and off again in good air")
	b.tank = 0.1
	b.order = Net.POST_REPAIR
	var ticks := 0
	while ticks < 90 and b.tank < Stations.TANK_FULL - 0.05:
		_run(Net.TICK_HZ)
		ticks += 1
	_expect(b.tank >= Stations.TANK_FULL - 0.05, "a bot low on oxygen fills its tank at an oxygen station (%d s)" % ticks)


func _medbay() -> void:
	print("  -- the medbay")
	var md: Medbay = server.medbay
	var map := server.map
	var docs: Array = map.autodoc.keys()
	docs.sort()
	var doc: int = docs[0]
	var bed: int = map.autodoc[doc]
	var w := map.width
	var hurt := server.crew.new_player("Раненый")
	hurt.st.place(bed % w, bed / w)
	hurt.health = 40.0
	hurt.wounds = 60.0
	_expect(md.in_bed(doc) == hurt, "somebody on the bed is in the autodoc")
	_run(5 * Net.TICK_HZ)
	_expect(hurt.wounds < 60.0, "its wounds close (%.0f left after 5 s)" % hurt.wounds)
	var w1: float = hurt.wounds
	var medic := server.crew.new_player("Медик")
	medic.take_job(Net.JOB_MEDIC)
	_face(medic, doc)
	medic.using = true
	var lessons: int = medic.skills[Net.SKILL_MEDICINE]
	_run(5 * Net.TICK_HZ + 2)
	medic.using = false
	_expect(w1 - hurt.wounds > (60.0 - w1) * 1.5, "tended, twice as quick")
	_expect(medic.skills[Net.SKILL_MEDICINE] > lessons, "and the medic learns from it")
	_expect(Medbay.report(hurt).contains("Раненый") and Medbay.report(hurt).contains("Раны"), "the scanner reports health and wounds")
	var sc: int = map.scanner.keys()[0]
	_face(medic, sc)
	server.repairs.press(medic)
	_expect(true, "(pressing \"use\" at the scanner)")
	var dead := server.crew.new_player("Мёртвый")
	server.crew.remove(hurt)
	dead.st.place(bed % w, bed / w)
	dead.cond = Net.COND_DEAD
	dead.health = Net.HEALTH_DEAD
	_run(2 * Net.TICK_HZ)
	_expect(dead.cond == Net.COND_DEAD, "the dead are not brought back")
	server.crew.remove(dead)
	server.crew.remove(medic)
	# a badly hurt bot walks to an autodoc by itself
	var b: Object = _bots()[1]
	b.order = Net.POST_FREE
	b.health = 30.0
	b.wounds = 0.0
	var ticks := 0
	var lay := false
	while ticks < 180 and b.health < Medbay.BOT_LEAVES_AT:
		_run(Net.TICK_HZ)
		ticks += 1
		for d: int in docs:
			if md.in_bed(d) == b:
				lay = true
	_expect(lay and b.health >= Medbay.BOT_LEAVES_AT, "a badly hurt bot lies down in an autodoc and is healed (%d s)" % ticks)


func _blast() -> void:
	print("  -- blast doors")
	var map := server.map
	var doors := server.doors
	var bl: Blast = server.blast
	var p := server.crew.new_player("Вахтенный")
	kept = [p]
	var holo: int = map.holo.keys()[0]
	_face(p, holo)
	# a door between two rooms, with floor on both sides
	var d := -1
	for k in map.other_first_door:
		if map.door_kind[k] == map.DOOR_BAND and map.door_sides[2 * k] >= 0 and map.door_sides[2 * k + 1] >= 0 and map.door_access[k] == 0:
			d = k
			break
	_expect(d >= 0, "(a door to lock)")
	bl.asked(p, d)
	_expect(doors.blast[d] == 1, "somebody at a holomap locks a door")
	_expect(doors.blocks(d, 0) and not doors.blocks(d, Net.access_of(Net.JOB_CREWMAN)),
		"it stays shut for pirates, opens for our own")
	bl.asked(p, d)
	_expect(doors.blast[d] == 0, "the same door again unlocks it")
	bl.asked(p, Net.BLAST_ALL)
	_expect(bl.locked_count() == map.other_first_door, "or every door at once")
	bl.asked(p, Net.BLAST_NONE)
	_expect(bl.locked_count() == 0, "and every one unlocked")
	var stranger := server.crew.new_player("Мимо")
	bl.asked(stranger, d)
	_expect(doors.blast[d] == 0, "only from a holomap")
	server.crew.remove(stranger)
	bl.asked(p, d)
	# a pirate cuts through
	var side: int = map.door_sides[2 * d]
	var w := map.width
	var pirate = server.pirates.spawn(side % w, side / w, false)
	var dir := -1
	for f in range(1, 5):
		if map.door_at(side % w + Net.DX[f], side / w + Net.DY[f]) == d:
			dir = f
	var ticks := 0
	while ticks < roundi((Blast.CUT_SECONDS - 1.0) * Net.TICK_HZ):
		pirate.st.place(side % w, side / w)
		pirate.st.dir = dir
		bl.tick()
		ticks += 1
	_expect(doors.blast[d] == 1 and doors.jammed[d] == 0, "a pirate walking into it is held for a while")
	for t in 2 * Net.TICK_HZ:
		pirate.st.place(side % w, side / w)
		pirate.st.dir = dir
		bl.tick()
	_expect(doors.blast[d] == 0 and doors.jammed[d] == 1, "then cuts through: the door is wrecked open")
	server.crew.remove(pirate)
	doors.jammed[d] = 0
	kept = []
	server.crew.remove(p)


func _ammo() -> void:
	print("  -- shells and rockets at the workbench")
	var map := server.map
	var ship = server.ship
	var p := server.crew.new_player("Механик")
	p.take_job(Net.JOB_ENGINEER)
	kept = [p]
	_face(p, map.bench.keys()[0])
	ship.store[Net.ITEM_PART] = 2
	var shells: int = int(ship.store.get(Net.ITEM_SHELL, 0))
	var rockets: int = int(ship.store.get(Net.ITEM_ROCKET, 0))
	server.workshop.asked(p, Net.BENCH_SHELLS, 0)
	_run(server.workshop.AMMO_TICKS + 2)
	_expect(int(ship.store[Net.ITEM_SHELL]) == shells + 3 and int(ship.store[Net.ITEM_PART]) == 1, "a spare part makes three shells")
	server.workshop.asked(p, Net.BENCH_ROCKETS, 0)
	_run(server.workshop.AMMO_TICKS + 2)
	_expect(int(ship.store[Net.ITEM_ROCKET]) == rockets + 2 and int(ship.store[Net.ITEM_PART]) == 0, "or two rockets")
	server.workshop.asked(p, Net.BENCH_SHELLS, 0)
	_expect(p.bench.is_empty(), "nothing without a part")
	server.crew.remove(p)
	kept = []
	print("  -- point defence")
	_expect(is_equal_approx(Weapons.guard_chance(Weapons.AUTOCANNON), Weapons.GUARD_SHELL_HIT)
		and is_equal_approx(Weapons.guard_chance(Weapons.HAMMER), Weapons.GUARD_SHELL_HIT), "point defence shoots at slow shells")
	_expect(Weapons.guard_chance(Weapons.RAILGUN) == 0.0 and Weapons.guard_chance(Weapons.LASER) == 0.0, "not at a railgun's slug or a laser")
	_expect(is_equal_approx(Weapons.guard_chance(Weapons.ROCKET), Weapons.GUARD_HIT), "and at rockets as before")


func _skills() -> void:
	print("  -- skills")
	var p := server.crew.new_player("Новичок")
	p.take_job(Net.JOB_CREWMAN)
	_expect(p.skills.size() == Net.SKILLS and Net.SKILLS == 4, "four skills, piloting among them")
	var pilot := server.crew.new_player("Пилот")
	pilot.take_job(Net.JOB_PILOT)
	_expect(pilot.skills[Net.SKILL_PILOT] == Net.JOB_START_SKILL, "a pilot by job starts at half")
	var before: int = pilot.skills[Net.SKILL_PILOT]
	pilot.train(Net.SKILL_PILOT)
	_expect(pilot.skills[Net.SKILL_PILOT] > before, "and gets better by doing")
	server.crew.remove(p)
	server.crew.remove(pilot)


func _crew_size() -> void:
	print("  -- bots stand in for players")
	var n := _bots().size()
	_expect(server.crew_size == 3, "two bots asked for: the crew is kept three strong")
	var a := server.crew.new_player("Первый")
	server.crew._bot_makes_way(a)
	_expect(_bots().size() == n, "the host joining takes no bot's place")
	var b := server.crew.new_player("Второй")
	server.crew._bot_makes_way(b)
	_expect(_bots().size() == n - 1, "a second player takes a bot's place")
	server.crew.remove(b)
	server.crew._bot_takes_over(b.name)
	_expect(_bots().size() == n, "a bot takes the place of one who leaves")
	server.crew.remove(a)
	server.crew._bot_takes_over(a.name)
	_expect(_bots().size() == n + 1, "(the crew stays full)")


func _at_locker(p):
	_face(p, server.map.locker.keys()[0])
	return p


func _to_console(p) -> void:
	_face(p, server.map.gun_console.keys()[0])


func _run(ticks: int) -> void:
	for t in ticks:
		for k in kept:
			k.health = 100.0
			k.wounds = 0.0
			k.tank = 1.0
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
