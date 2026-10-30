extends RefCounted
## Pictures of the things that can be carried, drawn in code into any square:
## a slot on the screen or a spot on the floor. Each is laid out on a 17 by 17 grid.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Gear := preload("res://src/shared/gear.gd")
const Plants := preload("res://src/shared/plants.gd")
const Sprites := preload("res://src/client/sprites.gd")

# the colour a ship weapon's picture is marked with, by its class (Weapons.CLASS_*)
const GUN_MARK: Array[Color] = [Color(1.0, 0.45, 0.2), Color(0.85, 0.55, 1.0), Color(0.4, 1.0, 0.45), Color(0.85, 0.85, 0.8), Color(0.35, 0.65, 1.0),
	Color(0.55, 1.0, 0.7), Color(0.3, 0.95, 1.0), Color(1.0, 0.4, 0.85), Color(0.95, 0.85, 0.4), Color(0.9, 0.9, 0.95),
	Color(0.7, 1.0, 0.55)]
# (v58) the frame of a tier's gun: plain, steel, gold (a tier is not told; the look is)
const TIER_RIM: Array[Color] = [Color(0.12, 0.12, 0.15), Color(0.12, 0.12, 0.15), Color(0.3, 0.34, 0.42), Color(0.75, 0.6, 0.2)]
# parts of a kind of gun (Weapons.KIND_*): the colour of their mark
const KIND_MARK: Array[Color] = [Color(1.0, 0.45, 0.2), Color(0.35, 0.65, 1.0), Color(0.85, 0.85, 0.8), Color(0.85, 0.55, 1.0), Color(0.95, 0.85, 0.4)]


