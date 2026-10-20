extends RefCounted
## The player's own settings: sound, picture and keys. They live in
## user://options.cfg (apart from the menu's settings.cfg, which the menu
## writes whole) and are put into effect at start and whenever they change.
##
## Every action can have two keys. A key may need Ctrl, Shift or Alt held with
## it; a key bound without them also works while they are held, unless another
## action has that same key with them (then each gets its own).

const PATH := "user://options.cfg"
const WORLD_BUS := "World"           # everything heard in the game
const HUM_BUS := "Hum"               # the engine's hum (a part of World)
const MUSIC_BUS := "Music"           # (v75) the music, beside World
const KEYS_PER_ACTION := 2

## action, what it is called on screen, default keys
const ACTIONS: Array = [
	["move_up", "Идти вверх", [KEY_W, KEY_UP]],
	["move_down", "Идти вниз", [KEY_S, KEY_DOWN]],
	["move_left", "Идти влево", [KEY_A, KEY_LEFT]],
	["move_right", "Идти вправо", [KEY_D, KEY_RIGHT]],
	["use", "Действие (чинить, пульт, лестница, поднять)", [KEY_E]],
	["drag", "Тащить лежащего", [KEY_F]],
	["act", "Применить вещь в руке (фонарик, надеть, лечить себя)", [KEY_Z]],
	["drop", "Положить вещь на пол", [KEY_G]],
	["suit", "Подача кислорода", [KEY_Q]],
	["inventory", "Инвентарь", [KEY_I, KEY_TAB]],
	["crew", "Экипаж: посты и приказы ботам", [KEY_O]],
	["slot_1", "Слот 1 в руку", [KEY_1]],
	["slot_2", "Слот 2 в руку", [KEY_2]],
	["slot_3", "Слот 3 в руку", [KEY_3]],
	["slot_4", "Слот 4 в руку", [KEY_4]],
	["slot_5", "Слот 5 в руку", [KEY_5]],
	["slot_6", "Слот 6 в руку", [KEY_6]],
	["chat", "Чат", [KEY_ENTER, KEY_KP_ENTER]],
	["radio", "Сказать в рацию", [KEY_T]],
	["respawn", "Вернуться из резерва (после гибели)", [KEY_R]],
	["admin", "Панель администратора", [KEY_F2]],
	["pause", "Меню", [KEY_ESCAPE]],
	["fullscreen", "Полный экран", [KEY_F11]],
	["info", "Сведения о корабле и подсказки клавиш", [KEY_F1]],
	["help", "Книга помощи", [KEY_H]],
	["debug", "Отладочные сведения", [KEY_F3]],
	["toggle_predict", "Предсказание движения (отладка)", [KEY_F4]],
]

static var volume := 0.8             # 0..1, everything
static var world_volume := 1.0       # 0..1, sounds of the game
static var hum_volume := 1.0         # 0..1, the engine's hum
static var steps_volume := 0.5       # (v56) 0..1, footsteps (the author found them too loud)
static var fight_volume := 1.0       # (v56) 0..1, the ship fight: guns, hits, the shield
static var music_volume := 0.6       # (v75) 0..1, the music (the menu's, and the drone in a fight)
static var shake := 1.0              # (v56) 0..1, how hard the screen shakes when the hull is hit
static var muted := false
static var fullscreen := false
static var vsync := true
static var max_fps := 60
static var show_fps := false
static var flash := true             # the white flash after a jump
static var first_shift := true       # (v74, the author's L1) the «first shift» checklist in a game
static var shift_done := 0           # (v74) its lines ticked off so far (bits, see FirstShift.STEPS), kept between games
static var mouse_look := true        # (v77, the author's V1) the view follows the mouse (off: where one walks)
static var ui_scale := 1.0           # (v73, the author's H5) the size of the interface (and its text): 0.75..1.5
static var keys := {}                # action -> Array of {"key": physical keycode, "ctrl", "shift", "alt"}


static func db_of(v: float) -> float:
	## (v56) A 0..1 setting as a change of loudness (silence at 0).
	return linear_to_db(maxf(v, 0.0001))


static func defaults() -> Dictionary:
	var out := {}
	for a: Array in ACTIONS:
		var list: Array = []
		for k: int in a[2]:
			list.append({"key": k, "ctrl": false, "shift": false, "alt": false})
		out[a[0]] = list
	return out


