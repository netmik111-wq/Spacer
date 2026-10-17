extends RefCounted
## The two bridge consoles, as shown in the console frame of GameScreen: the
## sector console (the chart of sectors and a button for every jump in reach)
## and the ship's controls (the sector as a square: click to set a course,
## buttons to stop and to dock). GameScreen owns the controls and opens and
## closes the frame; this fills them in.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var client: GameClient
var chart: Control                   # the picture
var text: Label                      # the lines under it
var buttons: GridContainer           # the buttons under those
var buttons_for := -1                # what the buttons were last built for (-1: build them anew)


func _init(p_client: GameClient, p_chart: Control, p_text: Label, p_buttons: GridContainer) -> void:
	client = p_client
	chart = p_chart
	text = p_text
	buttons = p_buttons


func update_chart() -> void:
	## The sector console: where the ship is, the drive, the fuel, and a jump button for every sector in reach.
	var now := client.server_now()
	var jumping := client.jump_to != Net.NO_SECTOR
	var wait := (client.drive_ready - now) / Net.TICK_HZ
	if jumping:
		text.text = "Корабль в секторе %s.\nКурс задан: %s. Прыжок через %d с." % [
			client.sectors.describe(client.sector), client.sectors.describe(client.jump_to),
			maxi(int(ceil((client.jump_tick - now) / Net.TICK_HZ)), 0)]
	elif wait > 0.0:
		text.text = "Корабль в секторе %s.\nДвигатель перезаряжается: ещё %d с." % [client.sectors.describe(client.sector), int(ceil(wait))]
	else:
		text.text = "Корабль в секторе %s.\nДвигатель готов. Куда прыгаем?" % client.sectors.describe(client.sector)
	var fuel := client.stock(Net.ITEM_FUEL)
	if fuel > 0:
		text.text += "\nТопливо в шкафу снабжения: %d. Прыжок сжигает одну канистру." % fuel
	else:
		text.text += "\nТоплива в шкафу снабжения нет: прыгнуть нельзя. Его продаёт торговец, оно бывает на брошенных кораблях, станция снабжения даёт немного."
	text.text += "\nДо начала пути отсюда прыжков: %d. Карта показывает только окрестности корабля." % client.sectors.far_from_start(client.sector)
	var goal := client.sectors.jumps_to_goal(client.sector)
	if client.won:
		text.text += "\nФлагман пиратов повержен: цель пути достигнута. Летите куда хотите."
	else:
		text.text += ("\nФлагман пиратов здесь, в этом секторе: уйти прыжком он не даст." if goal == 0 else
			"\nЦель пути, флагман пиратов: %d прыжк%s отсюда (красная метка на карте)." % [goal, _jumps_word(goal)])
	# one button per sector within reach; rebuilt when the ship has moved
	var place_key := Sectors.key(client.sectors.cell[client.sector]) * 2    # the buttons belong to this place in space
	if buttons_for != place_key:
		buttons_for = place_key
		for old in buttons.get_children():
			old.queue_free()
		for id in client.sectors.neighbours(client.sector):
			var go := Button.new()
			go.text = "Прыжок: %s" % client.sectors.describe(id)
			go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			go.pressed.connect(client.send_jump.bind(id))
			buttons.add_child(go)
		chart.queue_redraw()
	for go in buttons.get_children():
		if go is Button:
			(go as Button).disabled = jumping or wait > 0.0 or fuel < 1
	if jumping:
		chart.queue_redraw()


static func _jumps_word(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "ок"
	if n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14):
		return "а"
	return "ов"


