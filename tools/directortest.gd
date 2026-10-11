extends SceneTree
## Checks the director's pace without waiting in real time: a server is stepped
## by hand through many minutes of game time.
##   godot --headless --path . --script res://tools/directortest.gd
## Prints how many events came in each kind of sector and fails (exit code 1)
## if a supply station is not quiet, a meteor stream is, or events pile up on a
## crew that is already in trouble.

const GameServer := preload("res://src/server/game_server.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Net := preload("res://src/shared/net.gd")

var failed := 0


func _initialize() -> void:
	for crew in [1, 4]:
		for kind in [Sectors.STATION, Sectors.EMPTY, Sectors.METEORS]:
			for mends in [false, true]:
				_run(crew, kind, mends)
	print("DIRECTORTEST %s" % ("FAILED: %d" % failed if failed > 0 else "ok"))
	quit(1 if failed > 0 else 0)


func _run(crew: int, kind: int, mends: bool) -> void:
	## Thirty minutes in one sector. `mends`: the crew closes every hole 30 s after it appears.
	var server := GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26000 + crew * 10 + kind * 2 + (1 if mends else 0), "ship01", 0)
	if problem != "":
		print(problem)
		failed += 1
		return
	for i in crew:
		server._new_player("Проверка %d" % i)     # a crew member nobody controls: stands at the spawn point
	var here := 0
	for i in server.sectors.count:
		if server.sectors.kind[i] == kind:
			here = i
	server.sectors.kind[here] = kind
	server.sector = here
	server.director.entered_sector()
	var minutes := 30
	var most_holes := 0
	var hole_since := -1
	for t in minutes * 60 * Net.TICK_HZ:
		server._tick()
		var holes: int = server.air.holes.size()
		most_holes = maxi(most_holes, holes)
		if holes == 0:
			hole_since = -1
		elif hole_since < 0:
			hole_since = t
		elif mends and t - hole_since >= 30 * Net.TICK_HZ:
			server.seal_all()
			server.air.refill()                   # and airs the ship, so the crew stays on its feet
	var fired: int = server.director.fired
	var limit := maxi(1, crew / 2 + 1)
	print("crew %d, %s, crew %s holes: %d events in %d min, at most %d holes open at once" % [
		crew, Sectors.KIND_NAMES[kind], "mends" if mends else "ignores", fired, minutes, most_holes])
	if kind == Sectors.STATION:
		_expect(fired == 0, "a supply station is quiet")
	elif kind == Sectors.METEORS and mends:
		_expect(fired >= 12, "a meteor stream keeps a working crew busy")
	elif kind == Sectors.EMPTY and mends:
		_expect(fired >= 2 and fired <= 20, "quiet space has the odd event")
	if not mends and kind != Sectors.STATION:
		# a single volley may overshoot the limit by its own three hits, no more
		_expect(most_holes <= limit + 2, "the director holds back while holes stay open (limit %d)" % limit)
	server.stop()
	server.free()


func _expect(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1
