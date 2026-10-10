extends Node
## Everything shown while playing: the world, the HUD, chat and the pause
## panel. Reads the keyboard and tells the GameClient which way to walk.

signal exit_requested

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const WorldView := preload("res://src/client/world_view.gd")

const MOVES := [["move_up", 1], ["move_down", 2], ["move_left", 3], ["move_right", 4]]
const CHAT_LINES := 9
const CHAT_VISIBLE_SEC := 12.0        # a chat line stays this long, then fades
const NAME_COLOURS: Array[String] = ["ff6b5e", "6fa8ff", "6fd487", "f2c84b", "b98cf0", "f59a55", "5fd3e0", "e3e6ee"]

var client: GameClient
var hosting := false
var host_port := 0
var demo_walk := false               # test mode: wander without a keyboard
var forced_dir := -1                 # test mode: direction dictated by a script (-1 = off)

var _world: WorldView
var _ui: CanvasLayer
var _info: Label
var _hint: Label
var _debug: Label
var _monitor: TextureRect
var _monitor_frames: Array[AtlasTexture] = []
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
	_hint = _text(top, 13)
	_hint.text = "WASD или стрелки: ходить     Enter: чат     Esc: меню     F11: во весь экран"
	_hint.modulate = Color(1, 1, 1, 0.75)

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
		for i in int(meta["frames"]):
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(i * fw, 0, fw, fh)
			_monitor_frames.append(frame)
		_monitor = TextureRect.new()
		_monitor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_monitor.stretch_mode = TextureRect.STRETCH_SCALE
		_monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_monitor.texture = _monitor_frames[0]
		_monitor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_monitor.offset_left = -fw * 3 - 14
		_monitor.offset_top = -fh * 3 - 14
		_monitor.offset_right = -14
		_monitor.offset_bottom = -14
		root.add_child(_monitor)

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

	_build_pause(root)
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
	var colour := NAME_COLOURS[client.player_colour(from_id) % NAME_COLOURS.size()]
	_say("[color=#%s][b]%s:[/b][/color] %s" % [colour, _escape(client.player_name(from_id)), _escape(text)])


func _on_notice(text: String) -> void:
	_say("[color=#9aa3b5]%s[/color]" % _escape(text))


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _chat_input.visible:
			_close_chat()
		else:
			_set_pause(not _pause.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and not _pause.visible and not _chat_input.visible:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug"):
		show_debug(not _debug.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_predict"):
		client.predict = not client.predict
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc while typing: cancel the message (the text field would swallow the key otherwise)
	if _chat_input.visible and event.is_action_pressed("pause"):
		_close_chat()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if client == null:
		return
	# which way to walk: the most recently pressed of the held direction keys
	var busy := _chat_input.visible or _pause.visible
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
		want = _demo_dir
	if forced_dir >= 0:
		want = forced_dir
	client.want_dir = want

	var now_s := Time.get_ticks_msec() / 1000.0
	for entry: Array in _chat_lines:
		var age: float = now_s - float(entry[1])
		var alpha := 1.0 if _chat_input.visible else clampf(1.0 - (age - CHAT_VISIBLE_SEC) / 2.0, 0.0, 1.0)
		(entry[0] as RichTextLabel).modulate.a = alpha

	if _monitor != null and not _monitor_frames.is_empty():
		_monitor_time += delta
		_monitor.texture = _monitor_frames[int(_monitor_time / _monitor_step) % _monitor_frames.size()]

	_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.25
		_info.text = "На борту: %d     Пинг: %d мс" % [client.roster.size(), int(round(client.rtt_ms))]
		if _debug.visible:
			_debug.text = "тик сервера: %d\nпредсказание: %s (F4), исправлено шагов: %d\nсверка состояния: %d без расхождений, %d с расхождением\nпринято: %d пакетов, %.1f КБ\nкадров в секунду: %d" % [
				client.server_tick, "вкл" if client.predict else "выкл", client.mispredicts,
				client.checks_ok, client.checks_bad, client.packets_in, client.bytes_in / 1024.0,
				int(round(_fps_smooth))]
