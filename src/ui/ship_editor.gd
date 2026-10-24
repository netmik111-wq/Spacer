extends Control
## (v81, the author's top priority: "a working map editor for my spriter, very comfortable for
## humans") The ship editor, from the main menu: draws ships of every kind (ours, pirate ships,
## derelicts) and asteroids in the game's own pictures, keeps them in the «ships» folder next to
## the game (the same text form as maps/*.txt, so a file can be sent to friends), lists what is
## wrong as one draws, and «Попробовать» starts a game alone on what was drawn.
## His answers: https://claude.ai/artifact/68oyd5cH9wyAsoT5Gcwfww (E1-E11, all "A").

signal closed
signal try_requested(ship: String, kind: String)

const MapBuilder := preload("res://src/shared/map_builder.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Sprites := preload("res://src/client/sprites.gd")
const Drawing := preload("res://src/ui/editor/drawing.gd")
const Checks := preload("res://src/ui/editor/checks.gd")
const Canvas := preload("res://src/ui/editor/canvas.gd")

const AUTOSAVE_SEC := 60.0
const CATEGORIES := ["Все", "Стены и пол", "Двери и окна", "Пульты", "Машины", "Орудия и защита", "Медицина и быт", "Астероид"]
# every sign the editor draws with: [sign, name, category, where it goes]
const PALETTE := [
	["#", "Стена", 1, "Стены соединяются сами: углы и стыки подбираются по соседям."],
	[".", "Пол", 1, "Комнаты высотой в две клетки и больше, между горизонтальными стенами."],
	["s", "Пол: место появления", 1, "Здесь появляется экипаж. Нужен хотя бы один на нашем корабле."],
	["g", "Стеклянный пол", 1, "Сквозь него видна палуба ниже; воздух не проходит."],
	["c", "Мостки (решётка)", 1, "Видна палуба ниже, воздух общий. Под ними нужен пол."],
	["H", "Лестница", 1, "Ставится в одну и ту же клетку двух соседних палуб."],
	[" ", "Пустота (ластик)", 1, "Открытый космос. Правая кнопка мыши стирает любым инструментом."],
	["D", "Дверь", 2, "В горизонтальной стене, пол сверху и снизу (или космос с одной стороны: наружная дверь)."],
	["A", "Шлюзовая дверь", 2, "В вертикальной стене, между двумя комнатами."],
	["W", "Окно", 2, "В горизонтальной стене."],
	["<", "Широкое окно, левая половина", 2, "Ставится парой: «<» и «>» рядом."],
	[">", "Широкое окно, правая половина", 2, "Ставится парой: «<» и «>» рядом."],
	["F", "Силовое поле ангара", 2, "В верхней стене корпуса, над комнатой: держит воздух, за ним стоит челнок флотилии."],
	["1", "Карта сектора", 3, "Пульт в горизонтальной стене: прыжки между системами."],
	["3", "Штурвал", 3, "Пульт управления кораблём. Обязателен на нашем корабле."],
	["4", "Пульт орудий", 3, "Стрельба из орудий корпуса и зонд."],
	["5", "Монитор дрона", 3, "Разведывательный дрон."],
	["K", "Пульт связи", 3, "Вызовы, события, задания."],
	["V", "Пульт челнока", 3, "Рядом с силовым полем: сесть в челнок или вызвать его (флотилия из двух кораблей)."],
	["M", "Голокарта", 3, "Весь корабль: воздух, пробоины, поломки."],
	["I", "Интерком", 3, "Связь по кораблю."],
	["2", "Кислородная станция", 4, "Заправка баллонов скафандров."],
	["6", "Двигатель", 4, "Обязателен на нашем корабле: полёт и энергия."],
	["S", "Накопитель энергии", 4, "Держит корабль, когда двигатель стоит."],
	["Q", "Запасной накопитель", 4, "Держит свет и пульты в комнате, на которую смотрит (мостик)."],
	["7", "Воздушная установка", 4, "Восполняет воздух."],
	["9", "Насос шлюза", 4, "Стоит в стене камеры шлюза: у камеры внутренняя дверь и наружная в космос."],
	["8", "Шкаф снабжения", 4, "Запасы корабля и торговля."],
	["B", "Верстак", 4, "Разборка и улучшение орудий, топливо из лома."],
	["U", "Отсек модулей", 4, "Броня, фокусирующий массив, фазовый привод."],
	["T", "Орудие", 5, "В горизонтальной стене корпуса. Стреляют с пульта орудий."],
	["Z", "Генератор щита", 5, "Щит корабля."],
	["Y", "Автодок", 6, "Лечит лежащего перед ним."],
	["X", "Сканер тела", 6, "Показывает здоровье лежащего в автодоке."],
	["C", "Криокапсула", 6, "Здесь спит резерв экипажа."],
	["P", "Гидропонный лоток", 6, "Растения; два рядом могут скрещиваться."],
	["G", "Плита камбуза", 6, "Готовка из пайков."],
	["R", "Скала", 7, "Камень астероида: любой формы, без правил комнат."],
	["O", "Рудная жила", 7, "Из неё добывают руду: держать E рядом, в скафандре."],
	[",", "Каменный грунт", 7, "По нему можно ходить (пещеры, выступы)."],
]
const KIND_NAMES := {"ship": "Наш корабль", "pirate": "Пиратский корабль", "derelict": "Брошенный корабль", "asteroid": "Астероид"}
const KIND_SIZE := {"ship": [40, 20, 2], "pirate": [30, 8, 1], "derelict": [16, 8, 1], "asteroid": [18, 8, 1]}
const LOCKS := [["bridge", "Мостик (замок)"], ["engine", "Машинное (замок)"], ["medbay", "Медотсек (замок)"],
	["armory", "Оружейная (замок)"], ["guns", "Орудийная (замок)"], ["brig", "Камера (бриг)"]]
const SYSTEMS := [["weapons", "Оружие"], ["helm", "Рубка"], ["engine", "Двигатель"], ["crew", "Кубрик"],
	["jump", "Гипердвигатель"], ["shields", "Щиты"]]
const TOOLS := [
	[Canvas.Tool.BRUSH, "Кисть", "B", "Держите кнопку и ведите: рисует без пропусков."],
	[Canvas.Tool.LINE, "Линия", "L", "Прямая от нажатия до отпускания."],
	[Canvas.Tool.RECT, "Прямоугольник", "R", "Рамка; с Shift (или галочкой «залить») сплошной."],
	[Canvas.Tool.ROOM, "Комната", "M", "Стены вокруг, пол внутри. Общие стены соседних комнат не трогает."],
	[Canvas.Tool.FILL, "Заливка", "F", "Меняет всю связную область одного знака."],
	[Canvas.Tool.ERASE, "Ластик", "E", "Стирает в пустоту. Правая кнопка стирает любым инструментом."],
	[Canvas.Tool.PICK, "Пипетка", "I", "Берёт знак с рисунка. То же: Alt + щелчок."],
	[Canvas.Tool.SELECT, "Выделение", "S", "Ctrl+C, Ctrl+X, Ctrl+V, Delete; тащите выделенное, чтобы передвинуть."],
	[Canvas.Tool.MARK, "Метки комнат", "K", "Щёлкните по полу комнаты: замок, камера брига, система пиратов."],
]

var drawing := Drawing.new()
var ship_name := ""
var _canvas: Canvas
var _name_edit: LineEdit
var _kind: OptionButton
var _tabs: TabBar
var _deck_name: LineEdit
var _tool_buttons := {}
var _palette: ItemList
var _category: OptionButton
var _search: LineEdit
var _favs: HBoxContainer
var _favourites: Array[String] = ["#", ".", "D", "s"]
var _problems: VBoxContainer
var _problem_rows: Array = []
var _status: Label
var _info: Label
var _try: Button
var _mirror_x: CheckBox
var _mirror_y: CheckBox
var _filled: CheckBox
var _grid: CheckBox
var _layer: OptionButton             # (v82.1) which layer the tools change
var _objects_shown: CheckBox
var _open_popup: PopupPanel
var _open_list: ItemList
var _size_popup: PopupPanel
var _size_w: SpinBox
var _size_h: SpinBox
var _size_top: SpinBox
var _size_left: SpinBox
var _mark_menu: PopupMenu
var _mark_cell := Vector2i.ZERO
var _help: PopupPanel
var _checked_at := -1
var _check_due := 0.0
var _saved_at := -1                  # Drawing.changes when last saved
var _autosave_due := 0.0
var _remove_armed := false
var _new_armed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.06, 0.065, 0.09)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	root.add_child(_top_bar())
	var middle := HSplitContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	middle.add_child(_left_panel())
	var centre := HSplitContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(centre)
	var work := VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_child(work)
	work.add_child(_deck_bar())
	_canvas = Canvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.drawing = drawing
	_canvas.picked.connect(_on_picked)
	_canvas.hovered.connect(_on_hover)
	_canvas.mark_asked.connect(_on_mark_asked)
	_canvas.changed.connect(func() -> void: _note(sign_name(_canvas.sign)))
	work.add_child(_canvas)
	centre.add_child(_right_panel())
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bottom.add_child(_status)
	_info = Label.new()
	_info.modulate = Color(1, 1, 1, 0.65)
	bottom.add_child(_info)
	_make_popups()
	_new_drawing("ship")
	_set_tool(Canvas.Tool.BRUSH)
	_choose("#")


