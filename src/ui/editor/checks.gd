extends RefCounted
## (v81, the author's E8) The ship editor's problems panel: what is wrong with a drawing, or missing
## for the game, in plain words, each with its cell when it has one. An error means the game cannot
## load the drawing («Попробовать» waits for it to be fixed); a warning means something will not work
## or be missing in play. Saving works either way.

const MapBuilder := preload("res://src/shared/map_builder.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Net := preload("res://src/shared/net.gd")
const Drawing := preload("res://src/ui/editor/drawing.gd")

# what our own ship needs: [sign, error?, what is said when there is none]
const SHIP_NEEDS := [
	["3", true, "Нет штурвала (пульт управления, «3»): кораблём нельзя править."],
	["6", true, "Нет двигателя («6»): кораблю нечем лететь и не от чего брать энергию."],
	["1", false, "Нет пульта карты сектора («1»): некуда прыгать."],
	["9", false, "Нет шлюза с насосом («9»): не выйти в космос, никто не пристыкуется."],
	["S", false, "Нет накопителя энергии («S»): без двигателя корабль сразу без света."],
	["7", false, "Нет воздушной установки («7»): воздух не восполняется."],
	["8", false, "Нет шкафа снабжения («8»): запасы негде хранить, торговать нечем."],
	["2", false, "Нет кислородной станции («2»): баллоны скафандров не заправить."],
	["4", false, "Нет пульта орудий («4»): орудиями не стрелять."],
	["T", false, "Нет орудий в корпусе («T»): в бою нечем отвечать."],
	["Z", false, "Нет генератора щита («Z»): корабль без щита."],
	["C", false, "Нет криокапсул («C»): резерву экипажа негде спать."],
	["K", false, "Нет пульта связи («K»): ни вызовов, ни заданий."],
]


static func run(d: Drawing) -> Array:
	## Every problem: {"deck" (-1 = the whole ship), "x", "y", "text", "error"}.
	var out: Array = []
	var built := MapBuilder.build("ships:check", text_of(d))
	for p: Dictionary in built["problems"]:
		out.append(_p(int(p["deck"]), int(p["x"]), int(p["y"]), p["text"], true))
	for i in d.decks.size():
		var empty := true
		for s: String in d.decks[i]["cells"]:
			if s != " ":
				empty = false
				break
		if empty:
			out.append(_p(i, 0, 0, "Палуба «%s» пустая: в игре её не будет." % d.decks[i]["name"], false))
	var signs := {}
	for deck: Dictionary in d.decks:
		for s: String in deck["cells"]:
			signs[s] = int(signs.get(s, 0)) + 1
	var map: ShipMap = null
	if out.is_empty():
		map = ShipMap.new()
		var why := map.load_data("check", FileAccess.get_file_as_string("res://assets/tiles.json"), built["data"], d.kind == "ship")
		if why != "":
			out.append(_p(-1, 0, 0, why.trim_prefix("Карта «check»: "), true))
			map = null
		else:
			map.kind = d.kind
	match d.kind:
		"ship":
			for need: Array in SHIP_NEEDS:
				if not signs.has(need[0]):
					out.append(_p(-1, 0, 0, need[2], need[1]))
			if map != null and not map.lock_pump.is_empty() and not _others_fit(map):
				out.append(_p(-1, 0, 0, "Над наружной дверью шлюза мало пустого места: другие корабли не подойдут. Оставьте около 8 пустых рядов над ней.", false))
		"pirate", "derelict":
			if map != null and not _has_outer_door(map):
				out.append(_p(-1, 0, 0, "Нет наружной двери в космос («D» в стене с пустотой с одной стороны): к нему не пристыковаться.", false))
			if d.kind == "pirate" and map != null and map.rooms.size() < Net.ESYS_COUNT - 2:
				out.append(_p(-1, 0, 0, "Отсеков %d: для боя нужно не меньше %d (по одному на каждую систему)." % [map.rooms.size(), Net.ESYS_COUNT - 2], false))
		"asteroid":
			if not signs.has("O"):
				out.append(_p(-1, 0, 0, "На астероиде нет рудной жилы («O»): добывать нечего.", false))
	if d.kind != "ship" and map != null and not fits_alongside(map):
		out.append(_p(-1, 0, 0, "Слишком большой: не поместится рядом с кораблём игры (не выше 9 рядов, не шире 38 клеток).", false))
	return out


static func text_of(d: Drawing) -> String:
	return d.to_text()


static func _p(deck: int, x: int, y: int, text: String, error: bool) -> Dictionary:
	return {"deck": deck, "x": x, "y": y, "text": text, "error": error}


static func _has_outer_door(map: ShipMap) -> bool:
	for d in map.doors.size():
		if map.door_vent[d] == 1:
			return true
	return false


static func _others_fit(map: ShipMap) -> bool:
	## Can the game's derelict lie off this ship's airlock (as Derelict.setup asks)?
	var o := ShipMap.new()
	if o.load_from("derelict01", false) != "":
		return true
	return spot_off(map, o) != ShipMap.NO_OTHER


static func spot_off(ours: ShipMap, o: ShipMap) -> Vector2i:
	## Where that other drawing's corner lies docked at our airlock (NO_OTHER: it does not fit), as
	## Derelict.setup works it out; one without an outer door (an asteroid) lies above the airlock.
	if ours.lock_pump.is_empty():
		return ShipMap.NO_OTHER
	var door: Vector2i = ours.doors[int(ours.lock_pump.values()[0]["outer"])]
	var theirs := Vector2i(o.width / 2, o.height - 1)
	for d in o.doors.size():
		if o.door_vent[d] == 1:
			theirs = o.doors[d]
	var docked_at := door - theirs - Vector2i(0, 1)
	ours.others.append(o)
	var k := ours.others.size() - 1
	var ok := ours.other_fits_kind(k, docked_at) and ours.other_fits_kind(k, docked_at - Vector2i(0, 3))
	ours.others.remove_at(k)
	return docked_at if ok else ShipMap.NO_OTHER


static func fits_alongside(o: ShipMap) -> bool:
	## Does this drawing fit off the airlock of the game's ship?
	var ours := ShipMap.new()
	if ours.load_from("ship02") != "":
		return true
	return spot_off(ours, o) != ShipMap.NO_OTHER
