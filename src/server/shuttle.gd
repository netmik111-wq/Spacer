extends RefCounted
## (v86, the author's N1: "a small shuttle for up to 4 people, and a dock deck with a holographic force
## field that keeps the air in") The fleet's one shuttle. Each ship of our fleet has a hangar: a room with
## a force field in its outer wall ('F', air-tight and see-through) and the dock console beside it ('V').
## The shuttle waits outside one hangar's field; at its console a person gets in (E, then «Сесть») or calls
## it over when it stands empty at the other ship. Whoever is aboard flies it to the other ship's hangar
## (Net.SHUTTLE_SECONDS) and everyone steps out there.
##
## The shuttle is no part of the grid: its passengers are out of the world while aboard (Player.in_shuttle:
## nobody sees, hits or hears them, they neither walk nor breathe the ship's air). At the take-off they are
## put at the far hangar already, so their view is there to see the shuttle come in. Bots never use it
## (the author's N4: bots work only aboard their own ship).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

var server: GameServer
var docks: Array = []                # per ship of our fleet: ShipMap.shuttle_docks()
var at := -1                         # the dock it stands at or set off from (-1: the fleet has no shuttle)
var to := -1                         # the dock it flies to (-1: it stands)
var left_at := 0                     # the tick it set off
var riders: Array[Player] = []
var _told := {}                      # Player -> the packet last sent to them


func setup(p_server: GameServer) -> void:
	server = p_server
	docks = server.map.shuttle_docks()
	at = 0 if works() else -1
	to = -1
	riders.clear()
	_told = {}


func works() -> bool:
	## Is there a shuttle: two ships or more, each with a hangar?
	if docks.size() < 2:
		return false
	for d: Dictionary in docks:
		if d.is_empty():
			return false
	return true


func flying() -> bool:
	return at >= 0 and to >= 0


func dock_at(p: Player) -> int:
	## The dock whose console that player stands at, facing it (-1: none).
	if at < 0 or p == null or p.cond != Net.COND_OK or p.concussed > 0:
		return -1
	var ahead: int = server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	for i in docks.size():
		if int((docks[i] as Dictionary).get("console", -1)) == ahead:
			return i
	return -1


func asked(p: Player, action: int, arg: int) -> void:
	## Net.C_SHUTTLE from a player.
	if at < 0 or p == null or p.bot or p.pirate or p.corpse:
		return
	if action == Net.SHUTTLE_FLY or action == Net.SHUTTLE_LEAVE:
		if not riders.has(p) or flying():
			return
		if action == Net.SHUTTLE_LEAVE:
			_step_out(p, at)
			riders.erase(p)
			return
		if arg < 0 or arg >= docks.size() or arg == at:
			return
		_take_off(arg)
		return
	var here := dock_at(p)
	if here < 0 or riders.has(p):
		return
	if action == Net.SHUTTLE_BOARD:
		if flying() or at != here:
			server.chat.tell(p, "Челнока здесь нет: вызовите его.")
		elif riders.size() >= Net.SHUTTLE_SEATS:
			server.chat.tell(p, "В челноке нет мест: в нём %d человека." % Net.SHUTTLE_SEATS)
		elif p.dragging >= 0 or p.dragged_by >= 0:
			server.chat.tell(p, "С ношей в челнок не сесть.")
		else:
			p.in_shuttle = true
			p.inputs.clear()
			p.st.dir = 0
			p.using = false
			riders.append(p)
			server.usage.note(p, "shuttle")
			server.chat.sound(Net.SOUND_DOOR, p.st.x, p.st.y)
			server.replication.sight_changed()
	elif action == Net.SHUTTLE_CALL:
		if flying() or at == here:
			return
		if not riders.is_empty():
			server.chat.tell(p, "Челнок стоит у корабля %s с людьми: пусть летят или выйдут." % server.fleet.name_of(at))
			return
		_take_off(here)
		server.chat.tell(p, "Челнок вылетел к вам: %d с." % roundi(Net.SHUTTLE_SECONDS))