# ---------------------------------------------------------------- building the screen

func _button(text: String, tip: String, call: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(call)
	return b


func _top_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "  Редактор кораблей  "
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	bar.add_child(_button("Новый", "Чистый лист того вида, что выбран справа", _on_new))
	bar.add_child(_button("Открыть…", "Корабль из папки ships или из самой игры (как основа)", _on_open))
	bar.add_child(_button("Сохранить", "Ctrl+S. В папку ships рядом с игрой; ещё сохраняется само раз в минуту", save))
	var caption := Label.new()
	caption.text = "Имя:"
	bar.add_child(caption)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(200, 0)
	_name_edit.tooltip_text = "Имя файла в папке ships"
	_name_edit.text_changed.connect(func(t: String) -> void: ship_name = _clean_name(t))
	bar.add_child(_name_edit)
	_kind = OptionButton.new()
	for k: String in MapBuilder.KINDS:
		_kind.add_item(KIND_NAMES[k])
	_kind.tooltip_text = "Что это: наш корабль, пиратский, брошенный или астероид"
	_kind.focus_mode = Control.FOCUS_NONE
	_kind.item_selected.connect(func(i: int) -> void:
		drawing.set_kind(MapBuilder.KINDS[i])
		drawing.commit()
		_fill_palette())
	bar.add_child(_kind)
	bar.add_child(_button("Размер…", "Ширина и высота холста; добавить ряды сверху или столбцы слева", _on_size))
	_try = _button("▶ Попробовать", "Сохранить и сразу сыграть одному на этом корабле (F5)", _on_try)
	bar.add_child(_try)
	bar.add_child(_button("Обновить картинки", "Перечитать картинки из папки sprites, не перезапуская игру", _on_reload))
	bar.add_child(_button("Папка", "Открыть папку ships", func() -> void:
		DirAccess.make_dir_recursive_absolute(ShipMap.ships_dir())
		OS.shell_open(ShipMap.ships_dir())))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	bar.add_child(_button("Клавиши", "Все сочетания клавиш редактора", func() -> void: _help.popup_centered()))
	bar.add_child(_button("Выход", "Сохранить и вернуться в меню", _on_close))
	return bar


func _left_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	var tools := GridContainer.new()
	tools.columns = 3
	for t: Array in TOOLS:
		var b := _button("%s (%s)" % [t[1], t[2]], t[3], _set_tool.bind(t[0]))
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		_tool_buttons[t[0]] = b
		tools.add_child(b)
	panel.add_child(tools)
	var opts := GridContainer.new()
	opts.columns = 2
	_mirror_x = _check("Зеркало ↔ (X)", "Всё нарисованное повторяется зеркально слева направо", func(on: bool) -> void:
		drawing.mirror_x = on
		_canvas.queue_redraw())
	_mirror_y = _check("Зеркало ↕ (Y)", "Всё нарисованное повторяется зеркально сверху вниз", func(on: bool) -> void:
		drawing.mirror_y = on
		_canvas.queue_redraw())
	_filled = _check("Залить прямоуг.", "Прямоугольник сплошной, а не рамка", func(on: bool) -> void: _canvas.filled = on)
	_grid = _check("Сетка (G)", "Линии клеток", func(on: bool) -> void:
		_canvas.grid = on
		_canvas.queue_redraw())
	_grid.set_pressed_no_signal(true)
	for c in [_mirror_x, _mirror_y, _filled, _grid]:
		opts.add_child(c)
	panel.add_child(opts)
	# (v82.1, the author's note) layers: floor under, objects on top
	var layer_row := HBoxContainer.new()
	var layer_caption := Label.new()
	layer_caption.text = "Слой (Q):"
	layer_caption.add_theme_font_size_override("font_size", 12)
	layer_row.add_child(layer_caption)
	_layer = OptionButton.new()
	_layer.focus_mode = Control.FOCUS_NONE
	_layer.add_theme_font_size_override("font_size", 12)
	_layer.tooltip_text = "Пол (стены, пол, стекло, мостки, скала) лежит снизу, объекты (двери, окна, пульты, машины,\n" \
		+ "орудия, места появления, лестницы) — сверху. Пол под объектом остаётся, ластик сначала убирает объект.\n" \
		+ "«Только пол» и «Только объекты»: инструменты, ластик, выделение и заливка трогают один слой."
	for t in ["Пол и объекты", "Только пол", "Только объекты"]:
		_layer.add_item(t)
	_layer.item_selected.connect(func(i: int) -> void:
		drawing.layer = i
		_note("Слой: %s." % _layer.get_item_text(i)))
	layer_row.add_child(_layer)
	panel.add_child(layer_row)
	_objects_shown = _check("Объекты видны (O)", "Снимите, чтобы видеть один пол: что лежит под дверями, пультами и машинами",
		func(on: bool) -> void:
			_canvas.show_objects = on
			_canvas.queue_redraw())
	_objects_shown.set_pressed_no_signal(true)
	panel.add_child(_objects_shown)
	var undo_row := HBoxContainer.new()
	undo_row.add_child(_button("↶ Отменить", "Ctrl+Z", _undo))
	undo_row.add_child(_button("↷ Вернуть", "Ctrl+Y", _redo))
	panel.add_child(undo_row)
	var fav_caption := Label.new()
	fav_caption.text = "Последние (клавиши 1–9):"
	fav_caption.modulate = Color(1, 1, 1, 0.7)
	panel.add_child(fav_caption)
	_favs = HBoxContainer.new()
	panel.add_child(_favs)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск: дверь, двигатель, руда…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _fill_palette())
	panel.add_child(_search)
	_category = OptionButton.new()
	for c: String in CATEGORIES:
		_category.add_item(c)
	_category.focus_mode = Control.FOCUS_NONE
	_category.item_selected.connect(func(_i: int) -> void: _fill_palette())
	panel.add_child(_category)
	_palette = ItemList.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.fixed_icon_size = Vector2i(32, 32)
	_palette.focus_mode = Control.FOCUS_NONE
	_palette.item_selected.connect(func(i: int) -> void: _choose(str(_palette.get_item_metadata(i))))
	panel.add_child(_palette)
	return panel


