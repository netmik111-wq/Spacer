extends Control
## (v81) The ship editor's drawing area: the deck being drawn in the game's own pictures (walls pick
## their pieces as they are painted), the deck above faintly under it, the deck below through glass
## and catwalks, and every tool's hand work. The editor (ShipEditor) owns the drawing and the
## choices; this only draws it and turns the mouse into changes.
##
## Mouse: left draws with the tool, right rubs out, Alt + left takes the sign under it, the wheel
## zooms, the middle button (or Space held) moves the view.

signal picked(sign: String)          # the picker (or Alt + click) took a sign off the drawing
signal hovered(cell: Vector2i)       # the cell under the mouse changed (-1, -1: off the canvas)
signal mark_asked(cell: Vector2i)    # the room-mark tool was clicked on a cell
signal changed                       # something was drawn (a stroke ended)

const MapBuilder := preload("res://src/shared/map_builder.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Sprites := preload("res://src/client/sprites.gd")
const Drawing := preload("res://src/ui/editor/drawing.gd")

enum Tool { BRUSH, LINE, RECT, ROOM, FILL, ERASE, PICK, SELECT, MARK }

const T := 32
const SPACE := Color(0.035, 0.04, 0.07)
const GRID := Color(1, 1, 1, 0.07)
const MARK_COLOURS := {"bridge": Color(0.3, 0.6, 1.0), "engine": Color(1.0, 0.6, 0.2), "medbay": Color(0.3, 1.0, 0.6),
	"armory": Color(1.0, 0.3, 0.3), "guns": Color(0.9, 0.9, 0.3), "brig": Color(0.75, 0.45, 1.0)}
const SYSTEM_COLOUR := Color(1.0, 0.45, 0.35)

var drawing: Drawing
var deck := 0
var tool := Tool.BRUSH
var sign := "#"                      # what the tools draw with
var filled := false                  # the rectangle tool fills (else only its edge)
var grid := true
var show_objects := true             # (v82.1) false: only the floor layer is drawn (objects hidden)
var problems: Array = []             # from Checks: cells to frame in red
var zoom := 1.0
var view := Vector2(40, 40)          # where the canvas's corner is on the screen

var _tex: Texture2D
var _built := {}                     # MapBuilder's layout of the drawing as it was last drawn
var _built_at := -1                  # Drawing.changes then
var _standing := {}                  # (v91) cell of the built layout -> [the floor's tile under a machine standing there, its picture]
var _ids := {}
var _hover := Vector2i(-1, -1)
var _down := -1                      # the mouse button held (MOUSE_BUTTON_*), -1 = none
var _from := Vector2i.ZERO           # where a line, rectangle, room or selection began
var _last := Vector2i.ZERO           # the brush's last cell (strokes are joined with lines)
var _panning := false
var _pan_from := Vector2.ZERO
var _space := false
var selection := Rect2i()            # the selected cells (size 0: none)
var clip := {}                       # what was copied (Drawing.copy)
var floating := {}                   # a copy being laid (pasted or moved): it follows the mouse until a click
var _float_off := Vector2i.ZERO      # where the mouse holds the floating copy, from its corner
var _lifted := false                 # the floating copy was lifted off the drawing (a move), not pasted


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	reload_pictures()


func reload_pictures() -> void:
	## (v81, the author's E11) The tile sheet again, as it is now in the «sprites» folder.
	_tex = Sprites.sheet("tiles")
	_ids = MapBuilder.tile_ids()
	queue_redraw()


func cell_size() -> float:
	return T * zoom


func cell_at(screen: Vector2) -> Vector2i:
	var c := (screen - view) / cell_size()
	return Vector2i(floori(c.x), floori(c.y))


func centre_on(cell: Vector2i) -> void:
	view = size * 0.5 - (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size()
	queue_redraw()


func fit() -> void:
	## Zoom and place so the whole canvas shows.
	if drawing == null or size.x < 10:
		return
	var z := minf((size.x - 40) / (drawing.width * T), (size.y - 40) / (drawing.height * T))
	zoom = clampf(snappedf(z, 0.25) if z >= 0.5 else z, 0.25, 3.0)
	view = (size - Vector2(drawing.width, drawing.height) * cell_size()) * 0.5
	queue_redraw()


func _process(_delta: float) -> void:
	var key := drawing.changes * 2 + (1 if show_objects else 0) if drawing != null else -1
	if drawing != null and key != _built_at:
		_built_at = key
		_built = MapBuilder.build("ships:edit", drawing.to_text() if show_objects else drawing.base_text())["data"]
		_standing = _machines_standing()
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _tile_id(name: String) -> int:
	if drawing != null and drawing.kind == "pirate" and _ids.has("pirate_" + name):
		return int(_ids["pirate_" + name])
	return int(_ids.get(name, -1))


func _machines_standing() -> Dictionary:
	## (v91) The machines standing on the floor as the game draws them: turned the way they face, wide ones in pieces.
	var out := {}
	if _built.is_empty() or (_built.get("things", []) as Array).is_empty():
		return out
	var map := ShipMap.new()
	var ok := map.load_data("ships:edit", FileAccess.get_file_as_string("res://assets/tiles.json"), _built, false) == ""
	var names := {}
	for n: String in _ids.keys():
		names[int(_ids[n])] = n
	var w := int(_built["width"])
	for th: Array in _built["things"]:
		var c := int(th[1]) * w + int(th[0])
		var look := map.standing_look(c) if ok else str(names.get(int((_built["cells"] as Array)[c]), "")).trim_prefix("pirate_") + "_fl"
		out[c] = [int(th[2]), _tile_id(look)]
	return out


func tile_region(id: int) -> Rect2:
	return Rect2((id % 8) * T, (id / 8) * T, T, T)


func _cell_tile(d: int, x: int, y: int) -> int:
	## The tile drawn in that cell of deck d, as the game would draw it (doors shut).
	if _built.is_empty() or d >= (_built["decks"] as Array).size():
		return -1
	var w := int(_built["width"])
	if x >= w or y >= int(_built["deck_height"]):
		return -1
	var id := int((_built["cells"] as Array)[(d * int(_built["deck_stride"]) + y) * w + x])
	var s := drawing.at(d, Vector2i(x, y)) if show_objects else drawing.base_at(d, Vector2i(x, y))
	if s == "D" or s == "A":
		# (v91) in the kind its mark gives it, the plain one else
		var m := drawing.mark_at(d, Vector2i(x, y), "&")
		var look := "base" if m < 0 else str(drawing.marks[m]["what"])
		var door := _tile_id("door_%s_%s_green" % [look, "h" if s == "D" else "v"])
		return door if door >= 0 else _tile_id("door" if s == "D" else "airlock_closed")
	return id


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.022, 0.035))
	if drawing == null or _tex == null:
		return
	var cs := cell_size()
	var whole := Rect2(view, Vector2(drawing.width, drawing.height) * cs)
	draw_rect(whole, SPACE)
	var first := cell_at(Vector2.ZERO).max(Vector2i.ZERO)
	var last := cell_at(size).min(Vector2i(drawing.width - 1, drawing.height - 1))
	# the deck above, faintly (ladders and see-through floors must line up with it)
	if deck > 0:
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var id := _cell_tile(deck - 1, x, y)
				if id >= 0:
					draw_texture_rect_region(_tex, Rect2(view + Vector2(x, y) * cs, Vector2(cs, cs)), tile_region(id), Color(0.7, 0.8, 1.0, 0.22))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var id := _cell_tile(deck, x, y)
			if id < 0:
				continue
			var r := Rect2(view + Vector2(x, y) * cs, Vector2(cs, cs))
			var standing: Array = _standing.get((deck * int(_built["deck_stride"]) + y) * int(_built["width"]) + x, [])
			if not standing.is_empty():
				draw_texture_rect_region(_tex, r, tile_region(int(standing[0])))
				if int(standing[1]) >= 0:
					draw_texture_rect_region(_tex, r, tile_region(int(standing[1])))
				continue
			var kind := MapBuilder.tile_kind(id)
			if kind == "glass" or kind == "grate" or kind == "hatch":
				var under := _cell_tile(deck + 1, x, y)
				draw_rect(r, SPACE)
				if under >= 0:
					draw_texture_rect_region(_tex, r, tile_region(under), Color(0.55, 0.55, 0.6))
			draw_texture_rect_region(_tex, r, tile_region(id))
			if show_objects and drawing.at(deck, Vector2i(x, y)) == "s":
				draw_circle(r.get_center(), cs * 0.16, Color(0.4, 1.0, 0.5, 0.75))
	_draw_marks(cs)
	if grid and cs >= 12:
		for x in range(first.x, last.x + 2):
			var px := view.x + x * cs
			draw_line(Vector2(px, whole.position.y), Vector2(px, whole.end.y), GRID)
		for y in range(first.y, last.y + 2):
			var py := view.y + y * cs
			draw_line(Vector2(whole.position.x, py), Vector2(whole.end.x, py), GRID)
	draw_rect(whole, Color(1, 1, 1, 0.25), false, 1.0)
	if drawing.mirror_x:
		draw_line(Vector2(whole.get_center().x, whole.position.y), Vector2(whole.get_center().x, whole.end.y), Color(0.4, 0.8, 1.0, 0.5), 2.0)
	if drawing.mirror_y:
		draw_line(Vector2(whole.position.x, whole.get_center().y), Vector2(whole.end.x, whole.get_center().y), Color(0.4, 0.8, 1.0, 0.5), 2.0)
	for p: Dictionary in problems:
		if int(p["deck"]) == deck:
			var r := Rect2(view + Vector2(int(p["x"]), int(p["y"])) * cs, Vector2(cs, cs)).grow(-1)
			draw_rect(r, Color(1.0, 0.25, 0.2, 0.9) if p["error"] else Color(1.0, 0.8, 0.2, 0.9), false, 2.0)
	_draw_preview(cs)
	if selection.size != Vector2i.ZERO:
		var sr := Rect2(view + Vector2(selection.position) * cs, Vector2(selection.size) * cs)
		draw_rect(sr, Color(0.4, 0.8, 1.0, 0.12))
		draw_rect(sr, Color(0.4, 0.8, 1.0, 0.9), false, 2.0)
	if drawing.inside(_hover) and floating.is_empty():
		draw_rect(Rect2(view + Vector2(_hover) * cs, Vector2(cs, cs)), Color(1, 1, 1, 0.6), false, 1.0)


