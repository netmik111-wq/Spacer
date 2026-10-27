extends VBoxContainer
## The holomap's screen: the whole ship, deck by deck, as its sensors see it.
## Every cell of floor is coloured by the pressure in it, holes in the hull
## blink red, machines and consoles that are out of order are marked, doors show
## their emergency shutters and jams, and a dot shows where we stand. A line over
## the plan sums it up; the cell under the mouse is described under it. The
## server sends what it needs (Net.S_HOLO) while we stand at the monitor: see
## Holomap. Shown inside the console frame of GameScreen.
## (v60) A click on a door of our ship locks it against boarders (a blast door:
## it opens only for our own crew), a click again unlocks it; two buttons lock or
## unlock them all.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Gear := preload("res://src/shared/gear.gd")
const PowerView := preload("res://src/ui/power_view.gd")

const MAX_WIDTH := 820.0
const MAX_CELL := 20.0
const DECK_GAP := 26.0
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const WALL := Color(0.3, 0.36, 0.4)
const WINDOW := Color(0.45, 0.6, 0.7)
const BROKEN := Color(0.95, 0.3, 0.25)
const SHUTTER := Color(0.98, 0.8, 0.25)
const JAMMED := Color(0.98, 0.5, 0.2)
const BLAST := Color(0.75, 0.4, 0.98)
const BRIG := Color(0.95, 0.75, 0.3)             # (v75) the brig's cells
# the pressure scale: share of normal pressure -> colour (between stops the colour is blended)
const SCALE: Array = [[0.0, Color(0.16, 0.03, 0.05)], [0.2, Color(0.75, 0.16, 0.12)], [0.5, Color(0.9, 0.62, 0.18)],
	[0.76, Color(0.25, 0.62, 0.72)], [1.0, Color(0.2, 0.5, 0.85)]]

var client: GameClient
var _summary: Label
var _plan: Control
var _under: Label
var _px := 16.0
var _laid_for := 0                   # (v86) client.board_changes the plan was laid out for
var _decks: Array = []               # per deck: [first row, rows, top on the plan]
var _x0 := 0                         # the first column of the ship
var _index := {}                     # cell -> its place in client.holo_cells
var _hover := -1                     # the cell under the mouse
var _time := 0.0
var _seen := -1                      # client.holo_changes when the summary was last written
var _power: Label                    # (v61, the author's P6) the power monitor, as on the main SMES's terminal


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_plan = Control.new()
	_plan.mouse_filter = Control.MOUSE_FILTER_STOP
	_plan.draw.connect(_draw_plan)
	_plan.gui_input.connect(_on_plan_input)
	_plan.mouse_exited.connect(func() -> void: _hover = -1)
	add_child(_plan)
	_under = Label.new()
	_under.add_theme_font_size_override("font_size", 13)
	_under.custom_minimum_size = Vector2(0, 20)
	add_child(_under)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for b: Array in [["Заблокировать все двери", Net.BLAST_ALL], ["Снять блокировку со всех", Net.BLAST_NONE]]:
		var button := Button.new()
		button.text = b[0]
		button.focus_mode = Control.FOCUS_NONE
		var which: int = b[1]
		button.pressed.connect(func() -> void: client.send_blast(which))
		row.add_child(button)
	var tip := Label.new()
	tip.text = "Щелчок по двери: заблокировать её от абордажа (открывается только для своих)"
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", DIM)
	row.add_child(tip)
	_power = Label.new()
	_power.add_theme_font_size_override("font_size", 13)
	_power.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_power)
	_layout()


func _layout() -> void:
	## Where each deck of our own ship goes on the plan, and how big a cell is.
	var map := client.map
	_index.clear()
	for i in client.holo_cells.size():
		_index[client.holo_cells[i]] = i
	var x0 := map.width
	var x1 := -1
	_decks.clear()
	for d in map.deck_count:
		var first := -1
		var last := -1
		for y in range(d * map.deck_stride, mini(d * map.deck_stride + map.deck_height, map.height)):
			for x in map.width:
				var c := y * map.width + x
				if map.base_cells[c] >= 0 and (map.fleet_size() < 2 or map.fleet_of(c) == client.my_fleet):   # (v86) our ship only
					first = y if first < 0 else first
					last = y
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
		if first >= 0:
			_decks.append([first, last - first + 1, 0.0])
	if _decks.is_empty():
		return
	_x0 = x0
	var rows := 0
	for d: Array in _decks:
		rows += int(d[1])
	_px = floorf(minf(MAX_CELL, MAX_WIDTH / (x1 - x0 + 1)))
	var top := 0.0
	for d: Array in _decks:
		d[2] = top + 18.0
		top += 18.0 + int(d[1]) * _px + DECK_GAP
	_plan.custom_minimum_size = Vector2((x1 - x0 + 1) * _px, top - DECK_GAP + 34.0)


