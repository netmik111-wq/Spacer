extends RefCounted
## Where the ship is and where it goes: steering inside a sector, jumps between
## sectors, and what the ship finds on arriving.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func sector_kind() -> int:
	return server.sectors.kind[server.ship.sector]


func danger_kind() -> int:
	## What the director should treat the ship's surroundings as: a meteor
	## stream (v61: or an ion storm) is only dangerous while the ship is inside it.
	if (sector_kind() == Sectors.METEORS or sector_kind() == Sectors.ION_STORM) and not server.ship.in_reach:
		return Sectors.EMPTY
	return sector_kind()


func helm_asked(p: Player, go: bool, to: Vector2) -> void:
	## A player at the ship's controls sets a course inside the sector, or stops the ship.
	if not server.systems.at_console(p, server.map.helm) or server.ship.jump_to != Net.NO_SECTOR or server.engine_down():
		return
	var held := server.derelict.holds_ship()
	if go and held != "":
		server.chat.say(held)
		return
	server.ship.moving = go
	server.ship.dest = to.clamp(Vector2.ZERO, Vector2(Sectors.SPAN, Sectors.SPAN)) if go else server.ship.pos
	server.to_all(server.ship.helm_packet(server.tick))


func update() -> void:
	if server.ship.moving:
		server.ship.pos = server.ship.pos.move_toward(server.ship.dest, Sectors.SHIP_SPEED * Net.TICK_SEC)
		if server.ship.pos.is_equal_approx(server.ship.dest):
			server.ship.moving = false
			server.to_all(server.ship.helm_packet(server.tick))
	var now_in := server.sectors.within_reach(server.ship.sector, server.ship.pos)
	if now_in == server.ship.in_reach:
		return
	server.ship.in_reach = now_in
	match sector_kind():
		Sectors.METEORS:
			server.chat.say("Корабль вошёл в метеорный поток." if now_in else "Корабль вышел из метеорного потока.")
			server.director.surroundings_changed()
		Sectors.ION_STORM:
			server.hazards.storm_changed(now_in)
			server.director.surroundings_changed()
		Sectors.STATION:
			if now_in:
				server.air.refill()
				server.ship.store_air = Net.STORE_AIR_FULL
				var topped := server.ship.fuel() < Net.STATION_FUEL
				if topped:
					server.ship.store[Net.ITEM_FUEL] = Net.STATION_FUEL
				var patched := server.ship.hull < Net.HULL_MAX
				server.ship.hull = Net.HULL_MAX
				server.supplies.tell_store()
				server.chat.say("Стыковка со станцией снабжения. Воздух в отсеках и запас воздушной установки восполнены%s%s." %
					[", топлива в шкафу теперь %d канистры" % Net.STATION_FUEL if topped else "",
					", обшивка залатана" if patched else ""])
		Sectors.TRADER:
			if now_in:
				server.chat.say("Торговец на связи. Покупки делаются у шкафа снабжения на нижней палубе.")


func sectors_packet() -> PackedByteArray:
	var out := PackedByteArray([Net.S_SECTORS])
	out.append_array(server.sectors.pack())
	return out


func tell_nav() -> void:
	var msg := server.ship.nav_packet()
	for q: Player in server.players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func cannot_jump() -> bool:
	## (v54) Is the way out by jump closed: the engine out, no fuel, or every
	## sector console broken? (Pirates who see us so, with our guns silent, board.)
	if server.engine_down() or server.ship.fuel() <= 0:
		return true
	for cell: int in server.map.chart.keys():
		if not server.ship.broken.has(cell):
			return false
	return true


func jump_asked(p: Player, target: int) -> void:
	## A player at the sector console asks for a jump.
	if not server.systems.at_console(p, server.map.chart) or server.ship.jump_to != Net.NO_SECTOR or server.tick < server.ship.drive_ready or server.engine_down() or server.over != Net.OVER_NONE:
		return
	if target >= server.sectors.count or not server.sectors.linked(server.ship.sector, target):
		return
	if server.ship.fuel() < 1:
		server.chat.say("Прыгнуть не на чем: в шкафу снабжения нет топлива.")
		return
	var held := server.derelict.holds_ship()
	if held == "":
		held = server.flagship.holds_jump()
	if held != "":
		server.chat.say(held)
		return
	start_jump(target, p.name)


