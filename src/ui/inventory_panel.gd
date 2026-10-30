extends PanelContainer
## The inventory window (its own key, I by default): what our character wears
## and carries, large and with names, grouped as it is kept (at hand, in the
## jumpsuit's pockets, in the backpack), and what the chosen thing is and can do.
## A click takes a thing into the hand; a right click puts it on the floor; a
## click on clothing takes it off. The character can walk while it is open.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Options := preload("res://src/client/options.gd")

const CELL := 56.0
const GAP := 8.0
const LABEL_H := 16.0
const ROW_H := CELL + LABEL_H + 26.0       # a cell, its name under it, the group's caption over it
const WORN_NAMES: Array[String] = ["Скафандр", "Комбинезон", "Рюкзак", "Очки", "Бронежилет", "Энергощит", "Каска", "Ручной щит"]   # (v93, v98)
# the groups of slots: caption, first slot, how many
const GROUPS: Array = [["При себе", 0, Net.BASE_SLOTS], ["Карманы комбинезона", Net.BASE_SLOTS, Net.POCKETS],
	["Рюкзак", Net.BASE_SLOTS + Net.POCKETS, Net.PACK_SLOTS]]

var client: GameClient
var _canvas: Control
var _about: Label
var _shown := PackedByteArray()
var _drag := -1                       # (v73, the author's H2 note) the slot whose thing is being dragged
var _act: Button
var _drop: Button
var _supply: Button
var _inflate: Button                  # (v98)


func setup(p_client: GameClient) -> void:
	client = p_client
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	style.border_color = Color(0.7, 0.6, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Инвентарь"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var shut := Button.new()
	shut.text = "Закрыть"
	shut.focus_mode = Control.FOCUS_NONE
	shut.pressed.connect(func() -> void: visible = false)
	head.add_child(shut)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(Net.SLOTS * (CELL + GAP) + 3 * 18.0 + 60.0, ROW_H * 2 + 6)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_input)
	box.add_child(_canvas)
	_about = Label.new()
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(_canvas.custom_minimum_size.x, 66)
	_about.add_theme_font_size_override("font_size", 14)
	box.add_child(_about)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_act = _button(row, func() -> void: client.send_act())
	_drop = _button(row, func() -> void: client.send_drop())
	_supply = _button(row, func() -> void: client.send_suit(not client.supply))
	_inflate = _button(row, func() -> void: client.send_inflate())
	var tip := Label.new()
	tip.add_theme_font_size_override("font_size", 12)
	tip.modulate = Color(1, 1, 1, 0.6)
	tip.text = "Щелчок по вещи: взять в руку. Перетащить: в другой слот. Правый щелчок: положить на пол. Щелчок по одежде: снять (в руку, если она пуста)."
	box.add_child(tip)