func _check(text: String, tip: String, call: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 12)
	c.toggled.connect(call)
	return c


func _deck_bar() -> Control:
	var bar := HBoxContainer.new()
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(func(i: int) -> void:
		_canvas.deck = i
		_deck_name.text = str(drawing.decks[i]["name"]) if i < drawing.decks.size() else ""
		_canvas.queue_redraw())
	bar.add_child(_tabs)
	bar.add_child(_button("+", "Добавить палубу снизу", func() -> void:
		drawing.add_deck()
		drawing.commit()
		_refresh_tabs(drawing.decks.size() - 1)))
	bar.add_child(_button("−", "Убрать эту палубу (нажмите дважды)", _remove_deck))
	bar.add_child(_button("◀", "Поднять палубу выше", _move_deck.bind(-1)))
	bar.add_child(_button("▶", "Опустить палубу ниже", _move_deck.bind(1)))
	_deck_name = LineEdit.new()
	_deck_name.custom_minimum_size = Vector2(180, 0)
	_deck_name.tooltip_text = "Название палубы"
	_deck_name.text_submitted.connect(func(t: String) -> void:
		drawing.rename_deck(_canvas.deck, t)
		drawing.commit()
		_refresh_tabs(_canvas.deck)
		_deck_name.release_focus())
	bar.add_child(_deck_name)
	var hint := Label.new()
	hint.text = "  палуба выше видна бледно"
	hint.modulate = Color(1, 1, 1, 0.5)
	bar.add_child(hint)
	return bar


