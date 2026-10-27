extends RefCounted
## The two bridge consoles, as shown in the console frame of GameScreen: the
## sector console (the chart of sectors and a button for every jump in reach)
## and the ship's controls (the sector as a square: click to set a course,
## buttons to stop and to dock). GameScreen owns the controls and opens and
## closes the frame; this fills them in.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Gear := preload("res://src/shared/gear.gd")
const Stations := preload("res://src/server/stations.gd")    # only for its numbers
const Sprites := preload("res://src/client/sprites.gd")
const OURS := Color(87 / 255.0, 191 / 255.0, 236 / 255.0, 132 / 255.0)   # (v91) the colour of the author's ship icons
# (v77) What each kind of place found takes (Sectors.P_*), and the work places' hint once the ship is there.
const PLACE_HINTS: Array[String] = [
	"Обломки, контейнер, тела, поле боя: подлетите к метке, найденное подберут или оно всплывёт у шлюза.",
	"Обломки, контейнер, тела, поле боя: подлетите к метке, найденное подберут или оно всплывёт у шлюза.",
	"Обломки, контейнер, тела, поле боя: подлетите к метке, найденное подберут или оно всплывёт у шлюза.",
	"Брошенный корабль: подлетите к метке, он встанет над шлюзом.",
	"Обломки, контейнер, тела, поле боя: подлетите к метке, найденное подберут или оно всплывёт у шлюза.",
	"Засаду лучше облететь стороной: подлетев близко, пираты выходят в бой.",
	"Аномалия: подлетите к метке и остановитесь, потом изучайте её с голокарты.",
	"Астероид: подлетите к метке и остановитесь, потом выйдите в скафандре: от него откалывается руда.",
	"Газовое облако: подлетите к метке и остановитесь, потом встаньте к двигателю: топливозаборник наполняет бак.",
	"Разбитый пират: подлетите к метке, обломки встанут над шлюзом.",
]
const WORK_HERE: Array[String] = [
	"Корабль у аномалии: пока он стоит, изучайте её с голокарты.",
	"Корабль у астероида: пока он стоит, выйдите в скафандре, от него откалывается руда.",
	"Корабль в газовом облаке: пока он стоит и кто-то стоит у двигателя, бак наполняется.",
]
const ALERT_ABOUT: Array[String] = [
	"обычная служба.",
	"боты без дела идут на посты ремонта.",
	"все по постам, двери заперты, свет приглушён.",
]

var client: GameClient
var chart: Control                   # the picture
var text: Label                      # the lines under it
var buttons: GridContainer           # the buttons under those
var buttons_for := -1                # what the buttons were last built for (-1: build them anew)
var _story_seen := 0                 # (v63) the comms console's marks as last drawn
var show_road := false               # (v64, the author's C16) the chart shows the road of clusters instead of this one
var _icons: Texture2D                # (v91) the tile sheet, for the author's ship icons
var _heading := 0.0                  # (v91) the way our ship's icon points (it keeps it when the ship stops)


func _init(p_client: GameClient, p_chart: Control, p_text: Label, p_buttons: GridContainer) -> void:
	client = p_client
	chart = p_chart
	text = p_text
	buttons = p_buttons