func _take_off(dest: int) -> void:
	to = dest
	left_at = server.tick
	var front: int = int((docks[dest] as Dictionary)["front"])
	for q: Player in riders:
		# (they are out of the world already: put at the far hangar now, their view goes along)
		q.st.place(front % server.map.width, front / server.map.width)
		q.self_dirty = true
	for q: Player in riders:
		server.chat.tell(q, "Челнок отходит от поля и летит к кораблю %s: %d с." % [server.fleet.name_of(dest), roundi(Net.SHUTTLE_SECONDS)])


func _front_of(i: int) -> Vector2i:
	## The floor in front of that dock's console.
	var c: int = int((docks[i] as Dictionary)["front"])
	return Vector2i(c % server.map.width, c / server.map.width)


func hold(p: Player) -> void:
	## A tick of a passenger: the inputs that come are taken and dropped (the client sends none aboard).
	var tick := server.tick
	while not p.inputs.is_empty() and int(p.inputs[0][0]) <= tick:
		var inp: Array = p.inputs.pop_front()
		p.last_seq = inp[2]
		p.self_dirty = true
	p.st.dir = 0


func tick() -> void:
	if at < 0:
		return
	for q: Player in riders.duplicate():
		if q == null or q.corpse or q.slot < 0 or q.slot >= server.players.size() or server.players[q.slot] != q:
			riders.erase(q)                  # left the game
		elif q.cond != Net.COND_OK and not flying():
			_step_out(q, at)
			riders.erase(q)
	if flying() and server.tick - left_at >= roundi(Net.SHUTTLE_SECONDS * Net.TICK_HZ):
		at = to
		to = -1
		for q: Player in riders:
			_step_out(q, at)
		riders.clear()
		server.chat.sound(Net.SOUND_DOOR, _front_of(at).x, _front_of(at).y)
	_tell()


func _step_out(p: Player, i: int) -> void:
	## Puts a passenger back into the world, on a free floor cell of that hangar.
	p.in_shuttle = false
	var map = server.map
	var front: int = int((docks[i] as Dictionary)["front"])
	var room: int = map.room_of[front]
	var spot := front
	var seen := {front: true}
	var queue: Array[int] = [front]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if _free(c, p):
			spot = c
			break
		for d: int in [1, -1, map.width, -map.width]:
			var n := c + d
			if n >= 0 and n < map.cells.size() and not seen.has(n) and map.walk[n] == 1 and map.door_of[n] < 0 \
					and (room < 0 or map.room_of[n] == room):
				seen[n] = true
				queue.append(n)
	p.st.place(spot % map.width, spot / map.width)
	p.st.facing = Net.DIR_DOWN if int((docks[i] as Dictionary)["out"]) < 0 else Net.DIR_UP
	p.inputs.clear()
	p.self_dirty = true
	server.replication.sight_changed()


func _free(c: int, p: Player) -> bool:
	var map = server.map
	if map.held.has(c):
		return false
	for q: Player in server.players:
		if q != null and q != p and not q.in_shuttle and not q.corpse and q.st.y * map.width + q.st.x == c:
			return false
	return true


func packet() -> PackedByteArray:
	var done := 0
	if flying():
		done = clampi(roundi(float(server.tick - left_at) / (Net.SHUTTLE_SECONDS * Net.TICK_HZ) * 255.0), 0, 255)
	var out := PackedByteArray([Net.S_SHUTTLE, 255 if at < 0 else at, 255 if to < 0 else to, done, riders.size()])
	for q: Player in riders:
		out.append(q.slot & 0xFF)
		out.append(q.slot >> 8)
	return out


func _tell() -> void:
	## Every client is told where the shuttle is (when that changed for them). While it flies the share
	## is told every few ticks only: the client moves it on between.
	if flying() and server.tick % 5 != 0 and server.tick - left_at > 1:
		return
	var pkt := packet()
	for p: Player in server.players:
		if p == null or p.peer == null:
			continue
		if _told.get(p, PackedByteArray()) != pkt:
			_told[p] = pkt
			p.peer.send(0, pkt, ENetPacketPeer.FLAG_RELIABLE)
