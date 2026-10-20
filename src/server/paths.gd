extends RefCounted
## (v77, the author's B1: bots and pirates walk on a slant too) The shortest way over the
## grid in 8 ways, for whoever the server walks: bots, pirates, our security robots.
## A slant step costs 1.4 straight ones (as it takes 1.4 times as long, Mover.slant_span),
## so a way never zigzags where a straight one is as short. A slant is taken only where a
## player could take it (Mover.slant_open: no corner cut, no doorway crossed on a slant),
## and only past cells the walker could step into anyway.

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")

const STRAIGHT := 5
const SLANT := 7


static func first_step(map: ShipMap, start: int, goals: Dictionary, ok: Callable, slants: bool = true) -> Array:
	## [the first step of a shortest way from `start` to the nearest of `goals` (a direction
	## 1..8, -1 = the ladder underfoot, 0 = none), that goal (-1 = none reachable)].
	## `ok(x, y)`: may the walker step into that cell (bounds are checked here).
	## Ladders are climbed (but not out in space). `start` itself never counts as a goal.
	var w := map.width
	var h := map.height
	var cost := {start: 0}
	var first := {start: 0}
	var memo := {}
	var buckets: Array[PackedInt32Array] = [PackedInt32Array([start])]
	var b := 0
	while b < buckets.size():
		var list: PackedInt32Array = buckets[b]
		for cell in list:
			if int(cost[cell]) != b:
				continue                     # reached more cheaply since
			if cell != start and goals.has(cell):
				return [first[cell], cell]
			var x := cell % w
			var y := cell / w
			var open := [false, false, false, false, false]
			for d in range(1, 5):
				var nx: int = x + Net.DX[d]
				var ny: int = y + Net.DY[d]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if not memo.has(j):
					memo[j] = ok.call(nx, ny)
				if memo[j]:
					open[d] = true
					_reach(buckets, cost, first, j, b + STRAIGHT, d if cell == start else int(first[cell]))
			if slants and map.door_of[cell] < 0:
				for d in range(5, Net.DIRS + 1):
					var dx: int = Net.DX[d]
					var dy: int = Net.DY[d]
					var nx: int = x + dx
					var ny: int = y + dy
					var across := Net.dir_of(dx, 0)
					var upright := Net.dir_of(0, dy)
					if not open[across] or not open[upright] or nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var j := ny * w + nx
					if not memo.has(j):
						memo[j] = ok.call(nx, ny)
					if memo[j] and map.door_of[j] < 0 and map.door_of[y * w + nx] < 0 and map.door_of[ny * w + x] < 0 \
							and map.deck_of(y) == map.deck_of(ny):
						_reach(buckets, cost, first, j, b + SLANT, d if cell == start else int(first[cell]))
			if map.climb[cell] >= 0 and not map.floats(x, y):
				_reach(buckets, cost, first, map.climb[cell], b + STRAIGHT, -1 if cell == start else int(first[cell]))
		b += 1
	return [0, -1]


static func _reach(buckets: Array[PackedInt32Array], cost: Dictionary, first: Dictionary, to: int, c: int, step: int) -> void:
	if cost.has(to) and int(cost[to]) <= c:
		return
	cost[to] = c
	first[to] = step
	while buckets.size() <= c:
		buckets.append(PackedInt32Array())
	var list: PackedInt32Array = buckets[c]
	list.append(to)
	buckets[c] = list
