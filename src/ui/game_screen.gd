extends Node
## Everything shown while playing: the world, the HUD, chat and the pause
## panel. Reads the keyboard and tells the GameClient which way to walk.

signal exit_requested

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const WorldView := preload("res://src/client/world_view.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Director := preload("res://src/server/director.gd")   # only for the list of events in the host's menu

const MOVES := [["move_up", 1], ["move_down", 2], ["move_left", 3], ["move_right", 4]]
const CHAT_LINES := 9
const SLOT_PX := 34.0                # a slot of the inventory on screen
const SLOT_GAP := 4.0
const BIG_SLOT_PX := 60.0            # and in the search panel
const BIG_SLOT_GAP := 8.0
const HINT_LEFT := 550.0             # the hint line keeps clear of the chat (this far from the left edge)
const HINT_RIGHT := 250.0            # and of the instruments (this far from the right edge)
const CHAT_VISIBLE_SEC := 12.0        # a chat line stays this long, then fades
# when the lamps light, as shares of normal pressure (the damage itself is the server's: see vitals.gd)
const BREATH_MIN := 0.76
const PRESSURE_WARN := 0.5
const PRESSURE_MIN := 0.2
const NAME_COLOURS: Array[String] = ["ff6b5e", "6fa8ff", "6fd487", "f2c84b", "b98cf0", "f59a55", "5fd3e0", "e3e6ee"]

var client: GameClient
var hosting := false
var host_port := 0
var demo_walk := false               # test mode: wander without a keyboard
var forced_dir := -1                 # test mode: direction dictated by a script (-1 = off)
var forced_use := false              # test mode: the "use" key held by a script

var _world: WorldView
var _ui: CanvasLayer
var _info: Label
var _keys: Label
var _debug: Label
var _monitor: TextureRect
var _monitor_frames: Array = []       # per health state: Array[AtlasTexture]
var _alerts := {}                    # lamp name -> {"frames": Array[AtlasTexture], "seconds": float, "node": TextureRect}
var _alert_box: VBoxContainer
var _shade: ColorRect
var _blackout: ColorRect
var _fate: Label
var _tank_bar: ColorRect
var _tank_fill: ColorRect
var _hint: Label
var _work_bar: ColorRect
var _work_fill: ColorRect
var _use_held := false
var _console: PanelContainer         # the screen of a bridge console, shown over the game
var _console_kind := 0               # 3 = sector console, 4 = ship's controls (as GameClient.use_target)
var _console_title: Label
var _console_text: Label
var _chart: Control
var _jump_box: GridContainer
var _jump_buttons_for := -1          # what the jump buttons were last built for
var _console_shut: Button
var _store_buttons := {}             # the supply locker's buttons: Net.STORE_* -> Button
var _slots_view: Control             # what our character carries, slot by slot
var _slots_shown := PackedByteArray()
var _jump_label: Label
var _flash: ColorRect
var _monitor_step := 0.08
var _monitor_time := 0.0
var _chat_box: VBoxContainer
var _chat_lines: Array = []          # [RichTextLabel, time it was added]
var _chat_input: LineEdit
var _pause: PanelContainer
var _held: Array[int] = []
var _info_timer := 0.0
var _fps_smooth := 60.0
var _demo_until := 0.0
var _demo_dir := 0
var _rng := RandomNumberGenerator.new()


func setup(p_client: GameClient, p_hosting: bool, p_port: int) -> void:
	client = p_client
	hosting = p_hosting
	host_port = p_port
	client.chat.connect(_on_chat)
	client.notice.connect(_on_notice)

	_world = WorldView.new()
	add_child(_world)
	_world.setup(client)

	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_info = _text(top, 15)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_keys = _text(top, 13)
	_keys.text = "WASD: ходить    E: действие    F: тащить    Q: подача O2    Enter: чат    Esc: меню    F11: весь экран"
	_keys.modulate = Color(1, 1, 1, 0.75)

	_debug = _text(root, 13)
	_debug.position = Vector2(14, 40)
	_debug.visible = false

	# heartbeat monitor from the reference HUD (decorative until health exists)
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hud_monitor.json"))
	var sheet: Texture2D = load("res://assets/hud_monitor.png")
	if typeof(meta) == TYPE_DICTIONARY and sheet != null:
		var fw := int(meta["frame_width"])
		var fh := int(meta["frame_height"])
		_monitor_step = float(meta["frame_seconds"])
		for state in int(meta["states"]):
			var row: Array[AtlasTexture] = []
			for i in int(meta["frames"]):
				var frame := AtlasTexture.new()
				frame.atlas = sheet
				frame.region = Rect2(i * fw, state * fh, fw, fh)
				row.append(frame)
			_monitor_frames.append(row)
		_monitor = TextureRect.new()
		_monitor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_monitor.stretch_mode = TextureRect.STRETCH_SCALE
		_monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_monitor.texture = _monitor_frames[0][0]
		_monitor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_monitor.offset_left = -fw * 3 - 14
		_monitor.offset_top = -fh * 3 - 14
		_monitor.offset_right = -14
		_monitor.offset_bottom = -14
		root.add_child(_monitor)

		# warning lamps from the same HUD sheet, stacked above the monitor; lit only when something is wrong
		_alert_box = VBoxContainer.new()
		_alert_box.alignment = BoxContainer.ALIGNMENT_END
		_alert_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_alert_box.add_theme_constant_override("separation", 6)
		_alert_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_alert_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_alert_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_alert_box.offset_right = -14
		_alert_box.offset_bottom = -fh * 3 - 22
		root.add_child(_alert_box)
		var lamps: Texture2D = load("res://assets/hud_alerts.png")
		var described: Dictionary = meta.get("alerts", {})
		for lamp: String in ["kpa_low1", "kpa_low2", "o2_low", "o2_on", "o2_off"]:
			if not described.has(lamp) or lamps == null:
				continue
			var d: Dictionary = described[lamp]
			var frames: Array[AtlasTexture] = []
			for i in int(d["frames"]):
				var frame := AtlasTexture.new()
				frame.atlas = lamps
				frame.region = Rect2(int(d["x"]) + i * (int(d["w"]) + 1), 0, int(d["w"]), int(d["h"]))
				frames.append(frame)
			var node := TextureRect.new()
			node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			node.stretch_mode = TextureRect.STRETCH_SCALE
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.custom_minimum_size = Vector2(int(d["w"]), int(d["h"])) * 3
			node.size_flags_horizontal = Control.SIZE_SHRINK_END
			node.texture = frames[0]
			node.visible = false
			_alert_box.add_child(node)
			_alerts[lamp] = {"frames": frames, "seconds": float(d["frame_seconds"]), "node": node}

	# what our character carries, slot by slot, to the left of the instruments
	_slots_view = Control.new()
	_slots_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_view.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var slots_wide := Net.SLOTS * SLOT_PX + (Net.SLOTS - 1) * SLOT_GAP
	_slots_view.offset_right = -14 - 192 - 10 - 12 - 12
	_slots_view.offset_left = _slots_view.offset_right - slots_wide
	_slots_view.offset_bottom = -14
	_slots_view.offset_top = -14 - SLOT_PX
	_slots_view.draw.connect(func() -> void: _draw_slots(_slots_view, Vector2.ZERO, client.slots, SLOT_PX, SLOT_GAP))
	root.add_child(_slots_view)

	# how much oxygen the suit's tank holds: a bar drawn in code beside the monitor
	_tank_bar = ColorRect.new()
	_tank_bar.color = Color(0.13, 0.1, 0.19)
	_tank_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tank_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_tank_bar.offset_left = -14 - 192 - 10 - 12
	_tank_bar.offset_right = -14 - 192 - 10
	_tank_bar.offset_top = -14 - 96
	_tank_bar.offset_bottom = -14
	root.add_child(_tank_bar)
	_tank_fill = ColorRect.new()
	_tank_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tank_bar.add_child(_tank_fill)

	# what the "use" key would do here, and how far the work has got
	_hint = _text(root, 16)
	# it sits between the chat on the left and the instruments on the right, and wraps there
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = HINT_LEFT
	_hint.offset_right = -HINT_RIGHT
	_hint.offset_bottom = -92
	_hint.visible = false
	_work_bar = ColorRect.new()
	_work_bar.color = Color(0.08, 0.09, 0.13, 0.9)
	_work_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_work_bar.offset_left = -110
	_work_bar.offset_right = 110
	_work_bar.offset_top = -84
	_work_bar.offset_bottom = -70
	_work_bar.visible = false
	root.add_child(_work_bar)
	_work_fill = ColorRect.new()
	_work_fill.color = Color(0.95, 0.75, 0.3)
	_work_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_work_fill.position = Vector2(2, 2)
	_work_fill.size = Vector2(0, 10)
	_work_bar.add_child(_work_fill)

	# without power the ship is on emergency lighting: everything but our own instruments dims
	_blackout = ColorRect.new()
	_blackout.color = Color(0.03, 0.0, 0.06, 0.0)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_blackout)
	root.move_child(_blackout, 0)
	# the screen goes dark as our character fades, and says so when it is down
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_shade)
	root.move_child(_shade, 0)
	_fate = _text(root, 22)
	_fate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fate.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_fate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fate.offset_top = 96
	_fate.visible = false

	_chat_box = VBoxContainer.new()
	_chat_box.alignment = BoxContainer.ALIGNMENT_END
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_box.add_theme_constant_override("separation", 2)
	_chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_box.offset_left = 14
	_chat_box.offset_right = 540
	_chat_box.offset_top = -330
	_chat_box.offset_bottom = -52
	root.add_child(_chat_box)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Сообщение… (Enter: отправить, Esc: отмена)"
	_chat_input.max_length = Net.MAX_CHAT
	_chat_input.visible = false
	_chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.offset_left = 14
	_chat_input.offset_right = 520
	_chat_input.offset_top = -46
	_chat_input.offset_bottom = -14
	_chat_input.text_submitted.connect(_on_chat_submitted)
	root.add_child(_chat_input)

	_build_console(root)
	_build_pause(root)

	# a jump: the countdown, and a white flash on landing
	_jump_label = _text(root, 18)
	_jump_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_jump_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_jump_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_jump_label.offset_top = 56
	_jump_label.modulate = Color(0.7, 0.9, 1.0)
	_jump_label.visible = false
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.93, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_flash)
	client.arrived.connect(func() -> void: _flash.color.a = 0.9)
	_rng.randomize()
	_say("[color=#9aa3b5]Вы на борту. Нажмите Enter, чтобы написать в чат.[/color]")


