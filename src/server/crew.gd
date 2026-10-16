extends RefCounted
## The people aboard: players coming and going, bots, bodies, coming back from
## the reserve, what the air and wounds do to a body, and how the campaign is
## lost (the hull gives way, or nobody is left).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Vitals := preload("res://src/server/vitals.gd")
const Campaign := preload("res://src/server/campaign.gd")

const BOT_RESPAWN_TICKS := 300      # a dead bot is replaced after 15 s
const MAX_CORPSES := 30             # the oldest body is cleared away when there are more

var server: GameServer
var _campaign_told := PackedByteArray()   # the state of the campaign as clients were last told


func setup(p_server: GameServer) -> void:
	server = p_server
	_campaign_told = PackedByteArray()


func hello(peer: ENetPacketPeer, pkt: PackedByteArray) -> void:
	if pkt.size() < 4:
		server._reject(peer, Net.REJECT_BAD_HELLO)
		return
	if pkt.decode_u16(1) != Net.PROTOCOL:
		server._reject(peer, Net.REJECT_VERSION)
		return
	if server.player_count() >= server.max_players:
		server._reject(peer, Net.REJECT_FULL)
		return
	var n := pkt[3]
	if pkt.size() < 4 + n:
		server._reject(peer, Net.REJECT_BAD_HELLO)
		return
	var wanted := server.chat.clean(pkt.slice(4, 4 + n).get_string_from_utf8(), Net.MAX_NAME, "Игрок")
	var back_from_reserve := false
	if server.over == Net.OVER_NONE and server.dead_names.has(wanted):
		# their character died and they left: coming back takes somebody from the reserve
		if server.reserve <= 0 and living_crew() > 0:
			server._reject(peer, Net.REJECT_NO_CREW)
			return
		server.dead_names.erase(wanted)
		if server.reserve > 0:
			server.reserve -= 1
			back_from_reserve = true
		else:
			end_campaign(Net.OVER_CREW_LOST)    # nobody alive and nobody left to send
	var p := new_player(_unique_name(wanted))
	p.peer = peer
	server.admin.joined(p)
	var demoted := false
	if server.saved_crew.has(p.name):
		restore_character(p, server.saved_crew[p.name])   # back from the last evening, as they were
		server.saved_crew.erase(p.name)
	else:
		var job: int = pkt[4 + n] if pkt.size() > 4 + n else Net.JOB_CREWMAN
		if job >= Net.JOBS:
			job = Net.JOB_CREWMAN
		if job == Net.JOB_CAPTAIN and _has_captain():
			job = Net.JOB_CREWMAN                # one captain to a ship
			demoted = true
		p.take_job(job)
		if not back_from_reserve:
			_kit_out(p)                      # (somebody from the reserve comes with empty hands)
	server.pending.erase(peer)
	server.slot_of[peer] = p.slot

	var map_name := server.map.map_name.to_utf8_buffer()
	var w := PackedByteArray()
	w.resize(14)
	w.encode_u8(0, Net.S_WELCOME)
	w.encode_u16(1, p.slot)
	w.encode_u32(3, server.tick)
	w.encode_u32(7, server.map.crc)
	w.encode_u16(11, server.ship.id)
	w.encode_u8(13, map_name.size())
	w.append_array(map_name)
	peer.send(0, w, ENetPacketPeer.FLAG_RELIABLE)

	var roster := PackedByteArray()
	roster.resize(3)
	roster.encode_u8(0, Net.S_ROSTER)
	var count := 0
	for q: Player in server.players:
		if q != null:
			roster.append_array(roster_entry(q))
			count += 1
	roster.encode_u16(1, count)
	peer.send(0, roster, ENetPacketPeer.FLAG_RELIABLE)

	peer.send(0, server.ships_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.navigation.sectors_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.ship.nav_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.ship.helm_packet(server.tick), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.gunnery.packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.drone.packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.enemy_crew.packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.stations.packet(), ENetPacketPeer.FLAG_RELIABLE)
	for q: Player in server.players:
		if q != null and q != p:
			peer.send(0, look_packet(q), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.ship.devices_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.ship.power_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.ship.store_packet(), ENetPacketPeer.FLAG_RELIABLE)
	peer.send(0, server.supplies.trade_packet(), ENetPacketPeer.FLAG_RELIABLE)

	peer.send(0, campaign_packet(), ENetPacketPeer.FLAG_RELIABLE)
	announce_join(p, peer)
	if demoted:
		server.chat.tell(p, "Капитан на борту уже есть: вы поднимаетесь на борт матросом.")
	if back_from_reserve:
		server.chat.say("%s возвращается на борт из резерва экипажа. В резерве осталось: %d." % [p.name, server.reserve])
	server.log_line.emit("%s подключился (игроков: %d)." % [p.name, server.player_count()])