func update_helm() -> void:
	## The ship's controls: where the ship is inside the sector and where it is heading.
	var sectors := client.sectors
	var here := client.sector
	var at := client.ship_pos()
	var lines := PackedStringArray()
	var leaving := client.jump_to != Net.NO_SECTOR
	if leaving:
		# the ship is going into the jump: there is no course inside the sector any more
		lines.append("Корабль уходит в прыжок%s. Курс внутри сектора не действует." % (" и идёт по инерции" if client.ship_under_way() else ""))
	elif client.ship_under_way():
		lines.append("Корабль идёт заданным курсом, осталось %d." % int(ceil(at.distance_to(client.ship_dest))))
	else:
		lines.append("Корабль стоит. Щёлкните по карте, чтобы задать курс.")
	if client.pirates_alongside() and client.enemy_flags & Net.ENEMY_RAID and not client.other_docked:
		lines.append("У шлюза пиратский корабль: он ведёт бой на расстоянии. Бить его с пульта орудий.")
	elif client.pirates_alongside():
		lines.append("У шлюза пиратский корабль%s. Расстыковавшись, он уйдёт, но заклинившие двери шлюза выпустят воздух." %
			(", пристыкован силой" if client.other_docked else ", сейчас пристыкуется"))
	elif client.other_here() and client.other_wreck:
		lines.append("Разбитый пиратский корабль пристыкован к шлюзу." if client.other_docked else
			"Над шлюзом разбитый пиратский корабль. До него можно добраться через открытый космос или пристыковаться.")
		lines.append("Пока кто-то снаружи или корабли состыкованы, корабль не тронется и не прыгнет. Тронемся, и обломки останутся позади.")
	if client.fighting():
		# (v55) the battle position
		var pos := "Позиция в бою: %s." % Net.POS_NAMES[client.battle_pos].to_lower()
		if client.battle_goal != Net.POS_NONE:
			pos += " Манёвр на «%s»: ещё %d с, пока он идёт, мы не уклоняемся." % [Net.POS_NAMES[client.battle_goal].to_lower(), client.battle_left]
		lines.append(pos + " Уклонение от их выстрелов: %d%% (пока здесь стоит пилот)." % client.our_dodge)
		lines.append("Вплотную: как обычно, можно перейти к ним на абордаж. На дистанции: обе стороны попадают реже, пираты подходят к шлюзу вдвое медленнее. С фланга: мы попадаем лучше, но уклоняемся вдвое хуже. Держать позицию можно только с кем-то за штурвалом.")
	match sectors.kind[here]:
		Sectors.METEORS:
			var edge := float(sectors.reach[here]) - at.distance_to(sectors.spot[here])
			lines.append("Корабль внутри метеорного потока, до края %d." % int(ceil(edge)) if edge >= 0.0 else "Корабль вне метеорного потока.")
		Sectors.STATION, Sectors.TRADER:
			var what := "станции" if sectors.kind[here] == Sectors.STATION else "торговца"
			var gap := at.distance_to(sectors.spot[here]) - float(sectors.reach[here])
			lines.append("До %s %d." % [what, int(ceil(gap))] if gap > 0.0 else "Корабль у %s." % what)
		Sectors.DERELICT:
			if client.other_here() and not client.pirates_alongside() and not client.other_wreck:
				lines.append("Брошенный корабль пристыкован к шлюзу." if client.other_docked else
					"Брошенный корабль рядом, над шлюзом. До него можно добраться через открытый космос или пристыковаться.")
				lines.append("Пока кто-то снаружи или корабли состыкованы, корабль не тронется и не прыгнет.")
			else:
				var gap := at.distance_to(sectors.spot[here]) - float(sectors.reach[here])
				lines.append("До брошенного корабля %d." % int(ceil(gap)))
		_:
			lines.append("В этом секторе идти некуда: вокруг пусто.")
	text.text = "\n".join(lines)
	var buttons_key := Sectors.key(sectors.cell[here]) * 64 + 1 + (2 if client.other_here() else 0) + (4 if client.other_docked else 0) \
		+ (8 if client.pirates_alongside() else 0) + (32 if client.other_wreck else 0) + (16 if client.fighting() else 0)
	if buttons_for != buttons_key:
		buttons_for = buttons_key
		for old in buttons.get_children():
			old.queue_free()
		var halt := Button.new()
		halt.text = "Остановить корабль"
		halt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		halt.pressed.connect(func() -> void: client.send_helm(false))
		buttons.add_child(halt)
		if client.other_here() and (client.other_docked or not client.pirates_alongside()):
			var dock := Button.new()
			dock.text = ("Расстыковаться с пиратским кораблём" if client.pirates_alongside() else "Расстыковаться") \
				if client.other_docked else ("Пристыковаться к разбитому кораблю" if client.other_wreck else "Пристыковаться к брошенному кораблю")
			dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var on := not client.other_docked
			dock.pressed.connect(func() -> void: client.send_dock(on))
			buttons.add_child(dock)
		if client.fighting():
			for pos in [Net.POS_CLOSE, Net.POS_FAR, Net.POS_FLANK]:
				var go := Button.new()
				go.text = ["Подойти вплотную", "Отойти на дистанцию", "Зайти с фланга"][pos]
				go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				go.set_meta("pos", pos)
				go.pressed.connect(func() -> void: client.send_position(pos))
				buttons.add_child(go)
	for b in buttons.get_children():
		if b is Button:
			(b as Button).disabled = leaving
			if b.has_meta("pos"):
				var pos: int = b.get_meta("pos")
				(b as Button).disabled = pos == (client.battle_goal if client.battle_goal != Net.POS_NONE else client.battle_pos)
	chart.queue_redraw()


func helm_area() -> Rect2:
	## The square of the chart control that stands for the sector.
	var side := minf(chart.size.x, chart.size.y) - 12.0
	return Rect2((chart.size - Vector2(side, side)) * 0.5, Vector2(side, side))


