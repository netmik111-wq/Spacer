extends SceneTree
## Checks sight and sound on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/sighttest.gd
## Sight: a cone ahead made of two eyes, 160 degrees in the light and 60 in
## the dark, stopped by walls and shut doors. Sound: heard within its range on
## its own deck, through air only; in a vacuum only right next to it.
## Who a client is told about: only the characters its own one sees, feels
## right next to it, or sees by their flashlight (Replication).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Sight := preload("res://src/shared/sight.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26240, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.keep_heard = true
	var map := server.map
	var doors := server.doors

	print("two eyes")
	var light := Sight.eye_arcs(false)
	var dark := Sight.eye_arcs(true)
	_expect(light.size() == 2 and float(light[1][1]) - float(light[0][0]) == 160.0 and float(light[0][1]) - float(light[0][0]) == 85.0,
		"in the light: two eyes of 85 degrees, 160 together")
	_expect(float(dark[1][1]) - float(dark[0][0]) == 60.0, "in the dark: 60 together")
	_expect(float(light[0][1]) > float(light[1][0]), "the eyes overlap in the middle")
	_expect(Sight.eye_arcs(false, 1).size() == 1, "an eye can be left out (for when one is lost)")

	print("what is seen")
	var me := Vector2(8, 4)
	_expect(Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(14, 4), light, Sight.SIGHT_REACH), "ahead along the corridor")
	_expect(Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(10, 5), light, Sight.SIGHT_REACH), "and well to the side")
	_expect(not Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(6, 4), light, Sight.SIGHT_REACH), "but not behind")
	_expect(not Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(9, 2), light, Sight.SIGHT_REACH), "nor through a wall")
	_expect(Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(8, 5), light, Sight.SIGHT_REACH)
		and not Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(8, 5), dark, Sight.SIGHT_REACH), "in the dark the side is lost")
	_expect(Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(10, 4), dark, Sight.DARK_REACH)
		and not Sight.sees(map, doors, me, Net.DIR_RIGHT, Vector2i(12, 4), dark, Sight.DARK_REACH), "and only %d cells are made out without light" % Sight.DARK_REACH)

	print("what is heard")
	var a := server.crew.new_player("Слушатель")
	var b := server.crew.new_player("Ходок")
	a.st.place(8, 4)
	b.st.place(12, 4)
	server.air.refill()
	server.chat.sound(Net.SOUND_STEP, b.st.x, b.st.y, b.slot)
	_expect(a.heard.size() == 1 and b.heard.is_empty(), "footsteps 4 cells off are heard (not by the one walking)")
	a.heard.clear()
	server.chat.sound(Net.SOUND_STEP, 18, 4)
	_expect(a.heard.is_empty(), "10 cells off they are not")
	server.chat.sound(Net.SOUND_HISS, 18, 4)
	_expect(a.heard.size() == 1, "but air rushing out is")
	a.heard.clear()
	server.chat.sound(Net.SOUND_STEP, 8, 20)
	_expect(a.heard.is_empty(), "a sound on the other deck is not heard")
	for i in server.air.air.size():
		server.air.air[i] = 0.0
	server.chat.sound(Net.SOUND_STEP, b.st.x, b.st.y, b.slot)
	_expect(a.heard.is_empty(), "in a vacuum nothing is heard")
	server.chat.sound(Net.SOUND_STEP, 9, 4)
	_expect(a.heard.size() == 1, "except right next to one (felt through the suit)")
	a.heard.clear()
	server.air.refill()
	server.air.air[a.st.y * map.width + a.st.x] = 0.0
	server.chat.sound(Net.SOUND_STEP, b.st.x, b.st.y, b.slot)
	_expect(a.heard.is_empty(), "standing in a vacuum oneself, too")
	server.air.refill()
	a.heard.clear()
	b.st.place(1, 4)
	b.st.dir = Net.DIR_RIGHT
	a.st.place(3, 4)
	for t in 24:
		server._tick()
	var door_heard := false
	for h: Array in a.heard:
		door_heard = door_heard or int(h[0]) == Net.SOUND_DOOR
	_expect(door_heard, "a door is heard opening")

	print("who the server tells about whom")
	b.st.dir = Net.DIR_NONE
	a.st.dir = Net.DIR_NONE
	a.st.place(8, 4)
	a.st.facing = Net.DIR_RIGHT
	_expect(_told(a, b, 14, 4) == "seen", "one ahead along the corridor is sent")
	_expect(a.known.has(a.slot), "and so is one's own character")
	_expect(_told(a, b, 6, 4) == "hidden", "one behind is not: the client is told it went out of sight")
	_expect(_told(a, b, 9, 2) == "", "nor is one behind a wall")
	_expect(_told(a, b, 7, 4) == "seen", "one right behind is felt, so sent")
	server.ship.power_out_until = server.tick + 1000
	server.replication.sight_changed()
	_expect(not server.powered() and _told(a, b, 13, 4) == "hidden", "in the dark one 5 cells ahead is not sent")
	b.slots[0] = Net.ITEM_FLASHLIGHT_ON
	b.hand = 0
	_expect(_told(a, b, 6, 4) == "seen", "unless their flashlight gives them away")
	b.slots[0] = Net.ITEM_NONE
	server.ship.power_out_until = 0
	server.replication.sight_changed()
	a.cond = Net.COND_CRIT
	_expect(_told(a, b, 14, 4) == "hidden" and a.known.size() == 1, "one out cold is told about nobody but itself")
	a.cond = Net.COND_OK

	server.stop()
	server.free()
	print("SIGHTTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _told(viewer, other, x: int, y: int) -> String:
	## Puts `other` at x, y and lets the server work out what it tells viewer's
	## client now (as a send would): "seen", "hidden" (just went out of sight) or "".
	other.st.place(x, y)
	viewer.view_cx = viewer.st.x >> Net.CHUNK_SHIFT
	viewer.view_cy = server.map.local_y(viewer.st.y) >> Net.CHUNK_SHIFT
	var said := ""
	for i in 2 + server.replication.SEEN_GRACE:
		server.tick += 1
		var recs: PackedByteArray = server.replication._characters(viewer, false)
		for o in range(0, recs.size(), Net.ENT_BYTES):
			if recs.decode_u16(o) == other.slot:
				said = "hidden" if recs[o + 6] == Net.FACING_HIDDEN else "seen"
	if said == "" and viewer.known.has(other.slot):
		said = "seen"                        # (already known and unchanged)
	return said


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
