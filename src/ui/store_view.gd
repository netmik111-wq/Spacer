extends VBoxContainer
## The supply locker's screen: the ship's whole store at a glance. The ship's
## resources across the top (credits, fuel, air for the air plant, the hull,
## the crew reserve), then every thing the locker keeps as a card with its
## picture, how many there are and how many we carry, grouped by what it is for;
## under them what our character carries, and what a trader offers when one is
## alongside. A click on a card takes one, a right click buys one from a trader;
## a click on one of our own things puts it back. Shown inside the console
## frame of GameScreen while our character stands at the locker.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")

const CARD := Vector2(92, 104)
const CARD_GAP := 8.0
const GROUP_GAP := 26.0
const MAX_WIDTH := 900.0
const ICON := 46.0
const SLOT := 46.0
const SLOT_GAP := 6.0
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const GOOD := Color(0.45, 0.85, 0.55)
const WARN := Color(0.95, 0.75, 0.3)
const BAD := Color(0.95, 0.4, 0.35)
# the groups of cards: caption, the things in it (anything the locker keeps that is in none goes last)
const GROUPS: Array = [
	["Ремонт и топливо", [Net.ITEM_PATCH, Net.ITEM_PART, Net.ITEM_FUEL]],
	["Снаряжение", [Net.ITEM_SUIT + Net.SUIT_TANK_STEPS, Net.ITEM_JUMPSUIT, Net.ITEM_BACKPACK, Net.ITEM_FLASHLIGHT, Net.ITEM_RADIO]],
	["Медицина", [Net.ITEM_MEDPATCH, Net.ITEM_MEDKIT + Net.MEDKIT_USES]],
	["Оружие", [Net.ITEM_PISTOL, Net.ITEM_MAG, Net.ITEM_BATON]],
]

var client: GameClient
var _gauges: Control
var _cards: Control
var _about: Label
var _mine: Control
var _trade_box: HBoxContainer
var _put_all: Button
var _trade_buttons := {}             # Net.STORE_* -> Button
var _groups: Array = []              # [caption, PackedInt32Array of things, where it starts on the cards' canvas], as shown
var _hover := -1                     # the thing under the mouse (a card), or -1
var _hover_slot := -1                # our own slot under the mouse, or -1
var _shown := PackedByteArray()


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	_groups = []
	var placed := {}
	var kept := Items.kept_in_locker()
	for g: Array in GROUPS:
		var things := PackedInt32Array()
		for item: int in g[1]:
			if kept.has(item):
				things.append(item)
				placed[item] = true
		_groups.append([g[0], things])
	var rest := PackedInt32Array()
	for item in kept:
		if not placed.has(item):
			rest.append(item)
	if not rest.is_empty():
		_groups.append(["Прочее", rest])
	# the groups flow left to right, onto a new row when the next would not fit
	var x := 0.0
	var row := 0
	for g: Array in _groups:
		var w := _group_width(g)
		if x > 0.0 and x + w > MAX_WIDTH:
			x = 0.0
			row += 1
		g.append(Vector2(x, row * (CARD.y + 24.0)))
		x += w + GROUP_GAP
	_gauges = _canvas(Vector2(_width(), 50), _draw_gauges)
	_cards = _canvas(Vector2(_width(), (row + 1) * (CARD.y + 24.0)), _draw_cards)
	_cards.gui_input.connect(_on_cards_input)
	_cards.mouse_exited.connect(func() -> void: _hover = -1)
	_about = Label.new()
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(_width(), 40)
	_about.add_theme_font_size_override("font_size", 13)
	add_child(_about)
	_mine = _canvas(Vector2(_width(), SLOT + 22.0), _draw_mine)
	_mine.gui_input.connect(_on_mine_input)
	_mine.mouse_exited.connect(func() -> void: _hover_slot = -1)
	_trade_box = HBoxContainer.new()
	_trade_box.add_theme_constant_override("separation", 8)
	add_child(_trade_box)
	_put_all = _button("Положить всё обратно", func() -> void: client.send_store(Net.STORE_PUT_BACK))
	for offer: Array in [[Net.STORE_BUY_AIR, "Воздух +%d: %d кр." % [int(Net.AIR_LOT), Net.PRICE_AIR]],
			[Net.STORE_BUY_HULL, "Обшивка +%d: %d кр." % [Net.HULL_LOT, Net.PRICE_HULL]],
			[Net.STORE_HIRE, "Нанять в резерв: %d кр." % Net.PRICE_CREW]]:
		var action: int = offer[0]
		_trade_buttons[action] = _button(offer[1], func() -> void: client.send_store(action))


