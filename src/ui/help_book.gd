extends PanelContainer
## (v74, the author's L1) The help book (its own key, H by default): the keys, every machine
## of the ship with its picture and what E does there, every thing with its picture and what
## it is for, the dangers, and the way through the game. Built when first opened; the
## character can walk while it is open.

const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Options := preload("res://src/client/options.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Sprites := preload("res://src/client/sprites.gd")

const PIC := 40.0                    # a picture's size on the page

# the machines, each: its tile in assets/tiles.png, its name, what it is for and what E does there
const MACHINES := [
	["console_3", "Управление кораблём", "Корабль в космосе: W/S вперёд и назад, A/D поворот, Q/E вбок; щелчок по маленькой карте — автопилот. Прыжок, стыковка, тревога, уклонение."],
	["console_1", "Карта сектора", "Дорога скоплений: выходы, логово флагмана, что впереди."],
	["console_4", "Пульт орудий", "Орудия и щит в бою, цели в отсеках пиратов. Цифры выбирают орудие, Пробел стреляет готовыми."],
	["console_5", "Монитор дрона", "Дрон-разведчик: увидеть план пиратского корабля."],
	["console_2", "Кислородная стойка", "Держите E в скафандре: баллон заправится за 3 с. Нужна энергия."],
	["engine", "Двигатель", "Даёт энергию и тягу. Держите E с канистрой топлива в руке, чтобы залить её в бак."],
	["smes", "СМЭС", "Запас энергии корабля и щиток: включатели орудий и щита, перегрузка. Двигатель стоит, СМЭС пуст: темно."],
	["smes_small", "Резервный СМЭС мостика", "Держит мостик в работе, когда остальной корабль обесточен."],
	["air_plant", "Воздушная установка", "Даёт воздух в отсеки, пока есть энергия."],
	["locker", "Шкаф снабжения", "Все вещи корабля: заплатки, запчасти, канистры, оружие. Взять и положить."],
	["lock_pump", "Насос шлюза", "Выравнивает давление в шлюзе. Кнопка у двери шлюза делает весь цикл сама."],
	["gun", "Орудийная установка", "Орудие из шкафа ставят сюда руками (держите E). Снаряды и ракеты заряжают руками."],
	["shield", "Генератор щита", "Держит щит корабля в бою. E у генератора меняет форму щита: пузырь вокруг корабля или более крепкая дуга на одну сторону."],
	["holo", "Голокарта", "План корабля: воздух, пробоины, поломки, люди."],
	["intercom", "Интерком", "Сказанное с «!» в начале слышно у всех панелей."],
	["med_box", "Ящик первой помощи", "На стене: E берёт аптечку из запасов шкафа снабжения, с аптечкой в руке E кладёт её обратно."],
	["tech_box", "Ящик запчастей", "На стене: то же с запчастями и платами."],
	["comms", "Пульт связи", "Вызовы, задания и миссии, сигналы бедствия."],
	["dock", "Пульт челнока", "Во флотилии из двух кораблей: E — сесть в челнок у силового поля ангара (до 4 человек) или вызвать его. Перелёт 10 с."],
	["teleporter", "Платформа телепорта", "Сюда инженер ставит найденный телепорт (редкая находка в хранилищах брошенных кораблей). E — через 2 с вы и до двух ботов «К оружию» рядом окажетесь на корабле у борта. Домой: правая кнопка мыши по себе. Перезарядка 20 с."],
	["pod", "Абордажная капсула", "В бою с пиратом у борта: E — сесть (2 места). Через 5 с летит к пирату, пробивает обшивку, и вы внутри. E у застрявшей капсулы — домой. Ботов с приказом «К оружию» зовёт на второе место."],
	["window_field", "Силовое поле ангара", "Держит воздух в ангаре, пропускает свет. За ним стоит челнок."],
	["bench", "Верстак", "Только инженер: разобрать, починить и улучшить орудия, топливо из лома и руды."],
	["bay", "Модульная стойка", "Инженер ставит сюда модули корабля из ящиков."],
	["autodoc", "Автодок", "Лечит того, кто лежит перед ним; сам после 50 здоровья — вдвое медленнее. Держите E у автодока: лечит вдвое быстрее и лечит травмы. Пока лечит, над лежащим мигает зелёный крест."],
	["scanner", "Сканер тела", "Показывает здоровье, раны и переломы того, кто лежит в автодоке (или ваши)."],
	["tray", "Гидропонный лоток", "Посадить семена, ухаживать, собрать урожай: еда для экипажа."],
	["stove", "Плита камбуза", "Готовит блюда из еды: сытнее, бодрее, лечебнее."],
	["cryo", "Криокапсула", "Здесь спит резерв экипажа. Погибший возвращается отсюда (R)."],
]

const DANGERS := [
	["Пробоина", "Воздух уходит, аварийные шлюзы отсека падают. Заделайте её заплаткой (держите E). Воздух вернут соседние отсеки."],
	["Нет воздуха", "Наденьте скафандр и включите подачу кислорода (Q). Полного баллона хватает на 2 минуты."],
	["Темнота", "Двигатель стоит, а СМЭС пуст: свет гаснет, машины встают. Чините двигатель, берите фонарик."],
	["Голод", "Каждый прыжок экипаж ест. Без еды слабеют, потом умирают. Еда: шкаф, лотки, торговцы."],
	["Пираты", "Стреляют по кораблю и высаживают абордаж. Щит, орудия, оружие в руках, тревога на мостике."],
	["Метеоры и ионный шторм", "Метеоры летят в корпус: пилот уводит корабль (уклонение пробелом заранее), орудия разбивают их, поднятый щит останавливает. Шторм гасит системы. Облетайте их по карте."],
	["Корпус", "Каждое попадание снимает прочность. Её латают снаружи, в скафандре (держите E у обшивки)."],
	["Смерть", "Тело остаётся на корабле. R: вернуться новым членом экипажа из резерва."],
]

const ROAD := [
	["Цель", "Пройти дорогу скоплений и разбить флагман пиратов в его логове."],
	["Прыжок", "На пульте управления: выбрать соседнюю систему и прыгнуть. Каждый прыжок стоит топлива и еды."],
	["Скопления", "Из скопления два выхода, назад пути нет. Каждое следующее опаснее."],
	["Деньги", "Лом с обломков, руда, данные сканирования, задания. Торговцы продают и покупают."],
	["Экипаж", "Каждое место в экипаже занято ботом, игрок занимает место бота. Приказы ботам: O."],
]

var _pages: TabContainer
var _built := false


func setup() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(760, 520)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	style.border_color = Color(0.45, 0.65, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)


func toggle() -> void:
	if not _built:
		_build()
	visible = not visible


func show_tab(tab: int) -> void:
	if _built:
		_pages.current_tab = clampi(tab, 0, _pages.get_tab_count() - 1)


func _build() -> void:
	_built = true
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "Книга помощи"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Закрыть (%s или Esc)" % Options.key_text("help")
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	_pages = TabContainer.new()
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_pages)
	_page("Управление", _keys())
	var machines: Array = []
	var tiles: Texture2D = Sprites.sheet("tiles")
	var ids := _tile_ids()
	for m: Array in MACHINES:
		var tex := AtlasTexture.new()
		tex.atlas = tiles
		var id: int = ids.get(m[0], 0)
		tex.region = Rect2((id % 8) * 32, (id / 8) * 32, 32, 32)
		machines.append([tex, m[1], m[2]])
	_page("Машины", machines)
	var things: Array = []
	for c: Array in Items.CATEGORIES:
		for item: int in c[1]:
			var new := Items.loaded(item) if Items.rounds(item) == 0 else item
			if Items.name_of(new) != "" and Items.about(new) != "":
				things.append([new, Items.name_of(new), Items.about(new)])
	_page("Вещи", things)
	_page("Опасности", DANGERS)
	_page("Путь", ROAD)


