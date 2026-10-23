extends Node2D
## Draws the ship and everyone on it, and keeps the camera on our character.
## It only reads from the GameClient; it never changes game state.
##
## Every deck is drawn in the same place on the screen. The deck our
## character is on is drawn in full; the decks under it are drawn first and
## darker, so they show wherever the floor above is glass, a catwalk or a
## hatch; of the deck above only its see-through floors are hinted, with
## whoever stands on them.

const RED_ALERT_DIM := 0.3           # (v68) how far a red alert dims the lights (0 lit .. 1 dark)
const EMERGENCY_DIM := 0.67          # (v80, the author's note and his P2 "1/3?") the engine down, the SMES carrying the ship: a third of the light
const Net := preload("res://src/shared/net.gd")
const Plants := preload("res://src/shared/plants.gd")
const Sight := preload("res://src/shared/sight.gd")
const Mover := preload("res://src/shared/mover.gd")
const GameClient := preload("res://src/client/game_client.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const ItemArt := preload("res://src/client/item_art.gd")
const Sounds := preload("res://src/client/sounds.gd")
const Options := preload("res://src/client/options.gd")
const FightFx := preload("res://src/client/fight_fx.gd")
const Sprites := preload("res://src/client/sprites.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Music := preload("res://src/client/music.gd")

const CHAR_W := 32
const CHAR_H := 48
const CHAR_PAD := 1                  # transparent border around every frame in assets/chars.png
const FEET_Y := 29                   # where the feet rest inside a tile, in pixels from its top
const LIE_TURN := 0.2                # (v82) seconds to turn over lying down or getting up
const PRONE_CENTRE := Vector2(0, -8)  # (v79) the middle of a body lying low, from where its feet would stand
# column of the first frame for each facing in assets/chars.png (down, up, left, right;
# v74: then down-left, down-right, up-left, up-right)
const FACING_COLUMN := {1: 3, 2: 0, 3: 6, 4: 9, 5: 18, 6: 21, 7: 12, 8: 15}
# (v74) where the hand is, from the feet, for each facing (the thing held is drawn there)
const HAND_AT := {1: Vector2(-8, -17), 2: Vector2(8, -17), 3: Vector2(-5, -16), 4: Vector2(5, -16),
	5: Vector2(-7, -17), 6: Vector2(7, -17), 7: Vector2(-7, -17), 8: Vector2(7, -17)}
const HAND_SIZE := 12.0

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
const SOUND_LOOK := ["", "шаги", "дверь", "шипение", "падение", "стук", "лестница", "выстрел", "удар", "крик",
	"прыжок", "заряжание", "взрыв", "писк", "выстрел", "разряд",   # (v75: the kinds from 10 on were never played)
	"щелчок", "перезарядка", "взял", "взмах"]   # (v82; v84 the swing)
const HIT_FLASH := 0.25              # (v75, the author's F1) seconds a hurt figure shows red
const CASING_SECONDS := 30.0         # (v82) how long a spent casing lies on the floor
const CASING_FADE := 3.0             # and the last seconds of it, fading
const CASINGS_KEPT := 120
const HURT_SHAKE := 3.0              # (v82) screen pixels the picture shakes when we are hurt
const KICK_PX := 4.0                 # (v82) how far our own shot throws the camera back (a shotgun twice that); (v83) was 2.5
const KICK_SHAKE := 1.6              # (v83, his video) and how hard our own shot shakes the picture (a shotgun twice that)
const STAINS_KEPT := 400             # (v75) drops of blood kept on the floors (the oldest go first)
const RED_ALERT_TINT := 0.1          # (v75, the author's F3) how red the light is at red alert (it pulses round this)
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
var hover := true                    # outline what the mouse is over (off while a screen is open)
var hover_test := Vector2.INF       # (test helper) the mouse is taken to be this far from our character, in cells
var _hover_pen: Node2D               # above the dark too: the outline of the thing under the mouse
var _hover_on := Vector2i(-1, 0)     # [its cell, 1 = within reach] as drawn
var _rise_shown := false             # (v82) the getting-up bar is on
var _ring_pen: Node2D                # (v73) the ring that fills over the thing we work on
var _ring_shown := false
var _work_was := 0                   # (v82, his F1 note) the job's share last frame, for its ticks and its "done"
var _work_tick_at := 0.0             # and when the next tick sounds
var _hand_was := -1                  # (v82) the hand's slot last frame: a flick when it changes
var _healing: Array[int] = []        # (v82, his D2 note) ids lying in a working autodoc: a green cross pulses over them
var zoom_step := 0                   # (v73, the author's H6) Ctrl+wheel: one whole zoom step closer or farther
var _hover_ink: Node2D               # under _hover_pen: the silhouettes of things on the floor, drawn round them
var _body_ink: Sprite2D              # on a body under the mouse: its outline (OUTLINE_SHADER)
var _tile_lines := {}                # tile id -> the outline of the thing fitted into that wall tile (null: none)
var _tiles_image: Image              # the tile atlas, to find those outlines in
var _stars := PackedVector2Array()
var _star_sizes := PackedByteArray()
var _star_origin := Vector2.ZERO     # corner and size of the patch of sky the stars are scattered over
var _star_field := Vector2.ONE
var _star_shift := Vector2.ZERO      # how far the sky has slid: follows the ship's place in its sector
# The outline under the mouse (v54): things on the floor are drawn again in its
# colour a pixel out each of four ways (SILHOUETTE); a body's figure is copied, drawing
# only the pixels just outside it (OUTLINE).
const SILHOUETTE_SHADER := """shader_type canvas_item;
uniform vec4 ink : source_color;
void fragment() { COLOR = vec4(ink.rgb, ink.a * COLOR.a); }
"""
const OUTLINE_SHADER := """shader_type canvas_item;
uniform vec4 ink : source_color;
void fragment() {
	float near = 0.0;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			if (i * j == 0) {
				near = max(near, texture(TEXTURE, UV + vec2(float(i), float(j)) * TEXTURE_PIXEL_SIZE).a);
			}
		}
	}
	float own = texture(TEXTURE, UV).a;
	COLOR = vec4(ink.rgb, own > 0.5 ? 0.0 : ink.a * step(0.5, near));
}
"""
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
var _fight := FightFx.new()          # (v56) the ships' shots flying and bursting
var _alert_heard := -1               # (v68) client.alert_changes as last sounded (-1: not yet in the game)
var _shake := 0.0                    # (v56) how far the screen is thrown now, in screen pixels (dies away)
var _mask_camera: Camera2D
var _dark_layer: CanvasLayer
var _dark_sheet: ColorRect
const AFTERIMAGE_SECONDS := 10.0                # how long the silhouette of somebody lost from sight stays
var _afterimages := {}               # id -> [Sprite2D, seconds left, the cell it was last seen in]
var _shown := {}                     # id -> was it shown last frame
var _lean := Vector2.ZERO             # (v79) how far the camera leans toward the mouse now, in pixels
var lean_on := true                  # (v79) GameScreen turns it off while a console or window is open
const LEAN_EASE := 6.0
var _pass_side := {}                 # (v79) Vector2i(id, id) -> the side two passing people step to
const PASS_REACH := 1.0              # (v79) how near, in tiles, two people step aside for each other
var _other_seen := 0                 # GameClient.other_changes when the tiles were last laid
var _dark := 0.0                     # 0 = the lights are on, 1 = no power: eased, so it fades
var _flash := {}                     # (v75) id -> seconds left of its red flash after a wound
var _lie := {}                       # (v82) id -> 0 standing .. 1 lying: how far over the body is turned
var _prone_side := {}                # (v80) id -> 1.0 or -1.0: the side a body lying low has its head to
var _stand := {}                     # (v83) id -> where its feet are drawn (pixels on its deck), whether it stands or lies
var _casings: Array = []             # (v82) spent casings: [deck, position on its deck, angle, cell, seconds left]
var _kick := Vector2.ZERO            # (v82) the camera thrown back by our own shot (pixels), easing home
var _last_spent := -1000             # (v82) when the last bullet was seen fired (msec), and from where:
var _spent_from := Vector2.INF       # a shotgun's pellets come together and leave one casing
var _stains: Array = []              # (v75) blood on the floor: [deck, position on its deck (pixels), radius, (v80) cell]
var _sparks: Array = []              # (v75) sparks off a robot hit: [deck, position, seconds left]
var _alert_tint: ColorRect           # (v75) red light over the world at red alert
var _red := 0.0                      # how red it is now (eased)
var _amb_timer := 6.0                # (v75, the author's F5) seconds to the next sound of the ship itself
var _jumps_heard := -1               # client.jumps as last heard (the hull creaks after a jump)
var _creak_in := -1.0                # seconds to that creak (-1: none due)
var _boarders_until := 0.0           # (v75) the fight music keeps on this long after a pirate was last seen aboard


func setup(p_client: GameClient) -> void:
	client = p_client
	var map := client.map
	_tile = map.tile_size
	_stride = map.deck_stride
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chars_tex = Sprites.sheet("chars")
	_breach_tex = Sprites.sheet("breach")

	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(_tile, _tile)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = Sprites.sheet("tiles")
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
	_alert_tint = ColorRect.new()
	_alert_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_alert_tint.color = Color(1.0, 0.08, 0.04, 0.0)
	_dark_layer.add_child(_alert_tint)
	# We always see ourselves, even in pitch dark (without the glow around us
	# the author asked to be rid of): a copy of our figure over the dark.
	_me_layer = CanvasLayer.new()
	_me_layer.layer = 2
	_me_layer.follow_viewport_enabled = true
	add_child(_me_layer)
	_hover_pen = Node2D.new()
	_hover_pen.draw.connect(_draw_hover)
	_me_layer.add_child(_hover_pen)
	_hover_pen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hover_ink = Node2D.new()
	_hover_ink.show_behind_parent = true
	_hover_ink.material = _ink_material(SILHOUETTE_SHADER)
	_hover_ink.draw.connect(_draw_hover_ink)
	_hover_pen.add_child(_hover_ink)
	_ring_pen = Node2D.new()
	_ring_pen.draw.connect(_draw_ring)
	_me_layer.add_child(_ring_pen)
	_body_ink = Sprite2D.new()
	_body_ink.texture = _chars_tex
	_body_ink.region_enabled = true
	_body_ink.centered = false
	_body_ink.material = _ink_material(OUTLINE_SHADER)
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
	client.hit.connect(_on_hit)
	_audio = Sounds.new()
	add_child(_audio)
	client.shot.connect(_on_shot)
	client.jolt.connect(_on_jolt)

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


func _my_spot(me: Sprite2D) -> Vector2:
	## (v83) Where our own feet stand on the deck, in pixels. Lying down turns the figure over but leaves
	## the camera, the eyes and the light where they were (the drawn body moves; we do not).
	return _stand.get(client.my_id, me.position)


func _feet(pos_tiles: Vector2) -> Vector2:
	## Where the feet of a character at this place of its deck are, in pixels.
	return Vector2(pos_tiles.x * _tile + _tile * 0.5, pos_tiles.y * _tile + FEET_Y)


func _passing(samples: Dictionary) -> Dictionary:
	## (v79, his W1 note) People walk through one another; two standing close are drawn stepping
	## aside, each up to a quarter of a tile off its line, as if sliding past. Only the picture moves.
	var out := {}
	var ids: Array = samples.keys()
	ids.sort()
	for i in ids.size():
		var a: Array = samples[ids[i]]
		if int(a[4]) != Net.COND_OK or client.prone_of(ids[i]):
			continue
		for j in range(i + 1, ids.size()):
			var b: Array = samples[ids[j]]
			if int(b[4]) != Net.COND_OK or client.prone_of(ids[j]):
				continue
			var apart: Vector2 = b[0] - a[0]
			var d := apart.length()
			# two standing still chose their spots: they stay as they are
			if d >= PASS_REACH or not (bool(a[2]) or bool(b[2]) or _pass_side.has(Vector2i(ids[i], ids[j]))):
				_pass_side.erase(Vector2i(ids[i], ids[j]))
				continue
			# sideways to the line between them; kept from the last frame once they stand on one spot
			var side: Vector2 = _pass_side.get(Vector2i(ids[i], ids[j]), Vector2.ZERO)
			if d > 0.05:
				side = Vector2(-apart.y, apart.x) / d
				_pass_side[Vector2i(ids[i], ids[j])] = side
			elif side == Vector2.ZERO:
				side = Vector2.RIGHT
			var push := side * _tile * 0.25 * (1.0 - d / PASS_REACH)
			out[ids[i]] = (out.get(ids[i], Vector2.ZERO) - push).limit_length(_tile * 0.25)
			out[ids[j]] = (out.get(ids[j], Vector2.ZERO) + push).limit_length(_tile * 0.25)
	return out


func _frame(facing: int, moving: bool, pos_tiles: Vector2, colour: int) -> Rect2:
	var column: int = FACING_COLUMN.get(facing, 0)
	if moving:
		# alternate the two step poses tile by tile, switching in the middle of a slide
		column += 1 + (int(floorf(pos_tiles.x + pos_tiles.y + 0.5)) & 1)
	return _cell(column, colour)


class HandArt extends Node2D:
	## (v74, the author's N6) The thing in a character's hand, drawn on the figure (the small
	## picture the inventory shows, or the «sprites» folder's).
	var item := 0

	func _draw() -> void:
		if item != Net.ITEM_NONE:
			ItemArt.draw(self, Rect2(-HAND_SIZE * 0.5, -HAND_SIZE * 0.5, HAND_SIZE, HAND_SIZE), item)


func _hold(sprite: Sprite2D, facing: int, item: int) -> void:
	## Puts the thing held where the figure's hand is for that facing: behind the figure when
	## it faces away from us.
	var hand: HandArt = sprite.get_node_or_null("hand")
	if hand == null:
		if item == Net.ITEM_NONE:
			return
		hand = HandArt.new()
		hand.name = "hand"
		sprite.add_child(hand)
	hand.visible = item != Net.ITEM_NONE
	if not hand.visible:
		return
	if hand.item != item:
		hand.item = item
		hand.queue_redraw()
	hand.position = HAND_AT.get(facing, HAND_AT[Net.DIR_DOWN])
	hand.show_behind_parent = facing == Net.DIR_UP or facing == Net.DIR_UP_LEFT or facing == Net.DIR_UP_RIGHT


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
	# (v61) the bridge backup lights its room; (v68) the lights' breaker off is dark, a red alert dims them
	var lit_here := client.light_at(client.pred.y * map.width + client.pred.x)
	# (v80, the author's note: "the lights do not go out in a blackout") with the engine down the SMES keeps
	# the ship going, but only on emergency light: a third of the light (the backup-lit bridge stays as it was)
	var emergency := int(client.power_mon.get("flags", 0)) & 4 != 0 and not map.on_backup(client.pred.y * map.width + client.pred.x)
	var lit_dim := maxf(RED_ALERT_DIM if client.alert == Net.ALERT_RED else 0.0, EMERGENCY_DIM if emergency else 0.0)
	_dark = move_toward(_dark, lit_dim if lit_here else 1.0, delta * 2.5)
	# (v75, the author's F3) at red alert the ship's lights turn a dim, slowly pulsing red
	var now_s := Time.get_ticks_msec() / 1000.0
	var red_alert := client.alert == Net.ALERT_RED and lit_here and map.on_ship(client.pred.y * map.width + client.pred.x)
	_red = move_toward(_red, 1.0 if red_alert else 0.0, delta * 1.5)
	_alert_tint.color.a = _red * RED_ALERT_TINT * (0.75 + 0.25 * sin(now_s * 2.2))
	for id: int in _flash.keys():
		_flash[id] = float(_flash[id]) - delta
		if float(_flash[id]) <= 0.0:
			_flash.erase(id)
	for i in range(_sparks.size() - 1, -1, -1):
		_sparks[i][2] = float(_sparks[i][2]) - delta
		if float(_sparks[i][2]) <= 0.0:
			_sparks.remove_at(i)
	_lit = client.lit_cells()
	_dim = _find_dim()
	_near = _find_near()
	_shade.queue_redraw()
	(_dark_sheet.material as ShaderMaterial).set_shader_parameter("dark", DARK)
	# where light falls is drawn again only when it may have changed
	var mask_key := hash([_dark, _deck_shown, client.my_deck(), client.my_cond, client.other_changes, client.other_dark(),
		_dim.hash(), _near.hash(), _lit.hash()])
	_fight.update(delta)
	if mask_key != _mask_key or not _shots.is_empty() or _fight.busy():
		_mask_key = mask_key
		_mask.queue_redraw()
	for i in range(_shots.size() - 1, -1, -1):
		_shots[i][5] -= delta
		if float(_shots[i][5]) <= 0.0:
			_shots.remove_at(i)
	for i in range(_casings.size() - 1, -1, -1):
		_casings[i][4] -= delta
		if float(_casings[i][4]) < CASING_FADE:
			_decks[int(_casings[i][0])].things.queue_redraw()
		if float(_casings[i][4]) <= 0.0:
			_casings.remove_at(i)
	for i in range(_sounds.size() - 1, -1, -1):
		_sounds[i][3] -= delta
		if float(_sounds[i][3]) <= 0.0:
			_sounds.remove_at(i)
	_sound_pen.queue_redraw()


func _draw_things(d: int) -> void:
	## Things lying on the floor of one deck.
	var map := client.map
	var pen := _decks[d].things
	# (v75, the author's F1) blood where somebody was hurt, under everything
	for st: Array in _stains:
		if int(st[0]) == d and map.walk[int(st[3])] == 1:      # (v80) not where a ship alongside has gone from
			pen.draw_circle(st[1], float(st[2]), Color(0.42, 0.02, 0.03, 0.85))
	# (v82) spent casings, fading out at the end
	for c: Array in _casings:
		if int(c[0]) == d and map.walk[int(c[3])] == 1:
			var lie := Vector2.from_angle(float(c[2])) * 2.0
			pen.draw_line(c[1] - lie, c[1] + lie, Color(0.86, 0.66, 0.26, clampf(float(c[4]) / CASING_FADE, 0.0, 1.0)), 1.5)
	# (v69) each room's air vent: a grille in the floor, under whatever lies on it
	for cell: int in map.vents:
		if map.deck_of_cell(cell) != d:
			continue
		var at := _on_deck(cell) * _tile + Vector2(8, 11)
		pen.draw_rect(Rect2(at - Vector2(1, 1), Vector2(18, 12)), Color(0.12, 0.13, 0.15))
		pen.draw_rect(Rect2(at, Vector2(16, 10)), Color(0.32, 0.35, 0.38))
		for k in 4:
			pen.draw_rect(Rect2(at + Vector2(1, 1 + k * 2.5), Vector2(14, 1.2)), Color(0.08, 0.09, 0.1))
	for cell: int in client.floor_things.keys():
		if map.deck_of_cell(cell) != d:
			continue
		_floor_things_at(pen, cell, _on_deck(cell) * _tile)


func _floor_things_at(pen: CanvasItem, cell: int, corner: Vector2) -> void:
	## The things lying in one cell: one in the middle, several side by side.
	var here := PackedByteArray()
	for v in client.floor_things.get(cell, PackedByteArray()):
		if v != Net.ITEM_NONE:
			here.append(v)
	if here.size() == 1:
		ItemArt.draw(pen, Rect2(corner + Vector2(7, 9), Vector2(18, 18)), here[0])
		return
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




func _on_shot(kind: int, hit: int, from: Vector2, to: Vector2, delay: float, flight: float, by := -1) -> void:
	var map := client.map
	var deck := map.deck_of(clampi(roundi(from.y), 0, map.height - 1))
	if kind >= Net.SHOT_CANNON and kind != Net.SHOT_FLASH:
		# (v56) a ship's gun: it flies, then bursts (FightFx); drawn at the middle of the cells
		var lift := Vector2(_tile * 0.5, _tile * 0.5)
		_fight.add(kind, hit, Vector2(from.x, from.y - deck * _stride) * _tile + lift, Vector2(to.x, to.y - deck * _stride) * _tile + lift,
			deck, delay, flight)
		return
	var a := _feet(Vector2(from.x, from.y - deck * _stride)) + Vector2(0, -16)
	var b := _feet(Vector2(to.x, to.y - deck * _stride)) + Vector2(0, -16)
	# (v83, his video: "when you move, shots spawn behind") the server tells where the shooter stood when
	# it fired, which for a walker is behind where we draw him (ourselves: ahead by the ping; others: a
	# little behind or ahead). The trace starts where he is drawn, the end stays where it landed.
	var at_px := a + Vector2(0, 16)
	if _stand.has(by) and (_views[by] as Sprite2D).get_parent() == _decks[deck].chars:
		at_px = _stand[by]
		a = at_px + Vector2(0, -16)
	if kind == Net.SHOT_BULLET:
		_spent(from, to, deck, by == client.my_id if by >= 0 else from.distance_to(Vector2(client.pred.qx(), client.pred.qy()) / 4.0) < 0.8, at_px)
	_shots.append([kind, hit != 0, a, b, deck, SHOT_SECONDS * (3.0 if kind == Net.SHOT_FLASH else 1.0)])


func _spent(from: Vector2, to: Vector2, deck: int, mine: bool, at_px: Vector2) -> void:
	## (v82, the author's F1) A gun fired: a casing falls by the shooter (one for a shotgun's
	## whole spread), and our own shot kicks the camera back a little.
	var now := Time.get_ticks_msec()
	var again := now - _last_spent < 60 and from.distance_to(_spent_from) < 0.1
	_last_spent = now
	_spent_from = from
	var way := (to - from).normalized()
	# (v83, his video: no kick while walking) whose shot it is comes with it now; the distance from our
	# predicted place missed every shot fired on the move
	if mine and Options.shake > 0.0:
		_kick = -way * KICK_PX * (2.0 if again else 1.0) * Options.shake
		_shake = maxf(_shake, KICK_SHAKE * (2.0 if again else 1.0) * Options.shake)
	if again:
		return
	var cell := Vector2i(roundi(from.x), roundi(from.y))
	if not client.map.walkable(cell.x, cell.y):
		return
	var side := Vector2(-way.y, way.x) * (1.0 if randf() < 0.5 else -1.0)
	var at := at_px + side * randf_range(7.0, 13.0) + Vector2(randf_range(-3, 3), randf_range(-2, 2))
	_casings.append([deck, at, randf_range(0.0, PI), cell.y * client.map.width + cell.x, CASING_SECONDS])
	while _casings.size() > CASINGS_KEPT:
		_casings.pop_front()
	_decks[deck].things.queue_redraw()


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


func _update_hover() -> void:
	## Something usable under the mouse gets an outline, as in SS13 (the author's
	## note): bright when a click would reach it, faint when it is out of reach.
	## Only what we can see: the outline gives nothing away in the dark. The
	## outline follows the thing itself (the author, v54): a machine on a wall,
	## things on the floor, a body; a door, a hole or a ladder gets its cell's.
	var on := Vector2i(-1, 0)
	var map := client.map
	var at := cell_under_mouse() if hover_test == Vector2.INF else Vector2(client.pred.x, client.pred.y) + hover_test
	var c := Vector2i(roundi(at.x), roundi(at.y))
	if hover and client.my_cond == Net.COND_OK and c.x >= 0 and c.y >= 0 and c.x < map.width and c.y < map.height:
		var cell := c.y * map.width + c.x
		var reach := client.click_facing(c) >= 0
		if client.usable_at(cell) and (reach or can_see(c.x, c.y)):
			on = Vector2i(cell, 1 if reach else 0)
	if on.x < 0 and hover and client.my_cond == Net.COND_OK:
		# (v73, the author's I2) with the mouse on nothing, what the "use" key would act on is outlined
		var target := client.target_cell()
		if target >= 0:
			on = Vector2i(target, 1)
	if on != _hover_on:
		_hover_on = on
		_hover_pen.queue_redraw()
		_hover_ink.queue_redraw()
	_hover_body()


func ui_sound(name: String) -> void:
	## (v82) A console's own little sound (opening, closing, refusing), where we stand: only in air.
	var here := Vector2i(client.pred.x, client.pred.y)
	var cell := here.y * client.map.width + here.x
	if cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR:
		_audio.play(name, _feet(Vector2(here.x, client.map.local_y(here.y))), 6.0, false, -10.0)


func alarm_sound() -> void:
	## (v73) The chime of a danger banner, from the ship's speakers: only where there is air.
	var here := Vector2i(client.pred.x, client.pred.y)
	var cell := here.y * client.map.width + here.x
	if cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR:
		_audio.play(Sounds.ALERT_YELLOW, _feet(Vector2(here.x, client.map.local_y(here.y))), 40.0, false, -6.0)


func _update_ring() -> void:
	var working := client.work > 0 and client.target_cell() >= 0   # (v74) held or going on by itself (the bench, a kit)
	var rising := client.pred.rise > 0
	_work_sounds(working)
	var healing := _in_autodocs()
	if working or _ring_shown or rising or _rise_shown or not healing.is_empty() or not _healing.is_empty():
		_ring_shown = working
		_rise_shown = rising
		_healing = healing
		_ring_pen.queue_redraw()


func _work_sounds(working: bool) -> void:
	## (v82, his F1 note "a little sound for everything we do") a soft tick while a job goes on under
	## our hands, a knock when it is done, a flick when another thing comes into the hand.
	var now := Time.get_ticks_msec() / 1000.0
	if working and client.work > _work_was and now >= _work_tick_at:
		_work_tick_at = now + 0.32
		ui_sound(Sounds.UI_WORK)
	if not working and _work_was >= 95:
		ui_sound(Sounds.UI_DONE)
	_work_was = client.work if working else 0
	if _hand_was >= 0 and client.hand != _hand_was:
		ui_sound(Sounds.UI_SLOT)
	_hand_was = client.hand


func _in_autodocs() -> Array[int]:
	## (v82, his D2 note "it needs a bar so one sees one is being healed") Who lies on the bed of a
	## working autodoc. We know our own health; of others only that the machine is at them.
	var found: Array[int] = []
	if client.map.autodoc.is_empty() or not client.powered():
		return found
	var beds := {}
	for doc: int in client.map.autodoc.keys():
		if not client.broken.has(doc):
			beds[int(client.map.autodoc[doc])] = true
	var w := client.map.width
	if beds.has(client.pred.y * w + client.pred.x) and client.my_cond != Net.COND_DEAD and client.health < 100:
		found.append(client.my_id)
	for e: GameClient.Ent in client.ents.values():
		if e.id != client.my_id and e.cond != Net.COND_DEAD and beds.has(e.y * w + e.x) and _views.has(e.id) and _views[e.id].visible:
			found.append(e.id)
	return found


func _draw_ring() -> void:
	## (v73, the author's I3) The progress of a job held with "use", over the thing itself.
	var me: Sprite2D = _views.get(client.my_id)
	if _rise_shown and me != null and me.visible:
		# (v82, his crawl video) getting up: a small bar over the body, red filling to green, as in SS13
		var spot := me.position + Vector2(0, -CHAR_H * 0.5).rotated(me.rotation) + Vector2(0, -34)
		var at := _ring_pen.to_local(me.get_parent().to_global(spot))
		var share := 1.0 - float(client.pred.rise) / float(Mover.RISE_TICKS)
		_ring_pen.draw_rect(Rect2(at - Vector2(13, 3), Vector2(26, 6)), Color(0.05, 0.07, 0.1, 0.8))
		_ring_pen.draw_rect(Rect2(at - Vector2(12, 2), Vector2(24 * share, 4)), Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.9, 0.35), share))
	for id in _healing:
		var body: Sprite2D = _views.get(id)
		if body == null or not body.visible:
			continue
		var top := _ring_pen.to_local(body.get_parent().to_global(body.position + Vector2(0, -CHAR_H * 0.5) + Vector2(0, -44)))
		var beat := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 0.8)
		var green := Color(0.35, 1.0, 0.45, 0.5 + 0.5 * beat)
		var cross := top + Vector2(-17 if id == client.my_id else 0, 0)
		_ring_pen.draw_rect(Rect2(cross - Vector2(4, 1.5), Vector2(8, 3)), green)
		_ring_pen.draw_rect(Rect2(cross - Vector2(1.5, 4), Vector2(3, 8)), green)
		if id == client.my_id:
			# our own health filling up, beside the cross
			var share := clampf(client.health / 100.0, 0.0, 1.0)
			_ring_pen.draw_rect(Rect2(top - Vector2(11, 3), Vector2(28, 6)), Color(0.05, 0.07, 0.1, 0.8))
			_ring_pen.draw_rect(Rect2(top - Vector2(10, 2), Vector2(26 * share, 4)), Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.9, 0.35), share))
	if not _ring_shown:
		return
	var cell := client.target_cell()
	if cell < 0:
		return
	var mid := _on_deck(cell) * _tile + Vector2(_tile, _tile) * 0.5
	var share := clampf(client.work / 100.0, 0.0, 1.0)
	_ring_pen.draw_circle(mid, 9.0, Color(0.05, 0.07, 0.1, 0.55))
	_ring_pen.draw_arc(mid, 8.0, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 2.0, true)
	_ring_pen.draw_arc(mid, 8.0, -PI / 2.0, -PI / 2.0 + TAU * share, 32, Color(1.0, 0.86, 0.35, 0.95), 2.0, true)


