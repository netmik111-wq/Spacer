extends RefCounted
## The admin panel's commands (Net.ADMIN_*): the host and the players the host
## made admins can give themselves things, heal, kill and move people, mend
## the ship, fill it with air and supplies and call events, to try things out.
## The hosting player's game proves itself with the server's secret text; the
## others are admins by name (kept in the campaign's save).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Gear := preload("res://src/shared/gear.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Hulls := preload("res://src/shared/hulls.gd")

const BOTS_MOST := 16                # (v60.1) the admin panel adds bots up to this many

var server: GameServer
var names := {}                      # players made admins by the host: name -> true


func setup(p_server: GameServer) -> void:
	server = p_server
	names.clear()


func joined(p: Player) -> void:
	## A player who comes aboard under the name of an admin is one again.
	p.admin = names.has(p.name)


func asked(p: Player, pkt: PackedByteArray) -> void:
	if pkt.size() < 5:
		return
	var command := pkt[1]
	var argument := pkt[2]
	var target: Player = null
	var id := pkt.decode_u16(3)
	if id < server.players.size():
		target = server.players[id]
	if server.shutdown_token != "" and pkt.slice(5).get_string_from_utf8() == server.shutdown_token:
		if not p.host:
			p.host = true
			p.admin = true
	if not p.admin:
		return
	match command:
		Net.ADMIN_HELLO:
			pass
		Net.ADMIN_BREACH:
			# the wall the player faces, if it can be breached; otherwise the nearest that can
			var ahead := server.map.cell_ahead(p.st.x, p.st.y, p.st.facing)
			if not (ahead >= 0 and server.map.hull.has(ahead) and server.systems.breach(ahead)):
				server.systems.breach_near(p.st.x, p.st.y)
		Net.ADMIN_SEAL:
			server.systems.seal_all()
		Net.ADMIN_EVENT:
			server.director.fire(argument)
		Net.ADMIN_AUTO:
			server.director.auto = argument != 0
			server.chat.say("Ивентер: события идут сами." if server.director.auto else "Ивентер: события только вручную.")
		Net.ADMIN_SAVE:
			if server.save_path == "":
				server.chat.tell(p, "Эта игра запущена без сохранения.")
			elif server.over != Net.OVER_NONE:
				server.chat.tell(p, "Кампания окончена, сохранять нечего.")
			else:
				server.chat.say("Кампания сохранена." if server.save_campaign() else "Не удалось сохранить кампанию.")
		Net.ADMIN_GIVE:
			give(p, argument)
		Net.ADMIN_HEAL:
			if target != null:
				heal(target)
		Net.ADMIN_KILL:
			if target != null and not target.corpse and target.cond != Net.COND_DEAD:
				server.combat.hurt(target, 1000, null)
		Net.ADMIN_GOTO:
			if target != null and target != p:
				_put_beside(p, target)
		Net.ADMIN_BRING:
			if target != null and target != p:
				_put_beside(target, p)
		Net.ADMIN_GRANT:
			if p.host and target != null and target.peer != null and not target.host:
				target.admin = argument != 0
				if target.admin:
					names[target.name] = true
				else:
					names.erase(target.name)
				server.chat.tell(target, "Вы теперь администратор: панель открывается клавишей из настроек или из меню (Esc)." if target.admin
					else "Вы больше не администратор.")
				server.chat.tell(p, "%s %s." % [target.name, "теперь администратор" if target.admin else "больше не администратор"])
		Net.ADMIN_JOB:
			if target != null and not target.corpse and not target.pirate and argument < Net.JOBS:
				target.take_job(argument)
				server.crew.announce_join(target, null)       # everybody learns the new job from the roster
		Net.ADMIN_REPAIR:
			repair_all()
		Net.ADMIN_AIR:
			for i in server.map.base_walk.size():
				if server.map.base_walk[i] == 1:
					server.air.air[i] = 1.0
			server.ship.store_air = Net.STORE_AIR_FULL
			server.air.wake()
			server.chat.say("Администратор: воздух во всём корабле восстановлен.")
		Net.ADMIN_RESTOCK:
			for item in Items.kept_in_locker():
				# the ship's weapons: one of each in the cargo; rockets: ten (for trying the guns out)
				var least := Items.stock(item) if not Items.cargo(item) else (1 if Items.price(item) >= 20 else 10)
				server.ship.store[item] = maxi(int(server.ship.store.get(item, 0)), least)
			server.chat.say("Администратор: шкаф снабжения пополнен (в трюме по одному корабельному орудию каждого вида и ракеты).")
		Net.ADMIN_CREDITS:
			server.ship.credits = mini(server.ship.credits + Net.ADMIN_CREDITS_GIVEN, 60000)
		Net.ADMIN_HULL:
			server.ship.hull = Net.HULL_MAX
		Net.ADMIN_RESERVE:
			server.reserve = mini(server.reserve + 1, Net.RESERVE_MAX)
		Net.ADMIN_PIRATE:
			var at := Vector2i(p.st.x, p.st.y)
			var ahead := server.map.cell_ahead(p.st.x, p.st.y, p.st.facing)
			if ahead >= 0 and server.map.walkable(ahead % server.map.width, ahead / server.map.width):
				at = Vector2i(ahead % server.map.width, ahead / server.map.width)
			server.pirates.spawn(at.x, at.y, argument != 0)
		Net.ADMIN_PLACE:
			place_ship(argument % Net.ADMIN_TRADER_DEAL, argument / Net.ADMIN_TRADER_DEAL - 1)
		Net.ADMIN_STORE:
			store(argument)
		Net.ADMIN_FIT:
			fit(argument)
		Net.ADMIN_CHARGE:
			charge_all()
		Net.ADMIN_SKILLS:
			if target != null and not target.corpse and not target.pirate:
				target.skills.fill(Net.SKILL_MAX)
		Net.ADMIN_BOTS:
			bots(argument != 0)
		Net.ADMIN_FIGHT:
			fight(argument / 16, (argument / 2) % 8, argument % 2 == 1)


