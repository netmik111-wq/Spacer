extends VBoxContainer
## The gun console's screen. On the left the reactor's power, our shield and
## our guns: each with the weapon on it, its charge, a button to fire it, a
## switch for its power and a list to change the weapon for one in the cargo;
## and a volley of every gun that is ready. On the right the enemy ship as the
## guns' sights see it: its shield, its guns, its plan room by room, each room
## coloured by how worn the system in it is. A click on a room aims the guns
## there (a click off the rooms: anywhere); the buttons under the plan do the
## same. Shown inside the console frame of GameScreen while our character
## stands at the gun console.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Gunnery := preload("res://src/server/gunnery.gd")    # only for its numbers, to explain them
const Weapons := preload("res://src/shared/weapons.gd")

const PLAN := Vector2(420, 190)
const BAR := 330.0
const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const GOOD := Color(0.4, 0.8, 0.5)
const WARN := Color(0.95, 0.72, 0.28)
const BAD := Color(0.92, 0.32, 0.28)
const AIM := Color(1.0, 0.92, 0.35)
const SHIELD := Color(0.4, 0.65, 1.0)
const ION := Color(0.45, 0.7, 1.0)
const GUN_PLACES: Array[String] = ["левый борт у носа", "правый борт у носа", "днище"]
const SYSTEM_ABOUT: Array[String] = [
	"Выбить орудия: пираты перестанут стрелять. Повреждённые орудия стреляют реже.",
	"Выбить рубку: пираты будут промахиваться вдвое чаще, а наши попадания станут вернее.",
	"Выбить двигатель: пираты не смогут ни подойти к шлюзу (отсчёт до стыковки встанет), ни уйти прыжком.",
	"Бить по кубрику: каждые два урона убивают одного пирата; перебьём всех абордажников, и пираты уйдут ни с чем, перебьём весь экипаж, и корабль станет мёртвыми обломками.",
	"Бить по гипердвигателю: повреждённый, он дольше заряжает прыжок; выбитый, не даёт пиратам уйти.",
	"Бить по генератору щита: повреждённый, щит восстанавливается медленнее; выбитый, щит гаснет совсем. Ион и ЭМИ сюда гасят щит на время.",
]

var client: GameClient
var _status: Label
var _power: Label
var _power_bar: ColorRect
var _shield_label: Label
var _shield_bar: ColorRect
var _shield_button: Button
var _guns_box: VBoxContainer
var _gun_rows: Array = []            # per gun: [Label, ColorRect fill, fire Button, power Button, OptionButton, its signature]
var _volley: Button
var _enemy_line: Label
var _enemy_shield: ColorRect
var _plan: Control
var _aims: GridContainer
var _aim_buttons := {}               # Net.ESYS_* or Net.AIM_ANY -> Button
var _about: Label
var _hover := -2                     # the room under the mouse: Net.ESYS_*, -1 = none, -2 = not over the plan
var _hover_gun := -1                 # the gun whose row the mouse is over
var _time := 0.0


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	_status = _label(self, 15)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(BAR + 10, 0)
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	_power = _label(left, 13)
	_power_bar = _bar(left, DIM)
	var shield_head := HBoxContainer.new()
	left.add_child(shield_head)
	_shield_label = _label(shield_head, 13)
	_shield_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shield_button = Button.new()
	_shield_button.focus_mode = Control.FOCUS_NONE
	_shield_button.pressed.connect(func() -> void:
		client.send_gunset(Net.GUNSET_SHIELD, 0, 0 if client.shield_flags & Net.SHF_ON else 1))
	shield_head.add_child(_shield_button)
	_shield_bar = _bar(left, SHIELD)
	_label(left, 13).text = "Наши орудия"
	_guns_box = VBoxContainer.new()
	_guns_box.add_theme_constant_override("separation", 8)
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
	_enemy_line = _label(right, 12)
	_enemy_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_line.custom_minimum_size = Vector2(PLAN.x, 0)
	_enemy_shield = _bar(right, SHIELD, PLAN.x)
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
	_about.custom_minimum_size = Vector2(BAR + 24 + PLAN.x, 52)


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _bar(parent: Control, colour: Color, width: float = BAR) -> ColorRect:
	## A thin gauge: returns its fill, sized by _fill.
	var back := ColorRect.new()
	back.custom_minimum_size = Vector2(width, 8)
	back.color = Color(0.15, 0.17, 0.2)
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.size = Vector2(0, 8)
	fill.color = colour
	back.add_child(fill)
	return fill


static func _fill(fill: ColorRect, share: float) -> void:
	fill.size = Vector2((fill.get_parent() as Control).custom_minimum_size.x * clampf(share, 0.0, 1.0), 8)


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


func _fighting() -> bool:
	return client.enemy_full > 0 and client.enemy_sys.size() == Net.ESYS_COUNT


