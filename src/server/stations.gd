extends RefCounted
## (v55) Our own crew at their posts in a fight, the bots that take the
## captain's orders, the battle position the pilot picks, and our people
## boarding a pirate ship. Server only.
##
## Posts mirror the pirates' (EnemyCrew): whoever stands at the ship's
## controls facing them flies the ship, and the enemy's shots miss more often
## (more with a pilot by job, a little more again with somebody minding the
## engine); nobody there, and nothing is dodged, as before v55. Somebody at the
## shield generator makes it refill faster. The gun console is where shots are
## fired from, as before.
##
## Bots (the author's notebook: "bots and people are the ship's crew; bots play
## on their own and carry out the orders of whoever commands the ship") take
## a standing order from the captain, or from anybody while no captain is
## aboard (the author's yes): a post, mending what is broken, following, or
## free (they wander as before). A bot at the gun console fires whatever is
## ready, where the guns aim; one mending takes spare parts and patches from
## the hold. Bots keep to our own ship: they never go out into space.
##
## The battle position (the author's notebook: the engine moves the ship about
## the battlefield; my halfway version, one choice instead of steering): close
## in (as before), keep at a distance (both sides hit less, their boarding comes
## at half the pace), or take its flank (we hit better, dodge worse). Changing
## it is a manoeuvre of MANOEUVRE_SECONDS with no dodge; anything but close in
## needs somebody at the controls and the engine going, and nobody of ours out
## in space.
##
## Boarding: while close in, our people can cross through space to the pirate
## ship. When the first of them steps aboard, its crew come to life as pirates
## (EnemyCrew.come_to_life) and fight; whoever of ours stands in a room with a
## system in it wrecks it a point every SABOTAGE_SECONDS; with its crew all dead
## it is captured (Gunnery._wrecked). It cannot jump away, nor be let go for a
## ransom, while any of ours is aboard.

const Net := preload("res://src/shared/net.gd")
const Paths := preload("res://src/server/paths.gd")
const Player := preload("res://src/server/player.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Vitals := preload("res://src/server/vitals.gd")
const Gear := preload("res://src/shared/gear.gd")
const Upkeep := preload("res://src/shared/upkeep.gd")
const Items := preload("res://src/shared/items.gd")

const HELM_DODGE := 0.15             # the enemy's shots miss this much more often with somebody at the controls
const PILOT_DODGE := 0.10            # (v60) and up to this much more again with the piloting skill (a pilot by job starts at half)
const ENGINE_DODGE := 0.05           # and with somebody minding the engine
const SHIELD_PACE := 1.25            # the shield refills this much faster with somebody at its generator
const BOT_SHARE := 0.5               # (v70, the author's P1: "people should matter more than bots") a bot at a post gives half the help
const MANOEUVRE_SECONDS := 8.0       # to change the battle position, without dodging meanwhile
const FAR_HIT := 0.15                # at a distance both sides hit this much less
const FLANK_HIT := 0.15              # from its flank we hit this much better...
const FLANK_DODGE := 0.5             # ... and dodge only half as well
const BEHIND_HIT := 0.25            # (v59) behind it (by the phase drive only) we hit this much better...
const BEHIND_THEIR := 0.2            # ... and it hits this much worse
const LAPSE_SECONDS := 5.0           # far or flank, nobody at the controls this long: back close in
const SABOTAGE_SECONDS := 8.0        # one of our boarders in a system's room wrecks a point of it this often
const BOT_PLAN_TICKS := 10           # how often a bot under orders looks again at where to go
const BOT_AIR := 0.5                 # a bot does not go where the air is thinner than this
const BOT_SKIP_TICKS := 200          # (v72) how long a bot on work puts off a kind of work it found no way to
# (v68, the author's F1) the pilot's evade: their shots fired in its moment hit EVADE_DODGE less often
const EVADE_SECONDS := 1.5           # the moment, for one without piloting skill...
const EVADE_SKILL := 1.0             # ... and this much longer with the best skill
const EVADE_REST := 12.0             # before it can be pressed again
const EVADE_COST := 40.0             # taken from the SMES each time
# (v70, the author's H1: "a pilot should matter outside fights too") in a meteor
# stream each meteor is seen METEOR_WARN seconds ahead: the pilot at the controls
# steers round it with the evade (space), by lot; a bot at the controls does it by
# itself at half the chance; with nobody there it hits.
const METEOR_WARN := 2.5
const METEOR_DODGE := 0.6            # the chance to steer round it...
const METEOR_SKILL := 0.3            # ... and this much more with the best piloting skill
const METEOR_COST := 10.0            # from the SMES
const EVADE_DODGE := 0.5

var server: GameServer
var position := Net.POS_CLOSE
var goal := Net.POS_NONE             # the position the ship is manoeuvring to (POS_NONE = none)
var manoeuvre_until := 0
var ours_aboard := false             # somebody of ours, alive, is on the pirate ship now
var spots := {}                      # Net.POST_* -> Array of [cell to stand on, facing]
var _at := {}                        # Net.POST_* -> the Player at that post now
var _lapse := 0
var _sabotage := PackedFloat32Array()
var _told := PackedByteArray()
var evade_until := 0                 # (v68) the tick the pilot's evade ends
var evade_ready := 0                 # and the tick it can be pressed again
var meteor_at := 0                   # (v70) the tick a meteor seen coming strikes (0 = none coming)
var meteor_tried := false            # the pilot has steered (or tried) for this one
var meteor_missed := false           # and got the ship out of its way
var meteor_roll := -1.0              # (tests: a fixed lot instead of the dice; -1 = dice)
var alert := Net.ALERT_GREEN         # (v68, the author's J4) the alert level
var _alert_auto := false             # it went to yellow by itself when a pirate ship came
var _fight_seen := false
var volunteers := true               # (v72) free bots come to mend (tests that want things left broken switch it off)
var _spot_jobs := {}                 # (v72) bot slot -> {spot to mend from: the job's cell}, from its last plan
var _logged := {}                    # (v72) bot slot -> the work it last told of in the log
var _forcing := {}                   # (v72) bot slot -> the shutter it last told it raises
var _skip := {}                      # (v72) bot slot -> {task: tick}: work it found no way to, put off till then
var _job_words := {}                 # (v72) bot slot -> how the job it has taken is called (for the log)
var _announced := {}                 # (v74) job cell -> the tick a bot last said aloud it takes it
const ANNOUNCE_TICKS := 30 * Net.TICK_HZ
var _fetch_for := {}                 # (v74) bot slot -> the job it fetches patches or parts for (it holds it meanwhile)
var _alert_bots := {}                # slot -> the order the alert gave that bot (freed when it is called off, if it still has it)
var _progress := {}                  # (v75) bot slot -> [its task, the tick it last reached a cell new to this way, {cells}]
var _avoid := {}                     # (v75) bot slot -> {goal or job cell: tick}: where it got stuck, left alone till then
var _forced := {}                    # (v75) bot slot -> {door: [ticks it forced that door's shutter up]}
const STUCK_TICKS := 20 * Net.TICK_HZ   # (v75, the author's B1) no new cell on its way for this long: the bot is stuck
const AVOID_TICKS := 60 * Net.TICK_HZ   # and leaves that goal alone this long
const FORCE_AGAIN := 2                  # forcing the same shutter this many times within AVOID_TICKS is being stuck too


func setup(p_server: GameServer) -> void:
	server = p_server
	position = Net.POS_CLOSE
	goal = Net.POS_NONE
	evade_until = 0
	evade_ready = 0
	alert = Net.ALERT_GREEN
	_alert_auto = false
	_fight_seen = false
	_alert_bots = {}
	_sabotage.resize(Net.ESYS_COUNT)
	var map := server.map
	spots = {}
	for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD]:
		var list: Array = []
		for c: int in _devices(post).keys():
			list.append_array(_spots_for(c))
		spots[post] = list


func _devices(post: int) -> Dictionary:
	var map := server.map
	match post:
		Net.POST_HELM:
			return map.helm
		Net.POST_GUNS:
			return map.gun_console
		Net.POST_ENGINE:
			return map.engine
		Net.POST_SHIELD:
			return map.shield
	return {}


func _spots_for(target: int) -> Array:
	## Where one can stand to work on that cell (a machine, a door, a hole): [cell, facing] each.
	var map := server.map
	var out: Array = []
	var tx := target % map.width
	var ty := target / map.width
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := tx + dx
			var y := ty + dy
			if (dx == 0 and dy == 0) or not map.walkable(x, y) or map.door_at(x, y) >= 0 or not map.on_ship(y * map.width + x):
				continue
			for f in range(1, 5):
				if map.use_ahead(x, y, f, server.air.holes) == target:
					out.append([y * map.width + x, f])
	return out


# ---------------------------------------------------------------- who stands where

func _scan() -> void:
	## Who is at which post now, and whether any of ours is on the pirate ship.
	var map := server.map
	_at = {}
	ours_aboard = false
	var enemy: bool = server.derelict.here and server.derelict.kind == Net.OTHER_PIRATE and not server.derelict.wreck
	for p: Player in server.players:
		if p == null or p.pirate or p.ally or p.corpse or p.cond == Net.COND_DEAD:
			continue
		if enemy and map.is_other(p.st.y * map.width + p.st.x):
			ours_aboard = true
		if p.cond != Net.COND_OK or not server.powered():
			continue
		var ahead := map.use_ahead(p.st.x, p.st.y, p.st.facing)
		if ahead < 0 or server.ship.broken.has(ahead):
			continue
		for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD]:
			if _devices(post).has(ahead) and not _at.has(post):
				_at[post] = p


func manned(post: int) -> bool:
	return _at.has(post)


func at_post(post: int) -> Player:
	return _at.get(post, null)


