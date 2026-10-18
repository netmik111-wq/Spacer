extends VBoxContainer
## (v58) The workbench's screen: every ship's gun in the locker, with what an
## engineer can do to it here (take it apart into parts of its kind, mend it,
## upgrade it into the next gun of its line), and the parts the locker holds.
## The server does the work (see Workshop); the progress is shown like any
## other work. Shown inside the console frame of GameScreen.
## (v60) And ammunition: a spare part makes 3 shells, 2 rockets or 1 EMP rocket.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const WARN := Color(0.95, 0.75, 0.3)

var client: GameClient
var _top: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _work: Label
var _shown := ""                     # what the rows were made for
var working := false                 # the work is going (the server says so through our progress)


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(700, 0)
	_top = _label(14, INK)
	add_child(_top)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(700, 300)
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows)
	_work = _label(14, WARN)
	add_child(_work)


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func closed() -> void:
	if client.work > 0:
		client.send_bench(Net.BENCH_STOP, 0)


func refresh() -> void:
	var engineer := client.job == Net.JOB_ENGINEER
	var parts := PackedStringArray()
	for k in Weapons.KINDS:
		parts.append("%s %d" % [Weapons.KIND_NAMES[k], int(client.store.get(Items.gun_parts(k), 0))])
	_top.text = ("Детали орудий в шкафу снабжения: %s. Запчастей: %d." % [", ".join(parts), int(client.store.get(Net.ITEM_PART, 0))]) + \
		("" if engineer else "\nЗа верстаком работают только инженеры.")
	working = client.work > 0
	_work.text = "Идёт работа: %d%%" % client.work if client.work > 0 else ""
	var guns := PackedInt32Array()
	for item: int in client.store.keys():
		if Weapons.of_item(item) != Weapons.NONE and int(client.store[item]) > 0:
			guns.append(item)
	guns.sort()
	var key := "%s|%s|%s|%s" % [guns, client.store, engineer, working]
	if key == _shown:
		return
	_shown = key
	for c in _rows.get_children():
		c.queue_free()
	var ammo := HBoxContainer.new()
	ammo.add_theme_constant_override("separation", 8)
	var what := _label(14, INK)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.text = "Боеприпасы из запчасти: снарядов %d, ракет %d, ЭМИ-ракет %d" % [int(client.store.get(Net.ITEM_SHELL, 0)),
		int(client.store.get(Net.ITEM_ROCKET, 0)), int(client.store.get(Net.ITEM_EMP_ROCKET, 0))]
	ammo.add_child(what)
	var spare := int(client.store.get(Net.ITEM_PART, 0)) > 0
	_button(ammo, "3 снаряда", Net.BENCH_SHELLS, 0, engineer and spare)
	_button(ammo, "2 ракеты", Net.BENCH_ROCKETS, 0, engineer and spare)
	_button(ammo, "1 ЭМИ-ракета", Net.BENCH_EMP, 0, engineer and spare)
	_rows.add_child(ammo)
	if guns.is_empty():
		_rows.add_child(_label(14, DIM))
		(_rows.get_child(-1) as Label).text = "В шкафу снабжения нет корабельных орудий. Снятые с пульта орудия и добыча попадают туда."
		return
	for item in guns:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name := _label(14, INK)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text = "%s × %d" % [Items.name_of(item), int(client.store[item])]
		name.tooltip_text = Items.about(item)
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name)
		var n := Weapons.parts_from(item)
		if n > 0:
			_button(row, "Разобрать (+%d)" % n, Net.BENCH_APART, item, engineer)
		if Weapons.damaged(item):
			_button(row, "Починить (1 запчасть)", Net.BENCH_MEND, item, engineer and int(client.store.get(Net.ITEM_PART, 0)) > 0)
		var need := Weapons.upgrade_cost(item)
		if need > 0:
			var have := int(client.store.get(Items.gun_parts(Weapons.kind(Weapons.of_item(item))), 0))
			_button(row, "Улучшить (%d/%d дет.)" % [mini(have, need), need], Net.BENCH_UPGRADE, item, engineer and have >= need)
		_rows.add_child(row)


func _button(row: HBoxContainer, text: String, action: int, item: int, on: bool) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not on or working
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		client.send_bench(action, item))
	row.add_child(b)