func update_chart() -> void:
	## The sector console: the cluster, where the ship is, the drive, the fuel, and a jump
	## button for every sector a lane leads to (v64: and the long jump out at an exit).
	var sectors := client.sectors
	if sectors.count == 0:
		return
	var now := client.server_now()
	var jumping := client.jump_to != Net.NO_SECTOR
	var wait := (client.drive_ready - now) / Net.TICK_HZ
	var lines := PackedStringArray()
	lines.append("Скопление «%s» (%d-е на пути): %s." % [Sectors.CLUSTER_NAMES[sectors.ckind], sectors.depth + 1, Sectors.CLUSTER_ABOUT[sectors.ckind]])
	if jumping:
		lines.append("Корабль в секторе %s. Курс задан: %s. Прыжок через %d с." % [
			sectors.describe(client.sector), sectors.describe(client.jump_to) if client.jump_to == Sectors.EXIT_JUMP or knows_jump() else "«%s»" % sectors.names[client.jump_to],
			maxi(int(ceil((client.jump_tick - now) / Net.TICK_HZ)), 0)])
	elif wait > 0.0:
		lines.append("Корабль в секторе %s. Двигатель перезаряжается: ещё %d с." % [sectors.describe(client.sector), int(ceil(wait))])
	else:
		lines.append("Корабль в секторе %s. Двигатель готов. Куда прыгаем? (Кнопка ниже или щелчок по соседнему сектору на карте.)" % sectors.describe(client.sector))
	# (v67) fuel in units: a lane jump burns jump_cost from the tank, the long jump EXIT_FUEL times that
	var fuel := client.fuel
	var cans := client.stock(Net.ITEM_FUEL)
	lines.append("Топливо в баке: %d из %d. Прыжок сжигает %d, долгий прыжок из скопления %d; полёт внутри сектора тоже расходует топливо.%s" % [
		fuel, client.fuel_max, client.jump_cost, client.jump_cost * Sectors.EXIT_FUEL,
		(" Канистр в шкафу: %d (по %d, заливать у двигателя)." % [cans, Net.CAN_FUEL]) if cans > 0 else
		(" Топлива на прыжок нет! Его продаёт торговец, оно бывает в газовых облаках, на брошенных кораблях и в тайниках." if fuel < client.jump_cost else "")])
	var k := sectors.exit_of(client.sector)
	if k >= 0:
		lines.append(("Это выход из скопления: долгим прыжком отсюда в скопление «%s» (%s). Назад в это скопление уже не вернуться." %
			[Sectors.CLUSTER_NAMES[sectors.beyond[k]], Sectors.CLUSTER_ABOUT[sectors.beyond[k]]]) if not (sectors.locked and not client.won) else
			"Это выход из скопления, но глушилка флагмана держит его закрытым, пока флагман не разбит.")
	else:
		lines.append("Выходы из скопления отмечены стрелками справа: оттуда долгий прыжок в следующее.")
	# (v64) the pirate hunters
	var road: Dictionary = client.road
	if road.get("fog", false):
		lines.append("Мы в туманности: охотники нас не видят, но и наши сенсоры слепы. Что в соседних секторах, не видно.")
	else:
		var hunters: Array = road.get("hunters", [])
		var due := int(road.get("hunter_s", 65535))
		var line := "Пиратских охотников в скоплении: %d (красные ромбы)." % hunters.size() if not hunters.is_empty() else "Охотников в скоплении пока нет."
		if due != 65535:
			line += " Следующий придёт через %d:%02d." % [due / 60, due % 60]
		lines.append(line)
	var st: Dictionary = client.story
	if st.hash() != _story_seen:
		_story_seen = st.hash()
		chart.queue_redraw()
	if client.won:
		lines.append("Флагман пиратов повержен: цель пути достигнута. Летите куда хотите.")
	elif int(st.get("flags", 0)) & Net.STORY_FLAGSHIP and sectors.goal != Sectors.NO_GOAL:
		var d: int = sectors.hops_between(sectors.cell[client.sector], st["flagship"])
		lines.append("Флагман пиратов рыщет по скоплению: %s (красный треугольник). Рост: %d из 4." % [
			"он в нашем секторе!" if d == 0 else ("%d прыжк%s отсюда" % [d, _jumps_word(d)] if d > 0 else "где-то рядом"), int(st["growth"])])
	elif sectors.depth < Sectors.FLAG_DEPTH:
		var left := Sectors.FLAG_DEPTH - sectors.depth
		lines.append("Цель пути, флагман пиратов, ждёт в %d-м скоплении: впереди ещё %d скоплени%s до него." % [Sectors.FLAG_DEPTH + 1, left, "е" if left == 1 else ("я" if left < 5 else "й")])
	text.text = "\n".join(lines)
	# one button per sector a lane leads to, the long jump at an exit, and the road; rebuilt when they change
	var place_key := hash([sectors.cell[client.sector], client.road.get("known", PackedByteArray()), k, sectors.locked and not client.won, show_road, client.jump_cost])
	if buttons_for != place_key:
		buttons_for = place_key
		for old in buttons.get_children():
			old.queue_free()
		var number := 0                         # (v73, C2) each jump's number key (the old buttons go only at the frame's end)
		for id in sectors.neighbours(client.sector):
			number += 1
			var go := Button.new()
			go.text = "%d. Прыжок: %s" % [number, (sectors.describe(id) if client.knows_sector(id) else "«%s», неизвестно" % sectors.names[id])]
			go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			go.pressed.connect(client.send_jump.bind(id))
			go.set_meta("fuel", 1)              # (lane jumps' worth)
			go.set_meta("to", id)               # (v89) a click on the chart finds its button
			buttons.add_child(go)
		if k >= 0:
			var out := Button.new()
			out.text = ("%d. " % (number + 1)) + "Долгий прыжок: в скопление «%s» (%d топлива)" % [Sectors.CLUSTER_NAMES[sectors.beyond[k]], Sectors.EXIT_FUEL * client.jump_cost]
			out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			out.pressed.connect(client.send_jump.bind(Sectors.EXIT_JUMP))
			out.set_meta("fuel", Sectors.EXIT_FUEL)
			out.set_meta("exit", true)
			out.set_meta("to", Sectors.EXIT_JUMP)
			buttons.add_child(out)
		var view := Button.new()
		view.text = "Карта скопления" if show_road else "Карта пути"
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.pressed.connect(func() -> void:
			show_road = not show_road
			buttons_for = -1
			chart.queue_redraw())
		buttons.add_child(view)
		chart.queue_redraw()
	for go in buttons.get_children():
		if go is Button and go.has_meta("fuel"):
			(go as Button).disabled = jumping or wait > 0.0 or fuel < int(go.get_meta("fuel")) * client.jump_cost \
				or (go.has_meta("exit") and sectors.locked and not client.won)
	if jumping:
		chart.queue_redraw()


