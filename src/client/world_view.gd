extends Node2D
## Draws the ship and everyone on it, and keeps the camera on our character.
## It only reads from the GameClient; it never changes game state.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")

const CHAR_W := 32
const CHAR_H := 48
const CHAR_PAD := 1                  # transparent border around every frame in assets/chars.png
const FEET_Y := 29                   # where the feet rest inside a tile, in pixels from its top
# column of the first frame for each facing in assets/chars.png (down, up, left, right)
const FACING_COLUMN := {1: 3, 2: 0, 3: 6, 4: 9}

var client: GameClient
var show_names := true
var show_ghost := false              # debug: draw where the server says our character is

var _tile := 32
var _layer: TileMapLayer
var _chars: Node2D
var _camera: Camera2D
var _chars_tex: Texture2D
var _breach_tex: Texture2D
var _views := {}                     # id -> Sprite2D
var _labels := {}                    # id -> Label
var _label_layer: CanvasLayer
var _ghost: Sprite2D
var _stars := PackedVector2Array()
var _star_sizes := PackedByteArray()
var _source_id := 0
var _door_tiles: Array = []          # per door kind: tile ids for [shut, half open, open]
var _door_shown := PackedInt32Array()  # per door: which of those is on screen
var _door_was_open := PackedByteArray()
var _door_closing := PackedFloat32Array()   # per door: seconds left of the closing frame
var _holes: Node2D
var _hole_views := {}                # hull cell -> Sprite2D
var _air_view: Node2D
var _ship_seen := -1                 # client.ship_changes when the hull and air were last redrawn


func setup(p_client: GameClient) -> void:
	client = p_client
	var map := client.map
	_tile = map.tile_size
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(_tile, _tile)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/tiles.png")
	atlas.texture_region_size = Vector2i(_tile, _tile)
	var source_id := tiles.add_source(atlas)
	_source_id = source_id
	for i in map.tile_kinds.size():
		atlas.create_tile(Vector2i(i % map.atlas_columns, i / map.atlas_columns))
	_layer = TileMapLayer.new()
	_layer.tile_set = tiles
	add_child(_layer)
	for y in map.height:
		for x in map.width:
			var id := map.cells[y * map.width + x]
			if id >= 0:
				_layer.set_cell(Vector2i(x, y), source_id, Vector2i(id % map.atlas_columns, id / map.atlas_columns))

	# doors are redrawn as they open and close
	_door_tiles = [
		[map.tile_ids["door"], map.tile_ids["door_half"], map.tile_ids["door_open"]],
		[map.tile_ids["airlock_closed"], map.tile_ids["airlock_half"], map.tile_ids["airlock"]],
	]
	_door_shown.resize(map.doors.size())
	_door_shown.fill(-1)
	_door_was_open.resize(map.doors.size())
	_door_closing.resize(map.doors.size())

	_holes = Node2D.new()
	add_child(_holes)
	_air_view = Node2D.new()
	_air_view.draw.connect(_draw_air)
	add_child(_air_view)

	_chars = Node2D.new()
	_chars.y_sort_enabled = true
	add_child(_chars)
	_chars_tex = load("res://assets/chars.png")
	_breach_tex = load("res://assets/breach.png")

	_ghost = Sprite2D.new()
	_ghost.texture = _chars_tex
	_ghost.region_enabled = true
	_ghost.centered = false
	_ghost.offset = Vector2(-CHAR_W / 2.0, -CHAR_H)
	_ghost.modulate = Color(1, 1, 1, 0.35)
	_ghost.visible = false
	add_child(_ghost)

	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()

	_label_layer = CanvasLayer.new()
	_label_layer.layer = 1
	add_child(_label_layer)

	# a fixed scatter of stars around the ship
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var w := map.width * _tile
	var h := map.height * _tile
	for i in 420:
		_stars.append(Vector2(rng.randf_range(-700.0, w + 700.0), rng.randf_range(-500.0, h + 500.0)).floor())
		_star_sizes.append(2 if rng.randf() < 0.12 else 1)
	queue_redraw()


