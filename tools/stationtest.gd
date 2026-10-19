extends SceneTree
## Checks our own crew at their posts in a fight, bots under the captain's
## orders, the battle position and our boarding of a pirate ship (v55), on a
## real server stepped by hand:
##   godot --headless --path . --script res://tools/stationtest.gd
## Somebody at the controls dodges (a pilot by job better, the engine minded
## better still); bots go to the posts they are sent to, a gunner bot fires, a
## mending bot mends with parts from the hold; only the captain orders while
## one is aboard. The position takes a manoeuvre, changes the hits and lapses
## with nobody at the controls or somebody outside. A boarder brings the
## pirates' crew to life, wrecks systems by hand, stops the ship running, and
## killing its crew captures it for more than a wreck pays.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Derelict := preload("res://src/server/derelict.gd")
const Stations := preload("res://src/server/stations.gd")
const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var failed := 0
var server: GameServer
var kept = null                         # (a character _run keeps on its feet)


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26340, "ship02", 2)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.gunnery.flies = false              # (v56) shots land the moment they are fired here
	server.systems.knock_chance = 0.0   # (v68) pirate hits break nothing near them here
	var map := server.map
	var g: Gunnery = server.gunnery
	var d: Derelict = server.derelict
	var st: Stations = server.stations
	g.ransom_chance = 0.0
	g.enemy_hit_chance = 0.0
	for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD]:
		_expect(not (st.spots[post] as Array).is_empty(), "there is somewhere to stand at post %s" % Net.POST_NAMES[post])
	var bots: Array = []
	for p in server.players:
		if p != null and p.bot:
			bots.append(p)
	_expect(bots.size() == 2, "two bots aboard")

	# a fight: nobody at the controls, nothing is dodged
	server.shipyard.force_class = Net.ECLASS_RAIDER
	_expect(d.pirates_come(3, true), "a raider comes")
	_run(2)
	_expect(st.our_dodge() == 0.0, "nobody at the controls: no dodge")
	var cap := server.crew.new_player("Капитан")
	cap.take_job(Net.JOB_CAPTAIN)
	_stand(cap, Net.POST_HELM)
	_run(2)
	_expect(is_equal_approx(st.our_dodge(), Stations.HELM_DODGE), "the captain at the controls dodges %d%%" % roundi(st.our_dodge() * 100))
	var pilot := server.crew.new_player("Пилот")
	pilot.take_job(Net.JOB_PILOT)
	_stand(cap, -1)
	_stand(pilot, Net.POST_HELM)
	_run(2)
	_expect(is_equal_approx(st.our_dodge(), Stations.HELM_DODGE + Stations.PILOT_DODGE * pilot.skill(Net.SKILL_PILOT)), "a pilot by job dodges better (%d%%)" % roundi(st.our_dodge() * 100))
	_stand(cap, Net.POST_ENGINE)
	_run(2)
	_expect(is_equal_approx(st.our_dodge(), Stations.HELM_DODGE + Stations.PILOT_DODGE * pilot.skill(Net.SKILL_PILOT) + Stations.ENGINE_DODGE), "with the engine minded, better still")
	_expect(st.shield_pace() == 1.0, "nobody at the shield: it refills as before")

	# orders: only the captain while one is aboard
	cap.peer = null
	_expect(st.may_order(cap), "the captain may order")
	_expect(st.may_order(pilot), "anybody may while no captain is connected (bots only here)")
	# bots go to their posts
	_stand(pilot, -1)
	_stand(cap, -1)
	st.order_asked(cap, bots[0].slot, Net.POST_HELM)
	st.order_asked(cap, bots[1].slot, Net.POST_SHIELD)
	_run(Net.TICK_HZ * 40)
	_expect(st.at_post(Net.POST_HELM) == bots[0], "a bot walks to the controls and mans them (%s)" % Net.DOING_NAMES[bots[0].doing])
	_expect(st.at_post(Net.POST_SHIELD) == bots[1], "a bot walks to the shield generator (%s)" % Net.DOING_NAMES[bots[1].doing])
	_expect(st.shield_pace() > 1.0, "with somebody there the shield refills faster")
	_expect(st.our_dodge() > 0.0, "a bot at the controls dodges")

	# the battle position
	st.position_asked(bots[0], Net.POS_FAR)
	_expect(st.goal == Net.POS_FAR and st.our_dodge() == 0.0, "the manoeuvre starts; no dodge during it")
	_run(roundi(Stations.MANOEUVRE_SECONDS * Net.TICK_HZ) + 2)
	_expect(st.position == Net.POS_FAR, "at a distance after the manoeuvre")
	_expect(st.our_hit_bonus() < 0.0 and st.their_hit_bonus() < 0.0, "both sides hit less")
	st.position_asked(bots[0], Net.POS_FLANK)
	_run(roundi(Stations.MANOEUVRE_SECONDS * Net.TICK_HZ) + 2)
	_expect(st.position == Net.POS_FLANK and st.our_hit_bonus() > 0.0, "on its flank we hit better")
	var full_dodge := Stations.HELM_DODGE
	_expect(st.our_dodge() < full_dodge, "and dodge worse (%d%%)" % roundi(st.our_dodge() * 100))
	st.order_asked(cap, bots[0].slot, Net.POST_FREE)
	_stand(bots[0], -1)
	_run(roundi(Stations.LAPSE_SECONDS * Net.TICK_HZ) + 10)
	_expect(st.position == Net.POS_CLOSE, "with nobody at the controls the position lapses to close in")

	# all to posts: the bots take what nobody mans
	st.order_asked(cap, Net.NOBODY, Net.POST_ALL)
	_expect(bots[0].order == Net.POST_HELM and bots[1].order == Net.POST_GUNS, "all to posts: controls, then guns")
	# a gunner bot fires when the guns are ready
	var hull_before := g.enemy_hull
	for i in g.charge.size():
		g.charge[i] = 1.0
	g.enemy_shield = 0.0
	g.systems[Net.ESYS_HELM] = 0
	_run(Net.TICK_HZ * 40)
	_expect(g.enemy_hull < hull_before or not g.fighting(), "the gunner bot fires (hull %d -> %d)" % [hull_before, g.enemy_hull])

	# a mending bot
	var spare := int(server.ship.store.get(Net.ITEM_PART, 0))
	var engine: int = map.engine.keys()[0]
	server.ship.broken[engine] = true
	st.order_asked(cap, bots[1].slot, Net.POST_REPAIR)
	_run(Net.TICK_HZ * 60)
	_expect(not server.ship.broken.has(engine), "the mending bot mends the engine")
	_expect(int(server.ship.store.get(Net.ITEM_PART, 0)) == spare - 1, "with a spare part from the hold (%d -> %d)" % [spare, int(server.ship.store.get(Net.ITEM_PART, 0))])
	st.order_asked(cap, Net.NOBODY, Net.POST_FREE)
	_expect(bots[0].order == Net.POST_FREE and bots[1].order == Net.POST_FREE, "stand down: all free")
	g.enemy_gone()
	d.pirates_wrecked()
	_run(5)

	# boarding
	_expect(d.pirates_come(3, true), "another raider comes")
	_run(2)
	var n: int = d._pirates_party
	var reward: int = g.reward
	var credits: int = server.ship.credits
	var boarder := server.crew.new_player("Абордажник")
	var room := g.room_of_system(Net.ESYS_SHIELDS) if g.systems_full[Net.ESYS_SHIELDS] > 0 else g.room_of_system(Net.ESYS_ENGINE)
	var system := g.system_in(room)
	var local: int = map.other.rooms[room][0]
	var cell: int = d._cell(map.other_at, local)
	boarder.st.place(cell % map.width, cell / map.width)
	kept = boarder                                     # (its crew fight back: keep our boarder standing)
	var pirates_before: int = server.pirates.aboard()
	_run(2)
	_expect(st.ours_aboard, "our boarder is aboard the pirate ship")
	_expect(server.enemy_crew.in_world and server.pirates.aboard() - pirates_before == n, "its crew (%d) come to life as pirates" % n)
	_expect(server.enemy_crew.count() == n and g.boarders_left() == n, "the counts stay in step")
	var was: int = g.systems[system]
	g._mend_next = server.tick + 100000                # (its crew would mend it meanwhile)
	_run(roundi(Stations.SABOTAGE_SECONDS * Net.TICK_HZ) + 2)
	_expect(g.systems[system] < was or g.systems[system] == 0, "standing in its %s room wrecks it (%d -> %d)" % [Net.ESYS_NAMES[system], was, g.systems[system]])
	g._starts_to_flee()
	var flee: float = g.flee
	_run(Net.TICK_HZ * 2)
	_expect(g.flee == flee and g.fighting(), "it cannot jump away with ours aboard")
	g.flee = -1.0
	# kill one: the counts follow
	var victims: Array = server.enemy_crew.people.duplicate()
	server.combat.hurt(victims[0], 999, null)
	_run(3)
	# (its crew walk about, and now and then one has stepped across onto our ship: it
	# no longer counts as its crew, so count those still on their own ship)
	var home := 0
	for v in victims:
		if not v.corpse and v.cond != Net.COND_DEAD and map.is_other(v.st.y * map.width + v.st.x):
			home += 1
	_expect(home < n and g.boarders_left() == home and d._pirates_party == home and server.enemy_crew.count() == home,
		"one dead: its crew count follows (%d, %d of %d on their ship)" % [g.boarders_left(), home, n])
	# (v64) one walks over onto our ship: no longer its crew, but not counted dead either
	var walker = null
	for v in victims:
		if walker == null and not v.corpse and v.cond != Net.COND_DEAD and map.is_other(v.st.y * map.width + v.st.x):
			walker = v
	if walker != null and home > 1:
		var spot := server.crew.spawn_point()
		walker.st.place(spot.x, spot.y)
		_run(3)
		_expect(walker.cond != Net.COND_DEAD and not walker.corpse and g.boarders_left() == home - 1 and server.enemy_crew.count() == home - 1
			and server.enemy_crew.crossed == 0 and g.fighting(), "one walks over onto our ship: its crew count follows, and it is still a pirate aboard ours")
	for v in victims:
		server.combat.hurt(v, 999, null)
	boarder.health = 100.0
	_run(3)
	_expect(not g.fighting() and d.wreck, "its crew all dead: the ship is captured and stays alongside")
	_expect(server.ship.credits - credits == roundi(reward * Gunnery.CAPTURE_SHARE), "salvaged for %d credits (a wreck pays %d)" % [server.ship.credits - credits, reward])
	_expect(map.is_other(boarder.st.y * map.width + boarder.st.x) and boarder.cond == Net.COND_OK, "our boarder is still aboard it, alive")
	var bodies := 0
	for p in server.players:
		if p != null and p.corpse and map.is_other(p.st.y * map.width + p.st.x):
			bodies += 1
	var there := 0                                     # (those who died on our side lie there)
	for v in victims:
		if map.is_other(v.st.y * map.width + v.st.x):
			there += 1
	_expect(bodies == there and there > 0, "its dead lie aboard, no more and no fewer (%d of %d)" % [bodies, there])

	server.stop()
	print("stationtest: %d failed" % failed)
	quit(1 if failed > 0 else 0)


func _stand(p, post: int) -> void:
	## Puts a character at a post (or out of the way, -1).
	var map := server.map
	if post < 0:
		var spot := server.crew.spawn_point()
		p.st.place(spot.x, spot.y)
		return
	var s: Array = server.stations.spots[post][0]
	p.st.place(int(s[0]) % map.width, int(s[0]) / map.width)
	p.st.facing = int(s[1])


func _run(ticks: int) -> void:
	for t in ticks:
		if kept != null:
			kept.health = 100.0
			kept.wounds = 0.0
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		failed += 1
