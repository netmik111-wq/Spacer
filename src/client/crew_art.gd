extends RefCounted
## (v85, the author's note "new character is here, my spriter is working hard") The people's sheet,
## made when the game starts from the spriter's character (assets/crew.png, or crew.png in the
## «sprites» folder) and the old drawn sheet (assets/chars.png) for the machines.
##
## His sheet: frames of 32x64, three columns of helmet looks (0 a face behind clear glass, 1 the
## visor half down, 2 the orange visor down) and five rows of views (0 back three-quarter, looking
## up-left; 1 front three-quarter, looking down-right; 2 the side, looking right; 3 the front; 4 the
## back). The other three ways are those mirrored. Optional walking columns: 3 and 4 two steps with
## the clear glass, 5 and 6 two steps with the visor down; without them the steps are made here (a
## bob and a lifted foot).
##
## What it makes has the old sheet's layout (see Net.LOOKS): a row per colour and look, 24 frames of
## 8 ways x 3 (standing, step, step), cells of CHAR_W x CHAR_H with a 1-pixel border; after those,
## HALF_ROW + colour holds the half-visor frames, shown for a moment while a suit goes on or off.
## The navy of his suit is repainted in the colour of the row (the job's, the pirates'); a grey
## undersuit for one with no jumpsuit.

const Net := preload("res://src/shared/net.gd")
const Sprites := preload("res://src/client/sprites.gd")

const FRAME := Vector2i(32, 64)        # a frame of his sheet, and of the made one
const PAD := 1
const CELL := FRAME + Vector2i(2 * PAD, 2 * PAD)
const VIEWS := 5
const FEET := 61                       # the lowest row of the figure in a frame (the shadow lies round it)
const OLD := Vector2i(32, 48)          # a frame of assets/chars.png (the machines), with its 1-pixel border
const ROWS := (Net.ARMOUR_COLOUR + 1) * Net.LOOKS
const HALF_ROW := ROWS                 # + colour: the half-visor frames
# the colours of the rows, as tools/make_assets.py has them (SUIT_COLOURS): the crew's jobs, then the pirates
const TINTS: Array[Color] = [
	Color8(200, 55, 45), Color8(47, 111, 208), Color8(58, 154, 74), Color8(217, 165, 32),
	Color8(138, 79, 200), Color8(217, 112, 42), Color8(42, 169, 184), Color8(201, 204, 212),
	Color8(112, 72, 40), Color8(128, 28, 24), Color8(44, 40, 46),
]
const UNDERSUIT := Color8(118, 120, 128)
const NAVY_HUE := Vector2(205.0, 252.0)   # degrees: what counts as the suit's navy
const NAVY_SAT := 0.28
const NAVY_TOP := 0.45                    # the lightest navy: it becomes the colour itself
const LIFT := 2                           # pixels a foot comes up on a made step
# per our way (Net.DIR_*): his view and whether it is mirrored
const VIEW_OF := {
	Net.DIR_DOWN: [3, false], Net.DIR_UP: [4, false], Net.DIR_LEFT: [2, true], Net.DIR_RIGHT: [2, false],
	Net.DIR_DOWN_LEFT: [1, true], Net.DIR_DOWN_RIGHT: [1, false], Net.DIR_UP_LEFT: [0, false], Net.DIR_UP_RIGHT: [0, true],
}
# the first column of each way in the made sheet (as WorldView.FACING_COLUMN)
const COLUMN_OF := {Net.DIR_DOWN: 0, Net.DIR_UP: 3, Net.DIR_LEFT: 6, Net.DIR_RIGHT: 9,
	Net.DIR_DOWN_LEFT: 12, Net.DIR_DOWN_RIGHT: 15, Net.DIR_UP_LEFT: 18, Net.DIR_UP_RIGHT: 21}

static var _sheet: Texture2D = null
static var own := false                 # the spriter's sheet came from the «sprites» folder
static var walking_drawn := false       # his sheet has walking columns


static func sheet() -> Texture2D:
	if _sheet == null:
		_sheet = ImageTexture.create_from_image(build())
	return _sheet


static func forget() -> void:
	_sheet = null


