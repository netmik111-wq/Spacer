extends Control
## (v92, the author's plan item 0) The fight in real time, seen from outside: the ships as they fly
## and turn (their drawings from above), their guns turning, shields, shots and beams. Shown at the
## ship's controls in a fight (the pilot steers: W/S, A/D, Q/E, Space), at a gun mount taken by hand
## (the mouse aims, the button fires) and, small, to anyone by V. Everything comes from
## GameClient.arena (ArenaSeen), drawn a little in the past as the others are.
## (v95, the author's note) Out of a fight too: the helm shows the system round the ship (its station, trader,
## places, streams and storms where they are, Arena.SCALE cells to a unit of the system's map), the ship alongside,
## and a small map of the whole system in the corner: a click there sets the autopilot's course.

const Net := preload("res://src/shared/net.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")
const FightFx := preload("res://src/client/fight_fx.gd")
const GameClient := preload("res://src/client/game_client.gd")
const ArenaSeen := preload("res://src/client/arena_seen.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const BridgeView := preload("res://src/ui/bridge_view.gd")   # (only for its colours)

const WATCH := 0
const PILOT := 1
const TURRET := 2
const ALL := 3                       # (v93) at the gun console: the mouse aims every gun nobody aims by hand

const RADIUS := 170.0                # as Arena.RADIUS: breaking off is this far from every pirate
const SCALE := 4.0                   # (v95) as Arena.SCALE
const MINI := 150.0                  # (v95) the small map's side, pixels
const ARC_HALF := PI * 0.4           # as Arena.ARC_HALF
const OURS := {ArenaShape.FLOOR: Color(0.2, 0.24, 0.27), ArenaShape.WALL: Color(0.5, 0.6, 0.62),
	ArenaShape.PANE: Color(0.45, 0.75, 0.95), ArenaShape.GUN: Color(0.95, 0.82, 0.4)}
const THEIRS := {ArenaShape.FLOOR: Color(0.25, 0.19, 0.19), ArenaShape.WALL: Color(0.66, 0.42, 0.38),
	ArenaShape.PANE: Color(0.85, 0.6, 0.5), ArenaShape.GUN: Color(1.0, 0.55, 0.3)}
const HOW_COLOUR := {Net.LANDED: Color(1.0, 0.6, 0.25), Net.MISSED: Color(0.7, 0.7, 0.7), Net.RICOCHET: Color(0.9, 0.9, 1.0),
	Net.SHOT_DOWN: Color(1.0, 0.95, 0.6), 0: FightFx.SHIELD, Net.HELD: Color(0.75, 0.8, 0.85)}
# (v93, my A4 pick) a word by a shot's end on a hull: went through, the armour held, glanced off
const HOW_WORD := {Net.LANDED: "пробил", Net.HELD: "броня", Net.RICOCHET: "рикошет"}
const DARK := {ArenaShape.FLOOR: Color(0.2, 0.2, 0.21), ArenaShape.WALL: Color(0.45, 0.45, 0.47),
	ArenaShape.PANE: Color(0.4, 0.5, 0.55), ArenaShape.GUN: Color(0.55, 0.5, 0.45)}   # (v95) a ship alongside that is not a foe
const WORN_COLOUR := Color(1.0, 0.85, 0.3)        # armour half gone
const BARE_COLOUR := Color(0.95, 0.25, 0.2)       # no armour left

var client: GameClient
var mode := WATCH
var gun := -1                        # (TURRET) the number of our gun at the mount we stand at
var zoom := 2.5                      # pixels a cell
var firing := false                  # (TURRET) the mouse button held
var shield_up := true                # (v94, PILOT) the right mouse button raises and lowers the shield
var shield_touched := false          # the pilot has used it this fight (else bots hold the shield)
var vent_asked := false              # V pressed: sent once
var _mouse := Vector2.ZERO
var _stars := PackedVector3Array()
var _alongside: RefCounted           # (v95) the ArenaShape of the ship alongside, built once per kind
var _alongside_kind := -1


func setup(p_client: GameClient) -> void:
	client = p_client
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	for i in 160:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.15, 0.6)))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func t_now() -> float:
	return client.render_tick()


