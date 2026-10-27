extends PanelContainer
## (v55) The crew window (its own key, O by default): who mans the posts in a
## fight, the battle position, and the captain's orders to the bots, a row of
## buttons per bot. Anybody may look; orders go through only from the captain,
## or from anybody while no captain is aboard (the server decides). The
## character can walk while it is open.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")

var client: GameClient
var _status: Label
var _rows: GridContainer
var _hint: Label
var _shown_ids := PackedInt32Array()
var _labels: Array = []              # per bot row: its Label
var _buttons: Array = []             # per bot row: its Buttons, one per Net.POST_*
var _all: Button
var _free: Button
var _arms_all: Button               # (v89) every bot fights boarders
var _arms_none: Button              # (v89) only the guards do
var _log: RichTextLabel              # (v72) the bots' log
var _log_shown := 0                  # GameClient.bot_log_count already in it
var _log_any := false


func setup(p_client: GameClient) -> void:
	client = p_client
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	style.border_color = Color(0.7, 0.6, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Экипаж и посты"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var shut := Button.new()
	shut.text = "Закрыть"
	shut.focus_mode = Control.FOCUS_NONE
	shut.pressed.connect(func() -> void: visible = false)
	head.add_child(shut)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(720, 0)
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_all = Button.new()
	_all.text = "Все по местам"
	_all.tooltip_text = "Каждый бот к посту, который не занят игроком: штурвал, орудия, щиты, двигатель; остальные чинят"
	_all.focus_mode = Control.FOCUS_NONE
	_all.pressed.connect(func() -> void: client.send_order(Net.NOBODY, Net.POST_ALL))
	row.add_child(_all)
	_free = Button.new()
	_free.text = "Отбой"
	_free.tooltip_text = "Все боты свободны и бродят по кораблю"
	_free.focus_mode = Control.FOCUS_NONE
	_free.pressed.connect(func() -> void: client.send_order(Net.NOBODY, Net.POST_FREE))
	row.add_child(_free)
	# (v89, the author's note: "defenders of the ship... or only some of our crew fights back")
	_arms_all = Button.new()
	_arms_all.text = "Все к оружию"
	_arms_all.tooltip_text = "Каждый бот при абордаже берёт оружие из шкафа снабжения и отбивается, как охранник"
	_arms_all.focus_mode = Control.FOCUS_NONE
	_arms_all.pressed.connect(func() -> void: client.send_order(Net.NOBODY, Net.POST_ARMS))
	row.add_child(_arms_all)
	_arms_none = Button.new()
	_arms_none.text = "Оружие только охране"
	_arms_none.tooltip_text = "Боты, кроме охранников, при абордаже снова укрываются"
	_arms_none.focus_mode = Control.FOCUS_NONE
	_arms_none.pressed.connect(func() -> void: client.send_order(Net.NOBODY, Net.POST_NO_ARMS))
	row.add_child(_arms_none)
	_rows = GridContainer.new()
	_rows.columns = 2 + Net.POSTS
	_rows.add_theme_constant_override("h_separation", 4)
	_rows.add_theme_constant_override("v_separation", 4)
	box.add_child(_rows)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(720, 0)
	box.add_child(_hint)
	# (v72, the author's note) the bots' log: what each bot set about, kept for the whole game
	var head2 := Label.new()
	head2.text = "Журнал ботов (весь за игру; он же в файле crew_log.txt рядом с игрой)"
	head2.add_theme_font_size_override("font_size", 15)
	box.add_child(head2)
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(720, 200)
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.focus_mode = Control.FOCUS_NONE
	_log.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_log)


func toggle() -> void:
	visible = not visible
	_shown_ids = PackedInt32Array([-1])


