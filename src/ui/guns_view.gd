extends VBoxContainer
## The gun console's screen. On the left our guns, each with its charge and a
## button to fire it, and a volley of every gun that is ready; on the right the
## enemy ship as the guns' sights see it: its plan, room by room, each room
## coloured by how worn the system in it is. A click on a room aims the guns
## there (a click off the rooms: anywhere); the buttons under the plan do the
## same. Shown inside the console frame of GameScreen while our character
## stands at the gun console.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Gunnery := preload("res://src/server/gunnery.gd")    # only for its numbers, to explain them

const PLAN := Vector2(420, 200)
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const GOOD := Color(0.4, 0.8, 0.5)
const WARN := Color(0.95, 0.72, 0.28)
const BAD := Color(0.92, 0.32, 0.28)
const AIM := Color(1.0, 0.92, 0.35)
const GUN_PLACES: Array[String] = ["левый борт у носа", "правый борт у носа", "днище"]
const SYSTEM_ABOUT: Array[String] = [
	"Выбить орудия: пираты перестанут стрелять. Повреждённые орудия стреляют реже.",
	"Выбить рубку: пираты будут промахиваться вдвое чаще, а наши попадания станут почти верными.",
	"Выбить двигатель: пираты не смогут ни подойти к шлюзу (отсчёт до стыковки встанет), ни уйти прыжком.",
	"Бить по кубрику: каждые два попадания убивают одного пирата; перебьём всех абордажников, и пираты уйдут ни с чем, перебьём весь экипаж, и корабль станет мёртвыми обломками.",
	"Бить по гипердвигателю: повреждённый, он дольше заряжает прыжок; выбитый, не даёт пиратам уйти.",
]

var client: GameClient
var _status: Label
var _guns_box: VBoxContainer
var _gun_rows: Array = []            # per gun: [Label, ColorRect fill, Button]
var _volley: Button
var _plan: Control
var _aims: GridContainer
var _aim_buttons := {}               # Net.ESYS_* or Net.AIM_ANY -> Button
var _about: Label
var _hover := -2                     # the room under the mouse: Net.ESYS_*, -1 = none, -2 = not over the plan
var _time := 0.0


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 10)
	_status = _label(self, 15)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_label(left, 13).text = "Наши орудия"
	_guns_box = VBoxContainer.new()
	_guns_box.add_theme_constant_override("separation", 10)
	left.add_child(_guns_box)
	_volley = Button.new()
	_volley.text = "Залп всеми готовыми"
	_volley.focus_mode = Control.FOCUS_NONE
	_volley.pressed.connect(func() -> void: client.send_guns(255))
	left.add_child(_volley)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	_label(right, 13).text = "Цель: пиратский корабль (щёлкните по отсеку, чтобы навести орудия)"
	_plan = Control.new()
	_plan.custom_minimum_size = PLAN
	_plan.mouse_filter = Control.MOUSE_FILTER_STOP
	_plan.draw.connect(_draw_plan)
	_plan.gui_input.connect(_on_plan_input)
	_plan.mouse_exited.connect(func() -> void: _hover = -2)
	right.add_child(_plan)
	_aims = GridContainer.new()
	_aims.columns = 3
	_aims.add_theme_constant_override("h_separation", 6)
	_aims.add_theme_constant_override("v_separation", 4)
	right.add_child(_aims)
	for which in Net.ESYS_COUNT:
		_aim_button(which)
	_aim_button(Net.AIM_ANY)
	_about = _label(self, 13)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(740, 36)


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _aim_button(which: int) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: client.send_aim(which))
	b.mouse_entered.connect(func() -> void: _hover = which if which != Net.AIM_ANY else -1)
	b.mouse_exited.connect(func() -> void: _hover = -2)
	_aims.add_child(b)
	_aim_buttons[which] = b