func opened() -> void:
	if _laid_for != client.board_changes:
		_laid_for = client.board_changes
		_layout()               # (v86) aboard another ship of our fleet: its plan
	_seen = -1
	_hover = -1


func refresh(delta: float) -> void:
	## Called every frame while the screen is shown.
	_time += delta
	_plan.queue_redraw()
	var key := client.holo_changes * 1000 + hash(client.gear_tiers + client.gear_modules) % 1000
	if key != _seen:
		_seen = key
		_summary.text = _sum_up()
	_under.text = _describe(_hover)
	_power.text = PowerView.monitor_text(client).replace("\n", ";  ").replace("МОНИТОР ПИТАНИЯ;  ", "Питание: ")


static func pressure_colour(share: float) -> Color:
	for i in range(1, SCALE.size()):
		if share <= float(SCALE[i][0]):
			var a: Array = SCALE[i - 1]
			var b: Array = SCALE[i]
			return (a[1] as Color).lerp(b[1], (share - float(a[0])) / (float(b[0]) - float(a[0])))
	return SCALE[SCALE.size() - 1][1]


func _air(cell: int) -> int:
	## The pressure in a cell of our ship as the holomap last said (0..Net.AIR_FULL), -1 = not known.
	var i: int = _index.get(cell, -1)
	return client.holo_air[i] if i >= 0 and i < client.holo_air.size() else -1


func _devices() -> Array:
	## Every machine and console of our ship: [cell, what it is].
	var map := client.map
	var out := []
	for c: int in map.engine.keys():
		out.append([c, "двигатель"])
	for c: int in map.air_plant.keys():
		out.append([c, "воздушная установка"])
	for c: int in map.chart.keys():
		out.append([c, "карта сектора"])
	for c: int in map.helm.keys():
		out.append([c, "управление кораблём"])
	for c: int in map.gun_console.keys():
		out.append([c, "пульт орудий"])
	for c: int in map.lock_pump.keys():
		out.append([c, "насос шлюза"])
	for c: int in map.oxygen.keys():
		out.append([c, "кислородная стойка"])
	for c: int in map.locker.keys():
		out.append([c, "шкаф снабжения"])
	for c: int in map.holo.keys():
		out.append([c, "голокарта"])
	for i in map.guns.size():
		out.append([map.guns[i], "орудие %d" % (i + 1)])
	return out


func _sum_up() -> String:
	if client.holo_changes == 0 or client.holo_air.is_empty():
		return "Связь с датчиками корабля…"
	var map := client.map
	var lines := PackedStringArray()
	var broken := PackedStringArray()
	for d: Array in _devices():
		if client.broken.has(int(d[0])):
			broken.append(d[1])
	lines.append("Обшивка: %d из %d. Пробоин: %d. %s" % [client.hull, client.hull_max, client.holo_holes.size(),
		"Всё оборудование работает." if broken.is_empty() else "Не работает: %s." % ", ".join(broken)])
	var shutters := 0
	var jams := 0
	var locked := 0
	for d in client.holo_doors.size():
		var f: int = client.holo_doors[d] >> 1
		if f & 1:
			shutters += 1
		if f & 2:
			jams += 1
		if f & 16:
			locked += 1
	# rooms: floor split by doors, on each deck
	var low := 0
	var empty := 0
	var seen := {}
	for start: int in client.holo_cells:
		if seen.has(start) or map.door_of[start] >= 0:
			continue
		var room := [start]
		seen[start] = true
		var i := 0
		var sum := 0
		while i < room.size():
			var c: int = room[i]
			i += 1
			sum += maxi(_air(c), 0)
			for o: int in [1, -1, map.width, -map.width]:
				var j := c + o
				if map.on_ship(j) and not seen.has(j) and map.door_of[j] < 0 and map.deck_of_cell(j) == map.deck_of_cell(c):
					seen[j] = true
					room.append(j)
		var share := float(sum) / (room.size() * Net.AIR_FULL)
		if share < 0.2:
			empty += 1
		elif share < 0.76:
			low += 1
	var air := "Давление везде в норме." if low + empty == 0 else "Отсеков с пониженным давлением: %d, почти без воздуха: %d." % [low, empty]
	lines.append("%s Аварийных заслонок опущено: %d. Заклинивших дверей: %d. Заблокировано от абордажа: %d." % [air, shutters, jams, locked])
	lines.append(gear_line(client))
	return "\n".join(lines)