func _right_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var caption := Label.new()
	caption.text = "Проблемы (щёлкните, чтобы найти)"
	panel.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_problems = VBoxContainer.new()
	_problems.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problems.add_theme_constant_override("separation", 6)
	scroll.add_child(_problems)
	var about := Label.new()
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(290, 0)
	about.modulate = Color(1, 1, 1, 0.6)
	about.add_theme_font_size_override("font_size", 12)
	about.text = "Красное — ошибка: игра не загрузит корабль, «Попробовать» ждёт исправления. Жёлтое — чего-то не хватит в игре. Сохранять можно всегда."
	panel.add_child(about)
	return panel


func _make_popups() -> void:
	_open_popup = PopupPanel.new()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 420)
	_open_popup.add_child(box)
	var t := Label.new()
	t.text = "Открыть корабль"
	box.add_child(t)
	_open_list = ItemList.new()
	_open_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_open_list.item_activated.connect(func(i: int) -> void: _open_item(i))
	box.add_child(_open_list)
	box.add_child(_button("Открыть", "", func() -> void:
		var sel := _open_list.get_selected_items()
		if not sel.is_empty():
			_open_item(sel[0])))
	add_child(_open_popup)

	_size_popup = PopupPanel.new()
	var grid := GridContainer.new()
	grid.columns = 2
	_size_popup.add_child(grid)
	_size_w = _spin(grid, "Ширина", 4, Drawing.MAX_SIZE)
	_size_h = _spin(grid, "Высота", 3, Drawing.MAX_SIZE)
	_size_top = _spin(grid, "Добавить рядов сверху", -40, 40)
	_size_left = _spin(grid, "Добавить столбцов слева", -40, 40)
	grid.add_child(Control.new())
	grid.add_child(_button("Применить", "", func() -> void:
		var top := int(_size_top.value)
		var left := int(_size_left.value)
		drawing.resize(int(_size_w.value) + left, int(_size_h.value) + top, Vector2i(left, top))
		drawing.commit()
		_size_popup.hide()
		_canvas.fit()))
	add_child(_size_popup)

	_mark_menu = PopupMenu.new()
	_mark_menu.id_pressed.connect(_on_mark_chosen)
	add_child(_mark_menu)

	_help = PopupPanel.new()
	var help := Label.new()
	help.text = "\n".join(PackedStringArray([
		"Левая кнопка — рисовать инструментом, правая — стирать, Alt + щелчок — взять знак.",
		"Колесо — приблизить, средняя кнопка или пробел + мышь — двигать вид, Home — весь корабль.",
		"B кисть, L линия, R прямоугольник (Shift — сплошной), M комната, F заливка, E ластик, I пипетка,",
		"S выделение, K метки комнат. G — сетка. X / Y — зеркало (при вставке: перевернуть копию).",
		"Слои: пол снизу, объекты (двери, окна, пульты, машины, места появления, лестницы) сверху. Q — какой",
		"слой меняют инструменты (оба, только пол, только объекты), O — показать или спрятать объекты.",
		"Ctrl+Z отменить, Ctrl+Y (или Ctrl+Shift+Z) вернуть, Ctrl+C копировать, Ctrl+X вырезать,",
		"Ctrl+V вставить (копия следует за мышью, щелчок кладёт, Esc отменяет), Delete — стереть выделенное,",
		"Ctrl+A — выделить всё. 1–9 — последние знаки. Page Up / Page Down — палуба выше / ниже.",
		"Ctrl+S — сохранить, F5 — попробовать. Корабль сохраняется сам раз в минуту.",
		"",
		"Правила рисунка: комнаты не ниже двух клеток, между горизонтальными стенами. Машины и пульты",
		"стоят в горизонтальной стене и смотрят в комнату. Шлюз: камера с насосом «9», внутренняя дверь",
		"и наружная в космос. Лестница «H» — в одной клетке двух соседних палуб.",
	]))
	_help.add_child(help)
	add_child(_help)


