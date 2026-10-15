extends VBoxContainer
## The gun console's screen. On the left the reactor's power, our shield and
## our guns: each with the weapon on it, its charge, a button to fire it, a
## switch for its power and a list to change the weapon for one in the cargo;
## and a volley of every gun that is ready. On the right the enemy ship as the
## guns' sights see it: its name and class, its shield, its guns, its plan room
## by room, each room coloured by how worn the system in it is. Rooms not
## scanned yet show a question mark (v53): which room holds what is rolled for
## every ship. A click on a room aims the guns there (a click off the rooms:
## anywhere); the buttons under the plan aim at a system once we know its room.
## A probe from the cargo shows the whole ship. Shown inside the console frame of GameScreen while our character
## stands at the gun console.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Gunnery := preload("res://src/server/gunnery.gd")    # only for its numbers, to explain them
const Weapons := preload("res://src/shared/weapons.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const EnemyPlan := preload("res://src/ui/enemy_plan.gd")
const UNKNOWN := Color(0.22, 0.26, 0.34)

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
var _target: Label
var _probe: Button
var _ransom: Button
var _enemy_shield: ColorRect
var _plan: Control
var _aims: GridContainer
var _aim_buttons := {}               # Net.ESYS_* or Net.AIM_ANY -> Button
var _about: Label
var _hover := -2                     # the system under the mouse: Net.ESYS_*, -1 = none, -2 = not over the plan
var _hover_room := -1                # the room of the plan under the mouse (-1 = none)
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
	_target = _label(right, 13)
	_enemy_line = _label(right, 12)
	_enemy_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_line.custom_minimum_size = Vector2(PLAN.x, 0)
	_enemy_shield = _bar(right, SHIELD, PLAN.x)
	_plan = Control.new()
	_plan.custom_minimum_size = PLAN
	_plan.mouse_filter = Control.MOUSE_FILTER_STOP
	_plan.draw.connect(_draw_plan)
	_plan.gui_input.connect(_on_plan_input)
	_plan.mouse_exited.connect(func() -> void:
		_hover = -2
		_hover_room = -1)
	right.add_child(_plan)
	_probe = Button.new()
	_probe.focus_mode = Control.FOCUS_NONE
	_probe.pressed.connect(func() -> void: client.send_gunset(Net.GUNSET_PROBE, 0, 0))
	right.add_child(_probe)
	_ransom = Button.new()
	_ransom.focus_mode = Control.FOCUS_NONE
	_ransom.visible = false
	_ransom.pressed.connect(func() -> void: client.send_gunset(Net.GUNSET_RANSOM, 0, 0))
	right.add_child(_ransom)
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
		if client.ransom > 0:
			what = "Пираты сдаются и ждут ответа на выкуп (%d с). Выстрел будет отказом." % client.ransom_left
		elif client.enemy_flags & Net.ENEMY_FLEEING:
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
		var temper := "не известны (покажет зонд)"
		if client.enemy_temper != Net.TEMPER_UNKNOWN:
			var t: Dictionary = Hulls.temper(client.enemy_temper)
			temper = "%s: %s" % [t["name"], t["about"]]
		_enemy_line.text = "Щит пиратов: %s. Их орудия: %s. Повадки: %s." % [("%d из 100%s" % [client.enemy_shield,
			", пропускает" if client.enemy_shield < Weapons.SHIELD_HOLDS else ""]) if has_shield else "нет генератора щита",
			", ".join(names) if not names.is_empty() else "нет", temper]
		_fill(_enemy_shield, client.enemy_shield / 100.0 if has_shield else 0.0)
		_enemy_shield.color = SHIELD if client.enemy_shield >= Weapons.SHIELD_HOLDS else WARN
	else:
		_status.text = "Целей нет. Орудия бьют по пиратскому кораблю, пока он не пристыковался."
		_enemy_line.text = ""
		_fill(_enemy_shield, 0.0)
	_target.text = ("Цель: %s (щёлкните по отсеку, чтобы навести орудия)" % _enemy_name()) if fighting else "Цель: нет"
	var unknown := client.enemy_rooms.count(Net.ROOM_UNKNOWN)
	_probe.disabled = not fighting or client.probes <= 0 or client.ecrew_probe > 0
	_probe.text = "Запустить зонд-сканер (в трюме: %d)%s" % [client.probes,
		(", не просканировано отсеков: %d" % unknown) if fighting and unknown > 0 else ""]
	_ransom.visible = fighting and client.ransom > 0
	if _ransom.visible:
		_ransom.text = "Принять выкуп: %d кр. и топливо (осталось %d с)" % [client.ransom, client.ransom_left]
	_update_power()
	_update_guns(fighting)
	var aimed := _aimed_room()
	for which: int in _aim_buttons.keys():
		var b: Button = _aim_buttons[which]
		var known := which == Net.AIM_ANY or client.enemy_rooms.find(which) >= 0
		b.disabled = not fighting or not known
		b.set_pressed_no_signal(fighting and (client.gun_aim == which or (which != Net.AIM_ANY and aimed >= 0 and aimed == client.enemy_rooms.find(which))))
		if which == Net.AIM_ANY:
			b.text = "Куда попадёт"
		elif fighting and known:
			b.text = "%s: %s" % [Net.ESYS_NAMES[which], _state(which)]
		elif fighting and which == Net.ESYS_SHIELDS and client.enemy_sys_full[which] == 0:
			b.text = "%s: нет" % Net.ESYS_NAMES[which]       # (no shield generator: known from the start)
		elif fighting:
			b.text = "%s: ?" % Net.ESYS_NAMES[which]
		else:
			b.text = Net.ESYS_NAMES[which]
	var lines := PackedStringArray()
	var about := _hover if _hover >= 0 else (client.gun_aim if fighting and client.gun_aim < Net.ESYS_COUNT else -1)
	if _hover_gun >= 0 and _hover_gun < client.gun_weapon.size() and client.gun_weapon[_hover_gun] != Weapons.NONE:
		var w: int = client.gun_weapon[_hover_gun]
		lines.append("%s. %s Энергия: %d." % [Weapons.name_of(w), Weapons.info(w)["about"], Weapons.power(w)])
	elif about >= 0:
		lines.append(SYSTEM_ABOUT[about])
	elif _hover_room >= 0 and _hover_room < client.enemy_rooms.size() and client.enemy_rooms[_hover_room] == Net.ROOM_UNKNOWN:
		lines.append("Неизвестный отсек: что в нём, покажут сканеры (по отсеку раз в несколько секунд), наше попадание или зонд. Стрелять сюда можно и вслепую.")
	elif _hover_room >= 0:
		lines.append("Пустой отсек: попадание сюда бьёт только по корпусу.")
	else:
		lines.append("Без наводки снаряд ложится в случайный отсек. Попадание отнимает урон у корпуса и у системы в отсеке и показывает, что в отсеке.")
	lines.append("Щит держит всё, пока он не ниже 50; ниже пропускает выстрелы тем чаще, чем он слабее, и сам восстанавливается (%s в секунду). Ракеты щит не держит, бластер наполовину. Выбитую систему пираты чинят, только когда кто-то из них стоит в её отсеке: единица за %d с. Попадание в отсек может ранить пиратов в нём: раненый уходит в кубрик и не чинит (их показывают зонд и дрон)." % [
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
	return EnemyPlan.state(client, which)


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

func _enemy_name() -> String:
	for id: int in client.ships.keys():
		if id != client.my_ship:
			return str(client.ships[id]["name"])
	return "пиратский корабль"


func _aimed_room() -> int:
	## The room of the plan our guns aim at, or -1.
	if client.gun_aim == Net.AIM_ANY:
		return -1
	if client.gun_aim >= Net.AIM_ROOM:
		return client.gun_aim - Net.AIM_ROOM
	return client.enemy_rooms.find(client.gun_aim)


func _layout() -> Array:
	return EnemyPlan.layout(client, PLAN)


func _room_at_local(o, local: int) -> int:
	return EnemyPlan.room_at_local(o, local)


func _draw_plan() -> void:
	EnemyPlan.draw(_plan, client, PLAN, _time, _hover_room, _aimed_room())
	if _fighting() and client.gun_aim == Net.AIM_ANY:
		_plan.draw_string(ThemeDB.fallback_font, Vector2(6, PLAN.y - 6), "Наводки нет: куда попадёт", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)


func _room_at(at: Vector2) -> int:
	return EnemyPlan.room_at(client, PLAN, at)


func _system_in(room: int) -> int:
	if room < 0 or room >= client.enemy_rooms.size() or client.enemy_rooms[room] >= Net.ESYS_COUNT:
		return -1
	return client.enemy_rooms[room]


func _on_plan_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_room = _room_at((event as InputEventMouseMotion).position)
		_hover = _system_in(_hover_room)
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and client.enemy_full > 0:
		var room := _room_at((event as InputEventMouseButton).position)
		var system := _system_in(room)
		client.send_aim(system if system >= 0 else (Net.AIM_ROOM + room if room >= 0 else Net.AIM_ANY))
		_plan.accept_event()
