extends SceneTree
## (v100) Checks the placeholders (the author: "need placeholders if I don't upload any sprites, and a picture NO
## SPRITE if it doesn't have any ... so people don't look naked"):
##   godot --headless --path . --script res://tools/spritetest.gd
## Every thing has a picture of its own (none falls back to NO SPRITE); every wear sheet is there and laid out as
## body.png; one in a jumpsuit is drawn in it, not in the body's top and shorts; what is worn over the clothes is
## told to everyone (S_OUTFIT's gear byte) and changes are sent again; a block of walls is drawn solid (his note).
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const CrewArt := preload("res://src/client/crew_art.gd")
const Sprites := preload("res://src/client/sprites.gd")
const MapBuilder := preload("res://src/shared/map_builder.gd")

var failed := 0


class Asker extends Control:
	## Draws every thing once, in its own _draw (drawing anywhere else is refused), and keeps those it had no picture for.
	var missing: Array[int] = []
	var done := false

	func _draw() -> void:
		for item: int in Items.INFO.keys():
			if not ItemArt._drawn(self, Rect2(0, 0, 17, 17), item):
				missing.append(item)
		done = true


func _initialize() -> void:
	_things()


func _things() -> void:
	var asker := Asker.new()
	asker.size = Vector2(32, 32)
	get_root().add_child(asker)
	asker.queue_redraw()
	for i in 10:
		await process_frame
		if asker.done:
			break
	_expect(asker.done, "(the things were drawn)")
	var names := asker.missing.map(func(i: int) -> String: return "%d %s" % [i, Items.name_of(i)])
	_expect(asker.missing.is_empty(), "every thing has a picture of its own, none shows NO SPRITE (missing: %s)" % ", ".join(names))
	_expect(Items.INFO.has(Net.ITEM_MANTIS_CLAW) and not asker.missing.has(Net.ITEM_MANTIS_CLAW), "the mantis's claw is drawn")
	asker.queue_free()
	_rest()


func _rest() -> void:
	# the wear sheets, laid out as body.png
	var want := Vector2(CrewArt.FRAME.x * CrewArt.VIEWS, CrewArt.FRAME.y * CrewArt.BODIES)
	for name: String in Sprites.SHEETS.keys():
		if not name.begins_with("wear_"):
			continue
		var tex := Sprites.sheet(name)
		_expect(tex != null and tex.get_size() == want, "%s.png is there, %dx%d" % [name, int(want.x), int(want.y)])
		if tex != null:
			var im := tex.get_image()
			if im.is_compressed():
				im.decompress()
			var empty := 0
			for v in CrewArt.VIEWS:
				for b in CrewArt.BODIES:
					if im.get_region(Rect2i(v * CrewArt.FRAME.x, b * CrewArt.FRAME.y, CrewArt.FRAME.x, CrewArt.FRAME.y)).is_invisible():
						empty += 1
			var may_be_empty := 2 if name in ["wear_nvg", "wear_thermal"] else 0   # goggles from behind: only the strap
			_expect(empty <= may_be_empty, "%s has a picture for every way and body (%d empty)" % [name, empty])

	# one in a jumpsuit wears it: the man's front from the shoulders to the knees is cloth, not skin
	var sheet := CrewArt.build()
	var colour := 1
	var row_dressed := colour * Net.LOOKS + Net.OUTFIT_JUMPSUIT * 2
	var row_bare := colour * Net.LOOKS + Net.OUTFIT_BARE * 2
	var dressed := sheet.get_region(Rect2i(CrewArt.PAD, row_dressed * CrewArt.CELL.y + CrewArt.PAD, CrewArt.FRAME.x, CrewArt.FRAME.y))
	var bare := sheet.get_region(Rect2i(CrewArt.PAD, row_bare * CrewArt.CELL.y + CrewArt.PAD, CrewArt.FRAME.x, CrewArt.FRAME.y))
	var chest := Vector2i(16, 24)
	_expect(_skin(bare.get_pixelv(chest)), "(the bare man's chest is skin)")
	_expect(not _skin(dressed.get_pixelv(chest)) and dressed.get_pixelv(chest).a > 0.0, "the man in a jumpsuit has his chest covered")
	var trim := false
	for x in CrewArt.FRAME.x:
		var c := dressed.get_pixel(x, 30)
		if c.a > 0.0 and absf(c.h - CrewArt.TINTS[colour].h) < 0.05 and c.s > 0.3:
			trim = true
	_expect(trim, "its belt is in the job's colour")
	_expect(dressed.get_pixelv(chest).s < 0.15, "the jumpsuit itself is grey (his note)")

	# the gear worn over the clothes, told to everyone
	var server := GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26341, "ship01", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	var p = server.crew.new_player("Одетый")
	_expect(p.gear_look() == 0, "a fresh one wears nothing over its clothes")
	p.worn[Net.WEAR_SUIT] = Net.ITEM_NONE
	p.worn[Net.WEAR_BODY] = Net.ITEM_VEST
	p.worn[Net.WEAR_HEAD] = Net.ITEM_HELMET
	p.worn[Net.WEAR_EYES] = Net.ITEM_THERMAL
	_expect(p.gear_look() == Net.GEAR_VEST | Net.GEAR_HELMET | Net.GEAR_THERMAL, "vest, helmet and thermal goggles are its gear bits (%d)" % p.gear_look())
	p.worn[Net.WEAR_BELT] = Net.ITEM_ESHIELD
	p.worn[Net.WEAR_SHIELD] = Net.ITEM_RIOT
	_expect(p.gear_look() & (Net.GEAR_BELT | Net.GEAR_RIOT) == (Net.GEAR_BELT | Net.GEAR_RIOT), "the energy belt and the hand shield too")
	var pkt: PackedByteArray = server.crew.look_packet(p)
	_expect(pkt.size() == 6 and pkt[5] == p.gear_look(), "S_OUTFIT carries the gear byte")
	server.crew.tell_looks()
	var sent: int = p.look_sent
	p.worn[Net.WEAR_HEAD] = Net.ITEM_NONE
	server.crew.tell_looks()
	_expect(p.look_sent != sent, "taking the helmet off is told again")

	# (his Notebook note) a block of walls is drawn solid: the cells with wall below are the wall's top
	var text := "= Палуба\n#########\n#.......#\n#...###.#\n#...###.#\n#...###.#\n#.......#\n#.......#\n#########\n"
	var built := MapBuilder.build("ships:block", text)
	var ids := MapBuilder.tile_ids()
	var cells: Array = built["data"]["cells"]
	var w := 9
	_expect(int(cells[2 * w + 5]) == int(ids["wall_fill"]) and int(cells[3 * w + 5]) == int(ids["wall_fill"]), "the inside of a block of walls is solid")
	_expect(int(cells[4 * w + 5]) != int(ids["wall_fill"]), "its bottom row keeps the wall's face")
	_expect(int(cells[0 * w + 4]) != int(ids["wall_fill"]), "a plain wall one thick is not filled")

	print("spritetest: %s" % ("ok" if failed == 0 else "%d failed" % failed))
	server.stop()
	quit(1 if failed > 0 else 0)


func _skin(c: Color) -> bool:
	return c.a > 0.0 and c.r > c.g and c.g > c.b and c.r > 0.6 and c.s > 0.15


func _expect(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		failed += 1