func _draw() -> void:
	for i in _stars.size():
		var s := float(_star_sizes[i])
		var c := Color(0.75, 0.8, 1.0, 0.9) if s > 1.0 else Color(0.6, 0.65, 0.8, 0.55)
		draw_rect(Rect2(_stars[i], Vector2(s, s)), c)


func _feet(pos_tiles: Vector2) -> Vector2:
	return Vector2(pos_tiles.x * _tile + _tile * 0.5, pos_tiles.y * _tile + FEET_Y)


func _frame(facing: int, moving: bool, pos_tiles: Vector2, colour: int) -> Rect2:
	var column: int = FACING_COLUMN.get(facing, 0)
	if moving:
		# alternate the two step poses tile by tile, switching in the middle of a slide
		column += 1 + (int(floorf(pos_tiles.x + pos_tiles.y + 0.5)) & 1)
	return _cell(column, colour)


func _cell(column: int, colour: int) -> Rect2:
	return Rect2(column * (CHAR_W + 2 * CHAR_PAD) + CHAR_PAD, colour * (CHAR_H + 2 * CHAR_PAD) + CHAR_PAD, CHAR_W, CHAR_H)


func _update_ship(delta: float) -> void:
	var map := client.map
	# doors: shut, sliding or open
	for d in map.doors.size():
		var amount := client.door_open_amount(d)
		var frame := 0 if amount <= 0.0 else (2 if amount >= 1.0 else 1)
		if frame == 0 and _door_was_open[d] == 1:
			_door_closing[d] = 0.12          # show the half-open frame for a moment on the way shut
		_door_was_open[d] = 1 if frame == 2 else 0
		if _door_closing[d] > 0.0:
			_door_closing[d] -= delta
			if frame == 0:
				frame = 1
		if frame != _door_shown[d]:
			_door_shown[d] = frame
			var id: int = _door_tiles[map.door_kind[d]][frame]
			_layer.set_cell(map.doors[d], _source_id, Vector2i(id % map.atlas_columns, id / map.atlas_columns))
	# holes in the hull
	if client.ship_changes != _ship_seen:
		_ship_seen = client.ship_changes
		for cell: int in client.holes.keys():
			if not _hole_views.has(cell):
				var hole := Sprite2D.new()
				hole.texture = _breach_tex
				hole.centered = false
				hole.position = Vector2(cell % map.width, cell / map.width) * _tile
				_holes.add_child(hole)
				_hole_views[cell] = hole
		for cell: int in _hole_views.keys():
			if not client.holes.has(cell):
				(_hole_views[cell] as Sprite2D).queue_free()
				_hole_views.erase(cell)
		_air_view.queue_redraw()
	elif not client.holes.is_empty():
		_air_view.queue_redraw()             # air streaming out is animated


func _draw_air() -> void:
	## Thin air darkens a cell; next to a hole, streaks show the air rushing out.
	var map := client.map
	for y in map.height:
		for x in map.width:
			var a := client.air_at(x, y)
			if a < 0 or a >= Net.AIR_FULL - 2:
				continue
			var thin := 1.0 - float(a) / Net.AIR_FULL
			_air_view.draw_rect(Rect2(x * _tile, y * _tile, _tile, _tile), Color(0.03, 0.05, 0.16, 0.62 * pow(thin, 0.8)))
	var now := Time.get_ticks_msec() / 1000.0
	for cell: int in client.holes.keys():
		var hx := cell % map.width
		var hy := cell / map.width
		var hole_at := Vector2(hx + 0.5, hy + 0.5) * _tile
		for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var a := client.air_at(hx + o.x, hy + o.y)
			if a <= 2:
				continue
			var strength := float(a) / Net.AIR_FULL
			var from_cell := Vector2(hx + o.x + 0.5, hy + o.y + 0.5) * _tile
			for k in 6:
				# each streak starts at its own spot around the cell and flies into the hole
				var seed_a := float((cell * 31 + k * 17) % 97) / 97.0
				var seed_b := float((cell * 13 + k * 29) % 89) / 89.0
				var start := from_cell + Vector2(seed_a - 0.5, seed_b - 0.5) * _tile * 1.6 + Vector2(o) * _tile * 0.5
				var phase := fposmod(now * (1.4 + seed_b) + seed_a, 1.0)
				var head := start.lerp(hole_at, phase)
				var tail := start.lerp(hole_at, maxf(phase - 0.16, 0.0))
				_air_view.draw_line(tail, head, Color(0.86, 0.92, 1.0, 0.55 * strength * (1.0 - phase * 0.5)), 1.0)


