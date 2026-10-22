extends RefCounted
## Weapons and wounds: shooting (judged against what the shooter saw), blows,
## wounds, healing with a patch or a first-aid kit.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")

const TREAT_TICKS := 60             # one use of a first-aid kit takes 3 s
const SHOT_TICKS := 6                # a pistol fires at most this often
const SHOTGUN_PACE := 1.5            # (v80) a shotgun takes this much longer between shots (2.0 until v80)
const RELOAD_TICKS := 30             # putting a fresh magazine in takes 1.5 s
const BLOW_TICKS := 16               # a blow with a baton
const HIT_RADIUS := 0.45             # a shot passing this close (in cells) to somebody hits them
const FRIEND_CLOSE := 1.25          # (v78) a friend this close (in cells, across and down) to the shooter is never hit
const PRONE_AIMED := 1.0             # (v78) one lying down is hit only by a shot aimed this close to it
const SHOT_SEEN := 24                # a shot is drawn for everybody this close on its deck
# (v70, the author's J2) injuries
const BLEED_CHANCE := 0.25           # a bullet starts bleeding this often (a pellet: PELLET_BLEED)
const PELLET_BLEED := 0.1
const BLEED_RATE := 0.5              # health a second it costs (as a wound)
const BLEED_SECONDS := 90.0          # and it stops by itself after this long
const HEAVY_HIT := 25.0              # a wound this big at once may break a bone...
const BREAK_CHANCE := 0.2            # ... this often (an arm or a leg, by lot)
const BLOW_CONCUSS := 0.15           # a blow concusses this often (a stun baton: STUN_CONCUSS)
const STUN_CONCUSS := 0.3
const BLAST_CONCUSS := 0.5           # a bomb's blast
const FLASH_CONCUSS := 0.3           # a flashbang's
const CONCUSS_SECONDS := 90.0
const SPLINT_TICKS := 80             # setting a bone takes 4 s (down to half with skill)
const ARM_SLOWER := 2.0              # a broken arm: the hands are this many times slower...
const ARM_SPREAD := 0.8              # ... and a shot goes up to this many cells off
# (v70, the author's B3) the flashbang
const FLASH_FUSE := 20               # it bursts 1 s after it is thrown
const FLASH_REACH := 4.0             # cells: who sees it this close falls
const FLASH_STUN := 3.0
const ROBOT_STUN := 0.2              # a machine is knocked down for this share of the time
const CAUSE_OTHER := 0               # what a wound came from (see hurt)
const CAUSE_SHOT := 1
const CAUSE_PELLET := 2
const CAUSE_BLOW := 3
const CAUSE_BLAST := 4

var server: GameServer
var bangs: Array = []                # (v70) flashbangs in the air: [tick it bursts, cell, the thrower's slot]
var _rng := RandomNumberGenerator.new()   # (v70) injuries, pellets and wide shots: its own lots


