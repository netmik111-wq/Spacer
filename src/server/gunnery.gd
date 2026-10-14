extends RefCounted
## The ship's guns, and the guns of a pirate ship that comes for us. Server only.
##
## Our guns sit in the hull ('T' in the map) and are fired from the gun
## console on the bridge. Each charges by itself while the ship has power and
## the gun is whole; a charged gun fires at the enemy when told to. A pirate
## ship off the airlock shoots back until it docks: its hits tear the hull or
## put a gun or a bridge console out of order. Its own hull takes ENEMY_HULL
## hits; then it is wrecked and goes, and the ship is paid for it.

const Net := preload("res://src/shared/net.gd")

const CHARGE_SECONDS := 8.0          # from fired to ready again
const HIT_CHANCE := 0.75             # our shot hits
const ENEMY_HULL := 6                # hits a pirate ship takes before it is wrecked
const ENEMY_GAP := [9.0, 13.0]       # seconds between the pirate ship's shots
const ENEMY_HIT_CHANCE := 0.7
const ENEMY_BREACH_SHARE := 0.6      # of its hits, those that hole the hull (the rest put something out of order)
const WRECK_REWARD := 25             # credits for a wrecked pirate ship

var enemy_hit_chance := ENEMY_HIT_CHANCE   # (tests set it to 1)
var server: Node
var charge := PackedFloat32Array()   # per gun, 0..1
var enemy_hull := 0                  # hits the enemy can still take; 0 = no enemy
var _enemy_next := 0                 # the tick the enemy fires next
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: Node) -> void:
	server = p_server
	charge.resize(server.map.guns.size())
	charge.fill(1.0)
	enemy_hull = 0
	_told = PackedByteArray()
	_rng.randomize()


func enemy_arrives() -> void:
	enemy_hull = ENEMY_HULL
	_enemy_next = server.tick + roundi(_rng.randf_range(ENEMY_GAP[0], ENEMY_GAP[1]) * Net.TICK_HZ)


func enemy_gone() -> void:
	enemy_hull = 0


func fighting() -> bool:
	## A pirate ship lies off the airlock and has not docked yet: guns can reach it, and it shoots.
	var d = server.derelict
	return enemy_hull > 0 and d.here and d.kind == Net.OTHER_PIRATE and not d.docked


func tick() -> void:
	var map = server.map
	var step := 1.0 / (CHARGE_SECONDS * Net.TICK_HZ)
	for i in charge.size():
		if server.powered() and not server.ship.broken.has(map.guns[i]):
			charge[i] = minf(charge[i] + step, 1.0)
	if fighting() and server.tick >= _enemy_next:
		_enemy_next = server.tick + roundi(_rng.randf_range(ENEMY_GAP[0], ENEMY_GAP[1]) * Net.TICK_HZ)
		_enemy_fires()
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func packet() -> PackedByteArray:
	var map = server.map
	var out := PackedByteArray([Net.S_GUNS, server.ship.id & 0xFF, server.ship.id >> 8, charge.size()])
	for i in charge.size():
		out.append(255 if server.ship.broken.has(map.guns[i]) else roundi(charge[i] * 20.0) * 5)
	out.append(enemy_hull if fighting() else 0)
	out.append(ENEMY_HULL if fighting() else 0)
	var left := 0
	if fighting() and server.derelict._pirates_dock_at >= 0:
		left = maxi(int(ceil(float(server.derelict._pirates_dock_at - server.tick) / Net.TICK_HZ)), 0)
	out.append(left & 0xFF)
	out.append(left >> 8)
	return out


func fire(p, which: int) -> void:
	## Somebody at the gun console fires one gun, or every gun that is ready (which = 255).
	var map = server.map
	if not server.systems.at_console(p, map.gun_console):
		return
	if not fighting():
		server.chat.say("Стрелять не по кому: целей нет.")
		return
	var fired := 0
	for i in charge.size():
		if (which == 255 or which == i) and charge[i] >= 1.0 and not server.ship.broken.has(map.guns[i]):
			charge[i] = 0.0
			fired += 1
			_our_shot(i)
			if enemy_hull <= 0:
				break
	if fired > 0 and enemy_hull <= 0:
		_wrecked()


