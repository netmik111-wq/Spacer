extends Node
## Everything shown while playing: the world, the HUD, chat and the pause
## panel. Reads the keyboard and tells the GameClient which way to walk.

signal exit_requested

const Net := preload("res://src/shared/net.gd")
const Sprites := preload("res://src/client/sprites.gd")
const GameClient := preload("res://src/client/game_client.gd")
const WorldView := preload("res://src/client/world_view.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Gear := preload("res://src/shared/gear.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Options := preload("res://src/client/options.gd")
const OptionsPanel := preload("res://src/ui/options_panel.gd")
const AdminPanel := preload("res://src/ui/admin_panel.gd")
const InventoryPanel := preload("res://src/ui/inventory_panel.gd")
const CrewPanel := preload("res://src/ui/crew_panel.gd")
const HelpBook := preload("res://src/ui/help_book.gd")
const FirstShift := preload("res://src/ui/first_shift.gd")
const StoreView := preload("res://src/ui/store_view.gd")
const GunsView := preload("res://src/ui/guns_view.gd")
const TradeView := preload("res://src/ui/trade_view.gd")
const HoloView := preload("res://src/ui/holo_view.gd")
const DroneView := preload("res://src/ui/drone_view.gd")
const BenchView := preload("res://src/ui/bench_view.gd")
const GalleyView := preload("res://src/ui/galley_view.gd")
const Upkeep := preload("res://src/shared/upkeep.gd")
const PowerView := preload("res://src/ui/power_view.gd")
const CommsView := preload("res://src/ui/comms_view.gd")
const Plants := preload("res://src/shared/plants.gd")
const BridgeView := preload("res://src/ui/bridge_view.gd")
const Look := preload("res://src/ui/look.gd")
const BugReport := preload("res://src/client/bug_report.gd")

const MOVES := [["move_up", 1], ["move_down", 2], ["move_left", 3], ["move_right", 4]]
const CHAT_LINES := 9
const CHAT_ROOM := 278.0             # (v77) the height the chat lines may take, in pixels (the box's own)
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
var scripted_look := false           # (v77) test mode: look where one walks, whatever the setting (scripted walks turn by walking)
var aim_cells := Vector2.INF         # (v77) test mode: the mouse is taken to be this many cells from our character
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
var _won_known := false              # (v57) we have seen the flagship beaten (shown once, for VICTORY_SECONDS)
var _victory_left := 0.0
var _life := 0.0                     # seconds this screen has been up
const VICTORY_SECONDS := 15.0
const LAMP_NAMES := {               # (v73, the author's H1) what each lamp of the HUD means, when pointed at
	"kpa_low1": "Низкое давление вокруг: долго здесь без скафандра нельзя",
	"kpa_low2": "Давления почти нет: без скафандра и баллона здесь не выжить",
	"o2_low": "В баллоне мало кислорода: заправьте у кислородной стойки",
	"o2_on": "Вы дышите из баллона (Q: перекрыть)",
	"o2_off": "Подача из баллона перекрыта (Q: открыть)"}
var _tank_bar: ColorRect
var _tank_fill: ColorRect
var _hint: Label
var _work_bar: ColorRect
var _hint_rich: RichTextLabel        # (v73, the author's I4) the hint as shown: keys drawn as badges
var _hint_was := ""
static var _badge_rules: Array = []
var _work_fill: ColorRect
var _use_held := false
var _click_facing := 0               # a click on something to use: the way our character is turning to reach it
var _click_until := 0.0              # (given up if the turn has not come by then)
var _mouse_use := false              # the left button holds "use" down, like the key
var _console: PanelContainer         # the screen of a bridge console, shown over the game
var _console_kind := 0               # 3 = sector console, 4 = ship's controls (as GameClient.use_target)
var _console_title: Label
var _needs_box: VBoxContainer        # (v73) the bridge's alert panel (Look.needs)
var _needs_shown := []
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
var _drone_view: DroneView           # (v54) the drone monitor's screen, set up when first shown
var _bench_view: BenchView           # (v58) the workbench's screen, set up when first shown
var _galley_view: GalleyView         # (v71) the galley stove's screen, the same way
var _power_view: PowerView           # (v61) an SMES's terminal, set up when first shown
var _comms_view: CommsView           # (v63) the comms console, set up when first shown
var _slots_view: Control             # what our character carries, slot by slot
var _slots_shown := PackedByteArray()
var _drag_slot := -1                 # (v73) the slot whose thing is being dragged along the bar
var _hand_shown := -1
var _hand_label: Label               # what is in the hand, over the slots
var _hurt_label: Label               # (v70) our injuries, over that
var _jump_label: Label
var _flash: ColorRect
var _alert_label: Label              # (v68) the alert level, over the screen while it is not green
var _alert_tint: ColorRect           # (v68) a slow red pulse over the screen on red alert
var _pause_people: Label             # (v75) the people in the game, in the Esc menu
var _pause_shot: Image               # (v75) the screen when the Esc menu opened, for a bug report
var _give_up := 0.0                    # (v76) seconds R has been held while out cold
const GIVE_UP_SECONDS := 2
var _alert_time := 0.0
var _monitor_step := 0.08
var _monitor_time := 0.0
var _chat_box: VBoxContainer
var _chat_lines: Array = []          # [RichTextLabel, time it was added]
var _chat_hist: Array = []           # (v73, the author's H3) [tab, bbcode, time, text it is known by, times said]
var _chat_tab := 0                   # CHAT_TABS: what the chat shows
var _chat_tabs: HBoxContainer        # the tabs, shown while the chat is open
var _bot_log_seen := 0
const CHAT_TABS := ["Всё", "Корабль", "Рация", "Боты"]
const TAB_ALL := 0
const TAB_SHIP := 1
const TAB_RADIO := 2
const TAB_BOTS := 3
const TAB_SAY := 9                   # (a line spoken aloud: shown under "Всё" only)
const MERGE_SECONDS := 60.0          # a line said again within this long joins the last one ("×3")
var _chat_input: LineEdit
var _pause: PanelContainer
var _pause_admin: Button             # opens the admin panel; shown while the server counts us an admin
var _options: OptionsPanel
var _admin: AdminPanel
var _inventory: InventoryPanel
var _crew: CrewPanel
var _book: HelpBook                  # (v74) the help book (H)
var _shift: FirstShift               # (v74) the first shift's checklist
var _root: Control                   # (the windows above are made when first opened: making them
                                     # while joining would hold up the client's clock)
var _held: Array[int] = []
var _info_timer := 0.0
var _fps_smooth := 60.0
var _demo_until := 0.0
var _demo_dir := 0
var _rng := RandomNumberGenerator.new()
var _banner: PanelContainer          # (v73, the author's H4) a danger, big at the top of the screen
var _banner_text: Label
var _banner_left := 0.0
var _hull_warned := false            # the hull's own banner was shown (again once it is mended)
const BANNER_SECONDS := 4.0
var _look: PanelContainer            # (v73, the author's L3) the name of what is under the mouse
var _look_text: Label
var _look_cell := -2
var _menu: PopupMenu                 # (v73, the author's I1 and B1) the right-click menu of what can be done there
var _menu_acts: Array = []           # per item id: a Callable
var _menu_hold := false              # "work" chosen from the menu: "use" stays held until the job is done
var _menu_hold_until := 0.0
var _menu_worked := false
var _step_dir := 0                   # (v73, the author's I1 note) a step to the side, then use what was diagonal
var _step_from := Vector2i.ZERO
var _step_then := Vector2.ZERO
var _step_until := 0.0


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
	_shift = FirstShift.new()
	root.add_child(_shift)
	_shift.setup(client)

	# heartbeat monitor from the reference HUD (decorative until health exists)
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hud_monitor.json"))
	var sheet: Texture2D = Sprites.sheet("hud_monitor")
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
		_monitor.mouse_filter = Control.MOUSE_FILTER_PASS      # (v73, H1) for its label when pointed at
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
		var lamps: Texture2D = Sprites.sheet("hud_alerts")
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
			node.mouse_filter = Control.MOUSE_FILTER_PASS
			node.tooltip_text = LAMP_NAMES.get(lamp, "")
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
	_slots_view.draw.connect(func() -> void: _draw_slots(_slots_view, Vector2.ZERO, client.slots, client.worn, SLOT_PX, SLOT_GAP, client.hand, true))
	_slots_view.gui_input.connect(_on_slots_input)
	root.add_child(_slots_view)
	_hand_label = _text(root, 14)
	_hand_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hand_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hand_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hand_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hand_label.offset_right = _slots_view.offset_right
	_hand_label.offset_bottom = _slots_view.offset_top - 6
	_hurt_label = _text(root, 14)
	_hurt_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hurt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hurt_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hurt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hurt_label.offset_right = _slots_view.offset_right
	_hurt_label.offset_bottom = _hand_label.offset_bottom - 22
	_hurt_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))

	# how much oxygen the suit's tank holds: a bar drawn in code beside the monitor
	_tank_bar = ColorRect.new()
	_tank_bar.color = Color(0.13, 0.1, 0.19)
	_tank_bar.mouse_filter = Control.MOUSE_FILTER_PASS
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
	_hint.self_modulate.a = 0.0             # (v73) only measured: _hint_rich draws it
	_hint_rich = RichTextLabel.new()
	_hint_rich.bbcode_enabled = true
	_hint_rich.fit_content = true
	_hint_rich.scroll_active = false
	_hint_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_rich.add_theme_font_size_override("normal_font_size", 16)
	_hint_rich.add_theme_color_override("default_color", Color(0.95, 0.96, 1.0))
	_hint_rich.add_theme_constant_override("outline_size", 4)
	_hint_rich.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hint_rich.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_rich.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_rich.offset_left = HINT_LEFT
	_hint_rich.offset_right = -HINT_RIGHT
	_hint_rich.offset_bottom = -92
	_hint_rich.visible = false
	root.add_child(_hint_rich)
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
	_chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN   # (v77) taller than its room it grows up, never under the input line
	root.add_child(_chat_box)
	_chat_tabs = HBoxContainer.new()
	_chat_tabs.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_tabs.offset_left = 14
	_chat_tabs.offset_right = 540
	_chat_tabs.offset_top = -362
	_chat_tabs.offset_bottom = -334
	_chat_tabs.visible = false
	root.add_child(_chat_tabs)
	for k in CHAT_TABS.size():
		var tab := Button.new()
		tab.text = CHAT_TABS[k]
		tab.toggle_mode = true
		tab.button_pressed = k == 0
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 13)
		tab.tooltip_text = ["Все сообщения", "Сообщения корабля и предупреждения", "Рация и интерком", "Журнал ботов: что они делают"][k]
		tab.pressed.connect(func() -> void: _show_tab(k))
		_chat_tabs.add_child(tab)

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

	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.32, 0.04, 0.03, 0.88)
	banner_style.border_color = Color(1.0, 0.45, 0.3, 0.9)
	banner_style.set_border_width_all(2)
	banner_style.set_corner_radius_all(4)
	banner_style.content_margin_left = 22
	banner_style.content_margin_right = 22
	banner_style.content_margin_top = 10
	banner_style.content_margin_bottom = 10
	_banner.add_theme_stylebox_override("panel", banner_style)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 84
	_banner.visible = false
	root.add_child(_banner)
	_banner_text = _text(_banner, 20)
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_text.custom_minimum_size.x = 520

	_look = PanelContainer.new()
	_look.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look_style := StyleBoxFlat.new()
	look_style.bg_color = Color(0.05, 0.06, 0.09, 0.88)
	look_style.border_color = Color(0.45, 0.5, 0.6, 0.6)
	look_style.set_border_width_all(1)
	look_style.set_corner_radius_all(3)
	look_style.set_content_margin_all(6)
	_look.add_theme_stylebox_override("panel", look_style)
	_look.visible = false
	root.add_child(_look)
	_look_text = _text(_look, 14)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < _menu_acts.size():
			(_menu_acts[id] as Callable).call())
	root.add_child(_menu)

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
	_alert_tint = ColorRect.new()
	_alert_tint.color = Color(0.9, 0.05, 0.02, 0.0)
	_alert_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_alert_tint)
	_alert_label = _text(root, 15)
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alert_label.offset_top = 32
	_alert_label.visible = false
	_flash = ColorRect.new()
	_flash.color = Color(0.85, 0.93, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_flash)
	client.arrived.connect(func() -> void:
		if Options.flash:
			_flash.color.a = 0.9)
	_rng.randomize()
	_say("[color=#9aa3b5]Вы на борту. %s: чат, %s: сведения о корабле и подсказки клавиш, %s: книга помощи.[/color]" % [
		_escape(Options.key_text("chat")), _escape(Options.key_text("info")), _escape(Options.key_text("help"))])
	if hosting and not host_addresses().is_empty():
		# (v75, the author's E2) the host is told where friends join; Esc has a button that copies it
		_say("[color=#9aa3b5]Адрес для друзей: %s:%d (Esc: скопировать).[/color]" % [host_addresses()[0], host_port])


