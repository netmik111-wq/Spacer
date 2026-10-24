extends VBoxContainer
## (v86, the author's N1) The shuttle's dock console's screen, and the shuttle's own while we are in it:
## where the shuttle is, who is aboard, and what can be done (get in, call it here, fly to the other ship,
## get out). The server runs it all (see Shuttle). Shown inside the console frame of GameScreen.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")

const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const BLUE := Color(0.45, 0.75, 1.0)

var client: GameClient
var _state: Label
var _aboard: Label
var _buttons: HBoxContainer
var _shown := ""


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(520, 0)
	_state = _label(16, INK)
	add_child(_state)
	_aboard = _label(13, DIM)
	add_child(_aboard)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	add_child(_buttons)
	var note := _label(12, DIM)
	note.text = "Челнок берёт до %d человек. Перелёт между ангарами — %d с; на месте все выходят сами." % [
		Net.SHUTTLE_SEATS, roundi(Net.SHUTTLE_SECONDS)]
	add_child(note)


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	return l


func refresh() -> void:
	var here := client.shuttle_dock_here()
	var riding := client.riding()
	var at := client.shuttle_at
	var to := client.shuttle_to
	var text := ""
	if at < 0:
		text = "Челнока нет: он летает только между двумя кораблями флотилии, у каждого из которых есть ангар."
	elif to >= 0:
		text = "Челнок летит к кораблю %d: %d%%." % [to + 1, roundi(client.shuttle_done * 100.0)]
	elif riding:
		text = "Вы в челноке у корабля %d." % (at + 1)
	elif at == here:
		text = "Челнок стоит за силовым полем этого ангара."
	else:
		text = "Челнок у корабля %d." % (at + 1)
	_state.text = text
	_aboard.text = "На борту: %d из %d." % [client.shuttle_riders.size(), Net.SHUTTLE_SEATS] if at >= 0 else ""
	# the buttons, rebuilt only when what they can do changed
	var key := "%d %d %d %s %d" % [at, to, here, str(riding), client.shuttle_riders.size()]
	if key == _shown:
		return
	_shown = key
	for b in _buttons.get_children():
		b.queue_free()
	if at < 0 or to >= 0:
		return
	if riding:
		for i in client.shuttle_docks.size():
			if i != at:
				_button("Лететь к кораблю %d" % (i + 1), func() -> void: client.send_shuttle(Net.SHUTTLE_FLY, i), true)
		_button("Выйти", func() -> void: client.send_shuttle(Net.SHUTTLE_LEAVE))
	elif at == here:
		var b := _button("Сесть в челнок", func() -> void: client.send_shuttle(Net.SHUTTLE_BOARD), true)
		b.disabled = client.shuttle_riders.size() >= Net.SHUTTLE_SEATS
	elif here >= 0:
		var b := _button("Вызвать челнок сюда", func() -> void: client.send_shuttle(Net.SHUTTLE_CALL), true)
		b.disabled = not client.shuttle_riders.is_empty()
		if b.disabled:
			b.tooltip_text = "В челноке люди: пусть летят сюда или выйдут."


func _button(text: String, pressed: Callable, main := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if main:
		b.add_theme_color_override("font_color", BLUE)
	b.pressed.connect(pressed)
	_buttons.add_child(b)
	return b
