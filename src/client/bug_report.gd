extends RefCounted
## (v75, the author's S2) "Сообщить об ошибке": the game's recent logs, the saved
## campaign, the bots' log, the settings and a picture of the screen, put in one zip
## file the author attaches to a notebook note. Logs say why a thing happened, which
## a video cannot. Client only.

const GameClient := preload("res://src/client/game_client.gd")

const LOGS_KEPT := 6                 # the newest log files taken (the game and its server each write one per run)


static func folder() -> String:
	## Next to the game (run from the project: in user://).
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("bug_reports")
	return ProjectSettings.globalize_path("user://bug_reports")


static func make(shot: Image = null) -> String:
	## Writes the zip and returns its path ("" if it could not be written).
	DirAccess.make_dir_recursive_absolute(folder())
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := folder().path_join("report_%s.zip" % stamp)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return ""
	_add_text(zip, "about.txt", "Spacer %s\n%s %s\n%s\nВидеокарта: %s\n" % [
		str(ProjectSettings.get_setting("application/config/version", "")), OS.get_name(), OS.get_version(),
		Time.get_datetime_string_from_system(), RenderingServer.get_video_adapter_name()])
	for f: String in _newest_logs():
		_add_file(zip, "logs/" + f.get_file(), f)
	for f: String in ["user://campaign.json", "user://options.cfg", "user://settings.cfg", GameClient.log_path()]:
		_add_file(zip, f.get_file(), f)
	if shot != null and not shot.is_empty():
		_add_bytes(zip, "screen.png", shot.save_png_to_buffer())
	zip.close()
	return path


static func _newest_logs() -> Array:
	var dir := "user://logs"
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".log"):
			files.append(dir.path_join(f))
	files.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return files.slice(0, LOGS_KEPT)


static func _add_file(zip: ZIPPacker, name: String, from: String) -> void:
	if FileAccess.file_exists(from):
		_add_bytes(zip, name, FileAccess.get_file_as_bytes(from))


static func _add_text(zip: ZIPPacker, name: String, text: String) -> void:
	_add_bytes(zip, name, text.to_utf8_buffer())


static func _add_bytes(zip: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	zip.start_file(name)
	zip.write_file(bytes)
	zip.close_file()
