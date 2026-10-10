extends Node2D
## Draws the ship and everyone on it, and keeps the camera on our character.
## It only reads from the GameClient; it never changes game state.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")

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
var _views := {}                     # id -> Sprite2D
var _labels := {}                    # id -> Label
var _label_layer: CanvasLayer
var _ghost: Sprite2D
var _stars := PackedVector2Array()
var _star_sizes := PackedByteArray()


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

	_chars = Node2D.new()
	_chars.y_sort_enabled = true
	add_child(_chars)
	_chars_tex = load("res://assets/chars.png")

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


func _process(_delta: float) -> void:
	if client == null or client.phase != GameClient.PLAYING:
		return
	var zoom := clampf(floorf(get_viewport_rect().size.y / 230.0), 2.0, 6.0)
	_camera.zoom = Vector2(zoom, zoom)

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
