extends SceneTree
## Checks the air rules on the real map, without a network or a window:
##   godot --headless --path . --script res://tools/airtest.gd
## Prints how fast a breached compartment empties and fails (exit code 1)
## if air appears from nowhere, leaks through a shut door or does not settle.

const ShipMap := preload("res://src/shared/ship_map.gd")
const Doors := preload("res://src/shared/doors.gd")
const Air := preload("res://src/server/air.gd")
const Net := preload("res://src/shared/net.gd")
const Vitals := preload("res://src/server/vitals.gd")

var map := ShipMap.new()
var failed := 0


func _initialize() -> void:
	var problem := map.load_from("ship01")
	if problem != "":
		print(problem)
		quit(1)
		return
	var rooms := _rooms()
	print("map %s: %d walkable cells, %d doors, %d hull cells that can be breached, %d compartments" % [
		map.map_name, _count_walkable(), map.doors.size(), map.hull.size(), rooms.size()])

	# 1. nothing happens by itself
	var air := Air.new()
	var doors := Doors.new()
	air.setup(map)
	doors.setup(map.doors.size())
	var before := air.total()
	for i in 50:
		air.wake()
		air.step(doors, i)
	_expect(absf(air.total() - before) < 0.001, "a whole ship keeps all its air (%.3f -> %.3f)" % [before, air.total()])

	# 2. a hole empties its own compartment and nothing else while the doors are shut
	for hole in [map.hull[0], map.hull[map.hull.size() / 2]]:
		air.setup(map)
		doors.setup(map.doors.size())
		air.set_hole(hole, true)
		var room := _room_next_to(hole, rooms)
		var cells: Array = rooms[room]
		var marks := {0.5: -1, 0.3: -1, 0.1: -1}
		var step := 0
		# somebody stands in the far corner of the compartment from the moment it is breached
		var per_sec := float(Net.TICK_HZ) / Net.AIR_EVERY
		var body: int = cells[cells.size() - 1]
		var health := 100.0
		var cond := Net.COND_OK
		var fell := -1.0
		var died := -1.0
		while step < 3000 and (not air.settled or cond != Net.COND_DEAD):
			step += 1
			air.step(doors, step)
			var mean := _mean(air, cells)
			for m: float in marks.keys():
				if marks[m] < 0 and mean <= m:
					marks[m] = step
			health = Vitals.advance(health, cond, air.air[body], 1.0 / per_sec)
			var now := Vitals.condition(health, cond)
			if now != cond:
				if now == Net.COND_CRIT:
					fell = step / per_sec
				elif now == Net.COND_DEAD:
					died = step / per_sec
				cond = now
		print("  a person who stays inside passes out after %.0f s and dies after %.0f s" % [fell, died])
		_expect(fell > 5.0 and died > fell, "there is time to get out, and staying is fatal")
		print("hole at %d,%d, doors shut: compartment of %d cells falls to 50%% in %.1f s, 30%% in %.1f s, 10%% in %.1f s; settled after %.1f s" % [
			hole % map.width, hole / map.width, cells.size(), marks[0.5] / per_sec, marks[0.3] / per_sec, marks[0.1] / per_sec, step / per_sec])
		_expect(air.settled, "the air settles after a breach")
		_expect(_mean(air, cells) < 0.01, "the breached compartment ends up empty")
		var others_ok := true
		for r in rooms.size():
			if r != room and absf(_mean(air, rooms[r]) - 1.0) > 0.0001:
				others_ok = false
		_expect(others_ok, "shut doors keep the other compartments full")

		# 3. mend the hole, open one door of the empty compartment: the air spreads, none is lost
		air.set_hole(hole, false)
		var door := _door_of_room(cells)
		if door >= 0:
			doors.ready[door] = 0
			air.wake()
			var total := air.total()
			var n := 0
			while n < 5000 and not air.settled:
				n += 1
				air.step(doors, n)
			_expect(absf(air.total() - total) < 0.01, "opening a door loses no air (%.3f -> %.3f)" % [total, air.total()])
			_expect(_mean(air, cells) > 0.2, "air flows into the mended compartment (now %.0f%%), settled after %.1f s" % [_mean(air, cells) * 100.0, n / per_sec])
	# 4. the body: nothing happens in good air; a vacuum knocks out, then kills; good air brings back
	_expect(Vitals.harm(1.0) == 0.0 and Vitals.harm(Vitals.BREATH_MIN) == 0.0, "normal air does no harm")
	var out_at := 100.0 / Vitals.harm(0.0)
	print("  in a vacuum from full health: unconscious after %.0f s, dead after %.0f s" % [out_at, out_at * 2.0])
	var h := -40.0
	var c := Net.COND_CRIT
	var secs := 0.0
	while c == Net.COND_CRIT and secs < 1000.0:
		secs += 0.05
		h = Vitals.advance(h, c, 1.0, 0.05)
		c = Vitals.condition(h, c)
	_expect(c == Net.COND_OK, "an unconscious person in good air comes round (from -40 health in %.0f s)" % secs)
	print("AIRTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1


func _count_walkable() -> int:
	var n := 0
	for v in map.walk:
		n += v
	return n


func _mean(air: Air, cells: Array) -> float:
	var t := 0.0
	for c: int in cells:
		t += air.air[c]
	return t / cells.size()


func _rooms() -> Array:
	## Groups of cells that stay connected while every door is shut (door cells belong to no group).
	var seen := {}
	var out: Array = []
	for start in map.width * map.height:
		if map.walk[start] == 0 or map.door_of[start] >= 0 or seen.has(start):
			continue
		var group: Array = []
		var todo: Array = [start]
		seen[start] = true
		while not todo.is_empty():
			var c: int = todo.pop_back()
			group.append(c)
			var x := c % map.width
			var y := c / map.width
			for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var n := (y + o.y) * map.width + x + o.x
				if map.walkable(x + o.x, y + o.y) and map.door_of[n] < 0 and not seen.has(n):
					seen[n] = true
					todo.append(n)
		out.append(group)
	return out


func _room_next_to(hull_cell: int, rooms: Array) -> int:
	var x := hull_cell % map.width
	var y := hull_cell / map.width
	for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if map.walkable(x + o.x, y + o.y):
			var c := (y + o.y) * map.width + x + o.x
			for r in rooms.size():
				if (rooms[r] as Array).has(c):
					return r
	return -1


func _door_of_room(cells: Array) -> int:
	for c: int in cells:
		var x := c % map.width
		var y := c / map.width
		for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var d := map.door_at(x + o.x, y + o.y)
			if d >= 0:
				return d
	return -1
