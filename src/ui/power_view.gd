extends VBoxContainer
## (v61, the author's P5 and P6) An SMES's terminal, as in SS13: its charge and
## what it is doing, charging and output switched on or off, and how much it takes
## and gives a second. The main SMES's screen has the power monitor in its lower
## half: what the engine makes, what the ship draws and how long the charge would
## last. The terminal is the SMES's own: it works with the ship dark. The server
## does the work (see Power). Shown inside the console frame of GameScreen.
##
## (v68, the author's F2) The main SMES's screen is also the engineer's power
## panel: the guns', the point defence's and the shield's power switches, power
## for the engines (dodge), the breakers of the ship's own draw (lights, the air
## plant, the trays) and the reactor's overcharge.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")

const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const WARN := Color(0.95, 0.75, 0.3)
const GOOD := Color(0.45, 0.9, 0.55)
const ACT_CHARGE := 1                # as Power.ACT_*
const ACT_OUTPUT := 2
const ACT_INPUT := 3
const ACT_LEVEL := 4
const ACT_GUARD := 5
const ACT_SHIELD := 6
const ACT_ENGINES := 7
const ACT_BREAKER := 8
const ACT_OVERCHARGE := 9
const ACT_GUN := 16
const GUARD_NONE := 0                # Weapons.NONE

var client: GameClient
var cell := -1                       # the SMES this screen is open at
var _state: Label
var _bar: ProgressBar
var _charge_btn: Button
var _output_btn: Button
var _input: Label
var _level: Label
var _monitor: Label
var _panel: VBoxContainer            # (v68) the power panel (the main SMES only)
var _guns_row: HBoxContainer
var _gun_btns: Array = []
var _guard_btn: Button
var _shield_btn: Button
var _engines: Label
var _breaker_btns: Array = []
var _over_btn: Button
var _panel_note: Label


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(620, 0)
	_state = _label(15, INK)
	add_child(_state)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(600, 22)
	_bar.max_value = 100.0
	add_child(_bar)
	var switches := HBoxContainer.new()
	switches.add_theme_constant_override("separation", 10)
	_charge_btn = _button(switches, "", func() -> void: _send(ACT_CHARGE, 0 if _val("charging") else 1))
	_output_btn = _button(switches, "", func() -> void: _send(ACT_OUTPUT, 0 if _val("output") else 1))
	add_child(switches)
	var inrow := HBoxContainer.new()
	inrow.add_theme_constant_override("separation", 8)
	_input = _label(14, INK)
	_input.custom_minimum_size = Vector2(380, 0)
	inrow.add_child(_input)
	_button(inrow, "−", func() -> void: _send(ACT_INPUT, int(_val("input", 0)) - 1))
	_button(inrow, "+", func() -> void: _send(ACT_INPUT, int(_val("input", 0)) + 1))
	add_child(inrow)
	var outrow := HBoxContainer.new()
	outrow.add_theme_constant_override("separation", 8)
	_level = _label(14, INK)
	_level.custom_minimum_size = Vector2(380, 0)
	outrow.add_child(_level)
	_button(outrow, "−", func() -> void: _send(ACT_LEVEL, int(_val("level", 0)) - 1))
	_button(outrow, "+", func() -> void: _send(ACT_LEVEL, int(_val("level", 0)) + 1))
	add_child(outrow)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	_panel.add_child(HSeparator.new())
	_panel.add_child(_label(15, INK))
	(_panel.get_child(1) as Label).text = "ЩИТ ПИТАНИЯ"
	_guns_row = HBoxContainer.new()
	_guns_row.add_theme_constant_override("separation", 6)
	_panel.add_child(_guns_row)
	var defence := HBoxContainer.new()
	defence.add_theme_constant_override("separation", 6)
	_shield_btn = _button(defence, "", func() -> void: _send(ACT_SHIELD, 0 if client.shield_flags & Net.SHF_ON else 1))
	_guard_btn = _button(defence, "", func() -> void: _send(ACT_GUARD, 0 if client.guard_flags & Net.GUNF_ARMED else 1))
	_panel.add_child(defence)
	var eng := HBoxContainer.new()
	eng.add_theme_constant_override("separation", 8)
	_engines = _label(14, INK)
	_engines.custom_minimum_size = Vector2(380, 0)
	eng.add_child(_engines)
	_button(eng, "−", func() -> void: _send(ACT_ENGINES, int(client.panel["engines"]) - 1))
	_button(eng, "+", func() -> void: _send(ACT_ENGINES, int(client.panel["engines"]) + 1))
	_panel.add_child(eng)
	var brk := HBoxContainer.new()
	brk.add_theme_constant_override("separation", 6)
	for b in Net.BREAKER_NAMES.size():
		var k := b
		_breaker_btns.append(_button(brk, "", func() -> void: _send(ACT_BREAKER, k * 2 + (0 if _breaker_on(k) else 1))))
	_panel.add_child(brk)
	var over := HBoxContainer.new()
	_over_btn = _button(over, "", func() -> void: _send(ACT_OVERCHARGE, 0 if int(client.panel["over"]) > 0 else 1))
	_panel.add_child(over)
	_panel_note = _label(13, DIM)
	_panel.add_child(_panel_note)
	add_child(_panel)
	add_child(HSeparator.new())
	_monitor = _label(14, INK)
	add_child(_monitor)