func start_jump(target: int, by: String) -> void:
	server.ship.jump_to = target
	var charge := roundi(Net.JUMP_TICKS * server.outfit.jump_share())      # (v59) a better engine charges it quicker
	server.ship.jump_tick = server.tick + charge
	tell_nav()
	server.chat.say("%s задаёт курс: %s. Прыжок через %d секунд." % [by, server.sectors.describe(target), charge / Net.TICK_HZ])
	if server.ship.moving and not server.ship.pos.is_equal_approx(server.ship.dest):
		# The ship is leaving for the jump: the course it was on no longer counts.
		# It coasts straight on, on its inertia, until the jump takes it.
		var way := (server.ship.dest - server.ship.pos).normalized()
		var room := 1000.0                   # how far it can go that way before the edge of the sector
		if way.x > 0.0:
			room = minf(room, (Sectors.SPAN - server.ship.pos.x) / way.x)
		elif way.x < 0.0:
			room = minf(room, -server.ship.pos.x / way.x)
		if way.y > 0.0:
			room = minf(room, (Sectors.SPAN - server.ship.pos.y) / way.y)
		elif way.y < 0.0:
			room = minf(room, -server.ship.pos.y / way.y)
		server.ship.dest = (server.ship.pos + way * room).clamp(Vector2.ZERO, Vector2(Sectors.SPAN, Sectors.SPAN)).round()
		server.to_all(server.ship.helm_packet(server.tick))


func update_jump() -> void:
	if server.ship.jump_to == Net.NO_SECTOR or server.tick < server.ship.jump_tick:
		return
	if server.derelict.holds_ship() != "":
		# somebody went outside while the drive was charging: the ship does not leave them
		server.ship.jump_to = Net.NO_SECTOR
		tell_nav()
		server.chat.say("Прыжок отменён: %s" % server.derelict.holds_ship().to_lower())
		return
	if server.ship.fuel() < 1:
		# somebody took the last can out of the locker while the drive was charging
		server.ship.jump_to = Net.NO_SECTOR
		tell_nav()
		server.chat.say("Прыжок сорван: в шкафу снабжения не осталось топлива.")
		return
	if server.outfit.free_fuel() > 0.0 and server.rng.randf() < server.outfit.free_fuel():
		server.chat.say("Двигатель взял прыжок без топлива: канистра цела.")   # (v59) a better engine is thriftier
	else:
		server.ship.store[Net.ITEM_FUEL] = server.ship.fuel() - 1      # the jump burns one can
	server.supplies.tell_store()
	# The ship is somewhere else now: the chart is drawn anew around the new
	# sector, which is how space goes on for ever without being kept anywhere.
	var arrived: Vector2i = server.sectors.cell[server.ship.jump_to]
	server.ship.jump_to = Net.NO_SECTOR
	server.ship.drive_ready = server.tick + roundi(Net.DRIVE_REST_TICKS * server.outfit.jump_share())
	server.jumps += 1
	if not server.been.has(Sectors.key(arrived)):
		server.ship.credits += Net.EXPLORE_REWARD
		server.chat.say("За разведку нового сектора начислено %d кредитов." % Net.EXPLORE_REWARD)
	server.been[Sectors.key(arrived)] = true
	server.sectors.build(server.space_seed, arrived, server.been)
	server.ship.sector = server.sectors.here
	server.farthest = maxi(server.farthest, server.sectors.far_from_start(server.ship.sector))
	server.save_campaign()
	server.to_all(sectors_packet())
	server.ship.pos = server.sectors.entry[server.ship.sector]
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	server.ship.in_reach = server.sectors.within_reach(server.ship.sector, server.ship.pos)
	tell_nav()
	server.to_all(server.ship.helm_packet(server.tick))
	match sector_kind():
		Sectors.METEORS:
			server.chat.say("Сектор %s. Корабль внутри потока: уйти можно своим ходом с пульта управления или прыжком." % server.sectors.describe(server.ship.sector))
		Sectors.ION_STORM:
			server.chat.say("Сектор %s. Корабль внутри ионного шторма: реактор даёт половину энергии, разряды выбивают орудия, щит и СМЭС. Уйти можно своим ходом или прыжком." % server.sectors.describe(server.ship.sector))
			server.hazards.storm_changed(server.ship.in_reach, true)
		Sectors.TRADER:
			server.chat.say("Сектор %s. Торговец где-то рядом: подойдите к нему." % server.sectors.describe(server.ship.sector))
		Sectors.STATION:
			server.chat.say("Сектор %s. Подойдите к станции, чтобы восполнить воздух." % server.sectors.describe(server.ship.sector))
		_:
			server.chat.say("Сектор %s." % server.sectors.describe(server.ship.sector))
	server.director.entered_sector()