func helm_clicked(click: InputEventMouseButton) -> void:
	## A click on the ship's controls sets a course to that place in the sector.
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var area := helm_area()
		if area.has_point(click.position) and client.jump_to == Net.NO_SECTOR:
			client.send_helm(true, (click.position - area.position) / area.size * Sectors.SPAN)


func draw(kind: int) -> void:
	## The picture of the console of that kind (as GameClient.use_target): the
	## ship's controls (4) or the chart of sectors (3).
	if kind == 4:
		_draw_helm()
	else:
		_draw_chart()


func _draw_chart() -> void:
	## The chart of sectors: where the ship is, where it can jump, what is known about the rest.
	var sectors := client.sectors
	if sectors.count == 0:
		return
	var area := Rect2(Vector2(30, 22), chart.size - Vector2(60, 68))
	var place := func(id: int) -> Vector2:
		return area.position + Vector2(sectors.pos[id].x / 100.0, sectors.pos[id].y / 60.0) * area.size
	chart.draw_rect(Rect2(Vector2.ZERO, chart.size), Color(0.02, 0.05, 0.04))
	for l: Array in sectors.links:
		var near: bool = int(l[0]) == client.sector or int(l[1]) == client.sector
		chart.draw_line(place.call(int(l[0])), place.call(int(l[1])), Color(0.3, 0.8, 0.5, 0.75 if near else 0.22), 2.0 if near else 1.0)
	if client.jump_to != Net.NO_SECTOR:
		chart.draw_line(place.call(client.sector), place.call(client.jump_to), Color(1, 1, 1, 0.9), 3.0)
	var font := ThemeDB.fallback_font
	var colours := [Color(0.55, 0.62, 0.75), Color(1.0, 0.6, 0.25), Color(0.95, 0.85, 0.35), Color(0.3, 0.85, 0.8), Color(0.78, 0.5, 0.88),
		GOAL]   # one per Sectors.KIND_NAMES
	for id in sectors.count:
		var at: Vector2 = place.call(id)
		var known := client.knows_sector(id)
		if not known:
			chart.draw_circle(at, 3.0, Color(0.3, 0.36, 0.34))     # something is there; nobody knows what
			continue
		chart.draw_circle(at, 7.0, colours[sectors.kind[id]])
		if sectors.visited[id] == 1:
			chart.draw_circle(at, 2.5, Color(0.04, 0.08, 0.07))    # been there
		if id == client.sector:
			chart.draw_arc(at, 12.0, 0.0, TAU, 32, Color.WHITE, 2.0)
		chart.draw_string(font, at + Vector2(-70, 24), sectors.names[id], HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(0.85, 0.95, 0.88))
		if sectors.kind[id] == Sectors.FLAGSHIP:
			chart.draw_arc(at, 11.0, 0.0, TAU, 32, GOAL, 2.0)
	_draw_goal(area)
	# legend: what the colours are, then what the marks are
	var ink := Color(0.7, 0.8, 0.74)
	var x := 8.0
	var y := chart.size.y - 28
	for k in Sectors.KIND_NAMES.size():
		chart.draw_circle(Vector2(x + 5, y), 5.0, colours[k])
		chart.draw_string(font, Vector2(x + 14, y + 4), Sectors.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		x += 26.0 + font.get_string_size(Sectors.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	x = 8.0
	y = chart.size.y - 10
	var grey := colours[0] as Color
	for mark in 5:
		var at := Vector2(x + 5, y)
		var text := ""
		match mark:
			0:
				chart.draw_arc(at, 6.0, 0.0, TAU, 24, Color.WHITE, 1.5)
				text = "корабль здесь"
			1:
				chart.draw_circle(at, 5.0, grey)
				chart.draw_circle(at, 2.0, Color(0.04, 0.08, 0.07))
				text = "точка внутри: уже были"
			2:
				chart.draw_circle(at, 3.0, Color(0.3, 0.36, 0.34))
				text = "неизвестно, что там"
			3:
				chart.draw_line(at - Vector2(5, 0), at + Vector2(7, 0), Color(0.3, 0.8, 0.5, 0.75), 2.0)
				text = "маршрут для прыжка"
			4:
				chart.draw_line(at - Vector2(5, 0), at + Vector2(7, 0), Color.WHITE, 3.0)
				text = "заданный прыжок"
		chart.draw_string(font, Vector2(x + 16, y + 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		x += 30.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


const GOAL := Color(1.0, 0.25, 0.25)      # (v57) the flagship's sector, and the way to it


func _draw_goal(area: Rect2) -> void:
	## (v57) The flagship lies off the chart: an arrow at its edge points the way,
	## with how many jumps there are to go.
	var sectors := client.sectors
	if client.won:
		return                                   # (beaten: there is nowhere one must go any more)
	for id in sectors.count:
		if sectors.cell[id] == sectors.goal:
			return                               # it is on the chart: its own mark says enough
	var here := sectors.cell[sectors.here]
	var way := Vector2(sectors.goal - here)
	# where the window's edge is, in sectors from the middle; the arrow sits there
	var half := Vector2(Sectors.REACH_X + 0.5, Sectors.REACH_Y + 0.5)
	var k := minf(half.x / maxf(absf(way.x), 0.001), half.y / maxf(absf(way.y), 0.001))
	var at_cells := way * k
	var mid := area.position + area.size * 0.5
	var tip := mid + Vector2(at_cells.x / half.x, at_cells.y / half.y) * area.size * 0.5
	tip = tip.clamp(area.position + Vector2(8, 8), area.end - Vector2(8, 8))
	var dir := way.normalized()
	var side := dir.orthogonal()
	chart.draw_line(tip - dir * 40.0, tip - dir * 12.0, GOAL, 3.0)
	chart.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 18.0 + side * 7.0, tip - dir * 18.0 - side * 7.0]), GOAL)
	var label := "флагман: %d прыжк%s" % [sectors.jumps_to_goal(sectors.here), _jumps_word(sectors.jumps_to_goal(sectors.here))]
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var pos := (tip - dir * 40.0 + Vector2(-w / 2.0, 22.0)).clamp(Vector2(4, 14), chart.size - Vector2(w + 4, 4))
	chart.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOAL)


