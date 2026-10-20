extends RefCounted
## (v70, the author's J5: "handcuffs and a brig; prisoners are sold, ransomed or
## questioned") Pirates in our handcuffs. Server only.
##
## A pirate who is down (out cold, or knocked down by a stun baton or a
## flashbang) is cuffed with a click of handcuffs (Combat.cuff): what he fought
## with falls to the floor, and from then on he lies bound (Crew.update_vitals
## keeps him down), takes no part, and is hauled like anybody lying. Nobody
## fights him: our robots and the pirates leave him be.
##
## The brig's cells (v75, the author's P1; the armory too, as before) hold
## prisoners: a prisoner anywhere else slips the cuffs after LOOSE_SECONDS, grabs
## a pipe and fights again. In the brig he never does. (v75, the author's P2) Nor
## does he while he is hurt (below WHOLE_ENOUGH health) or while one of ours is
## in the room with him: the time only runs out once he is fit and unwatched.
##
## What a prisoner is good for:
##  - sold: a supply station or a trader takes every prisoner aboard for
##    Net.PRISONER_PAYS each (the trade screen's button, Net.STORE_PRISONERS);
##  - questioned: the first time somebody searches his pockets he talks (talk):
##    every hidden place of this system is marked on the chart, and to a guard
##    he also gives away the pirate hunters in this cluster;
##  - exchanged: a pirate ship come to fight us while we hold one calls the
##    comms console after SWAP_DELAY (the tale "prisoner_swap"): give him back
##    and they leave, ask a ransom, or refuse. Never the flagship's.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Tales := preload("res://src/server/tales.gd")

const LOOSE_SECONDS := 120.0         # a prisoner outside the brig slips the cuffs after this long
const SWAP_DELAY := 6.0              # seconds after a pirate ship comes before it calls about its man
const RANSOM_PAYS := 30              # what they pay for him when they agree to a ransom
const WHOLE_ENOUGH := 50.0           # (v75) a prisoner below this health is too weak to slip the cuffs

var server: GameServer
var sold := 0                        # (tests) prisoners handed over so far
var _swap_at := -1                   # the tick the pirates call about their man (-1 = no call due)


func setup(p_server: GameServer) -> void:
	server = p_server
	sold = 0
	_swap_at = -1


func all() -> Array:
	## Our prisoners, alive, wherever they lie.
	var out: Array = []
	for q: Player in server.players:
		if q != null and q.prisoner and not q.corpse and q.cond != Net.COND_DEAD:
			out.append(q)
	return out


func count() -> int:
	return all().size()


func in_brig(q: Player) -> bool:
	var map := server.map
	var c := q.st.y * map.width + q.st.x
	return map.is_brig(c) or c >= 0 and c < map.access_in.size() and (map.access_in[c] & Net.ACCESS_ARMORY) != 0


func watched(q: Player) -> bool:
	## (v75, the author's P2) One of ours (a player, a bot or our robot) awake in the same room.
	var map := server.map
	var room := map.room_at(q.st.x, q.st.y)
	if room < 0:
		return false
	for o: Player in server.players:
		if o == null or o == q or o.pirate or o.corpse or o.cond != Net.COND_OK:
			continue
		if map.room_at(o.st.x, o.st.y) == room:
			return true
	return false


func take(q: Player, by: Player) -> void:
	## Handcuffs on him (Combat.cuff has checked he may be cuffed).
	q.prisoner = true
	q.goal = 0
	q.ai_target = -1
	q.st.dir = Net.DIR_NONE
	q.inputs.clear()
	q.loose_at = server.tick + roundi(LOOSE_SECONDS * Net.TICK_HZ)
	var cell := q.st.y * server.map.width + q.st.x
	for at in Net.SLOTS:
		if q.slots[at] != Net.ITEM_NONE:
			server.put_on_floor(cell, q.slots[at])   # (what does not fit on the floor is lost)
			q.slots[at] = Net.ITEM_NONE
	server.crew.announce_join(q, null)       # (he shows as a prisoner now: Net.KIND_PRISONER)
	server.chat.say("%s заковывает в наручники: %s. Пленного держат в камере гауптвахты: в другом месте, когда он окрепнет и рядом никого, он через %d мин освободится." % [
		by.name if by != null else "Экипаж", q.name, roundi(LOOSE_SECONDS / 60.0)])


func tick() -> void:
	if server.tick % Net.TICK_HZ == 0:
		for q: Player in all():
			if in_brig(q) or q.dragged_by >= 0 or q.health < WHOLE_ENOUGH or q.cond == Net.COND_DEAD or watched(q):
				q.loose_at = server.tick + roundi(LOOSE_SECONDS * Net.TICK_HZ)
			elif server.tick >= q.loose_at:
				_breaks_free(q)
	if _swap_at >= 0 and server.tick >= _swap_at:
		_swap_at = -1
		if server.gunnery.fighting() and server.gunnery.boss == 0 and not server.gunnery.crewless and count() > 0 and not server.map.comms.is_empty():
			server.story.open(Tales.find("prisoner_swap"))


func _breaks_free(q: Player) -> void:
	q.prisoner = false
	q.stun_until = 0
	q.add(Net.ITEM_BATON, true)              # (a pipe, or what passes for one)
	server.crew.announce_join(q, null)
	server.chat.say("Пленный %s выбрался из наручников и хватается за трубу!" % q.name)


func enemy_arrives() -> void:
	## A pirate ship has come to fight: with a man of theirs in our hands, it calls about him.
	_swap_at = server.tick + roundi(SWAP_DELAY * Net.TICK_HZ) if count() > 0 else -1


func give_back(ransom: int) -> String:
	## (the call's answer) One prisoner goes back to them, and their ship leaves.
	## Returns what to add to the call's outcome.
	var list := all()
	if list.is_empty() or not server.gunnery.fighting():
		return " Но отдавать уже некого."
	if server.stations.ours_aboard:
		return " Но наши люди на их корабле: пока они там, пираты не уйдут. Бой продолжается."
	server.crew.remove(list[0])
	server.gunnery.swap_done(ransom)
	return (" +%d кр." % ransom) if ransom > 0 else ""


func sell(p: Player) -> void:
	## At a station or a trader: every prisoner aboard is handed over.
	var list := all()
	if list.is_empty():
		server.chat.tell(p, "На борту нет пленных.")
		return
	for q: Player in list:
		server.crew.remove(q)
	sold += list.size()
	server.ship.credits = mini(server.ship.credits + Net.PRISONER_PAYS * list.size(), 65535)
	server.chat.say("%s сдаёт пленных (%d): +%d кр." % [p.name, list.size(), Net.PRISONER_PAYS * list.size()])


func talk(p: Player, q: Player) -> void:
	## Somebody searches a prisoner's pockets: the first time, he talks.
	if not q.prisoner or q.talked:
		return
	q.talked = true
	server.road.reveal_here()
	var said := "Пленный %s под допросом выдаёт все тайники этой системы: они отмечены на карте." % q.name
	if p.job == Net.JOB_GUARD:
		var where := PackedStringArray()
		for h: Dictionary in server.road.hunters:
			where.append(server.sectors.names[int(h["at"])])
		said += (" Охраннику он называет и охотников: %s." % ", ".join(where)) if not where.is_empty() else " Охотников за нами, по его словам, в кластере нет."
	server.chat.say(said)