func _draw_marks(cs: float) -> void:
	var font := get_theme_default_font()
	for m: Dictionary in drawing.marks:
		if int(m["deck"]) != deck:
			continue
		var what := str(m["what"])
		if str(m["type"]) == "&":
			# (v91) a door's kind: a word on the door (its picture is drawn in that kind)
			var spot := view + (Vector2(int(m["x"]), int(m["y"])) + Vector2(0.05, 0.3)) * cs
			var word := MapBuilder._mark_name(what)
			draw_string_outline(font, spot, word, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(10 * zoom), 8), 3, Color(0, 0, 0, 0.8))
			draw_string(font, spot, word, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(10 * zoom), 8), Color(1.0, 0.85, 0.4))
			continue
		var col: Color = SYSTEM_COLOUR if str(m["type"]) == "%" else MARK_COLOURS.get(what, Color.WHITE)
		var cells := drawing.room_cells(deck, Vector2i(int(m["x"]), int(m["y"])))
		for c: Vector2i in cells:
			draw_rect(Rect2(view + Vector2(c) * cs, Vector2(cs, cs)), Color(col, 0.16))
		var at := view + (Vector2(int(m["x"]), int(m["y"])) + Vector2(0.1, 0.75)) * cs
		var label := MapBuilder._mark_name(what)
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(12 * zoom), 9), 3, Color(0, 0, 0, 0.8))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(12 * zoom), 9), col)