func refresh(delta: float) -> void:
	## Called every frame while the screen is shown.
	_time += delta
	var fighting := client.enemy_full > 0 and client.enemy_sys.size() == Net.ESYS_COUNT
	if fighting:
		var what := ""
		if client.enemy_flags & Net.ENEMY_FLEEING:
			what = "Пираты заряжают прыжок, чтобы уйти: %s." % ("прыжок сорван, пока не починят" if client.enemy_jumps_in == 65535
				else "уйдут через %d с" % client.enemy_jumps_in)
		elif client.enemy_flags & Net.ENEMY_RAID:
			what = "Пираты ведут бой на расстоянии."
		else:
			what = "Пристыкуется силой через %d с%s." % [client.enemy_docks_in,
				" (двигатель выбит: стоит на месте)" if client.enemy_sys[Net.ESYS_ENGINE] == 0 else ""]
		_status.text = "Корпус пиратского корабля: %d из %d попаданий до разрушения. %s" % [client.enemy_hull, client.enemy_full, what]
	else:
		_status.text = "Целей нет. Орудия бьют по пиратскому кораблю, пока он не пристыковался."
	_update_guns(fighting)
	for which: int in _aim_buttons.keys():
		var b: Button = _aim_buttons[which]
		b.disabled = not fighting
		b.set_pressed_no_signal(fighting and client.gun_aim == which)
		if which == Net.AIM_ANY:
			b.text = "Куда попадёт"
		elif fighting:
			b.text = "%s: %s" % [Net.ESYS_NAMES[which], _state(which)]
		else:
			b.text = Net.ESYS_NAMES[which]
	var hit := Gunnery.BLIND_HIT_CHANCE if fighting and client.enemy_sys[Net.ESYS_HELM] == 0 else Gunnery.HIT_CHANCE
	var lines := PackedStringArray()
	var about := _hover if _hover >= 0 else (client.gun_aim if fighting and client.gun_aim != Net.AIM_ANY else -1)
	if about >= 0:
		lines.append(SYSTEM_ABOUT[about])
	else:
		lines.append("Без наводки снаряд ложится в случайный отсек. Каждое попадание отнимает единицу корпуса и бьёт по системе в отсеке.")
	lines.append("Попадание: %d%%. Зарядка %d с, нужно питание. Выбитую систему пираты чинят: единица за %d с." % [
		roundi(hit * 100.0), int(Gunnery.CHARGE_SECONDS), int(Gunnery.ENEMY_REPAIR_SECONDS)])
	_about.text = "\n".join(lines)
	_plan.queue_redraw()


func _state(which: int) -> String:
	var left: int = client.enemy_sys[which]
	if which == Net.ESYS_CREW:
		return "%d чел." % ((left + Gunnery.HITS_PER_BOARDER - 1) / Gunnery.HITS_PER_BOARDER)
	return "выбит" if left == 0 else "%d/%d" % [left, client.enemy_sys_full[which]]


func _update_guns(fighting: bool) -> void:
	if _gun_rows.size() != client.gun_charge.size():
		for old in _guns_box.get_children():
			old.queue_free()
		_gun_rows.clear()
		for i in client.gun_charge.size():
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 3)
			_guns_box.add_child(box)
			var head := HBoxContainer.new()
			box.add_child(head)
			var title := _label(head, 13)
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var fire := Button.new()
			fire.text = "Огонь"
			fire.focus_mode = Control.FOCUS_NONE
			var which := i
			fire.pressed.connect(func() -> void: client.send_guns(which))
			head.add_child(fire)
			var bar := ColorRect.new()
			bar.custom_minimum_size = Vector2(300, 8)
			bar.color = Color(0.15, 0.17, 0.2)
			box.add_child(bar)
			var fill := ColorRect.new()
			fill.size = Vector2(0, 8)
			bar.add_child(fill)
			_gun_rows.append([title, fill, fire])
	var any := false
	for i in client.gun_charge.size():
		var c: int = client.gun_charge[i]
		var row: Array = _gun_rows[i]
		var place := GUN_PLACES[i] if i < GUN_PLACES.size() else ""
		(row[0] as Label).text = "Орудие %d (%s): %s" % [i + 1, place, "сломано, нужен ремонт" if c == 255 else ("готово" if c >= 100 else "заряжается, %d%%" % c)]
		var fill: ColorRect = row[1]
		fill.size = Vector2(300.0 * (0.0 if c == 255 else c / 100.0), 8)
		fill.color = BAD if c == 255 else (GOOD if c >= 100 else WARN)
		(row[2] as Button).disabled = not fighting or c != 100
		any = any or c == 100
	_volley.disabled = not fighting or not any


# ---------------------------------------------------------------- the enemy's plan

func _layout() -> Array:
	## [the enemy's drawing (ShipMap), cell size, where its corner goes on the plan].
	var o = client.map.others[Net.OTHER_PIRATE] if client.map.others.size() > Net.OTHER_PIRATE else null
	if o == null:
		return [null, 0.0, Vector2.ZERO]
	var px := floorf(minf(PLAN.x / o.width, PLAN.y / o.height))
	return [o, px, (PLAN - Vector2(o.width, o.height) * px) / 2.0]