func setup(p_server: GameServer) -> void:
	server = p_server
	bangs = []
	_rng.seed = 7070


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
	## (v70) A shotgun fires a spread, a stun baton knocks down, a flashbang is
	## thrown there, handcuffs go on a pirate lying next to us, a splint sets a bone.
	if p.cond != Net.COND_OK or p.corpse or server.tick < p.ready_tick:
		return
	var item := p.in_hand()
	var rounds := Items.rounds(item)
	var slow := ARM_SLOWER if p.arm else 1.0
	if rounds > 0:
		p.slots[p.hand] = item - 1
		p.ready_tick = server.tick + roundi(SHOT_TICKS * slow * (SHOTGUN_PACE if Items.INFO[item].has("pellets") else 1.0))
		if p.arm:
			at += Vector2(_rng.randf_range(-ARM_SPREAD, ARM_SPREAD), _rng.randf_range(-ARM_SPREAD, ARM_SPREAD))
		if Items.INFO[item].has("pellets"):
			_shotgun(p, clampi(seen_tick, server.tick - Player.HISTORY + 1, server.tick), at, int(Items.INFO[item]["pellets"]))
		else:
			_shoot(p, clampi(seen_tick, server.tick - Player.HISTORY + 1, server.tick), at)
	elif rounds == 0:
		var mag := p.slots.find(Items.ammo_of(item))
		if mag >= 0:
			p.slots[mag] = Net.ITEM_NONE
			p.slots[p.hand] = Items.loaded(item)
			p.ready_tick = server.tick + roundi(RELOAD_TICKS * slow)
	elif Items.INFO.has(item) and Items.INFO[item].has("blow"):
		p.ready_tick = server.tick + roundi(BLOW_TICKS * slow * (1.5 if Items.INFO[item].has("stun") else 1.0))
		_strike(p, at, int(Items.INFO[item]["blow"]), float(Items.INFO[item].get("stun", 0.0)))
	elif item == Net.ITEM_FLASHBANG:
		_throw(p, at)
	elif item == Net.ITEM_CUFFS:
		cuff(p, _beside(p, at, false))
	elif Items.INFO.has(item) and Items.INFO[item].has("heal"):
		var who := _beside(p, at, true)
		if who != null and (who.wounds > 0.0 or who.bleeding > 0):        # (a patch is not wasted on one who has no wounds)
			heal(who, float(Items.INFO[item]["heal"]))
			who.bleeding = 0                 # (v70) a patch stops bleeding
			p.slots[p.hand] = Net.ITEM_NONE
			if who != p:
				server.chat.say("%s заклеивает раны: %s." % [p.name, who.name])
		else:
			_why_not_treated(p, who)
	elif Items.meal(item):
		server.galley.eat(p, _beside(p, at, true))   # (v71) a galley's dish, for oneself or a neighbour
	elif item == Net.ITEM_ROBOT:
		server.robots.deploy(p, Vector2i(roundi(at.x), roundi(at.y)))   # (v62) a security robot set down there
	elif Items.uses(item) > 0 or item == Net.ITEM_SPLINT:
		# a first-aid kit (v70: or a splint): the treatment takes a while, and both must keep still for it
		var who := _beside(p, at, true)
		var needs := who != null and (who.leg or who.arm) if item == Net.ITEM_SPLINT else who != null and (who.wounds > 0.0 or who.injured())
		if needs:
			p.treating = who.slot
			p.work = 0
			p.work_cell = -2
			p.work_total = _treat_ticks(p, item)
			if who == p:
				server.chat.tell(p, "Вы %s: стойте на месте %d с." % ["вправляете себе перелом" if item == Net.ITEM_SPLINT else "обрабатываете свои раны",
					ceili(_treat_ticks(p, item) / float(Net.TICK_HZ))])
		elif item == Net.ITEM_SPLINT:
			server.chat.tell(p, "Шина нужна при переломе: щёлкните по себе (или Z) или по соседу со сломанной рукой или ногой." if who == null
				else "%s переломов нет." % ("У вас" if who == p else "У %s" % who.name))
		else:
			_why_not_treated(p, who)


func treat_self(p: Player) -> void:
	## (v69, the author's note "the first-aid kit doesn't work at all") Z with a kit
	## or a patch in hand: the same as a click on oneself.
	use_at(p, server.tick, Vector2(p.st.x, p.st.y))


func _why_not_treated(p: Player, who: Player) -> void:
	## (v69) A kit or a patch did nothing: say why, so it does not look broken.
	if who == null:
		server.chat.tell(p, "Лечить некого: щёлкните по себе (или Z) или по тому, кто стоит рядом.")
		return
	var whose := "У вас" if who == p else "У %s" % who.name
	if who.prisoner:
		server.chat.tell(p, "%s в наручниках: пленного не лечат аптечкой." % who.name)
		return
	var hunger: float = server.garden.hunger_of(who)
	if who.health < Net.HEALTH_FULL - 0.5 and hunger > 0.5 and who.health >= Net.HEALTH_FULL - who.wounds - hunger - 0.5:
		server.chat.tell(p, "%s нет ран: это голод. Поможет только еда." % whose)
	elif who.health < Net.HEALTH_FULL - 0.5:
		server.chat.tell(p, "%s нет ран: здоровье отнял плохой воздух. Оно вернётся само в нормальном воздухе (или в автодоке)." % whose)
	else:
		server.chat.tell(p, "%s нет ран: лечить нечего." % whose)


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
	var splint := kit == Net.ITEM_SPLINT
	if q == null or q.corpse or q.cond == Net.COND_DEAD or p.cond != Net.COND_OK or (Items.uses(kit) <= 0 and not splint) \
			or p.st.cd > 0 or p.st.dir != Net.DIR_NONE or absi(q.st.x - p.st.x) > 1 or absi(q.st.y - p.st.y) > 1 \
			or (not splint and q.wounds <= 0.0 and not q.injured()) or (splint and not q.leg and not q.arm):
		p.treating = -1
		p.work = 0
		return false
	p.work += 1
	if p.work >= _treat_ticks(p, kit):
		p.train(Net.SKILL_MEDICINE)
		p.work = 0
		if splint:
			# (v70) a splint sets one bone: the leg first (it slows one most)
			set_bone(q)
			p.slots[p.hand] = Net.ITEM_NONE
			server.chat.say("%s вправляет перелом: %s." % [p.name, q.name] if q != p else "%s вправляет себе перелом." % p.name)
			p.treating = -1
			return true
		heal(q, float(Items.MEDKIT_HEAL))
		# (v70) a kit's use also stops bleeding, sets a bone and eases a concussion
		var mended := q.injured()
		q.bleeding = 0
		q.concussed = 0
		if q.leg or q.arm:
			set_bone(q)
		p.slots[p.hand] = kit - 1 if Items.uses(kit) > 1 else Net.ITEM_NONE
		if q != p:
			server.chat.say("%s %s: %s." % [p.name, "оказывает помощь" if mended else "перевязывает раны", q.name])
		if (q.wounds <= 0.0 and not q.injured()) or p.slots[p.hand] == Net.ITEM_NONE:
			p.treating = -1
	return true


