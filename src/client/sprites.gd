extends RefCounted
## (v74, the author's N7) Pictures of one's own, as the «sounds» folder is for sounds: a PNG
## file of the right name in the «sprites» folder next to the game is used instead of the
## game's own picture. Sheets (the characters, the tiles, the hole in the hull, the health
## monitor and the warning lamps) must keep their size, as the game cuts frames out of them;
## a thing's picture (item_<number>.png, see dist_files/sprites/README.txt) may be any square
## size and is drawn in its slot, on the floor and in the hand. Files are read once, when the
## game first wants them.

const Items := preload("res://src/shared/items.gd")

# the sheets that can be replaced: file name -> where the game's own lies
const SHEETS := {
	"chars": "res://assets/chars.png",
	"tiles": "res://assets/tiles.png",
	"breach": "res://assets/breach.png",
	"hud_monitor": "res://assets/hud_monitor.png",
	"hud_alerts": "res://assets/hud_alerts.png",
	"shuttle": "res://assets/shuttle.png",   # (v86) the fleet's shuttle, nose up (4 x 3 tiles)
	# (v100) what people wear, laid out as body.png (4 ways x the woman, the man): placeholders the artist replaces
	"wear_jumpsuit": "res://assets/wear_jumpsuit.png",
	"wear_vest": "res://assets/wear_vest.png",
	"wear_helmet": "res://assets/wear_helmet.png",
	"wear_belt": "res://assets/wear_belt.png",
	"wear_riot": "res://assets/wear_riot.png",
	"wear_nvg": "res://assets/wear_nvg.png",
	"wear_thermal": "res://assets/wear_thermal.png",
	"wear_pack": "res://assets/wear_pack.png",
}

static var own_files := PackedStringArray()   # the pictures of one's own in use (for the log)
static var _sheets := {}                       # name -> Texture2D
static var _items := {}                        # item_<kind> -> Texture2D, or null: none of one's own


static func dirs() -> PackedStringArray:
	## Where pictures of one's own are looked for: next to the game, and (run from the project) in its folder.
	return PackedStringArray([OS.get_executable_path().get_base_dir().path_join("sprites"),
		ProjectSettings.globalize_path("res://").path_join("sprites")])


static func sheet(name: String) -> Texture2D:
	## A sheet of the game's pictures, or the one of the same name and size in the folder.
	if _sheets.has(name):
		return _sheets[name]
	var own: Texture2D = load(SHEETS[name])
	var tex := own
	var file := _own(name + ".png")
	if file != null:
		if Vector2(file.get_size()) == own.get_size():
			tex = ImageTexture.create_from_image(file)
			own_files.append(name + ".png")
		elif file.get_width() == int(own.get_width()) and file.get_height() < int(own.get_height()):
			# (v81) a sheet drawn for an older build, before new pictures were added at its bottom:
			# laid over the game's own, so the new pictures still show
			var whole := own.get_image()
			if whole.is_compressed():
				whole.decompress()
			whole.convert(Image.FORMAT_RGBA8)
			file.convert(Image.FORMAT_RGBA8)
			whole.blit_rect(file, Rect2i(Vector2i.ZERO, file.get_size()), Vector2i.ZERO)
			tex = ImageTexture.create_from_image(whole)
			own_files.append(name + ".png")
		else:
			print("sprites/%s.png is %dx%d, the game's is %dx%d: not used" % [name, file.get_width(), file.get_height(),
				own.get_width(), own.get_height()])
	_sheets[name] = tex
	return tex


static func reload() -> void:
	## (v81, the author's E11) Forget what was read, so the next ask reads the folder again (the
	## ship editor's «Обновить картинки»).
	_sheets.clear()
	_items.clear()
	own_files.clear()


static func item_key(item: int) -> String:
	## The name of a thing's picture: one for every kind (a pistol whatever its rounds).
	return "item_%d" % Items.kind_of(item)


static func item(item: int) -> Texture2D:
	## The picture of one's own for that thing, or null (the game draws its own).
	var key := item_key(item)
	if _items.has(key):
		return _items[key]
	var file := _own(key + ".png")
	var tex: Texture2D = ImageTexture.create_from_image(file) if file != null else null
	if tex != null:
		own_files.append(key + ".png")
	_items[key] = tex
	return tex


static func own_image(file: String) -> Image:
	## (v85) A picture of one's own of that name in the folder, or null.
	return _own(file)


static func _own(file: String) -> Image:
	for dir in dirs():
		var path := dir.path_join(file)
		if FileAccess.file_exists(path):
			var im := Image.load_from_file(path)
			if im != null and not im.is_empty():
				return im
	return null