func _inventory_panel() -> InventoryPanel:
	if _inventory == null:
		_inventory = InventoryPanel.new()
		_root.add_child(_inventory)
		_inventory.setup(client)
		_root.move_child(_inventory, _pause.get_index())
	return _inventory


func _crew_panel() -> CrewPanel:
	if _crew == null:
		_crew = CrewPanel.new()
		_root.add_child(_crew)
		_crew.setup(client)
		_root.move_child(_crew, _pause.get_index())
	return _crew


func _help_book() -> HelpBook:
	if _book == null:
		_book = HelpBook.new()
		_root.add_child(_book)
		_book.setup()
		_root.move_child(_book, _pause.get_index())
	return _book


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
	_keys.text = "%s%s%s%s: ходить    %s: действие    %s: тащить    %s: подача O2    %s: инвентарь    %s: экипаж    %s: книга помощи    %s: чат    %s: меню\n1–6 или колесо: что в руке    Щелчок: взять, пульт, машина или применить    %s: применить    %s: положить" % [
		Options.key_text("move_up"), Options.key_text("move_left"), Options.key_text("move_down"), Options.key_text("move_right"), Options.key_text("use"), Options.key_text("drag"),
		Options.key_text("suit"), Options.key_text("inventory"), Options.key_text("crew"), Options.key_text("help"), Options.key_text("chat"), Options.key_text("pause"), Options.key_text("act"), Options.key_text("drop")]


func _skills_text() -> String:
	var parts: Array[String] = []
	for i in Net.SKILLS:
		parts.append("%s %d" % [Net.SKILL_NAMES[i], client.skills[i]])
	return ", ".join(parts)


func _story() -> String:
	## (v75, the author's E1) What the run came to, beyond the road: fights, money, the dead.
	var sm := client.summary
	if sm.is_empty():
		return ""
	var out := "\nПиратских кораблей разбито: %d\nПиратов убито на борту: %d\nЗаработано кредитов: %d" % [int(sm["ships"]), int(sm["boarders"]), int(sm["earned"])]
	var deaths: Array = sm["deaths"]
	if deaths.is_empty():
		out += "\nПогибших нет"
	else:
		var lines := PackedStringArray()
		for d: Array in deaths.slice(maxi(deaths.size() - 6, 0)):
			lines.append("%s: %s" % [d[0], d[1]])
		out += "\nПогибли (%d): %s" % [deaths.size(), ", ".join(lines)]
	return out


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
	# (v73, the author's C1) the title, and an ✕ that closes the screen (as Esc and E do)
	var head := HBoxContainer.new()
	box.add_child(head)
	var balance := Control.new()
	balance.custom_minimum_size = Vector2(32, 0)
	head.add_child(balance)
	_console_title = Label.new()
	_console_title.add_theme_font_size_override("font_size", 20)
	_console_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_console_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_console_title)
	var cross := Button.new()
	cross.text = "✕"
	cross.flat = true
	cross.focus_mode = Control.FOCUS_NONE
	cross.custom_minimum_size = Vector2(32, 32)
	cross.tooltip_text = "Закрыть (Esc)"
	cross.add_theme_font_size_override("font_size", 18)
	cross.pressed.connect(func() -> void: _open_console(0))
	head.add_child(cross)
	# (v73, the author's L2) the ship's alert panel on the bridge's consoles: what is low or broken
	_needs_box = VBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 2)
	_needs_box.visible = false
	box.add_child(_needs_box)
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
	_drone_view = DroneView.new()
	_drone_view.visible = false
	box.add_child(_drone_view)
	_bench_view = BenchView.new()
	_bench_view.visible = false
	box.add_child(_bench_view)
	_galley_view = GalleyView.new()
	_galley_view.visible = false
	box.add_child(_galley_view)
	_power_view = PowerView.new()
	_power_view.visible = false
	box.add_child(_power_view)
	_comms_view = CommsView.new()
	_comms_view.visible = false
	box.add_child(_comms_view)
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
	## The bridge consoles and the holomap need power (v61: the bridge's backup SMES keeps those in its
	## room going); the supply locker and the workbench are worked by hand, an SMES's terminal is its own.
	return target == 12 or target == 22 or target == 28 or ((target == 3 or target == 4 or target == 17 or target == 20 or target == 21
		or target == 30 or target == 44) and client.power_at(client.use_cell()))


