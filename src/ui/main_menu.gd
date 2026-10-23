extends Control
## The first screen: pick a name, then create a game or join one.

signal host_requested(player_name: String, port: int, bots: int, campaign: String, mode: String, ship: String, own: bool)
signal join_requested(player_name: String, address: String, port: int)
signal quit_requested
signal editor_requested               # (v81) the ship editor

const Net := preload("res://src/shared/net.gd")
const SETTINGS := "user://settings.cfg"
const Campaign := preload("res://src/server/campaign.gd")
const OptionsPanel := preload("res://src/ui/options_panel.gd")
const BugReport := preload("res://src/client/bug_report.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const ShipPreview := preload("res://src/ui/ship_preview.gd")
const Drawing := preload("res://src/ui/editor/drawing.gd")
const Checks := preload("res://src/ui/editor/checks.gd")
const STANDARD_SHIP := "ship02"

var _name: LineEdit
var _address: LineEdit
var _bots: SpinBox
var _mode: OptionButton               # (v63) a new campaign's mode
var _complex: CheckBox               # (v71) complex repairs in a new campaign
var _job: OptionButton
var _job_about: Label
var _status: Label
var _new_armed := false              # "new campaign" was pressed once while a saved one exists
var _buttons: Array[Button] = []
var _options: OptionsPanel
var _ship: OptionButton               # (v84, the author's H2) the ship a new campaign is played on
var _ship_names: Array[String] = []   # per item of _ship: the map name (ship02 or ships:NAME)
var _ship_errors: Array[String] = []  # per item: what keeps it from being played ("" = nothing)
var _preview: ShipPreview
var _ship_note: Label
var _own: CheckBox                    # (v84, the author's H5) one's own other drawings come in the run
var _saved_ship := STANDARD_SHIP


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.043, 0.047, 0.078)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.14)
	style.border_color = Color(0.36, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Космический прототип"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Экипаж и кампания"
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_gap(8))
	# (v84) two columns, so the menu fits a 720-row window: who one is and joining on the left, a campaign of
	# one's own (with its ship) on the right
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(_caption("Своя игра: вы — хозяин, друзья подключаются к вам"))

	left.add_child(_caption("Имя"))
	_name = LineEdit.new()
	_name.max_length = Net.MAX_NAME
	_name.placeholder_text = "Как вас зовут на борту"
	left.add_child(_name)
	left.add_child(_caption("Профессия"))
	_job = OptionButton.new()
	for j in range(Net.JOB_CAPTAIN, Net.JOBS):
		_job.add_item(Net.JOB_NAMES[j], j)   # (v70, the author's J1: no sailor any more)
	_job.item_selected.connect(func(_i: int) -> void: _show_job())
	_job.select(0)                       # the captain: whoever starts a ship alone needs its bridge
	left.add_child(_job)
	_job_about = Label.new()
	_job_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_about.custom_minimum_size = Vector2(440, 0)
	_job_about.add_theme_font_size_override("font_size", 13)
	_job_about.modulate = Color(1, 1, 1, 0.6)
	left.add_child(_job_about)
	left.add_child(_gap(6))

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	right.add_child(host_row)
	var host := _button("Новая кампания")
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_on_host)
	host_row.add_child(host)
	var bots_caption := Label.new()
	bots_caption.text = "Ботов:"
	host_row.add_child(bots_caption)
	_bots = SpinBox.new()
	_bots.min_value = 0
	_bots.max_value = 8
	_bots.value = 2
	_bots.tooltip_text = "Боты — члены экипажа: бродят по кораблю, пока капитан не отдаст им приказ (окно «Экипаж», клавиша O)"
	host_row.add_child(_bots)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	right.add_child(mode_row)
	var mode_caption := Label.new()
	mode_caption.text = "Режим новой кампании:"
	mode_row.add_child(mode_caption)
	_mode = OptionButton.new()
	for n in Net.MODE_NAMES:
		_mode.add_item(n)
	_mode.select(Net.MODE_NORMAL)
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode.tooltip_text = "Лёгкий: разбитая обшивка не губит корабль, а только снижает её наибольшую прочность (на 50).\nОбычный: как задумано.\nТяжёлый: пираты злее и платят меньше, на абордаж идёт на одного больше, флагман растёт быстрее."
	mode_row.add_child(_mode)
	# (v71, the author's H1: "optional, chosen at the start of the game") complex repairs
	_complex = CheckBox.new()
	_complex.text = "Сложный ремонт"
	_complex.tooltip_text = "Для починки машин и дверей нужен ящик с инструментами, а каждой машине — своя запчасть:\nпультам и экранам плата, остальному механическая запчасть. Без них чинить втрое дольше.\nВ тяжёлом режиме включён сам."
	mode_row.add_child(_complex)
	_mode.item_selected.connect(func(i: int) -> void: _complex.button_pressed = i == Net.MODE_HARD)
	# (v84) the ship of a new campaign: the game's own, or one drawn in the ship editor
	var ship_row := HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 10)
	right.add_child(ship_row)
	var ship_caption := Label.new()
	ship_caption.text = "Корабль:"
	ship_row.add_child(ship_caption)
	_ship = OptionButton.new()
	_ship.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship.tooltip_text = "Свои корабли рисуют в «Редакторе кораблей» (папка ships рядом с игрой).\nДрузьям ничего копировать не нужно: игра пришлёт им чертёж при подключении."
	_ship.item_selected.connect(func(_i: int) -> void: _show_ship())
	ship_row.add_child(_ship)
	_preview = ShipPreview.new()
	right.add_child(_preview)
	_ship_note = Label.new()
	_ship_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ship_note.custom_minimum_size = Vector2(440, 0)
	_ship_note.add_theme_font_size_override("font_size", 13)
	right.add_child(_ship_note)
	_own = CheckBox.new()
	_own.text = "Мои пираты, обломки и астероиды встречаются в пути"
	right.add_child(_own)
	var saved := Campaign.summary()
	if saved != "":
		var go_on := _button("Продолжить кампанию")
		go_on.pressed.connect(_on_continue)
		right.add_child(go_on)
		var about := _caption("Сохранено: " + saved)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.custom_minimum_size = Vector2(440, 0)
		right.add_child(about)
	right.add_child(_gap(6))

	left.add_child(_caption("Адрес сервера (для подключения к чужой игре)"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	left.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "127.0.0.1"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	join_row.add_child(_address)
	var join := _button("Подключиться")
	join.pressed.connect(_on_join)
	join_row.add_child(join)
	left.add_child(_gap(6))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 44)
	_status.add_theme_font_size_override("font_size", 14)
	left.add_child(_status)

	var editor := Button.new()
	editor.text = "Редактор кораблей"
	editor.tooltip_text = "Рисовать свои корабли и астероиды и сразу пробовать их в игре"
	editor.custom_minimum_size = Vector2(0, 36)
	editor.pressed.connect(func() -> void: editor_requested.emit())
	left.add_child(editor)
	_buttons.append(editor)
	var settings := Button.new()
	settings.text = "Настройки: звук, изображение, клавиши"
	settings.custom_minimum_size = Vector2(0, 36)
	settings.pressed.connect(func() -> void: _options.open())
	left.add_child(settings)
	var report := Button.new()
	report.text = "Сообщить об ошибке (собрать журналы в архив)"
	report.custom_minimum_size = Vector2(0, 36)
	report.pressed.connect(_report)
	left.add_child(report)
	var quit := _button("Выход")
	quit.pressed.connect(func() -> void: quit_requested.emit())
	left.add_child(quit)
	_options = OptionsPanel.new()
	add_child(_options)

	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		_name.text = str(cfg.get_value("player", "name", ""))
		_address.text = str(cfg.get_value("player", "address", ""))
		_bots.value = int(cfg.get_value("player", "bots", 2))
		_mode.select(clampi(int(cfg.get_value("player", "mode", Net.MODE_NORMAL)), 0, Net.MODE_NAMES.size() - 1))
		_complex.button_pressed = bool(cfg.get_value("player", "complex", _mode.selected == Net.MODE_HARD))
		_job.select(clampi(int(cfg.get_value("player", "job", Net.JOB_CAPTAIN)) - Net.JOB_CAPTAIN, 0, Net.JOBS - 1 - Net.JOB_CAPTAIN))
		_saved_ship = str(cfg.get_value("player", "ship", STANDARD_SHIP))
		_own.button_pressed = bool(cfg.get_value("player", "own_others", false))
	_show_job()
	refresh_ships()
	_name.grab_focus()


func _report() -> void:
	## (v75, the author's S2) The logs and the save in one zip, shown in its folder.
	var path := BugReport.make(get_viewport().get_texture().get_image())
	if path == "":
		show_status("Не удалось записать архив в папку %s." % BugReport.folder(), true)
		return
	show_status("Архив готов: %s. Приложите его к заметке в блокноте." % path)
	OS.shell_show_in_file_manager(path)


func refresh_ships() -> void:
	## (v84) The ship list again (the ship editor may have saved a new drawing since): the game's own ship,
	## then every drawing of our own ship in the «ships» folder, with what would keep it from being played.
	var keep := _saved_ship if _ship_names.is_empty() else ship_name()
	_ship.clear()
	_ship_names = [STANDARD_SHIP]
	_ship_errors = [""]
	_ship.add_item("Стандартный корабль")
	var others := 0
	for d: Dictionary in ShipMap.own_drawings():
		if str(d["kind"]) != "ship":
			others += 1
			continue
		var error := _ship_error(str(d["file"]), str(d["text"]))
		_ship_names.append(str(d["name"]))
		_ship_errors.append(error)
		_ship.add_item(str(d["file"]) + ("  (не готов)" if error != "" else ""))
	_ship.select(maxi(_ship_names.find(keep), 0))
	var usable := ShipMap.coming_in_run().size()
	_own.disabled = usable == 0
	_own.tooltip_text = ("Своих рисунков пиратских кораблей, обломков и астероидов, годных для игры: %d из %d.\nОни встречаются в пути вместе с обычными (не подходящие по размеру к шлюзу корабля не встретятся)." % [usable, others]) \
		if usable > 0 else "В папке ships нет готовых рисунков пиратских кораблей, обломков или астероидов (их рисуют в «Редакторе кораблей»)."
	_show_ship()


static func _ship_error(file: String, text: String) -> String:
	## (v84, the author's H3) The first problem that keeps a drawing from being our ship, or "".
	var d := Drawing.new()
	d.from_text(text, file)
	for p: Dictionary in Checks.run(d):
		if bool(p["error"]):
			return str(p["text"])
	return ""


func _show_ship() -> void:
	var i := maxi(_ship.selected, 0)
	var name: String = _ship_names[i] if i < _ship_names.size() else STANDARD_SHIP
	if name.begins_with(ShipMap.USER_PREFIX):
		var text := FileAccess.get_file_as_string(ShipMap.ships_dir().path_join(name.trim_prefix(ShipMap.USER_PREFIX) + ".txt"))
		_preview.show_drawing(name, text)
	else:
		_preview.show_drawing(name, FileAccess.get_file_as_string("res://maps/%s.txt" % name))
	var error: String = _ship_errors[i] if i < _ship_errors.size() else ""
	if error != "":
		_ship_note.text = "На нём не начать: " + error + " Поправьте в редакторе."
		_ship_note.modulate = Color(1.0, 0.55, 0.5)
	elif name.begins_with(ShipMap.USER_PREFIX):
		_ship_note.text = "Свой корабль. Друзьям ничего не нужно копировать: чертёж придёт при подключении."
		_ship_note.modulate = Color(0.75, 0.85, 1.0)
	else:
		_ship_note.text = ""


func ship_name() -> String:
	## The map a new campaign is played on (ship02, or ships:NAME).
	var i := maxi(_ship.selected, 0)
	return _ship_names[i] if i < _ship_names.size() else STANDARD_SHIP


func _show_job() -> void:
	_job_about.text = Net.JOB_ABOUT[job()]


func job() -> int:
	## The job the player asks for (Net.JOB_*).
	return _job.get_item_id(maxi(_job.selected, 0))


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	_buttons.append(b)
	return b


func show_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1.0, 0.55, 0.5) if is_error else Color(0.75, 0.85, 1.0)