func _ghost(c: Vector2i, s: String, cs: float) -> void:
	## A sign about to be drawn there, half seen.
	if not drawing.inside(c):
		return
	var r := Rect2(view + Vector2(c) * cs, Vector2(cs, cs))
	var id := _tile_id(icon_tile(s))
	if s == " " or id < 0:
		draw_rect(r, Color(1, 0.3, 0.3, 0.3))
	else:
		draw_texture_rect_region(_tex, r, tile_region(id), Color(1, 1, 1, 0.6))
	draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)


func _draw_preview(cs: float) -> void:
	if not floating.is_empty():
		var corner := _hover - _float_off
		var cells: PackedStringArray = floating["cells"]
		for y in int(floating["h"]):
			for x in int(floating["w"]):
				var s := cells[y * int(floating["w"]) + x]
				if s != " ":
					_ghost(corner + Vector2i(x, y), s, cs)
		draw_rect(Rect2(view + Vector2(corner) * cs, Vector2(int(floating["w"]), int(floating["h"])) * cs), Color(0.4, 0.8, 1.0, 0.9), false, 2.0)
		return
	if _down < 0:
		if drawing.inside(_hover) and (tool == Tool.BRUSH or tool == Tool.LINE or tool == Tool.RECT):
			_ghost(_hover, sign, cs)
		return
	var s := _stroke_sign()
	match tool:
		Tool.LINE:
			for c in Drawing.line_cells(_from, _hover):
				_ghost(c, s, cs)
		Tool.RECT, Tool.ROOM:
			var r := Rect2i(_from, _hover - _from).abs()
			r.size += Vector2i.ONE
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
					if tool == Tool.ROOM:
						_ghost(Vector2i(x, y), "#" if edge else ".", cs)
					elif edge or filled or Input.is_key_pressed(KEY_SHIFT):
						_ghost(Vector2i(x, y), s, cs)
		Tool.SELECT:
			var r := Rect2i(_from, _hover - _from).abs()
			r.size += Vector2i.ONE
			draw_rect(Rect2(view + Vector2(r.position) * cs, Vector2(r.size) * cs), Color(0.4, 0.8, 1.0, 0.9), false, 2.0)


