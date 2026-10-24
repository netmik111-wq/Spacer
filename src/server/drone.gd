extends RefCounted
## The scouting drone (v54, the author's notebook: "an intruder drone that gets
## inside the ship, moved manually from a monitor, so you can scan the interior
## yourself"). Server only.
##
## A drone is a thing in the cargo (Net.ITEM_DRONE). Whoever stands at the
## drone monitor on the bridge sends one at the pirate ship we fight: it flies
## over for FLY_SECONDS and slips in through its outer door. Inside, it goes
## where the one at the monitor steers it, a cell at a time (anybody at the
## monitor may take over). Every room it enters shows what it holds, and it sees
## the pirates in the room it is in and next to it (EnemyCrew.visible). Its
## battery lasts BATTERY_SECONDS; pirates in its room may spot it and shoot it
## down. It can blow itself up where it is: the system in that room takes
## BLAST damage that no shield stops, the hull a point, and those in the room
## may be hurt. Whatever ends it (the battery, a shot, the blast, the enemy
## gone), it is spent.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const FLY_SECONDS := 4.0
const BATTERY_SECONDS := 60.0
const STEP_TICKS := 5                # one cell a quarter of a second
const SPOTTED := 0.15                # each second, each fit pirate in its room shoots it down this often
const BLAST := 2

var server: GameServer
var spotted := SPOTTED               # (tests set it)
var state := Net.DRONE_NONE
var at := -1                         # the cell of the enemy's drawing it is in
var dir := Net.DIR_NONE              # where it is steered
var _arrive := 0                     # the tick it gets there (while flying)
var _empty_at := 0                   # the tick its battery runs out
var _next_step := 0
var _told := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	_rng.randomize()
	state = Net.DRONE_NONE
	at = -1


func asked(p: Player, action: int, a: int) -> void:
	if not server.systems.at_console(p, server.map.drone_console):
		return
	match action:
		Net.DRONE_LAUNCH:
			_launch(p)
		Net.DRONE_STEER:
			if a <= Net.DIR_RIGHT:
				dir = a
		Net.DRONE_BLOW:
			if state == Net.DRONE_INSIDE:
				_blow(p)


func _launch(p: Player) -> void:
	var store: Dictionary = server.ship.store
	server.usage.note(p, "drone")          # (v82)
	if state != Net.DRONE_NONE:
		server.chat.tell(p, "Дрон уже в деле.")
		return
	if not server.gunnery.engaged():
		server.chat.tell(p, "Дрона посылать не к кому: рядом нет пиратского корабля.")
		return
	if int(store.get(Net.ITEM_DRONE, 0)) <= 0:
		server.chat.tell(p, "В трюме нет дронов. Их продают торговцы.")
		return
	store[Net.ITEM_DRONE] -= 1
	server.supplies.tell_store()
	state = Net.DRONE_FLYING
	dir = Net.DIR_NONE
	_arrive = server.tick + roundi(FLY_SECONDS * Net.TICK_HZ)
	server.chat.say_bridge("%s запускает дрона-разведчика: через %d с он проникнет на пиратский корабль." % [p.name, int(FLY_SECONDS)])


func inside() -> bool:
	return state == Net.DRONE_INSIDE


func room() -> int:
	var o = server.enemy_crew.o
	return o.room_of[at] if inside() and o != null and at >= 0 else -1


func sees(cell: int) -> bool:
	## Does the drone see that cell of the enemy's drawing (its room, or right next to it)?
	if not inside() or server.enemy_crew.o == null:
		return false
	var o = server.enemy_crew.o
	var r := room()
	if r >= 0 and o.room_of[cell] == r:
		return true
	return absi(cell % o.width - at % o.width) <= 1 and absi(cell / o.width - at / o.width) <= 1