func refresh(delta: float) -> void:
	## Called every frame while the screen is shown.
	_time += delta
	var fighting := _fighting()
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
		if client.enemy_flags & Net.ENEMY_HELD:
			what += " Захватный луч держит их: не уклоняются, не уходят и не подходят."
		_status.text = "Корпус пиратского корабля: %d из %d. %s" % [client.enemy_hull, client.enemy_full, what]
		var names := PackedStringArray()
		for w in client.enemy_weapons:
			names.append(Weapons.name_of(w).to_lower())
		var has_shield: bool = client.enemy_sys_full[Net.ESYS_SHIELDS] > 0
		_enemy_line.text = "Щит пиратов: %s. Их орудия: %s." % [("%d из 100%s" % [client.enemy_shield,
			", пропускает" if client.enemy_shield < Weapons.SHIELD_HOLDS else ""]) if has_shield else "нет генератора щита",
			", ".join(names) if not names.is_empty() else "нет"]
		_fill(_enemy_shield, client.enemy_shield / 100.0 if has_shield else 0.0)
		_enemy_shield.color = SHIELD if client.enemy_shield >= Weapons.SHIELD_HOLDS else WARN
	else:
		_status.text = "Целей нет. Орудия бьют по пиратскому кораблю, пока он не пристыковался."
		_enemy_line.text = ""
		_fill(_enemy_shield, 0.0)
	_update_power()
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
	var lines := PackedStringArray()
	var about := _hover if _hover >= 0 else (client.gun_aim if fighting and client.gun_aim != Net.AIM_ANY else -1)
	if _hover_gun >= 0 and _hover_gun < client.gun_weapon.size() and client.gun_weapon[_hover_gun] != Weapons.NONE:
		var w: int = client.gun_weapon[_hover_gun]
		lines.append("%s. %s Энергия: %d." % [Weapons.name_of(w), Weapons.info(w)["about"], Weapons.power(w)])
	elif about >= 0:
		lines.append(SYSTEM_ABOUT[about])
	else:
		lines.append("Без наводки снаряд ложится в случайный отсек. Попадание отнимает урон у корпуса и у системы в отсеке.")
	lines.append("Щит держит всё, пока он не ниже 50; ниже пропускает выстрелы тем чаще, чем он слабее, и сам восстанавливается (%s в секунду). Ракеты щит не держит, бластер наполовину. Выбитую систему пираты чинят: единица за %d с." % [
		str(Weapons.SHIELD_REGEN), int(Gunnery.ENEMY_REPAIR_SECONDS)])
	_about.text = "\n".join(lines)
	_plan.queue_redraw()


func _update_power() -> void:
	_power.text = "Реактор: занято %d из %d энергии" % [client.power_used, client.power_max]
	_fill(_power_bar, float(client.power_used) / maxf(client.power_max, 1.0))
	_power_bar.color = WARN if client.power_used >= client.power_max else GOOD
	var f := client.shield_flags
	if not (f & Net.SHF_HAS):
		_shield_label.text = "Щит: на корабле нет генератора"
		_shield_button.visible = false
		_fill(_shield_bar, 0.0)
		return
	_shield_button.visible = true
	_shield_button.text = "Выключить щит" if f & Net.SHF_ON else "Включить щит (%d эн.)" % Weapons.SHIELD_POWER
	var state := "%d из 100" % client.shield
	if not (f & Net.SHF_ON):
		state = "выключен"
	elif f & Net.SHF_BROKEN:
		state = "генератор сломан, нужен ремонт"
	elif f & Net.SHF_JAMMED:
		state = "%d, генератор выключен ионом" % client.shield
	elif not client.powered():
		state = "нет питания"
	elif client.shield < Weapons.SHIELD_HOLDS:
		state += ", пропускает"
	_shield_label.text = "Щит: %s%s" % [state, " (закалён)" if f & Net.SHF_HARDENED else ""]
	_fill(_shield_bar, client.shield / 100.0)
	_shield_bar.color = ION if f & Net.SHF_JAMMED else (SHIELD if client.shield >= Weapons.SHIELD_HOLDS else WARN)


func _state(which: int) -> String:
	var left: int = client.enemy_sys[which]
	if client.enemy_sys_full[which] == 0:
		return "нет"
	if which == Net.ESYS_CREW:
		return "%d чел." % ((left + Gunnery.HITS_PER_BOARDER - 1) / Gunnery.HITS_PER_BOARDER)
	if left > 0 and which < client.enemy_sys_out.size() and client.enemy_sys_out[which] > 0:
		return "выкл. %d с" % client.enemy_sys_out[which]
	return "выбит" if left == 0 else "%d/%d" % [left, client.enemy_sys_full[which]]


func _cargo_guns() -> Array:
	## [weapon, how many] of every ship weapon in the cargo.
	var out: Array = []
	for w in range(1, Weapons.COUNT):
		var n := client.stock(Weapons.item_of(w))
		if n > 0:
			out.append([w, n])
	return out


