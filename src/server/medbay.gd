extends RefCounted
## (v60, the author's S1) The medbay: autodocs and the body scanner. Server only.
##
## An autodoc ('Y' in the map) is a machine on the medbay's wall; the floor cell
## in front of it is its bed. Whoever lies or stands on the bed (anybody alive:
## a wounded crewman dragged there out cold, a bot that walked there itself) is
## healed AUTODOC_HEAL health a second while the ship has power and the autodoc
## works: wounds close first (they never close by themselves), then whatever
## thin air took; somebody out cold comes round as usual once health is back.
## It never brings back the dead (the author's rule: bodies stay). Somebody
## holding "use" at the autodoc tends the one in it: twice as quick, and a lesson
## in medicine every TEND_LESSON_SECONDS.
##
## The body scanner ('X') is groundwork for the complex health the author has in
## mind: pressing "use" at it reports on whoever lies in the nearest autodoc (or
## on the one at the scanner, with nobody there): health, wounds, conscious or
## not, the suit and its oxygen.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Vitals := preload("res://src/server/vitals.gd")

const AUTODOC_HEAL := 3.0            # health a second (the author's A4 default: from nothing to whole in about 35 s)
const TENDED := 2.0                  # this many times quicker with somebody tending
const TEND_LESSON_SECONDS := 5.0
const BOT_GOES_AT := 40.0            # a bot this badly hurt walks to an autodoc by itself (see Stations)
const BOT_LEAVES_AT := 90.0          # and gets up again at this much health

var server: GameServer
var _tended := {}                    # autodoc cell -> the tick somebody last tended it
var _lesson := {}                    # Player slot -> ticks of tending towards the next lesson


func setup(p_server: GameServer) -> void:
	server = p_server
	_tended = {}
	_lesson = {}


func works(doc: int) -> bool:
	return server.powered() and not server.ship.broken.has(doc)


func in_bed(doc: int) -> Player:
	## Who lies or stands on that autodoc's bed (the living only), or null.
	var bed: int = server.map.autodoc.get(doc, -1)
	if bed < 0:
		return null
	var w := server.map.width
	for q: Player in server.players:
		if q != null and not q.corpse and q.cond != Net.COND_DEAD and q.st.y * w + q.st.x == bed:
			return q
	return null


func free_beds(for_whom: Player) -> Array:
	## The beds of working autodocs nobody else lies on.
	var out: Array = []
	for doc: int in server.map.autodoc.keys():
		var q := in_bed(doc)
		if works(doc) and (q == null or q == for_whom):
			out.append(int(server.map.autodoc[doc]))
	return out


func needs_doc(q: Player) -> bool:
	return q.health < Net.HEALTH_FULL - 0.5 or q.wounds > 0.0


func tending(p: Player, doc: int) -> bool:
	## `p` holds "use" at that autodoc: true if there is somebody in it to tend.
	var q := in_bed(doc)
	if q == null or q == p or not works(doc) or not needs_doc(q):
		return false
	_tended[doc] = server.tick
	var n: int = _lesson.get(p.slot, 0) + 1
	if n >= roundi(TEND_LESSON_SECONDS * Net.TICK_HZ):
		n = 0
		p.train(Net.SKILL_MEDICINE)
	_lesson[p.slot] = n
	return true


func tick() -> void:
	for doc: int in server.map.autodoc.keys():
		if not works(doc):
			continue
		var q := in_bed(doc)
		if q == null or not needs_doc(q):
			continue
		var rate := AUTODOC_HEAL * (TENDED if server.tick - int(_tended.get(doc, -100)) <= 1 else 1.0) / Net.TICK_HZ
		if q.wounds > 0.0:
			server.combat.heal(q, rate)
		else:
			q.health = minf(q.health + rate, Net.HEALTH_FULL)
		if not needs_doc(q) and q.peer != null:
			server.chat.tell(q, "Автодок закончил: вы здоровы.")


func scan(p: Player, scanner: int) -> void:
	## The body scanner's report (see above), to the one who pressed "use" at it.
	if not server.powered() or server.ship.broken.has(scanner):
		server.chat.tell(p, "Сканер не работает: нет питания." if not server.powered() else "Сканер сломан.")
		return
	var who: Player = null
	var best := 1 << 30
	var w := server.map.width
	for doc: int in server.map.autodoc.keys():
		var q := in_bed(doc)
		var d := absi(doc % w - scanner % w) + absi(doc / w - scanner / w)
		if q != null and q != p and d < best:
			best = d
			who = q
	if who == null:
		who = p
	server.chat.tell(p, report(who))


static func report(q: Player) -> String:
	var state := "без сознания" if q.cond == Net.COND_CRIT else "в сознании"
	var parts := PackedStringArray()
	parts.append("Сканер: %s, %s." % [q.name, state])
	parts.append("Здоровье %d из %d." % [roundi(maxf(q.health, 0.0)), Net.HEALTH_FULL] if q.health > 0.0
		else "Здоровье на нуле: %d до гибели." % roundi(q.health - Net.HEALTH_DEAD))
	if q.wounds > 0.0:
		parts.append("Раны: %d (сами не затянутся: аптечка, пластырь или автодок)." % roundi(q.wounds))
	else:
		parts.append("Ран нет.")
	if q.has_suit():
		parts.append("Скафандр, кислород %d%%%s." % [roundi(q.tank * 100.0), ", подача включена" if q.supply else ""])
	else:
		parts.append("Без скафандра.")
	return " ".join(parts)