func _breaker_on(k: int) -> bool:
	return int(client.panel["breakers"]) & (1 << k) != 0


func _refresh_panel() -> void:
	## (v68) The power panel's buttons, as the server last told.
	var n := client.gun_weapon.size()
	if _gun_btns.size() != n:
		for b: Button in _gun_btns:
			b.queue_free()
		_gun_btns = []
		for i in n:
			var k := i
			_gun_btns.append(_button(_guns_row, "", func() -> void:
				_send(ACT_GUN + k, 0 if client.gun_flags[k] & Net.GUNF_ARMED else 1)))
	for i in n:
		var b: Button = _gun_btns[i]
		var w: int = client.gun_weapon[i]
		b.disabled = w == 0
		b.text = "Орудие %d: %s" % [i + 1, "—" if w == 0 else ("ВКЛ" if client.gun_flags[i] & Net.GUNF_ARMED else "ВЫКЛ")]
	_shield_btn.visible = client.shield_flags & Net.SHF_HAS != 0
	_shield_btn.text = "Щит: ВКЛ" if client.shield_flags & Net.SHF_ON else "Щит: ВЫКЛ"
	_guard_btn.visible = client.guard != GUARD_NONE
	_guard_btn.text = "«Заслон»: ВКЛ" if client.guard_flags & Net.GUNF_ARMED else "«Заслон»: ВЫКЛ"
	_engines.text = "Двигатели (уклонение): %d из 2, по 2 энергии, +5%% уклонения каждый" % int(client.panel["engines"])
	for b in _breaker_btns.size():
		(_breaker_btns[b] as Button).text = "%s: %s" % [Net.BREAKER_NAMES[b], "ВКЛ" if _breaker_on(b) else "ВЫКЛ"]
	var over: int = client.panel["over"]
	var rest: int = client.panel["rest"]
	_over_btn.text = ("Перегрузка реактора: идёт, ещё %d с (остановить)" % over) if over > 0 else (
		"Реактор остывает: %d с" % rest if rest > 0 else "Перегрузить реактор (+4 на 20 с, может сжечь двигатель)")
	_over_btn.disabled = over <= 0 and rest > 0
	_panel_note.text = "Энергия орудиям и щиту: занято %d из %d. Каждый выключенный рубильник отдаёт орудиям 1." % [client.power_used, client.power_max]


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(row: HBoxContainer, text: String, act: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 0)
	b.pressed.connect(act)
	row.add_child(b)
	return b


