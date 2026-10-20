extends RefCounted
## (v71, the author's H1: "optional, chosen at the start of the game: hard
## difficulty means more mechanics, not more enemy HP") Complex repairs, shared
## by the server (Repairs, the bots in Stations) and the client (the hints).
##
## With complex repairs off (the normal and easy games) a machine or a door is
## mended three times quicker with any spare part: a mechanical part or a circuit
## board. With them on (the hard game sets them; the menu lets anybody choose):
##   - every machine wants its own kind of part: consoles and screens a circuit
##     board (ITEM_BOARD), everything else and the doors a mechanical part (ITEM_PART);
##     without the right one the work takes NO_PART_SLOWER times as long;
##   - the one at work needs a toolbox (ITEM_TOOLBOX) on them: without one it takes
##     NO_TOOLS_SLOWER times as long again. The toolbox is never used up.
## Nothing ever needs a part outright, so a broken helm can always be mended
## (the author's rule: while a bridge console works there is a way to escape).

const Net := preload("res://src/shared/net.gd")


static func part_for(map, cell: int) -> int:
	## The spare part that machine (or door) wants with complex repairs on.
	if map.chart.has(cell) or map.helm.has(cell) or map.gun_console.has(cell) or map.drone_console.has(cell) \
			or map.holo.has(cell) or map.comms.has(cell) or map.intercom.has(cell) or map.autodoc.has(cell) \
			or map.scanner.has(cell) or map.bay.has(cell) or map.shield.has(cell):
		return Net.ITEM_BOARD
	return Net.ITEM_PART


static func spare(complex: bool, want: int, has: Callable) -> int:
	## The part that work would use up, from what `has` (item -> bool) says is carried;
	## ITEM_NONE if none would do.
	if has.call(want):
		return want
	if complex:
		return Net.ITEM_NONE
	var other := Net.ITEM_BOARD if want == Net.ITEM_PART else Net.ITEM_PART
	return other if has.call(other) else Net.ITEM_NONE


static func slower(complex: bool, part: int, toolbox: bool) -> int:
	## How many times longer than its plain time the work takes.
	var n := 1 if part != Net.ITEM_NONE else Net.NO_PART_SLOWER
	if complex and not toolbox:
		n *= Net.NO_TOOLS_SLOWER
	return n


static func lacking(complex: bool, part: int, want: int, toolbox: bool) -> String:
	## What the hint says is missing (in the player's words), "" if nothing.
	var out := PackedStringArray()
	if part == Net.ITEM_NONE:
		out.append("плата" if complex and want == Net.ITEM_BOARD else "запчасть")
	if complex and not toolbox:
		out.append("ящик с инструментами")
	if out.is_empty():
		return ""
	return " (нет: %s; дольше в %d раз)" % [", ".join(out), slower(complex, part, toolbox)]