func _has_captain() -> bool:
	for q: Player in server.players:
		if q != null and not q.corpse and not q.bot and not q.pirate and q.job == Net.JOB_CAPTAIN:
			return true
	for c: Dictionary in server.saved_crew.values():
		if int(c["job"]) == Net.JOB_CAPTAIN:
			return true                      # the captain of the last evening keeps the post
	return false


func restore_character(p: Player, c: Dictionary) -> void:
	## A saved character back in the world (see Campaign).
	p.take_job(int(c["job"]))
	p.colour = int(c["colour"])
	p.skills = PackedByteArray(c["skills"])
	p.slots = PackedByteArray(c["slots"])
	p.worn = PackedByteArray(c["worn"])
	p.hand = int(c["hand"])
	p.tank = float(c["tank"])
	p.supply = bool(c["supply"])
	p.health = float(c["health"])
	p.wounds = float(c["wounds"])
	p.cond = Net.COND_OK if p.health > 0.0 else Net.COND_CRIT
	p.st.place(int(c["x"]), int(c["y"]))
	p.st.facing = int(c["facing"])
	p.st.down = p.cond != Net.COND_OK
	p.self_dirty = true


func restore_body(c: Dictionary) -> void:
	## A body from the saved campaign, where it lay.
	var b := alloc(str(c["name"]))
	b.colour = int(c["colour"])
	b.job = int(c["job"])
	b.st.place(int(c["x"]), int(c["y"]))
	b.st.facing = int(c["facing"])
	b.st.down = true
	b.cond = Net.COND_DEAD
	b.health = Net.HEALTH_DEAD
	b.wounds = float(c["wounds"])
	b.slots = PackedByteArray(c["slots"])
	b.worn = PackedByteArray(c["worn"])
	b.tank = float(c["tank"])
	becomes_corpse(b)


func _kit_out(p: Player) -> void:
	## What a crew member has on them when they come aboard; the rest is in the locker.
	p.add(Net.ITEM_RADIO)
	p.add(Net.ITEM_PATCH)
	p.add(Net.ITEM_PART)
	match p.job:
		Net.JOB_ENGINEER:
			p.add(Net.ITEM_PART)
		Net.JOB_MEDIC:
			p.add(Net.ITEM_MEDPATCH)
		Net.JOB_GUARD:
			p.add(Net.ITEM_BATON)
		Net.JOB_CAPTAIN, Net.JOB_PILOT:
			p.add(Net.ITEM_FLASHLIGHT)


func _me_packet(p: Player) -> PackedByteArray:
	var out := PackedByteArray([Net.S_ME, p.job])
	out.append_array(p.skills)
	out.append((Net.ME_ADMIN if p.admin else 0) | (Net.ME_HOST if p.host else 0))
	return out


func tell_me(p: Player) -> void:
	## Tells a player their own job and skills when these changed.
	if p.peer == null:
		return
	var now := _me_packet(p)
	if now != p.me_sent:
		p.me_sent = now
		p.peer.send(0, now, ENetPacketPeer.FLAG_RELIABLE)


func alloc(player_name: String) -> Player:
	## A new record in a free slot. The slot number is the character's id.
	var p := Player.new()
	if server.free_slots.is_empty():
		p.slot = server.players.size()
		server.players.append(p)
	else:
		p.slot = server.free_slots.pop_back()
		server.players[p.slot] = p
	p.name = player_name
	p.dress()                            # everybody comes in a spacesuit and a jumpsuit
	return p


