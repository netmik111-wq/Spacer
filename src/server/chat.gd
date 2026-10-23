extends RefCounted
## Speech and sound: what is said aloud, by radio and by intercom, and who
## hears it; the sounds the world makes; lines from the ship itself in chat.
## Sound and voice travel through air: in a vacuum only what happens right
## next to somebody is heard.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

const CHAT_BURST := 5               # messages allowed per CHAT_WINDOW_MS
const CHAT_WINDOW_MS := 5000

var server: GameServer
var bot_lines: Array = []            # (v72, tests: with keep_heard) every line of the bots' log, [bot slot, text]


func setup(p_server: GameServer) -> void:
	server = p_server


func clean(text: String, limit: int, fallback: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 32 and c != 127:
			out += text[i]
	out = out.strip_edges().left(limit)
	return fallback if out.is_empty() else out


func talk(p: Player, raw: String) -> void:
	var now := Time.get_ticks_msec()
	while not p.chat_times.is_empty() and now - p.chat_times[0] > CHAT_WINDOW_MS:
		p.chat_times.pop_front()
	if p.chat_times.size() >= CHAT_BURST:
		return
	var text := clean(raw, Net.MAX_CHAT, "")
	if text.is_empty():
		return
	p.chat_times.append(now)
	var channel := Net.CHAT_NEAR
	if p.cond == Net.COND_DEAD:
		channel = Net.CHAT_DEAD
	elif p.cond != Net.COND_OK:
		tell(p, "Без сознания не поговоришь.")
		return
	elif text.begins_with(Net.CHAT_RADIO_MARK):
		channel = Net.CHAT_RADIO
	elif text.begins_with(Net.CHAT_INTERCOM_MARK):
		channel = Net.CHAT_INTERCOM
	if channel == Net.CHAT_RADIO or channel == Net.CHAT_INTERCOM:
		text = text.substr(1).strip_edges()
		if text.is_empty():
			return
	if channel == Net.CHAT_RADIO and p.count(Net.ITEM_RADIO) == 0:
		tell(p, "У вас нет рации. Без неё вас слышат только те, кто рядом.")
		return
	var panel := -1
	if channel == Net.CHAT_INTERCOM:
		panel = intercom_near(p.st.x, p.st.y, Net.INTERCOM_REACH)
		if panel < 0:
			tell(p, "Рядом нет интеркома: подойдите к панели на стене.")
			return
		if not server.powered():
			tell(p, "Интерком молчит: на корабле нет питания.")
			return
	var msg := chat_packet(p.slot, channel, text)
	for q: Player in server.players:
		if q != null and (q == p or hears_said(q, p, channel)):
			if server.keep_heard and q != p:
				q.said.append([channel, p.slot, text])
			if q.peer != null:
				q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	server.log_line.emit("[%s] %s: %s" % [["корабль", "рядом", "рация", "интерком", "мёртвые"][channel], p.name, text])


static func chat_packet(from: int, channel: int, text: String) -> PackedByteArray:
	var body := text.to_utf8_buffer()
	var msg := PackedByteArray()
	msg.resize(6)
	msg.encode_u8(0, Net.S_CHAT)
	msg.encode_u16(1, from)
	msg.encode_u8(3, channel)
	msg.encode_u16(4, body.size())
	msg.append_array(body)
	return msg


func hears_said(q: Player, p: Player, channel: int) -> bool:
	## Does q hear what p says on that channel?
	if q.corpse or q.bot or q.pirate:
		return false
	if channel == Net.CHAT_DEAD:
		return q.cond == Net.COND_DEAD
	if q.cond == Net.COND_DEAD:
		return false
	match channel:
		Net.CHAT_RADIO:
			return q.count(Net.ITEM_RADIO) > 0
		Net.CHAT_INTERCOM:
			if hears_voice(q, p.st.x, p.st.y):
				return true
			for cell: int in server.map.intercom:
				if server.map.deck_of_cell(cell) == server.map.deck_of(q.st.y) \
						and Vector2(q.st.x - cell % server.map.width, q.st.y - cell / server.map.width).length() <= Net.INTERCOM_HEAR \
						and server.air.air[q.st.y * server.map.width + q.st.x] >= Net.SOUND_AIR:
					return true
			return false
	return hears_voice(q, p.st.x, p.st.y)


func hears_voice(q: Player, x: int, y: int) -> bool:
	## A voice at x, y: close by on the same deck, with air at both ends to carry
	## it, or close enough to touch helmets.
	if server.map.deck_of(q.st.y) != server.map.deck_of(y):
		return false
	var d := Vector2(q.st.x - x, q.st.y - y).length()
	if d > Net.SPEECH_RANGE:
		return false
	if d <= Net.SOUND_CONTACT:
		return true
	return server.air.air[y * server.map.width + x] >= Net.SOUND_AIR and server.air.air[q.st.y * server.map.width + q.st.x] >= Net.SOUND_AIR


func intercom_near(x: int, y: int, reach: float) -> int:
	for cell: int in server.map.intercom:
		if server.map.deck_of_cell(cell) == server.map.deck_of(y) and Vector2(x - cell % server.map.width, y - cell / server.map.width).length() <= reach:
			return cell
	return -1


func _air_for_sound(x: int, y: int) -> float:
	## The air a sound at this cell travels in: a wall cell (a hole) takes the
	## thickest air next to it.
	var best := server.air.air[y * server.map.width + x] if server.map.walkable(x, y) else 0.0
	if not server.map.walkable(x, y):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if server.map.walkable(x + d.x, y + d.y):
				best = maxf(best, server.air.air[(y + d.y) * server.map.width + x + d.x])
	return best


func hears(q: Player, kind: int, x: int, y: int) -> bool:
	## Does this character hear a sound of that kind made at x, y?
	if q.corpse or q.cond == Net.COND_DEAD or server.map.deck_of(q.st.y) != server.map.deck_of(y):
		return false
	var d := Vector2(q.st.x - x, q.st.y - y).length()
	if d > Net.SOUND_RANGE[kind]:
		return false
	if d <= Net.SOUND_CONTACT:
		return true
	return _air_for_sound(x, y) >= Net.SOUND_AIR and server.air.air[q.st.y * server.map.width + q.st.x] >= Net.SOUND_AIR


func sound(kind: int, x: int, y: int, made_by: int = -1) -> void:
	## Something was heard at x, y: everyone in earshot is told where (but not who).
	var msg := PackedByteArray([Net.S_SOUND, kind, 0, 0, 0, 0])
	msg.encode_s16(2, x)
	msg.encode_s16(4, y)
	for q: Player in server.players:
		# (v82) one hears one's own shots, blows, doors and things put down; only one's own footsteps
		# are played by the client itself (until v82 the shooter's own gun was silent)
		if q == null or q.slot == made_by and kind == Net.SOUND_STEP or not hears(q, kind, x, y):
			continue
		if server.keep_heard:
			q.heard.append([kind, x, y])
		if q.pirate and made_by >= 0 and server.players[made_by] != null and not server.players[made_by].pirate:
			server.pirates.heard(q, x, y)
		if q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func say(text: String) -> void:
	## A line in everybody's chat from the ship itself.
	var msg := chat_packet(Net.SYSTEM_ID, Net.CHAT_SHIP, text)
	for q: Player in server.players:
		if q != null and q.peer != null and q.peer.get_state() == ENetPacketPeer.STATE_CONNECTED:   # (v84, as in Crew.remove)
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	server.log_line.emit("[корабль] %s" % text)


func alarm(text: String) -> void:
	## (v73, the author's H4) A danger from the ship: as say(), and shown big on every screen.
	var msg := chat_packet(Net.SYSTEM_ID, Net.CHAT_ALARM, text)
	for q: Player in server.players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	server.log_line.emit("[корабль] %s" % text)


var _bridge := {}                    # (v68) the rooms (ShipMap.rooms) of the bridge: those its consoles face
var _bridge_map: Object = null


func on_bridge(q: Player) -> bool:
	## (v68) Is this character on the bridge (in a room one of its consoles faces)?
	var map := server.map
	if _bridge_map != map:
		_bridge_map = map
		_bridge = {}
		for c: int in map.helm.keys() + map.gun_console.keys() + map.chart.keys():
			var front := map.fitting_front(c)
			if front >= 0 and map.room_of[front] >= 0:
				_bridge[map.room_of[front]] = true
	var at := q.st.y * map.width + q.st.x
	return at >= 0 and at < map.room_of.size() and _bridge.has(map.room_of[at])


func say_bridge(text: String) -> void:
	## (v68, the author's G3) A detail of the fight: only those on the bridge read it
	## (the rest hear what the bridge tells them). Warnings still go by say().
	var msg := chat_packet(Net.SYSTEM_ID, Net.CHAT_SHIP, text)
	for q: Player in server.players:
		if q != null and q.peer != null and not q.corpse and on_bridge(q):
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	server.log_line.emit("[мостик] %s" % text)


func tell(p: Player, text: String) -> void:
	## A line from the ship in one player's chat only.
	if p.peer == null:
		return
	var msg := chat_packet(Net.SYSTEM_ID, Net.CHAT_SHIP, text)
	p.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func bot_log(p: Player, text: String, aloud: bool = false) -> void:
	## (v72, the author's note: "logs of what bots are doing, not deleted like normal chat, so I
	## can track what is happening on the ship and bugs in the bots") A line in the bots' log,
	## kept by every client for the whole game (the crew window and crew_log.txt). The same line
	## twice in a row is not logged again. `aloud`: the bot also says it in everybody's chat
	## (repairs only: the author's "tell in chat that one of the bots is taking the work").
	if text == p.bot_said:
		return
	p.bot_said = text
	var body := text.to_utf8_buffer()
	var msg := PackedByteArray([Net.S_BOTLOG, 0, 0, 0, 0, 0, 0, 0, 0])
	msg.encode_u16(1, p.slot)
	msg.encode_u32(3, server.tick / Net.TICK_HZ)
	msg.encode_u16(7, body.size())
	msg.append_array(body)
	for q: Player in server.players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	if server.keep_heard:
		bot_lines.append([p.slot, text])
	if aloud:
		say("%s: %s" % [p.name, text])
	else:
		server.log_line.emit("[боты] %s: %s" % [p.name, text])
