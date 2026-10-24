extends RefCounted
## (v87, the author's base bodies: "man and woman, just for now") The people's sheet, made when the game
## starts from his base sheet (assets/body.png, or body.png in the «sprites» folder) and the old drawn
## sheet (assets/chars.png) for the machines. (v85's suited character, assets/crew.png, waits unused for
## the clothes drawn over the body later.)
##
## His sheet: frames of 32x48, four across (0 the front, looking down; 1 the right side; 2 the back; 3 the
## left side), the woman in the top row and the man below. Only four ways for now (his words): a slant
## shows the side it leans to (WorldView.FACING_COLUMN). No walking frames: (his S7 B) the figure slides
## standing, so the two step columns hold the standing picture until the spriter draws steps.
##
## What it makes: a row per colour and look (see Net.LOOKS), cells of CHAR_W x CHAR_H with a 1-pixel
## border; in each row the man's 12 frames (4 ways x 3: standing, step, step: down, up, left, right) and
## from WOMAN_COLUMN the woman's. VISOR_ROW + the rows for one on its oxygen tank and HALF_ROW + colour the
## moment of switching it: (his S4 B) nothing shows the tank for now, so they hold the same body; they stay
## for the helmet the spriter draws later.
## The navy of his top and shorts is repainted in the colour of the row (the job's, the pirates'); grey for
## one with no jumpsuit.

const Net := preload("res://src/shared/net.gd")
const Sprites := preload("res://src/client/sprites.gd")

const FRAME := Vector2i(32, 48)        # a frame of his sheet, and of the made one
const PAD := 1
const CELL := FRAME + Vector2i(2 * PAD, 2 * PAD)
const VIEWS := 4                       # front, right, back, left
const BODIES := 2                      # rows of his sheet: 0 the woman, 1 the man
const WOMAN_COLUMN := 12               # the woman's frames start here in the made sheet
const FEET := 47                       # the lowest row of the figure in a frame (the shadow lies round it)
const ROWS := (Net.ARMOUR_COLOUR + 1) * Net.LOOKS
const VISOR_ROW := ROWS                # + colour * LOOKS + look: on the tank, the bubble over the head
const HALF_ROW := ROWS + Net.PIRATE_COLOURS * Net.LOOKS + Net.SUIT_COLOURS * Net.LOOKS   # + colour: the bubble half seen
const ALL_ROWS := HALF_ROW + Net.SUIT_COLOURS + Net.PIRATE_COLOURS
# the colours of the rows, as tools/make_assets.py has them (SUIT_COLOURS): the crew's jobs, then the pirates
const TINTS: Array[Color] = [
	Color8(200, 55, 45), Color8(47, 111, 208), Color8(58, 154, 74), Color8(217, 165, 32),
	Color8(138, 79, 200), Color8(217, 112, 42), Color8(42, 169, 184), Color8(201, 204, 212),
	Color8(112, 72, 40), Color8(128, 28, 24), Color8(44, 40, 46),
]
const UNDERSUIT := Color8(118, 120, 128)
const NAVY_HUE := Vector2(205.0, 252.0)   # degrees: what counts as the clothes' navy
const NAVY_SAT := 0.28
const NAVY_TOP := 0.45                    # the lightest navy: it becomes the colour itself
# per our way (Net.DIR_*, the four straight ones): his view, and the first column in the made sheet
const VIEW_OF := {Net.DIR_DOWN: 0, Net.DIR_RIGHT: 1, Net.DIR_UP: 2, Net.DIR_LEFT: 3}
const COLUMN_OF := {Net.DIR_DOWN: 0, Net.DIR_UP: 3, Net.DIR_LEFT: 6, Net.DIR_RIGHT: 9}
const OLD := Vector2i(32, 48)             # a frame of assets/chars.png (the machines), with its 1-pixel border

static var _sheet: Texture2D = null
static var own := false                 # the sheet came from the «sprites» folder


static func sheet() -> Texture2D:
	if _sheet == null:
		_sheet = ImageTexture.create_from_image(build())
	return _sheet


static func forget() -> void:
	_sheet = null


static func source() -> Image:
	## His sheet, from the «sprites» folder or the game's own, as RGBA of 4 x 2 whole frames.
	var im := Sprites.own_image("body.png")
	own = im != null and im.get_width() == FRAME.x * VIEWS and im.get_height() == FRAME.y * BODIES
	if not own:
		if im != null:
			print("sprites/body.png is %dx%d, %dx%d is needed: not used" % [im.get_width(), im.get_height(),
				FRAME.x * VIEWS, FRAME.y * BODIES])
		im = (load("res://assets/body.png") as Texture2D).get_image()
	else:
		Sprites.own_files.append("body.png")
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var out := Image.create(FRAME.x * VIEWS, FRAME.y * BODIES, false, Image.FORMAT_RGBA8)
	out.blit_rect(im, Rect2i(0, 0, mini(out.get_width(), im.get_width()), mini(out.get_height(), im.get_height())), Vector2i.ZERO)
	return out


