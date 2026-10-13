extends SceneTree
## Checks things that can be carried, on a real server stepped by hand, without a network or a window:
##   godot --headless --path . --script res://tools/itemtest.gd
## Every thing is in the table of things. What is in the hand can be put down
## and picked up again, a cell holds only so many, and a body in the way is
## searched rather than robbed of the floor under it. The locker keeps any
## thing it stocks. A flashlight switches on in the hand, says so to everyone,
## and its light keeps to a narrow cone that walls and shut doors stop.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")
const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26230, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var map := server.map

	print("the table of things")
	var all_known := true
	for item in [Net.ITEM_PATCH, Net.ITEM_PART, Net.ITEM_FLASHLIGHT, Net.ITEM_FLASHLIGHT_ON]:
		all_known = all_known and Items.known(item) and Items.name_of(item) != ""
	_expect(all_known, "every thing has a name")
	var kept := Items.kept_in_locker()
	_expect(kept.has(Net.ITEM_PATCH) and kept.has(Net.ITEM_PART) and kept.has(Net.ITEM_FLASHLIGHT) and not kept.has(Net.ITEM_FLASHLIGHT_ON),
		"the locker keeps patches, parts and flashlights (and a lit flashlight as a flashlight)")
	_expect(Items.kind_of(Net.ITEM_FLASHLIGHT_ON) == Net.ITEM_FLASHLIGHT and not Items.light(Net.ITEM_FLASHLIGHT_ON).is_empty()
		and Items.light(Net.ITEM_FLASHLIGHT).is_empty(), "a lit flashlight is a flashlight that gives light")
	_expect(int(server.store[Net.ITEM_FLASHLIGHT]) == Items.stock(Net.ITEM_FLASHLIGHT), "the ship sets out with %d flashlights" % Items.stock(Net.ITEM_FLASHLIGHT))

	print("the locker and the hand")
	var p := server._new_player("Проверка")
	p.slots.fill(Net.ITEM_NONE)
	_face(p, map.locker.keys()[0])
	p.hand = 2
	server._store_asked(p, Net.STORE_TAKE, Net.ITEM_PATCH)
	server._store_asked(p, Net.STORE_TAKE, Net.ITEM_FLASHLIGHT)
	_expect(p.slots[2] == Net.ITEM_PATCH and p.slots[0] == Net.ITEM_FLASHLIGHT, "what is taken goes into an empty hand, else into the first free slot")
	_expect(int(server.store[Net.ITEM_FLASHLIGHT]) == Items.stock(Net.ITEM_FLASHLIGHT) - 1, "and the locker has one flashlight less")
	server._store_asked(p, Net.STORE_TAKE, 99)
	_expect(p.count(Net.ITEM_NONE) == Net.BASE_SLOTS + Net.POCKETS - 2, "a thing the locker does not keep cannot be taken")

	print("a flashlight")
	p.hand = 0
	_expect(server._act(p) and p.slots[0] == Net.ITEM_FLASHLIGHT_ON, "Z switches the flashlight in the hand on")
	_expect(Net.look_light(server._look(p)), "and everyone is told the character shines a light")
	p.hand = 2
	_expect(not Net.look_light(server._look(p)), "a lit flashlight that is not in the hand gives no light")
	_expect(not server._act(p), "a patch in the hand cannot be switched")
	p.hand = 0
	_expect(server._act(p) and p.slots[0] == Net.ITEM_FLASHLIGHT, "and Z switches it off again")
	server._act(p)
	server._store_asked(p, Net.STORE_PUT_BACK, 0)
	_expect(p.count(Net.ITEM_NONE) == Net.BASE_SLOTS + Net.POCKETS and int(server.store[Net.ITEM_FLASHLIGHT]) == Items.stock(Net.ITEM_FLASHLIGHT)
		and int(server.store[Net.ITEM_PATCH]) == Items.stock(Net.ITEM_PATCH), "everything goes back into the locker, a lit flashlight as a flashlight")

	print("putting down and picking up")
	p.st.place(2, 4)
	p.st.facing = Net.DIR_RIGHT
	p.hand = 0
	p.slots[0] = Net.ITEM_PATCH
	p.slots[1] = Net.ITEM_PART
	var here := 4 * map.width + 2
	_expect(server._put_down(p) and p.slots[0] == Net.ITEM_NONE and server.floor_things.has(here), "G puts the thing in the hand down underfoot")
	_expect(not server._put_down(p), "an empty hand puts nothing down")
	_expect(server.patches_aboard() == int(server.store[Net.ITEM_PATCH]) + 1, "a patch on the floor still counts as aboard")
	server._tick()
	p.hand = 3
	server._press(p)
	_expect(p.slots[3] == Net.ITEM_PATCH and not server.floor_things.has(here), "E picks it up again, into the free hand")
	for item in [Net.ITEM_PATCH, Net.ITEM_PART, Net.ITEM_PATCH, Net.ITEM_PART]:
		p.hand = p.slots.find(Net.ITEM_NONE)
		p.slots[p.hand] = item
		server._put_down(p)
	p.slots[0] = Net.ITEM_PATCH
	p.hand = 0
	_expect((server.floor_things[here] as PackedByteArray).count(Net.ITEM_NONE) == 0 and not server._put_down(p),
		"a cell holds %d things, no more" % Net.FLOOR_STACK)
	var underfoot := 4 * map.width + 3
	p.st.place(3, 4)
	p.st.facing = Net.DIR_LEFT
	p.slots.fill(Net.ITEM_NONE)
	p.slots[2] = Net.ITEM_FLASHLIGHT
	p.hand = 2
	server._put_down(p)
	p.hand = 0
	server._press(p)
	_expect(p.slots[0] == Net.ITEM_PART and server.floor_things.has(underfoot), "a thing in front is picked up before one underfoot, top one first")
	p.slots.fill(Net.ITEM_FLASHLIGHT)
	_expect(not server._pick_up(p), "with every slot full nothing is picked up")
	p.slots.fill(Net.ITEM_NONE)
	var q := server._new_player("Лежащий")
	q.st.place(2, 4)
	q.cond = Net.COND_CRIT
	q.st.down = true
	var lying_on := (server.floor_things[here] as PackedByteArray).count(Net.ITEM_NONE)
	p.st.place(3, 4)
	p.st.facing = Net.DIR_LEFT
	server.floor_things.erase(underfoot)
	_expect(not server._pick_up(p) and (server.floor_things[here] as PackedByteArray).count(Net.ITEM_NONE) == lying_on,
		"what lies under somebody lying there is not picked up (E searches them instead)")
	q.st.place(10, 7)
	_expect(server._pick_up(p), "and is, once they are moved")
	p.st.place(2, 4)
	p.st.facing = Net.DIR_UP
	_face(p, map.locker.keys()[0])
	var at_locker := p.st.y * map.width + p.st.x
	p.hand = 0
	p.slots[0] = Net.ITEM_PATCH
	server._put_down(p)
	server._press(p)
	_expect(server.floor_things.has(at_locker), "facing the locker, E is for the locker and leaves the floor alone")

	print("light and sight")
	var doors := server.doors
	var beam := Items.light(Net.ITEM_FLASHLIGHT_ON)
	var lit := Sight.cone(map, doors, Vector2(5, 4), Net.DIR_RIGHT, beam[0], beam[1])
	_expect(lit.has(4 * map.width + 14) and not lit.has(4 * map.width + 15), "a flashlight reaches %d cells along the corridor" % int(beam[1]))
	_expect(not lit.has(4 * map.width + 4), "and nothing behind its holder")
	var wide := 0
	for cell: int in lit.keys():
		if cell % map.width == 13:
			wide += 1
	_expect(wide <= 3, "its cone is narrow: %d cells across eight cells off" % wide)
	var up := Sight.cone(map, doors, Vector2(5, 4), Net.DIR_UP, 160.0, 9)
	_expect(up.has(3 * map.width + 5) and not up.has(2 * map.width + 5), "a wall is lit, and nothing behind it")
	var door := map.door_at(4, 4)
	_expect(door >= 0 and doors.is_shut(door), "(the door at 4,4 is shut)")
	var through := Sight.cone(map, doors, Vector2(1, 4), Net.DIR_RIGHT, beam[0], beam[1])
	_expect(through.has(4 * map.width + 4) and not through.has(4 * map.width + 5), "a shut door stops the light")
	doors.ready[door] = server.tick
	through = Sight.cone(map, doors, Vector2(1, 4), Net.DIR_RIGHT, beam[0], beam[1])
	_expect(through.has(4 * map.width + 5), "an open one lets it through")
	var below := Sight.cone(map, doors, Vector2(5, 4), Net.DIR_DOWN, 160.0, 30)
	var other_deck := false
	for cell: int in below.keys():
		other_deck = other_deck or map.deck_of_cell(cell) != 0
	_expect(not other_deck, "light stays on its own deck")

	server.stop()
	server.free()
	print("ITEMTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _face(p: RefCounted, wall_cell: int) -> void:
	## Puts the character in front of a thing on a wall, looking at it.
	var map := server.map
	var x := wall_cell % map.width
	var y := wall_cell / map.width
	if map.walkable(x, y + 1):
		p.st.place(x, y + 1)
		p.st.facing = Net.DIR_UP
	else:
		p.st.place(x, y - 1)
		p.st.facing = Net.DIR_DOWN
	p.st.dir = Net.DIR_NONE


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
