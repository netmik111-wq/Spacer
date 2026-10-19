extends RefCounted
## (v63, the road plan: the author's R2, R4, R5, R6, R8) The road between
## fights: calls on the comms console, quests, SOS sectors, the chapter's two
## missions, and help for a ship dry of fuel. Server only.
##
## The comms console ('K' on the bridge) shows one call at a time: a short
## story from Tales and two to four answers. Anybody at the console answers for
## the ship; nobody answering in ANSWER_SECONDS takes the event's plain answer.
## A call comes now and then on arriving in a quiet place (EVENT_CHANCE), never
## in a fight. Some answers are blue: open only because somebody aboard has the
## job or the skill, or the locker holds the thing (Tales: "need").
##
## Quests (at most MAX_QUESTS at a time, no time limit) point at a sector 2 to 4
## jumps away, marked on the chart: cargo for a station (delivered on arrival),
## a named pirate to beat there, a wreck's black box to bring back to the supply
## locker. The chapter's missions are quests of their own: find the lost convoy's
## log (offered 3 to 6 jumps out), then catch the courier with the flagship's
## codes, which show the flagship's rooms and take one step off its growth.
## About one quiet sector in seven sends an SOS (sos_at): answering it may bring
## survivors for the reserve, salvage, or a pirate trap.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Tales := preload("res://src/server/tales.gd")
const Plants := preload("res://src/shared/plants.gd")
const Player := preload("res://src/server/player.gd")

const ANSWER_SECONDS := 90.0         # a call nobody answers takes its plain answer after this long
const CALL_DELAY := 8.0              # a call on arriving comes this long after (the director's breather)
const EVENT_CHANCE := 0.35           # how often arriving somewhere quiet brings a call
const SOS_SHARE := 0.15              # of the quiet sectors, those that send an SOS
const MAX_QUESTS := 3
const QUEST_NEAR := 2                # quests point this many jumps away...
const QUEST_FAR := 4                 # ... up to this many
const HUNT_DELAY := 6.0              # a bounty's pirate comes out this long after we arrive in its sector
const M1_FROM := 3                   # the first mission is offered this many jumps out from the start...
const M1_TO := 6                     # ... up to this many
const M1_AGAIN := 3                  # turned down, it is offered again this many jumps later
const DRY_DRIFT := 0.3               # out of fuel: this often it is still the drifting can (Director), not a call
const PIRATE_NAMES: Array[String] = ["Ржавый Клык", "Мясник Орро", "Вдова Кесс", "Шрам", "Безносый Тибо", "Капитан Гарь", "Сестра Зола"]

var server: GameServer
var auto := true                     # (tests) false: calls come only by hand
var call := {}                       # the call waiting for an answer: "event", "until" (tick), "choices" (flags)
var last_title := ""                 # the last call's outcome, shown on the console while nobody calls
var last_text := ""
var quests: Array = []               # each {"kind", "at" (Vector2i), "reward", "title", "text", "placed", "part", "name"}
var sos_done := {}                   # SOS sectors answered or passed by: Sectors.key -> true
var chapter := 0                     # 0 the first mission not taken, 1 its convoy sought, 2 the courier sought, 3 the codes are ours
var m1_next := 0                     # (jumps) the first mission may be offered from this many jumps on
var codes := false
var _due_at := -1                    # the tick a call on arriving comes
var _due_event := -1
var _hunt_at := -1                   # the tick a quest's pirate comes out
var _hunt := -1                      # the quest whose pirate we fight (an index into quests), or -1
var _beaten := false
var _dirty := true
var _comms_dirty := true
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	call = {}
	last_title = ""
	last_text = ""
	quests = []
	sos_done = {}
	chapter = 0
	m1_next = 0
	codes = false
	_due_at = -1
	_hunt_at = -1
	_hunt = -1
	_dirty = true
	_comms_dirty = true
	_rng.randomize()


# --------------------------------------------------------------- places

static func sos_at(seed_value: int, at: Vector2i) -> bool:
	## Does that quiet sector send an SOS? (by lot from the game's seed; never the start)
	if at == Vector2i.ZERO or Sectors.kind_at(seed_value, at) != Sectors.EMPTY:
		return false
	var h := hash([seed_value, at.x, at.y, 63])
	return float(h & 0xFFFF) / 65536.0 < SOS_SHARE


