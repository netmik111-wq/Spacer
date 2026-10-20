extends PanelContainer
## The settings window: sound, picture and keys, in tabs. Opened from the main
## menu and from the game's menu (Esc); changes take effect at once and are
## kept when the window is closed (see Options).

signal closed

const Options := preload("res://src/client/options.gd")

const FPS_CHOICES: Array[int] = [30, 60, 120, 144, 0]

var _capture_action := ""            # waiting for a key for this action...
var _capture_index := 0              # ...in this place of its two
var _key_buttons := {}               # [action, index] -> Button
var _key_note: Label
var _tabs: TabContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	style.border_color = Color(0.36, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.custom_minimum_size = Vector2(760, 470)
	box.add_child(tabs)
	tabs.add_child(_sound_tab())
	tabs.add_child(_video_tab())
	tabs.add_child(_keys_tab())
	var done := Button.new()
	done.text = "Готово"
	done.custom_minimum_size = Vector2(0, 34)
	done.pressed.connect(close)
	box.add_child(done)


func show_tab(i: int) -> void:
	_tabs.current_tab = clampi(i, 0, _tabs.get_tab_count() - 1)


func open() -> void:
	_refresh_keys()
	_key_note.text = ""
	visible = true


func close() -> void:
	_capture_action = ""
	Options.save_all()
	visible = false
	closed.emit()


func _page(tab_name: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = tab_name
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	return page


func _slider(page: VBoxContainer, caption: String, value: float, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundf(value * 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size = Vector2(48, 0)
	shown.text = "%d%%" % int(slider.value)
	row.add_child(shown)
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = "%d%%" % int(v)
		changed.call(v / 100.0)
		Options.apply_sound())


func _check(page: VBoxContainer, caption: String, on: bool, changed: Callable) -> void:
	var box := CheckBox.new()
	box.text = caption
	box.button_pressed = on
	box.toggled.connect(changed)
	page.add_child(box)


func _sound_tab() -> Control:
	var page := _page("Звук")
	_slider(page, "Общая громкость", Options.volume, func(v: float) -> void: Options.volume = v)
	_slider(page, "Звуки на корабле", Options.world_volume, func(v: float) -> void: Options.world_volume = v)
	_slider(page, "Гул двигателя", Options.hum_volume, func(v: float) -> void: Options.hum_volume = v)
	_slider(page, "Шаги", Options.steps_volume, func(v: float) -> void: Options.steps_volume = v)
	_slider(page, "Бой кораблей", Options.fight_volume, func(v: float) -> void: Options.fight_volume = v)
	_slider(page, "Музыка", Options.music_volume, func(v: float) -> void: Options.music_volume = v)
	_check(page, "Выключить звук", Options.muted, func(on: bool) -> void:
		Options.muted = on
		Options.apply_sound())
	return page.get_parent()


func _video_tab() -> Control:
	var page := _page("Изображение")
	_check(page, "Полный экран (также F11)", Options.fullscreen, func(on: bool) -> void:
		Options.fullscreen = on
		Options.apply_video())
	_check(page, "Вертикальная синхронизация (без разрывов картинки)", Options.vsync, func(on: bool) -> void:
		Options.vsync = on
		Options.apply_video())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var label := Label.new()
	label.text = "Предел кадров в секунду"
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var fps := OptionButton.new()
	for f in FPS_CHOICES:
		fps.add_item("без предела" if f == 0 else str(f))
	fps.select(maxi(FPS_CHOICES.find(Options.max_fps), 0))
	fps.item_selected.connect(func(i: int) -> void:
		Options.max_fps = FPS_CHOICES[i]
		Options.apply_video())
	row.add_child(fps)
	_check(page, "Показывать число кадров в секунду", Options.show_fps, func(on: bool) -> void: Options.show_fps = on)
	_check(page, "Белая вспышка после прыжка", Options.flash, func(on: bool) -> void: Options.flash = on)
	# (v74, the author's L1) the first shift's checklist: turned on again, it starts over
	_check(page, "Подсказки первой смены", Options.first_shift, func(on: bool) -> void:
		Options.first_shift = on
		if on:
			Options.shift_done = 0)
	_slider(page, "Тряска при попаданиях", Options.shake, func(v: float) -> void: Options.shake = v)
	# (v73, the author's H5) the size of the interface and its text
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 12)
	page.add_child(size_row)
	var size_label := Label.new()
	size_label.text = "Размер интерфейса и текста"
	size_label.custom_minimum_size = Vector2(220, 0)
	size_row.add_child(size_label)
	var size_slider := HSlider.new()
	size_slider.min_value = 75
	size_slider.max_value = 150
	size_slider.step = 5
	size_slider.value = roundf(Options.ui_scale * 100.0)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_row.add_child(size_slider)
	var size_shown := Label.new()
	size_shown.custom_minimum_size = Vector2(48, 0)
	size_shown.text = "%d%%" % int(size_slider.value)
	size_row.add_child(size_shown)
	# taken when the slider is let go: the window itself grows with it
	size_slider.value_changed.connect(func(v: float) -> void:
		size_shown.text = "%d%%" % int(v)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			Options.ui_scale = v / 100.0)                 # (keys, the wheel)
	size_slider.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			Options.ui_scale = size_slider.value / 100.0)
	return page.get_parent()


func _keys_tab() -> Control:
	var page := _page("Управление")
	var about := Label.new()
	about.text = "Щёлкните по клавише и нажмите новую. Можно с Ctrl, Shift или Alt. Esc: отмена, Backspace: убрать клавишу."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_theme_font_size_override("font_size", 13)
	about.modulate = Color(1, 1, 1, 0.75)
	page.add_child(about)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for a: Array in Options.ACTIONS:
		var label := Label.new()
		label.text = a[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		for i in Options.KEYS_PER_ACTION:
			var b := Button.new()
			b.custom_minimum_size = Vector2(150, 28)
			var action: String = a[0]
			var index := i
			b.pressed.connect(func() -> void: _capture(action, index))
			grid.add_child(b)
			_key_buttons[[action, i]] = b
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	page.add_child(bottom)
	_key_note = Label.new()
	_key_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_note.add_theme_font_size_override("font_size", 13)
	_key_note.modulate = Color(1.0, 0.8, 0.5)
	bottom.add_child(_key_note)
	var reset := Button.new()
	reset.text = "Все клавиши по умолчанию"
	reset.pressed.connect(func() -> void:
		Options.keys = Options.defaults()
		Options.apply_keys()
		_capture_action = ""
		_key_note.text = "Клавиши сброшены."
		_refresh_keys())
	bottom.add_child(reset)
	_refresh_keys()
	return page.get_parent()


func _capture(action: String, index: int) -> void:
	_capture_action = action
	_capture_index = mini(index, (Options.keys.get(action, []) as Array).size())
	_refresh_keys()
	var b: Button = _key_buttons[[action, index]]
	b.text = "Нажмите клавишу…"
	_key_note.text = ""


func _refresh_keys() -> void:
	for key: Array in _key_buttons:
		var list: Array = Options.keys.get(key[0], [])
		var i: int = key[1]
		(_key_buttons[key] as Button).text = Options.binding_text(list[i]) if i < list.size() else "—"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture_action == "":
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	if not k.pressed or k.echo:
		return
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return                               # a modifier on its own: wait for the key itself
	var bare := not (k.ctrl_pressed or k.shift_pressed or k.alt_pressed)
	var action := _capture_action
	_capture_action = ""
	if code == KEY_ESCAPE and bare:
		_key_note.text = ""
	elif code == KEY_BACKSPACE and bare:
		Options.unbind(action, _capture_index)
		_key_note.text = "Клавиша убрана: %s." % Options.label_of(action)
	else:
		var b := Options.binding_of(k)
		var took := Options.bind(action, _capture_index, b)
		_key_note.text = "%s: %s." % [Options.label_of(action), Options.binding_text(b)]
		if took != "":
			_key_note.text += " Эта клавиша была у «%s»: там она убрана." % Options.label_of(took)
	_refresh_keys()
