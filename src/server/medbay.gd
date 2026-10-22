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
## (v70, the author's M1: "a medic should matter") Alone an autodoc only gets its
## patient out of danger: it heals up to UNTENDED_CAP health and no further. (v82, the
## rule "the ship runs fine if nobody touches it, touching gives a bonus") Alone it now
## goes on past UNTENDED_CAP at UNTENDED_SLOW of its pace, so nobody has to stand there. Tended,
## it heals fully, quicker with the tender's medicine skill (a bot tends at half),
## and after FIX_SECONDS of tending it also mends injuries: bleeding, broken bones,
## a concussion.
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
const BOT_LEAVES_AT := 90.0          # and gets up again at this much health (tended; untended at UNTENDED_CAP)
const UNTENDED_CAP := 50.0           # (v70) health an autodoc heals to with nobody tending it at its full pace
const UNTENDED_SLOW := 0.5           # (v82) and past it, alone, this share of that pace
const SKILL_TEND := 1.0              # (v70) a tender with the best medicine skill makes it this much quicker again
const FIX_SECONDS := 3.0             # (v70) of tending, to mend the patient's injuries

var server: GameServer
var _tended := {}                    # autodoc cell -> the tick somebody last tended it
var _lesson := {}                    # Player slot -> ticks of tending towards the next lesson
var _pace := {}                      # (v70) autodoc cell -> how many times quicker its tender makes it
var _fixing := {}                    # (v70) patient slot -> ticks of tending towards mending injuries
var _capped := {}                    # (v70) patient slot -> told the autodoc alone goes no further


func setup(p_server: GameServer) -> void:
	server = p_server
	_tended = {}
	_lesson = {}
	_pace = {}
	_fixing = {}
	_capped = {}


func works(doc: int) -> bool:
	return server.powered() and not server.ship.broken.has(doc)


func in_bed(doc: int, but: Player = null) -> Player:
	## Who lies or stands on that autodoc's bed (the living only, never `but`), or null.
	## (v69, the author's note: two on one bed) Of several, the worst off that needs it:
	## a healthy bot standing there no longer keeps the autodoc from the wounded.
	var bed: int = server.map.autodoc.get(doc, -1)
	if bed < 0:
		return null
	var w := server.map.width
	var best: Player = null
	for q: Player in server.players:
		if q == null or q == but or q.corpse or q.cond == Net.COND_DEAD or q.st.y * w + q.st.x != bed:
			continue
		if best == null or (needs_doc(q) and not needs_doc(best)) or (needs_doc(q) == needs_doc(best) and q.health - q.wounds < best.health - best.wounds):
			best = q
	return best


func free_beds(for_whom: Player) -> Array:
	## The beds of working autodocs nobody else lies on.
	var out: Array = []
	for doc: int in server.map.autodoc.keys():
		var q := in_bed(doc)
		if works(doc) and (q == null or q == for_whom):
			out.append(int(server.map.autodoc[doc]))
	return out


func needs_doc(q: Player) -> bool:
	return q.health < Net.HEALTH_FULL - 0.5 or q.wounds > 0.0 or q.injured()


func tended(doc: int) -> bool:
	return server.tick - int(_tended.get(doc, -100)) <= 1


func leave_at(doc: int) -> float:
	## (v70) The health a bot lying in that autodoc gets up at.
	return BOT_LEAVES_AT


func bed_of(q: Player) -> int:
	## The autodoc whose bed this one lies on (-1: none).
	var c := q.st.y * server.map.width + q.st.x
	for doc: int in server.map.autodoc.keys():
		if int(server.map.autodoc[doc]) == c:
			return doc
	return -1


func tending(p: Player, doc: int) -> bool:
	## `p` holds "use" at that autodoc: true if there is somebody in it to tend
	## (v69: somebody else, even when `p` stands on the bed too).
	var q := in_bed(doc, p)
	if q == null or not works(doc) or not needs_doc(q):
		return false
	if not tended(doc):
		server.usage.note(p, "tend")       # (v82) once each time somebody starts tending
	_tended[doc] = server.tick
	_pace[doc] = 1.0 + ((TENDED - 1.0) + SKILL_TEND * p.skill(Net.SKILL_MEDICINE)) * server.stations.share(p)
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
		var by_hand := tended(doc)
		var slow := not by_hand and q.health >= UNTENDED_CAP
		if slow:
			# (v70) out of danger: (v82) it goes on slowly alone, quicker with somebody tending
			if q.peer != null and not _capped.has(q.slot):
				_capped[q.slot] = true
				server.chat.tell(q, "Автодок вывел вас из опасности и долечивает медленно. Если кто-то держит E у автодока, он лечит быстрее и вылечит травмы.")
		else:
			_capped.erase(q.slot)
		var rate := AUTODOC_HEAL * (float(_pace.get(doc, TENDED)) if by_hand else (UNTENDED_SLOW if slow else 1.0)) / Net.TICK_HZ
		if by_hand and q.injured():
			var n: int = _fixing.get(q.slot, 0) + 1
			_fixing[q.slot] = n
			if n >= roundi(FIX_SECONDS * Net.TICK_HZ):
				_fixing.erase(q.slot)
				q.heal_injuries()
				q.self_dirty = true
				server.chat.say("Автодок под присмотром: у %s остановлена кровь, кости и голова в порядке." % q.name)
		if q.wounds > 0.0:
			server.combat.heal(q, rate)
		else:
			q.health = minf(q.health + rate, Net.HEALTH_FULL)
		if not needs_doc(q) and q.peer != null:
			server.chat.tell(q, "Автодок закончил: вы здоровы.")


func scan(p: Player, scanner: int) -> void:
	## The body scanner's report (see above), to the one who pressed "use" at it.
	server.usage.note(p, "scan")           # (v82)
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
	# (v70) injuries
	var hurt := PackedStringArray()
	if q.bleeding > 0:
		hurt.append("кровотечение")
	if q.leg:
		hurt.append("перелом ноги")
	if q.arm:
		hurt.append("перелом руки")
	if q.concussed > 0:
		hurt.append("контузия")
	if not hurt.is_empty():
		parts.append("Травмы: %s (шина, аптечка или автодок под присмотром)." % ", ".join(hurt))
	if q.has_suit():
		parts.append("Скафандр, кислород %d%%%s." % [roundi(q.tank * 100.0), ", подача включена" if q.supply else ""])
	else:
		parts.append("Без скафандра.")
	return " ".join(parts)
