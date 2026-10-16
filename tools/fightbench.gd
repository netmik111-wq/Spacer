extends SceneTree
## Measures how long ship fights last (v54, the author: "balance out fights so
## they don't go too long"). Not a test: it prints a table and always passes.
##   godot --headless --path . --script res://tools/fightbench.gd -- [fights per cell] [far] [mend seconds] [pilot]
## For every class and temper it brings a pirate ship for a raid (a fight to the
## end) against our ship as it starts (three lasers, shield on) and fights it on
## a real server stepped by hand. Our gunner fires every gun that is ready and
## aims as a sensible player would: at its shield room while the shield holds,
## then at its guns, its jump drive while it runs, else anywhere. Our crew mends
## one broken device every `mend` seconds (10 unless given; 0: nobody mends) (patching holes is left out: it does not
## change the fight). `far` is how many jumps from the start (more enemy guns).
## `pilot` 1 (v55) puts a pilot by job at the ship's controls (it dodges); 0 (the default) nobody.
## A ransom offered is taken. Prints the median fight length, how fights ended
## and our hull lost.

const GameServer := preload("res://src/server/game_server.gd")
const Gunnery := preload("res://src/server/gunnery.gd")
const Net := preload("res://src/shared/net.gd")
const Hulls := preload("res://src/shared/hulls.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var pilot = null                     # (v55) our pilot at the controls, or null
var mend := 10.0                     # seconds for our crew to put one broken device right (0 = nobody mends)
const LIMIT := 900                   # seconds: a fight still on by then is counted as "too long"

var server: GameServer


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 8
	var far := int(args[1]) if args.size() > 1 else 0
	mend = float(args[2]) if args.size() > 2 else mend
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26320 + far + int(mend), "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	var p := server.crew.new_player("Канонир")
	var map := server.map
	if args.size() > 3 and int(args[3]) == 1:
		pilot = server.crew.new_player("Пилот")
		pilot.take_job(Net.JOB_PILOT)
		var s: Array = server.stations.spots[Net.POST_HELM][0]
		pilot.st.place(int(s[0]) % map.width, int(s[0]) / map.width)
		pilot.st.facing = int(s[1])
	var console: int = map.gun_console.keys()[0]
	print("fights per cell: %d, jumps from start: %d, our crew mends a device every %s s, pilot: %s" % [n, far, str(mend) if mend > 0.0 else "(never)",
		"yes" if pilot != null else "no"])
	print("%-22s %-12s %8s %8s %8s   %s" % ["class", "temper", "median", "longest", "hull-", "ended"])
	for k: int in Hulls.CLASSES.keys():
		for t: int in Hulls.TEMPERS.keys():
			var times: Array = []
			var lost := 0
			var ends := {}
			for i in n:
				var r := _fight(p, console, k, t, far)
				times.append(r[0])
				lost += int(r[1])
				ends[r[2]] = int(ends.get(r[2], 0)) + 1
			times.sort()
			print("%-22s %-12s %7ds %7ds %8.1f   %s" % [Hulls.class_name_of(k), Hulls.temper(t)["name"], times[times.size() / 2],
				times[-1], float(lost) / n, str(ends)])
	quit(0)


func _fight(p, console: int, klass: int, temper: int, far: int) -> Array:
	## One raid from start to end: [seconds, our hull lost, how it ended].
	var map := server.map
	var g: Gunnery = server.gunnery
	var d = server.derelict
	var ship = server.ship
	ship.hull = Net.HULL_MAX
	ship.broken.clear()
	ship.jammed.clear()
	ship.shield = Weapons.SHIELD_FULL
	server.over = Net.OVER_NONE
	for c: int in server.air.holes.keys():
		server.air.set_hole(c, false)
	if far > 0:
		server.ship.sector = _sector_at(far)
	server.shipyard.force_class = klass
	if not d.pirates_come(2, true):
		return [0, 0, "could not come"]
	g.temper = temper
	p.st.place(console % map.width, console / map.width - 1)
	p.st.facing = Net.DIR_DOWN
	var start := server.tick
	var hull: int = ship.hull
	_ransomed = false
	var mend_at := 0
	while g.fighting() and server.over == Net.OVER_NONE and server.tick - start < LIMIT * Net.TICK_HZ:
		# (the gunner breathes from a tank and is patched up: holes near the console would knock them out,
		# and the crew would see to that in a real fight)
		p.supply = true
		p.tank = 1.0e9
		p.health = 100.0
		p.wounds = 0.0
		p.cond = Net.COND_OK
		p.st.down = false
		if pilot != null:
			pilot.supply = true
			pilot.tank = 1.0e9
			pilot.health = 100.0
			pilot.wounds = 0.0
			pilot.cond = Net.COND_OK
			pilot.st.down = false
		if g.ransom > 0:
			_ransomed = true
			g.ransom_taken(p)                # a sensible crew takes it
			break
		g.aim = _aim(g)
		g.fire(p, 255)
		if ship.broken.is_empty():
			mend_at = server.tick + roundi(mend * Net.TICK_HZ)
		elif server.tick >= mend_at and mend > 0.0:
			ship.broken.erase(ship.broken.keys()[0])
			mend_at = server.tick + roundi(mend * Net.TICK_HZ)
		server._tick()
	var how := "wrecked"
	if _ransomed:
		how = "ransom"
	elif server.over != Net.OVER_NONE:
		how = "we died"
	elif g.fighting():
		how = "too long"
	elif d.here and d.wreck:
		how = "wrecked"
	elif not d.here:
		how = "ran" if _last_escaped else "gone"
	var took: int = (server.tick - start) / Net.TICK_HZ
	if d.here:
		d._leave(true)
	g.enemy_gone()
	return [took, hull - ship.hull, how]


var _last_escaped := false
var _ransomed := false


func _aim(g: Gunnery) -> int:
	## Where a sensible gunner aims now.
	_last_escaped = g.fleeing()
	var want: Array = []
	if g.fleeing():
		want = [Net.ESYS_JUMP, Net.ESYS_ENGINE]
	if g.systems.size() > Net.ESYS_SHIELDS and g.systems_full[Net.ESYS_SHIELDS] > 0 and not g.down(Net.ESYS_SHIELDS):
		want.append(Net.ESYS_SHIELDS)
	want.append_array([Net.ESYS_WEAPONS, Net.ESYS_CREW])
	for s: int in want:
		var room := g.room_of_system(s)
		if room >= 0 and g.revealed[room] == 1 and not g.down(s):
			return s
	return Net.AIM_ANY


func _sector_at(far: int) -> int:
	## A sector that many jumps from the start, if the chart has one.
	for i in server.sectors.count:
		if server.sectors.far_from_start(i) == far:
			return i
	return server.ship.sector
