extends RefCounted
## (v97, the author's roadmap 3.2: "the teleporter as a late tech"; his v96 B4 A: a rare find with
## procedural places) Our teleporter: a crate (Gear.TELEPORT) found only in the vaults of derelicts made from
## pieces, installed into the ship's teleporter pad ('t', his T1 C: a machine of its own; Ship.teleporter).
## His T2-T4 answers (all A):
##   send   E at the pad (or the right-click menu there): after a TELEPORT_HUM hum whoever sent it, and up to two
##          armed bots told «К оружию» (or guards) within TELEPORT_REACH of the pad, stand on the ship alongside (a
##          pirate in a fight, a derelict, a wreck; never a rock), each in a room of their own. Shields do not stop it.
##   home   the menu on oneself over there; «Вернуть всех» at the pad brings everybody of ours back. Bots come
##          home by themselves once no foe is left there; a ship that leaves with ours aboard sends them home.
##   It needs the ship's power and TELEPORT_SECONDS between beams. Riders are never out of the world: the beam
##   is a hum, then a new place.
## Server only.

const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Player := preload("res://src/server/player.gd")

var server: GameServer
var ready_at: Array = []             # per ship of our fleet: the tick its teleporter may beam again
var hums: Array = []                 # beams on their way: {"go": tick, "ship": i, "who": Array[Player], "out": bool}
var went := {}                       # Player -> the ship of ours whose teleporter took them over
var _told := {}                      # Player -> the S_TELEPORT last sent to them


func setup(p_server: GameServer) -> void:
	server = p_server
	ready_at = []
	for i in server.fleet.size():
		ready_at.append(0)
	hums = []
	went = {}
	_told = {}


func has(i: int) -> bool:
	## Ship i of our fleet has a teleporter in its pad.
	return i >= 0 and i < server.fleet.ships.size() and server.fleet.ships[i].teleporter and _pad_front(i) >= 0


func _target() -> String:
	## "" while there is a ship alongside to beam onto, else why not.
	var d = server.derelict
	if not d.here or server.map.other == null or server.map.other_cells.is_empty():
		return "У нашего борта нет корабля: телепорту некуда отправлять."
	if d.kind == Net.OTHER_ROCK:
		return "Телепорт не высаживает на голый камень астероида."
	return ""


func _charged(i: int) -> String:
	if not has(i):
		return "Платформа телепорта пуста: телепорт — редкая находка в хранилищах брошенных кораблей." if _pad_front(i) >= 0 \
			else "На этом корабле нет платформы телепорта."
	if server.fleet.is_lost(i):
		return "Корабль мёртв: телепорт не работает."
	server.fleet.use(i)
	var on: bool = server.powered()
	server.fleet.use(0)
	if not on:
		return "Телепорт обесточен."
	for h: Dictionary in hums:
		if int(h["ship"]) == i:
			return "Телепорт уже гудит."
	if server.tick < int(ready_at[i]):
		return "Телепорт перезаряжается: ещё %d с." % ceili(float(int(ready_at[i]) - server.tick) / Net.TICK_HZ)
	return ""


func _pad_front(i: int) -> int:
	## The floor in front of ship i's teleporter pad (-1: none).
	for pad: int in server.map.teleporter:
		if maxi(server.map.fleet_of(pad), 0) == i:
			return int(server.map.teleporter[pad])
	return -1


func _near_pad(p: Player, front: int) -> bool:
	var w: int = server.map.width
	return front >= 0 and server.map.deck_of(p.st.y) == server.map.deck_of(front / w) \
		and maxi(absi(p.st.x - front % w), absi(p.st.y - front / w)) <= Gear.TELEPORT_REACH


func _ours(q: Player) -> bool:
	return q != null and not q.pirate and not q.ally and not q.corpse and not q.taken and not q.in_shuttle and q.cond == Net.COND_OK


func _over_there(q: Player) -> bool:
	return server.map.is_other(q.st.y * server.map.width + q.st.x)


# ---------------------------------------------------------------- asked