func mine() -> int:
	## The body of the ship of ours we are aboard.
	return client.my_fleet


func centre() -> Vector2:
	var s: Dictionary = client.arena.state(mine(), t_now())
	return s["pos"] if not s.is_empty() else Vector2.ZERO


func to_screen(at: Vector2) -> Vector2:
	return (at - centre()) * zoom + size / 2.0


func to_space(at: Vector2) -> Vector2:
	return (at - size / 2.0) / zoom + centre()


func aim_point() -> Vector2:
	## (TURRET) The point of the fight's space under the mouse.
	return to_space(_mouse)


func mini_rect() -> Rect2:
	## (v95) The small map of the whole system, at the top right (the pilot's view only).
	return Rect2(Vector2(size.x - MINI - 10.0, 10.0), Vector2(MINI, MINI))


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		_mouse = b.position
		if b.button_index == MOUSE_BUTTON_LEFT and mode == PILOT and mini_rect().has_point(b.position):
			# (v95, my F2 pick) a click on the small map: the autopilot's course
			firing = false
			if b.pressed:
				var r := mini_rect()
				client.send_helm(true, (b.position - r.position) / r.size * Sectors.SPAN)
		elif b.button_index == MOUSE_BUTTON_LEFT:
			firing = b.pressed and mode != WATCH     # (v93, the author's P1 note) the pilot fires the free guns too
		elif b.pressed and b.button_index == MOUSE_BUTTON_RIGHT and mode == PILOT:
			shield_up = not shield_up if shield_touched else false   # (v94) Starsector's: the pilot raises the shield
			shield_touched = true
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom * 1.2, 14.0)
		elif b.pressed and b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom / 1.2, 0.6 if mode != TURRET else 1.5)
		accept_event()


func _draw() -> void:
	var t := t_now()
	var now := Time.get_ticks_msec()
	client.arena.forget(now, t)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.05))
	var c := centre()
	for s: Vector3 in _stars:
		var p := Vector2(posmod(s.x * size.x - c.x * zoom * s.z, size.x), posmod(s.y * size.y - c.y * zoom * s.z, size.y))
		draw_rect(Rect2(p, Vector2(1.5, 1.5)), Color(0.8, 0.85, 1.0, s.z))
	if client.arena.bodies.is_empty():
		# (v94) the gun console out of a fight: space stays on its screen, empty
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y / 2.0), "Целей нет. Когда придёт враг, бой будет здесь.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(0.6, 0.68, 0.72))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.5, 0.6, 0.8), false, 1.0)
		return
	_draw_system()
	_draw_alongside(t)
	for id: int in client.arena.bodies.keys():
		_draw_ship(id, t)
	for b: Dictionary in client.arena.beams:
		var col: Color = FightFx.COLOURS.get(int(b["kind"]), Color.WHITE)
		draw_line(to_screen(b["from"]), to_screen(b["to"]), Color(col, 0.35), 5.0)
		draw_line(to_screen(b["from"]), to_screen(b["to"]), col.lightened(0.4), 1.5)
	for s: Dictionary in client.arena.shots.values():
		var at: Vector2 = client.arena.shot_at(s, t)
		var col: Color = FightFx.COLOURS.get(int(s["kind"]), Color.WHITE)
		var dir := (s["vel"] as Vector2).normalized()
		draw_line(to_screen(at - dir * 1.6), to_screen(at), col, 2.0 if FightFx.rocket_like(int(s["kind"])) else 1.5)
		draw_circle(to_screen(at), 1.8, col.lightened(0.5))
	for b: Dictionary in client.arena.bursts:
		var k := float(now - int(b["born"])) / ArenaSeen.BURST_MS
		var col: Color = HOW_COLOUR.get(int(b["how"]), Color.WHITE)
		draw_arc(to_screen(b["at"]), (1.0 + 3.0 * k) * zoom * 0.6, 0.0, TAU, 20, Color(col, 1.0 - k), 2.0)
		if HOW_WORD.has(int(b["how"])) and zoom >= 2.5:
			draw_string(ThemeDB.fallback_font, to_screen(b["at"]) + Vector2(6, -6 - 10.0 * k), HOW_WORD[int(b["how"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 1.0 - k))
	_draw_marks(t)
	if mode != WATCH:
		_draw_sight(t)
	_draw_words(t)
	_draw_hud(t)
	if mode == PILOT or mode == WATCH and size.x >= 500.0:
		_draw_mini()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.5, 0.6, 0.8), false, 1.0)