func _zone_of(o, local: int) -> int:
	for k in o.zones.size():
		if (o.zones[k] as PackedInt32Array).has(local):
			return k
	return -1


func _draw_plan() -> void:
	var font := ThemeDB.fallback_font
	_plan.draw_rect(Rect2(Vector2.ZERO, PLAN), Color(0.03, 0.06, 0.05))
	var lay := _layout()
	var o = lay[0]
	if o == null:
		return
	var px: float = lay[1]
	var at: Vector2 = lay[2]
	var fighting := client.enemy_full > 0 and client.enemy_sys.size() == Net.ESYS_COUNT
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	for y in o.height:
		for x in o.width:
			var local: int = y * o.width + x
			if o.cells[local] < 0:
				continue
			var r := Rect2(at + Vector2(x, y) * px, Vector2(px, px))
			if o.walk[local] == 0:
				_plan.draw_rect(r, Color(0.25, 0.3, 0.3) if fighting else Color(0.15, 0.18, 0.18))
				continue
			var z := _zone_of(o, local)
			var c := Color(0.12, 0.16, 0.16)
			if z >= 0 and fighting:
				var share := float(client.enemy_sys[z]) / maxf(client.enemy_sys_full[z], 1.0)
				c = (GOOD if share >= 1.0 else (WARN if share > 0.0 else BAD)).darkened(0.55)
				if z == _hover:
					c = c.lightened(0.25)
			_plan.draw_rect(r.grow(-1.0), c)
	if not fighting:
		_plan.draw_string(font, Vector2(0, PLAN.y / 2.0 + 6), "Нет цели", HORIZONTAL_ALIGNMENT_CENTER, PLAN.x, 18, DIM)
		return
	# the rooms' names and the sights on the room aimed at
	for k in o.zones.size():
		var cells: PackedInt32Array = o.zones[k]
		if cells.is_empty():
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for local in cells:
			var v := Vector2(local % o.width, local / o.width)
			lo = lo.min(v)
			hi = hi.max(v + Vector2.ONE)
		var box := Rect2(at + lo * px, (hi - lo) * px)
		var name := Net.ESYS_NAMES[k]
		var size := 13
		while size > 10 and font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > box.size.x - 2.0:
			size -= 1
		if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > box.size.x - 2.0:
			name = "Прыжок"                  # (a small room: the jump drive's short name)
		_plan.draw_string(font, box.position + Vector2(0, box.size.y / 2.0 - 2), name, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, size, INK)
		_plan.draw_string(font, box.position + Vector2(0, box.size.y / 2.0 + 14), _state(k), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 11, INK)
		if k == client.gun_aim:
			var aim := Color(AIM, 0.5 + 0.5 * pulse)
			_plan.draw_rect(box.grow(2.0), aim, false, 2.0)
			var mid := box.get_center()
			var rad := minf(box.size.x, box.size.y) * 0.35
			_plan.draw_arc(mid, rad, 0.0, TAU, 32, aim, 1.5)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_plan.draw_line(mid + d * rad * 0.6, mid + d * rad * 1.3, aim, 1.5)
	# holes in its hull, where we have seen them
	if client.other_here() and client.pirates_alongside():
		for y in o.height:
			for x in o.width:
				var cell: int = (client.map.other_at.y + y) * client.map.width + client.map.other_at.x + x
				if client.holes.has(cell):
					var mid := at + (Vector2(x, y) + Vector2(0.5, 0.5)) * px
					_plan.draw_line(mid - Vector2(4, 4), mid + Vector2(4, 4), BAD, 2.0)
					_plan.draw_line(mid - Vector2(4, -4), mid + Vector2(4, -4), BAD, 2.0)
	if client.gun_aim == Net.AIM_ANY:
		_plan.draw_string(font, Vector2(6, PLAN.y - 6), "Наводки нет: куда попадёт", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)


func _room_at(at: Vector2) -> int:
	var lay := _layout()
	var o = lay[0]
	if o == null:
		return -1
	var v: Vector2 = (at - (lay[2] as Vector2)) / float(lay[1])
	if v.x < 0 or v.y < 0 or v.x >= o.width or v.y >= o.height:
		return -1
	return _zone_of(o, int(v.y) * o.width + int(v.x))


func _on_plan_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _room_at((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and client.enemy_full > 0:
		var room := _room_at((event as InputEventMouseButton).position)
		client.send_aim(room if room >= 0 else Net.AIM_ANY)
		_plan.accept_event()