func _text(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _build_console(root: Control) -> void:
	_console = PanelContainer.new()
	_console.visible = false
	_console.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_console.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_console.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.08, 0.97)
	style.border_color = Color(0.3, 0.75, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	_console.add_theme_stylebox_override("panel", style)
	root.add_child(_console)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_console.add_child(box)
	_console_title = Label.new()
	_console_title.add_theme_font_size_override("font_size", 20)
	_console_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_console_title)
	_chart = Control.new()
	_chart.custom_minimum_size = Vector2(640, 300)
	_chart.draw.connect(_draw_chart)
	_chart.gui_input.connect(_on_chart_input)
	box.add_child(_chart)
	_console_text = Label.new()
	_console_text.add_theme_font_size_override("font_size", 14)
	_console_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_console_text.custom_minimum_size = Vector2(640, 0)
	box.add_child(_console_text)
	_jump_box = GridContainer.new()
	_jump_box.columns = 2
	_jump_box.add_theme_constant_override("h_separation", 8)
	_jump_box.add_theme_constant_override("v_separation", 6)
	box.add_child(_jump_box)
	_console_shut = Button.new()
	_console_shut.pressed.connect(func() -> void: _open_console(0))
	box.add_child(_console_shut)


func _opens_panel(target: int) -> bool:
	## Does the "use" key open a screen for this thing (see GameClient.use_target)?
	## The bridge consoles need power; the supply locker is opened by hand.
	return target == 12 or ((target == 3 or target == 4) and client.powered())