func here() -> Vector2i:
	return server.sectors.cell[server.ship.sector]


func entered_sector() -> void:
	## The ship has just arrived: deliveries, a quest's pirate, an SOS, a mission, or now and then a call.
	_due_at = -1
	_hunt_at = -1
	var at := here()
	var kind: int = server.sectors.kind[server.ship.sector]
	# cargo delivered to the station it was for
	for q: Dictionary in quests.duplicate():
		if int(q["kind"]) == Net.QUEST_CARGO and q["at"] == at:
			if int(server.ship.store.get(Net.ITEM_CARGO, 0)) > 0:
				server.ship.store[Net.ITEM_CARGO] = int(server.ship.store[Net.ITEM_CARGO]) - 1
				server.supplies.tell_store()
				_done(q, "Груз доставлен на станцию.")
			else:
				_fail(q, "Груз для станции потерян: его нет в шкафу снабжения.")
	for q: Dictionary in quests:
		if q["at"] == at and (int(q["kind"]) == Net.QUEST_BOUNTY or int(q.get("part", 0)) == 2):
			_hunt_at = server.tick + roundi(HUNT_DELAY * Net.TICK_HZ)
			server.chat.say("Сенсоры видят %s. Он нас тоже заметил." % str(q["name"]))
			return
	if kind == Sectors.FLAGSHIP or server.flagship.is_at(at):
		return
	if sos_at(server.space_seed, at) and not sos_done.has(Sectors.key(at)):
		sos_done[Sectors.key(at)] = true
		_dirty = true
		_due(Tales.find("sos"), 4.0)
		return
	if chapter == 0 and server.jumps >= m1_next:
		var far: int = server.sectors.far_from_start(server.ship.sector)
		if far >= M1_FROM and far <= M1_TO:
			m1_next = server.jumps + M1_AGAIN
			_due(Tales.find("m1"), 4.0)
			return
	if auto and _rng.randf() < EVENT_CHANCE:
		var e := _pick(kind)
		if e >= 0:
			_due(e, CALL_DELAY)


func _due(event: int, seconds: float) -> void:
	_due_event = event
	_due_at = server.tick + roundi(seconds * Net.TICK_HZ)


func _pick(kind: int) -> int:
	var total := 0
	for e: Dictionary in Tales.EVENTS:
		if (e.get("where", []) as Array).has(kind):
			total += int(e["weight"])
	if total == 0:
		return -1
	var roll := _rng.randi_range(1, total)
	for i in Tales.EVENTS.size():
		var e: Dictionary = Tales.EVENTS[i]
		if (e.get("where", []) as Array).has(kind):
			roll -= int(e["weight"])
			if roll <= 0:
				return i
	return -1


func dry_call() -> bool:
	## (the author's R8) Out of fuel for a while: a passing ship calls, now and then.
	## False when it is to be the drifting can as before (Director).
	if not call.is_empty() or server.map.comms.is_empty() or _rng.randf() < DRY_DRIFT:
		return false
	var pool := [Tales.find("dry_trader"), Tales.find("dry_kind")]
	var total := 0
	for i: int in pool:
		total += int(Tales.EVENTS[i]["weight"])
	var roll := _rng.randi_range(1, total)
	for i: int in pool:
		roll -= int(Tales.EVENTS[i]["weight"])
		if roll <= 0:
			return open(i)
	return false


# --------------------------------------------------------------- the call

func open(event: int) -> bool:
	## A call comes in now. False if another waits already.
	if not call.is_empty() or event < 0 or event >= Tales.EVENTS.size():
		return false
	call = {"event": event, "until": server.tick + roundi(ANSWER_SECONDS * Net.TICK_HZ), "flags": PackedByteArray()}
	_refresh_flags()
	var e: Dictionary = Tales.EVENTS[event]
	server.chat.say("Пульт связи: входящий вызов, «%s». Ответить можно с пульта связи на мостике (%d с)." % [e["title"], int(ANSWER_SECONDS)])
	_comms_dirty = true
	return true


func _refresh_flags() -> void:
	var e: Dictionary = Tales.EVENTS[int(call["event"])]
	var flags := PackedByteArray()
	for c: Dictionary in e["choices"]:
		var f := 0
		var need: Dictionary = c.get("need", {})
		if not need.is_empty():
			if need.has("pay"):
				if not _can_pay(need["pay"]):
					f |= Net.CHOICE_SHUT
			else:
				f |= Net.CHOICE_BLUE
				if not _has(need):
					f |= Net.CHOICE_SHUT
		flags.append(f)
	if flags != call["flags"]:
		call["flags"] = flags
		_comms_dirty = true


