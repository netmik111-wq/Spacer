extends SceneTree
## (v85) Saves the people's sheet the game makes from the spriter's character (src/client/crew_art.gd):
##   godot --headless --path . --script res://tools/crewshot.gd -- OUT.png

const CrewArt := preload("res://src/client/crew_art.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var t := Time.get_ticks_msec()
	var im := CrewArt.build()
	print("crew sheet %dx%d in %d ms" % [im.get_width(), im.get_height(), Time.get_ticks_msec() - t])
	im.save_png(args[0] if args.size() > 0 else "user://crew_sheet.png")
	quit(0)