func our_dodge() -> float:
	## How much less often the enemy's shots hit us now.
	if not server.gunnery.fighting() or not server.powered() or server.engine_down() or goal != Net.POS_NONE:
		return 0.0
	var pilot: Player = _at.get(Net.POST_HELM, null)
	if pilot == null:
		return 0.0
	var minder: Player = _at.get(Net.POST_ENGINE, null)
	var d := (HELM_DODGE + PILOT_DODGE * pilot.skill(Net.SKILL_PILOT)) * share(pilot) + (ENGINE_DODGE * share(minder) if minder != null else 0.0) \
		+ server.outfit.dodge_bonus() + server.power.engine_dodge()
	return d * (FLANK_DODGE if position == Net.POS_FLANK else 1.0)


func our_hit_bonus() -> float:
	match position:
		Net.POS_FAR:
			return -FAR_HIT
		Net.POS_FLANK:
			return FLANK_HIT
		Net.POS_BEHIND:
			return BEHIND_HIT
	return 0.0


func their_hit_bonus() -> float:
	match position:
		Net.POS_FAR:
			return -FAR_HIT
		Net.POS_BEHIND:
			return -BEHIND_THEIR
	return 0.0


func shield_pace() -> float:
	var p: Player = _at.get(Net.POST_SHIELD, null)
	return 1.0 + (SHIELD_PACE - 1.0) * share(p) if p != null else 1.0


static func share(p: Player) -> float:
	## (v70) How much of a post's help this one gives: a person all of it, a bot half.
	return BOT_SHARE if p != null and p.bot else 1.0


func slows_docking() -> bool:
	return position == Net.POS_FAR and server.gunnery.fighting()


# ---------------------------------------------------------------- the battle position

func position_asked(p: Player, to: int) -> void:
	## The pilot at the ship's controls takes the ship to a battle position.
	if not server.systems.at_console(p, server.map.helm) or to < 0 or to > Net.POS_BEHIND:
		return
	if not server.gunnery.fighting():
		server.chat.tell(p, "Боя нет: позицию выбирать не нужно.")
		return
	if to == (goal if goal != Net.POS_NONE else position):
		return
	if server.engine_down():
		server.chat.tell(p, "Двигатель не работает: манёвр невозможен.")
		return
	if to != Net.POS_CLOSE and server.derelict.someone_outside():
		server.chat.tell(p, "Кто-то из наших снаружи корабля: без них не отойти.")
		return
	if server.outfit.phase_ready():
		# (v59, the author's phase drive) a phase jump: there at once, then it recharges
		server.outfit.phase_used()
		position = to
		goal = Net.POS_NONE
		_lapse = 0
		server.chat.say_bridge("%s включает фазовый привод: корабль мгновенно на позиции «%s». %s Привод перезаряжается %d с." % [
			p.name, Net.POS_NAMES[to].to_lower(), _about(to), int(Gear.PHASE_SECONDS)])
		server.chat.sound(Net.SOUND_PHASE, p.st.x, p.st.y)
		return
	if to == Net.POS_BEHIND:
		if not server.outfit.phase():
			server.chat.tell(p, "Зайти в тыл можно только фазовым приводом (модуль в модульной стойке).")
		else:
			server.chat.tell(p, "Фазовый привод перезаряжается: ещё %d с." % ceili(float(server.ship.phase_ready - server.tick) / Net.TICK_HZ))
		return
	goal = to
	manoeuvre_until = server.tick + roundi(MANOEUVRE_SECONDS * Net.TICK_HZ)
	server.chat.say_bridge("%s ведёт корабль на позицию «%s»: манёвр %d с, пока он идёт, мы не уклоняемся." % [
		p.name, Net.POS_NAMES[to].to_lower(), int(MANOEUVRE_SECONDS)])


func _position_tick() -> void:
	if not server.gunnery.fighting():
		position = Net.POS_CLOSE
		goal = Net.POS_NONE
		_lapse = 0
		return
	if goal != Net.POS_NONE:
		if server.engine_down() or not server.powered():
			goal = Net.POS_NONE
			server.chat.say_bridge("Манёвр сорван: двигатель стоит.")
		elif goal != Net.POS_CLOSE and server.tick % 10 == 0 and server.derelict.someone_outside():
			goal = Net.POS_NONE
			server.chat.say_bridge("Манёвр сорван: кто-то из наших снаружи.")
		elif server.tick >= manoeuvre_until:
			position = goal
			goal = Net.POS_NONE
			_lapse = 0
			server.chat.say_bridge("Корабль на позиции «%s». %s" % [Net.POS_NAMES[position].to_lower(), _about(position)])
	if position == Net.POS_CLOSE:
		return
	if server.tick % 10 == 0 and server.derelict.someone_outside():
		position = Net.POS_CLOSE
		server.chat.say("Кто-то из наших вышел наружу: корабль подходит к пиратам вплотную, чтобы не бросить его.")
		return
	if server.powered() and not server.engine_down() and _at.has(Net.POST_HELM):
		_lapse = 0
		return
	_lapse += 1
	if _lapse >= roundi(LAPSE_SECONDS * Net.TICK_HZ):
		_lapse = 0
		position = Net.POS_CLOSE
		server.chat.say("Позицию некому держать (никого за штурвалом или двигатель стоит): пираты подходят вплотную.")


static func _about(pos: int) -> String:
	match pos:
		Net.POS_FAR:
			return "Обе стороны попадают реже (−%d%%), пираты подходят к шлюзу вдвое медленнее, на абордаж не перейти." % roundi(FAR_HIT * 100)
		Net.POS_FLANK:
			return "Мы попадаем лучше (+%d%%), но уклоняемся вдвое хуже; на абордаж не перейти." % roundi(FLANK_HIT * 100)
		Net.POS_BEHIND:
			return "Мы попадаем лучше (+%d%%), они хуже (−%d%%); на абордаж не перейти." % [roundi(BEHIND_HIT * 100), roundi(BEHIND_THEIR * 100)]
	return "Бой как обычно; к пиратам можно перейти через открытый космос."


# ---------------------------------------------------------------- (v68) the pilot's evade

func evading() -> bool:
	return server.tick < evade_until and server.gunnery.fighting()


func evade_asked(p: Player) -> void:
	## The one at the ship's controls throws the ship aside: the pirates' shots fired in
	## the next moment (longer with piloting skill) hit far less often. It costs the SMES.
	if not server.systems.at_console(p, server.map.helm):
		return
	server.usage.note(p, "evade")          # (v82)
	if meteor_at > 0 and not server.gunnery.fighting():
		_steer(p)
		return
	if not server.gunnery.fighting():
		server.chat.tell(p, "Боя нет: уклоняться не от чего.")
		return
	if server.engine_down() or not server.power.engine_running():
		server.chat.tell(p, "Двигатель не работает: уклонения не будет.")
		return
	if goal != Net.POS_NONE:
		server.chat.tell(p, "Корабль в манёвре: уклониться можно после него.")
		return
	if server.tick < evade_ready:
		server.chat.tell(p, "Уклонение будет готово через %d с." % ceili(float(evade_ready - server.tick) / Net.TICK_HZ))
		return
	if not server.power.spend(EVADE_COST):
		server.chat.tell(p, "В СМЭС не хватает заряда на уклонение (нужно %d)." % int(EVADE_COST))
		return
	evade_until = server.tick + roundi((EVADE_SECONDS + EVADE_SKILL * p.skill(Net.SKILL_PILOT)) * Net.TICK_HZ)
	evade_ready = server.tick + roundi(EVADE_REST * Net.TICK_HZ)
	p.train(Net.SKILL_PILOT)
	if server.arena.on():
		server.arena.dash(server.fleet.on, 0.0)   # (v92) in the fight's space the ship really jumps aside
	server.chat.say_bridge("%s бросает корабль в сторону: уклонение на %.1f с." % [p.name, float(evade_until - server.tick) / Net.TICK_HZ])


# ---------------------------------------------------------------- (v70) meteors

func meteor_seen() -> bool:
	## A meteor is coming (the director's, in a meteor stream): it strikes in
	## METEOR_WARN seconds unless the pilot steers round it. False if one is coming already.
	if meteor_at > 0 or (server.derelict.docked and server.derelict.kind == Net.OTHER_ROCK):
		return false                         # ((v99, my A3 pick) a ship landed on an asteroid is out of the stream's way)
	var rock: bool = server.arena.flying() and server.arena.launch_meteor(server.fleet.on)
	var warn: float = server.arena.ROCK_WARN if rock else METEOR_WARN
	meteor_at = server.tick + roundi(warn * Net.TICK_HZ)
	meteor_tried = false
	meteor_missed = false
	for c: int in server.map.helm.keys():
		server.chat.sound(Net.SOUND_BEEP, c % server.map.width, c / server.map.width)
	if rock:
		# (v96, the author's N2 A, my R1 pick) a real rock in space: steered round, shot apart or stopped by the shield
		server.chat.say_bridge("Метеор по курсу! Удар через %.0f с: пилот, уклонение (пробел) заранее, или разбейте его орудиями." % warn)
	else:
		server.chat.say_bridge("Метеор по курсу! Через %.1f с удар: пилот, уклонение (пробел у штурвала)." % METEOR_WARN)
	return true


func meteor_over() -> void:
	## (v96) The meteor in space struck, passed or was broken (Arena): nothing comes now.
	meteor_at = 0


func bot_steers_round(ship: int) -> bool:
	## (v96, my R2 pick) A meteor in space is near: a bot at the controls (nobody steered yet) throws the ship
	## aside by the old lot, at half a person's chance. True: it does.
	if meteor_tried:
		return false
	var pilot: Player = _at.get(Net.POST_HELM, null)
	if pilot == null or not pilot.bot or not server.power.engine_running() or server.engine_down():
		return false
	meteor_tried = true
	if _lot() >= (METEOR_DODGE + METEOR_SKILL * pilot.skill(Net.SKILL_PILOT)) * share(pilot):
		return false
	server.chat.say_bridge("%s закладывает вираж." % pilot.name)
	return true


