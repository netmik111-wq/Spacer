extends RefCounted
## Things in the hands and on the floor: picking up, putting down, switching a
## flashlight, putting clothes on and taking them off, the suit's oxygen supply.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func _lying_in(cell: int) -> bool:
	for q: Player in server.players:
		if q != null and q.cond != Net.COND_OK and q.st.y * server.map.width + q.st.x == cell:
			return true
	return false


func pick_up(p: Player) -> bool:
	## Picks up the top thing lying in the cell in front, or else in its own cell:
	## into the hand if the hand is free. Somebody lying there is searched instead
	## (the client asks for that), and a thing on the wall in front comes first.
	if p.cond != Net.COND_OK or p.corpse or server.repairs.usable_ahead(p):
		return false
	var here := p.st.y * server.map.width + p.st.x
	var ahead := server.map.cell_ahead(p.st.x, p.st.y, p.st.facing)
	for cell: int in [ahead, here]:
		if cell < 0 or not server.floor_things.has(cell) or _lying_in(cell):
			continue
		var things: PackedByteArray = server.floor_things[cell]
		var top := Net.FLOOR_STACK - 1
		while top >= 0 and things[top] == Net.ITEM_NONE:
			top -= 1
		if top < 0 or not p.add(things[top], true):
			return false
		things[top] = Net.ITEM_NONE
		if things.count(Net.ITEM_NONE) == Net.FLOOR_STACK:
			server.floor_things.erase(cell)
		else:
			server.floor_things[cell] = things
		server.replication.floor_record(cell)
		return true
	return false


func put_down(p: Player) -> bool:
	## Puts the thing in the hand down in its own cell, if there is room there.
	var item := p.in_hand()
	if p.cond != Net.COND_OK or p.corpse or item == Net.ITEM_NONE:
		return false
	var cell := p.st.y * server.map.width + p.st.x
	var things: PackedByteArray = server.floor_things.get(cell, PackedByteArray())
	if things.is_empty():
		things.resize(Net.FLOOR_STACK)
	var at := things.find(Net.ITEM_NONE)
	if at < 0:
		return false                         # the cell is full
	things[at] = item
	server.floor_things[cell] = things
	p.slots[p.hand] = Net.ITEM_NONE
	server.replication.floor_record(cell)
	server.chat.sound(Net.SOUND_DROP, p.st.x, p.st.y, p.slot)
	return true


func set_supply(p: Player, on: bool) -> void:
	## The oxygen supply on or off: it needs a suit, and oxygen in its tank.
	if p.cond == Net.COND_OK:
		p.supply = on and p.tank > 0.0 and p.has_suit()


func take_off(p: Player, wear: int) -> bool:
	## Takes off what is worn there, into the hand (or a free slot). Not while
	## things are kept in it, and not without room for it.
	if p.cond != Net.COND_OK or p.corpse:
		return false
	var keep_tank := p.tank
	var keep_supply := p.supply
	var item := p.take_off(wear)
	if item == Net.ITEM_NONE:
		return false
	if not p.add(item, true):
		p.put_on(item)                       # nowhere to put it: it stays on
		p.tank = keep_tank
		p.supply = keep_supply
		return false
	return true


func act(p: Player) -> bool:
	## Uses the thing in the hand by itself: switches a flashlight on or off, or
	## puts on something to wear (what was worn there comes off into the hand).
	var item := p.in_hand()
	if p.cond == Net.COND_OK and not p.corpse and Items.worn_as(item) >= 0:
		var wear := Items.worn_as(item)
		p.slots[p.hand] = Net.ITEM_NONE
		var old := Net.ITEM_NONE
		if p.worn[wear] != Net.ITEM_NONE:
			old = p.take_off(wear)
			if old == Net.ITEM_NONE:
				p.slots[p.hand] = item           # things are still kept in the old one
				return false
		p.put_on(item)
		p.slots[p.hand] = old
		return true
	if p.cond != Net.COND_OK or p.corpse or Items.switched(item) == Net.ITEM_NONE:
		return false
	p.slots[p.hand] = Items.switched(item)
	return true