func _spin(grid: GridContainer, caption: String, lo: int, hi: int) -> SpinBox:
	var l := Label.new()
	l.text = caption
	grid.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	grid.add_child(s)
	return s


# ---------------------------------------------------------------- palette and tools

static func sign_name(s: String) -> String:
	for p: Array in PALETTE:
		if p[0] == s:
			return p[1]
	return s


func _icon(s: String) -> Texture2D:
	var name := Canvas.icon_tile(s)
	var ids := MapBuilder.tile_ids()
	if drawing.kind == "pirate" and ids.has("pirate_" + name):
		name = "pirate_" + name
	if not ids.has(name):
		return null
	var a := AtlasTexture.new()
	a.atlas = Sprites.sheet("tiles")
	a.region = _canvas.tile_region(int(ids[name])) if _canvas != null else Rect2()
	return a


func _fill_palette() -> void:
	_palette.clear()
	var want := _search.text.strip_edges().to_lower()
	var cat := _category.selected
	for p: Array in PALETTE:
		if want != "" and not (str(p[1]).to_lower().contains(want) or str(p[3]).to_lower().contains(want) or p[0] == want):
			continue
		if want == "" and cat > 0 and int(p[2]) != cat:
			continue
		var i := _palette.add_item("%s   «%s»" % [p[1], p[0]], _icon(p[0]))
		_palette.set_item_metadata(i, p[0])
		_palette.set_item_tooltip(i, p[3])
		if p[0] == _canvas.sign:
			_palette.select(i)
	_fill_favs()


func _fill_favs() -> void:
	for c in _favs.get_children():
		c.queue_free()
	for i in _favourites.size():
		var s: String = _favourites[i]
		var b := Button.new()
		b.icon = _icon(s)
		b.tooltip_text = "%d: %s" % [i + 1, sign_name(s)]
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(26, 34)
		b.pressed.connect(_choose.bind(s))
		_favs.add_child(b)