func knows_jump() -> bool:
	return client.jump_to < client.sectors.count and client.knows_sector(client.jump_to)


func _draw_story(place: Callable) -> void:
	## (v63) Marks from the comms console: quests' targets, SOS calls, and the roaming flagship.
	var sectors := client.sectors
	var font := ThemeDB.fallback_font
	var st: Dictionary = client.story
	var awake := int(st.get("flags", 0)) & Net.STORY_FLAGSHIP != 0 and not client.won
	for id in sectors.count:
		var at: Vector2 = place.call(id)
		var c: Vector2i = sectors.cell[id]
		for m: Array in st.get("marks", []):
			if m[1] == c and int(m[0]) == Net.MARK_SOS:
				chart.draw_string(font, at + Vector2(-12, -12), "SOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.35, 0.3))
		for q: Dictionary in st.get("quests", []):
			if q["at"] == c:
				var d := 9.0
				chart.draw_polyline(PackedVector2Array([at + Vector2(0, -d - 6), at + Vector2(d, -6), at + Vector2(0, d - 6),
					at + Vector2(-d, -6), at + Vector2(0, -d - 6)]), QUEST, 2.0)
				chart.draw_string(font, at + Vector2(10, -10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, QUEST)
		if awake and st["flagship"] == c:
			# (v80, the author's note: the mark hid the system under it) a pointer above the system, not on it
			chart.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -17), at + Vector2(7, -29), at + Vector2(-7, -29)]), GOAL)
			chart.draw_string(font, at + Vector2(-40, -33), "ФЛАГМАН", HORIZONTAL_ALIGNMENT_CENTER, 80, 11, GOAL)


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
	elif client.other_here() and client.other_rock:
		lines.append("Над шлюзом астероид. Руду добывают из его жил в скафандре: держите E у жилы. Тронемся, и он останется позади.")
	elif client.other_here() and client.other_wreck:
		lines.append("Разбитый пиратский корабль пристыкован к шлюзу." if client.other_docked else
			"Над шлюзом разбитый пиратский корабль. До него можно добраться через открытый космос или пристыковаться.")
		lines.append("Пока кто-то снаружи или корабли состыкованы, корабль не тронется и не прыгнет. Тронемся, и обломки останутся позади.")
	if client.meteor_left > 0.0:
		# (v70, the author's H1) a meteor seen coming: the pilot steers round it
		lines.append("МЕТЕОР ПО КУРСУ! Удар через %.1f с. %s" % [client.meteor_left, "Манёвр сделан." if client.meteor_tried else
			"Уклонение (пробел): %d%% увернуться, %d заряда СМЭС." % [roundi(100.0 * (Stations.METEOR_DODGE + Stations.METEOR_SKILL * client.skills[Net.SKILL_PILOT] / float(Net.SKILL_MAX))), int(Stations.METEOR_COST)]])
	if client.fighting():
		# (v55) the battle position
		var pos := "Позиция в бою: %s." % Net.POS_NAMES[client.battle_pos].to_lower()
		if client.battle_goal != Net.POS_NONE:
			pos += " Манёвр на «%s»: ещё %d с, пока он идёт, мы не уклоняемся." % [Net.POS_NAMES[client.battle_goal].to_lower(), client.battle_left]
		lines.append(pos + " Уклонение от их выстрелов: %d%% (пока здесь стоит пилот)." % client.our_dodge)
		lines.append("Вплотную: можно на абордаж. На дистанции: обе стороны попадают реже. С фланга: мы попадаем лучше, уклоняемся хуже. Позицию держит тот, кто за штурвалом.")
		# (v68, the author's F1) the evade: press it as their guns are about to fire
		var ready := PackedStringArray()
		for c: int in client.enemy_charge:
			if c != 255:
				ready.append("%d%%" % c)
		var evade := "Уклонение идёт: ещё %.1f с." % (client.evade_left / 10.0) if client.evade_left > 0 else \
			("Уклонение перезаряжается: ещё %d с." % client.evade_rest if client.evade_rest > 0 else
			"Уклонение готово (пробел): на миг их выстрелы попадают вдвое реже, %d заряда СМЭС." % int(Stations.EVADE_COST))
		if not ready.is_empty():
			evade += " Заряд их орудий: %s." % ", ".join(ready)
		lines.append(evade)
		if _has_phase():
			# (v59) the phase drive
			lines.append(("Фазовый привод готов: следующая смена позиции мгновенная, можно зайти в тыл (мы попадаем лучше, они хуже)."
				if client.phase_left == 0 else "Фазовый привод перезаряжается: ещё %d с. Пока что позиция меняется обычным манёвром." % client.phase_left))
	match sectors.kind[here]:
		Sectors.METEORS:
			var edge := float(sectors.reach[here]) - at.distance_to(sectors.spot[here])
			lines.append("Корабль внутри метеорного потока, до края %d." % int(ceil(edge)) if edge >= 0.0 else "Корабль вне метеорного потока.")
		Sectors.ION_STORM:
			# (v61) the ion storm
			var edge := float(sectors.reach[here]) - at.distance_to(sectors.spot[here])
			lines.append(("Корабль внутри ионного шторма, до края %d. Реактор даёт половину энергии, разряды выбивают орудия, щит и СМЭС." % int(ceil(edge)))
				if edge >= 0.0 else "Корабль вне ионного шторма.")
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
			if client.road.get("places", []).is_empty() and not client.fighting():
				lines.append("Здесь нет ничего примечательного. Облетите сектор: сенсоры могут найти тайники.")
	# (v64) the places found inside the sector
	var found := PackedStringArray()
	for pl: Array in client.road.get("places", []):
		found.append(Sectors.PLACE_NAMES[int(pl[0])] + (" (пусто)" if pl[2] and int(pl[0]) != Sectors.P_WRECK else ""))
	if not found.is_empty():
		lines.append("Сенсоры нашли: %s." % ", ".join(found))
		# (v77, the author's note: the gas cloud "does nothing") each kind says what it takes
		var hints := PackedStringArray()
		for pl: Array in client.road.get("places", []):
			var kind := int(pl[0])
			var hint: String = PLACE_HINTS[kind] if kind < PLACE_HINTS.size() else ""
			if pl[2] or hint == "" or hints.has(hint):
				continue
			if kind >= Sectors.P_ANOMALY and kind <= Sectors.P_GAS and at.distance_to(pl[1]) <= Sectors.WORK_REACH:
				hint = WORK_HERE[kind - Sectors.P_ANOMALY]
			hints.append(hint)
		lines.append_array(hints)
	if client.road.get("fog", false):
		lines.append("Сектор в туманности: сенсоры видят только вблизи.")
	lines.append("%s: %s" % [Net.ALERT_NAMES[client.alert], ALERT_ABOUT[client.alert]])
	text.text = "\n".join(lines)
	var buttons_key := Sectors.key(sectors.cell[here]) * 128 + 1 + (2 if client.other_here() else 0) + (4 if client.other_docked else 0) \
		+ (8 if client.pirates_alongside() else 0) + (32 if client.other_wreck or client.other_rock else 0) + (16 if client.fighting() else 0) \
		+ (64 if _has_phase() else 0)
	buttons_key = buttons_key * 2 + (1 if client.meteor_left > 0.0 and not client.fighting() else 0)   # (v70) the meteor button
	if buttons_for != buttons_key:
		buttons_for = buttons_key
		for old in buttons.get_children():
			old.queue_free()
		var halt := Button.new()
		halt.text = "Остановить корабль"
		halt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		halt.pressed.connect(func() -> void: client.send_helm(false))
		buttons.add_child(halt)
		if client.other_here() and not client.other_rock and (client.other_docked or not client.pirates_alongside()):
			var dock := Button.new()
			dock.text = ("Расстыковаться с пиратским кораблём" if client.pirates_alongside() else "Расстыковаться") \
				if client.other_docked else ("Пристыковаться к разбитому кораблю" if client.other_wreck else "Пристыковаться к брошенному кораблю")
			dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var on := not client.other_docked
			dock.pressed.connect(func() -> void: client.send_dock(on))
			buttons.add_child(dock)
		if client.fighting():
			for pos in ([Net.POS_CLOSE, Net.POS_FAR, Net.POS_FLANK, Net.POS_BEHIND] if _has_phase() else [Net.POS_CLOSE, Net.POS_FAR, Net.POS_FLANK]):
				var go := Button.new()
				go.text = ["Подойти вплотную", "Отойти на дистанцию", "Зайти с фланга", "Фазой в тыл"][pos]
				go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				go.set_meta("pos", pos)
				go.pressed.connect(func() -> void: client.send_position(pos))
				buttons.add_child(go)
			var dodge := Button.new()
			dodge.text = "Уклонение!"
			dodge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dodge.set_meta("evade", true)
			dodge.pressed.connect(func() -> void: client.send_evade())
			buttons.add_child(dodge)
		elif client.meteor_left > 0.0:
			var steer := Button.new()
			steer.text = "Уклонение от метеора!"
			steer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			steer.set_meta("steer", true)
			steer.pressed.connect(func() -> void: client.send_evade())
			buttons.add_child(steer)
		for level in [Net.ALERT_GREEN, Net.ALERT_YELLOW, Net.ALERT_RED]:
			var al := Button.new()
			al.text = Net.ALERT_NAMES[level]
			al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			al.set_meta("alert", level)
			al.pressed.connect(func() -> void: client.send_alert(level))
			buttons.add_child(al)
	for b in buttons.get_children():
		if b is Button:
			(b as Button).focus_mode = Control.FOCUS_NONE   # (v68) the space bar is the evade, not "press the focused button"
			(b as Button).disabled = leaving
			if b.has_meta("pos"):
				var pos: int = b.get_meta("pos")
				(b as Button).disabled = pos == (client.battle_goal if client.battle_goal != Net.POS_NONE else client.battle_pos) \
					or (pos == Net.POS_BEHIND and client.phase_left > 0)
			elif b.has_meta("evade"):
				(b as Button).disabled = leaving or client.evade_left > 0 or client.evade_rest > 0 or client.battle_goal != Net.POS_NONE
			elif b.has_meta("steer"):
				(b as Button).disabled = leaving or client.meteor_tried
			elif b.has_meta("alert"):
				(b as Button).disabled = b.get_meta("alert") == client.alert
	chart.queue_redraw()