func _keys() -> Array:
	var k := func(action: String) -> String: return "[%s]" % Options.key_text(action)
	return [
		["Ходить", "%s %s %s %s. Две клавиши сразу: по диагонали (шаг в 1,4 раза дольше). Отпустите клавишу, и персонаж встанет где угодно, хоть на четверть клетки." % [k.call("move_up"), k.call("move_left"), k.call("move_down"), k.call("move_right")]],
		["Лечь", "%s: лечь или встать (встать — секунда). Лёжа ползёшь вдвое медленнее, пули летят над тобой, если стреляют не в тебя. Стоящего рядом с тобой союзника твои пули не задевают." % k.call("lie")],
		["Держать позицию", "%s: стоять стеной. Пока держите позицию, сквозь вашу клетку никто не пройдёт (пираты обходят), а свои стреляют мимо вас: можно встать строем и вести огонь в одну сторону. Любой шаг отпускает позицию." % k.call("hold")],
		["Действие", "%s: то, что перед вами (пульт, шкаф, лестница, поднять). Держать %s: работа (чинить, заделать, залить, взломать)." % [k.call("use"), Options.key_text("use")]],
		["Ступени", "Тёмные ступени ведут вниз, светлые вверх: просто пройдите по ним, руки не нужны."],
		["Мышь", "Щелчок по вещи рядом: как E. Правый щелчок: меню всего, что можно сделать. Ctrl + колесо: масштаб."],
		["Вещь в руке", "1–6 или колесо: что в руке. %s: применить (надеть, фонарик, лечить себя). %s: положить." % [k.call("act"), k.call("drop")]],
		["Кислород", "%s: подача кислорода из баллона скафандра." % k.call("suit")],
		["Тащить", "%s: тащить лежащего или отпустить." % k.call("drag")],
		["Окна", "%s: инвентарь. %s: экипаж и приказы ботам. %s: сведения о корабле. %s: эта книга." % [k.call("inventory"), k.call("crew"), k.call("info"), k.call("help")]],
		["Речь", "%s: чат. «;» в начале: рация, «!»: интерком у панели. %s: сразу в рацию." % [k.call("chat"), k.call("radio")]],
		["После гибели", "%s: вернуться из резерва новым членом экипажа." % k.call("respawn")],
	]


func _page(name: String, rows: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pages.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for r: Array in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		if r.size() == 3:
			row.add_child(_picture(r[0]))
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text = "[b]%s[/b]\n%s" % [r[r.size() - 2], r[r.size() - 1]]
		row.add_child(text)


func _picture(what: Variant) -> Control:
	if what is Texture2D:
		var pic := TextureRect.new()
		pic.texture = what
		pic.custom_minimum_size = Vector2(PIC, PIC)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return pic
	var item := int(what)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(PIC, PIC)
	icon.draw.connect(func() -> void: ItemArt.draw(icon, Rect2(Vector2(4, 4), Vector2(PIC - 8, PIC - 8)), item))
	return icon


static func _tile_ids() -> Dictionary:
	var out := {}
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/tiles.json"))
	if data is Dictionary:
		for t: Dictionary in data.get("tiles", []):
			out[str(t["name"])] = int(t["id"])
	return out
