extends SceneTree
## (v102) Checks the author's Notebook notes of 1 November, on a real server stepped by hand, and with a real client:
##   godot --headless --path . --script res://tools/followtest.gd
## Out of a fight our second ship follows the first by itself: the first turning on its spot no longer swings it
## round (his "both ships move like one"); the first flying off, it follows and keeps near; a key at the second
## ship's own helm flies it alone (the first stays), and once its pilot leaves the helm it follows again; a jump puts
## both in formation. Holding position (X) sent by a real client reaches the server (it was thrown away since v81).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Arena := preload("res://src/server/arena.gd")

const PORT := 26700

var failed := 0
var server: GameServer


func _initialize() -> void:
	_go()


func _go() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(PORT, "ship02|ship02", 1)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.wing.chance_for_test = 0.0
	server.stations.volunteers = false
	for q in server.players:
		if q != null and q.bot:
			q.order = Net.POST_FREE
	_follow()
	await _hold()
	server.stop()
	server.free()
	print("FOLLOWTEST %s" % ("ok" if failed == 0 else "FAILED: %d" % failed))
	quit(1 if failed > 0 else 0)


func _follow() -> void:
	print("  -- the second ship follows the first (his note: both ships move like one)")
	var a = server.arena
	var ship = server.ship
	ship.pos = Vector2(120, 120)
	ship.dest = ship.pos
	ship.moving = false
	_run(2)
	var lead = a.body(0)
	var two = a.body(1)
	_expect(lead != null and two != null and not a.on(), "two bodies of ours in space, no fight")
	if lead == null or two == null:
		return
	var touch: float = lead.shape.radius + two.shape.radius
	_expect(two.pos.distance_to(lead.pos) > touch * 0.6 and two.pos.distance_to(lead.pos) < touch + Arena.FOLLOW_ROOM,
		"it starts in formation beside and behind the first (%.0f cells apart)" % two.pos.distance_to(lead.pos))

	# the first turns on its spot: the second stays where it is (it used to swing round the first like a stick's end)
	var pilot = _at(0, "Пилот")
	var was: Vector2 = two.pos
	for i in 3 * Net.TICK_HZ:
		a.pilot_asked(pilot, Arena.KEY_RIGHT)
		_run(1)
	_expect(absf(wrapf(lead.rot, -PI, PI)) > 0.5, "the first turned on its spot (%.2f rad)" % lead.rot)
	_expect(two.pos.distance_to(was) < 2.0, "the second did not swing round it (moved %.1f cells)" % two.pos.distance_to(was))

	# the first flies off: the second follows and keeps near
	var start: Vector2 = two.pos
	var lead_start: Vector2 = lead.pos
	for i in 12 * Net.TICK_HZ:
		a.pilot_asked(pilot, Arena.KEY_AHEAD)
		_run(1)
	var gone: float = two.pos.distance_to(start)
	var apart: float = two.pos.distance_to(lead.pos)
	var led: float = lead.pos.distance_to(lead_start)
	_expect(gone > 10.0 and apart < touch + 80.0, "it follows the first (went %.0f cells, the first %.0f; %.0f apart)" % [gone, led, apart])
	_expect(two.thrusting or two.vel.length() > 3.0, "by its own engines (%.1f cells/s)" % two.vel.length())
	_away(pilot)
	_run(Arena.PILOT_HOLD + 25 * Net.TICK_HZ)
	apart = two.pos.distance_to(lead.pos)
	_expect(lead.vel.length() < 1.0 and apart < touch + Arena.FOLLOW_ROOM + 10.0 and apart > touch * 0.5,
		"once the first stops, the second stands near it, clear of it (%.0f apart, touching at %.0f)" % [apart, touch])

	# a key at the second ship's own helm flies it alone; the first stays
	var other = _at(1, "Второй пилот")
	var lead_was: Vector2 = lead.pos
	var two_was: Vector2 = two.pos
	for i in 5 * Net.TICK_HZ:
		server.fleet.use(1)
		a.pilot_asked(other, Arena.KEY_AHEAD)
		server.fleet.use(0)
		_run(1)
	_expect(two.solo and two.pos.distance_to(two_was) > 10.0, "W at the second ship's helm flies it alone (%.0f cells)" % two.pos.distance_to(two_was))
	_expect(lead.pos.distance_to(lead_was) < 1.0, "and the first stays where it was (%.1f)" % lead.pos.distance_to(lead_was))
	for i in 2 * Net.TICK_HZ:
		server.fleet.use(1)
		a.pilot_asked(other, 0)
		server.fleet.use(0)
		_run(1)
	_expect(two.solo, "standing at its helm with no key held, it stays its own")
	_away(other)
	_run(Arena.PILOT_HOLD + 40 * Net.TICK_HZ)
	apart = two.pos.distance_to(lead.pos)
	_expect(not two.solo and apart < touch + Arena.FOLLOW_ROOM + 10.0,
		"its pilot gone, it comes back to the first (%.0f apart)" % apart)

	# a jump (or a save) puts both in formation, standing
	ship.pos = Vector2(200, 160)
	_run(2)
	apart = two.pos.distance_to(lead.pos)
	_expect(apart > touch * 0.6 and apart < touch + Arena.FOLLOW_ROOM and two.vel == Vector2.ZERO,
		"put in a new place, the second stands in formation (%.0f apart)" % apart)


func _hold() -> void:
	print("  -- holding position (X) from a real client reaches the server")
	var c := GameClient.new()
	get_root().add_child(c)
	c.connect_to("127.0.0.1", PORT, "Стена")
	var until := Time.get_ticks_msec() + 8000
	while c.phase != GameClient.PLAYING and Time.get_ticks_msec() < until:
		await process_frame
	_expect(c.phase == GameClient.PLAYING, "the link joins")
	if c.phase != GameClient.PLAYING:
		return
	until = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < until:
		await process_frame
	var p = server.players[c.my_id]
	c.toggle_hold()
	until = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and not (p.st.hold and c.holds_position()):
		await process_frame   # (both: in one process the client's clock may trail the server's a tick or two)
	_expect(p.st.hold and c.holds_position(), "X: the server holds it too (server %s, client %s)" % [p.st.hold, c.holds_position()])
	until = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		await process_frame
	_expect(c.holds_position(), "and the client's word from the server keeps it held")
	c.toggle_hold()
	until = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until and p.st.hold:
		await process_frame
	_expect(not p.st.hold, "X again lets go on the server")
	c.close()
	get_root().remove_child(c)
	c.free()


func _at(ship: int, who: String):
	server.fleet.use(ship)
	var map = server.map
	var p = server.crew.new_player(who, ship)
	server.fleet.use(ship)
	var console: int = map.helm.keys()[0]
	var front: int = map.fitting_front(console)
	p.st.place(front % map.width, front / map.width)
	for f in [Net.DIR_UP, Net.DIR_DOWN, Net.DIR_LEFT, Net.DIR_RIGHT]:
		p.st.facing = f
		if map.use_ahead(p.st.x, p.st.y, f) == map.machine_of(console):
			break
	_expect(server.systems.at_console(p, map.helm), "(%s stands at the controls of ship %d)" % [who, ship])
	server.fleet.use(0)
	return p


func _away(p) -> void:
	server.fleet.use(0)
	var spawn: Vector2i = server.crew.spawn_point()
	p.st.place(spawn.x, spawn.y)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
