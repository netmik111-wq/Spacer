extends PanelContainer
## (v74, the author's L1) The «first shift» checklist: a short list in the top left corner of
## the screen of the first things to do aboard. Each line ticks itself when it is done; what is
## done is kept between games (Options.shift_done), so it shows only until every line is done.
## ✕ closes it for good; the settings turn it on again (from the start).

const Net := preload("res://src/shared/net.gd")
const Options := preload("res://src/client/options.gd")
const GameClient := preload("res://src/client/game_client.gd")

enum { WALK, OXYGEN, LOCKER, HAND, HELP, HELM, FUEL, JUMP }
# each line: what to do (the keys are filled in from Options when shown)
const STEPS := [
	"Пройдитесь: {move_up} {move_left} {move_down} {move_right}; две клавиши сразу — по диагонали",
	"Включите подачу кислорода из скафандра: {suit}",
	"Откройте шкаф снабжения: {use} у шкафа",
	"Возьмите другую вещь в руку: 1–6 или колесо мыши",
	"Откройте книгу помощи: {help}",
	"Встаньте к пульту управления на мостике: {use}",
	"Залейте канистру топлива в двигатель: держите {use}",
	"Прыгните в соседнюю систему с пульта управления",
]
const DONE_ALL := (1 << 8) - 1
const SHOW_DONE := 4.0               # seconds the last line stays ticked before the list goes

var client: GameClient
var _lines: Array = []               # a Label per step
var _steps_at := -1                  # client.steps_predicted when the game began
var _hand_at := -1
var _fuel_at := -1
var _sector_at := -1
var _gone_at := 0.0
var _start_at := 0.0                 # when the game began: the ship's state settles first


func setup(p_client: GameClient) -> void:
	client = p_client
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 64)            # under the line F1 shows
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.82)
	style.border_color = Color(0.45, 0.65, 0.8, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "Первая смена"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Убрать подсказки первой смены (вернуть: настройки, «Изображение»)"
	close.pressed.connect(func() -> void:
		Options.first_shift = false
		Options.save_all()
		visible = false)
	top.add_child(close)
	for i in STEPS.size():
		var line := Label.new()
		line.add_theme_font_size_override("font_size", 13)
		box.add_child(line)
		_lines.append(line)
	visible = Options.first_shift and Options.shift_done != DONE_ALL
	_show()


func mark(step: int) -> void:
	## A step done (the screen tells of those it sees: a console opened, the book opened).
	if Options.shift_done & (1 << step):
		return
	Options.shift_done |= 1 << step
	Options.save_all()
	_show()


func _process(_delta: float) -> void:
	if not visible or client == null or client.phase != GameClient.PLAYING or not client._have_self:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _start_at == 0.0:
		_start_at = now
	if now < _start_at + 2.0:
		return
	if _steps_at < 0:
		_steps_at = client.steps_predicted
		_hand_at = client.hand
		_fuel_at = client.fuel
		_sector_at = client.sector
	if client.steps_predicted - _steps_at >= 6:
		mark(WALK)
	if client.supply:
		mark(OXYGEN)
	if client.hand != _hand_at:
		mark(HAND)
	if client.fuel > _fuel_at:
		mark(FUEL)
	_fuel_at = mini(_fuel_at, client.fuel)
	if client.sector != _sector_at:
		mark(JUMP)
	if Options.shift_done == DONE_ALL:
		if _gone_at == 0.0:
			_gone_at = now + SHOW_DONE
		elif now >= _gone_at:
			visible = false
	elif not Options.first_shift:
		visible = false


func _show() -> void:
	for i in _lines.size():
		var done := (Options.shift_done & (1 << i)) != 0
		var text: String = STEPS[i]
		for action: String in ["move_up", "move_left", "move_down", "move_right", "suit", "use", "help"]:
			text = text.replace("{%s}" % action, "[%s]" % Options.key_text(action))
		var line: Label = _lines[i]
		line.text = ("✓ " if done else "○ ") + text
		line.add_theme_color_override("font_color", Color(0.55, 0.8, 0.6) if done else Color(0.92, 0.92, 0.95))
