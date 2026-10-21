extends RefCounted
## Somebody lying on the floor (out cold or dead): going through their pockets,
## taking and giving things, dressing them, and dragging them along.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")

const HAND_SEARCH := 1              # what a press of "search" or "drag" asks for (Player.want_kind)
const HAND_DRAG := 2
const HAND_WAIT_TICKS := 10         # a drag asked for in mid-step waits this long for the step to end

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func can_reach(p: Player, id: int) -> bool:
	## Can this character lay hands on that one: it is on its feet, the other is
	## lying (unconscious or dead), and they are in the same cell or next to each other
	## (v74: on a slant too).
	if p.cond != Net.COND_OK or id < 0 or id >= server.players.size() or id == p.slot:
		return false
	var other: Player = server.players[id]
	return other != null and other.cond != Net.COND_OK and not other.taken \
		and maxi(absi(other.st.x - p.st.x), absi(other.st.y - p.st.y)) <= 1


func hands_asked(p: Player, kind: int, id: int, at: int) -> void:
	## A press of "search" or "drag". Like a press on a ladder, it is judged on
	## the tick the client pressed it, where the client saw its character stand.
	p.want_kind = kind
	p.want_id = id
	p.want_tick = clampi(at, server.tick, server.tick + GameServer.MAX_INPUT_LEAD)
	if p.want_tick == server.tick:
		_do_hands(p)


func _do_hands(p: Player) -> void:
	var id := p.want_id
	if p.want_kind == HAND_SEARCH:
		p.want_kind = 0
		if id == Net.NOBODY:
			stop_search(p)
		elif can_reach(p, id):
			p.searching = id
			p.search_sent = PackedByteArray()        # so that the pockets are sent at once
			server.prisons.talk(p, server.players[id])   # (v70) a prisoner searched talks
	elif p.want_kind == HAND_DRAG:
		if id == Net.NOBODY:
			p.want_kind = 0
			let_go(p)
			return
		if p.st.cd > 0 and server.tick < p.want_tick + HAND_WAIT_TICKS:
			return                                   # in mid-step: take hold when the step is done
		p.want_kind = 0
		if p.dragging < 0 and p.st.cd == 0 and can_reach(p, id) and server.players[id].dragged_by < 0:
			var body: Player = server.players[id]
			p.dragging = id
			body.dragged_by = p.slot
			p.st.slow = true
			body.st.slow = true
			p.self_dirty = true


func let_go(p: Player) -> void:
	## Stops hauling.
	if p.dragging < 0:
		return
	var body: Player = server.players[p.dragging] if p.dragging < server.players.size() else null
	if body != null and body.dragged_by == p.slot:
		body.dragged_by = -1
		body.st.slow = body.slowed()         # (v70) a broken leg still slows (v71: or hunger)
	p.dragging = -1
	p.st.slow = p.slowed()
	p.self_dirty = true


func stop_search(p: Player) -> void:
	if p.searching < 0:
		return
	p.searching = -1
	if p.peer != null:
		var msg := PackedByteArray([Net.S_SEARCH, 0xFF, 0xFF])
		msg.resize(3 + Net.SLOTS)
		p.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func haul(p: Player, to_x: int, to_y: int) -> void:
	## The character has just stepped away from that cell: whoever it hauls slides into it.
	var body: Player = server.players[p.dragging]
	if body == null:
		return
	body.st.fx = body.st.qx()
	body.st.fy = body.st.qy()
	body.st.x = to_x
	body.st.y = to_y
	body.st.ox = 0
	body.st.oy = 0
	body.st.move_tick = server.tick
	body.st.span = Net.DRAG_TICKS if p.st.fine else p.st.span   # (v78) a quarter-stepper crosses a tile in DRAG_TICKS
	body.self_dirty = true


func update(p: Player) -> void:
	## Keeps hauling and searching honest: both end when either side is no
	## longer in a state for it, or they are no longer together.
	if p.want_kind != 0 and server.tick >= p.want_tick:
		_do_hands(p)
	if p.dragging >= 0 and not can_reach(p, p.dragging):
		let_go(p)
	if p.searching >= 0:
		if not can_reach(p, p.searching):
			stop_search(p)
		else:
			var other: Player = server.players[p.searching]
			var seen_now := other.slots.duplicate()
			seen_now.append_array(worn_shown(other))
			seen_now.append(server.combat.hurt_level(other))
			if seen_now != p.search_sent:
				p.search_sent = seen_now
				if p.peer != null:
					var msg := PackedByteArray([Net.S_SEARCH, p.searching & 0xFF, p.searching >> 8])
					msg.append_array(other.slots)
					msg.append_array(worn_shown(other))
					msg.append(server.combat.hurt_level(other))
					p.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func worn_shown(p: Player) -> PackedByteArray:
	## What it wears, as things: a suit shows how much oxygen is left in it.
	var out := p.worn.duplicate()
	if p.has_suit():
		out[Net.WEAR_SUIT] = Items.suit_with(p.tank)
	return out


func loot_asked(p: Player, theirs: bool, index: int) -> void:
	## While searching: take the thing in one of their slots, or give them one of ours.
	if p.searching < 0 or index >= Net.SLOTS + Net.WORN or not can_reach(p, p.searching):
		return
	var other: Player = server.players[p.searching]
	if index >= Net.SLOTS:
		# what they wear can be taken off them (to dress them, give them the thing itself)
		if not theirs:
			return
		var keep_tank := other.tank
		var worn_item := other.take_off(index - Net.SLOTS)
		if worn_item != Net.ITEM_NONE and not p.add(worn_item):
			other.put_on(worn_item)
			other.tank = keep_tank
		return
	if not theirs and Items.worn_as(p.slots[index]) >= 0 and other.cond != Net.COND_DEAD and other.put_on(p.slots[index]):
		# a suit (or clothes) given to somebody out cold goes onto them: put a
		# spacesuit on a fallen friend before carrying them through vacuum
		p.slots[index] = Net.ITEM_NONE
		if other.has_suit():
			other.supply = true              # and turn its oxygen on: they cannot do it themselves
		other.self_dirty = true
		return
	var from := other if theirs else p
	var to := p if theirs else other
	var item := from.slots[index]
	if item != Net.ITEM_NONE and to.add(item):
		from.slots[index] = Net.ITEM_NONE