func _update_guns(fighting: bool) -> void:
	var n := client.gun_charge.size()
	if _gun_rows.size() != n:
		for old in _guns_box.get_children():
			old.queue_free()
		_gun_rows.clear()
		for i in n:
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 3)
			box.mouse_filter = Control.MOUSE_FILTER_PASS
			var which := i
			box.mouse_entered.connect(func() -> void: _hover_gun = which)
			box.mouse_exited.connect(func() -> void: _hover_gun = -1)
			_guns_box.add_child(box)
			var title := _label(box, 13)
			var bar := _bar(box, GOOD)
			var buttons := HBoxContainer.new()
			buttons.add_theme_constant_override("separation", 6)
			box.add_child(buttons)
			var fire := Button.new()
			fire.text = "Огонь"
			fire.focus_mode = Control.FOCUS_NONE
			fire.pressed.connect(func() -> void: client.send_guns(which))
			buttons.add_child(fire)
			var power := Button.new()
			power.focus_mode = Control.FOCUS_NONE
			power.pressed.connect(func() -> void:
				client.send_gunset(Net.GUNSET_ARM, which, 0 if client.gun_flags[which] & Net.GUNF_ARMED else 1))
			buttons.add_child(power)
			var change := OptionButton.new()
			change.focus_mode = Control.FOCUS_NONE
			change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			change.fit_to_longest_item = false
			change.item_selected.connect(func(index: int) -> void:
				var w := change.get_item_id(index)
				change.select(0)
				if w >= 0:
					client.send_gunset(Net.GUNSET_MOUNT, which, w))
			buttons.add_child(change)
			for c: Control in [title, bar.get_parent(), buttons]:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
			_gun_rows.append([title, bar, fire, power, change, ""])
	var any := false
	var cargo := _cargo_guns()
	for i in n:
		var c: int = client.gun_charge[i]
		var w: int = client.gun_weapon[i]
		var flags: int = client.gun_flags[i]
		var row: Array = _gun_rows[i]
		var place := GUN_PLACES[i] if i < GUN_PLACES.size() else ""
		var state := ""
		if c == Net.GUN_BROKEN:
			state = "сломано, нужен ремонт"
		elif w == Weapons.NONE:
			state = "пусто"
		elif c == Net.GUN_JAMMED:
			state = "выключено ионом"
		elif not (flags & Net.GUNF_ARMED):
			state = "без питания"
		elif flags & Net.GUNF_BEAM:
			state = "луч горит"
		elif flags & Net.GUNF_NO_AMMO:
			state = "нет ракет"
		else:
			state = "готово" if c >= 100 else "заряжается, %d%%" % c
		var ammo := Weapons.ammo(w)
		(row[0] as Label).text = "%d. %s (%s): %s%s" % [i + 1, Weapons.name_of(w), place, state,
			(", ракет: %d" % client.stock(ammo)) if ammo != 0 else ""]
		var fill: ColorRect = row[1]
		var share := 0.0 if c >= Net.GUN_JAMMED else c / 100.0
		_fill(fill, 1.0 if c >= Net.GUN_JAMMED else share)
		fill.color = BAD if c == Net.GUN_BROKEN else (ION if c == Net.GUN_JAMMED else (GOOD if c >= 100 else WARN))
		var ready := c == 100 and flags & Net.GUNF_ARMED and not (flags & Net.GUNF_NO_AMMO) and not (flags & Net.GUNF_BEAM)
		(row[2] as Button).disabled = not fighting or not ready
		var power: Button = row[3]
		power.disabled = w == Weapons.NONE
		power.text = ("Питание: вкл" if flags & Net.GUNF_ARMED else "Питание: выкл (%d эн.)" % Weapons.power(w)) if w != Weapons.NONE else "Питание"
		any = any or ready
		# the list to change the weapon, rebuilt when the cargo or the gun changes
		var sig := "%d:%s" % [w, str(cargo)]
		if row[5] != sig:
			row[5] = sig
			var change: OptionButton = row[4]
			change.clear()
			change.add_item("Сменить оружие…", -1)
			for k: Array in cargo:
				change.add_item("Поставить: %s (в трюме %d, %d эн.)" % [Weapons.name_of(k[0]), k[1], Weapons.power(k[0])], k[0])
			if w != Weapons.NONE:
				change.add_item("Снять в трюм", Weapons.NONE)
			change.select(0)
			change.disabled = change.item_count <= 1
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
				if client.enemy_sys_full[z] == 0:
					c = Color(0.16, 0.18, 0.2)              # (no shield generator in it)
				elif z < client.enemy_sys_out.size() and client.enemy_sys_out[z] > 0:
					c = ION.darkened(0.5)                     # put out by ion or EMP for now
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
			name = "Прыжок" if k == Net.ESYS_JUMP else name.left(3)   # (a small room: a short name)
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
