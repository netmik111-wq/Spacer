extends Control
## The first screen: pick a name, then create a game or join one.

signal host_requested(player_name: String, port: int, bots: int)
signal join_requested(player_name: String, address: String, port: int)
signal quit_requested

const Net := preload("res://src/shared/net.gd")
const SETTINGS := "user://settings.cfg"

var _name: LineEdit
var _address: LineEdit
var _bots: SpinBox
var _status: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.043, 0.047, 0.078)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.14)
	style.border_color = Color(0.36, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Космический прототип"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Шаг 1: сервер и экипаж на одном корабле"
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_gap(8))

	box.add_child(_caption("Имя"))
	_name = LineEdit.new()
	_name.max_length = Net.MAX_NAME
	_name.placeholder_text = "Как вас зовут на борту"
	box.add_child(_name)
	box.add_child(_gap(6))

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	box.add_child(host_row)
	var host := _button("Создать игру")
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(_on_host)
	host_row.add_child(host)
	var bots_caption := Label.new()
	bots_caption.text = "Ботов:"
	host_row.add_child(bots_caption)
	_bots = SpinBox.new()
	_bots.min_value = 0
	_bots.max_value = 8
	_bots.value = 2
	_bots.tooltip_text = "Боты просто бродят по кораблю: с ними видно, как выглядят другие игроки"
	host_row.add_child(_bots)
	box.add_child(_gap(6))

	box.add_child(_caption("Адрес сервера (для подключения к чужой игре)"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "127.0.0.1"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	join_row.add_child(_address)
	var join := _button("Подключиться")
	join.pressed.connect(_on_join)
	join_row.add_child(join)
	box.add_child(_gap(6))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 44)
	_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_status)

	var quit := _button("Выход")
	quit.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit)

	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		_name.text = str(cfg.get_value("player", "name", ""))
		_address.text = str(cfg.get_value("player", "address", ""))
		_bots.value = int(cfg.get_value("player", "bots", 2))
	_name.grab_focus()


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	_buttons.append(b)
	return b


func show_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1.0, 0.55, 0.5) if is_error else Color(0.75, 0.85, 1.0)


func set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy


func player_name() -> String:
	var n := _name.text.strip_edges()
	return n if not n.is_empty() else "Игрок"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", _name.text.strip_edges())
	cfg.set_value("player", "address", _address.text.strip_edges())
	cfg.set_value("player", "bots", int(_bots.value))
	cfg.save(SETTINGS)


func _on_host() -> void:
	_save()
	host_requested.emit(player_name(), Net.DEFAULT_PORT, int(_bots.value))


func _on_join() -> void:
	_save()
	var text := _address.text.strip_edges()
	if text.is_empty():
		text = "127.0.0.1"
	var port := Net.DEFAULT_PORT
	# "address:port" is accepted (IPv6 addresses are left alone)
	if text.count(":") == 1:
		var parts := text.split(":")
		if parts[1].is_valid_int():
			text = parts[0]
			port = parts[1].to_int()
	join_requested.emit(player_name(), text, port)
