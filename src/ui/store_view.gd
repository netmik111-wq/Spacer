extends VBoxContainer
## The supply locker's screen: the ship's whole store at a glance. The ship's
## resources across the top (credits, fuel, air for the air plant, the hull,
## the crew reserve), then every thing the locker keeps as a card with its
## picture, how many there are and how many we carry, grouped by what it is for;
## under them what our character carries, and what a trader offers when one is
## alongside. A click on a card takes one, a right click buys one from a trader;
## a click on one of our own things puts it back. While a trader is alongside
## a button opens the trader's screen (TradeView). Shown inside the console
## frame of GameScreen while our character stands at the locker.
##
## (v65) The cards are sorted into tabs (TABS), and a group too long for one row
## wraps onto the next, so the screen keeps one width (WIDTH) however much the
## locker holds; the cards scroll in an area as high as the window allows.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const CARD := Vector2(80, 92)
const CARD_GAP := 6.0
const GROUP_GAP := 22.0
const PER_ROW := 10                  # cards in a full row
const WIDTH := PER_ROW * (CARD.x + CARD_GAP) - CARD_GAP
const CAPTION := 18.0                # a group's caption above its cards
const LINE_GAP := 8.0                # between lines of groups
const CARDS_HIGH := 400.0            # the cards scroll beyond this (less in a low window)
const CARDS_LOW := 220.0             # ... but never less
const AROUND := 430.0                # what the rest of the console frame takes of the window's height
const ICON := 40.0
const SLOT := 46.0
const SLOT_GAP := 6.0
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const GOOD := Color(0.45, 0.85, 0.55)
const WARN := Color(0.95, 0.75, 0.3)
const BAD := Color(0.95, 0.4, 0.35)
# (the groups of cards are Items.CATEGORIES; anything the locker keeps that is in none goes last.
# (v58) Ship weapons and gun parts show only what the cargo holds: there are too many kinds to show them all.)
const ONLY_HELD: Array[String] = ["Корабельное оружие", "Детали орудий", "Семена", "Задания"]
# (v65) The tabs: a caption and the groups (Items.CATEGORIES captions) in it; the first shows all.
# Groups no tab names (and «Прочее») go to the last one.
const TABS := [
	["Всё", []],
	["Припасы", ["Ремонт и топливо", "Провизия", "Медицина", "Добыча"]],
	["Снаряжение", ["Снаряжение", "Личное оружие"]],
	["Орудия", ["Корабельное оружие", "Боеприпасы", "Детали орудий"]],
	["Модули", ["Модули корабля"]],
	["Разведка и охрана", ["Разведка", "Охрана"]],
	["Семена и задания", ["Семена", "Задания"]],
]
const ALL_HELD := "Модули корабля"   # in the «Всё» tab this group, too, shows only what is held

var client: GameClient
var _gauges: Control
var _cards: Control
var _about: Label
var _mine: Control
var _trade_box: HBoxContainer
var _put_all: Button
var _trade: Button
var open_trade: Callable             # set by GameScreen: shows the trader's screen
var _groups: Array = []              # [caption, PackedInt32Array of things, where its caption is, Array of where each card is], as shown
var _tab := 0                        # (v65) the tab shown (TABS)
var _tabs: Array[Button] = []
var _tall := 0.0                     # how high the cards' canvas is
var _window_high := -1.0             # the window's height the scrolling area was sized for
var _hover := -1                     # the thing under the mouse (a card), or -1
var _hover_slot := -1                # our own slot under the mouse, or -1
var _shown := PackedByteArray()
var _scroll: ScrollContainer
var _held := ""                      # (v58) the kinds held, as the cards were laid out for


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	_lay_out()
	_gauges = _canvas(Vector2(WIDTH, 50), _draw_gauges)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == _tab
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_pressed_color", WARN)
		b.add_theme_color_override("font_hover_pressed_color", WARN)
		b.pressed.connect(_show_tab.bind(i))
		bar.add_child(b)
		_tabs.append(b)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_cards = _canvas(Vector2(WIDTH, 0), _draw_cards)
	_cards.reparent(_scroll)
	_size_cards()
	_cards.gui_input.connect(_on_cards_input)
	_cards.mouse_exited.connect(func() -> void: _hover = -1)
	_about = Label.new()
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(WIDTH, 40)
	_about.add_theme_font_size_override("font_size", 13)
	add_child(_about)
	_mine = _canvas(Vector2(WIDTH, SLOT + 22.0), _draw_mine)
	_mine.gui_input.connect(_on_mine_input)
	_mine.mouse_exited.connect(func() -> void: _hover_slot = -1)
	_trade_box = HBoxContainer.new()
	_trade_box.add_theme_constant_override("separation", 8)
	add_child(_trade_box)
	_put_all = _button("Положить всё обратно", func() -> void: client.send_store(Net.STORE_PUT_BACK))
	_trade = _button("Торговля: купить и продать…", func() -> void: open_trade.call())