static func icon_tile(s: String) -> String:
	## The tile that stands for a sign in the palette and in previews.
	return {"#": "wall_h", ".": "floor_m_t", "s": "floor_m_t", "g": "glass_m_t", "c": "grate_m_t", "H": "ladder_m_t",
		"D": "door", "A": "airlock_closed", "W": "window", "<": "window_l", ">": "window_r",
		"1": "console_1", "2": "console_2", "3": "console_3", "4": "console_4", "5": "console_5", "6": "engine",
		"7": "air_plant", "8": "locker", "9": "lock_pump", "T": "gun", "I": "intercom", "M": "holo", "Z": "shield",
		"B": "bench", "U": "bay", "Y": "autodoc", "X": "scanner", "S": "smes", "Q": "smes_small", "K": "comms",
		"P": "tray", "C": "cryo", "G": "stove", "F": "window_field", "V": "dock", "E": "med_box", "J": "tech_box",
		"N": "fire_box", "L": "wall_light", "R": "rock_1", "O": "rock_ore", ",": "rock_ground"}.get(s, "")


# ---------------------------------------------------------------- the mouse

func _stroke_sign() -> String:
	return " " if _down == MOUSE_BUTTON_RIGHT or tool == Tool.ERASE else sign


func _gui_input(event: InputEvent) -> void:
	if drawing == null:
		return
	if event is InputEventMouseMotion:
		var e := event as InputEventMouseMotion
		if _panning:
			view += e.position - _pan_from
			_pan_from = e.position
			queue_redraw()
			return
		var c := cell_at(e.position)
		if c != _hover:
			_hover = c
			hovered.emit(c if drawing.inside(c) else Vector2i(-1, -1))
			if _down >= 0 and (tool == Tool.BRUSH or tool == Tool.ERASE):
				drawing.line(deck, _last, c, _stroke_sign())
				_last = c
			queue_redraw()
	elif event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
			accept_event()
			return
		if e.button_index == MOUSE_BUTTON_MIDDLE or (e.button_index == MOUSE_BUTTON_LEFT and _space):
			_panning = e.pressed
			_pan_from = e.position
			return
		if e.button_index != MOUSE_BUTTON_LEFT and e.button_index != MOUSE_BUTTON_RIGHT:
			return
		grab_focus()
		var c := cell_at(e.position)
		if e.pressed:
			_press(e.button_index, c, e.alt_pressed)
		elif _down == e.button_index:
			_release(c, e.shift_pressed)