func give(p: Player, item: int) -> void:
	## A thing into the hand (or a free slot), or onto the floor at the admin's feet.
	## (v60.1) Cargo that is never carried (rockets, shells, probes, parts) goes into the locker.
	if not Items.INFO.has(item) or p.corpse:
		return
	if Items.cargo(item) and not Items.carried_gun(item):
		store(item)
		return
	if p.add(item, true):
		p.self_dirty = true
		return
	if not server.put_on_floor(p.st.y * server.map.width + p.st.x, item):
		server.chat.tell(p, "Некуда положить: руки, слоты и пол под ногами заняты.")


func heal(q: Player) -> void:
	## Whole again: health, wounds and the suit's tank; the dead come back to life
	## where they lie (a body left behind is not a player and stays a body).
	if q.corpse:
		return
	var was_dead := q.cond == Net.COND_DEAD
	var was_down := q.cond != Net.COND_OK
	q.health = Net.HEALTH_FULL
	q.wounds = 0.0
	q.treating = -1
	if q.has_suit():
		q.tank = 1.0
	if was_down:
		for r: Player in server.players:
			if r == null:
				continue
			if r.dragging == q.slot:
				server.looting.let_go(r)
			if r.searching == q.slot:
				server.looting.stop_search(r)
		q.cond = Net.COND_OK
		q.st.down = false
		q.st.dir = Net.DIR_NONE
		q.inputs.clear()
	q.self_dirty = true
	server.dead_names.erase(q.name)
	if was_dead:
		server.chat.say("%s возвращается к жизни." % q.name)
	elif was_down:
		server.chat.say("%s приходит в себя." % q.name)


func _put_beside(who: Player, by: Player) -> void:
	## Puts a character next to another one (in the same cell, if no other is free).
	var at := Vector2i(by.st.x, by.st.y)
	for d: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		var x := by.st.x + d.x
		var y := by.st.y + d.y
		if server.map.walkable(x, y) and server.map.door_at(x, y) < 0:
			at = Vector2i(x, y)
			break
	if who.dragging >= 0:
		server.looting.let_go(who)
	if who.dragged_by >= 0 and who.dragged_by < server.players.size() and server.players[who.dragged_by] != null:
		server.looting.let_go(server.players[who.dragged_by])
	who.st.place(at.x, at.y)
	who.inputs.clear()
	who.self_dirty = true


func repair_all() -> void:
	## Every hole closed, every machine and door mended, the power back.
	server.systems.seal_all()
	if not server.ship.broken.is_empty():
		server.ship.broken.clear()
		server.to_all(server.ship.devices_packet())
	for d in server.map.other_first_door:
		if server.doors.jammed[d] == 1 or server.doors.faulty[d] == 1:
			server.doors.jammed[d] = 0
			server.doors.faulty[d] = 0
			server.door_hold[d] = server.tick
	server.ship.power_out_until = 0
	server.systems.power_changed()
	server.chat.say("Администратор: корабль полностью исправлен.")