func _button(row: HBoxContainer, action: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	row.add_child(b)
	return b


func toggle() -> void:
	visible = not visible
	_shown = PackedByteArray()


func _worn_cell(k: int) -> Rect2:
	return Rect2(Vector2(k * (CELL + GAP + 40.0), 22.0), Vector2(CELL, CELL))


func _group_x(k: int) -> float:
	## Where a group of slots starts: each is as wide as its cells or its caption.
	var x := 0.0
	for j in k:
		x += _group_width(j) + 18.0
	return x


func _group_width(k: int) -> float:
	var cells: float = int(GROUPS[k][2]) * (CELL + GAP) - GAP
	return maxf(cells, ThemeDB.fallback_font.get_string_size(_caption(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)


func _caption(k: int) -> String:
	var first: int = GROUPS[k][1]
	if client.usable(first):
		return GROUPS[k][0]
	return "%s (нужен %s)" % [GROUPS[k][0], "комбинезон" if first == Net.BASE_SLOTS else "рюкзак"]


func _slot_cell(i: int) -> Rect2:
	for k in GROUPS.size():
		var first: int = GROUPS[k][1]
		if i >= first and i < first + int(GROUPS[k][2]):
			return Rect2(Vector2(_group_x(k) + (i - first) * (CELL + GAP), ROW_H + 28.0), Vector2(CELL, CELL))
	return Rect2()


func _draw_canvas() -> void:
	var font := ThemeDB.fallback_font
	var ink := Color(0.85, 0.88, 0.95)
	var dim := Color(0.6, 0.62, 0.7)
	_canvas.draw_string(font, Vector2(0, 14), "Надето", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)
	for k in Net.WORN:
		var cell := _worn_cell(k)
		var thing := client.worn[k] if k < client.worn.size() else Net.ITEM_NONE
		_canvas.draw_rect(cell, Color(0.1, 0.09, 0.07, 0.95))
		_canvas.draw_rect(cell, Color(0.7, 0.6, 0.4, 0.9), false, 1.0)
		if thing != Net.ITEM_NONE:
			ItemArt.draw(_canvas, cell, Items.suit_with(float(client.tank) / Net.TANK_FULL) if k == Net.WEAR_SUIT else thing)   # (v80) its real tank
		var label := WORN_NAMES[k]
		if k == Net.WEAR_SUIT and thing != Net.ITEM_NONE:
			label += " %d%%%s" % [client.tank * 100 / Net.TANK_FULL, ", сдут" if client.deflated else ""]
		elif k == Net.WEAR_BELT and thing != Net.ITEM_NONE:
			label += " %d" % client.eshield
		_canvas.draw_string(font, cell.position + Vector2(-20, CELL + 13), label if thing != Net.ITEM_NONE else "нет",
			HORIZONTAL_ALIGNMENT_CENTER, CELL + 40, 11, ink if thing != Net.ITEM_NONE else dim)
	for k in GROUPS.size():
		_canvas.draw_string(font, Vector2(_group_x(k), ROW_H + 20.0), _caption(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)
	for i in Net.SLOTS:
		var cell := _slot_cell(i)
		if not client.usable(i):
			_canvas.draw_rect(cell, Color(0.05, 0.05, 0.07, 0.4))
			continue
		var held := i == client.hand
		_canvas.draw_rect(cell, Color(0.14, 0.15, 0.1, 0.95) if held else Color(0.07, 0.08, 0.12, 0.92))
		if held:
			_canvas.draw_rect(cell.grow(1.0), Color(0.98, 0.82, 0.35), false, 2.0)
		else:
			_canvas.draw_rect(cell, Color(0.42, 0.46, 0.56, 0.9), false, 1.0)
		if i == _drag:
			_canvas.draw_rect(cell.grow(-2.0), Color(0.45, 0.75, 1.0, 0.9), false, 2.0)
		if i < Net.BASE_SLOTS:
			_canvas.draw_string(font, cell.position + Vector2(3, 11), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
		var thing := client.slots[i]
		if thing != Net.ITEM_NONE:
			ItemArt.draw(_canvas, cell, thing)
			_canvas.draw_string(font, cell.position + Vector2(-4, CELL + 13), Items.name_of(thing),
				HORIZONTAL_ALIGNMENT_CENTER, CELL + 8, 10, ink)


func _on_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed:
		# (v73) a thing dragged onto another slot trades places with what is there
		if click.button_index == MOUSE_BUTTON_LEFT and _drag >= 0:
			for i in Net.SLOTS:
				if i != _drag and _slot_cell(i).has_point(click.position) and client.usable(i):
					client.send_swap(_drag, i)
			_drag = -1
			_canvas.queue_redraw()
		return
	for k in Net.WORN:
		if _worn_cell(k).has_point(click.position) and click.button_index == MOUSE_BUTTON_LEFT:
			client.send_wear(k)
			_canvas.accept_event()
			return
	for i in Net.SLOTS:
		if _slot_cell(i).has_point(click.position) and client.usable(i):
			client.send_hand(i)
			if click.button_index == MOUSE_BUTTON_LEFT and client.slots[i] != Net.ITEM_NONE:
				_drag = i
				_canvas.queue_redraw()
			if click.button_index == MOUSE_BUTTON_RIGHT and client.slots[i] != Net.ITEM_NONE:
				client.send_drop()
			_canvas.accept_event()
			return


func _process(_delta: float) -> void:
	if not visible:
		return
	if client.my_cond != Net.COND_OK:
		visible = false
		return
	var now := client.slots + client.worn + PackedByteArray([client.hand, client.tank, 1 if client.supply else 0, 1 if client.deflated else 0, client.eshield])
	if _canvas.custom_minimum_size.x < _group_x(GROUPS.size() - 1) + _group_width(GROUPS.size() - 1):
		_canvas.custom_minimum_size.x = _group_x(GROUPS.size() - 1) + _group_width(GROUPS.size() - 1)
	if now == _shown:
		return
	_shown = now
	_canvas.queue_redraw()
	var item := client.in_hand()
	var free := 0
	var open := 0
	for i in Net.SLOTS:
		if client.usable(i):
			open += 1
			if client.slots[i] == Net.ITEM_NONE:
				free += 1
	var lines := PackedStringArray()
	if item == Net.ITEM_NONE:
		lines.append("В руке ничего (слот %d)." % (client.hand + 1))
	else:
		var what := Items.name_of(item)
		if Items.rounds(item) >= 0:
			what += ", %s %d из %d" % ["зарядов" if Items.energy(item) >= 0 else "патронов", Items.rounds(item), Items.full_rounds(item)]
		elif Items.uses(item) >= 0:
			what += ", применений %d из %d" % [Items.uses(item), Net.MEDKIT_USES]
		elif Items.tank_of(item) >= 0:
			what += ", кислорода %d%%" % (Items.tank_of(item) * 100 / Net.SUIT_TANK_STEPS)
		lines.append("В руке: %s. %s" % [what, Options.keyed(Items.about(item))])
	lines.append("Свободно слотов: %d из %d." % [free, open])
	if client.has_suit():
		lines.append("Подача кислорода из баллона %s." % ("включена" if client.supply else "выключена"))
	_about.text = "\n".join(lines)
	var switch := Items.switched(item)
	_act.visible = switch != Net.ITEM_NONE or Items.worn_as(item) >= 0
	_act.text = "%s (%s)" % ["Надеть" if Items.worn_as(item) >= 0 else ("Выключить" if not Items.light(item).is_empty() else "Включить"),
		Options.key_text("act")]
	_drop.visible = item != Net.ITEM_NONE
	_drop.text = "Положить на пол (%s)" % Options.key_text("drop")
	_supply.visible = client.has_suit()
	_supply.text = "%s подачу кислорода (%s)" % ["Выключить" if client.supply else "Включить", Options.key_text("suit")]
	_inflate.visible = client.has_suit()
	_inflate.text = "%s скафандр (%s)" % ["Надуть" if client.deflated else "Сдуть", Options.key_text("inflate")]