func _our_shot(i: int) -> void:
	var map = server.map
	var cell: int = map.guns[i]
	var x: int = cell % map.width
	var y: int = cell / map.width
	var out := _outward(cell)
	server.chat.sound(Net.SOUND_SHOT, x, y)
	var hit := _rng.randf() < HIT_CHANCE
	server.combat.tell_shot(Net.SHOT_CANNON, hit, Vector2(x, y), Vector2(x, y) + Vector2(out) * 12.0, y)
	if hit:
		enemy_hull -= 1
		# a hole in its hull where it shows
		var hull: PackedInt32Array = server.derelict._hull_cells()
		if not hull.is_empty():
			var c: int = hull[_rng.randi_range(0, hull.size() - 1)]
			if server.air.set_hole(c, true):
				server.replication.hull_record(c, 1)
		server.chat.say("Орудие %d: попадание! Корпус пиратского корабля: %d из %d." % [i + 1, maxi(enemy_hull, 0), ENEMY_HULL])
	else:
		server.chat.say("Орудие %d: промах." % (i + 1))


func _wrecked() -> void:
	enemy_hull = 0
	server.ship.credits += WRECK_REWARD
	server.ship.store[Net.ITEM_FUEL] = int(server.ship.store.get(Net.ITEM_FUEL, 0)) + Net.WRECK_FUEL
	server.derelict.pirates_wrecked()
	server.chat.say("Пиратский корабль разбит и уходит, не успев пристыковаться! За него начислено %d кредитов, из обломков подобрана канистра топлива." % WRECK_REWARD)
	server.supplies.tell_store()


func _enemy_fires() -> void:
	## The pirate ship's shot: it holes our hull, or puts a gun or a bridge console out of order.
	var map = server.map
	if _rng.randf() >= enemy_hit_chance:
		server.chat.say("Пиратский корабль стреляет: мимо.")
		return
	if _rng.randf() < ENEMY_BREACH_SHARE or map.hull.is_empty():
		var choice := PackedInt32Array()
		for c: int in map.hull:
			if not server.air.holes.has(c):
				choice.append(c)
		if choice.is_empty():
			return
		var c: int = choice[_rng.randi_range(0, choice.size() - 1)]
		_tracer_to(c)
		server.systems.breach(c)
		return
	var targets := PackedInt32Array()
	for g: int in map.guns:
		if not server.ship.broken.has(g):
			targets.append(g)
	if server.systems.can_break("console"):
		for c: int in map.chart.keys() + map.helm.keys():
			targets.append(c)
	if targets.is_empty():
		return
	var hit: int = targets[_rng.randi_range(0, targets.size() - 1)]
	server.ship.broken[hit] = true
	server.to_all(server.ship.devices_packet())
	server.crew.hull_hit(Net.HULL_PER_SYSTEM_HIT)
	_tracer_to(hit)
	server.chat.say("Попадание пиратов! Не работает: %s." % map.device_name(hit))


func _tracer_to(cell: int) -> void:
	var map = server.map
	var at := Vector2(cell % map.width, cell / map.width)
	server.combat.tell_shot(Net.SHOT_CANNON, true, at + Vector2(_outward(cell)) * 12.0, at, int(at.y))
	server.chat.sound(Net.SOUND_THUD, int(at.x), int(at.y))


func _outward(cell: int) -> Vector2i:
	## Which way is space from this wall cell (up if it cannot tell).
	var map = server.map
	var x: int = cell % map.width
	var y: int = cell / map.width
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if map.is_space(x + d.x, y + d.y):
			return d
	return Vector2i(0, -1)