func _open_console(kind: int) -> void:
	if _console_kind == 13 and kind != 13 and client.search_id >= 0:
		client.send_search(Net.NOBODY)       # we step back from the one we were searching
		client.search_id = -1
	if _console_kind == 20 and kind != 20:
		client.send_holo(false)
	if _console_kind == 21 and kind != 21:
		_drone_view.closed()
	if _console_kind == 22 and kind != 22:
		_bench_view.closed()
	if _console_kind == 44 and kind != 44:
		_galley_view.closed()
	_console_kind = kind
	_console.visible = kind != 0
	if kind == 0:
		return
	if kind == 12 or kind == 4:
		_shift.mark(FirstShift.LOCKER if kind == 12 else FirstShift.HELM)
	_close_chat()
	_bridge.buttons_for = -1
	var own_view := kind == 12 or kind == 17 or kind == 20 or kind == 21 or kind == 22 or kind == 28 or kind == 30 or kind == 44
	_trading = false
	if kind == 17 and _guns_view.client == null:
		_guns_view.setup(client)
	if kind == 21 and _drone_view.client == null:
		_drone_view.setup(client)
	if kind == 22 and _bench_view.client == null:
		_bench_view.setup(client)
	if kind == 44 and _galley_view.client == null:
		_galley_view.setup(client)
	if kind == 30 and _comms_view.client == null:
		_comms_view.setup(client)
	if kind == 28:
		if _power_view.client == null:
			_power_view.setup(client)
		_power_view.cell = client.use_cell()
	_store_view.visible = kind == 12
	_trade_view.visible = false
	_guns_view.visible = kind == 17
	_holo_view.visible = kind == 20
	_drone_view.visible = kind == 21
	_bench_view.visible = kind == 22
	_galley_view.visible = kind == 44
	_power_view.visible = kind == 28
	_comms_view.visible = kind == 30
	_chart.visible = not own_view
	_console_text.visible = not own_view
	_needs_box.visible = kind == 3 or kind == 4
	_needs_shown = []
	_jump_box.visible = not own_view
	_jump_box.columns = 2
	_console_style.border_color = Color(0.75, 0.62, 0.38) if kind == 12 else (Color(0.85, 0.4, 0.3) if kind == 17 else
		(Color(0.35, 0.7, 0.9) if kind == 20 else (Color(0.35, 0.9, 0.95) if kind == 21 else (Color(0.8, 0.65, 0.35) if kind == 22 or kind == 44 else (Color(0.9, 0.8, 0.3) if kind == 28 else (Color(0.45, 0.75, 1.0) if kind == 30 else Color(0.3, 0.75, 0.45)))))))
	_console_title.text = {3: "Карта сектора", 4: "Управление кораблём", 17: "Пульт орудий", 12: "Склад корабля: шкаф снабжения",
		13: "Обыск", 20: "Голокарта корабля", 21: "Монитор дрона-разведчика", 22: "Верстак: орудия из шкафа снабжения",
		28: _power_view.title() if kind == 28 else "", 30: "Пульт связи", 44: "Камбуз: плита"}.get(kind, "")
	if kind == 20:
		_holo_view.opened()
		client.send_holo(true)
	if kind == 21:
		_drone_view.opened()
	_console_shut.text = Options.keyed("Отойти от верстака (E или Esc)" if kind == 22 else ("Отойти от плиты (E или Esc)" if kind == 44 else ("Закрыть шкаф (E или Esc)" if kind == 12 else ("Закончить обыск (E или Esc)" if kind == 13 else "Отойти от пульта (E или Esc)"))))


func _show_trade(on: bool) -> void:
	## The supply locker's frame shows the trader's screen, or the locker's own.
	_trading = on
	if on and _trade_view.client == null:
		_trade_view.setup(client)
	_store_view.visible = not on
	_trade_view.visible = on
	_console_title.text = ("Станция снабжения" if client.at_station() else "Торговец") if on else "Склад корабля: шкаф снабжения"
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
	if _console_kind == 21:
		_drone_view.refresh(get_process_delta_time())
		return
	if _console_kind == 22:
		_bench_view.refresh()
		return
	if _console_kind == 44:
		_galley_view.refresh()
		return
	if _console_kind == 28:
		_power_view.refresh()
		return
	if _console_kind == 30:
		_comms_view.refresh()
		return
	_update_needs()
	if _console_kind == 4:
		_bridge.update_helm()
		return
	_bridge.update_chart()


const NEED_COLOURS := [Color(0.45, 0.85, 0.5), Color(0.98, 0.8, 0.3), Color(1.0, 0.42, 0.35)]


func _update_needs() -> void:
	## (v73, the author's L2) One line per need of the ship, coloured green, yellow
	## or red, worst first; rebuilt only when it changes.
	var needs := Look.needs(client)
	if needs == _needs_shown:
		return
	_needs_shown = needs
	for old in _needs_box.get_children():
		old.queue_free()
	var head := Label.new()
	head.text = "Состояние корабля"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	_needs_box.add_child(head)
	var grid := GridContainer.new()                   # two columns, so a bad day still fits the frame
	grid.columns = 2 if needs.size() > 2 else 1
	grid.add_theme_constant_override("h_separation", 16)
	_needs_box.add_child(grid)
	for n: Array in needs:
		var line := Label.new()
		line.text = "●  " + str(n[1])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(312 if grid.columns == 2 else 640, 0)
		line.add_theme_font_size_override("font_size", 13)
		line.add_theme_color_override("font_color", NEED_COLOURS[int(n[0])])
		grid.add_child(line)


func _lacking(cell: int) -> String:
	## (v71) What mending the thing in that cell lacks (a part, with complex repairs the right
	## one and a toolbox), as Repairs.spare_for and Upkeep.slower count it.
	var want := Upkeep.part_for(client.map, cell) if cell >= 0 else Net.ITEM_PART
	var part := Upkeep.spare(client.complex_repairs, want, func(item: int) -> bool: return client.carried(item) > 0)
	return Upkeep.lacking(client.complex_repairs, part, want, client.toolbox)


func _tray_hint(cell: int, no_power: bool) -> String:
	## (v63) What a hydroponic tray shows, and what holding E does there (see Garden).
	var t: Array = client.garden.get(cell, [0, Net.GROW_EMPTY, 0, 0])
	var working := _use_held and client.work > 0
	match int(t[1]):
		Net.GROW_EMPTY:
			var item: int = client.slots[client.hand]
			if Plants.is_seed(item):
				return "Сажаю…" if working else "Пустой лоток. Держите E, чтобы посадить: %s" % Plants.name_of(item).to_lower()
			return "Сажаю…" if working else "Пустой лоток. Держите E, чтобы посадить лучшие семена из шкафа снабжения"
		Net.GROW_GROWING:
			var what := "%s: %d%%" % [Plants.plant_name(int(t[0])), int(t[2])]
			if int(t[3]) & Net.GARDEN_CARE:
				return "Ухаживаю…" if working else "%s. Требует ухода: держите E%s" % [what, " (скоро завянет!)" if int(t[3]) & Net.GARDEN_NEGLECT else ""]
			if int(t[3]) & Net.GARDEN_DARK:
				return "%s. Без энергии не растёт" % what
			return "%s. Растёт" % what
		Net.GROW_RIPE:
			return "Собираю урожай…" if working else "%s созрел(а). Держите E, чтобы собрать урожай" % Plants.plant_name(int(t[0]))
	return "Расчищаю…" if working else "Растение завяло. Держите E, чтобы расчистить лоток"


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


func _draw_slots(canvas: Control, origin: Vector2, slots: PackedByteArray, worn: PackedByteArray, px: float, gap: float, hand: int = -1, own: bool = false) -> void:
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
				# (v80, the author's note: an empty suit looked full once put on) our own suit shows our tank
				ItemArt.draw(canvas, cell, Items.suit_with(float(client.tank) / Net.TANK_FULL) if k == Net.WEAR_SUIT and own else thing)
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
		if hand >= 0 and i < 6:
			# (v73, the author's H2) the number key of the slot, in its corner
			canvas.draw_string(font, cell.position + Vector2(2, 10), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.8, 0.84, 0.92, 0.7))
		if hand >= 0 and i == _drag_slot:
			canvas.draw_rect(cell.grow(-2.0), Color(0.45, 0.75, 1.0, 0.9), false, 2.0)





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
	_draw_slots(_chart, ours, client.slots, client.worn, px, BIG_SLOT_GAP, -1, true)
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
		var addresses := host_addresses()
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 14)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(380, 0)
		var where := ", ".join(addresses) if not addresses.is_empty() else "не найден"
		info.text = "Вы создали эту игру. Другие игроки в вашей сети подключаются по адресу: %s (порт %d).\nДля игры через интернет порт %d (UDP) нужно открыть на роутере." % [where, host_port, host_port]
		box.add_child(info)
		if not addresses.is_empty():
			# (v75, the author's E2) one click puts the address in the clipboard, to paste to friends
			var copy := Button.new()
			copy.text = "Копировать адрес: %s:%d" % [addresses[0], host_port]
			copy.pressed.connect(func() -> void:
				DisplayServer.clipboard_set("%s:%d" % [addresses[0], host_port])
				copy.text = "Скопировано: %s:%d" % [addresses[0], host_port])
			box.add_child(copy)
	# (v75, the author's E2) who is aboard: the people, not the bots
	_pause_people = Label.new()
	_pause_people.add_theme_font_size_override("font_size", 14)
	_pause_people.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_people.custom_minimum_size = Vector2(380, 0)
	box.add_child(_pause_people)
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
	# (v75, the author's S2) the logs, the save and a picture of the screen, in one zip
	var report := Button.new()
	report.text = "Сообщить об ошибке (собрать журналы в архив)"
	report.pressed.connect(func() -> void:
		var path := BugReport.make(_pause_shot)
		report.text = ("Архив готов: " + path.get_file()) if path != "" else "Не удалось записать архив"
		if path != "":
			OS.shell_show_in_file_manager(path))
	box.add_child(report)
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
		"crew":
			_crew_panel().toggle()
		"help":
			_help_book().toggle()
			_help_book().show_tab(tab)
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