func _has(need: Dictionary) -> bool:
	## Is somebody of that job, or with that much skill, aboard and alive; is the thing in the locker?
	if need.has("item"):
		return int(server.ship.store.get(int(need["item"]), 0)) > 0
	for p: Player in server.players:
		if p == null or p.pirate or p.ally or p.corpse or p.cond == Net.COND_DEAD:
			continue
		if need.has("job") and p.job == int(need["job"]):
			return true
		if need.has("skill"):
			var s: Array = need["skill"]
			if p.skills[int(s[0])] >= int(s[1]):
				return true
	return false


func _can_pay(pay: Dictionary) -> bool:
	for k: String in pay:
		if _amount(k) < int(pay[k]):
			return false
	return true


func _amount(what: String) -> int:
	match what:
		"credits":
			return server.ship.credits
		"food":
			return int(server.ship.store.get(Net.ITEM_FOOD, 0))
		"medkits":
			return int(server.ship.store.get(Net.ITEM_MEDKIT + Net.MEDKIT_USES, 0))
		"fuel":
			return int(server.ship.store.get(Net.ITEM_FUEL, 0))
	return 0


func answer_asked(p: Player, choice: int) -> void:
	## Somebody at the comms console answers the call.
	if call.is_empty() or not server.systems.at_console(p, server.map.comms):
		return
	_refresh_flags()
	var flags: PackedByteArray = call["flags"]
	if choice >= flags.size() or flags[choice] & Net.CHOICE_SHUT:
		return
	_answer(choice, p.name)


func _answer(choice: int, who: String) -> void:
	var e: Dictionary = Tales.EVENTS[int(call["event"])]
	var c: Dictionary = e["choices"][choice]
	var need: Dictionary = c.get("need", {})
	if need.has("pay"):
		for k: String in need["pay"]:
			_give(k, -int(need["pay"][k]))
	var outs: Array = c["out"]
	var total := 0
	for o: Array in outs:
		total += int(o[0])
	var roll := _rng.randi_range(1, total)
	var out: Array = outs[0]
	for o: Array in outs:
		roll -= int(o[0])
		if roll <= 0:
			out = o
			break
	call = {}
	var said := str(out[1])
	var extra := _apply(out[2])
	last_title = "%s: %s" % [e["title"], c["text"]]
	last_text = said + extra
	_comms_dirty = true
	server.chat.say("Связь, «%s» (%s): %s%s" % [e["title"], who if who != "" else "без ответа", said, extra])
	server.supplies.tell_store()


func _apply(fx: Dictionary) -> String:
	## Does what the outcome says. Returns what to add to its text (a quest not taken...).
	var extra := ""
	for k: String in fx:
		var n := int(fx[k])
		match k:
			"credits", "food", "fuel", "medkits":
				_give(k, n)
			"parts":
				_store(Net.ITEM_PART, n)
			"patches":
				_store(Net.ITEM_PATCH, n)
			"probe":
				_store(Net.ITEM_PROBE, n)
			"drone":
				_store(Net.ITEM_DRONE, n)
			"hull":
				server.ship.hull = clampi(server.ship.hull + n, 1, server.ship.hull_max)
				server.crew.tell_campaign()
			"reserve":
				var was: int = server.reserve
				server.reserve = mini(server.reserve + n, Net.RESERVE_MAX)
				if server.reserve == was:
					extra += " Резерв полон: места для них нет."
				server.crew.tell_campaign()
			"seeds":
				for i in n:
					_store(Plants.seed_item(_rng.randi_range(0, Plants.BOUGHT - 1)), 1)
			"hybrid":
				for i in n:
					_store(Plants.seed_item(Plants.TUBER if _rng.randf() < 0.5 else Plants.HERB), 1)
			"gear":
				for i in n:
					_store(server.outfit.loot(server.sectors.far_from_start(server.ship.sector), _rng), 1)
			"hurt":
				_hurt(float(n))
			"hole":
				for i in n:
					server.systems.breach_random()
			"glitch":
				server.systems.power_glitch()
			"raid":
				if server.derelict.pirates_can_come():
					server.derelict.pirates_come(server.director._party(), true)
			"quest":
				extra += _new_quest(n)
			"mission":
				extra += _mission(n)
	return extra