func tick() -> void:
	if state != Net.DRONE_NONE and (not server.gunnery.engaged() or server.enemy_crew.o == null):
		_lost("Связь с дроном потеряна: пиратского корабля больше нет рядом.")
	elif state == Net.DRONE_FLYING and server.tick >= _arrive and server.gunnery.enemy_guard and _rng.randf() < Weapons.GUARD_HIT:
		_lost("Точечная оборона пиратов сбила дрона на подлёте.")    # (v58)
	elif state == Net.DRONE_FLYING and server.tick >= _arrive:
		at = _entry()
		state = Net.DRONE_INSIDE
		_empty_at = server.tick + roundi(BATTERY_SECONDS * Net.TICK_HZ)
		_next_step = server.tick
		server.chat.say_bridge("Дрон проник на пиратский корабль. Управление с монитора дрона: клавиши движения.")
		_entered()
	elif inside():
		if dir != Net.DIR_NONE and server.tick >= _next_step:
			_next_step = server.tick + STEP_TICKS
			var o = server.enemy_crew.o
			var x: int = at % o.width + Net.DX[dir]
			var y: int = at / o.width + Net.DY[dir]
			var to: int = y * o.width + x
			if x >= 0 and x < o.width and y >= 0 and y < o.height and server.enemy_crew.passable(to):
				var was := room()
				at = to
				if room() != was:
					_entered()
		if server.tick >= _empty_at:
			_lost("Батарея дрона села: он потерян.")
		elif server.tick % Net.TICK_HZ == 0:
			_watch_for_pirates()
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func _entered() -> void:
	## It is in a room it may not have been in: what the room holds is known now.
	var r := room()
	if r >= 0:
		server.gunnery.reveal(r, "Дрон нашёл у пиратов")


func _watch_for_pirates() -> void:
	var crew = server.enemy_crew
	var r := room()
	for i in crew.count():
		if r >= 0 and crew.room_of(i) == r and not crew.hurt(i) and _rng.randf() < spotted:
			_lost("Пираты заметили дрона и сбили его.")
			return


func _blow(p: Player) -> void:
	var g = server.gunnery
	var r := room()
	var system: int = g.system_in(r)
	var said := PackedStringArray()
	g.enemy_hull = maxi(g.enemy_hull - 1, 0)
	if system >= 0 and system < g.systems.size() and g.systems[system] > 0 and system != Net.ESYS_CREW:
		g.systems[system] = maxi(g.systems[system] - BLAST, 0)
		said.append("%s: урон %d%s." % [Net.ESYS_NAMES[system], BLAST, ", выведено из строя" if g.systems[system] == 0 else ""])
		if system == Net.ESYS_SHIELDS and g.systems[system] == 0:
			g.enemy_shield = 0.0
	var hurt := g.crew_hit(r)
	if hurt != "":
		said.append(hurt)
	state = Net.DRONE_NONE
	at = -1
	server.chat.say_bridge("%s взрывает дрона внутри пиратского корабля.%s%s" % [p.name, "" if said.is_empty() else " " + " ".join(said), g._enemy_state()])
	g.settle()


func _lost(why: String) -> void:
	state = Net.DRONE_NONE
	at = -1
	dir = Net.DIR_NONE
	server.chat.say(why)


func _entry() -> int:
	## Where it gets in: the floor just inside the enemy's outer door (any floor if it has none).
	var o = server.enemy_crew.o
	for d in o.doors.size():
		if o.door_vent[d] != 1:
			continue
		var door: Vector2i = o.doors[d]
		for side: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var c: Vector2i = door + side
			if c.x >= 0 and c.y >= 0 and c.x < o.width and c.y < o.height and o.room_of[c.y * o.width + c.x] >= 0:
				return c.y * o.width + c.x
	return server.enemy_crew._any_floor()


func packet() -> PackedByteArray:
	var left := 0
	if inside():
		left = clampi(int(ceil(float(_empty_at - server.tick) / Net.TICK_HZ)), 0, 255)
	var coming := 0
	if state == Net.DRONE_FLYING:
		coming = clampi(int(ceil(float(_arrive - server.tick) / Net.TICK_HZ)), 0, 255)
	var cell := maxi(at, 0)
	return PackedByteArray([Net.S_DRONE, state, cell & 0xFF, cell >> 8, left, coming,
		mini(int(server.ship.store.get(Net.ITEM_DRONE, 0)), 255)])