func set_bone(q: Player) -> void:
	## (v70) A broken leg (else arm) set.
	if q.leg:
		q.leg = false
		q.st.slow = q.dragging >= 0 or q.dragged_by >= 0 or q.weak
		q.self_dirty = true
	else:
		q.arm = false


func _treat_ticks(p: Player, kit: int = Net.ITEM_NONE) -> int:
	## A treatment takes TREAT_TICKS for one with no skill, down to half that for the best.
	## (v70) Setting a bone with a splint, SPLINT_TICKS.
	return maxi(roundi((SPLINT_TICKS if kit == Net.ITEM_SPLINT else TREAT_TICKS) * (1.0 - 0.5 * p.skill(Net.SKILL_MEDICINE)) * p.pace(server.tick)), 1)


func _stops_shot(x: int, y: int) -> bool:
	## A bullet stops at anything that cannot be walked through: walls, windows, shut doors.
	## (v80, the author's note: "in space you cannot shoot enemies") open space lets it fly on.
	if not server.map.passable(x, y):
		return true
	var d := server.map.door_at(x, y)
	return d >= 0 and server.doors.is_shut(d)


func _shoot(p: Player, seen_tick: int, at: Vector2) -> void:
	var from := place_at(p, seen_tick)      # (v78) from where the shooter stood, quarters and all
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
		if along <= 0.2 or along >= best or spared(p, q, pos, from, at):
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
		hurt(hit, Items.PISTOL_DAMAGE, p, CAUSE_SHOT)


func spared(p: Player, q: Player, pos: Vector2, from: Vector2, at: Vector2) -> bool:
	## (v78, the author's M2 and C1 "B") A shot flies past `q` (drawn at `pos`): a friend right by
	## the shooter (within FRIEND_CLOSE across and down, as in RimWorld) is never hit, so two
	## can fire from one spot; and one lying low is hit only when aimed at (the shot
	## meant for somewhere within PRONE_AIMED of it).
	if q.pirate == p.pirate and absf(pos.x - from.x) <= FRIEND_CLOSE and absf(pos.y - from.y) <= FRIEND_CLOSE:
		return true
	if q.pirate == p.pirate and q.st.hold and q != p:
		return true                      # (v81, the author's human wall) friends fire past one holding the line
	# (v80, the author's question about several bodies on one tile) one out cold on the floor is as low
	return (q.st.prone or q.cond == Net.COND_CRIT) and pos.distance_to(at) > PRONE_AIMED


func _ray(p: Player, from: Vector2, way: Vector2, reach: float) -> float:
	## (v70) How far a shot that way from `p` (standing at `from`) flies before a wall, a shut door or the deck's end stops it.
	var start := Vector2i(p.st.x, p.st.y)
	var t := 0.3
	while t < reach:
		var c := from + way * t
		var cell := Vector2i(roundi(c.x), roundi(c.y))
		if cell != start and (_stops_shot(cell.x, cell.y) or server.map.deck_of(cell.y) != server.map.deck_of(start.y)):
			return t
		t += 0.1
	return reach


