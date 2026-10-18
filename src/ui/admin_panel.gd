extends PanelContainer
## The admin panel, for the host and the players the host made admins: tabs to
## give oneself any thing, to heal, kill and move people, to mend and supply
## the ship, and to call events and visitors. Every button is a command to the
## server (Net.ADMIN_*), which checks the right to it.
## It does not hold the keyboard: the character can walk while it is open.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Director := preload("res://src/server/director.gd")   # only for the list of events
const Weapons := preload("res://src/shared/weapons.gd")
const Gear := preload("res://src/shared/gear.gd")
const Hulls := preload("res://src/shared/hulls.gd")

const COUNTS: Array[int] = [1, 2, 5, 10]

var client: GameClient
var _count := 1
var _to_locker := false              # (v60.1) things go into the supply locker, not the hands
var _fx := Weapons.FX_NONE           # (v60.1) the effect a tier 3 gun is given with
var _damaged := false                # (v60.1) guns are given damaged
var _klass := Net.ECLASS_RAIDER      # (v60.1) the pirate ship called up
var _temper := Net.ADMIN_ANY_TEMPER
var _gear_pickers: Array = []        # (v60.1) per Gear.SYS_*: its picker on the ship tab, kept to the ship's tiers
var _people: VBoxContainer
var _people_for := ""                # what the list of people was built from
var _auto: CheckBox
var _tabs: TabContainer


func setup(p_client: GameClient) -> void:
	client = p_client
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_right = -14
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.07, 0.95)
	style.border_color = Color(0.8, 0.45, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Панель администратора"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("Закрыть", func() -> void: visible = false))
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.custom_minimum_size = Vector2(540, 520)
	tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)
	tabs.add_child(_things_tab())
	tabs.add_child(_people_tab())
	tabs.add_child(_ship_tab())
	tabs.add_child(_space_tab())
	client.roster_changed.connect(func() -> void: _people_for = "")


func toggle() -> void:
	visible = not visible and client.is_admin


func show_tab(i: int) -> void:
	_tabs.current_tab = clampi(i, 0, _tabs.get_tab_count() - 1)


func _process(_delta: float) -> void:
	if visible and not client.is_admin:
		visible = false
	if visible and _people_for != _people_key():
		_fill_people()
	if visible:
		for sys in _gear_pickers.size():
			var picker: OptionButton = _gear_pickers[sys]
			var shown := clampi(client.gear_tiers[sys] - 1, 0, picker.item_count - 1) if client.gear_tiers.size() > sys else 0
			if picker.selected != shown and not picker.get_popup().visible:
				picker.select(shown)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE        # keys stay with the game
	for state: String in ["normal", "hover", "pressed"]:
		var look := StyleBoxFlat.new()
		look.bg_color = {"normal": Color(0.2, 0.14, 0.13), "hover": Color(0.32, 0.2, 0.16), "pressed": Color(0.45, 0.27, 0.18)}[state]
		look.border_color = Color(0.55, 0.36, 0.28)
		look.set_border_width_all(1)
		look.set_corner_radius_all(3)
		look.set_content_margin_all(5)
		b.add_theme_stylebox_override(state, look)
	b.pressed.connect(action)
	return b


