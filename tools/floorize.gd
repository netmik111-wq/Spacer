extends SceneTree
## (v91) Moves the machines of maps/*.txt out of the walls onto the floor in front of them
## (MapBuilder.to_floor), writing the drawings back. `-- NAME...` limits it to those maps; `-- --dry` only prints.

const MapBuilder := preload("res://src/shared/map_builder.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dry := args.has("--dry")
	var names := []
	for a in args:
		if not a.begins_with("--"):
			names.append(a)
	var dir := DirAccess.open("res://maps")
	for f in dir.get_files():
		if not f.ends_with(".txt") or (not names.is_empty() and not names.has(f.get_basename())):
			continue
		var path := "res://maps/" + f
		var text := FileAccess.get_file_as_string(path)
		var out := MapBuilder.to_floor(text)
		if out == text:
			print("%s: nothing to move" % f)
			continue
		print("%s: moved" % f)
		if dry:
			print(out)
		else:
			var w := FileAccess.open(path, FileAccess.WRITE)
			w.store_string(out)
	quit()