func _exit_tree() -> void:
	# the body's outline is out of the tree while no body is under the mouse: free it ourselves
	if _body_ink != null and _body_ink.get_parent() == null:
		_body_ink.free()


func _hover_colour() -> Color:
	return Color(1.0, 0.92, 0.55, 0.9) if _hover_on.y == 1 else Color(0.75, 0.8, 0.9, 0.4)


func _hover_body() -> void:
	## A body lying under the mouse (with nothing on the wall there) is outlined
	## by a copy of its figure that draws only the rim round it.
	var sprite: Sprite2D = null
	if _hover_on.x >= 0 and _tile_line(client.map.cells[_hover_on.x]) == null:
		for e: GameClient.Ent in client.ents.values():
			if e.id != client.my_id and e.cond != Net.COND_OK and e.y * client.map.width + e.x == _hover_on.x and _views.has(e.id):
				sprite = _views[e.id]
				break
	if sprite == null or sprite.get_parent() == null:
		if _body_ink.get_parent() != null:
			_body_ink.get_parent().remove_child(_body_ink)
		return
	# beside the body, not in it: a body's sprite is freed when it leaves our view
	if _body_ink.get_parent() != sprite.get_parent():
		if _body_ink.get_parent() != null:
			_body_ink.get_parent().remove_child(_body_ink)
		sprite.get_parent().add_child(_body_ink)
	_body_ink.transform = sprite.transform
	_body_ink.z_index = sprite.z_index + 1
	_body_ink.region_rect = sprite.region_rect.grow(1.0)
	_body_ink.offset = sprite.offset - Vector2.ONE
	_body_ink.flip_h = sprite.flip_h
	(_body_ink.material as ShaderMaterial).set_shader_parameter("ink", _hover_colour())