func _held_now() -> String:
	var out := PackedStringArray()
	for item: int in client.store.keys():
		if client.stock(item) > 0:
			out.append(str(item))
	out.sort()
	return ",".join(out)


func _show_tab(i: int) -> void:
	if i == _tab:
		return
	_tab = i
	_lay_out()
	_size_cards()
	_scroll.scroll_vertical = 0
	_hover = -1
	_shown = PackedByteArray()


func _in_tab(caption: String) -> bool:
	if _tab == 0:
		return true
	if (TABS[_tab][1] as Array).has(caption):
		return true
	if _tab != TABS.size() - 1:
		return false
	for t: Array in TABS:
		if (t[1] as Array).has(caption):
			return false
	return true                          # a group no tab names goes to the last


func _lay_out() -> void:
	## The groups of cards in the tab shown and where each card is: the groups flow
	## left to right, onto a new line when the next would not fit; a group longer
	## than a whole line wraps its cards onto more rows.
	_held = _held_now() if client != null else ""
	_groups = []
	var placed := {}
	var kept := Items.kept_in_locker()
	for g: Array in Items.CATEGORIES:
		var things := PackedInt32Array()
		var held_only: bool = ONLY_HELD.has(g[0]) or (_tab == 0 and g[0] == ALL_HELD)
		for item: int in g[1]:
			if held_only and (ONLY_HELD.has(g[0]) or kept.has(item)):
				placed[item] = true
				if client.stock(item) > 0:
					things.append(item)
			elif kept.has(item):
				things.append(item)
				placed[item] = true
		if not things.is_empty() and _in_tab(g[0]):
			_groups.append([g[0], things])
	var rest := PackedInt32Array()
	for item in kept:
		if not placed.has(item):
			rest.append(item)
	if not rest.is_empty() and _in_tab("Прочее"):
		_groups.append(["Прочее", rest])
	var x := 0.0
	var y := 0.0
	var line := 0.0                      # how high the line of groups so far is
	for g: Array in _groups:
		var w := _group_width(g)
		if x > 0.0 and x + w > WIDTH:
			x = 0.0
			y += line + LINE_GAP
			line = 0.0
		var cards: Array[Vector2] = []
		var at := Vector2(x, y + CAPTION)
		for k in (g[1] as PackedInt32Array).size():
			if at.x + CARD.x > WIDTH + 0.5:
				at = Vector2(x, at.y + CARD.y + CARD_GAP)
			cards.append(at)
			at.x += CARD.x + CARD_GAP
		g.append(Vector2(x, y))
		g.append(cards)
		line = maxf(line, at.y + CARD.y - y)
		x = WIDTH if w > WIDTH else x + w + GROUP_GAP    # (a wrapped group ends its line)
	_tall = y + line + 4.0 if not _groups.is_empty() else 40.0


func _size_cards() -> void:
	var window := get_viewport().get_visible_rect().size.y if is_inside_tree() else 720.0
	_window_high = window
	var high := clampf(window - AROUND, CARDS_LOW, CARDS_HIGH)
	_scroll.custom_minimum_size = Vector2(WIDTH + 14.0, high)
	_cards.custom_minimum_size = Vector2(WIDTH, _tall)


func _group_width(g: Array) -> float:
	return (g[1] as PackedInt32Array).size() * (CARD.x + CARD_GAP) - CARD_GAP


