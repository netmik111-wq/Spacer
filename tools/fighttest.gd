extends SceneTree
## Checks weapons and pirates on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/fighttest.gd
## A pistol hits the first one in its line, not through walls, judged where
## the shooter saw them; it runs dry and takes a magazine. A baton reaches only
## the next cell. A patch closes wounds. Pirates board through the hull, hunt
## and hurt the crew, and leave bodies with their weapons.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Director := preload("res://src/server/director.gd")
const Items := preload("res://src/shared/items.gd")
const Net := preload("res://src/shared/net.gd")
const Armour := preload("res://src/shared/armour.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26250, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map

	print("a pistol")
	var a = _crew("Стрелок", 8, 4)
	var b = _crew("Мишень", 12, 4)
	a.slots[0] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
	a.hand = 0
	_run(3)
	server.combat.use_at(a, server.tick, Vector2(12, 4))
	_expect(is_equal_approx(b.health, 100.0 - Items.PISTOL_DAMAGE * Armour.taken(b.worn, b.deflated, Armour.KINETIC)) and a.slots[0] == Net.ITEM_PISTOL + Net.PISTOL_ROUNDS - 1,
		"a shot hits the one aimed at (%d left in the pistol)" % (a.slots[0] - Net.ITEM_PISTOL))
	server.combat.use_at(a, server.tick, Vector2(12, 4))
	_expect(a.slots[0] == Net.ITEM_PISTOL + Net.PISTOL_ROUNDS - 1, "a pistol does not fire again at once")
	_run(GameServer.Combat.SHOT_TICKS)
	b.health = 100.0
	var c = _crew("Заслон", 10, 4)
	server.combat.use_at(a, server.tick, Vector2(12, 4))
	_expect(c.health < 100.0 and b.health == 100.0, "it hits the first one in the way")
	c.st.place(3, 7)
	c.health = 100.0
	_run(GameServer.Combat.SHOT_TICKS)
	b.st.place(8, 1)
	server.combat.use_at(a, server.tick, Vector2(8, 1))
	_expect(b.health == 100.0, "not through a wall")
	_run(GameServer.Combat.SHOT_TICKS)
	# judged where the shooter saw the target: it has walked on since
	b.st.place(12, 4)
	_run(2)
	var seen := server.tick
	b.st.dir = Net.DIR_RIGHT
	_run(10)
	b.st.dir = Net.DIR_NONE
	_expect(b.st.x > 12, "(the target walked on to %d,4)" % b.st.x)
	server.combat.use_at(a, seen, Vector2(12, 4))
	_expect(b.health < 100.0, "a shot counts where the shooter saw the target on its screen")
	a.slots[0] = Net.ITEM_PISTOL
	a.slots[1] = Net.ITEM_MAG
	_run(GameServer.Combat.SHOT_TICKS)
	server.combat.use_at(a, server.tick, Vector2(12, 4))
	_expect(a.slots[0] == Net.ITEM_PISTOL + Net.PISTOL_ROUNDS and a.slots[1] == Net.ITEM_NONE, "an empty pistol takes the magazine")
	var reloaded_at := server.tick
	server.combat.use_at(a, server.tick, Vector2(14, 4))
	_expect(a.slots[0] == Net.ITEM_PISTOL + Net.PISTOL_ROUNDS and server.tick == reloaded_at, "and reloading takes a moment")

	print("a baton and a patch")
	a.slots[0] = Net.ITEM_BATON
	b.st.place(9, 4)
	b.health = 100.0
	_run(GameServer.Combat.RELOAD_TICKS)
	server.combat.use_at(a, server.tick, Vector2(9, 4))
	_expect(is_equal_approx(b.health, 100.0 - 15 * Armour.taken(b.worn, b.deflated, Armour.BLOW)), "a baton hurts the one next to us")
	b.health = 100.0
	_run(GameServer.Combat.BLOW_TICKS)
	server.combat.use_at(a, server.tick, Vector2(8.6, 3.7))
	_expect(is_equal_approx(b.health, 100.0 - 15 * Armour.taken(b.worn, b.deflated, Armour.BLOW)), "even when the click is not right on them")
	b.st.place(11, 4)
	b.health = 100.0
	_run(GameServer.Combat.BLOW_TICKS)
	server.combat.use_at(a, server.tick, Vector2(11, 4))
	_expect(b.health == 100.0, "and nobody further off")
	a.slots[0] = Net.ITEM_MEDPATCH
	a.health = 30.0
	a.wounds = 70.0
	_run(GameServer.Combat.BLOW_TICKS)
	server.combat.use_at(a, server.tick, Vector2(8, 4))
	_expect(a.health >= 70.0 and a.slots[0] == Net.ITEM_NONE, "a patch on oneself closes wounds and is used up")
	a.slots[0] = Net.ITEM_MEDPATCH
	b.st.place(9, 4)
	b.health = 20.0
	b.wounds = 80.0
	server.combat.use_at(a, server.tick, Vector2(9, 4))
	_expect(b.health >= 60.0, "or on the one next to us")
	a.slots[0] = Net.ITEM_MEDPATCH
	b.health = 100.0
	b.wounds = 0.0
	_run(GameServer.Combat.BLOW_TICKS)
	server.combat.use_at(a, server.tick, Vector2(9, 4))
	_expect(a.slots[0] == Net.ITEM_MEDPATCH, "but is not wasted on one with no wounds")

	print("wounds and healing")
	a.st.place(8, 4)
	b.st.place(9, 4)
	b.health = 100.0
	b.wounds = 0.0
	server.combat.hurt(b, 50, a)
	_run(10 * Net.TICK_HZ)
	_expect(b.health <= 50.5 and b.wounds == 50.0, "wounds do not close by themselves (health %d)" % int(b.health))
	b.health = 30.0
	_run(5 * Net.TICK_HZ)
	_expect(b.health >= 34.0 and b.health <= 50.0, "but what thin air took comes back, up to what the wounds allow")
	a.slots[0] = Net.ITEM_MEDKIT + Net.MEDKIT_USES
	a.hand = 0
	server.combat.use_at(a, server.tick, Vector2(9, 4))
	_run(GameServer.Combat.TREAT_TICKS / 2)
	_expect(b.wounds == 50.0, "a first-aid kit takes its time")
	_run(GameServer.Combat.TREAT_TICKS / 2 + 2)
	_expect(b.wounds == 50.0 - Items.MEDKIT_HEAL and a.slots[0] == Net.ITEM_MEDKIT + Net.MEDKIT_USES - 1,
		"and closes %d of the wounds per use (%d uses left)" % [Items.MEDKIT_HEAL, a.slots[0] - Net.ITEM_MEDKIT])
	_run(GameServer.Combat.TREAT_TICKS / 2)
	b.st.place(12, 4)
	_run(GameServer.Combat.TREAT_TICKS)
	_expect(b.wounds == 50.0 - Items.MEDKIT_HEAL, "the treatment stops when the patient walks off")
	b.st.place(9, 4)
	b.health = -30.0
	b.wounds = 130.0
	b.cond = Net.COND_CRIT
	b.st.down = true
	_run(5 * Net.TICK_HZ)
	_expect(b.cond == Net.COND_CRIT and b.health <= -29.0, "badly wounded, one lying unconscious does not come round")
	for i in 5:
		server.combat.use_at(a, server.tick, Vector2(9, 4))
		_run(GameServer.Combat.TREAT_TICKS + 2)
	_run(2 * Net.TICK_HZ)
	_expect(b.cond == Net.COND_OK, "treated, they come round (health %d)" % int(b.health))
	_expect(a.slots[0] == Net.ITEM_NONE or Items.uses(a.slots[0]) > 0, "a used-up kit is gone")

	print("pirates")
	b.st.place(2, 7)
	var holes := server.air.holes.size()
	_expect(server.director.fire(Director.BOARDING) and server.pirates.aboard() > 0 and server.air.holes.size() == holes + 1,
		"a boarding party cuts in through the hull (%d pirates)" % server.pirates.aboard())
	var w: int = server.director._weight(Director.EVENTS[Director.EVENTS.size() - 1], Sectors.EMPTY)
	_expect(w == 0, "and no second party comes while one is aboard")
	_expect(_roster_kind(_first_pirate()) == Net.KIND_PIRATE, "everyone is told they are pirates")
	for q in server.players:
		if q != null and q.pirate:
			server.crew.remove(q)
	server.systems.seal_all()
	server.air.refill()
	# a gunner and one of the crew in the same corridor
	a.st.place(2, 23)
	b.st.place(3, 23)
	var victim = _crew("Жертва", 12, 4)
	victim.st.facing = Net.DIR_RIGHT
	var pirate = server.pirates.spawn(5, 4, true)
	pirate.st.facing = Net.DIR_RIGHT
	for t in 200:
		server._tick()
		victim.health = maxf(victim.health, 1.0)        # kept on its feet so the pirate keeps at it
	_expect(victim.health < 100.0, "a pirate shoots the crew it sees (health %d)" % int(victim.health))
	_expect(Items.rounds(pirate.in_hand()) < Net.PISTOL_ROUNDS or not pirate.slots.has(Net.ITEM_MAG), "and uses up rounds doing it")
	var brawler = server.pirates.spawn(2, 4, false)
	victim.st.place(3, 4)
	victim.health = 100.0
	for t in 120:
		server._tick()
		victim.health = maxf(victim.health, 1.0)
	_expect(victim.health < 100.0, "a pirate with a baton comes up and strikes")
	server.combat.hurt(pirate, 300, a)
	_run(2)
	_expect(pirate.corpse and Items.is_weapon(pirate.slots[0]), "a dead pirate leaves a body with its weapon on it")
	victim.st.place(15, 4)
	victim.st.facing = Net.DIR_LEFT
	victim.cond = Net.COND_CRIT
	victim.st.down = true
	victim.health = -20.0
	brawler.st.place(16, 4)
	brawler.health = 100.0
	for t in 60:
		server._tick()
	_expect(victim.health > -40.0 and victim.cond != Net.COND_DEAD, "pirates leave those lying on the floor alone")

	print("a click turns the character")
	var t = _crew("Поворот", 8, 4)
	t.st.facing = Net.DIR_RIGHT
	t.inputs.append([server.tick + 1, preload("res://src/shared/mover.gd").TURN + Net.DIR_UP, 1])
	_run(2)
	_expect(t.st.facing == Net.DIR_UP and t.st.dir == Net.DIR_NONE and t.st.x == 8 and t.st.y == 4, "a turn input turns it on the spot")

	print("the locker and the trader")
	_expect(int(server.ship.store.get(Net.ITEM_PISTOL, 0)) == 1 and int(server.ship.store.get(Net.ITEM_MAG, 0)) == 2, "the ship sets out with a pistol and two magazines")
	_expect(server.supplies.weapons_aboard() >= 2, "the director knows the crew is armed (%d)" % server.supplies.weapons_aboard())

	server.stop()
	server.free()
	print("FIGHTTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _crew(who: String, x: int, y: int):
	var p := server.crew.new_player(who)
	p.slots.fill(Net.ITEM_NONE)
	p.st.place(x, y)
	p.st.facing = Net.DIR_RIGHT
	p.supply = true
	p.tank = 1.0
	return p


func _first_pirate():
	for q in server.players:
		if q != null and q.pirate:
			return q
	return null


func _roster_kind(p) -> int:
	return -1 if p == null else server.crew.roster_entry(p)[3]


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
