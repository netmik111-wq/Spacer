extends RefCounted
## Where the ship is and where it goes: steering inside a sector, jumps between
## sectors, and what the ship finds on arriving.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Gear := preload("res://src/shared/gear.gd")
const Items := preload("res://src/shared/items.gd")

const EXIT_CHARGE := 1.5             # (v64) the long jump out of a cluster charges this many times longer

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
	if go and server.ship.tank <= 0.0:
		server.chat.say("Баки пусты: своим ходом корабль не пойдёт. Залейте канистру топлива у двигателя.")   # (v67)
		return
	server.ship.moving = go
	server.ship.dest = to.clamp(Vector2.ZERO, Vector2(Sectors.SPAN, Sectors.SPAN)) if go else server.ship.pos
	server.to_all(server.ship.helm_packet(server.tick))


func update() -> void:
	if server.ship.moving and server.ship.jump_to == Net.NO_SECTOR and server.tick % 10 == 0 and server.derelict.someone_outside():
		# (v80, the author's note: "if people are outside they are left behind and die") somebody went out
		# while the ship was flying in the system: it stops for them
		server.ship.moving = false
		server.ship.dest = server.ship.pos
		server.to_all(server.ship.helm_packet(server.tick))
		server.chat.say("Корабль остановлен. " + server.derelict.holds_ship())
	if server.ship.moving:
		var was := server.ship.pos
		server.ship.pos = server.ship.pos.move_toward(server.ship.dest, Sectors.SHIP_SPEED * Net.TICK_SEC)
		if server.ship.jump_to == Net.NO_SECTOR:
			# (v67, the author's R3) flying inside a system burns fuel by the distance (not coasting into a jump)
			server.ship.tank = maxf(server.ship.tank - was.distance_to(server.ship.pos) * Net.FLIGHT_FUEL, 0.0)
			if server.ship.tank <= 0.0:
				server.ship.dest = server.ship.pos
				server.chat.say("Баки опустели: корабль лёг в дрейф. Залейте канистру топлива у двигателя.")
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
				var topped := server.ship.tank < Net.STATION_FUEL
				if topped:
					server.ship.tank = Net.STATION_FUEL
				var patched := server.ship.hull < server.ship.hull_max
				server.ship.hull = server.ship.hull_max
				server.supplies.tell_store()
				server.chat.say("Стыковка со станцией снабжения. Воздух в отсеках и запас воздушной установки восполнены%s%s." %
					[", топлива в баке теперь %d единиц" % Net.STATION_FUEL if topped else "",
					", обшивка залатана" if patched else ""])
				server.chat.say("Станция продаёт охранных роботов%s: покупки у шкафа снабжения." % (
					" и расширитель модульной стойки" if server.ship.modules.size() < Gear.MODULE_SLOTS_MAX else ""))
		Sectors.TRADER:
			if now_in:
				server.chat.say("Торговец на связи. Покупки делаются у шкафа снабжения на нижней палубе.")
				var w: PackedByteArray = server.supplies.wanted()
				if w.size() == 2:
					server.chat.say("Торговец ищет: %s и %s. За них он платит в полтора раза дороже обычного." % [
						Items.name_of(w[0]).to_lower(), Items.name_of(w[1]).to_lower()])


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
	if server.engine_down() or not server.ship.can_jump():
		return true
	for cell: int in server.map.chart.keys():
		if not server.ship.broken.has(cell):
			return false
	return true


func jump_asked(p: Player, target: int) -> void:
	## A player at the sector console asks for a jump.
	if not server.systems.at_console(p, server.map.chart) or server.ship.jump_to != Net.NO_SECTOR or server.tick < server.ship.drive_ready or server.engine_down() or server.over != Net.OVER_NONE:
		return
	if target == Sectors.EXIT_JUMP:
		var why: String = server.road.can_leave()     # (v64) the long jump out of the cluster
		if why != "":
			server.chat.say(why)
			return
	elif target >= server.sectors.count or not server.sectors.linked(server.ship.sector, target):
		return
	if not server.ship.can_jump(target == Sectors.EXIT_JUMP):
		server.chat.say("Прыгнуть не на чем: для прыжка нужно %d единиц топлива в баке, а там %d. Залейте канистры у двигателя." % [
			server.outfit.jump_fuel(target == Sectors.EXIT_JUMP), floori(server.ship.tank)])
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
	if target == Sectors.EXIT_JUMP:
		charge = roundi(charge * EXIT_CHARGE)  # (v64) the long jump takes longer to charge
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
	var long_jump := server.ship.jump_to == Sectors.EXIT_JUMP
	var arrived: Vector2i = server.sectors.cell[server.ship.jump_to] if not long_jump else Vector2i.ZERO
	var burn: int = server.outfit.jump_fuel(long_jump)
	if not server.ship.can_jump(long_jump):
		# the tank ran low while the drive was charging
		server.ship.jump_to = Net.NO_SECTOR
		tell_nav()
		server.chat.say("Прыжок сорван: в баке не хватает топлива.")
		return
	if long_jump and server.road.can_leave() != "":
		server.ship.jump_to = Net.NO_SECTOR
		tell_nav()
		server.chat.say("Прыжок сорван: %s" % server.road.can_leave().to_lower())
		return
	server.gunnery.parting_volley()          # (v67) running from a fight costs a volley
	if server.over != Net.OVER_NONE:
		server.ship.jump_to = Net.NO_SECTOR
		tell_nav()
		return
	server.ship.tank = maxf(server.ship.tank - burn, 0.0)          # (v67) by the engine's tier; the long jump twice
	server.supplies.tell_store()
	server.ship.jump_to = Net.NO_SECTOR
	server.ship.drive_ready = server.tick + roundi(Net.DRIVE_REST_TICKS * server.outfit.jump_share())
	server.jumps += 1
	server.outfit.jumped()                   # (v62) the welding drone
	server.salvage.jumped()                  # (v67) what floats outside stays behind
	if long_jump:
		server.road.next_cluster(server.sectors.exit_of(server.ship.sector))   # (v64) into the next cluster
		landed()
		return
	var target: int = server.sectors.cell.find(arrived)
	if not server.been.has(Sectors.key(arrived)) and Net.EXPLORE_REWARD > 0:
		server.ship.credits += Net.EXPLORE_REWARD
		server.chat.say("За разведку нового сектора начислено %d кредитов." % Net.EXPLORE_REWARD)
	server.been[Sectors.key(arrived)] = true
	server.sectors.visited[target] = 1
	server.ship.sector = target
	server.sectors.here = target
	landed()


func landed() -> void:
	## The ship has come out of a jump into server.sectors.here: everything that follows.
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
	server.garden.jumped()               # (v63) the crew eat
	server.story.entered_sector()