func _canvas(size: Vector2, draw: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.draw.connect(draw)
	add_child(c)
	return c


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_trade_box.add_child(b)
	return b


func refresh() -> void:
	## Called every frame while the screen is shown.
	var trading := client.can_trade()
	if _held_now() != _held:
		_lay_out()
		_size_cards()
		_shown = PackedByteArray()
	if get_viewport().get_visible_rect().size.y != _window_high:
		_size_cards()                    # the window was resized: fit the frame to it again
		var frame := get_parent().get_parent() as Control
		if frame != null:
			frame.reset_size()
	var now := PackedByteArray([client.credits & 0xFF, client.credits >> 8, client.hull, client.reserve,
		roundi(client.store_air), 1 if trading else 0, client.hand, _hover + 1, _hover_slot + 1, client.fuel & 0xFF, client.fuel >> 8])
	for item: int in client.store.keys():
		now.append(client.stock(item) & 0xFF)
	now.append_array(client.slots)
	now.append_array(client.worn)
	if now == _shown:
		return
	_shown = now
	_gauges.queue_redraw()
	_cards.queue_redraw()
	_mine.queue_redraw()
	var keeps_any := false
	for item in Items.kept_in_locker():
		keeps_any = keeps_any or client.carried(item) > 0
	for thing in client.slots:
		keeps_any = keeps_any or (thing != Net.ITEM_NONE and Items.cargo(thing))     # (v58) a gun carried in from a wreck
	_put_all.disabled = not keeps_any
	_trade.visible = trading
	_about.text = _about_text(trading)


func _about_text(trading: bool) -> String:
	var lines := PackedStringArray()
	if _hover >= 0:
		var line := "%s. %s В шкафу: %d, у вас: %d." % [Items.name_of(_hover), Items.about(_hover), client.stock(_hover), client.carried(_hover)]
		if trading and client.trade.has(_hover):
			line += " У торговца: %d кр. (правый щелчок)." % client.trade[_hover]
		if Items.carried_gun(_hover):
			line += " Корабельное орудие (щелчок: взять): его несут к орудию в корпусе и ставят, держа E%s." % (
				"; приказ, что куда ставить, даёт пульт орудий" if not Weapons.damaged(_hover) else ", но сначала его чинят на верстаке")
		elif Items.carried_round(_hover):
			line += " Груз корабля, но его можно взять (щелчок) и зарядить в орудие вручную, держа E у орудия."
		elif Items.cargo(_hover):
			var gun := Weapons.of_item(_hover) != Weapons.NONE
			line += " Это груз корабля: из шкафа не берётся%s." % (", ставится с пульта орудий" if gun else "")
		lines.append(line)
	elif _hover_slot >= 0 and client.slots[_hover_slot] != Net.ITEM_NONE:
		var thing := client.slots[_hover_slot]
		if not client.store.has(Items.kind_of(thing)) and not Items.cargo(thing):
			lines.append("%s: шкаф такое не хранит." % Items.name_of(thing))
		elif not Items.whole(thing):
			lines.append("%s: начатое назад не кладут." % Items.name_of(thing))
		else:
			lines.append("%s: щелчок, чтобы положить в шкаф." % Items.name_of(thing))
	else:
		lines.append("Щелчок по карточке: взять одну (в руку, если она пуста). Щелчок по своей вещи внизу: положить её в шкаф.")
	if trading:
		lines.append("Торговец на связи: правый щелчок по карточке покупает одну; продать и купить остальное: кнопка «Торговля».")
	elif client.sectors.count > 0 and client.sectors.kind[client.sector] == Sectors.TRADER:
		lines.append("Торговец в этом секторе. Чтобы покупать, %s." % ("подойдите к нему" if client.powered() else "нужно питание"))
	else:
		lines.append("Докупить запас можно у торговца; воздух для установки бесплатно пополняет станция снабжения.")
	return "\n".join(lines)


# ---------------------------------------------------------------- the ship's resources

func _draw_gauges() -> void:
	var font := ThemeDB.fallback_font
	var w := (_gauges.size.x - 4 * 12.0) / 5.0
	var fuel := client.stock(Net.ITEM_FUEL)
	var gauges := [
		["Кредиты", str(client.credits), -1.0, INK],
		# (v67) the tank, in units; how many lane jumps it holds, and cans in the locker
		["Топливо: прыжков %d, %s" % [client.fuel / maxi(client.jump_cost, 1), "%d %s" % [fuel, _jumps(fuel)]],
			"%d из %d" % [client.fuel, client.fuel_max], float(client.fuel) / maxf(client.fuel_max, 1.0), Color()],
		["Воздух установки", "%d из %d" % [int(round(client.store_air)), int(Net.STORE_AIR_FULL)], client.store_air / Net.STORE_AIR_FULL, Color()],
		["Обшивка", "%d из %d" % [client.hull, client.hull_max], float(client.hull) / client.hull_max, Color()],
		["Резерв экипажа", "%d из %d" % [client.reserve, Net.RESERVE_MAX], float(client.reserve) / Net.RESERVE_MAX, Color()],
	]
	for i in gauges.size():
		var g: Array = gauges[i]
		var box := Rect2(Vector2(i * (w + 12.0), 0), Vector2(w, 46))
		_gauges.draw_rect(box, Color(0.08, 0.1, 0.12, 0.9))
		_gauges.draw_rect(box, Color(0.3, 0.4, 0.45, 0.8), false, 1.0)
		_gauges.draw_string(font, box.position + Vector2(8, 15), g[0], HORIZONTAL_ALIGNMENT_LEFT, w - 16, 12, DIM)
		var share: float = g[2]
		if share >= 0.0:
			var colour := GOOD if share > 0.5 else (WARN if share > 0.2 else BAD)
			var bar := Rect2(box.position + Vector2(8, 24), Vector2(w - 16, 8))
			_gauges.draw_rect(bar, Color(0.15, 0.17, 0.2))
			_gauges.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(share, 0.0, 1.0), bar.size.y)), colour)
			_gauges.draw_string(font, box.position + Vector2(8, 43), g[1], HORIZONTAL_ALIGNMENT_LEFT, w - 16, 11, INK)
		else:
			_gauges.draw_string(font, box.position + Vector2(8, 38), g[1], HORIZONTAL_ALIGNMENT_LEFT, w - 16, 18, g[3])