func _shotgun(p: Player, seen_tick: int, at: Vector2, pellets: int) -> void:
	## (v70, the author's B3) A spread of pellets: each flies and hits the first it meets.
	var from := place_at(p, seen_tick)
	var aim := at - from
	if aim.length() < 0.1:
		return
	aim = aim.normalized()
	var hits := {}
	for k in pellets:
		var way := aim.rotated(Items.SHOTGUN_SPREAD * (2.0 * k / maxf(pellets - 1, 1) - 1.0) + _rng.randf_range(-0.04, 0.04))
		var best := _ray(p, from, way, float(Items.SHOTGUN_RANGE))
		var hit: Player = null
		for q: Player in server.players:
			if q == null or q == p or q.corpse or q.cond == Net.COND_DEAD or server.map.deck_of(q.st.y) != server.map.deck_of(p.st.y):
				continue
			var pos := place_at(q, seen_tick)
			var along := (pos - from).dot(way)
			if along <= 0.2 or along >= best or spared(p, q, pos, from, at):
				continue
			if (pos - (from + way * along)).length() <= HIT_RADIUS:
				best = along
				hit = q
		tell_shot(Net.SHOT_BULLET, hit != null, from, from + way * best, p.st.y)
		if hit != null:
			hits[hit] = int(hits.get(hit, 0)) + 1
	server.chat.sound(Net.SOUND_SHOTGUN, p.st.x, p.st.y, p.slot)
	if not hits.is_empty():
		p.train(Net.SKILL_GUNS)
	for q: Player in hits:
		hurt(q, Items.PELLET_DAMAGE * int(hits[q]), p, CAUSE_PELLET)
		if int(hits[q]) >= Items.SHOTGUN_KNOCK and q.cond != Net.COND_DEAD:
			stun_for(q, Items.SHOTGUN_KNOCK_SECONDS * (ROBOT_STUN if q.robot else 1.0))   # (v80) a blast at close range


func _throw(p: Player, at: Vector2) -> void:
	## (v70, the author's B3) A flashbang thrown towards `at` (THROW_RANGE at most): it
	## lands short of a wall and bursts FLASH_FUSE ticks later.
	var from := Vector2(p.st.x, p.st.y)
	var way := at - from
	var reach := minf(way.length(), float(Items.THROW_RANGE))
	if reach < 0.1:
		way = Vector2(Net.DX[p.st.facing], Net.DY[p.st.facing])
		reach = 1.0
	way = way.normalized()
	reach = minf(_ray(p, Vector2(p.st.x, p.st.y), way, reach + 0.01), reach)
	var end := from + way * reach
	var cell := Vector2i(roundi(end.x), roundi(end.y))
	if not server.map.passable(cell.x, cell.y):
		cell = Vector2i(p.st.x, p.st.y)
	p.slots[p.hand] = Net.ITEM_NONE
	p.ready_tick = server.tick + BLOW_TICKS
	bangs.append([server.tick + FLASH_FUSE, cell.y * server.map.width + cell.x, p.slot])
	server.chat.sound(Net.SOUND_DROP, cell.x, cell.y, p.slot)


func tick() -> void:
	## (v70) Flashbangs bursting, and bleeding.
	var i := 0
	while i < bangs.size():
		if server.tick >= int(bangs[i][0]):
			var b: Array = bangs[i]
			bangs.remove_at(i)
			flash(int(b[1]))
		else:
			i += 1


func flash(cell: int, stun: float = FLASH_STUN, concuss: float = FLASH_CONCUSS) -> int:
	## (v70) A blinding flash and a bang at that cell: whoever sees it within FLASH_REACH
	## falls (a machine for a moment). Returns how many fell.
	var map := server.map
	var w := map.width
	var at := Vector2i(cell % w, cell / w)
	tell_shot(Net.SHOT_FLASH, false, Vector2(at), Vector2(at), at.y)
	server.chat.sound(Net.SOUND_BANG, at.x, at.y)
	var fell := 0
	for q: Player in server.players:
		if q == null or q.corpse or q.cond == Net.COND_DEAD or map.deck_of(q.st.y) != map.deck_of(at.y):
			continue
		var to := Vector2i(q.st.x, q.st.y)
		if Vector2(to).distance_to(Vector2(at)) > FLASH_REACH:
			continue
		if to != at and not Sight.clear_cached(map, server.doors, at, to, server.replication.lines):
			continue
		stun_for(q, stun * (ROBOT_STUN if q.robot else 1.0))
		if not q.robot and _rng.randf() < concuss:
			concuss_now(q)
		fell += 1
	return fell