static func build() -> Image:
	var src := source()
	_settle(src)
	var out := Image.create(CELL.x * 24, CELL.y * ALL_ROWS, false, Image.FORMAT_RGBA8)
	var shadow := _shadow()
	var navy := _navy(src)
	var grey := _paint(src, navy, UNDERSUIT)
	for colour in TINTS.size():
		var painted := _paint(src, navy, TINTS[colour])
		for look in Net.LOOKS:
			var art := grey if look / 2 == Net.OUTFIT_BARE else painted
			_row(out, colour * Net.LOOKS + look, art, shadow)
			_row(out, VISOR_ROW + colour * Net.LOOKS + look, art, shadow)
		_row(out, HALF_ROW + colour, painted, shadow)
	# the machines and the heavy boarders keep the old drawn pictures (their four straight ways, for both bodies)
	var old := Sprites.sheet("chars").get_image()
	if old.is_compressed():
		old.decompress()
	old.convert(Image.FORMAT_RGBA8)
	for colour in range(TINTS.size(), Net.ARMOUR_COLOUR + 1):
		for look in Net.LOOKS:
			var row := colour * Net.LOOKS + look
			for c in 12:
				var from := Rect2i(c * (OLD.x + 2) + PAD, row * (OLD.y + 2) + PAD, OLD.x, OLD.y)
				for at: int in [c, WOMAN_COLUMN + c]:
					out.blit_rect(old, from, Vector2i(at * CELL.x + PAD, row * CELL.y + PAD + FRAME.y - OLD.y))
	return out


static func _settle(src: Image) -> void:
	## Each body's row moved up or down so the lowest pixel of its figures stands on FEET.
	for b in BODIES:
		var used := src.get_region(Rect2i(0, b * FRAME.y, src.get_width(), FRAME.y)).get_used_rect()
		if used.size.y <= 0:
			continue
		var low := used.end.y - 1
		if low == FEET:
			continue
		var band := src.get_region(Rect2i(0, b * FRAME.y, src.get_width(), FRAME.y))
		src.fill_rect(Rect2i(0, b * FRAME.y, src.get_width(), FRAME.y), Color(0, 0, 0, 0))
		var shift := FEET - low
		var keep := Rect2i(0, maxi(0, -shift), src.get_width(), FRAME.y - absi(shift))
		src.blit_rect(band, keep, Vector2i(0, b * FRAME.y + maxi(0, shift)))


static func _navy(src: Image) -> PackedInt32Array:
	## The byte offsets of the clothes' navy pixels, each followed by its brightness in thousandths.
	var out := PackedInt32Array()
	var data := src.get_data()
	for i in range(0, data.size(), 4):
		if data[i + 3] == 0:
			continue
		var c := Color8(data[i], data[i + 1], data[i + 2])
		var hue := c.h * 360.0
		if c.s >= NAVY_SAT and hue >= NAVY_HUE.x and hue <= NAVY_HUE.y:
			out.append(i)
			out.append(roundi(c.v * 1000.0))
	return out


static func _paint(src: Image, navy: PackedInt32Array, tint: Color) -> Image:
	var data := src.get_data()
	for k in range(0, navy.size(), 2):
		var i := navy[k]
		var c := Color.from_hsv(tint.h, tint.s, clampf(navy[k + 1] / 1000.0 / NAVY_TOP * tint.v, 0.0, 1.0))
		data[i] = c.r8
		data[i + 1] = c.g8
		data[i + 2] = c.b8
	return Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8, data)


static func _shadow() -> Image:
	## A soft shadow under the feet, so the figure sits on the floor (as the old drawn ones had).
	var im := Image.create(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
	var halves := [9, 11, 11, 10, 7]
	for k in halves.size():
		var y := FEET - 2 + k
		if y >= FRAME.y:
			break
		for x in range(16 - halves[k], 16 + halves[k]):
			im.set_pixel(x, y, Color(0, 0, 0, 70.0 / 255.0))
	return im


static func _row(out: Image, row: int, art: Image, shadow: Image) -> void:
	for body in BODIES:
		var first := WOMAN_COLUMN if body == 0 else 0
		for way: int in VIEW_OF.keys():
			var figure := art.get_region(Rect2i(int(VIEW_OF[way]) * FRAME.x, body * FRAME.y, FRAME.x, FRAME.y))
			for pose in 3:
				var cell := Vector2i((first + int(COLUMN_OF[way]) + pose) * CELL.x + PAD, row * CELL.y + PAD)
				out.blit_rect(shadow, Rect2i(Vector2i.ZERO, FRAME), cell)
				out.blend_rect(figure, Rect2i(Vector2i.ZERO, FRAME), cell)