func _draw_system() -> void:
	## (v95) The system round the ship: its edge, its main thing (station, trader, derelict, meteor stream, ion storm)
	## and the places the sensors found, where they are (Arena.SCALE cells to a unit), with the rings that count.
	var sectors = client.sectors
	var here: int = client.sector
	if sectors == null or here < 0 or here >= sectors.count:
		return
	var font := ThemeDB.fallback_font
	var side := Sectors.SPAN * SCALE
	draw_rect(Rect2(to_screen(Vector2.ZERO), Vector2(side, side) * zoom), Color(0.3, 0.75, 0.45, 0.35), false, 2.0)
	var spot: Vector2 = sectors.spot[here] * SCALE
	var reach: float = float(sectors.reach[here]) * SCALE
	match int(sectors.kind[here]):
		Sectors.METEORS:
			draw_circle(to_screen(spot), reach * zoom, Color(1.0, 0.55, 0.2, 0.08))
			draw_arc(to_screen(spot), reach * zoom, 0.0, TAU, 96, Color(1.0, 0.6, 0.25, 0.6), 1.5)
			_label(spot + Vector2(0.0, -reach), "метеорный поток", Color(1.0, 0.75, 0.5))
		Sectors.ION_STORM:
			draw_circle(to_screen(spot), reach * zoom, Color(BridgeView.ION, 0.08))
			draw_arc(to_screen(spot), reach * zoom, 0.0, TAU, 96, Color(BridgeView.ION, 0.6), 1.5)
			_label(spot + Vector2(0.0, -reach), "ионный шторм", BridgeView.ION.lightened(0.3))
		Sectors.STATION, Sectors.TRADER:
			var station := int(sectors.kind[here]) == Sectors.STATION
			var colour := Color(0.3, 0.85, 0.8) if station else Color(0.95, 0.85, 0.35)
			draw_arc(to_screen(spot), reach * zoom, 0.0, TAU, 64, Color(colour, 0.6), 1.5)
			var w := 14.0 if station else 10.0
			draw_rect(Rect2(to_screen(spot) - Vector2(w, w) * zoom / 2.0, Vector2(w, w) * zoom), Color(colour, 0.85))
			_label(spot + Vector2(0.0, reach + 6.0), "станция снабжения" if station else
				("торговец: " + Sectors.DEAL_NAMES[sectors.deal[here]] if sectors.deal.size() > here else "торговец"), colour)
		Sectors.DERELICT:
			if not client.other_here():
				var grey := Color(0.7, 0.7, 0.72)
				draw_arc(to_screen(spot), reach * zoom, 0.0, TAU, 64, Color(grey, 0.6), 1.5)
				draw_rect(Rect2(to_screen(spot) - Vector2(8, 4) * zoom, Vector2(16, 8) * zoom), grey, false, 1.5)
				_label(spot + Vector2(0.0, reach + 6.0), "брошенный корабль", grey)
	for pl: Array in client.road.get("places", []):
		var kind: int = pl[0]
		var at: Vector2 = (pl[1] as Vector2) * SCALE
		var gone: bool = pl[2] and kind != Sectors.P_WRECK
		var colour: Color = BridgeView.PLACE_COLOURS[kind] if not gone else Color(0.4, 0.45, 0.43)
		var ring := float(Sectors.PLACE_REACH)
		match kind:
			Sectors.P_AMBUSH:
				ring = Sectors.AMBUSH_REACH
				draw_circle(to_screen(at), ring * SCALE * zoom, Color(BridgeView.HUNTER, 0.06 if not gone else 0.02))
			Sectors.P_WRECK, Sectors.P_HULK:
				ring = Sectors.WRECK_REACH
			Sectors.P_ANOMALY, Sectors.P_ASTEROID, Sectors.P_GAS:
				ring = Sectors.WORK_REACH
		draw_arc(to_screen(at), ring * SCALE * zoom, 0.0, TAU, 48, Color(colour, 0.5), 1.0)
		draw_circle(to_screen(at), maxf(2.0 * zoom, 3.0), colour)
		_label(at + Vector2(0.0, ring * SCALE + 4.0), Sectors.PLACE_NAMES[kind] + (" (пусто)" if gone else ""), colour)
	if client.arena.course:
		var me := centre()
		var goal: Vector2 = client.ship_dest * SCALE
		draw_dashed_line(to_screen(me), to_screen(goal), Color(1, 1, 1, 0.45), 1.0, 6.0)
		var g := to_screen(goal)
		draw_line(g + Vector2(-6, -6), g + Vector2(6, 6), Color.WHITE, 1.5)
		draw_line(g + Vector2(-6, 6), g + Vector2(6, -6), Color.WHITE, 1.5)