func new_player(player_name: String) -> Player:
	var p := alloc(player_name)
	p.colour = p.slot % Net.SUIT_COLOURS
	var spot := spawn_point()
	p.st.place(spot.x, spot.y)
	return p


func add_bot() -> void:
	var n := 1
	for q: Player in server.players:
		if q != null and q.bot:
			n += 1
	var p := new_player(_unique_name("Бот %d" % n))
	p.bot = true
	p.add(Net.ITEM_FLASHLIGHT, true)
	announce_join(p, null)


func announce_join(p: Player, except: ENetPacketPeer) -> void:
	var msg := PackedByteArray([Net.S_JOIN])
	msg.append_array(roster_entry(p))
	for q: Player in server.players:
		if q != null and q.peer != null and q.peer != except:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func roster_entry(p: Player) -> PackedByteArray:
	var name_bytes := p.name.to_utf8_buffer()
	var e := PackedByteArray()
	e.resize(6)
	e.encode_u16(0, p.slot)
	e.encode_u8(2, p.colour)
	e.encode_u8(3, Net.KIND_CORPSE if p.corpse else (Net.KIND_PIRATE if p.pirate else (Net.KIND_BOT if p.bot else Net.KIND_PLAYER)))
	e.encode_u8(4, p.job)
	e.encode_u8(5, name_bytes.size())
	e.append_array(name_bytes)
	return e


func spawn_point() -> Vector2i:
	# prefer a spawn tile nobody is standing on
	var start := server.rng.randi_range(0, server.map.spawns.size() - 1)
	for i in server.map.spawns.size():
		var s: Vector2i = server.map.spawns[(start + i) % server.map.spawns.size()]
		var taken := false
		for q: Player in server.players:
			if q != null and q.st.x == s.x and q.st.y == s.y:
				taken = true
				break
		if not taken:
			return s
	return server.map.spawns[start]


func drop(peer: ENetPacketPeer) -> void:
	server.pending.erase(peer)
	if not server.slot_of.has(peer):
		return
	var p: Player = server.players[server.slot_of[peer]]
	server.slot_of.erase(peer)
	if p.cond == Net.COND_DEAD:
		# the dead stay where they fell, whether or not their player is still here
		p.peer = null
		becomes_corpse(p)
		if not p.bot and not p.pirate:
			server.dead_names[p.name] = true       # coming back will take somebody from the reserve
	else:
		if not p.bot and not p.pirate and server.over == Net.OVER_NONE:
			server.saved_crew[p.name] = Campaign.character(p)   # kept for when they come back
		remove(p)
	server.log_line.emit("%s вышел (игроков: %d)." % [p.name, server.player_count()])


func remove(p: Player) -> void:
	## Takes a character out of the world altogether.
	if p.dragging >= 0:
		server.looting.let_go(p)
	if p.dragged_by >= 0 and server.players[p.dragged_by] != null:
		server.looting.let_go(server.players[p.dragged_by])
	for q: Player in server.players:
		if q != null and q != p and q.searching == p.slot:
			server.looting.stop_search(q)    # (its slot may soon hold somebody else)
	server.replication.forget(p.slot)
	server.players[p.slot] = null
	server.free_slots.append(p.slot)
	server.corpses.erase(p.slot)
	var msg := PackedByteArray()
	msg.resize(3)
	msg.encode_u8(0, Net.S_LEAVE)
	msg.encode_u16(1, p.slot)
	for q: Player in server.players:
		# (a player leaving at the same moment may already be past sending to)
		if q != null and q.peer != null and q.peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func becomes_corpse(c: Player) -> void:
	## Marks a record as a body nobody controls and tells everyone what it is now.
	c.corpse = true
	c.bot = false
	c.using = false
	c.inputs.clear()
	server.corpses.append(c.slot)
	announce_join(c, null)
	if server.corpses.size() > MAX_CORPSES:
		remove(server.players[server.corpses[0]])


