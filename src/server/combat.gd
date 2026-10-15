extends RefCounted
## Weapons and wounds: shooting (judged against what the shooter saw), blows,
## wounds, healing with a patch or a first-aid kit.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")

const TREAT_TICKS := 60             # one use of a first-aid kit takes 3 s
const SHOT_TICKS := 6                # a pistol fires at most this often
const RELOAD_TICKS := 30             # putting a fresh magazine in takes 1.5 s
const BLOW_TICKS := 16               # a blow with a baton
const HIT_RADIUS := 0.45             # a shot passing this close (in cells) to somebody hits them
const SHOT_SEEN := 24                # a shot is drawn for everybody this close on its deck

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


func place_at(q: Player, when: int) -> Vector2:
	## Where a character was drawn on that tick (for the last Player.HISTORY
	## ticks): a shot is judged against what the shooter saw, not against
	## where things are by the time the click arrives.
	if when >= server.tick or server.tick - when >= Player.HISTORY or when <= 0:
		return Mover.visual_pos(q.st, server.tick)
	return q.history[when % Player.HISTORY]


func use_at(p: Player, seen_tick: int, at: Vector2) -> void:
	## A click with the thing in the hand: a pistol shoots there (or is
	## reloaded when empty), a baton strikes the cell next to us that way, a
	## patch for wounds is put on ourselves or on the one next to us.
	if p.cond != Net.COND_OK or p.corpse or server.tick < p.ready_tick:
		return
	var item := p.in_hand()
	var rounds := Items.rounds(item)
	if rounds > 0:
		p.slots[p.hand] = item - 1
		p.ready_tick = server.tick + SHOT_TICKS
		_shoot(p, clampi(seen_tick, server.tick - Player.HISTORY + 1, server.tick), at)
	elif rounds == 0:
		var mag := p.slots.find(Net.ITEM_MAG)
		if mag >= 0:
			p.slots[mag] = Net.ITEM_NONE
			p.slots[p.hand] = Net.ITEM_PISTOL + Net.PISTOL_ROUNDS
			p.ready_tick = server.tick + RELOAD_TICKS
	elif Items.INFO.has(item) and Items.INFO[item].has("blow"):
		p.ready_tick = server.tick + BLOW_TICKS
		_strike(p, at, int(Items.INFO[item]["blow"]))
	elif Items.INFO.has(item) and Items.INFO[item].has("heal"):
		var who := _beside(p, at, true)
		if who != null and who.wounds > 0.0:        # (a patch is not wasted on one who has no wounds)
			heal(who, float(Items.INFO[item]["heal"]))
			p.slots[p.hand] = Net.ITEM_NONE
			if who != p:
				server.chat.say("%s заклеивает раны: %s." % [p.name, who.name])
	elif Items.uses(item) > 0:
		# a first-aid kit: the treatment takes a while, and both must keep still for it
		var who := _beside(p, at, true)
		if who != null and who.wounds > 0.0:
			p.treating = who.slot
			p.work = 0
			p.work_cell = -2
			p.work_total = _treat_ticks(p)


func hurt_level(q: Player) -> int:
	## How hurt somebody looks: 0 unhurt, 1 lightly, 2 badly, 3 gravely, 4 dying.
	if q.health >= 95.0:
		return 0
	if q.health >= 60.0:
		return 1
	if q.health >= 20.0:
		return 2
	if q.health >= -40.0:
		return 3
	return 4


func heal(q: Player, amount: float) -> void:
	## Closes wounds: health comes back as far as the wounds healed.
	var closed := minf(amount, q.wounds)
	q.wounds -= closed
	q.health = minf(q.health + closed, Net.HEALTH_FULL)


func update_treatment(p: Player) -> bool:
	## A treatment with a first-aid kit in progress. It stops if either moves
	## away, the kit leaves the hand, or the one treating falls. True while it goes on.
	if p.treating < 0:
		return false
	var q: Player = server.players[p.treating] if p.treating < server.players.size() else null
	var kit := p.in_hand()
	if q == null or q.corpse or q.cond == Net.COND_DEAD or p.cond != Net.COND_OK or Items.uses(kit) <= 0 \
			or p.st.cd > 0 or p.st.dir != Net.DIR_NONE or absi(q.st.x - p.st.x) > 1 or absi(q.st.y - p.st.y) > 1 \
			or q.wounds <= 0.0:
		p.treating = -1
		p.work = 0
		return false
	p.work += 1
	if p.work >= _treat_ticks(p):
		p.train(Net.SKILL_MEDICINE)
		heal(q, float(Items.MEDKIT_HEAL))
		p.slots[p.hand] = kit - 1 if Items.uses(kit) > 1 else Net.ITEM_NONE
		p.work = 0
		if q != p:
			server.chat.say("%s перевязывает раны: %s." % [p.name, q.name])
		if q.wounds <= 0.0 or p.slots[p.hand] == Net.ITEM_NONE:
			p.treating = -1
	return true