func _draw_helm() -> void:
	var sectors := client.sectors
	var here := client.sector
	var area := helm_area()
	var scale := area.size.x / Sectors.SPAN
	var font := ThemeDB.fallback_font
	chart.draw_rect(Rect2(Vector2.ZERO, chart.size), Color(0.02, 0.05, 0.04))
	chart.draw_rect(area, Color(0.03, 0.08, 0.07))
	for i in range(1, 4):
		var k := area.size.x * i / 4.0
		chart.draw_line(area.position + Vector2(k, 0), area.position + Vector2(k, area.size.y), Color(0.3, 0.8, 0.5, 0.12))
		chart.draw_line(area.position + Vector2(0, k), area.position + Vector2(area.size.x, k), Color(0.3, 0.8, 0.5, 0.12))
	chart.draw_rect(area, Color(0.3, 0.75, 0.45, 0.6), false, 1.0)
	var spot := area.position + sectors.spot[here] * scale
	match sectors.kind[here]:
		Sectors.METEORS:
			chart.draw_circle(spot, sectors.reach[here] * scale, Color(1.0, 0.55, 0.2, 0.2))
			chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 48, Color(1.0, 0.6, 0.25, 0.8), 1.0)
			chart.draw_string(font, spot + Vector2(-70, 4), "метеорный поток", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1.0, 0.75, 0.5))
		Sectors.STATION, Sectors.TRADER:
			var colour := Color(0.3, 0.85, 0.8) if sectors.kind[here] == Sectors.STATION else Color(0.95, 0.85, 0.35)
			chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 32, Color(colour, 0.6), 1.0)
			chart.draw_rect(Rect2(spot - Vector2(4, 4), Vector2(8, 8)), colour)
			chart.draw_string(font, spot + Vector2(-70, 26), "станция" if sectors.kind[here] == Sectors.STATION else
				("торговец: " + Sectors.DEAL_NAMES[sectors.deal[here]] if sectors.deal.size() > here else "торговец"),
				HORIZONTAL_ALIGNMENT_CENTER, 140, 12, colour)
		Sectors.DERELICT:
			var grey := Color(0.7, 0.7, 0.72)
			chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 32, Color(grey, 0.6), 1.0)
			chart.draw_rect(Rect2(spot - Vector2(5, 3), Vector2(10, 6)), grey, false, 1.5)
			chart.draw_string(font, spot + Vector2(-70, 26), "брошенный корабль", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, grey)
	var ship := area.position + client.ship_pos() * scale
	if client.ship_under_way() and client.jump_to == Net.NO_SECTOR:
		var dest := area.position + client.ship_dest * scale
		chart.draw_line(ship, dest, Color(1, 1, 1, 0.55), 1.0)
		chart.draw_line(dest + Vector2(-5, -5), dest + Vector2(5, 5), Color.WHITE, 1.0)
		chart.draw_line(dest + Vector2(-5, 5), dest + Vector2(5, -5), Color.WHITE, 1.0)
	chart.draw_circle(ship, 5.0, Color.WHITE)
	chart.draw_arc(ship, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.6), 1.0)