func _hover_kind() -> int:
	## What the outline under the mouse goes round: 0 its cell, 1 a thing fitted
	## into the wall, 2 things on the floor, 3 a body.
	if _hover_on.x < 0:
		return 0
	if _tile_line(client.map.cells[_hover_on.x]) != null:
		return 1
	if _body_ink.get_parent() != null:
		return 3
	if client.floor_things.has(_hover_on.x) and client.map.door_of[_hover_on.x] < 0 and not client.holes.has(_hover_on.x):
		return 2
	return 0


func _draw_hover() -> void:
	if _hover_on.x < 0:
		return
	var corner := _on_deck(_hover_on.x) * _tile
	match _hover_kind():
		1:
			_hover_pen.draw_texture(_tile_line(client.map.cells[_hover_on.x]), corner, _hover_colour())
		2:
			_floor_things_at(_hover_pen, _hover_on.x, corner)    # the things again, over their silhouettes
		3:
			pass
		_:
			_hover_pen.draw_rect(Rect2(corner, Vector2(_tile, _tile)).grow(-0.5), _hover_colour(), false, 1.0)


func _draw_hover_ink() -> void:
	## The silhouettes of the things on the floor under the mouse, a pixel out
	## each of four ways: what is left of them round the things is their outline.
	if _hover_kind() != 2:
		return
	(_hover_ink.material as ShaderMaterial).set_shader_parameter("ink", _hover_colour())
	var corner := _on_deck(_hover_on.x) * _tile
	for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		_floor_things_at(_hover_ink, _hover_on.x, corner + d)