func _open_console(kind: int) -> void:
	if _console_kind == 13 and kind != 13 and client.search_id >= 0:
		client.send_search(Net.NOBODY)       # we step back from the one we were searching
		client.search_id = -1
	_console_kind = kind
	_console.visible = kind != 0
	if kind == 0:
		return
	_close_chat()
	_jump_buttons_for = -1
	_store_buttons.clear()
	_chart.visible = kind != 12
	_jump_box.visible = true
	_console_title.text = "Карта сектора" if kind == 3 else ("Управление кораблём" if kind == 4 else "Шкаф снабжения")
	_console_shut.text = "Закрыть шкаф (E или Esc)" if kind == 12 else ("Закончить обыск (E или Esc)" if kind == 13 else "Отойти от пульта (E или Esc)")


func _update_store() -> void:
	## The supply locker: what the ship has, what we carry, and a trader's prices when one is alongside.
	var trading := client.can_trade()
	var lines := PackedStringArray()
	lines.append("В шкафу: заплаток %d, запчастей %d. Воздух для установки: %d из %d. Кредиты: %d." % [
		client.store_patches, client.store_parts, int(round(client.store_air)), int(Net.STORE_AIR_FULL), client.credits])
	var free := client.slots.count(Net.ITEM_NONE)
	lines.append("У вас с собой: заплаток %d, запчастей %d. Свободных слотов: %d из %d." % [
		client.patches, client.parts, free, Net.SLOTS])
	lines.append("Заплатка нужна, чтобы заделать пробоину. Запчасть ускоряет ремонт машин и дверей: без неё он идёт втрое дольше.")
	if trading:
		lines.append("Торговец на связи.")
	elif client.sectors.count > 0 and client.sectors.kind[client.sector] == Sectors.TRADER:
		lines.append("Торговец в этом секторе. Чтобы покупать, %s." % ("подойдите к нему" if client.powered() else "нужно питание"))
	else:
		lines.append("Докупить запас можно у торговца. Воздух для установки бесплатно пополняет станция снабжения.")
	_console_text.text = "\n".join(lines)
	var wanted := 9000 + (1 if trading else 0)
	if _jump_buttons_for != wanted:
		_jump_buttons_for = wanted
		_store_buttons.clear()
		for old in _jump_box.get_children():
			old.queue_free()
		var offers := [[Net.STORE_TAKE_PATCH, "Взять заплатку"], [Net.STORE_TAKE_PART, "Взять запчасть"],
			[Net.STORE_PUT_BACK, "Положить всё обратно"]]
		if trading:
			offers.append([Net.STORE_BUY_PATCH, "Купить заплатку: %d" % Net.PRICE_PATCH])
			offers.append([Net.STORE_BUY_PART, "Купить запчасть: %d" % Net.PRICE_PART])
			offers.append([Net.STORE_BUY_AIR, "Купить воздух (%d): %d" % [int(Net.AIR_LOT), Net.PRICE_AIR]])
		for offer: Array in offers:
			var b := Button.new()
			b.text = offer[1]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(client.send_store.bind(int(offer[0])))
			_jump_box.add_child(b)
			_store_buttons[int(offer[0])] = b
	for action: int in _store_buttons.keys():
		var b: Button = _store_buttons[action]
		match action:
			Net.STORE_TAKE_PATCH:
				b.disabled = client.store_patches <= 0 or free == 0
			Net.STORE_TAKE_PART:
				b.disabled = client.store_parts <= 0 or free == 0
			Net.STORE_PUT_BACK:
				b.disabled = client.patches + client.parts == 0
			Net.STORE_BUY_PATCH:
				b.disabled = client.credits < Net.PRICE_PATCH
			Net.STORE_BUY_PART:
				b.disabled = client.credits < Net.PRICE_PART
			Net.STORE_BUY_AIR:
				b.disabled = client.credits < Net.PRICE_AIR or client.store_air >= Net.STORE_AIR_FULL