func _choose(s: String) -> void:
	_canvas.sign = s
	_favourites.erase(s)
	_favourites.push_front(s)
	if _favourites.size() > 9:
		_favourites.resize(9)
	if _canvas.tool == Canvas.Tool.PICK or _canvas.tool == Canvas.Tool.ERASE or _canvas.tool == Canvas.Tool.SELECT \
			or _canvas.tool == Canvas.Tool.MARK or _canvas.tool == Canvas.Tool.ROOM:
		_set_tool(Canvas.Tool.BRUSH)
	_fill_palette()
	_note("Рисую: %s. %s" % [sign_name(s), _hint_of(s)])


func _hint_of(s: String) -> String:
	for p: Array in PALETTE:
		if p[0] == s:
			return p[3]
	return ""


func _set_tool(t: int) -> void:
	_canvas.tool = t
	for k: int in _tool_buttons.keys():
		(_tool_buttons[k] as Button).button_pressed = k == t
	for row: Array in TOOLS:
		if row[0] == t:
			_note("%s: %s" % [row[1], row[3]])
	_canvas.queue_redraw()


func _on_picked(s: String) -> void:
	if s != " ":
		_choose(s)
		_set_tool(Canvas.Tool.BRUSH)


# ---------------------------------------------------------------- decks

func _refresh_tabs(select: int) -> void:
	_tabs.clear_tabs()
	for d: Dictionary in drawing.decks:
		_tabs.add_tab(str(d["name"]))
	select = clampi(select, 0, drawing.decks.size() - 1)
	_tabs.current_tab = select
	_canvas.deck = select
	_deck_name.text = str(drawing.decks[select]["name"])
	_canvas.queue_redraw()


func _remove_deck() -> void:
	if drawing.decks.size() <= 1:
		_note("Последнюю палубу не убрать.")
		return
	if not _remove_armed:
		_remove_armed = true
		_note("Нажмите «−» ещё раз, чтобы убрать палубу «%s» со всем нарисованным." % drawing.decks[_canvas.deck]["name"])
		return
	_remove_armed = false
	drawing.remove_deck(_canvas.deck)
	drawing.commit()
	_refresh_tabs(_canvas.deck)


func _move_deck(by: int) -> void:
	drawing.move_deck(_canvas.deck, by)
	drawing.commit()
	_refresh_tabs(_canvas.deck + by)


# ---------------------------------------------------------------- marks

func _on_mark_asked(c: Vector2i) -> void:
	if drawing.room_cells(_canvas.deck, c).is_empty():
		_note("Метки ставятся на пол комнаты.")
		return
	_mark_cell = c
	_mark_menu.clear()
	if drawing.kind == "pirate":
		for i in SYSTEMS.size():
			_mark_menu.add_item("Система: " + str(SYSTEMS[i][1]), 100 + i)
	else:
		for i in LOCKS.size():
			_mark_menu.add_item(str(LOCKS[i][1]), i)
	_mark_menu.add_separator()
	_mark_menu.add_item("Снять метку", 99)
	_mark_menu.position = Vector2i(get_global_mouse_position()) + get_window().position
	_mark_menu.popup()


func _on_mark_chosen(id: int) -> void:
	var cells := drawing.room_cells(_canvas.deck, _mark_cell)
	var type := "%" if drawing.kind == "pirate" else "@"
	drawing.remove_marks_in(_canvas.deck, cells, type)
	if id >= 100:
		drawing.set_mark(_canvas.deck, _mark_cell, "%", str(SYSTEMS[id - 100][0]))
	elif id < LOCKS.size():
		drawing.set_mark(_canvas.deck, _mark_cell, "@", str(LOCKS[id][0]))
	drawing.commit()
	_canvas.queue_redraw()


# ---------------------------------------------------------------- problems

func _process(delta: float) -> void:
	if drawing.changes != _checked_at:
		_check_due += delta
		if _check_due >= 0.3:
			_check_due = 0.0
			_checked_at = drawing.changes
			_run_checks()
	_autosave_due += delta
	if _autosave_due >= AUTOSAVE_SEC:
		_autosave_due = 0.0
		if drawing.changes != _saved_at and visible:
			save()
	_info.text = "%d×%d, палуб %d%s   " % [drawing.width, drawing.height, drawing.decks.size(),
		"" if drawing.changes == _saved_at else "  • не сохранено"]