func _tile_line(id: int) -> Texture2D:
	## The outline of what is fitted into a wall tile (a console, a machine, a
	## locker...): the pixels round those that differ from the bare wall. Null
	## for every other tile. Worked out once per tile.
	if id < 0:
		return null
	if _tile_lines.has(id):
		return _tile_lines[id]
	var map := client.map
	var line: Texture2D = null
	if id < map.fitting.size() and map.fitting[id] == 1:
		if _tiles_image == null:
			_tiles_image = Sprites.sheet("tiles").get_image()
			if _tiles_image.is_compressed():
				_tiles_image.decompress()
		var name := ""
		for n: String in map.tile_ids.keys():
			if int(map.tile_ids[n]) == id:
				name = n
		var wall: int = map.tile_ids.get("pirate_wall_h" if name.begins_with("pirate_") else "wall_h", -1)
		if wall >= 0:
			line = _outline_of(id, wall)
	_tile_lines[id] = line
	return line


func _outline_of(id: int, wall: int) -> Texture2D:
	var cols := client.map.atlas_columns
	var at := Vector2i(id % cols, id / cols) * _tile
	var bare := Vector2i(wall % cols, wall / cols) * _tile
	var t := _tile
	var inside := PackedByteArray()
	inside.resize(t * t)
	for y in t:
		for x in t:
			var a := _tiles_image.get_pixel(at.x + x, at.y + y)
			var b := _tiles_image.get_pixel(bare.x + x, bare.y + y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a) > 0.1:
				inside[y * t + x] = 1
	# close one-pixel gaps (a pixel of the thing the colour of the wall), then
	# fill what the outside cannot reach: the thing is one solid shape
	var grown := _spread(inside, t, 1)
	var solid := _spread(grown, t, 0)
	var outside := PackedByteArray()
	outside.resize(t * t)
	var todo: Array[int] = []
	for k in t:
		for c: int in [k, (t - 1) * t + k, k * t, k * t + t - 1]:
			if solid[c] == 0 and outside[c] == 0:
				outside[c] = 1
				todo.append(c)
	while not todo.is_empty():
		var c: int = todo.pop_back()
		var x := c % t
		var y := c / t
		for n: Vector2i in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
			if n.x >= 0 and n.y >= 0 and n.x < t and n.y < t:
				var k := n.y * t + n.x
				if solid[k] == 0 and outside[k] == 0:
					outside[k] = 1
					todo.append(k)
	var picture := Image.create(t, t, false, Image.FORMAT_RGBA8)
	var any := false
	for y in t:
		for x in t:
			if outside[y * t + x] == 0:
				continue
			for n: Vector2i in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
				if n.x >= 0 and n.y >= 0 and n.x < t and n.y < t and outside[n.y * t + n.x] == 0:
					picture.set_pixel(x, y, Color.WHITE)
					any = true
					break
	return ImageTexture.create_from_image(picture) if any else null