func _update_console() -> void:
	if client.search_id >= 0 and _console_kind != 13:
		_open_console(13)                    # the server let us search somebody: show their pockets
	if not _console.visible:
		return
	if _console_kind == 13:
		if client.search_id < 0 or client.my_cond != Net.COND_OK:
			_open_console(0)                 # they came round, we were pulled apart, or we went down
		else:
			_update_search()
		return
	if client.my_cond != Net.COND_OK or client.use_target() != _console_kind or not _opens_panel(_console_kind):
		_open_console(0)             # knocked out, pushed away from the console, or the power went
		return
	if _console_kind == 12:
		_update_store()
		return
	if _console_kind == 4:
		_update_helm()
		return
	var now := client.server_now()
	var jumping := client.jump_to != Net.NO_SECTOR
	var wait := (client.drive_ready - now) / Net.TICK_HZ
	if jumping:
		_console_text.text = "Корабль в секторе %s.\nКурс задан: %s. Прыжок через %d с." % [
			client.sectors.describe(client.sector), client.sectors.describe(client.jump_to),
			maxi(int(ceil((client.jump_tick - now) / Net.TICK_HZ)), 0)]
	elif wait > 0.0:
		_console_text.text = "Корабль в секторе %s.\nДвигатель перезаряжается: ещё %d с." % [client.sectors.describe(client.sector), int(ceil(wait))]
	else:
		_console_text.text = "Корабль в секторе %s.\nДвигатель готов. Куда прыгаем?" % client.sectors.describe(client.sector)
	_console_text.text += "\nДо начала пути отсюда прыжков: %d. Карта показывает только окрестности корабля." % client.sectors.far_from_start(client.sector)
	# one button per sector within reach; rebuilt when the ship has moved
	var place_key := Sectors.key(client.sectors.cell[client.sector]) * 2    # the buttons belong to this place in space
	if _jump_buttons_for != place_key:
		_jump_buttons_for = place_key
		for old in _jump_box.get_children():
			old.queue_free()
		for id in client.sectors.neighbours(client.sector):
			var go := Button.new()
			go.text = "Прыжок: %s" % client.sectors.describe(id)
			go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			go.pressed.connect(client.send_jump.bind(id))
			_jump_box.add_child(go)
		_chart.queue_redraw()
	for go in _jump_box.get_children():
		if go is Button:
			(go as Button).disabled = jumping or wait > 0.0
	if jumping:
		_chart.queue_redraw()


func _update_helm() -> void:
	## The ship's controls: where the ship is inside the sector and where it is heading.
	var sectors := client.sectors
	var here := client.sector
	var at := client.ship_pos()
	var lines := PackedStringArray()
	if client.ship_under_way():
		lines.append("Корабль идёт заданным курсом, осталось %d." % int(ceil(at.distance_to(client.ship_dest))))
	else:
		lines.append("Корабль стоит. Щёлкните по карте, чтобы задать курс.")
	match sectors.kind[here]:
		Sectors.METEORS:
			var edge := float(sectors.reach[here]) - at.distance_to(sectors.spot[here])
			lines.append("Корабль внутри метеорного потока, до края %d." % int(ceil(edge)) if edge >= 0.0 else "Корабль вне метеорного потока.")
		Sectors.STATION, Sectors.TRADER:
			var what := "станции" if sectors.kind[here] == Sectors.STATION else "торговца"
			var gap := at.distance_to(sectors.spot[here]) - float(sectors.reach[here])
			lines.append("До %s %d." % [what, int(ceil(gap))] if gap > 0.0 else "Корабль у %s." % what)
		_:
			lines.append("В этом секторе идти некуда: вокруг пусто.")
	_console_text.text = "\n".join(lines)
	if _jump_buttons_for != Sectors.key(sectors.cell[here]) * 2 + 1:
		_jump_buttons_for = Sectors.key(sectors.cell[here]) * 2 + 1
		for old in _jump_box.get_children():
			old.queue_free()
		var halt := Button.new()
		halt.text = "Остановить корабль"
		halt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		halt.pressed.connect(func() -> void: client.send_helm(false))
		_jump_box.add_child(halt)
	_chart.queue_redraw()


func _draw_slots(canvas: Control, origin: Vector2, slots: PackedByteArray, px: float, gap: float) -> void:
	## A row of inventory slots with what is in them.
	for i in slots.size():
		var cell := Rect2(origin + Vector2(i * (px + gap), 0), Vector2(px, px))
		canvas.draw_rect(cell, Color(0.07, 0.08, 0.12, 0.88))
		canvas.draw_rect(cell, Color(0.42, 0.46, 0.56, 0.9), false, 1.0)
		_draw_item(canvas, cell, slots[i])


func _draw_item(canvas: Control, cell: Rect2, item: int) -> void:
	var u := cell.size.x / 17.0          # the pictures are laid out on a 17 by 17 grid
	var at := cell.position
	if item == Net.ITEM_PATCH:
		# a plate of hull metal with a rivet in each corner
		canvas.draw_rect(Rect2(at + Vector2(3, 3) * u, Vector2(11, 11) * u), Color(0.2, 0.21, 0.27))
		canvas.draw_rect(Rect2(at + Vector2(4, 4) * u, Vector2(9, 9) * u), Color(0.72, 0.75, 0.8))
		canvas.draw_rect(Rect2(at + Vector2(4, 11) * u, Vector2(9, 2) * u), Color(0.52, 0.55, 0.62))
		for corner: Vector2 in [Vector2(5, 5), Vector2(11, 5), Vector2(5, 11), Vector2(11, 11)]:
			canvas.draw_rect(Rect2(at + corner * u, Vector2(u, u)), Color(0.25, 0.26, 0.33))
	elif item == Net.ITEM_PART:
		# a cog
		var mid := at + Vector2(8.5, 8.5) * u
		for k in 8:
			var out := Vector2.RIGHT.rotated(k * TAU / 8.0) * 5.2 * u
			canvas.draw_rect(Rect2(mid + out - Vector2(1.2, 1.2) * u, Vector2(2.4, 2.4) * u), Color(0.9, 0.55, 0.15))
		canvas.draw_circle(mid, 4.4 * u, Color(0.95, 0.65, 0.2))
		canvas.draw_circle(mid, 1.8 * u, Color(0.16, 0.14, 0.18))


func _search_row(mine: bool) -> Vector2:
	## Where a row of slots starts in the search panel: theirs above, ours below.
	var wide := Net.SLOTS * BIG_SLOT_PX + (Net.SLOTS - 1) * BIG_SLOT_GAP
	return Vector2((_chart.size.x - wide) * 0.5, 190.0 if mine else 60.0)