func set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy


func player_name() -> String:
	var n := _name.text.strip_edges()
	return n if not n.is_empty() else "Игрок"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", _name.text.strip_edges())
	cfg.set_value("player", "address", _address.text.strip_edges())
	cfg.set_value("player", "bots", int(_bots.value))
	cfg.set_value("player", "mode", _mode.selected)
	cfg.set_value("player", "complex", _complex.button_pressed)
	cfg.set_value("player", "job", job())
	cfg.set_value("player", "ship", ship_name())
	cfg.set_value("player", "own_others", _own.button_pressed)
	cfg.save(SETTINGS)


func _on_host() -> void:
	var error: String = _ship_errors[maxi(_ship.selected, 0)] if maxi(_ship.selected, 0) < _ship_errors.size() else ""
	if error != "":
		show_status("На этом корабле не начать: " + error, true)
		return
	if Campaign.exists() and not _new_armed:
		_new_armed = true
		show_status("Сохранённая кампания будет потеряна. Нажмите «Новая кампания» ещё раз, чтобы начать заново.", true)
		return
	_new_armed = false
	_save()
	host_requested.emit(player_name(), Net.DEFAULT_PORT, int(_bots.value), "new",
		Net.MODE_KEYS[maxi(_mode.selected, 0)] + ("+complex" if _complex.button_pressed else "+plain"), ship_name(), _own.button_pressed)


func _on_continue() -> void:
	_save()
	host_requested.emit(player_name(), Net.DEFAULT_PORT, int(_bots.value), "continue", "", "", false)   # (v84: the save's ship)


func _on_join() -> void:
	_save()
	var text := _address.text.strip_edges()
	if text.is_empty():
		text = "127.0.0.1"
	var port := Net.DEFAULT_PORT
	# "address:port" is accepted (IPv6 addresses are left alone)
	if text.count(":") == 1:
		var parts := text.split(":")
		if parts[1].is_valid_int():
			text = parts[0]
			port = parts[1].to_int()
	join_requested.emit(player_name(), text, port)