func asked(p: Player, action: int) -> void:
	## C_TELEPORT from a player.
	if not _ours(p):
		return
	match action:
		Net.TELE_SEND:
			var i: int = maxi(server.map.fleet_of(p.st.y * server.map.width + p.st.x), 0)
			var front := _pad_front(i)
			if not _near_pad(p, front):
				_tell(p, "Встаньте у платформы телепорта: он отправляет тех, кто рядом с ней.")
				return
			var why := _charged(i)
			if why == "":
				why = _target()
			if why != "":
				_tell(p, why)
				return
			server.usage.note(p, "teleport")
			_hum(i, _party(p, i, front), true)
		Net.TELE_HOME:
			if not _over_there(p):
				_tell(p, "Вы и так у себя на корабле.")
				return
			var i := _home_of(p)
			var why := _charged(i)
			if why != "":
				_tell(p, why)
				return
			_hum(i, [p], false)
		Net.TELE_ALL:
			var i: int = maxi(server.map.fleet_of(p.st.y * server.map.width + p.st.x), 0)
			if not _near_pad(p, _pad_front(i)):
				_tell(p, "Вернуть всех можно только от платформы телепорта.")
				return
			var why := _charged(i)
			if why != "":
				_tell(p, why)
				return
			var who: Array = []
			for q: Player in server.players:
				if _ours(q) and _over_there(q):
					who.append(q)
			if who.is_empty():
				_tell(p, "На том корабле никого из наших.")
				return
			_hum(i, who, false)


func _home_of(p: Player) -> int:
	## The ship of ours whose teleporter brings p home: the one that took them over, else their own, else any with one.
	var i: int = int(went.get(p, clampi(p.fleet_ship, 0, server.fleet.size() - 1)))
	if has(i):
		return i
	for k in server.fleet.size():
		if has(k):
			return k
	return i


func _party(p: Player, i: int, front: int) -> Array:
	## The sender and up to two armed bots told «К оружию» (or guards) near the pad.
	var who: Array = [p]
	for q: Player in server.players:
		if who.size() >= Gear.TELEPORT_PARTY:
			break
		if q == p or not _ours(q) or not q.bot or not (q.defends or q.job == Net.JOB_GUARD) or q.fleet_ship != i:
			continue
		if _near_pad(q, front) and server.defence.gun_slot(q) >= 0:
			who.append(q)
	return who


func _hum(i: int, who: Array, out: bool) -> void:
	hums.append({"go": server.tick + roundi(Gear.TELEPORT_HUM * Net.TICK_HZ), "ship": i, "who": who, "out": out})
	for q: Player in who:
		server.chat.sound(Net.SOUND_TELEPORT, q.st.x, q.st.y)
	var names := PackedStringArray()
	for q: Player in who:
		names.append(q.name)
	server.chat.say("Телепорт гудит: %s %s." % [", ".join(names), "на корабль у нашего борта" if out else "домой"])


# ---------------------------------------------------------------- every tick

func tick() -> void:
	for h: Dictionary in hums.duplicate():
		if server.tick >= int(h["go"]):
			hums.erase(h)
			_beam(h)
	_bots_home()
	var gone: Array = []
	for q: Player in went:
		if q == null or q.corpse or q.slot < 0 or q.slot >= server.players.size() or server.players[q.slot] != q or not _over_there(q):
			gone.append(q)
	for q: Player in gone:
		went.erase(q)
	for p: Player in server.players:
		if p == null or p.peer == null:
			continue
		var pkt := _packet(p)
		if _told.get(p, PackedByteArray()) != pkt:
			_told[p] = pkt
			p.peer.send(0, pkt, ENetPacketPeer.FLAG_RELIABLE)


func _beam(h: Dictionary) -> void:
	var i: int = h["ship"]
	var who: Array = (h["who"] as Array).filter(func(q: Player) -> bool: return _ours(q))
	server.fleet.use(i)
	var on: bool = server.powered()
	server.fleet.use(0)
	if not has(i) or not on:
		server.chat.say("Телепорт смолк: без энергии никого не отправить.")
		return
	if bool(h["out"]):
		if _target() != "":
			server.chat.say("Телепорт смолк: у нашего борта больше нет корабля.")
			return
		var front := _pad_front(i)
		who = who.filter(func(q: Player) -> bool: return _near_pad(q, front) and not _over_there(q))
		var spots := _landing(who.size())
		if spots.is_empty():
			return
		for k in who.size():
			var q: Player = who[k]
			_place(q, spots[mini(k, spots.size() - 1)])
			went[q] = i
		server.chat.say("Телепорт: наши на борту того корабля (%d)." % who.size())
	else:
		who = who.filter(func(q: Player) -> bool: return _over_there(q))
		var front := _pad_front(i)
		if front < 0 or who.is_empty():
			return
		for q: Player in who:
			_place(q, server.pods._free_near(front, q))
			went.erase(q)
		server.chat.say("Телепорт вернул домой: %d." % who.size())
	ready_at[i] = server.tick + roundi(Gear.TELEPORT_SECONDS * Net.TICK_HZ)


