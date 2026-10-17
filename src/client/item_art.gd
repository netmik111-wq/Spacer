extends RefCounted
## Pictures of the things that can be carried, drawn in code into any square:
## a slot on the screen or a spot on the floor. Each is laid out on a 17 by 17 grid.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

# the colour a ship weapon's picture is marked with, by its class (Weapons.CLASS_*)
const GUN_MARK: Array[Color] = [Color(1.0, 0.45, 0.2), Color(0.85, 0.55, 1.0), Color(0.4, 1.0, 0.45), Color(0.85, 0.85, 0.8), Color(0.35, 0.65, 1.0),
	Color(0.55, 1.0, 0.7), Color(0.3, 0.95, 1.0), Color(1.0, 0.4, 0.85), Color(0.95, 0.85, 0.4), Color(0.9, 0.9, 0.95)]
# (v58) the frame of a tier's gun: plain, steel, gold (a tier is not told; the look is)
const TIER_RIM: Array[Color] = [Color(0.12, 0.12, 0.15), Color(0.12, 0.12, 0.15), Color(0.3, 0.34, 0.42), Color(0.75, 0.6, 0.2)]
# parts of a kind of gun (Weapons.KIND_*): the colour of their mark
const KIND_MARK: Array[Color] = [Color(1.0, 0.45, 0.2), Color(0.35, 0.65, 1.0), Color(0.85, 0.85, 0.8), Color(0.85, 0.55, 1.0), Color(0.95, 0.85, 0.4)]


static func draw(canvas: CanvasItem, cell: Rect2, item: int) -> void:
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