func _label(at: Vector2, text: String, colour: Color) -> void:
	if zoom < 0.9 and text.length() > 12:
		return
	draw_string(ThemeDB.fallback_font, to_screen(at) + Vector2(-80, 12), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, colour)


func _draw_alongside(t: float) -> void:
	## (v95, my F5 pick) The ship alongside our airlock (a derelict, a wreck, an asteroid, a pirate not yet in the
	## fight's space), drawn where its drawing lies beside ours in the grid, as the server glues a docked pirate.
	if not client.other_here() or client.arena.bodies.has(2):
		return
	var map = client.map
	if map.other_kind < 0 or map.other_kind >= map.others.size():
		return
	var mine: int = map.fleet_near(map.other_at.y * map.width) if map.has_method("fleet_near") else 0
	mine = clampi(mine, 0, 1)
	var s: Dictionary = client.arena.state(mine, t)
	var ours: RefCounted = client.arena.shape_of(mine)
	if s.is_empty() or ours == null:
		return
	if _alongside_kind != map.other_kind:
		_alongside_kind = map.other_kind
		_alongside = ArenaShape.of_layout(map.others[map.other_kind])
	var them: RefCounted = _alongside
	var centre_at := Vector2(map.other_at.x + them.x0 + them.w / 2.0, map.local_y(map.other_at.y) + them.r0 + them.h / 2.0)
	var mid := Vector2(ours.x0 + ours.w / 2.0, ours.r0 + ours.h / 2.0)
	var rot: float = s["rot"]
	var pos: Vector2 = (s["pos"] as Vector2) + (centre_at - mid).rotated(rot)
	var colours: Dictionary = THEIRS if client.pirates_alongside() else DARK
	draw_set_transform(to_screen(pos), rot, Vector2(zoom, zoom))
	for y in them.h:
		for x in them.w:
			var k: int = them.kind[y * them.w + x]
			if k != ArenaShape.EMPTY:
				draw_rect(Rect2(them.middle(x, y) - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), colours.get(k, Color(0.4, 0.4, 0.4)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_mini() -> void:
	## (v95) The whole system small, at the top right: its edge, its main thing, the places, our ship; a click
	## (the pilot's) sets the autopilot's course.
	var sectors = client.sectors
	var here: int = client.sector
	if sectors == null or here < 0 or here >= sectors.count:
		return
	var r := mini_rect()
	var k := r.size.x / Sectors.SPAN
	draw_rect(r, Color(0.03, 0.07, 0.07, 0.85))
	draw_rect(r, Color(0.3, 0.75, 0.45, 0.7), false, 1.0)
	var spot: Vector2 = r.position + sectors.spot[here] * k
	var reach: float = float(sectors.reach[here]) * k
	match int(sectors.kind[here]):
		Sectors.METEORS:
			draw_arc(spot, reach, 0.0, TAU, 32, Color(1.0, 0.6, 0.25, 0.8), 1.0)
		Sectors.ION_STORM:
			draw_arc(spot, reach, 0.0, TAU, 32, Color(BridgeView.ION, 0.8), 1.0)
		Sectors.STATION:
			draw_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), Color(0.3, 0.85, 0.8))
		Sectors.TRADER:
			draw_rect(Rect2(spot - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.85, 0.35))
		Sectors.DERELICT:
			draw_rect(Rect2(spot - Vector2(3, 2), Vector2(6, 4)), Color(0.7, 0.7, 0.72), false, 1.0)
	for pl: Array in client.road.get("places", []):
		var kind: int = pl[0]
		var gone: bool = pl[2] and kind != Sectors.P_WRECK
		draw_circle(r.position + (pl[1] as Vector2) * k, 2.0, BridgeView.PLACE_COLOURS[kind] if not gone else Color(0.4, 0.45, 0.43))
	var view := Rect2(r.position + to_space(Vector2.ZERO) / SCALE * k, size / zoom / SCALE * k).intersection(r)
	if view.size.x > 0.0:
		draw_rect(view, Color(1, 1, 1, 0.25), false, 1.0)
	var me := r.position + client.ship_pos() * k
	if client.arena.course:
		var goal := r.position + client.ship_dest * k
		draw_line(me, goal, Color(1, 1, 1, 0.5), 1.0)
		draw_line(goal + Vector2(-3, -3), goal + Vector2(3, 3), Color.WHITE, 1.0)
		draw_line(goal + Vector2(-3, 3), goal + Vector2(3, -3), Color.WHITE, 1.0)
	var s: Dictionary = client.arena.state(0, t_now())
	var rot: float = s.get("rot", 0.0) if not s.is_empty() else 0.0
	draw_colored_polygon(PackedVector2Array([me + Vector2(5, 0).rotated(rot), me + Vector2(-3, 3).rotated(rot), me + Vector2(-3, -3).rotated(rot)]),
		BridgeView.OURS.lightened(0.3))
	for id: int in client.arena.bodies.keys():
		if id >= 2:
			var o: Dictionary = client.arena.state(id, t_now())
			if not o.is_empty():
				draw_circle(r.position + (o["pos"] as Vector2) / SCALE * k, 2.5, Color(1.0, 0.45, 0.35))
	if mode == PILOT:
		draw_string(ThemeDB.fallback_font, r.position + Vector2(0, r.size.y + 13), "щелчок — автопилот", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11,
			Color(0.6, 0.75, 0.7))


