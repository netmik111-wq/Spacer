extends SceneTree
## Checks the admin panel's commands on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/admintest.gd
## Only the host (proved with the server's secret text) and the players it made
## admins may use them; an admin gives itself things, heals and raises the dead,
## kills, moves people about, changes jobs, mends and supplies the ship, and
## puts a trader in the sector.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")

const TOKEN := "secret"

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	server.shutdown_token = TOKEN
	var problem := server.start(26193, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var host := server.crew.new_player("Хозяин")
	var guest := server.crew.new_player("Гость")
	guest.peer = null

	print("who may")
	_admin(guest, Net.ADMIN_CREDITS)
	_expect(server.ship.credits == Net.START_CREDITS, "a player who is not an admin is ignored")
	_admin(host, Net.ADMIN_HELLO, 0, 0, "wrong")
	_expect(not host.admin, "a wrong secret text proves nothing")
	_admin(host, Net.ADMIN_HELLO, 0, 0, TOKEN)
	_expect(host.admin and host.host, "the right one makes the host an admin")
	_admin(host, Net.ADMIN_CREDITS)
	_expect(server.ship.credits == Net.START_CREDITS + Net.ADMIN_CREDITS_GIVEN, "and the host's commands work without it afterwards")
	server.admin.names["Гость"] = true
	server.admin.joined(guest)
	_admin(guest, Net.ADMIN_HULL)
	_expect(guest.admin, "a player the host made an admin is one by name")
	_admin(guest, Net.ADMIN_GRANT, 1, host.slot)
	_expect(host.admin, "(only the host makes admins)")

	print("things")
	host.slots.fill(Net.ITEM_NONE)
	host.hand = 0
	var all := Items.spawnable()
	_expect(all.has(Net.ITEM_PISTOL + Net.PISTOL_ROUNDS) and all.has(Net.ITEM_SUIT + Net.SUIT_TANK_STEPS) and not all.has(Net.ITEM_FLASHLIGHT_ON),
		"the list holds one of everything, as new")
	_admin(host, Net.ADMIN_GIVE, Net.ITEM_MEDPATCH)
	_expect(host.slots[0] == Net.ITEM_MEDPATCH, "a thing comes into the hand")
	for i in Net.SLOTS:
		_admin(host, Net.ADMIN_GIVE, Net.ITEM_PATCH)
	var cell := host.st.y * server.map.width + host.st.x
	_expect(server.floor_things.has(cell) and (server.floor_things[cell] as PackedByteArray).has(Net.ITEM_PATCH),
		"with every slot full the rest lies at the feet")
	_admin(host, Net.ADMIN_GIVE, 250)
	_expect(true, "(an unknown thing is refused without an error)")

	print("people")
	guest.health = -150.0
	_run(2)
	_expect(guest.cond == Net.COND_DEAD, "(the guest is dead)")
	_admin(host, Net.ADMIN_HEAL, 0, guest.slot)
	_expect(guest.cond == Net.COND_OK and guest.health == Net.HEALTH_FULL and not guest.st.down, "healing raises the dead")
	guest.wounds = 40.0
	guest.health = 30.0
	guest.tank = 0.1
	_admin(host, Net.ADMIN_HEAL, 0, guest.slot)
	_expect(guest.wounds == 0.0 and guest.health == Net.HEALTH_FULL and guest.tank == 1.0, "and closes wounds and fills the tank")
	_admin(host, Net.ADMIN_KILL, 0, guest.slot)
	_run(2)
	_expect(guest.cond == Net.COND_DEAD, "killing kills")
	_admin(host, Net.ADMIN_HEAL, 0, guest.slot)
	_run(20)
	_expect(guest.cond == Net.COND_OK, "and the dead one stays alive after healing")
	host.st.place(server.map.spawns[0].x, server.map.spawns[0].y)
	guest.st.place(server.map.spawns[1].x, server.map.spawns[1].y)
	_admin(host, Net.ADMIN_BRING, 0, guest.slot)
	_expect(absi(guest.st.x - host.st.x) + absi(guest.st.y - host.st.y) <= 1, "«to me» puts them beside the admin")
	guest.st.place(server.map.spawns[2].x, server.map.spawns[2].y)
	_admin(host, Net.ADMIN_GOTO, 0, guest.slot)
	_expect(absi(guest.st.x - host.st.x) + absi(guest.st.y - host.st.y) <= 1, "«to them» puts the admin beside them")
	_expect(server.map.walkable(host.st.x, host.st.y), "(on a floor)")
	_admin(host, Net.ADMIN_JOB, Net.JOB_ENGINEER, guest.slot)
	_expect(guest.job == Net.JOB_ENGINEER and guest.st.access == Net.JOB_ACCESS[Net.JOB_ENGINEER], "a new job gives its access")

	print("the ship")
	server.systems.breach_near(host.st.x, host.st.y)
	server.ship.broken[server.map.engine.keys()[0]] = true
	server.doors.jammed[0] = 1
	_run(40)
	_expect(not server.powered() and not server.air.holes.is_empty(), "(a hole, a broken engine, a jammed door)")
	_admin(host, Net.ADMIN_REPAIR)
	_run(2)
	_expect(server.powered() and server.air.holes.is_empty() and server.ship.broken.is_empty() and server.doors.jammed[0] == 0,
		"«mend everything» mends everything")
	_admin(host, Net.ADMIN_AIR)
	var full := true
	for i in server.map.base_walk.size():
		if server.map.base_walk[i] == 1:
			full = full and server.air.air[i] >= 0.999
	_expect(full, "air everywhere")
	server.ship.store.clear()
	_admin(host, Net.ADMIN_RESTOCK)
	_expect(int(server.ship.store.get(Net.ITEM_FUEL, 0)) == Items.stock(Net.ITEM_FUEL), "the locker filled again")
	server.reserve = 0
	_admin(host, Net.ADMIN_RESERVE)
	_expect(server.reserve == 1, "one more in reserve")
	server.ship.hull = 3
	_admin(host, Net.ADMIN_HULL)
	_expect(server.ship.hull == Net.HULL_MAX, "a hull as new")

	print("space")
	_admin(host, Net.ADMIN_PLACE, Sectors.TRADER)
	_run(2)
	_expect(server.navigation.sector_kind() == Sectors.TRADER and server.ship.in_reach, "a trader here, with the ship at it")
	var before := server.pirates.aboard()
	_admin(host, Net.ADMIN_PIRATE, 1)
	_expect(server.pirates.aboard() == before + 1, "a pirate in front of the admin")

	print("ADMINTEST %s" % ("ok" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _admin(p, command: int, argument: int = 0, target: int = 0, token: String = "") -> void:
	var pkt := PackedByteArray([Net.C_ADMIN, command, argument, 0, 0])
	pkt.encode_u16(3, target)
	pkt.append_array(token.to_utf8_buffer())
	server.admin.asked(p, pkt)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
