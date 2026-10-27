extends SceneTree
## Checks the campaign saved between evenings, without a network or a window:
##   godot --headless --path . --script res://tools/savetest.gd
## One server plays a while and saves; a second one, started afresh, goes on
## from the save: the same place in space, supplies, reserve, hull, damage,
## air, things on the floor, bodies, and each character for its player.
## A lost campaign leaves no save behind.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Campaign := preload("res://src/server/campaign.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

const PATH := "user://savetest.json"

var failed := 0


func _initialize() -> void:
	Campaign.forget(PATH)
	var a := GameServer.new()
	get_root().add_child(a)
	if a.start(26193, "ship02", 0) != "":
		print("no port")
		quit(1)
		return
	a.director.auto = false
	a.save_path = PATH
	var map := a.map

	# an evening's play
	var p := a.crew.new_player("Аня")
	p.take_job(Net.JOB_MEDIC)
	p.skills[Net.SKILL_MEDICINE] = 77
	p.slots.fill(Net.ITEM_NONE)
	p.add(Net.ITEM_RADIO)
	p.add(Net.ITEM_PISTOL + 5)
	p.st.place(20, 15)
	p.health = 60.0
	p.wounds = 25.0
	var q := a.crew.new_player("Боря")
	q.st.place(24, 11)
	q.add(Net.ITEM_FUEL)
	q.health = -150.0
	_run(a, 2)
	_expect(q.cond == Net.COND_DEAD, "(one of the crew is dead)")
	a.space_seed = 12345
	a.road.build(Vector2i.ZERO)              # (v64) the first cluster of that space
	var arrived: Vector2i = a.sectors.cell[a.sectors.neighbours(a.sectors.start)[0]]
	a.been[Sectors.key(arrived)] = true
	a.road.build(arrived)
	a.ship.sector = a.sectors.here
	a.ship.pos = Vector2(33.0, 21.5)
	a.ship.store[Net.ITEM_PATCH] = 2
	a.ship.credits = 77
	a.reserve = 1
	a.ship.hull = 64
	a.ship.mounts[1] = 2                    # (Weapons.HEAVY) the guns and shield as set up (v49)
	a.ship.armed[1] = 0
	a.ship.hardened = true
	a.ship.shield_on = false
	a.jumps = 9
	a.farthest = 4
	var hole: int = map.hull[3]
	a.systems.breach(hole)
	_run(a, 40)
	var engine: int = map.engine.keys()[0]
	a.ship.broken[engine] = true
	a.power.set_charge(0.0)              # (v61) and the SMES empty: the ship dark
	a.doors.jammed[2] = 1
	a.doors.ready[2] = 0
	a.floor_things[15 * map.width + 22] = PackedByteArray([Net.ITEM_MAG, Net.ITEM_PART, 0, 0])
	var air_cell := 15 * map.width + 3
	var air_there: float = a.air.air[air_cell]
	a.voyage_ticks = 123456
	var health_was := p.health
	var wounds_was := p.wounds
	# (v82) what people used: bots never count
	a.usage.note(p, "evade")
	a.usage.note(p, "evade")
	var bot := a.crew.new_player("Бот")
	bot.bot = true
	a.usage.note(bot, "galley")
	_expect(int(a.usage.used.get("evade", 0)) == 2 and not a.usage.used.has("galley"), "people's use is counted, bots' is not")
	_expect(a.usage.lines()[0] == ["уклонение пилота", 2] and a.usage.lines().size() == a.usage.NAMES.size(), "most used first, the unused listed too")
	_expect(a.save_campaign() and Campaign.exists(PATH), "the campaign is saved")
	var hull_was: int = a.ship.hull                   # (the hole took its share)
	a.stop()
	a.queue_free()

	print("the next evening")
	var b := GameServer.new()
	get_root().add_child(b)
	b.start(26194, "ship02", 0)
	b.director.auto = false
	b.save_path = PATH
	_expect(b.resume_campaign(PATH) == "", "a new server goes on with it")
	_expect(b.space_seed == 12345 and b.sectors.cell[b.ship.sector] == arrived and b.been.size() == 2, "in the same place in the same space")
	_expect(b.ship.pos == Vector2(33.0, 21.5), "at the same spot in its sector")
	_expect(int(b.usage.used.get("evade", 0)) == 2 and FileAccess.file_exists(b.usage.path()), "what people used is kept, and usage.txt written")
	_expect(b.ship.store[Net.ITEM_PATCH] == 2 and b.ship.credits == 77, "with the same supplies and money")
	_expect(b.reserve == 1 and b.ship.hull == hull_was and b.voyage_ticks == 123456 and b.jumps == 9 and b.farthest == 4,
		"the same reserve, hull and record of the voyage")
	_expect(b.ship.mounts[1] == 2 and b.ship.armed[1] == 0 and b.ship.hardened and not b.ship.shield_on,
		"the same guns on their mounts, the shield as it was set, its hardening")
	_expect(b.air.holes.has(hole) and b.ship.broken.has(engine) and not b.powered(), "the hole is still there and the engine still out")
	_expect(b.doors.jammed[2] == 1, "a jammed door is still jammed")
	_expect(absf(b.air.air[air_cell] - air_there) < 0.01, "the air is as it was")
	_expect(b.floor_things.get(15 * map.width + 22, PackedByteArray()) == PackedByteArray([Net.ITEM_MAG, Net.ITEM_PART, 0, 0]), "what lay on the floor lies there")
	var body = null
	for c in b.players:
		if c != null and c.corpse and c.name == "Боря":
			body = c
	_expect(body != null and body.st.x == 24 and body.st.y == 11 and body.count(Net.ITEM_FUEL) == 1, "the body lies where it fell, with what it carried")
	_expect(b.dead_names.has("Боря"), "and its player coming back will take one from the reserve")
	_expect(b.saved_crew.has("Аня"), "the living wait for their players")
	var back := b.crew.new_player("Аня")
	b.crew.restore_character(back, b.saved_crew["Аня"])
	_expect(back.st.x == 20 and back.st.y == 15 and back.job == Net.JOB_MEDIC and back.skills[Net.SKILL_MEDICINE] == 77,
		"a player coming back finds their character where it stood, in its job, with its skills")
	_expect(back.count(Net.ITEM_PISTOL + 5) == 1 and back.count(Net.ITEM_RADIO) == 1 and absf(back.health - health_was) < 0.01 and absf(back.wounds - wounds_was) < 0.01,
		"with what it carried and its wounds")

	print("a ship drawn anew since the save (v91)")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	saved["layout"] = int(saved["layout"]) + 1
	var anew := PATH.get_basename() + "_anew.json"
	var f := FileAccess.open(anew, FileAccess.WRITE)
	f.store_string(JSON.stringify(saved))
	f.close()
	var c := GameServer.new()
	get_root().add_child(c)
	c.start(26195, "ship02", 0)
	c.director.auto = false
	_expect(c.resume_campaign(anew) == "", "it still goes on")
	_expect(c.floor_things.is_empty() and c.ship.store[Net.ITEM_MAG] >= 1 and c.ship.store[Net.ITEM_PART] >= 1, "what lay on the floor is in the locker")
	_expect(c.air.holes.is_empty() and c.ship.broken.is_empty(), "no holes nor breakdowns in cells that are something else now")
	var spot := Vector2i(int(c.saved_crew["Аня"]["x"]), int(c.saved_crew["Аня"]["y"]))
	var lying := Vector2i(-1, -1)
	for who in c.players:
		if who != null and who.corpse and who.name == "Боря":
			lying = Vector2i(who.st.x, who.st.y)
	_expect(c.map.spawns.has(spot) and c.map.spawns.has(lying), "the living and the dead are where one comes aboard")
	c.stop()
	c.queue_free()
	Campaign.forget(anew)

	print("the end")
	var sm := b.crew.summary_packet()
	_expect(sm.size() > 10 + 1 + 4 * b.usage.NAMES.size(), "the end screen gets what people used")
	b.ship.hull = 1
	b.crew.hull_hit(5)
	_expect(b.over == Net.OVER_WRECKED and not Campaign.exists(PATH), "a lost campaign leaves no save behind")
	_expect(not b.save_campaign(), "and the host's save button saves nothing")
	b.stop()
	_expect(not Campaign.exists(PATH), "and stopping the server writes none")
	Campaign.forget(PATH)
	print("SAVETEST %s" % ("ok" if failed == 0 else "FAILED: %d" % failed))
	quit(0 if failed == 0 else 1)


func _run(server: GameServer, ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
