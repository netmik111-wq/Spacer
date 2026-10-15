extends VBoxContainer
## The drone monitor's screen (v54): the plan of the pirate ship we fight (as
## the gun console shows it, EnemyPlan) with our scouting drone on it and the
## pirates it sees. While the screen is open the walking keys steer the drone,
## not our character (the server moves it, Drone). A button sends a drone from
## the cargo; another blows it up where it is. Shown inside the console frame
## of GameScreen while our character stands at the drone monitor.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const EnemyPlan := preload("res://src/ui/enemy_plan.gd")
const Options := preload("res://src/client/options.gd")
const Drone := preload("res://src/server/drone.gd")         # only for its numbers, to explain them

const PLAN := Vector2(620, 260)
const MOVES := [["move_up", Net.DIR_UP], ["move_down", Net.DIR_DOWN], ["move_left", Net.DIR_LEFT], ["move_right", Net.DIR_RIGHT]]
const INK := Color(0.86, 0.9, 0.95)

var client: GameClient
var _status: Label
var _plan: Control
var _launch: Button
var _blow: Button
var _about: Label
var _held: Array = []                # the walking keys held, the last pressed last
var _sent := Net.DIR_NONE            # the direction last sent
var _time := 0.0


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(PLAN.x, 0)
	add_child(_status)
	_plan = Control.new()
	_plan.custom_minimum_size = PLAN
	_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan.draw.connect(func() -> void:
		EnemyPlan.draw(_plan, client, PLAN, _time, -1, -1, _drone_room()))
	add_child(_plan)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_launch = Button.new()
	_launch.focus_mode = Control.FOCUS_NONE
	_launch.pressed.connect(func() -> void: client.send_drone(Net.DRONE_LAUNCH))
	row.add_child(_launch)
	_blow = Button.new()
	_blow.focus_mode = Control.FOCUS_NONE
	_blow.text = "Взорвать дрон здесь"
	_blow.pressed.connect(func() -> void: client.send_drone(Net.DRONE_BLOW))
	row.add_child(_blow)
	_about = Label.new()
	_about.add_theme_font_size_override("font_size", 13)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(PLAN.x, 0)
	_about.modulate = Color(0.75, 0.8, 0.88)
	add_child(_about)


func opened() -> void:
	_held.clear()
	_sent = Net.DIR_NONE


func closed() -> void:
	## Our character steps away: the drone stops where it is.
	if _sent != Net.DIR_NONE:
		client.send_drone(Net.DRONE_STEER, Net.DIR_NONE)
	_sent = Net.DIR_NONE
	_held.clear()


func _drone_room() -> int:
	var o = client.map.other if client.pirates_alongside() else null
	if o == null or client.drone_state != Net.DRONE_INSIDE:
		return -1
	return EnemyPlan.room_at_local(o, client.drone_at)


func refresh(delta: float) -> void:
	## Called every frame while the screen is shown: steers by the walking keys.
	_time += delta
	for m: Array in MOVES:
		var down := Options.held(m[0])
		if down and not _held.has(m[1]):
			_held.append(m[1])
		elif not down and _held.has(m[1]):
			_held.erase(m[1])
	var want: int = Net.DIR_NONE if _held.is_empty() or client.drone_state != Net.DRONE_INSIDE else _held[-1]
	if want != _sent:
		_sent = want
		client.send_drone(Net.DRONE_STEER, want)
	var fighting := EnemyPlan.fighting(client)
	match client.drone_state:
		Net.DRONE_FLYING:
			_status.text = "Дрон летит к пиратскому кораблю: ещё %d с." % client.drone_coming
		Net.DRONE_INSIDE:
			var room := _drone_room()
			var where := "в проходе"
			if room >= 0 and room < client.enemy_rooms.size():
				var z: int = client.enemy_rooms[room]
				where = "в отсеке: " + ("пустой" if z >= Net.ESYS_COUNT else Net.ESYS_NAMES[z].to_lower())
			_status.text = "Дрон внутри, %s. Батарея: %d с. Рядом пиратов: %d." % [where, client.drone_battery, client.ecrew.size()]
		_:
			_status.text = ("Дрон не запущен. Цель: пиратский корабль у шлюза." if fighting
				else "Дрон не запущен. Рядом нет пиратского корабля: посылать его не к кому.")
	_launch.text = "Запустить дрон (в трюме: %d)" % client.drones
	_launch.disabled = client.drone_state != Net.DRONE_NONE or client.drones <= 0 or not fighting
	_blow.disabled = client.drone_state != Net.DRONE_INSIDE
	_about.text = Options.keyed(("Клавиши движения ведут дрон по кораблю пиратов, пока вы у монитора. Каждый отсек, куда он заглянет, становится известен " +
		"пульту орудий, а пиратов в его отсеке и рядом видно на плане (красные точки; с белым кольцом чинят, тусклые ранены). " +
		"Батарея держит %d с. Пираты в одном отсеке с дроном могут его заметить и сбить. Взрыв дрона наносит %d урона системе " +
		"в его отсеке (щит не мешает), 1 урона корпусу и может задеть пиратов рядом.") % [int(Drone.BATTERY_SECONDS), Drone.BLAST])
	_plan.queue_redraw()