func _process(delta: float) -> void:
	if client == null or client.phase != GameClient.PLAYING:
		return
	var zoom := clampf(floorf(get_viewport_rect().size.y / 230.0), 2.0, 6.0)
	_camera.zoom = Vector2(zoom, zoom)
	_update_ship(delta)

	# characters
	for id: int in client.ents.keys():
		var s := client.sample(id)
		if s.is_empty():
			continue
		var sprite: Sprite2D = _views.get(id)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.texture = _chars_tex
			sprite.region_enabled = true
			sprite.centered = false
			sprite.offset = Vector2(-CHAR_W / 2.0, -CHAR_H)
			_chars.add_child(sprite)
			_views[id] = sprite
			var label := Label.new()
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			label.add_theme_constant_override("outline_size", 5)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size = Vector2(160, 18)
			_label_layer.add_child(label)
			_labels[id] = label
		var pos: Vector2 = s[0]
		sprite.position = (_feet(pos) * zoom).round() / zoom   # on a whole screen pixel
		sprite.region_rect = _frame(s[1], s[2], pos, client.player_colour(id))
	for id: int in _views.keys():
		if not client.ents.has(id):
			(_views[id] as Sprite2D).queue_free()
			(_labels[id] as Label).queue_free()
			_views.erase(id)
			_labels.erase(id)

	# camera follows our character; a ship smaller than the screen stays centred
	var me: Sprite2D = _views.get(client.my_id)
	var focus := me.position - Vector2(0, 14) if me != null else Vector2.ZERO
	var half := get_viewport_rect().size / zoom * 0.5
	var map_size := Vector2(client.map.width, client.map.height) * _tile
	var margin := 48.0
	if map_size.x + margin * 2.0 <= half.x * 2.0:
		focus.x = map_size.x * 0.5
	else:
		focus.x = clampf(focus.x, half.x - margin, map_size.x - half.x + margin)
	if map_size.y + margin * 2.0 <= half.y * 2.0:
		focus.y = map_size.y * 0.5
	else:
		focus.y = clampf(focus.y, half.y - margin, map_size.y - half.y + margin)
	# Keep the world on whole screen pixels. The camera's centre lands on half a
	# pixel when the window has an odd width or height (a maximised window, for
	# one), so the rounding has to take the screen centre into account.
	var screen_half := get_viewport_rect().size * 0.5
	_camera.position = ((focus * zoom - screen_half).round() + screen_half) / zoom

	# name tags are drawn in screen space so the text stays sharp
	var screen_centre := get_viewport_rect().size * 0.5
	for id: int in _labels.keys():
		var label: Label = _labels[id]
		label.visible = show_names
		if show_names:
			var sprite: Sprite2D = _views[id]
			label.text = client.player_name(id)
			if id == client.my_id:
				label.modulate = Color(0.6, 1.0, 0.7)
			elif client.is_bot(id):
				label.modulate = Color(0.72, 0.76, 0.86)
			else:
				label.modulate = Color(1, 1, 1)
			var top := (sprite.position - Vector2(0, CHAR_H - 6) - _camera.position) * zoom + screen_centre
			label.position = (top - Vector2(label.size.x * 0.5, label.size.y)).round()

	# debug: the server's idea of where we are
	var mine: GameClient.Ent = client.ents.get(client.my_id)
	_ghost.visible = show_ghost and mine != null
	if _ghost.visible:
		_ghost.position = _feet(Vector2(mine.x, mine.y))
		_ghost.region_rect = _cell(FACING_COLUMN.get(mine.facing, 0), client.player_colour(client.my_id))