func _run_checks() -> void:
	var found := Checks.run(drawing)
	_canvas.problems = found
	_canvas.queue_redraw()
	for c in _problems.get_children():
		c.queue_free()
	_problem_rows = found
	var errors := 0
	for i in found.size():
		var p: Dictionary = found[i]
		var where := ""
		if int(p["deck"]) >= 0:
			where = " (%s, %d:%d)" % [drawing.decks[int(p["deck"])]["name"] if int(p["deck"]) < drawing.decks.size() else "?", int(p["x"]), int(p["y"])]
		var row := Label.new()
		row.text = ("✖ " if p["error"] else "⚠ ") + str(p["text"]) + where
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(300, 0)
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45) if p["error"] else Color(1.0, 0.85, 0.45))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
				_on_problem(i))
		_problems.add_child(row)
		if p["error"]:
			errors += 1
	if found.is_empty():
		var ok := Label.new()
		ok.text = "Всё в порядке."
		ok.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		_problems.add_child(ok)
	_try.disabled = errors > 0
	_try.tooltip_text = "Сначала исправьте ошибки (красное справа)." if errors > 0 else "Сохранить и сразу сыграть одному на этом корабле (F5)"


func _on_problem(i: int) -> void:
	if i >= _problem_rows.size():
		return
	var p: Dictionary = _problem_rows[i]
	if int(p["deck"]) >= 0:
		_refresh_tabs(int(p["deck"]))
		_canvas.centre_on(Vector2i(int(p["x"]), int(p["y"])))
	_note(str(p["text"]))


# ---------------------------------------------------------------- files

static func _clean_name(t: String) -> String:
	var out := ""
	for ch in t.strip_edges():
		if not "/\\:*?\"<>|".contains(ch):
			out += ch
	return out.substr(0, 48)


func _new_drawing(kind: String) -> void:
	var s: Array = KIND_SIZE[kind]
	drawing.reset(int(s[0]), int(s[1]), int(s[2]))
	drawing.kind = kind
	ship_name = _free_name(KIND_NAMES[kind])
	_name_edit.text = ship_name
	_kind.select(MapBuilder.KINDS.find(kind))
	_saved_at = drawing.changes
	_refresh_tabs(0)
	_fill_palette()
	_canvas.fit.call_deferred()


func _free_name(base: String) -> String:
	var dir := ShipMap.ships_dir()
	var n := 1
	var name := base
	while FileAccess.file_exists(dir.path_join(name + ".txt")):
		n += 1
		name = "%s %d" % [base, n]
	return name


func _on_new() -> void:
	if drawing.changes != _saved_at and not _new_armed:
		_new_armed = true
		_note("Корабль не сохранён. Нажмите «Новый» ещё раз, чтобы начать чистый лист (или сначала «Сохранить»).")
		return
	_new_armed = false
	_new_drawing(MapBuilder.KINDS[maxi(_kind.selected, 0)])
	_note("Чистый лист: %s." % KIND_NAMES[drawing.kind])


func save() -> bool:
	if ship_name == "":
		ship_name = _free_name(KIND_NAMES[drawing.kind])
		_name_edit.text = ship_name
	DirAccess.make_dir_recursive_absolute(ShipMap.ships_dir())
	var path := ShipMap.ships_dir().path_join(ship_name + ".txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_note("Не удалось сохранить в %s." % path)
		return false
	f.store_string(drawing.to_text())
	f.close()
	_saved_at = drawing.changes
	_note("Сохранено: %s" % path)
	return true


func _on_open() -> void:
	_open_list.clear()
	var dir := ShipMap.ships_dir()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".txt"):
			var i := _open_list.add_item(f.get_basename())
			_open_list.set_item_metadata(i, dir.path_join(f))
	for f in DirAccess.get_files_at("res://maps"):
		if f.ends_with(".txt"):
			var i := _open_list.add_item("Из игры: " + f.get_basename())
			_open_list.set_item_metadata(i, "res://maps/" + f)
			_open_list.set_item_custom_fg_color(i, Color(0.7, 0.8, 1.0))
	_open_popup.popup_centered()


func _open_item(i: int) -> void:
	_open_popup.hide()
	open_path(str(_open_list.get_item_metadata(i)))


func open_path(path: String) -> void:
	## Opens a drawing: one of one's own from the «ships» folder, or (res://maps/...) one of the game's
	## own as a start, kept under a new name.
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_note("Не удалось открыть %s." % path)
		return
	drawing.from_text(text, path.get_file().get_basename())
	var game := path.begins_with("res://")
	ship_name = _free_name("Мой " + path.get_file().get_basename()) if game else path.get_file().get_basename()
	_name_edit.text = ship_name
	_kind.select(MapBuilder.KINDS.find(drawing.kind))
	_saved_at = -1 if game else drawing.changes
	_refresh_tabs(0)
	_fill_palette()
	_canvas.fit.call_deferred()
	_note("Открыт: %s%s" % [path.get_file(), " (копия корабля игры: сохранится под новым именем)" if game else ""])