func _group_width(g: Array) -> float:
	return (g[1] as PackedInt32Array).size() * (CARD.x + CARD_GAP) - CARD_GAP


func _width() -> float:
	var most := Net.SLOTS * (SLOT + SLOT_GAP) + 150.0
	for g: Array in _groups:
		if g.size() > 2:
			most = maxf(most, (g[2] as Vector2).x + _group_width(g))
	return most


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
	var now := PackedByteArray([client.credits & 0xFF, client.credits >> 8, client.hull, client.reserve,
		roundi(client.store_air), 1 if trading else 0, client.hand, _hover + 1, _hover_slot + 1])
	for item in Items.kept_in_locker():
		now.append(client.stock(item))
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
	_put_all.disabled = not keeps_any
	for action: int in _trade_buttons.keys():
		var b: Button = _trade_buttons[action]
		b.visible = trading
		match action:
			Net.STORE_BUY_AIR:
				b.disabled = client.credits < Net.PRICE_AIR or client.store_air >= Net.STORE_AIR_FULL
			Net.STORE_BUY_HULL:
				b.disabled = client.credits < Net.PRICE_HULL or client.hull >= Net.HULL_MAX
			Net.STORE_HIRE:
				b.disabled = client.credits < Net.PRICE_CREW or client.reserve >= Net.RESERVE_MAX
	_about.text = _about_text(trading)


func _about_text(trading: bool) -> String:
	var lines := PackedStringArray()
	if _hover >= 0:
		var line := "%s. %s В шкафу: %d, у вас: %d." % [Items.name_of(_hover), Items.about(_hover), client.stock(_hover), client.carried(_hover)]
		if trading and Items.price(_hover) > 0:
			line += " У торговца: %d кр. (правый щелчок)." % Items.price(_hover)
		lines.append(line)
	elif _hover_slot >= 0 and client.slots[_hover_slot] != Net.ITEM_NONE:
		var thing := client.slots[_hover_slot]
		if not client.store.has(Items.kind_of(thing)):
			lines.append("%s: шкаф такое не хранит." % Items.name_of(thing))
		elif not Items.whole(thing):
			lines.append("%s: начатое назад не кладут." % Items.name_of(thing))
		else:
			lines.append("%s: щелчок, чтобы положить в шкаф." % Items.name_of(thing))
	else:
		lines.append("Щелчок по карточке: взять одну (в руку, если она пуста). Щелчок по своей вещи внизу: положить её в шкаф.")
	if trading:
		lines.append("Торговец на связи: правый щелчок по карточке покупает одну.")
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
		["Топливо", "%d %s" % [fuel, _jumps(fuel)], -1.0, BAD if fuel == 0 else (WARN if fuel < 3 else INK)],
		["Воздух установки", "%d из %d" % [int(round(client.store_air)), int(Net.STORE_AIR_FULL)], client.store_air / Net.STORE_AIR_FULL, Color()],
		["Обшивка", "%d из %d" % [client.hull, Net.HULL_MAX], float(client.hull) / Net.HULL_MAX, Color()],
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
	return Rect2(_groups[group][2] + Vector2(k * (CARD.x + CARD_GAP), 18.0), CARD)


func _draw_cards() -> void:
	var font := ThemeDB.fallback_font
	var trading := client.can_trade()
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
			_cards.draw_string(font, r.position + Vector2(0, 8 + ICON + 15), Items.name_of(item), HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 12, INK)
			_cards.draw_string(font, r.position + Vector2(6, 16), "×%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM if n == 0 else GOOD)
			var mine := client.carried(item)
			if mine > 0:
				_cards.draw_string(font, r.position + Vector2(0, 16), "у вас %d " % mine, HORIZONTAL_ALIGNMENT_RIGHT, CARD.x - 4, 10, DIM)
			if trading and Items.price(item) > 0:
				var afford := client.credits >= Items.price(item)
				_cards.draw_string(font, r.position + Vector2(0, CARD.y - 8), "%d кр." % Items.price(item), HORIZONTAL_ALIGNMENT_CENTER, CARD.x, 11,
					WARN if afford else BAD)


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
	if click.button_index == MOUSE_BUTTON_LEFT and client.stock(item) > 0:
		client.send_store(Net.STORE_TAKE, item)
	elif click.button_index == MOUSE_BUTTON_RIGHT and client.can_trade() and Items.price(item) > 0:
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
		var back := thing != Net.ITEM_NONE and client.store.has(Items.kind_of(thing)) and Items.whole(thing)
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
