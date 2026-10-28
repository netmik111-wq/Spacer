extends SceneTree
## (v93) Checks the goggles (the author's O1) on a real server stepped by hand:
##   godot --headless --path . --script res://tools/eyestest.gd
## Goggles are worn over the eyes (Z), in their own place; night vision sees in the dark as if it were lit;
## thermal goggles show the living through a wall nearby on one's own deck, (v94) inside the field of view only, never the dead or robots, never
## far off. Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")
const Replication := preload("res://src/server/replication.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26331, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.replication.set_round(false)
	var map = server.map
	var r = server.replication

	# worn over the eyes, in a place of their own
	_expect(Items.worn_as(Net.ITEM_NVG) == Net.WEAR_EYES and Items.worn_as(Net.ITEM_THERMAL) == Net.WEAR_EYES, "goggles are worn over the eyes")
	_expect(Items.kept_in_locker().has(Net.ITEM_NVG) and Items.kept_in_locker().has(Net.ITEM_THERMAL), "the locker has a place for both")
	_expect(Items.price(Net.ITEM_NVG) > 0 and Items.price(Net.ITEM_THERMAL) > Items.price(Net.ITEM_NVG), "traders sell them, thermal dearer")
	var p = server.crew.new_player("Смотрящий")
	var q = server.crew.new_player("Тот")
	_expect(p.worn.size() == Net.WORN and p.has_suit(), "(a fresh one wears a suit, %d places)" % p.worn.size())
	p.slots[p.hand] = Net.ITEM_NVG
	_expect(server.inventory.act(p) and p.worn[Net.WEAR_EYES] == Net.ITEM_NVG and p.has_suit(), "Z puts night vision on, over the suit")
	p.slots[p.hand] = Net.ITEM_THERMAL
	_expect(server.inventory.act(p) and p.worn[Net.WEAR_EYES] == Net.ITEM_THERMAL and p.in_hand() == Net.ITEM_NVG, "the other pair swaps in, the first comes into the hand")
	p.slots[p.hand] = Net.ITEM_NONE
	p.worn[Net.WEAR_EYES] = Net.ITEM_NONE

	# a pair of places in sight of each other, too far to be made out in the dark
	var pair := _pair(p, q, func(lit: bool, dist: float) -> bool: return lit and dist > Sight.DARK_REACH + 2.0 and dist <= Sight.SIGHT_REACH - 1)
	_expect(not pair.is_empty(), "(two places in sight of each other, %s)" % str(pair))
	if not pair.is_empty():
		_put(p, q, pair)
		server.power.breaker[Net.BREAKER_LIGHTS] = 0
		_expect(not r.sees(p, q), "with the lights off, one at the far end of a room is not made out")
		p.worn[Net.WEAR_EYES] = Net.ITEM_NVG
		_expect(r.sees(p, q), "with night vision, it is")
		server.power.breaker[Net.BREAKER_LIGHTS] = 1
		p.worn[Net.WEAR_EYES] = Net.ITEM_NONE

	# a pair behind a wall from each other, close by on one deck
	var walled := _pair(p, q, func(lit: bool, dist: float) -> bool: return not lit and dist >= 2.0 and dist <= Replication.THERMAL_REACH - 1.0)
	_expect(not walled.is_empty(), "(two places a wall apart)")
	if not walled.is_empty():
		_put(p, q, walled)
		_expect(not r.sees(p, q), "a wall hides one")
		p.worn[Net.WEAR_EYES] = Net.ITEM_THERMAL
		_expect(r.sees(p, q), "thermal goggles show it through the wall")
		var ahead: int = p.st.facing
		var w: Vector2 = -Net.way(ahead)
		p.st.facing = Net.dir_of(roundi(w.x), roundi(w.y))
		_expect(not r.sees(p, q), "but not behind one's back (v94, the author's note)")
		p.st.facing = ahead
		q.robot = true
		_expect(not r.sees(p, q), "but not a robot")
		q.robot = false
		q.cond = Net.COND_DEAD
		_expect(not r.sees(p, q), "nor a body")
		q.cond = Net.COND_CRIT
		_expect(r.sees(p, q), "one out cold is still warm")
		q.cond = Net.COND_OK
		p.worn[Net.WEAR_EYES] = Net.ITEM_NVG
		_expect(not r.sees(p, q), "night vision sees no more through walls")
		p.worn[Net.WEAR_EYES] = Net.ITEM_NONE
	var far := _pair(p, q, func(lit: bool, dist: float) -> bool: return not lit and dist > Replication.THERMAL_REACH + 1.0 and dist < Replication.THERMAL_REACH + 4.0)
	if not far.is_empty():
		_put(p, q, far)
		p.worn[Net.WEAR_EYES] = Net.ITEM_THERMAL
		_expect(not r.sees(p, q), "thermal goggles reach only so far")
		p.worn[Net.WEAR_EYES] = Net.ITEM_NONE

	# the client knows them
	_expect(Items.INFO[Net.ITEM_NVG]["name"] != "" and Items.INFO[Net.ITEM_THERMAL]["about"] != "", "both have a name and words")

	print("eyestest: %s" % ("ok" if failed == 0 else "%d FAILED" % failed))
	server.stop()
	quit(1 if failed > 0 else 0)


func _pair(p, q, wanted: Callable) -> Array:
	## Two floor cells of the top deck, p facing q's way: [p cell, facing, q cell] for which
	## wanted(seen with the lights on, distance) holds.
	var map = server.map
	var walk := []
	for y in map.deck_height:
		for x in map.width:
			var c: int = y * map.width + x
			if map.walkable(x, y) and not map.on_backup(c) and not map.is_other(c):
				walk.append(c)
	for a: int in walk:
		for b: int in walk:
			if a == b:
				continue
			var d := Vector2(a % map.width, a / map.width).distance_to(Vector2(b % map.width, b / map.width))
			if d > Sight.SIGHT_REACH + 3:
				continue
			var way := Vector2(b % map.width - a % map.width, b / map.width - a / map.width)
			var facing: int = Net.dir_of(signi(roundi(way.x)) if absf(way.x) >= absf(way.y) else 0, signi(roundi(way.y)) if absf(way.y) > absf(way.x) else 0)
			_put(p, q, [a, facing, b])
			if wanted.call(server.replication.sees(p, q), d):
				return [a, facing, b]
	return []


func _put(p, q, pair: Array) -> void:
	var map = server.map
	p.st.place(int(pair[0]) % map.width, int(pair[0]) / map.width)
	p.st.facing = int(pair[1])
	q.st.place(int(pair[2]) % map.width, int(pair[2]) / map.width)


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
