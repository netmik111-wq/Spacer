extends VBoxContainer
## The trader's screen (v49, the author's request), opened from the supply
## locker while the ship is docked with a trader. Its goods are sorted into
## categories down the left (Items.CATEGORIES, and the trader's services);
## each row shows a thing, how many the locker holds, what the trader asks for
## it and what it pays for one of ours. Selling is from the locker: a thing we
## carry is put in first. Shown inside the console frame of GameScreen in place
## of the store's screen; `back` returns to it.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sectors := preload("res://src/shared/sectors.gd")

const ALL := -1
const SERVICES := -2
const ICON := 34.0
const LIST := Vector2(700, 330)
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const GOOD := Color(0.45, 0.85, 0.55)
const WARN := Color(0.95, 0.75, 0.3)

var client: GameClient
var back: Callable                   # set by GameScreen: back to the store's screen
var _credits: Label
var _cats: VBoxContainer
var _cat_buttons := {}               # category (index in Items.CATEGORIES, ALL or SERVICES) -> Button
var _rows: VBoxContainer
var _about: Label
var _cat := ALL
var _shown := ""


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	var to_store := Button.new()
	to_store.text = "◂ Шкаф снабжения"
	to_store.focus_mode = Control.FOCUS_NONE
	to_store.pressed.connect(func() -> void: back.call())
	head.add_child(to_store)
	_credits = Label.new()
	_credits.add_theme_font_size_override("font_size", 16)
	_credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_credits)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	_cats = VBoxContainer.new()
	_cats.custom_minimum_size = Vector2(190, 0)
	_cats.add_theme_constant_override("separation", 4)
	body.add_child(_cats)
	_cat_button(ALL, "Всё")
	for k in Items.CATEGORIES.size():
		_cat_button(k, Items.CATEGORIES[k][0])
	_cat_button(SERVICES, "Услуги и улучшения")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = LIST
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)
	_about = Label.new()
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(LIST.x + 202, 40)
	_about.add_theme_font_size_override("font_size", 13)
	add_child(_about)


func _cat_button(k: int, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		_cat = k
		_shown = "")
	_cats.add_child(b)
	_cat_buttons[k] = b


func refresh() -> void:
	## Called every frame while the screen is shown: rebuilt only when something changed.
	var sig := "%d|%d|%s|%s|%d|%s|%d|%d|%d|%d|%d" % [_cat, client.credits, str(client.store), str(client.trade), client.trade_flags, str(client.trade_back),
		client.hull, client.reserve, roundi(client.store_air), client.shield_flags, 1 if client.can_trade() else 0]
	if sig == _shown:
		return
	_shown = sig
	_credits.text = "Торговец: %s · Кредиты: %d" % [Sectors.DEAL_NAMES[client.trade_deal], client.credits]
	for k: int in _cat_buttons.keys():
		(_cat_buttons[k] as Button).set_pressed_no_signal(k == _cat)
	for old in _rows.get_children():
		old.queue_free()
	if not client.can_trade() or client.trade.is_empty():
		_note("Торговца рядом нет: торговать можно, пристыковавшись к нему, и только с питанием.")
		_about.text = ""
		return
	if _cat == SERVICES:
		_services()
	else:
		var any := false
		for k in Items.CATEGORIES.size():
			if _cat != ALL and _cat != k:
				continue
			var things: Array = []
			for item: int in Items.CATEGORIES[k][1]:
				if client.trade.has(item) or client.stock(item) > 0:
					things.append(item)
			if things.is_empty():
				continue
			any = true
			if _cat == ALL:
				_caption(Items.CATEGORIES[k][0])
			for item: int in things:
				_thing_row(item)
		if _cat == ALL and not client.trade_back.is_empty():
			_caption("Выкупить проданное")
			_buy_back()
		if _cat == ALL:
			_caption("Услуги и улучшения")
			_services()
		elif not any:
			_note("В этой категории торговцу нечего продать, а у нас в шкафу нечего ему предложить.")
	_about.text = "Это %s: %s. Купленное ложится в шкаф снабжения (корабельное оружие и боеприпасы: в трюм, ставят их с пульта орудий). Каждое орудие и каждый модуль у торговца один: купили, и его больше нет. Модули в ящиках ставит инженер (ящик в руке, держать E у машины или модульной стойки). Продаётся только то, что лежит в шкафу: свои вещи сначала положите в шкаф. Проданное можно выкупить у того же торговца за ту же цену." % [
		Sectors.DEAL_NAMES[client.trade_deal], Sectors.DEAL_ABOUT[client.trade_deal]]


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(LIST.x - 20, 0)
	l.add_theme_color_override("font_color", DIM)
	_rows.add_child(l)