func _lot() -> float:
	return meteor_roll if meteor_roll >= 0.0 else server.rng.randf()


func _steer(p: Player) -> void:
	## The pilot steers round the meteor coming.
	if meteor_tried:
		return
	if server.engine_down() or not server.power.engine_running():
		server.chat.tell(p, "Двигатель не работает: увернуться не выйдет.")
		return
	if not server.power.spend(METEOR_COST):
		server.chat.tell(p, "В СМЭС не хватает заряда на манёвр (нужно %d)." % int(METEOR_COST))
		return
	meteor_tried = true
	if server.arena.rocks_flying() > 0:
		# (v96) the meteor flies in space: the evade really throws the ship aside; early enough, it passes by
		server.arena.dash(server.fleet.on, 0.0)
		p.train(Net.SKILL_PILOT)
		server.chat.say_bridge("%s закладывает вираж." % p.name)
		return
	meteor_missed = _lot() < METEOR_DODGE + METEOR_SKILL * p.skill(Net.SKILL_PILOT)
	p.train(Net.SKILL_PILOT)
	server.chat.say_bridge("%s закладывает вираж%s" % [p.name, "." if meteor_missed else ", но не успевает!"])


func _meteor_tick() -> void:
	if meteor_at <= 0 or server.tick < meteor_at:
		return
	if server.arena.rocks_flying() > 0:
		return                               # (v96) it flies in space: it ends there (meteor_over)
	meteor_at = 0
	var pilot: Player = _at.get(Net.POST_HELM, null)
	if not meteor_tried and pilot != null and pilot.bot and server.power.engine_running() and not server.engine_down():
		meteor_missed = _lot() < (METEOR_DODGE + METEOR_SKILL * pilot.skill(Net.SKILL_PILOT)) * share(pilot)
	if meteor_missed:
		server.chat.say_bridge("Метеор прошёл мимо: корабль увернулся.")
		return
	server.systems.breach_random()
	server.hazards.meteor_on_enemy()


# ---------------------------------------------------------------- (v68) the alert

func alert_asked(p: Player, level: int) -> void:
	## The captain (or anybody, with no captain aboard) sets the alert at the ship's controls.
	if level < Net.ALERT_GREEN or level > Net.ALERT_RED or not server.systems.at_console(p, server.map.helm):
		return
	if not may_order(p):
		server.chat.tell(p, "Тревогу объявляет капитан.")
		return
	server.usage.note(p, "alert")          # (v82)
	set_alert(level, p)


func set_alert(level: int, by: Player = null) -> void:
	## Green: as usual. Yellow: the bots that were free go to work. Red: every bot to a
	## post, every blast door locked, the lights dimmed to red, a siren. Everybody hears it.
	if level == alert:
		return
	var was := alert
	alert = level
	_alert_auto = by == null and level == Net.ALERT_YELLOW
	var who := "" if by == null else by.name + ": "
	if was == Net.ALERT_RED and level != Net.ALERT_RED:
		for d in server.map.other_first_door:
			server.doors.blast[d] = 0
		server.blast.cut.clear()
	for slot: int in _alert_bots.keys():
		# (only those still at what the alert told them: a later order from the captain stands)
		var q: Player = server.players[slot] if slot < server.players.size() else null
		if q != null and q.bot and not q.corpse and q.order == int(_alert_bots[slot]):
			_set_order(q, Net.POST_FREE, by)
	_alert_bots = {}
	match level:
		Net.ALERT_GREEN:
			server.chat.say("%sОтбой тревоги. Зелёный уровень." % who)
		Net.ALERT_YELLOW:
			for q: Player in _bots(true):
				if q.order == Net.POST_FREE:
					_set_order(q, Net.POST_REPAIR, by)
					_alert_bots[q.slot] = Net.POST_REPAIR
			server.chat.say("%sЖёлтая тревога! Всем быть наготове.%s" % [who, " (Пиратский корабль рядом.)" if by == null else ""])
		Net.ALERT_RED:
			_all_to_posts(by, true)
			for q: Player in _bots(true):
				_alert_bots[q.slot] = q.order
			if server.powered():
				for d in server.map.other_first_door:
					server.doors.blast[d] = 1
			server.chat.say("%sКрасная тревога! Все по местам, бронедвери заблокированы." % who)


func _alert_tick() -> void:
	var fight: bool = server.gunnery.fighting()
	if fight and not _fight_seen:
		_fight_seen = true
		if alert == Net.ALERT_GREEN:
			set_alert(Net.ALERT_YELLOW)          # (my C1 pick) a pirate ship coming raises yellow by itself
	elif not fight and _fight_seen and server.tick % 20 == 0 and server.pirates.aboard() == 0:
		_fight_seen = false
		if _alert_auto and alert == Net.ALERT_YELLOW:
			set_alert(Net.ALERT_GREEN)


# ---------------------------------------------------------------- orders

func may_order(p: Player) -> bool:
	## The captain gives orders; while no captain is aboard, anybody may (the author's yes).
	if p == null or p.bot or p.pirate or p.corpse or p.cond != Net.COND_OK:
		return false
	if p.job == Net.JOB_CAPTAIN:
		return true
	for q: Player in server.players:
		if q != null and q.peer != null and not q.bot and not q.pirate and not q.corpse and q.job == Net.JOB_CAPTAIN \
				and q.cond != Net.COND_DEAD:
			return false
	return true


func order_asked(p: Player, id: int, post: int) -> void:
	if not may_order(p):
		server.chat.tell(p, "Приказы экипажу отдаёт капитан.")
		return
	# (v68) the captain's own order stands when the alert is called off
	if id == Net.NOBODY:
		_alert_bots = {}
	else:
		_alert_bots.erase(id)
	if id == Net.NOBODY:
		if post == Net.POST_ALL:
			# (v86) every ship of our fleet: its bots to its own posts
			var was: int = server.fleet.on
			for i in server.fleet.size():
				server.fleet.use(i)
				_all_to_posts(p, i != was)
			server.fleet.use(was)
		elif post == Net.POST_FREE:
			for q: Player in _bots():
				_set_order(q, Net.POST_FREE, p)
			server.chat.say("%s: «Отбой, все свободны»." % p.name)
		elif post == Net.POST_ARMS or post == Net.POST_NO_ARMS:
			for q: Player in _bots():
				_arms(q, post == Net.POST_ARMS)
			server.chat.say("%s: «%s»." % [p.name, "Все к оружию: отбиваем абордаж!" if post == Net.POST_ARMS else "Оружие только охране, остальным укрываться."])
		return
	if id >= server.players.size() or post >= Net.POSTS and post != Net.POST_ARMS and post != Net.POST_NO_ARMS:
		return
	var q: Player = server.players[id]
	if q == null or not q.bot or q.corpse:
		return
	if post == Net.POST_ARMS or post == Net.POST_NO_ARMS:
		_arms(q, post == Net.POST_ARMS)
		server.chat.say("%s: «%s, %s»." % [p.name, q.name, "к оружию, отбивай абордаж" if post == Net.POST_ARMS else "не воюй, укрывайся"])
		return
	_set_order(q, post, p)
	server.chat.say("%s: «%s, %s»." % [p.name, q.name, _order_words(post)])


static func _order_words(post: int) -> String:
	match post:
		Net.POST_HELM:
			return "к штурвалу"
		Net.POST_GUNS:
			return "к орудиям"
		Net.POST_ENGINE:
			return "к двигателю"
		Net.POST_SHIELD:
			return "к щитам"
		Net.POST_REPAIR:
			return "чинить всё, что сломано"
		Net.POST_FOLLOW:
			return "за мной"
	return "вольно"


func _bots(aboard := false) -> Array:
	## Our bots; `aboard`: only the crew of the ship of our fleet in place (v86, the author's note: bots were
	## sent to the other ship's posts).
	var out: Array = []
	for q: Player in server.players:
		if q != null and q.bot and not q.corpse and (not aboard or q.fleet_ship == server.fleet.on):
			out.append(q)
	return out


func _arms(q: Player, on: bool) -> void:
	## (v89, the author's note: "or only some of our crew fights back") The bot fights boarders
	## as the guard does (Defence) or runs from them as before.
	if q.job == Net.JOB_GUARD:
		return                               # the guard fights whatever it is told
	if q.defends != on:
		q.defends = on
		server.chat.bot_log(q, "приказ: %s." % ("к оружию" if on else "не воевать"))


func _set_order(q: Player, post: int, by: Player) -> void:
	if q.order != post:
		server.chat.bot_log(q, "приказ: %s." % Net.POST_NAMES[post].to_lower())
		_logged.erase(q.slot)
	_took(q, -1)
	q.order = post
	q.order_by = by.slot if by != null else -1
	q.bot_goal = -1
	q.bot_plan_tick = -1000
	q.bot_step = 0
	q.using = false
	q.st.dir = Net.DIR_NONE


func _all_to_posts(by: Player, quiet: bool = false) -> void:
	## Every bot to a post nobody of the players mans: the controls, the gun console,
	## the shield, the engine, (v60) then the mounted guns; the rest go to work.
	var wanted: Array = []
	for post: int in [Net.POST_HELM, Net.POST_GUNS, Net.POST_SHIELD, Net.POST_ENGINE]:
		if (spots[post] as Array).is_empty():
			continue
		var p: Player = _at.get(post, null)
		if p == null or p.bot:
			wanted.append(post)
	for i in server.map.guns.size():
		var g := server.mounts.gunner(i)
		if server.ship.mounts[i] != Weapons.NONE and (g == null or g.bot):
			wanted.append(Net.POST_MOUNTS)
	var bots := _bots(true)
	for i in bots.size():
		_set_order(bots[i], wanted[i] if i < wanted.size() else Net.POST_REPAIR, by)
	if not quiet:
		server.chat.say("%s: «Все по местам!»" % by.name)


# ---------------------------------------------------------------- a bot under orders