func _page(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	return page


func _note(page: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.7)
	page.add_child(label)


func _grid(page: Control, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	return grid


func _send(command: int, argument: int = 0, target: int = 0) -> void:
	client.send_admin(command, argument, target)


# --------------------------------------------------------------- things

func _things_tab() -> Control:
	## (v60.1) Built from the game's own lists (Items.admin_sections), so new things show up by themselves.
	var page := _page("Вещи")
	_note(page, "Щелчок по вещи: она появится у вас в руке или в свободном слоте, а если места нет, то на полу под ногами. "
		+ "Трюмные вещи (боеприпасы, зонды, дроны, детали) всегда идут в шкаф снабжения. Уровень вещи виден только здесь.")
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 4)
	page.add_child(row)
	row.add_child(_caption("Сколько штук:"))
	row.add_child(_picker(COUNTS.map(func(n: int) -> String: return str(n)), 0, func(i: int) -> void: _count = COUNTS[i]))
	row.add_child(_caption("Куда:"))
	row.add_child(_picker(["в руки", "в шкаф снабжения"], 0, func(i: int) -> void: _to_locker = i == 1))
	var guns := HFlowContainer.new()
	guns.add_theme_constant_override("h_separation", 8)
	guns.add_theme_constant_override("v_separation", 4)
	page.add_child(guns)
	guns.add_child(_caption("Орудия 3-го уровня с эффектом:"))
	var fx_names: Array = ["без эффекта"]
	for f in range(1, Weapons.FX_COUNT + 1):
		fx_names.append(Weapons.FX_NAMES[f])
	guns.add_child(_picker(fx_names, 0, func(i: int) -> void: _fx = i))
	var broken := CheckBox.new()
	broken.text = "повреждённые орудия"
	broken.focus_mode = Control.FOCUS_NONE
	broken.toggled.connect(func(on: bool) -> void: _damaged = on)
	guns.add_child(broken)
	for section: Array in Items.admin_sections():
		var head := Label.new()
		head.text = section[0]
		head.add_theme_font_size_override("font_size", 15)
		head.modulate = Color(1.0, 0.8, 0.6)
		page.add_child(head)
		var grid := _grid(page, 3)
		for item: int in section[1]:
			grid.add_child(_thing_button(item))
	return page.get_parent()


func _thing_button(item: int) -> Button:
	var w := Weapons.of_item(item)
	var g := Items.gear_of(item)
	var label := Items.name_of(item)
	if w != Weapons.NONE:
		label += " · ур. %d" % Weapons.tier(w)
	elif g != Gear.NONE:
		label += " · ур. %d" % Gear.tier(g)
	var b := _button("        " + label, func() -> void:
		var thing := item
		if w != Weapons.NONE:
			thing = Weapons.item_of(w, _fx if Weapons.FX_GUNS.has(w) else Weapons.FX_NONE, _damaged)
		for i in _count:
			_send(Net.ADMIN_STORE if _to_locker else Net.ADMIN_GIVE, thing))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(170, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.tooltip_text = Items.name_of(item) + "\n" + Items.about(item)
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(4, 4)
	icon.size = Vector2(32, 32)
	icon.draw.connect(func() -> void: ItemArt.draw(icon, Rect2(Vector2.ZERO, Vector2(32, 32)), item))
	b.add_child(icon)
	return b


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _picker(names: Array, chosen: int, picked: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for n: String in names:
		o.add_item(n)
	o.select(chosen)
	o.item_selected.connect(picked)
	return o


# --------------------------------------------------------------- people

func _people_tab() -> Control:
	var page := _page("Люди")
	_note(page, "«Вылечить» возвращает здоровье, закрывает раны, заправляет баллон и поднимает даже погибших (тела, оставленные после возвращения из резерва, не оживают).")
	page.add_child(_button("Вылечить всех", func() -> void:
		for id: int in client.roster:
			if int(client.roster[id]["kind"]) != Net.KIND_CORPSE and int(client.roster[id]["kind"]) != Net.KIND_PIRATE:
				_send(Net.ADMIN_HEAL, 0, id)))
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 6)
	page.add_child(bots)
	bots.add_child(_button("+1 бот в экипаж", func() -> void: _send(Net.ADMIN_BOTS, 1)))
	bots.add_child(_button("−1 бот", func() -> void: _send(Net.ADMIN_BOTS, 0)))
	_people = VBoxContainer.new()
	_people.add_theme_constant_override("separation", 10)
	page.add_child(_people)
	return page.get_parent()


func _people_key() -> String:
	return "%d,%s,%s" % [client.roster.size(), client.is_host, str(client.roster.keys())]


func _fill_people() -> void:
	_people_for = _people_key()
	for old in _people.get_children():
		old.queue_free()
	var ids: Array = client.roster.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = client.roster[id]
		var kind := int(entry["kind"])
		if kind == Net.KIND_CORPSE:
			continue
		var card := VBoxContainer.new()
		_people.add_child(card)
		var who := Label.new()
		var what := "пират" if kind == Net.KIND_PIRATE else ("бот, " if kind == Net.KIND_BOT else "") + Net.JOB_NAMES[int(entry["job"])].to_lower()
		who.text = "%s (%s)%s" % [entry["name"], what, "  — это вы" if id == client.my_id else ""]
		card.add_child(who)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 4)
		card.add_child(row)
		var target: int = id
		row.add_child(_button("Вылечить", func() -> void: _send(Net.ADMIN_HEAL, 0, target)))
		row.add_child(_button("Убить", func() -> void: _send(Net.ADMIN_KILL, 0, target)))
		if kind != Net.KIND_PIRATE:
			row.add_child(_button("Навыки на максимум", func() -> void: _send(Net.ADMIN_SKILLS, 0, target)))
		if id != client.my_id:
			row.add_child(_button("К нему", func() -> void: _send(Net.ADMIN_GOTO, 0, target)))
			row.add_child(_button("Ко мне", func() -> void: _send(Net.ADMIN_BRING, 0, target)))
		if kind != Net.KIND_PIRATE:
			var job := OptionButton.new()
			job.focus_mode = Control.FOCUS_NONE
			for j in Net.JOBS:
				job.add_item(Net.JOB_NAMES[j], j)
			job.select(int(entry["job"]))
			job.tooltip_text = "Сменить профессию (и доступ)"
			job.item_selected.connect(func(j: int) -> void: _send(Net.ADMIN_JOB, j, target))
			row.add_child(job)
		if client.is_host and kind == Net.KIND_PLAYER and id != client.my_id:
			row.add_child(_button("Сделать админом", func() -> void: _send(Net.ADMIN_GRANT, 1, target)))
			row.add_child(_button("Снять админа", func() -> void: _send(Net.ADMIN_GRANT, 0, target)))


# --------------------------------------------------------------- the ship

func _ship_tab() -> Control:
	var page := _page("Корабль")
	var grid := _grid(page, 2)
	for b: Array in [
		["Починить всё (пробоины, машины, двери)", Net.ADMIN_REPAIR],
		["Заделать все пробоины", Net.ADMIN_SEAL],
		["Пробить обшивку рядом со мной", Net.ADMIN_BREACH],
		["Воздух во всём корабле", Net.ADMIN_AIR],
		["Пополнить шкаф снабжения", Net.ADMIN_RESTOCK],
		["+%d кредитов" % Net.ADMIN_CREDITS_GIVEN, Net.ADMIN_CREDITS],
		["Обшивка как новая", Net.ADMIN_HULL],
		["+1 человек в резерв", Net.ADMIN_RESERVE],
		["Сохранить кампанию", Net.ADMIN_SAVE],
		["Зарядить всё (щит, орудия, прыжок, фазовый привод)", Net.ADMIN_CHARGE],
		["СМЭС: полный заряд", Net.ADMIN_SMES, 10],
		["СМЭС: пустой", Net.ADMIN_SMES, 0],
		["Ионный разряд сейчас", Net.ADMIN_SURGE],
	]:
		var command: int = b[1]
		var argument: int = b[2] if b.size() > 2 else 0
		var button := _button(b[0], func() -> void: _send(command, argument))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
	# (v60.1) the ship's gear at once, built from Gear's own list
	var head := Label.new()
	head.text = "Снаряжение корабля сразу (без работы инженера)"
	head.add_theme_font_size_override("font_size", 15)
	head.modulate = Color(1.0, 0.8, 0.6)
	page.add_child(head)
	var gear := _grid(page, 2)
	for sys in Gear.SYSTEMS:
		gear.add_child(_caption(Gear.SYS_NAMES[sys] + ":"))
		var names: Array = ["ур. 1: " + Gear.SYS_BUILT_IN[sys]]
		var fits: Array = [Net.ADMIN_FIT_BUILT_IN + sys]
		for t in range(2, 4):
			var g := Gear.for_system(sys, t)
			if g != Gear.NONE:
				names.append("ур. %d: %s" % [t, Gear.name_of(g)])
				fits.append(g)
		var picker := _picker(names, 0, func(i: int) -> void: _send(Net.ADMIN_FIT, fits[i]))
		_gear_pickers.append(picker)
		gear.add_child(picker)
	_note(page, "Модульная стойка (в ней %d ячейки, по одному модулю каждого вида):" % Gear.MODULE_SLOTS)
	var bay := _grid(page, 2)
	for g: int in Gear.all():
		if Gear.system_of(g) >= 0:
			continue
		var button := _button("В стойку: %s · ур. %d" % [Gear.name_of(g), Gear.tier(g)], func() -> void: _send(Net.ADMIN_FIT, g))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = Gear.about(g)
		bay.add_child(button)
	var clear := _button("Очистить стойку", func() -> void: _send(Net.ADMIN_FIT, Net.ADMIN_FIT_CLEAR_BAY))
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bay.add_child(clear)
	return page.get_parent()


# --------------------------------------------------------------- space and events

func _space_tab() -> Control:
	var page := _page("Космос и события")
	_note(page, "Корабль ставится прямо у станции, торговца или брошенного корабля в этом секторе (до следующего прыжка).")
	var grid := _grid(page, 2)
	var places: Array = [["Станция здесь", Sectors.STATION], ["Брошенный корабль здесь", Sectors.DERELICT],
		["Метеорный поток здесь", Sectors.METEORS], ["Ионный шторм здесь", Sectors.ION_STORM]]
	for d in Sectors.DEAL_NAMES.size():
		places.append(["Торговец здесь: " + Sectors.DEAL_NAMES[d], Sectors.TRADER + Net.ADMIN_TRADER_DEAL * (d + 1)])
	for b: Array in places:
		var kind: int = b[1]
		var button := _button(b[0], func() -> void: _send(Net.ADMIN_PLACE, kind))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
	# (v60.1) a pirate ship of the class and temper chosen, built from Hulls' own lists
	_note(page, "Пиратский корабль на выбор (флагманы вызываются событиями ниже):")
	var classes: Array = []
	var class_names: Array = []
	for k: int in Hulls.CLASSES.keys():
		if not Hulls.CLASSES[k].has("boss"):
			classes.append(k)
			class_names.append(str(Hulls.CLASSES[k]["name"]))
	var tempers: Array = [Net.ADMIN_ANY_TEMPER]
	var temper_names: Array = ["нрав: любой"]
	for t: int in Hulls.TEMPERS.keys():
		if not Hulls.TEMPERS[t].has("boss") and not Hulls.TEMPERS[t].has("machine"):
			tempers.append(t)
			temper_names.append("нрав: " + str(Hulls.TEMPERS[t]["name"]))
	var pick := HFlowContainer.new()
	pick.add_theme_constant_override("h_separation", 6)
	pick.add_theme_constant_override("v_separation", 4)
	page.add_child(pick)
	_klass = classes[maxi(classes.find(_klass), 0)]
	pick.add_child(_picker(class_names, classes.find(_klass), func(i: int) -> void: _klass = classes[i]))
	pick.add_child(_picker(temper_names, 0, func(i: int) -> void: _temper = tempers[i]))
	pick.add_child(_button("Бой на дистанции", func() -> void: _send(Net.ADMIN_FIGHT, _klass * 16 + _temper * 2 + 1)))
	pick.add_child(_button("Идёт на абордаж", func() -> void: _send(Net.ADMIN_FIGHT, _klass * 16 + _temper * 2)))
	grid.add_child(_button("Пират с пистолетом передо мной", func() -> void: _send(Net.ADMIN_PIRATE, 1)))
	grid.add_child(_button("Пират с дубинкой передо мной", func() -> void: _send(Net.ADMIN_PIRATE, 0)))
	_auto = CheckBox.new()
	_auto.text = "Ивентер ведёт события сам"
	_auto.button_pressed = true
	_auto.focus_mode = Control.FOCUS_NONE
	_auto.toggled.connect(func(on: bool) -> void: _send(Net.ADMIN_AUTO, 1 if on else 0))
	page.add_child(_auto)
	var events := _grid(page, 2)
	for e: Dictionary in Director.EVENTS:
		var id := int(e["id"])
		var button := _button("%s (%s)" % [e["name"], Director.SIZE_NAMES[int(e["size"])]], func() -> void: _send(Net.ADMIN_EVENT, id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		events.add_child(button)
	return page.get_parent()
