extends RefCounted
## (v87, the author's base bodies: "man and woman, just for now") The people's sheet, made when the game
## starts from his base sheet (assets/body.png, or body.png in the «sprites» folder) and the old drawn
## sheet (assets/chars.png) for the machines. (v85's suited character, assets/crew.png, waits unused for
## the clothes drawn over the body later.)
##
## His sheet: frames of 32x48, four across (0 the front, looking down; 1 the right side; 2 the back; 3 the
## left side), the woman in the top row and the man below. Only four ways for now (his words): a slant
## shows the side it leans to (WorldView.FACING_COLUMN). No walking frames: the steps are made here (a bob
## and a lifted foot).
##
## What it makes: a row per colour and look (see Net.LOOKS), cells of CHAR_W x CHAR_H with a 1-pixel
## border; in each row the man's 12 frames (4 ways x 3: standing, step, step: down, up, left, right) and
## from WOMAN_COLUMN the woman's. VISOR_ROW + the same row with a glass bubble over the head while it
## breathes from its oxygen tank (the visor of v85's C2, until a helmet is drawn); HALF_ROW + colour the
## bubble half seen, for a moment while the tank is switched on or off.
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
const LIFT := 2                           # pixels a foot comes up on a made step
const GLASS := Color(0.70, 0.88, 1.0, 0.22)      # the bubble's glass
const RIM := Color(0.85, 0.95, 1.0, 0.75)        # its edge
const SHINE := Color(1.0, 1.0, 1.0, 0.85)        # a glint up on one side
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
	var full := _bubbles(src, 1.0)
	var half := _bubbles(src, 0.5)
	for colour in TINTS.size():
		var painted := _paint(src, navy, TINTS[colour])
		for look in Net.LOOKS:
			var art := grey if look / 2 == Net.OUTFIT_BARE else painted
			_row(out, colour * Net.LOOKS + look, art, null, shadow)
			_row(out, VISOR_ROW + colour * Net.LOOKS + look, art, full, shadow)
		_row(out, HALF_ROW + colour, painted, half, shadow)
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


static func _bubbles(src: Image, strength: float) -> Image:
	## (v87, S4) A sheet of the same size with a glass bubble round each figure's head, to lay over it.
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for b in BODIES:
		for v in VIEWS:
			var frame := Rect2i(v * FRAME.x, b * FRAME.y, FRAME.x, FRAME.y)
			var used := src.get_region(frame).get_used_rect()
			if used.size.y <= 0:
				continue
			# the head: the top 12 rows of the figure, its middle the mean of their pixels
			var top := used.position.y
			var sum := 0.0
			var n := 0
			for y in range(top, mini(top + 12, FRAME.y)):
				for x in FRAME.x:
					if src.get_pixel(frame.position.x + x, frame.position.y + y).a > 0.5:
						sum += x
						n += 1
			if n == 0:
				continue
			var centre := Vector2(sum / n + 0.5, top + 7.0)
			var radius := Vector2(9.5, 9.0)
			for y in range(maxi(0, int(centre.y - radius.y) - 1), mini(FRAME.y, int(centre.y + radius.y) + 2)):
				for x in range(maxi(0, int(centre.x - radius.x) - 1), mini(FRAME.x, int(centre.x + radius.x) + 2)):
					var d := Vector2((x + 0.5 - centre.x) / radius.x, (y + 0.5 - centre.y) / radius.y).length()
					if d > 1.0:
						continue
					var c := RIM if d > 0.86 else GLASS
					var glint := Vector2(x + 0.5 - (centre.x - radius.x * 0.45), y + 0.5 - (centre.y - radius.y * 0.5))
					if glint.length() < 1.6:
						c = SHINE
					c.a *= strength
					out.set_pixel(frame.position.x + x, frame.position.y + y, c)
	return out


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


static func _row(out: Image, row: int, art: Image, glass: Image, shadow: Image) -> void:
	for body in BODIES:
		var first := WOMAN_COLUMN if body == 0 else 0
		for way: int in VIEW_OF.keys():
			var at := Rect2i(int(VIEW_OF[way]) * FRAME.x, body * FRAME.y, FRAME.x, FRAME.y)
			var figure := art.get_region(at)
			if glass != null:
				figure.blend_rect(glass, at, Vector2i.ZERO)
			for pose in 3:
				var frame := figure if pose == 0 else _step(figure, pose == 1)
				var cell := Vector2i((first + int(COLUMN_OF[way]) + pose) * CELL.x + PAD, row * CELL.y + PAD)
				out.blit_rect(shadow, Rect2i(Vector2i.ZERO, FRAME), cell)
				out.blend_rect(frame, Rect2i(Vector2i.ZERO, FRAME), cell)


static func _step(frame: Image, left: bool) -> Image:
	## A made step: the figure a pixel up, one foot LIFT pixels higher still.
	var used := frame.get_used_rect()
	var out := Image.create(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(frame, Rect2i(0, 1, FRAME.x, FRAME.y - 1), Vector2i.ZERO)
	if used.size.y <= 0:
		return out
	var legs := maxi(6, used.size.y * 22 / 100)
	var low := used.end.y - 1                          # (one up in `out`)
	var half := Rect2i(0 if left else FRAME.x / 2, low - legs, FRAME.x / 2, legs + 1)
	out.fill_rect(Rect2i(half.position.x, half.position.y - 1, half.size.x, half.size.y), Color(0, 0, 0, 0))
	out.blend_rect(frame, half, half.position - Vector2i(0, 1 + LIFT))
	return out