static func draw(canvas: CanvasItem, cell: Rect2, item: int) -> void:
	var own := Sprites.item(item)
	if own != null:
		canvas.draw_texture_rect(own, cell, false)      # (v74) a picture of one's own (the «sprites» folder)
		return
	var u := cell.size.x / 17.0
	var at := cell.position
	if item >= Net.ITEM_PISTOL and item <= Net.ITEM_PISTOL + Net.PISTOL_ROUNDS:
		# a pistol, and a pip for every round left in it
		canvas.draw_rect(Rect2(at + Vector2(2, 4) * u, Vector2(12, 4) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(10, 2) * u), Color(0.42, 0.44, 0.5))
		canvas.draw_rect(Rect2(at + Vector2(4, 7) * u, Vector2(4, 6) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(5, 8) * u, Vector2(2, 4) * u), Color(0.45, 0.28, 0.16))
		var n := item - Net.ITEM_PISTOL
		for k in Net.PISTOL_ROUNDS:
			canvas.draw_rect(Rect2(at + Vector2(9 + (k % 4) * 1.6, 9 + (k / 4) * 2.2) * u, Vector2(1, 1.4) * u),
				Color(0.95, 0.75, 0.25) if k < n else Color(0.25, 0.25, 0.3))
		return
	if item >= Net.ITEM_SHOTGUN and item <= Net.ITEM_SHOTGUN + Net.SHOTGUN_ROUNDS:
		# (v70) a shotgun: a long double barrel, a wooden stock, a pip for every shell in it
		canvas.draw_rect(Rect2(at + Vector2(1, 6) * u, Vector2(15, 3) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(6, 6.5) * u, Vector2(10, 1) * u), Color(0.45, 0.47, 0.52))
		canvas.draw_rect(Rect2(at + Vector2(6, 7.6) * u, Vector2(10, 0.8) * u), Color(0.35, 0.37, 0.42))
		canvas.draw_rect(Rect2(at + Vector2(1, 7) * u, Vector2(6, 4.5) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(1.5, 7.5) * u, Vector2(5, 3.5) * u), Color(0.5, 0.3, 0.15))
		var n := item - Net.ITEM_SHOTGUN
		for k in Net.SHOTGUN_ROUNDS:
			canvas.draw_rect(Rect2(at + Vector2(8 + k * 2, 11) * u, Vector2(1.3, 2) * u), Color(0.85, 0.2, 0.15) if k < n else Color(0.25, 0.25, 0.3))
		return
	if item >= Net.ITEM_LASER_GUN and item <= Net.ITEM_LASER_GUN + Net.LASER_ROUNDS:
		# (v98) a laser rifle: a long white body, a red lens at the muzzle, a pip for every charge
		canvas.draw_rect(Rect2(at + Vector2(1, 5) * u, Vector2(15, 4) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(2, 6) * u, Vector2(13, 2) * u), Color(0.82, 0.84, 0.88))
		canvas.draw_rect(Rect2(at + Vector2(14.5, 6) * u, Vector2(1.5, 2) * u), Color(1.0, 0.2, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(3, 9) * u, Vector2(3, 4) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(8, 9) * u, Vector2(3, 2.5) * u), Color(0.25, 0.55, 0.85))
		for k in Net.LASER_ROUNDS:
			canvas.draw_rect(Rect2(at + Vector2(2 + k * 1.4, 14) * u, Vector2(1, 1.4) * u),
				Color(1.0, 0.35, 0.3) if k < item - Net.ITEM_LASER_GUN else Color(0.25, 0.25, 0.3))
		return
	if item >= Net.ITEM_PLASMA_GUN and item <= Net.ITEM_PLASMA_GUN + Net.PLASMA_ROUNDS:
		# (v98) a plasma gun: a stubby dark body with a glowing green coil, a pip for every charge
		canvas.draw_rect(Rect2(at + Vector2(2, 5) * u, Vector2(12, 6) * u), Color(0.1, 0.1, 0.12))
		canvas.draw_rect(Rect2(at + Vector2(3, 6) * u, Vector2(10, 4) * u), Color(0.32, 0.36, 0.34))
		for k in 3:
			canvas.draw_rect(Rect2(at + Vector2(5 + k * 2.5, 6) * u, Vector2(1.2, 4) * u), Color(0.4, 1.0, 0.5))
		canvas.draw_circle(at + Vector2(14.5, 8) * u, 1.6 * u, Color(0.6, 1.0, 0.6))
		canvas.draw_rect(Rect2(at + Vector2(4, 11) * u, Vector2(3, 3) * u), Color(0.1, 0.1, 0.12))
		for k in Net.PLASMA_ROUNDS:
			canvas.draw_rect(Rect2(at + Vector2(9 + k * 1.8, 12) * u, Vector2(1.2, 1.6) * u),
				Color(0.4, 1.0, 0.5) if k < item - Net.ITEM_PLASMA_GUN else Color(0.25, 0.25, 0.3))
		return
	match item:
		Net.ITEM_VEST:
			# (v98) a bulletproof vest: dark plates, a grey strap
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(4, 2) * u, at + Vector2(7, 4) * u, at + Vector2(10, 4) * u,
				at + Vector2(13, 2) * u, at + Vector2(14, 15) * u, at + Vector2(3, 15) * u]), Color(0.1, 0.1, 0.12))
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(5, 3.5) * u, at + Vector2(7, 5) * u, at + Vector2(10, 5) * u,
				at + Vector2(12, 3.5) * u, at + Vector2(13, 14) * u, at + Vector2(4, 14) * u]), Color(0.3, 0.36, 0.3))
			canvas.draw_rect(Rect2(at + Vector2(5, 9) * u, Vector2(7, 1.2) * u), Color(0.55, 0.57, 0.6))
			return
		Net.ITEM_HELMET:
			# (v98) a combat helmet: a dome with a visor strip
			canvas.draw_circle(at + Vector2(8.5, 9) * u, 6.0 * u, Color(0.1, 0.1, 0.12))
			canvas.draw_circle(at + Vector2(8.5, 9) * u, 5.0 * u, Color(0.34, 0.4, 0.32))
			canvas.draw_rect(Rect2(at + Vector2(2, 10) * u, Vector2(13, 5) * u), Color(0, 0, 0, 0))
			canvas.draw_rect(Rect2(at + Vector2(3, 11) * u, Vector2(11, 2) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(5, 8.5) * u, Vector2(7, 1.6) * u), Color(0.55, 0.75, 0.9))
			return
		Net.ITEM_RIOT:
			# (v98) a hand shield: a tall plate with a window
			canvas.draw_rect(Rect2(at + Vector2(4, 1) * u, Vector2(9, 15) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(5, 2) * u, Vector2(7, 13) * u), Color(0.45, 0.48, 0.55))
			canvas.draw_rect(Rect2(at + Vector2(6, 3.5) * u, Vector2(5, 2.5) * u), Color(0.6, 0.85, 1.0, 0.8))
			canvas.draw_rect(Rect2(at + Vector2(5, 9) * u, Vector2(7, 1) * u), Color(0.95, 0.85, 0.3))
			return
		Net.ITEM_ESHIELD:
			# (v98) a personal energy shield: a belt box with a blue ring over it
			canvas.draw_rect(Rect2(at + Vector2(2, 10) * u, Vector2(13, 3) * u), Color(0.25, 0.2, 0.15))
			canvas.draw_rect(Rect2(at + Vector2(6, 8) * u, Vector2(5, 6) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(7, 9) * u, Vector2(3, 4) * u), Color(0.3, 0.55, 0.9))
			canvas.draw_arc(at + Vector2(8.5, 9) * u, 6.5 * u, PI * 1.1, PI * 1.9, 12, Color(0.5, 0.8, 1.0), 1.2 * u)
			return
		Net.ITEM_CELL:
			# (v98) an energy cell: a stubby battery with a glowing band
			canvas.draw_rect(Rect2(at + Vector2(5, 3) * u, Vector2(7, 12) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(6, 4) * u, Vector2(5, 10) * u), Color(0.5, 0.52, 0.58))
			canvas.draw_rect(Rect2(at + Vector2(7, 1.5) * u, Vector2(3, 1.5) * u), Color(0.75, 0.75, 0.8))
			canvas.draw_rect(Rect2(at + Vector2(6, 7) * u, Vector2(5, 3) * u), Color(0.45, 0.95, 1.0))
			return
	if item > Net.ITEM_MEDKIT and item <= Net.ITEM_MEDKIT + Net.MEDKIT_USES:
		# a first-aid kit: a white box with a red cross, and a pip for every use left
		canvas.draw_rect(Rect2(at + Vector2(2, 4) * u, Vector2(13, 10) * u), Color(0.15, 0.15, 0.18))
		canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 8) * u), Color(0.9, 0.9, 0.88))
		canvas.draw_rect(Rect2(at + Vector2(6, 2.5) * u, Vector2(5, 2) * u), Color(0.15, 0.15, 0.18))
		canvas.draw_rect(Rect2(at + Vector2(7.5, 6) * u, Vector2(2, 6) * u), Color(0.85, 0.15, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(5.5, 8) * u, Vector2(6, 2) * u), Color(0.85, 0.15, 0.15))
		for k in Net.MEDKIT_USES:
			canvas.draw_rect(Rect2(at + Vector2(3.5 + k * 2.2, 14.5) * u, Vector2(1.4, 1.2) * u),
				Color(0.4, 0.9, 0.5) if k < item - Net.ITEM_MEDKIT else Color(0.25, 0.25, 0.3))
		return
	if item >= Net.ITEM_SUIT and item <= Net.ITEM_SUIT + Net.SUIT_TANK_STEPS:
		# a helmet with its orange visor, and a gauge of the oxygen left in the tank
		canvas.draw_rect(Rect2(at + Vector2(3, 2) * u, Vector2(11, 11) * u), Color(0.15, 0.15, 0.19))
		canvas.draw_rect(Rect2(at + Vector2(4, 3) * u, Vector2(9, 9) * u), Color(0.42, 0.43, 0.5))
		canvas.draw_rect(Rect2(at + Vector2(5, 5) * u, Vector2(7, 3) * u), Color(0.95, 0.5, 0.18))
		canvas.draw_rect(Rect2(at + Vector2(6, 9) * u, Vector2(5, 3) * u), Color(0.25, 0.25, 0.3))
		var left := float(item - Net.ITEM_SUIT) / Net.SUIT_TANK_STEPS
		canvas.draw_rect(Rect2(at + Vector2(3, 14) * u, Vector2(11, 1.6) * u), Color(0.15, 0.15, 0.19))
		canvas.draw_rect(Rect2(at + Vector2(3, 14) * u, Vector2(11 * left, 1.6) * u), Color(0.35, 0.75, 0.95))
		return
	if Plants.is_seed(item):
		# (v63) a packet of seeds: a paper sachet with the plant's leaf on it; a mutated seed's packet has a gold corner
		canvas.draw_rect(Rect2(at + Vector2(4, 3) * u, Vector2(9, 12) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(5, 4) * u, Vector2(7, 10) * u), Color(0.86, 0.8, 0.62))
		var leaf: Color = Plants.KINDS[Plants.kind_of(item)]["leaf"]
		canvas.draw_circle(at + Vector2(8.5, 9) * u, 2.6 * u, leaf)
		canvas.draw_line(at + Vector2(8.5, 12) * u, at + Vector2(8.5, 9) * u, leaf.darkened(0.4), 0.8 * u)
		if Plants.trait_of(item) != Plants.PLAIN:
			canvas.draw_rect(Rect2(at + Vector2(10, 4) * u, Vector2(2, 2) * u), Color(0.95, 0.78, 0.25))
		return
	if item == Net.ITEM_FOOD:
		# (v63) a ration: a foil pack with a label
		canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 8) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(4, 6) * u, Vector2(9, 6) * u), Color(0.7, 0.72, 0.68))
		canvas.draw_rect(Rect2(at + Vector2(5.5, 7.5) * u, Vector2(6, 3) * u), Color(0.85, 0.55, 0.25))
		return
	if item == Net.ITEM_SCRAP:
		# (v67) scrap: a bent plate of hull and a torn strip
		canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(2, 9) * u, at + Vector2(9, 5) * u, at + Vector2(14, 8) * u,
			at + Vector2(12, 14) * u, at + Vector2(4, 13) * u]), Color(0.12, 0.12, 0.15))
		canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(3, 9.5) * u, at + Vector2(9, 6) * u, at + Vector2(13, 8.5) * u,
			at + Vector2(11.5, 13) * u, at + Vector2(4.5, 12) * u]), Color(0.5, 0.48, 0.45))
		canvas.draw_line(at + Vector2(5, 10) * u, at + Vector2(11, 11) * u, Color(0.65, 0.35, 0.2), 0.9 * u)
		canvas.draw_rect(Rect2(at + Vector2(10, 3) * u, Vector2(2, 4) * u), Color(0.38, 0.4, 0.46))
		return
	if item == Net.ITEM_ORE:
		# (v67) a lump of ore with glinting veins
		canvas.draw_circle(at + Vector2(8.5, 9.5) * u, 5.5 * u, Color(0.12, 0.12, 0.15))
		canvas.draw_circle(at + Vector2(8.5, 9.5) * u, 4.6 * u, Color(0.42, 0.33, 0.28))
		canvas.draw_circle(at + Vector2(6.5, 8) * u, 1.0 * u, Color(0.4, 0.85, 0.8))
		canvas.draw_circle(at + Vector2(10.5, 11) * u, 0.8 * u, Color(0.4, 0.85, 0.8))
		canvas.draw_circle(at + Vector2(9.5, 7) * u, 0.6 * u, Color(0.95, 0.8, 0.4))
		return
	if item == Net.ITEM_DATA:
		# (v67) a data core: a chip with a glowing stripe
		canvas.draw_rect(Rect2(at + Vector2(3, 4) * u, Vector2(11, 10) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(4, 5) * u, Vector2(9, 8) * u), Color(0.2, 0.3, 0.38))
		canvas.draw_rect(Rect2(at + Vector2(5, 8) * u, Vector2(7, 1.4) * u), Color(0.75, 0.5, 1.0))
		for k in 4:
			canvas.draw_rect(Rect2(at + Vector2(4.5 + k * 2.4, 14) * u, Vector2(1, 1.5) * u), Color(0.8, 0.7, 0.3))
		return
	if item == Net.ITEM_CARGO:
		# (v63) a quest's crate: a stencilled box
		canvas.draw_rect(Rect2(at + Vector2(2, 4) * u, Vector2(13, 10) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 8) * u), Color(0.55, 0.42, 0.25))
		canvas.draw_line(at + Vector2(3, 5) * u, at + Vector2(14, 13) * u, Color(0.35, 0.25, 0.14), 0.8 * u)
		canvas.draw_line(at + Vector2(14, 5) * u, at + Vector2(3, 13) * u, Color(0.35, 0.25, 0.14), 0.8 * u)
		return
	if item == Net.ITEM_BLACKBOX:
		# (v63) a black box (that is orange, as they are), with a blinking light
		canvas.draw_rect(Rect2(at + Vector2(3, 4) * u, Vector2(11, 10) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(4, 5) * u, Vector2(9, 8) * u), Color(0.95, 0.5, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(4, 8) * u, Vector2(9, 1.2) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_circle(at + Vector2(11.5, 6.5) * u, 0.9 * u, Color(1.0, 0.25, 0.2))
		return
	if item == Net.ITEM_ROBOT:
		# (v62) a security robot folded in its crate: a squat steel body, a green eye, a gun arm
		canvas.draw_rect(Rect2(at + Vector2(3, 4) * u, Vector2(11, 10) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(4, 5) * u, Vector2(9, 8) * u), Color(0.55, 0.58, 0.64))
		canvas.draw_rect(Rect2(at + Vector2(5, 6.5) * u, Vector2(7, 2.4) * u), Color(0.1, 0.12, 0.14))
		canvas.draw_circle(at + Vector2(8.5, 7.7) * u, 1.0 * u, Color(0.4, 1.0, 0.55))
		canvas.draw_rect(Rect2(at + Vector2(12.5, 9.5) * u, Vector2(3.5, 1.6) * u), Color(0.2, 0.2, 0.24))
		canvas.draw_rect(Rect2(at + Vector2(5, 13.5) * u, Vector2(2, 1.5) * u), Color(0.2, 0.2, 0.24))
		canvas.draw_rect(Rect2(at + Vector2(10, 13.5) * u, Vector2(2, 1.5) * u), Color(0.2, 0.2, 0.24))
		return
	if Gear.of_item(item) != Gear.NONE:
		_crate(canvas, at, u, Gear.of_item(item))
		return
	if Weapons.of_item(item) != Weapons.NONE:
		_ship_gun(canvas, at, u, Weapons.of_item(item))
		if Weapons.fx_of(item) != Weapons.FX_NONE:
			# (v58) a gun with an effect: a little star
			canvas.draw_circle(at + Vector2(14.5, 14.5) * u, 1.6 * u, Color(1.0, 0.9, 0.4))
		if Weapons.damaged(item):
			# (v58) damaged: scorched and cracked
			canvas.draw_rect(Rect2(at + Vector2(2, 7) * u, Vector2(14, 8) * u), Color(0.1, 0.06, 0.04, 0.45))
			canvas.draw_line(at + Vector2(3, 8) * u, at + Vector2(7, 13) * u, Color(0.95, 0.35, 0.2), 0.8 * u)
			canvas.draw_line(at + Vector2(7, 13) * u, at + Vector2(11, 9) * u, Color(0.95, 0.35, 0.2), 0.8 * u)
		return
	if item >= Net.ITEM_GUN_PARTS and item < Net.ITEM_GUN_PARTS + Weapons.KINDS:
		# (v58) gun parts: a coil, a plate and a bolt, marked with their kind's colour
		var mark: Color = KIND_MARK[item - Net.ITEM_GUN_PARTS]
		canvas.draw_rect(Rect2(at + Vector2(2, 9) * u, Vector2(7, 5) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(3, 10) * u, Vector2(5, 3) * u), Color(0.5, 0.53, 0.6))
		for k in 3:
			canvas.draw_rect(Rect2(at + Vector2(10 + k * 1.6, 4) * u, Vector2(1.0, 6) * u), mark)
		canvas.draw_rect(Rect2(at + Vector2(9.5, 12) * u, Vector2(5, 2) * u), Color(0.38, 0.4, 0.46))
		canvas.draw_rect(Rect2(at + Vector2(4, 4) * u, Vector2(3, 3) * u), mark)
		return
	if item == Net.ITEM_SHELL:
		# (v58) a shell standing up: a brass case and a dark tip
		canvas.draw_rect(Rect2(at + Vector2(6, 6) * u, Vector2(5, 9) * u), Color(0.12, 0.1, 0.06))
		canvas.draw_rect(Rect2(at + Vector2(7, 7) * u, Vector2(3, 7) * u), Color(0.85, 0.65, 0.25))
		canvas.draw_rect(Rect2(at + Vector2(7, 3) * u, Vector2(3, 4) * u), Color(0.35, 0.35, 0.4))
		return
	if item == Net.ITEM_ROCKET or item == Net.ITEM_EMP_ROCKET:
		# a rocket lying across: a grey body, a coloured nose, fins at the tail
		var nose := Color(0.85, 0.25, 0.18) if item == Net.ITEM_ROCKET else Color(0.35, 0.6, 1.0)
		canvas.draw_line(at + Vector2(3, 13) * u, at + Vector2(13, 4) * u, Color(0.1, 0.1, 0.12), 4.2 * u)
		canvas.draw_line(at + Vector2(3.5, 12.5) * u, at + Vector2(12, 5) * u, Color(0.72, 0.74, 0.78), 2.6 * u)
		canvas.draw_line(at + Vector2(11, 6) * u, at + Vector2(14, 3) * u, nose, 2.6 * u)
		canvas.draw_line(at + Vector2(2, 11) * u, at + Vector2(5, 14) * u, Color(0.3, 0.3, 0.36), 1.4 * u)
		return
	if item == Net.ITEM_PROBE:
		# a probe: a round body with a sensor eye, two antennae and small fins
		canvas.draw_circle(at + Vector2(8.5, 9) * u, 5.2 * u, Color(0.12, 0.12, 0.15))
		canvas.draw_circle(at + Vector2(8.5, 9) * u, 4.2 * u, Color(0.62, 0.66, 0.72))
		canvas.draw_circle(at + Vector2(8.5, 9) * u, 1.8 * u, Color(0.3, 0.85, 1.0))
		canvas.draw_line(at + Vector2(6, 5) * u, at + Vector2(3.5, 1.5) * u, Color(0.12, 0.12, 0.15), 1.0 * u)
		canvas.draw_line(at + Vector2(11, 5) * u, at + Vector2(13.5, 1.5) * u, Color(0.12, 0.12, 0.15), 1.0 * u)
		canvas.draw_rect(Rect2(at + Vector2(3, 3) * u, Vector2(1.2, 1.2) * u), Color(0.95, 0.35, 0.3))
		canvas.draw_rect(Rect2(at + Vector2(13, 3) * u, Vector2(1.2, 1.2) * u), Color(0.95, 0.35, 0.3))
		canvas.draw_rect(Rect2(at + Vector2(2, 12) * u, Vector2(3, 2) * u), Color(0.3, 0.32, 0.38))
		canvas.draw_rect(Rect2(at + Vector2(12, 12) * u, Vector2(3, 2) * u), Color(0.3, 0.32, 0.38))
		return
	if item == Net.ITEM_DRONE:
		# a scouting drone seen from above: a flat body, four rotor rings and an orange eye
		for c: Vector2 in [Vector2(4, 4), Vector2(13, 4), Vector2(4, 13), Vector2(13, 13)]:
			canvas.draw_line(at + Vector2(8.5, 8.5) * u, at + c * u, Color(0.12, 0.12, 0.15), 1.6 * u)
			canvas.draw_arc(at + c * u, 2.6 * u, 0.0, TAU, 12, Color(0.55, 0.58, 0.64), 1.2 * u)
		canvas.draw_rect(Rect2(at + Vector2(5.5, 6) * u, Vector2(6, 5) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(6, 6.5) * u, Vector2(5, 4) * u), Color(0.42, 0.45, 0.5))
		canvas.draw_circle(at + Vector2(8.5, 8.5) * u, 1.3 * u, Color(1.0, 0.6, 0.2))
		return
	match item:
		Net.ITEM_JUMPSUIT:
			# a folded jumpsuit with a collar and a pocket
			canvas.draw_rect(Rect2(at + Vector2(3, 3) * u, Vector2(11, 11) * u), Color(0.15, 0.15, 0.19))
			canvas.draw_rect(Rect2(at + Vector2(4, 4) * u, Vector2(9, 9) * u), Color(0.35, 0.45, 0.62))
			canvas.draw_rect(Rect2(at + Vector2(6, 4) * u, Vector2(5, 2) * u), Color(0.5, 0.6, 0.78))
			canvas.draw_rect(Rect2(at + Vector2(8, 6) * u, Vector2(1, 7) * u), Color(0.2, 0.26, 0.38))
			canvas.draw_rect(Rect2(at + Vector2(10, 8) * u, Vector2(2, 2) * u), Color(0.2, 0.26, 0.38))
		Net.ITEM_NVG, Net.ITEM_THERMAL:
			# (v93) goggles: a strap and two lenses, green for night vision, orange for heat
			var lens := Color(0.35, 1.0, 0.4) if item == Net.ITEM_NVG else Color(1.0, 0.5, 0.15)
			canvas.draw_rect(Rect2(at + Vector2(1.5, 7.5) * u, Vector2(14, 2) * u), Color(0.2, 0.2, 0.22))
			for x: float in [5.0, 12.0]:
				canvas.draw_circle(at + Vector2(x, 8.5) * u, 3.4 * u, Color(0.1, 0.1, 0.12))
				canvas.draw_circle(at + Vector2(x, 8.5) * u, 2.3 * u, lens)
				canvas.draw_circle(at + Vector2(x - 0.8, 7.6) * u, 0.7 * u, Color(1, 1, 1, 0.7))
		Net.ITEM_BACKPACK:
			# a backpack with a flap and two straps
			canvas.draw_rect(Rect2(at + Vector2(4, 3) * u, Vector2(9, 12) * u), Color(0.2, 0.15, 0.1))
			canvas.draw_rect(Rect2(at + Vector2(5, 4) * u, Vector2(7, 10) * u), Color(0.48, 0.36, 0.2))
			canvas.draw_rect(Rect2(at + Vector2(5, 4) * u, Vector2(7, 3) * u), Color(0.35, 0.25, 0.13))
			canvas.draw_rect(Rect2(at + Vector2(7, 9) * u, Vector2(3, 2) * u), Color(0.35, 0.25, 0.13))
			canvas.draw_rect(Rect2(at + Vector2(6, 1.5) * u, Vector2(5, 1.5) * u), Color(0.35, 0.25, 0.13))
		Net.ITEM_PATCH:
			# a plate of hull metal with a rivet in each corner
			canvas.draw_rect(Rect2(at + Vector2(3, 3) * u, Vector2(11, 11) * u), Color(0.2, 0.21, 0.27))
			canvas.draw_rect(Rect2(at + Vector2(4, 4) * u, Vector2(9, 9) * u), Color(0.72, 0.75, 0.8))
			canvas.draw_rect(Rect2(at + Vector2(4, 11) * u, Vector2(9, 2) * u), Color(0.52, 0.55, 0.62))
			for corner: Vector2 in [Vector2(5, 5), Vector2(11, 5), Vector2(5, 11), Vector2(11, 11)]:
				canvas.draw_rect(Rect2(at + corner * u, Vector2(u, u)), Color(0.25, 0.26, 0.33))
		Net.ITEM_PART:
			# a cog
			var mid := at + Vector2(8.5, 8.5) * u
			for k in 8:
				var out := Vector2.RIGHT.rotated(k * TAU / 8.0) * 5.2 * u
				canvas.draw_rect(Rect2(mid + out - Vector2(1.2, 1.2) * u, Vector2(2.4, 2.4) * u), Color(0.9, 0.55, 0.15))
			canvas.draw_circle(mid, 4.4 * u, Color(0.95, 0.65, 0.2))
			canvas.draw_circle(mid, 1.8 * u, Color(0.16, 0.14, 0.18))
		Net.ITEM_FUEL:
			# a jerrycan: a handle on top, a spout at the corner, a cross pressed into its side
			canvas.draw_rect(Rect2(at + Vector2(4, 4) * u, Vector2(9, 11) * u), Color(0.14, 0.1, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(5, 5) * u, Vector2(7, 9) * u), Color(0.78, 0.22, 0.14))
			canvas.draw_rect(Rect2(at + Vector2(5, 2.5) * u, Vector2(4, 2) * u), Color(0.14, 0.1, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(10.5, 2.5) * u, Vector2(2, 2) * u), Color(0.55, 0.55, 0.6))
			canvas.draw_line(at + Vector2(6, 7) * u, at + Vector2(11, 12) * u, Color(0.55, 0.14, 0.1), 1.2 * u)
			canvas.draw_line(at + Vector2(11, 7) * u, at + Vector2(6, 12) * u, Color(0.55, 0.14, 0.1), 1.2 * u)
		Net.ITEM_RADIO:
			# a handheld radio: a body with a speaker grille, a stub aerial and a lamp
			canvas.draw_rect(Rect2(at + Vector2(5, 5) * u, Vector2(7, 10) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(6, 6) * u, Vector2(5, 8) * u), Color(0.28, 0.32, 0.3))
			canvas.draw_rect(Rect2(at + Vector2(10, 1.5) * u, Vector2(1.4, 4) * u), Color(0.1, 0.1, 0.12))
			for k in 3:
				canvas.draw_rect(Rect2(at + Vector2(7, 9 + k * 1.6) * u, Vector2(3, 0.7) * u), Color(0.12, 0.13, 0.13))
			canvas.draw_rect(Rect2(at + Vector2(7, 6.8) * u, Vector2(1.2, 1.2) * u), Color(0.35, 0.95, 0.4))
		Net.ITEM_SHELLS:
			# (v70) a box of shotgun shells, two red ones on top
			canvas.draw_rect(Rect2(at + Vector2(4, 7) * u, Vector2(9, 7) * u), Color(0.12, 0.1, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(5, 8) * u, Vector2(7, 5) * u), Color(0.75, 0.6, 0.3))
			for k in 2:
				canvas.draw_rect(Rect2(at + Vector2(6 + k * 3, 3.5) * u, Vector2(2, 4) * u), Color(0.85, 0.2, 0.15))
				canvas.draw_rect(Rect2(at + Vector2(6 + k * 3, 6.5) * u, Vector2(2, 1) * u), Color(0.9, 0.75, 0.3))
		Net.ITEM_STUNNER:
			# (v70) a stun baton: a dark rod with a blue tip
			canvas.draw_line(at + Vector2(3, 13) * u, at + Vector2(14, 4) * u, Color(0.08, 0.08, 0.1), 3.2 * u)
			canvas.draw_line(at + Vector2(3, 13) * u, at + Vector2(14, 4) * u, Color(0.22, 0.22, 0.3), 1.8 * u)
			canvas.draw_line(at + Vector2(11.5, 6) * u, at + Vector2(14, 4) * u, Color(0.4, 0.75, 1.0), 2.2 * u)
			canvas.draw_circle(at + Vector2(14, 4) * u, 1.2 * u, Color(0.8, 0.95, 1.0))
		Net.ITEM_FLASHBANG:
			# (v70) a flashbang: a can with a pin ring
			canvas.draw_rect(Rect2(at + Vector2(5.5, 5) * u, Vector2(6, 9) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(6.5, 6) * u, Vector2(4, 7) * u), Color(0.45, 0.5, 0.4))
			canvas.draw_rect(Rect2(at + Vector2(6.5, 8.5) * u, Vector2(4, 1.2) * u), Color(0.9, 0.85, 0.3))
			canvas.draw_rect(Rect2(at + Vector2(7, 3) * u, Vector2(3, 2) * u), Color(0.55, 0.57, 0.62))
			canvas.draw_arc(at + Vector2(11.5, 3.5) * u, 1.6 * u, 0.0, TAU, 12, Color(0.75, 0.75, 0.8), 0.8 * u)
		Net.ITEM_WELDER:
			# (v70) a welder: a torch with a hose and a bright flame
			canvas.draw_rect(Rect2(at + Vector2(3, 9) * u, Vector2(8, 4) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(4, 10) * u, Vector2(6, 2) * u), Color(0.85, 0.6, 0.15))
			canvas.draw_line(at + Vector2(10, 10) * u, at + Vector2(13.5, 6) * u, Color(0.4, 0.42, 0.48), 1.6 * u)
			canvas.draw_circle(at + Vector2(14.5, 4.8) * u, 1.4 * u, Color(0.55, 0.85, 1.0))
			canvas.draw_line(at + Vector2(3, 12) * u, at + Vector2(1.5, 15) * u, Color(0.15, 0.15, 0.18), 1.2 * u)
		Net.ITEM_CUFFS:
			# (v70) handcuffs: two rings and a chain
			canvas.draw_arc(at + Vector2(5.5, 9) * u, 3.0 * u, 0.0, TAU, 16, Color(0.1, 0.1, 0.12), 2.0 * u)
			canvas.draw_arc(at + Vector2(5.5, 9) * u, 3.0 * u, 0.0, TAU, 16, Color(0.7, 0.72, 0.78), 1.0 * u)
			canvas.draw_arc(at + Vector2(11.5, 9) * u, 3.0 * u, 0.0, TAU, 16, Color(0.1, 0.1, 0.12), 2.0 * u)
			canvas.draw_arc(at + Vector2(11.5, 9) * u, 3.0 * u, 0.0, TAU, 16, Color(0.7, 0.72, 0.78), 1.0 * u)
		Net.ITEM_SPLINT:
			# (v70) a splint: two slats bound with white straps
			canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 3) * u), Color(0.15, 0.12, 0.1))
			canvas.draw_rect(Rect2(at + Vector2(3, 10) * u, Vector2(11, 3) * u), Color(0.15, 0.12, 0.1))
			canvas.draw_rect(Rect2(at + Vector2(3.5, 5.5) * u, Vector2(10, 2) * u), Color(0.7, 0.55, 0.32))
			canvas.draw_rect(Rect2(at + Vector2(3.5, 10.5) * u, Vector2(10, 2) * u), Color(0.7, 0.55, 0.32))
			for x in [5, 11]:
				canvas.draw_rect(Rect2(at + Vector2(x, 4.5) * u, Vector2(1.5, 9) * u), Color(0.92, 0.92, 0.9))
		Net.ITEM_BOMB:
			# (v70) a pirates' bomb: a dark box, a red lamp
			canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 8) * u), Color(0.08, 0.08, 0.1))
			canvas.draw_rect(Rect2(at + Vector2(4, 6) * u, Vector2(9, 6) * u), Color(0.32, 0.3, 0.26))
			canvas.draw_rect(Rect2(at + Vector2(5, 7) * u, Vector2(4, 2) * u), Color(0.1, 0.25, 0.1))
			canvas.draw_circle(at + Vector2(11, 8) * u, 1.3 * u, Color(1.0, 0.2, 0.15))
			canvas.draw_line(at + Vector2(6, 5) * u, at + Vector2(8, 2.5) * u, Color(0.85, 0.2, 0.15), 0.8 * u)
		Net.ITEM_TOOLBOX:
			# (v71) a toolbox: a red box with a handle and a latch
			canvas.draw_rect(Rect2(at + Vector2(2, 7) * u, Vector2(13, 7) * u), Color(0.1, 0.08, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(3, 8) * u, Vector2(11, 5) * u), Color(0.78, 0.18, 0.14))
			canvas.draw_rect(Rect2(at + Vector2(3, 9.6) * u, Vector2(11, 0.8) * u), Color(0.45, 0.1, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(6, 4) * u, Vector2(5, 1.2) * u), Color(0.1, 0.08, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(6, 4) * u, Vector2(1.2, 3.5) * u), Color(0.1, 0.08, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(9.8, 4) * u, Vector2(1.2, 3.5) * u), Color(0.1, 0.08, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(7.8, 9.2) * u, Vector2(1.4, 1.6) * u), Color(0.85, 0.85, 0.8))
		Net.ITEM_BOARD:
			# (v71) a circuit board: green, with chips and gold contacts
			canvas.draw_rect(Rect2(at + Vector2(2, 4) * u, Vector2(13, 9) * u), Color(0.06, 0.12, 0.08))
			canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 7) * u), Color(0.15, 0.5, 0.25))
			canvas.draw_rect(Rect2(at + Vector2(4.5, 6) * u, Vector2(3, 3) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(9, 6.5) * u, Vector2(4, 2) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_line(at + Vector2(7.5, 7.5) * u, at + Vector2(9, 7.5) * u, Color(0.85, 0.75, 0.3), 0.5 * u)
			for k in 5:
				canvas.draw_rect(Rect2(at + Vector2(3.5 + k * 2.2, 13) * u, Vector2(1.2, 1.5) * u), Color(0.9, 0.75, 0.25))
		Net.ITEM_STEW:
			# (v71) a stew: a bowl with brown stew and steam
			canvas.draw_rect(Rect2(at + Vector2(3, 8) * u, Vector2(11, 5) * u), Color(0.12, 0.12, 0.14))
			canvas.draw_rect(Rect2(at + Vector2(4, 9) * u, Vector2(9, 3.5) * u), Color(0.82, 0.82, 0.8))
			canvas.draw_rect(Rect2(at + Vector2(4.5, 8.5) * u, Vector2(8, 1.5) * u), Color(0.55, 0.32, 0.15))
			canvas.draw_circle(at + Vector2(7, 8.8) * u, 0.7 * u, Color(0.85, 0.55, 0.2))
			for x in [6.0, 9.0, 11.0]:
				canvas.draw_line(at + Vector2(x, 7) * u, at + Vector2(x - 0.8, 3.5) * u, Color(0.8, 0.82, 0.85, 0.6), 0.6 * u)
		Net.ITEM_COFFEE:
			# (v71) coffee: a mug with a handle, dark and steaming
			canvas.draw_rect(Rect2(at + Vector2(4, 6) * u, Vector2(7, 8) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(5, 7) * u, Vector2(5, 6) * u), Color(0.9, 0.88, 0.82))
			canvas.draw_rect(Rect2(at + Vector2(5, 7) * u, Vector2(5, 1.2) * u), Color(0.3, 0.17, 0.08))
			canvas.draw_arc(at + Vector2(11.5, 10) * u, 2.0 * u, -PI / 2, PI / 2, 8, Color(0.1, 0.1, 0.12), 1.2 * u)
			canvas.draw_line(at + Vector2(7.5, 5.5) * u, at + Vector2(6.8, 2.5) * u, Color(0.8, 0.82, 0.85, 0.6), 0.6 * u)
		Net.ITEM_BROTH:
			# (v71) a herb broth: a flask of green broth with a leaf
			canvas.draw_rect(Rect2(at + Vector2(5, 5) * u, Vector2(7, 9) * u), Color(0.1, 0.1, 0.12))
			canvas.draw_rect(Rect2(at + Vector2(6, 7) * u, Vector2(5, 6) * u), Color(0.35, 0.78, 0.6))
			canvas.draw_rect(Rect2(at + Vector2(7, 3) * u, Vector2(3, 2.5) * u), Color(0.6, 0.45, 0.3))
			canvas.draw_circle(at + Vector2(8.5, 10) * u, 1.3 * u, Color(0.6, 0.95, 0.75))
		Net.ITEM_MAG:
			# a magazine with a round showing at the top
			canvas.draw_rect(Rect2(at + Vector2(6, 4) * u, Vector2(5, 10) * u), Color(0.12, 0.12, 0.15))
			canvas.draw_rect(Rect2(at + Vector2(7, 5) * u, Vector2(3, 8) * u), Color(0.38, 0.4, 0.46))
			canvas.draw_rect(Rect2(at + Vector2(7.5, 2.5) * u, Vector2(2, 2) * u), Color(0.9, 0.7, 0.25))
		Net.ITEM_BATON:
			# a baton lying across, a grip at one end
			canvas.draw_line(at + Vector2(3, 13) * u, at + Vector2(14, 4) * u, Color(0.1, 0.1, 0.12), 3.2 * u)
			canvas.draw_line(at + Vector2(3, 13) * u, at + Vector2(14, 4) * u, Color(0.3, 0.32, 0.38), 1.8 * u)
			canvas.draw_line(at + Vector2(3, 13) * u, at + Vector2(6, 10.5) * u, Color(0.55, 0.3, 0.15), 2.2 * u)
		Net.ITEM_MEDPATCH:
			# a white patch with a red cross
			canvas.draw_rect(Rect2(at + Vector2(3, 5) * u, Vector2(11, 7) * u), Color(0.2, 0.2, 0.24))
			canvas.draw_rect(Rect2(at + Vector2(4, 6) * u, Vector2(9, 5) * u), Color(0.93, 0.92, 0.88))
			canvas.draw_rect(Rect2(at + Vector2(7.5, 6.5) * u, Vector2(2, 4) * u), Color(0.85, 0.15, 0.15))
			canvas.draw_rect(Rect2(at + Vector2(6.5, 7.5) * u, Vector2(4, 2) * u), Color(0.85, 0.15, 0.15))
		Net.ITEM_FLASHLIGHT, Net.ITEM_FLASHLIGHT_ON:
			# a torch lying on its side, the lens to the right; lit, the lens glows and throws a little light
			var lit := item == Net.ITEM_FLASHLIGHT_ON
			if lit:
				canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(13, 6.5) * u, at + Vector2(17, 3) * u,
					at + Vector2(17, 14) * u, at + Vector2(13, 10.5) * u]), Color(1.0, 0.95, 0.6, 0.45))
			canvas.draw_rect(Rect2(at + Vector2(2, 6) * u, Vector2(8, 5) * u), Color(0.15, 0.15, 0.19))
			canvas.draw_rect(Rect2(at + Vector2(3, 7) * u, Vector2(7, 3) * u), Color(0.42, 0.44, 0.52))
			canvas.draw_rect(Rect2(at + Vector2(5, 7) * u, Vector2(1, 1) * u), Color(0.85, 0.3, 0.25) if not lit else Color(0.4, 0.95, 0.4))
			canvas.draw_rect(Rect2(at + Vector2(10, 5) * u, Vector2(3, 7) * u), Color(0.15, 0.15, 0.19))
			canvas.draw_rect(Rect2(at + Vector2(10.5, 5.5) * u, Vector2(2, 6) * u), Color(0.55, 0.57, 0.66))
			canvas.draw_rect(Rect2(at + Vector2(12, 6) * u, Vector2(1, 5) * u), Color(1.0, 0.97, 0.75) if lit else Color(0.62, 0.7, 0.78))