func _on_size() -> void:
	_size_w.value = drawing.width
	_size_h.value = drawing.height
	_size_top.value = 0
	_size_left.value = 0
	_size_popup.popup_centered()


func _on_reload() -> void:
	Sprites.reload()
	_canvas.reload_pictures()
	_fill_palette()
	_note("Картинки перечитаны из папки sprites (%s)." % ", ".join(Sprites.dirs()))


func _on_try() -> void:
	if _try.disabled:
		_note("Сначала исправьте ошибки (красное справа).")
		return
	if save():
		try_requested.emit(ship_name, drawing.kind)


func _on_close() -> void:
	if drawing.changes != _saved_at:
		save()
	closed.emit()


func _note(text: String) -> void:
	_status.text = "  " + text


func _on_hover(c: Vector2i) -> void:
	if c.x < 0:
		return
	var s := drawing.at(_canvas.deck, c)
	_info.text = "%d:%d  %s   " % [c.x, c.y, sign_name(s) if s != " " else "пусто"]


# ---------------------------------------------------------------- keys

func _undo() -> void:
	if drawing.undo():
		_refresh_tabs(_canvas.deck)
		_note("Отменено.")


func _redo() -> void:
	if drawing.redo():
		_refresh_tabs(_canvas.deck)
		_note("Возвращено.")


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var e := event as InputEventKey
	if e.keycode == KEY_SPACE:
		_canvas.set_space(e.pressed)
	if not e.pressed or e.echo and not (e.keycode == KEY_Z or e.keycode == KEY_Y):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is SpinBox:
		return
	if _open_popup.visible or _size_popup.visible or _mark_menu.visible:
		return
	var ctrl := e.ctrl_pressed or e.meta_pressed
	var handled := true
	match e.keycode:
		KEY_Z when ctrl and e.shift_pressed: _redo()
		KEY_Z when ctrl: _undo()
		KEY_Y when ctrl: _redo()
		KEY_C when ctrl: _copy(false)
		KEY_X when ctrl: _copy(true)
		KEY_V when ctrl:
			_canvas.start_paste()
			_note("Вставка: копия следует за мышью. Щелчок кладёт, X / Y переворачивают, Esc отменяет.")
		KEY_A when ctrl:
			_set_tool(Canvas.Tool.SELECT)
			_canvas.selection = Rect2i(0, 0, drawing.width, drawing.height)
			_canvas.queue_redraw()
		KEY_S when ctrl: save()
		KEY_F5: _on_try()
		KEY_DELETE, KEY_BACKSPACE:
			if _canvas.selection.size != Vector2i.ZERO:
				drawing.clear(_canvas.deck, _canvas.selection)
				drawing.commit()
		KEY_ESCAPE:
			if not _canvas.floating.is_empty():
				_canvas.cancel_float()
			else:
				_canvas.selection = Rect2i()
				_canvas.queue_redraw()
		KEY_X when not _canvas.floating.is_empty(): _canvas.flip_float(true)
		KEY_Y when not _canvas.floating.is_empty(): _canvas.flip_float(false)
		KEY_X: _mirror_x.button_pressed = not _mirror_x.button_pressed
		KEY_Y: _mirror_y.button_pressed = not _mirror_y.button_pressed
		KEY_G: _grid.button_pressed = not _grid.button_pressed
		KEY_O: _objects_shown.button_pressed = not _objects_shown.button_pressed
		KEY_Q:
			_layer.select((_layer.selected + 1) % _layer.item_count)
			_layer.item_selected.emit(_layer.selected)
		KEY_HOME: _canvas.fit()
		KEY_PAGEUP: _refresh_tabs(_canvas.deck - 1)
		KEY_PAGEDOWN: _refresh_tabs(_canvas.deck + 1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var i: int = e.keycode - KEY_1
			if i < _favourites.size():
				_choose(_favourites[i])
		_:
			handled = false
			for row: Array in TOOLS:
				if not ctrl and OS.get_keycode_string(e.keycode) == row[2]:
					_set_tool(row[0])
					handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _copy(cut: bool) -> void:
	if _canvas.selection.size == Vector2i.ZERO:
		_note("Сначала выделите место (инструмент «Выделение», S).")
		return
	_canvas.clip = drawing.copy(_canvas.deck, _canvas.selection)
	if cut:
		drawing.clear(_canvas.deck, _canvas.selection)
		drawing.commit()
	_note("%s %d×%d. Ctrl+V — вставить." % ["Вырезано" if cut else "Скопировано", _canvas.selection.size.x, _canvas.selection.size.y])


func back_from_try() -> void:
	## The game started from «Попробовать» is over: the editor is shown again as it was.
	visible = true
	_canvas.reload_pictures()