static func _spread(cells: PackedByteArray, t: int, value: int) -> PackedByteArray:
	## value 1: every cell next to a set one is set too; value 0: every cell next
	## to an unset one is unset (a cell on the edge keeps its own).
	var out := cells.duplicate()
	for y in t:
		for x in t:
			if cells[y * t + x] == value:
				continue
			for n: Vector2i in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
				if n.x >= 0 and n.y >= 0 and n.x < t and n.y < t and cells[n.y * t + n.x] == value:
					out[y * t + x] = value
					break
	return out


static func _ink_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


func _draw_shade() -> void:
	## The warm light of flashlights on the floor, and shots: a trace, a flash
	## at the muzzle and a spark where it hit (the dark itself is the sheet over the screen).
	for sh: Array in _shots:
		if int(sh[4]) != _deck_shown:
			continue
		var left := minf(float(sh[5]) / SHOT_SECONDS, 1.0)
		var a: Vector2 = sh[2]
		var b: Vector2 = sh[3]
		if int(sh[0]) == Net.SHOT_BULLET:
			_shade.draw_line(a, b, Color(1.0, 0.9, 0.5, 0.85 * left), 1.5)
			_shade.draw_circle(a + (b - a).normalized() * 10.0, 5.0 * left, Color(1.0, 0.85, 0.4, left))
		elif int(sh[0]) == Net.SHOT_FLASH:
			# (v70) a flashbang or a bomb: a white burst
			_shade.draw_circle(b, 40.0 + 60.0 * (1.0 - left), Color(1.0, 1.0, 0.95, 0.75 * left))
			continue
		elif int(sh[0]) == Net.SHOT_BLOW:
			# (v84, the author's S1) a swing in front of the one striking, toward the mouse; the ring only on a hit
			var ang := (b - a).angle() if b != a else 0.0
			_shade.draw_arc(a, 18.0, ang - 0.9, ang + 0.9, 12, Color(1.0, 1.0, 1.0, 0.7 * left), 3.0)
			if not bool(sh[1]):
				continue
			_shade.draw_arc(b, 9.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.8 * left), 2.0)
		else:
			_shade.draw_arc(b, 9.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.8 * left), 2.0)
		if bool(sh[1]):
			_shade.draw_circle(b, 6.0 * left + 2.0, Color(0.9, 0.1, 0.1, 0.9 * left))
	_fight.draw(_shade, _deck_shown)
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
		elif int(sh[4]) == _deck_shown and int(sh[0]) == Net.SHOT_FLASH:
			_mask.draw_circle(sh[3], 140.0, Color(0, 0, 1, float(sh[5]) / SHOT_SECONDS))  # (v70) a flashbang lights the room
	_fight.draw_light(_mask, _deck_shown)
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
	var origin := _my_spot(me) + Vector2(0, -12)
	var half := 0.0
	for arc: Array in Sight.eye_arcs(false):
		half = maxf(half, maxf(absf(arc[0]), absf(arc[1])))
	var reach := (float(Sight.SIGHT_REACH) + 1.5) * _tile
	var m := _cone_fan.material as ShaderMaterial
	m.set_shader_parameter("origin", origin)
	m.set_shader_parameter("ahead", client.look_way())   # (v77) the mouse's way, or the way we face
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
			_cone.draw_circle(_my_spot(me) + Vector2(0, -12), _tile * 0.6, white)
		return
	_draw_light(_cone, _near, white, 0)


func _draw_look() -> void:
	## Green where our eyes reach: a cone from each eye, cut short by walls and
	## shut doors, and our own cell (somebody right behind us is felt, not seen).
	var me: Sprite2D = _views.get(client.my_id)
	if me == null or me.get_parent() != _decks[_deck_shown].chars or client.my_cond != Net.COND_OK:
		if me != null and client.my_cond != Net.COND_DEAD:
			_look.draw_circle(_my_spot(me) + Vector2(0, -12), _tile * 0.6, Color(0, 1, 0, 1))
		return
	var s := client.sample(client.my_id)
	if s.is_empty():
		return
	var green := Color(0, 1, 0, 1)
	var origin := _my_spot(me) + Vector2(0, -12)
	var ahead := client.look_way()               # (v77) the mouse's way, or the way we face
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
	for arc: Array in arcs:
		var points := PackedVector2Array([origin])
		for k in LOOK_RAYS + 1:
			var way := ahead.rotated(deg_to_rad(lerpf(float(arc[0]), float(arc[1]), float(k) / LOOK_RAYS)))
			var t := _ray_reach(origin, way, start_cell, reach)
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
			var local := (y + dy) * map.width + x
			if Sight.blocks(client.map, client.doors, x, y + dy):
				walls.append(c)
			elif map.cells[local] >= 0 and _clear_to(at_t, start_cell, c):
				seen[c] = true
			elif map.cells[local] >= 0 and (map.walk[local] == 0 or map.door_of[local] >= 0):
				# a window or an open door in a wall whose middle is hidden: told as a
				# wall is (its seen face or corner shows it whole), not left to the
				# rays, which cut a wedge out of it (v53, the author's video)
				walls.append(c)
	# Whole cells are told by these checks alone, not by whether a ray happened to
	# touch them: rays move with every pixel we walk, so a cell they only graze
	# (a room's far corner) was shown one frame and hidden the next (v52, the
	# author's video). The rays still draw the parts of cells seen in part.
	var walls_seen: Array[Vector2i] = []
	for c: Vector2i in walls:
		if _clear_to(at_t, start_cell, c):
			walls_seen.append(c)             # its middle in plain sight
			continue
		var found := false
		for d: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			# a corner: walls on both sides of it towards us, and the floor
			# cell diagonally in front of it seen
			var n := c + d
			if seen.has(n) and (at_t.x >= n.x if d.x > 0 else at_t.x <= n.x + 1) \
					and (at_t.y >= n.y if d.y > 0 else at_t.y <= n.y + 1) \
					and Sight.blocks(map, client.doors, c.x + d.x, c.y + dy) \
					and Sight.blocks(map, client.doors, c.x, c.y + d.y + dy):
				found = true
				break
		if found:
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
			if faces and seen.has(n):
				walls_seen.append(c)
				break
	for c: Vector2i in seen:
		_look.draw_rect(Rect2(Vector2(c) * _tile, Vector2(_tile, _tile)), green)
	for c: Vector2i in walls_seen:
		_look.draw_rect(Rect2(Vector2(c) * _tile, Vector2(_tile, _tile)), green)


