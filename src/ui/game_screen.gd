extends Node
## Everything shown while playing: the world, the HUD, chat and the pause
## panel. Reads the keyboard and tells the GameClient which way to walk.

signal exit_requested

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const WorldView := preload("res://src/client/world_view.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Director := preload("res://src/server/director.gd")   # only for the list of events in the host's menu
const Items := preload("res://src/shared/items.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Options := preload("res://src/client/options.gd")
const OptionsPanel := preload("res://src/ui/options_panel.gd")
const AdminPanel := preload("res://src/ui/admin_panel.gd")
const InventoryPanel := preload("res://src/ui/inventory_panel.gd")
const StoreView := preload("res://src/ui/store_view.gd")
const GunsView := preload("res://src/ui/guns_view.gd")
const TradeView := preload("res://src/ui/trade_view.gd")
const HoloView := preload("res://src/ui/holo_view.gd")
const BridgeView := preload("res://src/ui/bridge_view.gd")

const MOVES := [["move_up", 1], ["move_down", 2], ["move_left", 3], ["move_right", 4]]
const CHAT_LINES := 9
const SLOT_PX := 34.0                # a slot of the inventory on screen
const SLOT_GAP := 4.0
const BIG_SLOT_PX := 60.0            # and in the search panel
const BIG_SLOT_GAP := 8.0
const WORN_GAP := 12.0               # between what is worn (on the left) and the slots
const WORN_MARKS := ["С", "К", "Р"]  # an empty place for a suit, a jumpsuit, a backpack
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
var _info_on := false                # the status lines and the keys, shown by F1
var _debug: Label
var _monitor: TextureRect
var _monitor_frames: Array = []       # per health state: Array[AtlasTexture]
var _alerts := {}                    # lamp name -> {"frames": Array[AtlasTexture], "seconds": float, "node": TextureRect}
var _alert_box: VBoxContainer
var _shade: ColorRect
var _fate: Label
var _over: PanelContainer            # the end of the campaign: what the voyage came to
var _over_text: Label
var _tank_bar: ColorRect
var _tank_fill: ColorRect
var _hint: Label
var _work_bar: ColorRect
var _work_fill: ColorRect
var _use_held := false
var _click_facing := 0               # a click on something to use: the way our character is turning to reach it
var _click_until := 0.0              # (given up if the turn has not come by then)
var _mouse_use := false              # the left button holds "use" down, like the key
var _console: PanelContainer         # the screen of a bridge console, shown over the game
var _console_kind := 0               # 3 = sector console, 4 = ship's controls (as GameClient.use_target)
var _console_title: Label
var _console_text: Label
var _chart: Control
var _jump_box: GridContainer
var _bridge: BridgeView              # what the sector console and the ship's controls show in that frame
var _console_shut: Button
var _console_style: StyleBoxFlat
var _store_view: StoreView           # the screens of the supply locker, the gun console and the holomap,
var _guns_view: GunsView             # shown in the console's frame instead of its chart, text and buttons
var _trade_view: TradeView           # the trader's screen, opened from the supply locker's
var _trading := false                # the locker's frame shows the trader's screen
var _holo_view: HoloView
var _slots_view: Control             # what our character carries, slot by slot
var _slots_shown := PackedByteArray()
var _hand_shown := -1
var _hand_label: Label               # what is in the hand, over the slots
var _jump_label: Label
var _flash: ColorRect
var _monitor_step := 0.08
var _monitor_time := 0.0
var _chat_box: VBoxContainer
var _chat_lines: Array = []          # [RichTextLabel, time it was added]
var _chat_input: LineEdit
var _pause: PanelContainer
var _pause_admin: Button             # opens the admin panel; shown while the server counts us an admin
var _options: OptionsPanel
var _admin: AdminPanel
var _inventory: InventoryPanel
var _root: Control                   # (the windows above are made when first opened: making them
                                     # while joining would hold up the client's clock)
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
	# the keys, in two lines under the top right corner, so they do not run into the line on the left
	_keys = _text(root, 13)
	_show_keys()
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_keys.offset_right = -14
	_keys.offset_top = 34
	_keys.modulate = Color(1, 1, 1, 0.75)
	# Both are hidden until F1 (v47, the author's word: the screen is the ship and the dark, not text).
	_info.visible = false
	_keys.visible = false

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
	_slots_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_slots_view.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var slots_wide := _bar_width(SLOT_PX, SLOT_GAP)
	_slots_view.offset_right = -14 - 192 - 10 - 12 - 12
	_slots_view.offset_left = _slots_view.offset_right - slots_wide
	_slots_view.offset_bottom = -14
	_slots_view.offset_top = -14 - SLOT_PX
	_slots_view.draw.connect(func() -> void: _draw_slots(_slots_view, Vector2.ZERO, client.slots, client.worn, SLOT_PX, SLOT_GAP, client.hand))
	_slots_view.gui_input.connect(_on_slots_input)
	root.add_child(_slots_view)
	_hand_label = _text(root, 14)
	_hand_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hand_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hand_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hand_label.offset_right = _slots_view.offset_right
	_hand_label.offset_bottom = _slots_view.offset_top - 6

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

	# (without power the ship goes dark: the world view shades it cell by cell, see WorldView._draw_shade)
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
	_over = PanelContainer.new()
	_over.visible = false
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	var over_style := StyleBoxFlat.new()
	over_style.bg_color = Color(0.06, 0.03, 0.04, 0.92)
	over_style.border_color = Color(0.75, 0.25, 0.2)
	over_style.set_border_width_all(2)
	over_style.set_content_margin_all(24)
	_over.add_theme_stylebox_override("panel", over_style)
	root.add_child(_over)
	_over_text = _text(_over, 20)
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
	_chat_input.placeholder_text = "Вслух слышно рядом.  «;» в начале: рация,  «!»: интерком у панели.  Esc: отмена"
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
	_root = root
	if client.admin_token != "":
		client.send_admin(Net.ADMIN_HELLO)   # the server learns that our player is the host

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
	client.arrived.connect(func() -> void:
		if Options.flash:
			_flash.color.a = 0.9)
	_rng.randomize()
	_say("[color=#9aa3b5]Вы на борту. %s: чат, %s: сведения о корабле и подсказки клавиш.[/color]" % [
		_escape(Options.key_text("chat")), _escape(Options.key_text("info"))])


func _inventory_panel() -> InventoryPanel:
	if _inventory == null:
		_inventory = InventoryPanel.new()
		_root.add_child(_inventory)
		_inventory.setup(client)
		_root.move_child(_inventory, _pause.get_index())
	return _inventory


func _admin_panel() -> AdminPanel:
	if _admin == null:
		_admin = AdminPanel.new()
		_root.add_child(_admin)
		_admin.setup(client)
		_root.move_child(_admin, _pause.get_index())
	return _admin


func _options_panel() -> OptionsPanel:
	if _options == null:
		_options = OptionsPanel.new()
		_root.add_child(_options)
		_options.closed.connect(_show_keys)
	return _options


static func _open(panel: Control) -> bool:
	return panel != null and panel.visible


func _show_keys() -> void:
	## The keys, as the player has set them (see Options).
	_hand_shown = -1                     # (the line over the slots names keys too)
	_keys.text = "%s%s%s%s: ходить    %s: действие    %s: тащить    %s: подача O2    %s: инвентарь    %s: чат    %s: меню\n1–6 или колесо: что в руке    Щелчок: взять, пульт, машина или применить    %s: применить    %s: положить" % [
		Options.key_text("move_up"), Options.key_text("move_left"), Options.key_text("move_down"), Options.key_text("move_right"), Options.key_text("use"), Options.key_text("drag"),
		Options.key_text("suit"), Options.key_text("inventory"), Options.key_text("chat"), Options.key_text("pause"), Options.key_text("act"), Options.key_text("drop")]


func _skills_text() -> String:
	var parts: Array[String] = []
	for i in Net.SKILLS:
		parts.append("%s %d" % [Net.SKILL_NAMES[i], client.skills[i]])
	return ", ".join(parts)


static func _voyage(seconds: int) -> String:
	var minutes := seconds / 60
	return "%d ч %02d мин" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d мин" % minutes


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
	_console_style = style
	root.add_child(_console)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_console.add_child(box)
	_console_title = Label.new()
	_console_title.add_theme_font_size_override("font_size", 20)
	_console_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_console_title)
	_store_view = StoreView.new()
	box.add_child(_store_view)
	_store_view.setup(client)
	_store_view.open_trade = func() -> void: _show_trade(true)
	_trade_view = TradeView.new()
	_trade_view.visible = false
	box.add_child(_trade_view)
	_trade_view.back = func() -> void: _show_trade(false)
	_guns_view = GunsView.new()
	_guns_view.visible = false
	box.add_child(_guns_view)              # (it and the trader's screen are set up when first shown:
	                                       # building them at joining would knock the client's clock off)
	_holo_view = HoloView.new()
	box.add_child(_holo_view)
	_holo_view.setup(client)
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
	_bridge = BridgeView.new(client, _chart, _console_text, _jump_box)
	_console_shut = Button.new()
	_console_shut.pressed.connect(func() -> void: _open_console(0))
	box.add_child(_console_shut)


func _opens_panel(target: int) -> bool:
	## Does the "use" key open a screen for this thing (see GameClient.use_target)?
	## The bridge consoles and the holomap need power; the supply locker is opened by hand.
	return target == 12 or ((target == 3 or target == 4 or target == 17 or target == 20) and client.powered())


func _open_console(kind: int) -> void:
	if _console_kind == 13 and kind != 13 and client.search_id >= 0:
		client.send_search(Net.NOBODY)       # we step back from the one we were searching
		client.search_id = -1
	if _console_kind == 20 and kind != 20:
		client.send_holo(false)
	_console_kind = kind
	_console.visible = kind != 0
	if kind == 0:
		return
	_close_chat()
	_bridge.buttons_for = -1
	var own_view := kind == 12 or kind == 17 or kind == 20
	_trading = false
	if kind == 17 and _guns_view.client == null:
		_guns_view.setup(client)
	_store_view.visible = kind == 12
	_trade_view.visible = false
	_guns_view.visible = kind == 17
	_holo_view.visible = kind == 20
	_chart.visible = not own_view
	_console_text.visible = not own_view
	_jump_box.visible = not own_view
	_jump_box.columns = 2
	_console_style.border_color = Color(0.75, 0.62, 0.38) if kind == 12 else (Color(0.85, 0.4, 0.3) if kind == 17 else
		(Color(0.35, 0.7, 0.9) if kind == 20 else Color(0.3, 0.75, 0.45)))
	_console_title.text = {3: "Карта сектора", 4: "Управление кораблём", 17: "Пульт орудий", 12: "Склад корабля: шкаф снабжения",
		13: "Обыск", 20: "Голокарта корабля"}.get(kind, "")
	if kind == 20:
		_holo_view.opened()
		client.send_holo(true)
	_console_shut.text = Options.keyed("Закрыть шкаф (E или Esc)" if kind == 12 else ("Закончить обыск (E или Esc)" if kind == 13 else "Отойти от пульта (E или Esc)"))


func _show_trade(on: bool) -> void:
	## The supply locker's frame shows the trader's screen, or the locker's own.
	_trading = on
	if on and _trade_view.client == null:
		_trade_view.setup(client)
	_store_view.visible = not on
	_trade_view.visible = on
	_console_title.text = "Торговец" if on else "Склад корабля: шкаф снабжения"
	_console.reset_size()


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
		if _trading and not client.can_trade():
			_show_trade(false)               # the trader is out of reach, or the power went
		if _trading:
			_trade_view.refresh()
		else:
			_store_view.refresh()
		return
	if _console_kind == 17:
		_guns_view.refresh(get_process_delta_time())
		return
	if _console_kind == 20:
		_holo_view.refresh(get_process_delta_time())
		return
	if _console_kind == 4:
		_bridge.update_helm()
		return
	_bridge.update_chart()


func _bar_width(px: float, gap: float) -> float:
	return (Net.WORN + Net.SLOTS) * px + (Net.WORN + Net.SLOTS - 1) * gap + WORN_GAP


func _bar_cell(origin: Vector2, k: int, px: float, gap: float) -> Rect2:
	## Cell k of a row: first what is worn (0 .. WORN - 1), then the slots.
	var x := k * (px + gap) + (WORN_GAP if k >= Net.WORN else 0.0)
	return Rect2(origin + Vector2(x, 0), Vector2(px, px))


func _bar_at(origin: Vector2, at: Vector2, px: float, gap: float) -> int:
	## Which cell of a row a point falls in, or -1.
	for k in Net.WORN + Net.SLOTS:
		if _bar_cell(origin, k, px, gap).has_point(at):
			return k
	return -1


static func _slot_open(worn: PackedByteArray, at: int) -> bool:
	## Is that slot there for whoever wears this (the same rule as Player.usable)?
	if at < Net.BASE_SLOTS:
		return true
	if worn.size() < Net.WORN:
		return false
	if at < Net.BASE_SLOTS + Net.POCKETS:
		return worn[Net.WEAR_JUMPSUIT] != Net.ITEM_NONE
	return worn[Net.WEAR_PACK] != Net.ITEM_NONE


func _draw_slots(canvas: Control, origin: Vector2, slots: PackedByteArray, worn: PackedByteArray, px: float, gap: float, hand: int = -1) -> void:
	## A row: what is worn, then the slots with what is in them; the one in the hand is lit up.
	## Pockets and backpack slots show only faintly while there is no jumpsuit or backpack.
	var font := ThemeDB.fallback_font
	for k in Net.WORN + Net.SLOTS:
		var cell := _bar_cell(origin, k, px, gap)
		if k < Net.WORN:
			var thing := worn[k] if k < worn.size() else Net.ITEM_NONE
			canvas.draw_rect(cell, Color(0.1, 0.09, 0.07, 0.9))
			canvas.draw_rect(cell, Color(0.7, 0.6, 0.4, 0.9), false, 1.0)
			if thing == Net.ITEM_NONE:
				canvas.draw_string(font, cell.position + Vector2(0, px * 0.62), WORN_MARKS[k], HORIZONTAL_ALIGNMENT_CENTER, px, int(px * 0.4), Color(0.7, 0.6, 0.4, 0.5))
			else:
				ItemArt.draw(canvas, cell, Net.ITEM_SUIT + Net.SUIT_TANK_STEPS if k == Net.WEAR_SUIT else thing)
			continue
		var i := k - Net.WORN
		if not _slot_open(worn, i):
			canvas.draw_rect(cell, Color(0.05, 0.05, 0.07, 0.35))
			continue
		canvas.draw_rect(cell, Color(0.07, 0.08, 0.12, 0.88) if i != hand else Color(0.14, 0.15, 0.1, 0.92))
		if i == hand:
			canvas.draw_rect(cell.grow(1.0), Color(0.98, 0.82, 0.35), false, 2.0)
		else:
			canvas.draw_rect(cell, Color(0.42, 0.46, 0.56, 0.9), false, 1.0)
		ItemArt.draw(canvas, cell, slots[i])





func _search_px() -> float:
	## The size of a cell in the search panel: as big as fits.
	return minf(BIG_SLOT_PX, (_chart.size.x - 20.0 - WORN_GAP) / (Net.WORN + Net.SLOTS) - BIG_SLOT_GAP)


func _search_row(mine: bool) -> Vector2:
	## Where a row of slots starts in the search panel: theirs above, ours below.
	var wide := _bar_width(_search_px(), BIG_SLOT_GAP)
	return Vector2((_chart.size.x - wide) * 0.5, 190.0 if mine else 60.0)


func _draw_search() -> void:
	var font := ThemeDB.fallback_font
	_chart.draw_rect(Rect2(Vector2.ZERO, _chart.size), Color(0.02, 0.05, 0.04))
	var theirs := _search_row(false)
	var ours := _search_row(true)
	_chart.draw_string(font, theirs + Vector2(0, -12), "У лежащего:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.95, 0.88))
	var px := _search_px()
	_draw_slots(_chart, theirs, client.search_slots, client.search_worn, px, BIG_SLOT_GAP)
	_chart.draw_string(font, ours + Vector2(0, -12), "У вас:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.95, 0.88))
	_draw_slots(_chart, ours, client.slots, client.worn, px, BIG_SLOT_GAP)
	for row: Array in [[theirs, client.search_slots, client.search_worn], [ours, client.slots, client.worn]]:
		var things: PackedByteArray = row[2] + row[1]
		for k in things.size():
			if things[k] != Net.ITEM_NONE:
				var cell := _bar_cell(row[0], k, px, BIG_SLOT_GAP)
				_chart.draw_string(font, cell.position + Vector2(0, px + 14), Items.name_of(things[k]),
					HORIZONTAL_ALIGNMENT_CENTER, px, 10, Color(0.75, 0.85, 0.8))


func _update_search() -> void:
	## Going through somebody's pockets: their slots and ours; a click moves a thing across.
	var who := client.player_name(client.search_id)
	var dead := client.ents.has(client.search_id) and (client.ents[client.search_id] as GameClient.Ent).cond == Net.COND_DEAD
	var state := "тело" if dead else "без сознания, %s" % ["не ранен", "ранен легко", "ранен тяжело", "ранен очень тяжело", "при смерти"][clampi(client.search_hurt, 0, 4)]
	_console_title.text = "Обыск: %s (%s)" % [who, state]
	_console_text.text = "Щёлкните по вещи лежащего, чтобы забрать её (и одежду: скафандр, комбинезон, рюкзак — слева). Щёлкните по своей, чтобы положить ему."
	if _bridge.buttons_for != 13000:
		_bridge.buttons_for = 13000
		for old in _jump_box.get_children():
			old.queue_free()
	_chart.queue_redraw()


func _on_chart_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if _console_kind == 13:
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			for mine: bool in [false, true]:
				var k := _bar_at(_search_row(mine), click.position, _search_px(), BIG_SLOT_GAP)
				if k < 0:
					continue
				if k >= Net.WORN:
					client.send_loot(not mine, k - Net.WORN)
				elif not mine:
					client.send_loot(true, Net.SLOTS + k)        # take off what they wear
		return
	if _console_kind == 4:
		_bridge.helm_clicked(click)


func _draw_chart() -> void:
	## The console's picture: the search, or a bridge console's (see BridgeView).
	if _console_kind == 13:
		_draw_search()
	else:
		_bridge.draw(_console_kind)


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
		# the campaign saves itself every minute and after jumps; this is for the host's peace of mind
		var save := Button.new()
		save.text = "Сохранить кампанию"
		save.pressed.connect(func() -> void:
			client.send_admin(Net.ADMIN_SAVE)
			_set_pause(false))
		box.add_child(save)
	# the admin panel: events, things, people, the ship (see AdminPanel)
	_pause_admin = Button.new()
	_pause_admin.text = "Панель администратора (%s)" % Options.key_text("admin")
	_pause_admin.visible = false
	_pause_admin.pressed.connect(func() -> void:
		_set_pause(false)
		_admin_panel().toggle())
	box.add_child(_pause_admin)
	var settings := Button.new()
	settings.text = "Настройки: звук, изображение, клавиши"
	settings.pressed.connect(func() -> void:
		_set_pause(false)
		_options_panel().open())
	box.add_child(settings)
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


func open_panel(which: String) -> void:
	## Test helper: open one of the windows ("options:2" opens its third tab).
	var tab := int(which.get_slice(":", 1)) if which.contains(":") else 0
	match which.get_slice(":", 0):
		"inventory":
			_inventory_panel().toggle()
		"admin":
			_admin_panel().toggle()
			_admin_panel().show_tab(tab)
		"options":
			_options_panel().open()
			_options_panel().show_tab(tab)
		"pause":
			_set_pause(true)
		"trade":
			if _console_kind == 12:
				_show_trade(true)


func show_pause(on: bool) -> void:
	_set_pause(on)


func _set_pause(on: bool) -> void:
	_pause.visible = on
	if on:
		_close_chat()
		_pause_admin.visible = client.is_admin
		_pause_admin.text = "Панель администратора (%s)" % Options.key_text("admin")


func _open_chat(start: String = "") -> void:
	_chat_input.visible = true
	_chat_input.text = start
	_chat_input.grab_focus()
	_chat_input.caret_column = start.length()


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


func _on_chat(from_id: int, channel: int, text: String) -> void:
	if from_id == Net.SYSTEM_ID:
		_say("[color=#ffb14a][b]Корабль:[/b] %s[/color]" % _escape(text))
		return
	var colour := NAME_COLOURS[client.player_colour(from_id) % NAME_COLOURS.size()]
	var how: String = {Net.CHAT_RADIO: "[color=#7fd88f][рация][/color] ", Net.CHAT_INTERCOM: "[color=#8fc4ff][интерком][/color] ",
		Net.CHAT_DEAD: "[color=#8a8f9c][мёртвые][/color] "}.get(channel, "")
	_say("%s[color=#%s][b]%s:[/b][/color] %s" % [how, colour, _escape(client.player_name(from_id)), _escape(text)])


func _on_notice(text: String) -> void:
	_say("[color=#9aa3b5]%s[/color]" % _escape(text))


func _capital(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _on_slots_input(event: InputEvent) -> void:
	## A click on a slot takes what is in it into the hand.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var k := _bar_at(Vector2.ZERO, (event as InputEventMouseButton).position, SLOT_PX, SLOT_GAP)
		if k >= 0 and k < Net.WORN:
			client.send_wear(k)                                      # take it off, into the hand
		elif k >= Net.WORN and client.usable(k - Net.WORN):
			client.send_hand(k - Net.WORN)
		_slots_view.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if _open(_options):
		return                               # the settings window takes the keys itself
	var typing := _chat_input.visible
	var free_hands := not typing and not _pause.visible and not _console.visible
	if free_hands and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# the wheel turns through the slots
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_LEFT:
			_click_world()
			get_viewport().set_input_as_handled()
			return
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			var next := client.hand
			for step in Net.SLOTS:
				next = posmod(next + (-1 if button == MOUSE_BUTTON_WHEEL_UP else 1), Net.SLOTS)
				if client.usable(next):
					break
			client.send_hand(next)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey):
		return
	var done := true
	if Options.pressed(event, "pause"):
		if typing:
			_close_chat()
		elif _console.visible:
			_open_console(0)
		elif _open(_inventory) or _open(_admin):
			for panel: Control in [_inventory, _admin]:
				if panel != null:
					panel.visible = false
		else:
			_set_pause(not _pause.visible)
	elif typing:
		done = false
	elif Options.pressed(event, "info"):
		_info_on = not _info_on
		_keys.visible = _info_on
		_info_timer = 0.0
	elif Options.pressed(event, "debug"):
		show_debug(not _debug.visible)
	elif Options.pressed(event, "toggle_predict"):
		client.predict = not client.predict
	elif Options.pressed(event, "respawn"):
		client.send_respawn()
	elif _pause.visible:
		done = false
	elif Options.pressed(event, "use") and _console.visible:
		_open_console(0)                                # the key closes a screen it opened
	elif _console.visible:
		done = false
	elif Options.pressed(event, "use") and _use_screen(client.use_target()):
		pass
	elif Options.pressed(event, "drag"):
		if client.dragging():
			client.send_drag(Net.NOBODY)
		elif client.lying_near() >= 0:
			client.send_drag(client.lying_near())
	elif Options.pressed(event, "suit"):
		client.send_suit(not client.supply)
	elif Options.pressed(event, "drop"):
		client.send_drop()
	elif Options.pressed(event, "act"):
		client.send_act()
	elif Options.pressed(event, "inventory"):
		_inventory_panel().toggle()
	elif Options.pressed(event, "admin"):
		if client.is_admin:
			_admin_panel().toggle()
	elif Options.pressed(event, "chat"):
		_open_chat()
	elif Options.pressed(event, "radio"):
		_open_chat(Net.CHAT_RADIO_MARK + " ")
	else:
		done = false
		for i in Net.SLOTS:
			if Options.pressed(event, "slot_%d" % (i + 1)):
				client.send_hand(i)
				done = true
				break
	if done:
		get_viewport().set_input_as_handled()


func _use_screen(target: int) -> bool:
	## What the "use" key (or a click) opens: a bridge console, the locker, the
	## pockets of somebody lying, an intercom to speak into. False = none of those.
	if target == 13:
		client.send_search(client.lying_near())          # the screen opens when the server agrees
	elif target == 19:
		_open_chat(Net.CHAT_INTERCOM_MARK + " ")
	elif _opens_panel(target):
		_open_console(target)
	else:
		return false
	return true


func _click_world() -> void:
	## A left click in the world. On something within reach that the "use" key
	## works on (a console, a machine, a door, a hole, a thing on the floor,
	## somebody lying, the ladder underfoot) it turns our character to it and
	## uses it, as E would; held down it holds E. Anywhere else it uses the thing
	## in the hand there: shoot, strike, bandage.
	click_at(_world.cell_under_mouse())


func click_at(at: Vector2) -> void:
	## A left click on that place (in cells of the whole grid; see _click_world).
	var c := Vector2i(roundi(at.x), roundi(at.y))
	var f := -1 if _fires_at(c) else client.click_facing(c)
	if f < 0:
		client.turn_to(at)                   # the character turns to where it is clicked
		client.send_fire(at)
		return
	client.face(f)
	_click_facing = f
	_click_until = Time.get_ticks_msec() / 1000.0 + 0.6


func _fires_at(c: Vector2i) -> bool:
	## Is a click on this cell meant for the thing in the hand rather than for
	## what lies there: a weapon or something to heal with, aimed at somebody (or at ourselves)?
	var item := client.in_hand()
	if not (Items.is_weapon(item) or Items.uses(item) >= 0 or (Items.INFO.has(item) and Items.INFO[item].has("heal"))):
		return false
	if c == Vector2i(client.pred.x, client.pred.y):
		return true
	for e: GameClient.Ent in client.ents.values():
		if e.id != client.my_id and e.x == c.x and e.y == c.y:
			return true
	return false


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
	if _chat_input.visible and Options.pressed(event, "pause"):
		_close_chat()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if client == null:
		return
	# which way to walk: the most recently pressed of the held direction keys
	var busy := _chat_input.visible or _pause.visible or _console.visible or _open(_options)
	_update_console()
	for m: Array in MOVES:
		var dir: int = m[1]
		var down := Options.held(m[0]) and not busy
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
				client.send_use(true)        # happened to stop on a ladder or by a thing on the floor: take it
				client.send_use(false)
			elif _rng.randf() < 0.08:
				client.send_hand(_rng.randi_range(0, Net.SLOTS - 1))
				client.send_drop()           # and now and then leave something lying about
		want = _demo_dir
	if forced_dir >= 0:
		want = forced_dir
	client.want_dir = want

	# a click on something to use: once our character has turned to it, it is used as with the key
	if _click_facing > 0:
		if client.pred.facing == _click_facing:
			_click_facing = 0
			if not busy and not _use_screen(client.use_target()):
				_mouse_use = true
		elif Time.get_ticks_msec() / 1000.0 > _click_until:
			_click_facing = 0
	# the "use" key: tell the server when it goes down or up
	var use_now := (Options.held("use") and not busy) or forced_use or (_mouse_use and not busy)
	if _mouse_use and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_use = false                   # (after this frame: a quick click still presses once)
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
	elif target == 8 and client.map.guns.has(client.use_cell()):
		var g := client.map.guns.find(client.use_cell())
		var c: int = client.gun_charge[g] if g < client.gun_charge.size() else 0
		_hint.text = "Орудие %d: %s. Стреляют с пульта орудий на мостике" % [g + 1, "нет питания" if no_power else ("готово" if c >= 100 else "заряжается, %d%%" % c)]
	elif target == 17:
		_hint.text = "Пульт орудий обесточен: %s" % why if no_power else "E: пульт орудий"
	elif target == 8:
		var state := "нет питания" if no_power else "работает"
		if client.map.air_plant.has(client.use_cell()) and not no_power:
			state = "работает, воздуха в запасе %d из %d" % [int(round(client.store_air)), int(Net.STORE_AIR_FULL)] if client.store_air > 0.0 \
				else "стоит, запас воздуха исчерпан"
		_hint.text = "%s: %s" % [_capital(client.map.device_name(client.use_cell())), state]
	elif target == 12:
		_hint.text = "E: шкаф снабжения (склад корабля)"
	elif target == 20:
		_hint.text = "Голокарта обесточена: %s" % why if no_power else "E: голокарта корабля (воздух, пробоины, поломки)"
	elif target == 19:
		_hint.text = "Интерком обесточен: %s" % why if no_power else "E: сказать в интерком (услышат у всех панелей)"
	elif target == 18:
		var room: String = Net.ACCESS_NAMES.get(client.map.door_access[client.map.door_of[client.use_cell()]], "отсек")
		_hint.text = "Взламываю замок…" if (_use_held and client.work > 0) else "Нет доступа: %s. Держите E, чтобы взломать замок (услышит весь корабль)" % room
	elif target == 14:
		var cell := client.floor_cell()
		var more: int = Net.FLOOR_STACK - (client.floor_things[cell] as PackedByteArray).count(Net.ITEM_NONE) - 1
		var room := false
		for i in Net.SLOTS:
			room = room or (client.usable(i) and client.slots[i] == Net.ITEM_NONE)
		_hint.text = "На полу: %s%s.  %s" % [Items.name_of(client.top_thing(cell)).to_lower(),
			(" и ещё %d" % more) if more > 0 else "", "E или щелчок: поднять" if room else "Некуда взять: все слоты заняты"]
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
	elif target == 15:
		var pump := client.use_cell()
		var lock: Dictionary = client.map.lock_pump[pump]
		if client.pumps.has(pump):
			_hint.text = "Насос шлюза %s воздух.  E: остановить" % ("откачивает" if int(client.pumps[pump]) == 1 else "закачивает")
		elif no_power:
			_hint.text = "Насос шлюза обесточен: %s" % why
		elif not (client.doors.is_shut(int(lock["inner"])) and client.doors.is_shut(int(lock["outer"]))):
			_hint.text = "Насос шлюза: сначала должны закрыться обе двери"
		elif client.lock_air(pump) > 0.5:
			_hint.text = "E: откачать воздух из шлюза (наружная дверь откроется, когда воздуха не останется)"
		elif client.store_air <= 0.0:
			_hint.text = "Насос шлюза: запас воздуха пуст, закачать нечего"
		else:
			_hint.text = "E: закачать воздух в шлюз (внутренняя дверь откроется, когда давление выровняется)"
	elif target == 16:
		_hint.text = "Снимаю блокировку двери шлюза…" if (_use_held and client.work > 0) else \
			"Дверь шлюза не откроется, пока не закрыта вторая.\nДержите E, чтобы снять блокировку вручную"
	elif target == 10:
		_hint.text = "Чиню дверь…" if (_use_held and client.work > 0) else "Дверь заклинило открытой. Держите E, чтобы починить%s" % no_part
	elif target == 11:
		if _use_held and client.work > 0:
			_hint.text = "Чиню аварийный шлюз…"
		elif client.doors.is_sealed(client.map.door_of[client.use_cell()]):
			_hint.text = "Аварийный шлюз неисправен: упал и сам не поднимется.\nДержите E, чтобы починить%s" % no_part
		else:
			_hint.text = "Аварийный шлюз неисправен: при разгерметизации не сработает.\nДержите E, чтобы починить%s" % no_part
	_hint.text = Options.keyed(_hint.text)
	_work_bar.visible = (target == 1 or target == 5 or target >= 9 or Items.uses(client.in_hand()) > 0) and client.work > 0
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
	_lamp("o2_off", alive and client.has_suit() and not client.supply)
	_tank_bar.visible = alive and client.has_suit()          # the tank is the suit's
	_slots_view.visible = alive
	if client.slots + client.worn != _slots_shown or client.hand != _hand_shown:
		_slots_shown = client.slots + client.worn
		_hand_shown = client.hand
		_slots_view.queue_redraw()
		var item := client.in_hand()
		if item == Net.ITEM_NONE:
			_hand_label.text = "Рука пуста"
		else:
			var switch := Items.switched(item)
			var extra := ""
			if switch != Net.ITEM_NONE:
				extra = "    Z: %s" % ("выключить" if not Items.light(item).is_empty() else "включить")
			var rounds := Items.rounds(item)
			var info: Dictionary = Items.INFO.get(item, {})
			var what := Items.name_of(item).to_lower()
			if rounds > 0:
				what += " (%d из %d)" % [rounds, Net.PISTOL_ROUNDS]
				extra = "    Щелчок: выстрел"
			elif rounds == 0:
				what += " (пуст)"
				extra = "    Щелчок: перезарядить" if client.carried(Net.ITEM_MAG) > 0 else "    Нужен магазин"
			elif info.has("blow"):
				extra = "    Щелчок рядом: удар"
			elif info.has("heal"):
				extra = "    Щелчок по себе или соседу: заклеить раны"
			elif Items.worn_as(item) >= 0:
				if Items.tank_of(item) >= 0:
					what += " (кислорода %d%%)" % (Items.tank_of(item) * 100 / Net.SUIT_TANK_STEPS)
				extra = "    Z: надеть"
			elif Items.uses(item) > 0:
				what += " (%d из %d)" % [Items.uses(item), Net.MEDKIT_USES]
				extra = "    Щелчок по себе или соседу: лечить, 3 с не двигаясь"
			_hand_label.text = Options.keyed("В руке: %s%s    G: положить" % [what, extra])
		# a weapon in the hand shows a sight instead of the arrow
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if Items.is_weapon(item) or Items.INFO.get(item, {}).has("heal") or Items.uses(item) > 0 else Input.CURSOR_ARROW)
	_hand_label.visible = alive
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
		if client.reserve > 0:
			_fate.text = "Вы погибли. Нажмите R, чтобы вернуться новым членом экипажа из резерва (в резерве: %d)." % client.reserve
		else:
			_fate.text = "Вы погибли. Резерв экипажа пуст: вернуться можно, когда товарищи наймут людей у торговца."
	_fate.text = Options.keyed(_fate.text)
	_fate.visible = client.my_cond != Net.COND_OK and client.over == Net.OVER_NONE
	_over.visible = client.over != Net.OVER_NONE
	if _over.visible:
		_over_text.text = "КАМПАНИЯ ОКОНЧЕНА\n\n%s\n\nПройдено секторов: %d\nДальше всего от начала пути: %d прыжков\nПрыжков сделано: %d\nПродержались: %s\n\nНовую кампанию начинает хозяин игры: выйти в меню и создать игру заново." % [
			"Корабль разрушен: обшивка не выдержала." if client.over == Net.OVER_WRECKED else "Экипаж погиб, и заменить его некем.",
			client.sectors_seen, client.farthest, client.jumps, _voyage(client.voyage_seconds)]
	_shade.color.a = lerpf(_shade.color.a, dark, 1.0 - exp(-delta * 4.0))

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
		_info.visible = _info_on or Options.show_fps
		_info.text = "Кадров: %d" % int(round(_fps_smooth))
	if _info_timer <= 0.0 and _info_on:
		_info.text = "На борту: %d     Резерв: %d     Обшивка: %d%%     Пинг: %d мс     Сектор: %s" % [client.crew_count(),
			client.reserve, client.hull * 100 / Net.HULL_MAX, int(round(client.rtt_ms)),
			client.sectors.describe(client.sector) if client.sectors.count > 0 else "?"]
		if client.map.deck_count > 1:
			_info.text += "     %s" % client.map.deck_names[client.my_deck()]
		if Options.show_fps:
			_info.text += "     Кадров: %d" % int(round(_fps_smooth))
		_info.text += "\n%s     Навыки: %s" % [Net.JOB_NAMES[client.job], _skills_text()]
		if _debug.visible:
			_debug.text = "тик сервера: %d\nпредсказание: %s (F4), исправлено шагов: %d\nсверка состояния: %d без расхождений, %d с расхождением\nпринято: %d пакетов, %.1f КБ\nкадров в секунду: %d\nздоровье: %d, давление здесь: %d кПа, баллон: %d%%" % [
				client.server_tick, "вкл" if client.predict else "выкл", client.mispredicts,
				client.checks_ok, client.checks_bad, client.packets_in, client.bytes_in / 1024.0,
				int(round(_fps_smooth)), client.health,
				int(round(maxi(client.air_at(client.pred.x, client.pred.y), 0) * Net.KPA_FULL / Net.AIR_FULL)),
				client.tank * 100 / Net.TANK_FULL]