func place_ship(kind: int, deal: int = -1) -> void:
	## This sector gets a station, a trader or a derelict, and the ship is put
	## right by it (until the ship jumps: space itself is not changed). (v60.1)
	## A trader may be of the kind asked for (Sectors.DEAL_*; -1: as the sector has it).
	if kind != Sectors.STATION and kind != Sectors.TRADER and kind != Sectors.DERELICT:
		return
	if server.ship.jump_to != Net.NO_SECTOR or server.derelict.here:
		return
	var s := server.ship.sector
	server.sectors.kind[s] = kind
	if kind == Sectors.TRADER and deal >= 0 and deal < Sectors.DEAL_NAMES.size() and server.sectors.deal.size() > s:
		server.sectors.deal[s] = deal
	server.sectors.reach[s] = Sectors.DOCK_RANGE
	server.ship.pos = server.sectors.spot[s]
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	server.to_all(server.navigation.sectors_packet())
	server.to_all(server.ship.nav_packet())
	server.to_all(server.ship.helm_packet(server.tick))


func store(item: int) -> void:
	## (v60.1) A thing into the supply locker (counted as the thing it is a state of).
	if not Items.INFO.has(item):
		return
	var kind := Items.kind_of(item)
	server.ship.store[kind] = int(server.ship.store.get(kind, 0)) + 1
	server.supplies.tell_store()


func fit(what: int) -> void:
	## (v60.1) Gear in place at once, without an engineer's work (tests): a system's
	## tier or a module into the bay (what was there is gone), the built-in one back,
	## or the bay emptied.
	var ship = server.ship
	if what == Net.ADMIN_FIT_CLEAR_BAY:
		ship.modules.fill(Gear.NONE)
	elif what >= Net.ADMIN_FIT_BUILT_IN and what < Net.ADMIN_FIT_BUILT_IN + Gear.SYSTEMS:
		ship.gear[what - Net.ADMIN_FIT_BUILT_IN] = 1
	elif what > Gear.NONE and what < Gear.COUNT:
		if Gear.system_of(what) >= 0:
			ship.gear[Gear.system_of(what)] = Gear.tier(what)
		elif not ship.modules.has(what):
			var at: int = server.outfit._slot_for(what)
			ship.modules[maxi(at, 0)] = what
	else:
		return
	server.outfit.refresh()
	server.outfit.tick()
	server.chat.say("Администратор: снаряжение корабля изменено.")


func charge_all() -> void:
	## (v60.1) The shield full, every armed gun charged, the jump drive and the phase drive ready.
	var ship = server.ship
	if ship.shield_on:
		ship.shield = Weapons.SHIELD_FULL
	for i in ship.armed.size():
		if ship.armed[i] == 1 and i < server.gunnery.charge.size():
			server.gunnery.charge[i] = 1.0
	ship.drive_ready = server.tick
	ship.phase_ready = server.tick
	server.to_all(ship.helm_packet(server.tick))
	server.outfit.tick()


func bots(more: bool) -> void:
	## (v60.1) The crew kept one bot bigger or smaller (until the server stops).
	if more:
		if server.crew_size >= BOTS_MOST + 1:
			return
		server.crew_size += 1
		server.crew.add_bot()
		return
	for i in range(server.players.size() - 1, -1, -1):
		var q: Player = server.players[i]
		if q == null or not q.bot or q.corpse or q.dragged_by >= 0:
			continue
		for at in Net.SLOTS:
			server.supplies._put_back(q, at)
		server.crew.remove(q)
		server.crew_size = maxi(server.crew_size - 1, 1)
		server.supplies.tell_store()
		server.chat.say("Администратор: %s покидает корабль." % q.name)
		return


func fight(klass: int, temper: int, at_range: bool) -> void:
	## (v60.1) A pirate ship of the class and temper asked for comes up now (if one may).
	if not Hulls.CLASSES.has(klass) or Hulls.CLASSES[klass].has("boss"):
		return
	server.shipyard.force_class = klass
	server.shipyard.force_temper = temper if Hulls.TEMPERS.has(temper) else -1
	if not server.derelict.pirates_come(server.director._party(), at_range):
		server.chat.say("Администратор: пиратский корабль сейчас подойти не может (рядом другой корабль или кто-то снаружи).")
	server.shipyard.force_class = -1
	server.shipyard.force_temper = -1
