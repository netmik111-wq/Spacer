extends RefCounted
## (v101, his S3 A: "a run log for my playtests") The run's story as plain lines with the game time: when it began
## and on which ship, every cluster passed (how long it took, what came in and went out of the purse), every ship of
## the pirates beaten, every one of ours lost, and how the run ended. run_log.txt next to the game holds it after
## every save and at the end, so the author can send it with usage.txt after an evening (real play, not the simulator).
## The campaign save keeps it. Part of the server: GameServer keeps one of these.

var server: GameServer
var lines: Array = []                # "[mm:ss] text"
var _cluster_ticks := 0              # voyage_ticks when the cluster in hand began
var _cluster_earned := 0             # ship.earned then
var _cluster_credits := 0            # and ship.credits


func setup(p_server: GameServer) -> void:
	server = p_server


func started(ship_name: String) -> void:
	lines = []
	_mark()
	add("Начало кампании: корабль «%s», режим %s, %d кредитов." % [ship_name, ["лёгкий", "обычный", "трудный"][clampi(server.mode, 0, 2)],
		server.ship.credits])


func add(text: String) -> void:
	var s := server.voyage_ticks / 20
	lines.append("[%02d:%02d:%02d] %s" % [s / 3600, s / 60 % 60, s % 60, text])


func cluster_done(depth: int) -> void:
	## The long jump out of a cluster has come through (Road.next_cluster).
	var took := (server.voyage_ticks - _cluster_ticks) / 20
	var earned := server.ship.earned - _cluster_earned
	var spent := maxi(_cluster_credits + earned - server.ship.credits, 0)
	add("Скопление %d пройдено за %d мин: пришло %d кредитов, ушло %d, на счету %d, обшивка %d из %d." % [depth, took / 60, earned, spent,
		server.ship.credits, server.ship.hull, server.ship.hull_max])
	_mark()


func _mark() -> void:
	_cluster_ticks = server.voyage_ticks
	_cluster_earned = server.ship.earned
	_cluster_credits = server.ship.credits


func text() -> String:
	return "Журнал прохождения (Spacer %s, записан %s)\n%s\n" % [
		str(ProjectSettings.get_setting("application/config/version", "")), Time.get_datetime_string_from_system(), "\n".join(lines)]


static func path() -> String:
	## Next to the game (run from the project: in user://), like usage.txt.
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("run_log.txt")
	return "user://run_log.txt"


func write() -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f != null:
		f.store_string(text())
		f.close()


func save() -> Dictionary:
	return {"lines": lines, "ticks": _cluster_ticks, "earned": _cluster_earned, "credits": _cluster_credits}


func load_from(d: Dictionary) -> void:
	lines = Array(d.get("lines", []))
	_cluster_ticks = int(d.get("ticks", server.voyage_ticks))
	_cluster_earned = int(d.get("earned", server.ship.earned))
	_cluster_credits = int(d.get("credits", server.ship.credits))
	add("Продолжение с сохранения.")