func _give(what: String, n: int) -> void:
	match what:
		"credits":
			server.ship.credits = maxi(server.ship.credits + n, 0)
		"food":
			_store(Net.ITEM_FOOD, n)
		"fuel":
			_store(Net.ITEM_FUEL, n)
		"medkits":
			_store(Net.ITEM_MEDKIT + Net.MEDKIT_USES, n)


func _store(item: int, n: int) -> void:
	server.ship.store[item] = maxi(int(server.ship.store.get(item, 0)) + n, 0)


func _hurt(amount: float) -> void:
	## One of the crew, by lot, is hurt (a wound that does not close by itself).
	var who: Array = []
	for p: Player in server.players:
		if p != null and not p.pirate and not p.ally and not p.corpse and p.cond == Net.COND_OK:
			who.append(p)
	if who.is_empty():
		return
	var p: Player = who[_rng.randi_range(0, who.size() - 1)]
	p.wounds = minf(p.wounds + amount, Net.HEALTH_FULL)
	p.health = minf(p.health, Net.HEALTH_FULL - p.wounds)
	p.self_dirty = true
	server.chat.say("Пострадал(а): %s." % p.name)


# --------------------------------------------------------------- quests

func _target(kinds: Array, near: int, far: int, toward_goal: bool = false) -> Vector2i:
	## A sector of one of those kinds that far away, by lot (a little further if none is); Vector2i.MAX if none.
	var found := _targets(kinds, near, far, toward_goal)
	if found.is_empty():
		found = _targets(kinds, near, far + 2, toward_goal)
	if found.is_empty():
		return Vector2i.MAX
	return found[_rng.randi_range(0, found.size() - 1)]


func _targets(kinds: Array, near: int, far: int, toward_goal: bool) -> Array:
	var at := here()
	var goal := Sectors.goal_of(server.space_seed)
	var found: Array = []
	for dx in range(-far, far + 1):
		for dy in range(-far, far + 1):
			var c := at + Vector2i(dx, dy)
			var d := absi(dx) + absi(dy)
			if d < near or d > far or c == Vector2i.ZERO or c == goal or server.flagship.in_area(c):
				continue
			if toward_goal and Sectors.jumps_between(c, goal) >= Sectors.jumps_between(at, goal):
				continue
			if kinds.has(Sectors.kind_at(server.space_seed, c)) and not _taken(c):
				found.append(c)
	return found


func _taken(c: Vector2i) -> bool:
	for q: Dictionary in quests:
		if q["at"] == c:
			return true
	return false


func _new_quest(kind: int) -> String:
	if _side_quests() >= MAX_QUESTS:
		return " Но у нас уже %d заданий: больше не взять." % MAX_QUESTS
	var q := {"kind": kind, "placed": false, "part": 0, "name": ""}
	var at := Vector2i.MAX
	match kind:
		Net.QUEST_CARGO:
			at = _target([Sectors.STATION], QUEST_NEAR, QUEST_FAR)
			if at != Vector2i.MAX:
				_store(Net.ITEM_CARGO, 1)
				q["title"] = "Груз для станции"
				q["text"] = "Доставить ящик из шкафа снабжения на станцию в секторе %s." % Sectors.name_at(server.space_seed, at)
		Net.QUEST_BOUNTY:
			at = _target([Sectors.EMPTY, Sectors.METEORS, Sectors.DERELICT], QUEST_NEAR, QUEST_FAR)
			q["pirate"] = PIRATE_NAMES[_rng.randi_range(0, PIRATE_NAMES.size() - 1)]
			q["name"] = "пиратский корабль «%s»" % q["pirate"]
			q["title"] = "Награда за голову"
			q["text"] = "Найти и разбить %s в секторе %s." % [q["name"], Sectors.name_at(server.space_seed, at)] if at != Vector2i.MAX else ""
		Net.QUEST_BLACKBOX:
			at = _target([Sectors.DERELICT], QUEST_NEAR, QUEST_FAR)
			q["title"] = "Чёрный ящик"
			q["text"] = "Найти чёрный ящик на обломках в секторе %s и принести в шкаф снабжения." % Sectors.name_at(server.space_seed, at) if at != Vector2i.MAX else ""
	if at == Vector2i.MAX:
		return " Но подходящего сектора поблизости не нашлось."
	q["at"] = at
	var d := Sectors.jumps_between(here(), at)
	q["reward"] = [30, 40, 30][kind] + 8 * d
	quests.append(q)
	_dirty = true
	return " Награда: %d кредитов." % int(q["reward"])