func stun_for(q: Player, seconds: float) -> void:
	## (v70) Knocked down for that long (Crew.update_vitals keeps it down).
	q.stun_until = maxi(q.stun_until, server.tick + roundi(seconds * Net.TICK_HZ))


func concuss_now(q: Player) -> void:
	if q.robot:
		return
	if q.concussed == 0 and q.peer != null:
		server.chat.tell(q, "Контузия: в глазах двоится, пульты не разобрать. Пройдёт сама за %d с или с аптечкой." % int(CONCUSS_SECONDS))
	q.concussed = server.tick + roundi(CONCUSS_SECONDS * Net.TICK_HZ)


func injure(q: Player, taken: float, cause: int) -> void:
	## (v70, the author's J2) What a wound may do besides: bleeding, a broken bone, a concussion.
	if q.robot or q.cond == Net.COND_DEAD:
		return
	var bleed := BLEED_CHANCE if cause == CAUSE_SHOT else (PELLET_BLEED if cause == CAUSE_PELLET else 0.0)
	if bleed > 0.0 and q.bleeding == 0 and _rng.randf() < bleed:
		q.bleeding = roundi(BLEED_SECONDS * Net.TICK_HZ)
		if q.peer != null:
			server.chat.tell(q, "У вас кровотечение: остановит пластырь, аптечка или автодок.")
	if taken >= HEAVY_HIT and _rng.randf() < BREAK_CHANCE:
		if _rng.randf() < 0.5 and not q.leg:
			q.leg = true
			q.st.slow = true
			q.self_dirty = true
			server.chat.say("%s: перелом ноги!" % q.name)
		elif not q.arm:
			q.arm = true
			server.chat.say("%s: перелом руки!" % q.name)
	var concuss := BLOW_CONCUSS if cause == CAUSE_BLOW else (BLAST_CONCUSS if cause == CAUSE_BLAST else 0.0)
	if concuss > 0.0 and _rng.randf() < concuss:
		concuss_now(q)


func bleed(p: Player) -> void:
	## (v70) One tick of bleeding (Crew.update_vitals calls it).
	if p.bleeding <= 0 or p.cond == Net.COND_DEAD:
		return
	p.bleeding -= 1
	var lost := BLEED_RATE / Net.TICK_HZ
	p.health = maxf(p.health - lost, Net.HEALTH_DEAD - 1.0)
	p.wounds = minf(p.wounds + lost, Net.HEALTH_FULL - Net.HEALTH_DEAD + 1.0)
	if p.bleeding == 0 and p.peer != null:
		server.chat.tell(p, "Кровь остановилась сама.")


func cuff(p: Player, q: Player) -> void:
	## (v70, the author's J5) Handcuffs on a pirate who is down: he is our prisoner.
	## What he fought with falls to the floor.
	if q == null or not q.pirate or q.robot or q.prisoner or q.corpse or q.cond != Net.COND_CRIT:
		server.chat.tell(p, "Заковать можно только пирата, который лежит рядом (без сознания или оглушён)." if q == null or not q.pirate or q.prisoner
			else ("Робота не заковать." if q.robot else "Он ещё держится на ногах: сначала собейте его (электрошокер, граната, или пусть потеряет сознание)."))
		return
	p.slots[p.hand] = Net.ITEM_NONE
	server.prisons.take(q, p)


func _beside(p: Player, at: Vector2, self_too: bool) -> Player:
	## Whoever a click next to us means: ourselves (if `self_too` and the click
	## was on us), else of those in the cells around us (diagonals too) the one
	## nearest the click. A click is never quite on the cell, and the one
	## clicked may be in mid-step, so this is forgiving.
	var from := Vector2(p.st.x, p.st.y)
	# (v69) a click anywhere on our own cell is on us: the client rounds the mouse to a cell
	# the same way (GameScreen._fires_at), and the old 0.5 radius missed the cell's corners
	if self_too and Vector2i(roundi(at.x), roundi(at.y)) == Vector2i(p.st.x, p.st.y):
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


func _strike(p: Player, at: Vector2, damage: int, stun: float = 0.0) -> void:
	var q := _beside(p, at, false)
	var to := at if q == null else Vector2(q.st.x, q.st.y)
	tell_shot(Net.SHOT_BLOW, q != null, Vector2(p.st.x, p.st.y), to, p.st.y)
	server.chat.sound(Net.SOUND_ZAP if stun > 0.0 else Net.SOUND_BLOW, p.st.x, p.st.y, p.slot)
	if q != null:
		hurt(q, damage, p, CAUSE_BLOW)
		if stun > 0.0:
			# (v70) a stun baton: down for a while, and now and then concussed
			stun_for(q, stun * (ROBOT_STUN if q.robot else 1.0))
			if _rng.randf() < STUN_CONCUSS - BLOW_CONCUSS:
				concuss_now(q)