static func _jumps(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "канистра"
	if n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14):
		return "канистры"
	return "канистр"


# ---------------------------------------------------------------- the cards

func _card(group: int, k: int) -> Rect2:
	return Rect2(_groups[group][3][k], CARD)


func _draw_cards() -> void:
	var font := ThemeDB.fallback_font
	var trading := client.can_trade()
	if _groups.is_empty():
		_cards.draw_string(font, Vector2(0, 20), "Здесь пока ничего нет.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	for g in _groups.size():
		_cards.draw_string(font, (_groups[g][2] as Vector2) + Vector2(0, 13.0), _groups[g][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		var things: PackedInt32Array = _groups[g][1]
		for k in things.size():
			var item := things[k]
			var r := _card(g, k)
			var n := client.stock(item)
			var lit := item == _hover
			_cards.draw_rect(r, Color(0.13, 0.15, 0.17, 0.95) if lit else Color(0.08, 0.09, 0.11, 0.95))
			_cards.draw_rect(r, Color(0.95, 0.8, 0.4) if lit else Color(0.35, 0.4, 0.48, 0.9), false, 2.0 if lit else 1.0)
			var icon := Rect2(r.position + Vector2((CARD.x - ICON) / 2.0, 8), Vector2(ICON, ICON))
			ItemArt.draw(_cards, icon, item)
			if n == 0:
				_cards.draw_rect(icon, Color(0.05, 0.05, 0.07, 0.6))
			var label := Items.name_of(item)
			if Weapons.of_item(item) != Weapons.NONE:
				label = ("× " if Weapons.damaged(item) else "") + Weapons.short_of(Weapons.of_item(item)) + \
					("+" if Weapons.fx_of(item) != Weapons.FX_NONE else "")
			if Items.is_seed(item):
				label = label.trim_prefix("Семена: ")       # (the group's caption says it)
				label = label.left(1).to_upper() + label.substr(1)
			var size := 12
			while size > 10 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > CARD.x - 4:
				size -= 1
			var lines := _two_lines(label) if font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > CARD.x - 4 else PackedStringArray([label])
			if lines.size() == 1:
				_cards.draw_string(font, r.position + Vector2(0, 8 + ICON + 15), label, HORIZONTAL_ALIGNMENT_CENTER, CARD.x, size, INK)
			else:
				for i in 2:              # (v65) a long name (the ship's gear) goes on two lines
					_cards.draw_string(font, r.position + Vector2(2, 8 + ICON + 12 + i * 12), lines[i], HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 4, 10, INK)
			_cards.draw_string(font, r.position + Vector2(6, 16), "×%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM if n == 0 else GOOD)
			var mine := client.carried(item)
			if mine > 0:
				_cards.draw_string(font, r.position + Vector2(0, 16), "у вас %d " % mine, HORIZONTAL_ALIGNMENT_RIGHT, CARD.x - 4, 10, DIM)
			if trading and client.trade.has(item):
				var afford := client.credits >= int(client.trade[item])
				_cards.draw_string(font, r.position + Vector2(0, CARD.y - 6), "%d кр." % client.trade[item], HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 11,
					WARN if afford else BAD)


static func _two_lines(label: String) -> PackedStringArray:
	## A name split at the space nearest its middle (the second line is cut if still too long).
	var best := -1
	for i in label.length():
		if label[i] == " " and (best < 0 or absi(i - label.length() / 2) < absi(best - label.length() / 2)):
			best = i
	if best < 0:
		return PackedStringArray([label])
	return PackedStringArray([label.substr(0, best), label.substr(best + 1)])


func _card_at(at: Vector2) -> int:
	for g in _groups.size():
		var things: PackedInt32Array = _groups[g][1]
		for k in things.size():
			if _card(g, k).has_point(at):
				return things[k]
	return -1


func _on_cards_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var now := _card_at((event as InputEventMouseMotion).position)
		if now != _hover:
			_hover = now
			_shown = PackedByteArray()
		return
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var click := event as InputEventMouseButton
	var item := _card_at(click.position)
	if item < 0:
		return
	if click.button_index == MOUSE_BUTTON_LEFT and client.stock(item) > 0 and (not Items.cargo(item) or Items.carried(item)):
		client.send_store(Net.STORE_TAKE, item)
	elif click.button_index == MOUSE_BUTTON_RIGHT and client.can_trade() and client.trade.has(item):
		client.send_store(Net.STORE_BUY, item)
	_cards.accept_event()


# ---------------------------------------------------------------- what we carry

func _slot(i: int) -> Rect2:
	return Rect2(Vector2(i * (SLOT + SLOT_GAP), 18.0), Vector2(SLOT, SLOT))


func _draw_mine() -> void:
	var font := ThemeDB.fallback_font
	var free := 0
	var open := 0
	for i in Net.SLOTS:
		if client.usable(i):
			open += 1
			if client.slots[i] == Net.ITEM_NONE:
				free += 1
	_mine.draw_string(font, Vector2(0, 13), "У вас при себе (свободно %d из %d)" % [free, open], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
	for i in Net.SLOTS:
		var r := _slot(i)
		if not client.usable(i):
			_mine.draw_rect(r, Color(0.05, 0.05, 0.07, 0.4))
			continue
		var thing := client.slots[i]
		var back := thing != Net.ITEM_NONE and (client.store.has(Items.kind_of(thing)) or Items.cargo(thing)) and Items.whole(thing)
		_mine.draw_rect(r, Color(0.07, 0.08, 0.12, 0.92))
		var edge := Color(0.98, 0.82, 0.35) if i == _hover_slot and back else (Color(0.4, 0.6, 0.45, 0.9) if back else Color(0.32, 0.35, 0.42, 0.9))
		_mine.draw_rect(r, edge, false, 2.0 if i == _hover_slot else 1.0)
		if thing != Net.ITEM_NONE:
			ItemArt.draw(_mine, r, thing)


func _on_mine_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var now := -1
		for i in Net.SLOTS:
			if _slot(i).has_point((event as InputEventMouseMotion).position) and client.usable(i):
				now = i
		if now != _hover_slot:
			_hover_slot = now
			_shown = PackedByteArray()
		return
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var click := event as InputEventMouseButton
	for i in Net.SLOTS:
		if _slot(i).has_point(click.position) and client.usable(i) and client.slots[i] != Net.ITEM_NONE:
			client.send_store(Net.STORE_PUT_ONE, i)
			_mine.accept_event()
			return