func _has_phase() -> bool:
	return Gear.has_module(client.gear_modules, Gear.MOD_PHASE)


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


func chart_clicked(click: InputEventMouseButton) -> void:
	## (v89, the author's note: "click on a system to move to it") A click on a system a lane leads to
	## (or on an exit's arrow) does what its jump button does, while that button can be pressed.
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or show_road or client.sectors.count == 0:
		return
	var sectors := client.sectors
	var area := _chart_area()
	var best := -1
	var near := 16.0
	for id in sectors.neighbours(client.sector):
		var d := (area.position + Vector2(sectors.pos[id].x / 100.0, sectors.pos[id].y / 60.0) * area.size).distance_to(click.position)
		if d < near:
			near = d
			best = id
	if best < 0 and sectors.exit_of(client.sector) >= 0:
		var at := area.position + Vector2(sectors.pos[client.sector].x / 100.0, sectors.pos[client.sector].y / 60.0) * area.size
		if Rect2(at + Vector2(10, -14), Vector2(50, 22)).has_point(click.position):
			best = Sectors.EXIT_JUMP
	if best < 0:
		return
	for go in buttons.get_children():
		if go is Button and go.has_meta("to") and int(go.get_meta("to")) == best:
			if not (go as Button).disabled:
				client.send_jump(best)
			return