static func load_all() -> void:
	keys = defaults()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		volume = clampf(float(cfg.get_value("sound", "volume", volume)), 0.0, 1.0)
		world_volume = clampf(float(cfg.get_value("sound", "world", world_volume)), 0.0, 1.0)
		hum_volume = clampf(float(cfg.get_value("sound", "hum", hum_volume)), 0.0, 1.0)
		steps_volume = clampf(float(cfg.get_value("sound", "steps", steps_volume)), 0.0, 1.0)
		fight_volume = clampf(float(cfg.get_value("sound", "fight", fight_volume)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value("sound", "music", music_volume)), 0.0, 1.0)
		shake = clampf(float(cfg.get_value("video", "shake", shake)), 0.0, 1.0)
		muted = bool(cfg.get_value("sound", "muted", muted))
		fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
		vsync = bool(cfg.get_value("video", "vsync", vsync))
		max_fps = int(cfg.get_value("video", "max_fps", max_fps))
		show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
		flash = bool(cfg.get_value("video", "flash", flash))
		ui_scale = clampf(float(cfg.get_value("video", "ui_scale", ui_scale)), 0.75, 1.5)
		first_shift = bool(cfg.get_value("game", "first_shift", first_shift))
		mouse_look = bool(cfg.get_value("game", "mouse_look", mouse_look))
		shift_done = int(cfg.get_value("game", "shift_done", shift_done))
		for a: Array in ACTIONS:
			if cfg.has_section_key("keys", a[0]):
				var list: Array = []
				for b: Variant in cfg.get_value("keys", a[0], []):
					if typeof(b) == TYPE_DICTIONARY and int((b as Dictionary).get("key", 0)) != 0:
						list.append({"key": int(b["key"]), "ctrl": bool(b.get("ctrl", false)),
							"shift": bool(b.get("shift", false)), "alt": bool(b.get("alt", false))})
				keys[a[0]] = list.slice(0, KEYS_PER_ACTION)
	apply_keys()
	apply_sound()


static func save_all() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sound", "volume", volume)
	cfg.set_value("sound", "world", world_volume)
	cfg.set_value("sound", "hum", hum_volume)
	cfg.set_value("sound", "steps", steps_volume)
	cfg.set_value("sound", "fight", fight_volume)
	cfg.set_value("sound", "music", music_volume)
	cfg.set_value("video", "shake", shake)
	cfg.set_value("sound", "muted", muted)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "flash", flash)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("game", "first_shift", first_shift)
	cfg.set_value("game", "mouse_look", mouse_look)
	cfg.set_value("game", "shift_done", shift_done)
	for action: String in keys:
		cfg.set_value("keys", action, keys[action])
	cfg.save(PATH)


# --------------------------------------------------------------- keys

static func event_of(b: Dictionary) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = int(b["key"]) as Key       # physical keys: the same place on any keyboard layout
	ev.ctrl_pressed = bool(b["ctrl"])
	ev.shift_pressed = bool(b["shift"])
	ev.alt_pressed = bool(b["alt"])
	return ev


static func apply_keys() -> void:
	for a: Array in ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for b: Dictionary in keys.get(action, []):
			InputMap.action_add_event(action, event_of(b))


static func binding_of(event: InputEventKey) -> Dictionary:
	## What a key press would be kept as.
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	return {"key": int(code), "ctrl": event.ctrl_pressed, "shift": event.shift_pressed, "alt": event.alt_pressed}