func _leave_body(p: Player) -> void:
	## The character is about to be given a new body: its old one stays where it
	## lies, with everything it carried. Whoever was hauling or searching the
	## dead character goes on with the body.
	var c := alloc(p.name)
	c.colour = p.colour
	c.job = p.job
	c.st.copy_from(p.st)
	c.st.dir = Net.DIR_NONE
	c.st.down = true
	c.cond = Net.COND_DEAD
	c.health = Net.HEALTH_DEAD
	c.wounds = p.wounds
	c.slots = p.slots.duplicate()
	c.worn = p.worn.duplicate()
	c.tank = p.tank
	c.hand = p.hand
	for q: Player in server.players:
		if q == null:
			continue
		if q.dragging == p.slot:
			q.dragging = c.slot
			c.dragged_by = q.slot
		if q.searching == p.slot:
			q.searching = c.slot
			q.search_sent = PackedByteArray()
	p.dragged_by = -1
	p.st.slow = false
	becomes_corpse(c)


func _unique_name(wanted: String) -> String:
	var candidate := wanted
	var n := 1
	while true:
		var clash := false
		for q: Player in server.players:
			if q != null and not q.corpse and q.name == candidate:
				clash = true
				break
		if not clash:
			return candidate
		n += 1
		candidate = "%s %d" % [wanted.left(Net.MAX_NAME - 3), n]
	return candidate


func look_packet(p: Player) -> PackedByteArray:
	return PackedByteArray([Net.S_OUTFIT, p.slot & 0xFF, p.slot >> 8, p.look()])


func tell_looks() -> void:
	## Tells everyone how a character is dressed when that changes.
	for p: Player in server.players:
		if p != null and p.look() != p.look_sent:
			p.look_sent = p.look()
			server.to_all(look_packet(p))


func update_vitals(p: Player) -> void:
	## What the air in its cell does to one character this tick.
	if p.cond == Net.COND_DEAD:
		if p.bot and server.tick - p.died_tick >= BOT_RESPAWN_TICKS:
			respawn(p)
		return
	var breathes := server.air.air[p.st.y * server.map.width + p.st.x]
	if p.pirate:
		breathes = 1.0                       # pirates come in sealed suits
	elif p.supply:
		# on the tank: the air around does not matter while there is oxygen left
		p.tank = maxf(p.tank - Net.TICK_SEC / Vitals.TANK_SECONDS, 0.0)
		if p.tank > 0.0:
			breathes = 1.0
		else:
			p.supply = false
	p.health = Vitals.advance(p.health, p.cond, breathes, Net.TICK_SEC, p.wounds)
	var cond := Vitals.condition(p.health, p.cond)
	if cond == p.cond:
		return
	if p.cond == Net.COND_OK:
		server.chat.sound(Net.SOUND_THUD, p.st.x, p.st.y, p.slot)
	if cond == Net.COND_CRIT:
		server.chat.say("%s теряет сознание." % p.name)
	elif cond == Net.COND_DEAD:
		p.died_tick = server.tick
		server.chat.say("%s погибает." % p.name)
		if p.pirate:
			# a dead pirate is a body like any other, with what it carried
			p.cond = cond
			p.st.down = true
			p.st.dir = Net.DIR_NONE
			becomes_corpse(p)
			return
	elif p.cond == Net.COND_CRIT:
		server.chat.say("%s приходит в себя." % p.name)
	p.cond = cond
	p.st.down = cond != Net.COND_OK
	p.st.dir = Net.DIR_NONE
	p.inputs.clear()
	p.self_dirty = true


func respawn(p: Player) -> void:
	## A dead character comes back as a fresh crew member at a spawn point; the body stays.
	_leave_body(p)
	p.supply = false
	p.using = false
	p.work = 0
	p.slots.fill(Net.ITEM_NONE)
	p.dress()                            # (the old suit and clothes stay on the body; what the dead one carried stays with it)
	if not p.bot:
		# somebody new from the reserve, in the same job, dressed but with empty
		# hands (the author's word: only the first crew comes aboard with gear)
		p.skills.fill(0)
		p.take_job(p.job)
	var spot := spawn_point()
	p.st.place(spot.x, spot.y)
	p.st.dir = Net.DIR_NONE
	p.st.down = false
	p.st.facing = Net.DIR_DOWN
	p.health = Net.HEALTH_FULL
	p.wounds = 0.0
	p.treating = -1
	p.cond = Net.COND_OK
	p.inputs.clear()
	p.self_dirty = true
	server.chat.say("%s снова в строю." % p.name)


