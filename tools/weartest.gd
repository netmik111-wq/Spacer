extends SceneTree
## Checks clothing on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/weartest.gd
## Everybody comes in a spacesuit and a jumpsuit. A suit comes off and goes on
## with the oxygen left in it; without one the supply does not work. A jumpsuit
## gives two pockets, a backpack four more; neither comes off with things in
## it. What a body wears can be taken off it.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Items := preload("res://src/shared/items.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26280, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false

	var p := server.crew.new_player("Тест")
	p.slots.fill(Net.ITEM_NONE)
	p.hand = 0
	_expect(p.has_suit() and p.worn[Net.WEAR_JUMPSUIT] == Net.ITEM_JUMPSUIT and p.worn[Net.WEAR_PACK] == Net.ITEM_NONE,
		"a newcomer wears a spacesuit and a jumpsuit")
	_expect(p.count(Net.ITEM_NONE) == Net.BASE_SLOTS + Net.POCKETS, "and has %d slots: the jumpsuit's pockets count" % p.count(Net.ITEM_NONE))
	_expect(p.look() == Net.OUTFIT_SUIT * 2, "and looks suited")

	# the suit
	p.tank = 0.5
	_expect(server.inventory.take_off(p, Net.WEAR_SUIT) and p.slots[0] == Net.ITEM_SUIT + 5 and not p.has_suit(),
		"the suit comes off into the hand with half a tank in it")
	_expect(p.look() == Net.OUTFIT_JUMPSUIT * 2, "and then the jumpsuit shows")
	server.inventory.set_supply(p, true)
	_expect(not p.supply, "without a suit there is no oxygen supply")
	p.st.place(2, 7)
	for c in server.air.air.size():
		server.air.air[c] = 0.0
	server.air.settled = true
	var before := p.health
	_run(Net.TICK_HZ)
	_expect(p.health < before, "and vacuum hurts")
	server.air.refill()
	p.health = 100.0
	_expect(server.inventory.act(p) and p.has_suit() and absf(p.tank - 0.5) < 0.01 and p.slots[0] == Net.ITEM_NONE,
		"Z puts it back on with its oxygen")
	server.inventory.set_supply(p, true)
	_expect(p.supply, "and the supply works again")

	# pockets and a backpack
	p.slots[0] = Net.ITEM_BACKPACK
	_expect(server.inventory.act(p) and p.worn[Net.WEAR_PACK] == Net.ITEM_BACKPACK and p.count(Net.ITEM_NONE) == Net.SLOTS,
		"a backpack goes on: %d slots now" % Net.SLOTS)
	_expect(p.look() == Net.OUTFIT_SUIT * 2 + 1, "and shows")
	p.slots[Net.SLOTS - 1] = Net.ITEM_PATCH
	_expect(not server.inventory.take_off(p, Net.WEAR_PACK) and p.worn[Net.WEAR_PACK] == Net.ITEM_BACKPACK, "it does not come off with things in it")
	p.slots[Net.SLOTS - 1] = Net.ITEM_NONE
	_expect(server.inventory.take_off(p, Net.WEAR_PACK) and p.slots[0] == Net.ITEM_BACKPACK, "empty, it does")
	p.slots[0] = Net.ITEM_JUMPSUIT
	_expect(server.inventory.act(p) and p.worn[Net.WEAR_JUMPSUIT] == Net.ITEM_JUMPSUIT and p.slots[0] == Net.ITEM_JUMPSUIT,
		"putting on a jumpsuit over one swaps them")
	p.slots[0] = Net.ITEM_NONE
	p.slots[Net.BASE_SLOTS] = Net.ITEM_PART
	_expect(not server.inventory.take_off(p, Net.WEAR_JUMPSUIT), "a jumpsuit does not come off with something in its pockets")
	p.slots[Net.BASE_SLOTS] = Net.ITEM_NONE

	# the oxygen station fills only a suit that is worn
	_expect(p.has_suit(), "(still suited)")

	# a body
	var q := server.crew.new_player("Павший")
	q.slots.fill(Net.ITEM_NONE)
	q.st.place(p.st.x + 1, p.st.y)
	q.tank = 0.8
	q.health = Net.HEALTH_DEAD
	q.cond = Net.COND_DEAD
	q.st.down = true
	q.died_tick = server.tick - Net.RESPAWN_TICKS
	server.crew.respawn(q)
	var body = null
	for r in server.players:
		if r != null and r.corpse and r.name == "Павший":
			body = r
	_expect(body != null and body.has_suit() and q.has_suit() and absf(q.tank - 1.0) < 0.01,
		"the dead leave their suit on the body; the newcomer gets a fresh one")
	p.st.facing = Net.DIR_RIGHT
	p.searching = body.slot
	p.slots.fill(Net.ITEM_NONE)
	server.looting.loot_asked(p, true, Net.SLOTS + Net.WEAR_SUIT)
	_expect(not body.has_suit() and Items.tank_of(p.slots[0]) == 8, "a suit can be taken off a body, with what is left in its tank")
	server.looting.loot_asked(p, false, 0)
	_expect(p.slots[0] == Net.ITEM_NONE and body.count(Net.ITEM_SUIT) == 1 and not body.has_suit(),
		"given back to the dead, it goes into their pockets")
	var out := server.crew.new_player("Обморок")
	out.st.place(p.st.x + 1, p.st.y)
	out.take_off(Net.WEAR_SUIT)
	out.supply = false
	out.health = -10.0
	out.cond = Net.COND_CRIT
	out.st.down = true
	p.searching = out.slot
	p.slots[0] = Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	server.looting.loot_asked(p, false, 0)
	_expect(p.slots[0] == Net.ITEM_NONE and out.has_suit() and out.supply,
		"a suit given to somebody out cold goes onto them, with the oxygen on")

	# the locker keeps them
	_expect(int(server.ship.store.get(Net.ITEM_SUIT + Net.SUIT_TANK_STEPS, 0)) == 2 and int(server.ship.store.get(Net.ITEM_BACKPACK, 0)) == 2,
		"the locker holds spare suits and backpacks")

	server.stop()
	server.free()
	print("WEARTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