# (v60) what a bot's way leads to
const TASK_POST := 0                 # its post (or after its leader)
const TASK_MEND := 1                 # something to mend
const TASK_LOCKER := 2               # the supply locker: to take what it needs, or put a gun back
const TASK_MOUNT := 3                # a gun mount: to put the gun it carries up, or take one down
const TASK_OXYGEN := 4               # an oxygen station: to fill its suit's tank
const TASK_HEAL := 5                 # an autodoc's bed: to be healed
const TASK_GARDEN := 6               # (v63) a hydroponic tray: to plant, tend, harvest or clear it
const TASK_FUEL := 7                 # (v67) the engine: to pour a can of fuel into the tank
const TASK_LOAD := 8                 # (v68) a gun mount: to push a round it carries into its breech
const TASK_AIR := 9                  # (v75, the author's note: bots broke when the ship ran out of air) to a room with air
const BOT_POURS_BELOW := 400.0       # (v67) a bot on work pours cans from the locker while the tank is below this
const TANK_LOW := 0.35               # (v60) a bot with less in its tank goes to fill it before it works on
const TANK_FULL := 0.95
const SUPPLY_AIR := 0.8              # a bot turns its suit's supply on in air thinner than this


func bot_breathe(p: Player) -> void:
	## (v60, the author's N1: bots use the air stores so they do not die in a vacuum)
	## Any bot, under orders or not: the suit's supply on in thin air, off in good air.
	if p.cond != Net.COND_OK:
		return
	var thin: bool = server.air.air[p.st.y * server.map.width + p.st.x] < SUPPLY_AIR
	var on := thin and p.has_suit() and p.tank > 0.0
	if on != p.supply:
		server.inventory.set_supply(p, on)


func bot_think(p: Player) -> bool:
	## One tick of a bot's mind while it has an order (or, v60, is wounded and an
	## autodoc is free). False: nothing for it to do (it wanders, see Movement).
	if p.cond != Net.COND_OK:
		p.doing = Net.DOING_DOWN
		p.using = false
		p.bot_healing = false
		return true
	_wants_healing(p)
	if server.outside.drive(p):
		return true                          # (v61) out mending the hull (see Outside)
	if p.order == Net.POST_FREE and not p.bot_healing and not _volunteers(p):
		p.doing = Net.DOING_IDLE
		return false
	var map := server.map
	var here := p.st.y * map.width + p.st.x
	if server.tick - p.bot_plan_tick >= BOT_PLAN_TICKS or here != p.bot_from:
		_plan(p, here)
	watch_progress(p)
	if p.bot_step == -1:
		p.st.dir = Net.DIR_NONE
		p.using = false
		if p.st.cd > 0:
			return true
		server.movement.climb(p, true)
		p.bot_plan_tick = -1000
		return true
	if _through_lock(p) or _through_shutter(p):
		return true
	if p.bot_step > 0:
		p.using = false
		p.st.dir = Net.DIR_NONE if server.movement._would_vent(p.st.x, p.st.y, p.bot_step) and not _forced_ahead(p) else p.bot_step
		return true
	p.st.dir = Net.DIR_NONE
	if p.bot_goal == here:
		if p.bot_face > 0 and p.st.facing != p.bot_face:
			p.st.facing = p.bot_face
			p.self_dirty = true
		_work(p)
	elif p.bot_goal < 0 and p.order == Net.POST_FREE:
		return false
	return true


func _through_lock(p: Player) -> bool:
	## (v66) Its next step is into an airlock door that will not open: it presses
	## the door's button or forces it (Systems.get_past) until the door gives.
	if p.bot_step <= 0 or p.st.cd > 0:
		return false
	var ahead := server.map.door_at(p.st.x + Net.DX[p.bot_step], p.st.y + Net.DY[p.bot_step])
	if not server.systems.lock_bars(ahead):
		return false
	if _door_busy(p, ahead):
		p.st.dir = Net.DIR_NONE
		p.using = false
		return true
	return server.systems.get_past(p, ahead, true)


func _through_shutter(p: Player) -> bool:
	## (v72, the author's note: bots did not open the emergency shutter, and mended only after he
	## had raised it) Its way to a repair leads through a shutter that is down (see _route's
	## `shutters`): a bot in a suit holds "use" on it until it is forced up (Repairs), then walks on.
	if p.bot_step <= 0 or p.st.cd > 0 or not p.bot_shutters:
		return false
	var ahead := server.map.door_at(p.st.x + Net.DX[p.bot_step], p.st.y + Net.DY[p.bot_step])
	if ahead < 0 or server.systems.lock_door(ahead) or not server.doors.is_sealed(ahead):
		return false
	p.st.dir = Net.DIR_NONE
	if _door_busy(p, ahead):
		p.using = false                      # (v75) another bot is forcing it already: wait for it
		return true
	if p.st.facing != p.bot_step:
		p.st.facing = p.bot_step
		p.self_dirty = true
	p.using = true
	p.doing = Net.DOING_GOING
	if _forcing.get(p.slot, -1) != ahead:
		_forcing[p.slot] = ahead
		server.chat.bot_log(p, "поднимает аварийный шлюз, чтобы пройти: %s" % _job_words.get(p.slot, "наружу из отсека без воздуха"))
	return true


func _forced_ahead(p: Player) -> bool:
	## (v72) The door of its next step has just had its shutter forced up (by it, on its way to a
	## repair): it goes through, though the pressure behind differs.
	var d := server.map.door_at(p.st.x + Net.DX[p.bot_step], p.st.y + Net.DY[p.bot_step])
	return d >= 0 and p.bot_shutters and server.tick < server.forced_until[d]


func _volunteers(p: Player) -> bool:
	## (v72, the author's "repairs always first"; my B2 pick) A free bot comes to mend when
	## something is broken that no other bot has taken, then goes back to wandering.
	if p.bot_goal >= 0 and p.bot_task in [TASK_MEND, TASK_LOCKER, TASK_OXYGEN, TASK_AIR]:
		return true                          # on its way to it already
	if _short_of_air(p):
		return true                          # (v75) no air here, or its tank runs low: it sees to itself
	if not volunteers or (server.tick + p.slot) % BOT_PLAN_TICKS != 0 or _repair_jobs(p).is_empty():
		return false
	p.bot_plan_tick = -1000
	return true


func _short_of_air(p: Player) -> bool:
	## (v75) Standing where the air is too thin for a bot, or its suit's tank running low.
	var here := p.st.y * server.map.width + p.st.x
	return server.map.on_ship(here) and (server.air.air[here] < BOT_AIR or p.has_suit() and p.tank < TANK_LOW)


func _air_goals(p: Player, goals: Dictionary) -> void:
	## (v75) Every cell of our ship where a bot may breathe: the nearest is where it goes.
	var map := server.map
	for c in map.walk.size():
		if map.walk[c] == 1 and map.door_of[c] < 0 and map.on_ship(c) and server.air.air[c] >= BOT_AIR:
			goals[c] = 0


func _wants_healing(p: Player) -> void:
	## (v60) A badly hurt bot goes to lie in a free autodoc until it is whole enough.
	var m = server.medbay
	if p.bot_healing:
		var doc: int = m.bed_of(p)
		var up: float = m.leave_at(doc) if doc >= 0 else m.BOT_LEAVES_AT
		if p.health >= up and (p.wounds <= 0.0 or up < m.BOT_LEAVES_AT) or m.free_beds(p).is_empty():
			p.bot_healing = false
			p.bot_plan_tick = -1000
	elif p.health < m.BOT_GOES_AT and not m.free_beds(p).is_empty():
		p.bot_healing = true
		p.bot_plan_tick = -1000