func _draw_ship(id: int, t: float) -> void:
	var s: Dictionary = client.arena.state(id, t)
	var shape: RefCounted = client.arena.shape_of(id)
	if s.is_empty() or shape == null:
		return
	var ours := id < 2
	var colours: Dictionary = OURS if ours else THEIRS
	var pos: Vector2 = s["pos"]
	var rot: float = s["rot"]
	if int(s["flags"]) & Net.ARENA_THRUST:
		var back := Vector2(-shape.w / 2.0 - 1.5, 0.0)
		draw_circle(to_screen(pos + back.rotated(rot)), 0.9 * zoom, Color(0.5, 0.75, 1.0, 0.45))
	draw_set_transform(to_screen(pos), rot, Vector2(zoom, zoom))
	var worn: Dictionary = client.arena.armour.get(id, {})
	for y in shape.h:
		for x in shape.w:
			var k: int = shape.kind[y * shape.w + x]
			if k != ArenaShape.EMPTY:
				var col: Color = colours[k]
				if worn.has(y * shape.w + x):
					# (v93) the outer wall coloured by its armour: yellow as it wears, red with none left
					var a: Vector2i = worn[y * shape.w + x]
					var left := float(a.x) / maxf(float(a.y), 1.0)
					col = BARE_COLOUR if a.x <= 0 else WORN_COLOUR.lerp(col, left)
				draw_rect(Rect2(shape.middle(x, y) - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var aims: PackedFloat32Array = s["aims"]
	var gunf: PackedByteArray = s["gunf"]
	for k in aims.size():
		var at: Vector2 = pos + client.arena.gun_spot(id, k).rotated(rot)
		var lit := k < gunf.size() and gunf[k] & 1
		var col := Color(1.0, 0.9, 0.5) if lit else Color(0.7, 0.7, 0.7)
		if ours and id == mine() and k == gun and mode == TURRET:
			col = Color(0.5, 1.0, 0.6)
		var kind: int = client.arena.gun_kind(id, k)
		if ours and id == mine() and mode != WATCH and zoom >= 2.0:
			# (v94) each gun's arc: a narrow wedge for a fixed one, half a circle at the side, a whole ring on the roof
			var out := rot + client.arena.gun_out(id, k)
			var arc: float = ArenaShape.MOUNT_ARC[kind]
			var reach := 9.0 * zoom
			if kind == ArenaShape.MOUNT_ROOF:
				draw_arc(to_screen(at), reach * 0.6, 0.0, TAU, 32, Color(0.45, 0.7, 1.0, 0.18), 1.0)
			else:
				draw_arc(to_screen(at), reach, out - arc, out + arc, 24, Color(col, 0.22), 1.0)
				draw_line(to_screen(at), to_screen(at) + Vector2.from_angle(out - arc) * reach, Color(col, 0.16), 1.0)
				draw_line(to_screen(at), to_screen(at) + Vector2.from_angle(out + arc) * reach, Color(col, 0.16), 1.0)
		var long := 3.2 if kind == ArenaShape.MOUNT_HARD else 2.2
		draw_line(to_screen(at), to_screen(at + Vector2.from_angle(rot + aims[k]) * long), col, maxf(zoom * (0.45 if kind == ArenaShape.MOUNT_HARD else 0.35), 1.5))
		if kind == ArenaShape.MOUNT_ROOF:
			draw_circle(to_screen(at), maxf(zoom * 0.45, 2.0), Color(col, 0.8))
	var shield: int = s["shield"]
	if shield > 0:
		var r: Vector2 = shape.bubble()
		var pts := PackedVector2Array()
		var arc := (int(s["flags"]) >> Net.ARENA_ARC_SHIFT) & 7      # (v93) 0 a bubble, 1..4 an arc to one side
		var from := 0.0 if arc == 0 else float(s.get("sdir", (arc - 1) * PI / 2.0)) - ARC_HALF      # (v94) the pilot turns it
		var span := TAU if arc == 0 else ARC_HALF * 2.0
		for k in 41:
			var a := from + span * k / 40.0
			pts.append(to_screen(pos + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot)))
		var full := clampf(shield / 100.0, 0.0, 1.0)          # (Weapons.SHIELD_FULL) what its heat leaves it
		var tint: Color = FightFx.SHIELD.lerp(Color(1.0, 0.55, 0.3), 1.0 - full)
		draw_polyline(pts, Color(tint, 0.35 + 0.45 * full), (1.5 + 1.5 * full) * (1.0 if arc == 0 else 1.8))
	elif int(s.get("sstate", 0)) & Net.ARENA_OVERLOAD:
		# (v94) overloaded: sparks round the hull, blinking
		if (Time.get_ticks_msec() / 150) % 2 == 0:
			var r2: Vector2 = shape.bubble()
			for k in 10:
				var a := TAU * k / 10.0 + t * 0.3
				draw_circle(to_screen(pos + Vector2(cos(a) * r2.x, sin(a) * r2.y).rotated(rot)), 1.6, Color(1.0, 0.75, 0.35, 0.9))


func _draw_marks(t: float) -> void:
	## Ships off the screen: a mark at its edge, pointing to them.
	var rect := Rect2(Vector2(14, 14), size - Vector2(28, 28))
	for id: int in client.arena.bodies.keys():
		var s: Dictionary = client.arena.state(id, t)
		if s.is_empty():
			continue
		var p := to_screen(s["pos"])
		if rect.has_point(p):
			continue
		var dir := (p - size / 2.0).normalized()
		var edge := size / 2.0 + dir * minf(absf((size.x / 2.0 - 16.0) / maxf(absf(dir.x), 0.001)), absf((size.y / 2.0 - 16.0) / maxf(absf(dir.y), 0.001)))
		var col := Color(0.5, 0.9, 0.6) if id < 2 else Color(1.0, 0.45, 0.35)
		draw_colored_polygon(PackedVector2Array([edge + dir * 10.0, edge + dir.orthogonal() * 6.0, edge - dir.orthogonal() * 6.0]), col)
		var far: float = ((s["pos"] as Vector2) - centre()).length()
		draw_string(ThemeDB.fallback_font, edge - dir * 22.0 - Vector2(10, -4), "%d" % roundi(far), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_sight(t: float) -> void:
	## (TURRET) The arc our gun turns through, and the mark under the mouse.
	var s: Dictionary = client.arena.state(mine(), t)
	if s.is_empty():
		return
	if gun < 0:
		# (v93) the pilot or the gun console: the mark alone (every free gun turns to it as far as its arc lets it)
		var c := Color(1.0, 0.9, 0.4) if firing else Color(0.6, 1.0, 0.7, 0.8)
		draw_arc(_mouse, 7.0, 0.0, TAU, 20, c, 1.5)
		draw_line(_mouse - Vector2(12, 0), _mouse - Vector2(4, 0), c, 1.5)
		draw_line(_mouse + Vector2(4, 0), _mouse + Vector2(12, 0), c, 1.5)
		draw_line(_mouse - Vector2(0, 12), _mouse - Vector2(0, 4), c, 1.5)
		draw_line(_mouse + Vector2(0, 4), _mouse + Vector2(0, 12), c, 1.5)
		return
	var rot: float = s["rot"]
	var at: Vector2 = to_screen((s["pos"] as Vector2) + client.arena.gun_spot(mine(), gun).rotated(rot))
	var out: float = rot + client.arena.gun_out(mine(), gun)
	var arc: float = ArenaShape.MOUNT_ARC[client.arena.gun_kind(mine(), gun)]      # (v94) its own mount's arc
	draw_arc(at, 120.0, out - arc, out + arc, 32, Color(0.5, 1.0, 0.6, 0.25), 1.0)
	draw_line(at, at + Vector2.from_angle(out - arc) * 40.0, Color(0.5, 1.0, 0.6, 0.35), 1.0)
	draw_line(at, at + Vector2.from_angle(out + arc) * 40.0, Color(0.5, 1.0, 0.6, 0.35), 1.0)
	var rel := wrapf((_mouse - at).angle() - out, -PI, PI)
	var col := Color(1.0, 0.4, 0.3) if absf(rel) > arc else (Color(1.0, 0.9, 0.4) if firing else Color(0.6, 1.0, 0.7))
	draw_arc(_mouse, 9.0, 0.0, TAU, 20, col, 1.5)
	draw_line(_mouse - Vector2(14, 0), _mouse - Vector2(5, 0), col, 1.5)
	draw_line(_mouse + Vector2(5, 0), _mouse + Vector2(14, 0), col, 1.5)
	draw_line(_mouse - Vector2(0, 14), _mouse - Vector2(0, 5), col, 1.5)
	draw_line(_mouse + Vector2(0, 5), _mouse + Vector2(0, 14), col, 1.5)


func _draw_words(t: float) -> void:
	var font := ThemeDB.fallback_font
	var s: Dictionary = client.arena.state(mine(), t)
	var lines: Array[String] = []
	if not s.is_empty():
		var speed: float = (s["vel"] as Vector2).length()
		lines.append("Скорость: %.1f" % speed)
	if mode == PILOT and not client.arena.fight:
		lines.append("W/S — ход, A/D — поворот, Q/E — вбок, колесо — масштаб, Esc — отойти")
		lines.append("Щелчок по карте в углу — автопилот туда; мышь и левая кнопка — проба орудий")
	elif mode == PILOT:
		lines.append("W/S — ход, A/D — поворот, Q/E — вбок, Пробел — уклонение, Esc — отойти")
		lines.append("Мышь — прицел, левая — огонь орудиями без стрелка, правая — щит, V — сброс нагрева")
	elif mode == ALL and not client.arena.fight:
		lines.append("Целей нет. Мышь и левая кнопка — проба орудий без своего стрелка")
	elif mode == ALL:
		lines.append("Мышь — прицел, левая кнопка — огонь орудиями без своего стрелка")
	elif mode == TURRET:
		lines.append("Мышь — прицел, левая кнопка — огонь, колесо — масштаб, E или Esc — отойти")
	var y := 18.0
	for line in lines:
		draw_string(font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 0.8))
		y += 17.0



const HUD_HULL := Color(0.45, 0.85, 0.55)
const HUD_HEAT := Color(1.0, 0.62, 0.3)
const HUD_HARD := Color(0.85, 0.35, 0.2)
const HUD_INK := Color(0.82, 0.88, 0.9)
const HUD_DIM := Color(0.5, 0.56, 0.6)


func _bar(at: Vector2, width: float, share: float, col: Color, under := -1.0, under_col := Color.BLACK) -> void:
	draw_rect(Rect2(at, Vector2(width, 7)), Color(0.12, 0.15, 0.18, 0.9))
	draw_rect(Rect2(at, Vector2(width * clampf(share, 0.0, 1.0), 7)), col)
	if under >= 0.0:
		draw_rect(Rect2(at, Vector2(width * clampf(under, 0.0, 1.0), 7)), under_col)
	draw_rect(Rect2(at, Vector2(width, 7)), Color(0.4, 0.5, 0.55, 0.6), false, 1.0)


func _ship_bars(s: Dictionary, at: Vector2, width: float, name: String) -> void:
	## Hull points, heat (the shield's part darker), the shield's state: as Starsector's ship panel.
	var font := ThemeDB.fallback_font
	var hp: Vector2 = s.get("hp", Vector2.ZERO)
	var heat: Vector2 = s.get("heat", Vector2.ZERO)
	var state: int = s.get("sstate", 0)
	draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, width, 12, HUD_INK)
	draw_string(font, at + Vector2(0, 14), "Корпус %d / %d" % [roundi(hp.x), roundi(hp.y)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HUD_DIM)
	_bar(at + Vector2(0, 18), width, hp.x / maxf(hp.y, 1.0), HUD_HULL)
	var heat_share := heat.x / maxf(heat.y, 1.0)
	var word := "перегрузка!" if state & Net.ARENA_OVERLOAD else ("сброс нагрева" if state & Net.ARENA_VENT else
		("щит поднят" if state & Net.ARENA_RAISED else "щит опущен"))
	var hot := Color(1.0, 0.4, 0.3) if state & (Net.ARENA_OVERLOAD | Net.ARENA_VENT) else HUD_DIM
	draw_string(font, at + Vector2(0, 40), "Нагрев %d%%  ·  %s" % [roundi(heat_share * 100.0), word], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, hot)
	_bar(at + Vector2(0, 44), width, heat_share, HUD_HEAT, float(s.get("hard", 0.0)) * heat.y / maxf(heat.y, 1.0), HUD_HARD)


func _draw_hud(t: float) -> void:
	## (v94, my U1 pick: Starsector's panels) Ours at the bottom left with our guns' charge; the target's at the bottom right.
	if size.y < 200:
		return
	var font := ThemeDB.fallback_font
	var s: Dictionary = client.arena.state(mine(), t)
	if not s.is_empty():
		var w := 170.0
		var at := Vector2(10, size.y - 64)
		var charge: PackedFloat32Array = s.get("charge", PackedFloat32Array())
		var gunf: PackedByteArray = s.get("gunf", PackedByteArray())
		# the guns above the bars, one short row each
		var rows := charge.size()
		var y := at.y - 14.0 * rows - 6.0
		for k in rows:
			var kind: int = client.arena.gun_kind(mine(), k)
			var ready := charge[k] >= 0.999
			var name := "%d %s" % [k + 1, ArenaShape.MOUNT_NAMES[kind]]
			draw_string(font, Vector2(10, y + 9), name, HORIZONTAL_ALIGNMENT_LEFT, 90, 10,
				HUD_INK if k < gunf.size() and gunf[k] & 1 else HUD_DIM)
			_bar(Vector2(102, y + 2), 78, charge[k], Color(1.0, 0.9, 0.45) if ready else Color(0.55, 0.65, 0.7))
			y += 14.0
		_ship_bars(s, at, w, "Наш корабль")
	# the nearest pirate
	var best := -1
	var best_d := INF
	var me: Vector2 = s.get("pos", Vector2.ZERO) if not s.is_empty() else Vector2.ZERO
	for id: int in client.arena.bodies.keys():
		if id < 2:
			continue
		var o: Dictionary = client.arena.state(id, t)
		if not o.is_empty() and (o["pos"] as Vector2).distance_to(me) < best_d:
			best_d = (o["pos"] as Vector2).distance_to(me)
			best = id
	if best >= 0:
		var o: Dictionary = client.arena.state(best, t)
		_ship_bars(o, Vector2(size.x - 180, size.y - 64), 170.0, "Цель: %d клеток" % roundi(best_d))
