extends RefCounted
## Pictures of the things that can be carried, drawn in code into any square:
## a slot on the screen or a spot on the floor. Each is laid out on a 17 by 17 grid.

const Net := preload("res://src/shared/net.gd")


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