func _plan(p: Player, here: int) -> void:
	p.bot_plan_tick = server.tick
	p.bot_from = here
	var goals := {}                    # cell -> facing (0 = any)
	var was := p.bot_task
	_fetch_for.erase(p.slot)
	p.bot_task = TASK_POST
	if p.bot_healing:
		for bed: int in server.medbay.free_beds(p):
			goals[bed] = 0
		p.bot_task = TASK_HEAL
	elif p.has_suit() and (p.tank < TANK_LOW or was == TASK_OXYGEN and p.tank < TANK_FULL) and p.order != Net.POST_FOLLOW \
			and _oxygen_goals(p, goals):
		p.bot_task = TASK_OXYGEN
	else:
		match p.order:
			Net.POST_HELM, Net.POST_GUNS, Net.POST_ENGINE, Net.POST_SHIELD:
				var taken := _taken(p)
				if _post_down(p.order):
					# (v74, the author's note: a bot whose console was broken stood by it doing nothing)
					# it mends what is broken, its own console first if nobody else has it
					p.bot_task = _mend_goals(p, goals, taken, _devices(p.order))
				if p.bot_task == TASK_POST:
					goals.clear()
				for s: Array in spots[p.order] if p.bot_task == TASK_POST else []:
					if not taken.has(int(s[0])) and _breathable(p, int(s[0])):
						goals[int(s[0])] = int(s[1])
			Net.POST_MOUNTS:
				# (v75, the author's note: bots stood at a broken mount and nobody mended it)
				# a gunner mends a broken mount first, if no other bot has that job
				var broken_mounts := {}
				for i in server.map.guns.size():
					if server.ship.mounts[i] != Weapons.NONE and server.ship.broken.has(server.map.guns[i]):
						broken_mounts[server.map.guns[i]] = true
				if _repair_jobs(p).any(func(c: int) -> bool: return broken_mounts.has(c)):
					p.bot_task = _mend_goals(p, goals, _taken(p), broken_mounts)
				if p.bot_task == TASK_POST:
					goals = _mount_post_goals(p)
			Net.POST_REPAIR:
				p.bot_task = _work_goals(p, goals)
			Net.POST_FREE:
				p.bot_task = _mend_goals(p, goals, _taken(p))      # (v72) a free bot only comes to mend
			Net.POST_FOLLOW:
				var lead: Player = server.players[p.order_by] if p.order_by >= 0 and p.order_by < server.players.size() else null
				if lead != null and not lead.corpse and lead.cond != Net.COND_DEAD:
					# (v66) anywhere it can go: aboard, onto a ship alongside, and out into space in a suit
					var w := server.map.width
					for o: int in [1, -1, w, -w]:
						var c := lead.st.y * w + lead.st.x + o
						if server.map.door_of[c] < 0 and (server.map.walkable(c % w, c / w) or p.has_suit() and server.map.floats(c % w, c / w)) \
								and _breathable(p, c):
							goals[c] = 0
	_drop_avoided(p, goals)
	if goals.is_empty() and server.air.air[here] < BOT_AIR and p.order != Net.POST_FOLLOW and server.map.on_ship(here):
		# (v75, the author's note: bots stood in a room with no air till their tanks ran dry)
		# nothing to do here: it goes where there is air
		_air_goals(p, goals)
		_drop_avoided(p, goals)
		if not goals.is_empty():
			p.bot_task = TASK_AIR
	if goals.is_empty():
		p.bot_goal = -1
		p.bot_step = 0
		p.using = false
		p.doing = Net.DOING_IDLE
		_took(p, -1)
		_tell_task(p)
		return
	if goals.has(here):
		p.bot_goal = here
		p.bot_face = goals[here]
		p.bot_step = 0
		p.doing = _doing(p)
		_took(p, _job_of(p, here))
		_tell_task(p)
		return
	var wide: bool = p.order == Net.POST_FOLLOW or not server.map.on_ship(here)
	var suited := p.has_suit()
	var r := _route(here, goals, wide, suited)
	p.bot_shutters = false
	# (v72) through shutters that are down, only if no other way: in a suit, to a repair, or out of a
	# room with no air it is shut in (it lets air in there, never out of a good room into a bad one)
	if int(r[1]) < 0 and suited and p.tank > 0.2 and (p.bot_task == TASK_MEND or server.air.air[here] < BOT_AIR):
		r = _route(here, goals, wide, suited, true)
		p.bot_shutters = int(r[1]) >= 0
	if not p.bot_shutters:
		_forcing.erase(p.slot)
	p.bot_step = r[0]
	p.bot_goal = r[1]
	p.bot_face = int(goals.get(r[1], 0))
	p.using = false
	p.doing = Net.DOING_NO_WAY if p.bot_goal < 0 else (Net.DOING_CARRY if p.bot_task in [TASK_LOCKER, TASK_MOUNT] else
		(Net.DOING_HEAL if p.bot_task == TASK_HEAL else Net.DOING_GOING))
	if p.bot_goal < 0 and p.order == Net.POST_REPAIR and p.bot_task in [TASK_GARDEN, TASK_FUEL, TASK_LOAD, TASK_MOUNT]:
		# (v72) no way to this work (a tray behind a shutter that is down...): it does the next work meanwhile
		var skip: Dictionary = _skip.get(p.slot, {})
		skip[p.bot_task] = server.tick + BOT_SKIP_TICKS
		_skip[p.slot] = skip
		p.bot_plan_tick = -1000
		return
	if p.bot_task == TASK_MEND and p.bot_goal < 0:
		var jobs: Array = (_spot_jobs.get(p.slot, {}) as Dictionary).values()
		_took(p, -1)
		if not jobs.is_empty():
			server.chat.bot_log(p, "не могу добраться: %s." % _job_text(int(jobs[0])), p.order == Net.POST_REPAIR)
		return
	_took(p, _job_of(p, p.bot_goal))
	_tell_task(p)


func _drop_avoided(p: Player, goals: Dictionary) -> void:
	## (v75, the author's B1) Goals and jobs it got stuck on lately are left out for a while.
	var avoid: Dictionary = _avoid.get(p.slot, {})
	if avoid.is_empty():
		return
	for c: int in avoid.keys():
		if server.tick >= int(avoid[c]):
			avoid.erase(c)
	var jobs: Dictionary = _spot_jobs.get(p.slot, {})
	for c: int in goals.keys():
		if avoid.has(c) or p.bot_task == TASK_MEND and avoid.has(int(jobs.get(c, -1))):
			goals.erase(c)


func watch_progress(p: Player) -> void:
	## (v75, the author's B1: "should bots notice when they are stuck?") A bot on its way that has
	## reached no cell new to this way for STUCK_TICKS (it pushes on a door, walks back and forth,
	## forces the same shutter again) drops that goal for AVOID_TICKS, says so in the bots' log and
	## looks for another way or other work.
	var here := p.st.y * server.map.width + p.st.x
	if p.cond != Net.COND_OK or p.bot_goal < 0 or p.bot_goal == here or p.bot_step == 0 and not p.using:
		_progress.erase(p.slot)
		return
	var pr: Array = _progress.get(p.slot, [])
	if pr.is_empty() or int(pr[0]) != p.bot_task:
		_progress[p.slot] = [p.bot_task, server.tick, {here: true}]
		return
	var seen: Dictionary = pr[2]
	if not seen.has(here):
		seen[here] = true
		pr[1] = server.tick
		return
	if server.tick - int(pr[1]) >= STUCK_TICKS:
		stuck(p)


func stuck(p: Player) -> void:
	## (v75) The bot gives up its present goal for a while.
	var avoid: Dictionary = _avoid.get(p.slot, {})
	if p.bot_goal >= 0:
		avoid[p.bot_goal] = server.tick + AVOID_TICKS
	if p.bot_job >= 0:
		avoid[p.bot_job] = server.tick + AVOID_TICKS
	_avoid[p.slot] = avoid
	var what: String = _job_words.get(p.slot, "")
	server.chat.bot_log(p, "застрял по дороге%s: ищу другой путь или другое дело." % (" (%s)" % what if what != "" else ""))
	_took(p, -1)
	_progress.erase(p.slot)
	_forcing.erase(p.slot)
	p.using = false
	p.st.dir = Net.DIR_NONE
	p.bot_plan_tick = -1000


func shutter_forced(p: Player, door: int) -> bool:
	## (v75) A bot forced a shutter up. True: say it in everybody's chat (the first time in a while).
	## The same shutter forced again and again is a bot going round in circles: it is stuck.
	var by: Dictionary = _forced.get(p.slot, {})
	var ticks: Array = (by.get(door, []) as Array).filter(func(t: int) -> bool: return server.tick - t < AVOID_TICKS)
	ticks.append(server.tick)
	by[door] = ticks
	_forced[p.slot] = by
	if ticks.size() > FORCE_AGAIN:
		stuck(p)
	return ticks.size() == 1


func _door_busy(p: Player, door: int) -> bool:
	## (v75, the author's B3) Another bot already works at this door (forcing its shutter, pressing
	## its button): this one waits rather than crowd the doorway.
	for q: Player in server.players:
		if q == null or q == p or not q.bot or q.corpse or q.cond != Net.COND_OK or not q.using:
			continue
		if server.map.door_at(q.st.x + Net.DX[q.st.facing], q.st.y + Net.DY[q.st.facing]) == door:
			return true
	return false


func _job_of(p: Player, goal: int) -> int:
	## The repair job a plan going to `goal` holds: the one mended from that spot, or (v74, the
	## author's note: every bot said «беру пробоину» in turn for one hole) the one it fetches
	## patches or parts for, so other bots leave it alone instead of all running to the locker.
	if goal < 0:
		return -1
	if p.bot_task == TASK_MEND:
		return int((_spot_jobs.get(p.slot, {}) as Dictionary).get(goal, -1))
	if p.bot_task == TASK_LOCKER:
		return int(_fetch_for.get(p.slot, -1))
	return -1


func _doing(p: Player) -> int:
	match p.bot_task:
		TASK_MEND, TASK_GARDEN, TASK_FUEL:
			return Net.DOING_WORK
		TASK_LOCKER, TASK_MOUNT, TASK_OXYGEN:
			return Net.DOING_CARRY
		TASK_HEAL:
			return Net.DOING_HEAL
	return Net.DOING_POST


func _breathable(p: Player, cell: int) -> bool:
	return server.air.air[cell] >= BOT_AIR or (p.has_suit() and p.tank > 0.2)


func _add_spots(p: Player, target: int, goals: Dictionary, taken: Dictionary) -> void:
	for s: Array in _spots_for(target):
		if not taken.has(int(s[0])) and _breathable(p, int(s[0])):
			goals[int(s[0])] = int(s[1])


func _oxygen_goals(p: Player, goals: Dictionary) -> bool:
	if not server.powered():
		return false
	var taken := _taken(p)
	for c: int in server.map.oxygen.keys():
		if not server.ship.broken.has(c) and server.map.on_ship(server.map.fitting_front(c)):
			_add_spots(p, c, goals, taken)
	return not goals.is_empty()


func _mount_post_goals(p: Player) -> Dictionary:
	## (v60) A free mount with a gun on it, nobody else at it or making for it.
	var taken := _taken(p)
	var goals := {}
	var map := server.map
	for i in map.guns.size():
		if server.ship.mounts[i] == Weapons.NONE or server.ship.broken.has(map.guns[i]):
			continue
		var g := server.mounts.gunner(i)
		if g != null and g != p:
			continue
		var mine := {}
		_add_spots(p, map.guns[i], mine, taken)
		var others := false
		for q: Player in server.players:
			if q != null and q != p and q.bot and q.order == Net.POST_MOUNTS and mine.has(q.bot_goal):
				others = true
		if not others:
			goals.merge(mine)
	return goals


