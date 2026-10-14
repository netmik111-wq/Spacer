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
			place_ship(argument)


func give(p: Player, item: int) -> void:
	## A thing into the hand (or a free slot), or onto the floor at the admin's feet.
	if not Items.INFO.has(item) or p.corpse:
		return
	if p.add(item, true):
		p.self_dirty = true
		return
	var cell := p.st.y * server.map.width + p.st.x
	var things: PackedByteArray = server.floor_things.get(cell, PackedByteArray())
	if things.is_empty():
		things.resize(Net.FLOOR_STACK)
	var at := things.find(Net.ITEM_NONE)
	if at < 0:
		server.chat.tell(p, "Некуда положить: руки, слоты и пол под ногами заняты.")
		return
	things[at] = item
	server.floor_things[cell] = things
	server.replication.floor_record(cell)


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


func place_ship(kind: int) -> void:
	## This sector gets a station, a trader or a derelict, and the ship is put
	## right by it (until the ship jumps: space itself is not changed).
	if kind != Sectors.STATION and kind != Sectors.TRADER and kind != Sectors.DERELICT:
		return
	if server.ship.jump_to != Net.NO_SECTOR or server.derelict.here:
		return
	var s := server.ship.sector
	server.sectors.kind[s] = kind
	server.sectors.reach[s] = Sectors.DOCK_RANGE
	server.ship.pos = server.sectors.spot[s]
	server.ship.dest = server.ship.pos
	server.ship.moving = false
	server.to_all(server.navigation.sectors_packet())
	server.to_all(server.ship.nav_packet())
	server.to_all(server.ship.helm_packet(server.tick))