func _treat_ticks(p: Player) -> int:
	## A treatment takes TREAT_TICKS for one with no skill, down to half that for the best.
	return roundi(TREAT_TICKS * (1.0 - 0.5 * p.skill(Net.SKILL_MEDICINE)))


func _stops_shot(x: int, y: int) -> bool:
	## A bullet stops at anything that cannot be walked through: walls, windows, shut doors.
	if not server.map.walkable(x, y):
		return true
	var d := server.map.door_at(x, y)
	return d >= 0 and server.doors.is_shut(d)


func _shoot(p: Player, seen_tick: int, at: Vector2) -> void:
	var from := Vector2(p.st.x, p.st.y)
	var way := at - from
	if way.length() < 0.1:
		return
	way = way.normalized()
	var start := Vector2i(p.st.x, p.st.y)
	var reach := float(Items.PISTOL_RANGE)
	var t := 0.3
	while t < reach:
		var c := from + way * t
		var cell := Vector2i(roundi(c.x), roundi(c.y))
		if cell != start and (_stops_shot(cell.x, cell.y) or server.map.deck_of(cell.y) != server.map.deck_of(start.y)):
			reach = t
			break
		t += 0.1
	var hit: Player = null
	var best := reach
	for q: Player in server.players:
		if q == null or q == p or q.corpse or q.cond == Net.COND_DEAD or server.map.deck_of(q.st.y) != server.map.deck_of(p.st.y):
			continue
		var pos := place_at(q, seen_tick)
		var along := (pos - from).dot(way)
		if along <= 0.2 or along >= best:
			continue
		if (pos - (from + way * along)).length() <= HIT_RADIUS + 0.1 * p.skill(Net.SKILL_GUNS):
			best = along
			hit = q
	var end := from + way * best
	if hit != null:
		p.train(Net.SKILL_GUNS)
	tell_shot(Net.SHOT_BULLET, hit != null, from, end, p.st.y)
	server.chat.sound(Net.SOUND_SHOT, p.st.x, p.st.y, p.slot)
	if hit != null:
		hurt(hit, Items.PISTOL_DAMAGE, p)


func _beside(p: Player, at: Vector2, self_too: bool) -> Player:
	## Whoever a click next to us means: ourselves (if `self_too` and the click
	## was on us), else of those in the cells around us (diagonals too) the one
	## nearest the click. A click is never quite on the cell, and the one
	## clicked may be in mid-step, so this is forgiving.
	var from := Vector2(p.st.x, p.st.y)
	if self_too and at.distance_to(from) < 0.5:
		return p
	var best: Player = null
	var best_d := 1.6
	for q: Player in server.players:
		if q == null or q == p or q.corpse or q.cond == Net.COND_DEAD:
			continue
		if absi(q.st.x - p.st.x) > 1 or absi(q.st.y - p.st.y) > 1 or server.map.deck_of(q.st.y) != server.map.deck_of(p.st.y):
			continue
		var d := at.distance_to(Vector2(q.st.x, q.st.y))
		if d < best_d:
			best_d = d
			best = q
	return best


func _strike(p: Player, at: Vector2, damage: int) -> void:
	var q := _beside(p, at, false)
	var to := at if q == null else Vector2(q.st.x, q.st.y)
	tell_shot(Net.SHOT_BLOW, q != null, Vector2(p.st.x, p.st.y), to, p.st.y)
	server.chat.sound(Net.SOUND_BLOW, p.st.x, p.st.y, p.slot)
	if q != null:
		hurt(q, damage, p)


func hurt(q: Player, damage: int, by: Player) -> void:
	## A wound. What it does to the body is worked out with everything else in
	## Crew.update_vitals on the next tick.
	if q.cond == Net.COND_OK:
		server.chat.sound(Net.SOUND_CRY, q.st.x, q.st.y, q.slot)
	# (a wound that kills goes a little past the line, so that the next breath of good air does not undo it)
	q.health = maxf(q.health - damage, Net.HEALTH_DEAD - 1.0)
	q.wounds = minf(q.wounds + damage, Net.HEALTH_FULL - Net.HEALTH_DEAD + 1.0)
	if q.pirate and by != null:
		server.pirates.attacked(q, by)


func tell_shot(kind: int, hit: bool, from: Vector2, to: Vector2, row: int) -> void:
	var msg := PackedByteArray([Net.S_SHOT, kind, 1 if hit else 0, 0, 0, 0, 0, 0, 0, 0, 0])
	msg.encode_s16(3, roundi(from.x * 16.0))
	msg.encode_s16(5, roundi(from.y * 16.0))
	msg.encode_s16(7, roundi(to.x * 16.0))
	msg.encode_s16(9, roundi(to.y * 16.0))
	for q: Player in server.players:
		if q != null and q.peer != null and server.map.deck_of(q.st.y) == server.map.deck_of(row) \
				and Vector2(q.st.x, q.st.y).distance_to(from) <= SHOT_SEEN:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