func _work_goals(p: Player, goals: Dictionary) -> int:
	## (v60) A bot on "work": a gun it carries goes where it was ordered or back to
	## the locker; then what is broken is mended (it fetches patches and spare parts
	## from the locker first); then the console's orders for the guns are carried out.
	## (v72, the author's "repairs always first") Mending comes before the gun it carries too,
	## unless that gun fills its last free hand.
	var map := server.map
	var mounts = server.mounts
	var taken := _taken(p)
	var gun := _carried_gun(p)
	if gun >= 0 and p.count(Net.ITEM_NONE) == 0:
		return _carry_goals(p, gun, goals, taken)
	# a suit, if it has none and the locker has one
	if not p.has_suit() and _store_suit() >= 0:
		_locker_goals(p, goals, taken)
		if not goals.is_empty():
			return TASK_LOCKER
	# what is broken
	var mend := _mend_goals(p, goals, taken)
	if mend != TASK_POST:
		return mend
	# a gun in its hands
	if gun >= 0:
		return _carry_goals(p, gun, goals, taken)
	# (v68, my G1 pick) in a fight, rounds from the locker into the breeches of the guns that fire them
	if server.gunnery.fighting():
		var need := _mounts_wanting_rounds()
		if not need.is_empty():
			if not _put_off(p, TASK_LOAD):
				for i: int in need:
					if p.count(mounts.ammo_of(i)) > 0:
						_add_spots(p, map.guns[i], goals, taken)
				if not goals.is_empty():
					return TASK_LOAD
			for i: int in need:
				if int(server.ship.store.get(mounts.ammo_of(i), 0)) > 0 and p.count(Net.ITEM_NONE) > 0:
					_locker_goals(p, goals, taken)
					if not goals.is_empty():
						return TASK_LOCKER
	# (v63) the hydroponic trays
	for c: int in server.map.trays if not _put_off(p, TASK_GARDEN) else []:
		if server.garden.can(p, c) == "" and (server.garden.stage[server.garden.tray_of(c)] != Net.GROW_EMPTY or server.garden._best_seed() > 0):
			_add_spots(p, c, goals, taken)
	if not goals.is_empty():
		return TASK_GARDEN
	# (v67) fuel: a can from the locker into the tank at the engine
	if server.ship.tank < BOT_POURS_BELOW:
		if p.count(Net.ITEM_FUEL) > 0:
			for c: int in map.engine.keys() if not _put_off(p, TASK_FUEL) else []:
				if not server.ship.broken.has(c):
					_add_spots(p, c, goals, taken)
			if not goals.is_empty():
				return TASK_FUEL
		elif int(server.ship.store.get(Net.ITEM_FUEL, 0)) > 0 and not map.engine.is_empty():
			_locker_goals(p, goals, taken)
			if not goals.is_empty():
				return TASK_LOCKER
	# the console's orders for the guns
	var i := _haul_job(p)
	p.haul = i
	if i >= 0:
		if mounts.wanted[i] == mounts.WANT_DOWN and not _put_off(p, TASK_MOUNT):
			_add_spots(p, map.guns[i], goals, taken)
			return TASK_MOUNT
		if int(server.ship.store.get(mounts.wanted[i], 0)) > 0:
			_locker_goals(p, goals, taken)
			return TASK_LOCKER
		p.haul = -1                          # (somebody else carries that gun already)
	return TASK_POST


func _put_off(p: Player, task: int) -> bool:
	## (v72) This kind of work had no way to it a moment ago.
	return server.tick < int((_skip.get(p.slot, {}) as Dictionary).get(task, -1))


func _carry_goals(p: Player, gun: int, goals: Dictionary, taken: Dictionary) -> int:
	## A gun in its hands: up onto the mount the gun console wants it on, else back to the locker.
	var i: int = server.mounts.order_for(p.slots[gun])
	if i >= 0 and not server.ship.broken.has(server.map.guns[i]):
		p.haul = i
		_add_spots(p, server.map.guns[i], goals, taken)
		if not goals.is_empty():
			return TASK_MOUNT
	p.haul = -1
	_locker_goals(p, goals, taken)
	return TASK_LOCKER


func _post_down(post: int) -> bool:
	## (v74) Every console of the post is broken: a bot cannot do the post from any of them.
	var devices := _devices(post)
	for c: int in devices.keys():
		if not server.ship.broken.has(c):
			return false
	return not devices.is_empty()


func _mend_goals(p: Player, goals: Dictionary, taken: Dictionary, first: Dictionary = {}) -> int:
	## (v72) What is broken and not taken by another bot: TASK_MEND with the spots to mend it from
	## in `goals` (each spot's job kept in _spot_jobs), TASK_LOCKER for a suit, patches or parts
	## first, or TASK_POST with nothing to mend.
	var jobs := _repair_jobs(p)
	var own := jobs.filter(func(c: int) -> bool: return first.has(c))
	if not own.is_empty():
		jobs = own                          # (v74) a bot at a post mends its own console first
	var spot_job := {}
	_spot_jobs[p.slot] = spot_job
	if jobs.is_empty():
		return TASK_POST
	var fetch := not p.has_suit() and _store_suit() >= 0 or not _supplies_wanted(p).is_empty()
	if not p.has_suit() and _store_suit() >= 0:
		_locker_goals(p, goals, taken)      # a suit first: then every job is in reach
		if not goals.is_empty():
			return TASK_LOCKER
	var mend := {}
	var airless := -1                       # a job only the lack of air keeps this bot from
	for c: int in jobs:
		for s: Array in _spots_for(c):
			var at := int(s[0])
			# (v74) someone passing over the spot of the job it holds does not make it drop the job
			if taken.has(at) and c != p.bot_job or spot_job.has(at):
				continue
			if not _breathable(p, at):
				airless = c
				continue
			mend[at] = int(s[1])
			spot_job[at] = c
	if not mend.is_empty():
		if fetch:
			_locker_goals(p, goals, taken)  # patches or parts first
			if not goals.is_empty():
				var mine: Array = spot_job.values()
				_fetch_for[p.slot] = p.bot_job if mine.has(p.bot_job) else int(mine[0])
				return TASK_LOCKER
		goals.merge(mend)
		return TASK_MEND
	if airless < 0 or p.has_suit() and p.tank > 0.2:
		return TASK_POST                    # the rest is in other bots' hands
	var to := _suited_helper(p)
	server.chat.bot_log(p, "не могу добраться: %s: там нет воздуха, а скафандра нет.%s" % [_job_text(airless),
		" Передаю работу: %s." % to.name if to != null else ""], p.order == Net.POST_REPAIR)
	return TASK_POST


func _suited_helper(p: Player) -> Player:
	## (v72, the author's comment on L1: "if a bot cannot take the job, he passes it to the next with a
	## spacesuit") A bot in a suit with oxygen that mends (on «Работы», or free) to hand the job to; it
	## takes it by itself (a job no bot holds is anybody's), this only names it. Null: none aboard.
	for q: Player in _bots(true):
		if q != p and q.cond == Net.COND_OK and q.has_suit() and q.tank > 0.2 and q.order in [Net.POST_REPAIR, Net.POST_FREE]:
			return q
	return null


func _took(p: Player, job: int) -> void:
	## (v72) The repair job this bot has taken now (-1 = none). A new one is said aloud
	## (the author's "tell in chat that one of the bots is taking the work").
	if job == p.bot_job:
		return
	p.bot_job = job
	if job < 0:
		_job_words.erase(p.slot)
		return
	_job_words[p.slot] = _job_text(job)
	_logged.erase(p.slot)
	# (v74) the same job is said aloud once in a while, whichever bot takes it (the rest go to the log)
	# (v75, the author's B4) only a breach is said in everybody's chat; the rest goes to the bots' tab
	var aloud: bool = server.air.holes.has(job) and server.tick >= int(_announced.get(job, -ANNOUNCE_TICKS)) + ANNOUNCE_TICKS
	if aloud:
		_announced[job] = server.tick
	server.chat.bot_log(p, "беру %s." % _job_words[p.slot], aloud)


func _tell_task(p: Player) -> void:
	## (v72) What the bot sets about now, for the bots' log (repairs are told by _took).
	var words := ""
	match p.bot_task:
		TASK_MEND:
			return
		TASK_LOCKER:
			var want := PackedStringArray()
			for item: int in _supplies_wanted(p):
				want.append(Items.name_of(item).to_lower())
			if not p.has_suit() and _store_suit() >= 0:
				want.append("скафандр")
			words = "идёт к шкафу снабжения" + (": " + ", ".join(want) if not want.is_empty() else "")
		TASK_MOUNT:
			words = "несёт орудие к установке %d" % (p.haul + 1) if p.haul >= 0 else "несёт орудие"
		TASK_OXYGEN:
			words = "заправляет баллон скафандра"
		TASK_HEAL:
			words = "ранен, идёт в автодок"
		TASK_GARDEN:
			words = "работает в гидропонике"
		TASK_FUEL:
			words = "заливает топливо в двигатель"
		TASK_LOAD:
			words = "заряжает орудие"
		TASK_AIR:
			words = "здесь нет воздуха, уходит туда, где он есть"
		_:
			if p.order == Net.POST_FREE:
				return
			words = "работы нет, ждёт" if p.order == Net.POST_REPAIR and p.bot_goal < 0 else \
				("не может встать на пост: %s" % Net.POST_NAMES[p.order].to_lower() if p.bot_goal < 0 else "пост: %s" % Net.POST_NAMES[p.order].to_lower())
	if _logged.get(p.slot, "") == words:
		return                               # (a fresh look at the same work is not news)
	_logged[p.slot] = words
	server.chat.bot_log(p, words + ".")


func _job_text(cell: int) -> String:
	## (v72) How a repair job is called in the log: what is broken and where it is.
	var map := server.map
	var what := "поломку"
	if server.air.holes.has(cell):
		what = "пробоину"
	elif server.ship.broken.has(cell) and map.device_name(cell) != "":
		what = map.device_name(cell)
	elif map.door_of[cell] >= 0:
		var d: int = map.door_of[cell]
		what = "заклинившую дверь" if server.doors.jammed[d] == 1 else "аварийный шлюз"
	return "%s (%s)" % [what, _where(cell)]