func _ray_reach(origin: Vector2, way: Vector2, start: Vector2i, reach: float) -> float:
	## How far (in pixels) a look from `origin` along `way` goes before a wall or
	## shut door, at most `reach`. Walked cell by cell through the grid, so it
	## stops exactly at a wall's face and cannot slip past a corner between two
	## steps (v52: a ray stepped a few pixels at a time did, here one frame and
	## not the next, and a sliver behind the wall blinked).
	var from := origin / _tile
	var c := start
	var step := Vector2i(int(signf(way.x)), int(signf(way.y)))
	var t_max := Vector2(INF, INF)
	var t_delta := Vector2(INF, INF)
	if way.x != 0.0:
		t_max.x = ((c.x + (1 if way.x > 0.0 else 0)) - from.x) / way.x
		t_delta.x = 1.0 / absf(way.x)
	if way.y != 0.0:
		t_max.y = ((c.y + (1 if way.y > 0.0 else 0)) - from.y) / way.y
		t_delta.y = 1.0 / absf(way.y)
	var dy := _deck_shown * _stride
	var limit := reach / _tile
	while true:
		var t := 0.0
		if t_max.x < t_max.y:
			t = t_max.x
			c.x += step.x
			t_max.x += t_delta.x
		else:
			t = t_max.y
			c.y += step.y
			t_max.y += t_delta.y
		if t >= limit:
			return reach
		if Sight.blocks(client.map, client.doors, c.x, c.y + dy):
			return maxf(t * _tile - 1.0, 0.0)   # just short of its face, so no jagged strip pokes into it
	return reach


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
	var ahead := client.look_way()               # (v77) the mouse's way, or the way we face
	if not dark and not client.dark_cell(y * map.width + x):
		return Sight.sees_way(map, client.doors, me, ahead, on_ours, arcs, Sight.SIGHT_REACH)
	if Vector2(on_ours).distance_to(me) <= Sight.DARK_REACH + 0.5 \
			and Sight.sees_way(map, client.doors, me, ahead, on_ours, arcs, Sight.DARK_REACH):
		return true
	return _lit.has(y * map.width + x) and Sight.sees_way(map, client.doors, me, ahead, on_ours, arcs, Sight.SIGHT_REACH)


func _on_heard(kind: int, x: int, y: int) -> void:
	## A sound reached us: it plays from where it was made. Air rushing out and
	## a cry also leave a mark there if we cannot see the place (the author kept
	## those two), the less exactly the further off.
	var map := client.map
	if kind <= 0 or kind >= SOUND_LOOK.size():
		return
	var seen := can_see(x, y)
	if map.deck_of(y) == client.my_deck():
		_audio.play(kind, _feet(Vector2(x, map.local_y(y))), Net.SOUND_RANGE[kind], not seen or _thin_air_here(),
			(-8.0 + Options.db_of(Options.steps_volume)) if kind == Net.SOUND_STEP else 0.0)
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


func _on_jolt(kind: int, shot: int, at: Vector2) -> void:
	## (v56) A sound of the ship fight. Blows to the hull of the ship we stand on
	## shake the screen however near (harder close by, less on another deck);
	## every sound of it is heard only with air round us (a vacuum is silent, the
	## author's rule), muffled from another deck. The pirate ship's bursts are
	## heard aboard ours as the ship's sensors give them: farther off, not muffled.
	var map := client.map
	var cell := client.pred.y * map.width + client.pred.x
	var here := Vector2(client.pred.x, client.pred.y)
	var aboard_ours := map.on_ship(cell)
	var aboard_theirs := map.is_other(cell) or (not aboard_ours and map.other_at != ShipMap.NO_OTHER
		and Rect2(Vector2(map.other_at), Vector2(map.other.width, map.other.height)).has_point(here))
	var same_deck := map.deck_of(roundi(at.y)) == client.my_deck()
	var d := here.distance_to(at) + (0.0 if same_deck else 8.0)
	var ours := kind <= Net.JOLT_FIRE                # it happens on our ship (theirs: on the pirate ship)
	var on_it := aboard_ours if ours else aboard_theirs
	if on_it and (kind == Net.JOLT_HULL or kind == Net.JOLT_HEAVY or kind == Net.JOLT_THEIR_HIT):
		var hard := 9.0 if kind == Net.JOLT_HEAVY else 5.0
		_shake = maxf(_shake, hard * Options.shake / (1.0 + d / 7.0))
	var in_air := cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR
	if not in_air or not (aboard_ours or aboard_theirs):
		return
	var name := ""
	match kind:
		Net.JOLT_HULL:
			name = Sounds.HULL_HIT
		Net.JOLT_HEAVY:
			name = Sounds.HULL_HEAVY
		Net.JOLT_SHIELD:
			name = Sounds.SHIELD_HIT
		Net.JOLT_FIRE:
			# (for a gun firing, `shot` is the weapon)
			var own: String = {Weapons.AUTOCANNON: Sounds.GUN_AUTOCANNON, Weapons.RAILGUN: Sounds.GUN_RAIL,
				Weapons.HAMMER: Sounds.GUN_HAMMER, Weapons.PHOENIX: Sounds.GUN_PHOENIX, Weapons.STORM: Sounds.GUN_STORM,
				Weapons.DEVASTATOR: Sounds.GUN_DEVASTATOR, Weapons.REAPER: Sounds.GUN_REAPER, Weapons.GUARD: Sounds.GUN_FLAK,
				Weapons.NOVA: Sounds.GUN_NOVA, Weapons.SHRAPNEL: Sounds.GUN_SHRAPNEL}.get(shot, "")     # (v58) the new guns, each with its own sound
			if Weapons.bomb(shot):
				own = Sounds.GUN_BOMB            # (v62)
			match Weapons.klass(shot) if own == "" else -1:
				-1:
					name = own
				Weapons.CLASS_ROCKET:
					name = Sounds.GUN_ROCKET
				Weapons.CLASS_ION:
					name = Sounds.GUN_ION
				Weapons.CLASS_BEAM, Weapons.CLASS_TRACTOR, Weapons.CLASS_SIPHON:
					name = Sounds.GUN_BEAM
				_:
					name = Sounds.GUN_HEAVY if shot == Weapons.HEAVY or shot == Weapons.SIEGE else Sounds.GUN_LASER
		Net.JOLT_THEIR_HIT:
			name = Sounds.THEIR_HIT if aboard_ours or not on_it else Sounds.HULL_HIT
		Net.JOLT_THEIR_SHIELD:
			name = Sounds.THEIR_SHIELD
	if name == "":
		return
	var loud := Options.db_of(Options.fight_volume)
	if on_it and same_deck:
		# from where it happened: the gun, the hole
		_audio.play(name, _feet(Vector2(at.x, map.local_y(roundi(at.y)))), 40.0, _thin_air_here(), loud)
	elif on_it:
		_audio.play(name, _feet(Vector2(here.x, map.local_y(client.pred.y))), 40.0, true, loud - 2.0)   # through the deck
	else:
		_audio.play(name, _feet(Vector2(here.x, map.local_y(client.pred.y))), 40.0, _thin_air_here(), loud - 7.0)   # the other ship's


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
			_audio.play(Net.SOUND_STEP, _feet(Vector2(here.x, map.local_y(here.y))), Net.SOUND_RANGE[Net.SOUND_STEP], _thin_air_here(),
				-12.0 + Options.db_of(Options.steps_volume))   # (v56: quieter, the author's word)
		_last_cell = here
	if client.alert_changes != _alert_heard:
		# (v68, the author's J4) the alert sounds through the ship's speakers: everyone hears it where there is air
		var first := _alert_heard < 0
		_alert_heard = client.alert_changes
		var cell := here.y * map.width + here.x
		var in_air := cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR
		if not first and in_air and client.alert != Net.ALERT_GREEN:
			_audio.play(Sounds.ALERT_RED if client.alert == Net.ALERT_RED else Sounds.ALERT_YELLOW,
				_feet(Vector2(here.x, map.local_y(here.y))), 40.0, false, -4.0)
	_ambience(delta, here)
	_hum_timer -= delta
	if _hum_timer > 0.0:
		return
	_hum_timer = 0.25
	_music_now()
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