func _side_quests() -> int:
	var n := 0
	for q: Dictionary in quests:
		if int(q["kind"]) != Net.QUEST_MISSION:
			n += 1
	return n


func _mission(part: int) -> String:
	var q := {"kind": Net.QUEST_MISSION, "placed": false, "part": part, "name": ""}
	var at := Vector2i.MAX
	if part == 1:
		at = _target([Sectors.DERELICT], QUEST_NEAR, QUEST_FAR)
		q["title"] = "Пропавший конвой"
		q["text"] = "Найти обломки конвоя в секторе %s и принести бортовой журнал в шкаф снабжения." % Sectors.name_at(server.space_seed, at) if at != Vector2i.MAX else ""
		q["reward"] = 60
	else:
		at = _target([Sectors.EMPTY, Sectors.METEORS, Sectors.DERELICT], QUEST_NEAR, QUEST_FAR, true)
		if at == Vector2i.MAX:
			at = _target([Sectors.EMPTY, Sectors.METEORS, Sectors.DERELICT], QUEST_NEAR, QUEST_FAR)
		q["name"] = "курьер пиратов"
		q["title"] = "Коды флагмана"
		q["text"] = "Перехватить курьера пиратов в секторе %s: у него коды флагмана." % Sectors.name_at(server.space_seed, at) if at != Vector2i.MAX else ""
		q["reward"] = 80
	if at == Vector2i.MAX:
		return " Но сектор пока не найден: флот повторит запрос."
	q["at"] = at
	chapter = part
	quests.append(q)
	_dirty = true
	return ""


func _done(q: Dictionary, why: String) -> void:
	quests.erase(q)
	server.ship.credits += int(q["reward"])
	var extra := ""
	if int(q["kind"]) == Net.QUEST_MISSION and int(q["part"]) == 1:
		_store(server.outfit.loot(server.sectors.far_from_start(server.ship.sector), _rng, true), 1)
		extra = " Флот прислал ящик снаряжения (в шкафу снабжения)."
	elif int(q["kind"]) == Net.QUEST_MISSION and int(q["part"]) == 2:
		chapter = 3
		codes = true
		server.flagship.growth = maxi(server.flagship.growth - 1, 0)
		extra = " Коды флагмана наши: в бою будут видны все его отсеки, а его подготовка отброшена на шаг назад."
	server.chat.say("Задание «%s» выполнено. %s Награда: %d кредитов.%s" % [q["title"], why, int(q["reward"]), extra])
	server.supplies.tell_store()
	_dirty = true
	if int(q["kind"]) == Net.QUEST_MISSION and int(q["part"]) == 1:
		open(Tales.find("m2"))


func _fail(q: Dictionary, why: String) -> void:
	quests.erase(q)
	server.chat.say("Задание «%s» провалено. %s" % [q["title"], why])
	_dirty = true


func derelict_arrived(cells: PackedInt32Array) -> void:
	## (Derelict) A wreck has come alongside: if a quest's black box is on it, it lies somewhere on board.
	if cells.is_empty():
		return
	for q: Dictionary in quests:
		var boxed := int(q["kind"]) == Net.QUEST_BLACKBOX or (int(q["kind"]) == Net.QUEST_MISSION and int(q["part"]) == 1)
		if boxed and not bool(q["placed"]) and q["at"] == here():
			if server.put_on_floor(cells[_rng.randi_range(0, cells.size() - 1)], Net.ITEM_BLACKBOX):
				q["placed"] = true
				server.chat.say("Сигнал чёрного ящика идёт с брошенного корабля: он где-то на борту.")


func pirates_beaten() -> void:
	## (Gunnery) The pirate ship alongside is wrecked, taken, broken off or paid us off.
	if _hunt >= 0:
		_beaten = true