func _where(cell: int) -> String:
	## (v72) Where a cell is, in words: the deck, and the nearest named thing in the same room.
	var map := server.map
	var w := map.width
	var room := map.room_of[cell]
	if room < 0:
		for o: int in [1, -1, w, -w]:
			if cell + o >= 0 and cell + o < map.room_of.size() and map.room_of[cell + o] >= 0:
				room = map.room_of[cell + o]
				break
	var deck := map.deck_of_cell(cell)
	var words: String = map.deck_names[deck].to_lower() if deck >= 0 and deck < map.deck_names.size() else "корабль"
	var best := ""
	var best_d := 1e9
	if room >= 0:
		for dy in range(-8, 9):
			for dx in range(-8, 9):
				var x := cell % w + dx
				var y := cell / w + dy
				if x < 0 or y < 0 or x >= w or y >= map.height:
					continue
				var c := y * w + x
				var name := map.device_name(c)
				if name == "" or c == cell:
					continue
				var front := map.fitting_front(c)
				if front >= 0 and map.room_of[front] == room and dx * dx + dy * dy < best_d:
					best_d = dx * dx + dy * dy
					best = name
	return words + (", рядом " + best if best != "" else "")


func _mounts_wanting_rounds() -> Array:
	## (v68) The mounts whose gun fires shells or rockets and whose breech is not full.
	var out: Array = []
	var mounts = server.mounts
	for i in server.map.guns.size():
		if mounts.ammo_of(i) != 0 and mounts.loaded[i] < mounts.LOAD_MAX and not server.ship.broken.has(server.map.guns[i]):
			out.append(i)
	return out


func _carried_gun(p: Player) -> int:
	## The slot of a ship gun the bot carries, or -1.
	for k in p.slots.size():
		if p.slots[k] != Net.ITEM_NONE and Weapons.of_item(p.slots[k]) != Weapons.NONE:
			return k
	return -1


func _store_suit() -> int:
	var s := Net.ITEM_SUIT + Net.SUIT_TANK_STEPS
	return s if int(server.ship.store.get(s, 0)) > 0 else -1


func _locker_goals(p: Player, goals: Dictionary, taken: Dictionary) -> void:
	for c: int in server.map.locker.keys():
		_add_spots(p, c, goals, taken)


func _repair_jobs(p: Player) -> Array:
	## Broken machines, doors gone wrong, holes (with a patch to hand or in the locker).
	## (v72, my B3 pick) Not those another bot has taken (Player.bot_job).
	var map := server.map
	var jobs: Array = []
	for c: int in server.ship.broken.keys():
		jobs.append(c)
	for d in mini(map.other_first_door, map.doors.size()):
		if server.doors.jammed[d] == 1 or server.doors.faulty[d] == 1:
			var at: Vector2i = map.doors[d]
			if server.fleet.mine(at.y * map.width + at.x):   # (v86, the author's note) only aboard this ship of our fleet
				jobs.append(at.y * map.width + at.x)
	if p.count(Net.ITEM_PATCH) > 0 or int(server.ship.store.get(Net.ITEM_PATCH, 0)) > 0:
		for c: int in server.air.holes.keys():
			if not map.is_other(c) and server.fleet.mine(c):
				jobs.append(c)
	for q: Player in server.players:
		if q != null and q != p and q.bot and q.bot_job >= 0 and not q.corpse and q.cond == Net.COND_OK:
			jobs.erase(q.bot_job)
	return jobs


func _supplies_wanted(p: Player) -> Array:
	## (v60) What a bot on "work" should fetch from the locker before it sets to:
	## patches for holes, a spare part for machines and doors (three times quicker).
	var want: Array = []
	var store: Dictionary = server.ship.store
	var holes := false
	for c: int in server.air.holes.keys():
		holes = holes or not server.map.is_other(c) and server.fleet.mine(c)
	if holes and p.count(Net.ITEM_PATCH) == 0 and int(store.get(Net.ITEM_PATCH, 0)) > 0:
		want.append(Net.ITEM_PATCH)
	var machines := not server.ship.broken.is_empty()
	for d in mini(server.map.other_first_door, server.map.doors.size()):
		var at: Vector2i = server.map.doors[d]
		machines = machines or (server.doors.jammed[d] == 1 or server.doors.faulty[d] == 1) and server.fleet.mine(at.y * server.map.width + at.x)
	if not server.complex_repairs:
		if machines and p.count(Net.ITEM_PART) == 0 and int(store.get(Net.ITEM_PART, 0)) > 0:
			want.append(Net.ITEM_PART)
	elif machines:
		# (v71, the author's H1) complex repairs: a toolbox, and the kinds of part the broken things want
		if p.count(Net.ITEM_TOOLBOX) == 0 and int(store.get(Net.ITEM_TOOLBOX, 0)) > 0:
			want.append(Net.ITEM_TOOLBOX)
		var kinds := {}
		for c: int in server.ship.broken.keys():
			kinds[Upkeep.part_for(server.map, c)] = true
		for d in mini(server.map.other_first_door, server.map.doors.size()):
			if server.doors.jammed[d] == 1 or server.doors.faulty[d] == 1:
				kinds[Net.ITEM_PART] = true
		for k: int in kinds.keys():
			if p.count(k) == 0 and int(store.get(k, 0)) > 0:
				want.append(k)
	if p.count(Net.ITEM_NONE) == 0:
		return []
	return want


func _haul_job(p: Player) -> int:
	## The mount whose order this bot carries out: the one it had, else one nobody else has.
	var mounts = server.mounts
	if p.haul >= 0 and p.haul < mounts.wanted.size() and mounts.wanted[p.haul] != mounts.WANT_NONE:
		return p.haul
	for i in mounts.wanted.size():
		if mounts.wanted[i] == mounts.WANT_NONE or server.ship.broken.has(server.map.guns[i]):
			continue
		var free := true
		for q: Player in server.players:
			if q != null and q != p and q.bot and q.haul == i and q.order == Net.POST_REPAIR and q.cond == Net.COND_OK:
				free = false
		if free:
			return i
	return -1


func _taken(p: Player) -> Dictionary:
	## Cells others stand on or make for.
	var out := {}
	for q: Player in server.players:
		if q == null or q == p or q.corpse:
			continue
		out[q.st.y * server.map.width + q.st.x] = true
		if q.bot and q.bot_goal >= 0 and (q.order != Net.POST_FREE or q.bot_task != TASK_POST):   # (v72) a free bot come to mend too
			out[q.bot_goal] = true
	return out


func _route(start: int, goals: Dictionary, wide: bool = false, suited: bool = false, shutters: bool = false) -> Array:
	## [the first step of a shortest way to the nearest of the goals (a direction,
	## -1 = the ladder underfoot, 0 = none), that goal (-1 = none reachable)].
	## Our own ship only, ladders included, around shutters that are down; (v66)
	## through our airlocks (the bot pumps or forces their doors, see _through_lock),
	## and with `wide` onto a ship alongside too, and out into space in a suit. (v72) With
	## `shutters`, through emergency shutters that are down too (a suited bot forces them).
	var map := server.map
	var doors = server.doors
	var systems = server.systems
	return Paths.first_step(map, start, goals, func(nx: int, ny: int) -> bool:
		var j := ny * map.width + nx
		if not (map.walkable(nx, ny) and (wide or map.on_ship(j)) or wide and suited and map.floats(nx, ny)):
			return false
		var door := map.door_of[j]
		# (v70) nor through a welded door
		return not (door >= 0 and (doors.is_sealed(door) and not systems.lock_door(door) and not shutters or doors.welded[door] == 1)))


func _work(p: Player) -> void:
	## What a bot does at the end of its way.
	match p.bot_task:
		TASK_HEAL:
			p.doing = Net.DOING_HEAL
			p.using = false
			return
		TASK_OXYGEN:
			var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
			p.using = server.map.oxygen.has(ahead) and p.tank < TANK_FULL
			p.doing = Net.DOING_CARRY
			if not p.using:
				p.bot_plan_tick = -1000
			return
		TASK_LOCKER:
			_at_locker(p)
			return
		TASK_MOUNT:
			_at_mount(p)
			return
		TASK_FUEL:
			var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
			var k := p.slots.find(Net.ITEM_FUEL)
			if k >= 0:
				p.hand = k
			p.using = ahead >= 0 and k >= 0 and server.repairs.can_pour(p, ahead)
			p.doing = Net.DOING_WORK
			if not p.using:
				p.bot_plan_tick = -1000
			return
		TASK_LOAD:
			var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
			var i := server.map.guns.find(ahead)
			var k := p.slots.find(server.mounts.ammo_of(i)) if i >= 0 and server.mounts.ammo_of(i) != 0 else -1
			if k >= 0:
				p.hand = k
			p.using = k >= 0 and server.mounts.can(p, ahead) == ""
			p.doing = Net.DOING_CARRY
			if not p.using:
				p.bot_plan_tick = -1000
			return
		TASK_GARDEN:
			var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
			p.using = ahead >= 0 and server.garden.can(p, ahead) == ""
			p.doing = Net.DOING_WORK
			if not p.using:
				p.bot_plan_tick = -1000          # done here: on to the next
			return
	match Net.POST_REPAIR if p.bot_task == TASK_MEND else p.order:
		Net.POST_GUNS:
			p.doing = Net.DOING_POST
			var g = server.gunnery
			if g.fighting() and g.ransom == 0 and server.systems.at_console(p, server.map.gun_console) and _a_gun_ready():
				g.fire(p, 255)
		Net.POST_ENGINE:
			p.doing = Net.DOING_POST
			if server.tick % 40 == p.slot % 40:
				_keep_powered()
		Net.POST_REPAIR, Net.POST_FREE:
			var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing, server.air.holes)
			var hole := server.air.holes.has(ahead)
			var door := server.map.door_of[ahead] if ahead >= 0 else -1
			if not hole and not server.ship.broken.has(ahead) and not (door >= 0 and (server.doors.jammed[door] == 1 or server.doors.faulty[door] == 1)):
				p.using = false
				p.bot_plan_tick = -1000          # done here: on to the next
				if p.bot_job >= 0:
					server.chat.bot_log(p, "готово: %s." % _job_words.get(p.slot, "работа"))
					_took(p, -1)
				return
			var item := Net.ITEM_PATCH if hole else Net.ITEM_PART
			if hole and p.count(Net.ITEM_PATCH) == 0:
				p.using = false
				p.doing = Net.DOING_IDLE
				p.bot_plan_tick = -1000          # (off to the locker for one)
				return
			p.using = true
			p.doing = Net.DOING_WORK
		_:
			p.doing = Net.DOING_POST