static func gear_line(c: GameClient) -> String:
	## (v59) The ship's gear in one line: each system's crate, the modules in the bay.
	var parts := PackedStringArray()
	for sys in Gear.SYSTEMS:
		var t: int = c.gear_tiers[sys] if sys < c.gear_tiers.size() else 1
		var g := Gear.for_system(sys, t)
		parts.append(Gear.name_of(g) if g != Gear.NONE else Gear.SYS_BUILT_IN[sys].substr(0, 1).to_upper() + Gear.SYS_BUILT_IN[sys].substr(1))
	var mods := PackedStringArray()
	for g in c.gear_modules:
		if g != Gear.NONE:
			mods.append(Gear.name_of(g))
	return "Оснащение: %s (реактор %d энергии). Модульная стойка: %s." % [", ".join(parts),
		Gear.REACTOR_POWER[clampi(c.gear_tiers[Gear.SYS_REACTOR] if c.gear_tiers.size() > Gear.SYS_REACTOR else 1, 1, 3)],
		", ".join(mods) if not mods.is_empty() else "пусто"]


func _draw_plan() -> void:
	var font := ThemeDB.fallback_font
	var map := client.map
	var known := client.holo_changes > 0 and not client.holo_air.is_empty()
	var blink := 0.5 + 0.5 * sin(_time * 6.0)
	var broken_cells := {}
	for d: Array in _devices():
		broken_cells[int(d[0])] = client.broken.has(int(d[0]))
	var me := client.pred.y * map.width + client.pred.x
	for k in _decks.size():
		var deck: Array = _decks[k]
		var first: int = deck[0]
		var top: float = deck[2]
		_plan.draw_string(font, Vector2(0, top - 5), map.deck_names[map.deck_of(first)] if map.deck_of(first) < map.deck_names.size() else "Палуба",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		for y in range(first, first + int(deck[1])):
			for x in range(_x0, map.width):
				var cell := y * map.width + x
				var tile := map.base_cells[cell]
				if tile < 0:
					continue
				var r := Rect2(Vector2((x - _x0) * _px, top + (y - first) * _px), Vector2(_px, _px))
				if map.base_walk[cell] == 0:
					_plan.draw_rect(r, WINDOW if map.base_opaque[cell] == 0 and not map.on_floor.has(cell) else WALL)
					if broken_cells.has(cell):
						var bad: bool = broken_cells[cell]
						var mark := r.grow(-_px * 0.22)
						_plan.draw_rect(mark, Color(BROKEN, 0.55 + 0.45 * blink) if bad else Color(0.35, 0.85, 0.6))
						if bad:
							_plan.draw_string(font, r.position + Vector2(0, _px * 0.78), "!", HORIZONTAL_ALIGNMENT_CENTER, _px, int(_px * 0.8), Color.WHITE)
					if client.holo_holes.has(cell):
						var hole := Color(1.0, 0.2, 0.15, 0.4 + 0.6 * blink)
						_plan.draw_line(r.position + Vector2(2, 2), r.end - Vector2(2, 2), hole, 3.0)
						_plan.draw_line(Vector2(r.position.x + 2, r.end.y - 2), Vector2(r.end.x - 2, r.position.y + 2), hole, 3.0)
					continue
				var a := _air(cell)
				_plan.draw_rect(r, pressure_colour(float(a) / Net.AIR_FULL) if known and a >= 0 else Color(0.12, 0.14, 0.16))
				_plan.draw_rect(r, Color(0, 0, 0, 0.25), false, 1.0)
				if map.is_brig(cell):
					for k2 in 3:                # (v75) a brig cell: bars
						var bx := r.position.x + _px * (0.25 + 0.25 * k2)
						_plan.draw_line(Vector2(bx, r.position.y + 2), Vector2(bx, r.end.y - 2), BRIG, 1.5)
				var door := map.door_of[cell]
				if door >= 0 and door < client.holo_doors.size():
					var v: int = client.holo_doors[door]
					var f := v >> 1
					var across := map.door_kind[door] == ShipMap.DOOR_BAND      # a door in a horizontal wall: its leaf runs across
					var leaf := Rect2(r.position + Vector2(0, _px * 0.4), Vector2(_px, _px * 0.2)) if across \
						else Rect2(r.position + Vector2(_px * 0.4, 0), Vector2(_px * 0.2, _px))
					if f & 1:
						_plan.draw_rect(leaf.grow(1.0), SHUTTER)
					elif v & 1 == 0:
						_plan.draw_rect(leaf, Color(0.75, 0.78, 0.82))
					if f & 2:
						_plan.draw_rect(r.grow(-1.0), JAMMED, false, 2.0)
					elif f & 16:
						_plan.draw_rect(r.grow(-1.0), BLAST, false, 2.0)
				if cell == me and map.deck_of(y) == map.deck_of(client.pred.y):
					_plan.draw_circle(r.get_center(), _px * 0.3, Color(1, 1, 1, 0.6 + 0.4 * blink))
	# the legend
	var y0 := _plan.custom_minimum_size.y - 12.0
	var x := 0.0
	for e: Array in [[pressure_colour(1.0), "норма"], [pressure_colour(0.6), "понижено"], [pressure_colour(0.3), "опасно"],
			[pressure_colour(0.0), "вакуум"], [BROKEN, "сломано, пробоина"], [SHUTTER, "заслонка опущена"], [JAMMED, "дверь заклинило"], [BLAST, "заблокирована"], [BRIG, "гауптвахта"], [Color.WHITE, "вы здесь"]]:
		_plan.draw_rect(Rect2(Vector2(x, y0 - 10), Vector2(12, 12)), e[0])
		_plan.draw_string(font, Vector2(x + 16, y0), e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		x += 16.0 + font.get_string_size(e[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0


func _describe(cell: int) -> String:
	if cell < 0:
		return "Наведите мышь на клетку, чтобы узнать подробности."
	var map := client.map
	var deck := map.deck_names[map.deck_of_cell(cell)] if map.deck_of_cell(cell) < map.deck_names.size() else ""
	var parts := PackedStringArray([deck])
	if map.base_walk[cell] == 1:
		var a := _air(cell)
		if a >= 0:
			parts.append("давление %d кПа" % roundi(a * Net.KPA_FULL / Net.AIR_FULL))
		if map.is_brig(cell):
			parts.append("камера гауптвахты")
		var door := map.door_of[cell]
		if door >= 0 and door < client.holo_doors.size():
			var v: int = client.holo_doors[door]
			var f := v >> 1
			parts.append("дверь %s" % ("открыта" if v & 1 else "закрыта"))
			if f & 1:
				parts.append("аварийная заслонка опущена")
			if f & 2:
				parts.append("заклинило")
			if f & 4:
				parts.append("заслонка неисправна")
			if f & 16:
				parts.append("заблокирована от абордажа (щелчок: снять)")
			elif door < client.map.other_first_door:
				parts.append("щелчок: заблокировать от абордажа")
	else:
		var what := map.device_name(cell)
		for d: Array in _devices():
			if int(d[0]) == cell:
				what = d[1]
		if what != "":
			parts.append("%s: %s" % [what, "не работает" if client.broken.has(cell) else "в порядке"])
		elif map.base_opaque[cell] == 0 and not map.on_floor.has(cell):
			parts.append("иллюминатор")
		else:
			parts.append("переборка")
		if client.holo_holes.has(cell):
			parts.append("ПРОБОИНА")
	return ", ".join(parts) + "."


func _on_plan_input(event: InputEvent) -> void:
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if click and _hover >= 0:
		var door := client.map.door_of[_hover]
		if door >= 0 and door < client.map.other_first_door:
			client.send_blast(door)
		return
	if not (event is InputEventMouseMotion):
		return
	var at := (event as InputEventMouseMotion).position
	_hover = -1
	for deck: Array in _decks:
		var top: float = deck[2]
		var row := int(floor((at.y - top) / _px))
		if at.y >= top and row < int(deck[1]):
			var x := _x0 + int(floor(at.x / _px))
			var cell := (int(deck[0]) + row) * client.map.width + x
			if x >= 0 and x < client.map.width and client.map.base_cells[cell] >= 0:
				_hover = cell
			return