func host_addresses() -> PackedStringArray:
	## (v75) This computer's addresses others can reach, a Radmin VPN one (26.x.x.x) first.
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			if a.begins_with("26."):
				out.insert(0, a)
			else:
				out.append(a)
	return out


func _set_pause(on: bool) -> void:
	_pause.visible = on
	if on:
		_close_chat()
		_pause_shot = get_viewport().get_texture().get_image()   # (the screen as it was, under the menu)
		var names := PackedStringArray()
		for id: int in client.roster.keys():
			if int(client.roster[id]["kind"]) == Net.KIND_PLAYER:
				names.append(client.player_name(id) + (" (вы)" if id == client.my_id else ""))
		_pause_people.text = "В игре: %s" % ", ".join(names)
		_pause_admin.visible = client.is_admin
		_pause_admin.text = "Панель администратора (%s)" % Options.key_text("admin")


func _open_chat(start: String = "") -> void:
	_chat_input.visible = true
	_chat_tabs.visible = true
	_rebuild_chat()                      # more lines while it is open
	_chat_input.text = start
	_chat_input.grab_focus()
	_chat_input.caret_column = start.length()


func _close_chat() -> void:
	_chat_input.release_focus()
	_chat_input.visible = false
	_chat_tabs.visible = false
	if _chat_tab == TAB_BOTS:
		_show_tab(TAB_ALL)                # the bots' log is read with the chat open


func _on_chat_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if not clean.is_empty():
		client.send_chat(clean)
	_close_chat()


func _say(bbcode: String, tab: int = TAB_SHIP, known_by: String = "") -> void:
	## A line in the chat. (v73, the author's H3) Kept per tab; one said again
	## soon after (`known_by` the same) joins the last line as "×N" instead.
	var now := Time.get_ticks_msec() / 1000.0
	if known_by != "" and not _chat_hist.is_empty():
		var last: Array = _chat_hist[_chat_hist.size() - 1]
		if last[3] == known_by and now - float(last[2]) < MERGE_SECONDS:
			last[4] = int(last[4]) + 1
			last[2] = now
			_rebuild_chat()
			return
	_chat_hist.append([tab, bbcode, now, known_by, 1])
	while _chat_hist.size() > 80:
		_chat_hist.pop_front()
	if _chat_tab == TAB_ALL or _chat_tab == tab:
		_add_line(bbcode, now)


func _show_tab(k: int) -> void:
	_chat_tab = k
	for i in _chat_tabs.get_child_count():
		(_chat_tabs.get_child(i) as Button).button_pressed = i == k
	_rebuild_chat()


func _rebuild_chat() -> void:
	for entry: Array in _chat_lines:
		(entry[0] as RichTextLabel).queue_free()
	_chat_lines.clear()
	if _chat_tab == TAB_BOTS:
		var from := maxi(client.bot_log.size() - CHAT_LINES * 2, 0)
		for i in range(from, client.bot_log.size()):
			var l: Array = client.bot_log[i]
			_add_line("[color=#8a93a6]%d:%02d[/color] [color=#9fd0ff]%s:[/color] %s" % [int(l[0]) / 60, int(l[0]) % 60, _escape(str(l[1])), _escape(str(l[2]))],
				Time.get_ticks_msec() / 1000.0)
		return
	var shown: Array = []
	for i in range(_chat_hist.size() - 1, -1, -1):
		var h: Array = _chat_hist[i]
		if _chat_tab == TAB_ALL or int(h[0]) == _chat_tab:
			shown.push_front(h)
			if shown.size() >= CHAT_LINES * 2:
				break
	for h: Array in shown:
		_add_line(str(h[1]) + ("  [color=#c9cfdb]×%d[/color]" % int(h[4]) if int(h[4]) > 1 else ""), float(h[2]))


func _add_line(bbcode: String, at: float) -> void:
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
	_chat_lines.append([line, at])
	while _chat_lines.size() > (CHAT_LINES * 2 if _chat_input.visible else CHAT_LINES):
		(_chat_lines.pop_front()[0] as RichTextLabel).queue_free()


func _on_chat(from_id: int, channel: int, text: String) -> void:
	if from_id == Net.SYSTEM_ID:
		_say("[color=#%s][b]Корабль:[/b] %s[/color]" % ["ff7a5c" if channel == Net.CHAT_ALARM else "ffb14a", _escape(text)], TAB_SHIP, text)
		if channel == Net.CHAT_ALARM:
			show_banner(text)
		return
	var colour := NAME_COLOURS[client.player_colour(from_id) % NAME_COLOURS.size()]
	var how: String = {Net.CHAT_RADIO: "[color=#7fd88f][рация][/color] ", Net.CHAT_INTERCOM: "[color=#8fc4ff][интерком][/color] ",
		Net.CHAT_DEAD: "[color=#8a8f9c][мёртвые][/color] "}.get(channel, "")
	_say("%s[color=#%s][b]%s:[/b][/color] %s" % [how, colour, _escape(client.player_name(from_id)), _escape(text)],
		TAB_RADIO if channel == Net.CHAT_RADIO or channel == Net.CHAT_INTERCOM else TAB_SAY)


func _on_notice(text: String) -> void:
	_say("[color=#9aa3b5]%s[/color]" % _escape(text), TAB_SHIP, text)


func _bay_text() -> String:
	## (v59) What the module bay holds, in words.
	var names := PackedStringArray()
	for g in client.gear_modules:
		names.append(Gear.name_of(g).to_lower() if g != Gear.NONE else "пусто")
	return ", ".join(names)