func _at_locker(p: Player) -> void:
	## (v60) At the supply locker: a gun not wanted goes back in; the gun its order
	## wants, patches, a spare part and a suit come out. Then it goes on.
	var sup = server.supplies
	var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	p.using = false
	if ahead < 0 or not server.map.locker.has(ahead):
		p.bot_plan_tick = -1000
		return
	var gun := _carried_gun(p)
	if gun >= 0 and server.mounts.order_for(p.slots[gun]) < 0:
		sup.store_asked(p, Net.STORE_PUT_ONE, gun)
	if p.haul >= 0 and p.haul < server.mounts.wanted.size():
		var want: int = server.mounts.wanted[p.haul]
		if want != server.mounts.WANT_NONE and want != server.mounts.WANT_DOWN and not p.slots.has(want) \
				and int(server.ship.store.get(want, 0)) > 0:
			sup.store_asked(p, Net.STORE_TAKE, want)
	for item: int in _supplies_wanted(p):
		for n in (2 if item == Net.ITEM_PATCH else 1):
			if int(server.ship.store.get(item, 0)) > 0 and p.count(Net.ITEM_NONE) > 0:
				sup.store_asked(p, Net.STORE_TAKE, item)
	# (v72) a free bot come to mend takes only what mending wants, not cans or rounds
	if p.order == Net.POST_REPAIR and server.ship.tank < BOT_POURS_BELOW and p.count(Net.ITEM_FUEL) == 0 and int(server.ship.store.get(Net.ITEM_FUEL, 0)) > 0 \
			and p.count(Net.ITEM_NONE) > 0 and not server.map.engine.is_empty():
		sup.store_asked(p, Net.STORE_TAKE, Net.ITEM_FUEL)        # (v67) a can for the tank
	if server.gunnery.fighting() and p.order == Net.POST_REPAIR:
		for i: int in _mounts_wanting_rounds():          # (v68) rounds for the breeches, two at a time
			var ammo: int = server.mounts.ammo_of(i)
			while p.count(ammo) < 2 and int(server.ship.store.get(ammo, 0)) > 0 and p.count(Net.ITEM_NONE) > 0:
				sup.store_asked(p, Net.STORE_TAKE, ammo)
	if not p.has_suit() and _store_suit() >= 0 and p.count(Net.ITEM_NONE) > 0:
		sup.store_asked(p, Net.STORE_TAKE, _store_suit())
		var k := p.slots.find(_store_suit())
		if k >= 0:
			p.hand = k
			server.inventory.act(p)          # it puts the suit on
	p.doing = Net.DOING_CARRY
	p.bot_plan_tick = -1000


func _at_mount(p: Player) -> void:
	## (v60) At the gun mount its order is for: the gun it carries goes up (or, with
	## the order to take the gun down, it comes down into empty hands). Holding "use"
	## does it (see Mounts); then it goes on.
	var i := p.haul
	var cell := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	if i < 0 or i >= server.map.guns.size() or cell != server.map.guns[i]:
		p.using = false
		p.bot_plan_tick = -1000
		return
	var want: int = server.mounts.wanted[i]
	if want == server.mounts.WANT_NONE:
		p.using = false
		p.haul = -1
		p.bot_plan_tick = -1000
		return
	if want == server.mounts.WANT_DOWN:
		var empty := -1
		for k in p.slots.size():
			if p.usable(k) and p.slots[k] == Net.ITEM_NONE:
				empty = k
				break
		if empty < 0:
			p.using = false
			p.doing = Net.DOING_IDLE
			return
		p.hand = empty
	else:
		var k := p.slots.find(want)
		if k < 0:
			p.using = false
			p.bot_plan_tick = -1000
			return
		p.hand = k
	p.using = true
	p.doing = Net.DOING_CARRY


func _keep_powered() -> void:
	## (v68, my E1 pick) A bot at the engine minds the power panel beside it for a solo
	## player: the shield, then every mounted gun, powered as far as the reactor allows.
	## It never overcharges and never touches the breakers or the engines.
	var g = server.gunnery
	var ship = server.ship
	if not server.powered():
		return
	if not ship.shield_on:
		g.switch_shield(null, true)
	for i in ship.mounts.size():
		if ship.mounts[i] != Weapons.NONE and ship.armed[i] == 0:
			g.arm(null, i, true)
	if ship.guard != Weapons.NONE and not ship.guard_armed:
		g.arm_guard(null, true)


func _a_gun_ready() -> bool:
	var g = server.gunnery
	var ship = server.ship
	for i in g.charge.size():
		if g.charge[i] >= 1.0 and ship.armed[i] == 1 and g.beam_left[i] == 0 and not ship.broken.has(server.map.guns[i]) \
				and server.mounts.has_round(i):
			return true
	return false


# ---------------------------------------------------------------- boarding

func _boarding() -> void:
	var g = server.gunnery
	var em = server.enemy_crew
	if not g.fighting() or em.o == null:
		_sabotage.fill(0.0)
		return
	if ours_aboard and not em.in_world:
		var who := ""
		for p: Player in server.players:
			if p != null and not p.pirate and not p.ally and not p.corpse and p.cond != Net.COND_DEAD and server.map.is_other(p.st.y * server.map.width + p.st.x):
				who = p.name
				break
		em.come_to_life()
		if g.crewless:
			server.chat.say("%s поднимается на борт дрон-корабля! Его роботы-охранники (%d) включаются. Ядро дронов можно разбить руками: тогда корабль наш." % [who, em.count()])
		else:
			server.chat.say("%s поднимается на борт пиратского корабля! Его экипаж (%d) бросает посты и хватается за оружие." % [who, em.count()])
	if not em.in_world:
		return
	if em.count() < g.boarders_left():
		g.crew_lost(em.count(), em.crossed)
		em.crossed = 0
		if not g.fighting():
			return
	# ours in a room with a system in it wreck it
	var map := server.map
	var hands := PackedInt32Array()
	hands.resize(Net.ESYS_COUNT)
	for p: Player in server.players:
		if p == null or p.pirate or p.ally or p.corpse or p.cond != Net.COND_OK:
			continue
		var cell := p.st.y * map.width + p.st.x
		if not map.is_other(cell):
			continue
		var local: int = server.derelict._local(cell, map.other_at)
		var system: int = g.system_in(em.o.room_of[local]) if local >= 0 and local < em.o.room_of.size() else -1
		if system >= 0 and system != Net.ESYS_CREW:
			hands[system] += 1
	for k in Net.ESYS_COUNT:
		if hands[k] == 0 or k >= g.systems.size() or g.systems[k] == 0:
			_sabotage[k] = 0.0
			continue
		_sabotage[k] += mini(hands[k], 2) / (SABOTAGE_SECONDS * Net.TICK_HZ)
		if _sabotage[k] >= 0.9999:
			_sabotage[k] = 0.0
			g.wear_by_hand(k)


# ---------------------------------------------------------------- every tick

func tick() -> void:
	_scan()
	_position_tick()
	_boarding()
	_alert_tick()
	_meteor_tick()
	var now := packet()
	if now != _told:
		_told = now
		server.to_all(now)


func packet() -> PackedByteArray:
	var ship = server.ship
	var out := PackedByteArray([Net.S_STATIONS, ship.id & 0xFF, ship.id >> 8, position, goal,
		clampi(int(ceil(float(manoeuvre_until - server.tick) / Net.TICK_HZ)), 0, 255) if goal != Net.POS_NONE else 0,
		roundi(our_dodge() * 100.0), 100 + roundi(our_hit_bonus() * 100.0), 100 + roundi(their_hit_bonus() * 100.0)])
	var bits := 0
	for post: int in _at.keys():
		bits |= 1 << (post - 1)
	out.append(bits)
	var bots := _bots()
	bots.sort_custom(func(a: Player, b: Player) -> bool: return a.fleet_ship < b.fleet_ship or a.fleet_ship == b.fleet_ship and a.slot < b.slot)
	out.append(mini(bots.size(), 255))
	for q: Player in bots:
		out.append(q.slot & 0xFF)
		out.append(q.slot >> 8)
		out.append(q.order | (Net.ORDER_ARMS if q.defends or q.job == Net.JOB_GUARD else 0))
		out.append(q.doing if q.cond == Net.COND_OK else Net.DOING_DOWN)
		out.append(q.fleet_ship)            # (v86) the ship of our fleet it is crew of
	# (v68) u8 the alert (ALERT_*), u8 tenths of a second of the evade left, u8 seconds until it is ready again
	out.append(alert)
	out.append(clampi(ceili(float(evade_until - server.tick) * 10.0 / Net.TICK_HZ), 0, 255) if evading() else 0)
	out.append(clampi(ceili(float(evade_ready - server.tick) / Net.TICK_HZ), 0, 255))
	# (v70) u8 tenths of a second until a meteor seen coming strikes (0 = none), u8 1 = the pilot has steered
	out.append(clampi(ceili(float(meteor_at - server.tick) * 10.0 / Net.TICK_HZ), 1, 255) if meteor_at > 0 else 0)
	out.append(1 if meteor_tried else 0)
	return out