func _val(key: String, none: Variant = false) -> Variant:
	var i := client.smes_at(cell)
	return client.smes[i][key] if i >= 0 else none


func _send(action: int, value: int) -> void:
	var i := client.smes_at(cell)
	if i >= 0:
		client.send_smes(i, action, value)


func title() -> String:
	var i := client.smes_at(cell)
	return "Терминал резервного СМЭС мостика" if i >= 0 and client.smes[i]["small"] else "СМЭС и щит питания"


func refresh() -> void:
	var i := client.smes_at(cell)
	if i < 0:
		_state.text = "Терминал не отвечает."
		return
	var u: Dictionary = client.smes[i]
	var cap: int = maxi(int(u["capacity"]), 1)
	var share := float(u["charge"]) / cap
	var status: int = u["status"]
	_state.text = "Заряд: %d%%   Состояние: %s" % [roundi(share * 100.0), Net.SMES_STATUS[status] if status < Net.SMES_STATUS.size() else "?"]
	_state.add_theme_color_override("font_color", WARN if status >= Net.SMES_EMPTY else INK)
	_bar.value = share * 100.0
	_charge_btn.text = "Зарядка: ВКЛ" if u["charging"] else "Зарядка: ВЫКЛ"
	_output_btn.text = "Выход: ВКЛ" if u["output"] else "Выход: ВЫКЛ"
	_input.text = "Зарядка до %d ед./с (не больше %d), берёт сейчас %.1f" % [u["input"], u["input_max"], u["in_now"]]
	_level.text = "Выход до %d ед./с (не больше %d), отдаёт сейчас %.1f" % [u["level"], u["output_max"], u["out_now"]]
	_panel.visible = not u["small"]
	if not u["small"]:
		_refresh_panel()
	if u["small"]:
		_monitor.text = "Резервный СМЭС сам заряжается, пока у корабля есть энергия. Когда корабль обесточен, он держит свет и пульты мостика. Прыжок без двигателя невозможен."
	else:
		_monitor.text = monitor_text(client)


static func monitor_text(c: GameClient) -> String:
	## The power monitor: also on the holomap.
	var m: Dictionary = c.power_mon
	if m.is_empty():
		return "Монитор питания: нет данных."
	var flags: int = m["flags"]
	var lines := PackedStringArray()
	lines.append("МОНИТОР ПИТАНИЯ")
	if flags & Net.POWF_ENGINE:
		lines.append("Двигатель даёт: %d ед./с%s" % [m["made"], "  (ионный шторм: реактор вполсилы)" if flags & Net.POWF_STORM else ""])
	else:
		lines.append("Двигатель: не работает")
	lines.append("Корабль потребляет: %d (пульты, двери, свет, воздух, гидропоника) + %d (орудия, щит, двигатели)" % [m["base"], m["used"]])
	lines.append("Доступно орудиям и щиту: %d из %d по реактору" % [m["budget"], m["reactor"]])
	if flags & Net.POWF_CARRYING:
		lines.append("Корабль идёт на СМЭС: заряда хватит на %s" % _time(m["seconds"]))
	elif flags & Net.POWF_BACKUP:
		lines.append("Корабль обесточен: резервный СМЭС держит мостик")
	elif not (flags & Net.POWF_ENGINE):
		lines.append("Корабль обесточен")
	var total := 0
	var cap := 0
	for u: Dictionary in c.smes:
		if not u["small"]:
			total += int(u["charge"])
			cap += int(u["capacity"])
	if cap > 0:
		lines.append("Заряд СМЭС: %d%%" % roundi(100.0 * total / cap))
	return "\n".join(lines)


static func _time(seconds: int) -> String:
	if seconds >= 65535:
		return "долго"
	if seconds >= 90:
		return "%d мин" % roundi(seconds / 60.0)
	return "%d с" % seconds
