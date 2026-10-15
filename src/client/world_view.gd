extends Node2D
## Draws the ship and everyone on it, and keeps the camera on our character.
## It only reads from the GameClient; it never changes game state.
##
## Every deck is drawn in the same place on the screen. The deck our
## character is on is drawn in full; the decks under it are drawn first and
## darker, so they show wherever the floor above is glass, a catwalk or a
## hatch; of the deck above only its see-through floors are hinted, with
## whoever stands on them.

const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")
const GameClient := preload("res://src/client/game_client.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Sounds := preload("res://src/client/sounds.gd")

const CHAR_W := 32
const CHAR_H := 48
const CHAR_PAD := 1                  # transparent border around every frame in assets/chars.png
const FEET_Y := 29                   # where the feet rest inside a tile, in pixels from its top
# column of the first frame for each facing in assets/chars.png (down, up, left, right)
const FACING_COLUMN := {1: 3, 2: 0, 3: 6, 4: 9}

const BELOW_TINT := Color(0.6, 0.66, 0.8)        # a deck seen through the floor
const ABOVE_TINT := Color(0.8, 0.9, 1.0, 0.6)    # somebody seen from below through a see-through floor
const CEILING_TINT := Color(1, 1, 1, 0.38)       # the see-through floors of the deck above
# The ship without power and without light: near black, with a cold tinge, but
# the walls can still be made out faintly (v46, as in the author's SS13 screenshots;
# v47 deeper, his "deep dark")
const DARK := Color(0.0, 0.002, 0.012, 0.955)
const BEAM := Color(1.0, 0.86, 0.6)               # the colour of a flashlight's light: warm
const VIEW_CELLS := 9                             # cells seen either side of us across the screen
const LIGHT_SUB := 4                              # pixels to a cell in the pictures of light (_draw_light)
const FLASH := 0.95                               # how bright the middle of a flashlight's pool is
# A place out of sight is as dark as an unlit one, lit or not: only its outline
# is remembered, faintly (v47, the author's "deep dark" as in SS13; it was 0.74 dark)
const UNSEEN := 0.955
const STARLIGHT := 0.7                           # how much light a ship's outer skin gets from the stars
# In the dark the eyes still make out the room around them, dimly (v45, the
# author's screenshot; v46 dimmer and stopped by walls, like the SS13 shots):
# at most DIM of full light around our character, gone DIM_RADIUS cells off.
const DIM := 0.3
const DIM_RADIUS := 5.0
# Around our character, all the way round and in any light, a small soft pool
# is made out (v47, the author: "light on the main character like in SS13"):
# NEAR at our own cell, gone NEAR_RADIUS cells off, stopped by walls.
const NEAR := 0.8
const NEAR_RADIUS := 3.2
const CONE_SOFT := 14.0                           # degrees over which the sides of the cone fade out
const CONE_BAND := 1.6                            # and cells across which they fade, near us too
const LOOK_MARGIN := 26.0                         # degrees the cells seen are worked out past the cone, for that fade
# The smooth cone: a soft fan, worked out for each pixel. A side fades over a
# band CONE_BAND cells wide at our feet, widening by CONE_SOFT degrees outwards,
# so it reads as one soft straight edge (v48, the author: "smoother, like a triangle").
const CONE_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform vec2 origin;
uniform vec2 ahead;
uniform float half_field;
uniform float band;
uniform float spread;
uniform float reach;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	vec2 rel = local - origin;
	float r = length(rel);
	float f = 1.0;
	if (r > 1.0) {
		float a = acos(clamp(dot(rel / r, ahead), -1.0, 1.0));
		float out_by = a - half_field;          // how far past the side, as a turn
		float dist = out_by <= 0.0 ? -r * sin(min(-out_by, 1.5707)) : r * sin(min(out_by, 1.5707));
		float w = band + r * spread;
		f = 1.0 - smoothstep(-0.5 * w, 0.5 * w, dist);
		f *= 1.0 - smoothstep(reach - band, reach, r);
	}
	COLOR = vec4(0.0, 1.0, 0.0, f);
}
"""
const LOOK_RAYS := 48                             # rays per eye when the field of view is worked out
# The mask has two pictures in one: red is where light falls, green is what our
# eyes reach. Seen and lit = clear; out of sight or unlit = near black.
const DARK_SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_linear;
uniform vec4 dark;
uniform sampler2D cone : filter_linear;
uniform float unseen;
void fragment() {
	vec4 m = texture(mask, SCREEN_UV);
	float seen = clamp(m.g, 0.0, 1.0) * clamp(texture(cone, SCREEN_UV).g, 0.0, 1.0);
	// red: the ship's own light; blue: flashlights and flashes, which light only what we look at
	float lit = clamp(m.r + m.b * seen, 0.0, 1.0);
	COLOR = vec4(dark.rgb, mix(unseen, dark.a * (1.0 - lit), seen));
}
"""
const SEEN_ONLY_SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_linear;
uniform sampler2D cone : filter_linear;
void fragment() {
	// shown only where our eyes reach (the green of the mask, inside the smooth cone)
	COLOR.a *= clamp(texture(mask, SCREEN_UV).g, 0.0, 1.0) * clamp(texture(cone, SCREEN_UV).g, 0.0, 1.0);
}
"""
const SOUND_SECONDS := 1.6                        # how long the mark of a sound stays
const SOUND_LOOK := ["", "шаги", "дверь", "шипение", "падение", "стук", "лестница", "выстрел", "удар", "крик"]
const SOUND_COLOUR: Array[Color] = [Color.WHITE, Color(0.85, 0.85, 0.9), Color(0.4, 0.9, 0.85), Color(0.6, 0.85, 1.0),
	Color(1.0, 0.4, 0.35), Color(0.95, 0.85, 0.4), Color(0.9, 0.9, 0.9), Color(1.0, 0.65, 0.2), Color(1.0, 0.55, 0.4),
	Color(1.0, 0.3, 0.3)]
const STEP_MARK_GAP := 1.8                        # seconds: footsteps near an earlier mark of them make no new one
const SHOT_SECONDS := 0.18                        # how long a shot's trace stays


class DeckView:
	var group: Node2D                # everything of this deck
	var layer: TileMapLayer          # its tiles
	var holes: Node2D                # breaches in its hull
	var fx: Node2D                   # air streaming out, sparks
	var things: Node2D               # things lying on the floor
	var chars: Node2D                # the characters on it
	var ceiling: TileMapLayer        # its see-through floors alone: what is seen of it from the deck below


var client: GameClient
var show_names := true
var show_ghost := false              # debug: draw where the server says our character is

var _tile := 32
var _decks: Array[DeckView] = []
var _deck_shown := -1                # the deck the picture was last arranged for
var _stride := 16                    # rows from one deck to the next in the map's grid
var _camera: Camera2D
var _chars_tex: Texture2D
var _breach_tex: Texture2D
var _views := {}                     # id -> Sprite2D
var _labels := {}                    # id -> Label
var _seen := {}                      # id -> can it be seen from our deck (a name is hidden with its owner)
var _label_layer: CanvasLayer
var _ghost: Sprite2D
var _me_layer: CanvasLayer          # above the dark: our own character is always made out
var _me_over: Sprite2D
var _stars := PackedVector2Array()
var _star_sizes := PackedByteArray()
var _star_origin := Vector2.ZERO     # corner and size of the patch of sky the stars are scattered over
var _star_field := Vector2.ONE
var _star_shift := Vector2.ZERO      # how far the sky has slid: follows the ship's place in its sector
const STAR_PIXELS_PER_UNIT := 9.0
var _source_id := 0
var _door_tiles: Array = []          # per door kind: tile ids for [shut, half open, open]
var _door_shown := PackedInt32Array()  # per door: which of those is on screen
var _door_was_open := PackedByteArray()
var _door_closing := PackedFloat32Array()   # per door: seconds left of the closing frame
var _hole_views := {}                # hull cell -> Sprite2D
var _ship_seen := -1                 # client.ship_changes when the hull and air were last redrawn
var _floor_seen := -1                # client.floor_changes when the things on the floor were last redrawn
var _shade: Node2D                   # the warm light of flashlights on the floor
var _lit := {}                       # the cells lit right now (see GameClient.lit_cells): for names in the dark
var _dim := {}                       # the dim light around us in the dark: cell -> how strongly (Sight.glow)
var _near := {}                      # the small pool around us seen all the way round (Sight.glow)
var _light_textures := {}            # the pictures of light drawn last, one per pen (see _draw_light)
var _light_made := {}                # and for each: [what it was made from, where it is drawn]
var _mask_key := 0                   # what the picture of light was last drawn for
var _look_key := 0                   # what the field of view was last drawn for (see _process)
var _picture_key := 0                # the last picture of light made, and what from (see _light_picture)
var _picture: Array = [null, Rect2()]
# Darkness is a black sheet over the screen with holes where light falls. The holes
# are drawn, soft-edged, into a picture of their own (the mask) that follows the camera.
var _mask_view: SubViewport
var _mask: Node2D                    # draws where light falls (red)
var _look: Node2D                    # draws what our eyes reach (green)
# The smooth cone of the eyes, not cut by walls, with soft sides, and the pool
# around us: a second picture that the cells seen (green) are multiplied by, so
# what is seen ends along the cone's straight sides, not cell by cell (v47).
var _cone_view: SubViewport
var _cone: Node2D
var _cone_fan: Node2D                # the fan itself, drawn by CONE_SHADER
var _fan_rect := Rect2()             # where it is drawn (empty: nowhere)
var _cone_camera: Camera2D
var _sounds: Array = []              # marks of sounds heard: [kind, place in the deck's pixels, deck, seconds left]
var _audio: Sounds                   # what is heard (see Sounds)
var _last_cell := Vector2i(-1, -1)   # where our character was, for its own footsteps
var _hum_timer := 0.0
var _sound_pen: Node2D               # draws them over everything, in screen space
var _shots: Array = []               # shots and blows to draw: [kind, hit, from, to (deck pixels), deck, seconds left]
var _mask_camera: Camera2D
var _dark_layer: CanvasLayer
var _dark_sheet: ColorRect
const AFTERIMAGE_SECONDS := 10.0                # how long the silhouette of somebody lost from sight stays
var _afterimages := {}               # id -> [Sprite2D, seconds left, the cell it was last seen in]
var _shown := {}                     # id -> was it shown last frame
var _other_seen := 0                 # GameClient.other_changes when the tiles were last laid
var _dark := 0.0                     # 0 = the lights are on, 1 = no power: eased, so it fades


func setup(p_client: GameClient) -> void:
	client = p_client
	var map := client.map
	_tile = map.tile_size
	_stride = map.deck_stride
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chars_tex = load("res://assets/chars.png")
	_breach_tex = load("res://assets/breach.png")

	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(_tile, _tile)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/tiles.png")
	atlas.texture_region_size = Vector2i(_tile, _tile)
	var source_id := tiles.add_source(atlas)
	_source_id = source_id
	for i in map.tile_kinds.size():
		atlas.create_tile(Vector2i(i % map.atlas_columns, i / map.atlas_columns))

	for d in map.deck_count:
		var deck := DeckView.new()
		deck.group = Node2D.new()
		add_child(deck.group)
		deck.layer = TileMapLayer.new()
		deck.layer.tile_set = tiles
		deck.group.add_child(deck.layer)
		deck.ceiling = TileMapLayer.new()
		deck.ceiling.tile_set = tiles
		deck.ceiling.modulate = CEILING_TINT
		deck.ceiling.visible = false
		deck.holes = Node2D.new()
		deck.group.add_child(deck.holes)
		deck.fx = Node2D.new()
		deck.fx.draw.connect(_draw_fx.bind(d))
		deck.group.add_child(deck.fx)
		deck.things = Node2D.new()
		deck.things.draw.connect(_draw_things.bind(d))
		deck.group.add_child(deck.things)
		deck.chars = Node2D.new()
		deck.chars.y_sort_enabled = true
		deck.group.add_child(deck.chars)
		_decks.append(deck)
		# The see-through floors of the deck above are hinted on this deck's own
		# floor, under its characters, so they do not veil whoever walks here.
		if d > 0:
			deck.group.add_child(_decks[d - 1].ceiling)
			deck.group.move_child(_decks[d - 1].ceiling, 1)

	_paint_decks()
	var last := _decks[_decks.size() - 1]
	last.group.add_child(last.ceiling)       # nothing is below the lowest deck to see it from; kept only so it is freed
	last.ceiling.visible = false

	# doors are redrawn as they open and close
	_door_tiles = [
		["door", "door_half", "door_open"],
		["airlock_closed", "airlock_half", "airlock"],
	]
	_door_shown.resize(map.doors.size())
	_door_shown.fill(-1)
	_door_was_open.resize(map.doors.size())
	_door_closing.resize(map.doors.size())

	_shade = Node2D.new()
	_shade.z_index = map.deck_count + 3
	_shade.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shade.draw.connect(_draw_shade)
	add_child(_shade)
	_mask_view = SubViewport.new()
	_mask_view.disable_3d = true
	_mask_view.transparent_bg = true
	_mask_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mask_view)
	var adding := CanvasItemMaterial.new()
	adding.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mask = Node2D.new()
	_mask.material = adding
	_mask.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # light is drawn as small pictures, smoothed
	_mask.draw.connect(_draw_mask)
	_mask_view.add_child(_mask)
	_look = Node2D.new()
	_look.material = adding
	_look.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # the pool around us is a small picture too
	_look.draw.connect(_draw_look)
	_mask_view.add_child(_look)
	_mask_camera = Camera2D.new()
	_mask_view.add_child(_mask_camera)
	_mask_camera.enabled = true
	_cone_view = SubViewport.new()
	_cone_view.disable_3d = true
	_cone_view.transparent_bg = true
	_cone_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_cone_view)
	_cone = Node2D.new()
	_cone.material = adding
	_cone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cone.draw.connect(_draw_cone)
	_cone_view.add_child(_cone)
	_cone_fan = Node2D.new()
	var fan_shader := Shader.new()
	fan_shader.code = CONE_SHADER
	var fan_material := ShaderMaterial.new()
	fan_material.shader = fan_shader
	_cone_fan.material = fan_material
	_cone_view.add_child(_cone_fan)
	_cone_fan.draw.connect(func() -> void:
		if _fan_rect.has_area():
			_cone_fan.draw_rect(_fan_rect, Color.WHITE))
	_cone_camera = Camera2D.new()
	_cone_view.add_child(_cone_camera)
	_cone_camera.enabled = true
	_dark_layer = CanvasLayer.new()
	_dark_layer.layer = 1
	add_child(_dark_layer)
	_dark_sheet = ColorRect.new()
	_dark_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sheet_shader := Shader.new()
	sheet_shader.code = DARK_SHADER
	var sheet_material := ShaderMaterial.new()
	sheet_material.shader = sheet_shader
	sheet_material.set_shader_parameter("mask", _mask_view.get_texture())
	sheet_material.set_shader_parameter("cone", _cone_view.get_texture())
	sheet_material.set_shader_parameter("unseen", UNSEEN)
	_dark_sheet.material = sheet_material
	# the warm light of flashlights and the traces of shots show only where we look
	var seen_only := Shader.new()
	seen_only.code = SEEN_ONLY_SHADER
	var shade_material := ShaderMaterial.new()
	shade_material.shader = seen_only
	shade_material.set_shader_parameter("mask", _mask_view.get_texture())
	shade_material.set_shader_parameter("cone", _cone_view.get_texture())
	_shade.material = shade_material
	_dark_layer.add_child(_dark_sheet)
	# We always see ourselves, even in pitch dark (without the glow around us
	# the author asked to be rid of): a copy of our figure over the dark.
	_me_layer = CanvasLayer.new()
	_me_layer.layer = 2
	_me_layer.follow_viewport_enabled = true
	add_child(_me_layer)
	_me_over = Sprite2D.new()
	_me_over.texture = _chars_tex
	_me_over.region_enabled = true
	_me_over.centered = false
	_me_over.offset = Vector2(-CHAR_W / 2.0, -CHAR_H)
	_me_layer.add_child(_me_over)

	_ghost = Sprite2D.new()
	_ghost.texture = _chars_tex
	_ghost.region_enabled = true
	_ghost.centered = false
	_ghost.offset = Vector2(-CHAR_W / 2.0, -CHAR_H)
	_ghost.modulate = Color(1, 1, 1, 0.35)
	_ghost.visible = false
	_ghost.z_index = map.deck_count + 2
	add_child(_ghost)

	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()

	_label_layer = CanvasLayer.new()
	_label_layer.layer = 2
	add_child(_label_layer)
	_sound_pen = Node2D.new()
	_sound_pen.draw.connect(_draw_sounds)
	_label_layer.add_child(_sound_pen)
	client.heard.connect(_on_heard)
	_audio = Sounds.new()
	add_child(_audio)
	client.shot.connect(_on_shot)

	# a fixed scatter of stars around the ship
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var w := map.width * _tile
	var h := map.deck_height * _tile
	_star_origin = Vector2(-700.0, -500.0)
	_star_field = Vector2(w + 1400.0, h + 1000.0)
	for i in 420:
		_stars.append(Vector2(rng.randf_range(-700.0, w + 700.0), rng.randf_range(-500.0, h + 500.0)).floor())
		_star_sizes.append(2 if rng.randf() < 0.12 else 1)
	_arrange(0)
	queue_redraw()


func _draw() -> void:
	# the stars slide past as the ship moves inside its sector, and wrap around
	for i in _stars.size():
		var s := float(_star_sizes[i])
		var c := Color(0.75, 0.8, 1.0, 0.9) if s > 1.0 else Color(0.6, 0.65, 0.8, 0.55)
		var at := (_stars[i] - _star_origin + _star_shift * (1.6 if s > 1.0 else 1.0)).posmodv(_star_field) + _star_origin
		draw_rect(Rect2(at.floor(), Vector2(s, s)), c)


func _arrange(shown: int) -> void:
	## Sets what is drawn of every deck when our character is on deck `shown`.
	_deck_shown = shown
	for d in _decks.size():
		var deck := _decks[d]
		var above := d < shown
		deck.group.visible = d >= shown - 1          # two decks up nothing can be seen
		# the deeper a deck, the earlier it is drawn; never below zero, where the stars are
		deck.group.z_index = _decks.size() + 1 if above else _decks.size() - 1 - d
		deck.group.modulate = BELOW_TINT if d > shown else Color.WHITE
		deck.layer.visible = not above
		deck.holes.visible = not above
		deck.fx.visible = not above
		deck.things.visible = not above
		deck.chars.modulate = ABOVE_TINT if above else Color.WHITE
		deck.ceiling.visible = d == shown - 1


func _on_deck(cell: int) -> Vector2:
	## A cell of the map's grid as a place on its own deck, in tiles.
	return Vector2(cell % client.map.width, (cell / client.map.width) % _stride)


func _feet(pos_tiles: Vector2) -> Vector2:
	## Where the feet of a character at this place of its deck are, in pixels.
	return Vector2(pos_tiles.x * _tile + _tile * 0.5, pos_tiles.y * _tile + FEET_Y)


func _frame(facing: int, moving: bool, pos_tiles: Vector2, colour: int) -> Rect2:
	var column: int = FACING_COLUMN.get(facing, 0)
	if moving:
		# alternate the two step poses tile by tile, switching in the middle of a slide
		column += 1 + (int(floorf(pos_tiles.x + pos_tiles.y + 0.5)) & 1)
	return _cell(column, colour)


func _cell(column: int, row: int) -> Rect2:
	## A frame of the character sheet; a row is a colour and a way of being dressed (see Net.LOOKS).
	return Rect2(column * (CHAR_W + 2 * CHAR_PAD) + CHAR_PAD, row * (CHAR_H + 2 * CHAR_PAD) + CHAR_PAD, CHAR_W, CHAR_H)


func _update_ship(delta: float) -> void:
	var map := client.map
	if client.other_changes != _other_seen:
		_paint_decks()
	# doors: shut, sliding or open
	for d in map.doors.size():
		if not map.door_here(d):
			continue
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
			var id: int = map.tile_ids[map.door_tint(d) + str(_door_tiles[map.door_kind[d]][frame])]
			var at: Vector2i = map.doors[d]
			_decks[map.deck_of(at.y)].layer.set_cell(Vector2i(at.x, map.local_y(at.y)), _source_id,
				Vector2i(id % map.atlas_columns, id / map.atlas_columns))
	# holes in the hull
	if client.ship_changes != _ship_seen:
		_ship_seen = client.ship_changes
		for cell: int in client.holes.keys():
			if not _hole_views.has(cell):
				var hole := Sprite2D.new()
				hole.texture = _breach_tex
				hole.centered = false
				hole.position = _on_deck(cell) * _tile
				_decks[map.deck_of_cell(cell)].holes.add_child(hole)
				_hole_views[cell] = hole
		for cell: int in _hole_views.keys():
			if not client.holes.has(cell):
				(_hole_views[cell] as Sprite2D).queue_free()
				_hole_views.erase(cell)
		for deck in _decks:
			deck.fx.queue_redraw()
	else:
		for deck in _decks:
			deck.fx.queue_redraw()           # air streaming out, sparks and the machines are animated
	if client.floor_changes != _floor_seen:
		_floor_seen = client.floor_changes
		for deck in _decks:
			deck.things.queue_redraw()
	# light and dark change with every step anybody holding a flashlight takes
	_dark = move_toward(_dark, 0.0 if client.powered() else 1.0, delta * 2.5)
	_lit = client.lit_cells()
	_dim = _find_dim()
	_near = _find_near()
	_shade.queue_redraw()
	(_dark_sheet.material as ShaderMaterial).set_shader_parameter("dark", DARK)
	# where light falls is drawn again only when it may have changed
	var mask_key := hash([_dark, _deck_shown, client.my_deck(), client.my_cond, client.other_changes, client.other_dark(),
		_dim.hash(), _near.hash(), _lit.hash()])
	if mask_key != _mask_key or not _shots.is_empty():
		_mask_key = mask_key
		_mask.queue_redraw()
	_update_fan()
	for i in range(_shots.size() - 1, -1, -1):
		_shots[i][5] -= delta
		if float(_shots[i][5]) <= 0.0:
			_shots.remove_at(i)
	for i in range(_sounds.size() - 1, -1, -1):
		_sounds[i][3] -= delta
		if float(_sounds[i][3]) <= 0.0:
			_sounds.remove_at(i)
	_sound_pen.queue_redraw()


func _draw_things(d: int) -> void:
	## Things lying on the floor of one deck: one in the middle of its cell, several side by side.
	var map := client.map
	var pen := _decks[d].things
	for cell: int in client.floor_things.keys():
		if map.deck_of_cell(cell) != d:
			continue
		var things: PackedByteArray = client.floor_things[cell]
		var here := PackedByteArray()
		for v in things:
			if v != Net.ITEM_NONE:
				here.append(v)
		var corner := _on_deck(cell) * _tile
		if here.size() == 1:
			ItemArt.draw(pen, Rect2(corner + Vector2(7, 9), Vector2(18, 18)), here[0])
			continue
		for k in here.size():
			var spot := Vector2(3 + (k % 2) * 13, 6 + (k / 2) * 12)
			ItemArt.draw(pen, Rect2(corner + spot, Vector2(14, 14)), here[k])


func _find_dim() -> Dictionary:
	## The dim light our eyes make out around us in the dark (only worked out
	## when something is dark: it costs a few line checks).
	if _dark <= 0.0 and not client.other_dark():
		return {}
	if client.my_cond != Net.COND_OK:
		return {}
	var s := client.sample(client.my_id)
	if s.is_empty():
		return {}
	return client.glow(s[0], 0, DIM_RADIUS, 0.0)


func _find_near() -> Dictionary:
	## The small pool around us that is made out all the way round (NEAR).
	if client.my_cond != Net.COND_OK:
		return {}
	var s := client.sample(client.my_id)
	if s.is_empty():
		return {}
	return client.glow(s[0], 0, NEAR_RADIUS, 0.0)


func _draw_light(pen: CanvasItem, light: Dictionary, colour: Color, tag: int) -> void:
	## Light worked out cell by cell (cell -> 0..1), drawn smooth the way Space
	## Station 13 draws it: the light blends evenly between the middles of
	## neighbouring cells, so a pool of light fades out softly. A cell the light
	## does not reach (one behind a wall) stays dark, so nothing leaks past walls.
	## Drawn as a small picture, LIGHT_SUB pixels to a cell, stretched with
	## smoothing over the deck. `tag` tells apart the pictures drawn by one pen.
	## The picture is made again only when the light, the deck or the doors
	## changed (the same light is often drawn by several pens in one frame).
	var key := hash([light.hash(), _deck_shown, hash(client.doors.ready), client.other_changes])
	var which := [pen.get_instance_id(), tag]
	var texture: ImageTexture = _light_textures.get(which)
	var made: Array = _light_made.get(which, [])
	if made.is_empty() or made[0] != key or texture == null:
		var pic := _light_picture(light, key)
		made = [key, pic[1]]
		_light_made[which] = made
		if pic[0] == null:
			return
		var picture: Image = pic[0]
		if texture == null or texture.get_size() != Vector2(picture.get_size()):
			texture = ImageTexture.create_from_image(picture)
			_light_textures[which] = texture
		else:
			texture.update(picture)
	if made[1] == Rect2():
		return
	pen.draw_texture_rect(texture, made[1], false, colour)


func _light_picture(light: Dictionary, key: int) -> Array:
	## The picture _draw_light stretches over the deck, and where: [Image, Rect2],
	## or [null, Rect2()] when the light falls nowhere on the deck shown.
	if key == _picture_key:
		return _picture
	_picture_key = key
	_picture = [null, Rect2()]
	var map := client.map
	var top := _deck_shown * _stride
	var lo := Vector2i(map.width, map.deck_height)
	var hi := Vector2i(-1, -1)
	var here := {}                           # cells on the deck shown -> how strongly
	for cell: int in light.keys():
		var v := float(light[cell])
		var y := cell / map.width - top
		if v <= 0.0 or y < 0 or y >= map.deck_height:
			continue
		var x := cell % map.width
		here[Vector2i(x, y)] = v
		lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
		hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if here.is_empty():
		return _picture
	# one cell more all round, so the open floor just past the light's edge can
	# take the last of it: the pool fades out to nothing instead of stopping at
	# a cell's edge (v47, the author: "smoother")
	lo = Vector2i(maxi(lo.x - 1, 0), maxi(lo.y - 1, 0))
	hi = Vector2i(mini(hi.x + 1, map.width - 1), mini(hi.y + 1, map.deck_height - 1))
	var walls := {}                          # cell -> does it stop light (worked out once)
	for y in range(lo.y - 1, hi.y + 2):
		for x in range(lo.x - 1, hi.x + 2):
			walls[Vector2i(x, y)] = x < 0 or y < 0 or x >= map.width or y >= map.deck_height \
				or Sight.blocks(map, client.doors, x, y + top)
	var w := (hi.x - lo.x + 1) * LIGHT_SUB
	var h := (hi.y - lo.y + 1) * LIGHT_SUB
	var data := PackedByteArray()
	data.resize(w * h * 2)
	var k := 0
	for py in h:
		var cy := lo.y + py / LIGHT_SUB
		var gy := lo.y + (py + 0.5) / LIGHT_SUB - 0.5   # in cells, between the middles of cells
		var y0 := floori(gy)
		var fy := gy - y0
		for px in w:
			var cx := lo.x + px / LIGHT_SUB
			var own: float = here.get(Vector2i(cx, cy), 0.0)
			var v := 0.0
			if own > 0.0 or not walls[Vector2i(cx, cy)]:
				var gx := lo.x + (px + 0.5) / LIGHT_SUB - 0.5
				var x0 := floori(gx)
				var fx := gx - x0
				# a wall the light does not reach counts as this cell, so the edge of
				# a lit place next to a wall stays lit right up to it; open floor it
				# does not reach counts as dark, so the light fades into it
				var a: float = here.get(Vector2i(x0, y0), own if walls[Vector2i(x0, y0)] else 0.0)
				var b: float = here.get(Vector2i(x0 + 1, y0), own if walls[Vector2i(x0 + 1, y0)] else 0.0)
				var c: float = here.get(Vector2i(x0, y0 + 1), own if walls[Vector2i(x0, y0 + 1)] else 0.0)
				var d: float = here.get(Vector2i(x0 + 1, y0 + 1), own if walls[Vector2i(x0 + 1, y0 + 1)] else 0.0)
				v = lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
			data[k] = 255
			data[k + 1] = clampi(roundi(v * 255.0), 0, 255)
			k += 2
	_picture = [Image.create_from_data(w, h, false, Image.FORMAT_LA8, data),
		Rect2(Vector2(lo) * _tile, Vector2(hi - lo + Vector2i.ONE) * _tile)]
	return _picture




const SHIP_SHOT_COLOURS := {Net.SHOT_CANNON: Color(1.0, 0.55, 0.15), Net.SHOT_ION: Color(0.35, 0.65, 1.0),
	Net.SHOT_ROCKET: Color(0.85, 0.85, 0.8), Net.SHOT_PLASMA: Color(0.4, 1.0, 0.45), Net.SHOT_BEAM: Color(0.9, 0.6, 1.0),
	Net.SHOT_TRACTOR: Color(0.6, 1.0, 0.75), Net.SHOT_SIPHON: Color(0.35, 0.95, 1.0)}


func _on_shot(kind: int, hit: bool, from: Vector2, to: Vector2) -> void:
	var map := client.map
	var deck := map.deck_of(clampi(roundi(from.y), 0, map.height - 1))
	var a := _feet(Vector2(from.x, from.y - deck * _stride)) + Vector2(0, -16)
	var b := _feet(Vector2(to.x, to.y - deck * _stride)) + Vector2(0, -16)
	_shots.append([kind, hit, a, b, deck, SHOT_SECONDS * (3.0 if kind >= Net.SHOT_CANNON else 1.0)])


func cell_under_mouse() -> Vector2:
	## The place under the mouse in cells of the whole grid, on the deck shown.
	## A click on somebody's body counts as their cell (the body stands above its feet).
	var at := get_local_mouse_position() + Vector2(0, 14)
	return Vector2(at.x / _tile - 0.5, (at.y - FEET_Y) / _tile + 0.5 + _deck_shown * _stride - 0.5)


func _paint_decks() -> void:
	## Lays the tiles of every deck (again when another ship comes, goes or moves).
	var map := client.map
	for d in _decks.size():
		var deck: DeckView = _decks[d]
		deck.layer.clear()
		deck.ceiling.clear()
		for y in map.deck_height:
			for x in map.width:
				var cell := (d * _stride + y) * map.width + x
				var id := map.cells[cell]
				if id < 0:
					continue
				var in_atlas := Vector2i(id % map.atlas_columns, id / map.atlas_columns)
				deck.layer.set_cell(Vector2i(x, y), _source_id, in_atlas)
				if map.see_through[cell] == 1:
					deck.ceiling.set_cell(Vector2i(x, y), _source_id, in_atlas)
	_door_shown.fill(-1)
	_other_seen = client.other_changes


func _leave_afterimage(id: int, sprite: Sprite2D, _at: Vector2i) -> void:
	## Somebody just went out of sight: a fading silhouette stays where they were last seen.
	if _afterimages.has(id):
		(_afterimages[id][0] as Sprite2D).queue_free()
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.region_enabled = true
	ghost.region_rect = sprite.region_rect
	ghost.centered = false
	ghost.offset = sprite.offset
	ghost.position = sprite.position
	ghost.rotation = sprite.rotation
	ghost.modulate = Color(0.75, 0.8, 0.9, 0.55)
	sprite.get_parent().add_child(ghost)
	var s := client.sample(id)
	var cell: Vector2i = Vector2i(roundi(float(s[0].x)), roundi(float(s[0].y))) if not s.is_empty() else client.hidden.get(id, Vector2i(-1, -1))
	_afterimages[id] = [ghost, AFTERIMAGE_SECONDS, cell]


func _fade_afterimages(delta: float) -> void:
	## Silhouettes fade out; one goes at once when its owner is seen again, or
	## when we look at the place and nobody is there any more.
	for id: int in _afterimages.keys():
		var a: Array = _afterimages[id]
		a[1] = float(a[1]) - delta
		var cell: Vector2i = a[2]
		var view: Sprite2D = _views.get(id)
		var gone := float(a[1]) <= 0.0 or (view != null and view.visible) or not (client.ents.has(id) or client.hidden.has(id))
		if not gone and cell.x >= 0 and can_see(cell.x, cell.y):
			gone = true                      # we look there now: what is there is seen as it is
		var ghost: Sprite2D = a[0]
		if gone:
			ghost.queue_free()
			_afterimages.erase(id)
		else:
			ghost.modulate.a = 0.55 * float(a[1]) / AFTERIMAGE_SECONDS


func _draw_shade() -> void:
	## The warm light of flashlights on the floor, and shots: a trace, a flash
	## at the muzzle and a spark where it hit (the dark itself is the sheet over the screen).
	for sh: Array in _shots:
		if int(sh[4]) != _deck_shown:
			continue
		var left := float(sh[5]) / SHOT_SECONDS
		var a: Vector2 = sh[2]
		var b: Vector2 = sh[3]
		if int(sh[0]) >= Net.SHOT_CANNON:
			# a ship's gun: a trace coloured by what it fires and a burst where it lands
			# (a ripple of the shield where one stopped it: hit = 0)
			var k := int(sh[0])
			var c: Color = SHIP_SHOT_COLOURS.get(k, SHIP_SHOT_COLOURS[Net.SHOT_CANNON])
			var fade := minf(left, 1.0)
			_shade.draw_line(a, b, Color(c, 0.9 * fade), 2.0 if k == Net.SHOT_BEAM or k == Net.SHOT_TRACTOR or k == Net.SHOT_SIPHON else (5.0 if k == Net.SHOT_ROCKET else 4.0))
			if bool(sh[1]):
				_shade.draw_circle(b, 14.0 * left + 4.0, Color(c.lightened(0.3), 0.8 * fade))
			else:
				_shade.draw_arc(b, 22.0 - 6.0 * left, PI * 0.0, TAU, 24, Color(0.45, 0.75, 1.0, 0.8 * fade), 3.0)
			continue
		if int(sh[0]) == Net.SHOT_BULLET:
			_shade.draw_line(a, b, Color(1.0, 0.9, 0.5, 0.85 * left), 1.5)
			_shade.draw_circle(a + (b - a).normalized() * 10.0, 5.0 * left, Color(1.0, 0.85, 0.4, left))
		else:
			_shade.draw_arc(b, 9.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.8 * left), 2.0)
		if bool(sh[1]):
			_shade.draw_circle(b, 6.0 * left + 2.0, Color(0.9, 0.1, 0.1, 0.9 * left))
	_draw_light(_shade, _lit, Color(BEAM, 0.16 + 0.16 * _dark), 0)


func _draw_mask() -> void:
	## Red where light falls. Space outside the ship is never dark; the ship is
	## lit while it has power, and in the dark only flashlights and
	## muzzle flashes are.
	var map := client.map
	var red := Color(1, 0, 0, 1)
	var size := Vector2(map.width, map.deck_height) * _tile
	var far := 8000.0
	_mask.draw_rect(Rect2(-far, -far, size.x + 2 * far, far), red)                       # above the ship
	_mask.draw_rect(Rect2(-far, size.y, size.x + 2 * far, far), red)                     # below it
	_mask.draw_rect(Rect2(-far, 0, far, size.y), red)                                    # to its left
	_mask.draw_rect(Rect2(size.x, 0, far, size.y), red)                                  # to its right
	var ship := Color(1, 0, 0, 1.0 - _dark)
	for y in map.deck_height:
		var row := (_deck_shown * _stride + y) * map.width
		var x := 0
		while x < map.width:
			# runs of cells of one kind: space, our ship, or a derelict (always dark)
			var kind := _light_kind(map, row + x)
			var run := x
			while run < map.width and _light_kind(map, row + run) == kind:
				run += 1
			var rect := Rect2(Vector2(x, y) * _tile, Vector2(run - x, 1) * _tile)
			if kind == 0:
				_mask.draw_rect(rect, red)
			elif kind == 1 and ship.a > 0.0:
				_mask.draw_rect(rect, ship)
			x = run
	# Starlight: a ship's outer skin (the walls and doors that face open space)
	# is never quite dark, so one out in space sees the hulls around them. The
	# inside of a dark ship stays dark.
	var star := Color(1, 0, 0, STARLIGHT)
	for y in map.deck_height:
		var row := (_deck_shown * _stride + y) * map.width
		for x in map.width:
			var cell := row + x
			if map.cells[cell] < 0 or (map.opaque[cell] == 0 and map.door_of[cell] < 0):
				continue
			if _light_kind(map, cell) == 1 and ship.a >= 1.0:
				continue
			if _faces_space(map, x, y):
				_mask.draw_rect(Rect2(Vector2(x, y) * _tile, Vector2(_tile, _tile)), star)
	if _dark <= 0.0 and not client.other_dark():
		return
	# In the dark the room around us is made out dimly where we look (the green
	# of the mask); flashlights and muzzle flashes light it fully.
	var me: Sprite2D = _views.get(client.my_id)
	if me != null and me.get_parent() == _decks[_deck_shown].chars and client.my_cond == Net.COND_OK:
		_draw_light(_mask, _dim, Color(1, 0, 0, DIM), 0)
		_draw_light(_mask, _near, Color(1, 0, 0, NEAR * 0.5), 2)   # and a little more right around us
	for sh: Array in _shots:
		if int(sh[4]) == _deck_shown and int(sh[0]) == Net.SHOT_BULLET:
			_mask.draw_circle(sh[2], 26.0, Color(0, 0, 1, float(sh[5]) / SHOT_SECONDS))   # a muzzle flash lights the dark
	_draw_light(_mask, _lit, Color(0, 0, 1, FLASH), 1)       # flashlights: soft round pools


func _faces_space(map: ShipMap, x: int, y: int) -> bool:
	## Does this cell of the shown deck (x, y on the deck) touch open space?
	for k in range(1, 5):
		var nx := x + Net.DX[k]
		var ny := y + Net.DY[k]
		if nx < 0 or ny < 0 or nx >= map.width or ny >= map.deck_height:
			return true
		if map.cells[(_deck_shown * _stride + ny) * map.width + nx] < 0:
			return true
	return false


func _light_kind(map: ShipMap, cell: int) -> int:
	## 0 = open space (never dark), 1 = our ship, 2 = a derelict (no light of its own).
	if map.cells[cell] < 0:
		return 0
	return 2 if client.dark_cell(cell) else 1


func _soft_circle(pen: Node2D, mid: Vector2, full: float, gone: float, colour: Color) -> void:
	## A disc in full colour out to `full`, fading to nothing by `gone`.
	pen.draw_circle(mid, full, colour)
	var ring := 24
	var none := Color(colour, 0.0)
	for k in ring:
		var a0 := Vector2.RIGHT.rotated(TAU * k / ring)
		var a1 := Vector2.RIGHT.rotated(TAU * (k + 1) / ring)
		pen.draw_polygon(PackedVector2Array([mid + a0 * full, mid + a0 * gone, mid + a1 * gone, mid + a1 * full]),
			PackedColorArray([colour, none, none, colour]))


func _update_fan() -> void:
	## Where the soft fan of the cone (CONE_SHADER) is drawn this frame, if at all.
	_fan_rect = Rect2()
	_cone_fan.queue_redraw()
	var me: Sprite2D = _views.get(client.my_id)
	if me == null or me.get_parent() != _decks[_deck_shown].chars or client.my_cond != Net.COND_OK:
		return
	var s := client.sample(client.my_id)
	if s.is_empty():
		return
	var facing: int = s[1]
	var origin := me.position + Vector2(0, -12)
	var half := 0.0
	for arc: Array in Sight.eye_arcs(false):
		half = maxf(half, maxf(absf(arc[0]), absf(arc[1])))
	var reach := (float(Sight.SIGHT_REACH) + 1.5) * _tile
	var m := _cone_fan.material as ShaderMaterial
	m.set_shader_parameter("origin", origin)
	m.set_shader_parameter("ahead", Vector2(Net.DX[facing], Net.DY[facing]))
	m.set_shader_parameter("half_field", deg_to_rad(half))
	m.set_shader_parameter("band", CONE_BAND * _tile)
	m.set_shader_parameter("spread", tan(deg_to_rad(CONE_SOFT)))
	m.set_shader_parameter("reach", reach)
	_fan_rect = Rect2(origin - Vector2(reach, reach) * 1.1, Vector2(reach, reach) * 2.2)


func _draw_cone() -> void:
	## The smooth cone (see _cone_view): the whole field of view as one soft fan
	## (CONE_SHADER), not cut by walls (the cells seen do that); and the pool all
	## round us, at full strength.
	var me: Sprite2D = _views.get(client.my_id)
	var white := Color(0, 1, 0, 1)
	if me == null or me.get_parent() != _decks[_deck_shown].chars or client.my_cond != Net.COND_OK:
		if me != null and client.my_cond != Net.COND_DEAD:
			_cone.draw_circle(me.position + Vector2(0, -12), _tile * 0.6, white)
		return
	_draw_light(_cone, _near, white, 0)


func _draw_look() -> void:
	## Green where our eyes reach: a cone from each eye, cut short by walls and
	## shut doors, and our own cell (somebody right behind us is felt, not seen).
	var me: Sprite2D = _views.get(client.my_id)
	if me == null or me.get_parent() != _decks[_deck_shown].chars or client.my_cond != Net.COND_OK:
		if me != null and client.my_cond != Net.COND_DEAD:
			_look.draw_circle(me.position + Vector2(0, -12), _tile * 0.6, Color(0, 1, 0, 1))
		return
	var s := client.sample(client.my_id)
	if s.is_empty():
		return
	var facing: int = s[1]
	var green := Color(0, 1, 0, 1)
	var origin := me.position + Vector2(0, -12)
	var ahead := Vector2(Net.DX[facing], Net.DY[facing])
	var start_cell := Vector2i(floori(origin.x / _tile), floori(origin.y / _tile))
	_look.draw_rect(Rect2(Vector2(start_cell) * _tile, Vector2(_tile, _tile)), green)   # our own cell, not the wall beside it
	_draw_light(_look, _near, Color(0, 1, 0, NEAR), 0)       # and dimly all round us, as in SS13
	var reach := float(Sight.SIGHT_REACH) * _tile
	# the whole field of view, in the dark too: there it only lets flashlights
	# and the dim light around us show (people in the dark: see can_see). It is
	# worked out LOOK_MARGIN wider each side: the smooth cone (_draw_cone) fades it
	# out along straight sides there, instead of cell by cell.
	var arcs: Array = []
	for arc: Array in Sight.eye_arcs(false):
		var lo := minf(arc[0], arc[1])
		var hi := maxf(arc[0], arc[1])
		arcs.append([lo - LOOK_MARGIN if lo < 0.0 else lo, hi + LOOK_MARGIN if hi > 0.0 else hi])
	var cells := {}                          # cells a look passes through or stops at
	for arc: Array in arcs:
		var points := PackedVector2Array([origin])
		for k in LOOK_RAYS + 1:
			var way := ahead.rotated(deg_to_rad(lerpf(float(arc[0]), float(arc[1]), float(k) / LOOK_RAYS)))
			var t := 0.0
			var was := Vector2i(-100000, 0)
			while t < reach:
				var at := origin + way * t
				var c := Vector2i(floori(at.x / _tile), floori(at.y / _tile))
				if c == was:
					t += 4.0                 # still in the cell looked at last: nothing new
					continue
				was = c
				cells[c] = true
				if c != start_cell and Sight.blocks(client.map, client.doors, c.x, c.y + _deck_shown * _stride):
					while t > 0.0 and Vector2i(((origin + way * (t - 1.0)) / _tile).floor()) == c:
						t -= 1.0             # back to the face of the wall, so no jagged strip pokes into it
					t = maxf(t - 1.0, 0.0)
					break
				t += 4.0
			points.append(origin + way * minf(t, reach))
		_look.draw_colored_polygon(points, green)
	# As in SS13, a cell whose middle is in the cone is seen whole: floor right up
	# to the walls, and the walls themselves; one off the edge of the cone (beside
	# or behind us) is seen only as far as the cone itself reaches into it. The
	# rays above are too sparse to touch every wall seen nearly edge on (a wall
	# far along a corridor), so every cell in the cone is also checked on its own:
	# floor whose middle can be seen, and a wall with a face turned to us on a
	# floor cell that is seen (v44, the author's screenshot).
	var at_t := origin / _tile
	var dy := _deck_shown * _stride
	var map := client.map
	var r := Sight.SIGHT_REACH
	var seen := {}                           # floor (and anything else see-through) seen
	var walls: Array[Vector2i] = []
	for y in range(start_cell.y - r, start_cell.y + r + 1):
		for x in range(start_cell.x - r, start_cell.x + r + 1):
			var c := Vector2i(x, y)
			var mid := Vector2(c) + Vector2(0.5, 0.5)
			if mid.distance_to(at_t) > r + 0.5 or not _in_arcs(ahead, (mid - at_t), arcs):
				continue
			if x < 0 or y < 0 or x >= map.width or y + dy >= map.height:
				continue
			if Sight.blocks(client.map, client.doors, x, y + dy):
				walls.append(c)
			elif cells.has(c) or (map.cells[(y + dy) * map.width + x] >= 0 and _clear_to(at_t, start_cell, c)):
				seen[c] = true
	var walls_seen: Array[Vector2i] = []
	for c: Vector2i in walls:
		if cells.has(c):
			walls_seen.append(c)
			continue
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			# the face between the wall and that floor cell is turned towards our eye
			var n := c + d
			var faces := false
			if d.x > 0:
				faces = at_t.x >= n.x
			elif d.x < 0:
				faces = at_t.x <= n.x + 1
			elif d.y > 0:
				faces = at_t.y >= n.y
			else:
				faces = at_t.y <= n.y + 1
			if faces and (seen.has(n) or (cells.has(n) and not Sight.blocks(map, client.doors, n.x, n.y + dy))):
				walls_seen.append(c)
				break
	for c: Vector2i in seen:
		_look.draw_rect(Rect2(Vector2(c) * _tile, Vector2(_tile, _tile)), green)
	for c: Vector2i in walls_seen:
		_look.draw_rect(Rect2(Vector2(c) * _tile, Vector2(_tile, _tile)), green)


static func _in_arcs(ahead: Vector2, v: Vector2, arcs: Array) -> bool:
	var angle := rad_to_deg(ahead.angle_to(v))
	for arc: Array in arcs:
		if angle >= minf(arc[0], arc[1]) and angle <= maxf(arc[0], arc[1]):
			return true
	return false


func _clear_to(from: Vector2, start: Vector2i, to: Vector2i) -> bool:
	## Can the eye at `from` (in cells of the deck shown) see the middle of the
	## cell `to`: does the straight line between them cross no wall or shut
	## door? (Cell by cell, so a line cannot slip between two cells' checks.)
	var target := Vector2(to) + Vector2(0.5, 0.5)
	var d := target - from
	var c := start
	var step := Vector2i(int(signf(d.x)), int(signf(d.y)))
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	if d.x != 0.0:
		t_max.x = ((c.x + (1 if d.x > 0.0 else 0)) - from.x) / d.x
		t_delta.x = 1.0 / absf(d.x)
	if d.y != 0.0:
		t_max.y = ((c.y + (1 if d.y > 0.0 else 0)) - from.y) / d.y
		t_delta.y = 1.0 / absf(d.y)
	var dy := _deck_shown * _stride
	for i in 64:
		if c == to:
			return true
		if t_max.x < t_max.y:
			c.x += step.x
			t_max.x += t_delta.x
		else:
			c.y += step.y
			t_max.y += t_delta.y
		if c != to and Sight.blocks(client.map, client.doors, c.x, c.y + dy):
			return false
	return false


func _my_dark() -> bool:
	## Is our character in the dark: a ship without power, or aboard a derelict?
	return _dark >= 0.5 or client.dark_cell(client.pred.y * client.map.width + client.pred.x)


func can_see(x: int, y: int) -> bool:
	## Can our character make out somebody at this cell (a cell on any deck:
	## one seen through a see-through floor counts as the cell above it)?
	var map := client.map
	var me := Vector2(client.pred.x, client.pred.y)
	if client.my_cond != Net.COND_OK:
		return false                         # out cold, or dead: nothing is seen
	var its_deck := map.deck_of(y)
	var on_ours := Vector2i(x, y - (its_deck - _deck_shown) * _stride)
	var dark := _my_dark()
	var arcs := Sight.eye_arcs(dark)
	if not dark and not client.dark_cell(y * map.width + x):
		return Sight.sees(map, client.doors, me, client.pred.facing, on_ours, arcs, Sight.SIGHT_REACH)
	if Vector2(on_ours).distance_to(me) <= Sight.DARK_REACH + 0.5 \
			and Sight.sees(map, client.doors, me, client.pred.facing, on_ours, arcs, Sight.DARK_REACH):
		return true
	return _lit.has(y * map.width + x) and Sight.sees(map, client.doors, me, client.pred.facing, on_ours, arcs, Sight.SIGHT_REACH)


func _on_heard(kind: int, x: int, y: int) -> void:
	## A sound reached us: it plays from where it was made. Air rushing out and
	## a cry also leave a mark there if we cannot see the place (the author kept
	## those two), the less exactly the further off.
	var map := client.map
	if kind <= 0 or kind >= SOUND_LOOK.size():
		return
	var seen := can_see(x, y)
	if map.deck_of(y) == client.my_deck():
		_audio.play(kind, _feet(Vector2(x, map.local_y(y))), Net.SOUND_RANGE[kind], not seen or _thin_air_here())
	if seen or (kind != Net.SOUND_HISS and kind != Net.SOUND_CRY):
		return
	var far := Vector2(x, y).distance_to(Vector2(client.pred.x, client.pred.y))
	if kind == Net.SOUND_STEP:
		# footsteps come often: one mark for a while for somebody walking about there
		for old: Array in _sounds:
			if int(old[0]) == kind and float(old[3]) > SOUND_SECONDS - STEP_MARK_GAP \
					and (old[1] as Vector2).distance_to(_feet(Vector2(x, map.local_y(y)))) < 3.0 * _tile:
				return
	var spread := far / 5.0
	var at := Vector2(x + randf_range(-spread, spread), map.local_y(y) + randf_range(-spread, spread))
	_sounds.append([kind, _feet(at) + Vector2(0, -14), map.deck_of(y), SOUND_SECONDS])
	if _sounds.size() > 24:
		_sounds.pop_front()


func _thin_air_here() -> bool:
	## Our character stands in thin air: what it hears is muffled.
	var cell := client.pred.y * client.map.width + client.pred.x
	return cell >= 0 and cell < client.air.size() and client.air[cell] < Net.AIR_FULL * 0.6


func _update_audio(delta: float) -> void:
	## Our own footsteps (the server does not send us those) and the engine's hum.
	var map := client.map
	var here := Vector2i(client.pred.x, client.pred.y)
	if here != _last_cell:
		# a vacuum carries no sound, our own steps included: out in space, or in a room
		# with no air left, they are not heard at all (the author's rule)
		var cell := here.y * map.width + here.x
		var in_air := cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR \
			and not map.floats(here.x, here.y)
		if _last_cell.x >= 0 and map.deck_of(_last_cell.y) == map.deck_of(here.y) and client.my_cond == Net.COND_OK and in_air:
			_audio.play(Net.SOUND_STEP, _feet(Vector2(here.x, map.local_y(here.y))), Net.SOUND_RANGE[Net.SOUND_STEP], _thin_air_here(), -7.0)
		_last_cell = here
	_hum_timer -= delta
	if _hum_timer > 0.0:
		return
	_hum_timer = 0.25
	var engine := -1
	for cell: int in map.engine.keys():
		if map.deck_of_cell(cell) == client.my_deck():
			engine = cell
	var cell_here := here.y * map.width + here.x
	var in_air := cell_here >= 0 and cell_here < client.air.size() and client.air[cell_here] >= Net.AIR_FULL * Net.SOUND_AIR
	var on := engine >= 0 and client.powered() and not client.broken.has(engine) and in_air and client.phase == GameClient.PLAYING
	var ex := engine % map.width
	var ey := engine / map.width + 1
	_audio.hum(on, _feet(Vector2(ex, map.local_y(ey))), on and (not can_see(ex, ey) or _thin_air_here()))


func _draw_sounds() -> void:
	## Each mark: rings spreading from where the sound was, and what it was.
	## A sound off the screen is marked at its edge, pointing the way.
	var font := ThemeDB.fallback_font
	var screen := get_viewport_rect().size
	var zoom := _camera.zoom.x
	for snd: Array in _sounds:
		if int(snd[2]) != _deck_shown:
			continue
		var kind: int = snd[0]
		var age := 1.0 - float(snd[3]) / SOUND_SECONDS
		var colour := SOUND_COLOUR[kind]
		var spot: Vector2 = (snd[1] - _camera.position) * zoom + screen * 0.5
		var margin := 34.0
		var inside := Rect2(Vector2(margin, margin + 40), screen - Vector2(2 * margin, 2 * margin + 140))
		var edge := spot.clamp(inside.position, inside.end)
		var off := not edge.is_equal_approx(spot)
		var fade := 1.0 - age
		for r in 2:
			var grow := fposmod(age * 1.6 + r * 0.5, 1.0)
			_sound_pen.draw_arc(edge, 6.0 + grow * 22.0, 0.0, TAU, 28, Color(colour, (1.0 - grow) * 0.8 * fade), 2.0)
		if off:
			var way := (spot - edge).normalized()
			var tip := edge + way * 16.0
			_sound_pen.draw_colored_polygon(PackedVector2Array([tip, edge + way.rotated(2.5) * 9.0, edge + way.rotated(-2.5) * 9.0]),
				Color(colour, 0.85 * fade))
		var word: String = SOUND_LOOK[kind]
		_sound_pen.draw_string_outline(font, edge + Vector2(-60, 26), word, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, 4, Color(0, 0, 0, 0.8 * fade))
		_sound_pen.draw_string(font, edge + Vector2(-60, 26), word, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(colour, fade))


func lit(cell: int) -> bool:
	## Can a character in this cell be made out by us (see can_see)?
	var map := client.map
	return can_see(cell % map.width, cell / map.width)


func _draw_fx(d: int) -> void:
	## The moving details of one deck. Next to a hole, streaks show the air rushing out.
	## Thin air itself is deliberately not drawn: a compartment without air looks
	## like any other, and only the pressure gauge tells (the author's decision).
	var map := client.map
	var pen := _decks[d].fx
	var now := Time.get_ticks_msec() / 1000.0
	# the engine: its light falls on the floor in front of it, so its state can be
	# read from across the room, or from the deck above through a glass floor
	for cell: int in map.engine.keys():
		if map.deck_of_cell(cell) != d:
			continue
		var ex := cell % map.width
		var ey := cell / map.width
		var at := _on_deck(cell)
		var down := client.broken.has(cell)
		var beat := 0.8 + 0.2 * sin(now * 3.0) if not down else (1.0 if fposmod(now, 1.2) < 0.6 else 0.3)
		var light := Color(1.0, 0.16, 0.1) if down else Color(0.15, 0.95, 1.0)
		for dy in [1, 2]:
			for dx in [-1, 0, 1]:
				if map.walkable(ex + dx, ey + dy):
					var share := (0.5 if dx == 0 else 0.28) * (1.0 if dy == 1 else 0.6)
					pen.draw_rect(Rect2((at + Vector2(dx, dy)) * _tile, Vector2(_tile, _tile)), Color(light, share * beat))
		if not down:
			pen.draw_circle(at * _tile + Vector2(16.0, 14.0), 1.5 + beat * 1.5, Color(1, 1, 1, 0.55))
	# the air plant: while it works, air can be seen coming out of it
	for cell: int in map.air_plant.keys():
		if map.deck_of_cell(cell) != d or client.broken.has(cell) or not client.powered() or client.store_air <= 0.0:
			continue
		var out_cell: int = map.air_plant[cell]
		var way := 1.0 if out_cell > cell else -1.0
		var mouth := _on_deck(cell) * _tile + Vector2(16.0, 22.0 if way > 0.0 else 6.0)
		for k in 7:
			var seed_a := float((cell * 7 + k * 37) % 53) / 53.0
			var phase := fposmod(now * (0.7 + seed_a * 0.5) + seed_a * 3.0, 1.0)
			var from := mouth + Vector2((float(k) - 3.0) * 2.6, way * phase * 26.0)
			pen.draw_line(from, from + Vector2(0.0, way * 4.0), Color(0.75, 0.9, 1.0, 0.5 * (1.0 - phase)), 1.0)
	# emergency shutters that are down: a striped plate across the doorway and,
	# on each side of it, a lamp showing the pressure there. This is the one
	# place the ship shows where the air is (the author asked for exactly that).
	var lit := client.powered()
	for door in map.doors.size():
		var cell_at: Vector2i = map.doors[door]
		if not map.door_here(door) or map.deck_of(cell_at.y) != d:
			continue
		var corner := Vector2(cell_at.x, map.local_y(cell_at.y)) * _tile
		var band := map.door_kind[door] == ShipMap.DOOR_BAND
		var sealed := client.doors.is_sealed(door)
		var faulty := client.doors.faulty[door] == 1
		if client.doors.jammed[door] == 1:
			# stuck open: its works throw sparks on both sides of the opening
			var beat := int(now * 9.0) + door * 5
			for side in 2:
				if (beat + side) % 3 == 0:
					continue
				var from := corner + (Vector2(9 if side == 0 else 24, 10 + (beat * 5) % 14) if band else Vector2(13 + (beat * 5) % 6, 3 if side == 0 else 24))
				var to := from + Vector2(((beat * 13) % 7) - 3, ((beat * 11) % 7) - 3)
				pen.draw_line(from, to, Color(1.0, 0.9, 0.4, 0.95), 1.0)
				pen.draw_rect(Rect2(to, Vector2(1, 1)), Color(1, 1, 1))
		if faulty and not sealed and lit and fposmod(now + door * 0.37, 1.0) < 0.5:
			# a shutter that will not drop: a warning lamp blinks on the door frame
			var lamp_at := corner + (Vector2(15, 4) if band else Vector2(8, 26))
			pen.draw_rect(Rect2(lamp_at - Vector2(1, 1), Vector2(5, 5)), Color(0.05, 0.05, 0.08))
			pen.draw_rect(Rect2(lamp_at, Vector2(3, 3)), Color(1.0, 0.55, 0.1))
		var needs := map.door_access[door]
		if needs != 0 and lit and client.doors.dead[door] == 0:
			# the lock of a restricted room: a lamp on the frame, green when our job opens it
			var ours := (client.pred.access & needs) != 0
			var lock_at := corner + (Vector2(3, 14) if band else Vector2(14, 1))
			pen.draw_rect(Rect2(lock_at - Vector2(1, 1), Vector2(5, 5)), Color(0.05, 0.05, 0.08))
			pen.draw_rect(Rect2(lock_at, Vector2(3, 3)), Color(0.25, 0.9, 0.4) if ours else Color(1.0, 0.25, 0.2))
		if not sealed:
			continue
		var plate := Rect2(corner + Vector2(8, 9), Vector2(20, 14)) if band else Rect2(corner + Vector2(12, 3), Vector2(8, 21))
		pen.draw_rect(plate, Color(0.16, 0.15, 0.2))
		for row in int(plate.size.y):                     # warning stripes, slanted
			var from := -float(row % 6)
			while from < plate.size.x:
				var x0 := maxf(from, 0.0)
				var x1 := minf(from + 3.0, plate.size.x)
				if x1 > x0:
					pen.draw_rect(Rect2(plate.position + Vector2(x0, row), Vector2(x1 - x0, 1)), Color(0.93, 0.72, 0.18))
				from += 6.0
		pen.draw_rect(plate, Color(0.05, 0.05, 0.08), false, 1.0)
		for side in 2:
			var side_cell := map.door_sides[door * 2 + side]
			if side_cell < 0:
				continue
			var level := client.air[side_cell]
			var lamp := Color(0.25, 0.9, 0.4) if level >= Net.AIR_FULL * 0.76 else (Color(0.98, 0.8, 0.2) if level >= Net.AIR_FULL * 0.2 else Color(1.0, 0.25, 0.2))
			if not lit:
				lamp = Color(0.3, 0.31, 0.36)
			elif faulty:
				# a faulty shutter does not know the pressure: both lamps blink amber
				lamp = Color(1.0, 0.55, 0.1) if fposmod(now + door * 0.37, 1.0) < 0.5 else Color(0.3, 0.31, 0.36)
			var spot: Vector2
			if band:
				spot = corner + Vector2(15, 4 if side == 0 else 25)
			else:
				spot = corner + Vector2(8 if side == 0 else 21, 26)
			pen.draw_rect(Rect2(spot - Vector2(1, 1), Vector2(5, 5)), Color(0.05, 0.05, 0.08))
			pen.draw_rect(Rect2(spot, Vector2(3, 3)), lamp)
	# something out of order: its face is dark and it throws sparks
	for cell: int in client.broken.keys():
		if map.deck_of_cell(cell) != d:
			continue
		var corner := _on_deck(cell) * _tile
		pen.draw_rect(Rect2(corner + Vector2(7, 9), Vector2(18, 13)), Color(0.02, 0.02, 0.04, 0.82))
		var beat := int(now * 9.0) + cell
		if beat % 3 != 0:
			var from := corner + Vector2(10 + (beat * 7) % 12, 12 + (beat * 5) % 8)
			var to := from + Vector2(((beat * 13) % 9) - 4, ((beat * 11) % 9) - 2)
			pen.draw_line(from, to, Color(1.0, 0.9, 0.4, 0.95), 1.0)
			pen.draw_rect(Rect2(to, Vector2(1, 1)), Color(1, 1, 1))
	for cell: int in client.holes.keys():
		if map.deck_of_cell(cell) != d:
			continue
		var hx := cell % map.width
		var hy := cell / map.width           # in the map's grid: that is where the air is looked up
		var ly := map.local_y(hy)            # on its deck: that is where it is drawn
		var hole_at := Vector2(hx + 0.5, ly + 0.5) * _tile
		for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var a := client.air_at(hx + o.x, hy + o.y)
			if a <= 2:
				continue
			var strength := float(a) / Net.AIR_FULL
			var from_cell := Vector2(hx + o.x + 0.5, ly + o.y + 0.5) * _tile
			for k in 6:
				# each streak starts at its own spot around the cell and flies into the hole
				var seed_a := float((cell * 31 + k * 17) % 97) / 97.0
				var seed_b := float((cell * 13 + k * 29) % 89) / 89.0
				var start := from_cell + Vector2(seed_a - 0.5, seed_b - 0.5) * _tile * 1.6 + Vector2(o) * _tile * 0.5
				var phase := fposmod(now * (1.4 + seed_b) + seed_a, 1.0)
				var head := start.lerp(hole_at, phase)
				var tail := start.lerp(hole_at, maxf(phase - 0.16, 0.0))
				pen.draw_line(tail, head, Color(0.86, 0.92, 1.0, 0.55 * strength * (1.0 - phase * 0.5)), 1.0)


func _process(delta: float) -> void:
	if client == null or client.phase != GameClient.PLAYING:
		return
	var map := client.map
	# The screen shows at least VIEW_CELLS cells either side of us across (v46,
	# the author: 9, as in SS13), at a whole zoom so the pixels stay crisp.
	var zoom := clampf(floorf(get_viewport_rect().size.x / ((2 * VIEW_CELLS + 1) * _tile)), 1.0, 6.0)
	_camera.zoom = Vector2(zoom, zoom)
	_update_ship(delta)
	_update_audio(delta)
	var my_deck := client.my_deck()
	if my_deck != _deck_shown:
		_arrange(my_deck)
	var shift := -client.ship_pos() * STAR_PIXELS_PER_UNIT
	if not shift.is_equal_approx(_star_shift):
		_star_shift = shift
		queue_redraw()

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
		var cond: int = s[4]
		# which deck it is on, and where on that deck
		var its_deck := clampi(int(floorf((pos.y + 0.5) / _stride)), 0, _decks.size() - 1)
		pos.y -= its_deck * _stride
		var home := _decks[its_deck].chars
		if sprite.get_parent() != home:
			if sprite.get_parent() != null:
				sprite.get_parent().remove_child(sprite)
			home.add_child(sprite)
		# Through a floor: below us everybody is drawn and the floor above them
		# hides what it should; above us only those on a see-through floor show.
		var cell_x := clampi(roundi(pos.x), 0, map.width - 1)
		var cell_y := its_deck * _stride + clampi(roundi(pos.y), 0, map.deck_height - 1)
		var seen := client.seen_from(my_deck, cell_x, cell_y)
		_seen[id] = seen
		# out of our field of view (or in the dark) nobody is seen
		# (and the one we haul along behind us is always felt there)
		var hauled := client.dragging() and id == client.drag_id
		sprite.visible = id == client.my_id or hauled or ((its_deck > my_deck or seen) and can_see(cell_x, cell_y))
		if bool(_shown.get(id, false)) and not sprite.visible and id != client.my_id:
			_leave_afterimage(id, sprite, Vector2i(roundi(sprite.position.x), roundi(sprite.position.y)))
		_shown[id] = sprite.visible
		sprite.position = (_feet(pos) * zoom).round() / zoom   # on a whole screen pixel
		sprite.region_rect = _frame(s[1], s[2] and cond == Net.COND_OK, pos, client.player_colour(id) * Net.LOOKS + client.look_of(id))
		if cond == Net.COND_OK:
			sprite.rotation = 0.0
			sprite.modulate = Color.WHITE
		else:
			# on the floor: the figure is turned on its side and slid back over its tile
			sprite.rotation = PI / 2.0
			sprite.position += Vector2(-22.0, -7.0)
			sprite.modulate = Color(0.55, 0.55, 0.6) if cond == Net.COND_DEAD else Color(0.85, 0.85, 0.88)
	_fade_afterimages(delta)
	for id: int in _views.keys():
		if not client.ents.has(id):
			if bool(_shown.get(id, false)) and client.hidden.has(id) and id != client.my_id:
				# the server stopped telling us about it the moment we lost sight of it
				var gone_sprite: Sprite2D = _views[id]
				_leave_afterimage(id, gone_sprite, Vector2i(roundi(gone_sprite.position.x), roundi(gone_sprite.position.y)))
			_shown.erase(id)
			(_views[id] as Sprite2D).queue_free()
			(_labels[id] as Label).queue_free()
			_views.erase(id)
			_labels.erase(id)
			_seen.erase(id)

	# camera follows our character; a ship smaller than the screen stays centred
	var me: Sprite2D = _views.get(client.my_id)
	# what our eyes reach is worked out again only when something it depends on changed
	var mine_now := client.sample(client.my_id)
	var look_key := hash([me.position if me != null else Vector2.INF, me != null and me.get_parent() == _decks[my_deck].chars,
		mine_now[1] if not mine_now.is_empty() else 0, my_deck, client.my_cond, hash(client.doors.ready), client.other_changes])
	if look_key != _look_key:
		_look_key = look_key
		_look.queue_redraw()
		_cone.queue_redraw()
	_me_over.visible = me != null and me.get_parent() == _decks[my_deck].chars and client.my_cond != Net.COND_DEAD
	if _me_over.visible:
		_me_over.global_transform = me.global_transform
		_me_over.region_rect = me.region_rect
		_me_over.modulate = me.modulate * Color(0.8, 0.8, 0.85)
	var focus := me.position - Vector2(0, 14) if me != null else Vector2.ZERO
	var half := get_viewport_rect().size / zoom * 0.5
	var map_size := Vector2(map.width, map.deck_height) * _tile
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
	# the picture of where light falls follows the camera exactly
	_mask_view.size = Vector2i(get_viewport_rect().size)
	_mask_camera.position = _camera.position
	_mask_camera.zoom = _camera.zoom
	_cone_view.size = _mask_view.size
	_cone_camera.position = _camera.position
	_cone_camera.zoom = _camera.zoom

	# name tags are drawn in screen space so the text stays sharp
	var screen_centre := get_viewport_rect().size * 0.5
	for id: int in _labels.keys():
		var label: Label = _labels[id]
		# a name does not give away somebody the floor or the dark hides
		# (exactly when the character itself is shown: the same place, the same moment)
		label.visible = show_names and bool(_seen.get(id, false)) and _views.has(id) and (_views[id] as Sprite2D).visible
		if label.visible:
			var sprite: Sprite2D = _views[id]
			label.text = client.player_name(id)
			var lying: bool = sprite.rotation != 0.0
			if lying:
				label.modulate = Color(0.75, 0.5, 0.5)
			elif id == client.my_id:
				label.modulate = Color(0.6, 1.0, 0.7)
			elif client.is_pirate(id):
				label.modulate = Color(1.0, 0.45, 0.35)
			elif client.is_bot(id):
				label.modulate = Color(0.72, 0.76, 0.86)
			else:
				label.modulate = Color(1, 1, 1)
			if sprite.get_parent() != _decks[my_deck].chars:
				label.modulate.a = 0.55          # on another deck
			var above := Vector2(22, 7 - 20) if lying else Vector2(0, 6 - CHAR_H)
			var top := (sprite.position + above - _camera.position) * zoom + screen_centre
			label.position = (top - Vector2(label.size.x * 0.5, label.size.y)).round()

	# debug: the server's idea of where we are
	var mine: GameClient.Ent = client.ents.get(client.my_id)
	_ghost.visible = show_ghost and mine != null and map.deck_of(mine.y) == my_deck
	if _ghost.visible:
		_ghost.position = _feet(Vector2(mine.x, map.local_y(mine.y)))
		_ghost.region_rect = _cell(FACING_COLUMN.get(mine.facing, 0), client.player_colour(client.my_id) * Net.LOOKS + client.look_of(client.my_id))