func _hunt_tick() -> void:
	if _hunt_at >= 0 and server.tick >= _hunt_at:
		var d = server.derelict
		if server.pirates.aboard() > 0 or not d.pirates_can_come():
			_hunt_at = server.tick + Net.TICK_HZ
			return
		_hunt_at = -1
		var q := {}
		for k: Dictionary in quests:
			if k["at"] == here() and (int(k["kind"]) == Net.QUEST_BOUNTY or int(k.get("part", 0)) == 2):
				q = k
		if q.is_empty():
			return
		var yard = server.shipyard
		var was: int = yard.force_class
		if int(q["kind"]) == Net.QUEST_MISSION:
			yard.force_class = Net.ECLASS_GUNSHIP
		var design: Dictionary = yard.make(server.director._party(), true, d._pirate_spots())
		yard.force_class = was
		if design.is_empty():
			return
		design["name"] = "Корабль «%s»" % q["pirate"] if int(q["kind"]) == Net.QUEST_BOUNTY else "Курьер пиратов «Вестник»"
		if d.pirates_come(server.director._party(), true, design):
			_hunt = quests.find(q)
			_beaten = false
	if _hunt >= 0 and not server.derelict.here:
		var q: Dictionary = quests[_hunt] if _hunt < quests.size() else {}
		_hunt = -1
		if q.is_empty():
			return
		if _beaten:
			_done(q, "Цель уничтожена.")
		elif int(q["kind"]) == Net.QUEST_MISSION:
			var at := _target([Sectors.EMPTY, Sectors.METEORS, Sectors.DERELICT], QUEST_NEAR, QUEST_FAR, true)
			if at != Vector2i.MAX:
				q["at"] = at
				q["text"] = "Перехватить курьера пиратов в секторе %s: у него коды флагмана." % Sectors.name_at(server.space_seed, at)
				server.chat.say("Курьер ушёл: по перехвату он теперь в секторе %s." % Sectors.name_at(server.space_seed, at))
			_dirty = true
		else:
			_fail(q, "Цель ушла.")
	elif _hunt >= 0 and _beaten and server.gunnery.enemy_hull <= 0:
		# wrecked or broken off: it stays alongside as a wreck, but the job is done
		var q: Dictionary = quests[_hunt] if _hunt < quests.size() else {}
		_hunt = -1
		if not q.is_empty():
			_done(q, "Цель уничтожена.")


# --------------------------------------------------------------- the tick

func tick() -> void:
	if server.over != Net.OVER_NONE:
		return
	if not call.is_empty():
		if server.tick >= int(call["until"]):
			_unanswered()
		elif server.tick % Net.TICK_HZ == 0:
			_refresh_flags()
	elif _due_at >= 0 and server.tick >= _due_at:
		if server.gunnery.fighting() or server.pirates.aboard() > 0:
			_due_at = server.tick + Net.TICK_HZ        # never in a fight: it waits
		else:
			_due_at = -1
			open(_due_event)
	_hunt_tick()
	if server.tick % Net.TICK_HZ == 0:
		_boxes()
	if _comms_dirty:
		_comms_dirty = false
		server.to_all(comms_packet())
	if _dirty or (server.flagship.awake and server.tick % (2 * Net.TICK_HZ) == 0):
		_dirty = false
		server.to_all(story_packet())


func _unanswered() -> void:
	## Nobody answered: the plain answer, or the first that can be taken.
	_refresh_flags()
	var e: Dictionary = Tales.EVENTS[int(call["event"])]
	var flags: PackedByteArray = call["flags"]
	var pick := int(e.get("plain", 0))
	if flags[pick] & Net.CHOICE_SHUT:
		pick = flags.size() - 1
		for i in flags.size():
			if not flags[i] & Net.CHOICE_SHUT:
				pick = i
				break
	_answer(pick, "")


func _boxes() -> void:
	## A black box put into the supply locker completes the quest it was for (the mission first).
	if int(server.ship.store.get(Net.ITEM_BLACKBOX, 0)) <= 0:
		return
	var best := {}
	for q: Dictionary in quests:
		if bool(q["placed"]) and (int(q["kind"]) == Net.QUEST_BLACKBOX or int(q["kind"]) == Net.QUEST_MISSION):
			if best.is_empty() or int(q["kind"]) == Net.QUEST_MISSION:
				best = q
	if best.is_empty():
		return
	server.ship.store[Net.ITEM_BLACKBOX] = int(server.ship.store[Net.ITEM_BLACKBOX]) - 1
	_done(best, "Чёрный ящик доставлен.")


