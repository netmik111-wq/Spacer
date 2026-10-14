extends RefCounted
## The holomap monitors ('M' in the map, on the bridge and in the engine room):
## the whole ship at a glance, the air in every cell of it, the holes in its
## hull and the state of its doors (what is out of order every client knows
## already, from Net.S_DEVICES). Server only.
##
## A client sees the air only around itself, so the holomap is sent on its
## own (Net.S_HOLO) to those who stand at a monitor and asked for it, every
## SEND_EVERY ticks, until they step away, are knocked out or the power goes.
## It works only with power, like every console. This is the one place the
## game shows the air of rooms the player is not in: the author asked for it
## as a monitor one has to go to.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

const SEND_EVERY := 10               # ticks: twice a second

var server: GameServer
var watching := {}                   # player slot -> true: those the holomap is sent to
var cells := PackedInt32Array()      # the cells of our ship's floor, in the order their air is sent


func setup(p_server: GameServer) -> void:
	server = p_server
	watching.clear()
	cells = PackedInt32Array()
	for c in server.map.base_walk.size():
		if server.map.on_ship(c):
			cells.append(c)


func asked(p: Player, on: bool) -> void:
	if on and server.systems.at_console(p, server.map.holo):
		watching[p.slot] = true
		_send(p)
	else:
		watching.erase(p.slot)


func tick() -> void:
	if watching.is_empty() or server.tick % SEND_EVERY != 0:
		return
	for slot: int in watching.keys():
		var p: Player = server.players[slot] if slot < server.players.size() else null
		if p == null or p.peer == null or not server.systems.at_console(p, server.map.holo):
			watching.erase(slot)
			continue
		_send(p)


func _send(p: Player) -> void:
	if p.peer != null:
		p.peer.send(0, packet(), ENetPacketPeer.FLAG_RELIABLE)


func packet() -> PackedByteArray:
	var map := server.map
	var out := PackedByteArray([Net.S_HOLO, server.ship.id & 0xFF, server.ship.id >> 8])
	var o := out.size()
	out.resize(o + 2 + cells.size())
	out.encode_u16(o, cells.size())
	for i in cells.size():
		out[o + 2 + i] = clampi(roundi(server.air.air[cells[i]] * Net.AIR_FULL), 0, Net.AIR_FULL)
	var holes := PackedInt32Array()
	for c: int in server.air.holes.keys():
		if not map.is_other(c):
			holes.append(c)
	o = out.size()
	out.resize(o + 2 + holes.size() * 2)
	out.encode_u16(o, holes.size())
	for i in holes.size():
		out.encode_u16(o + 2 + i * 2, holes[i])
	out.append(map.other_first_door)
	for d in map.other_first_door:
		var open := 0 if server.doors.is_shut(d) else 1
		out.append(open | (server.doors.flags(d) << 1))
	return out
