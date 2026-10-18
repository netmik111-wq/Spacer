extends RefCounted
## (v60, the author's S2) Blast doors: whoever watches a holomap monitor can lock
## any door of our ship against boarders, or all of them at once. Server only.
##
## A locked door (Doors.blast) still opens for our own crew, bots included
## (Net.ACCESS_OURS), but not for pirates while the ship has power: a pirate that
## walks into it stands there cutting through it, CUT_SECONDS of work for one
## (two together cut twice as fast); then the door is wrecked open (jammed) until
## somebody mends it. Without power the locks do not hold (as every lock aboard).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

const CUT_SECONDS := 12.0            # (the author's A7 default) for one pirate to cut through a locked blast door

var server: GameServer
var cut := {}                        # door -> ticks of cutting done on it


func setup(p_server: GameServer) -> void:
	server = p_server
	cut = {}


func asked(p: Player, which: int) -> void:
	## Somebody at a holomap locks a door (or unlocks it: the same door again), or every one.
	if p.cond != Net.COND_OK or not server.systems.at_console(p, server.map.holo):
		return
	if not server.powered():
		server.chat.tell(p, "Нет питания: замки бронедверей не держат.")
		return
	var doors := server.doors
	var n: int = server.map.other_first_door
	if which == Net.BLAST_ALL or which == Net.BLAST_NONE:
		var on := 1 if which == Net.BLAST_ALL else 0
		for d in n:
			doors.blast[d] = on
		if on == 0:
			cut.clear()
		server.chat.say("%s %s." % [p.name, "блокирует все двери корабля: они открываются только для своих" if on == 1
			else "снимает блокировку со всех дверей"])
		return
	if which < 0 or which >= n:
		return
	doors.blast[which] = 1 - doors.blast[which]
	if doors.blast[which] == 0:
		cut.erase(which)
	server.chat.tell(p, "Дверь %s." % ("заблокирована: открывается только для своих" if doors.blast[which] == 1 else "разблокирована"))


func locked_count() -> int:
	return server.doors.blast.slice(0, server.map.other_first_door).count(1)


func tick() -> void:
	## Pirates walking into a locked blast door cut through it.
	var doors := server.doors
	var map := server.map
	for p: Player in server.players:
		if p == null or not p.pirate or p.corpse or p.cond != Net.COND_OK or p.st.dir == Net.DIR_NONE:
			continue
		var d := map.door_at(p.st.x + Net.DX[p.st.dir], p.st.y + Net.DY[p.st.dir])
		if d < 0 or not doors.blocks(d, p.st.access):
			continue
		var done: int = cut.get(d, 0) + 1
		cut[d] = done
		if done % Net.TICK_HZ == 0:
			server.chat.sound(Net.SOUND_BLOW, p.st.x, p.st.y, p.slot)
		if done >= roundi(CUT_SECONDS * Net.TICK_HZ):
			cut.erase(d)
			doors.blast[d] = 0
			doors.jammed[d] = 1
			doors.ready[d] = server.tick
			server.replication.sight_changed()
			server.chat.say("Пираты прорезали бронедверь! Она заклинена открытой, пока её не починят.")