func _caption(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", WARN)
	_rows.add_child(l)


func _row(item: int, title: String, detail: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(LIST.x - 20, ICON + 4)
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(func() -> void: _about.text = tip)
	_rows.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item != Net.ITEM_NONE:
		icon.draw.connect(func() -> void:
			icon.draw_rect(Rect2(Vector2.ZERO, Vector2(ICON, ICON)), Color(0.08, 0.09, 0.11))
			ItemArt.draw(icon, Rect2(Vector2.ZERO, Vector2(ICON, ICON)), item))
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name := Label.new()
	name.text = title
	name.add_theme_font_size_override("font_size", 14)
	text.add_child(name)
	var more := Label.new()
	more.text = detail
	more.add_theme_font_size_override("font_size", 11)
	more.add_theme_color_override("font_color", DIM)
	text.add_child(more)
	return row


func _button(row: HBoxContainer, text: String, on: bool, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not on
	b.custom_minimum_size = Vector2(130, 0)
	b.pressed.connect(action)
	row.add_child(b)


func _thing_row(item: int) -> void:
	var have := client.stock(item)
	var price: int = client.trade.get(item, 0)
	var w := Weapons.of_item(item)
	var share := client.trade_shares[1] if w != Weapons.NONE else (client.trade_shares[2] if _ammo(item) else client.trade_shares[0])
	var sell := Weapons.sell_price(Items.price(item), share / 100.0)
	var detail := "в шкафу: %d" % have
	if w != Weapons.NONE:
		detail = "в трюме: %d · энергия %d · заряд %d с · урон %d" % [have, Weapons.power(w), int(Weapons.info(w)["charge"]), int(Weapons.info(w)["damage"])]
		if Weapons.fx_of(item) != Weapons.FX_NONE:
			detail += " · " + Weapons.fx_name(Weapons.fx_of(item))
	var row := _row(item, Items.name_of(item), detail, "%s. %s" % [Items.name_of(item), Items.about(item)])
	_button(row, ("Купить: %d кр." % price) if price > 0 else "Нет в продаже", price > 0 and client.credits >= price,
		func() -> void: client.send_store(Net.STORE_BUY, item))
	_button(row, ("Продать: %d кр." % sell) if sell > 0 else "Не купит", have > 0 and sell > 0,
		func() -> void: client.send_store(Net.STORE_SELL, item))


func _services() -> void:
	var row := _row(Net.ITEM_NONE, "Воздух для установки +%d" % int(Net.AIR_LOT), "запас: %d из %d" % [roundi(client.store_air), int(Net.STORE_AIR_FULL)],
		"Пополняет запас воздушной установки.")
	_button(row, "Купить: %d кр." % Net.PRICE_AIR, client.credits >= Net.PRICE_AIR and client.store_air < Net.STORE_AIR_FULL,
		func() -> void: client.send_store(Net.STORE_BUY_AIR))
	row = _row(Net.ITEM_NONE, "Ремонт обшивки +%d" % Net.HULL_LOT, "прочность: %d из %d" % [client.hull, client.hull_max],
		"Латает обшивку корабля: прочность корпуса растёт.")
	_button(row, "Купить: %d кр." % Net.PRICE_HULL, client.credits >= Net.PRICE_HULL and client.hull < client.hull_max,
		func() -> void: client.send_store(Net.STORE_BUY_HULL))
	row = _row(Net.ITEM_NONE, "Нанять члена экипажа", "в резерве: %d из %d" % [client.reserve, Net.RESERVE_MAX],
		"Ещё одна жизнь: погибший игрок вернётся новым членом экипажа из резерва.")
	_button(row, "Нанять: %d кр." % Net.PRICE_CREW, client.credits >= Net.PRICE_CREW and client.reserve < Net.RESERVE_MAX,
		func() -> void: client.send_store(Net.STORE_HIRE))
	if (client.trade_flags & Net.TRADE_HARDEN) != 0:
		# (before v59 a trader could offer the hardening; it is now the top shield generator, «Эгида»)
		var hardened := (client.shield_flags & Net.SHF_HARDENED) != 0
		row = _row(Net.ITEM_NONE, "Закалка щита (редкое улучшение)", "уже установлена" if hardened else "этот торговец её предлагает",
			"Щит начинает останавливать и ракеты (обычные и ЭМИ), как лазеры. Ставится один раз и навсегда.")
		_button(row, "Купить: %d кр." % Weapons.SHIELD_HARDEN_PRICE, not hardened and client.credits >= Weapons.SHIELD_HARDEN_PRICE,
			func() -> void: client.send_store(Net.STORE_HARDEN))


static func _ammo(item: int) -> bool:
	return item == Net.ITEM_ROCKET or item == Net.ITEM_EMP_ROCKET or item == Net.ITEM_SHELL \
		or (item >= Net.ITEM_GUN_PARTS and item < Net.ITEM_GUN_PARTS + Weapons.KINDS)


func _buy_back() -> void:
	## (v58) What we sold this trader, to be bought back at the price it paid.
	var seen := {}
	for e: Array in client.trade_back:
		var item: int = e[0]
		var price: int = e[1]
		var key := "%d:%d" % [item, price]
		if seen.has(key):
			continue
		seen[key] = true
		var n := client.trade_back.filter(func(x: Array) -> bool: return int(x[0]) == item and int(x[1]) == price).size()
		var row := _row(item, Items.name_of(item), "продано вами: %d · выкуп по той же цене" % n,
			"%s. Проданное этому торговцу можно выкупить за ту же цену, по которой он его купил." % Items.name_of(item))
		_button(row, "Выкупить: %d кр." % price, client.credits >= price, func() -> void: client.send_store(Net.STORE_BUY_BACK, item))