func _process(_delta: float) -> void:
	if not visible:
		return
	var may := client.may_order()
	_status.text = _status_text()
	_add_log()
	_all.disabled = not may or client.crew_bots.is_empty()
	_free.disabled = not may or client.crew_bots.is_empty()
	_arms_all.disabled = _free.disabled
	_arms_none.disabled = _free.disabled
	_hint.text = ("" if may else "Приказы отдаёт капитан. ") + \
		"Человек или бот у пульта управления уклоняет корабль от выстрелов пиратов, у двигателя добавляет уклонения, у генератора щита ускоряет его восстановление. Бот у пульта орудий сам стреляет готовыми орудиями туда, куда они наведены. «У орудия»: бот встаёт у орудия в корпусе, и оно заряжается быстрее. Бот на «Работах» чинит, сам приносит запчасти и заплатки из шкафа снабжения, носит и ставит орудия по приказам с пульта орудий. Раненый бот сам ложится в автодок, а без воздуха включает подачу кислорода. «К оружию»: при абордаже бот берёт пистолет или дробовик из шкафа снабжения и отбивается, как охранник; без этого он укрывается от вооружённых пиратов."
	var ids := PackedInt32Array()
	for b: Array in client.crew_bots:
		ids.append(int(b[0]))
	ids.append(client.my_fleet)
	if ids != _shown_ids:
		_shown_ids = ids
		_build_rows()
	for i in client.crew_bots.size():
		var b: Array = client.crew_bots[i]
		var doing: String = "бродит по кораблю" if int(b[1]) == Net.POST_FREE and int(b[2]) == Net.DOING_IDLE \
			else Net.DOING_NAMES[clampi(int(b[2]), 0, Net.DOING_NAMES.size() - 1)]
		(_labels[i] as Label).text = "%s: %s" % [client.player_name(int(b[0])), doing]
		var buttons: Array = _buttons[i]
		for post in Net.POSTS:
			var button: Button = buttons[post]
			button.button_pressed = int(b[1]) == post
			button.disabled = not may
		var arms: Button = buttons[Net.POSTS]
		arms.button_pressed = b.size() > 4 and bool(b[4])
		arms.disabled = not may


func _add_log() -> void:
	var fresh := mini(client.bot_log_count - _log_shown, client.bot_log.size())
	_log_shown = client.bot_log_count
	for i in range(client.bot_log.size() - fresh, client.bot_log.size()):
		var e: Array = client.bot_log[i]
		if _log_any:
			_log.newline()
		_log_any = true
		_log.add_text("%s  %s: %s" % [GameClient.clock(int(e[0])), e[1], e[2]])


func _build_rows() -> void:
	for old in _rows.get_children():
		old.queue_free()
	_labels = []
	_buttons = []
	if client.crew_bots.is_empty():
		var none := Label.new()
		none.text = "Ботов на борту нет. Их число задаётся при создании игры."
		_rows.add_child(none)
		for k in Net.POSTS + 1:
			_rows.add_child(Control.new())
		return
	var ships := {}
	for b: Array in client.crew_bots:
		ships[int(b[3]) if b.size() > 3 else 0] = true
	var heading := -1
	for b: Array in client.crew_bots:
		var id := int(b[0])
		var ship := int(b[3]) if b.size() > 3 else 0
		if ships.size() > 1 and ship != heading:
			# (v86, the author's note) our fleet: each ship's bots under its own heading
			heading = ship
			var title := Label.new()
			title.text = "Корабль %d%s" % [ship + 1, " (вы здесь)" if ship == client.my_fleet else ""]
			title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
			_rows.add_child(title)
			for k in Net.POSTS + 1:
				_rows.add_child(Control.new())
		var name := Label.new()
		name.custom_minimum_size = Vector2(200, 0)
		_rows.add_child(name)
		_labels.append(name)
		var buttons: Array = []
		for post in Net.POSTS:
			var button := Button.new()
			button.text = Net.POST_NAMES[post]
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 13)
			button.pressed.connect(func() -> void: client.send_order(id, post))
			_rows.add_child(button)
			buttons.append(button)
		# (v89) whether it fights boarders (the guard's job always does)
		var arms := Button.new()
		arms.text = "К оружию"
		arms.tooltip_text = "При абордаже бот берёт оружие из шкафа снабжения и отбивается; без этого он укрывается"
		arms.toggle_mode = true
		arms.focus_mode = Control.FOCUS_NONE
		arms.add_theme_font_size_override("font_size", 13)
		arms.pressed.connect(func() -> void: client.send_order(id, Net.POST_ARMS if arms.button_pressed else Net.POST_NO_ARMS))
		_rows.add_child(arms)
		buttons.append(arms)
		_buttons.append(buttons)


func _status_text() -> String:
	var posts := PackedStringArray()
	var names := ["Штурвал", "Орудия", "Двигатель", "Щиты"]
	for k in 4:
		posts.append("%s: %s" % [names[k], "занят" if client.posts_manned & (1 << k) else "никого"])
	var lines := PackedStringArray([", ".join(posts) + "."])
	if client.fighting():
		var pos := "Позиция в бою: %s" % Net.POS_NAMES[client.battle_pos].to_lower()
		if client.battle_goal != Net.POS_NONE:
			pos += ", манёвр на «%s», ещё %d с" % [Net.POS_NAMES[client.battle_goal].to_lower(), client.battle_left]
		lines.append(pos + ". Уклонение от выстрелов пиратов: %d%%." % client.our_dodge)
	else:
		lines.append("Боя нет.")
	return "\n".join(lines)
