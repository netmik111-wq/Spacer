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

const COUNTS: Array[int] = [1, 2, 5, 10]

var client: GameClient
var _count := 1
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
	var page := _page("Вещи")
	_note(page, "Щелчок по вещи: она появится у вас в руке или в свободном слоте, а если места нет, то на полу под ногами.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	var caption := Label.new()
	caption.text = "Сколько штук:"
	row.add_child(caption)
	var count := OptionButton.new()
	count.focus_mode = Control.FOCUS_NONE
	for n in COUNTS:
		count.add_item(str(n))
	count.item_selected.connect(func(i: int) -> void: _count = COUNTS[i])
	row.add_child(count)
	var grid := _grid(page, 3)
	for item in Items.spawnable():
		var b := _button("        " + Items.name_of(item), func() -> void:
			for i in _count:
				_send(Net.ADMIN_GIVE, item))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(170, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = Items.about(item)
		var thing := item
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(4, 4)
		icon.size = Vector2(32, 32)
		icon.draw.connect(func() -> void: ItemArt.draw(icon, Rect2(Vector2.ZERO, Vector2(32, 32)), thing))
		b.add_child(icon)
		grid.add_child(b)
	return page.get_parent()


# --------------------------------------------------------------- people

func _people_tab() -> Control:
	var page := _page("Люди")
	_note(page, "«Вылечить» возвращает здоровье, закрывает раны, заправляет баллон и поднимает даже погибших (тела, оставленные после возвращения из резерва, не оживают).")
	page.add_child(_button("Вылечить всех", func() -> void:
		for id: int in client.roster:
			if int(client.roster[id]["kind"]) != Net.KIND_CORPSE and int(client.roster[id]["kind"]) != Net.KIND_PIRATE:
				_send(Net.ADMIN_HEAL, 0, id)))
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
	]:
		var command: int = b[1]
		var button := _button(b[0], func() -> void: _send(command))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
	return page.get_parent()


# --------------------------------------------------------------- space and events

func _space_tab() -> Control:
	var page := _page("Космос и события")
	_note(page, "Корабль ставится прямо у станции, торговца или брошенного корабля в этом секторе (до следующего прыжка).")
	var grid := _grid(page, 2)
	for b: Array in [["Станция здесь", Sectors.STATION], ["Торговец здесь", Sectors.TRADER], ["Брошенный корабль здесь", Sectors.DERELICT]]:
		var kind: int = b[1]
		var button := _button(b[0], func() -> void: _send(Net.ADMIN_PLACE, kind))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
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
