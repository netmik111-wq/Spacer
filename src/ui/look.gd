extends RefCounted
## (v73, the author's v73 answers) What the client can tell the player in words
## about a place or about the ship: the label under the mouse (L3) and the
## ship's needs on the bridge's alert panel (L2). Client side only.

const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const GameClient := preload("res://src/client/game_client.gd")

const OK := 0                         # needs: the colour of a line
const WARN := 1
const BAD := 2


static func thing_name(client: GameClient, cell: int) -> String:
	## What is fitted into this wall cell, in plain words ("" = nothing).
	var map := client.map
	var named := map.device_name(cell)
	if named != "":
		return named
	if map.oxygen.has(cell):
		return "кислородная стойка"
	if map.locker.has(cell):
		return "шкаф снабжения"
	if map.intercom.has(cell):
		return "интерком"
	if map.med_box.has(cell):
		return "ящик первой помощи"
	if map.tech_box.has(cell):
		return "ящик запчастей"
	var tile := map.tile_names[map.cells[cell]].trim_prefix("pirate_") if map.cells[cell] >= 0 else ""
	if tile == "fire_box":
		return "пожарный ящик"
	if tile == "wall_light":
		return "светильник"
	if map.bench.has(cell):
		return "верстак"
	if map.stove.has(cell):
		return "плита камбуза"
	if map.trays.has(cell):
		return "гидропонный лоток"
	if map.cryo.has(cell):
		return "криокапсула"
	return ""


static func name_at(client: GameClient, cell: int, seen: bool) -> String:
	## The label for what is in this cell: people first, then the thing on the
	## wall, a door, a hole, what lies on the floor, a ladder. `seen`: our
	## character can make the cell out (people and floor things are told only then).
	var map := client.map
	if cell < 0 or cell >= map.cells.size():
		return ""
	var x := cell % map.width
	var y := cell / map.width
	var lines: Array[String] = []
	if seen:
		for e: GameClient.Ent in client.ents.values():
			if e.x == x and e.y == y and e.id != client.my_id:
				lines.append(_who(client, e))
	var thing := thing_name(client, cell)
	if thing != "":
		lines.append(_capital(thing) + (": не работает" if client.broken.has(cell) else ""))
	var door := map.door_of[cell]
	if door >= 0:
		lines.append(_door(client, door))
	if client.holes.has(cell) and client.shut_panes.has(cell):
		lines.append("Разбитое окно за ставнем: воздух держится, пробоину надо заделать")
	elif client.holes.has(cell):
		lines.append("Пробоина в обшивке: воздух уходит")
	elif client.shut_panes.has(cell):
		lines.append("Окно: ставень опущен")      # (v91, the author's W1)
	if seen and client.floor_things.has(cell):
		var here := PackedByteArray()
		for v in client.floor_things[cell]:
			if v != Net.ITEM_NONE:
				here.append(v)
		if not here.is_empty():
			var names: Array[String] = []
			for v in here:
				names.append(Items.name_of(v).to_lower())
			lines.append("На полу: " + ", ".join(names))
	if map.climb[cell] >= 0 and lines.is_empty():
		lines.append("Лестница")
	if map.is_brig(cell) and door < 0:
		lines.append("Камера гауптвахты: здесь пленный не освободится")   # (v75, the author's P1)
	return "\n".join(lines)


static func _who(client: GameClient, e: GameClient.Ent) -> String:
	var name := client.player_name(e.id)
	var kind := int(client.roster[e.id]["kind"]) if client.roster.has(e.id) else Net.KIND_PLAYER
	var what := ""
	match kind:
		Net.KIND_BOT:
			what = "бот экипажа"
		Net.KIND_PIRATE:
			what = "пират"
		Net.KIND_ROBOT:
			what = "наш охранный робот"
		Net.KIND_CORPSE:
			what = "тело"
	var state := ""
	if kind != Net.KIND_CORPSE:
		if e.cond == Net.COND_DEAD:
			state = "мёртв"
		elif e.cond != Net.COND_OK:
			state = "без сознания"
	var parts: Array[String] = [name]
	if what != "":
		parts.append(what)
	if state != "":
		parts.append(state)
	return ", ".join(parts)