func _on_hit(blood: int, id: int, x: int, y: int) -> void:
	## (v75, the author's F1) Somebody near was hurt: the figure flashes red, a few drops
	## of blood stay on the floor (sparks fly off a robot), the blow is heard where there is air.
	var map := client.map
	_flash[id] = HIT_FLASH
	if id == client.my_id:
		_shake = maxf(_shake, HURT_SHAKE * Options.shake)   # (v82, his O1 note) we feel our own hurt
	var deck := map.deck_of(y)
	if deck < 0 or deck >= _decks.size():
		return
	var corner := Vector2(x, map.local_y(y)) * _tile
	if blood == Net.BLOOD_FLESH and map.walkable(x, y):
		# (v80, the author's note: blood stayed in open space and flew along with the ship) only on a floor
		for k in randi_range(2, 4):
			_stains.append([deck, corner + Vector2(randf_range(5.0, 27.0), randf_range(15.0, 30.0)), randf_range(1.2, 3.4), y * map.width + x])
		while _stains.size() > STAINS_KEPT:
			_stains.pop_front()
		_decks[deck].things.queue_redraw()
	else:
		_sparks.append([deck, corner + Vector2(16.0, 10.0), 0.35])
	var cell := y * map.width + x
	var near := Vector2(x, y).distance_to(Vector2(client.pred.x, client.pred.y)) <= Net.SOUND_CONTACT
	var aired := cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR
	if deck == client.my_deck() and (aired and not _thin_air_here() or near):
		_audio.play(Sounds.HIT if blood == Net.BLOOD_FLESH else Sounds.HIT_METAL, _feet(Vector2(x, map.local_y(y))), 10.0,
			not can_see(x, y), -3.0)


func _ambience(delta: float, here: Vector2i) -> void:
	## (v75, the author's F5) The ship sounds alive: a room's vent breathes now and then, a pipe
	## knocks in a wall, the hull groans a moment after a jump. Each from its place, never in a vacuum.
	var map := client.map
	var cell := here.y * map.width + here.x
	var in_air := cell >= 0 and cell < client.air.size() and client.air[cell] >= Net.AIR_FULL * Net.SOUND_AIR \
		and map.on_ship(cell) and client.my_cond == Net.COND_OK
	if _jumps_heard != client.jumps:
		if _jumps_heard >= 0:
			_creak_in = 1.8
		_jumps_heard = client.jumps
	if _creak_in >= 0.0:
		_creak_in -= delta
		if _creak_in < 0.0 and in_air:
			_audio.play(Sounds.AMB_CREAK, _feet(Vector2(here.x, map.local_y(here.y))) + Vector2(randf_range(-90, 90), -40), 16.0, false, -6.0)
	_amb_timer -= delta
	if _amb_timer > 0.0:
		return
	_amb_timer = randf_range(7.0, 16.0)
	if not in_air or not client.powered():
		return
	var room := map.room_of[cell]
	var vent := -1
	for v: int in map.vents:
		if room >= 0 and map.room_of[v] == room:
			vent = v
	if vent >= 0 and randf() < 0.55:
		_audio.play(Sounds.AMB_VENT, _feet(Vector2(vent % map.width, map.local_y(vent / map.width))), 7.0, false, -16.0)
	else:
		var spot := Vector2(here.x + randf_range(-4.0, 4.0), map.local_y(here.y) + randf_range(-2.0, 2.0))
		_audio.play(Sounds.AMB_PIPE, _feet(spot), 8.0, true, -12.0)