func _place(q: Player, cell: int) -> void:
	var map = server.map
	q.st.place(cell % map.width, cell / map.width)
	q.inputs.clear()
	q.self_dirty = true
	q.bot_plan_tick = -1000
	q.ai_goal = Vector2i(-1, -1)
	q.ai_target = -1
	q.dragging = -1
	server.chat.sound(Net.SOUND_TELEPORT, q.st.x, q.st.y)
	server.replication.sight_changed()


func _landing(n: int) -> Array:
	## Cells on the ship alongside, each in a room of its own as long as there are rooms.
	var map = server.map
	var rooms: Array = server.derelict._rooms()
	rooms.shuffle()
	var out: Array = []
	var taken := {}
	for pass_no in 2:
		for room: Array in rooms:
			if out.size() >= n:
				return out
			var free: Array = room.filter(func(c: int) -> bool:
				return not taken.has(c) and map.stair_to[c] < 0 and not server.pods._someone_at(c, null))
			if free.is_empty():
				continue
			var c: int = free[randi() % free.size()]
			taken[c] = true
			out.append(c)
	return out


func ship_leaves() -> void:
	## (my T2 pick) The ship alongside is going: its teleporter takes back whoever of ours it sent there.
	for q: Player in went.keys():
		if _ours(q) and _over_there(q):
			var front := _pad_front(int(went[q]))
			if front >= 0:
				_place(q, server.pods._free_near(front, q))
	went.clear()
	hums = hums.filter(func(h: Dictionary) -> bool: return not bool(h["out"]))


# ---------------------------------------------------------------- bots over there

func bot_think(p: Player) -> bool:
	## A bot our teleporter took over fights there; with no foe left aboard it waits for the way home.
	if not went.has(p) or not _over_there(p):
		return false
	var foe: Player = server.pods._nearest_pirate(p)
	var k: int = server.defence.gun_slot(p)
	if foe != null and k >= 0:
		p.hand = k
		p.doing = Net.DOING_FIGHT
		if p.ai_target < 0:
			p.ai_goal = Vector2i(foe.st.x, foe.st.y)
		server.pirates.think(p)
		return true
	if foe != null:
		return false
	p.st.dir = Net.DIR_NONE
	p.doing = Net.DOING_GOING
	return true


func _bots_home() -> void:
	## Bots over there with no foe left aboard go home with the next beam.
	if went.is_empty() or (server.tick % Net.TICK_HZ) != 0:
		return
	var by_ship := {}
	for q: Player in went:
		if q.bot and _ours(q) and _over_there(q) and server.pods._nearest_pirate(q) == null:
			var i: int = went[q]
			if not by_ship.has(i):
				by_ship[i] = []
			(by_ship[i] as Array).append(q)
	for i: int in by_ship:
		if _charged(i) == "":
			_hum(i, by_ship[i], false)


# ---------------------------------------------------------------- what clients are told

func _tell(p: Player, text: String) -> void:
	if not p.bot:
		server.chat.tell(p, text)


func _packet(p: Player) -> PackedByteArray:
	## S_TELEPORT: u8 TELE_NONE/READY/CHARGING/HUMMING for the teleporter that would serve them, u8 seconds to ready.
	var i: int
	if _over_there(p):
		i = _home_of(p)
	else:
		i = maxi(server.map.fleet_of(p.st.y * server.map.width + p.st.x), 0)
	var state := Net.TELE_NONE
	var secs := 0
	if has(i):
		state = Net.TELE_READY
		for h: Dictionary in hums:
			if int(h["ship"]) == i:
				state = Net.TELE_HUMMING
		if state == Net.TELE_READY and server.tick < int(ready_at[i]):
			state = Net.TELE_CHARGING
			secs = ceili(float(int(ready_at[i]) - server.tick) / Net.TICK_HZ)
	return PackedByteArray([Net.S_TELEPORT, state, clampi(secs, 0, 255)])
