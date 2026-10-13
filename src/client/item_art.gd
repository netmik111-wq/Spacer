extends RefCounted
## Pictures of the things that can be carried, drawn in code into any square:
## a slot on the screen or a spot on the floor. Each is laid out on a 17 by 17 grid.

const Net := preload("res://src/shared/net.gd")


static func draw(canvas: CanvasItem, cell: Rect2, item: int) -> void:
	var u := cell.size.x / 17.0
	var at := cell.position
	match item:
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