func _music_now() -> void:
	## (v75, the author's F4) A low drone while a pirate ship fights us, at red alert, or while
	## pirates were seen aboard lately; silent otherwise.
	if Music.current == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for e: GameClient.Ent in client.ents.values():
		if e.cond != Net.COND_DEAD and client.roster.has(e.id) and int(client.roster[e.id]["kind"]) == Net.KIND_PIRATE \
				and client.map.on_ship(e.y * client.map.width + e.x):
			_boarders_until = now + 20.0
	var danger := client.fighting() or client.alert == Net.ALERT_RED or now < _boarders_until
	Music.current.play(Sounds.MUSIC_FIGHT if danger and client.my_cond != Net.COND_DEAD else "")


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
	# (v75) sparks off a robot that was hit
	for sp: Array in _sparks:
		if int(sp[0]) != d:
			continue
		var k := float(sp[2]) / 0.35
		for j in 5:
			var dir := Vector2.from_angle(float(j) * 1.3 + float((sp[1] as Vector2).x))
			var from: Vector2 = (sp[1] as Vector2) + dir * (1.0 - k) * 10.0
			pen.draw_line(from, from + dir * 3.0, Color(1.0, 0.85, 0.35, k), 1.0)
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
	# (v63) the hydroponic trays: the plant in each, as far as it has grown; a drop blinks over one that wants tending
	for cell: int in client.garden.keys():
		if map.deck_of_cell(cell) != d:
			continue
		var t: Array = client.garden[cell]
		var stage := int(t[1])
		if stage == Net.GROW_EMPTY:
			continue
		var base := _on_deck(cell) * _tile + Vector2(16.0, 20.0)
		var dead := stage == Net.GROW_DEAD
		var leaf: Color = Color(0.45, 0.32, 0.18) if dead else (Plants.KINDS[Plants.kind_of(int(t[0]))]["leaf"] as Color)
		var tall := 3.0 + 9.0 * (1.0 if stage == Net.GROW_RIPE or dead else float(t[2]) / 100.0)
		for k in 3:
			var x := float(k - 1) * 5.0
			var tip := base + Vector2(x * (1.6 if dead else 1.0), -tall * (0.5 if dead else (1.0 - 0.2 * absf(k - 1))))
			pen.draw_line(base + Vector2(x * 0.4, 0.0), tip, leaf.darkened(0.3), 1.5)
			pen.draw_circle(tip, 2.0, leaf)
		if stage == Net.GROW_RIPE:
			for k in 3:
				pen.draw_circle(base + Vector2(float(k - 1) * 5.0, -tall + 3.0), 1.5, Color(1.0, 0.85, 0.35))
		if int(t[3]) & Net.GARDEN_CARE and fposmod(now + float(cell % 7) * 0.13, 1.0) < 0.6:
			var drop := base + Vector2(9.0, -tall - 4.0)
			pen.draw_circle(drop, 2.2, Color(0.3, 0.6, 1.0) if not (int(t[3]) & Net.GARDEN_NEGLECT) else Color(1.0, 0.4, 0.25))
	# (v63) the comms console's lamp blinks while a call waits
	if int(client.comms.get("state", Net.COMMS_QUIET)) == Net.COMMS_CALL and fposmod(now, 0.8) < 0.45:
		for cell: int in map.comms.keys():
			if map.deck_of_cell(cell) == d and client.power_at(cell):
				pen.draw_rect(Rect2(_on_deck(cell) * _tile + Vector2(22.0, 6.0), Vector2(5, 5)), Color(0.35, 0.75, 1.0))
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
		if client.doors.welded[door] == 1:
			# (v82, his note: a welded door looked like any other) a bead of weld where the leaves meet
			for k in 7:
				var bead := corner + (Vector2(18.0 + (1.5 if k % 2 == 0 else -1.5), 9.5 + k * 2.2) if band
					else Vector2(12.0 + k * 1.4, 13.5 + (1.5 if k % 2 == 0 else -1.5)))
				pen.draw_circle(bead, 2.0, Color(0.2, 0.17, 0.15))
				pen.draw_circle(bead, 1.3, Color(0.78, 0.55, 0.3))
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
			# (v69) amber: its lock was broken open and lets anybody through
			pen.draw_rect(Rect2(lock_at, Vector2(3, 3)), Color(1.0, 0.7, 0.15) if client.doors.picked[door] == 1
				else (Color(0.25, 0.9, 0.4) if ours else Color(1.0, 0.25, 0.2)))
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
	zoom = clampf(zoom + zoom_step, 1.0, 8.0)
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
	var samples := {}
	for id: int in client.ents.keys():
		var got := client.sample(id)
		if not got.is_empty():
			samples[id] = got
	var nudge := _passing(samples)
	for id: int in samples.keys():
		var s: Array = samples[id]
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
		sprite.position = ((_feet(pos) + nudge.get(id, Vector2.ZERO)) * zoom).round() / zoom   # on a whole screen pixel
		sprite.region_rect = _frame(s[1], s[2] and cond == Net.COND_OK, pos, client.player_colour(id) * Net.LOOKS + client.look_of(id))
		_hold(sprite, s[1], client.held_by(id) if cond == Net.COND_OK else Net.ITEM_NONE)
		# (v82, his crawl video) lying down, getting up and falling turn the body over in LIE_TURN
		# seconds rather than flipping it; a body first seen already lies
		var lies := cond != Net.COND_OK or client.prone_of(id)
		var was_t: float = _lie.get(id, 1.0 if lies else 0.0)
		var t := move_toward(was_t, 1.0 if lies else 0.0, delta / LIE_TURN)
		_lie[id] = t
		var stand_at := sprite.position
		_stand[id] = stand_at
		if cond == Net.COND_OK and (client.prone_of(id) or t > 0.0):
			# (v78) lying low, in its own colours. (v79, his note) Seen from above on its back, the body over
			# its own spot, not slid back like one knocked down. (v80, his note: "this feels very strange": looking
			# up it stood upright, looking down it stood on its head) Always lying across, as in SS13: the head
			# to the side it looks to, kept while it looks straight up or down.
			# (v83, his note with the SS13 video: "where you lay, the head stays in the same place") The side is
			# taken once, as it lies down; turning while down keeps the head where it is and only shows the
			# figure's frame for the new way, turned over with it, as SS13 does.
			var look_x := Net.way(s[1]).x
			if look_x != 0.0 and (was_t <= 0.0 or not _prone_side.has(id)):
				_prone_side[id] = 1.0 if look_x > 0.0 else -1.0
			var head := Vector2(float(_prone_side.get(id, 1.0)), 0.0)
			sprite.region_rect = _frame(s[1], false, pos, client.player_colour(id) * Net.LOOKS + client.look_of(id))
			sprite.rotation = wrapf(head.angle() + PI / 2.0, -PI, PI) * t
			var lying_at := ((_feet(pos) + PRONE_CENTRE - head * CHAR_H * 0.5) * zoom).round() / zoom
			sprite.position = (stand_at.lerp(lying_at, t) * zoom).round() / zoom
			sprite.modulate = Color.WHITE
		elif cond == Net.COND_OK:
			sprite.rotation = 0.0
			# (v81) one holding its position (the human wall) stands out in a steel blue
			sprite.modulate = Color(0.72, 0.85, 1.0) if client.hold_of(id) else Color.WHITE
		else:
			# on the floor: the figure is turned on its side and slid back over its tile
			sprite.rotation = PI / 2.0 * t
			sprite.position += (Vector2(-22.0, -7.0) * t * zoom).round() / zoom
			sprite.modulate = Color(0.55, 0.55, 0.6) if cond == Net.COND_DEAD else Color(0.85, 0.85, 0.88)
		if _flash.has(id):
			sprite.modulate = sprite.modulate.lerp(Color(1.0, 0.2, 0.2), clampf(float(_flash[id]) / HIT_FLASH, 0.0, 1.0))
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
			_prone_side.erase(id)
			_lie.erase(id)
			_stand.erase(id)

	# camera follows our character; a ship smaller than the screen stays centred
	var me: Sprite2D = _views.get(client.my_id)
	# what our eyes reach is worked out again only when something it depends on changed
	var mine_now := client.sample(client.my_id)
	var look_key := hash([_my_spot(me) if me != null else Vector2.INF, me != null and me.get_parent() == _decks[my_deck].chars,
		mine_now[1] if not mine_now.is_empty() else 0, roundi(rad_to_deg(client.look_angle)) if client.free_looking() else 0, my_deck, client.my_cond, hash(client.doors.ready), client.other_changes])
	if look_key != _look_key:
		_look_key = look_key
		_look.queue_redraw()
		_cone.queue_redraw()
	_me_over.visible = me != null and me.get_parent() == _decks[my_deck].chars and client.my_cond != Net.COND_DEAD
	if _me_over.visible:
		_me_over.global_transform = me.global_transform
		_me_over.region_rect = me.region_rect
		_me_over.modulate = me.modulate * Color(0.8, 0.8, 0.85)
	var focus := _my_spot(me) - Vector2(0, 14) if me != null else Vector2.ZERO
	# (v79, the author's V1) with the view following the mouse the camera leans toward it, by how far
	# the mouse is from the middle of the screen, at most Options.lean tiles; it eases there and back
	var lean_to := Vector2.ZERO
	if client.free_looking() and client.my_cond == Net.COND_OK and Options.lean > 0 and lean_on:
		var screen := get_viewport_rect().size
		var off := (get_viewport().get_mouse_position() - screen * 0.5) / (screen * 0.5)
		lean_to = off.limit_length(1.0) * Options.lean * _tile
	_lean = _lean.lerp(lean_to, 1.0 - exp(-delta * LEAN_EASE))
	focus += _lean
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
	# (v56) a blow to the hull throws the picture about, by whole screen pixels
	_shake = move_toward(_shake * exp(-6.0 * delta), 0.0, delta)
	# (v82) our own shot's kick, eased back in a tenth of a second or so
	_kick = _kick.move_toward(Vector2.ZERO, delta * 30.0)
	_camera.position += (_kick * zoom).round() / zoom
	if _shake >= 1.0:
		_camera.position += Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)).round() / zoom
	# the picture of where light falls follows the camera exactly
	_mask_view.size = Vector2i(get_viewport_rect().size)
	_mask_camera.position = _camera.position
	_mask_camera.zoom = _camera.zoom
	_cone_view.size = _mask_view.size
	_cone_camera.position = _camera.position
	_cone_camera.zoom = _camera.zoom
	# the soft fan of the cone goes where our character is drawn this frame
	# (worked out before the characters moved, it trailed a frame behind: v52)
	_update_fan()
	_update_hover()
	_update_ring()

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
			# (v82, his note) only one really down gets the red name, not one lying low by choice
			if (int((samples[id] as Array)[4]) != Net.COND_OK) if samples.has(id) else lying:
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
			# lying: over the middle of the body, whichever way it lies
			var above := Vector2(0, -CHAR_H * 0.5).rotated(sprite.rotation) + Vector2(0, -13) if lying else Vector2(0, 6 - CHAR_H)
			var top := (sprite.position + above - _camera.position) * zoom + screen_centre
			label.position = (top - Vector2(label.size.x * 0.5, label.size.y)).round()

	# debug: the server's idea of where we are
	var mine: GameClient.Ent = client.ents.get(client.my_id)
	_ghost.visible = show_ghost and mine != null and map.deck_of(mine.y) == my_deck
	if _ghost.visible:
		_ghost.position = _feet(Vector2(mine.x, map.local_y(mine.y)))
		_ghost.region_rect = _cell(FACING_COLUMN.get(mine.facing, 0), client.player_colour(client.my_id) * Net.LOOKS + client.look_of(client.my_id))