static func source() -> Image:
	## His sheet, from the «sprites» folder or the game's own, as RGBA with whole frames.
	var im := Sprites.own_image("crew.png")
	own = im != null and im.get_width() >= FRAME.x * 3 and im.get_height() >= FRAME.y * VIEWS - 8
	if not own:
		if im != null:
			print("sprites/crew.png is %dx%d, at least %dx%d is needed: not used" % [im.get_width(), im.get_height(),
				FRAME.x * 3, FRAME.y * VIEWS])
		im = (load("res://assets/crew.png") as Texture2D).get_image()
	else:
		Sprites.own_files.append("crew.png")
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var w := maxi(FRAME.x * 3, im.get_width() - im.get_width() % FRAME.x)
	var out := Image.create(w, FRAME.y * VIEWS, false, Image.FORMAT_RGBA8)
	out.blit_rect(im, Rect2i(0, 0, mini(w, im.get_width()), mini(out.get_height(), im.get_height())), Vector2i.ZERO)
	walking_drawn = w >= FRAME.x * 7
	return out


static func build() -> Image:
	var src := source()
	var cols := src.get_width() / FRAME.x
	_settle(src, cols)
	var out := Image.create(CELL.x * 24, CELL.y * (ROWS + Net.ARMOUR_COLOUR + 1), false, Image.FORMAT_RGBA8)
	var shadow := _shadow()
	var navy := _navy(src)
	var grey := _paint(src, navy, UNDERSUIT)
	var grey_m := grey.duplicate() as Image
	grey_m.flip_x()
	for colour in TINTS.size():
		var painted := _paint(src, navy, TINTS[colour])
		var mirrored := painted.duplicate() as Image
		mirrored.flip_x()
		for look in Net.LOOKS:
			var outfit := look / 2
			var art := grey if outfit == Net.OUTFIT_BARE else painted
			var art_m := grey_m if outfit == Net.OUTFIT_BARE else mirrored
			var helmet := 2 if outfit == Net.OUTFIT_SUIT else 0
			_row(out, colour * Net.LOOKS + look, art, art_m, cols, helmet, shadow)
		_row(out, HALF_ROW + colour, painted, mirrored, cols, 1, shadow)
	# the machines and the heavy boarders keep the old drawn pictures
	var old := Sprites.sheet("chars").get_image()
	if old.is_compressed():
		old.decompress()
	old.convert(Image.FORMAT_RGBA8)
	for colour in range(TINTS.size(), Net.ARMOUR_COLOUR + 1):
		for look in Net.LOOKS:
			var row := colour * Net.LOOKS + look
			for c in 24:
				var from := Rect2i(c * (OLD.x + 2) + PAD, row * (OLD.y + 2) + PAD, OLD.x, OLD.y)
				out.blit_rect(old, from, Vector2i(c * CELL.x + PAD, row * CELL.y + PAD + FRAME.y - OLD.y))
	return out


static func _settle(src: Image, cols: int) -> void:
	## Each view's row moved up or down so the lowest pixel of its figures stands on FEET.
	for v in VIEWS:
		var low := -1
		for c in cols:
			var used := src.get_region(Rect2i(c * FRAME.x, v * FRAME.y, FRAME.x, FRAME.y)).get_used_rect()
			if used.size.y > 0:
				low = maxi(low, used.end.y - 1)
		if low < 0 or low == FEET:
			continue
		var band := src.get_region(Rect2i(0, v * FRAME.y, src.get_width(), FRAME.y))
		src.fill_rect(Rect2i(0, v * FRAME.y, src.get_width(), FRAME.y), Color(0, 0, 0, 0))
		var shift := FEET - low
		var keep := Rect2i(0, maxi(0, -shift), src.get_width(), FRAME.y - absi(shift))
		src.blit_rect(band, keep, Vector2i(0, v * FRAME.y + maxi(0, shift)))


static func _navy(src: Image) -> PackedInt32Array:
	## The byte offsets of the suit's navy pixels, each followed by its brightness in thousandths.
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


static func _row(out: Image, row: int, art: Image, art_m: Image, cols: int, helmet: int, shadow: Image) -> void:
	var width := art.get_width()
	for way: int in VIEW_OF.keys():
		var view: int = VIEW_OF[way][0]
		var flip: bool = VIEW_OF[way][1]
		var from := art_m if flip else art
		for pose in 3:
			var col := helmet
			var drawn := walking_drawn and pose > 0 and helmet != 1
			if drawn:
				col = (3 if helmet == 0 else 5) + pose - 1
			# a column in the mirrored sheet counts from its other side
			var x := width - (col + 1) * FRAME.x if flip else col * FRAME.x
			var frame := from.get_region(Rect2i(x, view * FRAME.y, FRAME.x, FRAME.y))
			if pose > 0 and not drawn:
				frame = _step(frame, pose == 1)
			var cell := Vector2i((int(COLUMN_OF[way]) + pose) * CELL.x + PAD, row * CELL.y + PAD)
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