static func binding_text(b: Dictionary) -> String:
	var parts: Array[String] = []
	if bool(b.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(b.get("shift", false)):
		parts.append("Shift")
	if bool(b.get("alt", false)):
		parts.append("Alt")
	parts.append(_key_name(int(b.get("key", 0))))
	return "+".join(parts)


static func _key_name(code: int) -> String:
	match code:
		KEY_ESCAPE:
			return "Esc"
		KEY_ENTER:
			return "Enter"
		KEY_KP_ENTER:
			return "Enter (цифр.)"
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		KEY_SPACE:
			return "Пробел"
	return OS.get_keycode_string(code as Key)


static func key_text(action: String) -> String:
	## The first key of an action, as written on screen ("—" when it has none).
	var list: Array = keys.get(action, [])
	return binding_text(list[0]) if not list.is_empty() else "—"


const LETTERS := {"E": "use", "F": "drag", "Z": "act", "G": "drop", "Q": "suit", "R": "respawn"}
static var _letter: RegEx


static func keyed(text: String) -> String:
	## A line written with the default keys ("Держите E"), with the keys the
	## player has now put in their place.
	if _letter == null:
		_letter = RegEx.create_from_string("(?<![A-Za-zА-Яа-яЁё0-9])[EFZGQR](?![A-Za-zА-Яа-яЁё0-9])")
	var out := ""
	var from := 0
	for m: RegExMatch in _letter.search_all(text):
		out += text.substr(from, m.get_start() - from) + key_text(LETTERS[m.get_string()])
		from = m.get_end()
	return out + text.substr(from)


static func label_of(action: String) -> String:
	for a: Array in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


static func same(a: Dictionary, b: Dictionary) -> bool:
	return int(a["key"]) == int(b["key"]) and bool(a["ctrl"]) == bool(b["ctrl"]) \
		and bool(a["shift"]) == bool(b["shift"]) and bool(a["alt"]) == bool(b["alt"])


static func bind(action: String, index: int, b: Dictionary) -> String:
	## Puts a key on an action (in place `index`, or the end). Another action that
	## had the very same key loses it; returns that action's name, or "".
	var took := ""
	for other: String in keys:
		var list: Array = keys[other]
		for i in range(list.size() - 1, -1, -1):
			if same(list[i], b) and not (other == action and i == index):
				list.remove_at(i)
				if other != action:
					took = other
	var mine: Array = keys.get(action, [])
	if index < mine.size():
		mine[index] = b
	else:
		mine.append(b)
	keys[action] = mine.slice(0, KEYS_PER_ACTION)
	apply_keys()
	return took


static func unbind(action: String, index: int) -> void:
	var mine: Array = keys.get(action, [])
	if index < mine.size():
		mine.remove_at(index)
	apply_keys()


static func pressed(event: InputEvent, action: String) -> bool:
	## A key went down for that action. With modifiers held, an action bound to
	## exactly that combination wins over one bound to the bare key.
	if not event.is_action_pressed(action):
		return false
	if not (event is InputEventKey):
		return true
	var k := event as InputEventKey
	if not (k.ctrl_pressed or k.shift_pressed or k.alt_pressed):
		return true
	if event.is_action_pressed(action, false, true):
		return true                      # bound with these very modifiers
	# bound to the bare key: only if no action has this exact combination
	for a: Array in ACTIONS:
		if event.is_action_pressed(a[0], false, true):
			return false
	return true


static func held(action: String) -> bool:
	## The action's key is held down now (for walking and the "use" key).
	if not Input.is_action_pressed(action):
		return false
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var alt := Input.is_key_pressed(KEY_ALT)
	if not (ctrl or shift or alt):
		return true
	# with a modifier held: the key counts unless that combination belongs to something else
	for b: Dictionary in keys.get(action, []):
		if Input.is_physical_key_pressed(int(b["key"]) as Key) and (bool(b["ctrl"]) or bool(b["shift"]) or bool(b["alt"])):
			return true
	for b: Dictionary in keys.get(action, []):
		if not Input.is_physical_key_pressed(int(b["key"]) as Key):
			continue
		var combo := {"key": b["key"], "ctrl": ctrl, "shift": shift, "alt": alt}
		var taken := false
		for other: String in keys:
			if other == action:
				continue
			for ob: Dictionary in keys[other]:
				taken = taken or same(ob, combo)
		if not taken:
			return true
	return false


# --------------------------------------------------------------- sound and picture

static func ensure_buses() -> void:
	## World (everything heard in the game) and Hum (the engine) go into Master.
	for bus: String in [WORLD_BUS, HUM_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, WORLD_BUS if bus == HUM_BUS else "Master")


static func _db(share: float) -> float:
	return linear_to_db(maxf(share, 0.0001))


static func apply_sound() -> void:
	ensure_buses()
	AudioServer.set_bus_volume_db(0, _db(volume))
	AudioServer.set_bus_mute(0, muted or volume <= 0.001)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(WORLD_BUS), _db(world_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(WORLD_BUS), world_volume <= 0.001)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(HUM_BUS), _db(hum_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(HUM_BUS), hum_volume <= 0.001)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), _db(music_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MUSIC_BUS), music_volume <= 0.001)


static func apply_video() -> void:
	## Only for a game with a window.
	if DisplayServer.get_name() == "headless":
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if full != fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