static func _crate(canvas: CanvasItem, at: Vector2, u: float, g: int) -> void:
	## (v59) A crate of ship gear: a box with straps, the frame of its tier, and the
	## mark of what is in it (a shield arc, a reactor core, an engine nozzle, a sensor
	## eye, coils, armour plates, mirrors, a phase swirl).
	var rim: Color = TIER_RIM[clampi(Gear.tier(g), 0, 3)]
	canvas.draw_rect(Rect2(at + Vector2(1.5, 3) * u, Vector2(14, 11.5) * u), rim)
	canvas.draw_rect(Rect2(at + Vector2(2.5, 4) * u, Vector2(12, 9.5) * u), Color(0.36, 0.33, 0.27))
	canvas.draw_rect(Rect2(at + Vector2(2.5, 4) * u, Vector2(12, 1.2) * u), Color(0.5, 0.46, 0.38))
	canvas.draw_rect(Rect2(at + Vector2(4.5, 4) * u, Vector2(1, 9.5) * u), Color(0.22, 0.2, 0.17))
	canvas.draw_rect(Rect2(at + Vector2(11.5, 4) * u, Vector2(1, 9.5) * u), Color(0.22, 0.2, 0.17))
	var mid := at + Vector2(8.5, 9) * u
	canvas.draw_circle(mid, 3.0 * u, Color(0.1, 0.11, 0.14))
	match Gear.system_of(g):
		Gear.SYS_SHIELD:
			canvas.draw_arc(mid, 2.2 * u, PI, TAU, 10, Color(0.4, 0.7, 1.0), 0.9 * u)
		Gear.SYS_REACTOR:
			canvas.draw_circle(mid, 1.6 * u, Color(0.4, 1.0, 0.55))
		Gear.SYS_ENGINE:
			canvas.draw_rect(Rect2(mid - Vector2(1.6, 1.2) * u, Vector2(3.2, 2.4) * u), Color(1.0, 0.6, 0.25))
		Gear.SYS_SENSORS:
			canvas.draw_circle(mid, 1.7 * u, Color(0.9, 0.9, 0.95))
			canvas.draw_circle(mid, 0.8 * u, Color(0.2, 0.5, 0.9))
		Gear.SYS_COILS:
			for k in 3:                              # (v61) copper turns of a coil
				canvas.draw_line(mid + Vector2(-1.8, -1.4 + k * 1.4) * u, mid + Vector2(1.8, -1.4 + k * 1.4) * u, Color(0.95, 0.65, 0.25), 0.7 * u)
	if g == Gear.TELEPORT:                           # (v97) the teleporter: rings round a bright point
		canvas.draw_arc(mid, 2.2 * u, 0.0, TAU, 12, Color(0.4, 0.95, 1.0), 0.6 * u)
		canvas.draw_arc(mid, 1.3 * u, 0.0, TAU, 10, Color(0.6, 0.85, 1.0), 0.5 * u)
		canvas.draw_circle(mid, 0.6 * u, Color(1.0, 1.0, 1.0))
	match Gear.module_of(g):
		Gear.MOD_ARMOUR:
			for k in 3:
				canvas.draw_rect(Rect2(mid + Vector2(-2.0 + k * 1.4, -1.6) * u, Vector2(1.1, 3.2) * u), Color(0.7, 0.72, 0.78))
		Gear.MOD_FOCUS:
			for k in 3:
				canvas.draw_line(mid + Vector2(-2.2, -1.6 + k * 1.6) * u, mid + Vector2(1.8, 0) * u, Color(1.0, 0.5, 0.25), 0.6 * u)
		Gear.MOD_PHASE:
			canvas.draw_arc(mid, 2.0 * u, 0.0, PI * 1.5, 10, Color(0.75, 0.45, 1.0), 0.8 * u)
			canvas.draw_circle(mid, 0.8 * u, Color(0.9, 0.7, 1.0))
		Gear.MOD_JAMMER:                             # (v62) a crossed-out jump arrow
			canvas.draw_line(mid + Vector2(-2.0, 1.2) * u, mid + Vector2(2.0, -1.2) * u, Color(0.4, 0.8, 1.0), 0.7 * u)
			canvas.draw_line(mid + Vector2(-1.8, -1.6) * u, mid + Vector2(1.8, 1.6) * u, Color(1.0, 0.35, 0.3), 0.7 * u)
		Gear.MOD_WELDER:                             # a welding spark
			canvas.draw_line(mid + Vector2(-2.0, 1.6) * u, mid, Color(0.6, 0.62, 0.68), 0.8 * u)
			canvas.draw_circle(mid, 1.0 * u, Color(1.0, 0.85, 0.4))
		Gear.MOD_SALVAGE:                            # a claw
			canvas.draw_arc(mid, 1.8 * u, PI * 0.2, PI * 0.8, 6, Color(0.85, 0.75, 0.4), 0.7 * u)
			canvas.draw_arc(mid, 1.8 * u, PI * 1.2, PI * 1.8, 6, Color(0.85, 0.75, 0.4), 0.7 * u)
		Gear.MOD_LOADER:                             # shells in a row
			for k in 3:
				canvas.draw_rect(Rect2(mid + Vector2(-2.0 + k * 1.4, -1.5) * u, Vector2(0.9, 3.0) * u), Color(0.95, 0.8, 0.35))
		Gear.MOD_EXTENDER:                           # a plus: one more slot
			canvas.draw_rect(Rect2(mid - Vector2(0.4, 2.0) * u, Vector2(0.8, 4.0) * u), Color(0.5, 1.0, 0.6))
			canvas.draw_rect(Rect2(mid - Vector2(2.0, 0.4) * u, Vector2(4.0, 0.8) * u), Color(0.5, 1.0, 0.6))