func _chart_area() -> Rect2:
	## Where the systems are drawn on the chart (as _draw_chart places them).
	return Rect2(Vector2(30, 22), chart.size - Vector2(100, 68))


func draw(kind: int) -> void:
	## The picture of the console of that kind (as GameClient.use_target): the
	## ship's controls (4) or the chart of sectors (3).
	if kind == 4:
		_draw_helm()
	else:
		_draw_chart()


func _icon(at: Vector2, which: int, colour: Color, angle: float = 0.0) -> bool:
	## (v91, the author's M5) One of his five ship pictures on the chart (map_ship_1..5), centred there and
	## turned by `angle` (it points left). False when the sheet has none (an older sheet of one's own).
	var id: int = client.map.tile_ids.get("map_ship_%d" % which, -1)
	if id < 0:
		return false
	if _icons == null:
		_icons = Sprites.sheet("tiles")
	var cols := client.map.atlas_columns
	var big := 1.0 if which == 5 else 2.0    # (the small ones are drawn twice as big)
	chart.draw_set_transform(at, angle, Vector2(big, big))
	chart.draw_texture_rect_region(_icons, Rect2(-16, -16, 32, 32), Rect2((id % cols) * 32, (id / cols) * 32, 32, 32), colour)
	chart.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _draw_chart() -> void:
	## The chart of the cluster: where the ship is, where it can jump, what is known about
	## the rest, the exits, the hunters and the nebula. (v64) Or the road of clusters.
	var sectors := client.sectors
	if sectors.count == 0:
		return
	chart.draw_rect(Rect2(Vector2.ZERO, chart.size), Color(0.02, 0.05, 0.04))
	if show_road:
		_draw_road()
		return
	var area := _chart_area()
	var place := func(id: int) -> Vector2:
		return area.position + Vector2(sectors.pos[id].x / 100.0, sectors.pos[id].y / 60.0) * area.size
	var font := ThemeDB.fallback_font
	# the nebula first, under everything
	for id in sectors.count:
		if sectors.fog[id] == 1:
			chart.draw_circle(place.call(id), 34.0, FOG)
	for l: Array in sectors.links:
		var near: bool = int(l[0]) == client.sector or int(l[1]) == client.sector
		chart.draw_line(place.call(int(l[0])), place.call(int(l[1])), Color(0.3, 0.8, 0.5, 0.75 if near else 0.22), 2.0 if near else 1.0)
	if client.jump_to != Net.NO_SECTOR and client.jump_to < sectors.count:
		chart.draw_line(place.call(client.sector), place.call(client.jump_to), Color(1, 1, 1, 0.9), 3.0)
	var colours := [Color(0.55, 0.62, 0.75), Color(1.0, 0.6, 0.25), Color(0.95, 0.85, 0.35), Color(0.3, 0.85, 0.8), Color(0.78, 0.5, 0.88),
		GOAL, ION]   # one per Sectors.KIND_NAMES
	# the exits: an arrow on to the next cluster, with its kind
	var locked := sectors.locked and not client.won
	for k in sectors.exits.size():
		var at: Vector2 = place.call(sectors.exits[k])
		var tip := at + Vector2(46, 0)
		var ink := Color(0.6, 0.6, 0.6) if locked else EXIT
		chart.draw_line(at + Vector2(14, 0), tip, ink, 2.0)
		chart.draw_colored_polygon(PackedVector2Array([tip + Vector2(8, 0), tip + Vector2(-2, -6), tip + Vector2(-2, 6)]), ink)
		var label := "закрыт" if locked else Sectors.CLUSTER_NAMES[sectors.beyond[k]]
		chart.draw_string(font, at + Vector2(14, -8), label, HORIZONTAL_ALIGNMENT_LEFT, 90, 10, ink)
		if client.jump_to == Sectors.EXIT_JUMP and sectors.exits[k] == client.sector:
			chart.draw_line(at, tip, Color.WHITE, 3.0)
	for id in sectors.count:
		var at: Vector2 = place.call(id)
		var known := client.knows_sector(id)
		if not known:
			chart.draw_circle(at, 4.0, Color(0.3, 0.36, 0.34))     # something is there; nobody knows what
			chart.draw_string(font, at + Vector2(-4, -7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.56, 0.54))
		else:
			chart.draw_circle(at, 7.0, colours[sectors.kind[id]])
			if sectors.kind[id] == Sectors.FLAGSHIP:
				chart.draw_arc(at, 11.0, 0.0, TAU, 32, GOAL, 2.0)
		if sectors.visited[id] == 1:
			chart.draw_circle(at, 2.5, Color(0.04, 0.08, 0.07))    # been there
		if id == client.sector:
			chart.draw_arc(at, 12.0, 0.0, TAU, 32, Color.WHITE, 2.0)
		if known or id == client.sector:
			chart.draw_string(font, at + Vector2(-60, 22), sectors.names[id], HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(0.85, 0.95, 0.88))
	# the hunters
	for h: Array in client.road.get("hunters", []):
		if int(h[0]) < sectors.count:
			var at: Vector2 = place.call(int(h[0])) + Vector2(10, -10)
			if not _icon(at, 1, HUNTER):         # (v91) the author's small fast ship
				chart.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), HUNTER)
			if h[1]:
				chart.draw_arc(at, 8.0, 0.0, TAU, 16, HUNTER, 1.5)
	_draw_story(place)
	# legend: what the colours are, then what the marks are
	var ink := Color(0.7, 0.8, 0.74)
	var x := 8.0
	var y := chart.size.y - 28
	for k in Sectors.KIND_NAMES.size():
		var w: float = 20.0 + font.get_string_size(Sectors.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		if x + w > chart.size.x and x > 8.0:
			x = 8.0                              # (v61) seven kinds: the rest go on a line above
			y -= 16.0
		chart.draw_circle(Vector2(x + 5, y), 5.0, colours[k])
		chart.draw_string(font, Vector2(x + 14, y + 4), Sectors.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		x += w
	x = 8.0
	y = chart.size.y - 10
	var grey := colours[0] as Color
	for mark in 7:
		var at := Vector2(x + 5, y)
		var text := ""
		match mark:
			0:
				chart.draw_arc(at, 6.0, 0.0, TAU, 24, Color.WHITE, 1.5)
				text = "корабль здесь"
			1:
				chart.draw_circle(at, 5.0, grey)
				chart.draw_circle(at, 2.0, Color(0.04, 0.08, 0.07))
				text = "уже были"
			2:
				chart.draw_circle(at, 3.0, Color(0.3, 0.36, 0.34))
				text = "неизвестно"
			3:
				chart.draw_line(at - Vector2(5, 0), at + Vector2(7, 0), Color(0.3, 0.8, 0.5, 0.75), 2.0)
				text = "трасса"
			4:
				chart.draw_line(at - Vector2(5, 0), at + Vector2(5, 0), EXIT, 2.0)
				chart.draw_colored_polygon(PackedVector2Array([at + Vector2(9, 0), at + Vector2(4, -4), at + Vector2(4, 4)]), EXIT)
				text = "выход"
			5:
				chart.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(4, 0), at + Vector2(0, 5), at + Vector2(-4, 0)]), HUNTER)
				text = "охотник"
			6:
				chart.draw_circle(at, 6.0, Color(FOG, 0.6))
				text = "туманность"
		chart.draw_string(font, Vector2(x + 16, y + 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		x += 30.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


const GOAL := Color(1.0, 0.25, 0.25)      # (v57) the flagship's sector, and the way to it
const QUEST := Color(1.0, 0.85, 0.3)       # (v63) a quest's target
const ION := Color(0.4, 0.55, 1.0)         # (v61) an ion storm
const EXIT := Color(0.55, 0.95, 1.0)       # (v64) a way out of the cluster
const HUNTER := Color(1.0, 0.3, 0.45)      # (v64) a pirate hunter
const FOG := Color(0.55, 0.5, 0.65, 0.22)  # (v64) a nebula
const PLACE_COLOURS: Array[Color] = [Color(0.75, 0.7, 0.6), Color(0.95, 0.75, 0.3), Color(0.85, 0.85, 0.95), Color(0.7, 0.7, 0.72),
	Color(1.0, 0.6, 0.4), Color(1.0, 0.3, 0.45), Color(0.75, 0.5, 1.0), Color(0.65, 0.55, 0.45), Color(0.4, 0.85, 0.75), Color(0.85, 0.5, 0.45)]   # (v64) per Sectors.P_* (v67: and work places; v69: our wrecks)
const CLUSTER_COLOURS: Array[Color] = [Color(0.55, 0.62, 0.75), Color(0.95, 0.35, 0.3), Color(0.95, 0.85, 0.35), Color(0.4, 0.55, 1.0),
	Color(0.6, 0.6, 0.55)]                 # (v64) per kind of cluster


func _draw_road() -> void:
	## (v64, the author's C16) The road of clusters: those behind us, ours, the two ahead
	## to choose from, and how far the flagship's lair is.
	var sectors := client.sectors
	var font := ThemeDB.fallback_font
	var behind := sectors.road
	var shown := mini(behind.size(), 4)       # the last four behind us
	var steps := shown + 1 + 1 + maxi(Sectors.FLAG_DEPTH - sectors.depth - 1, 0)
	var w := (chart.size.x - 40.0) / maxf(steps, 4.0)
	var mid := chart.size.y * 0.45
	var box := Vector2(minf(w - 16.0, 130.0), 46.0)
	var x := 20.0
	var draw_box := func(at: Vector2, title: String, sub: String, colour: Color, ours: bool, dim: bool) -> void:
		var r := Rect2(at - box * 0.5, box)
		chart.draw_rect(r, Color(colour, 0.12 if dim else 0.25))
		chart.draw_rect(r, Color.WHITE if ours else Color(colour, 0.5 if dim else 0.9), false, 2.0 if ours else 1.0)
		chart.draw_string(font, r.position + Vector2(4, 18), title, HORIZONTAL_ALIGNMENT_CENTER, box.x - 8, 11, Color(0.9, 0.95, 0.92, 0.5 if dim else 1.0))
		chart.draw_string(font, r.position + Vector2(4, 36), sub, HORIZONTAL_ALIGNMENT_CENTER, box.x - 8, 10, Color(0.7, 0.8, 0.74, 0.5 if dim else 1.0))
	var last := Vector2(-1, -1)
	for i in shown:
		var kind: int = behind[behind.size() - shown + i]
		var at := Vector2(x + w * 0.5, mid)
		draw_box.call(at, Sectors.CLUSTER_NAMES[kind], "пройдено", CLUSTER_COLOURS[kind], false, true)
		if last.x >= 0:
			chart.draw_line(last + Vector2(box.x * 0.5, 0), at - Vector2(box.x * 0.5, 0), Color(0.5, 0.6, 0.55), 1.0)
		last = at
		x += w
	var here := Vector2(x + w * 0.5, mid)
	draw_box.call(here, Sectors.CLUSTER_NAMES[sectors.ckind], "мы здесь (%d-е)" % (sectors.depth + 1), CLUSTER_COLOURS[sectors.ckind], true, false)
	if last.x >= 0:
		chart.draw_line(last + Vector2(box.x * 0.5, 0), here - Vector2(box.x * 0.5, 0), Color(0.5, 0.6, 0.55), 1.0)
	x += w
	var locked := sectors.locked and not client.won
	for k in sectors.exits.size():
		var at := Vector2(x + w * 0.5, mid + (k * 2 - 1) * (box.y * 0.5 + 10.0))
		var kind: int = sectors.beyond[k]
		draw_box.call(at, Sectors.CLUSTER_NAMES[kind], "выход %s" % ("закрыт" if locked else ["сверху", "снизу"][k]), CLUSTER_COLOURS[kind], false, locked)
		chart.draw_line(here + Vector2(box.x * 0.5, 0), at - Vector2(box.x * 0.5, 0), EXIT, 1.5)
	x += w
	var left := Sectors.FLAG_DEPTH - sectors.depth - 1
	for i in maxi(left, 0):
		var at := Vector2(x + w * 0.5, mid)
		var lair := i == left - 1
		draw_box.call(at, "логово флагмана" if lair else "неизвестно", "%d-е скопление" % (sectors.depth + 3 + i), GOAL if lair else Color(0.4, 0.45, 0.43), false, not lair)
		x += w
	var line := "Флагман пиратов разбит: дальше скопления всё опаснее, лететь можно сколько угодно." if client.won else (
		"Мы в логове флагмана: выходы откроются, когда он будет разбит." if sectors.depth == Sectors.FLAG_DEPTH else
		("Флагман позади, но не разбит." if sectors.depth > Sectors.FLAG_DEPTH else "Каждое скопление опаснее прошлого. Вид скопления за выходом виден заранее."))
	chart.draw_string(font, Vector2(16, chart.size.y - 16), line, HORIZONTAL_ALIGNMENT_LEFT, chart.size.x - 32, 12, Color(0.75, 0.85, 0.8))


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
		Sectors.ION_STORM:
			chart.draw_circle(spot, sectors.reach[here] * scale, Color(ION, 0.18))
			chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 48, Color(ION, 0.8), 1.0)
			chart.draw_string(font, spot + Vector2(-70, 4), "ионный шторм", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, ION.lightened(0.3))
		Sectors.STATION, Sectors.TRADER:
			var colour := Color(0.3, 0.85, 0.8) if sectors.kind[here] == Sectors.STATION else Color(0.95, 0.85, 0.35)
			chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 32, Color(colour, 0.6), 1.0)
			if sectors.kind[here] == Sectors.STATION or not _icon(spot, 2, colour):    # (v91) a trader: his freighter
				chart.draw_rect(Rect2(spot - Vector2(4, 4), Vector2(8, 8)), colour)
			chart.draw_string(font, spot + Vector2(-70, 26), "станция" if sectors.kind[here] == Sectors.STATION else
				("торговец: " + Sectors.DEAL_NAMES[sectors.deal[here]] if sectors.deal.size() > here else "торговец"),
				HORIZONTAL_ALIGNMENT_CENTER, 140, 12, colour)
		Sectors.DERELICT:
			var grey := Color(0.7, 0.7, 0.72)
			chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 32, Color(grey, 0.6), 1.0)
			chart.draw_rect(Rect2(spot - Vector2(5, 3), Vector2(10, 6)), grey, false, 1.5)
			chart.draw_string(font, spot + Vector2(-70, 26), "брошенный корабль", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, grey)
	# (v64) the places found in the sector
	for pl: Array in client.road.get("places", []):
		var kind: int = pl[0]
		var at: Vector2 = area.position + (pl[1] as Vector2) * scale
		var gone: bool = pl[2] and kind != Sectors.P_WRECK
		var colour := PLACE_COLOURS[kind] if not gone else Color(0.4, 0.45, 0.43)
		match kind:
			Sectors.P_AMBUSH:
				chart.draw_circle(at, Sectors.AMBUSH_REACH * scale, Color(HUNTER, 0.12 if not gone else 0.04))
				chart.draw_arc(at, Sectors.AMBUSH_REACH * scale, 0.0, TAU, 40, Color(colour, 0.7), 1.0)
				chart.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), colour)
			Sectors.P_WRECK, Sectors.P_HULK:
				chart.draw_arc(at, Sectors.WRECK_REACH * scale, 0.0, TAU, 24, Color(colour, 0.6), 1.0)
				chart.draw_rect(Rect2(at - Vector2(5, 3), Vector2(10, 6)), colour, false, 1.5)
			Sectors.P_ANOMALY, Sectors.P_ASTEROID, Sectors.P_GAS:
				# (v67) work places: the ship must hold still inside the ring
				chart.draw_circle(at, 4.0, colour)
				chart.draw_arc(at, Sectors.WORK_REACH * scale, 0.0, TAU, 24, Color(colour, 0.5), 1.0)
			_:
				chart.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), colour)
				chart.draw_arc(at, Sectors.PLACE_REACH * scale, 0.0, TAU, 16, Color(colour, 0.4), 1.0)
		chart.draw_string(font, at + Vector2(-60, 18), Sectors.PLACE_NAMES[kind], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, colour)
	var ship := area.position + client.ship_pos() * scale
	if client.ship_under_way() and client.jump_to == Net.NO_SECTOR:
		var dest := area.position + client.ship_dest * scale
		chart.draw_line(ship, dest, Color(1, 1, 1, 0.55), 1.0)
		chart.draw_line(dest + Vector2(-5, -5), dest + Vector2(5, 5), Color.WHITE, 1.0)
		chart.draw_line(dest + Vector2(-5, 5), dest + Vector2(5, -5), Color.WHITE, 1.0)
	if client.ship_under_way() and client.ship_dest.distance_to(client.ship_pos()) > 0.5:
		_heading = (client.ship_dest - client.ship_pos()).angle() - PI
	if not _icon(ship, 5, OURS, _heading):        # (v91, the author's M5) our ship in his colour
		chart.draw_circle(ship, 5.0, Color.WHITE)
	chart.draw_arc(ship, 15.0, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 1.0)
	if client.other_here() and (not client.other_derelict or sectors.kind[here] != Sectors.DERELICT):
		# (v74, the author's note: a pirate ship our guns wrecked was not on the chart) the ship alongside
		var colour := PLACE_COLOURS[Sectors.P_HULK] if client.other_dark() else HUNTER
		var by := ship + Vector2(20, -14)
		if client.other_rock or not _icon(by, 4 if client.other_dark() else 3, colour):
			chart.draw_rect(Rect2(by - Vector2(5, 3), Vector2(10, 6)), colour, false, 1.5)
		chart.draw_string(font, by + Vector2(-60, -8), "астероид" if client.other_rock else "обломки пиратов" if client.other_wreck else
			("пираты" if client.pirates_alongside() else "корабль рядом"), HORIZONTAL_ALIGNMENT_CENTER, 120, 11, colour)