static func _door(client: GameClient, door: int) -> String:
	var d := client.doors
	var airlock := d.partner[door] >= 0
	var name := "Дверь шлюза" if airlock else "Дверь"
	var sides := client.map.door_sides
	if not airlock and (client.map.is_brig(sides[door * 2]) or client.map.is_brig(sides[door * 2 + 1])):
		name = "Дверь камеры"                 # (v75) a cell of the brig
	if d.welded[door] == 1:
		return name + ": заварена"
	if d.jammed[door] == 1:
		return name + ": заклинило открытой"
	if d.blast[door] == 1:
		return name + ": заблокирована от абордажа"
	if not d.is_shut(door):
		return name + ": открыта"
	if d.locked[door] == 1:
		return name + ": опущена аварийная заслонка (за ней другое давление)"
	if client.map.door_access[door] != 0:
		return name + ": закрыта, с замком"
	return name + ": закрыта"


static func _capital(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text


static func needs(client: GameClient) -> Array:
	## (L2) The ship's needs for the alert panel on the bridge: [level, text], the
	## worst first. A green line when nothing is wrong.
	var out: Array = []
	var hull_share := float(client.hull) / maxf(client.hull_max, 1)
	if hull_share < 0.35:
		out.append([BAD, "Корпус %d из %d: залатайте обшивку снаружи или у торговца" % [client.hull, client.hull_max]])
	elif hull_share < 0.7:
		out.append([WARN, "Корпус %d из %d" % [client.hull, client.hull_max]])
	if not client.holes.is_empty():
		out.append([BAD, "Пробоин: %d. Заплатки в шкафу снабжения, держите E у пробоины" % client.holes.size()])
	if not client.powered():
		out.append([BAD, "Нет питания: двигатель стоит и СМЭС пуст"])
	var broken: Array[String] = []
	for cell: int in client.broken.keys():
		var name := thing_name(client, cell)
		if name != "" and not broken.has(name):
			broken.append(name)
	if not broken.is_empty():
		out.append([BAD if broken.has("двигатель") or broken.has("управление кораблём") else WARN,
			"Сломано: %s. Держите E, чтобы починить" % ", ".join(broken)])
	if client.fuel < client.jump_cost:
		out.append([BAD, "Топливо %d: на прыжок не хватит (нужно %d). Канистру залейте в двигатель" % [client.fuel, client.jump_cost]])
	elif client.fuel < client.jump_cost * 3:
		out.append([WARN, "Топливо %d: прыжка на %d" % [client.fuel, client.fuel / maxi(client.jump_cost, 1)]])
	var air_full := float(Net.STORE_AIR_FULL)
	if client.store_air < air_full * 0.15:
		out.append([BAD, "Запас воздуха почти пуст: купите баллоны у торговца"])
	elif client.store_air < air_full * 0.4:
		out.append([WARN, "Запас воздуха: %d%%" % roundi(client.store_air * 100.0 / air_full)])
	var food := int(client.store.get(Net.ITEM_FOOD, 0))
	var people := maxi(client.crew_bots.size() + 1, 1)
	if not client.store.is_empty():                  # (known once the locker's list has come)
		if food == 0:
			out.append([BAD, "Еды нет: экипаж голодает с каждым прыжком"])
		elif food < people * 2:
			out.append([WARN, "Еды на %d прыжка" % maxi(food / people, 1)])
	for s: Dictionary in client.smes:
		if not bool(s.get("small", false)) and int(s.get("capacity", 0)) > 0:
			var share := float(s.get("charge", 0)) / float(s["capacity"])
			if share < 0.15:
				out.append([WARN, "СМЭС заряжен на %d%%" % roundi(share * 100.0)])
	if client.reserve == 0:
		out.append([WARN, "Резерв экипажа пуст: погибших заменить некем"])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	if out.is_empty():
		out.append([OK, "Всё в порядке"])
	return out