func _capital(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _on_slots_input(event: InputEvent) -> void:
	## A click on a slot takes what is in it into the hand. (v73, the author's H2)
	## Dragged onto another slot it trades places with what is there; dragged off
	## the bar it is put down on the floor. Pointed at, the slot names its thing.
	if event is InputEventMouseMotion:
		var k := _bar_at(Vector2.ZERO, (event as InputEventMouseMotion).position, SLOT_PX, SLOT_GAP)
		var tip := ""
		if k >= 0 and k < Net.WORN and k < client.worn.size() and client.worn[k] != Net.ITEM_NONE:
			tip = "%s (щелчок: снять)" % Items.name_of(client.worn[k])
		elif k >= Net.WORN and client.usable(k - Net.WORN):
			var thing := client.slots[k - Net.WORN]
			tip = ("%s. Щелчок: в руку, перетащить: в другой слот или на пол" % Items.name_of(thing)) if thing != Net.ITEM_NONE else "Пустой слот"
		_slots_view.tooltip_text = tip
		return
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var at := (event as InputEventMouseButton).position
	var k := _bar_at(Vector2.ZERO, at, SLOT_PX, SLOT_GAP)
	if (event as InputEventMouseButton).pressed:
		if k >= 0 and k < Net.WORN:
			client.send_wear(k)                                      # take it off, into the hand
		elif k >= Net.WORN and client.usable(k - Net.WORN):
			client.send_hand(k - Net.WORN)
			if client.slots[k - Net.WORN] != Net.ITEM_NONE:
				_drag_slot = k - Net.WORN
		_slots_view.accept_event()
		_slots_view.queue_redraw()
		return
	if _drag_slot < 0:
		return
	var from := _drag_slot
	_drag_slot = -1
	_slots_view.queue_redraw()
	if k >= Net.WORN and k - Net.WORN != from and client.usable(k - Net.WORN):
		client.send_swap(from, k - Net.WORN)
	elif k < 0 and not Rect2(Vector2.ZERO, _slots_view.size).grow(6.0).has_point(at):
		client.send_hand(from)
		client.send_drop()                                           # dragged off the bar: put down
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
		if button == MOUSE_BUTTON_RIGHT:
			_open_menu(_world.cell_under_mouse())
			get_viewport().set_input_as_handled()
			return
		if (button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN) and (event as InputEventMouseButton).ctrl_pressed:
			# (v73, the author's H6) Ctrl+wheel zooms; the wheel alone still turns through the slots
			_world.zoom_step = clampi(_world.zoom_step + (1 if button == MOUSE_BUTTON_WHEEL_UP else -1), -1, 1)
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
		elif _open(_inventory) or _open(_admin) or _open(_crew) or _open(_book):
			for panel: Control in [_inventory, _admin, _crew, _book]:
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
	elif Options.pressed(event, "respawn") and client.my_cond == Net.COND_DEAD:
		client.send_respawn()
	elif _pause.visible:
		done = false
	elif Options.pressed(event, "use") and _console.visible:
		_open_console(0)                                # the key closes a screen it opened
	elif _console_kind == 4 and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_SPACE:
		client.send_evade()                             # (v68) the pilot's evade, timed by hand
	elif _console.visible and _console_key(event as InputEventKey):
		pass
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
	elif Options.pressed(event, "lie"):
		client.toggle_prone()                 # (v78)
	elif Options.pressed(event, "hold"):
		var was := client.holds_position()
		client.toggle_hold()                  # (v81, the author's human wall)
		_say("[color=#9fc3ff]%s[/color]" % ("Позиция отпущена." if was else
			"Держите позицию: сквозь вас не пройти, свои стреляют мимо. Любой шаг отпускает."), TAB_SHIP, "hold")
	elif Options.pressed(event, "act"):
		client.send_act()
	elif Options.pressed(event, "inventory"):
		_inventory_panel().toggle()
	elif Options.pressed(event, "crew"):
		_crew_panel().toggle()
	elif Options.pressed(event, "help"):
		_help_book().toggle()
		_shift.mark(FirstShift.HELP)
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


const CONSOLE_KINDS := [3, 4, 17, 20, 21, 28, 30]   # (v70) use_target kinds that are consoles (a concussion keeps one from them)
const DAZED := "Контузия: в глазах двоится, с пультом не разобраться. Пройдёт сама; быстрее с аптечкой или в автодоке под присмотром."


func _console_key(key: InputEventKey) -> bool:
	## (v73, the author's C2) Keys at a console: at the gun console 1..9 fire that
	## gun and Space all that are ready; at the bridge's consoles 1..9 jump by that
	## button; at the supply locker 1..9 pick a tab. The keys are written on the buttons.
	if not key.pressed or key.echo:
		return false
	var n := -1
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
		n = key.physical_keycode - KEY_1
	if _console_kind == 17 and _guns_view.visible:
		if key.physical_keycode == KEY_SPACE:
			client.send_guns(255)
			return true
		if n >= 0:
			client.send_guns(n)
			return true
	elif (_console_kind == 3 or _console_kind == 4) and n >= 0:
		for b in _jump_box.get_children():
			if b is Button and (b as Button).has_meta("fuel") and not (b as Button).disabled and not b.is_queued_for_deletion():
				if n == 0:
					(b as Button).pressed.emit()
					return true
				n -= 1
	elif _console_kind == 12 and _store_view.visible and n >= 0:
		_store_view.pick_tab(n)
		return true
	return false


func _use_screen(target: int) -> bool:
	## What the "use" key (or a click) opens: a bridge console, the locker, the
	## pockets of somebody lying, an intercom to speak into. False = none of those.
	if client.concussed and CONSOLE_KINDS.has(target):
		_on_notice(DAZED)                                # (v70) the server would refuse it too (Systems.at_console)
	elif target == 13:
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
	if f < 0 and not _fires_at(c) and _step_beside(c):
		return                               # (v73) a step to the side first: see _process
	if f < 0:
		client.turn_to(at)                   # the character turns to where it is clicked
		client.send_fire(at)
		return
	client.face(f)
	_click_facing = f
	_click_until = Time.get_ticks_msec() / 1000.0 + 0.6


static func _badges(text: String) -> String:
	## (v73, I4) A hint written with the default keys, with each key and what it
	## does drawn as a badge: "Держите E, чтобы починить" -> [держать E] починить.
	if _badge_rules.is_empty():
		for rule: Array in [["Держите ([EFZGQR])(, чтобы |: )", "⟦держать $1⟧ "], ["Держите ([EFZGQR]) ", "⟦держать $1⟧ "],
				["(?<![A-Za-zА-Яа-яЁё0-9])([EFZGQR]) или щелчок: ", "⟦$1 / ЛКМ⟧ "],
				["(?<![A-Za-zА-Яа-яЁё0-9])([EFZGQR]): ", "⟦$1⟧ "]]:
			_badge_rules.append([RegEx.create_from_string(rule[0]), rule[1]])
	for rule: Array in _badge_rules:
		text = (rule[0] as RegEx).sub(text, rule[1], true)
	text = Options.keyed(text).replace("[", "[lb]")
	return text.replace("⟦", "[bgcolor=#2a3550][color=#ffd970] ").replace("⟧", " [/color][/bgcolor]")


func _fit_root() -> void:
	## (v73, the author's H5) The interface drawn at the size chosen in the settings.
	var view := get_viewport().get_visible_rect().size
	var s := Options.ui_scale
	if _root.scale.x != s or not _root.size.is_equal_approx(view / s):
		_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_root.position = Vector2.ZERO
		_root.scale = Vector2(s, s)
		_root.size = view / s


func show_banner(text: String) -> void:
	## (v73, the author's H4) A danger in big letters for a few seconds, with a chime
	## (heard only where there is air: vacuum stays silent). The first sentence is
	## enough there; the whole line stays in the chat.
	var first := text
	var cut := text.find("! ")
	if cut < 0:
		cut = text.find(". ")
	if cut > 0 and cut < 90:
		first = text.substr(0, cut + 1)
	_banner_text.text = first
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner.reset_size()
	_banner_left = BANNER_SECONDS
	_world.alarm_sound()


func _update_banner(delta: float) -> void:
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(_banner_left / 0.6, 0.0, 1.0)
		_banner.visible = _banner_left > 0.0
	# the hull's own warning, from what the client knows (the server says nothing at that moment)
	var low := client.hull * 10 < client.hull_max * 3 and client.hull > 0
	if low and not _hull_warned:
		_hull_warned = true
		show_banner("Корпус слабеет: %d из %d!" % [client.hull, client.hull_max])
	elif client.hull * 10 >= client.hull_max * 5:
		_hull_warned = false


func _update_look(busy: bool) -> void:
	## (v73, L3) The label beside the mouse: what is there and what a click does.
	var cell := -1
	var hovered := get_viewport().gui_get_hovered_control()
	if not busy and client.my_cond == Net.COND_OK and (hovered == null or hovered == _root):
		var at := _world.cell_under_mouse()
		var c := Vector2i(roundi(at.x), roundi(at.y))
		if c.x >= 0 and c.y >= 0 and c.x < client.map.width and c.y < client.map.height:
			cell = c.y * client.map.width + c.x
	if cell != _look_cell or (cell >= 0 and Engine.get_process_frames() % 10 == 0):
		_look_cell = cell
		var text := ""
		if cell >= 0:
			var c := Vector2i(cell % client.map.width, cell / client.map.width)
			text = Look.name_at(client, cell, _world.can_see(c.x, c.y))
			if text != "":
				var reach := client.click_facing(c) >= 0
				text += "\n[%s]" % ("ЛКМ: использовать    ПКМ: действия" if reach else "ПКМ: действия")
		_look_text.text = text
		_look.visible = text != ""
		_look.reset_size()
	if _look.visible:
		var mouse := get_viewport().get_mouse_position() / _root.scale
		var room := _root.size - _look.size - Vector2(4, 4)
		_look.position = Vector2(minf(mouse.x + 18, room.x), minf(mouse.y + 18, room.y))


func _step_beside(c: Vector2i) -> bool:
	## (v73, the author's note on I1: "when you stand diagonally you can use it too")
	## Something usable diagonally next to us: one step to the side brings it
	## within reach, then it is used as a click would. False if no step does it.
	var me := Vector2i(client.pred.x, client.pred.y)
	var d := c - me
	if absi(d.x) != 1 or absi(d.y) != 1 or client.dragging():
		return false
	var map := client.map
	if not client.usable_at(c.y * map.width + c.x):
		return false
	for side: Vector2i in [Vector2i(d.x, 0), Vector2i(0, d.y)]:
		var to := me + side
		var cell := to.y * map.width + to.x
		if map.walk[cell] == 1 and map.door_of[cell] < 0 and not client.holes.has(cell):
			_step_dir = (4 if side.x > 0 else 3) if side.x != 0 else (2 if side.y > 0 else 1)
			_step_from = me
			_step_then = Vector2(c)
			_step_until = Time.get_ticks_msec() / 1000.0 + 1.0
			return true
	return false


func _open_menu(at: Vector2) -> void:
	## (v73, the author's I1 and B1) The right-click menu: everything that can be
	## done with what is there, each with its key, and orders to a bot of ours.
	var map := client.map
	var c := Vector2i(roundi(at.x), roundi(at.y))
	if client.my_cond != Net.COND_OK or c.x < 0 or c.y < 0 or c.x >= map.width or c.y >= map.height:
		return
	var cell := c.y * map.width + c.x
	_menu.clear()
	_menu_acts.clear()
	var add := func(text: String, act: Callable) -> void:
		_menu.add_item(text, _menu_acts.size())
		_menu_acts.append(act)
	var title := Look.name_at(client, cell, _world.can_see(c.x, c.y))
	if title != "":
		_menu.add_separator(title.get_slice("\n", 0))
	var reach := client.click_facing(c) >= 0
	var me := Vector2i(client.pred.x, client.pred.y)
	var diagonal := absi(c.x - me.x) == 1 and absi(c.y - me.y) == 1
	if reach:
		add.call("Использовать  [%s / ЛКМ]" % Options.key_text("use"), func() -> void: click_at(at))
		if _holds(c):
			add.call("Работать, пока не готово  [держать %s]" % Options.key_text("use"), func() -> void:
				click_at(at)
				_menu_hold = true
				_menu_worked = false
				_menu_hold_until = Time.get_ticks_msec() / 1000.0 + 30.0)
	elif diagonal and client.usable_at(cell):
		add.call("Шагнуть и использовать", func() -> void: _step_beside(c))
	for e: GameClient.Ent in client.ents.values():
		if e.x != c.x or e.y != c.y or e.id == client.my_id:
			continue
		if e.cond != Net.COND_OK and maxi(absi(c.x - me.x), absi(c.y - me.y)) <= 1:
			# (v80, the author's note: "if a lot of bodies lie there, choose which to pull") one line each
			var id := e.id
			add.call("Тащить: %s  [%s]" % [client.player_name(id), Options.key_text("drag")], func() -> void:
				var f := client.click_facing(c)
				if f > 0:
					client.face(f)
				client.send_drag(id))
			add.call("Обыскать: %s" % client.player_name(id), func() -> void:
				var f := client.click_facing(c)
				if f > 0:
					client.face(f)
				client.send_search(id))
		if client.is_bot(e.id) and e.cond == Net.COND_OK:
			var id := e.id
			var now := -1
			for b: Array in client.crew_bots:
				if int(b[0]) == id:
					now = int(b[1])
			for post in Net.POST_NAMES.size():
				var p := post
				add.call("Приказ: %s%s" % [Net.POST_NAMES[post], "  ✓" if post == now else ""], func() -> void: client.send_order(id, p))
	if client.floor_things.has(cell) and maxi(absi(c.x - me.x), absi(c.y - me.y)) <= 1:
		# (v80, the author's note: "and what items to take from the floor") each thing in the pile
		var pile: PackedByteArray = client.floor_things[cell]
		for k in range(pile.size() - 1, -1, -1):
			if pile[k] != Net.ITEM_NONE:
				var at_k := k
				add.call("Взять: %s" % Items.name_of(pile[k]), func() -> void: client.send_take(cell, at_k))
	if client.dragging():
		add.call("Отпустить  [%s]" % Options.key_text("drag"), func() -> void: client.send_drag(Net.NOBODY))
	if title != "":
		add.call("Осмотреть", func() -> void: _say("[color=#9aa3b5]%s[/color]" % _escape(title.replace("\n", ". "))))
	if _menu_acts.is_empty():
		return
	_menu.reset_size()
	_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _holds(c: Vector2i) -> bool:
	## Is what is there a job for a held "use" key (mending, forcing, filling)?
	var f := client.click_facing(c)
	if f < 0:
		return false
	var t := client.use_target(f)
	return t == 1 or t == 2 or t == 5 or t == 9 or t == 10 or t == 11 or t == 16 or t == 18 or t == 23 or t == 25 \
		or t == 29 or t == 33 or t == 34 or t == 40 or t == 41 or t == 42 or t == 45


func _fires_at(c: Vector2i) -> bool:
	## Is a click on this cell meant for the thing in the hand rather than for
	## what lies there: a weapon or something to heal with, aimed at somebody (or at ourselves)?
	var item := client.in_hand()
	if not Items.aimed(item):
		return false
	if Items.INFO.has(item) and Items.INFO[item].has("throw"):
		return true                          # (v70) a flashbang is thrown wherever the click is
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


func _walk_dir() -> int:
	## Which way to walk: the most recently pressed of the held direction keys; (v74, the
	## author's N2) with one up/down key and one left/right key held, the slant between them.
	var up_down := 0
	var sideways := 0
	for dir: int in _held:
		if dir == Net.DIR_UP or dir == Net.DIR_DOWN:
			up_down = dir
		else:
			sideways = dir
	if up_down != 0 and sideways != 0:
		return Net.dir_of(Net.DX[sideways], Net.DY[up_down])
	return 0 if _held.is_empty() else _held[_held.size() - 1]


func _process(delta: float) -> void:
	if client == null:
		return
	# which way to walk: the most recently pressed of the held direction keys
	var busy := _chat_input.visible or _pause.visible or _console.visible or _open(_options)
	_world.hover = not busy
	_world.lean_on = not busy and not aim_cells.is_finite()   # (v79) no leaning with a window open or a scripted aim
	_update_look(busy)
	# (v77, the author's V1) the eyes follow the mouse (not while a console or a window has it)
	client.want_free_look = Options.mouse_look and not scripted_look
	if aim_cells.is_finite():
		client.aim_at(Vector2(client.pred.x, client.pred.y) + aim_cells, delta)
	else:
		client.aim_at(Vector2.INF if busy else _world.cell_under_mouse(), delta)
	_fit_root()
	_update_banner(delta)
	_update_console()
	for m: Array in MOVES:
		var dir: int = m[1]
		var down := Options.held(m[0]) and not busy
		if down and not _held.has(dir):
			_held.append(dir)
		elif not down and _held.has(dir):
			_held.erase(dir)
	var want := _walk_dir()
	if demo_walk:
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _demo_until:
			_demo_dir = _rng.randi_range(1, Net.DIRS) if _rng.randf() < 0.85 else 0   # (v74) slants too
			_demo_until = now + _rng.randf_range(0.15, 1.2)
			if client.use_target() >= 6 and _rng.randf() < 0.5:
				client.send_use(true)        # happened to stop on a ladder or by a thing on the floor: take it
				client.send_use(false)
			elif _rng.randf() < 0.08:
				client.send_hand(_rng.randi_range(0, Net.SLOTS - 1))
				client.send_drop()           # and now and then leave something lying about
		want = _demo_dir
	if _step_dir > 0:
		var now_at := Vector2i(client.pred.x, client.pred.y)
		if not _held.is_empty() or Time.get_ticks_msec() / 1000.0 > _step_until:
			_step_dir = 0                    # a key of our own, or the step did not come: given up
		elif now_at != _step_from:
			_step_dir = 0
			click_at(_step_then)
		else:
			want = _step_dir
	if forced_dir >= 0:
		want = forced_dir
	client.want_dir = want
	if _menu_hold:
		# "work, until done" from the menu: held as the key would be, until the job ends,
		# a key of our own is pressed or the character moves
		_menu_worked = _menu_worked or client.work > 0
		if not _held.is_empty() or (_menu_worked and client.work == 0) or Time.get_ticks_msec() / 1000.0 > _menu_hold_until \
				or (_click_facing == 0 and client.target_cell() < 0):
			_menu_hold = false

	# a click on something to use: once our character has turned to it, it is used as with the key
	if _click_facing > 0:
		if client.pred.facing == _click_facing:
			_click_facing = 0
			if not busy and not _use_screen(client.use_target()):
				_mouse_use = true
		elif Time.get_ticks_msec() / 1000.0 > _click_until:
			_click_facing = 0
	# the "use" key: tell the server when it goes down or up
	var use_now := (Options.held("use") and not busy) or forced_use or (_mouse_use and not busy) or (_menu_hold and not busy)
	if _mouse_use and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_use = false                   # (after this frame: a quick click still presses once)
	if use_now != _use_held:
		_use_held = use_now
		client.send_use(use_now)
		# (v74, the author's note: the bar stayed and blinked at the bottom after he let go, and the
		# next try seemed to go on from it) a job held with "use" starts again from nothing either way;
		# the server's word on it comes a moment later
		client.work = 0
	var target := client.use_target()
	var hauling := client.dragging()
	_hint.visible = (target != 0 or hauling) and not _console.visible
	if hauling and (target == 0 or target == 13):
		_hint.text = "Вы тащите: %s.  F: отпустить" % client.player_name(client.drag_id)
		target = -1                          # (the hint is set; none of the cases below applies)
	var no_power := not client.power_at(client.use_cell())
	var why := "двигатель не работает, СМЭС пуст" if client.engine_down() else "двигатель заглох, СМЭС пуст"
	var no_part := _lacking(client.use_cell())
	if client.concussed and CONSOLE_KINDS.has(target):
		_hint.text = DAZED
		target = -1
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
		_hint.text = "Орудие %d: %s. Стреляют с пульта орудий на мостике%s" % [g + 1, "нет питания" if no_power else ("готово" if c >= 100 else "заряжается, %d%%" % c),
			"" if no_power else "; вы у орудия: оно заряжается быстрее"]
	elif target == 25:
		var mount_why := client.mount_here(client.use_cell())
		var g := client.map.guns.find(client.use_cell())
		var item: int = client.slots[client.hand]
		if mount_why != "":
			_hint.text = mount_why
		elif _use_held and client.work > 0:
			_hint.text = ("Досылаю снаряд…" if Weapons.of_item(item) == Weapons.NONE else "Ставлю орудие…") \
				if item != Net.ITEM_NONE else "Снимаю орудие…"
		elif item != Net.ITEM_NONE and Weapons.of_item(item) == Weapons.NONE:
			# (v68, the author's F3) a round carried by hand into the breech
			var n: int = client.mount_loaded[g] if g < client.mount_loaded.size() else 0
			_hint.text = "Орудие %d. Держите E, чтобы дослать в казённик: %s (заряжено %d из 4; заряженное бьёт быстрее)" % [
				g + 1, Items.name_of(item).to_lower(), n]
		elif item != Net.ITEM_NONE:
			_hint.text = "Орудие %d. Держите E, чтобы поставить: %s" % [g + 1, Items.name_of(item).to_lower()]
		else:
			var c: int = client.gun_charge[g] if g < client.gun_charge.size() else 0
			_hint.text = "Орудие %d: %s%s. Держите E с пустыми руками, чтобы снять его" % [g + 1,
				"нет питания" if no_power else ("готово" if c >= 100 else "заряжается, %d%%" % c),
				"" if no_power else "; вы у орудия: оно заряжается быстрее"]
	elif target == 26:
		_hint.text = "Автодок обесточен: %s" % why if no_power else "Автодок: лечит того, кто лежит перед ним. Держите E, чтобы помогать (вдвое быстрее)"
	elif target == 27:
		_hint.text = "Сканер обесточен: %s" % why if no_power else "E: медицинский сканер (осмотрит лежащего в автодоке)"
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
	elif target == 30:
		var calling := int(client.comms.get("state", Net.COMMS_QUIET)) == Net.COMMS_CALL
		_hint.text = "Пульт связи обесточен: %s" % why if no_power else ("E: пульт связи — входящий вызов!" if calling else "E: пульт связи (вызовы, задания, флагман)")
	elif target == 31:
		_hint.text = _tray_hint(client.use_cell(), no_power)
	elif target == 32:
		_hint.text = "Криокапсула: здесь спит резерв экипажа (%d). Замена погибшему выходит отсюда%s" % [client.reserve,
			"" if not no_power else " (сейчас обесточена: выход у точки появления)"]
	elif target == 28:
		var k := client.smes_at(client.use_cell())
		var share := 0
		if k >= 0:
			share = roundi(100.0 * float(client.smes[k]["charge"]) / maxf(float(client.smes[k]["capacity"]), 1.0))
		_hint.text = "E: терминал %s (заряд %d%%)" % ["резервного СМЭС" if k >= 0 and client.smes[k]["small"] else "СМЭС", share]
	elif target == 33:
		if client.fuel > client.fuel_max - Net.CAN_FUEL:
			_hint.text = "Бак полон (%d из %d): канистра не войдёт" % [client.fuel, client.fuel_max]
		else:
			_hint.text = "Заливаю топливо…" if (_use_held and client.work > 0) else "Бак: %d из %d. Держите E, чтобы залить канистру (+%d)" % [client.fuel, client.fuel_max, Net.CAN_FUEL]
	elif target == 45:
		_hint.text = "Добываю руду…" if (_use_held and client.work > 0) else "Рудная жила. Держите E, чтобы добыть кусок руды"
	elif target == 34:
		_hint.text = "Срезаю лом…" if (_use_held and client.work > 0) else "Обшивка мёртвого корабля. Держите E, чтобы срезать кусок лома"
	elif target == 29:
		if client.hull >= client.hull_max:
			_hint.text = "Обшивка цела"
		elif client.patches <= 0 and client.scrap <= 0:
			_hint.text = "Обшивка %d из %d: латать снаружи можно заплатками или ломом из шкафа снабжения" % [client.hull, client.hull_max]
		else:
			_hint.text = "Латаю обшивку…" if (_use_held and client.work > 0) else "Обшивка %d из %d. Держите E, чтобы залатать снаружи (+%d за заплатку, +%d за лом)" % [client.hull, client.hull_max, 15, 10]
	elif target == 23:
		var gear_why := client.gear_here(client.use_cell())
		var item: int = client.slots[client.hand]
		if gear_why != "":
			_hint.text = gear_why
		elif _use_held and client.work > 0:
			_hint.text = "Устанавливаю…" if item != Net.ITEM_NONE else "Вынимаю модуль…"
		elif item != Net.ITEM_NONE:
			_hint.text = "Держите E, чтобы установить: %s" % Items.name_of(item).to_lower()
		else:
			_hint.text = "Модульная стойка: %s. Держите E, чтобы вынуть последний модуль" % _bay_text()
	elif target == 24:
		_hint.text = "Модульная стойка: %s. Ящик с модулем в руке: держите E, чтобы поставить" % _bay_text()
	elif target == 44:
		_hint.text = "Плита камбуза обесточена: %s" % why if no_power else "E: камбуз (рагу, кофе, травяной отвар из пайков)"
	elif target == 22:
		_hint.text = "E: верстак (разобрать, починить, улучшить орудия)" if client.job == Net.JOB_ENGINEER \
			else "Верстак: за ним работают только инженеры (E: посмотреть)"
	elif target == 21:
		_hint.text = "Монитор дрона обесточен: %s" % why if no_power else "E: монитор дрона-разведчика"
	elif target == 20:
		_hint.text = "Голокарта обесточена: %s" % why if no_power else "E: голокарта корабля (воздух, пробоины, поломки)"
	elif target == 19:
		_hint.text = "Интерком обесточен: %s" % why if no_power else "E: сказать в интерком (услышат у всех панелей)"
	elif target == 41:
		_hint.text = "Обезвреживаю бомбу…" if (_use_held and client.work > 0) else \
			"Пиратская бомба! Держите E, чтобы обезвредить (%d с, инженеру вдвое быстрее)" % 5
	elif target == 42:
		var welded := client.doors.welded[client.map.door_of[client.use_cell()]] == 1
		_hint.text = ("Срезаю шов…" if welded else "Завариваю дверь…") if (_use_held and client.work > 0) else \
			("Дверь заварена. Держите E, чтобы срезать шов" if welded else "Держите E, чтобы заварить дверь: её не откроет никто, пираты прорежут за 12 с")
	elif target == 43:
		_hint.text = "Дверь заварена: не открывается ни для кого. Срезать шов можно сварочным аппаратом"
	elif target == 40:
		_hint.text = "Чиню замок…" if (_use_held and client.work > 0) else "Замок взломан: дверь открыта для всех. Держите E, чтобы починить (с запчастью быстрее)"
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
			var door := client.map.door_of[client.use_cell()]
			var pump := _lock_pump_of(door)
			var gap := client.shutter_gap(door)
			var kpa := int(round(int(gap[0]) * Net.KPA_FULL / Net.AIR_FULL))
			var where := "" if int(gap[1]) == 0 else (", за ним давление ниже" if int(gap[1]) < 0 else ", за ним давление выше")
			if pump >= 0 and client.pumps.has(pump):
				_hint.text = "Насос шлюза выравнивает давление: дверь скоро откроется"
			elif pump >= 0 and client.doors.is_shut(client.doors.partner[door]):
				# (v66) the button by the airlock door, on either side
				_hint.text = "Дверь шлюза: разница давлений %d кПа%s.\nE: кнопка шлюза (насос выровняет давление)    Держите E: открыть вручную" % [kpa, where]
			else:
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
		elif client.docked_air(pump) >= 0.0:
			var docked := client.docked_air(pump)
			if absf(client.lock_air(pump) - docked) < 0.05:
				# (v73) the way home: back to the pressure on our own side
				var inside := client.lock_inside_air(pump)
				if absf(client.lock_air(pump) - inside) < 0.05:
					_hint.text = "Давление в шлюзе как на пристыкованном корабле и у нас: обе двери откроются"
				elif client.lock_air(pump) < inside and client.store_air <= 0.0:
					_hint.text = "Давление как на пристыкованном корабле. Запас воздуха пуст: внутрь только вручную"
				else:
					_hint.text = "Давление как на пристыкованном корабле.  E: %s воздух, чтобы вернуться на наш корабль (откроется внутренняя дверь)" % \
						("закачать" if client.lock_air(pump) < inside else "откачать")
			elif client.lock_air(pump) < docked and client.store_air <= 0.0:
				_hint.text = "Насос шлюза: запас воздуха пуст, закачать нечего"
			else:
				_hint.text = "E: %s воздух, чтобы выровнять давление с пристыкованным кораблём (откроется наружная дверь)" % \
					("закачать" if client.lock_air(pump) < docked else "откачать")
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
	_hint_rich.visible = _hint.visible
	if _hint.visible and _hint.text != _hint_was:
		_hint_was = _hint.text
		_hint_rich.text = "[center]%s[/center]" % _badges(_hint.text)
	_hint.text = Options.keyed(_hint.text)
	_work_bar.visible = (target == 1 or target == 5 or target >= 9 or Items.uses(client.in_hand()) > 0) and client.work > 0 \
		and client.target_cell() < 0         # (v73) then the ring over the thing shows it (v74: held or not)
	_work_fill.size.x = 216.0 * client.work / 100.0
	var shift := (HINT_LEFT - HINT_RIGHT) * 0.5          # under the middle of the hint line
	_work_bar.offset_left = shift - 110.0
	_work_bar.offset_right = shift + 110.0

	var now_s := Time.get_ticks_msec() / 1000.0
	if _chat_tab == TAB_BOTS and client.bot_log_count != _bot_log_seen:
		_bot_log_seen = client.bot_log_count
		_rebuild_chat()
	# (v77, the author's note: the chat sat too low) long lines wrap into two rows: the oldest
	# go until the rest fit the box, so the newest always stay just above the input line
	while _chat_lines.size() > 1 and _chat_box.get_combined_minimum_size().y > CHAT_ROOM:
		var gone := _chat_lines.pop_front()[0] as RichTextLabel
		_chat_box.remove_child(gone)
		gone.queue_free()
	for entry: Array in _chat_lines:
		var age: float = now_s - float(entry[1])
		var alpha := 1.0 if _chat_input.visible else clampf(1.0 - (age - CHAT_VISIBLE_SEC) / 2.0, 0.0, 1.0)
		(entry[0] as RichTextLabel).modulate.a = alpha

	# the monitor shows one of eight states, from unhurt to dead
	_monitor_time += delta
	if _monitor != null and not _monitor_frames.is_empty():
		var row: Array = _monitor_frames[mini(_health_state(), _monitor_frames.size() - 1)]
		_monitor.texture = row[int(_monitor_time / _monitor_step) % row.size()]
		_monitor.tooltip_text = "Здоровье: %s" % ("мертвы" if client.my_cond == Net.COND_DEAD else
			("без сознания" if client.my_cond != Net.COND_OK else "%d из 100" % clampi(client.health, 0, 100)))

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
				what += " (%d из %d)" % [rounds, Items.full_rounds(item)]
				extra = "    Щелчок: выстрел"
			elif rounds == 0:
				what += " (пуст)"
				extra = "    Щелчок: перезарядить" if client.carried(Items.ammo_of(item)) > 0 else \
					("    Нужен магазин" if Items.ammo_of(item) == Net.ITEM_MAG else "    Нужны патроны")
			elif info.has("stun"):
				extra = "    Щелчок рядом: разряд (собьёт с ног)"
			elif info.has("blow"):
				extra = "    Щелчок рядом: удар"
			elif info.has("throw"):
				extra = "    Щелчок: бросить (до %d клеток)" % Items.THROW_RANGE
			elif item == Net.ITEM_CUFFS:
				extra = "    Щелчок по лежащему пирату рядом: заковать"
			elif item == Net.ITEM_SPLINT:
				extra = "    Щелчок по соседу или Z на себя: вправить перелом"
			elif item == Net.ITEM_WELDER:
				extra = "    Держите E у закрытой двери: заварить или срезать шов"
			elif info.has("meal"):
				extra = "    Щелчок по соседу или Z на себя: съесть"
			elif info.has("heal"):
				extra = "    Щелчок по соседу или Z на себя: заклеить раны"
			elif Items.worn_as(item) >= 0:
				if Items.tank_of(item) >= 0:
					what += " (кислорода %d%%)" % (Items.tank_of(item) * 100 / Net.SUIT_TANK_STEPS)
				extra = "    Z: надеть"
			elif Items.uses(item) > 0:
				what += " (%d из %d)" % [Items.uses(item), Net.MEDKIT_USES]
				extra = "    Щелчок по соседу или Z на себя: лечить, 3 с не двигаясь"
			_hand_label.text = Options.keyed("В руке: %s%s    G: положить" % [what, extra])
		# a weapon in the hand shows a sight instead of the arrow
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if Items.aimed(item) else Input.CURSOR_ARROW)
	_hand_label.visible = alive
	# (v70) injuries
	var hurt := PackedStringArray()
	if client.bleeding:
		hurt.append("кровотечение")
	if client.leg_broken:
		hurt.append("перелом ноги (идёте медленно)")
	if client.arm_broken:
		hurt.append("перелом руки (руки медленнее, стрельба неточная)")
	if client.concussed:
		hurt.append("контузия (пульты не даются)")
	var lines := PackedStringArray()
	if not hurt.is_empty():
		lines.append("Травмы: " + ", ".join(hurt))
	if client.weak:
		lines.append("Слабость от голода: идёте медленно")       # (v71)
	if client.meal != 0 and client.meal_left > 0:
		lines.append("%s: %s, ещё %d:%02d" % [Items.name_of(client.meal), {Net.ITEM_STEW: "раны затягиваются",
			Net.ITEM_COFFEE: "работа быстрее"}.get(client.meal, ""), client.meal_left / 60, client.meal_left % 60])
	_hurt_label.text = "\n".join(lines)
	_hurt_label.visible = alive and not lines.is_empty()
	var share := float(client.tank) / Net.TANK_FULL
	_tank_fill.position = Vector2(2, 2 + 92.0 * (1.0 - share))
	_tank_fill.size = Vector2(8, 92.0 * share)
	_tank_bar.tooltip_text = "Кислород в баллоне скафандра: %d%%" % roundi(share * 100.0)
	_tank_fill.color = Color(0.25, 0.85, 0.75) if share > 0.5 else (Color(0.95, 0.75, 0.3) if share > 0.2 else Color(0.95, 0.35, 0.3))

	# fading out: the screen darkens below 40 health
	var dark := clampf((40.0 - client.health) / 40.0, 0.0, 1.0) * 0.5
	if client.concussed and client.my_cond == Net.COND_OK:
		dark = maxf(dark, 0.22 + 0.12 * sin(_life * 2.2))   # (v70) a concussion: the world swims
	# (v76) out cold: holding R for GIVE_UP_SECONDS gives up (the character dies, R then brings a new one)
	var out_cold := client.my_cond == Net.COND_CRIT and client.health <= 0
	_give_up = _give_up + delta if out_cold and Options.held("respawn") and not busy else 0.0
	if _give_up >= GIVE_UP_SECONDS:
		_give_up = -INF                        # (once per hold)
		client.send_respawn()
	if client.my_cond == Net.COND_CRIT:
		dark = 0.72
		_fate.text = "Вы без сознания"
		if out_cold:
			_fate.text += ". Тяжёлые раны убьют вас за несколько минут, если вас не вылечат. Удерживайте R %d с, чтобы сдаться и вернуться из резерва." % GIVE_UP_SECONDS
	elif client.my_cond == Net.COND_DEAD:
		dark = 0.8
		if client.reserve > 0:
			_fate.text = "Вы погибли. Нажмите R, чтобы вернуться новым членом экипажа из резерва (в резерве: %d)." % client.reserve
		else:
			_fate.text = "Вы погибли. Резерв экипажа пуст: вернуться можно, когда товарищи наймут людей у торговца."
	_fate.text = Options.keyed(_fate.text)
	_fate.visible = client.my_cond != Net.COND_OK and client.over == Net.OVER_NONE
	# (v57) the flagship beaten: the game is won, shown for a while; the voyage goes on
	if client.won and not _won_known:
		_won_known = true
		_victory_left = VICTORY_SECONDS if _life > 3.0 else 0.0      # (joining a game won before: not shown)
	_victory_left = maxf(_victory_left - delta, 0.0)
	_life += delta
	_over.visible = client.over != Net.OVER_NONE or _victory_left > 0.0
	if _over.visible and client.over == Net.OVER_NONE:
		_over_text.text = "ПОБЕДА\n\nФлагман пиратов повержен: цель пути достигнута.\n\nПройдено секторов: %d\nПрыжков сделано: %d\nПуть занял: %s%s\n\nИгра выиграна. Можно лететь дальше: космос не кончается." % [
			client.sectors_seen, client.jumps, _voyage(client.voyage_seconds), _story()]
	elif _over.visible:
		_over_text.text = "КАМПАНИЯ ОКОНЧЕНА\n\n%s\n\nПройдено секторов: %d\nДальше всего от начала пути: %d прыжков\nПрыжков сделано: %d\nПродержались: %s%s\n\nНовую кампанию начинает хозяин игры: выйти в меню и создать игру заново." % [
			Net.OVER_TEXT[clampi(client.over, 0, Net.OVER_TEXT.size() - 1)],
			client.sectors_seen, client.farthest, client.jumps, _voyage(client.voyage_seconds), _story()]
	_shade.color.a = lerpf(_shade.color.a, dark, 1.0 - exp(-delta * 4.0))

	# the jump
	_jump_label.visible = client.jump_to != Net.NO_SECTOR and not _console.visible
	if _jump_label.visible:
		_jump_label.text = "Прыжок через %d с: %s" % [
			maxi(int(ceil((client.jump_tick - client.server_now()) / Net.TICK_HZ)), 0), client.sectors.describe(client.jump_to)]
	_flash.color.a = maxf(_flash.color.a - delta * 1.6, 0.0)
	# (v68) the alert
	_alert_time += delta
	_alert_label.visible = client.alert != Net.ALERT_GREEN and not _console.visible
	if _alert_label.visible:
		_alert_label.text = Net.ALERT_NAMES[client.alert].to_upper()
		_alert_label.modulate = Color(1.0, 0.35, 0.3, 0.6 + 0.4 * sin(_alert_time * 4.0)) if client.alert == Net.ALERT_RED \
			else Color(1.0, 0.85, 0.35)
	_alert_tint.color.a = 0.0                # (v75) the red light of a red alert is in the world now (WorldView)

	_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.25
		_info.visible = _info_on or Options.show_fps
		_info.text = "Кадров: %d" % int(round(_fps_smooth))
	if _info_timer <= 0.0 and _info_on:
		_info.text = "На борту: %d     Резерв: %d     Обшивка: %d%%     Пинг: %d мс     Сектор: %s" % [client.crew_count(),
			client.reserve, client.hull * 100 / client.hull_max, int(round(client.rtt_ms)),
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


func _lock_pump_of(door: int) -> int:
	## (v66) The pump of the airlock that door belongs to, or -1.
	for c: int in client.map.lock_pump.keys():
		var lock: Dictionary = client.map.lock_pump[c]
		if int(lock["inner"]) == door or int(lock["outer"]) == door:
			return c
	return -1