func hurt(q: Player, damage: int, by: Player, cause: int = CAUSE_OTHER) -> void:
	## A wound. What it does to the body is worked out with everything else in
	## Crew.update_vitals on the next tick. (v70) It may also injure (see injure).
	if q.cond == Net.COND_OK:
		server.chat.sound(Net.SOUND_CRY, q.st.x, q.st.y, q.slot)
	if damage > 0:
		tell_hit(q)
	var taken := damage * q.toughness        # (v62) heavy armour takes half, our robot more
	# (a wound that kills goes a little past the line, so that the next breath of good air does not undo it)
	q.health = maxf(q.health - taken, Net.HEALTH_DEAD - 1.0)
	q.wounds = minf(q.wounds + taken, Net.HEALTH_FULL - Net.HEALTH_DEAD + 1.0)
	injure(q, taken, cause)
	if (q.pirate or q.ally) and by != null:
		server.pirates.attacked(q, by)
	elif q.bot and by != null:
		server.defence.hurt_by(q, by)         # (v79) it knows where the pirate is now: it runs (or a guard fights)


func tell_hit(q: Player) -> void:
	## (v75, the author's F1) A wound shows: those near on its deck see the figure flash and blood drip.
	var msg := PackedByteArray([Net.S_HIT, Net.BLOOD_METAL if q.robot else Net.BLOOD_FLESH, 0, 0, 0, 0, 0, 0])
	msg.encode_u16(2, q.slot)
	msg.encode_s16(4, q.st.x)
	msg.encode_s16(6, q.st.y)
	for o: Player in server.players:
		if o != null and o.peer != null and server.map.deck_of(o.st.y) == server.map.deck_of(q.st.y) \
				and Vector2(o.st.x, o.st.y).distance_to(Vector2(q.st.x, q.st.y)) <= SHOT_SEEN:
			o.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func tell_shot(kind: int, hit, from: Vector2, to: Vector2, row: int, delay := 0, flight := 0) -> void:
	## Draws a shot for everybody near either end of it on its deck. `hit` is a
	## bool for a hand weapon, or (a ship's shot) 0 shield, Net.LANDED, Net.MISSED.
	## (v56) A ship's shot shows `delay` ticks from now and flies `flight` ticks.
	var msg := PackedByteArray([Net.S_SHOT, kind, int(hit), 0, 0, 0, 0, 0, 0, 0, 0, clampi(delay, 0, 255), clampi(flight, 0, 255)])
	msg.encode_s16(3, roundi(from.x * 16.0))
	msg.encode_s16(5, roundi(from.y * 16.0))
	msg.encode_s16(7, roundi(to.x * 16.0))
	msg.encode_s16(9, roundi(to.y * 16.0))
	for q: Player in server.players:
		if q != null and q.peer != null and server.map.deck_of(q.st.y) == server.map.deck_of(row) \
				and minf(Vector2(q.st.x, q.st.y).distance_to(from), Vector2(q.st.x, q.st.y).distance_to(to)) <= SHOT_SEEN:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func tell_volley(whose: int, kind: int, ends: int, room: int, delay: int, flight: int) -> void:
	## (v56) A ship's shot for the plan on the gun console (and the drone monitor): to all.
	server.to_all(PackedByteArray([Net.S_VOLLEY, whose, kind, ends, room if room >= 0 and room < 255 else 255,
		clampi(delay, 0, 255), clampi(flight, 0, 255)]))


func jolt(kind: int, shot: int, at: Vector2) -> void:
	## (v56) A sound of the ship fight (Net.JOLT_*) at that place: everybody is
	## told, wherever they are. Blows to the hull of the ship one stands on shake the screen;
	## whether they hear it the client decides by the air round them (the author's
	## rule: a vacuum carries no sound, though the deck plates still shake).
	var msg := PackedByteArray([Net.S_JOLT, kind, shot, 0, 0, 0, 0])
	msg.encode_s16(3, roundi(at.x))
	msg.encode_s16(5, roundi(at.y))
	for q: Player in server.players:
		if q != null and q.peer != null:
			q.peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