func _zoom_at(at: Vector2, k: float) -> void:
	var before := (at - view) / cell_size()
	zoom = clampf(zoom * k, 0.25, 4.0)
	view = at - before * cell_size()
	queue_redraw()


func _press(button: int, c: Vector2i, alt: bool) -> void:
	if not floating.is_empty():
		if button == MOUSE_BUTTON_LEFT:
			drawing.paste(deck, c - _float_off, floating)
			drawing.commit()
			selection = Rect2i(c - _float_off, Vector2i(int(floating["w"]), int(floating["h"])))
			floating = {}
			_lifted = false
			changed.emit()
		else:
			cancel_float()
		queue_redraw()
		return
	if alt or tool == Tool.PICK:
		if drawing.inside(c):
			picked.emit(drawing.base_at(deck, c) if drawing.layer == Drawing.LAYER_FLOOR or not show_objects else drawing.at(deck, c))
		return
	if tool == Tool.MARK:
		if drawing.inside(c) and button == MOUSE_BUTTON_LEFT:
			mark_asked.emit(c)
		return
	if tool == Tool.SELECT and button == MOUSE_BUTTON_LEFT and selection.has_point(c):
		# a drag inside the selection moves it
		lift_selection(c)
		return
	_down = button
	_from = c
	_last = c
	match tool:
		Tool.BRUSH, Tool.ERASE:
			drawing.paint(deck, c, _stroke_sign())
		Tool.FILL:
			drawing.fill(deck, c, _stroke_sign())
			_down = -1
			drawing.commit()
			changed.emit()
		Tool.SELECT:
			selection = Rect2i()
	queue_redraw()


func _release(c: Vector2i, shift: bool) -> void:
	var s := _stroke_sign()
	var r := Rect2i(_from, c - _from).abs()
	r.size += Vector2i.ONE
	match tool:
		Tool.LINE:
			drawing.line(deck, _from, c, s)
		Tool.RECT:
			if s == " ":
				drawing.clear(deck, r)
			else:
				drawing.rect(deck, r, s, filled or shift)
		Tool.ROOM:
			if s == " ":
				drawing.clear(deck, r)
			else:
				drawing.room(deck, r)
		Tool.SELECT:
			selection = r.intersection(Rect2i(0, 0, drawing.width, drawing.height))
	_down = -1
	drawing.commit()
	changed.emit()
	queue_redraw()


func lift_selection(holding: Vector2i) -> void:
	## The selection comes up off the drawing and follows the mouse (moved, not copied).
	if selection.size == Vector2i.ZERO:
		return
	floating = drawing.copy(deck, selection)
	drawing.clear(deck, selection)
	_lifted = true
	_float_off = holding - selection.position
	selection = Rect2i()
	queue_redraw()


func start_paste() -> void:
	if clip.is_empty():
		return
	floating = clip.duplicate(true)
	_lifted = false
	_float_off = Vector2i(int(clip["w"]) / 2, int(clip["h"]) / 2)
	queue_redraw()


func cancel_float() -> void:
	## Esc while laying a copy: a move is put back where it was (undo), a paste forgotten.
	if floating.is_empty():
		return
	floating = {}
	if _lifted:
		drawing.commit()
		drawing.undo()                   # the cells it was lifted off come back
	_lifted = false
	queue_redraw()


func flip_float(across: bool) -> void:
	if not floating.is_empty():
		floating = Drawing.flip_clip(floating, across)
		queue_redraw()


func set_space(held: bool) -> void:
	_space = held
	mouse_default_cursor_shape = Control.CURSOR_DRAG if held else Control.CURSOR_ARROW