func respawn_from_reserve(p: Player) -> void:
	## A dead player asks to come back: that takes one of the reserve.
	if server.over != Net.OVER_NONE:
		return
	if p.bot:
		respawn(p)
		return
	if server.reserve <= 0:
		server.chat.tell(p, "Резерв экипажа пуст: заменить вас некем. Товарищи могут нанять людей у торговца.")
		return
	server.reserve -= 1
	respawn(p)
	server.chat.say("В резерве экипажа осталось: %d." % server.reserve)


func living_crew() -> int:
	## Players' characters still alive (unconscious counts: they may yet come round).
	var n := 0
	for q: Player in server.players:
		if q != null and not q.bot and not q.pirate and not q.corpse and q.cond != Net.COND_DEAD:
			n += 1
	return n


func check_crew() -> void:
	## The campaign is lost when every player's character is dead and the
	## reserve has nobody left to send.
	if server.reserve > 0:
		return
	var players_here := 0
	for q: Player in server.players:
		if q != null and not q.bot and not q.pirate and not q.corpse:
			players_here += 1
	if players_here > 0 and living_crew() == 0:
		end_campaign(Net.OVER_CREW_LOST)


func hull_hit(amount: int) -> void:
	## The hull takes a blow. At nothing it gives way and the campaign is over.
	if server.over != Net.OVER_NONE:
		return
	var was := server.ship.hull
	server.ship.hull = maxi(server.ship.hull - amount, 0)
	if server.ship.hull == 0:
		end_campaign(Net.OVER_WRECKED)
	elif was > 50 and server.ship.hull <= 50:
		server.chat.say("Обшивка на пределе: прочность %d из %d. Залатать её могут на станции снабжения или у торговца." % [server.ship.hull, Net.HULL_MAX])


func end_campaign(how: int) -> void:
	if server.over != Net.OVER_NONE:
		return
	server.over = how
	server.ship.jump_to = Net.NO_SECTOR
	server.navigation.tell_nav()
	server.ship.moving = false
	server.to_all(server.ship.helm_packet(server.tick))
	var why: String = Net.OVER_TEXT[how]
	server.chat.say("%s Кампания окончена. Пройдено секторов: %d, дальше всего от начала: %d прыжков, продержались %s." % [
		why, server.been.size(), server.farthest, voyage_text(server.voyage_ticks)])
	tell_campaign()
	campaign_ended()


func campaign_ended() -> void:
	## A lost campaign cannot be continued: its save is let go.
	if server.save_path != "":
		Campaign.forget(server.save_path)


static func voyage_text(ticks: int) -> String:
	var minutes := ticks / Net.TICK_HZ / 60
	return "%d ч %02d мин" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d мин" % minutes


func campaign_packet() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(15)
	out.encode_u8(0, Net.S_CAMPAIGN)
	out.encode_u8(1, server.ship.hull)
	out.encode_u8(2, server.reserve)
	out.encode_u8(3, server.over)
	out.encode_u16(4, mini(server.been.size(), 65535))
	out.encode_u16(6, mini(server.farthest, 65535))
	out.encode_u16(8, mini(server.jumps, 65535))
	out.encode_u32(10, server.voyage_ticks / Net.TICK_HZ)
	out.encode_u8(14, 1 if server.won else 0)
	return out


func tell_campaign() -> void:
	## Tells everyone the state of the campaign when it changed (the time is only refreshed with the rest).
	var now := campaign_packet()
	if now.slice(0, 10) + now.slice(14) != _campaign_told.slice(0, 10) + _campaign_told.slice(14):
		_campaign_told = now
		server.to_all(now)