static func _ship_gun(canvas: CanvasItem, at: Vector2, u: float, w: int) -> void:
	## A ship's gun off its mount: a breech block with a barrel, marked with its class's colour;
	## heavier guns have thicker barrels, the rapid laser and the blaster several.
	var mark: Color = GUN_MARK[Weapons.klass(w)]
	canvas.draw_rect(Rect2(at + Vector2(2, 7) * u, Vector2(8, 8) * u), TIER_RIM[clampi(Weapons.tier(w), 0, 3)])
	canvas.draw_rect(Rect2(at + Vector2(3, 8) * u, Vector2(6, 6) * u), Color(0.5, 0.53, 0.6))
	var barrels := 3 if w == Weapons.RAPID or w == Weapons.BLASTER or w == Weapons.PHOENIX or w == Weapons.AUTOCANNON \
		else (2 if w == Weapons.GUARD or w == Weapons.STORM else 1)
	var thick := 2.0 + (1.0 if Weapons.tier(w) == 2 else (2.0 if Weapons.tier(w) >= 3 else 0.0))
	if barrels > 1:
		thick = minf(thick, 2.0)
	for k in barrels:
		var y := 11.0 - thick / 2.0 + (k - (barrels - 1) / 2.0) * 2.4
		canvas.draw_rect(Rect2(at + Vector2(9, y) * u, Vector2(7, thick) * u), Color(0.12, 0.12, 0.15))
		canvas.draw_rect(Rect2(at + Vector2(9.5, y + 0.4) * u, Vector2(6, thick - 0.8) * u), Color(0.38, 0.4, 0.46))
	if Weapons.klass(w) == Weapons.CLASS_ROCKET:
		canvas.draw_rect(Rect2(at + Vector2(9, 8) * u, Vector2(6, 6) * u), Color(0.12, 0.12, 0.15))
		for k in 2:
			canvas.draw_circle(at + Vector2(10.6 + k * 2.8, 11) * u, 1.0 * u, mark)
	canvas.draw_rect(Rect2(at + Vector2(4, 9.5) * u, Vector2(4, 3) * u), mark)
	for k in Weapons.power(w):                           # a pip per point of power it draws
		canvas.draw_rect(Rect2(at + Vector2(2 + k * 2.2, 3) * u, Vector2(1.4, 1.6) * u), Color(0.95, 0.85, 0.3))