func admin_call(event: int) -> void:
	## (admin) That event's call now (255: any that fits this sector); a call already waiting is dropped.
	call = {}
	if event == 255:
		event = _pick(server.sectors.kind[server.ship.sector])
	open(event)


func changed() -> void:
	_dirty = true


# --------------------------------------------------------------- packets

func comms_packet() -> PackedByteArray:
	var out := PackedByteArray([Net.S_COMMS, Net.COMMS_CALL if not call.is_empty() else Net.COMMS_QUIET, 0, 0])
	var title := last_title
	var text := last_text
	var choices: Array = []
	var flags := PackedByteArray()
	if not call.is_empty():
		var e: Dictionary = Tales.EVENTS[int(call["event"])]
		out.encode_u16(2, maxi(int(call["until"]) - server.tick, 0) / Net.TICK_HZ)
		title = e["title"]
		text = e["text"]
		for c: Dictionary in e["choices"]:
			choices.append(c["text"])
		flags = call["flags"]
	_put_text(out, title)
	_put_text(out, text)
	out.append(choices.size())
	for i in choices.size():
		out.append(flags[i])
		_put_text(out, choices[i])
	return out


static func _put_text(out: PackedByteArray, text: String) -> void:
	var b := text.to_utf8_buffer()
	var at := out.size()
	out.resize(at + 2)
	out.encode_u16(at, b.size())
	out.append_array(b)


func story_packet() -> PackedByteArray:
	var f = server.flagship
	var flags := 0
	if f.awake:
		flags |= Net.STORY_FLAGSHIP | Net.STORY_AWAKE
	if f.caught():
		flags |= Net.STORY_CAUGHT
	if server.garden.starving():
		flags |= Net.STORY_STARVING
	if codes:
		flags |= Net.STORY_CODES
	var out := PackedByteArray([Net.S_STORY, flags])
	out.resize(9)
	var at: Vector2i = f.where()
	out.encode_s16(2, at.x)
	out.encode_s16(4, at.y)
	out[6] = f.growth
	out.encode_u16(7, f.seconds_to_grow())
	out.append(quests.size())
	for q: Dictionary in quests:
		var kind := int(q["kind"])
		var n := out.size()
		out.resize(n + 7)
		out[n] = kind
		out.encode_s16(n + 1, (q["at"] as Vector2i).x)
		out.encode_s16(n + 3, (q["at"] as Vector2i).y)
		out.encode_u16(n + 5, int(q["reward"]))
		_put_text(out, q["title"])
		_put_text(out, q["text"])
	# the SOS sectors in the chart's window not answered yet
	var marks: Array = []
	for i in server.sectors.count:
		var c: Vector2i = server.sectors.cell[i]
		if sos_at(server.space_seed, c) and not sos_done.has(Sectors.key(c)):
			marks.append([Net.MARK_SOS, c])
	out.append(marks.size())
	for m: Array in marks:
		var n := out.size()
		out.resize(n + 5)
		out[n] = int(m[0])
		out.encode_s16(n + 1, (m[1] as Vector2i).x)
		out.encode_s16(n + 3, (m[1] as Vector2i).y)
	return out


# --------------------------------------------------------------- saving

func save() -> Dictionary:
	var qs: Array = []
	for q: Dictionary in quests:
		var c := q.duplicate()
		c["at"] = [(q["at"] as Vector2i).x, (q["at"] as Vector2i).y]
		qs.append(c)
	return {"quests": qs, "sos": sos_done.keys(), "chapter": chapter, "m1_next": m1_next, "codes": codes,
		"last_title": last_title, "last_text": last_text}


func load_from(d: Dictionary) -> void:
	quests = []
	for q: Dictionary in d.get("quests", []):
		var c := q.duplicate()
		c["at"] = Vector2i(int(q["at"][0]), int(q["at"][1]))
		c["kind"] = int(c["kind"])
		c["reward"] = int(c["reward"])
		c["part"] = int(c.get("part", 0))
		quests.append(c)
	sos_done = {}
	for k in d.get("sos", []):
		sos_done[int(k)] = true
	chapter = int(d.get("chapter", 0))
	m1_next = int(d.get("m1_next", 0))
	codes = bool(d.get("codes", false))
	last_title = str(d.get("last_title", ""))
	last_text = str(d.get("last_text", ""))
	_dirty = true
	_comms_dirty = true