func _draw_search() -> void:
	var font := ThemeDB.fallback_font
	_chart.draw_rect(Rect2(Vector2.ZERO, _chart.size), Color(0.02, 0.05, 0.04))
	var theirs := _search_row(false)
	var ours := _search_row(true)
	_chart.draw_string(font, theirs + Vector2(0, -12), "У лежащего:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.95, 0.88))
	_draw_slots(_chart, theirs, client.search_slots, BIG_SLOT_PX, BIG_SLOT_GAP)
	_chart.draw_string(font, ours + Vector2(0, -12), "У вас:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.95, 0.88))
	_draw_slots(_chart, ours, client.slots, BIG_SLOT_PX, BIG_SLOT_GAP)


func _update_search() -> void:
	## Going through somebody's pockets: their slots and ours; a click moves a thing across.
	var who := client.player_name(client.search_id)
	var dead := client.ents.has(client.search_id) and (client.ents[client.search_id] as GameClient.Ent).cond == Net.COND_DEAD
	_console_title.text = "Обыск: %s (%s)" % [who, "тело" if dead else "без сознания"]
	_console_text.text = "Щёлкните по вещи лежащего, чтобы забрать её. Щёлкните по своей, чтобы положить ему."
	if _jump_buttons_for != 13000:
		_jump_buttons_for = 13000
		for old in _jump_box.get_children():
			old.queue_free()
	_chart.queue_redraw()


func _helm_area() -> Rect2:
	## The square of the chart control that stands for the sector.
	var side := minf(_chart.size.x, _chart.size.y) - 12.0
	return Rect2((_chart.size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _on_chart_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if _console_kind == 13:
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			for mine: bool in [false, true]:
				var from := click.position - _search_row(mine)
				var index := int(floorf(from.x / (BIG_SLOT_PX + BIG_SLOT_GAP)))
				if from.y >= 0.0 and from.y < BIG_SLOT_PX and index >= 0 and index < Net.SLOTS \
						and from.x - index * (BIG_SLOT_PX + BIG_SLOT_GAP) < BIG_SLOT_PX:
					client.send_loot(not mine, index)
		return
	if _console_kind != 4:
		return
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var area := _helm_area()
		if area.has_point(click.position):
			client.send_helm(true, (click.position - area.position) / area.size * Sectors.SPAN)


func _draw_helm() -> void:
	var sectors := client.sectors
	var here := client.sector
	var area := _helm_area()
	var scale := area.size.x / Sectors.SPAN
	var font := ThemeDB.fallback_font
	_chart.draw_rect(Rect2(Vector2.ZERO, _chart.size), Color(0.02, 0.05, 0.04))
	_chart.draw_rect(area, Color(0.03, 0.08, 0.07))
	for i in range(1, 4):
		var k := area.size.x * i / 4.0
		_chart.draw_line(area.position + Vector2(k, 0), area.position + Vector2(k, area.size.y), Color(0.3, 0.8, 0.5, 0.12))
		_chart.draw_line(area.position + Vector2(0, k), area.position + Vector2(area.size.x, k), Color(0.3, 0.8, 0.5, 0.12))
	_chart.draw_rect(area, Color(0.3, 0.75, 0.45, 0.6), false, 1.0)
	var spot := area.position + sectors.spot[here] * scale
	match sectors.kind[here]:
		Sectors.METEORS:
			_chart.draw_circle(spot, sectors.reach[here] * scale, Color(1.0, 0.55, 0.2, 0.2))
			_chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 48, Color(1.0, 0.6, 0.25, 0.8), 1.0)
			_chart.draw_string(font, spot + Vector2(-70, 4), "метеорный поток", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(1.0, 0.75, 0.5))
		Sectors.STATION, Sectors.TRADER:
			var colour := Color(0.3, 0.85, 0.8) if sectors.kind[here] == Sectors.STATION else Color(0.95, 0.85, 0.35)
			_chart.draw_arc(spot, sectors.reach[here] * scale, 0.0, TAU, 32, Color(colour, 0.6), 1.0)
			_chart.draw_rect(Rect2(spot - Vector2(4, 4), Vector2(8, 8)), colour)
			_chart.draw_string(font, spot + Vector2(-70, 26), "станция" if sectors.kind[here] == Sectors.STATION else "торговец",
				HORIZONTAL_ALIGNMENT_CENTER, 140, 12, colour)
	var ship := area.position + client.ship_pos() * scale
	if client.ship_under_way():
		var dest := area.position + client.ship_dest * scale
		_chart.draw_line(ship, dest, Color(1, 1, 1, 0.55), 1.0)
		_chart.draw_line(dest + Vector2(-5, -5), dest + Vector2(5, 5), Color.WHITE, 1.0)
		_chart.draw_line(dest + Vector2(-5, 5), dest + Vector2(5, -5), Color.WHITE, 1.0)
	_chart.draw_circle(ship, 5.0, Color.WHITE)
	_chart.draw_arc(ship, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.6), 1.0)


func _draw_chart() -> void:
	## The chart of sectors: where the ship is, where it can jump, what is known about the rest.
	if _console_kind == 4:
		_draw_helm()
		return
	if _console_kind == 13:
		_draw_search()
		return
	var sectors := client.sectors
	if sectors.count == 0:
		return
	var area := Rect2(Vector2(30, 22), _chart.size - Vector2(60, 50))
	var place := func(id: int) -> Vector2:
		return area.position + Vector2(sectors.pos[id].x / 100.0, sectors.pos[id].y / 60.0) * area.size
	_chart.draw_rect(Rect2(Vector2.ZERO, _chart.size), Color(0.02, 0.05, 0.04))
	for l: Array in sectors.links:
		var near: bool = int(l[0]) == client.sector or int(l[1]) == client.sector
		_chart.draw_line(place.call(int(l[0])), place.call(int(l[1])), Color(0.3, 0.8, 0.5, 0.75 if near else 0.22), 2.0 if near else 1.0)
	if client.jump_to != Net.NO_SECTOR:
		_chart.draw_line(place.call(client.sector), place.call(client.jump_to), Color(1, 1, 1, 0.9), 3.0)
	var font := ThemeDB.fallback_font
	var colours := [Color(0.55, 0.62, 0.75), Color(1.0, 0.6, 0.25), Color(0.95, 0.85, 0.35), Color(0.3, 0.85, 0.8)]
	for id in sectors.count:
		var at: Vector2 = place.call(id)
		var known := client.knows_sector(id)
		if not known:
			_chart.draw_circle(at, 3.0, Color(0.3, 0.36, 0.34))     # something is there; nobody knows what
			continue
		_chart.draw_circle(at, 7.0, colours[sectors.kind[id]])
		if sectors.visited[id] == 1:
			_chart.draw_circle(at, 2.5, Color(0.04, 0.08, 0.07))    # been there
		if id == client.sector:
			_chart.draw_arc(at, 12.0, 0.0, TAU, 32, Color.WHITE, 2.0)
		_chart.draw_string(font, at + Vector2(-70, 24), sectors.names[id], HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(0.85, 0.95, 0.88))
	# legend
	var x := 8.0
	for k in Sectors.KIND_NAMES.size():
		_chart.draw_circle(Vector2(x + 5, _chart.size.y - 10), 5.0, colours[k])
		_chart.draw_string(font, Vector2(x + 14, _chart.size.y - 6), Sectors.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.74))
		x += 26.0 + font.get_string_size(Sectors.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


func _build_pause(root: Control) -> void:
	_pause = PanelContainer.new()
	_pause.visible = false
	_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.14, 0.96)
	style.border_color = Color(0.36, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	_pause.add_theme_stylebox_override("panel", style)
	root.add_child(_pause)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_pause.add_child(box)
	var title := Label.new()
	title.text = "Меню"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	if hosting:
		var addresses := PackedStringArray()
		for a in IP.get_local_addresses():
			if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
				addresses.append(a)
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 14)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(380, 0)
		var where := ", ".join(addresses) if not addresses.is_empty() else "не найден"
		info.text = "Вы создали эту игру. Другие игроки в вашей сети подключаются по адресу: %s (порт %d).\nДля игры через интернет порт %d (UDP) нужно открыть на роутере." % [where, host_port, host_port]
		box.add_child(info)
	if client.admin_token != "":
		# the host is the game master: the director can be left to itself or driven by hand
		var auto := CheckBox.new()
		auto.text = "Ивентер ведёт события сам"
		auto.button_pressed = true
		auto.toggled.connect(func(on: bool) -> void: client.send_admin(Net.ADMIN_AUTO, 1 if on else 0))
		box.add_child(auto)
		for e: Dictionary in Director.EVENTS:
			var fire := Button.new()
			fire.text = "Событие: %s (%s)" % [e["name"], Director.SIZE_NAMES[int(e["size"])]]
			fire.pressed.connect(func() -> void:
				client.send_admin(Net.ADMIN_EVENT, int(e["id"]))
				_set_pause(false))
			box.add_child(fire)
	var resume := Button.new()
	resume.text = "Продолжить"
	resume.pressed.connect(func() -> void: _set_pause(false))
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "Выйти в главное меню"
	leave.pressed.connect(func() -> void: exit_requested.emit())
	box.add_child(leave)


func show_debug(on: bool) -> void:
	_debug.visible = on
	_world.show_ghost = on
	_info_timer = 0.0


func open_console_here() -> void:
	## Test helper: open the console our character faces, as the "use" key would.
	if client.use_target() == 13:
		client.send_search(client.lying_near())
	elif _opens_panel(client.use_target()):
		_open_console(client.use_target())


func show_pause(on: bool) -> void:
	_set_pause(on)


func _set_pause(on: bool) -> void:
	_pause.visible = on
	if on:
		_close_chat()


func _open_chat() -> void:
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()


func _close_chat() -> void:
	_chat_input.release_focus()
	_chat_input.visible = false


func _on_chat_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if not clean.is_empty():
		client.send_chat(clean)
	_close_chat()


func _say(bbcode: String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", 14)
	line.add_theme_font_size_override("bold_font_size", 14)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	line.add_theme_constant_override("outline_size", 5)
	line.text = bbcode
	_chat_box.add_child(line)
	_chat_lines.append([line, Time.get_ticks_msec() / 1000.0])
	while _chat_lines.size() > CHAT_LINES:
		(_chat_lines.pop_front()[0] as RichTextLabel).queue_free()


func _on_chat(from_id: int, text: String) -> void:
	if from_id == Net.SYSTEM_ID:
		_say("[color=#ffb14a][b]Корабль:[/b] %s[/color]" % _escape(text))
		return
	var colour := NAME_COLOURS[client.player_colour(from_id) % NAME_COLOURS.size()]
	_say("[color=#%s][b]%s:[/b][/color] %s" % [colour, _escape(client.player_name(from_id)), _escape(text)])


func _on_notice(text: String) -> void:
	_say("[color=#9aa3b5]%s[/color]" % _escape(text))


func _capital(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _chat_input.visible:
			_close_chat()
		elif _console.visible:
			_open_console(0)
		else:
			_set_pause(not _pause.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use") and not _chat_input.visible and not _pause.visible and (_console.visible or _opens_panel(client.use_target()) or client.use_target() == 13):
		# a bridge console, the locker, somebody lying: the key opens a screen, and closes it again
		if _console.visible:
			_open_console(0)
		elif client.use_target() == 13:
			client.send_search(client.lying_near())      # the screen opens when the server agrees
		else:
			_open_console(client.use_target())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drag") and not _chat_input.visible and not _pause.visible and not _console.visible:
		if client.dragging():
			client.send_drag(Net.NOBODY)
		elif client.lying_near() >= 0:
			client.send_drag(client.lying_near())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and not _pause.visible and not _chat_input.visible:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug"):
		show_debug(not _debug.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("suit") and not _chat_input.visible and not _pause.visible:
		client.send_suit(not client.supply)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("respawn") and not _chat_input.visible:
		client.send_respawn()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_predict"):
		client.predict = not client.predict
		get_viewport().set_input_as_handled()


func _health_state() -> int:
	## Which of the monitor's eight pictures fits our health (the scale Space Station 13 uses).
	if client.my_cond == Net.COND_DEAD:
		return 7
	if client.my_cond == Net.COND_CRIT or client.health <= 0:
		return 6
	if client.health >= 100:
		return 0
	return clampi(5 - client.health / 20, 1, 5)


func _lamp(lamp: String, on: bool) -> void:
	if not _alerts.has(lamp):
		return
	var a: Dictionary = _alerts[lamp]
	var node: TextureRect = a["node"]
	node.visible = on
	if on:
		var frames: Array = a["frames"]
		var seconds: float = a["seconds"]
		node.texture = frames[int(_monitor_time / seconds) % frames.size()] if seconds > 0.0 else frames[0]


func _input(event: InputEvent) -> void:
	# Esc while typing: cancel the message (the text field would swallow the key otherwise)
	if _chat_input.visible and event.is_action_pressed("pause"):
		_close_chat()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if client == null:
		return
	# which way to walk: the most recently pressed of the held direction keys
	var busy := _chat_input.visible or _pause.visible or _console.visible
	_update_console()
	for m: Array in MOVES:
		var dir: int = m[1]
		var down := Input.is_action_pressed(m[0]) and not busy
		if down and not _held.has(dir):
			_held.append(dir)
		elif not down and _held.has(dir):
			_held.erase(dir)
	var want := 0 if _held.is_empty() else _held[_held.size() - 1]
	if demo_walk:
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _demo_until:
			_demo_dir = _rng.randi_range(1, 4) if _rng.randf() < 0.85 else 0
			_demo_until = now + _rng.randf_range(0.15, 1.2)
			if client.use_target() >= 6 and _rng.randf() < 0.5:
				client.send_use(true)        # happened to stop on a ladder: take it
				client.send_use(false)
		want = _demo_dir
	if forced_dir >= 0:
		want = forced_dir
	client.want_dir = want

	# the "use" key: tell the server when it goes down or up
	var use_now := (Input.is_action_pressed("use") and not busy) or forced_use
	if use_now != _use_held:
		_use_held = use_now
		client.send_use(use_now)
	var target := client.use_target()
	var hauling := client.dragging()
	_hint.visible = (target != 0 or hauling) and not _console.visible
	if hauling and (target == 0 or target == 13):
		_hint.text = "Вы тащите: %s.  F: отпустить" % client.player_name(client.drag_id)
		target = -1                          # (the hint is set; none of the cases below applies)
	var no_power := not client.powered()
	var why := "двигатель не работает" if client.engine_down() else "сбой питания"
	var no_part := "" if client.parts > 0 else " (без запчасти втрое дольше)"
	if target == 1:
		if client.patches <= 0:
			_hint.text = "Нечем заделать пробоину: заплатки в шкафу снабжения на нижней палубе"
		else:
			_hint.text = "Заделываю пробоину…" if (_use_held and client.work > 0) else "Держите E, чтобы заделать пробоину"
	elif target == 2:
		if no_power:
			_hint.text = "Кислородная стойка обесточена: %s" % why
		else:
			_hint.text = "Баллон полон" if client.tank >= Net.TANK_FULL else ("Заправляю баллон…" if _use_held else "Держите E, чтобы заправить баллон")
	elif target == 3 or target == 4:
		if no_power:
			_hint.text = "Пульт обесточен: %s" % why
		else:
			_hint.text = "E: карта сектора" if target == 3 else "E: управление кораблём"
	elif target == 5:
		var what := _capital(client.map.device_name(client.use_cell()))
		_hint.text = "Чиню…" if (_use_held and client.work > 0) else "%s не работает. Держите E, чтобы починить%s" % [what, no_part]
	elif target == 8:
		var state := "нет питания" if no_power else "работает"
		if client.map.air_plant.has(client.use_cell()) and not no_power:
			state = "работает, воздуха в запасе %d из %d" % [int(round(client.store_air)), int(Net.STORE_AIR_FULL)] if client.store_air > 0.0 \
				else "стоит, запас воздуха исчерпан"
		_hint.text = "%s: %s" % [_capital(client.map.device_name(client.use_cell())), state]
	elif target == 12:
		_hint.text = "E: шкаф снабжения"
	elif target == 13:
		var lying := client.lying_near()
		var is_dead := client.ents.has(lying) and (client.ents[lying] as GameClient.Ent).cond == Net.COND_DEAD
		_hint.text = "%s: %s.  E: обыскать    F: тащить" % [client.player_name(lying), "тело" if is_dead else "без сознания"]
	elif target == 6 or target == 7:
		var to := client.my_deck() + (1 if target == 6 else -1)
		_hint.text = "E: %s по лестнице (%s)" % ["спуститься" if target == 6 else "подняться", client.map.deck_names[to].to_lower()]
	elif target == 9:
		if _use_held and client.work > 0:
			_hint.text = "Поднимаю аварийный шлюз…"
		elif no_power:
			_hint.text = "Аварийный шлюз закрыт и обесточен.\nДержите E, чтобы открыть вручную"
		else:
			var gap := client.shutter_gap(client.map.door_of[client.use_cell()])
			var kpa := int(round(int(gap[0]) * Net.KPA_FULL / Net.AIR_FULL))
			var where := "" if int(gap[1]) == 0 else (", за ним давление ниже" if int(gap[1]) < 0 else ", за ним давление выше")
			_hint.text = "Аварийный шлюз закрыт: разница давлений %d кПа%s.\nДержите E, чтобы открыть вручную" % [kpa, where]
	elif target == 10:
		_hint.text = "Чиню дверь…" if (_use_held and client.work > 0) else "Дверь заклинило открытой. Держите E, чтобы починить%s" % no_part
	elif target == 11:
		if _use_held and client.work > 0:
			_hint.text = "Чиню аварийный шлюз…"
		elif client.doors.is_sealed(client.map.door_of[client.use_cell()]):
			_hint.text = "Аварийный шлюз неисправен: упал и сам не поднимется.\nДержите E, чтобы починить%s" % no_part
		else:
			_hint.text = "Аварийный шлюз неисправен: при разгерметизации не сработает.\nДержите E, чтобы починить%s" % no_part
	_work_bar.visible = (target == 1 or target == 5 or target >= 9) and client.work > 0
	_work_fill.size.x = 216.0 * client.work / 100.0
	var shift := (HINT_LEFT - HINT_RIGHT) * 0.5          # under the middle of the hint line
	_work_bar.offset_left = shift - 110.0
	_work_bar.offset_right = shift + 110.0

	var now_s := Time.get_ticks_msec() / 1000.0
	for entry: Array in _chat_lines:
		var age: float = now_s - float(entry[1])
		var alpha := 1.0 if _chat_input.visible else clampf(1.0 - (age - CHAT_VISIBLE_SEC) / 2.0, 0.0, 1.0)
		(entry[0] as RichTextLabel).modulate.a = alpha

	# the monitor shows one of eight states, from unhurt to dead
	_monitor_time += delta
	if _monitor != null and not _monitor_frames.is_empty():
		var row: Array = _monitor_frames[mini(_health_state(), _monitor_frames.size() - 1)]
		_monitor.texture = row[int(_monitor_time / _monitor_step) % row.size()]

	# warning lamps: thin air and low pressure where our character stands
	var here := client.air_at(client.pred.x, client.pred.y)
	var alive := client.my_cond != Net.COND_DEAD
	_lamp("o2_low", alive and here >= 0 and here < Net.AIR_FULL * BREATH_MIN)
	_lamp("kpa_low1", alive and here >= Net.AIR_FULL * PRESSURE_MIN and here < Net.AIR_FULL * PRESSURE_WARN)
	_lamp("kpa_low2", alive and here >= 0 and here < Net.AIR_FULL * PRESSURE_MIN)
	_lamp("o2_on", alive and client.supply)
	_lamp("o2_off", alive and not client.supply)
	_tank_bar.visible = alive
	_slots_view.visible = alive
	if client.slots != _slots_shown:
		_slots_shown = client.slots.duplicate()
		_slots_view.queue_redraw()
	var share := float(client.tank) / Net.TANK_FULL
	_tank_fill.position = Vector2(2, 2 + 92.0 * (1.0 - share))
	_tank_fill.size = Vector2(8, 92.0 * share)
	_tank_fill.color = Color(0.25, 0.85, 0.75) if share > 0.5 else (Color(0.95, 0.75, 0.3) if share > 0.2 else Color(0.95, 0.35, 0.3))

	# fading out: the screen darkens below 40 health
	var dark := clampf((40.0 - client.health) / 40.0, 0.0, 1.0) * 0.5
	if client.my_cond == Net.COND_CRIT:
		dark = 0.72
		_fate.text = "Вы без сознания"
	elif client.my_cond == Net.COND_DEAD:
		dark = 0.8
		_fate.text = "Вы погибли. Нажмите R, чтобы вернуться новым членом экипажа."
	_fate.visible = client.my_cond != Net.COND_OK
	_shade.color.a = lerpf(_shade.color.a, dark, 1.0 - exp(-delta * 4.0))
	_blackout.color.a = lerpf(_blackout.color.a, 0.0 if client.powered() else 0.42, 1.0 - exp(-delta * 6.0))

	# the jump
	_jump_label.visible = client.jump_to != Net.NO_SECTOR and not _console.visible
	if _jump_label.visible:
		_jump_label.text = "Прыжок через %d с: %s" % [
			maxi(int(ceil((client.jump_tick - client.server_now()) / Net.TICK_HZ)), 0), client.sectors.describe(client.jump_to)]
	_flash.color.a = maxf(_flash.color.a - delta * 1.6, 0.0)

	_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.25
		_info.text = "На борту: %d     Пинг: %d мс     Сектор: %s" % [client.crew_count(), int(round(client.rtt_ms)),
			client.sectors.describe(client.sector) if client.sectors.count > 0 else "?"]
		if client.map.deck_count > 1:
			_info.text += "     %s" % client.map.deck_names[client.my_deck()]
		if _debug.visible:
			_debug.text = "тик сервера: %d\nпредсказание: %s (F4), исправлено шагов: %d\nсверка состояния: %d без расхождений, %d с расхождением\nпринято: %d пакетов, %.1f КБ\nкадров в секунду: %d\nздоровье: %d, давление здесь: %d кПа, баллон: %d%%" % [
				client.server_tick, "вкл" if client.predict else "выкл", client.mispredicts,
				client.checks_ok, client.checks_bad, client.packets_in, client.bytes_in / 1024.0,
				int(round(_fps_smooth)), client.health,
				int(round(maxi(client.air_at(client.pred.x, client.pred.y), 0) * Net.KPA_FULL / Net.AIR_FULL)),
				client.tank * 100 / Net.TANK_FULL]
